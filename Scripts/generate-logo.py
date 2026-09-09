#!/usr/bin/env python3
"""Turns Resources/CueLogo.svg into geometry the app and the icon can draw.

Run by hand when the artwork changes:

    ./Scripts/generate-logo.py

The SVG holds one wing of the waveform — the tall shape first, then five
progressively shorter ones. The finished mark is that wing mirrored around the
tall shape, which is done here rather than in the file so the drawing the
designer actually made stays the single source.

Two outputs, because they are read at different moments: Swift for the app,
which must not depend on a file at runtime, and JSON for the icon script, which
is a standalone `swift` file and cannot import the app's module.
"""

import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Resources" / "CueLogo.svg"


def parse_matrix(value):
    if not value:
        return (1, 0, 0, 1, 0, 0)
    match = re.match(r"matrix\(([^)]*)\)", value.strip())
    if not match:
        return (1, 0, 0, 1, 0, 0)
    return tuple(float(x) for x in re.split(r"[,\s]+", match.group(1).strip()))


def compose(m1, m2):
    a1, b1, c1, d1, e1, f1 = m1
    a2, b2, c2, d2, e2, f2 = m2
    return (
        a1 * a2 + c1 * b2, b1 * a2 + d1 * b2,
        a1 * c2 + c1 * d2, b1 * c2 + d1 * d2,
        a1 * e2 + c1 * f2 + e1, b1 * e2 + d1 * f2 + f1,
    )


def apply(matrix, x, y):
    a, b, c, d, e, f = matrix
    return (a * x + c * y + e, b * x + d * y + f)


def parse_path(data):
    """Handles the subset this artwork uses: absolute M, L, C and Z."""
    tokens = re.findall(r"[MmLlCcZz]|-?\d*\.?\d+(?:e[-+]?\d+)?", data, re.I)
    counts = {"M": 2, "L": 2, "C": 6, "Z": 0}
    out, index, command = [], 0, None
    while index < len(tokens):
        if re.match(r"[A-Za-z]", tokens[index]):
            command = tokens[index]
            index += 1
            if command.upper() == "Z":
                out.append(("Z", []))
                continue
        count = counts[command.upper()]
        out.append((command, [float(tokens[index + k]) for k in range(count)]))
        index += count
        if command == "M":
            command = "L"
    return out


def collect(node, matrix, shapes):
    for child in node:
        tag = child.tag.split("}")[-1]
        combined = compose(matrix, parse_matrix(child.get("transform")))
        if tag == "g":
            collect(child, combined, shapes)
        elif tag == "path":
            shapes.append((parse_path(child.get("d", "")), combined))


def flatten(shapes):
    result = []
    for commands, matrix in shapes:
        segments, current, start = [], (0, 0), (0, 0)
        for command, args in commands:
            kind = command.upper()
            if kind == "M":
                current = (args[0], args[1])
                start = current
                segments.append(("M", [apply(matrix, *current)]))
            elif kind == "L":
                current = (args[0], args[1])
                segments.append(("L", [apply(matrix, *current)]))
            elif kind == "C":
                c1, c2 = (args[0], args[1]), (args[2], args[3])
                current = (args[4], args[5])
                segments.append(("C", [apply(matrix, *c1), apply(matrix, *c2), apply(matrix, *current)]))
            elif kind == "Z":
                segments.append(("Z", []))
                current = start
        result.append(segments)
    return result


