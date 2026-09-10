#!/bin/bash
# Regression suite for setup.sh and upgrade.sh. Run after editing either
# script (or the templates): tests/verify.sh
#
# Builds throwaway target projects in a temp directory and runs the real
# scripts against them, covering the happy paths, the CHANGES.md migration,
# and every guarded failure mode: closed stdin at prompts, symlinked
# contracts and files, unwritable or blocked destinations, foreign AGENTS.md
# confirmation, layout detection, partial-run reporting, and bash 3.2.
KLAWDE="$(cd "$(dirname "$0")/.." && pwd)"
BASE="$(mktemp -d)"
cleanup() { chmod -R u+w "$BASE" 2>/dev/null; rm -rf "$BASE"; }
trap cleanup EXIT

pass=0; fail=0
ok()  { pass=$((pass+1)); echo "PASS: $1"; }
bad() { fail=$((fail+1)); echo "FAIL: $1"; }
check() { # check <desc> <cond...>
  local desc="$1"; shift
  if "$@"; then ok "$desc"; else bad "$desc"; fi
}
grepq()  { grep -q "$1" "$2"; }
ngrepq() { ! grep -q "$1" "$2"; }

mkfx() { # mkfx <name> -> creates a stale claude install fixture
  local d="$BASE/$1"
  mkdir -p "$d/.claude/commands"
  echo "OLD CONTRACT" > "$d/CLAUDE.md"
  for f in klawde.md close.md; do echo "OLD $f" > "$d/.claude/commands/$f"; done
  # The retired lean command, as klawde shipped it: recognised by its title line.
  printf '# /klaude: Entry Protocol (lean)\nOLD klaude.md\n' > "$d/.claude/commands/klaude.md"
  echo "$d"
}
# A faithful changes.db of an earlier schema version, built by removing from a
# fresh install exactly what each later version added. Dropping the concerns
# table drops its own triggers with it.
mk_old_db() { # mk_old_db <path> <version 1|2|3|4|5>
  sqlite3 "$1" < "$KLAWDE/template/changes-schema.sql"
  sqlite3 "$1" 'DROP TRIGGER legacy_summaries_no_replace; DROP TRIGGER entries_refs_one_line; DROP TRIGGER concerns_immutable_text; PRAGMA user_version = 5;'
  sed -n '/^CREATE TRIGGER concerns_immutable_text /,/END;/p' "$KLAWDE/template/changes-schema.sql" \
    | sed 's/NEW.ref_serial IS NOT OLD.ref_serial/COALESCE(NEW.ref_serial, -1) <> COALESCE(OLD.ref_serial, -1)/' | sqlite3 "$1"
  if [ "$2" -eq 5 ]; then return; fi
  sqlite3 "$1" 'DROP TRIGGER entries_one_line; DROP TRIGGER concerns_one_line; DROP TRIGGER concerns_resolution_one_line; DROP TRIGGER areas_name_plain; PRAGMA user_version = 4;'
  if [ "$2" -le 3 ]; then sqlite3 "$1" 'DROP TRIGGER concerns_no_backfill; DROP TRIGGER concerns_well_formed; DROP TRIGGER concerns_resolution_well_formed; DROP TRIGGER areas_name_clean; DROP TRIGGER legacy_summaries_no_update; DROP TRIGGER legacy_summaries_no_delete; DROP TRIGGER entries_well_formed; PRAGMA user_version = 3;'; fi
  if [ "$2" -le 2 ]; then sqlite3 "$1" 'DROP VIEW concern_lines; DROP TABLE concerns; DROP TRIGGER entries_no_replace; PRAGMA user_version = 2;'; fi
  if [ "$2" -le 1 ]; then sqlite3 "$1" 'DROP TRIGGER areas_no_update; DROP TRIGGER entries_no_backfill; PRAGMA user_version = 1;'; fi
}

echo "=== S1: foreign AGENTS.md + .claude/commands, no root CLAUDE.md ==="
d="$BASE/s1"; mkdir -p "$d/.claude/commands"
echo "OLD close" > "$d/.claude/commands/close.md"
echo "foreign agents file" > "$d/AGENTS.md"
out="$(cd "$d" && printf '\nn\ny\n' | "$KLAWDE/upgrade.sh" 2>&1)"; rc=$?
echo "$out" > "$BASE/s1.out"
check "S1 detection offers 'both'" grepq 'Enter for detected: both' "$BASE/s1.out"
check "S1 foreign-AGENTS.md confirmation asked" grepq 'Overwrite AGENTS.md' "$BASE/s1.out"
check "S1 exit 0 after confirming" test "$rc" -eq 0
check "S1 close.md upgraded" grepq 'Close Protocol' "$d/.claude/commands/close.md"
check "S1 AGENTS.md overwritten after y" grepq '# AGENTS.md' "$d/AGENTS.md"

echo "=== S1b: --codex on foreign AGENTS.md proceeds only on y, notes skipped Claude install ==="
d="$BASE/s1b"; mkdir -p "$d/.claude/commands"
echo "OLD close" > "$d/.claude/commands/close.md"
echo "foreign agents file" > "$d/AGENTS.md"
out="$(cd "$d" && printf 'y\n' | "$KLAWDE/upgrade.sh" --codex --no-backup 2>&1)"; rc=$?
echo "$out" > "$BASE/s1b.out"
check "S1b layout-skip note shown" grepq 'Claude install was detected but is NOT being upgraded' "$BASE/s1b.out"
check "S1b exit 0" test "$rc" -eq 0
check "S1b close.md untouched (deliberate codex-only)" grepq 'OLD close' "$d/.claude/commands/close.md"
check "S1b AGENTS.md overwritten after y" grepq '# AGENTS.md' "$d/AGENTS.md"

echo "=== S1c: declining foreign AGENTS.md under --both falls back to claude-only ==="
d="$(mkfx s1c)"; echo "foreign agents file" > "$d/AGENTS.md"
out="$(cd "$d" && printf 'n\n' | "$KLAWDE/upgrade.sh" --both --no-backup 2>&1)"; rc=$?
echo "$out" > "$BASE/s1c.out"
check "S1c exit 0" test "$rc" -eq 0
check "S1c fallback message shown" grepq 'upgrading the Claude layout only' "$BASE/s1c.out"
check "S1c AGENTS.md untouched" grepq 'foreign agents file' "$d/AGENTS.md"
check "S1c claude layout upgraded" cmp -s "$KLAWDE/template/close.md" "$d/.claude/commands/close.md"
check "S1c no .agents/ created" bash -c "! test -e '$d/.agents'"

echo "=== S1d: foreign AGENTS.md cannot be confirmed non-interactively ==="
d="$BASE/s1d"; mkdir -p "$d"; echo "foreign agents file" > "$d/AGENTS.md"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --codex --no-backup < /dev/null 2>&1)"; rc=$?
echo "$out" > "$BASE/s1d.out"
check "S1d exit nonzero" test "$rc" -ne 0
check "S1d explicit cannot-confirm error" grepq 'cannot confirm overwriting' "$BASE/s1d.out"
check "S1d AGENTS.md untouched" grepq 'foreign agents file' "$d/AGENTS.md"
out="$(cd "$d" && printf 'n\n' | "$KLAWDE/upgrade.sh" --codex --no-backup 2>&1)"; rc=$?
check "S1d declining codex-only aborts nonzero, nothing changed" \
  bash -c "test $rc -ne 0 && grep -q 'foreign agents file' '$d/AGENTS.md'"

echo "=== S2: AGENTS.md -> CLAUDE.md symlink aborts before any write ==="
d="$(mkfx s2)"; ln -s CLAUDE.md "$d/AGENTS.md"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --both --no-backup 2>&1)"; rc=$?
echo "$out" > "$BASE/s2.out"
check "S2 exit nonzero" test "$rc" -ne 0
check "S2 symlink error shown" grepq 'is a symlink' "$BASE/s2.out"
check "S2 CLAUDE.md untouched" grepq 'OLD CONTRACT' "$d/CLAUDE.md"
check "S2 close.md untouched" grepq 'OLD close.md' "$d/.claude/commands/close.md"

echo "=== S2b: symlinked command file refused in preflight ==="
d="$(mkfx s2b)"
echo "elsewhere" > "$d/other.md"
rm "$d/.claude/commands/close.md"; ln -s ../../other.md "$d/.claude/commands/close.md"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
echo "$out" > "$BASE/s2b.out"
check "S2b exit nonzero" test "$rc" -ne 0
check "S2b symlink named in error" grepq 'close.md is a symlink' "$BASE/s2b.out"
check "S2b CLAUDE.md untouched" grepq 'OLD CONTRACT' "$d/CLAUDE.md"

echo "=== S3: closed stdin fails loudly, nothing written ==="
d="$(mkfx s3)"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" < /dev/null 2>&1)"; rc=$?
echo "$out" > "$BASE/s3.out"
check "S3 no-flags exit nonzero" test "$rc" -ne 0
check "S3 explicit stdin error" grepq 'stdin closed at a prompt' "$BASE/s3.out"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude < /dev/null 2>&1)"; rc=$?
echo "$out" > "$BASE/s3b.out"
check "S3 --claude (backup prompt) exit nonzero" test "$rc" -ne 0
check "S3 --claude explicit stdin error" grepq 'stdin closed at a prompt' "$BASE/s3b.out"
check "S3 CLAUDE.md untouched" grepq 'OLD CONTRACT' "$d/CLAUDE.md"
check "S3 close.md untouched" grepq 'OLD close.md' "$d/.claude/commands/close.md"

echo "=== S4: unwritable destinations fail preflight before any write ==="
d="$(mkfx s4)"; chmod 444 "$d/.claude/commands/close.md"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
echo "$out" > "$BASE/s4.out"
check "S4 exit nonzero" test "$rc" -ne 0
check "S4 error names close.md" grepq 'cannot write.*close.md' "$BASE/s4.out"
check "S4 CLAUDE.md untouched (preflight ran before writes)" grepq 'OLD CONTRACT' "$d/CLAUDE.md"
chmod 644 "$d/.claude/commands/close.md"
d="$(mkfx s4b)"; chmod 555 "$d/.claude/commands"   # --backup needs the dir writable too
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --backup 2>&1)"; rc=$?
check "S4b backup-dir preflight fails, CLAUDE.md untouched" \
  bash -c "test $rc -ne 0 && grep -q 'OLD CONTRACT' '$d/CLAUDE.md'"
