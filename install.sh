#!/bin/bash
# Cài dotfiles: skill automatic-workflow cho Claude Code (+ lệnh autowf) và các công cụ nó cần.
# Chạy lại nhiều lần vẫn an toàn. Dùng được trên macOS và Linux (GitHub Codespaces).
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"
BIN_DIR="$HOME/.local/bin"

# Copy skill vào ~/.claude/skills để dùng được ở mọi project (bỏ các file backup *.bak*)
mkdir -p "$SKILLS_DIR"
for src in "$DOTFILES_DIR"/claude/skills/*/; do
  name=$(basename "$src")
  mkdir -p "$SKILLS_DIR/$name"
  for f in "$src"*; do
    case "$f" in *.bak*) continue ;; esac
    if [ -f "$f" ]; then cp "$f" "$SKILLS_DIR/$name/"; fi
  done
done
chmod +x "$SKILLS_DIR/automatic-workflow/auto.sh"

# Lệnh autowf trỏ tới auto.sh của skill (SKILL.md gọi `autowf`)
mkdir -p "$BIN_DIR"
# Giữ nguyên wrapper tự viết (vd. trên Windows/Git Bash, nơi ln -s chỉ copy file): chỉ thay link hoặc bản copy của auto.sh
if [ -e "$BIN_DIR/autowf" ] && [ ! -L "$BIN_DIR/autowf" ] && ! head -n 3 "$BIN_DIR/autowf" | grep -q '^# autowf — Claude lên plan'; then
  echo "ℹ️  Giữ nguyên $BIN_DIR/autowf (wrapper tự viết, không phải link tới auto.sh)"
else
  ln -sf "$SKILLS_DIR/automatic-workflow/auto.sh" "$BIN_DIR/autowf"
fi
rc="$HOME/.bashrc"; [ "$(basename "${SHELL:-}")" = zsh ] && rc="$HOME/.zshrc"
add_to_rc() { grep -qxF "$1" "$rc" 2>/dev/null || echo "$1" >> "$rc"; }
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) add_to_rc 'export PATH="$HOME/.local/bin:$PATH"' ;;
esac

# Cài Claude Code và agent viết code nếu chưa có
if ! command -v claude >/dev/null; then
  if command -v npm >/dev/null; then npm i -g @anthropic-ai/claude-code
  else curl -fsSL https://claude.ai/install.sh | bash; fi
fi
if ! command -v gemini >/dev/null; then
  if command -v npm >/dev/null; then npm i -g @google/gemini-cli
  else echo "⚠️  Không có npm — bỏ qua cài gemini-cli"; fi
fi
# Không có agy (Antigravity CLI, CODER mặc định của autowf) thì dùng gemini làm agent viết code
if ! command -v agy >/dev/null; then
  add_to_rc 'export CODER="${CODER:-gemini}"'
  echo "ℹ️  Chưa có agy — đặt CODER=gemini trong $rc"
fi

# Cài tmux để workflow chạy nền
if ! command -v tmux >/dev/null; then
  if command -v apt-get >/dev/null; then
    SUDO=""; [ "$(id -u)" -eq 0 ] || SUDO="sudo"
    $SUDO apt-get update && $SUDO apt-get install -y tmux
  elif command -v brew >/dev/null; then brew install tmux
  else echo "⚠️  Không cài được tmux tự động — hãy cài tay"; fi
fi

echo "✅ Đã cài skill automatic-workflow vào $SKILLS_DIR và lệnh $BIN_DIR/autowf"
