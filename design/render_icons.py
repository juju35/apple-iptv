#!/usr/bin/env python3
"""Renders the app icon for iOS, macOS and tvOS from one SVG design.

    python3 design/render_icons.py [--preview out.png]

Needs Python Playwright (Chromium) and Pillow. Writes straight into the asset catalog.
"""

from __future__ import annotations

import argparse
import io
from pathlib import Path

from PIL import Image
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "Sources/Resources/Assets.xcassets"
APPICON = ASSETS / "AppIcon.appiconset"
BRAND = ASSETS / "App Icon & Top Shelf Image.brandassets"

# Palette: deep cinema red, lit from the top.
BG_TOP = "#ff4a5c"
BG_MID = "#d0122f"
BG_BOTTOM = "#5c0414"

DEFS = f"""
<defs>
  <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="{BG_TOP}"/>
    <stop offset="0.45" stop-color="{BG_MID}"/>
    <stop offset="1" stop-color="{BG_BOTTOM}"/>
  </linearGradient>
  <radialGradient id="sheen" cx="0.3" cy="0.05" r="0.9">
    <stop offset="0" stop-color="#fff" stop-opacity="0.18"/>
    <stop offset="0.6" stop-color="#fff" stop-opacity="0"/>
  </radialGradient>
  <radialGradient id="vignette" cx="0.5" cy="0.45" r="0.75">
    <stop offset="0.6" stop-color="#000" stop-opacity="0"/>
    <stop offset="1" stop-color="#000" stop-opacity="0.35"/>
  </radialGradient>
  <linearGradient id="glass" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#fff" stop-opacity="0.22"/>
    <stop offset="1" stop-color="#fff" stop-opacity="0.06"/>
  </linearGradient>
  <linearGradient id="rim" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#fff" stop-opacity="1"/>
    <stop offset="1" stop-color="#fff" stop-opacity="0.82"/>
  </linearGradient>
  <filter id="lift" x="-60%" y="-60%" width="220%" height="240%">
    <feDropShadow dx="0" dy="14" stdDeviation="20" flood-color="#3a0008" flood-opacity="0.40"/>
  </filter>
</defs>
"""

# Glyph in a 1024 x 1024 space: a glass screen with a play triangle and a stand bar.
SCREEN = '<rect x="196" y="250" width="632" height="430" rx="104"/>'
PLAY = '<path d="M452 386 L452 544 L589 465 Z" stroke-linejoin="round" stroke-width="58"/>'
STAND = '<rect x="400" y="732" width="224" height="40" rx="20"/>'


def glyph(screen: bool = True, play: bool = True) -> str:
    parts = []
    if screen:
        parts.append(f"""
  <g filter="url(#lift)">
    <g fill="url(#glass)" stroke="url(#rim)" stroke-width="32">{SCREEN}</g>
    <g fill="#fff" opacity="0.92">{STAND}</g>
  </g>""")
    if play:
        parts.append(f"""
  <g filter="url(#lift)" fill="#fff" stroke="#fff">{PLAY}</g>""")
    return "".join(parts)


def background(width: int, height: int) -> str:
    return f"""
  <rect width="{width}" height="{height}" fill="url(#bg)"/>
  <rect width="{width}" height="{height}" fill="url(#sheen)"/>
  <rect width="{width}" height="{height}" fill="url(#vignette)"/>"""


def svg(width: int, height: int, body: str) -> str:
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}">{DEFS}{body}</svg>'
    )


def placed(content: str, width: int, height: int, glyph_height: float) -> str:
    """Centers 1024-space content at a given rendered height."""
    scale = glyph_height / 1024
    dx = (width - 1024 * scale) / 2
    dy = (height - 1024 * scale) / 2
    return f'<g transform="translate({dx:.2f} {dy:.2f}) scale({scale:.5f})">{content}</g>'


def ios() -> str:
    return svg(1024, 1024, background(1024, 1024) + glyph())


