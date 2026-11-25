# S4 代管式每日比價代理（本機模擬 Managed Agents）

## 1. 模仿哪一章、做什麼

- 模仿官方 `claude-quickstarts` 第 9 章 **managed-agents**（K902 講義：`~/workspace/kindle-902-claude-quickstarts/lessons/ch09-managed-agents.md`，主要參考 `daily-brief` 與 `sentry`）。
- 一句話：每天把網路交換器比價資料整理成一份推薦報告。代理設定有版本號，每次執行是一個 session，過程寫成事件紀錄，報告交給評分者照 rubric 打分，FAIL 就重寫，排程指令只印不建。
- 目的是看懂「雲端代管」到底在管哪些東西：設定版本、session、事件串流、outcome 評分、排程。這些都先在本機用檔案模擬出來。

## 2. 三個靈魂拷問

| 問題 | 答案 |
| --- | --- |
| 這個代理是給誰用的？ | 只有我自己。設計成無人值守（每天排程跑一次），沒有人即時看著，所以要有評分者把關，並且每一步都留下事件紀錄，事後可以查。 |
| 被賦予了哪些工具的權限？ | **可以用**：`read_input`（只讀 `data/` 裡指定的那一個 JSON）、`write_report`（只能寫進自己 session 資料夾的 `report.md`）。工具由主機程式代為執行，每次呼叫前會比對 `agent.json` 的 `tools` 清單，不在清單上就記一筆錯誤事件並停下。**刻意不給**：`web_search`、`web_fetch`（官方無人值守範例也都關掉，避免被注入的文字有對外出口）、`bash`、`send_email`。`claude -p` 本身是用 `--tools ""` 啟動，模型碰不到電腦。 |
| 資料和成果最後存在哪裡？ | 輸入：`data/switches.json`（教學用假資料）。代理設定：`agents/price-report/agent.json`，版本鎖存在 `agent-lock.json`。成果：`runs/<session_id>/` 底下的 `events.jsonl`、`report.md`、`summary.json`，全部在本機，`runs/` 不進版控。不上傳、不寄信。 |

## 3. 架構與資料流

```text
agents/price-report/agent.json  (name, version, model, system, tools)
        │ load_agent：檢查版本鎖（內容改了但 version 沒升 → 拒絕執行）
        ▼
┌──────────── Session  runs/<sesn_id>/ ───────────────────────────┐
│ session.created → session.running                                 │
│   tool.use read_input ──► data/switches.json ──► tool.result      │
│   ┌─ outcome 迴圈（最多重寫 1 次）──────────────────────────────┐ │
│   │ model.call(writer) claude -p ─► agent.message                │ │
│   │ tool.use write_report ─► report.md ─► tool.result            │ │
│   │ model.call(grader) claude -p + rubric.md ─► outcome.graded   │ │
│   │   FAIL → 把不通過的理由當成回饋，回到 writer                  │ │
│   └──────────────────────────────────────────────────────────────┘ │
│ session.idle（或中途失敗時寫 session.error）→ summary.json        │
└───────────────────────────────────────────────────────────────────┘
        ▲
deploy.py --dry-run：印出 schtasks／cron，「每天 08:00 開一個新 session」
```

本機元件對應官方 Managed Agents 物件：

| 本機模擬 | 官方 Managed Agents | 說明 |
| --- | --- | --- |
| `agents/price-report/agent.json` ＋ `agent-lock.json` | `POST /v1/agents`（agent 有版本）、`ant apply` 寫的 `claude-lock.json` | 改設定就要升 `version`，舊 session 才查得到當時用的是哪一版 |
| `runs/<session_id>/` | session | 一次執行一個 session，彼此獨立 |
| `events.jsonl` | session 的 SSE 事件串流／事件紀錄（`events.stream`、`events.list`） | 每筆都有 `ts` 和 `type`，只追加不修改 |
| `call_tool()` 由主機代為執行 | custom tool（`agent.custom_tool_use` → `user.custom_tool_result`） | 權限白名單在主機端比對 |
| `rubric.md` ＋ 評分者 `claude -p` | outcomes（rubric 評分、評分者迭代） | FAIL 就帶著理由重寫，有次數上限 |
| `deploy.py`、`deployment.json` | scheduled deployments（cron 加時區，每次開新 session） | 本範例只印出指令 |
| `MAX_MODEL_CALLS = 4` | `budget.max_list_cost`（以「分」為單位的字串） | 本機只限制呼叫次數，不算錢 |

