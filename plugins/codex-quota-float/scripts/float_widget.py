#!/usr/bin/env python3
"""Always-on-top compact desktop widget for official Codex quota status."""

from __future__ import annotations

import argparse
import ctypes
import datetime as dt
import json
import os
import subprocess
import sys
import threading
import tkinter as tk
import urllib.error
import urllib.request
import webbrowser
from pathlib import Path

from collect_status import collect_status


PANEL_URL = "http://127.0.0.1:17447/"
PLUGIN_ROOT = Path(__file__).resolve().parents[1]
PID_FILE = Path.home() / ".codex" / "quota-float-widget.pid"
POSITION_FILE = Path.home() / ".codex" / "quota-float-position.json"
ERROR_LOG = Path.home() / ".codex" / "quota-float-widget.log"

COMPACT_SIZE = 64
EXPANDED_WIDTH = 244
EXPANDED_HEIGHT = 64
TRANSPARENT = "#FF00FF"
SURFACE = "#FAFBFB"
INK = "#172127"
MUTED = "#68727C"
LINE = "#D3D9DC"
TRACK = "#DFE4E6"
GREEN = "#1C8F72"
AMBER = "#D99A2B"
RED = "#C94B4B"
STALE = "#8A9299"


def percent_text(value: object) -> str:
    if value is None:
        return "--"
    try:
        return f"{float(value):.0f}%"
    except (TypeError, ValueError):
        return "--"


def enable_dpi_awareness() -> None:
    if os.name != "nt":
        return
    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(2)
    except (AttributeError, OSError):
        try:
            ctypes.windll.user32.SetProcessDPIAware()
        except (AttributeError, OSError):
            pass


