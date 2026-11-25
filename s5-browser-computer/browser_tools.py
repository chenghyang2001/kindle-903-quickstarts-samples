"""S5 瀏覽器工具組：用 Playwright 無頭 Chromium 實作 navigate／read_page／click／type／screenshot。

模仿官方 browser-toolset（K902 第 4 章）：工具是「DOM 層」的，模型拿到的是帶編號的元素清單，
不是螢幕截圖座標。編號存在頁面的 data-agent-id 屬性上，換頁就失效，要重新 read_page。

同檔附練習網站伺服器 PracticeSite（http.server，只綁 127.0.0.1）。
"""
from __future__ import annotations

import functools
import threading
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urljoin, urlparse

from playwright.sync_api import Error as PlaywrightError
from playwright.sync_api import sync_playwright

MAX_TEXT_CHARS = 1500
# 在頁面裡替可互動元素編號；回傳編號清單給 Python
MARK_ELEMENTS_JS = """
() => {
  const sel = 'a, button, input, select, textarea';
  const out = [];
  document.querySelectorAll(sel).forEach((el) => {
    const r = el.getBoundingClientRect();
    if (r.width === 0 || r.height === 0) return;  // 隱藏的元素不給模型看
    const id = out.length + 1;
    el.setAttribute('data-agent-id', String(id));
    const label = (el.innerText || el.value || el.placeholder || el.name || '').trim();
    out.push({id, tag: el.tagName.toLowerCase(), type: el.type || '', label: label.slice(0, 60)});
  });
  return out;
}
"""


class ToolError(Exception):
    """工具執行失敗：訊息會原樣回給模型，讓它自己修正（官方範例同樣做法）。"""


class _QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        # 為什麼關掉：每個請求都印一行會淹沒「第 N 步」的輸出
        return


class PracticeSite:
    """在背景執行緒啟動練習網站；port=0 讓作業系統挑空的埠，避免撞埠。"""

    def __init__(self, root: Path, port: int = 0):
        handler = functools.partial(_QuietHandler, directory=str(root))
        self.server = ThreadingHTTPServer(("127.0.0.1", port), handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    @property
    def base_url(self) -> str:
        host, port = self.server.server_address[:2]
        return f"http://{host}:{port}/"

    def __enter__(self) -> PracticeSite:
        self.thread.start()
        return self

    def __exit__(self, *exc) -> None:
        self.server.shutdown()
        self.server.server_close()


class BrowserTools:
    """五個瀏覽器工具。allowed_hosts 是白名單，navigate 只放行這些 host:port。"""

    def __init__(self, allowed_hosts: set[str], shot_dir: Path):
        self.allowed_hosts = allowed_hosts
        self.shot_dir = shot_dir
        self._pw = sync_playwright().start()
        self._browser = self._pw.chromium.launch(headless=True)
        self.page = self._browser.new_page(viewport={"width": 1000, "height": 700})

    def close(self) -> None:
        try:
            self._browser.close()
        finally:
            self._pw.stop()

    def check_url(self, url: str) -> None:
        """白名單政策：放行就什麼都不做，不放行就丟 ToolError（模仿官方 policy 函式）。"""
        parsed = urlparse(url)
        if parsed.scheme not in ("http", "https") or parsed.netloc not in self.allowed_hosts:
            raise ToolError(f"網址不在白名單，拒絕前往：{url}（只允許 {sorted(self.allowed_hosts)}）")

    def navigate(self, url: str) -> str:
        self.check_url(url)
        try:
            self.page.goto(url, wait_until="load", timeout=10_000)
        except PlaywrightError as exc:
            raise ToolError(f"開啟失敗：{exc}") from exc
        return f"已開啟 {self.page.url}"

    def read_page(self) -> str:
        """精簡可見文字＋編號元素清單；文字截斷避免把整頁塞給模型。"""
        elements = self.page.evaluate(MARK_ELEMENTS_JS)
        text = self.page.inner_text("body").strip()[:MAX_TEXT_CHARS]
        lines = [f"網址：{self.page.url}", f"標題：{self.page.title()}", "可見文字：", text, "可互動元素："]
        lines += [f"[{e['id']}] <{e['tag']} {e['type']}> {e['label']}" for e in elements]
        return "\n".join(lines)

    def _locate(self, element_id: int):
        loc = self.page.locator(f"[data-agent-id='{int(element_id)}']")
        if loc.count() == 0:
            raise ToolError(f"找不到元素 {element_id}，編號可能已因換頁失效，請重新 read_page")
        return loc.first

    def click(self, element_id: int) -> str:
        target = self._locate(element_id)
        href = target.get_attribute("href")
        if href:
            # 點連結前也過白名單：避免模型繞過 navigate 直接點到外站
            self.check_url(urljoin(self.page.url, href))
        target.click(timeout=5_000)
        self.page.wait_for_load_state("load")
        return f"已點擊元素 {element_id}，目前網址 {self.page.url}"

    def type(self, element_id: int, text: str) -> str:
        self._locate(element_id).fill(str(text), timeout=5_000)
        return f"已在元素 {element_id} 輸入「{text}」"

    def screenshot(self, step: int) -> str:
        path = self.shot_dir / f"step-{step}.png"
        self.page.screenshot(path=str(path))
        return str(path)
