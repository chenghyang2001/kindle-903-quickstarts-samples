#!/bin/bash
# K903 範例 S2 互動演練：AMR 產品問答網頁——知識庫檢索＋結構化 JSON＋轉真人，一次跑一步
# 用法：bash s2.sh <步驟 1-8>；第 8 步分兩半：bash s2.sh 8（先出題）→ bash s2.sh 8b（範例答案＋對比 S1）
# 呼叫模型：只有第 5、6 步各呼叫模型 1 次（共 2 次，claude -p，透過 server.py → shared/llm_agent.ask），其餘步驟全部離線
# 伺服器：第 4～7 步會在背景啟動 server.py（只綁 127.0.0.1），該步結束時由 trap 一定關掉，不會留殘留行程
# 可調環境變數：S2_PORT（預設 8903）、K902_CLI_MODEL、K902_CLI_TIMEOUT（都不是金鑰；不要設任何 API 金鑰）
set -u
STEP="${1:-1}"
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/../.."
S2="$REPO/s2-customer-web"
WORK="$S2/logs"   # 伺服器輸出與探測檔跟 server.py 自己的紀錄放一起：*/logs/ 已在 .gitignore
PORT="${S2_PORT:-8903}"
BASE="http://127.0.0.1:$PORT"
mkdir -p "$WORK"
G=$'\e[32m'; Y=$'\e[33m'; C=$'\e[36m'; B=$'\e[1m'; R=$'\e[31m'; N=$'\e[0m'

banner() { clear; printf '%s╔══════════════════════════════════════════════════════╗%s\n' "$C" "$N"; printf '%s  K903 範例 S2｜AMR 產品問答網頁　第 %s / 8 步%s\n' "$B" "${STEP%b}" "$N"; printf '%s  %s%s\n' "$B" "$1" "$N"; printf '%s╚══════════════════════════════════════════════════════╝%s\n\n' "$C" "$N"; }
tip() { printf '%s💡 %s%s\n\n' "$Y" "$1" "$N"; }
show() { printf '%s▶ 要執行的程式：%s\n' "$G" "$N"; printf '%s' "$1" | sed "s/^/${G}  │ ${N}/"; printf '\n%s▶ 執行結果：%s\n' "$G" "$N"; }
done_step() { printf '\n%s👉 第 %s 步完成%s\n' "$C" "$STEP" "$N"; }
# 在 s2-customer-web 底下跑 Python，才能直接 import server（server.py 自己會把 shared/ 加進 sys.path）
run() { (cd "$S2" && S2_BASE="$BASE" S2_WORK="$WORK" PYTHONUTF8=1 PYTHONPATH=. python - <<PY
$1
PY
); done_step; }

# ---------- 背景伺服器：啟動、等就緒、一定關掉 ----------
SERVER_PID=""
stop_server() {
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null
    wait "$SERVER_PID" 2>/dev/null
    printf '%s🛑 伺服器已關閉（PID %s）%s\n' "$C" "$SERVER_PID" "$N"
  fi
  SERVER_PID=""
}
trap stop_server EXIT
trap 'exit 130' INT TERM   # Ctrl+C 時改走 exit，讓 EXIT trap 一樣會關伺服器

# mingw curl 寫 /dev/null 會回錯誤碼 23，所以改看 HTTP 狀態碼：000 代表沒有程式在聽
port_busy() { [ "$(curl -s -o "$WORK/.probe" -w '%{http_code}' --max-time 2 "$BASE/" 2>/dev/null)" != "000" ]; }

start_server() {
  if port_busy; then
    printf '%s埠 %s 已經有程式在用（可能是別處沒關的 server.py）。請先關掉它，或改用 S2_PORT=8913 bash s2.sh %s%s\n' "$R" "$PORT" "$STEP" "$N"
    exit 1
  fi
  (cd "$S2" && PYTHONUTF8=1 exec python server.py --port "$PORT") > "$WORK/practice-server.log" 2>&1 &
  SERVER_PID=$!
  for _ in $(seq 1 30); do
    if port_busy; then
      printf '%s🚀 背景伺服器就緒：%s（PID %s，輸出寫在 %s）%s\n\n' "$C" "$BASE" "$SERVER_PID" "s2-customer-web/logs/practice-server.log" "$N"
      return 0
    fi
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then break; fi
    sleep 0.5
  done
  printf '%s伺服器啟動失敗，最後幾行輸出：%s\n' "$R" "$N"; tail -n 5 "$WORK/practice-server.log"
  exit 1
}