chmod 755 "$d/.claude/commands"

echo "=== S4c: .claude existing as a regular file is caught in preflight ==="
d="$BASE/s4c"; mkdir -p "$d"; echo "OLD CONTRACT" > "$d/CLAUDE.md"; echo "i am a file" > "$d/.claude"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
echo "$out" > "$BASE/s4c.out"
check "S4c exit nonzero" test "$rc" -ne 0
check "S4c blocked-parent error shown" grepq 'blocked by a non-directory parent' "$BASE/s4c.out"
check "S4c CLAUDE.md untouched" grepq 'OLD CONTRACT' "$d/CLAUDE.md"

echo "=== S4d: legacy init.md in an unwritable directory is caught in preflight ==="
d="$(mkfx s4d)"; printf '# /init — Entry Protocol\nOLD init\n' > "$d/.claude/commands/init.md"; chmod 555 "$d/.claude/commands"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
echo "$out" > "$BASE/s4d.out"
check "S4d exit nonzero" test "$rc" -ne 0
check "S4d cannot-remove error names init.md" grepq 'cannot remove.*init.md' "$BASE/s4d.out"
check "S4d CLAUDE.md untouched" grepq 'OLD CONTRACT' "$d/CLAUDE.md"
chmod 755 "$d/.claude/commands"

echo "=== S5: happy paths ==="
d="$(mkfx s5)"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
echo "$out" > "$BASE/s5.out"
check "S5 claude upgrade exit 0" test "$rc" -eq 0
check "S5 CLAUDE.md matches template" cmp -s "$KLAWDE/template/CLAUDE.md" "$d/CLAUDE.md"
check "S5 close.md matches template" cmp -s "$KLAWDE/template/close.md" "$d/.claude/commands/close.md"
check "S5 retired klaude.md removed" bash -c "! test -f '$d/.claude/commands/klaude.md'"
check "S5 schema installed" cmp -s "$KLAWDE/template/changes-schema.sql" "$d/.claude/changes-schema.sql"
check "S5 source version printed" grepq 'source version: ' "$BASE/s5.out"
check "S5 restart note printed" grepq 'restart it' "$BASE/s5.out"
check "S5 Code craft restore note printed for a contract without the section" grepq 'no Code craft section' "$BASE/s5.out"
d="$BASE/s5c"; mkdir -p "$d/.agents/skills"; echo "OLD AGENTS" > "$d/AGENTS.md"
echo "OLD schema" > "$d/.agents/changes-schema.sql"   # klawde artifact: no foreign-AGENTS.md prompt
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --codex --no-backup 2>&1)"; rc=$?
echo "$out" > "$BASE/s5c.out"
check "S5 codex upgrade exit 0" test "$rc" -eq 0
check "S5 AGENTS.md retitled" grepq '# AGENTS.md' "$d/AGENTS.md"
check "S5 codex skill written" grepq 'Close Protocol' "$d/.agents/skills/close/SKILL.md"
check "S5 codex: no foreign prompt (artifacts present)" ngrepq 'Overwrite AGENTS.md' "$BASE/s5c.out"
check "S5 codex: no restart note" ngrepq 'restart it' "$BASE/s5c.out"
d="$(mkfx s5b)"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --both --no-backup 2>&1)"; rc=$?
check "S5 both upgrade exit 0" test "$rc" -eq 0
check "S5 both: CLAUDE.md is claude variant" grepq '# CLAUDE.md' "$d/CLAUDE.md"
check "S5 both: AGENTS.md is codex variant" grepq '# AGENTS.md' "$d/AGENTS.md"
d="$(mkfx s5d)"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --backup 2>&1)"; rc=$?
n="$(ls "$d" "$d/.claude/commands" | grep -c '\.bak\.')"
check "S5 --backup completes with .bak files" bash -c "test $rc -eq 0 && test $n -ge 4"

echo "=== S5e: legacy klaude.md alone counts as Claude detection evidence, then is retired ==="
d="$BASE/s5e"; mkdir -p "$d/.claude/commands"; printf '# /klaude: Entry Protocol (lean)\nOLD klaude\n' > "$d/.claude/commands/klaude.md"
out="$(cd "$d" && printf '\nn\n' | "$KLAWDE/upgrade.sh" 2>&1)"; rc=$?
echo "$out" > "$BASE/s5e.out"
check "S5e detected claude" grepq 'Enter for detected: claude' "$BASE/s5e.out"
check "S5e exit 0" test "$rc" -eq 0
check "S5e retirement message shown" grepq 'Removed retired .claude/commands/klaude.md' "$BASE/s5e.out"
check "S5e klaude.md removed, klawde.md installed" \
  bash -c "! test -f '$d/.claude/commands/klaude.md' && cmp -s '$KLAWDE/template/klawde.md' '$d/.claude/commands/klawde.md'"

echo "=== S5g: legacy compresschanges.md alone counts as Claude detection evidence, then is retired ==="
d="$BASE/s5g"; mkdir -p "$d/.claude/commands"
printf '# /compresschanges — Compact CHANGES.md History\nOLD compresschanges\n' > "$d/.claude/commands/compresschanges.md"
out="$(cd "$d" && printf '\nn\n' | "$KLAWDE/upgrade.sh" 2>&1)"; rc=$?
echo "$out" > "$BASE/s5g.out"
check "S5g detected claude" grepq 'Enter for detected: claude' "$BASE/s5g.out"
check "S5g exit 0" test "$rc" -eq 0
check "S5g compresschanges.md retired" \
  bash -c "grep -q 'Removed retired .claude/commands/compresschanges.md' '$BASE/s5g.out' && ! test -f '$d/.claude/commands/compresschanges.md'"

echo "=== S6: setup.sh fresh installs + guards ==="
d="$BASE/s6"; mkdir -p "$d"
out="$(cd "$d" && "$KLAWDE/setup.sh" --both 2>&1)"; rc=$?
echo "$out" > "$BASE/s6.out"
check "S6 fresh --both exit 0" test "$rc" -eq 0
check "S6 CLAUDE.md matches template" cmp -s "$KLAWDE/template/CLAUDE.md" "$d/CLAUDE.md"
check "S6 codex skill written" grepq 'Close Protocol' "$d/.agents/skills/close/SKILL.md"
check "S6 source version printed" grepq 'source version: ' "$BASE/s6.out"
d="$BASE/s6b"; mkdir -p "$d"
out="$(cd "$d" && "$KLAWDE/setup.sh" < /dev/null 2>&1)"; rc=$?
check "S6 setup no-flags EOF fails loudly" bash -c "test $rc -ne 0 && echo \"$out\" | grep -q 'stdin closed at a prompt'"
d="$BASE/s6c"; mkdir -p "$d"; echo MINE > "$d/CLAUDE.md"
out="$(cd "$d" && "$KLAWDE/setup.sh" --claude < /dev/null 2>&1)"; rc=$?
echo "$out" > "$BASE/s6c.out"
check "S6 setup EOF at overwrite prompt fails loudly" bash -c "test $rc -ne 0 && grep -q 'stdin closed at a prompt' '$BASE/s6c.out'"
check "S6 partial-install trap message shown" grepq 'did NOT complete' "$BASE/s6c.out"
check "S6 existing CLAUDE.md untouched" grepq 'MINE' "$d/CLAUDE.md"
d="$BASE/s6d"; mkdir -p "$d"; echo x > "$d/AGENTS.md"; ln -s AGENTS.md "$d/CLAUDE.md"
out="$(cd "$d" && "$KLAWDE/setup.sh" --claude 2>&1)"; rc=$?
check "S6 setup rejects symlinked CLAUDE.md" bash -c "test $rc -ne 0 && echo \"$out\" | grep -q 'is a symlink'"
d="$BASE/s6e"; mkdir -p "$d"; echo MINE > "$d/CLAUDE.md"
out="$(cd "$d" && printf 'n\n' | "$KLAWDE/setup.sh" --claude 2>&1)"; rc=$?
check "S6 declining one overwrite still installs the rest" \
  bash -c "test $rc -eq 0 && grep -q MINE '$d/CLAUDE.md' && test -f '$d/.claude/commands/close.md'"
d="$BASE/s6f"; mkdir -p "$d"
out="$(cd "$d" && printf '2\n' | "$KLAWDE/setup.sh" 2>&1)"; rc=$?
check "S6 interactive '2' installs codex" bash -c "test $rc -eq 0 && test -f '$d/.agents/skills/close/SKILL.md'"

echo "=== S7: CHANGES.md migration ==="
d="$BASE/s7"; mkdir -p "$d"
cat > "$d/CHANGES.md" <<'EOF'
2025-01-10: set up the project
2025-02-01 [code] added the parser
2025-03-05 001 [code] (core) fixed the tokenizer refs=abc
2025-03-06 002 [decision] (core) added streaming supersedes=1
EOF
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
echo "$out" > "$BASE/s7.out"
n="$(sqlite3 -readonly "$d/changes.db" 'SELECT count(*) FROM entries;' 2>/dev/null)"
check "S7 migration exit 0" test "$rc" -eq 0
check "S7 migrated 4 + 1 doc entry" test "$n" = "5"
check "S7 CHANGES.md renamed" test -f "$d/CHANGES.md.migrated"
check "S7 link imported" test "$(sqlite3 -readonly "$d/changes.db" 'SELECT count(*) FROM links;')" = "1"
check "S7 post-upgrade check printed" grepq 'changes.db checked: integrity ok' "$BASE/s7.out"

