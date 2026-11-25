#!/bin/bash
# K903 範例 S3 互動演練：兩階段自動寫程式 harness——初始化代理切功能寫測試，寫程式代理一個 session 做一項，中斷後接著做，一次跑一步
# 用法：bash s3.sh <步驟 1-8>；第 8 步分兩半：bash s3.sh 8（先出題）→ bash s3.sh 8b（範例答案＋還原 workdir）
#       bash s3.sh restore：把 workdir 還原成演練前 4/4 完成的備份（8b 也會問要不要還原）
#       bash s3.sh seed：新電腦用，從 s3-long-running/snapshot-4of4 重建 workdir（不呼叫模型）；
#       第 3、4、7 步和 restore 發現 workdir 與備份都不存在時也會自動重建
# 呼叫模型：只有第 5、6 步會呼叫模型，各最多 2 次（harness.py 自己的 claude -p，--max-calls 2），整章最多 4 次；其餘步驟全部離線
# 乾跑：bash s3.sh 5 --dry-run／bash s3.sh 6 --dry-run 用寫死的假回覆（內容取自 4/4 完成版）代替模型，
#       產出寫到 s3-long-running/logs/dry-run-workdir（已被 .gitignore 排除），不動真正的 workdir，只用來檢查腳本路徑，不算演練
# 不設任何 API 金鑰
set -u
STEP="${1:-1}"
MODE="${2:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
S3="$ROOT/s3-long-running"
WD="$S3/workdir"
BAK="$S3/workdir.bak-4of4"
DRYWD="$S3/logs/dry-run-workdir"
SNAP="$S3/snapshot-4of4"
G=$'\e[32m'; Y=$'\e[33m'; C=$'\e[36m'; R=$'\e[31m'; B=$'\e[1m'; N=$'\e[0m'

banner() { clear; printf '%s╔══════════════════════════════════════════════════════╗%s\n' "$C" "$N"; printf '%s  K903 範例 S3｜兩階段自動寫程式　第 %s / 8 步%s\n' "$B" "${STEP%b}" "$N"; printf '%s  %s%s\n' "$B" "$1" "$N"; printf '%s╚══════════════════════════════════════════════════════╝%s\n\n' "$C" "$N"; }
tip() { printf '%s💡 %s%s\n\n' "$Y" "$1" "$N"; }
warn() { printf '%s⚠ %s%s\n' "$R" "$1" "$N"; }
show() { printf '%s▶ 要執行的程式：%s\n' "$G" "$N"; printf '%s' "$1" | sed "s/^/${G}  │ ${N}/"; printf '\n%s▶ 執行結果：%s\n' "$G" "$N"; }
done_step() { printf '\n%s👉 第 %s 步完成%s\n' "$C" "$STEP" "$N"; }
# 在 s3-long-running/ 底下跑一段 Python；P 用單引號包住，所以 Python 程式碼裡不能出現單引號
run() { (cd "$S3" && PYTHONUTF8=1 PYTHONDONTWRITEBYTECODE=1 S3_MODE="$MODE" S3_BAK="$(basename "$BAK")" S3_DRYWD="logs/$(basename "$DRYWD")" python - <<PY
import sys
sys.path.insert(0, ".")
sys.path.insert(0, "../shared")
$1
PY
); RUN_RC=$?; done_step; }
# 在 s3-long-running/ 底下跑一行 shell 指令
runcmd() { (cd "$S3" && eval "$1"); done_step; }
# 印出某個 workdir 的完成數，例如 4/4；沒有清單就印 none
# 傳相對於 s3-long-running/ 的名稱給 Windows 的 Python（/c/... 這種 MSYS 路徑它看不懂）
progress_of() { (cd "$S3" && PYTHONUTF8=1 python -c "
import json, sys
from pathlib import Path
p = Path(sys.argv[1]) / 'feature_list.json'
if not p.exists():
    print('none'); sys.exit(0)
try:
    fs = json.loads(p.read_text(encoding='utf-8'))['features']
except (ValueError, KeyError):
    print('broken'); sys.exit(0)
print('{}/{}'.format(sum(1 for f in fs if f.get('passes')), len(fs)))
" "$(basename "$1")"); }
# 給人看的版本：4/4 完成、沒有功能清單、清單讀不懂
label_of() { local p; p="$(progress_of "$1")"; case "$p" in none) echo 沒有功能清單 ;; broken) echo 清單讀不懂 ;; *) echo "$p 完成" ;; esac; }
is_full() { local p; p="$(progress_of "$1")"; [ "$p" != none ] && [ "$p" != broken ] && [ "${p%/*}" = "${p#*/}" ]; }

