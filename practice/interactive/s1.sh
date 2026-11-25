#!/bin/bash
# K903 範例 S1 互動演練：本機資料夾小管家——自己寫的最小工具迴圈（模仿官方第 3 章 agents），一次跑一步
# 用法：bash s1.sh <步驟 1-8>；第 8 步分兩半：bash s1.sh 8（先出題）→ bash s1.sh 8b（範例答案＋改給客戶用會怎麼變）
# 呼叫模型：只有第 4 步會呼叫模型，最多 2 次（claude -p，透過 shared/llm_agent.py；不重試），其餘步驟全部離線
# 乾跑：bash s1.sh 4 --dry-run 用寫死的假回覆代替模型，只用來檢查腳本路徑，不算演練（畫面會標明）
set -u
STEP="${1:-1}"
MODE="${2:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/../.."
G=$'\e[32m'; Y=$'\e[33m'; C=$'\e[36m'; B=$'\e[1m'; N=$'\e[0m'

banner() { clear; printf '%s╔══════════════════════════════════════════════════════╗%s\n' "$C" "$N"; printf '%s  K903 範例 S1｜本機資料夾小管家　第 %s / 8 步%s\n' "$B" "${STEP%b}" "$N"; printf '%s  %s%s\n' "$B" "$1" "$N"; printf '%s╚══════════════════════════════════════════════════════╝%s\n\n' "$C" "$N"; }
tip() { printf '%s💡 %s%s\n\n' "$Y" "$1" "$N"; }
show() { printf '%s▶ 要執行的程式：%s\n' "$G" "$N"; printf '%s' "$1" | sed "s/^/${G}  │ ${N}/"; printf '\n%s▶ 執行結果：%s\n' "$G" "$N"; }
# 在 repo 根目錄執行；P 用單引號包住，所以 Python 程式碼裡不能出現單引號
run() { (cd "$REPO" && PYTHONUTF8=1 S1_MODE="$MODE" python - <<PY
import sys
sys.path.insert(0, "s1-agent-loop")
sys.path.insert(0, "shared")
$1
PY
); rc=$?; printf '\n%s👉 第 %s 步完成（結束碼 %s）%s\n' "$C" "$STEP" "$rc" "$N"; return $rc; }

case "$STEP" in
1) banner "這個範例模仿官方第 3 章的什麼"
   tip "官方 agents 是一個 while True 迴圈：呼叫模型 → 有工具要求就執行 → 結果放回歷史 → 再呼叫。S1 把同一個迴圈縮成不到兩百行，用 claude -p 驅動，工具換成三個唯讀的檔案工具。"
   P='from pathlib import Path
import folder_agent as fa

home = Path.home()
def short(p):
    p = Path(p)
    try:
        return "~/" + p.resolve().relative_to(home).as_posix()
    except ValueError:
        return str(p)

src = Path("s1-agent-loop/folder_agent.py").read_text(encoding="utf-8").splitlines()
print("S1 主程式：s1-agent-loop/folder_agent.py，共", len(src), "行")
print("預設根目錄：", short(fa.DEFAULT_ROOT), "（存在：{}）".format(fa.DEFAULT_ROOT.is_dir()))
print("官方講義：", "~/workspace/kindle-902-claude-quickstarts/lessons/ch03-agents.md",
      "（存在：{}）".format((home / "workspace/kindle-902-claude-quickstarts/lessons/ch03-agents.md").is_file()))
