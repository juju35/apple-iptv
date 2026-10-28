"""Finishes scripts/screenshots.sh's captures.

- App Store Connect refuses screenshots with an alpha channel: the PNGs are flattened in place.
- The README shows smaller copies (screenshots/, 600 px wide for iPhone, 1000 px for iPad, 800 px for iPhone Duo,
  960 px for Apple TV).

Usage: python scripts/screenshots_post.py appstore/screenshots screenshots
"""

import sys
from pathlib import Path

from PIL import Image

# Folder: (README file prefix, width).
README = {
    "iphone-6.9": ("iphone", 600),
    "ipad-13": ("ipad", 1000),
    "iphone-duo": ("duo", 800),
    "apple-tv": ("tv", 960),
}


def main(source: Path, readme: Path) -> None:
    readme.mkdir(exist_ok=True)
    for old in readme.glob("*.png"):
        old.unlink()
    for folder, (prefix, width) in README.items():
        for path in sorted((source / folder).glob("*.png")):
            image = Image.open(path).convert("RGB")
            image.save(path, optimize=True)
            height = round(image.height * width / image.width)
            small = image.resize((width, height), Image.Resampling.LANCZOS)
            target = readme / f"{prefix}-{path.name}"
            small.save(target, optimize=True)
            print(target)


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