# 乾跑用：把 harness 的模型呼叫換成假回覆，內容取自 4/4 完成版（備份優先，沒有就用現在的 workdir）
DRY_PY='import json, os
from pathlib import Path
import harness

src = Path(os.environ["S3_BAK"])
if not (src / "ledger.py").exists():
    src = Path("workdir")
if not (src / "ledger.py").exists():
    print("乾跑需要一份 4/4 完成版當假回覆的來源，找不到 workdir/ledger.py 或備份。")
    raise SystemExit(1)

def fake_ask(prompt, system=None):
    # 初始化代理：回原本的功能清單＋測試檔；寫程式代理：回完成版 ledger.py
    if "初始化代理" in (system or ""):
        feats = json.loads((src / "feature_list.json").read_text(encoding="utf-8"))["features"]
        files = [{"path": "tests/" + p.name, "content": p.read_text(encoding="utf-8")}
                 for p in sorted((src / "tests").glob("*.py"))]
        return json.dumps({"features": [{k: f[k] for k in ("id", "description", "test_command")} for f in feats],
                           "files": files, "progress_note": "（乾跑假筆記）"}, ensure_ascii=False)
    return json.dumps({"files": [{"path": "ledger.py", "content": (src / "ledger.py").read_text(encoding="utf-8")}],
                       "note": "（乾跑假筆記）"}, ensure_ascii=False)

harness.ask = fake_ask
dry = Path(os.environ["S3_DRYWD"]).resolve()
print("【乾跑模式】模型是寫死的假回覆，產出寫到 logs/dry-run-workdir；正式演練不要加 --dry-run。")
print()'

restore() {
  rm -rf "$DRYWD"
  if [ -d "$BAK" ]; then
    if ! is_full "$BAK"; then warn "備份 $(basename "$BAK") 不是全部完成（$(label_of "$BAK")），不自動還原，請手動檢查"; return 1; fi
    rm -rf "$WD" && mv "$BAK" "$WD" || { warn "還原失敗：mv 不成功（可能有檔案被其他程式開著）"; return 1; }
    printf '%s已還原：workdir.bak-4of4 → workdir%s\n' "$G" "$N"
  elif is_full "$WD"; then
    printf 'workdir 本來就是全部完成的狀態，不需要還原。\n'
  else
    warn "找不到備份 workdir.bak-4of4，workdir 目前是 $(label_of "$WD")；要回到 4/4 完成版：rm -rf s3-long-running/workdir && bash s3.sh seed（或照 s3-long-running/README.md 重跑 harness）"
    return 1
  fi
  printf 'workdir 現在：%s｜git HEAD %s\n' "$(label_of "$WD")" "$(cd "$WD" && git log -1 --format=%h 2>/dev/null)"
}

