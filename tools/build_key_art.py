"""Builds the key art: the title logo (assets/ui/logo.png, from tools/build_logo.py) on black.

  assets/ui/splash.png           1920x1080, the boot splash and title screen: the logo centred
  assets/ui/wallpaper.png        1920x1080, behind the menus: plain black (the main menu draws
                                 the logo itself)
  dist/itch/01_cover_630x500.png the itch.io cover: the logo centred (dist/itch/ is local only)

The black is the boot splash / clear colour in project.godot (0.03, 0.03, 0.05), so the boot
splash, title screen and menus run into each other without a seam. Run: python tools/build_key_art.py
(then re-import in Godot, or the game keeps showing the old images).
"""
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOGO = os.path.join(ROOT, "assets", "ui", "logo.png")
BLACK = (8, 8, 13)  # Color(0.03, 0.03, 0.05)
# [path, size, logo width as a share of the image width]
OUTPUTS = [
    (os.path.join(ROOT, "assets", "ui", "splash.png"), (1920, 1080), 0.62),
    (os.path.join(ROOT, "assets", "ui", "wallpaper.png"), (1920, 1080), 0.0),
    (os.path.join(ROOT, "dist", "itch", "01_cover_630x500.png"), (630, 500), 0.88),
]


def main() -> None:
    logo = Image.open(LOGO).convert("RGBA")
    for path, size, share in OUTPUTS:
        if not os.path.isdir(os.path.dirname(path)):
            print(f"skipped {path} (no folder)")
            continue
        image = Image.new("RGBA", size, BLACK + (255,))
        if share > 0.0:
            width = round(size[0] * share)
            height = round(logo.height * width / logo.width)
            scaled = logo.resize((width, height), Image.LANCZOS)
            image.alpha_composite(scaled, ((size[0] - width) // 2, (size[1] - height) // 2))
        image.convert("RGB").save(path)
        print(f"wrote {path} {size[0]}x{size[1]}")


if __name__ == "__main__":
    main()
