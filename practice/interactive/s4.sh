#!/bin/bash
# K903 範例 S4 互動演練：代管式每日比價代理——在本機用檔案模擬 Managed Agents（模仿官方第 9 章 managed-agents），一次跑一步
# 用法：bash s4.sh <步驟 1-8>；第 8 步分兩半：bash s4.sh 8（先出題）→ bash s4.sh 8b（範例答案＋本機和雲端的差別）
# 呼叫模型：只有第 4 步會呼叫模型，最多 2 次（claude -p，透過 shared/llm_agent.py；不重試），其餘步驟全部離線
# 乾跑：bash s4.sh 4 --dry-run 用寫死的假回覆代替模型，session 寫到暫存資料夾、跑完刪掉，只用來檢查腳本路徑，不算演練
# 第 3 步會暫時改 agent.json 再還原，並用 sha256 確認還原成功；整份演練不改 s4-managed-cloud/ 的任何檔案
set -u
STEP="${1:-1}"
MODE="${2:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/../.."
G=$'\e[32m'; Y=$'\e[33m'; C=$'\e[36m'; B=$'\e[1m'; N=$'\e[0m'

banner() { clear; printf '%s╔══════════════════════════════════════════════════════╗%s\n' "$C" "$N"; printf '%s  K903 範例 S4｜代管式每日比價代理　第 %s / 8 步%s\n' "$B" "${STEP%b}" "$N"; printf '%s  %s%s\n' "$B" "$1" "$N"; printf '%s╚══════════════════════════════════════════════════════╝%s\n\n' "$C" "$N"; }
tip() { printf '%s💡 %s%s\n\n' "$Y" "$1" "$N"; }
show() { printf '%s▶ 要執行的程式：%s\n' "$G" "$N"; printf '%s' "$1" | sed "s/^/${G}  │ ${N}/"; printf '\n%s▶ 執行結果：%s\n' "$G" "$N"; }
# 在 repo 根目錄執行；P 用單引號包住，所以 Python 程式碼裡不能出現單引號、錢字號與反斜線跳脫
run() { (cd "$REPO" && PYTHONUTF8=1 S4_MODE="$MODE" python - <<PY
import sys
sys.path.insert(0, "s4-managed-cloud")
sys.path.insert(0, "shared")
$1
PY
); printf '\n%s👉 第 %s 步完成%s\n' "$C" "$STEP" "$N"; }

case "$STEP" in
1) banner "雲端代管在管什麼：五件事"
   tip "官方 Managed Agents 把代理迴圈搬到 Anthropic 伺服器，你只宣告資源、讀事件。S4 不用 API，改由 run_session.py 扮演伺服器，把它管的五件事各用一個本機檔案模擬出來。"
   P='from pathlib import Path

base = Path("s4-managed-cloud")
rows = [
    ("1 agent", "有版本號的代理設定：模型、系統提示、工具", "agents/price-report/agent.json＋agent-lock.json", "POST /v1/agents（改設定就發新版本）"),
    ("2 session", "一次執行，彼此獨立", "runs/<sesn_id>/", "sessions.create"),
    ("3 事件流", "執行過程的每一步，只追加不修改", "runs/<sesn_id>/events.jsonl", "events.stream（SSE）／events.list"),
    ("4 outcome", "照 rubric 評分，不過就帶理由重寫", "rubric.md＋評分者 claude -p", "outcomes（評分者迭代）"),
    ("5 排程", "固定時間開一個新 session", "deploy.py --dry-run＋deployment.json", "scheduled deployment（cron＋時區）"),
]
print("{:<10} | {:<26} | {:<40} | {}".format("管什麼", "意思", "S4 本機檔案", "官方對應"))
print("-" * 125)
for r in rows:
    print("{:<10} | {:<26} | {:<40} | {}".format(*r))
