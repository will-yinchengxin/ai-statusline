#!/bin/bash
# Will's Codex CLI Statusline adapter
# Codex CLI uses native [tui].status_line items instead of Claude Code's
# external statusLine command. This script installs that native config and
# provides a local preview with the same visual style as statusline.sh.
exec 2>/dev/null

set -u

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CONFIG_FILE="$CODEX_HOME/config.toml"
BACKUP_FILE="$CONFIG_FILE.will-statusline.bak"
STATUS_ITEMS='["model-with-reasoning", "fast-mode", "current-dir", "git-branch", "context-used", "context-remaining", "five-hour-limit", "weekly-limit", "used-tokens", "total-input-tokens", "total-output-tokens", "session-id", "codex-version"]'

RST="\033[0m"
DIM="\033[2m"
BOLD="\033[1m"
CYAN="\033[36m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
MAGENTA="\033[35m"
BLUE="\033[94m"
WHITE="\033[97m"
GRAY="\033[90m"

usage() {
  cat <<'EOF'
Usage:
  bash codex-statusline.sh --install   Configure ~/.codex/config.toml
  bash codex-statusline.sh --preview   Print a local preview
  bash codex-statusline.sh --items     Print the Codex status_line items
  bash codex-statusline.sh --help

Codex CLI does not run an external statusline command like Claude Code.
This adapter writes the equivalent native [tui].status_line configuration.
EOF
}

short_dir() {
  local dir="$1"
  [ -z "$dir" ] && printf "~" && return
  dir="${dir/#$HOME/\~}"
  local count
  count=$(printf '%s' "$dir" | tr -cd '/' | wc -c | tr -d ' ')
  if [ "${#dir}" -gt 30 ] && [ "$count" -ge 3 ]; then
    printf '%s' "$dir" | awk -F'/' '{print ".../" $(NF-1) "/" $NF}'
  else
    printf '%s' "$dir"
  fi
}

fmt_tokens() {
  local t="${1:-0}"
  if [ "$t" -ge 1000000 ] 2>/dev/null; then
    awk "BEGIN { printf \"%.1fM\", $t / 1000000 }"
  elif [ "$t" -ge 1000 ] 2>/dev/null; then
    awk "BEGIN { printf \"%.1fk\", $t / 1000 }"
  else
    printf "%s" "$t"
  fi
}

usage_color() {
  local pct="${1:-0}"
  if   [ "$pct" -ge 85 ] 2>/dev/null; then printf "%s" "$RED"
  elif [ "$pct" -ge 60 ] 2>/dev/null; then printf "%s" "$YELLOW"
  else printf "%s" "$GREEN"
  fi
}

quota_color() {
  local pct="${1:-0}"
  if   [ "$pct" -ge 90 ] 2>/dev/null; then printf "%s" "$RED"
  elif [ "$pct" -ge 70 ] 2>/dev/null; then printf "%s" "$YELLOW"
  else printf "%s" "$BLUE"
  fi
}

