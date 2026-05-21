#!/bin/bash
# cc-statusline — Lucas's Claude Code statusline.
# Inspired by https://github.com/nilbuild/claude-statusline (MIT).
#
# Line 1: <Model> | ✍️ <ctx%> | [🏠|🌳] <name> (<branch>*) [⚑N] | ⏲️ <duration>
# Line 2: <5h-bar> <pct>% ⟳ <reset>  |  <7d-bar> <pct>% ⟳ <reset>
#
# Both lines truncate as a whole with … when over MAX_WIDTH cols.

set -f

input=$(cat)

if [ -z "$input" ]; then
    printf "Claude"
    exit 0
fi


# ── Colors ──────────────────────────────────────────────
# $'...' interpolates \033 → actual ESC byte (vs literal \033 4-char string).
blue=$'\033[38;2;0;153;255m'
orange=$'\033[38;2;255;176;85m'
green=$'\033[38;2;0;175;80m'
cyan=$'\033[38;2;86;182;194m'
red=$'\033[38;2;255;85;85m'
yellow=$'\033[38;2;230;200;0m'
white=$'\033[38;2;220;220;220m'
magenta=$'\033[38;2;180;140;255m'
dim=$'\033[2m'
reset=$'\033[0m'

sep=" ${dim}|${reset} "

# ── Helpers ─────────────────────────────────────────────
color_for_pct() {
    local pct=$1
    if [ "$pct" -ge 90 ]; then printf "$red"
    elif [ "$pct" -ge 70 ]; then printf "$yellow"
    elif [ "$pct" -ge 50 ]; then printf "$orange"
    else printf "$green"
    fi
}

build_bar() {
    local pct=$1
    local width=$2
    [ "$pct" -lt 0 ] 2>/dev/null && pct=0
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100

    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))
    local bar_color
    bar_color=$(color_for_pct "$pct")

    local filled_str="" empty_str=""
    for ((i=0; i<filled; i++)); do filled_str+="●"; done
    for ((i=0; i<empty; i++)); do empty_str+="○"; done

    printf "${bar_color}${filled_str}${dim}${empty_str}${reset}"
}

format_epoch_time() {
    local epoch=$1
    local style=$2
    [ -z "$epoch" ] || [ "$epoch" = "null" ] || [ "$epoch" = "0" ] && return

    local result=""
    case "$style" in
        time)
            result=$(date -j -r "$epoch" +"%l:%M%p" 2>/dev/null)
            [ -z "$result" ] && result=$(date -d "@$epoch" +"%l:%M%P" 2>/dev/null)
            result=$(echo "$result" | sed 's/^ //; s/\.//g' | tr '[:upper:]' '[:lower:]')
            ;;
        datetime)
            result=$(date -j -r "$epoch" +"%b %-d, %l:%M%p" 2>/dev/null)
            [ -z "$result" ] && result=$(date -d "@$epoch" +"%b %-d, %l:%M%P" 2>/dev/null)
            result=$(echo "$result" | sed 's/  / /g; s/^ //; s/\.//g' | tr '[:upper:]' '[:lower:]')
            ;;
        *)
            result=$(date -j -r "$epoch" +"%b %-d" 2>/dev/null)
            [ -z "$result" ] && result=$(date -d "@$epoch" +"%b %-d" 2>/dev/null)
            result=$(echo "$result" | tr '[:upper:]' '[:lower:]')
            ;;
    esac
    printf "%s" "$result"
}

iso_to_epoch() {
    local iso_str="$1"
    local stripped="${iso_str%%.*}"
    local is_utc=false
    case "$iso_str" in
        *Z*|*+00:00*|*-00:00*) is_utc=true ;;
    esac
    stripped="${stripped%%Z}"
    stripped="${stripped%%+*}"
    stripped="${stripped%%-[0-9][0-9]:[0-9][0-9]}"

    local epoch=""
    if $is_utc; then
        epoch=$(env TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
        [ -z "$epoch" ] && epoch=$(env TZ=UTC date -d "${stripped/T/ }" +%s 2>/dev/null)
    else
        epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
        [ -z "$epoch" ] && epoch=$(date -d "${stripped/T/ }" +%s 2>/dev/null)
    fi
    [ -n "$epoch" ] && echo "$epoch"
}

# Strip ANSI escape codes to measure visible width.
strip_ansi() {
    printf "%s" "$1" | sed $'s/\033\\[[0-9;]*[a-zA-Z]//g'
}

# ── Extract stdin JSON ──────────────────────────────────
model_name=$(echo "$input" | jq -r '.model.display_name // "Claude"')

size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
[ "$size" -eq 0 ] 2>/dev/null && size=200000

input_tokens=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
cache_create=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
cache_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
current=$(( input_tokens + cache_create + cache_read ))
if [ "$size" -gt 0 ]; then
    pct_used=$(( current * 100 / size ))
else
    pct_used=0
fi

