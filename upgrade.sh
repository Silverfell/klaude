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
      -e 's#\.claude/changes-schema\.sql#.agents/changes-schema.sql#g' \
      -e 's#`/klawde`#`$klawde`#g' \
      -e 's#`/klaude`#`$klaude`#g' \
      -e 's#`/close`#`$close`#g' \
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
  for cmd in klawde.md klaude.md close.md; do
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
    rm "$legacy_init"
    echo "Removed legacy .claude/commands/init.md."
  fi
  # Retire /compresschanges (the log is never compacted now).
  local legacy_compress="$TARGET_DIR/.claude/commands/compresschanges.md"
  if [ -f "$legacy_compress" ]; then
    maybe_backup "$legacy_compress"
    rm "$legacy_compress"
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
    "Run only when explicitly invoked. Klawde entry protocol (full mode): read BRIEFING.md in full and the last 5 changes.db log entries (creating either if missing), then confirm readiness at session start, with the Code craft module active."
  upgrade_skill klaude klaude.md \
    "Run only when explicitly invoked. Klawde entry protocol (lean mode): same as klawde, but with the Code craft module disabled for the session."
  upgrade_skill close close.md \
    "Run only when explicitly invoked. Klawde close protocol: append decisions and scope changes to the changes.db log, update BRIEFING.md, and verify log integrity before ending work."
  # The log schema $klawde uses to create changes.db on first run.
  dst="$TARGET_DIR/.agents/changes-schema.sql"
  if [ -f "$dst" ]; then maybe_backup "$dst"; fi
  mkdir -p "$(dirname "$dst")"
  cp "$SCRIPT_DIR/template/changes-schema.sql" "$dst"
  echo "Overwrote $dst."
  # Retire the compresschanges skill (the log is never compacted now).
  local legacy_skill="$TARGET_DIR/.agents/skills/compresschanges/SKILL.md"
  if [ -f "$legacy_skill" ]; then
    maybe_backup "$legacy_skill"
    rm "$legacy_skill"
    rmdir "$(dirname "$legacy_skill")" 2>/dev/null || true
    echo "Removed retired .agents/skills/compresschanges/SKILL.md."
  fi
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

# ---------------------------------------------------------------------------
# Migrate a legacy text CHANGES.md into the changes.db log (runs once).
# Target-agnostic: the log lives in the project root under either layout.
# ---------------------------------------------------------------------------
changes="$TARGET_DIR/CHANGES.md"
db="$TARGET_DIR/changes.db"
schema="$SCRIPT_DIR/template/changes-schema.sql"

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
  # --- Normalization: bring legacy text formats up to the last text format ---
  # so the import pass below only has to understand one line shape.
  needs_conversion=0
  if grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}:' "$changes"; then
    needs_conversion=1
  fi
  # Entries written before serials and areas existed: date followed straight by [type].
  needs_serials=0
  if grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} \[' "$changes"; then
    needs_serials=1
  fi

  if [ "$needs_conversion" -eq 1 ] || [ "$needs_serials" -eq 1 ]; then
    echo "Normalizing legacy CHANGES.md entries before import."

    # Back up first (if enabled) so the original is recoverable
    maybe_backup "$changes"

    if [ "$needs_conversion" -eq 1 ]; then
      # Convert old-format entries (YYYY-MM-DD: description) to [note] type.
      # Leaves already-typed entries untouched; the serial pass below handles them.
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
      tmp2="$(mktemp)"
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
      mv "$tmp2" "$changes"
      echo "Backfilled serials and (-) areas onto $(cat "$tmp2.count") entries."
      rm -f "$tmp2.count"
    fi
  fi

  echo "Migrating CHANGES.md into changes.db."

  # --- Create the database from the shipped schema -------------------------
  rm -f "$db"
  sqlite3 -bail "$db" < "$schema"

  sql="$(mktemp)"
  diag="$(mktemp)"
  areas_raw="$(mktemp)"

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
  awk -v Q="'" '
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
      printf "INSERT INTO entries (serial,date,type,area,description,refs) VALUES (%d,%s,%s,%s,%s,%s);\n", \
             serial, lit(d), lit(type), lit(area), lit(desc), (refs == "" ? "NULL" : lit(refs))
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
             lit(substr(d, 1, 7)), lit(area), lit(rest)
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
          printf "INSERT INTO links VALUES (%d,%d,%s);\n", lf[i], lt[i], lit(lk[i])
          nins++
        } else {
          diagline[++nd] = "DANGLING entry " lf[i] " " lk[i] "=" lt[i]
          nskip++
        }
      }
      for (i = 1; i <= nd; i++) print diagline[i] > "/dev/stderr"
      printf "COUNTS %d %d %d %d %d\n", n + 0, maxs + 0, nins + 0, nskip + 0, ns + 0 > "/dev/stderr"
    }
  ' "$changes" >> "$sql" 2> "$diag"
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
    echo "Error: importing CHANGES.md into changes.db failed. CHANGES.md is untouched; no database was written." >&2
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
    echo "CHANGES.md is untouched and no database was written. Report this with a copy of CHANGES.md." >&2
    exit 1
  fi

  rm -f "$sql" "$diag" "$areas_raw"

  # --- Retire the text log -------------------------------------------------
  mv "$changes" "$changes.migrated"
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
  if [ "$skip_count" -gt 0 ]; then
    echo "Skipped $skip_count link(s) that pointed at serials the file no longer contains (see warnings above)."
  fi
  echo "CHANGES.md is now CHANGES.md.migrated. Delete it once you are satisfied with changes.db, and commit changes.db like any other project file."
fi

echo ""
echo "Done. Upgrade complete at $TARGET_DIR (target: $TARGET)"
