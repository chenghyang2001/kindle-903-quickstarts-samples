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

> 以各範例 README 為準；本表是規劃時的初版，範例實作後若有出入，以範例內為準。

| 範例 | 做給誰用 | 工具權限 | 資料與成果存哪 |
| --- | --- | --- | --- |
| S1 本機資料夾小管家 | 使用者自己，在終端機用 | 只能讀指定資料夾（列目錄、讀檔）；不給寫入、刪除、網路 | 不寫任何檔案，結果印在終端機，另留一份 JSON 執行紀錄 |
| S2 AMR 產品問答網頁 | 外部客戶，用瀏覽器問 | 只能查 `kb/` 知識庫；不能碰其他檔案、不能上網 | 知識庫在 `kb/`，對話紀錄存本機 `logs/`；正式上線要改用 API key，不能用個人訂閱 |
| S3 兩階段自動寫程式 | 使用者自己，無人看著連續跑 | 只能在 `workdir/` 內讀寫檔、跑測試 | 成果是 `workdir/` 裡的程式、進度檔與 git 歷史 |
| S4 代管式每日比價代理 | 使用者自己，排程自動跑 | 只能讀輸入資料、寫報告 | 設定檔、session 紀錄、報告存在 `runs/`；真雲端版會在 Anthropic 的容器裡 |
| S5 瀏覽器讀價代理 | 使用者自己 | 只能操作一個無頭瀏覽器，且只限本機練習網站 | 截圖和讀到的資料存 `runs/` |

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
```
