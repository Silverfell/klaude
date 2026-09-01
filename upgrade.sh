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

# The harness keeps its project log in a SQLite database (changes.db), driven
# entirely through the sqlite3 CLI. The migration below also needs it.
if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "Error: the sqlite3 CLI was not found on PATH." >&2
  echo "Klawde keeps its project log in changes.db and needs sqlite3 to read, write and migrate it." >&2
  echo "Install it (macOS: preinstalled, or 'brew install sqlite'; Debian/Ubuntu: 'apt install sqlite3'; Fedora: 'dnf install sqlite')." >&2
  exit 1
fi

# Read one line of user input into the named variable. A closed stdin
# (non-interactive run) must be a loud error, not a silent set -e exit
# at the prompt with nothing upgraded.
prompt_read() {
  if ! IFS= read -r "$1"; then
    echo "" >&2
    echo "Error: stdin closed at a prompt (non-interactive run?). Nothing was changed." >&2
    echo "Pass flags to skip the prompts: --claude/--codex/--both and --backup/--no-backup." >&2
    exit 1
  fi
}

# Every shipped source must be present before anything is written; a stale or
# partial checkout would otherwise abort mid-copy and leave a partial upgrade.
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
    echo "Remove the symlink and re-run; the upgrade writes a real file in its place." >&2
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
    [ -f "$path" ] || return 1
    [ -w "$path" ] || return 1
    # Backups land next to the file, so the directory must be writable too.
    if [ "$BACKUP" = "yes" ] && [ ! -w "$dir" ]; then return 1; fi
    return 0
  fi
  while [ ! -e "$dir" ]; do dir="$(dirname "$dir")"; done
  [ -d "$dir" ] && [ -w "$dir" ]
}

# Preflight problems are collected, all reported, then fatal in one exit, so
# every offender surfaces before the first write instead of the run aborting
# mid-way with a partial upgrade.
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
# An existing file about to be removed or renamed: rm/mv need a writable directory.
check_removal() {
  if [ -f "$1" ] && [ ! -w "$(dirname "$1")" ]; then
    bad_dest "cannot remove $1 (its directory is not writable)."
  fi
}
gate_preflight() {
  if [ "$PREFLIGHT_BAD" -eq 1 ]; then
    echo "Nothing was changed. Fix the problems above and re-run." >&2
    exit 1
  fi
}

# Detect an existing install to offer as the default selection. Both layouts
# present means a combined install. Harness files count as evidence alongside
# the root contracts: a project whose root contract was renamed or removed
# still has an install worth upgrading, and must not be silently skipped.
has_claude=0
has_codex=0
codex_artifacts=0
if [ -f "$TARGET_DIR/CLAUDE.md" ]; then has_claude=1; fi
for f in klawde.md klaude.md close.md init.md; do
  if [ -f "$TARGET_DIR/.claude/commands/$f" ]; then has_claude=1; fi
done
if [ -f "$TARGET_DIR/.claude/changes-schema.sql" ]; then has_claude=1; fi
if [ -f "$TARGET_DIR/AGENTS.md" ]; then has_codex=1; fi
# Only klawde's own files count as Codex evidence: .agents/skills is a shared
# convention, and another tool's skills must not pass for a klawde install.
for f in klawde klaude close compresschanges; do
  if [ -f "$TARGET_DIR/.agents/skills/$f/SKILL.md" ]; then codex_artifacts=1; fi
done
if [ -f "$TARGET_DIR/.agents/changes-schema.sql" ]; then codex_artifacts=1; fi
if [ "$codex_artifacts" -eq 1 ]; then has_codex=1; fi
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

# Ask whether to create backups, unless a flag already decided.
if [ -z "$BACKUP" ]; then
  echo "Create .bak backups before overwriting? [Y/n]"
  prompt_read ans
  case "$ans" in
    n|N|no|No) BACKUP="no" ;;
    *) BACKUP="yes" ;;
  esac
fi

# An install the chosen target leaves out stays stale; say so rather than
# letting a successful-looking run hide it.
if [ "$has_claude" -eq 1 ] && [ "$TARGET" = "codex" ]; then
  echo "Note: an existing Claude install was detected but is NOT being upgraded (target: codex). Re-run with --claude or --both to upgrade it."
