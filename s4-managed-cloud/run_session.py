"""S4 代管式每日比價代理（本機模擬版）：模仿 claude-quickstarts 第 9 章 managed-agents。

做什麼：讀 agents/price-report/agent.json（有版本的代理設定）→ 建一個 session（runs/<session_id>/）
→ 代理用 read_input 讀比價資料、寫報告、用 write_report 存檔 → 另一個 claude -p 當評分者
照 rubric.md 打分（outcome）→ FAIL 就帶理由重寫一次 → session.idle。每一步都寫進 events.jsonl。

為什麼這樣模擬：官方 Managed Agents 的代理迴圈跑在 Anthropic 伺服器上，要 API 額度；
K903 規定不設金鑰，所以「伺服器」由這支程式扮演，模型一律走 claude -p（shared/llm_agent.py）。

用法（Git Bash，在 s4-managed-cloud 目錄）：
    PYTHONUTF8=1 python run_session.py
    PYTHONUTF8=1 python run_session.py --input data/switches.json --agent agents/price-report
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
import uuid
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "shared"))
from llm_agent import extract_json, run_claude

HERE = Path(__file__).resolve().parent
RUNS_DIR = HERE / "runs"
# 寫一次＋評一次＋（FAIL 時）重寫一次＋再評一次，最多 4 次；超過就是程式有 bug，寧可停下
MAX_MODEL_CALLS = 4
REQUIRED_AGENT_FIELDS = ("name", "version", "model", "system", "tools", "outcome")
GRADER_SYSTEM = (
    "你是嚴格的報告評分者。只依評分標準逐條判斷 PASS 或 FAIL，理由一句話、要具體。"
    "比對數字時以輸入資料為準。只輸出 JSON。"
)


def now() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise SystemExit(f"錯誤：找不到檔案 {path}") from exc
    except json.JSONDecodeError as exc:
        raise SystemExit(f"錯誤：{path} 不是合法 JSON：{exc}") from exc


def load_agent(agent_dir: Path) -> tuple[dict, str]:
    """讀代理設定並檢查版本鎖。對應官方 POST /v1/agents：同一版號的內容不可以偷改。"""
    config_path = agent_dir / "agent.json"
    agent = load_json(config_path)
    missing = [k for k in REQUIRED_AGENT_FIELDS if k not in agent]
    if missing:
        raise SystemExit(f"錯誤：{config_path} 缺欄位 {missing}")
    # 用正規化後的 JSON 算雜湊：git 在不同電腦把換行轉成 CRLF 時，版本鎖才不會誤判
    canonical = json.dumps(agent, ensure_ascii=False, sort_keys=True).encode("utf-8")
    digest = hashlib.sha256(canonical).hexdigest()[:12]
    lock_path = agent_dir / "agent-lock.json"
    lock = load_json(lock_path) if lock_path.exists() else {}
    version_key = str(agent["version"])
    if version_key in lock and lock[version_key] != digest:
        # 官方改代理會產生新版本；這裡強制「改設定就升 version」，舊 session 才查得到當時用哪版
        raise SystemExit(
            f"錯誤：agent.json 內容變了但 version 還是 {version_key}（鎖定 {lock[version_key]}，現在 {digest}）。"
            "請把 version 加 1 再執行。"
        )
    if version_key not in lock:
        lock[version_key] = digest
        lock_path.write_text(json.dumps(lock, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return agent, digest


class Session:
    """一次執行＝一個 session：有自己的資料夾與只增不改的事件紀錄。"""

    def __init__(self, agent: dict, digest: str) -> None:
        self.id = f"sesn_{datetime.now().astimezone():%Y%m%d-%H%M%S}_{uuid.uuid4().hex[:6]}"
        self.dir = RUNS_DIR / self.id
        self.dir.mkdir(parents=True, exist_ok=False)
        self.events_path = self.dir / "events.jsonl"
        self.agent = agent
        self.model_calls = 0
        self.emit("session.created", agent=agent["name"], agent_version=agent["version"], agent_sha=digest)

    def emit(self, event_type: str, **data: object) -> None:
        record = {"ts": now(), "type": event_type, **data}
        with self.events_path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")
        print(f"  [{record['ts'][11:19]}] {event_type}")

    def ask_model(self, prompt: str, system: str, role: str) -> str:
        if self.model_calls >= MAX_MODEL_CALLS:
            raise RuntimeError(f"模型呼叫已達上限 {MAX_MODEL_CALLS} 次")
        self.model_calls += 1
        payload = run_claude(prompt, system=system, model=self.agent["model"])
        usage = payload.get("usage") or {}
        self.emit("model.call", role=role, n=self.model_calls,
                  output_tokens=usage.get("output_tokens"), duration_ms=payload.get("duration_ms"))
        return str(payload.get("result", ""))


def call_tool(session: Session, name: str, **args: object) -> str:
    """主機代為執行工具（像官方的 custom tool）：先查權限，再記 tool.use／tool.result。"""
    session.emit("tool.use", name=name, input={k: (Path(str(v)).name if k == "path" else str(v)[:80]) for k, v in args.items()})
    if name not in session.agent["tools"]:
        session.emit("tool.result", name=name, is_error=True, content="權限不足：agent.json 沒有允許這個工具")
        raise PermissionError(f"代理沒有 {name} 工具的權限")
    if name == "read_input":
        content = Path(str(args["path"])).read_text(encoding="utf-8")
        session.emit("tool.result", name=name, content=f"讀到 {len(content)} 字")
        return content
    if name == "write_report":
        report_path = session.dir / "report.md"
        report_path.write_text(str(args["text"]).strip() + "\n", encoding="utf-8")
        session.emit("tool.result", name=name, content=f"已寫入 {report_path.name}")
        return str(report_path)
    raise ValueError(f"未知工具 {name}")


def draft_report(session: Session, input_text: str, feedback: str | None) -> str:
    prompt = f"以下是 read_input 工具的結果：\n```json\n{input_text}\n```\n請依系統提示寫出報告。"
    if feedback:
        prompt += f"\n\n上一版被評分者退回，請修正後輸出完整新版報告。退回理由：\n{feedback}"
    text = session.ask_model(prompt, session.agent["system"], role="writer")
    session.emit("agent.message", chars=len(text), preview=text[:120])
    return text


def grade_report(session: Session, rubric: str, input_text: str, report: str) -> dict:
    """outcome：另一個 claude -p 當評分者。整體結果由程式依各條計算，不採信模型自己寫的 overall。"""
    prompt = (
        f"# 評分標準\n{rubric}\n\n# 輸入資料\n```json\n{input_text}\n```\n\n# 待評報告\n{report}\n\n"
        '輸出格式：{"criteria": [{"id": 1, "result": "PASS 或 FAIL", "reason": "一句話"}, ...共 5 條]}'
    )
    raw = session.ask_model(prompt, GRADER_SYSTEM, role="grader")
    try:
        criteria = extract_json(raw).get("criteria", [])
    except ValueError as exc:
        criteria = [{"id": 0, "result": "FAIL", "reason": f"評分者輸出無法解析：{exc}"}]
    if len(criteria) != 5:
        criteria.append({"id": 0, "result": "FAIL", "reason": f"評分者只回了 {len(criteria)} 條，應為 5 條"})
    overall = "PASS" if all(str(c.get("result")).upper() == "PASS" for c in criteria) else "FAIL"
    return {"overall": overall, "criteria": criteria}


def run(agent_dir: Path, input_path: Path) -> Session:
    agent, digest = load_agent(agent_dir)
    rubric = (HERE / agent["outcome"]["rubric"]).read_text(encoding="utf-8")
    session = Session(agent, digest)
    session.emit("session.running", input=input_path.name)
    try:
        grades = run_outcome_loop(session, agent, rubric, input_path)
    except (RuntimeError, PermissionError, OSError) as exc:
        # 中途失敗也要留下終止事件，事後看 events.jsonl 才知道停在哪一步
        session.emit("session.error", error=str(exc)[:300])
        raise
    session.emit("session.idle", stop_reason="end_turn", final_outcome=grades[-1]["overall"])
    write_summary(session, grades)
    return session


def run_outcome_loop(session: Session, agent: dict, rubric: str, input_path: Path) -> list[dict]:
    """寫報告→評分→FAIL 就帶理由重寫，最多重寫 max_revisions 次（官方 outcomes 的評分者迭代）。"""
    input_text = call_tool(session, "read_input", path=input_path)
    feedback, grades = None, []
    for attempt in range(1 + int(agent["outcome"].get("max_revisions", 1))):
        report = draft_report(session, input_text, feedback)
        call_tool(session, "write_report", text=report)
        grade = grade_report(session, rubric, input_text, report)
        grades.append(grade)
        session.emit("outcome.graded", attempt=attempt + 1, overall=grade["overall"], criteria=grade["criteria"])
        if grade["overall"] == "PASS":
            break
        feedback = "\n".join(f"- 第 {c.get('id')} 條：{c.get('reason')}" for c in grade["criteria"]
                             if str(c.get("result")).upper() != "PASS")
    return grades


def write_summary(session: Session, grades: list[dict]) -> None:
    summary = {
        "session_id": session.id,
        "agent": f"{session.agent['name']}@v{session.agent['version']}",
        "model": session.agent["model"],
        "model_calls": session.model_calls,
        "attempts": len(grades),
        "final_outcome": grades[-1]["overall"],
        "grades": grades,
        "files": ["events.jsonl", "report.md", "summary.json"],
    }
    (session.dir / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def print_result(session: Session) -> None:
    summary = json.loads((session.dir / "summary.json").read_text(encoding="utf-8"))
    print(f"\nsession 路徑：{session.dir}")
    print(f"代理：{summary['agent']}　模型呼叫：{summary['model_calls']} 次　嘗試：{summary['attempts']} 次")
    for index, grade in enumerate(summary["grades"], start=1):
        print(f"第 {index} 次評分：{grade['overall']}")
        for c in grade["criteria"]:
            print(f"  {c.get('id')}. {c.get('result')}｜{c.get('reason')}")
    print("\n報告前 15 行：")
    lines = (session.dir / "report.md").read_text(encoding="utf-8").splitlines()
    print("\n".join(lines[:15]))


def main() -> int:
    parser = argparse.ArgumentParser(description="S4 代管式每日比價代理（本機模擬）")
    parser.add_argument("--agent", default=str(HERE / "agents" / "price-report"), help="代理設定資料夾")
    parser.add_argument("--input", default=str(HERE / "data" / "switches.json"), help="比價資料 JSON")
    args = parser.parse_args()
    try:
        session = run(Path(args.agent).resolve(), Path(args.input).resolve())
    except (RuntimeError, PermissionError, OSError, KeyError) as exc:
        print(f"錯誤：{exc}", file=sys.stderr)
        return 1
    print_result(session)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
