# K903 Claude Quickstarts 範例實作

K902（官方 `anthropics/claude-quickstarts` 的 10 章導讀）的續集。K902 帶你讀懂官方怎麼做，K903 則是「照官方建議，親手做出 5 個貼近生活的小範例」，先模仿、再延伸成自己的需求。

書號 9 開頭代表這是自製教材，沒有對應的原書。

## 學習順序（由簡到難）

| 順序 | 範例 | 對應官方章（K902） | 一句話主題 | 為什麼排在這裡 | 資料夾 |
| --- | --- | --- | --- | --- | --- |
| 1 | S1 本機資料夾小管家 | 第 3 章 agents | 搞懂代理迴圈：模型想、呼叫工具、看結果、再想 | 所有範例都建立在這個迴圈上，工具最少、不碰網路 | [s1-agent-loop](s1-agent-loop/) |
| 2 | S2 AMR 產品問答網頁 | 第 1 章 customer-support-agent | 給客戶用：網頁介面加知識庫問答 | 第一次加上「別人」使用者，開始談權限邊界 | [s2-customer-web](s2-customer-web/) |
| 3 | S3 兩階段自動寫程式 | 第 10 章 autonomous-coding | 長時間工作：規劃階段加實作階段，無人看著連續跑 | 要處理進度檔、續跑、停止條件 | [s3-long-running](s3-long-running/) |
| 4 | S4 代管式每日比價代理 | 第 9 章 managed-agents | 雲端代管：設定、session、報告分開存 | 要先懂迴圈與長時間工作，才看得懂代管的價值 | [s4-managed-cloud](s4-managed-cloud/) |
| 5 | S5 瀏覽器讀價代理 | 第 4～8 章 browser／computer use | 電腦與瀏覽器進階操作 | 權限最大、風險最高，放最後 | [s5-browser-computer](s5-browser-computer/) |

## 三個靈魂拷問

每個範例學完，都要回答這三題。寫不出來，代表還沒真的懂這個代理。

1. 這個代理是做給誰用的？
2. 它被賦予了哪些工具的權限？
3. 它的資料和成果最後存在哪裡？

### 為什麼每章都要問

代理跟一般程式不同：它會自己決定下一步。所以「誰在用、能動什麼、東西存哪」決定了風險與成本。這三題同時也決定你該用 `claude -p`（訂閱額度）還是正式 API。

### 每題該想什麼

| 題目 | 該想什麼 |
| --- | --- |
| 做給誰用 | 只有自己、同事，還是外部客戶？對方會不會故意亂問？同時有幾個人用？ |
| 工具權限 | 逐一列出工具，每個都問「沒有它行不行」。能唯讀就不給寫入；能限定資料夾就不給整顆硬碟；能不上網就不上網。 |
| 資料存哪 | 輸入從哪來、對話紀錄、中間檔、最終成果各存哪？有沒有個資？會不會被 git 推上去？ |

### 常見錯誤

- 給客戶用，卻用個人訂閱的 `claude -p`：違反使用條款、額度被客戶吃光、無法保證穩定。給別人用要改走 API key。
- 權限給太大：為了方便給「讀寫整個家目錄」或「任意執行命令」，模型一句誤解就可能刪檔。
- 只想到工具，沒想到資料：對話紀錄、截圖、報告散落各處，不知道哪些含個資。
- 把 `runs/`、`logs/`、`workdir/` 推上 GitHub：這些是執行產物，已在 `.gitignore`。
- 只回答「做什麼」而不回答「給誰」：沒有使用者，就無從判斷權限該多嚴。

空白模板見 [TEMPLATE-three-questions.md](TEMPLATE-three-questions.md)，學完每章、或要寫自己的需求時使用。

## 5 個範例的三個靈魂拷問總覽

> 本表摘自各範例 README 第 2 節，細節以範例內為準。五個範例的 `claude -p` 都用 `--tools ""` 啟動，模型本身沒有任何工具，下表的「工具」都是程式代為執行。

| 範例 | 做給誰用 | 工具權限 | 資料與成果存哪 |
| --- | --- | --- | --- |
| S1 本機資料夾小管家 | 使用者自己，在終端機一個人用 | `list_dir`、`read_file`（最多 4000 字）、`search_text`，全部唯讀，限定一個根目錄（預設 shopping-notes，可用 `--root` 改）；不給寫檔、刪檔、執行指令、上網 | 答案只印在終端機；迴圈紀錄寫 `runs/<時間>.json`，只存每輪請求與結果長度、不存工具讀到的全文；`runs/` 不進版控 |
| S2 AMR 產品問答網頁 | 外部客戶（想買 AMR 的工廠、倉儲人員）；本範例只在 127.0.0.1 示範，正式上線要改用公司 API key，不能用個人訂閱 | 程式讀 `kb/` 的 5 份 markdown 給模型看；模型不能讀檔、上網、查訂單、下單、改價、寄信；議價、客訴、退貨一律交真人 | 知識庫 `kb/*.md` 進 git；每次問答寫 `logs/YYYY-MM-DD.jsonl`（可能含客戶個資，`logs/` 不進版控） |
| S3 兩階段自動寫程式 | 想學長時間任務怎麼分 session 接力的自己；產出的 `ledger.py` 是自用記帳小工具 | 模型只回 JSON，寫檔、跑測試、commit 由 harness 代做；只准寫進 `workdir/`，擋 `..`、絕對路徑、`.git/`；清單與進度檔只有 harness 能寫；不能改 `tests/`；一次最多呼叫模型 10 次 | 全部在 `workdir/`（獨立 git repo）：`feature_list.json`、`progress.md`、`tests/`、`ledger.py` 與 git 歷史；外層 repo 排除 `workdir/` |
| S4 代管式每日比價代理 | 只有自己，無人值守（每天排程跑一次），靠評分者把關與事件紀錄 | `read_input`（只讀 `data/` 指定的一個 JSON）、`write_report`（只寫自己 session 的 `report.md`），呼叫前比對 `agent.json` 的工具清單；刻意不給 `web_search`、`web_fetch`、`bash`、`send_email` | 輸入 `data/switches.json`；設定 `agents/price-report/agent.json`＋`agent-lock.json`；成果 `runs/<session_id>/` 的 `events.jsonl`、`report.md`、`summary.json`，`runs/` 不進版控 |
| S5 瀏覽器讀價代理 | 只有自己，在終端機看著它跑（有人即時看著） | `navigate`（只限白名單的本機練習網站 `127.0.0.1:<埠>`）、`read_page`、`click`、`type`、`screenshot`；不連外網、不登入、不付款、不讀寫本機其他檔案 | 練習網站 `site/` 進版控；每次執行的 `step-N.png` 與 `result.json` 存 `runs/<時間>/`，不進版控 |