fi
if [ "$has_codex" -eq 1 ] && [ "$TARGET" = "claude" ]; then
  echo "Note: an existing Codex install was detected but is NOT being upgraded (target: claude). Re-run with --codex or --both to upgrade it."
fi

# Refuse symlinked contracts first: it is the precise diagnosis, and there is
# no point asking about a file the preflight would refuse to write anyway.
if [ "$TARGET" != "codex" ]; then check_no_symlink "$TARGET_DIR/CLAUDE.md"; fi
if [ "$TARGET" != "claude" ]; then check_no_symlink "$TARGET_DIR/AGENTS.md"; fi

# An AGENTS.md with no .agents/ klawde artifacts behind it may belong to
# another tool entirely; overwriting it needs explicit confirmation, and no
# flag can grant that, so a non-interactive run must abort here.
if [ "$TARGET" != "claude" ] && [ -f "$TARGET_DIR/AGENTS.md" ] && [ "$codex_artifacts" -eq 0 ]; then
  echo "Warning: AGENTS.md exists but no .agents/ klawde files were found; it may belong to another tool."
  echo "Overwrite AGENTS.md and continue the Codex upgrade? [y/N]"
  if ! IFS= read -r overwrite_agents; then
    echo "" >&2
    echo "Error: stdin closed; cannot confirm overwriting a possibly foreign AGENTS.md. Nothing was changed." >&2
    echo "Run interactively, or re-run with --claude to leave the Codex layout alone." >&2
    exit 1
  fi
  if [[ ! "$overwrite_agents" =~ ^[Yy]$ ]]; then
    if [ "$TARGET" = "both" ]; then
      TARGET="claude"
      echo "AGENTS.md left untouched; upgrading the Claude layout only."
    else
      echo "AGENTS.md left untouched. Nothing was changed." >&2
      exit 1
    fi
  fi
fi

# The paths the migration and schema-upgrade steps below work with; the
# preflight needs them before the first write.
changes="$TARGET_DIR/CHANGES.md"
db="$TARGET_DIR/changes.db"
schema="$SCRIPT_DIR/template/changes-schema.sql"

# Refuse symlinked, unwritable and unremovable destinations before any write.
if [ "$TARGET" != "codex" ]; then
  for path in "$TARGET_DIR/CLAUDE.md" "$TARGET_DIR/.claude/commands/klawde.md" \
              "$TARGET_DIR/.claude/commands/close.md" \
              "$TARGET_DIR/.claude/changes-schema.sql"; do
    check_dest "$path"
  done
  check_removal "$TARGET_DIR/.claude/commands/init.md"
  check_removal "$TARGET_DIR/.claude/commands/klaude.md"
  check_removal "$TARGET_DIR/.claude/commands/compresschanges.md"
fi
if [ "$TARGET" != "claude" ]; then
  for path in "$TARGET_DIR/AGENTS.md" "$TARGET_DIR/.agents/skills/klawde/SKILL.md" \
              "$TARGET_DIR/.agents/skills/close/SKILL.md" \
              "$TARGET_DIR/.agents/changes-schema.sql"; do
    check_dest "$path"
  done
  check_removal "$TARGET_DIR/.agents/skills/klaude/SKILL.md"
  check_removal "$TARGET_DIR/.agents/skills/compresschanges/SKILL.md"
  for old in klawde close compresschanges; do
    check_removal "${CODEX_HOME:-$HOME/.codex}/prompts/$old.md"
  done
fi
# Migration and schema-upgrade targets (target-agnostic; see below).
if [ -f "$db" ]; then
  if ! uv="$(sqlite3 -readonly "$db" 'PRAGMA user_version;' 2>/dev/null)"; then
    bad_dest "changes.db exists but is not a readable SQLite database."
  elif [ "$uv" -gt 3 ]; then
    bad_dest "changes.db schema is v$uv, newer than this checkout supports (v3); run 'git pull' in $SCRIPT_DIR and retry."
  elif [ "$uv" -lt 3 ]; then
    # The schema upgrade below writes it in place.
    check_dest "$db"
  fi
