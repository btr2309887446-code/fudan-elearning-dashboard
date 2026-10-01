"""Generate the application icon (gradient rounded square + 复)."""

import os
from PIL import Image, ImageDraw, ImageFont

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'build')
os.makedirs(OUT, exist_ok=True)

S = 512
C1 = (78, 168, 245)    # #4ea8f5
C2 = (124, 107, 240)   # #7c6bf0

grad = Image.new('RGB', (S, S))
draw = ImageDraw.Draw(grad)
for y in range(S):
    t = y / (S - 1)
    draw.line(
        [(0, y), (S, y)],
        fill=(
            int(C1[0] + (C2[0] - C1[0]) * t),
            int(C1[1] + (C2[1] - C1[1]) * t),
            int(C1[2] + (C2[2] - C1[2]) * t),
        ),
    )

# Slight top highlight so the tile does not look flat at small sizes.
highlight = Image.new('L', (S, S), 0)
hd = ImageDraw.Draw(highlight)
for y in range(S):
    hd.line([(0, y), (S, y)], fill=int(38 * (1 - y / (S - 1))))
grad = Image.composite(Image.new('RGB', (S, S), (255, 255, 255)), grad, highlight)

img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
mask = Image.new('L', (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.23), fill=255)
img.paste(grad, (0, 0), mask)

font_path = None
for candidate in (r'C:\Windows\Fonts\msyhbd.ttc', r'C:\Windows\Fonts\msyh.ttc', r'C:\Windows\Fonts\simhei.ttf'):
    if os.path.exists(candidate):
        font_path = candidate
        break

if font_path:
    font = ImageFont.truetype(font_path, int(S * 0.60))
    d = ImageDraw.Draw(img)
    text = '复'
    bbox = d.textbbox((0, 0), text, font=font)
    w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    d.text(((S - w) / 2 - bbox[0], (S - h) / 2 - bbox[1]), text, font=font, fill=(255, 255, 255, 255))
else:
    print('WARNING: no CJK font found, icon will be blank')

img.save(os.path.join(OUT, 'icon.png'))
img.resize((256, 256), Image.LANCZOS).save(
    os.path.join(OUT, 'icon.ico'),
    sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
)
print('icon written to', OUT)
print('font:', font_path)
