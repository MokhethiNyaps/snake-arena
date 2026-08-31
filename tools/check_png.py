#!/usr/bin/env python3
"""Blank-frame detector for sandbox-rendered screenshots.

Rendered runs happen under Xvfb + llvmpipe (no GPU, no display). The agent
has no vision, so "the scene rendered" is verified by decoding the PNG and
checking for content: colour diversity, brightness variance, and spatial
structure (neighbouring rows must not all be identical).

Usage: python3 tools/check_png.py /path/to/shot.png
Exit 0 = real render (varied content), 1 = likely blank/uniform frame.
"""
import sys
import zlib
import struct


def unfilter(raw: bytes, w: int, h: int, bpp: int) -> bytes:
    stride = w * bpp
    out = bytearray()
    prev = bytearray(stride)
    pos = 0
    for _ in range(h):
        f = raw[pos]
        pos += 1
        line = bytearray(raw[pos:pos + stride])
        pos += stride
        if f == 1:  # Sub
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 0xFF
        elif f == 2:  # Up
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif f == 3:  # Average
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif f == 4:  # Paeth
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        out += line
        prev = line
    return bytes(out)


def load_png(path: str):
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    pos = 8
    w = h = None
    idat = b""
    while pos < len(data):
        ln = struct.unpack(">I", data[pos:pos + 4])[0]
        typ = data[pos + 4:pos + 8]
        if typ == b"IHDR":
            w, h = struct.unpack(">II", data[pos + 8:pos + 16])
        elif typ == b"IDAT":
            idat += data[pos + 8:pos + 8 + ln]
        pos += 12 + ln
    return unfilter(zlib.decompress(idat), w, h, 4), w, h


def check(path: str) -> bool:
    raw, w, h = load_png(path)
    total = w * h
    quant = set()
    bright = 0
    bright_sum = 0
    row_sums = []
    for y in range(h):
        row = y * w * 4
        s = 0
        for x in range(0, w, 2):  # sample every 2nd pixel for speed
            i = row + x * 4
            r, g, b = raw[i], raw[i + 1], raw[i + 2]
            lum = r + g + b
            quant.add((r >> 4, g >> 4, b >> 4))
            s += lum
            if lum > 120:
                bright += 1
                bright_sum += lum
        row_sums.append(s)
    sampled = (w // 2) * h
    mean = sum(row_sums) / sampled if sampled else 0
    var = sum((s - mean) ** 2 for s in row_sums) / h if h else 0
    std = var ** 0.5
    bright_frac = bright / sampled
    # content criteria:
    # 1. colour diversity (>= 8 quantized colours)
    # 2. row-to-row brightness structure (std of row sums > 0.5% of mean)
    # 3. at least a few bright pixels but not a solid wash (< 90%)
    ok = len(quant) >= 8 and std > max(0.005 * mean, 2.0) and 0.0002 < bright_frac < 0.9
    print(f"{path}: {w}x{h}, colors(4bit)={len(quant)}, row_std={std:.1f} "
          f"(mean={mean:.1f}), bright_px={100.0 * bright_frac:.2f}%")
    print("VERDICT:", "real render (varied content)" if ok else "likely blank/uniform frame")
    return ok


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(0 if check(sys.argv[1]) else 1)
