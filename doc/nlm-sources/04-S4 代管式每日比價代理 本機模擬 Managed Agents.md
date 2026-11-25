# S4 代管式每日比價代理 本機模擬 Managed Agents

> K903《Claude Quickstarts 範例實作》第 4 段，共 5 段。對應官方 claude-quickstarts（K902）第 9 章 managed-agents。
> 書號 9 開頭為自製教材，沒有原書；模型一律走 claude -p 轉接層，不設 API 金鑰。

## 導讀

S4 用本機檔案模擬雲端代管（Managed Agents）在管的東西：代理設定有版本號、每次執行是一個 session、過程寫成事件串流、報告交給評分者照 rubric 打分，FAIL 就重寫，排程指令只印不建。這一段要學會：無人值守的代理為什麼一定要有評分者與事件紀錄，以及為什麼刻意不給 web_search、web_fetch、bash、send_email 這些工具。

每個範例學完都要回答三個靈魂拷問：這個代理是做給誰用的？它被賦予了哪些工具的權限？它的資料和成果最後存在哪裡？

## 範例說明（README）

### 1. 模仿哪一章、做什麼

- 模仿官方 `claude-quickstarts` 第 9 章 **managed-agents**（K902 講義：`~/workspace/kindle-902-claude-quickstarts/lessons/ch09-managed-agents.md`，主要參考 `daily-brief` 與 `sentry`）。
- 一句話：每天把網路交換器比價資料整理成一份推薦報告。代理設定有版本號，每次執行是一個 session，過程寫成事件紀錄，報告交給評分者照 rubric 打分，FAIL 就重寫，排程指令只印不建。
- 目的是看懂「雲端代管」到底在管哪些東西：設定版本、session、事件串流、outcome 評分、排程。這些都先在本機用檔案模擬出來。

### 2. 三個靈魂拷問

| 問題 | 答案 |
| --- | --- |
| 這個代理是給誰用的？ | 只有我自己。設計成無人值守（每天排程跑一次），沒有人即時看著，所以要有評分者把關，並且每一步都留下事件紀錄，事後可以查。 |
| 被賦予了哪些工具的權限？ | **可以用**：`read_input`（只讀 `data/` 裡指定的那一個 JSON）、`write_report`（只能寫進自己 session 資料夾的 `report.md`）。工具由主機程式代為執行，每次呼叫前會比對 `agent.json` 的 `tools` 清單，不在清單上就記一筆錯誤事件並停下。**刻意不給**：`web_search`、`web_fetch`（官方無人值守範例也都關掉，避免被注入的文字有對外出口）、`bash`、`send_email`。`claude -p` 本身是用 `--tools ""` 啟動，模型碰不到電腦。 |
| 資料和成果最後存在哪裡？ | 輸入：`data/switches.json`（教學用假資料）。代理設定：`agents/price-report/agent.json`，版本鎖存在 `agent-lock.json`。成果：`runs/<session_id>/` 底下的 `events.jsonl`、`report.md`、`summary.json`，全部在本機，`runs/` 不進版控。不上傳、不寄信。 |

### 3. 架構與資料流

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

### 4. 怎麼跑（Git Bash）

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

### 5. 實際跑出來的結果（2026-11-25 冒煙測試）

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

### 首選推薦
**Mercusys MS105G 5 埠 Gigabit**，價格 229 元，賣家為光華 3C 專賣店（優選）。
評分 4.98（2,282 則評價），銷量 8,000 件，在 5 埠款中價格僅高於無品牌款與 TOTOLINK，但評價數與銷量遠高於它們。
比同樣 4.98 分、銷量 10,000 件的 TP-Link TL-SG105（439 元）便宜 210 元，符合 Gigabit、非網管、非 PoE 的需求。

### CP 值排序
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

### 6. 跟官方原版差在哪，正式上線要改什麼

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

### 7. 模仿指南：改成自己的需求，改這 3 個地方

1. **`data/`**：換成你的資料（例如每日匯率、課表、待辦清單）。JSON 結構不限，模型讀得懂就好。
2. **`agents/price-report/agent.json`**：改 `system`，說明報告的段落與限制；要換模型或工具就改 `model`、`tools`。**改完一定要把 `version` 加 1**，否則程式會拒絕執行。想要好幾個代理，就複製整個資料夾改名。
3. **`rubric.md`**：寫 5 條「看得出對錯」的具體標準（數字一致、段落齊全、長度上限……）。條數變了，記得一起改 `run_session.py` 裡檢查「應為 5 條」的那一行。

排程時間在 `agents/price-report/deployment.json` 的 `schedule.expression` 修改，再跑 `deploy.py --dry-run` 看新的指令。

## 逐步演練教練稿（8 步）

K903 範例 S4 互動演練：代管式每日比價代理，在本機用檔案模擬雲端代管（教練稿）

