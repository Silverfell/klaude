# Shared by setup.sh and upgrade.sh, which source it after resolving SCRIPT_DIR.

# The harness drives changes.db entirely through the sqlite3 CLI.
require_sqlite() {
  if ! command -v sqlite3 >/dev/null 2>&1; then
    echo "Error: the sqlite3 CLI was not found on PATH." >&2
    echo "Install it (macOS: preinstalled, or 'brew install sqlite'; Debian/Ubuntu: 'apt install sqlite3'; Fedora: 'dnf install sqlite')." >&2
    exit 1
  fi
}

# Read one line of user input into the named variable; a closed stdin is a loud error.
prompt_read() {
  if ! IFS= read -r "$1"; then
    echo "" >&2
    echo "Error: stdin closed at a prompt (non-interactive run?). Nothing was changed." >&2
    echo "Pass flags to skip the prompts." >&2
    exit 1
  fi
}

# The two contracts have different content: a contract that is a symlink is refused.
check_no_symlink() {
  if [ -L "$1" ]; then
    echo "Error: $1 is a symlink (to '$(readlink "$1")'). Nothing was changed." >&2
    echo "Klawde's Claude and Codex contracts cannot share one file; remove the symlink and re-run." >&2
    exit 1
  fi
}

# True when the destination can be written or created. BACKUP=yes also needs
# the directory writable, because the backup lands beside the file.
dest_writable() {
  local path="$1" dir
  dir="$(dirname "$path")"
  if [ -e "$path" ]; then
    [ -f "$path" ] || return 1
    [ -w "$path" ] || return 1
    if [ "${BACKUP:-}" = "yes" ] && [ ! -w "$dir" ]; then return 1; fi
    return 0
  fi
  while [ ! -e "$dir" ]; do dir="$(dirname "$dir")"; done
  [ -d "$dir" ] && [ -w "$dir" ]
}

# Preflight problems are collected and reported together before the first write.
PREFLIGHT_BAD=0
bad_dest() {
  echo "Error: $1" >&2
  PREFLIGHT_BAD=1
}
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

# Rewrite a template for the Codex layout: retitle the contract, retarget the
# command and schema paths, and turn slash invocations into $skills.
rewrite_codex() {
  sed -e '1s/^# CLAUDE\.md$/# AGENTS.md/' \
      -e 's/^## Slash Commands$/## Skills/' \
      -e 's#`\.claude/commands/\([A-Za-z_]*\)\.md`#`.agents/skills/\1/SKILL.md`#g' \
      -e 's#\.claude/changes-schema\.sql#.agents/changes-schema.sql#g' \
      -e 's#`/upgrade_klawde`#`$upgrade_klawde`#g' \
      -e 's#`/klawde`#`$klawde`#g' \
      -e 's#`/close`#`$close`#g' \
      -e 's|^# /upgrade_klawde: |# $upgrade_klawde: |' \
      -e 's|^# /klawde: |# $klawde: |' \
      -e 's|^# /close: |# $close: |' \
      "$1"
}

# A Codex skill: front matter, then the rewritten protocol.
build_skill_file() { # <src> <name> <description> <dst>
  local src="$1" name="$2" desc="$3" dst="$4"
  {
    printf -- '---\n'
    printf 'name: %s\n' "$name"
    printf 'description: "%s"\n' "$desc"
    printf -- '---\n\n'
    rewrite_codex "$src"
  } > "$dst"
}

KLAWDE_SKILL_DESC="Run only when explicitly invoked. Klawde entry protocol: read BRIEFING.md in full, guidelines.md if present, the last 5 changes.db log entries and the open tasks, creating the records if missing, then confirm readiness at session start."
CLOSE_SKILL_DESC="Run only when explicitly invoked. Klawde close protocol: append what was done to the changes.db log, clear completed tasks, and update BRIEFING.md where this session changed what it states."
UPGRADE_KLAWDE_SKILL_DESC="Run only when explicitly invoked, after upgrade.sh. Klawde record migration: bring an older changes.db to the current schema and rewrite BRIEFING.md to its four fields, with the user approving each step."

source_version() {
  git -C "$SCRIPT_DIR" log -1 --format='%h %ad' --date=short 2>/dev/null || echo unknown
}
