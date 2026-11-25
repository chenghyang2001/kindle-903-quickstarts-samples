"""S5 瀏覽器讀價代理：模型看頁面狀態決定下一步，Playwright 執行，結果回給模型。

模仿官方 browser-use-demo（K902 第 4～5 章）的「看 → 想 → 做」迴圈，但模型走 claude -p（Max 訂閱）。
用法（在本資料夾）：
    PYTHONUTF8=1 python price_agent.py                       跑預設目標（找 GS-108 最低價）
    PYTHONUTF8=1 python price_agent.py --goal "找出 ... 最低價"
    PYTHONUTF8=1 python price_agent.py --check-allowlist     不呼叫模型，只測白名單會擋外部網址
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "shared"))
from llm_agent import ask, extract_json

from browser_tools import BrowserTools, PracticeSite, ToolError

HERE = Path(__file__).resolve().parent
DEFAULT_GOAL = "找出「NetLink GS-108 8 埠 Gigabit 交換器」的最低價和賣家"
MAX_STEPS = 8
SYSTEM_PROMPT = """你是瀏覽器操作代理。每一回合你會收到目標、之前的動作紀錄、目前頁面（可見文字＋編號元素）。
你只能回一個 JSON 物件，從下列擇一：
{"action": "navigate", "url": "..."}
{"action": "read_page"}
{"action": "click", "element_id": 編號}
{"action": "type", "element_id": 編號, "text": "..."}
{"action": "screenshot"}
{"final": {"product": "...", "price": "...", "seller": "..."}}
規則：一次只做一個動作；編號只用目前頁面列出的；確定答案後立刻回 final；不要編造頁面上沒有的資料。"""


def build_prompt(goal: str, history: list[str], page_state: str, step: int) -> str:
    done = "\n".join(history) or "（尚無）"
    return f"目標：{goal}\n第 {step}/{MAX_STEPS} 步。\n之前的動作：\n{done}\n\n目前頁面：\n{page_state}"


def run_action(tools: BrowserTools, decision: dict, step: int) -> str:
    """把模型的 JSON 動作派給對應工具；工具錯誤轉成文字回給模型，不中斷迴圈。"""
    action = decision.get("action")
    try:
        if action == "navigate":
            return tools.navigate(str(decision.get("url", "")))
        if action == "read_page":
            return "已重新讀取頁面（下一步會看到最新狀態）"
        if action == "click":
            return tools.click(int(decision["element_id"]))
        if action == "type":
            return tools.type(int(decision["element_id"]), str(decision.get("text", "")))
        if action == "screenshot":
            return f"已截圖 {tools.screenshot(step)}"
        return f"錯誤：不認得的動作 {action!r}"
    except ToolError as exc:
        return f"錯誤：{exc}"
    except (KeyError, ValueError, TypeError) as exc:
        return f"錯誤：動作參數不正確（{exc}）"


def agent_loop(tools: BrowserTools, goal: str, start_url: str) -> tuple[dict | None, int]:
    """主迴圈：回傳（最終答案或 None, 模型呼叫次數）。"""
    print(f"起始：{tools.navigate(start_url)}")
    history: list[str] = []
    for step in range(1, MAX_STEPS + 1):
        reply = ask(build_prompt(goal, history, tools.read_page(), step), system=SYSTEM_PROMPT)
        try:
            decision = extract_json(reply)
        except ValueError as exc:
            history.append(f"第 {step} 步：（回覆不是 JSON）→ {exc}")
            print(history[-1])
            continue
        if "final" in decision:
            print(f"第 {step} 步：final → {json.dumps(decision['final'], ensure_ascii=False)}")
            return decision["final"], step
        result = run_action(tools, decision, step)
        tools.screenshot(step)  # 每步留一張圖，方便事後對照模型看到什麼
        history.append(f"第 {step} 步：{json.dumps(decision, ensure_ascii=False)} → {result}")
        print(history[-1])
    return None, MAX_STEPS


def check_allowlist(tools: BrowserTools) -> int:
    """不呼叫模型：確認外部網址會被白名單擋下。"""
    for url in ("https://shopee.tw/", "file:///C:/Windows/win.ini"):
        try:
            tools.navigate(url)
            print(f"失敗：{url} 沒有被擋下")
            return 1
        except ToolError as exc:
            print(f"已擋下：{exc}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="S5 瀏覽器讀價代理（練習網站）")
    parser.add_argument("--goal", default=DEFAULT_GOAL)
    parser.add_argument("--check-allowlist", action="store_true")
    args = parser.parse_args()
    run_dir = HERE / "runs" / datetime.now().strftime("%Y%m%d-%H%M%S")
    run_dir.mkdir(parents=True, exist_ok=True)
    with PracticeSite(HERE / "site") as site:
        host = site.base_url.split("/")[2]
        print(f"練習網站：{site.base_url}（白名單只有 {host}）")
        tools = BrowserTools({host}, run_dir)
        try:
            if args.check_allowlist:
                return check_allowlist(tools)
            final, calls = agent_loop(tools, args.goal, site.base_url + "index.html")
        except RuntimeError as exc:  # claude -p 失敗、逾時
            print(f"錯誤：{exc}", file=sys.stderr)
            return 1
        finally:
            tools.close()
    print(f"\n最終答案：{json.dumps(final, ensure_ascii=False) if final else '（8 步內沒有答案）'}")
    print(f"模型呼叫次數：{calls}")
    print("截圖：" + ", ".join(p.name for p in sorted(run_dir.glob("*.png"))))
    (run_dir / "result.json").write_text(json.dumps({"goal": args.goal, "final": final, "model_calls": calls},
                                                     ensure_ascii=False, indent=2), encoding="utf-8")
    return 0 if final else 2


if __name__ == "__main__":
    sys.exit(main())