【第 1 步：雲端代管在管什麼，五件事】
這個範例模仿官方第九章的 Managed Agents。雲端代管的意思是，代理迴圈跑在 Anthropic 的伺服器上，你只負責宣告資源、讀取事件。我們不用 API，改由一支 Python 程式扮演伺服器，把它管的五件事各用一個本機檔案模擬出來。第一是有版本號的代理設定，第二是 session，也就是一次執行，第三是事件串流，第四是照評分標準打分的 outcome，第五是排程。畫面會用一張表對照本機檔案和官方物件，並對回官方原文：改設定就會發布新版本。目的，是先知道雲端到底替你管了哪些東西。

【第 2 步：看代理設定和版本鎖】
第二步打開代理設定檔。你會看到名稱、版本一、模型 sonnet、系統提示，還有工具白名單：只有讀資料和寫報告兩個工具，上網搜尋、抓網頁、bash 和寄信都刻意不給。接著看版本鎖：程式把設定正規化之後算 sha256，取前十二碼當指紋，第一版的指紋記在鎖檔裡，現在算出來一致。目的，是知道同一個版號的內容不可以偷改。

【第 3 步：改了模型卻不升版號，被程式拒絕】
第三步故意犯錯。程式先備份設定檔、記下 sha256，再把模型從 sonnet 改成 haiku，版本號維持一，然後執行。版本鎖在建立 session 之前就擋下來，錯誤訊息說內容變了但版本還是一，請加一，所以完全沒有呼叫模型。不管成功或失敗，程式都會把原檔寫回去，畫面會顯示 sha256 和原檔完全一致，鎖檔也沒被動過。後半在暫存資料夾示範正確做法：把版本升成二，程式就放行，鎖檔裡第一版和第二版的指紋並存。目的，是體會為什麼改設定一定要升版號：舊的 session 事後才查得到當時用的是哪一版。

【第 4 步：實跑一個 session】
第四步會呼叫模型兩次，大約十五到三十秒，不重試。第一次是寫手，讀比價資料寫成報告；第二次是評分者，照評分標準的五條逐條打分。程式原本最多呼叫四次，評分不通過會帶著理由重寫一次；為了守住本章兩次的預算，這裡在演練中把上限暫時改成二。萬一評分不通過，第三次呼叫會被擋下，並記一筆錯誤事件，這正好就是官方預算上限的作用。實測結果，五條全部通過，首選推薦是 Mercusys MS105G，二百二十九元。目的，是親眼看到一個 session 從建立到閒置的完整過程。

【第 5 步：逐行看事件紀錄，對照官方事件】
第五步打開最新 session 的事件紀錄，一行一筆。順序是：建立、開始執行、讀資料的工具呼叫和結果、寫手的模型呼叫、代理訊息、寫報告的工具呼叫和結果、評分者的模型呼叫、評分結果，最後是閒置。右邊一欄對到官方的事件名稱，例如工具呼叫對到 agent.custom_tool_use，結果由主機回送，對到 user.custom_tool_result，閒置對到 session.status_idle。程式也檢查時間只增不減，代表只追加、不修改。目的，是看懂官方的即時事件串流，本質上就是一份按時間排的紀錄，可以重播。

【第 6 步：看報告、評分標準和評分結果】
第六步看報告、評分標準和評分理由，這一步是本章的重點。冒煙測試那一次，評分者在第二條理由裡明明寫了，報告中「價格僅高於無品牌款與 TOTOLINK」這句比較有誤，卻還是給 PASS。用程式對資料就看得出來：比首選便宜的只有一百五十九元的無品牌款，TOTOLINK 是二百七十五元，其實比較貴。為什麼仍然 PASS？因為第二條只要求只推一項、理由引用數字，沒有要求比較必須正確。評分者只會照評分標準打分，評分標準沒寫到的品質，就不會被擋下。修法是在第二條加一句：理由中的比較必須和輸入資料一致。目的，是記住評分標準寫得不夠具體，評分就會放水。

【第 7 步：用 dry-run 看排程怎麼寫】
第七步執行部署程式的 dry-run 模式。畫面印出三種寫法：Windows 的 schtasks、Linux 的 cron，還有官方雲端的排程設定，都是台北時間每天早上八點開一個新 session。不加 dry-run 參數，程式會直接拒絕；我們也查過系統，確認沒有真的建立排程。最後講費用：本機版走訂閱，不花 API 額度；雲端正式版每天一個 session 都要扣 API 額度，必須用預算上限控管。目的，是明白排程就是「定時開新 session」，而搬上雲端是要花錢的決定。

【第 8 步：三個靈魂拷問，先自己回答】
最後是三個靈魂拷問：這個代理給誰用、被賦予哪些工具權限、資料和成果存在哪裡。請先不要看答案，用一兩句話自己說出來，尤其想一想：如果真的搬上雲端，資料會在誰手上。想好之後說「繼續」。

【第 8 步後半：範例答案，本機和真雲端的差別】
範例答案從說明文件的表格讀出來：只給自己用、無人值守，所以要有評分者和事件紀錄把關；只有讀資料和寫報告兩個工具，白名單由主機比對；所有東西都在本機的 runs 資料夾。重點在第三題的對照：本機版的設定、session、事件和報告都在自己的硬碟，刪掉資料夾就沒了；真正的雲端版，這些都由 Anthropic 保管，換來即時串流、斷線續接和跨日記憶，代價是 API 額度，以及資料離開本機。目的，是記住同一個代理，搬上雲端之後，資料的保管人就換了。