print()
for rel in ["run_session.py", "deploy.py", "agents/price-report/agent.json", "agents/price-report/agent-lock.json",
            "agents/price-report/deployment.json", "rubric.md", "data/switches.json"]:
    p = base / rel
    n = len(p.read_text(encoding="utf-8").splitlines()) if p.is_file() else 0
    print("  {:<38} {}".format(rel, "{} 行".format(n) if p.is_file() else "（找不到）"))
runs = sorted((base / "runs").glob("sesn_*"))
print("  runs/ 目前已有 {} 個 session".format(len(runs)))
print()
try:
    import qs_source
    hits = qs_source.grep("managed-agents/daily-brief/agents/daily-brief/agent.md", "new version")
    if hits:
        print("對照官方原文：daily-brief/agent.md 第 {} 行：{}".format(hits[0][0], hits[0][1].strip()))
except Exception as exc:
    print("（這台電腦沒有官方 repo，略過原始碼對照：{}）".format(type(exc).__name__))'
   show "$P"; run "$P" ;;
2) banner "看 agent.json 和版本鎖"
   tip "agent.json 就是官方的 agent 物件。版本鎖 agent-lock.json 記著「第 1 版的內容指紋」：程式把設定正規化成 JSON 再算 sha256 取前 12 碼，跟鎖裡的比，不一樣就拒絕執行。"
   P='import hashlib, inspect, json
from pathlib import Path
import run_session as rs

d = Path("s4-managed-cloud/agents/price-report")
agent = json.loads((d / "agent.json").read_text(encoding="utf-8"))
lock = json.loads((d / "agent-lock.json").read_text(encoding="utf-8"))
print("=== agent.json 的欄位 ===")
for k, v in agent.items():
    text = json.dumps(v, ensure_ascii=False)
    print("  {:<13} {}".format(k, text if len(text) <= 70 else text[:70] + "…（共 {} 字）".format(len(text))))
print()
print("工具白名單 tools：", agent["tools"], "｜刻意不給 denied_tools：", agent["denied_tools"])
print()
canonical = json.dumps(agent, ensure_ascii=False, sort_keys=True).encode("utf-8")
digest = hashlib.sha256(canonical).hexdigest()[:12]
print("=== 版本鎖 agent-lock.json ===")
print(" ", json.dumps(lock, ensure_ascii=False))
print("  現在 agent.json 的指紋：", digest, "→", "和第 {} 版的鎖一致".format(agent["version"]) if lock.get(str(agent["version"])) == digest else "和鎖不一致！")
print()
print("=== load_agent 裡負責比對的那幾行 ===")
lines, start = inspect.getsourcelines(rs.load_agent)
for i, line in enumerate(lines, start):
    if any(key in line for key in ("canonical", "digest", "version_key", "lock[")):
        print("{:>4} | {}".format(i, line.rstrip()))'
   show "$P"; run "$P" ;;
3) banner "改了 model 卻不升 version：被程式拒絕（離線，會自動還原）"
   tip "先備份 agent.json 並記下 sha256，把 model 改成 haiku 再執行 run_session.py。版本鎖在建立 session 之前就擋下，所以不會呼叫模型。不管成功失敗都會寫回原檔，最後用 sha256 確認還原。後半在暫存資料夾示範「升 version 就放行」。"
   P='import hashlib, json, shutil, subprocess, sys, tempfile
from pathlib import Path
import run_session as rs

d = Path("s4-managed-cloud/agents/price-report")
cfg, lock_path = d / "agent.json", d / "agent-lock.json"
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
original = cfg.read_bytes()
before_cfg, before_lock = sha(cfg), sha(lock_path)
agent = json.loads(original.decode("utf-8"))
lock = json.loads(lock_path.read_text(encoding="utf-8"))
if str(agent["version"]) not in lock:
    print("版本鎖裡沒有第 {} 版，這一步會讓程式往下呼叫模型，所以停止。".format(agent["version"]))
    raise SystemExit(1)