# 第 5、6 步共用的 Python 片段：送一題、印回覆、印這題在 logs/ 留下的那一筆紀錄
ASK_PY='import json, os, urllib.request, urllib.error
from datetime import datetime
from pathlib import Path
BASE = os.environ["S2_BASE"]
NO_PROXY = urllib.request.build_opener(urllib.request.ProxyHandler({}))

def post(question):
    data = json.dumps({"question": question}, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(BASE + "/api/ask", data=data, headers={"Content-Type": "application/json"})
    try:
        with NO_PROXY.open(req, timeout=240) as res:
            return res.status, json.loads(res.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        return exc.code, json.loads(exc.read().decode("utf-8"))

def last_log():
    path = Path("logs") / "{:%Y-%m-%d}.jsonl".format(datetime.now())
    lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
    return json.loads(lines[-1]) if lines else None

def ask_and_show(question):
    print("客戶問題：", question)
    try:
        status, body = post(question)
    except (OSError, ValueError) as exc:
        print("送出失敗：", exc)
        return None
    print("HTTP", status)
    for key in ("answer", "sources", "confidence", "needs_human"):
        print("  {:<12} {}".format(key, json.dumps(body.get(key), ensure_ascii=False)))
    log = last_log()
    if log and log.get("question") == question:
        print()
        print("logs/ 裡這一筆：檢索到", log["retrieved"], "；error =", json.dumps(log["error"], ensure_ascii=False), "；耗時", log["seconds"], "秒")
        if log["error"]:
            print("  error 不是 null：代表模型回覆不合格或呼叫失敗，伺服器改回安全預設（轉真人）")
    return body
'

case "$STEP" in
1) banner "這個範例模仿官方第 1 章的什麼"
   tip "官方 customer-support-agent 的核心是「先檢索、再請模型回固定格式的 JSON、驗證後才給畫面」。S2 把 Next.js 和 Bedrock 全換成 Python 標準庫，但這條骨架原封不動。這一步全部離線。"
   P='from pathlib import Path
import server

print("【表 1】官方第 1 章 vs 本範例 S2")
rows = [
    ("檢索", "Amazon Bedrock 知識庫（向量，取 3 段）", "kb/ 5 份 md，字元重疊評分，取前 {} 份".format(server.TOP_K)),
    ("模型呼叫", "@anthropic-ai/sdk ＋ API key", "claude -p（訂閱額度，不設金鑰）"),
    ("回覆契約", "zod 驗證 7 個欄位", "手寫 validate_reply 驗 4 個欄位"),
    ("轉真人", "redirect_to_agent，前端發事件", "needs_human，網頁顯示標籤"),
    ("網頁", "Next.js ＋ shadcn/ui", "http.server ＋ 一頁 HTML"),
]
print("{:<8} | {:<34} | {}".format("項目", "官方原版", "S2"))
print("-" * 92)
for r in rows:
    print("{:<8} | {:<34} | {}".format(*r))
print()
print("【表 2】S2 的檔案")
for rel in ("server.py", "static/index.html", "smoke_test.py", "README.md"):
    print("  {:<20} {:>4} 行".format(rel, len(Path(rel).read_text(encoding="utf-8").splitlines())))
print("  kb/                 ", len(list(Path("kb").glob("*.md"))), "份虛構知識庫")
print()
print("【表 3】一次請求的流程（server.py 裡的函式）")
flow = [
    ("parse_question", "空字串、超過 {} 字、壞 JSON → 400，不呼叫模型".format(server.MAX_QUESTION_CHARS)),
    ("retrieve", "算問題和每份文件的重疊分數，取前 {} 份".format(server.TOP_K)),
    ("build_prompt", "<docs>文件全文</docs> ＋ 客戶問題"),
    ("ask", "claude -p 一次，沒有任何工具、沒有工具迴圈"),
    ("validate_reply", "驗 4 個欄位；失敗就回 SAFE_FALLBACK（轉真人）"),
    ("write_log", "logs/日期.jsonl 追加一行"),
]
for i, (fn, desc) in enumerate(flow, 1):
    print("  {}. {:<15} {}".format(i, fn, desc))
print()
print("只綁", server.HOST, "埠", server.DEFAULT_PORT, "：這是本機示範，不對區網開放")'
   show "$P"; run "$P" ;;
2) banner "看知識庫與檢索評分"
   tip "中文沒有空白，程式把問題切成「相鄰兩個字」一組（bigram），數有幾組出現在文件裡。分數同分時照檔名順序，只取前 2 份。"
   P='import server

