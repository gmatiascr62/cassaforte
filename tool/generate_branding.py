"""Genera los recursos de Android (icono y pantalla de inicio) a partir de
branding/icon.png y branding/presplash.png.

Uso: python3 tool/generate_branding.py   (requiere Pillow)
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android/app/src/main/res"
BG = (3, 60, 36)  # Verde de fondo de las imágenes.
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def extract(img: Image.Image) -> Image.Image:
    """Separa el dibujo dorado/crema del fondo verde (canal rojo como clave)."""
    img = img.convert("RGB")
    out = Image.new("RGBA", img.size)
    src, dst = img.load(), out.load()
    lo, hi = 35, 110
    for y in range(img.height):
        for x in range(img.width):
            r, g, b = src[x, y]
            a = min(1.0, max(0.0, (r - lo) / (hi - lo)))
            if a == 0:
                dst[x, y] = (0, 0, 0, 0)
                continue
            fg = [
                min(255, max(0, round((c - (1 - a) * bc) / a)))
                for c, bc in zip((r, g, b), BG)
            ]
            dst[x, y] = (*fg, round(a * 255))
    return out.crop(out.getbbox())


def centered(art: Image.Image, size: int, fraction: float) -> Image.Image:
    """Coloca [art] centrado en un lienzo transparente cuadrado."""
    scale = fraction * size / max(art.size)
    w, h = round(art.width * scale), round(art.height * scale)
    canvas = Image.new("RGBA", (size, size))
    canvas.alpha_composite(art.resize((w, h), Image.LANCZOS), ((size - w) // 2, (size - h) // 2))
    return canvas


def main() -> None:
    icon = Image.open(ROOT / "branding/icon.png").convert("RGB")
    emblem = extract(icon)

    for name, d in DENSITIES.items():
        folder = RES / f"mipmap-{name}"
        folder.mkdir(parents=True, exist_ok=True)
        # Icono clásico (Android 7 y anteriores): imagen completa.
        legacy = round(48 * d)
        icon.resize((legacy, legacy), Image.LANCZOS).save(folder / "ic_launcher.png", optimize=True)
        # Primer plano adaptativo (108 dp; el emblema dentro de la zona segura de 66 dp).
        size = round(108 * d)
        fg = centered(emblem, size, 0.56)
        fg.save(folder / "ic_launcher_foreground.png", optimize=True)
        # Versión monocroma para iconos temáticos (Android 13+).
        mono = Image.new("RGBA", fg.size, (255, 255, 255, 0))
        mono.putalpha(fg.getchannel("A"))
        mono.save(folder / "ic_launcher_monochrome.png", optimize=True)
        # Icono de la pantalla de inicio de Android 12+ (288 dp, círculo de 192 dp).
        splash_dir = RES / f"drawable-{name}"
        splash_dir.mkdir(parents=True, exist_ok=True)
        centered(emblem, round(288 * d), 0.58).save(splash_dir / "splash_icon.png", optimize=True)
        # Pantalla de inicio de Android 11 y anteriores: emblema y nombre.
        presplash = extract(Image.open(ROOT / "branding/presplash.png"))
        target_w = round(170 * d)
        h = round(presplash.height * target_w / presplash.width)
        presplash.resize((target_w, h), Image.LANCZOS).save(splash_dir / "launch_logo.png", optimize=True)


if __name__ == "__main__":
    main()
