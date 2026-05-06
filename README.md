# CLO-3D-PDF-Fixer

Fixes the broken scale in PDF files exported from [CLO 3D](https://www.clo3d.com/) via **Export → Adobe (PDF) → AI File (\*.pdf)**.

When opened in Inkscape, macOS Preview, or any standard PDF reader, CLO 3D's exported patterns appear at **~28.35% of their true size**. This tool corrects them to real-world dimensions with no manual rescaling needed.

---

## Disclaimer

This tool was developed and tested against PDFs exported from **CLO 3D version 2026.0.238 (r56171)** on macOS. It worked for my use case — your mileage may vary. Different CLO 3D versions may export differently, and I make no guarantees that this will work for your files.

Use this at your own risk. I am not responsible for any issues arising from the use or misuse of this code. I am not affiliated with or a representative of CLO in any way.

---

## The Problem

CLO 3D writes all path coordinates in **millimeters** in its exported PDF files. However, every PDF reader interprets coordinates as **points** (1 pt = 1/72 inch) by default, unless told otherwise.

The PDF specification provides a `UserUnit` field to override this assumption. CLO 3D does include a `UserUnit` entry in its exports — but it sets it to `72.0` (which would mean "each coordinate unit equals 1 inch"), and more critically, it declares the file as **PDF version 1.4**, in which `UserUnit` is not a valid field and is therefore ignored by all conforming readers.

The result: a pattern piece that is 25.4 mm (1 inch) wide gets stored with the coordinate value `25.4`, which every reader interprets as 25.4 pt — roughly 0.353 inches. The scale error is exactly `72 ÷ 25.4 = 2.83465×`.

### Observed symptoms

- A 1-inch square drawn in CLO 3D measures **~0.354 inches** (25.4 pt) in Inkscape
- macOS Preview reports the page size as **~40.8 × 42.6 inches** instead of the true ~115.6 × 120.7 inches
- Changing the export scale percentage (100%, 200%, etc.) in CLO 3D has no effect on the output size

### Root cause (verified from raw PDF bytes)

```
/Type/Page/UserUnit 72.0/MediaBox[0 0 2937.55 3064.63]
```

- Coordinates are in mm ✓
- `UserUnit 72.0` is meaningless in PDF 1.4 and ignored by all readers ✗
- All readers fall back to treating coordinate values as points ✗
- Scale error: `72 / 25.4 = 2.834645...×` too small ✗

---

## The Fix

This tool uses [Ghostscript](https://www.ghostscript.com/) to re-render the PDF with the correct target page size. It reads the `MediaBox` from the input file, multiplies the dimensions by `72/25.4` to convert mm → points, and passes that as the true output size to `gs`. The resulting PDF has coordinates in real points and displays at the correct size in all readers.

No `UserUnit` manipulation is needed — the content streams themselves are rescaled.

---

## Requirements

- **Ghostscript** (`gs`)
  - macOS: `brew install ghostscript`
  - Linux: `sudo apt install ghostscript` / `sudo dnf install ghostscript`
  - Windows: [download from ghostscript.com](https://www.ghostscript.com/releases/gsdnld.html)

**Python script only:** Python 3.6+  
**Shell script only:** bash or zsh; standard `grep` and `awk` (macOS and Linux built-ins work fine)

---

## Usage

### Python (cross-platform)

```bash
python3 fix-clo3d-pdf.py INPUT.pdf [OUTPUT.pdf]
```

If `OUTPUT.pdf` is omitted, writes `INPUT-fixed.pdf` in the same directory as the input.

```
$ python3 fix-clo3d-pdf.py tracksuit.pdf
Input:       tracksuit.pdf
Output:      tracksuit-fixed.pdf
MediaBox:    [0.0 0.0 2937.55 3064.63]  (values treated as mm)
Scale:       72 / 25.4 = 2.834646 pt/mm
Target size: 8326.91 × 8687.14 pt  =  2937.55 × 3064.63 mm  =  115.652 × 120.655 in

Running Ghostscript...
Done. Written to: tracksuit-fixed.pdf

Expected page size in Preview (Cmd+I):
  115.65 × 120.65 inches
  = 2937.6 × 3064.6 mm
```

### Shell (macOS / Linux)

```bash
./fix-clo3d-pdf.sh INPUT.pdf [OUTPUT.pdf]
```

Windows users should use the Python script or run the shell script under Git Bash / WSL.

---

## Verification

After converting:

| Tool | How to check | Expected result |
|---|---|---|
| macOS Preview | `Cmd+I` → Page Size | ~115.65 × 120.65 in (varies by canvas size) |
| Inkscape | Open file, click a known piece, check dimensions | True mm/inch value |

A pattern piece that was 1 inch in CLO 3D should measure **1 inch** (±0.003 in tolerance from CLO 3D's internal coordinate precision) in Inkscape after conversion.

---

## License

See [LICENSE](LICENSE).