echo "=== S7d: markdown on the brief's Areas line does not leak into the vocabulary ==="
d="$BASE/s7d"; mkdir -p "$d"
printf -- '- Areas: `import`, **cli**, _api_, order_import.\n' > "$d/BRIEFING.md"
echo '2025-03-05 001 [code] (import) x' > "$d/CHANGES.md"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
echo "$out" > "$BASE/s7d.out"
areas="$(sqlite3 -readonly "$d/changes.db" 'SELECT name FROM areas ORDER BY name;' 2>/dev/null | tr '\n' ' ')"
check "S7d exit 0" test "$rc" -eq 0
check "S7d seeded areas are clean names" test "$areas" = "api cli import order_import "
check "S7d seeded list printed" grepq 'areas (api cli import order_import)' "$BASE/s7d.out"

echo "=== S7e: a repeated serial is refused in preflight, nothing written ==="
d="$(mkfx s7e)"
printf '2025-03-05 001 [code] (-) first\r\n2025-03-06 001 [code] (-) second\n' > "$d/CHANGES.md"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
echo "$out" > "$BASE/s7e.out"
check "S7e exit nonzero" test "$rc" -ne 0
check "S7e repeated serial named" grepq 'repeats serial(s) 1;' "$BASE/s7e.out"
check "S7e CLAUDE.md untouched, no changes.db" bash -c "grep -q 'OLD CONTRACT' '$d/CLAUDE.md' && ! test -e '$d/changes.db'"

echo "=== S7f: a link that does not point backwards is skipped with a truthful summary ==="
d="$BASE/s7f"; mkdir -p "$d"
printf '2025-03-05 001 [code] (-) a\n2025-03-06 002 [note] (-) b closes=2\n' > "$d/CHANGES.md"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
echo "$out" > "$BASE/s7f.out"
check "S7f exit 0" test "$rc" -eq 0
check "S7f bad-link warning shown" grepq 'does not point backwards' "$BASE/s7f.out"
check "S7f summary no longer blames a missing serial" \
  bash -c "grep -q 'could not place' '$BASE/s7f.out' && ! grep -q 'no longer contains' '$BASE/s7f.out'"

echo "=== S7g: markdown or padding on an entry's area is cleaned exactly as the seed is ==="
d="$BASE/s7g"; mkdir -p "$d"
printf '2025-03-05 001 [code] (`import`) markdown area\n2025-03-06 002 [code] ( core ) padded area\n' > "$d/CHANGES.md"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
echo "$out" > "$BASE/s7g.out"
check "S7g exit 0" test "$rc" -eq 0
check "S7g seeded areas clean" test "$(sqlite3 -readonly "$d/changes.db" 'SELECT name FROM areas ORDER BY name;' 2>/dev/null | tr '\n' ' ')" = "core import "
check "S7g entries carry the clean area" test "$(sqlite3 -readonly "$d/changes.db" 'SELECT area FROM entries WHERE serial IN (1,2) ORDER BY serial;' 2>/dev/null | tr '\n' ' ')" = "import core "

echo "=== S7h: an impossible legacy date is refused before any write, naming the entry ==="
d="$(mkfx s7h)"
printf '2025-06-31 001 [note] (-) june has thirty days\n' > "$d/CHANGES.md"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
echo "$out" > "$BASE/s7h.out"
check "S7h exit nonzero" test "$rc" -ne 0
check "S7h refused entry named with its date" grepq "Refused: INSERT INTO entries .*'2025-06-31'" "$BASE/s7h.out"
check "S7h reason names the real-date rule" grepq 'real date' "$BASE/s7h.out"
check "S7h nothing written" bash -c "grep -q 'OLD CONTRACT' '$d/CLAUDE.md' && ! test -e '$d/changes.db' && test -f '$d/CHANGES.md'"

echo "=== S7i: a comma-separated link list links every target ==="
d="$BASE/s7i"; mkdir -p "$d"
printf '2025-03-05 001 [code] (-) a\n2025-03-06 002 [code] (-) b\n2025-03-07 003 [decision] (-) c supersedes=1,2\n' > "$d/CHANGES.md"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
check "S7i exit 0" test "$rc" -eq 0
check "S7i both links imported" test "$(sqlite3 -readonly "$d/changes.db" 'SELECT count(*) FROM links;' 2>/dev/null)" = "2"

echo "=== S7j: a normalized CHANGES.md is backed up only at commit, and .migrated holds the normalized form ==="
d="$BASE/s7j"; mkdir -p "$d"
printf '2025-01-10: old style\r\n' > "$d/CHANGES.md"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --backup 2>&1)"; rc=$?
check "S7j exit 0" test "$rc" -eq 0
check "S7j original backed up, .migrated normalized, CHANGES.md gone" \
  bash -c "ls '$d' | grep -q 'CHANGES.md.bak' && grep -q '\[note\]' '$d/CHANGES.md.migrated' && ! test -e '$d/CHANGES.md'"

echo "=== S7b: migration destinations are preflighted ==="
d="$BASE/s7b"; mkdir -p "$d"
echo '2025-03-05 001 [code] (core) fixed the tokenizer' > "$d/CHANGES.md"
echo 'node_modules' > "$d/.gitignore"; chmod 444 "$d/.gitignore"; echo "OLD CONTRACT" > "$d/CLAUDE.md"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
check "S7b read-only .gitignore fails preflight, CLAUDE.md untouched" \
  bash -c "test $rc -ne 0 && echo \"$out\" | grep -q 'cannot write.*gitignore' && grep -q 'OLD CONTRACT' '$d/CLAUDE.md'"
chmod 644 "$d/.gitignore"
d="$BASE/s7c"; mkdir -p "$d"; echo "OLD CONTRACT" > "$d/CLAUDE.md"
echo '2025-03-05 001 [code] (core) fixed the tokenizer' > "$d/CHANGES.md"
chmod 555 "$d"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
check "S7c read-only project root fails preflight (changes.db not creatable)" \
  bash -c "test $rc -ne 0 && echo \"$out\" | grep -q 'cannot write.*changes.db'"
chmod 755 "$d"

echo "=== S8: changes.db states ==="
d="$(mkfx s8)"; echo "not a database" > "$d/changes.db"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
echo "$out" > "$BASE/s8.out"
check "S8 garbage changes.db caught in preflight" grepq 'not a readable SQLite database' "$BASE/s8.out"
check "S8 exit nonzero, CLAUDE.md untouched" bash -c "test $rc -ne 0 && grep -q 'OLD CONTRACT' '$d/CLAUDE.md'"
d="$(mkfx s8b)"
mk_old_db "$d/changes.db" 1
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
check "S8b v1 db upgraded to v6 in place" \
  bash -c "test $rc -eq 0 && test \"\$(sqlite3 -readonly '$d/changes.db' 'PRAGMA user_version;')\" = 6"
check "S8b v1 path also gains the entries no-replace guard" \
  test "$(sqlite3 -readonly "$d/changes.db" "SELECT count(*) FROM sqlite_master WHERE name='entries_no_replace';")" = "1"
d="$(mkfx s8c)"
sqlite3 "$d/changes.db" < "$KLAWDE/template/changes-schema.sql"
chmod 444 "$d/changes.db"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
check "S8c read-only current-version db does not block the upgrade" test "$rc" -eq 0
chmod 644 "$d/changes.db"
d="$(mkfx s8d)"
mk_old_db "$d/changes.db" 1
chmod 444 "$d/changes.db"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
check "S8d read-only v1 db fails preflight, CLAUDE.md untouched" \
  bash -c "test $rc -ne 0 && echo \"$out\" | grep -q 'cannot write.*changes.db' && grep -q 'OLD CONTRACT' '$d/CLAUDE.md'"
chmod 644 "$d/changes.db"

echo "=== S8f: a changes.db that is not a klawde log is refused in preflight ==="
d="$(mkfx s8f)"; : > "$d/changes.db"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
echo "$out" > "$BASE/s8f.out"
check "S8f zero-byte changes.db refused" bash -c "test $rc -ne 0 && grep -q 'not a klawde log' '$BASE/s8f.out'"
check "S8f CLAUDE.md untouched" grepq 'OLD CONTRACT' "$d/CLAUDE.md"
d="$(mkfx s8g)"; sqlite3 "$d/changes.db" 'CREATE TABLE t(x);'
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
echo "$out" > "$BASE/s8g.out"
check "S8g foreign SQLite file refused" bash -c "test $rc -ne 0 && grep -q 'not a klawde log' '$BASE/s8g.out'"
check "S8g CLAUDE.md untouched, foreign db intact" \
  bash -c "grep -q 'OLD CONTRACT' '$d/CLAUDE.md' && test \"\$(sqlite3 -readonly '$d/changes.db' \"SELECT count(*) FROM sqlite_master WHERE name='t';\")\" = 1"
d="$(mkfx s8h)"; mkdir "$d/changes.db"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
echo "$out" > "$BASE/s8h.out"
check "S8h directory named changes.db refused" bash -c "test $rc -ne 0 && grep -q 'not a regular file' '$BASE/s8h.out'"
check "S8h CLAUDE.md untouched" grepq 'OLD CONTRACT' "$d/CLAUDE.md"

echo "=== S8e: an entry the schema refuses stops the upgrade before any write, naming the entry ==="
d="$(mkfx s8e)"
echo '2025-03-05 001 [badtype] (core) entry with a type the schema refuses' > "$d/CHANGES.md"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
echo "$out" > "$BASE/s8e.out"
check "S8e exit nonzero" test "$rc" -ne 0
check "S8e nothing-changed message shown" grepq 'Nothing was changed' "$BASE/s8e.out"
check "S8e refused entry named" grepq "Refused: INSERT INTO entries .*'badtype'" "$BASE/s8e.out"
check "S8e no partial-upgrade claim" ngrepq 'may be partially updated' "$BASE/s8e.out"
check "S8e CLAUDE.md untouched, no changes.db, CHANGES.md intact" \
  bash -c "grep -q 'OLD CONTRACT' '$d/CLAUDE.md' && ! test -e '$d/changes.db' && test -f '$d/CHANGES.md' && ! test -e '$d/CHANGES.md.migrated'"

