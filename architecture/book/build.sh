#!/usr/bin/env bash
# Build the Platform Architecture Guide as a PDF (A4, for screens and printing)
# and an EPUB (for Kindle and other e-readers).
#
# Requirements: python3 and Docker. Pandoc and LaTeX run inside the official
# pandoc/extra image, so nothing is installed on the host.
#
# Usage: architecture/book/build.sh            → architecture/book/dist/
set -euo pipefail

PANDOC_IMAGE="pandoc/extra:3.7"
BOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUIDE_DIR="$(dirname "$BOOK_DIR")"
DIST="$BOOK_DIR/dist"
NAME="Platform-Architecture-Guide"

VERSION="$(grep -o 'Guide version:\*\* [0-9.]*' "$GUIDE_DIR/README.md" | grep -o '[0-9.]*$')"
DATE="$(date +%Y-%m-%d)"

mkdir -p "$DIST"
python3 -I "$BOOK_DIR/assemble.py" "$GUIDE_DIR" "$DIST/book.md"

pandoc() {
  docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -v "$BOOK_DIR:/data" -w /data/dist \
    "$PANDOC_IMAGE" "$@"
}

COMMON=(
  book.md
  --from markdown-raw_html-raw_tex-implicit_figures
  --top-level-division=part
  --toc
  --metadata "title=Platform Architecture Guide"
  --metadata "subtitle=Multi-app Frappe platform: architecture, contracts, security, compliance and delivery"
  --metadata "date=Version $VERSION · $DATE"
  --metadata "lang=en-GB"
)

# Source Serif/Sans/Code Pro ship with TeX Live inside the image; they are loaded
# by file name (they are not registered with fontconfig).
FONTS=()
for kind in main:SourceSerifPro sans:SourceSansPro mono:SourceCodePro; do
  FONTS+=(-V "${kind%%:*}font=${kind#*:}")
  for opt in Extension=.otf UprightFont=*-Regular BoldFont=*-Bold \
             ItalicFont=*-RegularIt BoldItalicFont=*-BoldIt; do
    FONTS+=(-V "${kind%%:*}fontoptions=$opt")
  done
done
# Allow long inline code (paths such as features/leave-requests/) to break at hyphens.
FONTS+=(-V "monofontoptions=HyphenChar=-")

echo "Building PDF…"
pandoc "${COMMON[@]}" \
  --toc-depth=1 --template eisvogel --pdf-engine=xelatex \
  --lua-filter /data/inline-code-breaks.lua \
  -V book -V classoption=oneside -V titlepage -V toc-own-page \
  -V titlepage-color=1F3A5F -V titlepage-text-color=FFFFFF -V titlepage-rule-color=FFFFFF \
  "${FONTS[@]}" \
  -V fontsize=10pt -V geometry:margin=2cm \
  -V code-block-font-size='\scriptsize' -V table-use-row-colors \
  -V colorlinks -V linkcolor=NavyBlue -V urlcolor=NavyBlue -V toccolor=black \
  -V header-left="Platform Architecture Guide" -V header-right="v$VERSION" \
  -V footer-left="" \
  -V header-includes='\setlength{\emergencystretch}{3em}' \
  -o "$NAME.pdf" 2> "$DIST/pdf.log" || { cat "$DIST/pdf.log"; exit 1; }

echo "Building EPUB…"
pandoc "${COMMON[@]}" \
  --toc-depth=2 --split-level=2 --css /data/epub.css \
  -o "$NAME.epub" 2> "$DIST/epub.log" || { cat "$DIST/epub.log"; exit 1; }

rm -f "$DIST/book.md"
echo "Done: $DIST/$NAME.pdf and $DIST/$NAME.epub"