真正的雲端版要 API 額度。使用者帳戶目前剩約 US$19.99，所以本範例**完全不呼叫 API**，模型一律走 `claude -p`（Max 訂閱）。

## 4. 怎麼跑（Git Bash）

```bash
cd ~/workspace/kindle-903-quickstarts-samples/s4-managed-cloud

# 跑一個 session（模型呼叫 2～4 次，約 15～40 秒）
PYTHONUTF8=1 python run_session.py

# 換輸入資料或代理設定
PYTHONUTF8=1 python run_session.py --input data/switches.json --agent agents/price-report

# 看排程要怎麼建（只印，不建立）
PYTHONUTF8=1 python deploy.py --dry-run

# 看最新一個 session 的事件
cat "$(ls -d runs/sesn_* | tail -1)/events.jsonl"
```

## 5. 實際跑出來的結果（2026-11-25 冒煙測試）

`python run_session.py`（模型呼叫 2 次，約 18 秒）：

```text
  [14:16:07] session.created
  [14:16:07] session.running
  [14:16:07] tool.use
  [14:16:07] tool.result
  [14:16:15] model.call
  [14:16:15] agent.message
  [14:16:15] tool.use
  [14:16:15] tool.result
  [14:16:25] model.call
  [14:16:25] outcome.graded
  [14:16:25] session.idle

session 路徑：...\s4-managed-cloud\runs\sesn_20261125-141607_3a626c
代理：price-report@v1　模型呼叫：2 次　嘗試：1 次
第 1 次評分：PASS
  1. PASS｜表格列出全部 8 項商品，不多不少，價格（229、275、369、439、439、159、669、729）與輸入資料完全一致。
  2. PASS｜只推 Mercusys MS105G 一項，並引用 229 元、4.98 分、2,282 則評價、8,000 件銷量等正確數字（文中「價格僅高於無品牌款與 TOTOLINK」的比較有誤，但不影響本條要求）。
  3. PASS｜表格六欄（排名、商品、價格、評分（評價數）、銷量、賣家）齊全，排名 1 到 8 連續。
  4. PASS｜注意事項點名無品牌款（評分 4.6、海外出貨）與 D-Link DGS-108、TOTOLINK S505G 樣本偏少等具體風險。
  5. PASS｜全文繁體中文（型號除外），約 27 行未超過 50 行，且沒有開場白或結語。

報告前 15 行：
# 網路交換器每日比價報告（2026-11-25）

## 首選推薦
**Mercusys MS105G 5 埠 Gigabit**，價格 229 元，賣家為光華 3C 專賣店（優選）。
評分 4.98（2,282 則評價），銷量 8,000 件，在 5 埠款中價格僅高於無品牌款與 TOTOLINK，但評價數與銷量遠高於它們。
比同樣 4.98 分、銷量 10,000 件的 TP-Link TL-SG105（439 元）便宜 210 元，符合 Gigabit、非網管、非 PoE 的需求。

## CP 值排序
| 排名 | 商品 | 價格 | 評分（評價數） | 銷量 | 賣家 |
|---|---|---|---|---|---|
| 1 | Mercusys MS105G 5 埠 | 229 | 4.98（2,282） | 8,000 | 光華 3C 專賣店（優選） |
| 2 | TOTOLINK S505G 5 埠 | 275 | 4.98（206） | 613 | 速易購電腦 |
| 3 | Mercusys MS108G 8 埠 | 369 | 4.97（640） | 1,500 | 光華 3C 專賣店（優選） |
| 4 | TP-Link TL-SG105 5 埠 鋼殼 | 439 | 4.98（5,457） | 10,000 | TP-Link 官方商城 |
| 5 | D-Link DGS-105 5 埠 金屬殼 | 439 | 4.98（2,267） | 4,000 | 蝦皮商城（台南） |
```

這次學到一件事：評分者在第 2 條**發現了**「價格僅高於無品牌款與 TOTOLINK」這句比較寫錯了（229 元其實比 TOTOLINK 的 275 元便宜），但 rubric 沒有規定理由裡的比較要正確，所以仍然給 PASS。**評分者只會照 rubric 打分**，rubric 漏寫的品質要求就不會被擋下。要擋這種錯，就在第 2 條加一句「理由中的比較必須和資料一致」。