# 從 snapshot-4of4 重建 workdir：複製檔案 → git init → 一個 commit（原本的 5 個 commit 只留在 git-log.txt）
seed() {
  if [ -d "$WD" ]; then
    printf 'workdir 已經存在（%s），不重建。要從快照重來，先刪掉 s3-long-running/workdir 再跑 bash s3.sh seed。
' "$(label_of "$WD")"
    return 0
  fi
  if [ -d "$BAK" ]; then
    printf '有 workdir.bak-4of4 備份（演練中），不從快照重建；要還原請跑 bash s3.sh restore。
'
    return 0
  fi
  if [ ! -f "$SNAP/feature_list.json" ]; then warn "找不到快照 $SNAP/feature_list.json，無法重建"; return 1; fi
  mkdir -p "$WD" && cp -R "$SNAP"/. "$WD"/ && rm -f "$WD/README.md" "$WD/git-log.txt"     || { warn "複製快照失敗"; rm -rf "$WD"; return 1; }
  if ! (cd "$WD" && git init -q && git add -A         && git -c user.name=k903-harness -c user.email=harness@localhost commit -q              -m "從 snapshot-4of4 重建：4/4 完成版（原本的 git log 見 snapshot-4of4/git-log.txt）"); then
    warn "git init／commit 失敗，已刪掉重建到一半的 workdir"; rm -rf "$WD"; return 1
  fi
  printf '%s已從 snapshot-4of4 重建 workdir：%s｜git HEAD %s%s
' "$G" "$(label_of "$WD")" "$(cd "$WD" && git log -1 --format=%h)" "$N"
}
# 第 3、4、7 步和 restore 用：workdir 與備份都不存在（例如新電腦剛 clone）就自動重建
ensure_wd() {
  if [ ! -d "$WD" ] && [ ! -d "$BAK" ]; then
    printf '%s找不到 workdir 也沒有備份（新電腦剛 clone？），先從 snapshot-4of4 自動重建。%s
' "$Y" "$N"
    seed || exit 1
    echo
  fi
}

if [ ! -d "$S3" ]; then echo "找不到範例資料夾：$S3"; exit 1; fi

case "$STEP" in
seed) STEP=0; seed ;;

1) banner "長時間工作的難處：context 會滿、會中斷、會自我放水"
   tip "叫代理一口氣寫完一個專案會出三種事：對話越來越長塞爆 context、跑到一半被中斷就全部重來、自己說「做好了」其實沒做好。官方 autonomous-coding 的解法是「兩階段＋進度檔＋git」。先把三個難處對到 S3 的做法。本步不呼叫模型。"
   P='from pathlib import Path

rows = [
    ("context 會滿", "一個對話做到底，越做越長，前面的事被擠掉或變貴",
     "每個 session 都是全新 context，只做一項功能", "每次 claude -p 都是新行程；提示詞只帶規格、清單、筆記、git log、現有檔案（上限 4 萬字）"),
    ("會中斷", "當機、限流、關機，跑到一半的狀態全丟",
     "狀態寫在檔案和 git，重跑同一條指令就接著做", "feature_list.json＋progress.md＋git；session 編號從 progress.md 數出來"),
    ("會自我放水", "代理自己說做好了，或改測試、改清單讓自己過關",
     "先寫驗收測試，再逐項實作（官方只靠提示詞叮嚀）", "測試由初始化代理寫、寫程式代理不能改 tests/；passes 只有 harness 跑完測試才能改"),
]
print("{:<10} | {:<34} | {:<34} | {}".format("難處", "會發生什麼", "官方解法", "S3 怎麼做"))
print("-" * 150)
for r in rows:
    print("{:<10} | {:<34} | {:<34} | {}".format(*r))
print()
print("兩階段：")
print("  第 1 階段　初始化代理：讀 app_spec.md → 切 3～4 項功能＋寫好驗收測試（只跑一次）")
print("  第 2 階段　寫程式代理：每個 session 挑一項沒過的功能 → 寫程式 → harness 跑測試 → 通過才 commit")
print()
lesson = Path.home() / "workspace" / "kindle-902-claude-quickstarts" / "lessons" / "ch10-autonomous-coding.md"
print("官方導讀：~/workspace/kindle-902-claude-quickstarts/lessons/ch10-autonomous-coding.md（{}）".format("在" if lesson.exists() else "這台沒有"))
print("差別：官方用 Claude Agent SDK＋API 金鑰、模型自己有 Read/Write/Bash；S3 走 claude -p、模型沒有任何工具，只回 JSON。")'
   show "$P"; run "$P" ;;

