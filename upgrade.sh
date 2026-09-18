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

# The schema version this checkout ships, read from the schema itself.
schema="$SCRIPT_DIR/template/changes-schema.sql"
SCHEMA_MAX="$(sed -n 's/^PRAGMA user_version = \([0-9][0-9]*\);$/\1/p' "$schema")"
case "$SCHEMA_MAX" in
  ''|*[!0-9]*)
    echo "Error: $schema carries no PRAGMA user_version; the checkout looks corrupt." >&2
    exit 1 ;;
esac

# Detect the existing install. Harness files count alongside the root contract;
# only klawde's own files count as Codex evidence, since .agents/skills is shared.
has_claude=0
has_codex=0
codex_artifacts=0
for f in CLAUDE.md .claude/commands/klawde.md .claude/commands/close.md \
         .claude/changes-schema.sql .claude/check-log.sh; do
  if [ -f "$TARGET_DIR/$f" ]; then has_claude=1; fi
done
if [ -f "$TARGET_DIR/AGENTS.md" ]; then has_codex=1; fi
for f in .agents/skills/klawde/SKILL.md .agents/skills/close/SKILL.md \
         .agents/changes-schema.sql .agents/check-log.sh; do
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

# An AGENTS.md with no klawde artifacts behind it may belong to another tool.
if [ "$TARGET" != "claude" ] && [ -f "$TARGET_DIR/AGENTS.md" ] && [ "$codex_artifacts" -eq 0 ]; then
  echo "Warning: AGENTS.md exists but no .agents/ klawde files were found; it may belong to another tool."
  echo "Overwrite AGENTS.md and continue? [y/N]"
  if ! IFS= read -r overwrite_agents; then
    echo "" >&2
    echo "Error: stdin closed; cannot confirm overwriting a possibly foreign AGENTS.md. Nothing was changed." >&2
    echo "Run interactively, or re-run with --claude to leave the Codex layout alone." >&2
    exit 1
  fi
  if [[ ! "$overwrite_agents" =~ ^[Yy]$ ]]; then
    echo "AGENTS.md left untouched. Nothing was changed." >&2
    exit 1
  fi
fi

db="$TARGET_DIR/changes.db"
# One line per difference against the shipped schema, as object|name|status.
db_drift() {
  bash "$SCRIPT_DIR/template/check-log.sh" --objects "$1" "$schema"
}

# Preflight: every destination, and the log if present.
if [ "$TARGET" != "codex" ]; then
  for path in "$TARGET_DIR/CLAUDE.md" "$TARGET_DIR/.claude/commands/klawde.md" \
              "$TARGET_DIR/.claude/commands/close.md" \
              "$TARGET_DIR/.claude/changes-schema.sql" "$TARGET_DIR/.claude/check-log.sh"; do
    check_dest "$path"
  done
fi
if [ "$TARGET" != "claude" ]; then
  for path in "$TARGET_DIR/AGENTS.md" "$TARGET_DIR/.agents/skills/klawde/SKILL.md" \
              "$TARGET_DIR/.agents/skills/close/SKILL.md" \
              "$TARGET_DIR/.agents/changes-schema.sql" "$TARGET_DIR/.agents/check-log.sh"; do
    check_dest "$path"
  done
fi
DB_DRIFT=""
uv=""
if [ -e "$db" ]; then
  if [ ! -f "$db" ] || ! uv="$(sqlite3 -readonly "$db" 'PRAGMA user_version;' 2>/dev/null)"; then
    bad_dest "changes.db exists but is not a readable SQLite database file; move it aside and re-run."
  else
    required="entries areas links legacy_summaries"
    if [ "$uv" -ge 3 ]; then required="$required concerns"; fi
    for t in $required; do
      if [ "$(sqlite3 -readonly "$db" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='$t';" 2>/dev/null)" != "1" ]; then
        bad_dest "changes.db lacks the $t table its schema v$uv requires: it is not a klawde log, or is damaged. Move it aside, or recover it from git, and re-run."
        break
      fi
    done
    if [ "$PREFLIGHT_BAD" -eq 0 ] && [ "$uv" -gt "$SCHEMA_MAX" ]; then
      bad_dest "changes.db schema is v$uv, newer than this checkout supports (v$SCHEMA_MAX); run 'git pull' in $SCRIPT_DIR and retry."
    fi
    if [ "$PREFLIGHT_BAD" -eq 0 ]; then
      DB_DRIFT="$(db_drift "$db")" || bad_dest "changes.db could not be compared against the shipped schema."
      if [ "$uv" -lt "$SCHEMA_MAX" ] || [ -n "$DB_DRIFT" ]; then
        check_dest "$db"
      fi
    fi
  fi
