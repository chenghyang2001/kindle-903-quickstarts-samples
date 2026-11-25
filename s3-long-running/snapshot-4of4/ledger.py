"""記帳 CSV 月統計 CLI（ledger）。只用 Python 3 標準庫。"""

import csv
import sys
from datetime import datetime


def _warn(msg):
    # 在呼叫當下寫到 sys.stderr（測試用 redirect_stderr 擷取）
    print(f"警告：{msg}", file=sys.stderr)


def load_records(path):
    """讀取 date,category,amount 格式的 CSV，回傳記錄清單（保留原順序）。

    日期不合法、金額不是數字或欄位不足的列會被略過，並印警告到 stderr。
    檔案不存在時會丟出 FileNotFoundError（交給 CLI 處理）。
    """
    records = []
    with open(path, encoding="utf-8-sig", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        if header is None:
            return records
        for row in reader:
            lineno = reader.line_num
            if not row or all(not cell.strip() for cell in row):
                # 空白列：直接略過
                continue
            if len(row) < 3:
                _warn(f"第 {lineno} 列欄位不足，已略過：{row!r}")
                continue
            date_s = row[0].strip()
            category = row[1].strip()
            amount_s = row[2].strip()
            try:
                datetime.strptime(date_s, "%Y-%m-%d")
            except ValueError:
                _warn(f"第 {lineno} 列日期不合法，已略過：{date_s!r}")
                continue
            try:
                amount = float(amount_s)
            except ValueError:
                _warn(f"第 {lineno} 列金額不是數字，已略過：{amount_s!r}")
                continue
            records.append({"date": date_s, "category": category, "amount": amount})
    return records


def sum_by_category(records):
    """依分類加總金額，回傳 dict[str, float]。"""
    totals = {}
    for r in records:
        cat = r["category"]
        totals[cat] = totals.get(cat, 0.0) + float(r["amount"])
    return totals


def sum_by_month(records):
    """依 YYYY-MM 加總金額，回傳 dict[str, float]。"""
    totals = {}
    for r in records:
        month = r["date"][:7]
        totals[month] = totals.get(month, 0.0) + float(r["amount"])
    return totals


SEP = "    "  # 名稱與金額之間固定 4 個空白


def format_report(records):
    """組出報表文字：各分類合計（依名稱排序）、每月總計（依時間排序）與總計。"""
    by_cat = sum_by_category(records)
    by_month = sum_by_month(records)
    total = sum(float(r["amount"]) for r in records)

    lines = ["== 各分類合計 =="]
    for cat in sorted(by_cat):
        lines.append(f"{cat}{SEP}{by_cat[cat]:.2f}")
    lines.append("== 每月總計 ==")
    for month in sorted(by_month):
        lines.append(f"{month}{SEP}{by_month[month]:.2f}")
    lines.append(f"總計{SEP}{total:.2f}")
    return "\n".join(lines) + "\n"


def main(argv=None):
    """CLI 進入點，回傳結束碼。"""
    if argv is None:
        argv = sys.argv[1:]
    if len(argv) != 1:
        print("用法：python ledger.py <csv 路徑>", file=sys.stderr)
        return 2
    path = argv[0]
    try:
        records = load_records(path)
    except FileNotFoundError:
        print(f"錯誤：找不到檔案：{path}", file=sys.stderr)
        return 1
    except OSError as e:
        print(f"錯誤：無法讀取檔案：{path}（{e}）", file=sys.stderr)
        return 1
    except UnicodeDecodeError:
        print(f"錯誤：檔案不是 UTF-8 編碼：{path}", file=sys.stderr)
        return 1
    sys.stdout.write(format_report(records))
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