2) banner "看 app_spec.md 和 harness 的兩階段結構"
   tip "app_spec.md 是唯一的需求來源，最重要的是「介面」那一段：測試和實作由不同 session 寫，靠它對齊。harness.py 的外層 run() 只做一個判斷：feature_list.json 不存在就跑初始化，存在就挑下一項功能。本步只讀檔，不呼叫模型。"
   P='import inspect
from pathlib import Path
import harness

spec = Path("app_spec.md").read_text(encoding="utf-8").splitlines()
print("=== app_spec.md（{} 行）的段落 ===".format(len(spec)))
for line in spec:
    if line.startswith("#"):
        print("  " + line)
print()
print("=== 「介面」那一段（實作與測試都照這個） ===")
on = False
for line in spec:
    if line.startswith("## "):
        on = line.startswith("## 介面")
        continue
    if on and line.strip():
        print("  " + line)
print()
print("=== harness.py 的兩階段（函式與行號） ===")
parts = [
    ("第 1 階段", harness.run_initializer, "INIT_PROMPT 叫模型切功能＋寫測試；validate_features 檢查 3～4 項；最後才寫清單"),
    ("第 2 階段", harness.pick_feature, "挑第一項 passes=false 且嘗試少於 {} 次的功能".format(harness.MAX_ATTEMPTS)),
    ("第 2 階段", harness.run_coding, "CODE_PROMPT 叫模型回 ledger.py；harness 寫檔、跑測試、改 passes、commit"),
    ("外層", harness.run, "跑 --max-sessions 圈；每圈判斷要初始化還是寫程式；全部過了就停"),
]
for stage, fn, desc in parts:
    lines, start = inspect.getsourcelines(fn)
    print("  {:<6} {:<16} 第 {:>3}～{:>3} 行｜{}".format(stage, fn.__name__, start, start + len(lines) - 1, desc))
print()
lines, start = inspect.getsourcelines(harness.run)
print("=== run() 原始碼 ===")
for i, line in enumerate(lines, start):
    print("{:>4} | {}".format(i, line.rstrip()))'
   show "$P"; run "$P" ;;

3) banner "跨 session 的記憶就是這三個檔：feature_list.json、progress.md、git log"
   tip "寫程式代理每次都是全新 context，對上一棒一無所知。它知道進度，全靠 harness 把這三樣東西塞進提示詞：清單說還剩什麼、筆記說上一棒做了什麼、git log 是存檔點。本步讀現在的 workdir（演練前是 4/4 完成版），不呼叫模型。"
   P='import json, subprocess
from pathlib import Path
import harness

wd = Path("workdir")
if not (wd / "feature_list.json").exists():
    print("workdir 還沒有 feature_list.json（第 5 步會先把它改名備份、從空的 workdir 重來）。執行 bash s3.sh restore 還原後再看。")
    raise SystemExit(0)
feats = harness.load_features(wd)
print("【1】feature_list.json：功能清單與狀態（只有 harness 能寫）")
for f in feats:
    mark = "PASS" if f["passes"] else ("GAVE-UP" if f.get("attempts", 0) >= harness.MAX_ATTEMPTS else "TODO")
    print("  {:<3} {:<7} 嘗試 {} 次｜{}".format(f["id"], mark, f.get("attempts", 0), f["description"][:60] + "…"))
print()
text = (wd / "progress.md").read_text(encoding="utf-8")
print("【2】progress.md：每個 session 的交接筆記（harness 追加，{} 字）".format(len(text)))
for block in text.split("\n## ")[1:]:
    head, _, body = block.partition("\n")
    first = next((l for l in body.splitlines() if l.strip() and not l.startswith("寫入：")), "")
    print("  ## " + head)
    if first:
        print("     " + first[:80] + ("…" if len(first) > 80 else ""))
