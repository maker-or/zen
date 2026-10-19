#!/usr/bin/env python3
"""Build the pen-arrival map that animates the handwritten Zen wordmark.

For every pixel of the logo (zen/icon.icon/Assets/zen.svg) this records when
the pen reaches it, from 0 to 1, in the alpha channel of
zen/Resources/ZenLogoArrival.png. The intro's shader
reveals pixels whose time has come, so a stroke appears only when the pen gets
to it, never early because another stroke passes nearby.

The pen follows the letters' centrelines, found by skeletonizing the outline,
in writing order between the waypoints in STROKES (SVG units, 210 x 128).
Rerun this after changing the logo, and adjust the waypoints if letters move.

Requires numpy, scipy, scikit-image and Pillow.
"""
import re
import struct
import zlib
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import binary_dilation, distance_transform_edt, grey_opening, uniform_filter1d
from scipy.spatial import cKDTree
from skimage.morphology import skeletonize

ROOT = Path(__file__).resolve().parents[1]
SVG = ROOT / "zen/icon.icon/Assets/zen.svg"
# A bundle resource, not an asset: the asset catalog would cut it to 8 bits.
OUT = ROOT / "zen/Resources/ZenLogoArrival.png"
VIEW = (210, 128)        # the SVG viewBox
TRACE_SCALE = 6          # pixels per unit for finding centrelines
MAP_SCALE = 5            # pixels per unit in the shipped map
LIFT = 18.0              # a pen lift lasts as long as drawing this much line
EXTEND = 5.0             # a skeleton stops short of each tip; extend this far
INK_MARGIN = 0.4         # the pen inks this far past the stroke's half-width

# (waypoints in writing order, extend start, extend end, pause before). Only
# real tips are extended; strokes that begin at a junction aren't. The pause
# is in the same units as LIFT.
STROKES = [
    # z: top bar, diagonal and its short tail
    ([(2, 32), (39, 8), (35, 34), (26, 46)], True, True, 0),
    # z's lower curve and descender loop, the connector, then on into the e:
    # up its left side, over the top, down the right side, around the bottom
    # and out along the tail
    ([(35, 34), (60, 50), (59, 60), (58, 95), (22, 123), (40, 80), (59, 59), (60, 50), (88, 30),
      (98, 26), (110, 5), (113, 18), (100, 32), (95, 37), (105, 55), (140, 38)], False, True, LIFT),
    # n: stem
    ([(150, 9), (144, 55)], True, True, LIFT),
    # n: arch and tail, starting from the stem
    ([(151, 22), (172, 10), (172, 53), (207, 34)], False, True, LIFT),
]


def outline_mask(scale):
    """Rasterize the logo's single path (cubic Béziers) like an SVG renderer."""
    d = re.search(r'<path d="([^"]*)"', SVG.read_text()).group(1)
    tokens = re.findall(r"[MCLHVZ]|-?\d*\.?\d+(?:e-?\d+)?", d)
    subpaths, current, pos, cmd, i = [], [], (0.0, 0.0), None, 0
    while i < len(tokens):
        if tokens[i].isalpha():
            cmd = tokens[i]
            i += 1
        if cmd == "Z":
            subpaths.append(current)
            current, cmd = [], None
            continue
        if cmd == "M":
            if current:
                subpaths.append(current)
            pos = (float(tokens[i]), float(tokens[i + 1]))
            current, cmd, i = [pos], "L", i + 2
        elif cmd == "L":
            pos = (float(tokens[i]), float(tokens[i + 1]))
            current.append(pos)
            i += 2
        elif cmd == "H":
            pos = (float(tokens[i]), pos[1])
            current.append(pos)
            i += 1
        elif cmd == "V":
            pos = (pos[0], float(tokens[i]))
            current.append(pos)
            i += 1
        elif cmd == "C":
            p1, p2, p3 = [(float(tokens[i + k]), float(tokens[i + k + 1])) for k in (0, 2, 4)]
            for t in np.linspace(0, 1, 16)[1:]:
                current.append(tuple((1 - t) ** 3 * np.array(pos) + 3 * (1 - t) ** 2 * t * np.array(p1)
                                     + 3 * (1 - t) * t * t * np.array(p2) + t ** 3 * np.array(p3)))
            pos, i = p3, i + 6
        else:
            raise SystemExit(f"Unsupported path command {cmd!r} in {SVG}")
    if current:
        subpaths.append(current)
    # SVG's default nonzero rule: overlapping parts of the outline (where the
    # connector runs into the e) stay filled, while counters wound the other
    # way cancel. Even-odd would punch holes where outlines overlap.
    size = (VIEW[0] * scale, VIEW[1] * scale)
    winding = np.zeros(size[::-1], int)
    for points in subpaths:
        xs, ys = np.array(points).T
        direction = 1 if np.dot(xs, np.roll(ys, -1)) - np.dot(ys, np.roll(xs, -1)) > 0 else -1
        image = Image.new("1", size, 0)
        ImageDraw.Draw(image).polygon([(x * scale, y * scale) for x, y in points], fill=1)
        winding += direction * np.array(image, int)
    return winding != 0


def write_png16(path, rgba):
    """A 16-bit RGBA PNG (Pillow only writes 8-bit RGBA)."""
    height, width, _ = rgba.shape
    rows = b"".join(b"\x00" + rgba[y].tobytes() for y in range(height))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 16, 6, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b""))


