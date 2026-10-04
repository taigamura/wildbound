#!/usr/bin/env python3
"""Normalize a ChatGPT "pixel art" image into a true HD-2D sprite (docs/HD2D.md, Step 3).

ChatGPT draws on its own rough grid (each "pixel" is a soft ~8-12 px square). This finds
that grid and snaps to it, so every source pixel becomes exactly one sprite pixel: edges
and colour noise get cleaned up, but no detail is merged away. It also makes alpha hard,
drops stray specks (baked-in particles), crops, scales up by a whole number
(nearest-neighbour) to about 512 px, and prints the art-pack manifest numbers.

  python3 scripts/hd2d-sprite.py raw.png out.png                                # humanoid
  python3 scripts/hd2d-sprite.py raw.png out.png --kind monster --size 1.22     # Kilnback
  python3 scripts/hd2d-sprite.py raw.png out.png --palette-from docs/hd2d/anchors/humanoid.png

--kind/--size set the in-game height (the manifest `height`), not the pixel count, so a
sprite drawn on a finer grid shows the same size, just with smaller pixels.

Needs Pillow (pip install pillow).
"""
import argparse
import math
from PIL import Image

HUMANOID_UNITS = 128  # in-game figure height of a humanoid, in art units (docs/HD2D.md)
MONSTER_UNITS = 100   # in-game figure height of a size-1 monster; scaled by species size
MARGIN = 0.12         # empty margin around the figure, as a fraction of its height
TARGET = 512          # rough final image height
GRID_RANGE = (4, 32)  # plausible source pixel sizes, in source px
ISLAND = 0.01         # drop opaque pieces smaller than this share of the largest piece
DARK_SHARE = 1 / 3    # a dark colour covering this much of a cell beats the majority (keeps outlines and eyes)
DARK_GAP = 48         # ...if it is at least this much darker (luma, 0-255) than the majority colour
# Always in the palette, so every sprite can use them: the element accents (ELEM in
# game/src/core/data.ts) and a trim gold.
RESERVED = [(0xFF, 0x6A, 0x3D), (0x34, 0xA8, 0xFF), (0x4F, 0xCF, 0x5C), (0xFF, 0xCF, 0x2E), (0xD4, 0xA7, 0x3A)]


def remove_background(im: Image.Image, tol: int) -> Image.Image:
    """Use the image's own alpha if it has any; otherwise key out the corner colour."""
    im = im.convert('RGBA')
    if im.getextrema()[3][0] < 250:
        return im
    w, h = im.size
    corners = [im.getpixel(p)[:3] for p in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1))]
    bg = tuple(sorted(c[i] for c in corners)[1] for i in range(3))   # robust to one odd corner
    px = im.load()
    for y in range(h):
        for x in range(w):
            r, g, b, _ = px[x, y]
            if abs(r - bg[0]) <= tol and abs(g - bg[1]) <= tol and abs(b - bg[2]) <= tol:
                px[x, y] = (0, 0, 0, 0)
    return im


def opaque_pixels(im: Image.Image) -> list:
    return [p[:3] for p in getattr(im, 'get_flattened_data', im.getdata)() if p[3] >= 128]


def palette_image(src: str | None, colors: int, sprite: Image.Image) -> Image.Image:
    """A 'P' image whose palette is RESERVED plus the anchor's colours (or an adaptive fill)."""
    if src:
        found = sorted(set(opaque_pixels(Image.open(src).convert('RGBA'))))
    else:
        opaque = opaque_pixels(sprite)
        strip = Image.new('RGB', (len(opaque), 1)); strip.putdata(opaque)
        q = strip.quantize(colors=max(1, colors - len(RESERVED)), method=Image.Quantize.MEDIANCUT)
        pal = q.getpalette()[:3 * len(q.getcolors())]
        found = [tuple(pal[i:i + 3]) for i in range(0, len(pal), 3)]
    cols = list(dict.fromkeys(RESERVED + found))[:256]
    p = Image.new('P', (1, 1))
    p.putpalette([c for rgb in cols for c in rgb] + [0, 0, 0] * (256 - len(cols)))
    return p


