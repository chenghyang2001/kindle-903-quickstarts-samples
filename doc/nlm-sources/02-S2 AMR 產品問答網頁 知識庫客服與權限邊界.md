# S2 AMR 產品問答網頁 知識庫客服與權限邊界

> K903《Claude Quickstarts 範例實作》第 2 段，共 5 段。對應官方 claude-quickstarts（K902）第 1 章 customer-support-agent。
> 書號 9 開頭為自製教材，沒有原書；模型一律走 claude -p 轉接層，不設 API 金鑰。

## 導讀

S2 第一次把「別人」帶進來：一個給外部客戶用的 AMR 產品問答網頁。程式把 kb/ 的五份 markdown 交給模型，模型只能根據知識庫回答，議價、客訴、退貨一律交給真人。這一段要學會：給客戶用的代理，權限邊界要畫在哪裡、紀錄可能含個資要怎麼存，以及為什麼正式上線必須改用公司的 API key，而不能用個人訂閱的 claude -p。

每個範例學完都要回答三個靈魂拷問：這個代理是做給誰用的？它被賦予了哪些工具的權限？它的資料和成果最後存在哪裡？

## 範例說明（README）

### 1. 模仿哪一章

模仿官方 `claude-quickstarts` 第 1 章 **customer-support-agent**（K902 講義：`~/workspace/kindle-902-claude-quickstarts/lessons/ch01-customer-support-agent.md`）。

一句話：虛構公司「示範機器人股份有限公司」的客服網頁，客戶在瀏覽器問 AMR 產品問題，程式先從知識庫找出最相關的 2 份文件，再請模型只根據這些文件回一個固定格式的 JSON，查不到就轉真人客服。

跟官方一樣，重點在「回覆契約」：模型每次都必須回 `{"answer", "sources", "confidence", "needs_human"}` 四個欄位，程式驗證通過才給網頁，驗證失敗就回安全的預設答案。

![網頁截圖](docs/screenshot.png)

### 2. 三個靈魂拷問

| 題目 | 這個範例的答案 |
| --- | --- |
| 給誰用？ | **外部客戶**（想買 AMR 的工廠、倉儲人員）。這是 S1 之後第一次出現「別人」當使用者：對方可能亂問、可能故意誘導模型說出文件以外的內容、可能同時很多人在用。**所以本範例只能在自己電腦 127.0.0.1 示範。正式給客戶用時，不可以用個人 Max 訂閱加 `claude -p`**：那違反個人訂閱的使用方式，額度會被客戶吃光，也沒有穩定性保證。正式上線要改用公司的 API key，並加上速率限制與身分驗證（見第 6 節）。 |
| 被賦予哪些工具權限？ | **可以做的**：讀 `kb/` 裡的 5 份 markdown（由程式讀，不是模型讀），回一段文字。**刻意不給的**：模型沒有任何工具（`claude -p --tools ""`），不能讀檔、不能上網、不能執行指令；不能查訂單或客戶資料；不能下單、改價、承諾折扣；不能寄信。來源欄位也只保留程式真的有給它看的檔名，模型編出來的檔名會被刪掉。遇到議價、客訴、退貨，一律 `needs_human=true` 交給真人。 |
| 資料和成果存在哪？ | 知識庫：`kb/*.md`（進 git）。每次問答：`logs/YYYY-MM-DD.jsonl` 一行一筆，含問題、檢索到的文件與分數、回覆、錯誤原因、耗時（`logs/` 已在 `.gitignore`，不推上 GitHub）。**客戶的問題可能含公司名稱、聯絡方式等個資**，正式上線要訂保存期限並限制誰能讀紀錄。模型這端：`claude -p` 加了 `--no-session-persistence`，不在本機留 session 紀錄。 |

### 3. 架構與資料流

```text
瀏覽器 static/index.html
  │  POST /api/ask {"question": "..."}
  ▼
server.py（http.server，只綁 127.0.0.1:8903）
  │ ① parse_question：空字串或超過 500 字 → 400（不呼叫模型）
  │ ② retrieve：中文兩字一組（bigram）＋英數詞，算和每份 kb 文件的重疊數，取前 2 份
  │ ③ build_prompt：<docs>文件全文</docs> + 客戶問題
  ▼
shared/llm_agent.ask() ──► claude -p（系統提示走檔案、問題走 stdin、無任何工具）
  │ ④ extract_json + validate_reply：四個欄位型別檢查、來源只留真的檢索到的
  │    失敗 → SAFE_FALLBACK（轉真人）
  │ ⑤ write_log：logs/YYYY-MM-DD.jsonl
  ▼
回 JSON → 前端用 textContent 顯示答案、來源、信心、「已轉真人客服」標籤
```

