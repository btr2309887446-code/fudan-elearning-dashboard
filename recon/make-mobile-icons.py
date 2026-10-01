"""生成各平台的应用图标源图。

沿用桌面端那颗图标（蓝紫渐变 + 复），但按移动端的要求重新出图：
  - icon.png            1024×1024，满幅圆角方块，给 iOS / macOS / web
  - icon_foreground.png 1024×1024，透明底、图形缩到约 60%，给 Android 自适应图标
    （Android 会把前景裁进各种形状里，所以四周要留够安全边距）
"""

import os
from PIL import Image, ImageDraw, ImageFont

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'flutter_app', 'assets', 'icon')
os.makedirs(OUT, exist_ok=True)

S = 1024
C1 = (78, 168, 245)    # #4ea8f5
C2 = (124, 107, 240)   # #7c6bf0


def gradient(size):
    grad = Image.new('RGB', (size, size))
    draw = ImageDraw.Draw(grad)
    for y in range(size):
        t = y / (size - 1)
        draw.line(
            [(0, y), (size, y)],
            fill=(
                int(C1[0] + (C2[0] - C1[0]) * t),
                int(C1[1] + (C2[1] - C1[1]) * t),
                int(C1[2] + (C2[2] - C1[2]) * t),
            ),
        )
    # 顶部轻微高光，避免小尺寸下显得死板。
    highlight = Image.new('L', (size, size), 0)
    hd = ImageDraw.Draw(highlight)
    for y in range(size):
        hd.line([(0, y), (size, y)], fill=int(38 * (1 - y / (size - 1))))
    return Image.composite(Image.new('RGB', (size, size), (255, 255, 255)), grad, highlight)


font_path = None
for candidate in (
    r'C:\Windows\Fonts\msyhbd.ttc',
    r'C:\Windows\Fonts\msyh.ttc',
    r'C:\Windows\Fonts\simhei.ttf',
):
    if os.path.exists(candidate):
        font_path = candidate
        break


def draw_glyph(img, ratio, size):
    """在 img 中央画「复」，占画布高度的 ratio。"""
    if not font_path:
        return
    font = ImageFont.truetype(font_path, int(size * ratio))
    d = ImageDraw.Draw(img)
    text = '复'
    bbox = d.textbbox((0, 0), text, font=font)
    w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    d.text(
        ((size - w) / 2 - bbox[0], (size - h) / 2 - bbox[1]),
        text,
        font=font,
        fill=(255, 255, 255, 255),
    )


# --- 1. 满幅圆角方块（macOS / web）-----------------------------------------
# macOS 不自动套遮罩，所以要自带圆角与外边距。
full = Image.new('RGBA', (S, S), (0, 0, 0, 0))
mask = Image.new('L', (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.23), fill=255)
full.paste(gradient(S), (0, 0), mask)
draw_glyph(full, 0.60, S)
full.save(os.path.join(OUT, 'icon.png'))

# --- 2. iOS：满幅方形、无透明 ----------------------------------------------
# iOS 会自己套用圆角遮罩，图标若预先切了圆角，四角会露出白边。
# 所以这里让渐变铺满整个正方形，并且不带 alpha 通道。
ios_icon = gradient(S).convert('RGB')
draw_glyph(ios_icon.convert('RGBA'), 0.60, S)
ios_rgba = gradient(S).convert('RGBA')
draw_glyph(ios_rgba, 0.60, S)
flat = Image.new('RGB', (S, S))
flat.paste(ios_rgba, (0, 0), ios_rgba)
flat.save(os.path.join(OUT, 'icon_ios.png'))

# --- 3. Android 自适应图标前景（透明底、留安全边距）------------------------
fg = Image.new('RGBA', (S, S), (0, 0, 0, 0))
draw_glyph(fg, 0.42, S)
fg.save(os.path.join(OUT, 'icon_foreground.png'))

print('图标已写入', OUT)
for name in ('icon.png', 'icon_ios.png', 'icon_foreground.png'):
    p = os.path.join(OUT, name)
    with Image.open(p) as im:
        print(f'  {name:24} {im.size[0]}x{im.size[1]} {im.mode}')
print('字体:', font_path)