def edge_profile(im: Image.Image, axis: int) -> list[float]:
    """Colour change across each column boundary (axis 0) or row boundary (axis 1),
    summed over the figure. Peaks sit on the source's pixel edges."""
    px = im.load(); w, h = im.size
    n, m = (w, h) if axis == 0 else (h, w)
    prof = [0.0] * (n - 1)
    for j in range(0, m, 2):
        for i in range(n - 1):
            p, q = (px[i, j], px[i + 1, j]) if axis == 0 else (px[j, i], px[j, i + 1])
            if p[3] >= 128 and q[3] >= 128:
                prof[i] += abs(p[0] - q[0]) + abs(p[1] - q[1]) + abs(p[2] - q[2])
    mu = sum(prof) / len(prof)
    return [v - mu for v in prof]


def detect_grid(prof: list[float]) -> tuple[float, float]:
    """(period, offset) of the strongest periodic edge pattern. Harmonics (period / 2) can
    score close to the true period, so take the largest period within 85% of the best."""
    scores = []
    p = GRID_RANGE[0]
    while p <= GRID_RANGE[1]:
        w = 2 * math.pi / p
        re = sum(v * math.cos(w * i) for i, v in enumerate(prof))
        im = sum(v * math.sin(w * i) for i, v in enumerate(prof))
        scores.append((math.hypot(re, im), p, math.atan2(im, re)))
        p = round(p + 0.02, 2)
    best = max(s for s, _, _ in scores)
    _, period, phase = max((t for t in scores if t[0] >= 0.85 * best), key=lambda t: t[1])
    # the profile peaks at index i0 = phase * period / 2pi; that edge lies between px i0 and i0 + 1
    return period, (phase * period / (2 * math.pi) + 1) % period


def cell_edges(size: int, period: float, offset: float) -> list[int]:
    """Cell boundaries in source px, keeping partial cells at the ends only if they're
    at least a third of a pixel."""
    edges, e = [], offset - period
    while e < size:
        if e > 0: edges.append(e)
        e += period
    edges = [0.0] + edges + [float(size)]
    if len(edges) > 2 and edges[1] - edges[0] < period / 3: edges.pop(1)
    if len(edges) > 2 and edges[-1] - edges[-2] < period / 3: edges.pop(-2)
    return [round(v) for v in edges]


def majority_downsample(idx: Image.Image, alpha: Image.Image, xs: list[int], ys: list[int]) -> tuple[Image.Image, Image.Image]:
    """One sprite pixel per grid cell: the most common opaque source colour in the cell
    (not an average), so edges and small accents stay crisp. A clearly darker colour wins
    with only DARK_SHARE of the cell, so 1 px outlines and eyes survive."""
    pal = idx.getpalette()
    luma = [0.299 * pal[i] + 0.587 * pal[i + 1] + 0.114 * pal[i + 2] for i in range(0, len(pal), 3)]
    w, h = len(xs) - 1, len(ys) - 1
    ip, ap = idx.load(), alpha.load()
    out, out_a = Image.new('P', (w, h)), Image.new('L', (w, h), 0)
    out.putpalette(pal)
    op, oa = out.load(), out_a.load()
    for ty in range(h):
        for tx in range(w):
            counts, n = {}, 0
            for y in range(ys[ty], ys[ty + 1]):
                for x in range(xs[tx], xs[tx + 1]):
                    if ap[x, y] >= 128:
                        c = ip[x, y]; counts[c] = counts.get(c, 0) + 1; n += 1
            if n and n * 2 >= (xs[tx + 1] - xs[tx]) * (ys[ty + 1] - ys[ty]):
                top = max(counts, key=counts.get)
                dark = min(counts, key=lambda c: luma[c])
                if counts[dark] >= n * DARK_SHARE and luma[top] - luma[dark] >= DARK_GAP:
                    top = dark
                op[tx, ty] = top; oa[tx, ty] = 255
    return out, out_a


