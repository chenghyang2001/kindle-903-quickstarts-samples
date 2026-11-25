"""S2 冒煙測試：背景啟動 server.py，打 3 個請求（2 次會呼叫模型），測完一定關掉伺服器。

用法（Git Bash，在本資料夾）：PYTHONUTF8=1 python smoke_test.py [--port 8903]
模型呼叫：2 次（知識庫內 1 題、知識庫外 1 題）；空字串那題在伺服器端就擋下，不會呼叫模型。
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
CASES = [
    ("知識庫內", "DR-800 最大載重多少？充電到九成要多久？", 200, False),
    ("知識庫外", "你們公司有賣掃地機器人嗎？可以幫我訂高鐵票嗎？", 200, True),
    ("空字串", "   ", 400, None),
]


def post(url: str, question: str) -> tuple[int, dict]:
    """用 urllib 送 POST；4xx 也讀回 JSON 內容，方便印出錯誤訊息。"""
    data = json.dumps({"question": question}, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=240) as res:
            return res.status, json.loads(res.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        return exc.code, json.loads(exc.read().decode("utf-8"))


def wait_ready(base_url: str, seconds: int = 15) -> None:
    """輪詢首頁直到伺服器能回應；逾時丟 RuntimeError。"""
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(base_url + "/", timeout=2):
                return
        except (urllib.error.URLError, ConnectionError):
            time.sleep(0.5)
    raise RuntimeError("伺服器啟動逾時")


def run_cases(base_url: str) -> int:
    """跑全部案例，印實際輸出，回傳失敗數。"""
    failures = 0
    for label, question, want_status, want_human in CASES:
        started = time.monotonic()
        status, body = post(base_url + "/api/ask", question)
        ok = status == want_status and (want_human is None or body.get("needs_human") is want_human)
        failures += 0 if ok else 1
        print(f"[{'PASS' if ok else 'FAIL'}] {label}（{time.monotonic() - started:.1f} 秒）HTTP {status}")
        print("       " + json.dumps(body, ensure_ascii=False))
    return failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8903)
    args = parser.parse_args()
    base_url = f"http://127.0.0.1:{args.port}"
    env = {**os.environ, "PYTHONUTF8": "1"}
    server = subprocess.Popen([sys.executable, str(BASE_DIR / "server.py"), "--port", str(args.port)], env=env)
    try:
        wait_ready(base_url)
        failures = run_cases(base_url)
    except (RuntimeError, OSError, json.JSONDecodeError) as exc:
        print(f"錯誤：{exc}", file=sys.stderr)
        failures = 1
    finally:
        server.terminate()   # 一定關掉，避免 8903 被殘留行程佔住
        try:
            server.wait(timeout=10)
        except subprocess.TimeoutExpired:
            server.kill()
    print(f"結果：{'全部通過' if failures == 0 else f'{failures} 項失敗'}（模型呼叫 2 次）")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
