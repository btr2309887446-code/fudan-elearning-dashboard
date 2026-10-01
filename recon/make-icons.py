"""从一张源图生成全平台的应用图标。

用法：
    python recon/make-icons.py [源图路径]

默认源图是 build/icon-new-source.png。

产出：
    build/icon.png                              1024，圆角+透明角，给 electron-builder
    build/icon.ico                              Windows 多尺寸 ico
    flutter_app/assets/icon/icon.png          macOS / web（圆角+透明角）
    flutter_app/assets/icon/icon_ios.png      iOS：满幅方图、无 alpha
    flutter_app/assets/icon/icon_foreground.png  Android 自适应前景
    build/icon-preview.png                      多尺寸预览图，人工核对

设计取舍（都写在这里，避免下次又要重新想）：
  - 源图是白底、无透明通道。iOS 要求图标不透明且满幅，所以白底正合适；
    macOS 与 Windows 习惯是圆角方块，所以另存一份切了圆角的。
  - Android 自适应图标的安全区只有画布的约 62%（圆形遮罩会裁掉四角与边缘），
    所以前景里的图案要按这个比例缩，否则底部那行字会被裁掉。
"""

import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_SRC = os.path.join(ROOT, 'build', 'icon-new-source.png')

BUILD = os.path.join(ROOT, 'build')
FLUTTER_ICONS = os.path.join(ROOT, 'flutter_app', 'assets', 'icon')

# 图案四周留的空白比例（相对画布）。iOS 的圆角遮罩会吃掉边缘，
# 留一点内边距图案才不会被切。
CONTENT_RATIO = 0.86

# Android 自适应图标的安全区比例。
ANDROID_SAFE_RATIO = 0.62

# 圆角半径，macOS/Windows 风格。
CORNER_RATIO = 0.225


def content_bbox(im: Image.Image, threshold: int = 18):
    """找出非白内容的包围盒。"""
    rgb = im.convert('RGB')
    bg = Image.new('RGB', im.size, (255, 255, 255))
    from PIL import ImageChops

    diff = ImageChops.difference(rgb, bg).convert('L')
    return diff.point(lambda v: 255 if v > threshold else 0).getbbox()


def square_master(src: Image.Image, ratio: float = CONTENT_RATIO) -> Image.Image:
    """裁掉多余白边，补成正方形，图案占画布的 ratio。"""
    bbox = content_bbox(src)
    if bbox:
        src = src.crop(bbox)

    w, h = src.size
    # 先把图案放进一个「内容方格」，再扩到整张画布。
    side = max(w, h)
    content = Image.new('RGB', (side, side), (255, 255, 255))
    content.paste(src, ((side - w) // 2, (side - h) // 2))

    canvas = int(round(side / ratio))
    master = Image.new('RGB', (canvas, canvas), (255, 255, 255))
    master.paste(content, ((canvas - side) // 2, (canvas - side) // 2))
    return master


def rounded(im: Image.Image, radius_ratio: float = CORNER_RATIO) -> Image.Image:
    """切成圆角方块，四角透明。"""
    size = im.size[0]
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    mask = Image.new('L', (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size - 1, size - 1], radius=int(size * radius_ratio), fill=255
    )
    out.paste(im.convert('RGBA'), (0, 0), mask)
    return out


def fit_center(im: Image.Image, canvas: int, ratio: float) -> Image.Image:
    """把图案按 ratio 缩放后居中放到白色画布上（用于 Android 前景）。"""
    inner = int(round(canvas * ratio))
    small = im.resize((inner, inner), Image.LANCZOS)
    out = Image.new('RGBA', (canvas, canvas), (255, 255, 255, 255))
    off = (canvas - inner) // 2
    out.paste(small.convert('RGBA'), (off, off))
    return out


def main() -> None:
    src_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SRC
    if not os.path.exists(src_path):
        raise SystemExit(f'找不到源图：{src_path}')

    os.makedirs(BUILD, exist_ok=True)
    os.makedirs(FLUTTER_ICONS, exist_ok=True)

    raw = Image.open(src_path)
    print(f'源图：{os.path.basename(src_path)}  {raw.size[0]}x{raw.size[1]}  {raw.mode}')

    master = square_master(raw)          # 正方形、白底、图案占 CONTENT_RATIO
    master = master.resize((1024, 1024), Image.LANCZOS)
    print(f'母版：1024x1024（图案占 {CONTENT_RATIO:.0%}）')

    # --- 桌面端（Electron / electron-builder）---
    build_png = rounded(master)
    build_png.save(os.path.join(BUILD, 'icon.png'))
    ico_sizes = [16, 24, 32, 48, 64, 128, 256]
    build_png.save(
        os.path.join(BUILD, 'icon.ico'),
        format='ICO',
        sizes=[(s, s) for s in ico_sizes],
    )
    print(f'  build/icon.png + build/icon.ico（{", ".join(str(s) for s in ico_sizes)}）')

    # --- macOS / web：圆角带透明角 ---
    rounded(master).save(os.path.join(FLUTTER_ICONS, 'icon.png'))

    # --- iOS：满幅方图、不透明 ---
    # iOS 自己套圆角遮罩，图标若预切圆角，四角会露白边。
    master.convert('RGB').save(os.path.join(FLUTTER_ICONS, 'icon_ios.png'))

    # --- Android 自适应前景 ---
    # 注意别在这里再缩一次：flutter_launcher_icons 生成 mipmap-anydpi-v26 时
    # 会给前景加上 `android:inset="16%"`，也就是 drawable 只会占画布中央的 68%。
    # 如果前景自己又缩到 62%，两者叠加后 Logo 只剩 36%，小得离谱。
    # 直接用母版（图案占 86%），叠加 inset 之后约 58%，正好落在安全区内。
    master.convert('RGBA').save(os.path.join(FLUTTER_ICONS, 'icon_foreground.png'))
    print(f'  flutter_app/assets/icon/ {{icon.png, icon_ios.png, icon_foreground.png}}')

    # --- 预览图：把关键尺寸并排画出来，人工核对小尺寸下是否还认得出 ---
    checks = [16, 32, 48, 64, 128, 256]
    pad = 16
    width = sum(checks) + pad * (len(checks) + 1)
    height = max(checks) + pad * 2 + 20
    preview = Image.new('RGB', (width, height), (242, 242, 247))
    x = pad
    for s in checks:
        preview.paste(build_png.resize((s, s), Image.LANCZOS), (x, pad), build_png.resize((s, s), Image.LANCZOS))
        x += s + pad
    preview.save(os.path.join(BUILD, 'icon-preview.png'))
    print('  build/icon-preview.png（多尺寸并排，用于核对）')

    print('\n完成。接下来运行：')
    print('  cd flutter_app && dart run flutter_launcher_icons')


if __name__ == '__main__':
    main()