cwd=$(echo "$input" | jq -r '.cwd // ""')
[ -z "$cwd" ] || [ "$cwd" = "null" ] && cwd=$(pwd)

# ── Worktree vs repo root ───────────────────────────────
# 🌳 + worktree name only (branch implied, no redundant `(worktree-foo)`)
# 🏠 + repo dirname + (branch*) when in repo root
if [[ "$cwd" == *"/.claude/worktrees/"* ]]; then
    place_icon="🌳"
    place_name=$(basename "$cwd")
    show_branch=false
else
    place_icon="🏠"
    place_name=$(basename "$cwd")
    show_branch=true
fi

# ── Git state ───────────────────────────────────────────
git_branch=""
git_dirty=""
git_stash_count=0
if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git_branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)
    if [ -n "$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)" ]; then
        git_dirty="*"
    fi
    # Stash count — only counted if at least one stash exists
    git_stash_count=$(git -C "$cwd" --no-optional-locks stash list 2>/dev/null | wc -l | tr -d ' ')
fi

# Worktree: still capture dirty so we can suffix the worktree name with *
[ "$show_branch" = "false" ] && [ -n "$git_dirty" ] && place_name+="*"

# ── Session duration ────────────────────────────────────
# Source priority:
#   1. ~/.claude/sessions/<pid>.json `startedAt` looked up by sessionId
#      (CC's own session registry — authoritative, epoch ms)
#   2. stdin .session.start_time (older CC versions)
#   3. mtime of the session JSONL file (last-resort fallback)
session_duration=""
start_epoch=""

# Try stdin sessionId first; the field name varies across CC versions.
session_id=$(echo "$input" | jq -r '.session.id // .sessionId // .session_id // empty')

