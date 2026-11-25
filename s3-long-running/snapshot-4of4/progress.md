# 進度筆記（每個 session 由 harness 追加）

## Session 1：初始化

寫入：tests/__init__.py, tests/test_f1.py, tests/test_f2.py, tests/test_f3.py, tests/test_f4.py

已完成：把規格切成 F1～F4 四項功能，並寫好 tests/__init__.py 與 tests/test_f1.py～test_f4.py。ledger.py 還沒寫，請在專案根目錄建立 ledger.py（測試用 import ledger 載入，所以請從根目錄執行 python -m unittest tests.test_xxx）。建議依序實作：F1 load_records → F2 sum_by_category/sum_by_month → F3 format_report → F4 CLI。實作重點：(1) 以 encoding='utf-8'、newline='' 開檔，用 csv 模組讀取並跳過表頭。(2) 日期用 datetime.strptime(s, '%Y-%m-%d') 驗證，所以 2026-02-30、2026/10/03 都算不合法。amount 一律轉成 float；空字串或非數字要略過。欄位不足的列也略過。每一列錯誤都用 print(..., file=sys.stderr) 印警告，要在呼叫當下寫到 sys.stderr，因為測試用 redirect_stderr 擷取。檔案全部合法時不要印任何警告。(3) 報表每列格式是『名稱 + 4 個空白 + f"{x:.2f}"』，總計列是『總計    xxx.xx』。分類與月份都直接用 sorted() 排序。結尾可以有一個換行，但不要有多餘的空白或空行。(4) CLI 要用 if __name__ == '__main__': 包起來，import 時不能執行。檔案不存在時捕捉 FileNotFoundError（或先檢查路徑），印錯誤到 stderr 後 sys.exit(1)，不能露出 traceback。(5) 測試在 Windows 上會設定 PYTHONIOENCODING=utf-8 執行子程序。

## Session 2：F1 通過

寫入：ledger.py

F1 完成：ledger.py 已有 load_records（utf-8-sig 讀檔、跳過表頭、略過空白列，錯誤列印「警告：…」到 stderr，檔案不存在會丟 FileNotFoundError 給 CLI 處理）。下一棒請在 ledger.py 加 F2 的 sum_by_category / sum_by_month。

## Session 3：F2 通過

寫入：ledger.py

F2 完成：ledger.py 新增 sum_by_category / sum_by_month（月份鍵取 date[:7]，值一律 float，空清單回傳 {}）。下一棒做 F3 format_report，可直接用這兩個函式並以 sorted() 排序鍵。

## Session 4：F3 通過

寫入：ledger.py

F3 完成：format_report 回傳以單一換行結尾的報表字串（各行為『名稱 + 4 空白 + .2f 金額』）。下一棒做 F4：在 if __name__ == '__main__': 中讀 sys.argv[1]，捕捉 FileNotFoundError 印錯誤到 stderr 並 sys.exit(1)，否則 print(format_report(...), end='')。

## Session 5：F4 通過

寫入：ledger.py

F4 完成：ledger.py 新增 main(argv) 回傳結束碼（成功 0、檔案不存在或無法讀取 1、參數數量錯誤 2），只在 if __name__ == '__main__': 中呼叫 sys.exit(main())，import 時不會執行；錯誤訊息印到 stderr，不顯示 traceback。F1～F4 應該已全部完成。
