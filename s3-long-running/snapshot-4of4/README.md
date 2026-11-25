# snapshot-4of4：S3 workdir 的 4/4 完成版快照

## 這是什麼

`s3-long-running/workdir/` 是 harness 產出的資料夾，本身是一個獨立的 git repo，外層 `.gitignore` 排除了它（`*/workdir/`），所以換電腦 clone 之後不會有 workdir。

這個資料夾是 2026-11-25 冒煙測試跑出來的 4/4 完成版（workdir 的 HEAD 是 `a1bc69b`），去掉 `.git/` 與 `__pycache__/` 之後的工作樹，讓新電腦**不呼叫模型**也能演練 S3 的第 3、4、7 步與 `restore`。

| 檔案 | 用途 |
| --- | --- |
| `feature_list.json`、`progress.md`、`ledger.py`、`tests/`、`.gitignore` | workdir 工作樹的原樣複本 |
| `git-log.txt` | 原本 workdir 的 `git log --oneline`（5 個 commit）。重建出來的 workdir 只有 1 個 commit，第 3 步會改顯示這份 |
| `README.md` | 本說明（重建時不會複製進 workdir） |

## 怎麼還原

在 `practice/interactive/` 底下：

```bash
bash s3.sh seed
```

它會把本資料夾的檔案（`README.md`、`git-log.txt` 除外）複製成 `s3-long-running/workdir/`，接著 `git init`，再用一個 commit 提交全部檔案，commit 訊息是「從 snapshot-4of4 重建…」。

- workdir 已經存在時什麼都不做，只印提示。
- 不跑 seed 也可以：第 3、4、7 步與 `restore` 發現 workdir 和 `workdir.bak-4of4` 都不存在時，會自動重建。

## 跟原本 workdir 的差別

- git 歷史只有 1 個 commit，原本的 5 個 commit 只留在 `git-log.txt` 裡，不能 `git checkout` 回到中間的存檔點。
- 其他檔案內容相同。Windows 上 git 的換行轉換（`core.autocrlf`）可能讓換行字元不同，但不影響執行與測試。
