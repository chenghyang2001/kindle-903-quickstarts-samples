"""S3 兩階段自動寫程式 harness（模仿官方 claude-quickstarts/autonomous-coding）。

第 1 階段：初始化代理讀 app_spec.md，產出 workdir/feature_list.json、驗收測試檔、progress.md，git init＋第一個 commit。
第 2 階段：寫程式代理每個 session 只做一項未完成功能；模型只回 JSON（檔名＋內容），
          寫檔、跑測試、改 passes、commit 全由 harness 負責。
可續跑：所有狀態都在 workdir 的檔案與 git 裡，中斷後重跑同一條指令就接著做。

用法（Git Bash，在 s3-long-running 目錄）：
    PYTHONUTF8=1 python harness.py                  # 預設最多 3 個 session
    PYTHONUTF8=1 python harness.py --max-sessions 5 --max-calls 10
    PYTHONUTF8=1 python harness.py --selftest       # 離線檢查路徑與指令白名單（不呼叫模型）
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "shared"))
# 寫程式 session 的回覆含整份程式碼，比預設 180 秒容易超時
os.environ.setdefault("K902_CLI_TIMEOUT", "300")
from llm_agent import ask  # 要先把 shared 加進 sys.path 才能匯入，所以放在這裡

SPEC_FILE = HERE / "app_spec.md"
DEFAULT_WORKDIR = HERE / "workdir"
TEST_TIMEOUT_SECONDS = 60
MAX_ATTEMPTS = 2          # 第一次＋重試 1 次
MAX_CONTEXT_CHARS = 40000  # 帶給模型的現有檔案總長上限，避免提示詞爆量
HARNESS_OWNED = {"feature_list.json", "progress.md"}
SAFE_ARG = re.compile(r"^[A-Za-z0-9_./-]+$")
GIT_ID = ["-c", "user.name=k903-harness", "-c", "user.email=harness@localhost"]

INIT_SYSTEM = "你是軟體專案的初始化代理。你只輸出一個 JSON 物件，不輸出任何其他文字。"
CODE_SYSTEM = (
    "你是寫程式代理。這是全新的 context，你對之前的 session 沒有記憶，"
    "只能靠提示詞裡的功能清單、progress.md 與 git log 接上進度。你只輸出一個 JSON 物件。"
)


class HarnessError(Exception):
    """harness 拒絕執行的情況（路徑跳脫、指令不在白名單、模型回覆格式錯）。"""


# ---------- 安全檢查：寫檔路徑與測試指令 ----------

def safe_target(workdir: Path, rel_path: str, allow_tests: bool) -> Path:
    """把模型給的相對路徑轉成 workdir 內的絕對路徑；跳脫或碰到 harness 專屬檔就丟錯。"""
    if not rel_path or Path(rel_path).is_absolute() or ":" in rel_path:
        raise HarnessError(f"不接受絕對路徑或空路徑：{rel_path!r}")
    root = workdir.resolve()
    target = (root / rel_path).resolve()
    if target != root and root not in target.parents:
        raise HarnessError(f"路徑跳出 workdir：{rel_path!r}")
    parts = target.relative_to(root).parts
    if not parts or parts[0] == ".git" or rel_path in HARNESS_OWNED:
        raise HarnessError(f"這個檔案只有 harness 能寫：{rel_path!r}")
    # 驗收測試由初始化代理寫好就鎖住，寫程式代理不能改測試讓自己過關
    if parts[0] == "tests" and not allow_tests:
        raise HarnessError(f"寫程式代理不能修改測試：{rel_path!r}")
    return target


def parse_test_command(command: str, workdir: Path) -> list[str]:
    """只允許 `python -m unittest ...` 或 `python <檔案>.py`，回傳可直接執行的參數清單。"""
    try:
        tokens = shlex.split(command)
    except ValueError as exc:
        raise HarnessError(f"指令解析失敗：{command!r}") from exc
    if len(tokens) < 2 or tokens[0] != "python":
        raise HarnessError(f"只允許 python 開頭的指令：{command!r}")
    rest = tokens[1:]
    if rest[:2] == ["-m", "unittest"]:
        args = rest[2:]
    elif len(rest) == 1 and rest[0].endswith(".py"):
        safe_target(workdir, rest[0], allow_tests=True)  # 只檢查不跳脫
        args = rest
    else:
        raise HarnessError(f"不在白名單：{command!r}")
    for arg in args:
        if not SAFE_ARG.match(arg) or ".." in arg:
            raise HarnessError(f"參數含不安全字元：{arg!r}")
    # 用執行 harness 的同一個 Python，避免 Windows 上 python 指向別的版本
    return [sys.executable] + rest


def run_test(command: str, workdir: Path) -> tuple[bool, str]:
    """跑驗收測試（60 秒 timeout、不經 shell），回傳（是否通過, 輸出尾段）。"""
    argv = parse_test_command(command, workdir)
    try:
        proc = subprocess.run(argv, cwd=workdir, capture_output=True, text=True, encoding="utf-8",
                              errors="replace", timeout=TEST_TIMEOUT_SECONDS, check=False)
    except subprocess.TimeoutExpired:
        return False, f"測試超過 {TEST_TIMEOUT_SECONDS} 秒"
    output = (proc.stdout + proc.stderr).strip()
    return proc.returncode == 0, output[-2000:]


# ---------- 檔案與 git ----------

def git(workdir: Path, *args: str) -> str:
    """在 workdir 跑 git，失敗丟 HarnessError。"""
    try:
        proc = subprocess.run(["git", *GIT_ID, *args], cwd=workdir, capture_output=True, text=True,
                              encoding="utf-8", errors="replace", check=False)
    except OSError as exc:
        raise HarnessError(f"無法執行 git：{exc}") from exc
    if proc.returncode != 0:
        raise HarnessError(f"git {' '.join(args)} 失敗：{proc.stderr.strip()[:300]}")
    return proc.stdout.strip()


def commit_all(workdir: Path, message: str) -> str:
    """把 workdir 全部變更提交，回傳短 hash。"""
    git(workdir, "add", "-A")
    git(workdir, "commit", "-q", "-m", message)
    return git(workdir, "rev-parse", "--short", "HEAD")


def load_features(workdir: Path) -> list[dict]:
    path = workdir / "feature_list.json"
    return json.loads(path.read_text(encoding="utf-8"))["features"]


def save_features(workdir: Path, features: list[dict]) -> None:
    """先寫暫存檔再改名：中斷時不會留下寫一半的清單（官方原版的陷阱 6）。"""
    path = workdir / "feature_list.json"
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps({"features": features}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp.replace(path)


def append_progress(workdir: Path, session_no: int, title: str, body: str) -> None:
    with (workdir / "progress.md").open("a", encoding="utf-8") as handle:
        handle.write(f"\n## Session {session_no}：{title}\n\n{body.strip()}\n")


def next_session_no(workdir: Path) -> int:
    """session 編號從 progress.md 數出來，續跑時接著編。"""
    path = workdir / "progress.md"
    if not path.exists():
        return 1
    return len(re.findall(r"^## Session ", path.read_text(encoding="utf-8"), re.MULTILINE)) + 1


def write_files(workdir: Path, files: list, allow_tests: bool) -> list[str]:
    """先全部檢查路徑再寫，任何一個不合法就整批不寫。"""
    if not isinstance(files, list) or not files:
        raise HarnessError("模型回覆沒有 files 清單")
    planned = []
    for item in files:
        if not isinstance(item, dict) or not isinstance(item.get("content"), str):
            raise HarnessError(f"files 項目格式錯：{str(item)[:120]}")
        planned.append((safe_target(workdir, str(item.get("path", "")), allow_tests), item["content"]))
    for target, content in planned:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")
    return [str(t.relative_to(workdir.resolve())).replace("\\", "/") for t, _ in planned]


def snapshot_files(workdir: Path) -> str:
    """把 workdir 現有原始碼（不含 .git）串成文字，讓全新 context 的模型看得到現況。"""
    chunks, total = [], 0
    for path in sorted(workdir.rglob("*")):
        rel = path.relative_to(workdir).as_posix()
        if not path.is_file() or rel.startswith(".git/") or "__pycache__" in rel:
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        total += len(text)
        if total > MAX_CONTEXT_CHARS:
            chunks.append(f"（其餘檔案省略：超過 {MAX_CONTEXT_CHARS} 字）")
            break
        chunks.append(f"--- {rel} ---\n{text}")
    return "\n".join(chunks)


# ---------- 模型呼叫 ----------

def parse_model_json(text: str) -> dict:
    """從回覆抽出第一個 JSON 物件；用 raw_decode 而不是正規式，程式碼裡有大括號也不會切錯。"""
    start = text.find("{")
    if start == -1:
        raise HarnessError(f"模型回覆沒有 JSON：{text[:200]}")
    try:
        obj, _ = json.JSONDecoder().raw_decode(text[start:])
    except json.JSONDecodeError as exc:
        raise HarnessError(f"模型回覆的 JSON 解析失敗：{exc}") from exc
    if not isinstance(obj, dict):
        raise HarnessError("模型回覆的 JSON 不是物件")
    return obj


class CallBudget:
    """整次執行的模型呼叫上限，避免無人看管時無限燒額度（官方原版沒有上限）。"""

    def __init__(self, limit: int) -> None:
        self.limit, self.used = limit, 0

    def call(self, prompt: str, system: str) -> dict:
        if self.used >= self.limit:
            raise HarnessError(f"已達模型呼叫上限 {self.limit} 次")
        self.used += 1
        try:
            return parse_model_json(ask(prompt, system=system))
        except (RuntimeError, ValueError) as exc:
            raise HarnessError(f"模型呼叫失敗：{exc}") from exc


# ---------- 第 1 階段：初始化代理 ----------

INIT_PROMPT = """請讀下面的規格，把它切成 3～4 項可以逐項驗收的功能，並且寫好每一項的驗收測試。

