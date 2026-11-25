# CLAUDE.md

K903「Claude Quickstarts 範例實作」教材 repo（見 README.md）。K902 的續集：照官方 `anthropics/claude-quickstarts` 的建議，做 5 個貼近生活的小範例。沒有原書。

- 這是學習用教材（快速 demo 模式），不是正式專案。
- 每個範例資料夾都要有 README.md，且必須回答三個靈魂拷問（做給誰用、工具權限、資料與成果存哪）；根目錄 `TEMPLATE-three-questions.md` 是空白模板。README 總覽表與各範例 README 不一致時，以各範例 README 為準。
- 呼叫模型一律走 `shared/llm_agent.py` 或 `shared/claude_cli_client.py`（`claude -p`，訂閱額度）；不可設定任何 API 金鑰，不 mock 模型。
- 官方原始碼 `~/workspace/claude-quickstarts` 只讀：不修改、不整包複製進本 repo、不安裝它的依賴。查看用 `shared/qs_source.py`。
- 路徑一律寫 `~` 或 `Path.home()`，不寫死使用者資料夾；不寫個人資料。
- `runs/`、`logs/`、`workdir/` 是執行產物，不進版控（已在 `.gitignore`）。

## 架構

```text
README.md                    總覽、學習順序、三個靈魂拷問
TEMPLATE-three-questions.md  空白模板與 claude -p／API 判斷表
shared/                      共用轉接層：llm_agent.py、claude_cli_client.py、qs_source.py
s1-agent-loop/               S1 本機資料夾小管家（對應官方 agents）
s2-customer-web/             S2 AMR 產品問答網頁（對應 customer-support-agent）
s3-long-running/             S3 兩階段自動寫程式（對應 autonomous-coding）
s4-managed-cloud/            S4 代管式每日比價代理（對應 managed-agents）
s5-browser-computer/         S5 瀏覽器讀價代理（對應 browser／computer use）
```

## 本專案例外

本專案是學習用教材（快速 demo 模式），豁免全域「程式碼三 agent 鐵律」：直接寫檔，不派 code-writer／code-qa／code-reviewer；不需詢問複雜度，也不需詢問是否使用快速模式。
`shared/` 三支共用工具改動後，要重跑 `PYTHONUTF8=1 python shared/<檔名>.py --selftest`。
