import contextlib
import io
import os
import tempfile
import unittest

import ledger


def rec(date, category, amount):
    return {"date": date, "category": category, "amount": float(amount)}


EXPECTED_SAMPLE = [
    "== 各分類合計 ==",
    "交通    35.00",
    "餐飲    205.50",
    "== 每月總計 ==",
    "2026-10    155.00",
    "2026-11    85.50",
    "總計    240.50",
]


def lines_of(report):
    return report.rstrip("\n").split("\n")


class TestFormatReport(unittest.TestCase):
    def test_spec_example(self):
        records = [
            rec("2026-10-03", "餐飲", 120),
            rec("2026-10-05", "交通", 35),
            rec("2026-11-01", "餐飲", 85.5),
        ]
        report = ledger.format_report(records)
        self.assertIsInstance(report, str)
        self.assertEqual(lines_of(report), EXPECTED_SAMPLE)

    def test_sorting_and_two_decimals(self):
        records = [
            rec("2026-01-15", "交通", 10),
            rec("2025-12-31", "餐飲", 0.5),
            rec("2026-01-02", "餐飲", 1234.567),
            rec("2025-12-01", "娛樂", 100),
        ]
        report = ledger.format_report(records)
        self.assertEqual(lines_of(report), [
            "== 各分類合計 ==",
            "交通    10.00",
            "娛樂    100.00",
            "餐飲    1235.07",
            "== 每月總計 ==",
            "2025-12    100.50",
            "2026-01    1244.57",
            "總計    1345.07",
        ])

    def test_with_load_records(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "data.csv")
            with open(path, "w", encoding="utf-8", newline="") as f:
                f.write(
                    "date,category,amount\n"
                    "2026-10-03,餐飲,120\n"
                    "2026-10-05,交通,35\n"
                    "bad-date,餐飲,999\n"
                    "2026-11-01,餐飲,85.5\n"
                )
            with contextlib.redirect_stderr(io.StringIO()):
                records = ledger.load_records(path)
        self.assertEqual(lines_of(ledger.format_report(records)), EXPECTED_SAMPLE)


if __name__ == "__main__":
    unittest.main()
