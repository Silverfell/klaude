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
  echo "Usage: upgrade.sh [--claude|--codex|--both] [--backup|--no-backup]"
  echo "  --claude     Upgrade a Claude Code install (CLAUDE.md + .claude/commands/)"
  echo "  --codex      Upgrade a Codex install (AGENTS.md + .agents/skills/)"
  echo "  --both       Upgrade both layouts"
  echo "  --backup     Create .bak backups before overwriting (skip the prompt)"
  echo "  --no-backup  Do not create backups (skip the prompt)"
  echo "  With no target flag, the existing install is detected and you are prompted."
}

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
require_sqlite

# Detect the existing install. Harness files count alongside the root contract;
# only klawde's own files count as Codex evidence, since .agents/skills is shared.
# The two checker scripts are listed because older versions installed them.
has_claude=0
has_codex=0
claude_artifacts=0
codex_artifacts=0
if [ -f "$TARGET_DIR/CLAUDE.md" ]; then has_claude=1; fi
for f in .claude/commands/klawde.md .claude/commands/close.md \
         .claude/commands/upgrade_klawde.md .claude/changes-schema.sql \
         .claude/check-log.sh .claude/check-briefing.sh; do
  if [ -f "$TARGET_DIR/$f" ]; then claude_artifacts=1; fi
done
if [ "$claude_artifacts" -eq 1 ]; then has_claude=1; fi
if [ -f "$TARGET_DIR/AGENTS.md" ]; then has_codex=1; fi
for f in .agents/skills/klawde/SKILL.md .agents/skills/close/SKILL.md \
         .agents/skills/upgrade_klawde/SKILL.md .agents/changes-schema.sql \
         .agents/check-log.sh .agents/check-briefing.sh; do
  if [ -f "$TARGET_DIR/$f" ]; then codex_artifacts=1; fi
done
if [ "$codex_artifacts" -eq 1 ]; then has_codex=1; fi
DETECTED=""
if [ "$has_claude" -eq 1 ] && [ "$has_codex" -eq 1 ]; then
  DETECTED="both"
elif [ "$has_claude" -eq 1 ]; then
  DETECTED="claude"
elif [ "$has_codex" -eq 1 ]; then
  DETECTED="codex"
fi

if [ -z "$TARGET" ]; then
  echo "Upgrade for:"
  echo "[1] claude"
  echo "[2] codex"
  echo "[3] both"
  if [ -n "$DETECTED" ]; then
    echo "[Enter for detected: $DETECTED]"
  fi
  prompt_read sel
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

if [ -z "$BACKUP" ]; then
  echo "Create .bak backups before overwriting? [Y/n]"
  prompt_read ans
  case "$ans" in
    n|N|no|No) BACKUP="no" ;;
    *) BACKUP="yes" ;;
  esac
fi

if [ "$has_claude" -eq 1 ] && [ "$TARGET" = "codex" ]; then
  echo "Note: an existing Claude install was detected but is NOT being upgraded (target: codex). Re-run with --claude or --both to upgrade it."
fi
if [ "$has_codex" -eq 1 ] && [ "$TARGET" = "claude" ]; then
  echo "Note: an existing Codex install was detected but is NOT being upgraded (target: claude). Re-run with --codex or --both to upgrade it."
fi

if [ "$TARGET" != "codex" ]; then check_no_symlink "$TARGET_DIR/CLAUDE.md"; fi
if [ "$TARGET" != "claude" ]; then check_no_symlink "$TARGET_DIR/AGENTS.md"; fi

# Preflight: every destination this upgrade writes. The records themselves are
# never touched here; `/upgrade_klawde` migrates them afterwards.
if [ "$TARGET" != "codex" ]; then
  for path in "$TARGET_DIR/CLAUDE.md" "$TARGET_DIR/.claude/commands/klawde.md" \
              "$TARGET_DIR/.claude/commands/close.md" \
              "$TARGET_DIR/.claude/commands/upgrade_klawde.md" \
              "$TARGET_DIR/.claude/changes-schema.sql"; do
    check_dest "$path"
  done
fi
if [ "$TARGET" != "claude" ]; then
  for path in "$TARGET_DIR/AGENTS.md" "$TARGET_DIR/.agents/skills/klawde/SKILL.md" \
              "$TARGET_DIR/.agents/skills/close/SKILL.md" \
              "$TARGET_DIR/.agents/skills/upgrade_klawde/SKILL.md" \
              "$TARGET_DIR/.agents/changes-schema.sql"; do
    check_dest "$path"
  done
fi
gate_preflight

# A root contract with no klawde files behind it may be the user's own, or
# another tool's; overwriting it needs a confirmation no flag can give.
confirm_foreign() { # <file> <layout flag that leaves it alone>
  echo "Warning: $1 exists but no klawde files were found beside it; it may not be klawde's."
  echo "Overwrite $1 and continue? [y/N]"
  if ! IFS= read -r answer; then
    echo "" >&2
    echo "Error: stdin closed; cannot confirm overwriting a possibly foreign $1. Nothing was changed." >&2
    echo "Run interactively, or re-run with $2 to leave that layout alone." >&2
    exit 1
  fi
  if [[ ! "$answer" =~ ^[Yy]$ ]]; then
    echo "$1 left untouched. Nothing was changed." >&2
    exit 1
  fi
}
if [ "$TARGET" != "codex" ] && [ -f "$TARGET_DIR/CLAUDE.md" ] && [ "$claude_artifacts" -eq 0 ]; then
  confirm_foreign CLAUDE.md --codex
