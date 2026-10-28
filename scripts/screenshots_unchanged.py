"""Puts back the committed screenshots that a new capture changed only slightly.

Text antialiasing varies a little from one run to the next and the Dynamic Island is sometimes caught
mid-animation: without this, every run of the Screenshots workflow would commit new images for nothing. A screenshot
counts as changed when its size changed, or when more than THRESHOLD % of its pixels below the status bar differ
strongly (by more than STRONG on 0-255): a changed word or colour does, antialiasing does not.

Usage: python scripts/screenshots_unchanged.py appstore/screenshots screenshots
"""

import subprocess
import sys
from io import BytesIO
from pathlib import Path

from PIL import Image, ImageChops

THRESHOLD = 0.1
STRONG = 64
# Status bar and Dynamic Island: the top 7 % of the screen.
STATUS_BAR = 0.07


def committed(path: Path) -> Image.Image | None:
    result = subprocess.run(["git", "show", f"HEAD:{path.as_posix()}"], capture_output=True, check=False)
    return Image.open(BytesIO(result.stdout)).convert("RGB") if result.returncode == 0 else None


def main(folders: list[str]) -> None:
    for folder in folders:
        for path in sorted(Path(folder).rglob("*.png")):
            old = committed(path)
            if old is None:
                continue
            new = Image.open(path).convert("RGB")
            if new.size != old.size:
                print(f"changed (size): {path}")
                continue
            top = round(new.height * STATUS_BAR)
            box = (0, top, new.width, new.height)
            diff = ImageChops.difference(new.crop(box), old.crop(box)).convert("L")
            strong = sum(diff.histogram()[STRONG + 1 :]) / (diff.width * diff.height) * 100
            if strong <= THRESHOLD:
                subprocess.run(["git", "checkout", "--", str(path)], check=True)
            else:
                print(f"changed ({strong:.3f} %): {path}")


if __name__ == "__main__":
    main(sys.argv[1:])