## 主要程式碼

### s4-managed-cloud/deploy.py

```python
"""S4 排程部署（只印不做）：讀 deployment.json，印出 Windows schtasks 與 Linux cron 的寫法。

為什麼只支援 --dry-run：這是教材，看懂「排程＝每次開一個新 session」即可；
真的建立排程會讓電腦每天自動呼叫模型，要不要開由使用者自己決定。
正式雲端版對應 Anthropic Managed Agents 的 scheduled deployment（要 API 額度）。

用法（Git Bash，在 s4-managed-cloud 目錄）：
    PYTHONUTF8=1 python deploy.py --dry-run
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEPLOYMENT_PATH = HERE / "agents" / "price-report" / "deployment.json"


def load_deployment() -> dict:
    try:
        deployment = json.loads(DEPLOYMENT_PATH.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError) as exc:
        raise SystemExit(f"錯誤：讀不到 {DEPLOYMENT_PATH}：{exc}") from exc
    minute, hour, *_ = deployment["schedule"]["expression"].split()
    if not (minute.isdigit() and hour.isdigit()):
        raise SystemExit("錯誤：本範例只支援「每天固定時刻」的 cron（例如 0 8 * * *）")
    deployment["_hhmm"] = f"{int(hour):02d}:{int(minute):02d}"
    return deployment


def windows_command(deployment: dict) -> str:
    # 路徑用 %USERPROFILE%，換電腦不用改；Git Bash 下要加 MSYS_NO_PATHCONV=1，否則 /Create 會被轉成路徑
    workdir = r"%USERPROFILE%\workspace\kindle-903-quickstarts-samples\s4-managed-cloud"
    action = f'cmd /c "cd /d {workdir} && set PYTHONUTF8=1 && python run_session.py >> runs\\schedule.log 2>&1"'
    return (f'MSYS_NO_PATHCONV=1 schtasks /Create /TN "{deployment["task_name"]}" /SC DAILY '
            f'/ST {deployment["_hhmm"]} /TR \'{action}\' /F')


def cron_line(deployment: dict) -> str:
    workdir = "$HOME/workspace/kindle-903-quickstarts-samples/s4-managed-cloud"
    return (f'CRON_TZ={deployment["schedule"]["timezone"]}\n'
            f'{deployment["schedule"]["expression"]} cd {workdir} && PYTHONUTF8=1 python3 run_session.py '
            '>> runs/schedule.log 2>&1')


def main() -> int:
    parser = argparse.ArgumentParser(description="印出排程指令（不建立排程）")
    parser.add_argument("--dry-run", action="store_true", help="只印出指令（本範例唯一支援的模式）")
    args = parser.parse_args()
    if not args.dry_run:
        print("本範例只支援 --dry-run：不會真的建立排程。請加上 --dry-run。", file=sys.stderr)
        return 2
    deployment = load_deployment()
    print(f"[dry-run] 代理 {deployment['agent']}：{deployment['schedule']['timezone']} 每天 {deployment['_hhmm']} 開一個新 session\n")
    print("Windows（Git Bash）建立排程：")
    print("  " + windows_command(deployment))
    print(f'  查看：MSYS_NO_PATHCONV=1 schtasks /Query /TN "{deployment["task_name"]}"')
    print(f'  刪除：MSYS_NO_PATHCONV=1 schtasks /Delete /TN "{deployment["task_name"]}" /F\n')
    print("Linux／VPS（crontab -e 加入）：")
    print("  " + cron_line(deployment).replace("\n", "\n  "))
    print("\n雲端正式版（Anthropic scheduled deployment，要 API 額度，本範例不呼叫）：")
    print(f"  schedule: {{type: cron, expression: \"{deployment['schedule']['expression']}\", "
          f"timezone: {deployment['schedule']['timezone']}}}")
    print(f"  備註：{deployment['budget_note']}")
    print("\n[dry-run] 沒有建立任何排程。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

### s4-managed-cloud/run_session.py

```python
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
```

### s4-managed-cloud/rubric.md

```markdown
# 比價報告評分標準（outcome rubric）

評分者對每一條給 PASS 或 FAIL，並附一句理由。任一條 FAIL，整份報告就是 FAIL。

1. **資料完整且不編造**：「CP 值排序」表格列出輸入資料的全部商品（不多不少），每一筆的價格與輸入資料完全相同。
2. **有明確首選**：「首選推薦」只推一項商品，理由至少引用一個實際數字（價格、評分、評價數或銷量）。
3. **排序表格欄位齊全**：表格有排名、商品、價格、評分（評價數）、銷量、賣家六欄，且排名從 1 開始連續。
4. **指出風險**：「注意事項」至少一條具體風險，並點名是哪一項商品或哪一類情況。
5. **格式與語言**：全文繁體中文（商品型號除外），不超過 50 行，沒有報告以外的開場白或結語。
```
