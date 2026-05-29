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

echo "Upgrading klawde defaults in $TARGET_DIR"
echo ""

# Overwrite CLAUDE.md
if [ ! -f "$SCRIPT_DIR/CLAUDE.md" ]; then
  echo "Error: $SCRIPT_DIR/CLAUDE.md not found in source."
  exit 1
fi
if [ -f "$TARGET_DIR/CLAUDE.md" ]; then
  claude_backup="$TARGET_DIR/CLAUDE.md.bak.$(date +%Y%m%d-%H%M%S)"
  cp "$TARGET_DIR/CLAUDE.md" "$claude_backup"
  echo "Backed up existing CLAUDE.md to $(basename "$claude_backup")."
fi
cp "$SCRIPT_DIR/CLAUDE.md" "$TARGET_DIR/CLAUDE.md"
echo "Overwrote CLAUDE.md."

# Overwrite .claude/commands/init.md and close.md
mkdir -p "$TARGET_DIR/.claude/commands"
for cmd in init.md close.md compresschanges.md; do
  src="$SCRIPT_DIR/$cmd"
  dst="$TARGET_DIR/.claude/commands/$cmd"
  if [ ! -f "$src" ]; then
    echo "Warning: $src not found in source. Skipped."
    continue
  fi
  if [ -f "$dst" ]; then
    cmd_backup="$dst.bak.$(date +%Y%m%d-%H%M%S)"
    cp "$dst" "$cmd_backup"
    echo "Backed up existing .claude/commands/$cmd to $(basename "$cmd_backup")."
  fi
  cp "$src" "$dst"
  echo "Overwrote .claude/commands/$cmd."
done

# Convert existing CHANGES.md to new typed format
changes="$TARGET_DIR/CHANGES.md"
if [ -f "$changes" ]; then
  echo ""

  # Detect whether any work is needed before backing up or rewriting
  needs_conversion=0
  if grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}:' "$changes"; then
    needs_conversion=1
  fi
  needs_hint=0
  if ! grep -qF 'Format: `YYYY-MM-DD [type]' "$changes"; then
    needs_hint=1
  fi

  if [ "$needs_conversion" -eq 0 ] && [ "$needs_hint" -eq 0 ]; then
    echo "CHANGES.md already in current format. No conversion needed."
  else
    echo "Found existing CHANGES.md, converting to new format."

    # Back up first so the original is recoverable
    backup="$changes.bak.$(date +%Y%m%d-%H%M%S)"
    cp "$changes" "$backup"
    echo "Backup saved to $(basename "$backup")."

    if [ "$needs_conversion" -eq 1 ]; then
      # Convert old-format entries (YYYY-MM-DD: description) to [note] type.
      # Leaves new-format entries (YYYY-MM-DD [type] description) untouched.
      tmp="$(mktemp)"
      converted=0
      while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}):[[:space:]]*(.*)$ ]]; then
          printf '%s [note] %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" >> "$tmp"
          converted=$((converted + 1))
        else
          printf '%s\n' "$line" >> "$tmp"
        fi
      done < "$changes"
      mv "$tmp" "$changes"
      echo "Converted $converted old-format entries to [note] type."
    fi

    if [ "$needs_hint" -eq 1 ]; then
      tmp2="$(mktemp)"
      awk 'NR==1 {print; print ""; print "Format: `YYYY-MM-DD [type] description` (max 200 chars). Types: decision, plan, doc, scope, code, note."; print ""; next} NR==2 && /^[[:space:]]*$/ {next} {print}' "$changes" > "$tmp2"
      mv "$tmp2" "$changes"
      echo "Added format hint to CHANGES.md header."
    fi
  fi
else
  echo ""
  echo "No existing CHANGES.md found. Skipped conversion."
fi

echo ""
echo "Done. Upgrade complete at $TARGET_DIR"
