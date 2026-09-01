#!/usr/bin/env bash
set -euo pipefail

# Resolve the directory where this script lives (the source of truth)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Target is the current working directory (where the user invokes from)
TARGET_DIR="$(pwd)"

usage() {
  echo "Usage: setup.sh [--claude|--codex|--both]"
  echo "  --claude   Install for Claude Code (CLAUDE.md + .claude/commands/)"
  echo "  --codex    Install for Codex (AGENTS.md + .agents/skills/)"
  echo "  --both     Install both layouts"
  echo "  With no flag, you are prompted to choose."
}

# Parse the target flag. The target flags are mutually exclusive.
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

# The harness keeps its project log in a SQLite database (changes.db), driven
# entirely through the sqlite3 CLI. Without it, no session can start.
if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "Error: the sqlite3 CLI was not found on PATH." >&2
  echo "Klawde keeps its project log in changes.db and needs sqlite3 to read and write it." >&2
  echo "Install it (macOS: preinstalled, or 'brew install sqlite'; Debian/Ubuntu: 'apt install sqlite3'; Fedora: 'dnf install sqlite')." >&2
  exit 1
fi

# Read one line of user input into the named variable. A closed stdin
# (non-interactive run) must be a loud error, not a silent set -e exit
# at the prompt with a partial or missing install.
prompt_read() {
  if ! IFS= read -r "$1"; then
    echo "" >&2
    echo "Error: stdin closed at a prompt (non-interactive run?)." >&2
    echo "Pass a target flag to skip the prompt: --claude/--codex/--both." >&2
    exit 1
  fi
}

# Every shipped source must be present before anything is written; a stale or
# partial checkout would otherwise abort mid-copy and leave a partial install.
check_templates() {
  local f missing=0
  for f in CLAUDE.md klawde.md close.md changes-schema.sql; do
    if [ ! -f "$SCRIPT_DIR/template/$f" ]; then
      echo "Error: $SCRIPT_DIR/template/$f not found in source." >&2
      missing=1
    fi
  done
  if [ "$missing" -eq 1 ]; then
    echo "The source checkout looks stale or incomplete; run 'git pull' in $SCRIPT_DIR and retry." >&2
    exit 1
  fi
}
check_templates

# The two contracts must be distinct regular files: writing one through a
# symlink would clobber the other layout's contract with rewritten content.
check_no_symlink() {
  if [ -L "$1" ]; then
    echo "Error: $1 is a symlink (to '$(readlink "$1")'). Nothing was changed." >&2
    echo "Klawde's Claude and Codex contracts have different content and cannot share one file." >&2
    echo "Remove the symlink and re-run; the install writes a real file in its place." >&2
    exit 1
  fi
}

# Confirm one destination can be written (or created) without writing anything.
# A destination that exists as something other than a regular file, or whose
# nearest existing ancestor is not a directory, cannot be written either.
dest_writable() {
  local path="$1" dir
  dir="$(dirname "$path")"
  if [ -e "$path" ]; then
    [ -f "$path" ] && [ -w "$path" ]
    return
  fi
  while [ ! -e "$dir" ]; do dir="$(dirname "$dir")"; done
  [ -d "$dir" ] && [ -w "$dir" ]
}

# Preflight problems are collected, all reported, then fatal in one exit, so
# every offender surfaces before the first write instead of the run aborting
# mid-way with a partial install.
PREFLIGHT_BAD=0
bad_dest() {
  echo "Error: $1" >&2
  PREFLIGHT_BAD=1
}
# A destination file about to be overwritten or created.
check_dest() {
  if [ -L "$1" ]; then
    bad_dest "$1 is a symlink (to '$(readlink "$1")'); klawde writes real files, remove the symlink first."
  elif ! dest_writable "$1"; then
    bad_dest "cannot write $1 (not writable, or blocked by a non-directory parent)."
  fi
}
gate_preflight() {
  if [ "$PREFLIGHT_BAD" -eq 1 ]; then
    echo "Nothing was changed. Fix the problems above and re-run." >&2
    exit 1
  fi
}

# Prompt for the target if no flag was given.
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

# Rewrite a template file for the Codex layout, writing to stdout:
#   - retitle the contract (CLAUDE.md -> AGENTS.md) and its command section
#   - retarget command paths to skill paths
#   - retarget the shipped log schema to the Codex layout
#   - rewrite slash invocations to skill ($name) invocations
# Each rule is a no-op on files that lack the matched text.
rewrite_codex() {
  sed -e '1s/^# CLAUDE\.md$/# AGENTS.md/' \
      -e 's/^## Slash Commands$/## Skills/' \
      -e 's#`\.claude/commands/\([A-Za-z]*\)\.md`#`.agents/skills/\1/SKILL.md`#g' \
      -e 's#\.claude/changes-schema\.sql#.agents/changes-schema.sql#g' \
      -e 's#`/klawde`#`$klawde`#g' \
      -e 's#`/close`#`$close`#g' \
      -e 's|^# /klawde: |# $klawde: |' \
      -e 's|^# /close: |# $close: |' \
      "$1"
}

