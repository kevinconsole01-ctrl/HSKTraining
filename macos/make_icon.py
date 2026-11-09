#!/usr/bin/env python3
"""Genera AppIcon.icns per l'app macOS Zìgé."""

from pathlib import Path
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
SIZE = 1024
PAPER = (240, 241, 238, 255)
PAPER_HI = (248, 249, 246, 255)
RULE = (214, 218, 212, 255)
INK = (22, 24, 26, 255)
INK_SOFT = (134, 140, 132, 255)
SEAL = (179, 35, 42, 255)


def rounded_rect(draw, box, radius, fill=None, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def dashed_line(draw, start, end, fill, width, dash=22, gap=18):
    x1, y1 = start
    x2, y2 = end
    dx, dy = x2 - x1, y2 - y1
    length = (dx * dx + dy * dy) ** 0.5
    if length == 0:
        return
    ux, uy = dx / length, dy / length
    pos = 0.0
    while pos < length:
        seg_end = min(pos + dash, length)
        draw.line(
            (
                x1 + ux * pos,
                y1 + uy * pos,
                x1 + ux * seg_end,
                y1 + uy * seg_end,
            ),
            fill=fill,
            width=width,
        )
        pos += dash + gap


def make_icon():
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    # Ombra morbida sotto la piastra.
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    rounded_rect(shadow_draw, (72, 90, 952, 970), 210, fill=(0, 0, 0, 70))
    shadow = shadow.filter(ImageFilter.GaussianBlur(26))
    image.alpha_composite(shadow)

    # Piastra di carta.
    plate = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    plate_draw = ImageDraw.Draw(plate)
    rounded_rect(plate_draw, (72, 72, 952, 952), 210, fill=PAPER, outline=RULE, width=6)

    # Leggero riflesso in alto, senza gradienti invadenti.
    rounded_rect(plate_draw, (92, 92, 932, 500), 190, fill=PAPER_HI)

    # Griglia 米字格.
    left, top, right, bottom = 206, 206, 818, 818
    plate_draw.rectangle((left, top, right, bottom), outline=INK, width=16)
    cx, cy = (left + right) // 2, (top + bottom) // 2
    dashed_line(plate_draw, (left + 20, cy), (right - 20, cy), INK_SOFT, 12)
    dashed_line(plate_draw, (cx, top + 20), (cx, bottom - 20), INK_SOFT, 12)
    dashed_line(plate_draw, (left + 28, top + 28), (right - 28, bottom - 28), INK_SOFT, 9, dash=18, gap=20)
    dashed_line(plate_draw, (right - 28, top + 28), (left + 28, bottom - 28), INK_SOFT, 9, dash=18, gap=20)

    # Timbro rosso leggermente ruotato.
    seal_size = 286
    seal = Image.new("RGBA", (seal_size, seal_size), (0, 0, 0, 0))
    seal_draw = ImageDraw.Draw(seal)
    rounded_rect(seal_draw, (4, 4, seal_size - 4, seal_size - 4), 28, fill=SEAL)
    rounded_rect(
        seal_draw,
        (20, 20, seal_size - 20, seal_size - 20),
        18,
        outline=(255, 255, 255, 70),
        width=3,
    )

    font_path = "/System/Library/Fonts/Supplemental/Songti.ttc"
    try:
        font = ImageFont.truetype(font_path, 218, index=0)
    except OSError:
        font = ImageFont.truetype("/System/Library/Fonts/PingFang.ttc", 218, index=2)

    text = "字"
    box = seal_draw.textbbox((0, 0), text, font=font)
    text_w = box[2] - box[0]
    text_h = box[3] - box[1]
    seal_draw.text(
        ((seal_size - text_w) / 2 - box[0], (seal_size - text_h) / 2 - box[1]),
        text,
        font=font,
        fill=(255, 255, 255, 255),
    )

    seal = seal.rotate(-4, resample=Image.BICUBIC, expand=True)
    plate.alpha_composite(
        seal,
        ((SIZE - seal.width) // 2, (SIZE - seal.height) // 2),
    )

    image.alpha_composite(plate)
    return image


def write_iconset(image: Image) -> Path:
    iconset = HERE / "Zige.iconset"
    if iconset.exists():
        for child in iconset.iterdir():
            child.unlink()
    else:
        iconset.mkdir()

    for base in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            pixels = base * scale
            name = f"icon_{base}x{base}{'@2x' if scale == 2 else ''}.png"
            image.resize((pixels, pixels), Image.LANCZOS).save(iconset / name)

    return iconset


def main() -> int:
    image = make_icon()
    image.save(HERE / "icon-1024.png")

    iconset = write_iconset(image)
    icns = HERE / "AppIcon.icns"
    subprocess.run(
        ["iconutil", "-c", "icns", str(iconset), "-o", str(icns)],
        check=True,
    )
    print(f"Generato {icns}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
