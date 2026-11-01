"""Render the Steam guide images into media/ (original artwork, no game assets).

  python3 tools/make_steam_images.py media <bold font> <regular font> <mono font>

Used: Cantarell ExtraBold, Cantarell Regular, FiraCode Nerd Font SemiBold. Needs Pillow.
"""
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = sys.argv[1]
BOLD, REG, MONO = sys.argv[2], sys.argv[3], sys.argv[4]
SS = 2  # supersampling

BG_TOP = (36, 18, 58)
BG_BOTTOM = (10, 6, 22)
GOLD = (232, 194, 106)
GOLD_DIM = (176, 140, 72)
TEXT = (240, 234, 248)
MUTED = (170, 156, 196)


def font(path, px):
    return ImageFont.truetype(path, px * SS)


def background(w, h):
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / (h - 1)
        d.line([(0, y), (w, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM)))
    # soft gold glow behind the keys
    glow = Image.new("L", (w, h), 0)
    ImageDraw.Draw(glow).ellipse([w * 0.15, h * 0.30, w * 0.85, h * 0.95], fill=70)
    glow = glow.filter(ImageFilter.GaussianBlur(w * 0.12))
    img = Image.composite(Image.new("RGB", (w, h), (90, 60, 40)), img, glow)
    return img


def centered(d, cx, y, text, f, fill):
    l, t, r, b = d.textbbox((0, 0), text, font=f)
    d.text((cx - (r - l) / 2 - l, y - t), text, font=f, fill=fill)
    return b - t


def keycap(img, x, y, size, label, f):
    """A keyboard key seen slightly from above: dark base, lighter top face, gold legend."""
    d = ImageDraw.Draw(img)
    r = size * 0.16
    depth = size * 0.10
    # drop shadow
    sh = Image.new("L", img.size, 0)
    ImageDraw.Draw(sh).rounded_rectangle([x + depth * 0.4, y + depth * 1.6, x + size + depth * 0.4, y + size + depth * 1.6],
                                         radius=r, fill=150)
    sh = sh.filter(ImageFilter.GaussianBlur(size * 0.06))
    img.paste((0, 0, 0), mask=sh)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([x, y + depth, x + size, y + size + depth], radius=r, fill=(28, 22, 40), outline=GOLD_DIM,
                        width=max(2, int(size * 0.012)))
    top = [x + size * 0.06, y, x + size * 0.94, y + size * 0.86]
    d.rounded_rectangle(top, radius=r * 0.8, fill=(58, 46, 82))
    # top-face highlight
    hl = [top[0] + size * 0.03, top[1] + size * 0.03, top[2] - size * 0.03, top[1] + size * 0.30]
    d.rounded_rectangle(hl, radius=r * 0.6, fill=(72, 58, 100))
    centered(d, x + size / 2, y + size * 0.43 - f.size * 0.36, label, f, GOLD)


def square(path, s=512):
    w = h = s * SS
    img = background(w, h)
    d = ImageDraw.Draw(img)
    centered(d, w / 2, h * 0.075, "QuickSave", font(BOLD, 74), TEXT)
    centered(d, w / 2, h * 0.245, "for Queens Domain", font(REG, 28), MUTED)
    k = w * 0.30
    gap = w * 0.08
    x0 = (w - 2 * k - gap) / 2
    ky = h * 0.40
    kf = font(MONO, 64)
    keycap(img, x0, ky, k, "F5", kf)
    keycap(img, x0 + k + gap, ky, k, "F9", kf)
    d = ImageDraw.Draw(img)
    lf = font(BOLD, 30)
    centered(d, x0 + k / 2, ky + k * 1.18, "SAVE", lf, TEXT)
    centered(d, x0 + k * 1.5 + gap, ky + k * 1.18, "LOAD", lf, TEXT)
    centered(d, w / 2, h * 0.915, "unofficial mod · by derlocke-ng", font(REG, 22), MUTED)
    img.resize((s, s), Image.LANCZOS).save(path)


def banner(path, w0=1280, h0=720):
    w, h = w0 * SS, h0 * SS
    img = background(w, h)
    d = ImageDraw.Draw(img)
    lx = w * 0.07
    tf = font(BOLD, 120)
    l, t, r, b = d.textbbox((0, 0), "QuickSave", font=tf)
    d.text((lx - l, h * 0.26 - t), "QuickSave", font=tf, fill=TEXT)
    sf = font(REG, 44)
    d.text((lx, h * 0.26 + (b - t) + h * 0.05), "for Queens Domain", font=sf, fill=MUTED)
    bf = font(REG, 34)
    lines = ["F5  quicksave anywhere", "F9 ×2  load it, even after death", "your normal saves stay untouched"]
    y = h * 0.60
    for i, line in enumerate(lines):
        d.ellipse([lx, y + 14 * SS, lx + 12 * SS, y + 26 * SS], fill=GOLD)
        d.text((lx + 30 * SS, y), line, font=bf, fill=TEXT if i < 2 else MUTED)
        y += 58 * SS
    k = h * 0.30
    gap = k * 0.18
    kx = w - lx - (2 * k + gap) - k * 0.05   # right margin = left margin (minus the shadow offset)
    ky = h * 0.30
    kf = font(MONO, 84)
    keycap(img, kx, ky, k, "F5", kf)
    keycap(img, kx + k + gap, ky, k, "F9", kf)
    d = ImageDraw.Draw(img)
    lf = font(BOLD, 44)
    centered(d, kx + k / 2, ky + k * 1.20, "SAVE", lf, TEXT)
    centered(d, kx + k * 1.5 + gap, ky + k * 1.20, "LOAD", lf, TEXT)
    credit = "unofficial mod · by derlocke-ng"
    d.text((w - lx - d.textbbox((0, 0), credit, font=font(REG, 28))[2], h * 0.915), credit,
           font=font(REG, 28), fill=MUTED)
    img.resize((w0, h0), Image.LANCZOS).save(path)


square(f"{OUT}/steam-guide-preview-512.png")
banner(f"{OUT}/steam-guide-banner-1280x720.png")
print("ok")
