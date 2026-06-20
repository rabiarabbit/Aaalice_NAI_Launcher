# macOS 图标生成

把角色立绘合成成 macOS 风格的**圆角方块**（白色背景 squircle，弧度对齐 Dock）：
- **Dock 应用图标** → `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_*.png`（带透明边距，符合 macOS 规范）
- **菜单栏托盘图标** → `assets/icons/tray_icon.png`（满幅）

## 生成

```bash
python3 -m venv venv && venv/bin/pip install Pillow
venv/bin/python tool/macos_icon/make_macos_icons.py                 # 默认 char-scale=0.84
# 重新构建让图标生效
flutter build macos
```

## 白边（角色留白）可调

`--char-scale` 控制角色相对圆角方块的大小，即**白边宽度**——越小，白边越宽：

```bash
venv/bin/python tool/macos_icon/make_macos_icons.py --char-scale 0.62
```

`previews/` 里有几档对比图（灰底仅为看清白方块边界）：

| 预览 | `--char-scale` | 白边 |
|------|---------------|------|
| `previews/current_0.84.png` | 0.84 | 当前默认（窄） |
| `previews/A_0.74.png` | 0.74 | 略宽 |
| `previews/B_0.62.png` | 0.62 | 适中 |
| `previews/C_0.52.png` | 0.52 | 宽 |

挑一档喜欢的白边，用对应 `--char-scale` 重新生成即可。源立绘见 `assets/icons/ios/AppIcon.appiconset/icon-1024.png`。