fi
if [ "$TARGET" != "claude" ] && [ -f "$TARGET_DIR/AGENTS.md" ] && [ "$codex_artifacts" -eq 0 ]; then
  confirm_foreign AGENTS.md --claude
fi

echo ""
echo "Upgrading klawde defaults in $TARGET_DIR (target: $TARGET, backups: $BACKUP)"
echo ""

maybe_backup() {
  local path="$1"
  if [ "$BACKUP" = "yes" ]; then
    local backup="$path.bak.$(date +%Y%m%d-%H%M%S)" n=0
    while [ -e "$backup" ]; do n=$((n + 1)); backup="$path.bak.$(date +%Y%m%d-%H%M%S).$n"; done
    if ! cp "$path" "$backup"; then
      echo "Error: could not back up $path; the original was not removed." >&2
      return 1
    fi
    echo "Backed up $(basename "$path") to $(basename "$backup")."
  fi
}

overwrite() { # <src> <dst>
  if [ -f "$2" ]; then maybe_backup "$2"; fi
  mkdir -p "$(dirname "$2")"
  cp "$1" "$2"
  echo "Overwrote $2."
}

write_contract() { # <dst> <claude|codex>
  local dst="$1"
  if [ -f "$dst" ]; then maybe_backup "$dst"; fi
  if [ "$2" = "codex" ]; then
    rewrite_codex "$SCRIPT_DIR/template/CLAUDE.md" > "$dst"
  else
    cp "$SCRIPT_DIR/template/CLAUDE.md" "$dst"
  fi
  echo "Overwrote $dst."
}

# Files earlier versions installed that this one no longer ships: the two
# checkers, which reference a schema that no longer exists, and the migration
# command under its former name, whose instructions are unsafe against the
# current schema. Leaving either in place keeps it invokable.
remove_stale() { # <layout directory: .claude|.agents>
  local stale
  for stale in "$1/check-log.sh" "$1/check-briefing.sh"; do
    if [ -f "$TARGET_DIR/$stale" ]; then
      rm -f "$TARGET_DIR/$stale"
      echo "Removed $stale (no longer part of klawde)."
    fi
  done
  if [ "$1" = ".claude" ]; then
    stale=".claude/commands/klawdeupgrade.md"
  else
    stale=".agents/skills/klawdeupgrade/SKILL.md"
  fi
  if [ -f "$TARGET_DIR/$stale" ]; then
    rm -f "$TARGET_DIR/$stale"
    # The skill's directory is klawde's own; remove it when nothing else is in it.
    rmdir "$TARGET_DIR/.agents/skills/klawdeupgrade" 2>/dev/null || true
    echo "Removed $stale (renamed to upgrade_klawde)."
  fi
}

upgrade_claude() {
  write_contract "$TARGET_DIR/CLAUDE.md" claude
  for cmd in klawde.md close.md upgrade_klawde.md; do
    overwrite "$SCRIPT_DIR/template/$cmd" "$TARGET_DIR/.claude/commands/$cmd"
  done
  for artifact in changes-schema.sql; do
    overwrite "$SCRIPT_DIR/template/$artifact" "$TARGET_DIR/.claude/$artifact"
  done
  remove_stale .claude
}

upgrade_skill() { # <name> <template file> <description>
  local name="$1" src="$2" desc="$3"
  local dst="$TARGET_DIR/.agents/skills/$name/SKILL.md"
  if [ -f "$dst" ]; then maybe_backup "$dst"; fi
  mkdir -p "$(dirname "$dst")"
  build_skill_file "$SCRIPT_DIR/template/$src" "$name" "$desc" "$dst"
  echo "Overwrote $dst."
}

upgrade_codex() {
  write_contract "$TARGET_DIR/AGENTS.md" codex
  upgrade_skill klawde klawde.md "$KLAWDE_SKILL_DESC"
  upgrade_skill close close.md "$CLOSE_SKILL_DESC"
  upgrade_skill upgrade_klawde upgrade_klawde.md "$UPGRADE_KLAWDE_SKILL_DESC"
  for artifact in changes-schema.sql; do
    overwrite "$SCRIPT_DIR/template/$artifact" "$TARGET_DIR/.agents/$artifact"
  done
  remove_stale .agents
}

# From the first write onward, an abort must say the install may be partial.
WRITES_STARTED=0
on_fail() {
  echo "" >&2
  if [ "$WRITES_STARTED" -eq 1 ]; then
    echo "Error: the upgrade did NOT complete; this install may be partially updated." >&2
  else
    echo "Error: the upgrade did not start; nothing was changed." >&2
  fi
  echo "Fix the problem above and re-run upgrade.sh." >&2
}
trap 'if [ $? -ne 0 ]; then on_fail; fi' EXIT

WRITES_STARTED=1
case "$TARGET" in
  claude) upgrade_claude ;;
  codex)  upgrade_codex ;;
  both)   upgrade_claude; upgrade_codex ;;
esac

trap - EXIT
echo ""
echo "Done. Upgrade complete at $TARGET_DIR (target: $TARGET, source version: $(source_version))"
echo "Run /upgrade_klawde in your agent to migrate BRIEFING.md and changes.db."
echo "guidelines.md is never written by an upgrade. If you do not have one, /upgrade_klawde offers to install it."
if [ "$TARGET" != "codex" ]; then
  echo "If a Claude Code session is open in this project, restart it: slash commands load at session start."
fi