backup = Path(tempfile.gettempdir()) / "k903-s4-agent.json.bak"
backup.write_bytes(original)
print("備份：", backup.name, "（系統暫存資料夾）｜原檔 sha256：", before_cfg[:16], "…")
try:
    changed = dict(agent, model="haiku")
    cfg.write_text(json.dumps(changed, ensure_ascii=False, indent=2) + chr(10), encoding="utf-8")
    print("已暫改：model sonnet → haiku，version 維持", agent["version"])
    print()
    proc = subprocess.run([sys.executable, "run_session.py"], cwd="s4-managed-cloud", capture_output=True,
                          text=True, encoding="utf-8", errors="replace", timeout=60)
    print("執行 run_session.py 的結果：exit code", proc.returncode, "（預期 1）")
    print("  stderr：", proc.stderr.strip())
finally:
    cfg.write_bytes(original)
after_cfg, after_lock = sha(cfg), sha(lock_path)
print()
print("還原 agent.json：", "成功，sha256 與原檔完全一致" if after_cfg == before_cfg else "失敗！請用 " + backup.name + " 手動還原")
print("agent-lock.json：", "沒有被改動" if after_lock == before_lock else "被改動了！")
if after_cfg == before_cfg:
    backup.unlink()
print()
print("=== 正確做法：升 version（在暫存資料夾做，不碰原檔、不呼叫模型） ===")
tmp = Path(tempfile.mkdtemp(prefix="k903-s4-"))
try:
    shutil.copy(d / "agent.json", tmp / "agent.json")
    shutil.copy(lock_path, tmp / "agent-lock.json")
    v2 = dict(agent, model="haiku", version=agent["version"] + 1)
    (tmp / "agent.json").write_text(json.dumps(v2, ensure_ascii=False, indent=2), encoding="utf-8")
    _, digest = rs.load_agent(tmp)
    print("load_agent 放行，第 2 版指紋：", digest)
    print("暫存資料夾的鎖變成：", (tmp / "agent-lock.json").read_text(encoding="utf-8").replace(chr(10), " "))
    print("→ 第 1 版的指紋還留著，舊 session 事後查得到當時用哪一版。")
finally:
    shutil.rmtree(tmp, ignore_errors=True)'
   show "$P"; run "$P" ;;
4) banner "實跑一個 session：寫報告＋評分"
   tip "這一步會呼叫模型最多 2 次（寫手一次、評分者一次，約 15～30 秒，不重試）。程式原本的上限是 4 次（不過就重寫一次），為了守住本章 2 次的預算，這裡在演練行程裡把 MAX_MODEL_CALLS 暫改成 2：萬一評分 FAIL，第 3 次呼叫會被擋下並寫一筆 session.error，這正好就是官方預算上限的作用。"
   P='import os, json, shutil, tempfile, time
from pathlib import Path
import run_session as rs

rs.MAX_MODEL_CALLS = 2  # 只在這個演練行程裡改，不動原檔
DRY = os.environ.get("S4_MODE") == "--dry-run"
calls = {"n": 0}
real_run = rs.run_claude
FAKE_REPORT = "# 網路交換器每日比價報告（乾跑）" + chr(10) + "（乾跑假報告，不是模型寫的）"
FAKE_GRADE = json.dumps({"criteria": [{"id": i, "result": "PASS", "reason": "乾跑假評分"} for i in range(1, 6)]})

def counted(prompt, system=None, model=None):
    calls["n"] += 1
    if DRY:
        return {"result": FAKE_REPORT if calls["n"] == 1 else FAKE_GRADE, "usage": {}, "duration_ms": 0}
    return real_run(prompt, system=system, model=model)

rs.run_claude = counted
tmp_runs = None
if DRY:
    tmp_runs = Path(tempfile.mkdtemp(prefix="k903-s4-runs-"))
    rs.RUNS_DIR = tmp_runs
    print("【乾跑模式】模型是寫死的假回覆，session 寫進暫存資料夾、跑完刪掉；正式演練不要加 --dry-run。")