def main():
    tree = ET.parse(SOURCE)
    raw = []
    collect(tree.getroot(), (1, 0, 0, 1, 0, 0), raw)
    wing = flatten(raw)

    tall = wing[0]
    centre = (
        min(p[0] for _, ps in tall for p in ps) + max(p[0] for _, ps in tall for p in ps)
    ) / 2

    def mirrored(segments):
        return [(c, [[2 * centre - p[0], p[1]] for p in ps]) for c, ps in segments]

    full = (
        [mirrored(s) for s in reversed(wing[1:])]
        + [tall]
        + [[(c, [list(p) for p in ps]) for c, ps in s] for s in wing[1:]]
    )

    xs = [p[0] for s in full for _, ps in s for p in ps]
    ys = [p[1] for s in full for _, ps in s for p in ps]
    minx, maxx, miny, maxy = min(xs), max(xs), min(ys), max(ys)
    width, height = maxx - minx, maxy - miny

    def unit(point):
        return ((point[0] - minx) / width, (point[1] - miny) / height)

    runs = []
    for shape in full:
        numbers = []
        for command, points in shape:
            if command.upper() in ("M", "C"):
                for point in points:
                    x, y = unit(point)
                    numbers += [round(x, 5), round(y, 5)]
        runs.append(numbers)

    aspect = width / height

    (ROOT / "Resources" / "CueLogo.json").write_text(
        json.dumps({"aspect": round(aspect, 5), "shapes": runs}, indent=1) + "\n"
    )

    body = "\n".join(
        "        [" + ", ".join("%.5f" % n for n in run) + "]," for run in runs
    )
    (ROOT / "Sources" / "Cue" / "UI" / "CueLogoPath.swift").write_text(SWIFT % (aspect, body))

    print("%d shapes, aspect %.4f" % (len(full), aspect))


SWIFT = '''import CoreGraphics
import SwiftUI

// Generated by Scripts/generate-logo.py from Resources/CueLogo.svg.
// Edit the artwork, not this file.

/// Cue's mark, as drawn.
///
/// The artwork itself rather than an approximation of it. The source file holds
/// one wing of the waveform; the finished mark is that wing mirrored around its
/// tall shape, which is done in the generator so the drawing the designer made
/// stays the single source.
///
/// Coordinates are normalised into a unit box with y increasing downward, so
/// the mark can be drawn at any size in either coordinate system.
///
/// `nonisolated` because `Shape.path(in:)` is, and geometry has no business
/// belonging to an actor: these are constants and a pure function of a
/// rectangle.
nonisolated enum CueLogoPath {
    /// Width divided by height, for callers that need to reserve space.
    static let aspect: CGFloat = %.5f

    /// One shape per element.
    ///
    /// Each is a flat run of coordinates: the first pair is the starting point,
    /// and every six numbers after it are a cubic curve — two control points and
    /// an end point. Every shape closes.
    static let shapes: [[CGFloat]] = [
%s
    ]

    /// The whole mark, fitted into `rect` without distorting it.
    static func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / aspect, rect.height)
        let size = CGSize(width: scale * aspect, height: scale)
        let origin = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)

        var path = Path()
        for shape in shapes {
            guard shape.count >= 8 else { continue }

            func point(_ index: Int) -> CGPoint {
                CGPoint(
                    x: origin.x + shape[index] * size.width,
                    y: origin.y + shape[index + 1] * size.height
                )
            }

            path.move(to: point(0))
            var index = 2
            while index + 5 < shape.count {
                path.addCurve(to: point(index + 4), control1: point(index), control2: point(index + 2))
                index += 6
            }
            path.closeSubpath()
        }
        return path
    }

    /// One shape, fitted the same way — for drawing them individually so each
    /// can move on its own.
    static func path(forShape index: Int, in rect: CGRect) -> Path {
        guard shapes.indices.contains(index) else { return Path() }

        var path = Path()
        let shape = shapes[index]
        guard shape.count >= 8 else { return path }

        func point(_ offset: Int) -> CGPoint {
            CGPoint(
                x: rect.minX + shape[offset] * rect.width,
                y: rect.minY + shape[offset + 1] * rect.height
            )
        }

        path.move(to: point(0))
        var offset = 2
        while offset + 5 < shape.count {
            path.addCurve(to: point(offset + 4), control1: point(offset), control2: point(offset + 2))
            offset += 6
        }
        path.closeSubpath()
        return path
    }
}
'''

if __name__ == "__main__":
    main()