print()
print("【3】git log --oneline：每通過一項就 commit 一次，可以回到任何一個存檔點")
log = subprocess.run(["git", "log", "--oneline"], cwd=wd, capture_output=True, text=True, encoding="utf-8")
lines = log.stdout.splitlines()
if len(lines) == 1 and "snapshot-4of4" in lines[0]:
    print("  " + lines[0][:90])
    print("  ↑ 這個 workdir 是從 snapshot-4of4 重建的（新電腦 clone 後沒有原本的 workdir），所以只有 1 個 commit。")
    print("    原本 harness 逐項 commit 的歷史存在 snapshot-4of4/git-log.txt：")
    lines = Path("snapshot-4of4/git-log.txt").read_text(encoding="utf-8").splitlines()
for line in lines:
    print("  " + line[:90])
print()
nxt = harness.pick_feature(feats)
print("harness 據此推算：下一個是 Session {}，要做的功能：{}".format(
    harness.next_session_no(wd), nxt["id"] if nxt else "沒有（全部完成，重跑也不會呼叫模型）"))
print()
print("CODE_PROMPT 裡帶給模型的段落：", [l for l in harness.CODE_PROMPT.splitlines() if l.startswith("=== ")])'
   show "$P"; ensure_wd; run "$P" ;;

4) banner "權限護欄：寫檔路徑、驗收指令白名單、不准改 tests/"
   tip "模型沒有任何工具，只能回 JSON。寫檔、跑測試都由 harness 代做，所以護欄全部寫在 harness 裡。先跑官方式的 --selftest，再逐項測給你看哪些會被擋。本步不呼叫模型。"
   CMD='PYTHONUTF8=1 python harness.py --selftest; echo "結束碼：$?（0＝全部規則都正常擋下）"'
   ensure_wd
   show "$CMD"; (cd "$S3" && eval "$CMD")
   echo
   P='from pathlib import Path
import harness
from harness import HarnessError

wd = harness.DEFAULT_WORKDIR
print("【表 1】safe_target：模型說要寫的檔案（寫程式代理，allow_tests=False）")
for rel in ["ledger.py", "src/util.py", "../harness.py", "C:/Windows/x.py", "/etc/passwd",
            ".git/config", "feature_list.json", "progress.md", "tests/test_f1.py"]:
    try:
        harness.safe_target(wd, rel, allow_tests=False)
        verdict = "放行"
    except HarnessError as exc:
        verdict = "擋下：" + str(exc).split("：")[0]
    print("  {:<20} {}".format(rel, verdict))
print()
print("【表 2】parse_test_command：驗收指令白名單（不經 shell，60 秒 timeout）")
for cmd in ["python -m unittest tests.test_f1", "python ledger.py", "python -m pip install requests",
            "python -c \"import os\"", "python -m unittest tests;rm", "bash -c ls", "python ../evil.py"]:
    try:
        harness.parse_test_command(cmd, wd)
        verdict = "放行"
    except HarnessError as exc:
        verdict = "擋下：" + str(exc).split("：")[0]
    print("  {:<36} {}".format(cmd, verdict))
print()
print("【其他護欄】")
print("  harness 專屬檔：", sorted(harness.HARNESS_OWNED), "→ 模型不能改清單、也不能自己標成通過")
print("  同一項最多嘗試：", harness.MAX_ATTEMPTS, "次，用完標成 GAVE-UP 並跳過（官方原版無限重試）")
print("  整次執行模型呼叫上限：--max-calls，預設 10（CallBudget）")
print("  清單原子寫入：save_features 先寫 feature_list.tmp，再 replace 改名；中斷也不會留下寫一半的清單")
src = Path("../shared/llm_agent.py").read_text(encoding="utf-8")
print("  claude -p 參數：", next(l.strip() for l in src.splitlines() if "\"--tools\"" in l))'
   show "$P"; run "$P" ;;

