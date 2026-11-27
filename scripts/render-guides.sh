#!/usr/bin/env bash
# Builds docs/guides/src/*.md into HTML and prints each to PDF with Chrome (headless).
# Runs in WSL using the Windows Chrome install; set CHROME to use another Chrome/Chromium.
# Usage: scripts/render-guides.sh [guide-name ...]   (default: all)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHROME="${CHROME:-/mnt/c/Program Files/Google/Chrome/Application/chrome.exe}"
PY="${PYTHON:-python3}"
"$PY" "$ROOT/docs/guides/build.py" "$@"

WIN_TMP="/mnt/c/Users/${WIN_USER:-NAYAN}/AppData/Local/Temp/eks-guides"
WIN_TMP_DOS="C:\\Users\\${WIN_USER:-NAYAN}\\AppData\\Local\\Temp\\eks-guides"
mkdir -p "$WIN_TMP"
for html in "$ROOT"/docs/guides/html/*.html; do
  name="$(basename "$html" .html)"
  if [ "$#" -gt 0 ] && [[ " $* " != *" $name "* ]]; then continue; fi
  cp "$html" "$WIN_TMP/$name.html"
  timeout 180 "$CHROME" --headless=new --disable-gpu --no-pdf-header-footer \
    --user-data-dir="$WIN_TMP_DOS\\profile" \
    --print-to-pdf="$WIN_TMP_DOS\\$name.pdf" "file:///C:/Users/${WIN_USER:-NAYAN}/AppData/Local/Temp/eks-guides/$name.html" >/dev/null 2>&1 || true
  cp "$WIN_TMP/$name.pdf" "$ROOT/docs/guides/pdf/$name.pdf"
  pages="$(python3 -c 'import re,sys; print(len(re.findall(rb"/Type\s*/Page[^s]", open(sys.argv[1],"rb").read())))' "$ROOT/docs/guides/pdf/$name.pdf")"
  echo "pdf/$name.pdf  ($pages pages)"
done
