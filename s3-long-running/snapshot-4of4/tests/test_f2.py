import unittest

import ledger


def rec(date, category, amount):
    return {"date": date, "category": category, "amount": float(amount)}


SAMPLE = [
    rec("2026-10-03", "餐飲", 120),
    rec("2026-10-05", "交通", 35),
    rec("2026-11-01", "餐飲", 85.5),
]


class TestSumByCategory(unittest.TestCase):
    def test_sample(self):
        result = ledger.sum_by_category(SAMPLE)
        self.assertIsInstance(result, dict)
        self.assertEqual(set(result.keys()), {"餐飲", "交通"})
        self.assertAlmostEqual(result["餐飲"], 205.5)
        self.assertAlmostEqual(result["交通"], 35.0)
        for v in result.values():
            self.assertIsInstance(v, float)

    def test_empty(self):
        self.assertEqual(ledger.sum_by_category([]), {})

    def test_many_categories(self):
        records = [
            rec("2026-01-01", "A", 1.25),
            rec("2026-02-01", "B", 2),
            rec("2026-03-01", "A", 3.75),
            rec("2026-03-02", "C", 0.1),
        ]
        result = ledger.sum_by_category(records)
        self.assertEqual(set(result.keys()), {"A", "B", "C"})
        self.assertAlmostEqual(result["A"], 5.0)
        self.assertAlmostEqual(result["B"], 2.0)
        self.assertAlmostEqual(result["C"], 0.1)


class TestSumByMonth(unittest.TestCase):
    def test_sample(self):
        result = ledger.sum_by_month(SAMPLE)
        self.assertIsInstance(result, dict)
        self.assertEqual(set(result.keys()), {"2026-10", "2026-11"})
        self.assertAlmostEqual(result["2026-10"], 155.0)
        self.assertAlmostEqual(result["2026-11"], 85.5)
        for v in result.values():
            self.assertIsInstance(v, float)

    def test_empty(self):
        self.assertEqual(ledger.sum_by_month([]), {})

    def test_key_format_and_year_boundary(self):
        records = [
            rec("2025-12-31", "餐飲", 10),
            rec("2026-01-01", "餐飲", 20),
            rec("2026-01-31", "交通", 5.5),
        ]
        result = ledger.sum_by_month(records)
        self.assertEqual(set(result.keys()), {"2025-12", "2026-01"})
        self.assertAlmostEqual(result["2025-12"], 10.0)
        self.assertAlmostEqual(result["2026-01"], 25.5)
        for k in result:
            self.assertRegex(k, r"^\d{4}-\d{2}$")


if __name__ == "__main__":
    unittest.main()
