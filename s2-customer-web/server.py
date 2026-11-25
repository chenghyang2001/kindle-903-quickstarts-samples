"""S2 AMR 產品問答網頁：模仿官方 customer-support-agent（知識庫檢索＋結構化 JSON 回覆）。

做什麼：瀏覽器問產品問題 → 從 kb/ 用字元重疊評分取前 2 份文件 → claude -p 依文件回 JSON →
        驗證欄位後回給網頁，並寫一行 JSONL 到 logs/。
為什麼用 claude -p：本教材規定不設 API 金鑰、走 Max 訂閱；這只適合「自己本機示範」，
        正式給外部客戶用一定要換 API key（見 README）。

用法（Git Bash，在本資料夾）：
    PYTHONUTF8=1 python server.py                 → 啟動 http://127.0.0.1:8903
    PYTHONUTF8=1 python server.py --port 8913     → 換埠
    PYTHONUTF8=1 python server.py --selftest      → 離線檢查檢索與 JSON 驗證（不呼叫模型）
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
from datetime import datetime
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(BASE_DIR.parent / "shared"))
from llm_agent import ask, extract_json  # shared 要先加進 sys.path 才能匯入

KB_DIR = BASE_DIR / "kb"
LOG_DIR = BASE_DIR / "logs"
INDEX_HTML = BASE_DIR / "static" / "index.html"
HOST = "127.0.0.1"          # 只綁本機：這是示範，不對區網或網際網路開放
DEFAULT_PORT = 8903
MAX_QUESTION_CHARS = 500
MAX_BODY_BYTES = 8 * 1024   # 擋掉超大請求，避免一次塞爆記憶體
TOP_K = 2
CONFIDENCE_LEVELS = ("high", "medium", "low")

SYSTEM_PROMPT = """你是「示範機器人股份有限公司」（虛構公司）的 AMR 產品客服。
規則：
1. 只能根據使用者訊息裡 <docs> 提供的知識庫文件回答，不可以用文件外的知識或自己猜。
2. 文件裡找不到答案、或問題和本公司 AMR 產品無關時：answer 寫「這個問題我無法從產品資料確認，已為您轉真人客服。」，needs_human 設 true，confidence 設 low，sources 給空陣列。
3. 客戶要求議價、客訴、退貨、或情緒不滿時，也要 needs_human 設 true。
4. 回答用繁體中文，簡短（150 字內），價格一律提醒「以正式報價單為準」。
5. 只輸出一個 JSON 物件，格式：
{"answer": "給客戶看的回答", "sources": ["實際用到的文件檔名"], "confidence": "high|medium|low", "needs_human": true或false}
"""

SAFE_FALLBACK = {
    "answer": "抱歉，系統暫時無法回答，已為您轉真人客服。",
    "sources": [],
    "confidence": "low",
    "needs_human": True,
}


# ---------- 知識庫與檢索 ----------

def load_kb(kb_dir: Path = KB_DIR) -> dict[str, str]:
    """讀 kb/*.md，回傳 {檔名: 內容}；資料夾空的就直接報錯，免得模型永遠答不出來還以為是模型的問題。"""
    docs = {p.name: p.read_text(encoding="utf-8") for p in sorted(kb_dir.glob("*.md"))}
    if not docs:
        raise RuntimeError(f"知識庫是空的：{kb_dir}")
    return docs


def tokenize(text: str) -> set[str]:
    """中文取相鄰兩字（bigram）、英數取整個詞：中文沒有空白分詞，bigram 是標準庫做得到的最簡單近似。"""
    lowered = text.lower()
    tokens = set(re.findall(r"[a-z0-9][a-z0-9\-]*", lowered))
    for run in re.findall(r"[一-鿿]+", lowered):
        tokens.update(run[i:i + 2] for i in range(len(run) - 1))
    return tokens


def retrieve(question: str, docs: dict[str, str], top_k: int = TOP_K) -> list[tuple[str, int]]:
    """依「問題的 token 有幾個出現在文件裡」排序，回傳前 top_k 份的 (檔名, 分數)，分數 0 的不回。"""
    query_tokens = tokenize(question)
    scored = []
    for name, body in docs.items():
        doc_tokens = tokenize(body + " " + name)
        scored.append((name, len(query_tokens & doc_tokens)))
    scored.sort(key=lambda item: item[1], reverse=True)
    return [item for item in scored[:top_k] if item[1] > 0]


# ---------- 模型呼叫與回覆驗證 ----------

def build_prompt(question: str, hits: list[tuple[str, int]], docs: dict[str, str]) -> str:
    """把檢索到的文件包成 <docs>；檢索不到就明說沒有文件，讓模型走轉真人的規則。"""
    if hits:
        parts = [f'<doc name="{name}">\n{docs[name]}\n</doc>' for name, _ in hits]
        doc_block = "\n".join(parts)
    else:
        doc_block = "（知識庫中沒有找到相關文件）"
    return f"<docs>\n{doc_block}\n</docs>\n\n客戶問題：{question}"


def validate_reply(raw: dict, allowed_sources: set[str]) -> dict:
    """檢查四個欄位的型別與值；不合格丟 ValueError。sources 只保留真的有給模型看的檔名，防模型亂編來源。"""
    answer = raw.get("answer")
    if not isinstance(answer, str) or not answer.strip():
        raise ValueError("answer 必須是非空字串")
    sources = raw.get("sources")
    if not isinstance(sources, list) or not all(isinstance(s, str) for s in sources):
        raise ValueError("sources 必須是字串陣列")
    confidence = raw.get("confidence")
    if confidence not in CONFIDENCE_LEVELS:
        raise ValueError(f"confidence 必須是 {CONFIDENCE_LEVELS} 之一")
    needs_human = raw.get("needs_human")
    if not isinstance(needs_human, bool):
        raise ValueError("needs_human 必須是布林值")
    return {
        "answer": answer.strip(),
        "sources": [s for s in sources if s in allowed_sources],
        "confidence": confidence,
        "needs_human": needs_human,
    }


def answer_question(question: str, docs: dict[str, str]) -> tuple[dict, list[tuple[str, int]], str | None]:
    """檢索 → 呼叫一次模型 → 驗證；任何一步失敗都回安全預設（轉真人），並把錯誤原因帶回去寫紀錄。"""
    hits = retrieve(question, docs)
    try:
        text = ask(build_prompt(question, hits, docs), system=SYSTEM_PROMPT)
        reply = validate_reply(extract_json(text), {name for name, _ in hits})
        return reply, hits, None
    except (RuntimeError, ValueError) as exc:
        return dict(SAFE_FALLBACK), hits, str(exc)[:300]


def write_log(entry: dict) -> None:
    """每次問答追加一行 JSONL；寫不進去只印警告，不讓紀錄失敗擋住客戶拿到答案。"""
    try:
        LOG_DIR.mkdir(exist_ok=True)
        path = LOG_DIR / f"{datetime.now():%Y-%m-%d}.jsonl"
        with path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except OSError as exc:
        print(f"[警告] 紀錄寫入失敗：{exc}", file=sys.stderr)


# ---------- HTTP ----------

def parse_question(body: bytes) -> str:
    """解析 POST 內容並驗證 question；不合格丟 ValueError（由呼叫端回 400）。"""
    try:
        payload = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError("請求內容必須是 UTF-8 JSON") from exc
    question = payload.get("question") if isinstance(payload, dict) else None
    if not isinstance(question, str) or not question.strip():
        raise ValueError("question 不可為空")
    question = question.strip()
    if len(question) > MAX_QUESTION_CHARS:
        raise ValueError(f"question 不可超過 {MAX_QUESTION_CHARS} 字")
    return question


class AskHandler(BaseHTTPRequestHandler):
    """GET / 回聊天頁；POST /api/ask 回 JSON 答案；其他一律 404。"""

    docs: dict[str, str] = {}

    def send_json(self, status: HTTPStatus, payload: dict) -> None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self) -> None:  # http.server 規定的方法名
        if self.path not in ("/", "/index.html"):
            self.send_json(HTTPStatus.NOT_FOUND, {"error": "not found"})
            return
        try:
            data = INDEX_HTML.read_bytes()
        except OSError:
            self.send_json(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": "頁面讀取失敗"})
            return
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self) -> None:
        if self.path != "/api/ask":
            self.send_json(HTTPStatus.NOT_FOUND, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            length = -1
        if length <= 0 or length > MAX_BODY_BYTES:
            self.send_json(HTTPStatus.BAD_REQUEST, {"error": "請求大小不正確"})
            return
        try:
            question = parse_question(self.rfile.read(length))
        except ValueError as exc:
            self.send_json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return
        self.handle_question(question)

    def handle_question(self, question: str) -> None:
        started = time.monotonic()
        reply, hits, error = answer_question(question, self.docs)
        write_log({
            "time": datetime.now().isoformat(timespec="seconds"),
            "question": question,
            "retrieved": [{"doc": name, "score": score} for name, score in hits],
            "reply": reply,
            "error": error,
            "seconds": round(time.monotonic() - started, 1),
        })
        self.send_json(HTTPStatus.OK, reply)


# ---------- 自我檢查與進入點 ----------

def selftest() -> None:
    """離線檢查：分詞、檢索排序、JSON 驗證、輸入驗證（不呼叫模型）。"""
    docs = load_kb()
    assert len(docs) >= 4, "知識庫至少要 4 份"
    top = retrieve("DR-800 充電要多久？", docs)
    assert top and top[0][0] == "03-charging-battery.md", top
    assert retrieve("zzzz", docs) == []
    good = {"answer": "約 1.5 小時", "sources": ["a.md", "編的.md"], "confidence": "high", "needs_human": False}
    assert validate_reply(good, {"a.md"})["sources"] == ["a.md"]
    for bad in ({**good, "confidence": "超高"}, {**good, "needs_human": "否"}, {**good, "answer": ""}):
        try:
            validate_reply(bad, {"a.md"})
        except ValueError:
            continue
        raise AssertionError(f"應該驗證失敗：{bad}")
    for bad_body in (b'{"question": "  "}', b"not json", json.dumps({"question": "x" * 501}).encode()):
        try:
            parse_question(bad_body)
        except ValueError:
            continue
        raise AssertionError(f"應該 400：{bad_body[:30]!r}")
    print("selftest OK")


def main() -> int:
    parser = argparse.ArgumentParser(description="S2 AMR 產品問答網頁")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args()
    try:
        if args.selftest:
            selftest()
            return 0
        AskHandler.docs = load_kb()
        server = ThreadingHTTPServer((HOST, args.port), AskHandler)
    except (RuntimeError, OSError) as exc:
        print(f"錯誤：{exc}", file=sys.stderr)
        return 1
    print(f"S2 問答網頁啟動：http://{HOST}:{args.port}（知識庫 {len(AskHandler.docs)} 份，Ctrl+C 結束）", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