echo "=== S9: bash 3.2 compatibility (/bin/bash on macOS) ==="
d="$(mkfx s9)"
out="$(cd "$d" && /bin/bash "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
check "S9 upgrade under /bin/bash exit 0" test "$rc" -eq 0
check "S9 close.md upgraded" cmp -s "$KLAWDE/template/close.md" "$d/.claude/commands/close.md"
d="$BASE/s9b"; mkdir -p "$d"
out="$(cd "$d" && /bin/bash "$KLAWDE/setup.sh" --claude 2>&1)"; rc=$?
check "S9 setup under /bin/bash exit 0" test "$rc" -eq 0

echo "=== S10: retired Codex skills are recognised by their front matter; nothing outside the project is touched ==="
d="$BASE/s10"; mkdir -p "$d/.agents/skills/klawde" "$d/.agents/skills/klaude" "$d/.agents/skills/compresschanges"
echo "OLD SKILL" > "$d/.agents/skills/klawde/SKILL.md"; echo "OLD AGENTS" > "$d/AGENTS.md"
printf -- '---\nname: klaude\ndescription: "old lean skill"\n---\n\nOLD LEAN SKILL\n' > "$d/.agents/skills/klaude/SKILL.md"
# Same directory name as a retired skill, but not klawde's front matter: must survive.
printf -- '---\nname: my-compressor\ndescription: "mine"\n---\n\nmy own skill that mentions changes.db and BRIEFING.md\n' > "$d/.agents/skills/compresschanges/SKILL.md"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --codex --no-backup 2>&1)"; rc=$?
echo "$out" > "$BASE/s10.out"
check "S10 exit 0" test "$rc" -eq 0
check "S10 klawde skill counts as artifact: no foreign prompt" ngrepq 'Overwrite AGENTS.md' "$BASE/s10.out"
check "S10 retired klaude skill removed with its directory" \
  bash -c "grep -q 'Removed retired .agents/skills/klaude/SKILL.md' '$BASE/s10.out' && ! test -e '$d/.agents/skills/klaude'"
check "S10 a same-named skill without klawde's front matter is left in place and reported" \
  bash -c "grep -q 'my own skill' '$d/.agents/skills/compresschanges/SKILL.md' && grep -q 'Left retired .agents/skills/compresschanges/SKILL.md in place' '$BASE/s10.out'"
check "S10 no prompt retirement anywhere in the script" ngrepq 'prompts/' "$KLAWDE/upgrade.sh"

echo "=== S11: foreign .agents/skills does not pass for a klawde install ==="
d="$BASE/s11"; mkdir -p "$d/.agents/skills/deploy"
echo "other tool skill" > "$d/.agents/skills/deploy/SKILL.md"
echo "foreign agents file" > "$d/AGENTS.md"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --codex --no-backup < /dev/null 2>&1)"; rc=$?
echo "$out" > "$BASE/s11.out"
check "S11 non-interactive overwrite refused" test "$rc" -ne 0
check "S11 cannot-confirm error shown" grepq 'cannot confirm overwriting' "$BASE/s11.out"
check "S11 AGENTS.md untouched" grepq 'foreign agents file' "$d/AGENTS.md"
out="$(cd "$d" && printf 'y\n' | "$KLAWDE/upgrade.sh" --codex --no-backup 2>&1)"; rc=$?
check "S11 interactive y proceeds" bash -c "test $rc -eq 0 && grep -q '# AGENTS.md' '$d/AGENTS.md'"
check "S11 foreign skill untouched" grepq 'other tool skill' "$d/.agents/skills/deploy/SKILL.md"

echo "=== S12: CHANGES.md itself is preflighted (read-only, symlink) ==="
d="$(mkfx s12)"; echo '2025-01-10: legacy' > "$d/CHANGES.md"; chmod 444 "$d/CHANGES.md"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
echo "$out" > "$BASE/s12.out"
check "S12 read-only CHANGES.md fails preflight" bash -c "test $rc -ne 0 && grep -q 'cannot write.*CHANGES.md' '$BASE/s12.out'"
check "S12 CLAUDE.md untouched" grepq 'OLD CONTRACT' "$d/CLAUDE.md"
chmod 644 "$d/CHANGES.md"
d="$(mkfx s12b)"; echo '2025-01-10: legacy' > "$d/real-log.md"; ln -s real-log.md "$d/CHANGES.md"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
check "S12b symlinked CHANGES.md refused, CLAUDE.md untouched" \
  bash -c "test $rc -ne 0 && echo \"$out\" | grep -q 'CHANGES.md is a symlink' && grep -q 'OLD CONTRACT' '$d/CLAUDE.md'"

echo "=== S13: read-only legacy init.md in a writable dir is removed cleanly ==="
d="$(mkfx s13)"; printf '# /init — Entry Protocol\nOLD init\n' > "$d/.claude/commands/init.md"; chmod 444 "$d/.claude/commands/init.md"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup < /dev/null 2>&1)"; rc=$?
echo "$out" > "$BASE/s13.out"
check "S13 exit 0" test "$rc" -eq 0
check "S13 removal message truthful, file gone" \
  bash -c "grep -q 'Removed legacy' '$BASE/s13.out' && ! test -f '$d/.claude/commands/init.md'"

echo "=== S13b: a same-named command that is not klawde's is left in place, even when it talks about klawde's files ==="
d="$(mkfx s13b)"; echo "my own init command that reads changes.db and BRIEFING.md" > "$d/.claude/commands/init.md"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup < /dev/null 2>&1)"; rc=$?
echo "$out" > "$BASE/s13b.out"
check "S13b exit 0" test "$rc" -eq 0
check "S13b foreign init.md left in place and reported" \
  bash -c "grep -q 'Left legacy .claude/commands/init.md in place' '$BASE/s13b.out' && grep -q 'my own init command' '$d/.claude/commands/init.md'"
d="$BASE/s13c"; mkdir -p "$d/.claude/commands"; echo "my own init command about BRIEFING.md" > "$d/.claude/commands/init.md"
out="$(cd "$d" && printf '\n' | "$KLAWDE/upgrade.sh" 2>&1)"; rc=$?
check "S13c a foreign init.md alone is not detected as a klawde install" \
  bash -c "test $rc -ne 0 && echo \"$out\" | grep -q 'no existing install detected' && ! test -f '$d/CLAUDE.md'"

echo "=== S14: CRLF CHANGES.md is stripped before import ==="
d="$BASE/s14"; mkdir -p "$d"
printf '2025-03-05 001 [code] (core) crlf line refs=abc\r\n2025-01-01: old style\r\n' > "$d/CHANGES.md"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
echo "$out" > "$BASE/s14.out"
check "S14 exit 0" test "$rc" -eq 0
check "S14 strip message shown" grepq 'Stripped CRLF' "$BASE/s14.out"
check "S14 no CR reached the database" bash -c \
  "test \"\$(sqlite3 -readonly '$d/changes.db' \"SELECT count(*) FROM entries WHERE description LIKE '%'||char(13)||'%' OR coalesce(refs,'') LIKE '%'||char(13)||'%';\")\" = 0"
check "S14 both entries imported (+ doc entry)" \
  test "$(sqlite3 -readonly "$d/changes.db" 'SELECT count(*) FROM entries;')" = "3"

echo "=== S15: migration in a git repo appends to a no-trailing-newline .gitignore ==="
d="$BASE/s15"; mkdir -p "$d"; git -C "$d" init -q
printf 'node_modules' > "$d/.gitignore"
printf '2025-03-05 001 [code] (-) entry\n' > "$d/CHANGES.md"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
check "S15 .gitignore gains the entry on its own line" \
  bash -c "test $rc -eq 0 && grep -qx 'CHANGES.md.migrated' '$d/.gitignore' && grep -qx 'node_modules' '$d/.gitignore'"

echo "=== S16: setup.sh and upgrade.sh produce identical Codex layouts ==="
d1="$BASE/s16a"; d2="$BASE/s16b"; mkdir -p "$d1" "$d2"
(cd "$d1" && "$KLAWDE/setup.sh" --codex >/dev/null 2>&1)
(cd "$d2" && "$KLAWDE/upgrade.sh" --codex --no-backup < /dev/null >/dev/null 2>&1)
same=1
for f in AGENTS.md .agents/changes-schema.sql .agents/check-log.sh .agents/skills/klawde/SKILL.md \
         .agents/skills/close/SKILL.md; do
  cmp -s "$d1/$f" "$d2/$f" || same=0
done
check "S16 no drift between the duplicated codex writers" test "$same" -eq 1

echo "=== S21: the Codex rewrite leaves no Claude-only reference behind ==="
# rewrite_codex rewrites only backticked /klawde, /close and .claude/commands
# paths and the bare schema path; anything else survives verbatim into files
# where it is wrong. Every template must therefore stay inside those forms.
left=""
for f in "$d1/AGENTS.md" "$d1"/.agents/skills/*/SKILL.md "$d1/.agents/changes-schema.sql" "$d1/.agents/check-log.sh"; do
  # The rewritten skill paths contain /klawde/ and /close/ legitimately; drop
  # them before looking for anything the rewrite missed.
  hits="$(sed 's#\.agents/skills/[a-z]*/SKILL\.md##g' "$f" | grep -n -E '/klawde|/close|\.claude/|CLAUDE\.md' || true)"
  if [ -n "$hits" ]; then left="$left$f: $hits"$'\n'; fi
done
check "S21 no /klawde, /close, .claude/ or CLAUDE.md in the generated Codex files" test -z "$left"
if [ -n "$left" ]; then printf '%s' "$left"; fi

echo "=== S17: a changes.db from a newer klawde is refused ==="
d="$(mkfx s17)"
sqlite3 "$d/changes.db" < "$KLAWDE/template/changes-schema.sql"
sqlite3 "$d/changes.db" 'PRAGMA user_version = 99;'
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
echo "$out" > "$BASE/s17.out"
check "S17 exit nonzero" test "$rc" -ne 0
check "S17 newer-schema error shown" grepq 'newer than this checkout supports' "$BASE/s17.out"
check "S17 CLAUDE.md untouched" grepq 'OLD CONTRACT' "$d/CLAUDE.md"

