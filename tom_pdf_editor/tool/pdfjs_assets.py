#!/usr/bin/env python3
# Copyright (c) 2026 Peter Nicolai Alexis Kyaw
# SPDX-License-Identifier: BSD-3-Clause
"""Writes the asset list of the vendored pdf.js into pubspec.yaml.

Flutter's `assets:` takes folders one level deep, so every folder of
`third_party/pdfjs/<version>/` is listed between the markers
`# pdfjs-assets: begin` and `# pdfjs-assets: end`. Run it from the package
root after taking in a new pdf.js release: `python3 tool/pdfjs_assets.py`
(`--check` exits 1 when the list is out of date).
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BEGIN = "    # pdfjs-assets: begin"
END = "    # pdfjs-assets: end"


def folders():
    base = os.path.join(ROOT, "third_party", "pdfjs")
    out = []
    for path, dirs, files in os.walk(base):
        dirs.sort()
        if any(not f.startswith(".") for f in files):
            rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
            out.append(rel + "/")
    return sorted(out)


def main():
    pubspec = os.path.join(ROOT, "pubspec.yaml")
    text = open(pubspec).read()
    if BEGIN not in text or END not in text:
        sys.exit("pubspec.yaml has no pdfjs-assets markers")
    head, rest = text.split(BEGIN, 1)
    _, tail = rest.split(END, 1)
    block = BEGIN + "\n" + "".join(f"    - {f}\n" for f in folders()) + END
    new = head + block + tail
    if "--check" in sys.argv:
        sys.exit(0 if new == text else 1)
    open(pubspec, "w").write(new)


if __name__ == "__main__":
    main()
