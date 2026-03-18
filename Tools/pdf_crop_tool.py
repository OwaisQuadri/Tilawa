#!/usr/bin/env python3
"""
PDF Crop Tool — visually set crop insets for each mushaf PDF.

Uses matplotlib (works on all macOS versions, unlike tkinter).

Usage:
    python3 pdf_crop_tool.py auto          # auto-find simulator PDFs
    python3 pdf_crop_tool.py <pdf_path>    # single PDF
    python3 pdf_crop_tool.py <directory>   # all PDFs in directory

Controls (buttons at bottom + keyboard shortcuts):
    - Drag the colored crop handles to adjust the visible region
    - [O] Opening  [R] Right  [L] Left — switch which crop set to edit
    - [Set Offset] — mark current PDF page as Quran page 1
    - [< Prev] [Next >] — navigate pages (also arrow keys)
    - [Save & Next] — save settings and move to next PDF
    - [Skip] — close without saving

Output JSON format:
{
    "filename": "mushaf_qaloon.pdf",
    "pageOffset": 4,
    "cropOpening": {"top": 0.03, "bottom": 0.03, "leading": 0.05, "trailing": 0.05},
    "cropRight":   {"top": 0.02, "bottom": 0.02, "leading": 0.08, "trailing": 0.02},
    "cropLeft":    {"top": 0.02, "bottom": 0.02, "leading": 0.02, "trailing": 0.08}
}
"""

import sys
import json
import os
import numpy as np

try:
    import fitz  # PyMuPDF
except ImportError:
    print("Install PyMuPDF: pip3 install pymupdf")
    sys.exit(1)

try:
    import matplotlib
    matplotlib.use("macosx")
    # Disable ALL default matplotlib key bindings so they don't conflict
    for key in list(matplotlib.rcParams.keys()):
        if key.startswith("keymap."):
            matplotlib.rcParams[key] = []
    import matplotlib.pyplot as plt
    from matplotlib.patches import Rectangle
    from matplotlib.widgets import Button as MplButton
except ImportError:
    print("Install matplotlib: pip3 install matplotlib")
    sys.exit(1)


