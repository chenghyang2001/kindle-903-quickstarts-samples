#!/bin/bash
# K903 範例 S5 互動演練：瀏覽器讀價代理——模型看頁面文字決定下一步，Playwright 真的去點，一次跑一步
# 用法：bash s5.sh <步驟 1-8>
# 呼叫模型：只有第 5 步會呼叫模型（price_agent.py 自己的 claude -p，實測 4 次、上限 8 次），其餘步驟全部離線
# 不設任何 API 金鑰；練習網站由程式自己開在 127.0.0.1 隨機埠，結束時關閉
set -u
STEP="${1:-1}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
S5="$ROOT/s5-browser-computer"
G=$'\e[32m'; Y=$'\e[33m'; C=$'\e[36m'; B=$'\e[1m'; N=$'\e[0m'

banner() { clear; printf '%s╔══════════════════════════════════════════════════════╗%s\n' "$C" "$N"; printf '%s  K903 範例 S5｜瀏覽器讀價代理　第 %s / 8 步%s\n' "$B" "$STEP" "$N"; printf '%s  %s%s\n' "$B" "$1" "$N"; printf '%s╚══════════════════════════════════════════════════════╝%s\n\n' "$C" "$N"; }
tip() { printf '%s💡 %s%s\n\n' "$Y" "$1" "$N"; }
show() { printf '%s▶ 要執行的程式：%s\n' "$G" "$N"; printf '%s' "$1" | sed "s/^/${G}  │ ${N}/"; printf '\n%s▶ 執行結果：%s\n' "$G" "$N"; }
done_step() { printf '\n%s👉 第 %s 步完成%s\n' "$C" "$STEP" "$N"; }
# 在 s5-browser-computer/ 底下跑一段 Python（PYTHONPATH 帶上 shared/，和 price_agent.py 一樣）
run() { (cd "$S5" && PYTHONUTF8=1 PYTHONPATH=".:$ROOT/shared" python - <<PY
$1
PY
); done_step; }
# 在 s5-browser-computer/ 底下跑一行 shell 指令
runcmd() { (cd "$S5" && eval "$1"); done_step; }
# 等學習者想一下；不是互動終端機（例如被其他程式呼叫）就直接往下
pause() { if [ -t 0 ]; then printf '%s⌨  %s%s' "$Y" "$1" "$N"; read -r _; echo; fi; }

if [ ! -d "$S5" ]; then echo "找不到範例資料夾：$S5"; exit 1; fi

case "$STEP" in
1) banner "這個範例對應官方第 4～8 章的哪些概念"
   tip "S5 是 K902 第 4～8 章（browser／computer use）的生活版：在本機練習網購網站找商品最低價。先把五章的重點，對到 S5 裡實際負責的檔案和函式。本步不呼叫模型。"
   P='from pathlib import Path

lessons = Path.home() / "workspace" / "kindle-902-claude-quickstarts" / "lessons"
rows = [
    ("4", "browser-toolset", "ch04-browser-toolset.md", "DOM 層工具：模型拿元素編號 ref_N，不拿座標", "browser_tools.py：read_page 替元素編號（data-agent-id），click／type 用編號"),
    ("4", "browser-toolset", "ch04-browser-toolset.md", "URL 政策：驅動程式執行前先檢查網址", "browser_tools.py：check_url 白名單，navigate 與 click 都先過它"),
    ("5", "browser-use-demo", "ch05-browser-use-demo.md", "看 → 想 → 做 的工具迴圈", "price_agent.py：agent_loop 每步 read_page → claude -p → run_action"),
    ("5", "browser-use-demo", "ch05-browser-use-demo.md", "工具錯誤回給模型自己修", "browser_tools.py：ToolError；run_action 把錯誤轉成文字寫進動作紀錄"),
    ("6", "computer-toolset", "ch06-computer-toolset.md", "截圖＋座標的 computer 工具", "本範例刻意不用：screenshot 只存檔給人看，不給模型（第 7 步細講）"),
    ("7", "computer-use-demo", "ch07-computer-use-demo.md", "容器裡的瀏覽器／桌面，人可以在旁邊看", "改用 Playwright 無頭 Chromium＋runs/ 截圖，不需要 Docker、VNC"),
    ("8", "computer-use-best-practices", "ch08-computer-use-best-practices.md", "步數上限、最小權限、不可逆動作要人確認", "MAX_STEPS = 8；只給 5 個工具；不給登入、付款、下單、連外網"),
]
print("{:<3} | {:<27} | {:<40} | {}".format("章", "官方專案", "官方概念", "在 S5 哪裡"))
print("-" * 130)
for ch, proj, _f, concept, where in rows:
    print("{:<3} | {:<27} | {:<40} | {}".format(ch, proj, concept, where))