輸出 JSON 格式：
{{"features": [{{"id": "F1", "description": "一句話說明", "test_command": "python -m unittest tests.test_f1"}}],
  "files": [{{"path": "tests/__init__.py", "content": ""}}, {{"path": "tests/test_f1.py", "content": "..."}}],
  "progress_note": "給下一棒的交接筆記（做了什麼、建議先做哪一項）"}}

規則：
- 功能依實作順序排列，前面的功能不能依賴後面的。
- test_command 只能是 `python -m unittest tests.test_xxx` 這種形式。
- 只寫測試檔與 tests/__init__.py，不要寫 ledger.py（那是寫程式代理的工作）。
- 測試只用標準庫 unittest，測試資料用 tempfile 產生；測試要嚴格對照規格裡的介面與輸出格式。

=== 規格 app_spec.md ===
{spec}
"""


def validate_features(raw: object, workdir: Path) -> list[dict]:
    """檢查初始化代理給的清單：3～4 項、欄位齊全、測試指令在白名單內。"""
    if not isinstance(raw, list) or not 3 <= len(raw) <= 4:
        raise HarnessError("features 必須是 3～4 項")
    features = []
    for item in raw:
        if not isinstance(item, dict) or not all(item.get(k) for k in ("id", "description", "test_command")):
            raise HarnessError(f"功能缺欄位：{str(item)[:120]}")
        parse_test_command(item["test_command"], workdir)
        features.append({"id": str(item["id"]), "description": str(item["description"]),
                         "test_command": item["test_command"], "passes": False, "attempts": 0})
    return features


def run_initializer(workdir: Path, budget: CallBudget, session_no: int) -> None:
    print(f"Session {session_no}：初始化代理（讀規格 → 產出功能清單與驗收測試）")
    workdir.mkdir(parents=True, exist_ok=True)
    reply = budget.call(INIT_PROMPT.format(spec=SPEC_FILE.read_text(encoding="utf-8")), INIT_SYSTEM)
    features = validate_features(reply.get("features"), workdir)
    if not (workdir / ".git").exists():
        git(workdir, "init", "-q")
    # 跑測試會產生 __pycache__，不排除的話每次 commit 都會把 .pyc 帶進去
    (workdir / ".gitignore").write_text("__pycache__/\n*.pyc\n", encoding="utf-8")
    written = write_files(workdir, reply.get("files"), allow_tests=True)
    (workdir / "progress.md").write_text("# 進度筆記（每個 session 由 harness 追加）\n", encoding="utf-8")
    append_progress(workdir, session_no, "初始化", f"寫入：{', '.join(written)}\n\n{reply.get('progress_note', '')}")
    save_features(workdir, features)  # 最後才寫清單：它存在＝初始化完成
    commit = commit_all(workdir, "初始化：功能清單、驗收測試、進度筆記")
    print(f"  → 功能 {len(features)} 項：{', '.join(f['id'] for f in features)} → commit {commit}")


# ---------- 第 2 階段：寫程式代理 ----------

CODE_PROMPT = """這個 session 只做一項功能：{fid}（{desc}）。
驗收方式：harness 會在 workdir 執行 `{cmd}`，結束碼 0 才算通過。

