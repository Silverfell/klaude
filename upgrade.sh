#!/usr/bin/env bash
set -euo pipefail

# Resolve the directory where this script lives (the source of truth)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Target is the current working directory (where the user invokes from)
TARGET_DIR="$(pwd)"

usage() {
  echo "Usage: upgrade.sh [--claude|--codex|--both] [--backup|--no-backup]"
  echo "  --claude     Upgrade a Claude Code install (CLAUDE.md + .claude/commands/)"
  echo "  --codex      Upgrade a Codex install (AGENTS.md + .agents/skills/)"
  echo "  --both       Upgrade both layouts"
  echo "  --backup     Create .bak backups before overwriting (skip the prompt)"
  echo "  --no-backup  Do not create backups (skip the prompt)"
  echo "  With no target flag, the existing install is detected and you are prompted."
}

# Parse flags. Target flags are mutually exclusive; backup flags are last-wins.
TARGET=""
BACKUP=""
set_target() {
  if [ -n "$TARGET" ]; then
    echo "Error: specify only one of --claude, --codex, or --both." >&2
    exit 1
  fi
  TARGET="$1"
}
for arg in "$@"; do
  case "$arg" in
    --claude)    set_target claude ;;
    --codex)     set_target codex ;;
    --both)      set_target both ;;
    --backup)    BACKUP="yes" ;;
    --no-backup) BACKUP="no" ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "Error: unknown argument '$arg'." >&2; usage >&2; exit 1 ;;
  esac
done

if [ "$SCRIPT_DIR" = "$TARGET_DIR" ]; then
  echo "Error: you are already in the source directory. cd to your project first."
  exit 1
fi

# Detect an existing install to offer as the default selection. Both contract
# files present means a combined install.
has_claude=0
has_codex=0
if [ -f "$TARGET_DIR/CLAUDE.md" ]; then has_claude=1; fi
if [ -f "$TARGET_DIR/AGENTS.md" ]; then has_codex=1; fi
DETECTED=""
if [ "$has_claude" -eq 1 ] && [ "$has_codex" -eq 1 ]; then
  DETECTED="both"
elif [ "$has_claude" -eq 1 ]; then
  DETECTED="claude"
elif [ "$has_codex" -eq 1 ]; then
  DETECTED="codex"
fi

# Prompt for the target if no flag was given, defaulting to what was detected.
if [ -z "$TARGET" ]; then
  echo "Upgrade for:"
  echo "[1] claude"
  echo "[2] codex"
  echo "[3] both"
  if [ -n "$DETECTED" ]; then
    echo "[Enter for detected: $DETECTED]"
  fi
  read -r sel
  case "$sel" in
    1|claude) TARGET="claude" ;;
    2|codex)  TARGET="codex" ;;
    3|both)   TARGET="both" ;;
    "")
      if [ -n "$DETECTED" ]; then
        TARGET="$DETECTED"
      else
        echo "Error: no selection given and no existing install detected." >&2; exit 1
      fi ;;
    *) echo "Error: unrecognized selection '$sel'. Expected 1, 2, or 3." >&2; exit 1 ;;
  esac
fi

# Ask whether to create backups, unless a flag already decided.
if [ -z "$BACKUP" ]; then
  echo "Create .bak backups before overwriting? [Y/n]"
  read -r ans
  case "$ans" in
    n|N|no|No) BACKUP="no" ;;
    *) BACKUP="yes" ;;
  esac
fi

echo ""
echo "Upgrading klawde defaults in $TARGET_DIR (target: $TARGET, backups: $BACKUP)"
echo ""

# Back up a file only when backups are enabled.
maybe_backup() {
  local path="$1"
  if [ "$BACKUP" = "yes" ]; then
    local backup="$path.bak.$(date +%Y%m%d-%H%M%S)"
    cp "$path" "$backup"
    echo "Backed up $(basename "$path") to $(basename "$backup")."
  fi
}

# Rewrite a template file for the Codex layout, writing to stdout (see setup.sh).
rewrite_codex() {
  sed -e '1s/^# CLAUDE\.md$/# AGENTS.md/' \
      -e 's/^## Slash Commands$/## Skills/' \
      -e 's#`\.claude/commands/\([A-Za-z]*\)\.md`#`.agents/skills/\1/SKILL.md`#g' \
      -e 's#`/klawde`#`$klawde`#g' \
      -e 's#`/klaude`#`$klaude`#g' \
      -e 's#`/close`#`$close`#g' \
      -e 's#`/compresschanges`#`$compresschanges`#g' \
      "$1"
}

