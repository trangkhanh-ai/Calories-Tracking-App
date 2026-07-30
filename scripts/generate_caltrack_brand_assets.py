"""Generate the committed CalTrack branding PNG assets.

Usage:
    python scripts/generate_caltrack_brand_assets.py
"""

from __future__ import annotations

import json
import os
import platform
import shutil
import subprocess
import tempfile
from decimal import Decimal
from pathlib import Path

from PIL import Image, __version__ as PILLOW_VERSION


ROOT = Path(__file__).resolve().parents[1]
SVG_PATH = ROOT / "docs/assets/branding/caltrack-mark.svg"
IOS_CATALOG = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json"
CANVAS_SIZE = 1024
BACKGROUND = (0xF7, 0xF9, 0xFC, 0xFF)
LANCZOS = Image.Resampling.LANCZOS


def locate_chrome() -> Path:
    candidates: list[Path] = []
    configured = os.environ.get("CHROME_PATH")
    if configured:
        candidates.append(Path(configured).expanduser())

    system = platform.system()
    if system == "Windows":
        for variable in ("PROGRAMFILES", "PROGRAMFILES(X86)", "LOCALAPPDATA"):
            base = os.environ.get(variable)
            if base:
                candidates.append(
                    Path(base) / "Google/Chrome/Application/chrome.exe"
                )
        candidates.append(Path("C:/Program Files/Chromium/Application/chrome.exe"))
    elif system == "Darwin":
        candidates.extend(
            [
                Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"),
                Path.home()
                / "Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                Path("/Applications/Chromium.app/Contents/MacOS/Chromium"),
            ]
        )
    else:
        candidates.extend(
            Path(path)
            for path in (
                "/usr/bin/google-chrome",
                "/usr/bin/google-chrome-stable",
                "/usr/bin/chromium",
                "/usr/bin/chromium-browser",
                "/snap/bin/chromium",
            )
        )

    for executable in (
        "google-chrome",
        "google-chrome-stable",
        "chromium",
        "chromium-browser",
    ):
        resolved = shutil.which(executable)
        if resolved:
            candidates.append(Path(resolved))

    checked: set[Path] = set()
    for candidate in candidates:
        candidate = candidate.resolve()
        if candidate in checked:
            continue
        checked.add(candidate)
        if candidate.is_file():
            return candidate

    raise FileNotFoundError(
        "Chrome was not found. Set CHROME_PATH to a local Chrome executable."
    )


def render_svg(
    chrome: Path,
    svg: str,
    background: str,
    destination: Path,
    profile_directory: Path,
) -> Image.Image:
    html = f"""<!doctype html>
<html><head><meta charset="utf-8"><style>
html, body {{ margin: 0; width: {CANVAS_SIZE}px; height: {CANVAS_SIZE}px;
  overflow: hidden; background: {background}; }}
svg {{ display: block; width: {CANVAS_SIZE}px; height: {CANVAS_SIZE}px; }}
</style></head><body>{svg}</body></html>
"""
    html_path = destination.with_suffix(".html")
    html_path.write_text(html, encoding="utf-8", newline="\n")

    command = [
        str(chrome),
        "--headless",
        "--disable-background-networking",
        "--disable-extensions",
        "--disable-gpu",
        "--disable-sync",
        "--hide-scrollbars",
        "--no-first-run",
        "--force-device-scale-factor=1",
        f"--user-data-dir={profile_directory}",
        f"--window-size={CANVAS_SIZE},{CANVAS_SIZE}",
        "--default-background-color=00000000",
        f"--screenshot={destination}",
        html_path.as_uri(),
    ]
    if platform.system() == "Linux" and hasattr(os, "geteuid") and os.geteuid() == 0:
        command.insert(1, "--no-sandbox")

    result = subprocess.run(command, capture_output=True, text=True, check=False)
    if result.returncode != 0 or not destination.is_file():
        details = (result.stderr or result.stdout).strip()
        raise RuntimeError(f"Chrome failed to render {html_path.name}: {details}")

    with Image.open(destination) as rendered:
        if rendered.size != (CANVAS_SIZE, CANVAS_SIZE):
            raise RuntimeError(
                f"Chrome rendered {rendered.size}, expected "
                f"{CANVAS_SIZE}x{CANVAS_SIZE}"
            )
        return rendered.convert("RGBA")


