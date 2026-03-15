#!/bin/bash
EDGE="/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"
DIR="C:\\Users\\gyane\\claude-multi-account\\marketing\\images"
FDIR="file:///C:/Users/gyane/claude-multi-account/marketing/images"

capture() {
    local name="$1" w="$2" h="$3"
    "$EDGE" --headless --disable-gpu \
        --screenshot="${DIR}\\${name}.png" \
        --window-size=${w},${h} \
        --default-background-color=0 \
        --hide-scrollbars \
        "${FDIR}/${name}.html" 2>/dev/null
    if [ -f "/c/Users/gyane/claude-multi-account/marketing/images/${name}.png" ]; then
        local sz=$(stat -c%s "/c/Users/gyane/claude-multi-account/marketing/images/${name}.png" 2>/dev/null)
        echo "  OK  ${name}.png ($((sz/1024)) KB)"
    else
        echo "  FAIL ${name}.png"
    fi
}

echo "Capturing screenshots..."
for f in /c/Users/gyane/claude-multi-account/marketing/images/*.html; do
    name=$(basename "$f" .html)
    if [[ "$name" == *"twitter"* ]] || [[ "$name" == *"github"* ]] || [[ "$name" == *"linkedin"* ]]; then
        if [[ "$name" == *"github"* ]]; then
            capture "$name" 1280 640
        else
            capture "$name" 1200 628
        fi
    else
        capture "$name" 800 900
    fi
done
echo "Done!"