elif [ -f "$changes" ]; then
  # The migration rewrites CHANGES.md in place (normalization), creates the
  # database, and renames CHANGES.md (same directory).
  check_dest "$changes"
  check_dest "$db"
  if [ -f "$TARGET_DIR/.gitignore" ]; then check_dest "$TARGET_DIR/.gitignore"; fi
fi
gate_preflight

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
      -e 's#\.claude/changes-schema\.sql#.agents/changes-schema.sql#g' \
      -e 's#`/klawde`#`$klawde`#g' \
      -e 's#`/close`#`$close`#g' \
      -e 's|^# /klawde: |# $klawde: |' \
      -e 's|^# /close: |# $close: |' \
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

upgrade_claude() {
  local dst="$TARGET_DIR/CLAUDE.md"
  if [ -f "$dst" ]; then maybe_backup "$dst"; fi
  mkdir -p "$(dirname "$dst")"
  cp "$SCRIPT_DIR/template/CLAUDE.md" "$dst"
  echo "Overwrote $dst."
  for cmd in klawde.md close.md; do
    dst="$TARGET_DIR/.claude/commands/$cmd"
    if [ -f "$dst" ]; then maybe_backup "$dst"; fi
    mkdir -p "$(dirname "$dst")"
    cp "$SCRIPT_DIR/template/$cmd" "$dst"
    echo "Overwrote $dst."
  done
  # The log schema /klawde uses to create changes.db on first run.
  dst="$TARGET_DIR/.claude/changes-schema.sql"
  if [ -f "$dst" ]; then maybe_backup "$dst"; fi
  mkdir -p "$(dirname "$dst")"
  cp "$SCRIPT_DIR/template/changes-schema.sql" "$dst"
  echo "Overwrote $dst."
  # Retire the legacy /init command (entry protocol is now /klawde).
  local legacy_init="$TARGET_DIR/.claude/commands/init.md"
  if [ -f "$legacy_init" ]; then
    maybe_backup "$legacy_init"
    rm -f "$legacy_init"
    echo "Removed legacy .claude/commands/init.md."
  fi
  # Retire /klaude (the lean variant is gone; /klawde is the entry protocol).
  local legacy_klaude="$TARGET_DIR/.claude/commands/klaude.md"
  if [ -f "$legacy_klaude" ]; then
    maybe_backup "$legacy_klaude"
    rm -f "$legacy_klaude"
    echo "Removed retired .claude/commands/klaude.md."
  fi
  # Retire /compresschanges (the log is never compacted now).
  local legacy_compress="$TARGET_DIR/.claude/commands/compresschanges.md"
  if [ -f "$legacy_compress" ]; then
    maybe_backup "$legacy_compress"
    rm -f "$legacy_compress"
    echo "Removed retired .claude/commands/compresschanges.md."
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
    "Run only when explicitly invoked. Klawde entry protocol: read BRIEFING.md in full and the last 5 changes.db log entries (creating either if missing), then confirm readiness at session start."
  upgrade_skill close close.md \
    "Run only when explicitly invoked. Klawde close protocol: append decisions and scope changes to the changes.db log, triage open concerns, update BRIEFING.md, and verify log integrity before ending work."
  # The log schema $klawde uses to create changes.db on first run.
  dst="$TARGET_DIR/.agents/changes-schema.sql"
  if [ -f "$dst" ]; then maybe_backup "$dst"; fi
  mkdir -p "$(dirname "$dst")"
  cp "$SCRIPT_DIR/template/changes-schema.sql" "$dst"
  echo "Overwrote $dst."
  # Retire the klaude skill (the lean variant is gone; $klawde is the entry protocol).
  local legacy_klaude_skill="$TARGET_DIR/.agents/skills/klaude/SKILL.md"
  if [ -f "$legacy_klaude_skill" ]; then
    maybe_backup "$legacy_klaude_skill"
    rm -f "$legacy_klaude_skill"
    rmdir "$(dirname "$legacy_klaude_skill")" 2>/dev/null || true
    echo "Removed retired .agents/skills/klaude/SKILL.md."
  fi
  # Retire the compresschanges skill (the log is never compacted now).
  local legacy_skill="$TARGET_DIR/.agents/skills/compresschanges/SKILL.md"
  if [ -f "$legacy_skill" ]; then
    maybe_backup "$legacy_skill"
    rm -f "$legacy_skill"
    rmdir "$(dirname "$legacy_skill")" 2>/dev/null || true
    echo "Removed retired .agents/skills/compresschanges/SKILL.md."
  fi
  # Retire deprecated global prompts from earlier versions (honors CODEX_HOME).
  local prompts_dir="${CODEX_HOME:-$HOME/.codex}/prompts"
  for old in klawde close compresschanges; do
    local legacy_prompt="$prompts_dir/$old.md"
    if [ -f "$legacy_prompt" ]; then
      maybe_backup "$legacy_prompt"
      rm -f "$legacy_prompt"
      echo "Removed deprecated prompt $legacy_prompt."
    fi
  done
}