def drop_islands(alpha: Image.Image) -> int:
    """Clear opaque pieces (8-connected) smaller than ISLAND x the largest one: stray
    ember squares, sparkles and other baked-in particles the engine should draw instead."""
    w, h = alpha.size; a = alpha.load()
    seen, pieces = set(), []
    for y in range(h):
        for x in range(w):
            if a[x, y] and (x, y) not in seen:
                piece, stack = [], [(x, y)]; seen.add((x, y))
                while stack:
                    cx, cy = stack.pop(); piece.append((cx, cy))
                    for dx in (-1, 0, 1):
                        for dy in (-1, 0, 1):
                            nx, ny = cx + dx, cy + dy
                            if 0 <= nx < w and 0 <= ny < h and a[nx, ny] and (nx, ny) not in seen:
                                seen.add((nx, ny)); stack.append((nx, ny))
                pieces.append(piece)
    big = max(map(len, pieces))
    dropped = 0
    for piece in pieces:
        if len(piece) < big * ISLAND:
            for p in piece: a[p] = 0
            dropped += 1
    return dropped


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('src'); ap.add_argument('out')
    ap.add_argument('--kind', choices=['humanoid', 'monster'], default='humanoid', help='sets the in-game height (default humanoid)')
    ap.add_argument('--size', type=float, default=1.0, help='monster species size (SPECIES[key].size in data.ts)')
    ap.add_argument('--height', type=int, help='force the figure to this many sprite pixels instead of snapping to the source grid')
    ap.add_argument('--palette-from', help='lock to this anchor PNG\'s colours (optional)')
    ap.add_argument('--colors', type=int, default=64, help='adaptive palette size when no --palette-from (default 64)')
    ap.add_argument('--keep-islands', action='store_true', help='keep small detached pieces')
    ap.add_argument('--tol', type=int, default=24, help='background key tolerance per channel (default 24)')
    a = ap.parse_args()
    units = HUMANOID_UNITS if a.kind == 'humanoid' else MONSTER_UNITS * a.size

    im = remove_background(Image.open(a.src), a.tol)
    box = im.getchannel('A').point(lambda v: 255 if v >= 128 else 0).getbbox()
    if not box: raise SystemExit('No figure found (is the whole image background?)')
    im = im.crop(box)

    if a.height:
        period = im.height / a.height
        xs = [round(i * period) for i in range(round(im.width / period))] + [im.width]
        ys = [round(i * period) for i in range(a.height)] + [im.height]
        grid = f'forced to {a.height} px'
    else:
        (px_, ox), (py_, oy) = detect_grid(edge_profile(im, 0)), detect_grid(edge_profile(im, 1))
        period = (px_ + py_) / 2 if abs(px_ - py_) < 0.1 * max(px_, py_) else max(px_, py_)
        xs, ys = cell_edges(im.width, period, ox % period), cell_edges(im.height, period, oy % period)
        grid = f'source grid {period:.2f} px (x {px_:.2f}, y {py_:.2f})'

    # lock the palette at full resolution, then one sprite pixel per grid cell
    pal = palette_image(a.palette_from, a.colors, im)
    idx = im.convert('RGB').quantize(palette=pal, dither=Image.Dither.NONE)
    small, alpha = majority_downsample(idx, im.getchannel('A'), xs, ys)
    dropped = 0 if a.keep_islands else drop_islands(alpha)
    sprite = small.convert('RGBA'); sprite.putalpha(alpha)
    sprite = sprite.crop(alpha.getbbox()); alpha = sprite.getchannel('A')
    w, fh = sprite.size

    # margin, feet near the bottom
    m = max(2, round(fh * MARGIN))
    canvas = Image.new('RGBA', (w + 2 * m, fh + 2 * m), (0, 0, 0, 0))
    canvas.paste(sprite, (m, m))
    k = max(1, TARGET // canvas.height)
    canvas.resize((canvas.width * k, canvas.height * k), Image.Resampling.NEAREST).save(a.out)

    # manifest numbers: feet = centre of the lowest opaque row; head ~ upper sixth of the figure;
    # height = the canvas in art units, so the figure itself is `units` tall in game
    row = [x for x in range(w) if alpha.getpixel((x, fh - 1))]
    feet_x = m + (sum(row) / len(row) if row else w / 2)
    head_row = [x for x in range(w) if alpha.getpixel((x, round(fh * 0.17)))]
    head_x = m + (sum(head_row) / len(head_row) if head_row else w / 2)
    W, H = canvas.size
    print(f'{a.out}: {W * k}x{H * k} px (sprite {w}x{fh} on a {W}x{H} grid, x{k}); {grid}; {dropped} specks dropped')
    print(f"  anchor: [{feet_x / W:.3f}, {(m + fh) / H:.3f}], height: {round(H * units / fh)}, head: [{head_x / W:.3f}, {(m + fh * 0.17) / H:.3f}],")


if __name__ == '__main__':
    main()