fi
# A missing or changed table cannot be repaired without risking its rows, and a
# trigger the schema does not define can silence inserts (RAISE(IGNORE)); both
# are refused here. A pre-v3 log legitimately lacks the concerns table.
if [ "$PREFLIGHT_BAD" -eq 0 ] && [ -n "$DB_DRIFT" ]; then
  while IFS='|' read -r kind name status; do
    if [ "$kind" = "table" ] && [ "$status" != "unexpected" ]; then
      if [ "$name" = "concerns" ] && [ "$uv" -lt 3 ] && [ "$status" = "missing" ]; then
        continue
      fi
      bad_dest "changes.db has a missing or changed $name table; recover the database from git before upgrading."
    elif [ "$kind" = "trigger" ] && [ "$status" = "unexpected" ]; then
      bad_dest "changes.db carries a trigger the shipped schema does not define ($name); remove it, or recover the database from git, before upgrading."
    fi
  done <<< "$DB_DRIFT"
fi
gate_preflight

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

# The contract's Code craft section is optional; say so when the overwrite restores it.
note_code_craft() {
  if [ -f "$1" ] && ! grep -q '^### Code craft' "$1"; then
    echo "Note: $(basename "$1") has no Code craft section; the upgrade restores it. Delete the section again if you do not want it."
  fi
}

overwrite() { # <src> <dst>
  if [ -f "$2" ]; then maybe_backup "$2"; fi
  mkdir -p "$(dirname "$2")"
  cp "$1" "$2"
  echo "Overwrote $2."
}

upgrade_claude() {
  note_code_craft "$TARGET_DIR/CLAUDE.md"
  overwrite "$SCRIPT_DIR/template/CLAUDE.md" "$TARGET_DIR/CLAUDE.md"
  for cmd in klawde.md close.md; do
    overwrite "$SCRIPT_DIR/template/$cmd" "$TARGET_DIR/.claude/commands/$cmd"
  done
  for artifact in changes-schema.sql check-log.sh; do
    overwrite "$SCRIPT_DIR/template/$artifact" "$TARGET_DIR/.claude/$artifact"
  done
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
  local dst="$TARGET_DIR/AGENTS.md"
  note_code_craft "$dst"
  if [ -f "$dst" ]; then maybe_backup "$dst"; fi
  rewrite_codex "$SCRIPT_DIR/template/CLAUDE.md" > "$dst"
  echo "Overwrote $dst."
  upgrade_skill klawde klawde.md "$KLAWDE_SKILL_DESC"
  upgrade_skill close close.md "$CLOSE_SKILL_DESC"
  for artifact in changes-schema.sql check-log.sh; do
    overwrite "$SCRIPT_DIR/template/$artifact" "$TARGET_DIR/.agents/$artifact"
  done
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

# Bring an existing changes.db to the shipped schema, in place: create the
# concerns table a pre-v3 log lacks, restore missing or changed triggers and
# views from the shipped definitions, and set the version, all in one
# transaction. Tables are never rebuilt (preflight refused that); objects the
# schema does not define are never dropped.
if [ -f "$db" ]; then
  if [ "$uv" -lt "$SCHEMA_MAX" ] || [ -n "$DB_DRIFT" ]; then
    maybe_backup "$db"
  fi
  if [ "$uv" -lt 3 ]; then
    sed -n '/^CREATE TABLE concerns (/,/^);/p' "$schema" \
      | sed '1s/^CREATE TABLE /CREATE TABLE IF NOT EXISTS /' | sqlite3 -bail "$db"
  fi
  drift="$(db_drift "$db")"
  repairable="$(printf '%s\n' "$drift" \
    | awk -F'|' 'NF == 3 && $1 != "table" && ($3 == "missing" || $3 == "changed")')"
  restored="$(printf '%s\n' "$repairable" | awk -F'|' '$3 == "missing" { printf "%s ", $2 }')"
  if [ -n "$repairable" ] || [ "$uv" -lt "$SCHEMA_MAX" ]; then
    {
      echo 'BEGIN;'
      if [ -n "$repairable" ]; then
        while IFS='|' read -r kind name status; do
          case "$kind" in
            trigger)
              printf 'DROP TRIGGER IF EXISTS %s;\n' "$name"
              sed -n "/^CREATE TRIGGER $name /,/END;/p" "$schema" ;;
            view)
              printf 'DROP VIEW IF EXISTS %s;\n' "$name"
              sed -n "/^CREATE VIEW $name /,/;$/p" "$schema" ;;
            *) echo "Error: cannot safely repair $kind $name ($status)." >&2; exit 1 ;;
          esac
        done <<< "$repairable"
      fi
      printf 'PRAGMA user_version = %s;\n' "$SCHEMA_MAX"
      echo 'COMMIT;'
    } | sqlite3 -bail "$db"
  fi
  bash "$SCRIPT_DIR/template/check-log.sh" "$db" "$schema"
  if [ "$uv" -lt "$SCHEMA_MAX" ]; then
    echo "Upgraded the changes.db schema from v$uv to v$SCHEMA_MAX."
  fi
  if [ -n "$restored" ]; then
    echo "restored missing: ${restored% }."
  fi
  if [ -n "$repairable" ]; then
    echo "Reconciled trigger/view definitions with the shipped schema."
  fi
fi

trap - EXIT
echo ""
echo "Done. Upgrade complete at $TARGET_DIR (target: $TARGET, source version: $(source_version))"
if [ "$TARGET" != "codex" ]; then
  echo "If a Claude Code session is open in this project, restart it: slash commands load at session start."
fi