# From the first write onward, any abort must say the install may be partial
# instead of dying quietly with some files upgraded and some stale.
on_fail() {
  echo "" >&2
  echo "Error: the upgrade did NOT complete; this install may be partially updated." >&2
  echo "Fix the problem above and re-run upgrade.sh." >&2
}
# All migration scratch files live in one directory so every exit path —
# success, explicit abort, or a set -e death — removes them in one sweep.
MIGTMP=""
cleanup_migtmp() { if [ -n "$MIGTMP" ]; then rm -rf "$MIGTMP"; fi; }
trap 'rc=$?; cleanup_migtmp; if [ "$rc" -ne 0 ]; then on_fail; fi' EXIT

case "$TARGET" in
  claude) upgrade_claude ;;
  codex)  upgrade_codex ;;
  both)   upgrade_claude; upgrade_codex ;;
esac

# ---------------------------------------------------------------------------
# Migrate a legacy text CHANGES.md into the changes.db log (runs once).
# Target-agnostic: the log lives in the project root under either layout.
# The $changes / $db / $schema paths are set above, before the preflight.
# ---------------------------------------------------------------------------
echo ""
if [ -f "$db" ]; then
  echo "changes.db is already present. Log migration already done; skipped."
  if [ -f "$changes" ]; then
    echo "A CHANGES.md is also present but was not touched; changes.db is the live log."
  fi
elif [ ! -f "$changes" ]; then
  echo "No CHANGES.md and no changes.db found. /klawde creates changes.db on its next run."
elif [ ! -f "$schema" ]; then
  echo "Error: $schema not found in source; cannot migrate CHANGES.md." >&2
  exit 1