5) banner "實跑示範：從空的 workdir 跑 --max-sessions 2，看到初始化和 F1"
   tip "先把現在 4/4 完成的 workdir 改名成 workdir.bak-4of4 備份（不刪），再從空的 workdir 跑 2 個 session：Session 1 初始化代理切功能寫測試，Session 2 寫程式代理做 F1。會呼叫模型 2 次，約 1～2 分鐘。結束碼 0＝正常，1＝harness 停止（例如 claude -p 失敗），要照實說明。"
   if [ "$MODE" = "--dry-run" ]; then
     rm -rf "$DRYWD"
     P="$DRY_PY"'
code = harness.run(dry, 2, 2)
print()
print("乾跑結束碼：", code, "｜產出在 logs/dry-run-workdir（真正的 workdir 沒動）")'
     show "$P"; run "$P"
   else
     if [ -d "$BAK" ]; then
       if ! is_full "$BAK"; then warn "已有備份但不是全部完成（$(label_of "$BAK")），為了不弄丟成果先停下，請手動檢查 $BAK"; exit 1; fi
       printf '已有 4/4 完成的備份 workdir.bak-4of4；現在的 workdir（%s）是之前演練的產物，清掉重來。\n' "$(label_of "$WD")"
       rm -rf "$WD"
     elif [ -d "$WD" ]; then
       mv "$WD" "$BAK" || { warn "改名失敗（可能有檔案被其他程式開著），停止"; exit 1; }
       printf '%s已備份：workdir（%s）→ workdir.bak-4of4%s\n' "$G" "$(label_of "$BAK")" "$N"
     fi
     printf '現在 workdir 存在嗎？%s\n\n' "$([ -d "$WD" ] && echo 是 || echo 否，從零開始)"
     CMD='PYTHONUTF8=1 python harness.py --max-sessions 2 --max-calls 2; echo "結束碼：$?（0＝正常、1＝harness 停止）"'
     show "$CMD"; runcmd "$CMD"
   fi ;;

6) banner "示範中斷後續跑：同一條指令再跑一次，它從 Session 3 接著做"
   tip "上一步跑完 2 個 session 就停了，等於「被中斷」。現在什麼都不用改，同一條指令再跑一次：harness 讀 progress.md 數出下一個是 Session 3，讀清單挑出 F2。這一步最多再呼叫模型 2 次（F2、F3），F4 留著沒做，正好示範「下次再跑就會接著做 F4」。"
   if [ "$MODE" = "--dry-run" ]; then
     P="$DRY_PY"'
if not (dry / "feature_list.json").exists():
    print("logs/dry-run-workdir 還沒有清單，請先跑 bash s3.sh 5 --dry-run。")
    raise SystemExit(0)
print("續跑前：下一個 session 編號 =", harness.next_session_no(dry))
code = harness.run(dry, 2, 2)
print()
print("乾跑結束碼：", code, "｜產出在 logs/dry-run-workdir（真正的 workdir 沒動）")'
     show "$P"; run "$P"
   else
     if [ ! -d "$BAK" ]; then warn "還沒有 workdir.bak-4of4 備份，代表第 5 步還沒跑；先跑 bash s3.sh 5"; exit 1; fi
     printf '續跑前：workdir %s\n' "$(label_of "$WD")"
     if [ "$(progress_of "$WD")" = none ]; then warn "workdir 還沒有清單：第 5 步沒有成功，這次會從初始化重來（照實說明即可）"; fi
     echo
     CMD='PYTHONUTF8=1 python harness.py --max-sessions 2 --max-calls 2; echo "結束碼：$?（0＝正常、1＝harness 停止）"'
     show "$CMD"; (cd "$S3" && eval "$CMD")
     printf '\n%s還沒做完的部分：%s如果還有 TODO，下次再跑同一條指令就會接著做（本章模型預算 4 次到這裡用完，所以先停）。\n' "$B" "$N"
     done_step
   fi ;;