def resized(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    return image.resize(size, LANCZOS)


def centered_mark(
    mark_master: Image.Image,
    size: int,
    background: tuple[int, int, int, int],
) -> Image.Image:
    mark_size = round(size * 0.60)
    mark = resized(mark_master, (mark_size, mark_size))
    canvas = Image.new("RGBA", (size, size), background)
    offset = ((size - mark_size) // 2, (size - mark_size) // 2)
    canvas.alpha_composite(mark, offset)
    return canvas


def save_png(image: Image.Image, relative_path: str) -> None:
    output = ROOT / relative_path
    output.parent.mkdir(parents=True, exist_ok=True)
    image.save(output, format="PNG", compress_level=9, optimize=False)


def ios_catalog_outputs() -> list[tuple[str, tuple[int, int]]]:
    catalog = json.loads(IOS_CATALOG.read_text(encoding="utf-8"))
    outputs: list[tuple[str, tuple[int, int]]] = []
    for entry in catalog["images"]:
        filename = entry["filename"]
        width, height = (Decimal(value) for value in entry["size"].split("x"))
        scale = Decimal(entry["scale"].removesuffix("x"))
        pixel_width = width * scale
        pixel_height = height * scale
        if pixel_width != pixel_width.to_integral_value() or pixel_height != pixel_height.to_integral_value():
            raise ValueError(f"Non-integral AppIcon dimensions for {filename}")
        outputs.append(
            (
                f"ios/Runner/Assets.xcassets/AppIcon.appiconset/{filename}",
                (int(pixel_width), int(pixel_height)),
            )
        )
    return outputs


def main() -> None:
    chrome = locate_chrome()
    svg = SVG_PATH.read_text(encoding="utf-8")

    with tempfile.TemporaryDirectory(prefix="caltrack-brand-") as temporary:
        temp = Path(temporary)
        mark_master = render_svg(
            chrome,
            svg,
            "transparent",
            temp / "mark.png",
            temp / "chrome-mark-profile",
        )
        rendered_icon = render_svg(
            chrome,
            svg,
            "#F7F9FC",
            temp / "app-icon.png",
            temp / "chrome-icon-profile",
        )
        app_icon_master = Image.new("RGBA", rendered_icon.size, BACKGROUND)
        app_icon_master.alpha_composite(rendered_icon)

        for path, size in {
            "assets/branding/caltrack-mark.png": 256,
            "web/favicon.png": 32,
            "web/icons/favicon-16.png": 16,
            "web/icons/favicon-32.png": 32,
        }.items():
            source = mark_master if path.endswith("caltrack-mark.png") else app_icon_master
            save_png(resized(source, (size, size)), path)

        for path, size in {
            "assets/branding/caltrack-logo.png": 512,
            "web/icons/Icon-192.png": 192,
            "web/icons/Icon-512.png": 512,
            "web/icons/apple-touch-icon-180.png": 180,
            "android/app/src/main/res/mipmap-mdpi/ic_launcher.png": 48,
            "android/app/src/main/res/mipmap-hdpi/ic_launcher.png": 72,
            "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png": 96,
            "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png": 144,
            "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png": 192,
        }.items():
            save_png(resized(app_icon_master, (size, size)), path)

        for size in (192, 512):
            save_png(
                centered_mark(mark_master, size, BACKGROUND),
                f"web/icons/Icon-maskable-{size}.png",
            )

        save_png(
            centered_mark(mark_master, 432, (0, 0, 0, 0)),
            "android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png",
        )

        for path, size in ios_catalog_outputs():
            save_png(resized(app_icon_master, size), path)

    print(f"Generated CalTrack brand assets with {chrome}")
    print(f"Pillow {PILLOW_VERSION}; resize filter: LANCZOS")


if __name__ == "__main__":
    main()