對照官方：官方用 Amazon Bedrock Knowledge Bases 做檢索、Next.js 做網頁；這裡全部換成 Python 標準庫，一支 `server.py` 加一頁 HTML。

### 4. 怎麼跑（Git Bash）

```bash
cd ~/workspace/kindle-903-quickstarts-samples/s2-customer-web

# 離線自我檢查（不呼叫模型）
PYTHONUTF8=1 python server.py --selftest

# 啟動網頁，瀏覽器開 http://127.0.0.1:8903 ，Ctrl+C 結束
PYTHONUTF8=1 python server.py

# 冒煙測試：自動在背景啟動伺服器、打 3 題、測完關掉（呼叫模型 2 次）
PYTHONUTF8=1 python smoke_test.py
```

前提：已安裝並登入 Claude Code（`claude` 在 PATH 中）。**不要**設定 `ANTHROPIC_API_KEY`。要換模型可設 `K902_CLI_MODEL=haiku`。

### 5. 實際跑出來的結果

2026-11-25 冒煙測試真實輸出（完整版在 `docs/smoke-output.txt`）：

```text
S2 問答網頁啟動：http://127.0.0.1:8903（知識庫 5 份，Ctrl+C 結束）
[PASS] 知識庫內（4.2 秒）HTTP 200
       {"answer": "DR-800 最大載重為 800 公斤。充電時間方面，從 10% 充到 90% 約需 1.5 小時。另外，DR-800 支援自動充電，電量低於設定值（預設 20%）時會自行回到充電樁充電。", "sources": ["01-product-specs.md", "03-charging-battery.md"], "confidence": "high", "needs_human": false}
[PASS] 知識庫外（3.6 秒）HTTP 200
       {"answer": "這個問題我無法從產品資料確認，已為您轉真人客服。", "sources": [], "confidence": "low", "needs_human": true}
[PASS] 空字串（0.0 秒）HTTP 400
       {"error": "question 不可為空"}
結果：全部通過（模型呼叫 2 次）
```

`logs/` 裡兩筆紀錄的 `error` 都是 `null`，代表「知識庫外」那題的轉真人是模型照規則判斷的，不是解析失敗走預設回覆。

網頁截圖（上方圖片）是用 Playwright 開本機 Chrome 實際送出一題「需要貼磁條嗎？用什麼導航？保固幾年？」拍的（第 3 次模型呼叫）。這題剛好示範了一個限制：問題一次問三件事，檢索只取前 2 份，保固文件沒被選進去，所以模型答了導航、保固那部分老實說查不到並轉真人。

### 6. 跟官方原版差在哪，正式上線要改什麼

| 項目 | 官方原版 | 本範例 | 正式上線要改成 |
| --- | --- | --- | --- |
| 模型呼叫 | `@anthropic-ai/sdk`，要 `ANTHROPIC_API_KEY` | `claude -p`（個人 Max 訂閱） | **公司的 API key**（放環境變數或密鑰管理服務），不可用個人訂閱 |
| 檢索 | Amazon Bedrock Knowledge Bases（向量檢索，n=3） | 標準庫字元重疊評分，取前 2 份 | 文件一多就換向量檢索或混合檢索，並切成段落而不是整份文件 |
| 網頁 | Next.js＋shadcn/ui，左右側欄顯示思考與來源 | `http.server`＋一頁 HTML | 正式網頁框架，放在 HTTPS 反向代理後面 |
| 回覆欄位 | `response`、`thinking`、`user_mood`、`suggested_questions`、`redirect_to_agent` 等 | 只留 4 個欄位 | 依客服流程增加（例如情緒、分類） |
| JSON 驗證 | zod schema | 手寫 `validate_reply` | 用 schema 函式庫，或 API 的結構化輸出功能 |
| 轉真人 | 前端發事件 | 只顯示標籤 | 真的接客服工單或即時客服系統 |
| 防濫用 | 原型，未處理 | 只綁本機、限 500 字、限 8 KB 請求 | **速率限制**（每 IP／每帳號）、**身分驗證**、提示詞注入防護、紀錄保存期限與個資遮罩、費用上限告警 |

### 7. 模仿指南：改成自己的需求，改這 3 個地方

1. **`kb/` 換成你的文件**：每份一個主題、檔名有意義（來源欄位會直接顯示檔名）。例如改成「社區管委會 FAQ」或「公司 IT 報修說明」。
2. **`server.py` 的 `SYSTEM_PROMPT`**：改公司名稱、角色、什麼情況要轉真人（例如「涉及金額退款一律轉真人」）、回答字數。JSON 欄位若要增減，`validate_reply` 跟著改。
3. **`server.py` 的 `retrieve` 與 `TOP_K`**：文件多、問題常一次問好幾件事時，把 `TOP_K` 調大，或把文件切成小段再評分；`static/index.html` 的標題與「試試看」按鈕也順手改掉。

