# cc-statusline

Minimal Claude Code statusline. Two lines, terminal wraps if it overflows.

Inspired by [nilbuild/claude-statusline](https://github.com/nilbuild/claude-statusline) (MIT).

## What it looks like

```
Sonnet 4.6 | ✍️ 41% | 🏠 find-me-trials (main*) ⚑2 | ⏲️ 1h0m
●●○○○ 47% ⟳ 4:30pm | ●○○○○ 18% ⟳ may 26, 4:30pm
```

Inside a worktree:
```
Opus 4.7 | ✍️ 65% | 🌳 open-signup* ⚑2 | ⏲️ 3h0m
●●○○○ 47% ⟳ 4:30pm | ●○○○○ 18% ⟳ may 26, 4:30pm
```

### Line 1 — session
`Model | ctx% | place name (branch*) ⚑stash | ⏲️ duration`

- 🏠 in the repo root, 🌳 inside a worktree (`.claude/worktrees/<name>`)
- Branch shown in the repo root; worktree mode shows the worktree name only (branch is implied)
- `*` = dirty working tree
- `⚑N` = stash count, only shown when stashes exist

### Line 2 — rate limits
`5h-bar pct% ⟳ reset | 7d-bar pct% ⟳ reset`

- 5-segment bars, no labels
- `current` (5-hour) on the left, `weekly` (7-day) on the right

### Color thresholds
- `< 50%` green
- `≥ 50%` orange
- `≥ 70%` yellow
- `≥ 90%` red

Applied to context %, 5-hour %, and 7-day %.

## Install

```bash
curl -sL https://raw.githubusercontent.com/lucasfdale/cc-statusline/main/install.sh | bash
```

Backs up any existing `~/.claude/statusline.sh` to `statusline.sh.bak`, drops the new script in, and wires it into `~/.claude/settings.json`.

Restart Claude Code afterward.

## Uninstall

```bash
curl -sL https://raw.githubusercontent.com/lucasfdale/cc-statusline/main/uninstall.sh | bash
```

Restores `statusline.sh.bak` if present, otherwise moves the script to Trash. Removes the `statusLine` entry from `~/.claude/settings.json`.

## Requirements

- `jq` — JSON parsing
- `curl` — fetching rate-limit data when stdin lacks it
- `git` — branch / dirty / stash info

macOS: `brew install jq` covers the only one that isn't preinstalled.

## Data sources

- **Stdin JSON** (Claude Code hook payload) — model, cwd, context window, session start, and rate limits when CC v2.x provides them
- **`~/.claude/settings.json`** — read-only
- **`api.anthropic.com/api/oauth/usage`** — only when stdin lacks rate limits, with a 60-second cache at `/tmp/claude/statusline-usage-cache.json`. OAuth token sourced from (in order): `$CLAUDE_CODE_OAUTH_TOKEN`, macOS Keychain (`Claude Code-credentials`), `~/.claude/.credentials.json`, Linux `secret-tool`

No other network calls. No telemetry. No file reads outside `~/.claude/` and the current repo.

## License

MIT. See [LICENSE](./LICENSE).