print()
rows = [
    ("代理迴圈", "agent.py 的 _agent_loop：while True", "agent_loop：for 最多 {} 輪".format(fa.MAX_ROUNDS)),
    ("呼叫模型", "anthropic SDK＋API 金鑰", "claude -p（shared/llm_agent.py），不設金鑰"),
    ("工具協定", "原生 tool_use／tool_result block", "提示詞約定：回 {tool,args} 或 {final} JSON"),
    ("一輪幾個工具", "可多個，預設平行", "一個"),
    ("結束條件", "這一輪沒有 tool_use", "回了 final，或第 {} 輪強制回答".format(fa.MAX_ROUNDS)),
    ("歷史", "MessageHistory，超過上限丟最舊", "build_prompt 每輪重送全文，工具結果截到 {} 字".format(fa.RESULT_LIMIT)),
    ("工具", "本機工具＋MCP＋伺服器端工具", "list_dir、read_file、search_text（全部唯讀）"),
]
print("{:<10} | {:<34} | {}".format("項目", "官方 agents（第 3 章）", "S1 本機資料夾小管家"))
print("-" * 100)
for r in rows:
    print("{:<10} | {:<34} | {}".format(*r))
print()
try:
    import qs_source
    hits = qs_source.grep("agents/agent.py", "while True:")
    if hits:
        print("對照官方原始碼：agents/agent.py 第 {} 行 {}".format(hits[0][0], hits[0][1].strip()))
except Exception as exc:
    print("（這台電腦沒有官方 repo，略過原始碼對照：{}）".format(type(exc).__name__))'
   show "$P"; run "$P" ;;
2) banner "看工具定義：三個唯讀工具，全部鎖在根目錄"
   tip "工具就是「說明文字寫進系統提示＋一個 Python 函式」。模型只能回文字（claude -p 加了 --tools 空字串），真正讀檔的是我們的程式；每個工具第一行都先過 safe_path。"
   P='import inspect
import folder_agent as fa
import llm_agent

print("=== 寫進系統提示的工具說明（模型只看得到這段） ===")
print(fa.SYSTEM_PROMPT)
print()
print("TOOLS 對照表：", {k: v.__name__ for k, v in fa.TOOLS.items()})
print("read_file 上限 RESULT_LIMIT =", fa.RESULT_LIMIT, "字；search_text 最多", fa.MAX_SEARCH_HITS, "筆；只搜", sorted(fa.TEXT_SUFFIXES))
print()
print("=== safe_path：唯一的守門員 ===")
lines, start = inspect.getsourcelines(fa.safe_path)
for i, line in enumerate(lines, start):
    print("{:>4} | {}".format(i, line.rstrip()))
print()
cmd = llm_agent.build_command("claude", "sys.txt", None)
print("claude -p 的旗標：", " ".join(cmd[1:]))
print("→ --tools 後面是空字串：模型自己什麼都不能做，只能提出請求。")
print()
root = fa.DEFAULT_ROOT.resolve()
listing = fa.run_tool(root, "list_dir", {"path": "."}).splitlines()
print("離線試用 list_dir(\".\")：共 {} 項，最後 3 項：".format(len(listing)))
for name in listing[-3:]:
    print("  ", name)'
   show "$P"; run "$P" ;;
3) banner "看迴圈主程式：agent_loop、build_prompt、ask_model"
   tip "每次 claude -p 都是全新行程、沒有記憶，所以 build_prompt 每輪把「問題＋之前所有請求與工具結果」攤平重送。這就是官方 history 在做的事。"
   P='import inspect, json
import folder_agent as fa

for fn in (fa.agent_loop, fa.ask_model):
    lines, start = inspect.getsourcelines(fn)
    print("=== {}（第 {}～{} 行） ===".format(fn.__name__, start, start + len(lines) - 1))
    for i, line in enumerate(lines, start):
        print("{:>4} | {}".format(i, line.rstrip()))
    print()

print("=== 示範：第 2 輪送給模型的逐字稿長什麼樣（離線組字串，不呼叫模型） ===")
fake_steps = [{"round": 1, "request": {"tool": "list_dir", "args": {"path": "."}},
               "result": "2026-11-24-network-switch/\n2026-11-25-latte-art-pitcher/\nREADME.md"}]
print(fa.build_prompt("最近一次比價是什麼商品？", fake_steps, is_last=False))
print()
print("最後一輪（第 {} 輪）結尾會換成：".format(fa.MAX_ROUNDS))
print(fa.build_prompt("最近一次比價是什麼商品？", [], is_last=True).splitlines()[-1])'
   show "$P"; run "$P" ;;
