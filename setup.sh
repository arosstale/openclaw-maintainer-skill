#!/bin/bash
# openclaw-maintainer setup script
# creates symlinks for claude code and codex cli

set -e

SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
COMMANDS_DIR="$SKILL_DIR/commands"

echo "Setting up openclaw-maintainer skill..."

# command files to link
CMDS=(reviewpr.md preparepr.md mergepr.md)

# claude code symlinks
mkdir -p ~/.claude/commands
for cmd in "${CMDS[@]}"; do
  target="$COMMANDS_DIR/$cmd"
  link="$HOME/.claude/commands/$cmd"
  if [ -L "$link" ]; then
    rm "$link"
  elif [ -f "$link" ]; then
    echo "Backing up existing $link to $link.bak"
    mv "$link" "$link.bak"
  fi
  ln -s "$target" "$link"
  echo "  ~/.claude/commands/$cmd -> $target"
done

# codex cli symlinks
mkdir -p ~/.codex/prompts
for cmd in "${CMDS[@]}"; do
  target="$COMMANDS_DIR/$cmd"
  link="$HOME/.codex/prompts/$cmd"
  if [ -L "$link" ]; then
    rm "$link"
  elif [ -f "$link" ]; then
    echo "Backing up existing $link to $link.bak"
    mv "$link" "$link.bak"
  fi
  ln -s "$target" "$link"
  echo "  ~/.codex/prompts/$cmd -> $target"
done

echo "Done! Commands available:"
echo "  /reviewpr   - review a PR"
echo "  /preparepr  - rebase, fix, run gates, push updates (no merge)"
echo "  /mergepr    - merge a prepared PR"