7) banner "跑代理寫出來的 ledger.py：用 sample.csv 實際算一次"
   tip "代理寫出的工具真的能用嗎？用 sample.csv（第 5 列是故意放的壞列）實際跑一次，並和 app_spec.md 的範例輸出逐行比對。剛剛演練的 workdir 若還沒做到 F4（命令列），就改用 4/4 完成的備份版。最後再跑全部驗收測試和「檔案不存在」的錯誤路徑。本步不呼叫模型。"
   P='import os, subprocess, sys
from pathlib import Path
import harness

drill, full = Path("workdir"), Path(os.environ["S3_BAK"])
def status(d):
    if not (d / "feature_list.json").exists():
        return "沒有功能清單"
    feats = harness.load_features(d)
    return "{}/{} 完成".format(sum(f["passes"] for f in feats), len(feats))
print("演練的 workdir：{}｜備份 workdir.bak-4of4：{}".format(status(drill), status(full) if full.exists() else "不存在"))
target = drill
if not ((drill / "feature_list.json").exists() and all(f["passes"] for f in harness.load_features(drill))):
    target = full if full.exists() else drill
print("這一步用：", target.as_posix())
print()
csv_path = Path("sample.csv").resolve()
print("=== sample.csv ===")
print(csv_path.read_text(encoding="utf-8").strip())
print()
env = dict(os.environ, PYTHONIOENCODING="utf-8")
p = subprocess.run([sys.executable, "ledger.py", str(csv_path)], cwd=target, capture_output=True, text=True, encoding="utf-8", env=env)
print("=== python ledger.py sample.csv（結束碼 {}） ===".format(p.returncode))
print("[stderr] " + p.stderr.strip())
print(p.stdout.rstrip())
print()
spec = Path("app_spec.md").read_text(encoding="utf-8").split("## 輸出")[1].split("```text")[1].split("```")[0].strip()
same = p.stdout.strip() == spec
print("和 app_spec.md 的範例輸出比對：", "完全一致" if same else "不一致，回頭看 progress.md 與測試")
print()
t = subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", "tests", "-t", "."], cwd=target,
                   capture_output=True, text=True, encoding="utf-8", env=env)
print("=== 全部驗收測試：python -m unittest discover（結束碼 {}） ===".format(t.returncode))
print("  " + (t.stderr.strip().splitlines() or ["（無輸出）"])[-1] + "｜" + next((l for l in t.stderr.splitlines() if l.startswith("Ran ")), ""))
m = subprocess.run([sys.executable, "ledger.py", "no-such.csv"], cwd=target, capture_output=True, text=True, encoding="utf-8", env=env)
print("=== 檔案不存在：python ledger.py no-such.csv（結束碼 {}，預期 1） ===".format(m.returncode))
print("  [stderr] " + m.stderr.strip() + ("（有 Traceback，不合規格）" if "Traceback" in m.stderr else "（沒有 Traceback，合規格）"))
if t.returncode != 0:
    print("驗收測試沒有全部通過，第 7 步回傳結束碼 1")
    raise SystemExit(1)'
   show "$P"; ensure_wd; run "$P"; exit "$RUN_RC" ;;

8) banner "三個靈魂拷問：先自己回答"
   tip "先不要看答案。對著 S3 想一想三題，各用一兩句話說出來；第 2 題特別想一下：這個 harness 設計成可以「沒人看著跑好幾個小時」，那它的權限該比有人看著時鬆還是嚴？想好之後說「繼續」，教練會執行 bash s3.sh 8b。"
   P='qs = [
    "1. 這個代理是給誰用的？（誰下指令、有沒有人在旁邊看著）",
    "2. 被賦予了哪些工具權限？（模型能做什麼、harness 代做什麼、刻意不給什麼）",
    "3. 資料和成果最後存在哪裡？（哪三個檔是記憶、哪些進版控、哪些不進）",
]
print("三個靈魂拷問：")
for q in qs:
    print("  " + q)
print()
print("提示：第 3 步的三個記憶檔、第 4 步被擋下的路徑與指令、第 5～6 步的 --max-calls 都是線索。")
print("想好後說「繼續」→ bash s3.sh 8b")'
   show "$P"; run "$P" ;;