docs = server.load_kb()
print("【知識庫】")
for name, body in docs.items():
    print("  {:<24} {:>4} 字　{}".format(name, len(body), body.splitlines()[0].lstrip("# ")))
print()
q0 = "DR-800 充電要多久？"
print("分詞範例：", q0, "→", sorted(server.tokenize(q0)))
print()
QS = [
    ("一般問題", "DR-800 最大載重多少？充電到九成要多久？"),
    ("一題問三件事", "需要貼磁條嗎？用什麼導航？保固幾年？"),
    ("跟產品無關但字面相近", "你們公司有賣掃地機器人嗎？"),
    ("完全無關", "可以幫我訂高鐵票嗎？"),
]
names = list(docs)
short = [n[:2] for n in names]
for label, q in QS:
    qt = server.tokenize(q)
    scores = [len(qt & server.tokenize(docs[n] + " " + n)) for n in names]
    picked = [n for n, _ in server.retrieve(q, docs)]
    print("【{}】{}".format(label, q))
    print("  各文件分數：", "  ".join("{}={}".format(s, v) for s, v in zip(short, scores)))
    print("  取前 {} 份：".format(server.TOP_K), picked if picked else "（沒有任何文件，模型只會看到「沒有找到相關文件」）")
    if "保固" in q:
        print("  ⚠ 04-warranty-service.md 只有 1 分，跟 03 同分卻排在後面，被擠出前 2 名 → 模型看不到保固文件，只能答「查不到、轉真人」")
    if "掃地" in q:
        print("  ⚠ 「機器人」「公司」讓它拿到分數：檢索只會找字，判斷「這題該不該答」還是要靠模型照規則")
    print()'
   show "$P"; run "$P" ;;
3) banner "JSON 回覆格式與驗證：為什麼要擋掉模型自己編的 sources"
   tip "sources 會直接秀給客戶看，像是「這句話出自哪份正式文件」。模型編出一個不存在的檔名，客戶就會相信一份根本沒有的文件。這一步用假回覆離線測，不呼叫模型。"
   P='import server
from llm_agent import extract_json

print("系統提示要求的格式：")
print("  " + [l for l in server.SYSTEM_PROMPT.splitlines() if l.startswith("{")][0])
print()
allowed = {"01-product-specs.md", "03-charging-battery.md"}
print("這次真的有給模型看的文件：", sorted(allowed))
print()
cases = [
    ("合格，但多編了一個來源", "{\"answer\": \"DR-800 載重 800 公斤。\", \"sources\": [\"01-product-specs.md\", \"內部價格表-機密.md\"], \"confidence\": \"high\", \"needs_human\": false}"),
    ("包在程式碼區塊裡", "好的，回覆如下：\n```json\n{\"answer\": \"約 1.5 小時\", \"sources\": [\"03-charging-battery.md\"], \"confidence\": \"medium\", \"needs_human\": false}\n```"),
    ("confidence 亂填", "{\"answer\": \"可以\", \"sources\": [], \"confidence\": \"超高\", \"needs_human\": false}"),
    ("needs_human 寫成字串", "{\"answer\": \"可以\", \"sources\": [], \"confidence\": \"low\", \"needs_human\": \"否\"}"),
    ("根本不是 JSON", "抱歉，我覺得您應該直接打電話問業務。"),
]
for label, text in cases:
    print("【{}】".format(label))
    try:
        reply = server.validate_reply(extract_json(text), allowed)
        print("  通過 → sources 變成", reply["sources"], "；needs_human =", reply["needs_human"])
    except ValueError as exc:
        print("  不通過：", str(exc)[:60])
        print("  → 網頁拿到 SAFE_FALLBACK：", server.SAFE_FALLBACK["answer"])
    print()
print("重點：")
print("  1. sources 只留「程式真的有給模型看」的檔名，編的「內部價格表-機密.md」被刪掉")
print("  2. 任何一個欄位不合格，整個回覆作廢、改轉真人；寧可少答，也不讓壞回覆上畫面")'
   show "$P"; run "$P" ;;