toml_value() {
  local key="$1"
  [ -f "$CONFIG_FILE" ] || return
  awk -F= -v k="$key" '
    $0 ~ "^[[:space:]]*" k "[[:space:]]*=" {
      v=$2
      sub(/^[[:space:]]*/, "", v)
      sub(/[[:space:]]*#.*/, "", v)
      gsub(/^"|"$/, "", v)
      print v
      exit
    }
  ' "$CONFIG_FILE"
}

latest_session_jsonl() {
  [ -d "$CODEX_HOME/sessions" ] || return
  find "$CODEX_HOME/sessions" -name 'rollout-*.jsonl' -print 2>/dev/null | sort | tail -n 1
}

jsonl_field() {
  local file="$1" expr="$2"
  [ -n "$file" ] && [ -f "$file" ] && command -v jq >/dev/null 2>&1 || return
  jq -r "select(.type == \"session_meta\") | $expr // empty" "$file" 2>/dev/null | tail -n 1
}

detect_context() {
  local latest
  latest=$(latest_session_jsonl)
  CODEX_MODEL="${CODEX_MODEL:-$(jsonl_field "$latest" '.payload.model')}"
  CODEX_MODEL="${CODEX_MODEL:-$(toml_value model)}"
  CODEX_MODEL="${CODEX_MODEL:-Codex}"

  CODEX_REASONING="${CODEX_REASONING:-$(toml_value model_reasoning_effort)}"
  [ -n "${CODEX_REASONING:-}" ] && CODEX_MODEL="$CODEX_MODEL $CODEX_REASONING"

  CODEX_CWD="${CODEX_CWD:-$(jsonl_field "$latest" '.payload.cwd')}"
  CODEX_CWD="${CODEX_CWD:-$PWD}"

  CODEX_SESSION_ID="${CODEX_SESSION_ID:-$(jsonl_field "$latest" '.payload.id')}"
  CODEX_VERSION="${CODEX_VERSION:-$(codex --version 2>/dev/null | awk '{print $NF}')}"
  CODEX_VERSION="${CODEX_VERSION:-unknown}"
}

language_part() {
  local cwd="$1"
  if [ -f "$cwd/pom.xml" ] || [ -f "$cwd/build.gradle" ] || [ -f "$cwd/build.gradle.kts" ]; then
    printf "Java"
  elif [ -f "$cwd/Cargo.toml" ]; then
    printf "Rust"
  elif [ -f "$cwd/go.mod" ]; then
    printf "Go"
  elif [ -f "$cwd/pyproject.toml" ] || [ -f "$cwd/requirements.txt" ] || [ -f "$cwd/setup.py" ]; then
    printf "Python"
  elif [ -f "$cwd/package.json" ]; then
    if grep -q '"typescript"' "$cwd/package.json" 2>/dev/null || [ -f "$cwd/tsconfig.json" ]; then
      printf "TypeScript"
    else
      printf "Node.js"
    fi
  elif [ -f "$cwd/composer.json" ]; then
    printf "PHP"
  elif [ -f "$cwd/Gemfile" ]; then
    printf "Ruby"
  elif [ -f "$cwd/CMakeLists.txt" ] || ls "$cwd"/*.cpp "$cwd"/*.cc "$cwd"/*.h >/dev/null 2>&1; then
    printf "C/C++"
  elif [ -f "$cwd/Makefile" ]; then
    printf "Make"
  elif ls "$cwd"/*.sh >/dev/null 2>&1; then
    printf "Shell"
  else
    printf "Text"
  fi
}

git_segment() {
  local cwd="$1" branch porcelain ahead_behind ahead behind
  branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null \
    || git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  if [ -z "$branch" ]; then
    printf "%b" "${DIM}[${RST}${GRAY}no git${RST}${DIM}]${RST}"
    return
  fi

  porcelain=$(git -C "$cwd" status --porcelain 2>/dev/null)
  ahead_behind=$(git -C "$cwd" rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)
  ahead=$(echo "$ahead_behind" | awk '{print $1}')
  behind=$(echo "$ahead_behind" | awk '{print $2}')

  local remote_seg=""
  [ -n "$ahead" ] && [ "$ahead" -gt 0 ] 2>/dev/null && remote_seg="${remote_seg} ${CYAN}↑${ahead}领先${RST}"
  [ -n "$behind" ] && [ "$behind" -gt 0 ] 2>/dev/null && remote_seg="${remote_seg} ${RED}↓${behind}落后${RST}"

  if [ -z "$porcelain" ]; then
    printf "%b" "${DIM}[${RST}${MAGENTA}${BOLD}⎇ ${branch}${RST}${remote_seg} ${GREEN}✓ 干净${RST}${DIM}]${RST}"
    return
  fi

  local staged worktree untracked conflicts status_seg=""
  staged=$(echo "$porcelain" | grep -c '^[AMRCD]')
  worktree=$(echo "$porcelain" | grep -c '^.[MD]')
  untracked=$(echo "$porcelain" | grep -c '^\?\?')
  conflicts=$(echo "$porcelain" | grep -c '^UU\|^AA\|^DD')

  [ "$conflicts" -gt 0 ] && status_seg="${status_seg}${RED}✖ ${conflicts}冲突${RST}"
  [ "$staged" -gt 0 ] && status_seg="${status_seg:+${status_seg} ${DIM}·${RST} }${GREEN}● ${staged}暂存${RST}"
  [ "$worktree" -gt 0 ] && status_seg="${status_seg:+${status_seg} ${DIM}·${RST} }${YELLOW}○ ${worktree}已改${RST}"
  [ "$untracked" -gt 0 ] && status_seg="${status_seg:+${status_seg} ${DIM}·${RST} }${BLUE}? ${untracked}新文件${RST}"

  printf "%b" "${DIM}[${RST}${MAGENTA}${BOLD}⎇ ${branch}${RST}${remote_seg} ${DIM}│${RST} ${status_seg}${DIM}]${RST}"
}

preview() {
  detect_context

  local username dir_display used_tokens total_tokens ctx_pct ctx_color bar filled empty
  username=$(whoami 2>/dev/null || echo user)
  dir_display=$(short_dir "$CODEX_CWD")
  used_tokens="${CODEX_USED_TOKENS:-0}"
  total_tokens="${CODEX_CONTEXT_WINDOW:-0}"
  ctx_pct="${CODEX_CONTEXT_USED_PERCENT:-0}"
  ctx_color=$(usage_color "$ctx_pct")

  local BAR_WIDTH=12
  filled=$((ctx_pct * BAR_WIDTH / 100))
  [ "$filled" -gt "$BAR_WIDTH" ] && filled=$BAR_WIDTH
  empty=$((BAR_WIDTH - filled))
  bar=""
  [ "$filled" -gt 0 ] && bar=$(printf "%${filled}s" | tr ' ' '▓')
  [ "$empty" -gt 0 ] && bar="${bar}$(printf "%${empty}s" | tr ' ' '░')"

  local model_part userdir_part ctx_part five_part seven_part lang git_part time_part version_part
  model_part="${DIM}[${RST}${CYAN}${BOLD}${CODEX_MODEL}${RST}${DIM}]${RST}"
  userdir_part="${DIM}[${RST}${GREEN}${BOLD}${username}${RST}${GRAY}@${RST}${WHITE}${dir_display}${RST}${DIM}]${RST}"
  if [ "$total_tokens" -gt 0 ] 2>/dev/null; then
    ctx_part="${DIM}[${RST}${GRAY}Ctx${RST} ${ctx_color}${bar}${RST} ${ctx_color}${BOLD}${ctx_pct}%${RST} ${DIM}$(fmt_tokens "$used_tokens")/$(fmt_tokens "$total_tokens")${RST}${DIM}]${RST}"
  else
    ctx_part="${DIM}[${RST}${GRAY}Ctx${RST} ${ctx_color}${bar}${RST} ${ctx_color}${BOLD}${ctx_pct}%${RST}${DIM}]${RST}"
  fi

  five_part="${DIM}[${RST}${GRAY}5h${RST} ${DIM}native${RST}${DIM}]${RST}"
  seven_part="${DIM}[${RST}${GRAY}7d${RST} ${DIM}native${RST}${DIM}]${RST}"
  lang="${DIM}[${RST}$(language_part "$CODEX_CWD")${DIM}]${RST}"
  git_part=$(git_segment "$CODEX_CWD")
  time_part="${DIM}[${RST}${GRAY}$(date +"%H:%M" 2>/dev/null)${RST}${DIM}]${RST}"
  version_part="${DIM}[${RST}${GRAY}codex ${CODEX_VERSION}${RST}${DIM}]${RST}"

  printf "%b\n%b\n%b\n" \
    "╭─ ${model_part} ${userdir_part} ${version_part}" \
    "├─ ${ctx_part} ${five_part} ${seven_part}" \
    "╰─ ${lang} ${git_part} ${time_part}"
}

install_config() {
  mkdir -p "$CODEX_HOME"
  [ -f "$CONFIG_FILE" ] || printf '\n' > "$CONFIG_FILE"
  cp "$CONFIG_FILE" "$BACKUP_FILE"

  if command -v python3 >/dev/null 2>&1; then
    CONFIG_FILE="$CONFIG_FILE" STATUS_ITEMS="$STATUS_ITEMS" python3 - <<'PYEOF'
import os
from pathlib import Path

path = Path(os.environ["CONFIG_FILE"])
items = os.environ["STATUS_ITEMS"]
lines = path.read_text().splitlines()

out = []
in_tui = False
seen_tui = False
inserted = False
i = 0

while i < len(lines):
    line = lines[i]
    stripped = line.strip()
    is_header = stripped.startswith("[") and stripped.endswith("]")

    if is_header:
        if in_tui and not inserted:
            out.append(f"status_line = {items}")
            inserted = True
        in_tui = stripped == "[tui]"
        seen_tui = seen_tui or in_tui
        out.append(line)
        i += 1
        continue

    if in_tui and stripped.startswith("status_line"):
        out.append(f"status_line = {items}")
        inserted = True
        if "[" in line and "]" not in line:
            i += 1
            while i < len(lines) and "]" not in lines[i]:
                i += 1
        i += 1
        continue

    out.append(line)
    i += 1

if in_tui and not inserted:
    out.append(f"status_line = {items}")
    inserted = True

if not seen_tui:
    if out and out[-1].strip():
        out.append("")
    out.append("[tui]")
    out.append(f"status_line = {items}")

path.write_text("\n".join(out).rstrip() + "\n")
PYEOF
  else
    {
      printf '\n[tui]\n'
      printf 'status_line = %s\n' "$STATUS_ITEMS"
    } >> "$CONFIG_FILE"
  fi

  printf "Configured Codex status line in %s\n" "$CONFIG_FILE"
  printf "Backup written to %s\n" "$BACKUP_FILE"
}

case "${1:---preview}" in
  --install) install_config ;;
  --preview) preview ;;
  --items) printf "%s\n" "$STATUS_ITEMS" ;;
  --help|-h) usage ;;
  *) usage; exit 2 ;;
esac