d = Path("s4-managed-cloud")
started = time.time()
try:
    session = rs.run((d / "agents/price-report").resolve(), (d / "data/switches.json").resolve())
    rs.print_result(session)
except (RuntimeError, PermissionError, OSError, KeyError) as exc:
    print()
    print("session 中途停止：", exc)
    print("（events.jsonl 最後一筆是 session.error，第 5 步可以看到停在哪裡）")
finally:
    if tmp_runs is not None:
        shutil.rmtree(tmp_runs, ignore_errors=True)
print()
print("模型呼叫：{} 次（上限 2）｜耗時 {:.1f} 秒".format(calls["n"], time.time() - started))'
   show "$P"; run "$P" ;;
5) banner "逐行看 events.jsonl，對照官方 SSE 事件"
   tip "官方 session 的事件是 SSE 串流，可以即時看、也可以用 events.list 從頭重播。S4 把同一件事寫成一行一筆的 JSON，跑完才看。每一行對到官方哪一種事件，看右邊那一欄。"
   P='import json
from pathlib import Path

runs = sorted(Path("s4-managed-cloud/runs").glob("sesn_*/events.jsonl"))
if not runs:
    print("runs/ 裡沒有 session，請先跑第 4 步。")
    raise SystemExit(0)
path = runs[-1]
print("看最新一個 session：", path.parent.name, "（共 {} 個 session）".format(len(runs)))
OFFICIAL = {
    "session.created": "不是事件：sessions.create 回傳的 session 物件",
    "session.running": "session.status_running",
    "tool.use": "agent.custom_tool_use（自訂工具；內建工具是 agent.tool_use）",
    "tool.result": "user.custom_tool_result（由你的主機回送）",
    "model.call": "span.model_request_start／span.model_request_end",
    "agent.message": "agent.message",
    "outcome.graded": "outcomes 評分結果（官方範例沒示範，名稱是本機自訂）",
    "session.idle": "session.status_idle（stop_reason＝end_turn）",
    "session.error": "session.error",
}
events = []
for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
    try:
        events.append(json.loads(line))
    except ValueError:
        print("第 {} 行不是 JSON，略過".format(n))
print()
print("{:>3} | {:<8} | {:<15} | {:<34} | {}".format("#", "時間", "type", "重點欄位", "官方對應"))
print("-" * 125)
for i, e in enumerate(events, 1):
    keys = {k: v for k, v in e.items() if k not in ("ts", "type", "criteria", "preview", "input")}
    info = json.dumps(keys, ensure_ascii=False)
    print("{:>3} | {:<8} | {:<15} | {:<34} | {}".format(i, e.get("ts", "")[11:19], e.get("type"), info[:34],
          OFFICIAL.get(e.get("type"), "（沒有對應）")))
print()
ts = [e.get("ts", "") for e in events]
print("時間只增不減（只追加不修改）：", ts == sorted(ts))
print("最後一筆：", events[-1].get("type") if events else "（空）", "← 官方 session 跑完也會停在 status_idle 等下一個 user.message")
print("官方有、S4 沒有的：user.message（S4 把任務直接寫在提示詞裡）、agent.thinking、斷線續接。")'
   show "$P"; run "$P" ;;
6) banner "看報告、rubric 和評分：評分者抓到錯卻給 PASS"
   tip "評分者只照 rubric 打分。冒煙測試時，它在第 2 條理由裡指出報告一句比較寫錯了，但 rubric 第 2 條沒要求「比較要正確」，所以還是 PASS。rubric 寫得不夠具體，評分就會放水。"
   P='import json, re
from pathlib import Path

base = Path("s4-managed-cloud")
sessions = sorted(base.glob("runs/sesn_*/summary.json"))
if not sessions:
    print("runs/ 裡沒有完成的 session，請先跑第 4 步。")
    raise SystemExit(0)