輸出 JSON 格式：
{{"files": [{{"path": "ledger.py", "content": "完整檔案內容"}}], "note": "給下一棒的交接筆記（一兩句）"}}

規則：
- 每個檔案都給完整內容（會整個覆蓋），路徑相對於 workdir。
- 不能修改 tests/ 底下的檔案，也不能寫 feature_list.json、progress.md。
- 已通過的功能不能弄壞；只用 Python 標準庫。
{retry}
=== 規格 app_spec.md ===
{spec}

=== feature_list.json ===
{features}

=== progress.md ===
{progress}

=== git log --oneline ===
{log}

=== workdir 現有檔案 ===
{files}
"""


def build_code_prompt(workdir: Path, feature: dict) -> str:
    retry = ""
    if feature.get("last_error"):
        retry = f"- 上一次嘗試失敗，測試輸出如下，請針對它修正：\n```\n{feature['last_error']}\n```\n"
    return CODE_PROMPT.format(
        fid=feature["id"], desc=feature["description"], cmd=feature["test_command"], retry=retry,
        spec=SPEC_FILE.read_text(encoding="utf-8"),
        features=(workdir / "feature_list.json").read_text(encoding="utf-8"),
        progress=(workdir / "progress.md").read_text(encoding="utf-8"),
        log=git(workdir, "log", "--oneline", "-10"), files=snapshot_files(workdir))


def pick_feature(features: list[dict]) -> dict | None:
    """挑第一項還沒通過、也還沒用完重試次數的功能。"""
    for feature in features:
        if not feature["passes"] and feature.get("attempts", 0) < MAX_ATTEMPTS:
            return feature
    return None


def run_coding(workdir: Path, budget: CallBudget, session_no: int, features: list[dict], feature: dict) -> None:
    tag = "（重試）" if feature.get("attempts", 0) else ""
    print(f"Session {session_no}：處理功能 {feature['id']}{tag} {feature['description']}")
    feature["attempts"] = feature.get("attempts", 0) + 1
    try:
        reply = budget.call(build_code_prompt(workdir, feature), CODE_SYSTEM)
        written = write_files(workdir, reply.get("files"), allow_tests=False)
        passed, output = run_test(feature["test_command"], workdir)
    except HarnessError as exc:
        if "呼叫上限" in str(exc):
            feature["attempts"] -= 1  # 沒真的試，不算一次
            raise
        written, passed, output, reply = [], False, f"harness 拒絕：{exc}", {}
    feature["passes"] = passed
    feature["last_error"] = None if passed else output[-1500:]
    result = "通過" if passed else "失敗"
    save_features(workdir, features)
    append_progress(workdir, session_no, f"{feature['id']} {result}",
                    f"寫入：{', '.join(written) or '（無）'}\n\n{reply.get('note', '')}")
    if passed:
        commit = commit_all(workdir, f"完成 {feature['id']}：{feature['description']}")
    else:
        commit = "（未 commit：失敗的程式碼留在工作區，帶進下一次重試）"
        print("  測試輸出尾段：\n    " + output[-600:].replace("\n", "\n    "))
    print(f"  → 測試結果：{result} → commit {commit}")


# ---------- 外層迴圈 ----------

def print_summary(workdir: Path, budget: CallBudget) -> None:
    print(f"\n本次模型呼叫：{budget.used} 次（上限 {budget.limit}）")
    if not (workdir / "feature_list.json").exists():
        return
    print("== git log --oneline ==")
    print(git(workdir, "log", "--oneline"))
    print("== feature_list.json 狀態 ==")
    for f in load_features(workdir):
        mark = "PASS" if f["passes"] else ("GAVE-UP" if f.get("attempts", 0) >= MAX_ATTEMPTS else "TODO")
        print(f"  {f['id']:<4} {mark:<8} 嘗試 {f.get('attempts', 0)} 次  {f['description']}")


def run(workdir: Path, max_sessions: int, max_calls: int) -> int:
    budget = CallBudget(max_calls)
    try:
        for _ in range(max_sessions):
            session_no = next_session_no(workdir)
            if not (workdir / "feature_list.json").exists():
                run_initializer(workdir, budget, session_no)
                continue
            features = load_features(workdir)
            feature = pick_feature(features)
            if feature is None:
                done = sum(f["passes"] for f in features)
                print(f"沒有可做的功能了：已完成 {done}/{len(features)} 項")
                break
            run_coding(workdir, budget, session_no, features, feature)
    except HarnessError as exc:
        print(f"停止：{exc}", file=sys.stderr)
        print_summary(workdir, budget)
        return 1
    print_summary(workdir, budget)
    return 0


def selftest() -> None:
    """離線檢查安全規則（不呼叫模型）。"""
    wd = DEFAULT_WORKDIR
    assert safe_target(wd, "ledger.py", False).name == "ledger.py"
    for bad in ("../x.py", "/etc/passwd", "C:/x.py", ".git/config", "progress.md", "tests/test_f1.py"):
        try:
            safe_target(wd, bad, allow_tests=False)
        except HarnessError:
            continue
        raise AssertionError(f"應該擋下：{bad}")
    assert parse_test_command("python -m unittest tests.test_f1", wd)[1:] == ["-m", "unittest", "tests.test_f1"]
    for bad in ("rm -rf .", "python -c 'import os'", "python ../evil.py", "python -m pip install x",
                "python -m unittest tests;rm", "bash -c ls"):
        try:
            parse_test_command(bad, wd)
        except HarnessError:
            continue
        raise AssertionError(f"應該擋下：{bad}")
    assert parse_model_json('說明\n```json\n{"files": [{"path": "a.py", "content": "d = {1: 2}"}]}\n```')["files"]
    print("selftest 通過")


def main() -> int:
    parser = argparse.ArgumentParser(description="S3 兩階段自動寫程式 harness（claude -p）")
    parser.add_argument("--max-sessions", type=int, default=3, help="這次最多跑幾個 session（預設 3）")
    parser.add_argument("--max-calls", type=int, default=10, help="這次最多呼叫模型幾次（預設 10）")
    parser.add_argument("--workdir", type=Path, default=DEFAULT_WORKDIR, help="產出的專案資料夾")
    parser.add_argument("--selftest", action="store_true", help="離線檢查，不呼叫模型")
    args = parser.parse_args()
    if args.selftest:
        selftest()
        return 0
    if args.max_sessions < 1 or args.max_calls < 1:
        print("錯誤：--max-sessions 與 --max-calls 都要 >= 1", file=sys.stderr)
        return 2
    return run(args.workdir.resolve(), args.max_sessions, args.max_calls)


if __name__ == "__main__":
    sys.exit(main())