4) banner "離線自我檢查，再把伺服器啟動在背景"
   tip "先跑 --selftest（不呼叫模型），再用 & 把 server.py 放到背景、輪詢到它能回應。本步結束時 trap 會自動把它關掉，你會看到「伺服器已關閉」。"
   P='PYTHONUTF8=1 python server.py --selftest
(cd s2-customer-web && PYTHONUTF8=1 exec python server.py --port 8903) > logs/practice-server.log 2>&1 &
SERVER_PID=$!
trap stop_server EXIT          # 不管成功、失敗、Ctrl+C，離開時一定 kill
curl -s http://127.0.0.1:8903/ | grep "<title>"
curl -s -X POST http://127.0.0.1:8903/nothing'
   show "$P"
   (cd "$S2" && PYTHONUTF8=1 python server.py --selftest) || { printf '%sselftest 失敗%s\n' "$R" "$N"; exit 1; }
   echo
   start_server
   printf '首頁標題：'; curl -s --max-time 5 "$BASE/" | grep -o '<title>[^<]*</title>'
   printf '不存在的路徑：'; curl -s --max-time 5 -X POST "$BASE/nothing"; echo
   printf '伺服器自己的啟動訊息：'; head -n 1 "$WORK/practice-server.log"
   echo
   tip "伺服器只聽 127.0.0.1：同一個區網的別台電腦連不到。這是故意的，因為它背後是個人訂閱的 claude -p。"
   stop_server
   if port_busy; then printf '%s⚠ 埠 %s 還有回應，請檢查殘留行程%s\n' "$R" "$PORT" "$N"; else printf '確認：埠 %s 已經沒有回應\n' "$PORT"; fi
   done_step ;;
5) banner "問一題知識庫內的問題（呼叫模型 1 次）"
   tip "這一步會呼叫模型 1 次（claude -p），通常 5～10 秒，最多等 4 分鐘。答案每次措辭可能不同，看的是 sources、confidence、needs_human 三個欄位。"
   start_server
   P="$ASK_PY"'
ask_and_show("DR-800 最大載重多少？充電到九成要多久？")
print()
print("看點：sources 應該只出現檢索到的檔名；needs_human 應該是 false")'
   show 'ask_and_show("DR-800 最大載重多少？充電到九成要多久？")   # POST /api/ask，細節見 s2.sh 的 ASK_PY'
   run "$P" ;;
6) banner "問一題知識庫外的問題：needs_human=true（呼叫模型 1 次）"
   tip "這一步會呼叫模型 1 次。這題一份文件都檢索不到，模型照系統提示第 2 條規則回「轉真人」。看 logs/ 的 error 是 null，才能證明是模型判斷的，不是解析失敗走預設。"
   start_server
   P="$ASK_PY"'
body = ask_and_show("可以幫我訂高鐵票嗎？")
print()
if body is not None:
    print("needs_human =", body.get("needs_human"), "→", "轉真人 ✔" if body.get("needs_human") is True else "沒有轉真人，記下來，這是模型沒照規則")'
   show 'ask_and_show("可以幫我訂高鐵票嗎？")   # POST /api/ask，細節見 s2.sh 的 ASK_PY'
   run "$P" ;;