print()
print("K902 講義是否在這台電腦：")
seen = set()
for _c, _p, f, _x, _y in rows:
    if f in seen:
        continue
    seen.add(f)
    p = lessons / f
    print("  {} ~/workspace/kindle-902-claude-quickstarts/lessons/{}".format("OK" if p.exists() else "缺", f))
print()
print("和官方的最大差別：模型走 claude -p（訂閱額度），每步回一個 JSON 動作字串，由程式自己解析；不是 API 原生 tool use。")'
   show "$P"; run "$P" ;;

2) banner "看練習網站：site/ 底下 5 個靜態頁"
   tip "代理只准逛這個本機練習網站。先列出 5 個檔案和標題，再離線把 GS-108 商品頁的四家報價讀出來，先知道正確答案是什麼，第 5 步才判斷得了模型有沒有答對。本步不呼叫模型。"
   P='import re
from pathlib import Path

site = Path("site")
print("{:<20} | {:>4} | {}".format("檔案", "行數", "標題"))
print("-" * 70)
for p in sorted(site.glob("*.html")):
    html = p.read_text(encoding="utf-8")
    m = re.search(r"<title>(.*?)</title>", html)
    print("{:<20} | {:>4} | {}".format(p.name, len(html.splitlines()), m.group(1) if m else "（無標題）"))
print()
print("流程：index.html 搜尋框 → results.html?q=...（前端 JavaScript 過濾清單）→ product-*.html 報價表")
print()
html = (site / "product-gs108.html").read_text(encoding="utf-8")
rows = re.findall(r"<tr><td>(.*?)</td><td>NT\$ (\d+)</td><td>(.*?)</td></tr>", html)
print("product-gs108.html 的報價表（離線解析）：")
print("{:<10} | {:>6} | {}".format("賣家", "價格", "運費"))
for seller, price, ship in rows:
    print("{:<10} | {:>6} | {}".format(seller, price, ship))
best = min(rows, key=lambda r: int(r[1]))
print()
print("正確答案：最低價是 {} 的 NT$ {}（{}）".format(best[0], best[1], best[2]))
print("要留意運費：阿德電腦標價 645，加運費 60 是 705；不論看標價或含運價，最低都是快樂3C 的 612。")
print()
print("想自己用瀏覽器逛：python -m http.server 8000 --bind 127.0.0.1 --directory site")'
   show "$P"; run "$P" ;;

3) banner "看 5 個瀏覽器工具與白名單（browser_tools.py）"
   tip "BrowserTools 有 navigate、read_page、click、type、screenshot 五個工具。重點有兩個：read_page 把頁面整理成文字加元素編號給模型；check_url 白名單，連 click 點連結前也會再檢查一次。本步只把原始碼當文字讀，不開瀏覽器、不呼叫模型。"
   P='from pathlib import Path

src = Path("browser_tools.py").read_text(encoding="utf-8").splitlines()
def line_of(text):
    for i, s in enumerate(src, 1):
        if text in s:
            return i
    return 0

tools = [
    ("navigate(url)", "def navigate", "先 check_url，再 page.goto，逾時 10 秒"),
    ("read_page()", "def read_page", "跑 MARK_ELEMENTS_JS 替 a/button/input/select/textarea 編號；可見文字截 1500 字"),
    ("click(element_id)", "def click", "用 data-agent-id 找元素；有 href 先過白名單再點"),
    ("type(element_id, text)", "def type", "用 fill 填入文字，逾時 5 秒"),
    ("screenshot(step)", "def screenshot", "存成 runs/<時間>/step-N.png，只給人看"),
]
print("【表 1】5 個工具")
print("{:<24} | {:>4} | {}".format("工具", "行號", "做什麼"))
print("-" * 100)
for name, key, desc in tools:
    print("{:<24} | {:>4} | {}".format(name, line_of(key), desc))
print()
print("【表 2】白名單在哪裡生效")
checks = [
    ("check_url 本體", "def check_url"),
    ("只允許 http/https 且 host:port 在清單", "parsed.scheme not in"),
    ("navigate 前檢查", "self.check_url(url)"),
    ("click 連結前檢查", "self.check_url(urljoin"),
    ("找不到編號時叫模型重新 read_page", "請重新 read_page"),
]
for desc, key in checks:
    n = line_of(key)
    print("  第 {:>3} 行｜{:<34}｜{}".format(n, desc, src[n - 1].strip() if n else "（找不到）"))
print()
print("白名單內容在 price_agent.py 的 main()：只放練習網站那一個 127.0.0.1:<隨機埠>。")
print("錯誤用 ToolError 丟出，run_action 轉成「錯誤：...」文字回給模型，讓它自己修正，不中斷迴圈。")'
   show "$P"; run "$P" ;;

