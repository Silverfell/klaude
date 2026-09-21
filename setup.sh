#!/usr/bin/env bash
set -euo pipefail

# Resolve the directory this script lives in, through a symlink if invoked as one.
self="${BASH_SOURCE[0]}"
while [ -L "$self" ]; do
  link="$(readlink "$self")"
  case "$link" in /*) self="$link" ;; *) self="$(dirname "$self")/$link" ;; esac
done
SCRIPT_DIR="$(cd "$(dirname "$self")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

TARGET_DIR="$(pwd)"

usage() {
  echo "Usage: setup.sh [--claude|--codex|--both]"
  echo "  --claude   Install for Claude Code (CLAUDE.md + .claude/commands/)"
  echo "  --codex    Install for Codex (AGENTS.md + .agents/skills/)"
  echo "  --both     Install both layouts"
  echo "  With no flag, you are prompted to choose."
}

TARGET=""
set_target() {
  if [ -n "$TARGET" ]; then
    echo "Error: specify only one of --claude, --codex, or --both." >&2
    exit 1
  fi
  TARGET="$1"
}
for arg in "$@"; do
  case "$arg" in
    --claude) set_target claude ;;
    --codex)  set_target codex ;;
    --both)   set_target both ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Error: unknown argument '$arg'." >&2; usage >&2; exit 1 ;;
  esac
done

if [ "$SCRIPT_DIR" = "$TARGET_DIR" ]; then
  echo "Error: you are already in the source directory. cd to your project first."
  exit 1
fi
require_sqlite

if [ -z "$TARGET" ]; then
  echo "Install for:"
  echo "[1] claude"
  echo "[2] codex"
  echo "[3] both"
  prompt_read sel
  case "$sel" in
    1|claude) TARGET="claude" ;;
    2|codex)  TARGET="codex" ;;
    3|both)   TARGET="both" ;;
    *) echo "Error: unrecognized selection '$sel'. Expected 1, 2, or 3." >&2; exit 1 ;;
  esac
fi

# Prompt before clobbering an existing destination. 0 = write, 1 = skip.
should_write() {
  local dst="$1"
  if [ -f "$dst" ]; then
    echo "$dst already exists. Overwrite? [y/N]"
    prompt_read confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      echo "Skipped $dst."
      return 1
    fi
  fi
  return 0
}

install_claude() {
  local dst="$TARGET_DIR/CLAUDE.md"
  if should_write "$dst"; then
    cp "$SCRIPT_DIR/template/CLAUDE.md" "$dst"
    echo "Copied $dst."
  fi
  for cmd in klawde.md close.md upgrade_klawde.md; do
    dst="$TARGET_DIR/.claude/commands/$cmd"
    if should_write "$dst"; then
      mkdir -p "$(dirname "$dst")"
      cp "$SCRIPT_DIR/template/$cmd" "$dst"
      echo "Copied $dst."
    fi
  done
  for artifact in changes-schema.sql; do
    dst="$TARGET_DIR/.claude/$artifact"
    if should_write "$dst"; then
      mkdir -p "$(dirname "$dst")"
      cp "$SCRIPT_DIR/template/$artifact" "$dst"
      echo "Copied $dst."
    fi
  done
}

install_skill() { # <name> <template file> <description>
  local name="$1" src="$2" desc="$3"
  local dst="$TARGET_DIR/.agents/skills/$name/SKILL.md"
  if should_write "$dst"; then
    mkdir -p "$(dirname "$dst")"
    build_skill_file "$SCRIPT_DIR/template/$src" "$name" "$desc" "$dst"
    echo "Wrote $dst."
  fi
}

install_codex() {
  local dst="$TARGET_DIR/AGENTS.md"
  if should_write "$dst"; then
    rewrite_codex "$SCRIPT_DIR/template/CLAUDE.md" > "$dst"
    echo "Wrote $dst."
  fi
  install_skill klawde klawde.md "$KLAWDE_SKILL_DESC"
  install_skill close close.md "$CLOSE_SKILL_DESC"
  install_skill upgrade_klawde upgrade_klawde.md "$UPGRADE_KLAWDE_SKILL_DESC"
  for artifact in changes-schema.sql; do
    dst="$TARGET_DIR/.agents/$artifact"
    if should_write "$dst"; then
      mkdir -p "$(dirname "$dst")"
      cp "$SCRIPT_DIR/template/$artifact" "$dst"
      echo "Copied $dst."
    fi
  done
}

# guidelines.md is the same file in both layouts, so it is written once
# regardless of target: writing it per layout would prompt --both users to
# overwrite the file the first layout just installed.
install_guidelines() {
  local dst="$TARGET_DIR/guidelines.md"
  if should_write "$dst"; then
    cp "$SCRIPT_DIR/template/guidelines.md" "$dst"
    echo "Copied $dst."
  fi
}

# Refuse symlinked, unwritable and blocked destinations before any write.
if [ "$TARGET" != "codex" ]; then
  check_no_symlink "$TARGET_DIR/CLAUDE.md"
  for path in "$TARGET_DIR/CLAUDE.md" "$TARGET_DIR/.claude/commands/klawde.md" \
              "$TARGET_DIR/.claude/commands/close.md" \
              "$TARGET_DIR/.claude/commands/upgrade_klawde.md" \
              "$TARGET_DIR/.claude/changes-schema.sql"; do
    check_dest "$path"
  done
fi
if [ "$TARGET" != "claude" ]; then
  check_no_symlink "$TARGET_DIR/AGENTS.md"
  for path in "$TARGET_DIR/AGENTS.md" "$TARGET_DIR/.agents/skills/klawde/SKILL.md" \
              "$TARGET_DIR/.agents/skills/close/SKILL.md" \
              "$TARGET_DIR/.agents/skills/upgrade_klawde/SKILL.md" \
              "$TARGET_DIR/.agents/changes-schema.sql"; do
    check_dest "$path"
  done
fi
check_dest "$TARGET_DIR/guidelines.md"
gate_preflight

# From the first write onward, an abort must say the install may be partial.
on_fail() {
  echo "" >&2
  echo "Error: the install did NOT complete; it may be partial. Fix the problem above and re-run setup.sh." >&2
}
trap 'if [ $? -ne 0 ]; then on_fail; fi' EXIT

case "$TARGET" in
  claude) install_claude ;;
  codex)  install_codex ;;
  both)   install_claude; install_codex ;;
esac
install_guidelines

trap - EXIT
echo ""
echo "Done. Project initialized at $TARGET_DIR (target: $TARGET, source version: $(source_version))"
echo "Run /klawde in Claude Code, or \$klawde in Codex, to start a session; it creates BRIEFING.md and changes.db on its first run."
echo "guidelines.md at the project root is yours now: edit it, or delete it to turn those code rules off. Upgrades never write it."
if [ "$TARGET" != "codex" ]; then
  echo "If a Claude Code session is already open in this project, restart it: slash commands load at session start."
fi
