import contextlib
import io
import os
import tempfile
import unittest

import ledger


def write_csv(dirpath, text, name="data.csv"):
    path = os.path.join(dirpath, name)
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(text)
    return path


class TestLoadRecords(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmpdir = self._tmp.name

    def tearDown(self):
        self._tmp.cleanup()

    def load(self, text):
        path = write_csv(self.tmpdir, text)
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            records = ledger.load_records(path)
        return records, err.getvalue()

    def test_valid_rows(self):
        records, err = self.load(
            "date,category,amount\n"
            "2026-10-03,餐飲,120\n"
            "2026-10-05,交通,35\n"
            "2026-11-01,餐飲,85.5\n"
        )
        self.assertIsInstance(records, list)
        self.assertEqual(records, [
            {"date": "2026-10-03", "category": "餐飲", "amount": 120.0},
            {"date": "2026-10-05", "category": "交通", "amount": 35.0},
            {"date": "2026-11-01", "category": "餐飲", "amount": 85.5},
        ])
        for r in records:
            self.assertIsInstance(r, dict)
            self.assertEqual(set(r.keys()), {"date", "category", "amount"})
            self.assertIsInstance(r["date"], str)
            self.assertIsInstance(r["category"], str)
            self.assertIsInstance(r["amount"], float)
        self.assertEqual(err.strip(), "")

    def test_header_only(self):
        records, _ = self.load("date,category,amount\n")
        self.assertEqual(records, [])

    def test_invalid_dates_skipped(self):
        records, err = self.load(
            "date,category,amount\n"
            "2026-13-01,餐飲,10\n"
            "2026-02-30,餐飲,10\n"
            "2026/10/03,餐飲,10\n"
            "abc,餐飲,10\n"
            "2026-10-03,交通,20\n"
        )
        self.assertEqual(records, [
            {"date": "2026-10-03", "category": "交通", "amount": 20.0},
        ])
        self.assertNotEqual(err.strip(), "")

    def test_invalid_amount_skipped(self):
        records, err = self.load(
            "date,category,amount\n"
            "2026-10-01,餐飲,abc\n"
            "2026-10-02,餐飲,\n"
            "2026-10-03,餐飲,12.5\n"
        )
        self.assertEqual(records, [
            {"date": "2026-10-03", "category": "餐飲", "amount": 12.5},
        ])
        self.assertNotEqual(err.strip(), "")

    def test_missing_fields_skipped(self):
        records, err = self.load(
            "date,category,amount\n"
            "2026-10-01,餐飲\n"
            "2026-10-02\n"
            "2026-10-03,娛樂,300\n"
        )
        self.assertEqual(records, [
            {"date": "2026-10-03", "category": "娛樂", "amount": 300.0},
        ])
        self.assertNotEqual(err.strip(), "")

    def test_order_preserved(self):
        records, _ = self.load(
            "date,category,amount\n"
            "2026-12-01,B,1\n"
            "2026-01-01,A,2\n"
            "2026-06-01,C,3\n"
        )
        self.assertEqual([r["date"] for r in records],
                         ["2026-12-01", "2026-01-01", "2026-06-01"])


if __name__ == "__main__":
    unittest.main()