# Build a Codex skill file: SKILL.md with name/description front matter,
# followed by the rewritten protocol body.
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

# Overwrite guard: prompt before clobbering an existing destination.
# Returns 0 when the caller should write, 1 when it should skip.
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
    mkdir -p "$(dirname "$dst")"
    cp "$SCRIPT_DIR/template/CLAUDE.md" "$dst"
    echo "Copied $dst."
  fi
  for cmd in klawde.md close.md; do
    dst="$TARGET_DIR/.claude/commands/$cmd"
    if should_write "$dst"; then
      mkdir -p "$(dirname "$dst")"
      cp "$SCRIPT_DIR/template/$cmd" "$dst"
      echo "Copied $dst."
    fi
  done
  # The log schema /klawde uses to create changes.db on first run.
  dst="$TARGET_DIR/.claude/changes-schema.sql"
  if should_write "$dst"; then
    mkdir -p "$(dirname "$dst")"
    cp "$SCRIPT_DIR/template/changes-schema.sql" "$dst"
    echo "Copied $dst."
  fi
}

# name | template file | skill description
install_skill() {
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
    mkdir -p "$(dirname "$dst")"
    rewrite_codex "$SCRIPT_DIR/template/CLAUDE.md" > "$dst"
    echo "Wrote $dst."
  fi
  install_skill klawde klawde.md \
    "Run only when explicitly invoked. Klawde entry protocol: read BRIEFING.md in full and the last 5 changes.db log entries (creating either if missing), then confirm readiness at session start."
  install_skill close close.md \
    "Run only when explicitly invoked. Klawde close protocol: append decisions and scope changes to the changes.db log, triage open concerns, update BRIEFING.md, and verify log integrity before ending work."
  # The log schema $klawde uses to create changes.db on first run.
  dst="$TARGET_DIR/.agents/changes-schema.sql"
  if should_write "$dst"; then
    mkdir -p "$(dirname "$dst")"
    cp "$SCRIPT_DIR/template/changes-schema.sql" "$dst"
    echo "Copied $dst."
  fi
}

# Refuse symlinked, unwritable and blocked destinations before any write.
if [ "$TARGET" != "codex" ]; then
  check_no_symlink "$TARGET_DIR/CLAUDE.md"
  for path in "$TARGET_DIR/CLAUDE.md" "$TARGET_DIR/.claude/commands/klawde.md" \
              "$TARGET_DIR/.claude/commands/close.md" \
              "$TARGET_DIR/.claude/changes-schema.sql"; do
    check_dest "$path"
  done
fi
if [ "$TARGET" != "claude" ]; then
  check_no_symlink "$TARGET_DIR/AGENTS.md"
  for path in "$TARGET_DIR/AGENTS.md" "$TARGET_DIR/.agents/skills/klawde/SKILL.md" \
              "$TARGET_DIR/.agents/skills/close/SKILL.md" \
              "$TARGET_DIR/.agents/changes-schema.sql"; do
    check_dest "$path"
  done
fi
gate_preflight

# From the first write onward, any abort must say the install may be partial
# instead of dying quietly with some files written and some missing.
on_fail() {
  echo "" >&2
  echo "Error: the install did NOT complete; it may be partial." >&2
  echo "Fix the problem above and re-run setup.sh." >&2
}
trap 'if [ $? -ne 0 ]; then on_fail; fi' EXIT

case "$TARGET" in
  claude) install_claude ;;
  codex)  install_codex ;;
  both)   install_claude; install_codex ;;
esac

trap - EXIT
src_version="$(git -C "$SCRIPT_DIR" log -1 --format='%h %ad' --date=short 2>/dev/null || echo unknown)"
echo ""
echo "Done. Project initialized at $TARGET_DIR (target: $TARGET, source version: $src_version)"
case "$TARGET" in
  claude)
    echo "Wrote CLAUDE.md, .claude/commands/ and .claude/changes-schema.sql in this project."
    echo "Run /klawde in Claude Code to start a session." ;;
  codex)
    echo "Wrote AGENTS.md, .agents/skills/ and .agents/changes-schema.sql in this project."
    echo "In Codex, run \$klawde (or pick klawde from /skills) to start a session." ;;
  both)
    echo "Wrote CLAUDE.md + .claude/ (Claude Code) and AGENTS.md + .agents/ (Codex), including the log schema for each."
    echo "Run /klawde in Claude Code, or \$klawde in Codex, to start a session." ;;
esac
if [ "$TARGET" != "codex" ]; then
  echo "If a Claude Code session is already open in this project, restart it: slash commands load at session start."
fi
echo "The entry protocol creates BRIEFING.md and the changes.db log on its first run; commit changes.db like any other project file."