### 檔案清單

| 路徑 | 用途 |
| --- | --- |
| `server.py` | 伺服器：檢索、呼叫模型、驗證 JSON、寫紀錄；`--selftest` 離線檢查 |
| `static/index.html` | 聊天網頁（textContent 顯示，防 XSS） |
| `smoke_test.py` | 冒煙測試：背景啟動、3 個案例、一定關閉伺服器 |
| `kb/01～05-*.md` | 虛構知識庫：產品規格、導航與 SLAM、充電與電池、保固與維修、報價流程 |
| `docs/screenshot.png` | 網頁實際畫面 |
| `docs/smoke-output.txt` | 冒煙測試完整輸出 |
| `logs/` | 執行時產生的 JSONL 紀錄（不進 git） |

## 逐步演練教練稿（8 步）

K903 範例 S2 互動演練：AMR 產品問答網頁，知識庫檢索加結構化 JSON 回覆，查不到就轉真人（教練稿）

【第 1 步：這個範例模仿官方第 1 章的什麼】
S2 模仿的是官方第一章的客服代理。官方用雲端知識庫做檢索、用網頁框架做畫面，這裡全部換成 Python 標準庫，一支伺服器程式加一頁網頁。但骨架完全一樣：先從知識庫找文件，再請模型照固定格式回一個 JSON，程式驗證通過才給畫面看。畫面會列出官方和 S2 的對照表、S2 的檔案，還有一次請求會經過的六個函式。整條路上只有一次模型呼叫，模型沒有任何工具，也沒有工具迴圈。目的，是先認出這個範例到底模仿了官方的哪一段。

【第 2 步：看知識庫和檢索評分】
第二步看知識庫和檢索。知識庫是五份虛構的產品文件。因為中文沒有空格，程式把問題切成相鄰兩個字一組，數有幾組出現在每份文件裡，分數最高的前兩份才交給模型。請注意第二題，一題同時問磁條、導航和保固三件事：保固文件只拿到一分，跟充電文件同分，卻因為排在後面被擠出前兩名，模型根本看不到保固資料。另外，掃地機器人這種無關問題，也會因為機器人、公司這些字拿到分數。目的，是看懂檢索只會找字，它的限制會直接變成答案的限制。

【第 3 步：JSON 回覆格式和驗證】
第三步看回覆契約。模型每次都必須回答案、來源、信心和要不要轉真人四個欄位。我們不呼叫模型，直接餵五個假回覆給驗證函式。第一個回覆多編了一份叫內部價格表的來源，驗證後被刪掉，只留下真的有給模型看的檔名。為什麼要擋？因為來源會直接秀給客戶看，客戶會相信那是一份正式文件。後面三個，信心亂填、轉真人寫成字串、或根本不是 JSON，整個回覆都會作廢，改回安全預設，也就是轉真人。目的，是記住寧可少答，也不讓壞回覆上畫面。

【第 4 步：啟動伺服器，在背景執行】
第四步先跑離線自我檢查，不呼叫模型，看到通過才繼續。接著把伺服器放到背景啟動，等它能回應，畫面會印出網頁標題、不存在路徑的錯誤，和伺服器自己的啟動訊息。伺服器只聽本機位址，同一個區網的別台電腦都連不到，這是故意的，因為它背後用的是個人訂閱。這一步結束時，腳本用 trap 一定把伺服器關掉，最後確認埠號已經沒有回應。後面第五到第七步也一樣，每一步自己開、自己關。目的，是學會背景服務一定要有收尾，不留下殘留行程。

【第 5 步：問一題知識庫內的問題】
第五步會呼叫模型一次，通常五到十秒。我們問 DR 八百的最大載重和充電時間。畫面會列出四個欄位，來源應該是產品規格和充電兩份文件，信心是高，不需要轉真人。下面還會印出這一題在紀錄檔裡的那一筆：檢索到哪些文件、各幾分，錯誤欄位是 null。答案的措辭每次可能不同，重點看那三個欄位。目的，是親眼走完一次檢索、呼叫、驗證、寫紀錄的完整流程。

【第 6 步：問一題知識庫外的問題】
第六步再呼叫模型一次，問一個跟產品無關的問題：可以幫我訂高鐵票嗎？這題一份文件都檢索不到，模型照系統提示的規則，回答無法確認、已轉真人客服，來源是空的，需要轉真人是 true。關鍵在紀錄檔的錯誤欄位是 null，代表這是模型照規則判斷的，不是回覆壞掉才走安全預設。如果這裡沒有轉真人，就照實記下來，那是模型沒照規則。目的，是看懂查不到就交給真人，是一個刻意設計的出口。