class CropTool:
    RENDER_DPI = 72

    def __init__(self, pdf_path, output_path):
        self.pdf_path = pdf_path
        self.output_path = output_path
        self.doc = fitz.open(pdf_path)
        self.filename = os.path.basename(pdf_path)
        self.current_page = 0
        self.page_offset = 0
        self.saved = False

        self.crops = {
            "opening": {"top": 0.0, "bottom": 0.0, "leading": 0.0, "trailing": 0.0},
            "right":   {"top": 0.0, "bottom": 0.0, "leading": 0.0, "trailing": 0.0},
            "left":    {"top": 0.0, "bottom": 0.0, "leading": 0.0, "trailing": 0.0},
        }
        self.active_mode = "opening"

        if os.path.exists(output_path):
            with open(output_path) as f:
                data = json.load(f)
            self.page_offset = data.get("pageOffset", 0)
            for key in ["opening", "right", "left"]:
                json_key = f"crop{key.capitalize()}"
                if json_key in data:
                    self.crops[key] = data[json_key]
            self.current_page = self.page_offset
            print(f"  Loaded existing settings from {os.path.basename(output_path)}")

        self.dragging = False
        self.drag_edge = None

        self._build_ui()

    def _build_ui(self):
        # Layout: image area on top, buttons at bottom
        self.fig = plt.figure(figsize=(7, 11))
        self.fig.canvas.manager.set_window_title(f"Crop Tool — {self.filename}")

        # Main image axes (most of the figure)
        self.ax = self.fig.add_axes([0.02, 0.12, 0.96, 0.84])

        # Title text
        self.title_text = self.fig.text(
            0.5, 0.97, "", ha="center", va="top", fontsize=10, fontfamily="monospace"
        )

        # --- Button row 1: Navigation ---
        btn_h = 0.035
        btn_y1 = 0.065
        btn_y2 = 0.02

        btn_color = "#444444"
        btn_hover = "#666666"

        ax_prev = self.fig.add_axes([0.02, btn_y1, 0.12, btn_h])
        self.btn_prev = MplButton(ax_prev, "< Prev", color=btn_color, hovercolor=btn_hover)
        self.btn_prev.label.set_color("white")
        self.btn_prev.label.set_fontsize(9)
        self.btn_prev.on_clicked(lambda _: self._navigate(-1))

        ax_next = self.fig.add_axes([0.15, btn_y1, 0.12, btn_h])
        self.btn_next = MplButton(ax_next, "Next >", color=btn_color, hovercolor=btn_hover)
        self.btn_next.label.set_color("white")
        self.btn_next.label.set_fontsize(9)
        self.btn_next.on_clicked(lambda _: self._navigate(1))

        ax_prev5 = self.fig.add_axes([0.28, btn_y1, 0.1, btn_h])
        self.btn_prev5 = MplButton(ax_prev5, "<< 5", color=btn_color, hovercolor=btn_hover)
        self.btn_prev5.label.set_color("white")
        self.btn_prev5.label.set_fontsize(9)
        self.btn_prev5.on_clicked(lambda _: self._navigate(-5))

        ax_next5 = self.fig.add_axes([0.39, btn_y1, 0.1, btn_h])
        self.btn_next5 = MplButton(ax_next5, "5 >>", color=btn_color, hovercolor=btn_hover)
        self.btn_next5.label.set_color("white")
        self.btn_next5.label.set_fontsize(9)
        self.btn_next5.on_clicked(lambda _: self._navigate(5))

        ax_offset = self.fig.add_axes([0.52, btn_y1, 0.16, btn_h])
        self.btn_offset = MplButton(ax_offset, "Set Offset", color="#884400", hovercolor="#aa6600")
        self.btn_offset.label.set_color("white")
        self.btn_offset.label.set_fontsize(9)
        self.btn_offset.on_clicked(lambda _: self._set_offset())

        ax_save = self.fig.add_axes([0.70, btn_y1, 0.14, btn_h])
        self.btn_save = MplButton(ax_save, "Save & Next", color="#006600", hovercolor="#008800")
        self.btn_save.label.set_color("white")
        self.btn_save.label.set_fontsize(9)
        self.btn_save.on_clicked(lambda _: (self._save(), plt.close(self.fig)))

        ax_skip = self.fig.add_axes([0.85, btn_y1, 0.13, btn_h])
        self.btn_skip = MplButton(ax_skip, "Skip", color="#660000", hovercolor="#880000")
        self.btn_skip.label.set_color("white")
        self.btn_skip.label.set_fontsize(9)
        self.btn_skip.on_clicked(lambda _: plt.close(self.fig))

        # --- Button row 2: Mode selection ---
        mode_colors = {
            "opening": ("#553300", "#775500"),
            "right":   ("#003355", "#005577"),
            "left":    ("#335500", "#557700"),
        }

        ax_opening = self.fig.add_axes([0.02, btn_y2, 0.15, btn_h])
        c = mode_colors["opening"]
        self.btn_opening = MplButton(ax_opening, "[O] Opening", color=c[0], hovercolor=c[1])
        self.btn_opening.label.set_color("white")
        self.btn_opening.label.set_fontsize(9)
        self.btn_opening.on_clicked(lambda _: self._set_mode("opening"))

        ax_right = self.fig.add_axes([0.18, btn_y2, 0.15, btn_h])
        c = mode_colors["right"]
        self.btn_right = MplButton(ax_right, "[R] Right pg", color=c[0], hovercolor=c[1])
        self.btn_right.label.set_color("white")
        self.btn_right.label.set_fontsize(9)
        self.btn_right.on_clicked(lambda _: self._set_mode("right"))

        ax_left = self.fig.add_axes([0.34, btn_y2, 0.15, btn_h])
        c = mode_colors["left"]
        self.btn_left = MplButton(ax_left, "[L] Left pg", color=c[0], hovercolor=c[1])
        self.btn_left.label.set_color("white")
        self.btn_left.label.set_fontsize(9)
        self.btn_left.on_clicked(lambda _: self._set_mode("left"))

        # Mode indicator
        self.mode_text = self.fig.text(
            0.55, btn_y2 + btn_h / 2, "", va="center", fontsize=10,
            fontfamily="monospace", fontweight="bold"
        )

        # Connect events
        self.fig.canvas.mpl_connect("key_press_event", self._on_key)
        self.fig.canvas.mpl_connect("button_press_event", self._on_press)
        self.fig.canvas.mpl_connect("motion_notify_event", self._on_motion)
        self.fig.canvas.mpl_connect("button_release_event", self._on_release)

        self._render_page()
        plt.show()

    def _navigate(self, delta):
        self.current_page = max(0, min(self.doc.page_count - 1, self.current_page + delta))
        self._render_page()

    def _set_mode(self, mode):
        self.active_mode = mode
        self._render_page()

    def _set_offset(self):
        self.page_offset = self.current_page
        print(f"  Page offset set to {self.page_offset}")
        self._render_page()

    def _content_page(self):
        return self.current_page - self.page_offset + 1

    def _active_crop_key(self):
        cp = self._content_page()
        if cp <= 2:
            return "opening"
        return "right" if cp % 2 == 0 else "left"

    def _active_crop(self):
        return self.crops[self._active_crop_key()]

    def _render_page(self):
        page = self.doc[self.current_page]
        mat = fitz.Matrix(self.RENDER_DPI / 72, self.RENDER_DPI / 72)
        pix = page.get_pixmap(matrix=mat)
        if pix.n == 4:
            img = np.frombuffer(pix.samples, dtype=np.uint8).reshape(pix.height, pix.width, 4)[:, :, :3]
        else:
            img = np.frombuffer(pix.samples, dtype=np.uint8).reshape(pix.height, pix.width, pix.n)

        self.img_w, self.img_h = pix.width, pix.height

        self.ax.clear()
        self.ax.imshow(img)
        self.ax.set_xlim(0, pix.width)
        self.ax.set_ylim(pix.height, 0)
        self.ax.set_aspect("equal")
        self.ax.axis("off")

        # Draw crop overlays
        w, h = pix.width, pix.height
        crop = self.crops[self.active_mode]
        t = crop["top"] * h
        b = crop["bottom"] * h
        le = crop["trailing"] * w
        r = crop["leading"] * w

        overlay_alpha = 0.5
        for rect_coords in [
            (0, 0, w, t),
            (0, h - b, w, b),
            (0, t, le, h - b - t),
            (w - r, t, r, h - b - t),
        ]:
            x, y, rw, rh = rect_coords
            if rw > 0 and rh > 0:
                self.ax.add_patch(Rectangle(
                    (x, y), rw, rh,
                    facecolor="black", alpha=overlay_alpha, edgecolor="none"
                ))

        self.ax.add_patch(Rectangle(
            (le, t), w - le - r, h - t - b,
            facecolor="none", edgecolor="#ff3333", linewidth=2
        ))

        # Drag handles
        mid_x = (le + w - r) / 2
        mid_y = (t + h - b) / 2
        handles = [
            ("top", mid_x, t, "#ff3333"),
            ("bottom", mid_x, h - b, "#3333ff"),
            ("trailing", le, mid_y, "#33ff33"),
            ("leading", w - r, mid_y, "#ffaa00"),
        ]
        for edge, cx, cy, color in handles:
            self.ax.plot(cx, cy, "s", color=color, markersize=8,
                        markeredgecolor="white", markeredgewidth=1.5)
            self.ax.annotate(
                f"{edge}: {crop[edge]:.3f}",
                (cx, cy), fontsize=7, color=color, fontweight="bold",
                textcoords="offset points",
                xytext=(12, 8) if edge in ("top", "leading") else (-12, -8),
                ha="left" if edge in ("top", "leading") else "right",
                bbox=dict(boxstyle="round,pad=0.2", facecolor="black", alpha=0.7)
            )

        # Update title
        cp = self._content_page()
        mode_labels = {"opening": "OPENING", "right": "RIGHT", "left": "LEFT"}
        auto_mode = self._active_crop_key()
        page_type = mode_labels[auto_mode]

        self.title_text.set_text(
            f"PDF pg {self.current_page}/{self.doc.page_count - 1}  |  "
            f"Content pg {cp}  |  "
            f"Offset: {self.page_offset}  |  "
            f"Auto-type: {page_type}"
        )

        # Mode indicator
        editing = mode_labels[self.active_mode]
        mode_color = {"opening": "#aa7700", "right": "#0077aa", "left": "#77aa00"}[self.active_mode]
        self.mode_text.set_text(f"Editing: {editing}")
        self.mode_text.set_color(mode_color)

        self.fig.canvas.draw_idle()

    def _on_key(self, event):
        if event.key == "left":
            self._navigate(-1)
        elif event.key == "right":
            self._navigate(1)
        elif event.key == "o":
            self._set_mode("opening")
        elif event.key == "r":
            self._set_mode("right")
        elif event.key == "l":
            self._set_mode("left")
        elif event.key == "p":
            self._set_offset()
        elif event.key == "s":
            self._save()
            plt.close(self.fig)
        elif event.key == "q":
            plt.close(self.fig)

    def _on_press(self, event):
        if event.inaxes != self.ax or event.button != 1:
            return
        w, h = self.img_w, self.img_h
        crop = self.crops[self.active_mode]
        t = crop["top"] * h
        b = crop["bottom"] * h
        le = crop["trailing"] * w
        r = crop["leading"] * w

        mid_x = (le + w - r) / 2
        mid_y = (t + h - b) / 2
        thresh = 20

        edges = [
            ("top", mid_x, t),
            ("bottom", mid_x, h - b),
            ("trailing", le, mid_y),
            ("leading", w - r, mid_y),
        ]
        for edge, cx, cy in edges:
            dx = abs(event.xdata - cx)
            dy = abs(event.ydata - cy)
            if (dx < thresh * 3 and dy < thresh) or (dx < thresh and dy < thresh * 3):
                self.dragging = True
                self.drag_edge = edge
                return

    def _on_motion(self, event):
        if not self.dragging or event.inaxes != self.ax:
            return
        w, h = self.img_w, self.img_h
        crop = self.crops[self.active_mode]

        if self.drag_edge == "top":
            crop["top"] = max(0, min(0.4, event.ydata / h))
        elif self.drag_edge == "bottom":
            crop["bottom"] = max(0, min(0.4, (h - event.ydata) / h))
        elif self.drag_edge == "trailing":
            crop["trailing"] = max(0, min(0.4, event.xdata / w))
        elif self.drag_edge == "leading":
            crop["leading"] = max(0, min(0.4, (w - event.xdata) / w))

        self._render_page()

    def _on_release(self, event):
        self.dragging = False
        self.drag_edge = None

    def _save(self):
        data = {
            "filename": self.filename,
            "pageOffset": self.page_offset,
            "cropOpening": self.crops["opening"],
            "cropRight": self.crops["right"],
            "cropLeft": self.crops["left"],
        }
        with open(self.output_path, "w") as f:
            json.dump(data, f, indent=2)
        self.saved = True
        print(f"  Saved to {os.path.basename(self.output_path)}")


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 pdf_crop_tool.py <pdf_path_or_directory_or_auto>")
        print("\nOpens a GUI to visually set crop insets and page offsets.")
        print("Settings auto-save to <pdf_name>_crop.json next to the PDF.")
        print("\nExamples:")
        print("  python3 pdf_crop_tool.py auto")
        print("  python3 pdf_crop_tool.py ~/path/to/mushaf.pdf")
        print("  python3 pdf_crop_tool.py ~/path/to/MushafPDFs/")
        sys.exit(1)

    target = sys.argv[1]

    if target == "auto" or not os.path.exists(target):
        import glob
        pattern = os.path.expanduser(
            "~/Library/Developer/CoreSimulator/Devices/*/data/Containers/Data/Application/*/Documents/MushafPDFs"
        )
        candidates = glob.glob(pattern)
        candidates = [c for c in candidates if any(
            f.endswith(".pdf") and not f.startswith("chunks_")
            and os.path.isfile(os.path.join(c, f))
            for f in os.listdir(c)
        )]
        if candidates:
            target = max(candidates, key=os.path.getmtime)
            print(f"Auto-found MushafPDFs at:\n  {target}\n")
        else:
            if target == "auto":
                print("No MushafPDFs directories found in the simulator.")
                print("Download a mushaf PDF in the app first, then re-run.")
            else:
                print(f"Error: '{target}' does not exist.")
            sys.exit(1)

    if os.path.isdir(target):
        pdfs = sorted(
            f for f in os.listdir(target)
            if f.endswith(".pdf") and os.path.isfile(os.path.join(target, f))
            and not f.startswith("chunks_")
        )
        if not pdfs:
            print(f"No PDF files found in {target}")
            sys.exit(1)
        print(f"Found {len(pdfs)} PDFs. Opening each one in sequence.\n")
        for i, pdf_name in enumerate(pdfs):
            pdf_path = os.path.join(target, pdf_name)
            output_path = pdf_path.replace(".pdf", "_crop.json")
            print(f"[{i+1}/{len(pdfs)}] {pdf_name}")
            CropTool(pdf_path, output_path)
    else:
        if not target.endswith(".pdf"):
            print(f"Error: '{target}' is not a PDF file.")
            sys.exit(1)
        output_path = target.replace(".pdf", "_crop.json")
        CropTool(target, output_path)


if __name__ == "__main__":
    main()