# Build a Codex skill file: SKILL.md with front matter plus rewritten body.
build_skill_file() {
  local src="$1" name="$2" desc="$3" dst="$4"
  {
    printf -- '---\n'
    printf 'name: %s\n' "$name"
    printf 'description: "%s"\n' "$desc"
    printf -- '---\n\n'
    rewrite_codex "$src"
  } > "$dst"
}

# A missing source contract is fatal.
if [ ! -f "$SCRIPT_DIR/template/CLAUDE.md" ]; then
  echo "Error: $SCRIPT_DIR/template/CLAUDE.md not found in source."
  exit 1
fi

upgrade_claude() {
  local dst="$TARGET_DIR/CLAUDE.md"
  if [ -f "$dst" ]; then maybe_backup "$dst"; fi
  mkdir -p "$(dirname "$dst")"
  cp "$SCRIPT_DIR/template/CLAUDE.md" "$dst"
  echo "Overwrote $dst."
  for cmd in klawde.md klaude.md close.md compresschanges.md; do
    dst="$TARGET_DIR/.claude/commands/$cmd"
    if [ -f "$dst" ]; then maybe_backup "$dst"; fi
    mkdir -p "$(dirname "$dst")"
    cp "$SCRIPT_DIR/template/$cmd" "$dst"
    echo "Overwrote $dst."
  done
  # Retire the legacy /init command (entry protocol is now /klawde).
  local legacy_init="$TARGET_DIR/.claude/commands/init.md"
  if [ -f "$legacy_init" ]; then
    maybe_backup "$legacy_init"
    rm "$legacy_init"
    echo "Removed legacy .claude/commands/init.md."
  fi
}

# name | template file | skill description
upgrade_skill() {
  local name="$1" src="$2" desc="$3"
  local dst="$TARGET_DIR/.agents/skills/$name/SKILL.md"
  if [ -f "$dst" ]; then maybe_backup "$dst"; fi
  mkdir -p "$(dirname "$dst")"
  build_skill_file "$SCRIPT_DIR/template/$src" "$name" "$desc" "$dst"
  echo "Overwrote $dst."
}

upgrade_codex() {
  local dst="$TARGET_DIR/AGENTS.md"
  if [ -f "$dst" ]; then maybe_backup "$dst"; fi
  mkdir -p "$(dirname "$dst")"
  rewrite_codex "$SCRIPT_DIR/template/CLAUDE.md" > "$dst"
  echo "Overwrote $dst."
  upgrade_skill klawde klawde.md \
    "Run only when explicitly invoked. Klawde entry protocol (full mode): read or create BRIEFING.md and CHANGES.md and confirm readiness at session start, with the Code craft module active."
  upgrade_skill klaude klaude.md \
    "Run only when explicitly invoked. Klawde entry protocol (lean mode): same as klawde, but with the Code craft module disabled for the session."
  upgrade_skill close close.md \
    "Run only when explicitly invoked. Klawde close protocol: record decisions and scope changes to CHANGES.md and update BRIEFING.md before ending work."
  upgrade_skill compresschanges compresschanges.md \
    "Run only when explicitly invoked. Klawde journal compaction: summarize CHANGES.md entries older than 30 days while preserving decisions and scope changes."
  # Retire deprecated global prompts from earlier versions (honors CODEX_HOME).
  local prompts_dir="${CODEX_HOME:-$HOME/.codex}/prompts"
  for old in klawde close compresschanges; do
    local legacy_prompt="$prompts_dir/$old.md"
    if [ -f "$legacy_prompt" ]; then
      maybe_backup "$legacy_prompt"
      rm "$legacy_prompt"
      echo "Removed deprecated prompt $legacy_prompt."
    fi
  done
}

case "$TARGET" in
  claude) upgrade_claude ;;
  codex)  upgrade_codex ;;
  both)   upgrade_claude; upgrade_codex ;;
esac

# Convert existing CHANGES.md to new typed format (target-agnostic; runs once).
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

    # Back up first (if enabled) so the original is recoverable
    maybe_backup "$changes"

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
echo "Done. Upgrade complete at $TARGET_DIR (target: $TARGET)"