# (1) Session registry lookup
if [ -n "$session_id" ] && [ -d "$HOME/.claude/sessions" ]; then
    # Find the registry file with matching sessionId (one jq pass over all of them)
    started_ms=$(jq -r --arg sid "$session_id" 'select(.sessionId == $sid) | .startedAt' \
        "$HOME"/.claude/sessions/*.json 2>/dev/null | head -1)
    if [ -n "$started_ms" ] && [ "$started_ms" != "null" ]; then
        start_epoch=$(( started_ms / 1000 ))
    fi
fi

# (2) Stdin fallback (legacy)
if [ -z "$start_epoch" ]; then
    session_start=$(echo "$input" | jq -r '.session.start_time // .session.startedAt // empty')
    if [ -n "$session_start" ] && [ "$session_start" != "null" ]; then
        # Pure-digits (no `T`, no `-`, no `:`) = epoch (ms if ≥13 digits, else seconds).
        # Anything else → treat as ISO 8601.
        if [[ "$session_start" =~ ^[0-9]+$ ]]; then
            if [ ${#session_start} -ge 13 ]; then
                start_epoch=$(( session_start / 1000 ))
            else
                start_epoch=$session_start
            fi
        else
            start_epoch=$(iso_to_epoch "$session_start")
        fi
    fi
fi

# (3) JSONL mtime fallback
if [ -z "$start_epoch" ] && [ -n "$session_id" ]; then
    sanitized=$(echo "$cwd" | sed 's|/|-|g')
    jsonl="$HOME/.claude/projects/${sanitized}/${session_id}.jsonl"
    if [ -f "$jsonl" ]; then
        # Use birth time on macOS (stat -f %B), creation/mtime on Linux fallback
        start_epoch=$(stat -f %B "$jsonl" 2>/dev/null || stat -c %Y "$jsonl" 2>/dev/null)
    fi
fi

if [ -n "$start_epoch" ] && [ "$start_epoch" -gt 0 ] 2>/dev/null; then
    now_epoch=$(date +%s)
    elapsed=$(( now_epoch - start_epoch ))
    if [ "$elapsed" -ge 3600 ]; then
        session_duration="$(( elapsed / 3600 ))h$(( (elapsed % 3600) / 60 ))m"
    elif [ "$elapsed" -ge 60 ]; then
        session_duration="$(( elapsed / 60 ))m"
    elif [ "$elapsed" -ge 0 ]; then
        session_duration="${elapsed}s"
    fi
fi

# ── Build line 1 ────────────────────────────────────────
pct_color=$(color_for_pct "$pct_used")
line1="${blue}${model_name}${reset}"
line1+="${sep}"
line1+="✍️ ${pct_color}${pct_used}%${reset}"
line1+="${sep}"
line1+="${place_icon} ${cyan}${place_name}${reset}"
if $show_branch && [ -n "$git_branch" ]; then
    line1+=" ${green}(${git_branch}${red}${git_dirty}${green})${reset}"
fi
if [ "$git_stash_count" -gt 0 ] 2>/dev/null; then
    line1+=" ${dim}📚${git_stash_count}${reset}"
fi
if [ -n "$session_duration" ]; then
    line1+="${sep}"
    line1+="${dim}⏲️ ${reset}${white}${session_duration}${reset}"
fi

# ── Rate limits ─────────────────────────────────────────
# Source design:
#   - Utilization: prefer stdin (freshest per-keystroke).
#   - Reset timestamps: ALWAYS from the cache, refreshed via the API on TTL miss.
#     Stdin's resets_at field is unreliable (CC sends it irregularly), and the
#     cache previously starved when has_stdin_rates locked out refreshes —
#     reset times went stale for hours. This refresh path is independent of
#     stdin contents.
five_pct=""; five_reset_epoch=""
seven_pct=""; seven_reset_epoch=""

stdin_five=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
if [ -n "$stdin_five" ]; then
    five_pct=$(printf "%.0f" "$stdin_five")
    seven_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' | awk '{printf "%.0f", $1}')
fi

cache_file="/tmp/claude/statusline-usage-cache.json"
cache_max_age=300  # 5min — reset timestamps don't move that fast; saves API hammer
mkdir -p /tmp/claude
usage_data=""
needs_refresh=true

if [ -f "$cache_file" ]; then
    cache_mtime=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null)
    now=$(date +%s)
    cache_age=$(( now - cache_mtime ))
    if [ "$cache_age" -lt "$cache_max_age" ]; then
        needs_refresh=false
    fi
    usage_data=$(cat "$cache_file" 2>/dev/null)
fi

if $needs_refresh; then
    token=""
    if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
        token="$CLAUDE_CODE_OAUTH_TOKEN"
    elif command -v security >/dev/null 2>&1; then
        blob=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
        if [ -n "$blob" ]; then
            token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
        fi
    fi
    if [ -z "$token" ] || [ "$token" = "null" ]; then
        creds_file="${HOME}/.claude/.credentials.json"
        if [ -f "$creds_file" ]; then
            token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds_file" 2>/dev/null)
        fi
    fi
    if [ -z "$token" ] || [ "$token" = "null" ]; then
        if command -v secret-tool >/dev/null 2>&1; then
            blob=$(timeout 2 secret-tool lookup service "Claude Code-credentials" 2>/dev/null)
            if [ -n "$blob" ]; then
                token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
            fi
        fi
    fi

    if [ -n "$token" ] && [ "$token" != "null" ]; then
        response=$(curl -s --max-time 5 \
            -H "Accept: application/json" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $token" \
            -H "anthropic-beta: oauth-2025-04-20" \
            -H "User-Agent: claude-code/2.1.34" \
            "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
        if [ -n "$response" ] && echo "$response" | jq -e '.five_hour' >/dev/null 2>&1; then
            usage_data="$response"
            echo "$response" > "$cache_file"
        fi
    fi
fi

# Pull reset timestamps + utilization-fallback from cache.
if [ -n "$usage_data" ] && echo "$usage_data" | jq -e . >/dev/null 2>&1; then
    five_reset_iso=$(echo "$usage_data" | jq -r '.five_hour.resets_at // empty')
    five_reset_epoch=$(iso_to_epoch "$five_reset_iso")
    seven_reset_iso=$(echo "$usage_data" | jq -r '.seven_day.resets_at // empty')
    seven_reset_epoch=$(iso_to_epoch "$seven_reset_iso")

    # If stdin didn't carry utilization, use cache values.
    if [ -z "$five_pct" ]; then
        five_pct=$(echo "$usage_data" | jq -r '.five_hour.utilization // 0' | awk '{printf "%.0f", $1}')
    fi
    if [ -z "$seven_pct" ]; then
        seven_pct=$(echo "$usage_data" | jq -r '.seven_day.utilization // 0' | awk '{printf "%.0f", $1}')
    fi
fi

# ── Build line 2 ────────────────────────────────────────
# 5-circle bars, no labels, 5h | 7d on one line
line2=""
bar_width=5

if [ -n "$five_pct" ]; then
    five_bar=$(build_bar "$five_pct" "$bar_width")
    five_color=$(color_for_pct "$five_pct")
    five_reset_fmt=$(format_epoch_time "$five_reset_epoch" "time")
    line2+="${five_bar} ${five_color}${five_pct}%${reset}"
    [ -n "$five_reset_fmt" ] && line2+=" ${dim}⟳${reset} ${white}${five_reset_fmt}${reset}"
fi

if [ -n "$seven_pct" ]; then
    seven_bar=$(build_bar "$seven_pct" "$bar_width")
    seven_color=$(color_for_pct "$seven_pct")
    seven_reset_fmt=$(format_epoch_time "$seven_reset_epoch" "datetime")
    [ -n "$line2" ] && line2+="${sep}"
    line2+="${seven_bar} ${seven_color}${seven_pct}%${reset}"
    [ -n "$seven_reset_fmt" ] && line2+=" ${dim}⟳${reset} ${white}${seven_reset_fmt}${reset}"
fi

# ── Output ──────────────────────────────────────────────
printf "%s" "$line1"
[ -n "$line2" ] && printf "\n%s" "$line2"

exit 0