## 互動演練

`practice/interactive/` 是五個範例的逐步演練腳本，一次跑一步；`coach-sN.txt` 是每一步的教練講稿。

用法（Git Bash，在 repo 根目錄）：

```bash
cd practice/interactive
bash s1.sh 1      # 格式：bash sN.sh <步驟>，N 是範例編號
```

- 每章 8 步，第 8 步分兩半：`bash sN.sh 8` 先出三個靈魂拷問，自己想好後再跑 `bash sN.sh 8b` 看範例答案。
- 建議順序：S1 → S2 → S3 → S4 → S5（和上面的學習順序一樣）。

各章會呼叫真模型的步驟（數字取自各 `sN.sh` 開頭註解，其餘步驟全部離線）：

| 章 | 呼叫模型的步驟 | 大約次數 |
| --- | --- | --- |
| S1 | 第 4 步 | 最多 2 次 |
| S2 | 第 5、6 步 | 各 1 次，共 2 次 |
| S3 | 第 5、6 步 | 各最多 2 次，整章最多 4 次 |
| S4 | 第 4 步 | 最多 2 次 |
| S5 | 第 5 步 | 實測 4 次，上限 8 次 |

### `--dry-run`：不呼叫模型，只檢查腳本路徑

用寫死的假回覆代替模型，畫面會標明是乾跑，不算演練：

```bash
bash s1.sh 4 --dry-run
bash s3.sh 5 --dry-run    # 產出寫到 s3-long-running/logs/dry-run-workdir，不動真正的 workdir
bash s3.sh 6 --dry-run
bash s4.sh 4 --dry-run    # session 寫到暫存資料夾，跑完刪掉
```

S2、S5 的腳本沒有 `--dry-run`。

### S3 的 `restore`

S3 第 5 步會先把 4/4 完成的 `s3-long-running/workdir` 改名成 `workdir.bak-4of4`，再從空的 workdir 重跑。演練完要還原：

```bash
bash s3.sh restore    # workdir.bak-4of4 → workdir（8b 結尾也會問要不要還原）
```

`workdir.bak-*/` 已在 `.gitignore`。

**新電腦先跑 seed（或讓它自動重建）**：`workdir/` 也在 `.gitignore`，clone 下來時不存在。4/4 完成版的工作樹放在進版控的 `s3-long-running/snapshot-4of4/`：

```bash
bash s3.sh seed       # 從 snapshot-4of4 重建 workdir：複製檔案、git init、一個 commit；不呼叫模型
```

第 3、4、7 步與 `restore` 發現 workdir 和 `workdir.bak-4of4` 都不存在時會自動重建，不跑 seed 也可以。重建版只有 1 個 commit，第 3 步會改顯示 `snapshot-4of4/git-log.txt` 裡原本的 5 個 commit。

## 使用前準備

1. `claude` CLI 已安裝並登入（跑 `claude -p "hi"` 能回應）。
2. 不設定 `ANTHROPIC_API_KEY`（也不設任何其他 API 金鑰）；一旦設了，`claude -p` 會改扣 API 額度。
3. 所有模型呼叫一律走 `shared/` 轉接層（`claude -p`，用訂閱額度）：
   - `shared/llm_agent.py`：單次問答與 JSON 抽取（`ask`、`ask_json`）
   - `shared/claude_cli_client.py`：模仿 anthropic SDK 的最小介面，含工具迴圈
   - `shared/qs_source.py`：唯讀查看官方 quickstarts 原始碼（`~/workspace/claude-quickstarts`）
4. Windows 上執行 Python 要加 `PYTHONUTF8=1`。轉接層自我檢查：

   ```bash
   PYTHONUTF8=1 python shared/llm_agent.py --selftest
   ```

## 怎麼用這份教材

1. 先看該範例的 README 和它的三個靈魂拷問。
2. 照 README 跑一次，看到結果。
3. 對照 K902 對應章的講義（`~/workspace/kindle-902-claude-quickstarts/lessons/`），看官方原本怎麼做。
4. 複製 [TEMPLATE-three-questions.md](TEMPLATE-three-questions.md) 填自己的需求，再用範例當模板改寫成自己的版本。

## 目錄

```text
README.md                      本檔
TEMPLATE-three-questions.md    三個靈魂拷問空白模板
CLAUDE.md                      給 Claude Code 的專案說明
shared/                        共用轉接層（claude -p）
s1-agent-loop/ … s5-browser-computer/   五個範例
practice/interactive/          互動演練腳本 s1.sh～s5.sh 與教練稿 coach-s1.txt～coach-s5.txt
```
