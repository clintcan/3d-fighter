"""Builds the brush-painted title logo: assets/ui/logo.png (transparent).

"3D" in white fading to icy blue, "FIGHTER" in yellow fading to orange, both leaning
forward with dry-brush streaks, ragged bristle tails, paint specks, a dark outline and a
coloured glow. Lettering: the Permanent Marker font by Font Diner (Apache 2.0,
tools/fonts/, kept out of the game: only this tool uses it).

Run: python tools/build_logo.py   (needs Pillow and numpy)
"""
import os

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "tools", "fonts", "PermanentMarker-Regular.ttf")
OUT = os.path.join(ROOT, "assets", "ui", "logo.png")
SIZE = 400            # glyph size in pixels
SHEAR = 0.24          # forward lean
SEED = 11

rng = np.random.default_rng(SEED)


def glyphs(text: str) -> np.ndarray:
    """Alpha mask (0..1) of `text`, leaning forward, with margin for tails and glow."""
    font = ImageFont.truetype(FONT, SIZE)
    left, top, right, bottom = font.getbbox(text)
    w, h = right - left + 400, bottom - top + 260
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).text((200 - left, 130 - top), text, font=font, fill=255)
    mask = mask.transform(mask.size, Image.AFFINE, (1, SHEAR, -SHEAR * h * 0.5, 0, 1, 0), Image.BICUBIC)
    return np.asarray(mask).astype(np.float32) / 255.0


def streaks(shape, length: float, seed: int) -> np.ndarray:
    """Noise stretched along x: the bristle pattern of a dry brush (0..1)."""
    r = np.random.default_rng(seed)
    h, w = shape
    small = r.random((h // 3 + 2, max(2, int(w / length)) + 2)).astype(np.float32)
    img = Image.fromarray((small * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
    img = img.filter(ImageFilter.GaussianBlur(1.2))
    return np.asarray(img).astype(np.float32) / 255.0


def dry_brush(alpha: np.ndarray, seed: int, tail_dir: int) -> np.ndarray:
    """Breaks up the edges along the bristle streaks and drags ragged tails off them."""
    s = streaks(alpha.shape, 40.0, seed)
    inner = np.asarray(Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(7))).astype(np.float32) / 255.0
    edge = np.clip(alpha - inner, 0, 1)                       # the outer band of each stroke
    ragged = alpha * np.where(edge > 0.05, (s > 0.25).astype(np.float32), 1.0)
    # Tails: the paint smeared sideways, thinning out, only along some bristles.
    tail = np.zeros_like(alpha)
    bristles = (streaks(alpha.shape, 160.0, seed + 1) > 0.78).astype(np.float32)
    for k in range(4, 130, 2):
        shifted = np.roll(ragged, tail_dir * k, axis=1)
        tail = np.maximum(tail, shifted * bristles * (1.0 - k / 130.0) ** 2.2)
    return np.clip(np.maximum(ragged, (tail > 0.25) * tail), 0, 1)


def specks(alpha: np.ndarray, count: int) -> np.ndarray:
    """Paint flecks thrown off near the strokes."""
    h, w = alpha.shape
    img = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(img)
    near = np.argwhere(np.asarray(Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(61))) > 0)
    for _ in range(count):
        y, x = near[rng.integers(len(near))]
        r = rng.uniform(1.0, 4.5)
        d.ellipse((x - r, y - r * 0.8, x + r, y + r * 0.8), fill=int(rng.uniform(140, 255)))
    return np.asarray(img).astype(np.float32) / 255.0 * (1.0 - alpha)


def paint(alpha: np.ndarray, top: tuple, bottom: tuple, glow: tuple, seed: int) -> Image.Image:
    """Colours a stroke mask: vertical gradient, bristle texture, outline and glow."""
    h, w = alpha.shape
    rows = np.nonzero(alpha.max(axis=1) > 0.5)[0]
    t = np.clip((np.arange(h) - rows.min()) / max(1, rows.max() - rows.min()), 0, 1)[:, None, None]
    color = np.array(top)[None, None, :] * (1 - t) + np.array(bottom)[None, None, :] * t
    texture = 0.93 + 0.07 * streaks(alpha.shape, 30.0, seed + 7)[:, :, None]
    rgb = np.clip(color * texture, 0, 1)
    fill = np.dstack([rgb, alpha])

    a_img = Image.fromarray((alpha * 255).astype(np.uint8))
    outline = np.asarray(a_img.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(1.0))).astype(np.float32) / 255.0
    shadow = np.roll(np.roll(np.asarray(a_img.filter(ImageFilter.GaussianBlur(4))).astype(np.float32) / 255.0, 10, axis=0), 8, axis=1)
    halo = np.asarray(a_img.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(26))).astype(np.float32) / 255.0

    out = np.zeros((h, w, 4), np.float32)
    def over(dst, src):
        a = src[..., 3:4]
        dst[..., :3] = src[..., :3] * a + dst[..., :3] * (1 - a)
        dst[..., 3:4] = a + dst[..., 3:4] * (1 - a)
    over(out, np.dstack([np.broadcast_to(np.array(glow), (h, w, 3)), halo * 0.55]))
    over(out, np.dstack([np.broadcast_to(np.array((0.0, 0.0, 0.05)), (h, w, 3)), shadow * 0.7]))
    over(out, np.dstack([np.broadcast_to(np.array((0.03, 0.04, 0.12)), (h, w, 3)), outline * 0.9]))
    over(out, fill)
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8), "RGBA")


def main() -> None:
    a3d = glyphs("3D")
    afi = glyphs("FIGHTER")
    a3d = np.clip(dry_brush(a3d, SEED, -1) + specks(a3d, 70) * 0.9, 0, 1)
    afi = np.clip(dry_brush(afi, SEED + 3, 1) + specks(afi, 110) * 0.9, 0, 1)
    p3d = paint(a3d, (1.0, 1.0, 1.0), (0.62, 0.8, 1.0), (0.25, 0.55, 1.0), SEED)
    pfi = paint(afi, (1.0, 0.9, 0.32), (1.0, 0.5, 0.08), (1.0, 0.45, 0.05), SEED + 3)
    # "3D" sits a little lower and overlaps "FIGHTER" slightly, like a painted mark.
    gap = -330
    w = p3d.width + pfi.width + gap
    h = max(p3d.height, pfi.height) + 40
    logo = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    logo.alpha_composite(pfi, (p3d.width + gap, 0))
    logo.alpha_composite(p3d, (0, 30))
    logo = logo.crop(logo.getbbox())
    logo.save(OUT, optimize=True)
    print("saved", OUT, logo.size)


if __name__ == "__main__":
    main()
