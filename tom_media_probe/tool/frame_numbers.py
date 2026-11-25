#!/usr/bin/env python3
"""Reads the frame number out of JPEGs the extraction run kept (PROBE_KEEP),
where the run itself could not (no graphics context, as over SSH).

    python3 tool/frame_numbers.py <folder with frame_*.jpg>

A fixture's frame carries its number in the top strip: 20 squares of 16x24
pixels in a 320x240 picture, square b white when bit b is set. Needs Pillow.
"""
import glob
import os
import re
import sys

from PIL import Image


def number(path: str) -> int:
    image = Image.open(path).convert('L')
    width, height = image.size
    y = int(12 / 240 * height)
    value = 0
    for bit in range(20):
        x = int((bit + 0.5) * 16 / 320 * width)
        if image.getpixel((x, y)) > 128:
            value |= 1 << bit
    return value


def main() -> int:
    for path in sorted(glob.glob(os.path.join(sys.argv[1], 'frame_*.jpg'))):
        name = os.path.basename(path)
        asked = int(re.search(r'_(\d+)\.jpg$', name).group(1))
        print(f'{name}: frame {number(path)}, asked {asked} ms '
              f'(frame {asked * 30 // 1000})')
    return 0


if __name__ == '__main__':
    sys.exit(main())
