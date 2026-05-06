#!/usr/bin/env python3
"""
fix-clo3d-pdf.py — Rescale CLO 3D AI File (*.pdf) exports to correct real-world dimensions.

CLO 3D exports AI-format PDFs with coordinates written in millimeters, but the
PDF version header (1.4) makes the UserUnit field invalid, so every reader treats
the coordinate values as points instead. This causes patterns to display at
~28.35% of their true size in all readers (Inkscape, Preview, etc.).

This script uses Ghostscript to bake the correct 72/25.4 scale factor into the
coordinate streams so any reader sees the right dimensions without any manual
scaling.

Requirements:
  Ghostscript must be installed and on your PATH.
  Install via Homebrew:  brew install ghostscript
"""

import sys
import os
import re
import subprocess
import argparse

SCALE = 72 / 25.4  # points per mm — the exact correction factor


def extract_mediabox(pdf_path):
    """Scan raw PDF bytes for the MediaBox and return (x0, y0, w, h)."""
    with open(pdf_path, "rb") as f:
        data = f.read()
    m = re.search(
        rb"/MediaBox\s*\[\s*([\d.+-]+)\s+([\d.+-]+)\s+([\d.+-]+)\s+([\d.+-]+)\s*\]",
        data,
    )
    if not m:
        raise ValueError(
            "Could not find a MediaBox in this PDF. "
            "Is this a CLO 3D AI File export?"
        )
    return tuple(float(v) for v in m.groups())


def main():
    parser = argparse.ArgumentParser(
        prog="fix-clo3d-pdf.py",
        description=(
            "Rescale a CLO 3D AI File (*.pdf) export to correct real-world dimensions.\n"
            "\n"
            "CLO 3D writes all path coordinates in millimeters but declares the file\n"
            "as PDF 1.4, which makes the UserUnit field it includes invalid. Every\n"
            "reader (Inkscape, macOS Preview, etc.) therefore treats those mm values\n"
            "as points, shrinking everything to ~28% of true size.\n"
            "\n"
            "This script feeds the PDF through Ghostscript with the correct target\n"
            "page size so the scale factor is baked into the output coordinates."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  python3 fix-clo3d-pdf.py export.pdf\n"
            "      Writes export-fixed.pdf in the same directory.\n"
            "\n"
            "  python3 fix-clo3d-pdf.py export.pdf corrected/output.pdf\n"
            "      Writes to a specific output path.\n"
            "\n"
            "Verification after conversion:\n"
            "  macOS Preview (Cmd+I)  — page size should be ~2.835x larger than before\n"
            "  Inkscape (File > Open) — pattern pieces should measure true mm / inches\n"
            "                           without any manual rescaling\n"
            "\n"
            "Background:\n"
            "  The correction factor is exactly 72/25.4 = 2.834645... pt/mm.\n"
            "  A 1-inch square in CLO 3D is stored as 25.4 coordinate units;\n"
            "  after correction it spans 72 pt = 1 inch in any PDF reader."
        ),
    )
    parser.add_argument("input", help="Path to the CLO 3D exported PDF")
    parser.add_argument(
        "output",
        nargs="?",
        help="Output path (default: <input-basename>-fixed.pdf)",
    )
    args = parser.parse_args()

    # Validate input
    if not os.path.isfile(args.input):
        print(f"Error: file not found: {args.input}", file=sys.stderr)
        sys.exit(1)

    # Determine output path
    if args.output:
        out_path = args.output
    else:
        input_dir = os.path.dirname(os.path.abspath(args.input))
        input_name = os.path.basename(args.input)
        base, ext = os.path.splitext(input_name)
        out_path = os.path.join(input_dir, base + "-fixed" + (ext or ".pdf"))

    if os.path.abspath(out_path) == os.path.abspath(args.input):
        print(
            "Error: output path is the same as the input. "
            "Specify a different output path.",
            file=sys.stderr,
        )
        sys.exit(1)

    # Extract MediaBox
    try:
        x0, y0, w, h = extract_mediabox(args.input)
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

    # Compute target dimensions in true points
    target_w = (w - x0) * SCALE
    target_h = (h - y0) * SCALE
    true_w_mm = w - x0
    true_h_mm = h - y0

    print(f"Input:       {args.input}")
    print(f"Output:      {out_path}")
    print(f"MediaBox:    [{x0} {y0} {w} {h}]  (values treated as mm)")
    print(f"Scale:       72 / 25.4 = {SCALE:.6f} pt/mm")
    print(
        f"Target size: {target_w:.2f} × {target_h:.2f} pt"
        f"  =  {true_w_mm:.2f} × {true_h_mm:.2f} mm"
        f"  =  {true_w_mm/25.4:.3f} × {true_h_mm/25.4:.3f} in"
    )
    print()

    # Check gs is available
    if subprocess.run(["which", "gs"], capture_output=True).returncode != 0:
        print(
            "Error: Ghostscript (gs) not found on PATH.\n"
            "Install it with:  brew install ghostscript",
            file=sys.stderr,
        )
        sys.exit(1)

    cmd = [
        "gs",
        "-sDEVICE=pdfwrite",
        "-dNOPAUSE",
        "-dBATCH",
        "-dQUIET",
        f"-dDEVICEWIDTHPOINTS={target_w:.4f}",
        f"-dDEVICEHEIGHTPOINTS={target_h:.4f}",
        "-dFIXEDMEDIA",
        "-dPDFFitPage",
        f"-sOutputFile={out_path}",
        args.input,
    ]

    print("Running Ghostscript...")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print("Ghostscript failed with the following error:", file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        sys.exit(1)

    print(f"Done. Written to: {out_path}")
    print()
    print("Expected page size in Preview (Cmd+I):")
    print(f"  {true_w_mm/25.4:.2f} × {true_h_mm/25.4:.2f} inches")
    print(f"  = {true_w_mm:.1f} × {true_h_mm:.1f} mm")


if __name__ == "__main__":
    main()
