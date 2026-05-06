#!/bin/bash
# Will's Claude Code Statusline
# Line 1: ╭─[Model] [user@dir] [Ctx ▓▓░░░░░░░░ 12% 24k/200k] [5h: 42% ↻3h20m] [7d: 8% ↻6d2h] [$0.05]
# Line 2: ╰─[🐍 Python] [⎇ main ✓ 干净] [🕐 14:32]
exec 2>/dev/null

CACHE_DIR="$HOME/.cache/will-statusline"
CACHE_FILE="$CACHE_DIR/last.json"
CACHE_MAX_AGE=21600

# ── Read JSON from Claude Code stdin ──
input=$(cat)
tab=$(printf '\t')

jq_expr='[
  (.model.display_name // "Claude"),
  ((.context_window.current_usage.input_tokens // 0)
   + (.context_window.current_usage.cache_creation_input_tokens // 0)
   + (.context_window.current_usage.cache_read_input_tokens // 0) | tostring),
  (.context_window.context_window_size // 0 | tostring),
  (.context_window.used_percentage // 0 | tostring),
  (.cost.total_cost_usd // 0 | tostring),
  (.workspace.current_dir // ""),
  (.rate_limits.five_hour.used_percentage // null | if . then (. | round | tostring) else "null" end),
  (.rate_limits.five_hour.resets_at // "" | tostring),
  (.rate_limits.seven_day.used_percentage // null | if . then (. | round | tostring) else "null" end),
  (.rate_limits.seven_day.resets_at // "" | tostring)
] | @tsv'

jq_rl='[
  (.rate_limits.five_hour.used_percentage // null | if . then (. | round | tostring) else "null" end),
  (.rate_limits.five_hour.resets_at // "" | tostring),
  (.rate_limits.seven_day.used_percentage // null | if . then (. | round | tostring) else "null" end),
  (.rate_limits.seven_day.resets_at // "" | tostring)
] | @tsv'

cache_file_mtime() {
  local ts=""
  ts=$(stat -c %Y "$1" 2>/dev/null || true)
  [ -z "$ts" ] && ts=$(stat -f %m "$1" 2>/dev/null || true)
  printf '%s\n' "${ts:-0}"
}

# ── Parse live input ──
parsed=""
[ -n "$input" ] && parsed=$(printf '%s' "$input" | jq -r "$jq_expr" 2>/dev/null)

IFS="$tab" read -r model used_tokens window_size used_pct cost_usd cwd \
  live_five_pct live_five_reset live_seven_pct live_seven_reset <<EOF
$parsed
EOF

model="${model:-Claude}"
used_tokens="${used_tokens:-0}"
window_size="${window_size:-0}"
used_pct="${used_pct:-0}"
cost_usd="${cost_usd:-0}"
cwd="${cwd:-}"

five_pct="${live_five_pct:-}"
five_reset="${live_five_reset:-}"
seven_pct="${live_seven_pct:-}"
seven_reset="${live_seven_reset:-}"

# ── Cache fallback for rate_limits ──
if [ "$five_pct" = "null" ] || [ -z "$five_pct" ]; then
  if [ -f "$CACHE_FILE" ]; then
    cache_age=$(( $(date +%s) - $(cache_file_mtime "$CACHE_FILE") ))
    if [ "$cache_age" -lt "$CACHE_MAX_AGE" ]; then
      cached=$(jq -r "$jq_rl" "$CACHE_FILE" 2>/dev/null)
      IFS="$tab" read -r five_pct five_reset seven_pct seven_reset <<EOF
$cached
EOF
    fi
  fi
fi

# Persist live rate_limits
if [ "${live_five_pct:-}" != "null" ] && [ -n "${live_five_pct:-}" ] && [ -n "$input" ]; then
  mkdir -p "$CACHE_DIR"
  printf '%s' "$input" | jq '{rate_limits: .rate_limits}' \
    > "${CACHE_FILE}.tmp" 2>/dev/null \
    && mv "${CACHE_FILE}.tmp" "$CACHE_FILE" 2>/dev/null \
    || true
fi

# ── Colors ──
RST="\033[0m"
DIM="\033[2m"
BOLD="\033[1m"
ITALIC="\033[3m"
CYAN="\033[36m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
MAGENTA="\033[35m"
BLUE="\033[94m"
WHITE="\033[97m"
GRAY="\033[90m"

# ── Helpers ──
format_reset() {
  local ts="$1"
  [ -z "$ts" ] && return
  local epoch now diff
  epoch=$(printf '%s' "$ts" | tr -dc '0-9')
  [ -z "$epoch" ] && return
  now=$(date +%s)
  diff=$((epoch - now))
  [ "$diff" -le 0 ] && return
  local mins=$(( diff / 60 )) hours=$(( diff / 3600 )) days=$(( diff / 86400 ))
  if [ "$days" -ge 1 ]; then
    printf "%dd%dh" "$days" $(( hours % 24 ))
  elif [ "$hours" -ge 1 ]; then
    printf "%dh%dm" "$hours" $(( mins % 60 ))
  else
    printf "%dm" "$mins"
  fi
}

usage_color() {
  local pct="$1"
  if   [ "$pct" -ge 85 ] 2>/dev/null; then printf "%s" "$RED"
  elif [ "$pct" -ge 60 ] 2>/dev/null; then printf "%s" "$YELLOW"
  else printf "%s" "$GREEN"
  fi
}

quota_color() {
  local pct="$1"
  if   [ "$pct" -ge 90 ] 2>/dev/null; then printf "%s" "$RED"
  elif [ "$pct" -ge 70 ] 2>/dev/null; then printf "%s" "$YELLOW"
  else printf "%s" "$BLUE"
  fi
}

# ── Shorten working directory ──
short_dir() {
  local dir="$1"
  [ -z "$dir" ] && printf "~" && return
  # Replace $HOME with ~
  dir="${dir/#$HOME/\~}"
  # Keep last 2 path components if longer than 30 chars
  local count
  count=$(printf '%s' "$dir" | tr -cd '/' | wc -c)
  if [ "${#dir}" -gt 30 ] && [ "$count" -ge 3 ]; then
    printf '%s' "$dir" | awk -F'/' '{print "…/" $(NF-1) "/" $NF}'
  else
    printf '%s' "$dir"
  fi
}

# ── Token formatting (smart k/M) ──
fmt_tokens() {
  local t="$1"
  if [ "$t" -ge 1000000 ] 2>/dev/null; then
    printf "%.1fM" "$(echo "scale=1; $t / 1000000" | bc 2>/dev/null || echo 0)"
  elif [ "$t" -ge 1000 ] 2>/dev/null; then
    printf "%.1fk" "$(echo "scale=1; $t / 1000" | bc 2>/dev/null || echo 0)"
  else
    printf "%s" "$t"
  fi
}

# ── Build segments ──

# [Model] — bold cyan
model_part="${DIM}[${RST}${CYAN}${BOLD}${model}${RST}${DIM}]${RST}"

# [user@dir]
username=$(whoami 2>/dev/null || echo 'user')
dir_display=$(short_dir "$cwd")
userdir_part="${DIM}[${RST}${GREEN}${BOLD}${username}${RST}${GRAY}@${RST}${WHITE}${dir_display}${RST}${DIM}]${RST}"

# Context progress bar
ctx_pct_int=$(printf '%.0f' "$used_pct" 2>/dev/null || echo 0)
ctx_color=$(usage_color "$ctx_pct_int")

BAR_WIDTH=12
filled=$((ctx_pct_int * BAR_WIDTH / 100))
[ "$filled" -gt "$BAR_WIDTH" ] && filled=$BAR_WIDTH
empty=$((BAR_WIDTH - filled))
bar=""
[ "$filled" -gt 0 ] && bar=$(printf "%${filled}s" | tr ' ' '▓')
[ "$empty"  -gt 0 ] && bar="${bar}$(printf "%${empty}s" | tr ' ' '░')"

used_fmt=$(fmt_tokens "$used_tokens")
if [ "$window_size" -gt 0 ] 2>/dev/null; then
  total_fmt=$(fmt_tokens "$window_size")
  ctx_part="${DIM}[${RST}${GRAY}Ctx${RST} ${ctx_color}${bar}${RST} ${ctx_color}${BOLD}${ctx_pct_int}%${RST} ${DIM}${used_fmt}/${total_fmt}${RST}${DIM}]${RST}"
else
  ctx_part="${DIM}[${RST}${GRAY}Ctx${RST} ${ctx_color}${bar}${RST} ${ctx_color}${BOLD}${ctx_pct_int}%${RST}${DIM}]${RST}"
fi

# 5h quota
if [ "$five_pct" != "null" ] && [ -n "$five_pct" ]; then
  color=$(quota_color "$five_pct")
  reset_str=$(format_reset "$five_reset")
  if [ -n "$reset_str" ]; then
    five_part="${DIM}[${RST}${GRAY}5h${RST} ${color}${BOLD}${five_pct}%${RST} ${DIM}↻${reset_str}${RST}${DIM}]${RST}"
  else
    five_part="${DIM}[${RST}${GRAY}5h${RST} ${color}${BOLD}${five_pct}%${RST}${DIM}]${RST}"
  fi
else
  five_part="${DIM}[5h --]${RST}"
fi

# 7d quota
if [ "$seven_pct" != "null" ] && [ -n "$seven_pct" ]; then
  color=$(quota_color "$seven_pct")
  reset_str=$(format_reset "$seven_reset")
  if [ -n "$reset_str" ]; then
    seven_part="${DIM}[${RST}${GRAY}7d${RST} ${color}${BOLD}${seven_pct}%${RST} ${DIM}↻${reset_str}${RST}${DIM}]${RST}"
  else
    seven_part="${DIM}[${RST}${GRAY}7d${RST} ${color}${BOLD}${seven_pct}%${RST}${DIM}]${RST}"
  fi
else
  seven_part="${DIM}[7d --]${RST}"
fi

# Cost
cost_part=""
if [ "$(echo "$cost_usd > 0" | bc 2>/dev/null)" = "1" ] 2>/dev/null; then
  cost_fmt=$(printf "%.3f" "$cost_usd")
  cost_part=" ${DIM}[${RST}${YELLOW}\$${cost_fmt}${RST}${DIM}]${RST}"
fi

# ── Language detection (ordered by specificity) ──
lang_icon=""
if [ -n "$cwd" ]; then
  if [ -f "$cwd/pom.xml" ] || [ -f "$cwd/build.gradle" ] || [ -f "$cwd/build.gradle.kts" ]; then
    lang_icon="☕ Java"
  elif [ -f "$cwd/Cargo.toml" ]; then
    lang_icon="🦀 Rust"
  elif [ -f "$cwd/go.mod" ]; then
    lang_icon="🔵 Go"
  elif [ -f "$cwd/pyproject.toml" ] || [ -f "$cwd/requirements.txt" ] || [ -f "$cwd/setup.py" ]; then
    lang_icon="🐍 Python"
  elif [ -f "$cwd/package.json" ]; then
    if grep -q '"typescript"' "$cwd/package.json" 2>/dev/null || [ -f "$cwd/tsconfig.json" ]; then
      lang_icon="🔷 TypeScript"
    else
      lang_icon="🟨 Node.js"
    fi
  elif [ -f "$cwd/composer.json" ]; then
    lang_icon="🐘 PHP"
  elif [ -f "$cwd/Gemfile" ]; then
    lang_icon="💎 Ruby"
  elif [ -f "$cwd/CMakeLists.txt" ] || ls "$cwd"/*.cpp "$cwd"/*.cc "$cwd"/*.h >/dev/null 2>&1; then
    lang_icon="⚙️  C/C++"
  elif [ -f "$cwd/Makefile" ]; then
    lang_icon="🔧 Make"
  elif ls "$cwd"/*.sh >/dev/null 2>&1; then
    lang_icon="🐚 Shell"
  else
    lang_icon="📄 Text"
  fi
fi
lang_part="${DIM}[${RST}${lang_icon}${DIM}]${RST}"

# ── Git info ──
branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null \
         || git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
git_part="${DIM}[${RST}${GRAY}no git${RST}${DIM}]${RST}"

if [ -n "$branch" ]; then
  porcelain=$(git -C "$cwd" status --porcelain 2>/dev/null)
  ahead_behind=$(git -C "$cwd" rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)
  ahead=$(echo "$ahead_behind" | awk '{print $1}')
  behind=$(echo "$ahead_behind" | awk '{print $2}')

  branch_disp="${MAGENTA}${BOLD}⎇ ${branch}${RST}"

  # remote ahead/behind
  remote_seg=""
  [ -n "$ahead"  ] && [ "$ahead"  -gt 0 ] && remote_seg="${remote_seg} ${CYAN}↑${ahead}领先${RST}"
  [ -n "$behind" ] && [ "$behind" -gt 0 ] && remote_seg="${remote_seg} ${RED}↓${behind}落后${RST}"

  if [ -n "$porcelain" ]; then
    # 原版计数逻辑完整保留
    idx_added=$(echo    "$porcelain" | grep -c '^A')
    idx_modified=$(echo "$porcelain" | grep -c '^[MRC]')
    idx_deleted=$(echo  "$porcelain" | grep -c '^D')
    idx_total=$((idx_added + idx_modified + idx_deleted))

    wt_modified=$(echo "$porcelain" | grep -c '^.[M]')
    wt_deleted=$(echo  "$porcelain" | grep -c '^.[D]')
    wt_total=$((wt_modified + wt_deleted))

    untracked=$(echo "$porcelain" | grep -c '^\?\?')
    conflicts=$(echo "$porcelain" | grep -c '^UU\|^AA\|^DD')

    seg_staged=""
    seg_worktree=""
    seg_untracked=""
    seg_conflict=""

    # 冲突（最高优先级，红色警示）
    [ "$conflicts" -gt 0 ] && \
      seg_conflict="${RED}✖ ${conflicts}冲突${RST}"

    # 已暂存（绿色实心圆）
    if [ "$idx_total" -gt 0 ]; then
      detail=""
      [ "$idx_added"    -gt 0 ] && detail="${detail}${idx_added}新增 "
      [ "$idx_modified" -gt 0 ] && detail="${detail}${idx_modified}修改 "
      [ "$idx_deleted"  -gt 0 ] && detail="${detail}${idx_deleted}删除 "
      seg_staged="${GREEN}● ${DIM}${detail% }${RST}"
    fi

    # 未暂存（黄色空心圆）
    if [ "$wt_total" -gt 0 ]; then
      detail=""
      [ "$wt_modified" -gt 0 ] && detail="${detail}${wt_modified}已改 "
      [ "$wt_deleted"  -gt 0 ] && detail="${detail}${wt_deleted}已删 "
      seg_worktree="${YELLOW}○ ${DIM}${detail% }${RST}"
    fi

    # 未跟踪（蓝色问号）
    [ "$untracked" -gt 0 ] && \
      seg_untracked="${BLUE}? ${untracked}新文件${RST}"

    # 拼接状态段，用细分隔线隔开非空项
    status_seg=""
    for seg in "$seg_conflict" "$seg_staged" "$seg_worktree" "$seg_untracked"; do
      [ -n "$seg" ] && status_seg="${status_seg:+${status_seg} ${DIM}·${RST} }${seg}"
    done

    git_part="${DIM}[${RST}${branch_disp}${remote_seg} ${DIM}│${RST} ${status_seg}${DIM}]${RST}"
  else
    # 工作区干净
    if [ -n "$remote_seg" ]; then
      git_part="${DIM}[${RST}${branch_disp}${remote_seg} ${GREEN}✓${RST}${DIM}]${RST}"
    else
      git_part="${DIM}[${RST}${branch_disp} ${GREEN}✓ 干净${RST}${DIM}]${RST}"
    fi
  fi
fi

# ── Current time ──
cur_time=$(date +"%H:%M" 2>/dev/null)
time_part="${DIM}[${RST}${GRAY}🕐 ${cur_time}${RST}${DIM}]${RST}"

# ── Assemble three lines ──
# Line 1: model  user@dir  cost
line1="╭─ ${model_part} ${userdir_part}${cost_part}"

# Line 2: ctx bar  5h quota  7d quota
line2="├─ ${ctx_part} ${five_part} ${seven_part}"

# Line 3: language  git  time
line3="╰─ ${lang_part} ${git_part} ${time_part}"

printf "%b\n%b\n%b\n" "$line1" "$line2" "$line3"