echo "=== S18: the brief shape measurement shipped in the commands ==="
# /klawde step 8 and /close step 7 carry the same awk one-liner; it must be one
# command, and it must count what the protocols say it counts.
d="$BASE/s18"; mkdir -p "$d"
grep '^awk ' "$KLAWDE/template/klawde.md" > "$d/klawde.cmd"
grep '^awk ' "$KLAWDE/template/close.md"  > "$d/close.cmd"
check "S18 klawde.md carries exactly one measurement" test "$(wc -l < "$d/klawde.cmd")" -eq 1
check "S18 close.md carries exactly one measurement"  test "$(wc -l < "$d/close.cmd")" -eq 1
check "S18 both commands identical" cmp -s "$d/klawde.cmd" "$d/close.cmd"
# The expected shape comes from the brief template /klawde ships (its first
# fenced block), never from a list typed here: adding a field to the template
# must change this expectation by itself.
expected="Shape:"; sep=""; nfields=0
while IFS= read -r name; do
  expected="$expected$sep $name 1"; sep=","; nfields=$((nfields+1))
done <<EOF
$(awk '/^```markdown$/ { if (seen) exit; seen = 1; next } seen && /^```$/ { exit } seen' "$KLAWDE/template/klawde.md" | sed -n 's/^- \([^:]*\):.*/\1/p')
EOF
check "S18 the template carries eleven fields, as the protocols say" test "$nfields" -eq 11
cat > "$d/BRIEFING.md" <<'EOF'
# Briefing

- Purpose: CLI tool that syncs Shopify orders into the local ERP.
- Current scope: order import, retry queue, dry-run mode. No refunds yet.
- Key decisions: Postgres SKIP LOCKED over Redis (2026-05-12); single binary, no daemon.
- Non-goals: multi-tenant support, real-time sync.
- Areas: import, retry, cli, config.
- Breaking-change context: v0.4 renamed config key `shop_url` to `store_url`.
- Current focus: retry queue hardening.
- Next steps:
- Open questions: should dry-run write an audit file?
- Do-not-touch: `legacy/importer.pl` (production cron depends on its exact output).
- Environment quirks: Shopify sandbox throttles hard after ~50 req/min.
EOF
out="$(cd "$d" && /bin/bash "$d/close.cmd")"
check "S18 well-shaped brief measures all 1s in the template's field order" test "$out" = "$expected"
cat > "$d/BRIEFING.md" <<'EOF'
# Briefing

- Purpose: CLI tool that syncs Shopify orders into the local ERP.
- Current scope: order import, retry queue, dry-run mode. No refunds yet.
- Key decisions:
  - Postgres SKIP LOCKED over Redis (2026-05-12)
  - single binary, no daemon
- Non-goals: multi-tenant support, real-time sync.
- Areas: import, retry, cli, config.
- Breaking-change context: v0.4 renamed config key `shop_url` to `store_url`.
- Current focus: retry queue hardening.
- Current focus (2026-06-01): backoff cap.
- Next steps: add backoff cap; test double-delivery on restart.
  Also verify the retry table index.

- Open questions: should dry-run write an audit file?
- Do-not-touch: `legacy/importer.pl` (production cron depends on its exact output).
- Environment quirks: Shopify sandbox throttles hard after ~50 req/min.
EOF
out="$(cd "$d" && /bin/bash "$d/close.cmd")"
check "S18 sub-bullets counted" bash -c "case '$out' in *'Key decisions 3,'*) exit 0;; *) exit 1;; esac"
check "S18 continuation line counted" bash -c "case '$out' in *'Next steps 2,'*) exit 0;; *) exit 1;; esac"
check "S18 duplicate Current focus surfaces as a second name" bash -c "case '$out' in *'Current focus 1, Current focus (2026-06-01) 1,'*) exit 0;; *) exit 1;; esac"
check "S18 blank line between fields not counted" bash -c "case '$out' in *'Open questions 1,'*) exit 0;; *) exit 1;; esac"
# The user's own fields measure like any other; the protocols decide what to
# do with the number. A column-zero item that happens to hold a colon reads as
# a field name, and text after the last field counts into that field.
cat > "$d/BRIEFING.md" <<'EOF'
# Briefing

- Purpose: CLI tool that syncs Shopify orders into the local ERP.
- Current scope: order import, retry queue, dry-run mode. No refunds yet.
- Key decisions: Postgres SKIP LOCKED over Redis (2026-05-12); single binary, no daemon.
- Non-goals: multi-tenant support, real-time sync.
- Areas: import, retry, cli, config.
- Breaking-change context: v0.4 renamed config key `shop_url` to `store_url`.
- Current focus: retry queue hardening.
- Next steps: add backoff cap; test double-delivery on restart.
- Open questions:
  - should dry-run write an audit file?
  - should refunds land in v1?
- should we pick option A: or option B?
- Do-not-touch: `legacy/importer.pl` (production cron depends on its exact output).
- Environment quirks: Shopify sandbox throttles hard after ~50 req/min.

## Notes
Some text a session left after the last field.
EOF
out="$(cd "$d" && /bin/bash "$d/close.cmd")"
check "S18 a user field's sub-bullets are counted into it" bash -c "case '$out' in *'Open questions 3,'*) exit 0;; *) exit 1;; esac"
check "S18 a column-zero item with a colon measures as a foreign name" bash -c "case '$out' in *'should we pick option A 1,'*) exit 0;; *) exit 1;; esac"
check "S18 a section under a heading after the last field is reported as Trailing, not folded into the field" \
  bash -c "case '$out' in *'Environment quirks 1, Trailing 2'*) exit 0;; *) exit 1;; esac"
# Odd but common bullet spellings measure as the fields they are.
cat > "$d/BRIEFING.md" <<'EOF'
# Briefing

-  Purpose: two spaces after the dash.
* Current scope: asterisk bullet.
- Key decisions : space before the colon.
- Non-goals: x.
- Areas: x.
- Breaking-change context: x.
- Current focus: x.
- Next steps: x.
- Open questions: x?
- Do-not-touch: x.
- Environment quirks: x.
Wrapped text with no heading still counts into the last field.
EOF
out="$(cd "$d" && /bin/bash "$d/close.cmd")"
check "S18 two spaces after the dash still names the field" bash -c "case '$out' in *'Shape: Purpose 1,'*) exit 0;; *) exit 1;; esac"
check "S18 an asterisk bullet still names the field" bash -c "case '$out' in *'Current scope 1,'*) exit 0;; *) exit 1;; esac"
check "S18 a space before the colon is trimmed from the name" bash -c "case '$out' in *'Key decisions 1,'*) exit 0;; *) exit 1;; esac"
check "S18 unheaded text after the last field counts into it" bash -c "case '$out' in *'Environment quirks 2'*) exit 0;; *) exit 1;; esac"

echo "=== S19: older changes.db files gain the missing objects in place, matching a fresh install ==="
d="$(mkfx s19)"
mk_old_db "$d/changes.db" 2
# The fixtures must be what the protocols describe: v1 = 7 triggers, v2 = 9, v3 = 17.
tc() { sqlite3 -readonly "$1" "SELECT count(*) FROM sqlite_master WHERE type='trigger';"; }
check "S19 v2 fixture carries 9 triggers" test "$(tc "$d/changes.db")" = "9"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
echo "$out" > "$BASE/s19.out"
check "S19 exit 0" test "$rc" -eq 0
check "S19 upgraded to v6" test "$(sqlite3 -readonly "$d/changes.db" 'PRAGMA user_version;')" = "6"
check "S19 v3 message shown" grepq 'Upgraded the changes.db schema to v3' "$BASE/s19.out"
check "S19 v4 message shown" grepq 'Upgraded the changes.db schema to v4' "$BASE/s19.out"
check "S19 v5 message shown" grepq 'Upgraded the changes.db schema to v5' "$BASE/s19.out"
check "S19 post-upgrade check printed, nothing restored" \
  bash -c "grep -q 'changes.db checked: integrity ok' '$BASE/s19.out' && ! grep -q 'restored missing' '$BASE/s19.out'"
fresh="$BASE/s19-fresh.db"
sqlite3 "$fresh" < "$KLAWDE/template/changes-schema.sql"
q="SELECT name, replace(coalesce(sql,''), 'IF NOT EXISTS ', '') FROM sqlite_master WHERE name LIKE 'concern%' OR name = 'entries_no_replace' ORDER BY name;"
check "S19 in-place concern objects match the shipped schema" \
  bash -c "test \"\$(sqlite3 -readonly '$d/changes.db' \"$q\")\" = \"\$(sqlite3 -readonly '$fresh' \"$q\")\""
# The lifecycle the contract promises must actually be enforced by the upgraded db.
sqlite3 "$d/changes.db" "INSERT INTO entries (type,area,description) VALUES ('decision','-','s19 decision');"
sqlite3 "$d/changes.db" "INSERT INTO concerns (concern, ref_serial) VALUES ('s19 concern', 1);"
check "S19 delete refused" bash -c "! sqlite3 '$d/changes.db' 'DELETE FROM concerns;' 2>/dev/null"
check "S19 text edit refused" bash -c "! sqlite3 '$d/changes.db' \"UPDATE concerns SET concern='x' WHERE id=1;\" 2>/dev/null"
check "S19 unknown area refused" bash -c "! sqlite3 '$d/changes.db' \"INSERT INTO concerns (area, concern) VALUES ('nope','y');\" 2>/dev/null"
check "S19 dangling ref_serial refused" bash -c "! sqlite3 '$d/changes.db' \"INSERT INTO concerns (concern, ref_serial) VALUES ('z', 99);\" 2>/dev/null"
check "S19 resolve is one-way" bash -c "sqlite3 '$d/changes.db' \"UPDATE concerns SET resolved=date('now','localtime'), resolution='done' WHERE id=1;\" && ! sqlite3 '$d/changes.db' \"UPDATE concerns SET resolved=NULL, resolution=NULL WHERE id=1;\" 2>/dev/null"
check "S19 entry INSERT OR REPLACE refused" bash -c "! sqlite3 '$d/changes.db' \"INSERT OR REPLACE INTO entries (serial,type,area,description) VALUES (1,'note','-','evil');\" 2>/dev/null"
check "S19 concern INSERT OR REPLACE refused" bash -c "! sqlite3 '$d/changes.db' \"INSERT OR REPLACE INTO concerns (id, concern) VALUES (1,'evil');\" 2>/dev/null"
# close.md's integrity step states the trigger count first, then the object
# count; keep the trigger count synced to the schema.
want="$(grep -o 'trigger count must be `[0-9]*`' "$KLAWDE/template/close.md" | head -1 | tr -dc '0-9')"
have="$(sqlite3 -readonly "$fresh" "SELECT count(*) FROM sqlite_master WHERE type='trigger';")"
check "S19 close.md trigger count matches the schema ($have)" test "$want" = "$have"
check "S19 upgraded db carries the full trigger set" \
  bash -c "test \"\$(sqlite3 -readonly '$d/changes.db' \"SELECT count(*) FROM sqlite_master WHERE type='trigger';\")\" = \"$have\""
