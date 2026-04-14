#!/usr/bin/env bash
set -euo pipefail

# Resolve the directory where this script lives (the source of truth)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Target is the current working directory (where the user invokes from)
TARGET_DIR="$(pwd)"

if [ "$SCRIPT_DIR" = "$TARGET_DIR" ]; then
  echo "Error: you are already in the source directory. cd to your project first."
  exit 1
fi

# Copy CLAUDE.md
if [ -f "$TARGET_DIR/CLAUDE.md" ]; then
  echo "CLAUDE.md already exists in $TARGET_DIR. Overwrite? [y/N]"
  read -r confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Skipped CLAUDE.md."
  else
    cp "$SCRIPT_DIR/CLAUDE.md" "$TARGET_DIR/CLAUDE.md"
    echo "Overwrote CLAUDE.md."
  fi
else
  cp "$SCRIPT_DIR/CLAUDE.md" "$TARGET_DIR/CLAUDE.md"
  echo "Copied CLAUDE.md."
fi

# Copy .claude/commands/
mkdir -p "$TARGET_DIR/.claude/commands"

for cmd in init.md close.md compresschanges.md; do
  src="$SCRIPT_DIR/$cmd"
  dst="$TARGET_DIR/.claude/commands/$cmd"

  if [ ! -f "$src" ]; then
    echo "Warning: $src not found in source. Skipped."
    continue
  fi

  if [ -f "$dst" ]; then
    echo ".claude/commands/$cmd already exists. Overwrite? [y/N]"
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      echo "Skipped .claude/commands/$cmd."
      continue
    fi
  fi

  cp "$src" "$dst"
  echo "Copied .claude/commands/$cmd."
done

echo ""
echo "Done. Project initialized at $TARGET_DIR"
echo "Run /init in Claude Code to start a session."