4) banner "用 --check-allowlist 測白名單（真的開無頭 Chromium，不呼叫模型）"
   tip "先實跑 price_agent.py --check-allowlist：它會真的啟動練習網站和無頭 Chromium，試著前往 shopee.tw 和 file:///，兩個都要被擋。接著再離線多測幾種網址，看 check_url 的判斷規則。本步不呼叫模型。"
   CMD='PYTHONUTF8=1 python price_agent.py --check-allowlist; echo "結束碼：$?（0＝兩個都擋下）"'
   show "$CMD"; (cd "$S5" && eval "$CMD")
   echo
   P='from types import SimpleNamespace
from browser_tools import BrowserTools, ToolError

# 不開瀏覽器，只借用 check_url 的判斷規則
fake = SimpleNamespace(allowed_hosts={"127.0.0.1:50354"})
cases = [
    "http://127.0.0.1:50354/product-gs108.html",
    "http://127.0.0.1:8080/",
    "http://localhost:50354/",
    "https://shopee.tw/",
    "file:///C:/Windows/win.ini",
    "javascript:alert(1)",
]
print("{:<45} | {}".format("網址", "結果"))
print("-" * 70)
for url in cases:
    try:
        BrowserTools.check_url(fake, url)
        print("{:<45} | 放行".format(url))
    except ToolError:
        print("{:<45} | 擋下".format(url))
print()
print("規則很嚴：連同一台電腦的別的埠、localhost 這個別名都擋；只認練習網站那一個 host:port。")'
   show "$P"; run "$P" ;;

5) banner "實跑代理：看每一步模型選了什麼動作（本章唯一呼叫模型的一步）"
   tip "這一步會真的呼叫 claude -p，實測 4 次、約 20～30 秒，上限 8 次。每一步印出模型回的 JSON 動作和執行結果。模型每次可能走不同路線，例如先截圖或多讀一次頁面，只要最後答對 快樂3C NT\$ 612 就算成功。"
   CMD='PYTHONUTF8=1 python price_agent.py; echo "結束碼：$?（0＝有答案、2＝8 步內沒答案、1＝claude -p 失敗）"'
   show "$CMD"; runcmd "$CMD" ;;

6) banner "打開 runs/ 底下的截圖與 result.json"
   tip "找最新一次有 result.json 的執行資料夾，印出 result.json，再列截圖。截圖只給人事後對照，模型從頭到尾沒看過這些圖。會試著用 powershell Start-Process 開最後一張圖，失敗就只列檔名。本步不呼叫模型。"
   P='import json
import shutil
import subprocess
from pathlib import Path

runs = sorted((d for d in Path("runs").glob("*") if (d / "result.json").exists()), reverse=True)
if not runs:
    print("runs/ 底下還沒有 result.json，請先跑第 5 步。")
    raise SystemExit(0)
latest = runs[0]
print("最新的執行資料夾：", latest.as_posix(), "（共 {} 次有結果的執行）".format(len(runs)))
print()
result = json.loads((latest / "result.json").read_text(encoding="utf-8"))
print("result.json：")
print(json.dumps(result, ensure_ascii=False, indent=2))
final = result.get("final") or {}
ok = "快樂3C" in str(final.get("seller", "")) and "612" in str(final.get("price", ""))
print()
print("和第 2 步的正確答案比對：", "答對（快樂3C NT$ 612）" if ok else "沒答對，回頭看第 5 步每一步的動作")
print()
shots = sorted(latest.glob("step-*.png"), key=lambda p: int(p.stem.split("-")[1]))
print("截圖（第 N 步動作做完後的畫面）：")
for p in shots:
    print("  {}  {:>7,} bytes".format(p.name, p.stat().st_size))
if shots and shutil.which("powershell"):
    target = str(shots[-1].resolve())
    try:
        subprocess.run(["powershell", "-NoProfile", "-Command", "Start-Process -FilePath \"{}\"".format(target)],
                       check=True, timeout=20)
        print()
        print("已用預設看圖程式開啟：", shots[-1].name)
    except (subprocess.SubprocessError, OSError) as exc:
        print()
        print("開圖失敗（{}），請自己開：{}".format(type(exc).__name__, target))
elif shots:
    print()
    print("這台沒有 powershell，請自己開：", shots[-1].resolve())'
   show "$P"; run "$P" ;;

7) banner "browser toolset 和 computer use 差在哪；改成 computer use 要換哪些工具"
   tip "S5 是 browser toolset 那一種：模型看文字和元素編號。computer use 則是看截圖、給座標。先看對照表，再看要改成 computer use 時，5 個工具各要換成什麼。本步不呼叫模型。"
   P='diff = [
    ("模型看到什麼", "DOM 整理後的文字＋元素編號", "螢幕截圖（像素）"),
    ("怎麼指定目標", "元素編號（S5 是 data-agent-id）", "螢幕座標 (x, y)"),
    ("底層", "CDP；S5 用 Playwright", "VNC／作業系統滑鼠鍵盤"),
    ("優點", "便宜、準、不怕解析度", "什麼程式都能操作，不限瀏覽器"),
    ("缺點", "只能操作網頁", "要看圖、座標會點歪、比較慢"),
]
print("【表 1】對照")
print("{:<14} | {:<34} | {}".format("", "browser toolset（第 4～5 章）", "computer use（第 6～8 章）"))
print("-" * 95)
for r in diff:
    print("{:<14} | {:<34} | {}".format(*r))
