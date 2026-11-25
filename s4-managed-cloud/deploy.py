"""S4 排程部署（只印不做）：讀 deployment.json，印出 Windows schtasks 與 Linux cron 的寫法。

為什麼只支援 --dry-run：這是教材，看懂「排程＝每次開一個新 session」即可；
真的建立排程會讓電腦每天自動呼叫模型，要不要開由使用者自己決定。
正式雲端版對應 Anthropic Managed Agents 的 scheduled deployment（要 API 額度）。

用法（Git Bash，在 s4-managed-cloud 目錄）：
    PYTHONUTF8=1 python deploy.py --dry-run
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEPLOYMENT_PATH = HERE / "agents" / "price-report" / "deployment.json"


def load_deployment() -> dict:
    try:
        deployment = json.loads(DEPLOYMENT_PATH.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError) as exc:
        raise SystemExit(f"錯誤：讀不到 {DEPLOYMENT_PATH}：{exc}") from exc
    minute, hour, *_ = deployment["schedule"]["expression"].split()
    if not (minute.isdigit() and hour.isdigit()):
        raise SystemExit("錯誤：本範例只支援「每天固定時刻」的 cron（例如 0 8 * * *）")
    deployment["_hhmm"] = f"{int(hour):02d}:{int(minute):02d}"
    return deployment


def windows_command(deployment: dict) -> str:
    # 路徑用 %USERPROFILE%，換電腦不用改；Git Bash 下要加 MSYS_NO_PATHCONV=1，否則 /Create 會被轉成路徑
    workdir = r"%USERPROFILE%\workspace\kindle-903-quickstarts-samples\s4-managed-cloud"
    action = f'cmd /c "cd /d {workdir} && set PYTHONUTF8=1 && python run_session.py >> runs\\schedule.log 2>&1"'
    return (f'MSYS_NO_PATHCONV=1 schtasks /Create /TN "{deployment["task_name"]}" /SC DAILY '
            f'/ST {deployment["_hhmm"]} /TR \'{action}\' /F')


def cron_line(deployment: dict) -> str:
    workdir = "$HOME/workspace/kindle-903-quickstarts-samples/s4-managed-cloud"
    return (f'CRON_TZ={deployment["schedule"]["timezone"]}\n'
            f'{deployment["schedule"]["expression"]} cd {workdir} && PYTHONUTF8=1 python3 run_session.py '
            '>> runs/schedule.log 2>&1')


def main() -> int:
    parser = argparse.ArgumentParser(description="印出排程指令（不建立排程）")
    parser.add_argument("--dry-run", action="store_true", help="只印出指令（本範例唯一支援的模式）")
    args = parser.parse_args()
    if not args.dry_run:
        print("本範例只支援 --dry-run：不會真的建立排程。請加上 --dry-run。", file=sys.stderr)
        return 2
    deployment = load_deployment()
    print(f"[dry-run] 代理 {deployment['agent']}：{deployment['schedule']['timezone']} 每天 {deployment['_hhmm']} 開一個新 session\n")
    print("Windows（Git Bash）建立排程：")
    print("  " + windows_command(deployment))
    print(f'  查看：MSYS_NO_PATHCONV=1 schtasks /Query /TN "{deployment["task_name"]}"')
    print(f'  刪除：MSYS_NO_PATHCONV=1 schtasks /Delete /TN "{deployment["task_name"]}" /F\n')
    print("Linux／VPS（crontab -e 加入）：")
    print("  " + cron_line(deployment).replace("\n", "\n  "))
    print("\n雲端正式版（Anthropic scheduled deployment，要 API 額度，本範例不呼叫）：")
    print(f"  schedule: {{type: cron, expression: \"{deployment['schedule']['expression']}\", "
          f"timezone: {deployment['schedule']['timezone']}}}")
    print(f"  備註：{deployment['budget_note']}")
    print("\n[dry-run] 沒有建立任何排程。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
