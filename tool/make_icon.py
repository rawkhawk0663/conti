# Zeichnet das Conti-Symbol: Quadrat mit runden Ecken, Verlauf Pink → Violett,
# darin ein weisses „C“ (Schrift Sora Bold) mit einem kleinen Punkt wie ein Saldo-Ring.
# Aufruf: python3 tool/make_icon.py
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

S = 1024
base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PINK, VIOLET = (240, 71, 156), (122, 60, 240)


def gradient():
    g = Image.new('RGBA', (S, S))
    px = g.load()
    for y in range(S):
        for x in range(S):
            t = (x + y) / (2 * (S - 1))
            px[x, y] = tuple(int(PINK[i] + (VIOLET[i] - PINK[i]) * t) for i in range(3)) + (255,)
    return g


def icon(size, rounded=True):
    g = gradient()
    mask = Image.new('L', (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=230 if rounded else 0, fill=255)
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    im.paste(g, (0, 0), mask)
    # weicher Glanz oben links
    glow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([-200, -260, 700, 560], fill=(255, 255, 255, 38))
    glow = glow.filter(ImageFilter.GaussianBlur(80))
    im = Image.alpha_composite(im, Image.composite(glow, Image.new('RGBA', (S, S), (0, 0, 0, 0)), mask))
    d = ImageDraw.Draw(im)
    font = ImageFont.truetype(os.path.join(base, 'assets/fonts/Sora-Bold.ttf'), 640)
    box = d.textbbox((0, 0), 'C', font=font)
    w, h = box[2] - box[0], box[3] - box[1]
    d.text(((S - w) / 2 - box[0] - 20, (S - h) / 2 - box[1]), 'C', font=font, fill=(255, 255, 255, 255))
    # Punkt: das „Saldo“ am Ende des Rings
    d.ellipse([700, 640, 800, 740], fill=(255, 255, 255, 255))
    return im.resize((size, size), Image.LANCZOS)


os.makedirs(os.path.join(base, 'assets/brand'), exist_ok=True)
icon(512).save(os.path.join(base, 'assets/brand/conti_icon.png'))
icon(256).save(os.path.join(base, 'windows/runner/resources/app_icon.ico'),
               sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
for name, px in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
    icon(px).save(os.path.join(base, f'android/app/src/main/res/mipmap-{name}/ic_launcher.png'))
print('ok')