print()
swap = [
    ("read_page()", "screenshot()，而且圖片要回傳給模型看", "模型改成看像素，不再有文字清單"),
    ("click(element_id)", "left_click(x, y)", "編號拿掉，改給座標"),
    ("type(element_id, text)", "left_click 搜尋框 → type(text)", "type 打進目前焦點，要先點一下"),
    ("（按搜尋鈕）", "key(\"Enter\")", "也可以按 Enter 送出"),
    ("（無）", "scroll、wait", "長頁面要捲、動態頁要等"),
    ("navigate(url)", "通常拿掉，改點網址列再打字", "白名單要改成在網路層擋（代理伺服器、防火牆）"),
    ("screenshot(step)", "同一個工具，但變成模型的眼睛", "S5 現在只存檔給人看"),
]
print("【表 2】改成 computer use 時工具怎麼換")
print("{:<24} | {:<38} | {}".format("S5 現在", "computer use", "說明"))
print("-" * 110)
for r in swap:
    print("{:<24} | {:<38} | {}".format(*r))
print()
print("卡關點：claude -p 這條路只能傳文字。要讓模型看圖，得把截圖存檔、在提示詞請 Claude Code 用 Read 工具讀圖，或改走官方 API。")'
   show "$P"; run "$P" ;;

8) banner "三個靈魂拷問：先自己答，再看範例答案"
   tip "每個範例都要回答三個問題。先自己想，按 Enter 才顯示 README 的範例答案。最後說明為什麼練習只准連本機網站。本步不呼叫模型。"
   Q1="這個代理是給誰用的？（有人看著，還是無人值守？）"
   Q2="被賦予了哪些工具權限？刻意不給哪些？最壞情況是什麼？"
   Q3="資料和成果最後存在哪裡？哪些進版控、哪些不進？"
   printf '%s1. %s%s\n' "$B" "$Q1" "$N"; pause "想好了按 Enter 看範例答案…"
   printf '%s   範例答案：%s只有使用者自己，在終端機看著它跑（有人即時看著）。學習用，不是無人值守的爬蟲。\n\n' "$G" "$N"
   printf '%s2. %s%s\n' "$B" "$Q2" "$N"; pause "想好了按 Enter 看範例答案…"
   printf '%s   範例答案：%s給 navigate（只限白名單裡的 127.0.0.1:<埠>）、read_page、click、type、screenshot（只寫進 runs/<時間>/）。\n' "$G" "$N"
   printf '   刻意不給：連外網、登入、付款、下單、送出個資、讀寫本機其他檔案、執行命令；點連結前也過白名單。\n'
   printf '   最壞情況：模型在練習網站上亂點，或回報錯的價格。\n\n'
   printf '%s3. %s%s\n' "$B" "$Q3" "$N"; pause "想好了按 Enter 看範例答案…"
   printf '%s   範例答案：%s練習網站在 site/（虛構商品，進版控）。截圖 step-N.png 與 result.json 存在 runs/<時間>/，\n' "$G" "$N"
   printf '   被 .gitignore 排除、不進版控，也不上傳任何地方。\n\n'
   printf '%s為什麼練習只准連本機網站？%s\n' "$B" "$N"
   printf '  1. 真實網站（像蝦皮）會擋自動化，跑不穩，還可能違反使用條款或被封鎖。\n'
   printf '  2. 頁面文字可能藏提示詞注入；本機虛構網站內容是自己寫的，可控。\n'
   printf '  3. 真實網站有登入、付款、下單這類不可逆動作，練習階段不該碰（第 8 章：不可逆動作要人確認）。\n'
   printf '  4. 答案固定（快樂3C NT$ 612），每次跑都能比對對錯；真實價格天天變，無法驗收。\n'
   printf '  5. 白名單只放一個 host:port，最壞情況被限制在「在練習網站亂點」。\n\n'
   printf '本範例的產出：%s\n' "$(ls -d "$S5"/runs/*/ 2>/dev/null | wc -l) 個 runs/ 執行資料夾（含 --check-allowlist 留下的空資料夾）"
   printf '整章模型呼叫：只有第 5 步 price_agent.py 自己的 claude -p（實測 4 次，上限 8 次）。\n'
   done_step ;;

*) echo "步驟要 1～8" ;;
esac
