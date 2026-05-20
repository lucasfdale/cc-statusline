#!/bin/bash
# cc-statusline installer.
# One-liner: curl -sL https://raw.githubusercontent.com/lucasfdale/cc-statusline/main/install.sh | bash
set -e

CLAUDE_DIR="$HOME/.claude"
STATUSLINE_DEST="$CLAUDE_DIR/statusline.sh"
SETTINGS="$CLAUDE_DIR/settings.json"
REPO_RAW="https://raw.githubusercontent.com/lucasfdale/cc-statusline/main"

# Colors
g=$'\033[38;2;0;175;80m'; r=$'\033[38;2;255;85;85m'; y=$'\033[38;2;230;200;0m'; d=$'\033[2m'; n=$'\033[0m'

echo
echo "  ${g}cc-statusline installer${n}"
echo "  ${d}───────────────────────${n}"
echo

# Deps
missing=()
for cmd in jq curl git python3; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if [ ${#missing[@]} -gt 0 ]; then
    echo "  ${r}✗${n} Missing dependencies: ${missing[*]}"
    echo "  ${d}brew install jq${n}  # if you're on macOS"
    exit 1
fi
echo "  ${g}✓${n} Dependencies found (jq, curl, git, python3)"

mkdir -p "$CLAUDE_DIR"

# Backup any existing statusline
if [ -f "$STATUSLINE_DEST" ]; then
    cp "$STATUSLINE_DEST" "$STATUSLINE_DEST.bak"
    echo "  ${y}!${n} Backed up existing statusline to ${d}statusline.sh.bak${n}"
fi

# Fetch latest statusline.sh
if curl -fsSL "$REPO_RAW/statusline.sh" -o "$STATUSLINE_DEST"; then
    chmod 755 "$STATUSLINE_DEST"
    echo "  ${g}✓${n} Installed statusline to ${d}$STATUSLINE_DEST${n}"
else
    echo "  ${r}✗${n} Failed to fetch statusline.sh from $REPO_RAW"
    exit 1
fi

# Wire into settings.json
if [ -f "$SETTINGS" ]; then
    # Patch in-place using jq
    tmp=$(mktemp)
    if jq '.statusLine = {"type":"command","command":"bash \"$HOME/.claude/statusline.sh\""}' "$SETTINGS" > "$tmp"; then
        mv "$tmp" "$SETTINGS"
        echo "  ${g}✓${n} Updated ${d}settings.json${n} with statusLine config"
    else
        rm -f "$tmp"
        echo "  ${r}✗${n} Could not parse $SETTINGS — fix it manually"
        exit 1
    fi
else
    cat > "$SETTINGS" <<'JSON'
{
  "statusLine": {
    "type": "command",
    "command": "bash \"$HOME/.claude/statusline.sh\""
  }
}
JSON
    echo "  ${g}✓${n} Created ${d}settings.json${n} with statusLine config"
fi

echo
echo "  ${g}Done.${n} Restart Claude Code to see the new statusline."
echo
