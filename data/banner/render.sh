#!/bin/sh
# Render banner.html to data/banner.png (2560x1280, transparent rounded corners).
set -eu

cd "$(dirname "$0")"

CHROME=${CHROME:-}
if [ -z "$CHROME" ]; then
    for c in google-chrome google-chrome-stable chromium chromium-browser; do
        if command -v "$c" >/dev/null 2>&1; then CHROME=$c; break; fi
    done
fi
if [ -z "$CHROME" ]; then
    echo "No Chrome/Chromium found; set CHROME=/path/to/chrome" >&2
    exit 1
fi

if ! fc-list : family | grep -q "Inter Display"; then
    echo "warning: 'Inter Display' font not installed, output will use a fallback font" >&2
fi

"$CHROME" --headless=new --disable-gpu --hide-scrollbars \
    --force-device-scale-factor=2 \
    --default-background-color=00000000 \
    --allow-file-access-from-files \
    --window-size=1280,640 \
    --screenshot="$PWD/../banner.png" \
    "file://$PWD/banner.html" 2>/dev/null

echo "Wrote $(cd .. && pwd)/banner.png"