def pen_path(skeleton, waypoints):
    """The skeleton route through the waypoints, as pixel coordinates."""
    ys, xs = np.nonzero(skeleton)
    points = np.stack([xs, ys], 1)

    def snap(p):
        target = np.array(p) * TRACE_SCALE
        return tuple(points[np.argmin(((points - target) ** 2).sum(1))])

    def route(a, b):
        previous, queue = {a: None}, deque([a])
        while queue:
            c = queue.popleft()
            if c == b:
                break
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    n = (c[0] + dx, c[1] + dy)
                    if (n not in previous and 0 <= n[0] < skeleton.shape[1]
                            and 0 <= n[1] < skeleton.shape[0] and skeleton[n[1], n[0]]):
                        previous[n] = c
                        queue.append(n)
        if b not in previous:
            raise SystemExit(f"No centreline between waypoints {a} and {b}")
        path = [b]
        while previous[path[-1]] is not None:
            path.append(previous[path[-1]])
        return path[::-1]

    path = []
    for a, b in zip(waypoints, waypoints[1:]):
        segment = route(snap(a), snap(b))
        path += segment if not path else segment[1:]
    return np.array(path, float) / TRACE_SCALE


def main():
    skeleton = skeletonize(outline_mask(TRACE_SCALE))
    samples, arrivals, offset = [], [], 0.0
    for waypoints, extend_start, extend_end, pause in STROKES:
        offset += pause
        p = pen_path(skeleton, waypoints)
        # Smooth pixel stair-steps so the pen moves evenly.
        p = np.stack([uniform_filter1d(p[:, i], 9, mode="nearest") for i in (0, 1)], 1)

        def extension(end, inner):
            direction = (end - inner) / (np.linalg.norm(end - inner) or 1)
            return [end + direction * t for t in np.linspace(0.2, EXTEND, 25)]

        if extend_start:
            p = np.vstack([extension(p[0], p[min(12, len(p) - 1)])[::-1], p])
        if extend_end:
            p = np.vstack([p, extension(p[-1], p[max(-13, -len(p))])])
        along = np.r_[0, np.cumsum(np.linalg.norm(np.diff(p, axis=0), axis=1))]
        samples.append(p)
        arrivals.append(offset + along)
        offset += along[-1]
    total = offset
    stroke_arrivals = arrivals
    samples, arrivals = np.vstack(samples), np.concatenate(arrivals) / total

    # Ink model: the pen is as wide as the stroke it's drawing. A pixel is
    # inked the first time the pen passes within that half-width of it, as long as
    # the ink can reach it without crossing a gap (line of sight inside the
    # letter). Junctions get a round blob from the first stroke through them,
    # while separate strokes that pass close, like the e's tail and the n's
    # stem, can't reveal each other. Pixels no pass covers (the antialiased
    # fringe) take their nearest centreline point.
    width, height = VIEW[0] * MAP_SCALE, VIEW[1] * MAP_SCALE
    glyph = np.array(Image.fromarray(outline_mask(TRACE_SCALE)).resize((width, height), Image.NEAREST))
    reachable = binary_dilation(glyph, iterations=2)      # tolerate the antialiased edge
    half_width = distance_transform_edt(glyph) / MAP_SCALE

    def to_pixels(points):
        px = np.clip((points * MAP_SCALE).astype(int), 0, [width - 1, height - 1])
        return px[..., 0], px[..., 1]

    # The local half-width, capped at the stroke's typical one: a junction is
    # wider than either stroke, and an uncapped pen would poke into branches
    # that haven't been drawn yet.
    sx, sy = to_pixels(samples)
    local = half_width[sy, sx]
    stroke_of = np.concatenate([np.full(len(a), k) for k, a in enumerate(stroke_arrivals)])
    typical = np.array([np.median(local[stroke_of == k]) for k in range(len(STROKES))])
    radius = np.minimum(local, typical[stroke_of]) + INK_MARGIN

    def in_sight(a, b):
        steps = max(2, int(np.linalg.norm(b - a) * 4))
        x, y = to_pixels(a + (b - a) * np.linspace(0, 1, steps)[:, None])
        return reachable[y, x].all()

    yy, xx = np.nonzero(binary_dilation(glyph, iterations=6))   # glyph plus antialiased fringe
    queries = np.stack([(xx + 0.5) / MAP_SCALE, (yy + 0.5) / MAP_SCALE], 1)
    tree = cKDTree(samples)
    _, nearest = tree.query(queries)
    arrival = np.ones((height, width))
    for i, nearby in enumerate(tree.query_ball_point(queries, radius.max())):
        best = arrivals[nearest[i]]          # the nearest point always counts
        nearby = np.array(nearby, int)
        if len(nearby):
            within = nearby[np.linalg.norm(samples[nearby] - queries[i], axis=1) <= radius[nearby]]
            for candidate in within[np.argsort(arrivals[within])]:
                if arrivals[candidate] >= best:
                    break
                if in_sight(queries[i], samples[candidate]):
                    best = arrivals[candidate]
                    break
        arrival[yy[i], xx[i]] = best
    # Drop tiny late islands, which would flash as holes.
    arrival = grey_opening(arrival, size=(7, 7))

    # Alpha carries the value because it isn't colour-managed when sampled.
    # 16 bits: at 8 bits each step spans ~3 units of pen travel, which makes
    # the pen's soft edge advance in visible bands.
    rgba = np.zeros((height, width, 4), ">u2")
    rgba[..., 3] = np.round(arrival * 65535).astype(">u2")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    write_png16(OUT, rgba)
    print(f"Pen length {total:.0f} units over {len(STROKES)} strokes; wrote {width}x{height} map to {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