【第 7 步：空字串回 400，以及 XSS 防護】
第七步不呼叫模型。我們用 curl 送四種壞輸入：空白字串、不是 JSON、超過五百字、沒有內容，全部回 400。再比對紀錄檔的行數，前後一樣，證明壞輸入在進模型之前就被擋掉，一點額度都沒花到。接著看網頁怎麼顯示文字：全部用 textContent，不用 innerHTML。客戶輸入的內容，和模型被誘導回的內容，都可能夾帶一段 HTML，用 innerHTML 就會被瀏覽器當程式執行。目的，是記住使用者輸入和模型回覆，兩邊都是不可信的文字。

【第 8 步：三個靈魂拷問，先自己回答】
最後是三個靈魂拷問。畫面只出題，不給答案：這個代理是做給誰用的？被賦予了哪些工具權限？資料和成果存在哪裡？請先在心裡或紙上答完。提示是：對方會不會故意亂問？模型自己能讀檔嗎？客戶的問題存在哪，誰看得到？想好了跟我說繼續，我再執行下半段，顯示範例答案。目的，是先逼自己回答，才知道哪裡還沒想清楚。

【第 8 步下半：範例答案，以及跟 S1 的對比】
下半段把 S1 和 S2 的答案並排。S1 給自己用，S2 給外部客戶用；只換了第一題，後面全變了。因為使用者變成陌生人，權限縮到最小，連讀檔都不讓模型自己做，議價、客訴、退貨一律轉真人。紀錄裡存的是別人的問題，可能有個資，要訂保存期限、限制誰能讀。連付費方式都變了：示範可以用個人訂閱，正式給客戶用一定要換公司的 API key，再加上速率限制和身分驗證。這一章一共只呼叫模型兩次，伺服器每一步都已關閉。目的，是體會同樣是代理，給客戶用會讓三題的答案完全不同。

## 主要程式碼

### s2-customer-web/server.py

```python
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
```

### s2-customer-web/smoke_test.py

```python
"""S2 冒煙測試：背景啟動 server.py，打 3 個請求（2 次會呼叫模型），測完一定關掉伺服器。

用法（Git Bash，在本資料夾）：PYTHONUTF8=1 python smoke_test.py [--port 8903]
模型呼叫：2 次（知識庫內 1 題、知識庫外 1 題）；空字串那題在伺服器端就擋下，不會呼叫模型。
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
CASES = [
    ("知識庫內", "DR-800 最大載重多少？充電到九成要多久？", 200, False),
    ("知識庫外", "你們公司有賣掃地機器人嗎？可以幫我訂高鐵票嗎？", 200, True),
    ("空字串", "   ", 400, None),
]


def post(url: str, question: str) -> tuple[int, dict]:
    """用 urllib 送 POST；4xx 也讀回 JSON 內容，方便印出錯誤訊息。"""
    data = json.dumps({"question": question}, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=240) as res:
            return res.status, json.loads(res.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        return exc.code, json.loads(exc.read().decode("utf-8"))


def wait_ready(base_url: str, seconds: int = 15) -> None:
    """輪詢首頁直到伺服器能回應；逾時丟 RuntimeError。"""
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(base_url + "/", timeout=2):
                return
        except (urllib.error.URLError, ConnectionError):
            time.sleep(0.5)
    raise RuntimeError("伺服器啟動逾時")


def run_cases(base_url: str) -> int:
    """跑全部案例，印實際輸出，回傳失敗數。"""
    failures = 0
    for label, question, want_status, want_human in CASES:
        started = time.monotonic()
        status, body = post(base_url + "/api/ask", question)
        ok = status == want_status and (want_human is None or body.get("needs_human") is want_human)
        failures += 0 if ok else 1
        print(f"[{'PASS' if ok else 'FAIL'}] {label}（{time.monotonic() - started:.1f} 秒）HTTP {status}")
        print("       " + json.dumps(body, ensure_ascii=False))
    return failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8903)
    args = parser.parse_args()
    base_url = f"http://127.0.0.1:{args.port}"
    env = {**os.environ, "PYTHONUTF8": "1"}
    server = subprocess.Popen([sys.executable, str(BASE_DIR / "server.py"), "--port", str(args.port)], env=env)
    try:
        wait_ready(base_url)
        failures = run_cases(base_url)
    except (RuntimeError, OSError, json.JSONDecodeError) as exc:
        print(f"錯誤：{exc}", file=sys.stderr)
        failures = 1
    finally:
        server.terminate()   # 一定關掉，避免 8903 被殘留行程佔住
        try:
            server.wait(timeout=10)
        except subprocess.TimeoutExpired:
            server.kill()
    print(f"結果：{'全部通過' if failures == 0 else f'{failures} 項失敗'}（模型呼叫 2 次）")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
```
