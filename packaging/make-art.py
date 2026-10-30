#!/usr/bin/env python3
"""Generates the app icon set and the DMG background (1x + @2x). Requires Pillow.
Usage: python3 packaging/make-art.py   (from the repo root)"""
import json, os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICONSET = os.path.join(ROOT, "App/Resources/Assets.xcassets/AppIcon.appiconset")
PKG = os.path.join(ROOT, "packaging")
FONT_CANDIDATES = [
    "/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Helvetica.ttc",
    "/usr/share/fonts/truetype/sand-box/google/Inter/Inter-VariableFont_opsz,wght.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]

def font(size, weight=None):
    for p in FONT_CANDIDATES:
        if os.path.exists(p):
            f = ImageFont.truetype(p, size)
            if weight:
                try: f.set_variation_by_axes([14 if size < 40 else 32, weight])
                except Exception:
                    try: f.set_variation_by_axes([weight])
                    except Exception: pass
            return f
    return ImageFont.load_default()

def vgradient(w, h, top, bottom):
    g = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / max(h - 1, 1)
        g.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return g.resize((w, h))

def icon(size=1024):
    S = 4  # supersample
    W = size * S
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    # macOS icon grid: ~824/1024 rounded square with shadow.
    inset = int(W * 100 / 1024)
    box = (inset, inset, W - inset, W - inset)
    radius = int((box[2] - box[0]) * 0.225)
    shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((box[0], box[1] + W // 80, box[2], box[3] + W // 80), radius, fill=(0, 0, 0, 90))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(W // 60)))
    mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius, fill=255)
    bg = vgradient(W, W, (92, 78, 230), (42, 32, 128)).convert("RGBA")
    img.paste(bg, (0, 0), mask)
    d = ImageDraw.Draw(img)
    # Yellow face.
    cx, cy, r = W * 0.56, W * 0.53, W * 0.27
    face = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    fd = ImageDraw.Draw(face)
    fd.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(255, 204, 51))
    fd.ellipse((cx - r, cy - r, cx + r, cy + r), outline=(232, 160, 20), width=int(W * 0.008))
    img.alpha_composite(face)
    # Eyes and smile.
    er = r * 0.12
    for ex in (cx - r * 0.36, cx + r * 0.36):
        d.ellipse((ex - er, cy - r * 0.32 - er * 1.4, ex + er, cy - r * 0.32 + er * 1.4), fill=(70, 45, 20))
    d.arc((cx - r * 0.6, cy - r * 0.45, cx + r * 0.6, cy + r * 0.62), 20, 160, fill=(70, 45, 20), width=int(r * 0.13))
    # The ':' motif: two white rounded dots to the left of the face, like a typed shortcode.
    dr = W * 0.045
    colx = W * 0.215
    for dy in (cy - r * 0.42, cy + r * 0.42):
        d.ellipse((colx - dr, dy - dr, colx + dr, dy + dr), fill=(255, 255, 255))
    return img.resize((size, size), Image.LANCZOS)

def write_iconset():
    os.makedirs(ICONSET, exist_ok=True)
    master = icon(1024)
    images = []
    for pt in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = pt * scale
            name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
            master.resize((px, px), Image.LANCZOS).save(os.path.join(ICONSET, name))
            images.append({"idiom": "mac", "size": f"{pt}x{pt}", "scale": f"{scale}x", "filename": name})
    with open(os.path.join(ICONSET, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"version": 1, "author": "xcode"}}, f, indent=2)
    with open(os.path.join(os.path.dirname(ICONSET), "Contents.json"), "w") as f:
        json.dump({"info": {"version": 1, "author": "xcode"}}, f, indent=2)
    master.save(os.path.join(PKG, "icon-preview.png"))

# DMG window layout (points). Keep in sync with scripts/make-dmg.sh.
WIN_W, WIN_H = 660, 400
APP_X, APPS_X, ICON_Y = 180, 480, 190

def background(scale):
    W, H = WIN_W * scale, WIN_H * scale
    img = vgradient(W, H, (250, 249, 255), (232, 230, 246)).convert("RGBA")
    d = ImageDraw.Draw(img)
    # Arrow between the two icon positions (icons are 128 pt; leave room).
    y = ICON_Y * scale
    x0, x1 = (APP_X + 84) * scale, (APPS_X - 84) * scale
    col = (108, 96, 220, 255)
    lw = 7 * scale
    head = 22 * scale
    d.line((x0, y, x1 - head * 0.8, y), fill=col, width=lw)
    d.polygon([(x1, y), (x1 - head * 1.3, y - head), (x1 - head * 1.3, y + head)], fill=col)
    for xx in (x0,):
        d.ellipse((xx - lw / 2, y - lw / 2, xx + lw / 2, y + lw / 2), fill=col)
    # Text.
    title = font(26 * scale, 650)
    sub = font(14 * scale, 450)
    t = "Drag to Applications"
    tw = d.textlength(t, font=title)
    d.text(((W - tw) / 2, 300 * scale), t, font=title, fill=(40, 34, 90, 255))
    s = "Then open Rev from your Applications folder"
    sw = d.textlength(s, font=sub)
    d.text(((W - sw) / 2, 340 * scale), s, font=sub, fill=(110, 105, 150, 255))
    return img.convert("RGB")

if __name__ == "__main__":
    write_iconset()
    background(1).save(os.path.join(PKG, "dmg-background.png"))
    background(2).save(os.path.join(PKG, "dmg-background@2x.png"))
    # Preview: background with the icon composited where Finder will put it.
    prev = background(2).convert("RGBA")
    ic = icon(256)
    prev.alpha_composite(ic, (APP_X * 2 - 128, ICON_Y * 2 - 128))
    folder = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    fd = ImageDraw.Draw(folder)
    fd.rounded_rectangle((20, 60, 236, 220), 18, fill=(90, 170, 240)); fd.rounded_rectangle((20, 44, 110, 80), 12, fill=(90, 170, 240))
    fd.text((128, 140), "A", font=font(90, 700), fill=(255, 255, 255), anchor="mm")
    prev.alpha_composite(folder, (APPS_X * 2 - 128, ICON_Y * 2 - 128))
    prev.convert("RGB").save(os.path.join(PKG, "dmg-preview.png"))
    print("wrote icon set, packaging/dmg-background{,@2x}.png, icon-preview.png, dmg-preview.png")
