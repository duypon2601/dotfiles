#!/bin/bash
set -e

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

# Copy skill vào ~/.claude/skills để dùng được ở mọi project
mkdir -p ~/.claude/skills
cp -r "$DOTFILES_DIR/claude/skills/"* ~/.claude/skills/
chmod +x ~/.claude/skills/automatic-workflow/auto.sh

# Cài Claude Code và agent viết code nếu chưa có
command -v claude >/dev/null || npm i -g @anthropic-ai/claude-code
command -v gemini >/dev/null || npm i -g @google/gemini-cli

# Cài tmux để workflow chạy nền
command -v tmux >/dev/null || (sudo apt-get update && sudo apt-get install -y tmux)





B
