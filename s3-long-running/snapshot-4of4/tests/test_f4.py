import os
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEDGER = os.path.join(ROOT, "ledger.py")

EXPECTED_SAMPLE = [
    "== 各分類合計 ==",
    "交通    35.00",
    "餐飲    205.50",
    "== 每月總計 ==",
    "2026-10    155.00",
    "2026-11    85.50",
    "總計    240.50",
]


def run_cli(*args):
    env = dict(os.environ)
    env["PYTHONIOENCODING"] = "utf-8"
    env["PYTHONUTF8"] = "1"
    proc = subprocess.run(
        [sys.executable, LEDGER] + list(args),
        cwd=ROOT,
        env=env,
        capture_output=True,
        timeout=30,
    )
    out = proc.stdout.decode("utf-8").replace("\r\n", "\n")
    err = proc.stderr.decode("utf-8", errors="replace")
    return proc.returncode, out, err


def lines_of(text):
    return text.rstrip("\n").split("\n")


class TestCLI(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmpdir = self._tmp.name

    def tearDown(self):
        self._tmp.cleanup()

    def write(self, text):
        path = os.path.join(self.tmpdir, "data.csv")
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write(text)
        return path

    def test_spec_example(self):
        path = self.write(
            "date,category,amount\n"
            "2026-10-03,餐飲,120\n"
            "2026-10-05,交通,35\n"
            "2026-11-01,餐飲,85.5\n"
        )
        code, out, err = run_cli(path)
        self.assertEqual(code, 0, err)
        self.assertEqual(lines_of(out), EXPECTED_SAMPLE)

    def test_bad_rows_warn_on_stderr_only(self):
        path = self.write(
            "date,category,amount\n"
            "2026-10-03,餐飲,120\n"
            "2026-13-01,餐飲,1\n"
            "2026-10-05,交通,35\n"
            "2026-10-06,交通,abc\n"
            "2026-10-07,交通\n"
            "2026-11-01,餐飲,85.5\n"
        )
        code, out, err = run_cli(path)
        self.assertEqual(code, 0, err)
        self.assertEqual(lines_of(out), EXPECTED_SAMPLE)
        self.assertNotEqual(err.strip(), "")

    def test_missing_file(self):
        missing = os.path.join(self.tmpdir, "no_such_file.csv")
        code, out, err = run_cli(missing)
        self.assertEqual(code, 1)
        self.assertNotEqual(err.strip(), "")
        self.assertNotIn("Traceback", err)
        self.assertNotIn("總計", out)


if __name__ == "__main__":
    unittest.main()