版本鎖測試（不呼叫模型）：把設定裡的 `model` 改成 `haiku`，但 `version` 不動，再執行：

```text
錯誤：agent.json 內容變了但 version 還是 1（鎖定 1624e4351b5f，現在 d6704af49fff）。請把 version 加 1 再執行。
```

`python deploy.py --dry-run`：

```text
[dry-run] 代理 price-report：Asia/Taipei 每天 08:00 開一個新 session

Windows（Git Bash）建立排程：
  MSYS_NO_PATHCONV=1 schtasks /Create /TN "K903-S4-price-report" /SC DAILY /ST 08:00 /TR 'cmd /c "cd /d %USERPROFILE%\workspace\kindle-903-quickstarts-samples\s4-managed-cloud && set PYTHONUTF8=1 && python run_session.py >> runs\schedule.log 2>&1"' /F
  ...
Linux／VPS（crontab -e 加入）：
  CRON_TZ=Asia/Taipei
  0 8 * * * cd $HOME/workspace/kindle-903-quickstarts-samples/s4-managed-cloud && PYTHONUTF8=1 python3 run_session.py >> runs/schedule.log 2>&1

雲端正式版（Anthropic scheduled deployment，要 API 額度，本範例不呼叫）：
  schedule: {type: cron, expression: "0 8 * * *", timezone: Asia/Taipei}
  ...
[dry-run] 沒有建立任何排程。
```

## 6. 跟官方原版差在哪，正式上線要改什麼

| 項目 | 官方原版 | 本範例 |
| --- | --- | --- |
| 模型呼叫 | `ANTHROPIC_API_KEY` 或 `ant auth login`，扣 API 額度 | `claude -p`，用 Max 訂閱，不設任何金鑰 |
| 代理迴圈在哪跑 | Anthropic 伺服器 | 本機的 `run_session.py` 扮演伺服器 |
| 工具 | 沙箱（Docker 類環境）裡的 bash、檔案工具、MCP；網路白名單寫在 `environment.yaml` | 只有兩個由主機執行的 Python 函式；`claude -p --tools ""` 不給任何內建工具 |
| 事件 | SSE 即時串流，可重播、可斷線續接 | 寫進 `events.jsonl`，跑完才看；不支援續接 |
| 記憶 | memory store（跨 session，可設唯讀或讀寫） | 沒有。每個 session 只讀當天的輸入檔 |
| 評分 | outcomes 內建 | 自己多呼叫一次 `claude -p` 當評分者，整體結果由程式依 5 條計算，不採信模型自己寫的 overall |
| 排程與預算 | scheduled deployment ＋ `budget.max_list_cost` | 只印 schtasks／cron；預算用呼叫次數上限代替 |

正式上線要改的地方：

1. 輸入改成真實資料來源（例如蝦皮 API）。抓資料要在主機端做，不要給模型上網的工具。
2. 加跨日記憶（像 `daily-brief` 的 state store），例如記住昨天的價格，報告才能寫「比昨天降 30 元」。
3. 補 rubric：加上「理由裡的比較要和資料一致」，這就是本次冒煙測試漏掉的那類錯誤。
4. 真的要改走雲端時：用 `ant apply` 建 agent／environment／deployment，設定預算上限，並把 `web_search` 和 `web_fetch` 關掉。注意這會開始扣 API 額度。
5. 排程前先手動建立 `runs/` 資料夾，否則 `>> runs\schedule.log` 會失敗。也要決定報告怎麼送達：通知屬於對外動作，必須另外設計並經過確認。

## 7. 模仿指南：改成自己的需求，改這 3 個地方

1. **`data/`**：換成你的資料（例如每日匯率、課表、待辦清單）。JSON 結構不限，模型讀得懂就好。
2. **`agents/price-report/agent.json`**：改 `system`，說明報告的段落與限制；要換模型或工具就改 `model`、`tools`。**改完一定要把 `version` 加 1**，否則程式會拒絕執行。想要好幾個代理，就複製整個資料夾改名。
3. **`rubric.md`**：寫 5 條「看得出對錯」的具體標準（數字一致、段落齊全、長度上限……）。條數變了，記得一起改 `run_session.py` 裡檢查「應為 5 條」的那一行。

排程時間在 `agents/price-report/deployment.json` 的 `schedule.expression` 修改，再跑 `deploy.py --dry-run` 看新的指令。
