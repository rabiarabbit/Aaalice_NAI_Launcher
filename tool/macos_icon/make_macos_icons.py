#!/usr/bin/env python3
"""生成 macOS 应用图标（Dock）+ 菜单栏托盘图标。

从角色立绘 assets/icons/ios/AppIcon.appiconset/icon-1024.png 合成
macOS 风格的圆角方块（白色背景 squircle，弧度对齐 Dock）。

依赖 Pillow：
    python3 -m venv venv && venv/bin/pip install Pillow

生成实际图标（覆盖 AppIcon 各尺寸 + tray_icon.png）：
    venv/bin/python tool/macos_icon/make_macos_icons.py                 # 默认 char_scale=0.84
    venv/bin/python tool/macos_icon/make_macos_icons.py --char-scale 0.62
之后重新 `flutter build macos`。

`--char-scale` 控制角色相对圆角方块的大小，即「白边宽度」：越小白边越宽。
生成对比预览（灰底仅为看清白方块边界）：
    venv/bin/python tool/macos_icon/make_macos_icons.py --previews
对比图在 tool/macos_icon/previews/，挑一档喜欢的白边，用对应 --char-scale 重新生成即可。
"""
import argparse
import os
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "assets/icons/ios/AppIcon.appiconset/icon-1024.png")
BG = (255, 255, 255, 255)   # 白色背景
CORNER = 0.2237             # macOS 图标圆角比例（≈ Dock 弧度）


def rounded_square(size, char_scale):
    ss = 4  # 超采样抗锯齿
    r = round(size * CORNER)
    m = Image.new("L", (size * ss, size * ss), 0)
    ImageDraw.Draw(m).rounded_rectangle(
        [0, 0, size * ss - 1, size * ss - 1], radius=r * ss, fill=255)
    m = m.resize((size, size), Image.LANCZOS)
    sq = Image.new("RGBA", (size, size), BG)
    ch = Image.open(SRC).convert("RGBA")
    cs = round(size * char_scale)
    ch = ch.resize((cs, cs), Image.LANCZOS)
    sq.alpha_composite(ch, ((size - cs) // 2, (size - cs) // 2))
    sq.putalpha(m)
    return sq


def make_icon(canvas, char_scale, content_ratio):
    """content_ratio=0.806 → Dock 规范（带透明边距）；1.0 → 菜单栏满幅。"""
    c = round(canvas * content_ratio)
    mg = (canvas - c) // 2
    img = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    img.alpha_composite(rounded_square(c, char_scale), (mg, mg))
    return img


def showcase(icon, bg=(110, 115, 125)):
    pad = icon.width // 5
    cv = Image.new("RGBA", (icon.width + pad * 2, icon.height + pad * 2), bg + (255,))
    cv.alpha_composite(icon, (pad, pad))
    return cv.convert("RGB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--char-scale", type=float, default=0.84,
                    help="角色相对圆角方块的缩放（越小白边越宽）")
    ap.add_argument("--previews", action="store_true",
                    help="只生成 previews/ 对比图，不覆盖实际图标")
    args = ap.parse_args()

    if args.previews:
        prev = os.path.join(os.path.dirname(__file__), "previews")
        os.makedirs(prev, exist_ok=True)
        for name, c in [("current_0.84", 0.84), ("A_0.74", 0.74),
                        ("B_0.62", 0.62), ("C_0.52", 0.52)]:
            showcase(make_icon(1024, c, 0.806)).save(f"{prev}/{name}.png")
        print("已生成 previews/（current_0.84 / A_0.74 / B_0.62 / C_0.52）")
        return

    cs = args.char_scale
    icon_dir = os.path.join(ROOT, "macos/Runner/Assets.xcassets/AppIcon.appiconset")
    for s in [16, 32, 64, 128, 256, 512, 1024]:
        make_icon(s, cs, 0.806).save(f"{icon_dir}/app_icon_{s}.png")   # Dock 带透明边距
    make_icon(44, cs, 1.0).save(os.path.join(ROOT, "assets/icons/tray_icon.png"))  # 菜单栏满幅
    print(f"已生成 AppIcon（7 尺寸）+ tray_icon，char_scale={cs}")


if __name__ == "__main__":
    main()
