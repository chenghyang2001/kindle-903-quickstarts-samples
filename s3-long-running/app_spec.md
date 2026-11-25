# 規格：記帳 CSV 月統計 CLI（ledger）

## 目標

做一個命令列小工具，讀一份記帳 CSV，印出各分類合計與每月總計。只用 Python 3 標準庫。

## 輸入格式

CSV 檔，第一列是表頭 `date,category,amount`：

```csv
date,category,amount
2026-10-03,餐飲,120
2026-10-05,交通,35
2026-11-01,餐飲,85.5
```

- `date`：`YYYY-MM-DD`
- `category`：任意文字（可以是中文）
- `amount`：數字，可以有小數

## 輸出（範例）

```text
== 各分類合計 ==
交通    35.00
餐飲    205.50
== 每月總計 ==
2026-10    155.00
2026-11    85.50
總計    240.50
```

分類依名稱排序、月份依時間排序，金額固定兩位小數。

## 介面（實作與測試都要照這個）

- 主程式檔：`ledger.py`，執行方式 `python ledger.py <csv 路徑>`
- `load_records(path) -> list[dict]`：讀 CSV，回傳 `{"date": str, "category": str, "amount": float}` 的清單；格式錯的列（日期不合法、金額不是數字、欄位不足）略過並印警告到 stderr
- `sum_by_category(records) -> dict[str, float]`
- `sum_by_month(records) -> dict[str, float]`（鍵是 `YYYY-MM`）
- `format_report(records) -> str`：組出上面的輸出文字
- 檔案不存在時，CLI 印錯誤到 stderr 並以結束碼 1 離開

## 範圍限制

- 功能清單切成 3～4 項，每項都能用 `python -m unittest tests.test_xxx` 單獨驗收
- 測試檔放 `tests/`（要有 `tests/__init__.py`），測試資料用 `tempfile` 在測試中產生，不依賴外部檔案
- 不做圖表、不做資料庫、不裝第三方套件