7) banner "壞輸入回 400，以及網頁怎麼防 XSS（不呼叫模型）"
   tip "壞輸入在 parse_question 就擋掉，根本不會花到模型額度；我們用 logs/ 的行數證明這一點。XSS 的防法在網頁端：所有文字都用 textContent，不用 innerHTML。"
   start_server
   LOG="$S2/logs/$(date +%Y-%m-%d).jsonl"
   before=$( [ -f "$LOG" ] && wc -l < "$LOG" || echo 0 )
   P="curl -s -w '  [HTTP %{http_code}]' -X POST $BASE/api/ask -H 'Content-Type: application/json' -d '{\"question\": \"   \"}'"
   show "$P"
   printf '空白字串：'; curl -s --max-time 10 -w '  [HTTP %{http_code}]\n' -X POST "$BASE/api/ask" -H 'Content-Type: application/json' -d '{"question": "   "}'
   printf '不是 JSON：'; curl -s --max-time 10 -w '  [HTTP %{http_code}]\n' -X POST "$BASE/api/ask" -H 'Content-Type: application/json' -d 'hello'
   LONG=$(printf 'x%.0s' $(seq 1 501))
   printf '501 個字：'; curl -s --max-time 10 -w '  [HTTP %{http_code}]\n' -X POST "$BASE/api/ask" -H 'Content-Type: application/json' -d "{\"question\": \"$LONG\"}"
   printf '沒有內容：'; curl -s --max-time 10 -w '  [HTTP %{http_code}]\n' -X POST "$BASE/api/ask" -H 'Content-Type: application/json' -H 'Content-Length: 0'
   after=$( [ -f "$LOG" ] && wc -l < "$LOG" || echo 0 )
   printf '\nlogs/ 行數：前 %s 行、後 %s 行 → %s\n\n' "$before" "$after" "$( [ "$before" = "$after" ] && echo '沒有新增，代表模型一次都沒被呼叫' || echo '有新增，請檢查')"
   printf '%s▶ 網頁怎麼顯示文字（static/index.html）：%s\n' "$G" "$N"
   grep -n 'textContent\|innerHTML' "$S2/static/index.html" | sed "s/^/${G}  │ ${N}/"
   echo
   echo '如果用 innerHTML：客戶輸入 <img src=x onerror=alert(1)>，或模型被誘導回一段 HTML，'
   echo '瀏覽器就會把它當程式執行。textContent 只把它當純文字顯示，所以不怕。'
   echo '使用者輸入和模型回覆，兩邊都要當「不可信的文字」。'
   stop_server
   done_step ;;
8) banner "三個靈魂拷問：先自己答"
   tip "先不要看答案。S2 跟 S1 一樣是「模型＋程式」的代理，差別只在使用者換人了。"
   printf '%s請先在心裡（或紙上）回答 S2 的三題：%s\n' "$B" "$N"
   echo '  1. 這個代理是做給誰用的？'
   echo '  2. 它被賦予了哪些工具的權限？'
   echo '  3. 它的資料和成果最後存在哪裡？'
   echo
   echo '提示：想想對方會不會故意亂問？模型自己能讀檔嗎？客戶的問題存在哪、誰看得到？'
   printf '\n%s想好了，執行 bash s2.sh 8b 看範例答案和 S1 對比%s\n' "$C" "$N" ;;
8b) banner "三個靈魂拷問：範例答案，以及跟 S1 的對比"
   tip "同樣是「模型＋程式」的代理，S1 給自己用、S2 給客戶用。只換了第 1 題的答案，第 2、3 題就跟著全變了。"
   P='rows = [
    ("1. 給誰用",
     "使用者自己，在終端機一個人用",
     "外部客戶，用瀏覽器問；可能亂問、誘導、同時很多人"),
    ("2. 工具權限",
     "模型可叫 list_dir／read_file／search_text，限定一個資料夾、唯讀",
     "模型沒有任何工具；程式替它讀 kb/；議價、客訴、退貨一律轉真人"),
    ("3. 資料存哪",
     "答案印終端機；runs/ 留迴圈紀錄，不存讀到的全文",
     "logs/ 存每筆客戶問題（可能含個資），要訂保存期限、限制誰能讀"),
    ("→ 用什麼呼叫",
     "claude -p（自己用、量小）",
     "示範可用 claude -p；正式上線必須換公司 API key，加速率限制與身分驗證"),
]
print("{:<12} | {:<44} | {}".format("", "S1 本機資料夾小管家", "S2 AMR 產品問答網頁"))
print("-" * 120)
for r in rows:
    print("{:<12} | {:<44} | {}".format(*r))
print()
print("為什麼「給客戶用」讓三題全變：")
print("  第 1 題：使用者從「可信任的自己」變成「不認識的陌生人」，要假設對方會試探。")
print("  第 2 題：所以權限縮到最小，連讀檔都不讓模型自己做；做不到的事交給真人。")
print("  第 3 題：紀錄裡出現的是「別人的」資料，保存、權限、個資都要管。")
print("  最後連付費方式都變了：個人訂閱給客戶用違反使用方式、額度會被吃光、也沒有穩定保證。")
print()
print("本章用到的模型呼叫：第 5、6 步各 1 次，共 2 次；伺服器每一步結束都已關閉。")'
   show "$P"; run "$P" ;;
*) echo "步驟要 1～8 或 8b" ;;
esac
