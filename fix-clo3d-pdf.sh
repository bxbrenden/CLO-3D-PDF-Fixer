#!/usr/bin/env bash
# fix-clo3d-pdf.sh — Rescale CLO 3D AI File (*.pdf) exports to correct real-world dimensions.
#
# USAGE:
#   ./fix-clo3d-pdf.sh INPUT_PDF [OUTPUT_PDF]
#
# If OUTPUT_PDF is omitted, writes <input-basename>-fixed.pdf in the same directory.
#
# DEPENDENCIES:
#   gs (Ghostscript)  — the only non-standard requirement
#     macOS:   brew install ghostscript
#     Linux:   sudo apt install ghostscript  (Debian/Ubuntu)
#              sudo dnf install ghostscript  (Fedora/RHEL)
#   grep, awk — standard on macOS and Linux; available on Windows via Git Bash or WSL
#
# CROSS-PLATFORM NOTES:
#   macOS    ✅  bash 3.2+ (system) or any newer shell; BSD grep and awk both work
#   Linux    ✅  bash + GNU grep/awk
#   Windows  ⚠️  Requires Git Bash or WSL. Native CMD/PowerShell not supported.
#               On Windows, Ghostscript may be named gswin64c — rename or alias it to gs.
#
# BACKGROUND:
#   CLO 3D writes path coordinates in millimeters but declares the file as PDF 1.4,
#   which makes its UserUnit field invalid. Every reader (Inkscape, macOS Preview,
#   Acrobat) therefore treats those mm values as points, displaying patterns at
#   ~28.35% of their true size (factor of 72/25.4 = 2.83465 too small).
#
#   This script reads the MediaBox from the input PDF, computes the true point
#   dimensions (mm × 72/25.4), and tells Ghostscript to re-render into that
#   corrected page size — baking the right scale into the output coordinates.
#   No manual rescaling in Inkscape or any other tool is needed afterward.

set -euo pipefail

# ── Help ──────────────────────────────────────────────────────────────────────
usage() {
    sed -n '/^# USAGE/,/^[^#]/{ /^#/{ s/^# \{0,1\}//; p } }' "$0"
    echo ""
    echo "Example:"
    echo "  ./fix-clo3d-pdf.sh my-export.pdf"
    echo "      Writes my-export-fixed.pdf in the same directory."
    echo ""
    echo "  ./fix-clo3d-pdf.sh my-export.pdf /tmp/output.pdf"
    echo "      Writes to a specific path."
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" || -z "${1:-}" ]]; then
    usage
    exit 0
fi

# ── Arguments ─────────────────────────────────────────────────────────────────
INPUT="$1"

if [[ ! -f "$INPUT" ]]; then
    echo "Error: file not found: $INPUT" >&2
    exit 1
fi

if [[ -n "${2:-}" ]]; then
    OUTPUT="$2"
else
    input_dir=$(cd "$(dirname "$INPUT")" && pwd)
    input_name=$(basename "$INPUT")
    base="${input_name%.*}"
    ext="${input_name##*.}"
    OUTPUT="${input_dir}/${base}-fixed.${ext}"
fi

if [[ "$(realpath "$INPUT")" == "$(realpath "$OUTPUT" 2>/dev/null || echo "$OUTPUT")" ]]; then
    echo "Error: output path is the same as input. Specify a different output path." >&2
    exit 1
fi

# ── Dependency check ──────────────────────────────────────────────────────────
if ! command -v gs &>/dev/null; then
    echo "Error: Ghostscript (gs) not found on PATH." >&2
    echo "  macOS:  brew install ghostscript" >&2
    echo "  Linux:  sudo apt install ghostscript" >&2
    exit 1
fi

# ── Extract MediaBox ──────────────────────────────────────────────────────────
# The MediaBox is stored as plain text in the page dictionary even in compressed
# PDFs, so grep -a (treat binary as text) reliably finds it.
mediabox_raw=$(grep -aEo 'MediaBox *\[[^]]*\]' "$INPUT" | head -1)

if [[ -z "$mediabox_raw" ]]; then
    echo "Error: could not find a MediaBox in this PDF." >&2
    echo "Is this a CLO 3D AI File export?" >&2
    exit 1
fi

# Extract the four numbers in order: x0 y0 width height
read -r x0 y0 w h <<< "$(echo "$mediabox_raw" | grep -oE '[0-9]+\.?[0-9]*' | tr '\n' ' ')"

if [[ -z "$w" || -z "$h" ]]; then
    echo "Error: could not parse MediaBox values from: $mediabox_raw" >&2
    exit 1
fi

# ── Compute target dimensions ─────────────────────────────────────────────────
# Coordinates are in mm; multiply by 72/25.4 to get true points.
target_w=$(awk "BEGIN { printf \"%.4f\", ($w - $x0) * 72 / 25.4 }")
target_h=$(awk "BEGIN { printf \"%.4f\", ($h - $y0) * 72 / 25.4 }")
true_w_in=$(awk "BEGIN { printf \"%.3f\", ($w - $x0) / 25.4 }")
true_h_in=$(awk "BEGIN { printf \"%.3f\", ($h - $y0) / 25.4 }")
true_w_mm=$(awk "BEGIN { printf \"%.2f\", ($w - $x0) }")
true_h_mm=$(awk "BEGIN { printf \"%.2f\", ($h - $y0) }")

echo "Input:       $INPUT"
echo "Output:      $OUTPUT"
echo "MediaBox:    [$x0 $y0 $w $h]  (values treated as mm)"
echo "Scale:       72 / 25.4 = 2.834645... pt/mm"
echo "Target size: ${target_w} × ${target_h} pt  =  ${true_w_mm} × ${true_h_mm} mm  =  ${true_w_in} × ${true_h_in} in"
echo ""

# ── Run Ghostscript ───────────────────────────────────────────────────────────
echo "Running Ghostscript..."
gs \
    -sDEVICE=pdfwrite \
    -dNOPAUSE \
    -dBATCH \
    -dQUIET \
    -dDEVICEWIDTHPOINTS="$target_w" \
    -dDEVICEHEIGHTPOINTS="$target_h" \
    -dFIXEDMEDIA \
    -dPDFFitPage \
    -sOutputFile="$OUTPUT" \
    "$INPUT"

echo "Done. Written to: $OUTPUT"
echo ""
echo "Expected page size in Preview (Cmd+I):  ${true_w_in} × ${true_h_in} inches"