latest = sessions[-1].parent
print("=== 最新 session 的 report.md（", latest.name, "）前 8 行 ===")
for line in (latest / "report.md").read_text(encoding="utf-8").splitlines()[:8]:
    print("  " + line)
print()
print("=== rubric.md 第 2 條 ===")
rubric = (base / "rubric.md").read_text(encoding="utf-8")
print("  " + next(l for l in rubric.splitlines() if l.startswith("2.")).replace("**", ""))
print()
WORDS = ("有誤", "錯", "不正確", "不一致", "但不影響")
found = None
for s in reversed(sessions):
    summ = json.loads(s.read_text(encoding="utf-8"))
    for c in summ["grades"][-1]["criteria"]:
        if c.get("result") == "PASS" and any(w in str(c.get("reason")) for w in WORDS):
            found = (s.parent.name, c)
            break
    if found:
        break
if found:
    print("=== 評分者「看到錯、仍給 PASS」的那一條（來源：{}） ===".format(found[0]))
    print("  第 {} 條 {}｜{}".format(found[1]["id"], found[1]["result"], found[1]["reason"]))
else:
    print("所有 session 的 PASS 理由都沒提到錯誤（模型每次不同）；README 第 5 節有冒煙測試那一次的原文。")
print()
data = json.loads((base / "data/switches.json").read_text(encoding="utf-8"))
top = next(x for x in data["items"] if "Mercusys MS105G" in x["name"])
cheaper = [x["name"] + " " + str(x["price"]) + " 元" for x in data["items"] if x["price"] < top["price"]]
print("用程式對資料：首選", top["name"], top["price"], "元；資料裡比它便宜的只有：", "、".join(cheaper) or "（沒有）")
toto = [x for x in data["items"] if "TOTOLINK" in x["name"]]
if toto and found:
    print("  TOTOLINK", toto[0]["price"], "元比首選貴，所以「價格僅高於無品牌款與 TOTOLINK」是錯的。")
print()
print("修法：rubric 第 2 條加一句「理由中的比較必須和輸入資料一致」，評分者就有依據給 FAIL、讓寫手重寫。")'
   show "$P"; run "$P" ;;
7) banner "deploy.py --dry-run：排程怎麼寫、雲端版要花錢"
   tip "排程的本質是「每天固定時間開一個新 session」。deploy.py 只印不建：不加 --dry-run 就拒絕。真的上雲端要 API 額度，帳戶只剩約 19.99 美元，所以本範例完全不呼叫 API。"
   P='import json, subprocess, sys
from pathlib import Path

def call(args):
    return subprocess.run([sys.executable, "deploy.py"] + args, cwd="s4-managed-cloud", capture_output=True,
                          text=True, encoding="utf-8", errors="replace", timeout=30)

p = call(["--dry-run"])
print("=== python deploy.py --dry-run（exit code {}） ===".format(p.returncode))
print(p.stdout.replace(str(Path.home()), "~"))
p = call([])
print("=== 不加 --dry-run（exit code {}，預期 2） ===".format(p.returncode))
print("  " + p.stderr.strip())
print()
if sys.platform == "win32":
    q = subprocess.run(["schtasks", "/Query", "/TN", "K903-S4-price-report"], capture_output=True, text=True,
                       encoding="cp950", errors="replace")
    print("確認沒有真的建排程：schtasks /Query exit code", q.returncode, "（非 0＝查無此排程）")
print()
dep = json.loads(Path("s4-managed-cloud/agents/price-report/deployment.json").read_text(encoding="utf-8"))
print("deployment.json 的 schedule：", json.dumps(dep["schedule"], ensure_ascii=False))
print("費用怎麼算（雲端預算欄位見上面 dry-run 的備註）：")
print("  本機版：模型走 claude -p（Max 訂閱），一天約 2～4 次呼叫，不花 API 額度；預算只用 MAX_MODEL_CALLS = 4 限次數。")
print("  雲端版：每天一個 session 都扣 API 額度（模型 token＋沙箱執行時間），用 budget.max_list_cost 設上限。")'
   show "$P"; run "$P" ;;