def ensure_panel_server() -> None:
    try:
        with urllib.request.urlopen(PANEL_URL + "api/status", timeout=1.2) as response:
            if response.status == 200:
                return
    except (OSError, urllib.error.URLError):
        pass

    python_exe = Path(sys.executable)
    if python_exe.name.lower() == "pythonw.exe":
        candidate = python_exe.with_name("python.exe")
        if candidate.exists():
            python_exe = candidate
    subprocess.Popen(
        [
            str(python_exe),
            str(PLUGIN_ROOT / "scripts" / "panel_server.py"),
            "--port",
            "17447",
        ],
        cwd=str(PLUGIN_ROOT),
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def primary_limit(limits: list[dict]) -> dict:
    available = [item for item in limits if item.get("remainingPercent") is not None]
    codex_limits = [item for item in available if item.get("limitId") == "codex"]
    candidates = codex_limits or available
    if not candidates:
        return limits[0] if limits else {}
    return min(candidates, key=lambda item: float(item.get("remainingPercent", 100)))


def quota_color(percent: object) -> str:
    if percent is None:
        return STALE
    numeric = max(0, min(100, float(percent)))
    if numeric >= 50:
        return GREEN
    if numeric >= 20:
        return AMBER
    return RED


def friendly_limit_label(item: dict) -> str:
    window = item.get("window") or "额度周期"
    if item.get("limitId") == "codex":
        return f"Codex 通用额度 · {window}"
    limit_name = str(item.get("limitName") or item.get("label") or "独立模型")
    if "spark" in limit_name.lower():
        return f"Spark 独立额度 · {window}"
    return f"{limit_name} 独立额度 · {window}"


def source_status_text(status: str | None) -> str:
    if status == "available":
        return "官方实时"
    if status == "stale":
        return "官方缓存"
    return "数据不可用"


def log_error(error: object) -> None:
    try:
        ERROR_LOG.parent.mkdir(parents=True, exist_ok=True)
        with ERROR_LOG.open("a", encoding="utf-8") as handle:
            handle.write(f"{dt.datetime.now().astimezone().isoformat()} {error}\n")
    except OSError:
        pass


class QuotaFloatWidget:
    def __init__(self, refresh_seconds: int) -> None:
        self.refresh_ms = max(30, refresh_seconds) * 1000
        self.status: dict = {}
        self.expanded = False
        self.detail_window: tk.Toplevel | None = None
        self.refresh_thread: threading.Thread | None = None
        self.refresh_result: dict | Exception | None = None
        self.next_refresh_job: str | None = None
        self.pending_click_job: str | None = None
        self.suppress_next_release = False
        self.dragged = False
        self.press_pointer_x = 0
        self.press_pointer_y = 0
        self.press_window_x = 0
        self.press_window_y = 0

        self.root = tk.Tk()
        self.root.title("Codex Quota Float")
        self.root.overrideredirect(True)
        self.root.attributes("-topmost", True)
        self.root.attributes("-alpha", 0.98)
        self.root.configure(bg=TRANSPARENT)
        try:
            self.root.attributes("-transparentcolor", TRANSPARENT)
        except tk.TclError:
            self.root.configure(bg=SURFACE)

        self.canvas = tk.Canvas(
            self.root,
            width=COMPACT_SIZE,
            height=COMPACT_SIZE,
            bg=TRANSPARENT,
            bd=0,
            highlightthickness=0,
            cursor="hand2",
        )
        self.canvas.pack(fill="both", expand=True)
        self.bind_pointer_events()

        self.menu = tk.Menu(self.root, tearoff=0)
        self.menu.add_command(label="展开 / 收起", command=self.toggle_expanded)
        self.menu.add_command(label="查看全部额度", command=self.show_details)
        self.menu.add_command(label="立即刷新", command=self.refresh)
        self.menu.add_command(label="打开网页面板", command=self.open_browser_panel)
        self.menu.add_separator()
        self.menu.add_command(label="退出悬浮窗", command=self.quit)

        self.apply_initial_geometry()
        self.draw()
        self.refresh()

    def bind_pointer_events(self) -> None:
        self.canvas.bind("<ButtonPress-1>", self.on_press)
        self.canvas.bind("<B1-Motion>", self.on_drag)
        self.canvas.bind("<ButtonRelease-1>", self.on_release)
        self.canvas.bind("<Double-Button-1>", self.on_double_click)
        self.canvas.bind("<Button-3>", self.show_menu)

    def screen_bounds(self, width: int, height: int, x: int, y: int) -> tuple[int, int]:
        max_x = max(0, self.root.winfo_screenwidth() - width)
        max_y = max(0, self.root.winfo_screenheight() - height)
        return max(0, min(max_x, x)), max(0, min(max_y, y))

    def load_anchor(self) -> tuple[int, int] | None:
        try:
            payload = json.loads(POSITION_FILE.read_text(encoding="utf-8"))
            return int(payload["right"]), int(payload["centerY"])
        except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError):
            return None

    def apply_initial_geometry(self) -> None:
        anchor = self.load_anchor()
        if anchor is None:
            right = self.root.winfo_screenwidth() - 42
            center_y = self.root.winfo_screenheight() - 120
        else:
            right, center_y = anchor
        x, y = self.screen_bounds(
            COMPACT_SIZE,
            COMPACT_SIZE,
            right - COMPACT_SIZE,
            center_y - COMPACT_SIZE // 2,
        )
        self.root.geometry(f"{COMPACT_SIZE}x{COMPACT_SIZE}+{x}+{y}")

    def save_position(self) -> None:
        try:
            width = EXPANDED_WIDTH if self.expanded else COMPACT_SIZE
            height = EXPANDED_HEIGHT if self.expanded else COMPACT_SIZE
            payload = {
                "right": self.root.winfo_x() + width,
                "centerY": self.root.winfo_y() + height // 2,
            }
            POSITION_FILE.parent.mkdir(parents=True, exist_ok=True)
            POSITION_FILE.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        except OSError as exc:
            log_error(exc)

    def on_press(self, event: tk.Event) -> None:
        self.dragged = False
        self.press_pointer_x = event.x_root
        self.press_pointer_y = event.y_root
        self.press_window_x = self.root.winfo_x()
        self.press_window_y = self.root.winfo_y()

    def on_drag(self, event: tk.Event) -> None:
        dx = event.x_root - self.press_pointer_x
        dy = event.y_root - self.press_pointer_y
        if abs(dx) > 3 or abs(dy) > 3:
            self.dragged = True
        width = EXPANDED_WIDTH if self.expanded else COMPACT_SIZE
        height = EXPANDED_HEIGHT if self.expanded else COMPACT_SIZE
        x, y = self.screen_bounds(width, height, self.press_window_x + dx, self.press_window_y + dy)
        self.root.geometry(f"+{x}+{y}")

    def on_release(self, _event: tk.Event) -> None:
        if self.dragged:
            self.save_position()
            return
        if self.suppress_next_release:
            self.suppress_next_release = False
            return
        if self.pending_click_job:
            self.root.after_cancel(self.pending_click_job)
        self.pending_click_job = self.root.after(230, self.perform_single_click)

    def perform_single_click(self) -> None:
        self.pending_click_job = None
        self.toggle_expanded()

    def on_double_click(self, _event: tk.Event) -> None:
        if self.pending_click_job:
            self.root.after_cancel(self.pending_click_job)
            self.pending_click_job = None
        self.suppress_next_release = True
        self.show_details()

    def show_menu(self, event: tk.Event) -> None:
        self.menu.tk_popup(event.x_root, event.y_root)

    def toggle_expanded(self) -> None:
        old_width = EXPANDED_WIDTH if self.expanded else COMPACT_SIZE
        old_height = EXPANDED_HEIGHT if self.expanded else COMPACT_SIZE
        right = self.root.winfo_x() + old_width
        center_y = self.root.winfo_y() + old_height // 2

        self.expanded = not self.expanded
        width = EXPANDED_WIDTH if self.expanded else COMPACT_SIZE
        height = EXPANDED_HEIGHT if self.expanded else COMPACT_SIZE
        x, y = self.screen_bounds(width, height, right - width, center_y - height // 2)
        self.canvas.configure(width=width, height=height)
        self.root.geometry(f"{width}x{height}+{x}+{y}")
        self.save_position()
        self.root.after_idle(self.draw)

    def refresh(self) -> None:
        if self.refresh_thread and self.refresh_thread.is_alive():
            return
        if self.next_refresh_job:
            self.root.after_cancel(self.next_refresh_job)
            self.next_refresh_job = None
        self.refresh_result = None
        self.refresh_thread = threading.Thread(target=self.collect_in_background, daemon=True)
        self.refresh_thread.start()
        self.root.after(100, self.poll_refresh)

    def collect_in_background(self) -> None:
        args = argparse.Namespace(config=None, cache=None, pretty=False)
        try:
            self.refresh_result = collect_status(args)
        except Exception as exc:  # pragma: no cover - desktop runtime guard
            self.refresh_result = exc

    def poll_refresh(self) -> None:
        if self.refresh_thread and self.refresh_thread.is_alive():
            self.root.after(100, self.poll_refresh)
            return
        if isinstance(self.refresh_result, dict):
            self.status = self.refresh_result
            self.draw()
            if self.detail_window and self.detail_window.winfo_exists():
                self.render_detail()
        elif isinstance(self.refresh_result, Exception):
            log_error(self.refresh_result)
        self.next_refresh_job = self.root.after(self.refresh_ms, self.refresh)

    def draw_ring(self, cx: int, cy: int, radius: int, percent: object, width: int) -> None:
        color = quota_color(percent)
        bounds = (cx - radius, cy - radius, cx + radius, cy + radius)
        self.canvas.create_oval(*bounds, fill=SURFACE, outline=TRACK, width=width)
        if percent is not None:
            numeric = max(0, min(100, float(percent)))
            inset = width / 2
            arc_bounds = (
                bounds[0] + inset,
                bounds[1] + inset,
                bounds[2] - inset,
                bounds[3] - inset,
            )
            self.canvas.create_arc(
                *arc_bounds,
                start=90,
                extent=-3.6 * numeric,
                style="arc",
                outline=color,
                width=width,
            )

    def draw_rounded_panel(self, x1: int, y1: int, x2: int, y2: int, radius: int) -> None:
        points = [
            x1 + radius,
            y1,
            x2 - radius,
            y1,
            x2,
            y1,
            x2,
            y1 + radius,
            x2,
            y2 - radius,
            x2,
            y2,
            x2 - radius,
            y2,
            x1 + radius,
            y2,
            x1,
            y2,
            x1,
            y2 - radius,
            x1,
            y1 + radius,
            x1,
            y1,
        ]
        self.canvas.create_polygon(
            points,
            smooth=True,
            splinesteps=24,
            fill=SURFACE,
            outline=LINE,
            width=1,
        )

    def draw(self) -> None:
        self.canvas.delete("all")
        if self.expanded:
            self.draw_expanded()
        else:
            self.draw_compact()

    def draw_compact(self) -> None:
        limits = self.status.get("limits", [])
        primary = primary_limit(limits)
        percent = primary.get("remainingPercent")
        official_status = self.status.get("officialQuota", {}).get("status")
        self.draw_ring(32, 32, 29, percent, 5)
        self.canvas.create_text(
            32,
            32,
            text=percent_text(percent),
            fill=INK,
            font=("Segoe UI", 15, "bold"),
        )
        dot_color = GREEN if official_status == "available" else STALE if official_status == "stale" else RED
        self.canvas.create_oval(52, 8, 60, 16, fill=dot_color, outline=SURFACE, width=2)

    def draw_expanded(self) -> None:
        limits = self.status.get("limits", [])
        primary = primary_limit(limits)
        percent = primary.get("remainingPercent")
        official_status = self.status.get("officialQuota", {}).get("status")

        self.draw_rounded_panel(1, 1, EXPANDED_WIDTH - 2, EXPANDED_HEIGHT - 2, 7)
        self.draw_ring(32, 32, 25, percent, 5)
        self.canvas.create_text(
            32,
            32,
            text=percent_text(percent),
            fill=INK,
            font=("Segoe UI", 12, "bold"),
        )

        label = friendly_limit_label(primary)
        reset = primary.get("resetLabel") or "重置时间未知"
        self.canvas.create_text(65, 18, text=label, fill=INK, font=("Microsoft YaHei UI", 10, "bold"), anchor="w")
        self.canvas.create_text(65, 43, text=reset, fill=MUTED, font=("Microsoft YaHei UI", 8), anchor="w")
        source_label = source_status_text(official_status)
        self.canvas.create_text(
            EXPANDED_WIDTH - 9,
            43,
            text=source_label,
            fill=GREEN if official_status == "available" else STALE,
            font=("Microsoft YaHei UI", 7, "bold"),
            anchor="e",
        )

        dot_color = GREEN if official_status == "available" else STALE if official_status == "stale" else RED
        self.canvas.create_oval(EXPANDED_WIDTH - 14, 7, EXPANDED_WIDTH - 7, 14, fill=dot_color, outline=SURFACE, width=1)

    def show_details(self) -> None:
        if self.detail_window and self.detail_window.winfo_exists():
            self.detail_window.lift()
            self.render_detail()
            return
        self.detail_window = tk.Toplevel(self.root)
        self.detail_window.title("Codex 额度详情")
        self.detail_window.geometry("500x560")
        self.detail_window.attributes("-topmost", True)
        self.detail_window.configure(bg="#F7F9FC")

        self.detail_text = tk.Text(
            self.detail_window,
            wrap="word",
            bd=0,
            padx=20,
            pady=18,
            bg="#F7F9FC",
            fg="#172033",
            font=("Microsoft YaHei UI", 10),
        )
        self.detail_text.pack(fill="both", expand=True)
        button_bar = tk.Frame(self.detail_window, bg="#F7F9FC")
        button_bar.pack(fill="x", padx=16, pady=(0, 14))
        tk.Button(button_bar, text="立即刷新", command=self.refresh).pack(side="left")
        tk.Button(button_bar, text="网页面板", command=self.open_browser_panel).pack(side="left", padx=8)
        tk.Button(button_bar, text="关闭", command=self.detail_window.destroy).pack(side="right")
        self.render_detail()

    def render_detail(self) -> None:
        if not self.detail_window or not self.detail_window.winfo_exists():
            return
        official = self.status.get("officialQuota", {})
        limits = self.status.get("limits", [])
        source_labels = {
            "official-app-server": "Codex 官方实时接口",
            "official-app-server-cache": "上次成功读取的官方缓存",
            "manual": "手动配置",
        }
        source = source_labels.get(official.get("source"), official.get("source") or "未知")
        shared_limits = [item for item in limits if item.get("limitId") == "codex"]
        independent_limits = [item for item in limits if item.get("limitId") != "codex"]
        lines = [
            "Codex 额度详情",
            "",
            f"套餐: {str(self.status.get('plan') or '未知').upper()}",
            f"数据源: {source}",
            f"更新时间: {self.status.get('generatedAt', '未知')}",
            "",
            "通用共享额度",
            "模型选择器中未被后台单独列出的模型，共同参考这里的额度状态。",
        ]

        for item in shared_limits:
            remaining = percent_text(item.get("remainingPercent"))
            used = item.get("usedPercent")
            lines.append(f"\n{friendly_limit_label(item)}")
            lines.append(f"  剩余 {remaining}" + (f" · 已用 {used}%" if used is not None else ""))
            if item.get("resetLabel"):
                lines.append(f"  {item['resetLabel']}")

        if independent_limits:
            lines.extend(
                [
                    "",
                    "独立模型额度",
                    "只有 Codex 后台明确单列的特殊模型才会出现在这里；它不代表当前正在使用该模型。",
                ]
            )
            for item in independent_limits:
                remaining = percent_text(item.get("remainingPercent"))
                used = item.get("usedPercent")
                lines.append(f"\n{friendly_limit_label(item)}")
                lines.append(f"  剩余 {remaining}" + (f" · 已用 {used}%" if used is not None else ""))
                if item.get("resetLabel"):
                    lines.append(f"  {item['resetLabel']}")

        lines.extend(
            [
                "",
                "额度结构说明",
                "模型列表不等于额度列表。当前官方接口没有分别返回每个常规模型的独立百分比，因此本插件不会自行拆分或猜测模型额度。",
                "",
                "刷新状态",
                official.get("note", ""),
                "悬浮窗每隔约 60 秒静默刷新。读取失败时会明确标记缓存，不会把本地 Token 估算冒充官方额度。",
            ]
        )
        warnings = self.status.get("warnings", [])
        if warnings:
            lines.extend(["", "状态提示", *[f"- {warning}" for warning in warnings]])

        self.detail_text.configure(state="normal")
        self.detail_text.delete("1.0", "end")
        self.detail_text.insert("1.0", "\n".join(lines))
        self.detail_text.configure(state="disabled")

    def open_browser_panel(self) -> None:
        ensure_panel_server()
        webbrowser.open(PANEL_URL)

    def quit(self) -> None:
        self.save_position()
        try:
            PID_FILE.unlink(missing_ok=True)
        except OSError:
            pass
        self.root.destroy()

    def run(self) -> None:
        PID_FILE.parent.mkdir(parents=True, exist_ok=True)
        PID_FILE.write_text(str(os.getpid()), encoding="utf-8")
        self.root.mainloop()


def main() -> int:
    parser = argparse.ArgumentParser(description="Start the Codex quota floating desktop widget.")
    parser.add_argument("--refresh-seconds", type=int, default=60)
    args = parser.parse_args()

    try:
        enable_dpi_awareness()
        app = QuotaFloatWidget(args.refresh_seconds)
        app.run()
    except Exception as exc:
        log_error(exc)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