else
  MIGTMP="$(mktemp -d)"

  # --- Normalization: bring legacy text formats up to the last text format ---
  # so the import pass below only has to understand one line shape.
  # Windows line endings count: a CR that survives into an entry is permanent,
  # because the log it lands in is immutable.
  needs_crlf=0
  if grep -q "$(printf '\r')" "$changes"; then
    needs_crlf=1
  fi
  needs_conversion=0
  if grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}:' "$changes"; then
    needs_conversion=1
  fi
  # Entries written before serials and areas existed: date followed straight by [type].
  needs_serials=0
  if grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} \[' "$changes"; then
    needs_serials=1
  fi

  changes_note="CHANGES.md was not modified."
  backfilled=0
  premax=0

  if [ "$needs_crlf" -eq 1 ] || [ "$needs_conversion" -eq 1 ] || [ "$needs_serials" -eq 1 ]; then
    echo "Normalizing legacy CHANGES.md entries before import."

    # Back up first (if enabled) so the original is recoverable
    maybe_backup "$changes"
    if [ "$BACKUP" = "yes" ]; then
      changes_note="CHANGES.md was normalized in place (content preserved; the original is in its .bak file)."
    else
      changes_note="CHANGES.md was normalized in place (content preserved; backups were declined)."
    fi

    if [ "$needs_crlf" -eq 1 ]; then
      # Strip CRs before the passes below, so none can leak into a description.
      tr -d '\r' < "$changes" > "$MIGTMP/crlf"
      mv -f "$MIGTMP/crlf" "$changes"
      echo "Stripped CRLF line endings from CHANGES.md."
    fi

    if [ "$needs_conversion" -eq 1 ]; then
      # Convert old-format entries (YYYY-MM-DD: description) to [note] type.
      # Leaves already-typed entries untouched; the serial pass below handles them.
      tmp="$MIGTMP/conv"
      converted=0
      while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}):[[:space:]]*(.*)$ ]]; then
          printf '%s [note] %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" >> "$tmp"
          converted=$((converted + 1))
        else
          printf '%s\n' "$line" >> "$tmp"
        fi
      done < "$changes"
      mv -f "$tmp" "$changes"
      echo "Converted $converted old-format entries to [note] type."
    fi

    # The pass above produces `YYYY-MM-DD [type] ...` lines, which still need
    # serials. Re-check the file rather than trusting the pre-conversion answer:
    # a file that held only legacy lines would otherwise import as zero entries.
    if grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} \[' "$changes"; then
      needs_serials=1
    fi

    if [ "$needs_serials" -eq 1 ]; then
      # Backfill serials and the (-) area onto pre-serial entries, continuing from the
      # highest serial already present so a partially migrated file stays consistent.
      maxid="$(awk '/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9]+ / {v=$2+0; if (v>m) m=v} END {print m+0}' "$changes")"
      premax="$maxid"
      tmp2="$MIGTMP/serial"
      awk -v start="$maxid" '
        /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] \[note\] Summary:/ {
          rest = substr($0, 12)
          sub(/^\[note\][ ]+/, "", rest)
          printf "%s SUM [note] (-) %s\n", substr($0, 1, 10), rest
          next
        }
        /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] \[/ {
          rest = substr($0, 12)
          if (match(rest, /^\[[a-z]+\]/)) {
            n++
            printf "%s %03d %s (-) %s\n", substr($0, 1, 10), start + n, \
                   substr(rest, RSTART, RLENGTH), substr(rest, RSTART + RLENGTH + 1)
            next
          }
        }
        { print }
        END { printf "%d\n", n > "/dev/stderr" }
      ' "$changes" 2> "$tmp2.count" > "$tmp2"
      mv -f "$tmp2" "$changes"
      backfilled="$(cat "$tmp2.count")"
      echo "Backfilled serials and (-) areas onto $backfilled entries."
    fi
  fi

  echo "Migrating CHANGES.md into changes.db."

  # --- Create the database from the shipped schema -------------------------
  rm -f "$db"
  sqlite3 -bail "$db" < "$schema"

  sql="$MIGTMP/sql"
  diag="$MIGTMP/diag"
  areas_raw="$MIGTMP/areas_raw"
  ent="$MIGTMP/ent"
  sums="$MIGTMP/sums"
  lnk="$MIGTMP/lnk"
  # The awk below only opens the files it writes to; the readers need all three.
  : > "$ent"; : > "$sums"; : > "$lnk"

  # --- Seed the closed area vocabulary -------------------------------------
  # Sources: the brief's "- Areas:" line, plus every area actually used by an
  # entry. Both are needed: an entry whose area is unknown aborts on insert.
  if [ -f "$TARGET_DIR/BRIEFING.md" ]; then
    grep -m1 -E '^[[:space:]]*-[[:space:]]*Areas:' "$TARGET_DIR/BRIEFING.md" \
      | sed -E 's/^[[:space:]]*-[[:space:]]*Areas:[[:space:]]*//' \
      | tr ',' '\n' >> "$areas_raw" || true
  fi
  awk '/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9]+ \[[a-z]+\] \(/ {
         rest = substr($0, 12)
         sub(/^[0-9]+[ ]+\[[a-z]+\][ ]+/, "", rest)
         if (match(rest, /^\([^)]*\)/)) print substr(rest, 2, RLENGTH - 2)
       }' "$changes" >> "$areas_raw"

  echo "BEGIN;" > "$sql"
  sed -E 's/^[[:space:]]+//; s/[[:space:]]*\.?[[:space:]]*$//' "$areas_raw" \
    | grep -v '^$' | grep -vx -- '-' | sort -u \
    | sed -E "s/'/''/g; s/^(.*)\$/INSERT OR IGNORE INTO areas VALUES ('\\1');/" >> "$sql" || true
  area_count="$(grep -c '^INSERT OR IGNORE INTO areas' "$sql" || true)"

  # --- Emit entry, summary and link inserts --------------------------------
  # Links go last: a link naming a serial that has not been inserted yet is
  # refused by a trigger, which would abort the whole transaction.
  awk -v Q="'" -v ENT="$ent" -v SUMS="$sums" -v LNK="$lnk" '
    function lit(s) { gsub(Q, Q Q, s); return Q s Q }
    function addlink(f, t, k,   key) {
      if (f <= t) { diagline[++nd] = "BADLINK entry " f " " k "=" t; nskip++; return }
      key = f "|" t "|" k
      if (key in lseen) return
      lseen[key] = 1
      nl++; lf[nl] = f; lt[nl] = t; lk[nl] = k
    }
    /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9]+ \[[a-z]+\] \(/ {
      d = substr($0, 1, 10)
      rest = substr($0, 12)
      match(rest, /^[0-9]+/)
      serial = substr(rest, RSTART, RLENGTH) + 0
      rest = substr(rest, RLENGTH + 2)
      match(rest, /^\[[a-z]+\]/)
      type = substr(rest, 2, RLENGTH - 2)
      rest = substr(rest, RLENGTH + 2)
      match(rest, /^\([^)]*\)/)
      area = substr(rest, 2, RLENGTH - 2)
      desc = substr(rest, RLENGTH + 2)
      refs = ""
      # Tags sit at the tail, separated from the description by two spaces
      # and from each other by one. Peel them off right to left.
      while (match(desc, /[ ]+(supersedes|closes|refs)=[^ ]+$/)) {
        tok = substr(desc, RSTART, RLENGTH)
        desc = substr(desc, 1, RSTART - 1)
        sub(/^[ ]+/, "", tok)
        p = index(tok, "=")
        k = substr(tok, 1, p - 1)
        v = substr(tok, p + 1)
        if (k == "refs") refs = v
        else addlink(serial, v + 0, k)
      }
      sub(/[ ]+$/, "", desc)
      if (desc == "") desc = "(no description)"
      if (area == "") area = "-"
      seen[serial] = 1
      n++
      if (serial > maxs) maxs = serial
      printf "%d\tINSERT INTO entries (serial,date,type,area,description,refs) VALUES (%d,%s,%s,%s,%s,%s);\n", \
             serial, serial, lit(d), lit(type), lit(area), lit(desc), (refs == "" ? "NULL" : lit(refs)) > ENT
      next
    }
    /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] SUM \[[a-z]+\]/ {
      d = substr($0, 1, 10)
      rest = substr($0, 12)
      sub(/^SUM[ ]+\[[a-z]+\][ ]+/, "", rest)
      area = "-"
      if (match(rest, /^\([^)]*\)/)) {
        area = substr(rest, 2, RLENGTH - 2)
        rest = substr(rest, RLENGTH + 2)
      }
      if (rest == "") rest = "(empty summary)"
      printf "INSERT INTO legacy_summaries (month,area,description) VALUES (%s,%s,%s);\n", \
             lit(substr(d, 1, 7)), lit(area), lit(rest) > SUMS
      ns++
      next
    }
    /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ {
      diagline[++nd] = "UNPARSED " $0
      next
    }
    { next }
    END {
      for (i = 1; i <= nl; i++) {
        if (lt[i] in seen) {
          printf "INSERT INTO links VALUES (%d,%d,%s);\n", lf[i], lt[i], lit(lk[i]) > LNK
          nins++
        } else {
          diagline[++nd] = "DANGLING entry " lf[i] " " lk[i] "=" lt[i]
          nskip++
        }
      }
      for (i = 1; i <= nd; i++) print diagline[i] > "/dev/stderr"
      printf "COUNTS %d %d %d %d %d\n", n + 0, maxs + 0, nins + 0, nskip + 0, ns + 0 > "/dev/stderr"
    }
  ' "$changes" 2> "$diag"
  # Entries must land in ascending serial order: the schema's no-backfill
  # trigger refuses a serial below the current maximum, and the normalized
  # file lists backfilled (highest) serials first.
  sort -n "$ent" | cut -f2- >> "$sql"
  cat "$sums" "$lnk" >> "$sql"
  echo "COMMIT;" >> "$sql"

  awk_entries="$(awk '$1 == "COUNTS" { print $2 }' "$diag")"
  awk_max="$(awk '$1 == "COUNTS" { print $3 }' "$diag")"
  link_count="$(awk '$1 == "COUNTS" { print $4 }' "$diag")"
  skip_count="$(awk '$1 == "COUNTS" { print $5 }' "$diag")"
  sum_count="$(awk '$1 == "COUNTS" { print $6 }' "$diag")"

  # Warn about anything the import could not place, before it becomes invisible.
  while IFS= read -r warn; do
    case "$warn" in
      DANGLING*) echo "Warning: link skipped, target serial is not in the file (collapsed by an old compaction): ${warn#DANGLING }" ;;
      BADLINK*)  echo "Warning: link skipped, it does not point backwards: ${warn#BADLINK }" ;;
      UNPARSED*) echo "Warning: dated line not recognized as an entry and not imported: ${warn#UNPARSED }" ;;
    esac
  done < "$diag"

  if ! sqlite3 -bail "$db" < "$sql"; then
    rm -f "$db"
    echo "Error: importing CHANGES.md into changes.db failed. No database was written. $changes_note" >&2
    exit 1
  fi

  # --- Verify the import against the file it came from ---------------------
  file_entries="$(grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]+ \[[a-z]+\] \(' "$changes" || true)"
  file_max="$(awk '/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9]+ \[[a-z]+\] \(/ {v = $2 + 0; if (v > m) m = v} END {print m + 0}' "$changes")"
  db_entries="$(sqlite3 -readonly "$db" 'SELECT count(*) FROM entries;')"
  db_max="$(sqlite3 -readonly "$db" 'SELECT coalesce(max(serial), 0) FROM entries;')"

  if [ "$db_entries" != "$file_entries" ] || [ "$db_max" != "$file_max" ] || [ "$awk_entries" != "$file_entries" ] || [ "$awk_max" != "$file_max" ]; then
    rm -f "$db"
    echo "Error: migration verification failed." >&2
    echo "  CHANGES.md: $file_entries entries, max serial $file_max" >&2
    echo "  changes.db: $db_entries entries, max serial $db_max" >&2
    echo "No database was written. $changes_note Report this with a copy of CHANGES.md." >&2
    exit 1
  fi

  # --- Record the migration in the new log ---------------------------------
  # The newest entry then explains where the log came from, which matters
  # because the next session's tail read starts from it.
  mig_desc="Migrated CHANGES.md into changes.db ($file_entries entries)"
  if [ "$backfilled" -gt 0 ] && [ "$premax" -gt 0 ]; then
    mig_desc="$mig_desc; serials $(printf '%03d' $((premax + 1)))-$(printf '%03d' $((premax + backfilled))) are backfilled pre-serial entries, older than their serial order suggests"
  fi
  sqlite3 -bail "$db" "INSERT INTO entries (type, area, description) VALUES ('doc','-','$mig_desc');"
  mig_serial="$(sqlite3 -readonly "$db" 'SELECT max(serial) FROM entries;')"

  # --- Retire the text log -------------------------------------------------
  mv -f "$changes" "$changes.migrated"
  if command -v git >/dev/null 2>&1 && git -C "$TARGET_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    gitignore="$TARGET_DIR/.gitignore"
    if ! { [ -f "$gitignore" ] && grep -qxF 'CHANGES.md.migrated' "$gitignore"; }; then
      if [ -s "$gitignore" ] && [ "$(tail -c 1 "$gitignore" | wc -l)" -eq 0 ]; then
        printf '\n' >> "$gitignore"
      fi
      printf '%s\n' 'CHANGES.md.migrated' >> "$gitignore"
      echo "Added CHANGES.md.migrated to .gitignore."
    fi
  fi

  echo "Migrated $file_entries entries (max serial $file_max), $link_count links, $sum_count legacy monthly summaries, $area_count areas."
  echo "Appended migration entry $(printf '%03d' "$mig_serial") [doc] recording the import."
  if [ "$backfilled" -gt 0 ] && [ "$premax" -gt 0 ]; then
    echo "Warning: $backfilled pre-serial entries were backfilled with serials above the pre-existing maximum ($premax), so the session-start tail will show those oldest entries as most recent until new entries are written. Entry $(printf '%03d' "$mig_serial") records this."
  fi
  if [ "$skip_count" -gt 0 ]; then
    echo "Skipped $skip_count link(s) that pointed at serials the file no longer contains (see warnings above)."
  fi
  echo "CHANGES.md is now CHANGES.md.migrated. Delete it once you are satisfied with changes.db, and commit changes.db like any other project file."
