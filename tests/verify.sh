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
# upgrade.sh retires deprecated Codex prompts from $CODEX_HOME; point it at the
# sandbox so no test can ever touch the real ~/.codex.
export CODEX_HOME="$BASE/codex-home"

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
  for f in klawde.md klaude.md close.md; do echo "OLD $f" > "$d/.claude/commands/$f"; done
  echo "$d"
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
d="$(mkfx s4d)"; echo "OLD init" > "$d/.claude/commands/init.md"; chmod 555 "$d/.claude/commands"
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
check "S5 schema installed" cmp -s "$KLAWDE/template/changes-schema.sql" "$d/.claude/changes-schema.sql"
check "S5 source version printed" grepq 'source version: ' "$BASE/s5.out"
check "S5 restart note printed" grepq 'restart it' "$BASE/s5.out"
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

echo "=== S5e: klaude.md alone counts as Claude detection evidence ==="
d="$BASE/s5e"; mkdir -p "$d/.claude/commands"; echo "OLD klaude" > "$d/.claude/commands/klaude.md"
out="$(cd "$d" && printf '\nn\n' | "$KLAWDE/upgrade.sh" 2>&1)"; rc=$?
echo "$out" > "$BASE/s5e.out"
check "S5e detected claude" grepq 'Enter for detected: claude' "$BASE/s5e.out"
check "S5e exit 0" test "$rc" -eq 0
check "S5e klaude.md upgraded" cmp -s "$KLAWDE/template/klaude.md" "$d/.claude/commands/klaude.md"

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
sqlite3 "$d/changes.db" < "$KLAWDE/template/changes-schema.sql"
sqlite3 "$d/changes.db" 'DROP TRIGGER areas_no_update; DROP TRIGGER entries_no_backfill; PRAGMA user_version = 1;'
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
check "S8b v1 db upgraded to v2 in place" \
  bash -c "test $rc -eq 0 && test \"\$(sqlite3 -readonly '$d/changes.db' 'PRAGMA user_version;')\" = 2"
d="$(mkfx s8c)"
sqlite3 "$d/changes.db" < "$KLAWDE/template/changes-schema.sql"
chmod 444 "$d/changes.db"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
check "S8c read-only current (v2) db does not block the upgrade" test "$rc" -eq 0
chmod 644 "$d/changes.db"
d="$(mkfx s8d)"
sqlite3 "$d/changes.db" 'PRAGMA user_version = 1; CREATE TABLE areas(area TEXT); CREATE TABLE entries(serial INTEGER);'
chmod 444 "$d/changes.db"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
check "S8d read-only v1 db fails preflight, CLAUDE.md untouched" \
  bash -c "test $rc -ne 0 && echo \"$out\" | grep -q 'cannot write.*changes.db' && grep -q 'OLD CONTRACT' '$d/CLAUDE.md'"
chmod 644 "$d/changes.db"

echo "=== S8e: a mid-run failure still reports a possibly-partial upgrade ==="
d="$(mkfx s8e)"
echo '2025-03-05 001 [badtype] (core) entry with a type the schema refuses' > "$d/CHANGES.md"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
echo "$out" > "$BASE/s8e.out"
check "S8e exit nonzero" test "$rc" -ne 0
check "S8e partial-upgrade message shown" grepq 'may be partially updated' "$BASE/s8e.out"
check "S8e files before the failure were written" grepq '# CLAUDE.md' "$d/CLAUDE.md"

echo "=== S9: bash 3.2 compatibility (/bin/bash on macOS) ==="
d="$(mkfx s9)"
out="$(cd "$d" && /bin/bash "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
check "S9 upgrade under /bin/bash exit 0" test "$rc" -eq 0
check "S9 close.md upgraded" cmp -s "$KLAWDE/template/close.md" "$d/.claude/commands/close.md"
d="$BASE/s9b"; mkdir -p "$d"
out="$(cd "$d" && /bin/bash "$KLAWDE/setup.sh" --claude 2>&1)"; rc=$?
check "S9 setup under /bin/bash exit 0" test "$rc" -eq 0

echo "=== S10: deprecated Codex prompts are retired from CODEX_HOME, never \$HOME ==="
d="$BASE/s10"; mkdir -p "$d/.agents/skills/klawde"
echo "OLD SKILL" > "$d/.agents/skills/klawde/SKILL.md"; echo "OLD AGENTS" > "$d/AGENTS.md"
mkdir -p "$CODEX_HOME/prompts"; echo "old prompt" > "$CODEX_HOME/prompts/klawde.md"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --codex --no-backup 2>&1)"; rc=$?
echo "$out" > "$BASE/s10.out"
check "S10 exit 0" test "$rc" -eq 0
check "S10 klawde skill counts as artifact: no foreign prompt" ngrepq 'Overwrite AGENTS.md' "$BASE/s10.out"
check "S10 retirement message printed" grepq 'Removed deprecated prompt' "$BASE/s10.out"
check "S10 sandboxed prompt removed" bash -c "! test -f '$CODEX_HOME/prompts/klawde.md'"

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
d="$(mkfx s13)"; echo "OLD init" > "$d/.claude/commands/init.md"; chmod 444 "$d/.claude/commands/init.md"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup < /dev/null 2>&1)"; rc=$?
echo "$out" > "$BASE/s13.out"
check "S13 exit 0" test "$rc" -eq 0
check "S13 removal message truthful, file gone" \
  bash -c "grep -q 'Removed legacy' '$BASE/s13.out' && ! test -f '$d/.claude/commands/init.md'"

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
for f in AGENTS.md .agents/changes-schema.sql .agents/skills/klawde/SKILL.md \
         .agents/skills/klaude/SKILL.md .agents/skills/close/SKILL.md; do
  cmp -s "$d1/$f" "$d2/$f" || same=0
done
check "S16 no drift between the duplicated codex writers" test "$same" -eq 1

echo "=== S17: a changes.db from a newer klawde is refused ==="
d="$(mkfx s17)"
sqlite3 "$d/changes.db" < "$KLAWDE/template/changes-schema.sql"
sqlite3 "$d/changes.db" 'PRAGMA user_version = 3;'
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
echo "$out" > "$BASE/s17.out"
check "S17 exit nonzero" test "$rc" -ne 0
check "S17 newer-schema error shown" grepq 'newer than this checkout supports' "$BASE/s17.out"
check "S17 CLAUDE.md untouched" grepq 'OLD CONTRACT' "$d/CLAUDE.md"

echo "=== S18: the brief shape measurement shipped in the commands ==="
# /klawde step 8 and /close step 6 carry the same awk one-liner; it must be one
# command, and it must count what the protocols say it counts.
d="$BASE/s18"; mkdir -p "$d"
grep '^awk ' "$KLAWDE/template/klawde.md" > "$d/klawde.cmd"
grep '^awk ' "$KLAWDE/template/close.md"  > "$d/close.cmd"
check "S18 klawde.md carries exactly one measurement" test "$(wc -l < "$d/klawde.cmd")" -eq 1
check "S18 close.md carries exactly one measurement"  test "$(wc -l < "$d/close.cmd")" -eq 1
check "S18 both commands identical" cmp -s "$d/klawde.cmd" "$d/close.cmd"
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
check "S18 well-shaped brief measures all 1s" test "$out" = "Shape: Purpose 1, Current scope 1, Key decisions 1, Non-goals 1, Areas 1, Breaking-change context 1, Current focus 1, Next steps 1, Open questions 1, Do-not-touch 1, Environment quirks 1"
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

echo ""
echo "RESULT: $pass passed, $fail failed"
exit "$fail"
