"""Builds windows/runner/resources/app_icon.ico from assets/logo.png.

The logo is a full square; Start, the taskbar and the installer show the icon
with rounded corners, like other modern Windows apps. Corners are cut with an
anti-aliased mask drawn at 4x and scaled down.

    python tool/app_icon.py
"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "assets" / "logo.png"
TARGET = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
SIZES = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256]
# Share of the side used as the corner radius.
RADIUS = 0.22
SUPERSAMPLE = 4


def rounded(logo: Image.Image, size: int) -> Image.Image:
    image = logo.resize((size, size), Image.Resampling.LANCZOS)
    big = size * SUPERSAMPLE
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, big - 1, big - 1), radius=round(big * RADIUS), fill=255
    )
    image.putalpha(mask.resize((size, size), Image.Resampling.LANCZOS))
    return image


def main() -> None:
    logo = Image.open(SOURCE).convert("RGB")
    frames = [rounded(logo, size) for size in SIZES]
    frames[-1].save(
        TARGET,
        format="ICO",
        sizes=[(size, size) for size in SIZES],
        append_images=frames[:-1],
    )


if __name__ == "__main__":
    main()