# An in-place upgrade from any earlier version must yield the same objects as a
# fresh install: every table, view and trigger, with the same SQL.
q_all="SELECT type, name, tbl_name, replace(coalesce(sql,''), 'IF NOT EXISTS ', '') FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name;"
check "S19 v2 upgrade yields a schema identical to a fresh install" \
  bash -c "test \"\$(sqlite3 -readonly '$d/changes.db' \"$q_all\")\" = \"\$(sqlite3 -readonly '$fresh' \"$q_all\")\""
d1="$(mkfx s19v1)"; mk_old_db "$d1/changes.db" 1
check "S19 v1 fixture carries 7 triggers" test "$(tc "$d1/changes.db")" = "7"
out="$(cd "$d1" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
check "S19 v1 upgrade exit 0" test "$rc" -eq 0
check "S19 v1 upgrade yields a schema identical to a fresh install" \
  bash -c "test \"\$(sqlite3 -readonly '$d1/changes.db' \"$q_all\")\" = \"\$(sqlite3 -readonly '$fresh' \"$q_all\")\""
d3="$(mkfx s19v3)"; mk_old_db "$d3/changes.db" 3
check "S19 v3 fixture carries 17 triggers" test "$(tc "$d3/changes.db")" = "17"
out="$(cd "$d3" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
echo "$out" > "$BASE/s19v3.out"
check "S19 v3 upgrade exit 0, only the v4, v5 and v6 steps run" \
  bash -c "test $rc -eq 0 && grep -q 'schema to v4' '$BASE/s19v3.out' && grep -q 'schema to v5' '$BASE/s19v3.out' && grep -q 'schema to v6' '$BASE/s19v3.out' && ! grep -q 'schema to v3' '$BASE/s19v3.out'"
check "S19 v3 upgrade yields a schema identical to a fresh install" \
  bash -c "test \"\$(sqlite3 -readonly '$d3/changes.db' \"$q_all\")\" = \"\$(sqlite3 -readonly '$fresh' \"$q_all\")\""
d4="$(mkfx s19v4)"; mk_old_db "$d4/changes.db" 4
check "S19 v4 fixture carries 24 triggers" test "$(tc "$d4/changes.db")" = "24"
out="$(cd "$d4" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
echo "$out" > "$BASE/s19v4.out"
check "S19 v4 upgrade exit 0, only the v5 and v6 steps run" \
  bash -c "test $rc -eq 0 && grep -q 'schema to v5' '$BASE/s19v4.out' && grep -q 'schema to v6' '$BASE/s19v4.out' && ! grep -q 'schema to v4' '$BASE/s19v4.out'"
check "S19 v4 upgrade yields a schema identical to a fresh install" \
  bash -c "test \"\$(sqlite3 -readonly '$d4/changes.db' \"$q_all\")\" = \"\$(sqlite3 -readonly '$fresh' \"$q_all\")\""
check "S19 a fresh install refuses an unknown entry area" \
  bash -c "! sqlite3 '$fresh' \"INSERT INTO entries (type,area,description) VALUES ('note','nope','x');\" 2>/dev/null"

echo "=== S20: every sqlite3 statement the templates ship runs against the shipped schema ==="
# The protocols are executed by an agent verbatim; a typo in one ships silently
# unless something runs them. Each template gets its own fixture: /klawde
# starts from no database (its own step creates it), the others from a seeded
# one deep enough for the serials the examples name.
s20_run() { # s20_run <template> <seed 0|1>
  local tpl="$1" seed="$2" w="$BASE/s20-$1" n=0 failed=0 line i sql
  rm -rf "$w"; mkdir -p "$w/.claude"
  cp "$KLAWDE/template/changes-schema.sql" "$w/.claude/changes-schema.sql"
  if [ "$seed" -eq 1 ]; then
    sqlite3 "$w/changes.db" < "$KLAWDE/template/changes-schema.sql"
    sql="INSERT INTO areas VALUES ('queue'),('api'),('cli'),('import'),('retry'),('config');"
    i=1; while [ "$i" -le 60 ]; do sql="$sql INSERT INTO entries (type,area,description) VALUES ('note','-','filler $i');"; i=$((i+1)); done
    sqlite3 "$w/changes.db" "$sql"
  fi
  cp "$KLAWDE/template/check-log.sh" "$w/.claude/check-log.sh"
  # Extract complete CLI commands, including quoted heredocs. Running only a
  # heredoc opener would falsely pass without executing any of its SQL.
  awk -v out="$w" '
    /^[[:space:]]*(sqlite3 |bash \.claude\/check-log\.sh)/ {
      sub(/^[[:space:]]*/, "")
      file = out "/stmt-" ++n ".sh"
      print > file
      if ($0 ~ /<</) body = 1
      else close(file)
      next
    }
    body { print > file; if ($0 == "KLAWDE_SQL") { body = 0; close(file) } }
    END { print n + 0 > (out "/count"); if (body) exit 1 }
  ' "$KLAWDE/template/$tpl" || failed=1
  n="$(cat "$w/count")"
  i=1
  while [ "$i" -le "$n" ]; do
    if ! (cd "$w" && /bin/bash -e "stmt-$i.sh" > /dev/null 2> "$w/err"); then
      failed=1; echo "  $tpl command $i failed:"; cat "$w/err"
    fi
    i=$((i + 1))
  done
  check "S20 $tpl carries statements to run" test "$n" -gt 0
  check "S20 $tpl: all $n statements ran clean" test "$failed" -eq 0
}
s20_run klawde.md 0
s20_run close.md 1
s20_run CLAUDE.md 1

echo "=== S22: the schema version and the trigger count agree everywhere they are stated ==="
schema_v="$(sed -n 's/^PRAGMA user_version = \([0-9]*\);$/\1/p' "$KLAWDE/template/changes-schema.sql")"
upgrade_v="$(grep -o "PRAGMA user_version = [0-9]*;" "$KLAWDE/upgrade.sh" | tr -dc '0-9\n' | sort -n | tail -1)"
check "S22 upgrade.sh's last in-place upgrade reaches the shipped schema version (v$schema_v)" test "$upgrade_v" = "$schema_v"
readme_t="$(grep -o 'the [0-9]* triggers' "$KLAWDE/README.MD" | head -1 | tr -dc '0-9')"
check "S22 README trigger count matches the schema ($have)" test "$readme_t" = "$have"
close_obj="$(grep -o 'the object count `[0-9]*`' "$KLAWDE/template/close.md" | head -1 | tr -dc '0-9')"
schema_obj="$(grep -cE '^CREATE (TABLE|VIEW) ' "$KLAWDE/template/changes-schema.sql")"
check "S22 close.md object count matches the schema's tables and views ($schema_obj)" test "$close_obj" = "$schema_obj"
close_v="$(grep -o 'integrity ok, schema v[0-9]*' "$KLAWDE/template/close.md" | head -1 | tr -dc '0-9')"
check "S22 close.md closing block names the shipped schema version (v$schema_v)" test "$close_v" = "$schema_v"

echo "=== S24: a present changes.db is checked and repaired whatever its version ==="
d="$(mkfx s24)"; sqlite3 "$d/changes.db" < "$KLAWDE/template/changes-schema.sql"
sqlite3 "$d/changes.db" 'DROP TRIGGER entries_no_update; DROP TRIGGER entries_no_delete; DROP TRIGGER links_no_update; DROP TRIGGER links_no_delete; DROP TRIGGER areas_no_update; DROP TRIGGER areas_no_delete; DROP TRIGGER entries_no_replace; DROP VIEW concern_lines;'
check "S24 damaged current-version db has lost seven triggers" test "$(tc "$d/changes.db")" = "23"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
echo "$out" > "$BASE/s24.out"
check "S24 exit 0" test "$rc" -eq 0
check "S24 restored objects reported by name" \
  bash -c "grep -q 'restored missing:.*entries_no_update' '$BASE/s24.out' && grep -q 'restored missing:.*concern_lines' '$BASE/s24.out'"
check "S24 full trigger set back" test "$(tc "$d/changes.db")" = "$have"
check "S24 log protected again" bash -c "sqlite3 '$d/changes.db' \"INSERT INTO entries (type,description) VALUES ('note','x');\" && ! sqlite3 '$d/changes.db' 'DELETE FROM entries;' 2>/dev/null"
check "S24 repaired db identical to a fresh install" \
  bash -c "test \"\$(sqlite3 -readonly '$d/changes.db' \"$q_all\")\" = \"\$(sqlite3 -readonly '$fresh' \"$q_all\")\""
d="$(mkfx s24b)"; sqlite3 "$d/changes.db" < "$KLAWDE/template/changes-schema.sql"
sqlite3 "$d/changes.db" 'DROP TRIGGER entries_no_delete;'; chmod 444 "$d/changes.db"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
check "S24b read-only db that needs a repair fails preflight, CLAUDE.md untouched" \
  bash -c "test $rc -ne 0 && echo \"$out\" | grep -q 'cannot write.*changes.db' && grep -q 'OLD CONTRACT' '$d/CLAUDE.md'"