4) banner "實跑一題：真模型自己決定用哪個工具"
   tip "這一步會呼叫模型最多 2 次（每次約 5～10 秒，不重試）。做法就是 agent_loop 的 max_rounds=2（等於命令列的 --max-rounds 2）：第 2 輪是最後一輪，提示詞會要求模型直接作答、不能再用工具。答案空的、太短或把格式說明抄回來，is_valid_answer 會擋下並標成「模型未給出有效答案」。題目只看資料夾名稱就答得出來。"
   P='import os, time
import folder_agent as fa

DRY = os.environ.get("S1_MODE") == "--dry-run"
calls = {"n": 0}

def fake_run(prompt, system=None):
    # 乾跑用：第 1 次要 list_dir，第 2 次回答；只檢查腳本路徑，不是真模型
    calls["n"] += 1
    if calls["n"] == 1:
        return {"result": "{\"tool\": \"list_dir\", \"args\": {\"path\": \".\"}}"}
    return {"result": "{\"final\": \"（乾跑假答案，不是模型回的）\"}"}

if DRY:
    fa.run_claude = fake_run
    print("【乾跑模式】模型是寫死的假回覆，只用來檢查路徑；正式演練不要加 --dry-run。")
QUESTION = "最新的一筆比價是哪一天、什麼商品？列出根目錄，看資料夾名稱回答就好。"
root = fa.DEFAULT_ROOT.resolve()
print("問題：", QUESTION)
print()
started = time.time()
try:
    answer, steps, valid = fa.agent_loop(root, QUESTION, max_rounds=2)
except RuntimeError as exc:
    print("呼叫模型失敗：", exc)
    raise SystemExit(1)
log_path = None if DRY else fa.save_run(root, QUESTION, answer, steps, time.time() - started, valid)
print()
print("=== 答案 ===")
print(answer)
print()
print("模型呼叫：{} 次（上限 2）｜有效答案：{}｜耗時 {:.1f} 秒".format(len(steps), valid, time.time() - started))
print("紀錄：" + ("乾跑不寫紀錄" if log_path is None else "s1-agent-loop/runs/" + log_path.name))
raise SystemExit(0 if valid else 3)'
   show "$P"; run "$P" ;;
5) banner "看 runs/ 的 JSON 紀錄：記了什麼、刻意沒記什麼"
   tip "紀錄只存問題、答案、每輪請求與結果長度，不存工具讀到的全文，避免把私人筆記再複製一份。找不到第 4 步的紀錄時，改看冒煙測試留下的那一份。"
   P='import json
from pathlib import Path

runs = sorted(Path("s1-agent-loop/runs").glob("*.json"))
if not runs:
    print("runs/ 裡沒有紀錄，請先跑第 4 步。")
    raise SystemExit(0)
print("runs/ 共 {} 份紀錄：{}".format(len(runs), ", ".join(p.name for p in runs[-4:])))
latest = runs[-1]
try:
    rec = json.loads(latest.read_text(encoding="utf-8"))
except ValueError as exc:
    print("紀錄讀不懂：", latest.name, exc)
    raise SystemExit(1)
print("看最新一份：", latest.name)
print()
print("最上層欄位：", list(rec.keys()))
print("問題：", rec.get("question"))
print("模型呼叫：", rec.get("model_calls"), "次｜耗時：", rec.get("seconds"), "秒｜有效答案：", rec.get("valid_answer", "（舊紀錄沒有這個欄位）"))
print()
print("{:>4} | {:<12} | {:>8} | {}".format("輪", "工具", "結果字數", "請求"))
print("-" * 90)
for r in rec.get("rounds", []):
    print("{:>4} | {:<12} | {:>8} | {}".format(r.get("round"), str(r.get("tool")), r.get("result_chars"),
          json.dumps(r.get("request"), ensure_ascii=False)[:60]))
