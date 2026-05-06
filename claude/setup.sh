#!/bin/bash
# Will's Claude Code Statusline — One-line Installer
# Usage: curl -sL https://raw.githubusercontent.com/USER/REPO/main/scripts/setup.sh | bash

set -e

CLAUDE_DIR="$HOME/.claude"
DEST="$CLAUDE_DIR/statusline.sh"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

# ── Pre-flight checks ──────────────────────────────────────────────
if ! command -v curl &>/dev/null; then
  echo "❌ curl is required but not installed." >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  if command -v brew &>/dev/null; then
    echo "📦 Installing jq via Homebrew..."
    brew install jq
  elif command -v apt-get &>/dev/null; then
    echo "📦 Installing jq via apt..."
    sudo apt-get install -y jq
  elif command -v dnf &>/dev/null; then
    echo "📦 Installing jq via dnf..."
    sudo dnf install -y jq
  else
    echo "❌ jq is required but not installed." >&2
    echo "   macOS:  brew install jq" >&2
    echo "   Linux:  sudo apt-get install jq  or  sudo dnf install jq" >&2
    exit 1
  fi
fi

mkdir -p "$CLAUDE_DIR"

# ── Validate existing settings.json ────────────────────────────────
if [ -f "$SETTINGS_FILE" ]; then
  if ! python3 -c "import json; json.load(open('$SETTINGS_FILE'))" 2>/dev/null \
     && ! jq empty "$SETTINGS_FILE" 2>/dev/null; then
    echo "❌ $SETTINGS_FILE is not valid JSON. Refusing to modify it." >&2
    exit 1
  fi
fi

# ── Check for existing statusLine ──────────────────────────────────
if [ -f "$SETTINGS_FILE" ]; then
  existing=$(jq -r '.statusLine.command // empty' "$SETTINGS_FILE" 2>/dev/null)
  if [ -n "$existing" ] && [ "$existing" != "bash ~/.claude/statusline.sh" ]; then
    echo "⚠️  Another statusline is already configured:"
    echo "   $existing"
    # curl|bash runs in a non-interactive pipe, so we need /dev/tty
    printf "   Replace it with Will's statusline? [Y/n] "
    read -r ans < /dev/tty 2>/dev/null || ans="Y"
    if [ "$ans" = "n" ] || [ "$ans" = "N" ]; then
      echo "Skipped. Existing statusline kept."
      exit 0
    fi
  fi
fi

# ── Download statusline.sh ─────────────────────────────────────────
echo "⬇️  Downloading statusline script..."
curl -fsSL "https://raw.githubusercontent.com/will-yinchengxin/claude-statusline/refs/heads/main/claude/statusline.sh" -o "$DEST"
chmod +x "$DEST"

# ── Wire up settings.json ──────────────────────────────────────────
echo "⚙️  Configuring settings.json..."

if command -v python3 &>/dev/null; then
  # Prefer python3 for safe JSON merge (preserves all existing keys)
  SETTINGS_FILE="$SETTINGS_FILE" python3 - <<'PYEOF'
import json, os, tempfile

path = os.environ["SETTINGS_FILE"]
d = {}
if os.path.exists(path):
    with open(path) as f:
        d = json.load(f)

d["statusLine"] = {"type": "command", "command": "bash ~/.claude/statusline.sh"}

directory = os.path.dirname(path)
fd, tmp_path = tempfile.mkstemp(prefix="settings.", suffix=".json.tmp", dir=directory)
with os.fdopen(fd, "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
os.replace(tmp_path, path)
PYEOF
else
  # Fallback: jq only
  if [ -f "$SETTINGS_FILE" ]; then
    tmp=$(mktemp)
    jq '.statusLine = {"type":"command","command":"bash ~/.claude/statusline.sh"}' \
      "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"
  else
    echo '{"statusLine":{"type":"command","command":"bash ~/.claude/statusline.sh"}}' \
      | jq '.' > "$SETTINGS_FILE"
  fi
fi

# ── Done ───────────────────────────────────────────────────────────
echo ""
echo "✅ Will's statusline installed!"
echo "   Restart Claude Code to activate."
echo ""
echo "   To uninstall:"
echo "     rm -f ~/.claude/statusline.sh"
echo "     # Then remove the statusLine key from ~/.claude/settings.json"