fi

# ---------------------------------------------------------------------------
# Upgrade an existing changes.db to the current schema version, in place.
# v1 -> v2 added the areas_no_update and entries_no_backfill triggers.
# v2 -> v3 added the concerns table, its triggers, the concern_lines view, and
# the no-replace guards that stop INSERT OR REPLACE from rewriting rows.
# Every statement is extracted from the shipped schema, so the two cannot drift.
# ---------------------------------------------------------------------------
add_trigger_from_schema() {
  local trig="$1" stmt
  stmt="$(sed -n "/^CREATE TRIGGER $trig /,/END;/p" "$schema")"
  if [ -z "$stmt" ]; then
    echo "Error: trigger $trig not found in $schema; cannot upgrade the changes.db schema." >&2
    exit 1
  fi
  printf '%s\n' "$stmt" \
    | sed '1s/^CREATE TRIGGER /CREATE TRIGGER IF NOT EXISTS /' \
    | sqlite3 -bail "$db"
}
if [ -f "$db" ]; then
  uv="$(sqlite3 -readonly "$db" 'PRAGMA user_version;')"
  if [ "$uv" -lt 3 ]; then
    maybe_backup "$db"
  fi
  if [ "$uv" -lt 2 ]; then
    for trig in areas_no_update entries_no_backfill; do
      add_trigger_from_schema "$trig"
    done
    sqlite3 -bail "$db" 'PRAGMA user_version = 2;'
    echo ""
    echo "Upgraded the changes.db schema to v2 (added the areas_no_update and entries_no_backfill triggers)."
  fi
  if [ "$uv" -lt 3 ]; then
    tbl="$(sed -n '/^CREATE TABLE concerns (/,/^);/p' "$schema")"
    view="$(sed -n '/^CREATE VIEW concern_lines /,/^  FROM concerns c;$/p' "$schema")"
    if [ -z "$tbl" ] || [ -z "$view" ]; then
      echo "Error: concerns table or concern_lines view not found in $schema; cannot upgrade the changes.db schema." >&2
      exit 1
    fi
    printf '%s\n' "$tbl" | sed '1s/^CREATE TABLE /CREATE TABLE IF NOT EXISTS /' | sqlite3 -bail "$db"
    for trig in concerns_no_delete concerns_immutable_text concerns_resolve_once \
                concerns_born_open concerns_area_known concerns_ref_exists \
                concerns_no_replace entries_no_replace; do
      add_trigger_from_schema "$trig"
    done
    printf '%s\n' "$view" | sed '1s/^CREATE VIEW /CREATE VIEW IF NOT EXISTS /' | sqlite3 -bail "$db"
    sqlite3 -bail "$db" 'PRAGMA user_version = 3;'
    echo ""
    echo "Upgraded the changes.db schema to v3 (added the concerns table, its triggers and view, and the no-replace guards on entries and concerns)."
  fi
fi

trap - EXIT
cleanup_migtmp
src_version="$(git -C "$SCRIPT_DIR" log -1 --format='%h %ad' --date=short 2>/dev/null || echo unknown)"
echo ""
echo "Done. Upgrade complete at $TARGET_DIR (target: $TARGET, source version: $src_version)"
if [ "$TARGET" != "codex" ]; then
  echo "If a Claude Code session is open in this project, restart it: slash commands load at session start."
fi