8) banner "三個靈魂拷問：先自己回答"
   tip "先不要看答案。對著 S4 想一想三題，各用一兩句話說出來；第 3 題特別想一下：如果這個代理真的搬上雲端，資料會存在哪裡、誰保管？想好之後說「繼續」，教練會執行 bash s4.sh 8b。"
   P='qs = [
    "1. 這個代理是給誰用的？（誰看結果、有沒有人即時盯著、所以需要什麼把關）",
    "2. 被賦予了哪些工具權限？（可以用什麼、刻意不給什麼、誰在檢查白名單）",
    "3. 資料和成果最後存在哪裡？（輸入、設定、事件、報告各在哪；換成真雲端又在哪）",
]
print("三個靈魂拷問：")
for q in qs:
    print("  " + q)
print()
print("提示：第 2 步的 tools／denied_tools、第 4 步的 call_tool、第 5 步的 events.jsonl 都是線索。")
print("想好後說「繼續」→ bash s4.sh 8b")'
   show "$P"; run "$P" ;;
8b) banner "三個靈魂拷問：範例答案＋本機和真雲端「存在哪裡」的差別"
   tip "範例答案直接從 s4-managed-cloud/README.md 的表格讀出來。重點在第 3 題：本機版所有東西都在你的硬碟；換成真雲端，session、事件、評分都在 Anthropic 那邊，你要靠 API 取回。"
   P='import re
from pathlib import Path

readme = Path("s4-managed-cloud/README.md").read_text(encoding="utf-8")
rows = [line for line in readme.splitlines() if re.match(r"^[|] (這個代理|被賦予|資料和成果)", line)]
print("=== 範例答案（摘自 s4-managed-cloud/README.md） ===")
for line in rows:
    cells = [c.strip() for c in line.strip("|").split("|")]
    q, a = cells[0], cells[1].replace("**", "").replace(chr(96), "")
    print("■ " + q)
    print("  " + a)
    print()
if len(rows) != 3:
    print("（README 表格只讀到 {} 列，請直接打開 README 第 2 節看）".format(len(rows)))
print("=== 第 3 題：本機模擬 vs 真正雲端，資料存在哪裡 ===")
change = [
    ("代理設定", "agents/price-report/agent.json（自己的硬碟）", "Anthropic 的 agent 物件；本機只留 ant apply 的檔案與 lock"),
    ("版本紀錄", "agent-lock.json，自己算 sha256", "伺服器自動發新版本，舊版仍可查"),
    ("session", "runs/<sesn_id>/ 資料夾", "Anthropic 伺服器上，用 session ID 查"),
    ("事件", "events.jsonl，跑完才寫完", "伺服器保存，SSE 即時串流、events.list 重播、可斷線續接"),
    ("報告", "runs/.../report.md", "沙箱檔案或 agent.message；要自己取回存檔"),
    ("跨日記憶", "沒有", "memory store（伺服器保管，可設唯讀或讀寫）"),
    ("憑證", "不需要（claude -p 用訂閱）", "API 金鑰放主機環境變數；第三方憑證放 vault"),
]
print("{:<8} | {:<40} | {}".format("項目", "本機模擬（S4）", "真正雲端（Managed Agents）"))
print("-" * 120)
for r in change:
    print("{:<8} | {:<40} | {}".format(*r))
print()
print("一句話：本機版「資料都在自己手上、刪資料夾就沒了」；雲端版「資料在 Anthropic 保管，換來重播、續接和跨日記憶，代價是 API 額度與資料離開本機」。")'
   show "$P"; run "$P" ;;
*) echo "步驟要 1～8（第 8 步的後半是 8b）" ;;
esac