chmod 644 "$d/changes.db"
d="$(mkfx s24c)"; sqlite3 "$d/changes.db" < "$KLAWDE/template/changes-schema.sql"
sqlite3 "$d/changes.db" 'DROP TABLE links;'
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
check "S24c db missing a table is refused in preflight, CLAUDE.md untouched" \
  bash -c "test $rc -ne 0 && echo \"$out\" | grep -q 'missing a table' && grep -q 'OLD CONTRACT' '$d/CLAUDE.md'"

echo "=== S25: the two rewrite_codex copies are identical ==="
a="$(sed -n '/^rewrite_codex() {/,/^}/p' "$KLAWDE/setup.sh")"
b="$(sed -n '/^rewrite_codex() {/,/^}/p' "$KLAWDE/upgrade.sh")"
check "S25 rewrite_codex found in setup.sh" test -n "$a"
check "S25 rewrite_codex found in upgrade.sh" test -n "$b"
check "S25 rewrite_codex identical in setup.sh and upgrade.sh" test "$a" = "$b"

echo "=== S26: the scripts work when invoked through a symlink ==="
mkdir -p "$BASE/bin"; ln -s "$KLAWDE/setup.sh" "$BASE/bin/klawde-setup"; ln -s "$KLAWDE/upgrade.sh" "$BASE/bin/klawde-upgrade"
d="$BASE/s26"; mkdir -p "$d"
out="$(cd "$d" && "$BASE/bin/klawde-setup" --claude 2>&1)"; rc=$?
check "S26 setup via symlink" bash -c "test $rc -eq 0 && cmp -s '$KLAWDE/template/CLAUDE.md' '$d/CLAUDE.md'"
out="$(cd "$d" && "$BASE/bin/klawde-upgrade" --claude --no-backup 2>&1)"; rc=$?
check "S26 upgrade via symlink" test "$rc" -eq 0

echo "=== S23: the v4 guards hold on a fresh install ==="
g="$BASE/s23.db"; sqlite3 "$g" < "$KLAWDE/template/changes-schema.sql"
sqlite3 "$g" "INSERT INTO areas VALUES ('queue'); INSERT INTO entries (type,area,description) VALUES ('note','queue','ok'); INSERT INTO concerns (concern) VALUES ('a; b; c'); INSERT INTO legacy_summaries VALUES ('2025-01','-','old');"
refused() { ! sqlite3 "$g" "$1" 2>/dev/null; }
allowed() { sqlite3 "$g" "$1" 2>/dev/null; }
check "S23 concern id below the maximum refused" refused "INSERT INTO concerns (id, concern) VALUES (0, 'x; y; z');"
check "S23 whitespace-only concern refused" refused "INSERT INTO concerns (concern) VALUES ('   ');"
check "S23 impossible opened date refused" refused "INSERT INTO concerns (opened, concern) VALUES ('9999-99-99', 'x; y; z');"
check "S23 rolled-over opened date refused" refused "INSERT INTO concerns (opened, concern) VALUES ('2026-02-30', 'x; y; z');"
check "S23 whitespace-only entry description refused" refused "INSERT INTO entries (type, description) VALUES ('note', ' ');"
check "S23 impossible entry date refused" refused "INSERT INTO entries (date, type, description) VALUES ('2026-13-01', 'note', 'x');"
check "S23 blank resolution reason refused" refused "UPDATE concerns SET resolved = date('now','localtime'), resolution = '  ' WHERE id = 1;"
check "S23 impossible resolved date refused" refused "UPDATE concerns SET resolved = '9999-99-99', resolution = 'done' WHERE id = 1;"
check "S23 untrimmed area name refused" refused "INSERT INTO areas VALUES (' api');"
check "S23 '-' as an area name refused" refused "INSERT INTO areas VALUES ('-');"
check "S23 case variant of an existing area refused" refused "INSERT INTO areas VALUES ('Queue');"
check "S23 case variant refused even under INSERT OR IGNORE" refused "INSERT OR IGNORE INTO areas VALUES ('QUEUE');"
check "S23 exact re-insert of an area still ignored quietly" allowed "INSERT OR IGNORE INTO areas VALUES ('queue');"
check "S23 a new clean area still accepted" allowed "INSERT INTO areas VALUES ('order_import');"
check "S23 legacy summary edit refused" refused "UPDATE legacy_summaries SET description = 'x';"
check "S23 legacy summary delete refused" refused "DELETE FROM legacy_summaries;"
check "S23 a well-formed resolve still succeeds" allowed "UPDATE concerns SET resolved = date('now','localtime'), resolution = 'settled' WHERE id = 1;"

echo "=== S27: retirement stops when a backup or removal fails ==="
failbin="$BASE/failbin"; mkdir -p "$failbin"
cat > "$failbin/cp" <<'SH'
#!/bin/bash
case "$1" in */klaude.md|*/klaude/SKILL.md) echo 'injected backup failure' >&2; exit 1 ;; esac
exec /bin/cp "$@"
SH
chmod +x "$failbin/cp"
for layout in claude codex; do
  d="$(mkfx "s27-$layout")"
  legacy="$d/.claude/commands/klaude.md"
  if [ "$layout" = codex ]; then
    legacy="$d/.agents/skills/klaude/SKILL.md"
    mkdir -p "$(dirname "$legacy")"; printf '%s\n' 'name: klaude' 'CUSTOM LEGACY' > "$legacy"
  fi
  out="$(cd "$d" && PATH="$failbin:$PATH" "$KLAWDE/upgrade.sh" "--$layout" --backup 2>&1)"; rc=$?
  printf '%s\n' "$out" > "$BASE/s27-$layout.out"
  check "S27 $layout backup failure aborts" test "$rc" -ne 0
  check "S27 $layout original survives" test -f "$legacy"
  check "S27 $layout no false backup success" ngrepq 'Backed up \(klaude.md\|SKILL.md\)' "$BASE/s27-$layout.out"
  check "S27 $layout failure is reported" grepq 'could not back up' "$BASE/s27-$layout.out"
done
cat > "$failbin/rm" <<'SH'
#!/bin/bash
case "$*" in *'/klaude.md'*) echo 'injected removal failure' >&2; exit 1 ;; esac
exec /bin/rm "$@"
SH
chmod +x "$failbin/rm"
d="$(mkfx s27-remove)"
out="$(cd "$d" && PATH="$failbin:$PATH" "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
check "S27 failed removal aborts" test "$rc" -ne 0
check "S27 failed removal retains original" test -f "$d/.claude/commands/klaude.md"

echo "=== S28: existing migration archives are never overwritten ==="
for kind in file directory symlink dangling; do
  d="$(mkfx "s28-$kind")"
  printf '%s\n' '2026-09-01 001 [note] (-) Original history' > "$d/CHANGES.md"
  printf '%s\n' 'UNRELATED CONTENT' > "$d/other.txt"
  case "$kind" in
    file) echo 'EARLIER ARCHIVE' > "$d/CHANGES.md.migrated" ;;
    directory) mkdir "$d/CHANGES.md.migrated" ;;
    symlink) ln -s other.txt "$d/CHANGES.md.migrated" ;;
    dangling) ln -s missing.txt "$d/CHANGES.md.migrated" ;;
  esac
  out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
  check "S28 $kind archive refused before writes" test "$rc" -ne 0
  check "S28 $kind original log survives" test -f "$d/CHANGES.md"
  check "S28 $kind contract unchanged" grepq 'OLD CONTRACT' "$d/CLAUDE.md"
  check "S28 $kind unrelated file unchanged" grepq '^UNRELATED CONTENT$' "$d/other.txt"
  check "S28 $kind database not created" test ! -e "$d/changes.db"
done

echo "=== S29: contract hard links are refused even for a single layout ==="
for script in setup upgrade; do
  for target in claude codex both; do
    d="$(mkfx "s29-$script-$target")"
    ln "$d/CLAUDE.md" "$d/AGENTS.md"
    flags=""; if [ "$script" = upgrade ]; then flags="--no-backup"; fi
    out="$(cd "$d" && "$KLAWDE/$script.sh" "--$target" $flags < /dev/null 2>&1)"; rc=$?
    check "S29 $script $target refuses shared inode" test "$rc" -ne 0
    check "S29 $script $target contract unchanged" grepq 'OLD CONTRACT' "$d/CLAUDE.md"
  done
done

echo "=== S30: definition drift is detected readonly and repaired with backup ==="
d="$(mkfx s30)"; sqlite3 "$d/changes.db" < "$KLAWDE/template/changes-schema.sql"
sqlite3 "$d/changes.db" "INSERT INTO entries (type,description) VALUES ('note','keep me'); DROP TRIGGER entries_no_update; CREATE TRIGGER entries_no_update BEFORE UPDATE ON entries BEGIN SELECT 1; END; DROP VIEW log_lines; CREATE VIEW log_lines AS SELECT serial, 'wrong' AS line FROM entries;"
before="$(cksum < "$d/changes.db")"
out="$(bash "$KLAWDE/template/check-log.sh" "$d/changes.db" 2>&1)"; rc=$?
printf '%s\n' "$out" > "$BASE/s30-check.out"
check "S30 checker rejects same-name no-op trigger" test "$rc" -ne 0
check "S30 trigger drift named with its status" grepq 'trigger|entries_no_update|changed' "$BASE/s30-check.out"
check "S30 view drift named with its status" grepq 'view|log_lines|changed' "$BASE/s30-check.out"
check "S30 checker did not alter database" test "$before" = "$(cksum < "$d/changes.db")"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --backup 2>&1)"; rc=$?
check "S30 upgrade repairs definitions" test "$rc" -eq 0
check "S30 repaired database passes checker" bash "$KLAWDE/template/check-log.sh" "$d/changes.db"
check "S30 history unchanged" test "$(sqlite3 "$d/changes.db" 'SELECT description FROM entries;')" = 'keep me'
check "S30 history protected again" bash -c "! sqlite3 '$d/changes.db' \"UPDATE entries SET description='rewritten';\" 2>/dev/null"
backed=0; for backup in "$d"/changes.db.bak.*; do if [ -f "$backup" ]; then backed=1; fi; done
check "S30 current-version repair backs up database" test "$backed" -eq 1
# Both the checker and installer must support apostrophes in paths.
d="$(mkfx "s30-quoted'path")"; sqlite3 "$d/changes.db" < "$KLAWDE/template/changes-schema.sql"
check "S30 quoted path verifies" bash "$KLAWDE/template/check-log.sh" "$d/changes.db"
# Changed table definitions cannot be fixed without risking records.
sqlite3 "$d/changes.db" 'ALTER TABLE entries ADD COLUMN unwanted TEXT;'
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
check "S30 altered table aborts upgrade" test "$rc" -ne 0
check "S30 altered table leaves contract unchanged" grepq 'OLD CONTRACT' "$d/CLAUDE.md"

