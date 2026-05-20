#!/bin/bash
# cc-statusline uninstaller.
# curl -sL https://raw.githubusercontent.com/lucasfdale/cc-statusline/main/uninstall.sh | bash
set -e

CLAUDE_DIR="$HOME/.claude"
STATUSLINE_DEST="$CLAUDE_DIR/statusline.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

g=$'\033[38;2;0;175;80m'; r=$'\033[38;2;255;85;85m'; y=$'\033[38;2;230;200;0m'; d=$'\033[2m'; n=$'\033[0m'

echo
echo "  ${g}cc-statusline uninstaller${n}"
echo "  ${d}─────────────────────────${n}"
echo

backup="$STATUSLINE_DEST.bak"
if [ -f "$backup" ]; then
    # Use /usr/bin/trash so the previous statusline is recoverable
    if command -v /usr/bin/trash >/dev/null 2>&1; then
        /usr/bin/trash "$STATUSLINE_DEST" 2>/dev/null || true
    fi
    mv "$backup" "$STATUSLINE_DEST"
    echo "  ${g}✓${n} Restored previous statusline from ${d}statusline.sh.bak${n}"
elif [ -f "$STATUSLINE_DEST" ]; then
    if command -v /usr/bin/trash >/dev/null 2>&1; then
        /usr/bin/trash "$STATUSLINE_DEST"
    else
        rm "$STATUSLINE_DEST"
    fi
    echo "  ${g}✓${n} Moved ${d}statusline.sh${n} to Trash"
else
    echo "  ${y}!${n} No statusline found — nothing to remove"
fi

if [ -f "$SETTINGS" ]; then
    tmp=$(mktemp)
    if jq 'del(.statusLine)' "$SETTINGS" > "$tmp"; then
        mv "$tmp" "$SETTINGS"
        echo "  ${g}✓${n} Removed statusLine from ${d}settings.json${n}"
    else
        rm -f "$tmp"
        echo "  ${r}✗${n} Could not parse $SETTINGS — fix it manually"
        exit 1
    fi
fi

echo
echo "  ${g}Done.${n} Restart Claude Code to apply changes."
echo
