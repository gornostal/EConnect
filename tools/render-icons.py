#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
#
# Renders the app icon sizes that meson installs, from the master artwork in
# data/icons/logo.png. Run it after replacing that file:
#
#     ./tools/render-icons.py [path/to/artwork.png]
#
# 32, 48, 64 and 128 are what AppCenter requires; 256 is there for HiDPI.
# Needs python3-pil.

import os
import sys

from PIL import Image, ImageFilter

APP_ID = "io.github.gornostal.econnect"
SIZES = (32, 48, 64, 128, 256)
# Leave a little air so the artwork does not touch the icon's edges.
MARGIN = 0.94

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
icons_dir = os.path.join(root, "data", "icons")
source = sys.argv[1] if len(sys.argv) > 1 else os.path.join(icons_dir, "logo.png")

image = Image.open(source).convert("RGBA")
bbox = image.getchannel("A").getbbox()
if bbox is None:
    sys.exit(f"{source}: the image is fully transparent")
content = image.crop(bbox)
print(f"{source}: {image.size[0]}x{image.size[1]}, artwork {content.size[0]}x{content.size[1]}")

for size in SIZES:
    box = int(round(size * MARGIN))
    width, height = content.size
    scale = min(box / width, box / height)
    if scale > 1:
        print(f"  warning: upscaling to {size}px; the master artwork is too small")
    scaled_size = (max(1, round(width * scale)), max(1, round(height * scale)))

    scaled = content.resize(scaled_size, Image.LANCZOS)
    if size <= 48:
        # Downscaling this far softens the edges; claw a little back.
        scaled = scaled.filter(ImageFilter.UnsharpMask(radius=0.6, percent=60, threshold=2))

    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(scaled, ((size - scaled_size[0]) // 2, (size - scaled_size[1]) // 2), scaled)

    out_dir = os.path.join(icons_dir, str(size))
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, f"{APP_ID}.png")
    canvas.save(out_path, optimize=True)
    print(f"  {os.path.relpath(out_path, root)}: {os.path.getsize(out_path)} bytes")