8b) banner "三個靈魂拷問：範例答案＋「無人看著」為什麼要特別嚴格"
   tip "範例答案直接從 s3-long-running/README.md 的表格讀出來。重點在後半：長時間任務的賣點是沒人看著也能跑，但正因為沒人看著，出錯不會有人當場喊停，所以每一道護欄都要寫進程式，不能靠提示詞。最後把 workdir 還原成演練前 4/4 完成的備份。"
   P='import re
from pathlib import Path

readme = Path("README.md").read_text(encoding="utf-8")
rows = [line for line in readme.splitlines() if re.match(r"^[|] (這個代理|被賦予|資料和成果)", line)]
print("=== 範例答案（摘自 s3-long-running/README.md） ===")
for line in rows:
    cells = [c.strip() for c in line.strip("|").split("|")]
    q, a = cells[0], re.sub(r"<br/?>", " ", cells[1]).replace("**", "").replace(chr(96), "")
    print("■ " + q)
    print("  " + a)
    print()
if len(rows) != 3:
    print("（README 表格只讀到 {} 列，請直接打開 README 第 2 節看）".format(len(rows)))
print("=== 「無人看著」為什麼要特別嚴格 ===")
why = [
    ("出錯沒人喊停", "有人看著時，代理亂改檔你會當場按 Ctrl+C；無人值守時，錯誤會一路累積到早上",
     "全部通過就停、同一項最多試 2 次、--max-calls 上限"),
    ("額度會被燒光", "卡在同一個錯誤無限重試，一晚可以燒掉整個月的額度（官方原版沒有上限）",
     "CallBudget 呼叫上限；GAVE-UP 後跳過"),
    ("自我放水沒人抓", "沒人看測試，代理改測試、改清單就能「全部通過」",
     "tests/ 鎖住、清單只有 harness 能寫、passes 只看測試結束碼"),
    ("中斷後狀態壞掉", "半夜當機留下寫一半的清單，下次重跑會誤判成已初始化",
     "清單最後才寫、先寫暫存檔再改名"),
    ("提示詞不是護欄", "「請不要改測試」這種叮嚀，模型偶爾會不聽，沒人看就沒人發現",
     "規則寫在 safe_target、parse_test_command 這些程式碼裡"),
]
print("{:<12} | {:<52} | {}".format("風險", "為什麼無人看著更嚴重", "S3 的護欄"))
print("-" * 130)
for r in why:
    print("{:<12} | {:<52} | {}".format(*r))
print()
print("一句話：有人看著時，人是最後一道護欄；無人看著時，程式就是唯一的護欄，所以要比有人看著時更嚴。")'
   show "$P"; (cd "$S3" && PYTHONUTF8=1 python - <<PY
$P
PY
)
   echo
   printf '%s=== 還原 workdir ===%s\n' "$B" "$N"
   printf '演練的 workdir：%s｜備份 workdir.bak-4of4：%s\n' "$(label_of "$WD")" "$([ -d "$BAK" ] && label_of "$BAK" || echo 不存在)"
   if [ -d "$BAK" ] || [ -d "$DRYWD" ]; then
     ans=n
     if [ -t 0 ]; then printf '%s⌨  要現在把 workdir 還原成 4/4 完成的備份嗎？（演練產物會刪掉）[y/N] %s' "$Y" "$N"; read -r ans; fi
     case "$ans" in
       y|Y) restore ;;
       *) printf '先不還原。之後要還原，執行：bash %s restore\n' "$0" ;;
     esac
   else
     printf 'workdir 就是原本的版本，不需要還原。\n'
   fi
   done_step ;;

restore) STEP=8b; ensure_wd; restore ;;

*) echo "步驟要 1～8（第 8 步的後半是 8b）；還原 workdir 用 restore；新電腦從快照重建 workdir 用 seed" ;;
esac
