"""S1 本機資料夾小管家：模仿 claude-quickstarts 第 3 章 agents 的最小工具迴圈。

做什麼：使用者用自然語言問某個資料夾（預設 ~/workspace/console/shopping-notes）裡的內容，
模型自己決定要呼叫 list_dir／read_file／search_text 哪個工具、呼叫幾次，最後給出答案。

為什麼不用 anthropic SDK：K903 規定不設 API 金鑰，模型一律走 claude -p（shared/llm_agent.py）。
原生 tool use 改成「模型回 JSON」：{"tool": 名稱, "args": {...}} 或 {"final": 答案}。

用法（Git Bash）：
    PYTHONUTF8=1 python folder_agent.py "最近一次比價是什麼商品？推薦哪一款？"
    PYTHONUTF8=1 python folder_agent.py --root ~/某資料夾 "問題"
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "shared"))
from llm_agent import run_claude

MAX_ROUNDS = 5
DEFAULT_ROOT = Path.home() / "workspace" / "console" / "shopping-notes"
RUNS_DIR = Path(__file__).resolve().parent / "runs"
TEXT_SUFFIXES = {".md", ".txt", ".json", ".csv"}
# 工具結果太長會讓下一輪提示詞爆量，每筆最多回給模型這麼多字
RESULT_LIMIT = 4000
# 最終答案少於這個字數，多半是模型把格式說明複述一次的殘渣，不當成答案
MIN_ANSWER_CHARS = 8
INVALID_ANSWER = "模型未給出有效答案"
# 模型把提示詞裡的格式說明抄回來時會出現這些片段（實測：`明、{"final":...}只輸出JSON。`）
ECHO_MARKERS = ('{"final"', '{"tool"', "只輸出JSON", "只輸出 JSON", "<你的答案>")
MAX_SEARCH_HITS = 30

SYSTEM_PROMPT = """你是「本機資料夾小管家」，只能透過工具讀取一個資料夾來回答使用者的問題。
根目錄就是「{root_name}」資料夾本身，路徑一律用相對於根目錄的寫法（根目錄本身是 "."）。
使用者提到「{root_name}」時指的是根目錄，不要把它當成子資料夾。

可用工具（全部唯讀）：
- list_dir   args: {"path": "相對路徑"}               列出資料夾內容（資料夾結尾有 /）
- read_file  args: {"path": "相對路徑", "max_chars": 整數}  讀文字檔前 max_chars 字（預設 3000）
- search_text args: {"keyword": "關鍵字"}              在所有文字檔中找含關鍵字的行