print()
has_full = any("result" in r for r in rec.get("rounds", []))
print("rounds 裡有沒有 result 全文：", has_full, "（預期 False，save_run 刻意拿掉）")
print("root 欄位存的是：", str(rec.get("root")).replace(str(Path.home()), "~"), "← 實際存的是本機絕對路徑（這裡把家目錄顯示成 ~），紀錄不進版控（.gitignore 有 */runs/）")'
   show "$P"; run "$P" ;;
6) banner "試路徑跳脫：.. 和絕對路徑都被擋（離線）"
   tip "模型提出的路徑一律不可信。safe_path 先 resolve 再檢查是不是在根目錄底下，被擋的請求變成錯誤文字回給模型，程式不會當掉。危險路徑在讀檔之前就被拒絕，所以不會真的碰到那些檔案。"
   P='import folder_agent as fa

root = fa.DEFAULT_ROOT.resolve()
cases = [
    ("list_dir", {"path": "."}, "根目錄本身"),
    ("list_dir", {"path": "2026-11-25-latte-art-pitcher"}, "根目錄內的子資料夾"),
    ("read_file", {"path": "../../.ssh/id_rsa"}, "用 .. 往上跳"),
    ("list_dir", {"path": "C:/Windows"}, "Windows 絕對路徑"),
    ("read_file", {"path": "/etc/passwd"}, "Unix 絕對路徑"),
    ("list_dir", {"path": "2026-11-25-latte-art-pitcher/../../life-notes"}, "先進去再跳出來"),
    ("delete_file", {"path": "README.md"}, "要一個不存在的工具"),
    ("read_file", {"file": "README.md"}, "參數名稱寫錯"),
]
print("{:<12} | {:<44} | {:<16} | {}".format("工具", "參數", "情境", "結果首行"))
print("-" * 120)
for name, args, label in cases:
    out = fa.run_tool(root, name, args)
    first = out.splitlines()[0][:50] if out else ""
    print("{:<12} | {:<44} | {:<16} | {}".format(name, str(args)[:44], label, first))
print()
print("已知漏洞（README 第 6 節有寫）：search_text 用 rglob 掃整棵樹，沒有逐檔過 safe_path；")
print("根目錄裡若有指向外面的符號連結，內容仍會被搜到。")'
   show "$P"; run "$P" ;;
7) banner "換一個自己的問題或 --root（離線看機制）"
   tip "換資料夾只要加 --root。這一步不呼叫模型：先離線看換根目錄後工具看到什麼、錯的根目錄怎麼在呼叫模型前就被擋。真的要問自己的問題，演練結束後照畫面最後的指令自己跑（會再花 2～5 次呼叫）。"
   P='import subprocess, sys
from pathlib import Path
import folder_agent as fa

new_root = Path.home() / "workspace" / "console" / "life-notes"
print("換成 --root ~/workspace/console/life-notes（存在：{}）".format(new_root.is_dir()))
if new_root.is_dir():
    r = new_root.resolve()
    print("list_dir(\".\")：")
    for line in fa.run_tool(r, "list_dir", {"path": "."}).splitlines():
        print("  ", line)
    print("search_text(\"溫度\") 前 3 筆：")
    for line in fa.run_tool(r, "search_text", {"keyword": "溫度"}).splitlines()[:3]:
        print("  ", line[:100])
    print("原本根目錄的檔案，現在變成跳脫：", fa.run_tool(r, "list_dir", {"path": "../shopping-notes"}))
print()
print("Git Bash 的 ~ 可能被展開成 /c/Users/...，to_local_path 會轉成 Windows 看得懂的寫法：")
print("  /c/Users/someone/notes →", fa.to_local_path("/c/Users/someone/notes").as_posix() if sys.platform == "win32" else "（非 Windows 不轉換）")
print()
print("錯的根目錄：實際執行 folder_agent.py --root ~/no-such-dir（在呼叫模型前就結束）")
proc = subprocess.run([sys.executable, "s1-agent-loop/folder_agent.py", "--root", str(Path.home() / "no-such-dir"), "測試"],
                      capture_output=True, text=True, encoding="utf-8", errors="replace")