echo "=== S31: v6 guards hold fresh and after a v5 upgrade ==="
for origin in fresh v5; do
  d="$(mkfx "s31-$origin")"; g="$d/changes.db"
  if [ "$origin" = v5 ]; then
    mk_old_db "$g" 5
    check "S31 faithful v5 carries 28 triggers" test "$(tc "$g")" = 28
    out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
    check "S31 v5 upgrade succeeds" test "$rc" -eq 0
  else
    sqlite3 "$g" < "$KLAWDE/template/changes-schema.sql"
  fi
  sqlite3 "$g" "INSERT INTO legacy_summaries VALUES ('2025-01','-','original'); INSERT INTO concerns (concern) VALUES ('observed; consequence; criterion');"
  check "S31 $origin legacy replacement refused" refused "INSERT OR REPLACE INTO legacy_summaries (rowid,month,area,description) VALUES (1,'2025-01','-','rewritten');"
  check "S31 $origin legacy append still allowed" allowed "INSERT INTO legacy_summaries VALUES ('2025-02','-','another');"
  check "S31 $origin null reference cannot become -1" refused 'UPDATE concerns SET ref_serial=-1 WHERE id=1;'
  check "S31 $origin reference remains null" test "$(sqlite3 "$g" 'SELECT ref_serial IS NULL FROM concerns WHERE id=1;')" = 1
  check "S31 $origin LF refs refused" refused "INSERT INTO entries (type,description,refs) VALUES ('note','ok','commit' || char(10) || 'fake line');"
  check "S31 $origin CR refs refused" refused "INSERT INTO entries (type,description,refs) VALUES ('note','ok','commit' || char(13) || 'fake line');"
  check "S31 $origin plain refs allowed" allowed "INSERT INTO entries (type,description,refs) VALUES ('note','ok','abc123');"
  check "S31 $origin normal resolution allowed" allowed "UPDATE concerns SET resolved=date('now','localtime'), resolution='settled' WHERE id=1;"
  check "S31 $origin matches current schema" bash "$KLAWDE/template/check-log.sh" "$g"
done

echo "=== S32: authored SQL preserves literal shell syntax and apostrophes ==="
d="$(mkfx s32)"; sqlite3 "$d/changes.db" < "$KLAWDE/template/changes-schema.sql"
sqlite3 "$d/changes.db" "INSERT INTO areas VALUES ('queue');"
cat > "$d/payload" <<'TEXT'
Literal `touch marker-backtick` $(touch marker-dollar) $5 "quotes" and don''t
TEXT
# Replace only the example's description inside the actual shipped command.
awk -v payload="$d/payload" '
  BEGIN { getline text < payload; close(payload) }
  { sub(/Retry moved to the gateway; per-client retry double-billed the API/, text); print }
' "$BASE/s20-CLAUDE.md/stmt-1.sh" > "$d/write.sh"
out="$(cd "$d" && /bin/bash write.sh 2>&1)"; rc=$?
check "S32 literal SQL write succeeds" test "$rc" -eq 0
check "S32 backtick command never ran" test ! -e "$d/marker-backtick"
check "S32 dollar substitution never ran" test ! -e "$d/marker-dollar"
expected="$(sed "s/''/'/g" "$d/payload")"
check "S32 stored text is exact" test "$(sqlite3 "$d/changes.db" 'SELECT description FROM entries;')" = "$expected"

echo "=== S33: the installed checker alone identifies the layout ==="
for layout in claude codex; do
  d="$BASE/s33-$layout"; mkdir -p "$d"
  dir=.claude; if [ "$layout" = codex ]; then dir=.agents; fi
  mkdir -p "$d/$dir"; cp "$KLAWDE/template/check-log.sh" "$d/$dir/check-log.sh"
  out="$(cd "$d" && printf '\n' | "$KLAWDE/upgrade.sh" --no-backup 2>&1)"; rc=$?
  printf '%s\n' "$out" > "$BASE/s33-$layout.out"
  check "S33 $layout detected from checker" grepq "Enter for detected: $layout" "$BASE/s33-$layout.out"
  check "S33 $layout upgrade completes" test "$rc" -eq 0
done

echo "=== S34: objects the shipped schema does not define ==="
# An extra trigger is not inert: a BEFORE INSERT trigger raising IGNORE makes
# every INSERT succeed and record nothing, so a session would report entries it
# never wrote. Refused before any file is written, and sent to git, not upgrade.
d="$(mkfx s34trig)"; sqlite3 "$d/changes.db" < "$KLAWDE/template/changes-schema.sql"
sqlite3 "$d/changes.db" "CREATE TRIGGER silent_drop BEFORE INSERT ON entries BEGIN SELECT RAISE(IGNORE); END;"
before="$(cksum < "$d/changes.db")"
out="$(bash "$KLAWDE/template/check-log.sh" "$d/changes.db" 2>&1)"; rc=$?
printf '%s\n' "$out" > "$BASE/s34trig.check"
check "S34 checker rejects a trigger the schema does not define" test "$rc" -ne 0
check "S34 checker names it with its status" grepq 'trigger|silent_drop|unexpected' "$BASE/s34trig.check"
check "S34 checker sends it to git, not back to upgrade.sh" grepq 'recover changes.db from git' "$BASE/s34trig.check"
check "S34 the silencing trigger really does swallow inserts" \
  bash -c "sqlite3 '$d/changes.db' \"INSERT INTO entries (type,description) VALUES ('note','x');\" && test \"\$(sqlite3 -readonly '$d/changes.db' 'SELECT count(*) FROM entries;')\" = 0"
before="$(cksum < "$d/changes.db")"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --backup 2>&1)"; rc=$?
printf '%s\n' "$out" > "$BASE/s34trig.upgrade"
check "S34 upgrade refuses it" test "$rc" -ne 0
check "S34 refusal comes before any write" grepq 'Nothing was changed' "$BASE/s34trig.upgrade"
check "S34 contract unchanged" grepq 'OLD CONTRACT' "$d/CLAUDE.md"
check "S34 database untouched" test "$before" = "$(cksum < "$d/changes.db")"
backed=0; for backup in "$d"/changes.db.bak.*; do if [ -e "$backup" ]; then backed=1; fi; done
check "S34 no backup was taken either" test "$backed" -eq 0
# An extra table or view cannot weaken the log, so it is reported and left
# alone. Repair selects objects by what each difference is: dropping one the
# schema does not define would destroy the rows or the definition behind it.
d="$(mkfx s34extra)"; sqlite3 "$d/changes.db" < "$KLAWDE/template/changes-schema.sql"
sqlite3 "$d/changes.db" "CREATE TABLE scratchpad (k TEXT); INSERT INTO scratchpad VALUES ('keep me'); CREATE VIEW my_report AS SELECT 1 AS x;"
out="$(bash "$KLAWDE/template/check-log.sh" "$d/changes.db" 2>&1)"; rc=$?
printf '%s\n' "$out" > "$BASE/s34extra.check"
check "S34 an extra table or view does not fail the check" test "$rc" -eq 0
check "S34 extras are still reported" grepq 'table|scratchpad|unexpected' "$BASE/s34extra.check"
sqlite3 "$d/changes.db" 'DROP TRIGGER entries_no_delete;'
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
printf '%s\n' "$out" > "$BASE/s34extra.upgrade"
check "S34 upgrade completes alongside extras" test "$rc" -eq 0
check "S34 extra table survives with its rows" \
  test "$(sqlite3 -readonly "$d/changes.db" 'SELECT k FROM scratchpad;')" = "keep me"
check "S34 extra view survives" \
  test "$(sqlite3 -readonly "$d/changes.db" "SELECT count(*) FROM sqlite_master WHERE name='my_report';")" = "1"
check "S34 the genuinely missing trigger was restored" \
  test "$(sqlite3 -readonly "$d/changes.db" "SELECT count(*) FROM sqlite_master WHERE name='entries_no_delete';")" = "1"
check "S34 repaired database still passes the checker" bash "$KLAWDE/template/check-log.sh" "$d/changes.db"
# A view on its own, with no unexpected table sorting ahead of it: dispatching
# on the object kind alone would drop it here and report success, so this is the
# case that actually catches a repair reaching past what the schema ships.
d="$(mkfx s34view)"; sqlite3 "$d/changes.db" < "$KLAWDE/template/changes-schema.sql"
sqlite3 "$d/changes.db" "CREATE VIEW my_report AS SELECT serial FROM entries; DROP TRIGGER entries_no_delete;"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
check "S34 upgrade completes with an extra view alone" test "$rc" -eq 0
check "S34 an extra view is never dropped by the repair" \
  test "$(sqlite3 -readonly "$d/changes.db" "SELECT count(*) FROM sqlite_master WHERE name='my_report';")" = "1"
check "S34 its missing trigger was still restored" \
  test "$(sqlite3 -readonly "$d/changes.db" "SELECT count(*) FROM sqlite_master WHERE name='entries_no_delete';")" = "1"

echo "=== S35: every shipped script parses ==="
# bash -n takes one script; anything after the first is an argument to it, not
# a second file to check, so each one is verified on its own.
for f in setup.sh upgrade.sh template/check-log.sh tests/verify.sh; do
  check "S35 $f parses" /bin/bash -n "$KLAWDE/$f"
done


echo ""
echo "RESULT: $pass passed, $fail failed"
exit "$fail"