每一輪你只能輸出「一個 JSON 物件」，不要任何其他文字：
- 要用工具：{"tool": "工具名稱", "args": {...}}
- 可以回答了：{"final": "給使用者的繁體中文答案"}
不要自己編造工具結果；答案要根據工具讀到的內容。"""


class PathEscapeError(ValueError):
    """路徑解析後跑到根目錄外面（例如用 .. 跳脫）。"""


# ---------- 工具（全部唯讀，且限制在 root 底下） ----------

def safe_path(root: Path, rel: str) -> Path:
    """把相對路徑解析成絕對路徑；解析後不在 root 底下就拒絕，防 .. 與絕對路徑跳脫。"""
    target = (root / (rel or ".")).resolve()
    if target != root and root not in target.parents:
        raise PathEscapeError(f"拒絕存取根目錄以外的路徑：{rel}")
    return target


def list_dir(root: Path, path: str = ".") -> str:
    target = safe_path(root, path)
    if not target.is_dir():
        return f"錯誤：{path} 不是資料夾"
    names = [p.name + ("/" if p.is_dir() else "") for p in sorted(target.iterdir())]
    return "\n".join(names) or "（空資料夾）"


def read_file(root: Path, path: str, max_chars: int = 3000) -> str:
    target = safe_path(root, path)
    if not target.is_file():
        return f"錯誤：{path} 不是檔案"
    text = target.read_text(encoding="utf-8", errors="replace")
    limit = max(1, min(int(max_chars), RESULT_LIMIT))
    suffix = f"\n…（已截斷，全文 {len(text)} 字）" if len(text) > limit else ""
    return text[:limit] + suffix


def search_text(root: Path, keyword: str) -> str:
    if not keyword or not keyword.strip():
        return "錯誤：keyword 是空的"
    needle = keyword.lower()
    hits: list[str] = []
    for file in sorted(root.rglob("*")):
        if not file.is_file() or file.suffix.lower() not in TEXT_SUFFIXES:
            continue
        lines = file.read_text(encoding="utf-8", errors="replace").splitlines()
        for number, line in enumerate(lines, 1):
            if needle in line.lower():
                hits.append(f"{file.relative_to(root).as_posix()}:{number}: {line.strip()[:200]}")
                if len(hits) >= MAX_SEARCH_HITS:
                    return "\n".join(hits) + f"\n…（只列前 {MAX_SEARCH_HITS} 筆）"
    return "\n".join(hits) or f"找不到含「{keyword}」的行"


TOOLS = {"list_dir": list_dir, "read_file": read_file, "search_text": search_text}


def run_tool(root: Path, name: str, args: dict) -> str:
    """執行模型要求的工具；任何錯誤都變成文字回給模型，讓它自己換做法，而不是讓程式當掉。"""
    func = TOOLS.get(name)
    if func is None:
        return f"錯誤：沒有叫 {name} 的工具，可用：{', '.join(TOOLS)}"
    try:
        return func(root, **(args or {}))
    except PathEscapeError as exc:
        return f"錯誤：{exc}"
    except (TypeError, ValueError) as exc:
        return f"錯誤：參數不對（{exc}）"
    except OSError as exc:
        return f"錯誤：讀取失敗（{exc}）"


# ---------- 代理迴圈 ----------

def build_system(root: Path) -> str:
    """系統提示帶入根目錄名稱：題目寫到資料夾名稱時，模型才不會把它當成子資料夾去列。"""
    return SYSTEM_PROMPT.replace("{root_name}", root.name)


def build_prompt(question: str, steps: list[dict], is_last: bool) -> str:
    """每次 claude -p 都是全新行程，所以要把問題和所有工具往來攤平成一份逐字稿送進去。"""
    parts = [f"使用者的問題：{question}"]
    for step in steps:
        parts.append(f"[第 {step['round']} 輪] 你要求：{json.dumps(step['request'], ensure_ascii=False)}\n"
                     f"工具結果：\n{step['result'][:RESULT_LIMIT]}")
    if is_last:
        # 給完整範例而不是「...」：模型看到省略號時常把格式說明本身抄成答案
        parts.append("這是最後一輪，不能再呼叫工具。請根據上面各輪的工具結果回答使用者的問題；"
                     "資料不足就說明目前查到什麼、還缺什麼。\n"
                     "整個回覆只能是一個 JSON 物件，格式如下（把角括號那段換成你的繁體中文答案）：\n"
                     '{"final": "<你的答案>"}')
    else:
        parts.append("請輸出下一步的 JSON。")
    return "\n\n".join(parts)


def parse_reply(reply: str) -> dict:
    """找回覆裡第一個含 tool 或 final 的 JSON 物件。

    為什麼不用 extract_json：它取第一個 { 到最後一個 }，模型把同一個 JSON 重複兩次
    （實測：外面多包一層標籤再重寫一次）時，會把兩段黏在一起而解析失敗。
    """
    decoder = json.JSONDecoder()
    for start in (i for i, ch in enumerate(reply) if ch == "{"):
        try:
            obj, _ = decoder.raw_decode(reply, start)
        except json.JSONDecodeError:
            continue
        if isinstance(obj, dict) and ("tool" in obj or "final" in obj):
            return obj
    # 完全沒有 JSON 時把整段文字當答案，交給 is_valid_answer 把關
    return {"final": reply.strip()}


def ask_model(prompt: str, system: str) -> dict:
    """呼叫一次模型並解析出這一輪的請求。"""
    return parse_reply(str(run_claude(prompt, system=system).get("result", "")))


def is_valid_answer(answer: object) -> bool:
    """擋掉空答案、太短的殘渣、把格式說明抄回來的亂碼。"""
    if not isinstance(answer, str):
        return False
    text = answer.strip()
    return len(text) >= MIN_ANSWER_CHARS and not any(marker in text for marker in ECHO_MARKERS)


def finish(round_no: int, request: dict, steps: list[dict]) -> tuple[str, list[dict], bool]:
    """收尾一輪 final：無效答案不往下傳，只在紀錄留前 80 字原文方便除錯。"""
    raw = request.get("final")
    valid = is_valid_answer(raw)
    print(f"第 {round_no} 輪：模型回覆最終答案" + ("" if valid else f"，但{INVALID_ANSWER}"))
    entry = {"round": round_no, "request": {"final": "..."}, "tool": None, "result_chars": 0, "valid_answer": valid}
    if not valid:
        entry["raw_final"] = str(raw)[:80]
    steps.append(entry)
    return (str(raw).strip() if valid else INVALID_ANSWER), steps, valid


def agent_loop(root: Path, question: str, max_rounds: int = MAX_ROUNDS) -> tuple[str, list[dict], bool]:
    steps: list[dict] = []
    system = build_system(root)
    for round_no in range(1, max_rounds + 1):
        request = ask_model(build_prompt(question, steps, is_last=round_no == max_rounds), system)
        if "final" in request:
            return finish(round_no, request, steps)
        name, args = str(request.get("tool")), request.get("args") or {}
        result = run_tool(root, name, args if isinstance(args, dict) else {})
        first_line = result.splitlines()[0][:60] if result else ""
        print(f"第 {round_no} 輪：模型要求 {name}({json.dumps(args, ensure_ascii=False)}) "
              f"→ 結果 {len(result)} 字，首行：{first_line}")
        steps.append({"round": round_no, "request": request, "tool": name,
                      "result": result, "result_chars": len(result)})
    print(f"已達最多 {max_rounds} 輪，{INVALID_ANSWER}")
    return INVALID_ANSWER, steps, False


def save_run(root: Path, question: str, answer: str, steps: list[dict], seconds: float, valid: bool) -> Path:
    """迴圈紀錄只存每輪的請求、工具、結果長度，不存工具結果全文（避免把私人筆記複製一份）。"""
    RUNS_DIR.mkdir(exist_ok=True)
    out = RUNS_DIR / f"{datetime.now().astimezone():%Y%m%d-%H%M%S}.json"
    record = {
        "question": question, "root": str(root), "answer": answer, "valid_answer": valid,
        "model_calls": len(steps), "seconds": round(seconds, 1),
        "rounds": [{k: v for k, v in s.items() if k != "result"} for s in steps],
    }
    out.write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding="utf-8")
    return out


def to_local_path(raw: str) -> Path:
    """Git Bash 設了 MSYS_NO_PATHCONV=1 時，~ 會展開成 /c/Users/...，Windows Python 看不懂，要轉回 C:/..."""
    if sys.platform == "win32" and len(raw) >= 3 and raw[0] == "/" and raw[2] == "/" and raw[1].isalpha():
        raw = f"{raw[1]}:{raw[2:]}"
    return Path(raw).expanduser().resolve()


def main() -> int:
    parser = argparse.ArgumentParser(description="本機資料夾小管家（唯讀工具迴圈，模型走 claude -p）")
    parser.add_argument("question", help="要問的問題")
    parser.add_argument("--root", default=str(DEFAULT_ROOT), help="只允許讀取的根目錄")
    parser.add_argument("--max-rounds", type=int, default=MAX_ROUNDS, help=f"最多幾輪（預設 {MAX_ROUNDS}）")
    opts = parser.parse_args()
    if opts.max_rounds < 1:
        print("錯誤：--max-rounds 至少要 1", file=sys.stderr)
        return 2
    root = to_local_path(opts.root)
    if not root.is_dir():
        print(f"錯誤：根目錄不存在或不是資料夾：{root}", file=sys.stderr)
        return 2
    started = time.time()
    try:
        answer, steps, valid = agent_loop(root, opts.question, opts.max_rounds)
    except RuntimeError as exc:
        print(f"錯誤：呼叫模型失敗：{exc}", file=sys.stderr)
        return 1
    log_path = save_run(root, opts.question, answer, steps, time.time() - started, valid)
    print(f"\n=== 答案 ===\n{answer}\n\n（模型呼叫 {len(steps)} 次，紀錄：{log_path}）")
    return 0 if valid else 3


if __name__ == "__main__":
    sys.exit(main())