def macos() -> str:
    # Big Sur+ grid: 824 pt body inset in the 1024 canvas, continuous-corner squircle, soft shadow.
    body = (
        '<clipPath id="squircle"><rect x="100" y="100" width="824" height="824" rx="185"/></clipPath>'
        '<filter id="mac-shadow" x="-20%" y="-20%" width="140%" height="150%">'
        '<feDropShadow dx="0" dy="12" stdDeviation="14" flood-color="#000" flood-opacity="0.32"/></filter>'
        '<rect x="100" y="100" width="824" height="824" rx="185" fill="#000" filter="url(#mac-shadow)"/>'
        f'<g clip-path="url(#squircle)">{background(1024, 1024)}'
        f'{placed(glyph(), 1024, 1024, 824)}</g>'
        '<rect x="100.5" y="100.5" width="823" height="823" rx="185" fill="none" '
        'stroke="#fff" stroke-opacity="0.18"/>'
    )
    return svg(1024, 1024, body)


def tv_back(width: int, height: int) -> str:
    return svg(width, height, background(width, height) + placed(glyph(play=False), width, height, height * 0.95))


def tv_front(width: int, height: int) -> str:
    return svg(width, height, placed(glyph(screen=False), width, height, height * 0.95))


def top_shelf(width: int, height: int) -> str:
    return svg(width, height, background(width, height) + placed(glyph(), width, height, height * 0.8))


def render(page, markup: str, width: int, height: int, transparent: bool) -> Image.Image:
    page.set_viewport_size({"width": width, "height": height})
    page.set_content(f'<html><body style="margin:0;background:transparent">{markup}</body></html>')
    png = page.screenshot(omit_background=transparent, clip={"x": 0, "y": 0, "width": width, "height": height})
    image = Image.open(io.BytesIO(png))
    return image.convert("RGBA" if transparent else "RGB")


def save(image: Image.Image, path: Path, size: tuple[int, int] | None = None) -> None:
    if size and image.size != size:
        image = image.resize(size, Image.LANCZOS)
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview", type=Path, help="only write a preview sheet to this path")
    args = parser.parse_args()

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch()
        page = browser.new_page()
        ios_icon = render(page, ios(), 1024, 1024, transparent=False)
        mac_icon = render(page, macos(), 1024, 1024, transparent=True)

        if args.preview:
            sheet = Image.new("RGB", (2088, 1064), "#f2f2f7")
            sheet.paste(ios_icon, (20, 20))
            sheet.paste(mac_icon, (1044, 20), mac_icon)
            save(sheet, args.preview)
            browser.close()
            return

        save(ios_icon, APPICON / "AppIcon-iOS.png")
        for points in (16, 32, 128, 256, 512):
            save(mac_icon, APPICON / f"AppIcon-mac-{points}.png", (points, points))
            save(mac_icon, APPICON / f"AppIcon-mac-{points}@2x.png", (points * 2, points * 2))

        for stack, (width, height), scales in (
            ("App Icon.imagestack", (400, 240), (1, 2)),
            ("App Icon - App Store.imagestack", (1280, 768), (1,)),
        ):
            for scale in scales:
                suffix = "" if scale == 1 else f"@{scale}x"
                w, h = width * scale, height * scale
                back = render(page, tv_back(w, h), w, h, transparent=False)
                front = render(page, tv_front(w, h), w, h, transparent=True)
                save(back, BRAND / stack / f"Back.imagestacklayer/Content.imageset/Back{suffix}.png")
                save(front, BRAND / stack / f"Front.imagestacklayer/Content.imageset/Front{suffix}.png")

        for name, width in (("Top Shelf Image.imageset", 1920), ("Top Shelf Image Wide.imageset", 2320)):
            for scale in (1, 2):
                suffix = "" if scale == 1 else f"@{scale}x"
                w, h = width * scale, 720 * scale
                save(render(page, top_shelf(w, h), w, h, transparent=False), BRAND / name / f"TopShelf{suffix}.png")

        browser.close()


if __name__ == "__main__":
    main()