print("  exit code：", proc.returncode, "（預期 2）")
print("  stderr：", proc.stderr.strip().replace(str(Path.home()), "~"))
print()
print("演練結束後，自己換題目試試（會呼叫模型 2～5 次）：")
print("  cd ~/workspace/kindle-903-quickstarts-samples/s1-agent-loop")
print("  PYTHONUTF8=1 python folder_agent.py --root ~/workspace/console/life-notes \"最近量了什麼？\"")'
   show "$P"; run "$P" ;;
8) banner "三個靈魂拷問：先自己回答"
   tip "先不要看答案。對著 S1 想一想三題，各用一兩句話說出來；想好之後說「繼續」，教練會執行 bash s1.sh 8b 顯示範例答案。"
   P='qs = [
    "1. 這個代理是給誰用的？（誰在什麼地方、用什麼方式跟它說話）",
    "2. 被賦予了哪些工具權限？（可以做什麼、刻意不給什麼、範圍到哪裡）",
    "3. 資料和成果最後存在哪裡？（答案在哪、紀錄在哪、哪些東西刻意不存）",
]
print("三個靈魂拷問：")
for q in qs:
    print("  " + q)
print()
print("提示：第 2、5、6 步看到的 safe_path、--tools 空字串、runs/ 紀錄欄位都是線索。")
print("想好後說「繼續」→ bash s1.sh 8b")'
   show "$P"; run "$P" ;;
8b) banner "三個靈魂拷問：範例答案＋改給客戶用會怎麼變"
   tip "範例答案直接從 s1-agent-loop/README.md 的表格讀出來。重點在右半：同一個迴圈，使用者從自己換成客戶，三題的答案全部要重寫。"
   P='import re
from pathlib import Path

readme = Path("s1-agent-loop/README.md").read_text(encoding="utf-8")
rows = [line for line in readme.splitlines() if re.match(r"^[|] (這個代理|被賦予|資料和成果)", line)]
print("=== 範例答案（摘自 s1-agent-loop/README.md） ===")
for line in rows:
    cells = [c.strip() for c in line.strip("|").split("|")]
    q, a = cells[0], re.sub(r"<br/?>", " ", cells[1]).replace("**", "").replace(chr(96), "")
    print("■ " + q)
    print("  " + a)
    print()
if len(rows) != 3:
    print("（README 表格只讀到 {} 列，請直接打開 README 第 2 節看）".format(len(rows)))
print("=== 如果改成給客戶用（例：讓客戶問你公開的產品說明資料夾） ===")
change = [
    ("給誰用", "自己，在終端機一個人用",
     "外部客戶，從網頁或客服聊天進來；要登入或至少限流，要擋惡意提問與提示詞注入"),
    ("工具權限", "三個唯讀工具，根目錄是自己的筆記",
     "根目錄換成只放公開文件的專用資料夾；仍然唯讀；補 search_text 的符號連結漏洞；限制單檔大小與每人每分鐘次數；回答前過濾不該外流的內容"),
    ("存在哪裡", "答案印在終端機；runs/ 只存長度，不進版控",
     "答案回到客戶畫面；紀錄要去識別化（不存客戶個資與本機絕對路徑）、定保存期限、集中到伺服器 log；模型改用 API（金鑰放伺服器環境變數），不能再用個人訂閱的 claude -p"),
]
print("{:<8} | {:<30} | {}".format("題目", "現在（給自己）", "改給客戶用"))
print("-" * 120)
for r in change:
    print("{:<8} | {:<30} | {}".format(*r))
print()
print("一句話：S1 安全是因為「使用者＝資料擁有者＝唯一受影響的人」；換成客戶，這三個角色分開了，權限與紀錄就要重新設計。")'
   show "$P"; run "$P" ;;
*) echo "步驟要 1～8（第 8 步的後半是 8b）" ;;
esac
