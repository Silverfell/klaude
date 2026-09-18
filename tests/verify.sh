#!/bin/bash
# Regression suite for setup.sh, upgrade.sh, lib.sh and the templates. Builds
# throwaway projects in a temp directory and runs the real scripts against them.
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
tc() { sqlite3 -readonly "$1" "SELECT count(*) FROM sqlite_master WHERE type='trigger';"; }

mkfx() { # mkfx <name> -> a stale claude install fixture
  local d="$BASE/$1"
  mkdir -p "$d/.claude/commands"
  echo "OLD CONTRACT" > "$d/CLAUDE.md"
  for f in klawde.md close.md; do echo "OLD $f" > "$d/.claude/commands/$f"; done
  echo "$d"
}
# A faithful changes.db of an earlier schema version, built by removing from a
# fresh install exactly what each later version added.
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
fresh="$BASE/fresh.db"
sqlite3 "$fresh" < "$KLAWDE/template/changes-schema.sql"
schema_v="$(sqlite3 -readonly "$fresh" 'PRAGMA user_version;')"
have="$(tc "$fresh")"
q_all="SELECT type, name, tbl_name, replace(coalesce(sql,''), 'IF NOT EXISTS ', '') FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name;"
same_as_fresh() { test "$(sqlite3 -readonly "$1" "$q_all")" = "$(sqlite3 -readonly "$fresh" "$q_all")"; }
differs_from_fresh() { ! same_as_fresh "$1"; }

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

echo "=== S1d: foreign AGENTS.md cannot be confirmed non-interactively; declining aborts ==="
d="$BASE/s1d"; mkdir -p "$d"; echo "foreign agents file" > "$d/AGENTS.md"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --codex --no-backup < /dev/null 2>&1)"; rc=$?
echo "$out" > "$BASE/s1d.out"
check "S1d exit nonzero" test "$rc" -ne 0
check "S1d explicit cannot-confirm error" grepq 'cannot confirm overwriting' "$BASE/s1d.out"
check "S1d AGENTS.md untouched" grepq 'foreign agents file' "$d/AGENTS.md"
d="$(mkfx s1e)"; echo "foreign agents file" > "$d/AGENTS.md"
out="$(cd "$d" && printf 'n\n' | "$KLAWDE/upgrade.sh" --both --no-backup 2>&1)"; rc=$?
check "S1d declining under --both aborts, nothing changed" \
  bash -c "test $rc -ne 0 && grep -q 'foreign agents file' '$d/AGENTS.md' && grep -q 'OLD CONTRACT' '$d/CLAUDE.md'"

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
check "S5 an unrecognized contract without Code craft gets the section, and the note says so" grepq 'had no Code craft section; the upgrade installed it' "$BASE/s5.out"
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
check "S5 --backup completes with .bak files" bash -c "test $rc -eq 0 && test $n -ge 3"

echo "=== S5e: a removed Code craft section stays out across upgrades, judged per layout ==="
# The expected contract is built apart from upgrade.sh's own strip: delete from
# the Code craft heading up to the Tools heading, by line number.
without_craft() { # <contract> -> stdout
  local a b
  a="$(grep -n '^### Code craft' "$1" | cut -d: -f1)"
  b="$(grep -n '^### Tools$' "$1" | cut -d: -f1)"
  sed "${a},$((b - 1))d" "$1"
}
check "S5e the template carries both headings the recognition rule reads" \
  bash -c "grep -q '^## Deviations\$' '$KLAWDE/template/CLAUDE.md' && grep -q '^### Code craft' '$KLAWDE/template/CLAUDE.md'"
without_craft "$KLAWDE/template/CLAUDE.md" > "$BASE/s5e.expected"
check "S5e the expectation lacks the section and keeps its neighbours" \
  bash -c "! grep -q '^### Code craft' '$BASE/s5e.expected' && grep -q '^### Code\$' '$BASE/s5e.expected' && grep -q '^### Tools\$' '$BASE/s5e.expected'"
d="$BASE/s5e"; mkdir -p "$d"
(cd "$d" && "$KLAWDE/setup.sh" --both >/dev/null 2>&1)
cp "$d/AGENTS.md" "$BASE/s5e-agents.full"
{ cat "$BASE/s5e.expected"; echo "STALE LINE"; } > "$d/CLAUDE.md"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --both --no-backup 2>&1)"; rc=$?
echo "$out" > "$BASE/s5e.out"
check "S5e exit 0" test "$rc" -eq 0
check "S5e CLAUDE.md is the template minus exactly the Code craft section" cmp -s "$BASE/s5e.expected" "$d/CLAUDE.md"
check "S5e kept-out note printed once, for CLAUDE.md only" \
  bash -c "test \"\$(grep -c 'the upgrade kept it out' '$BASE/s5e.out')\" -eq 1 && grep -q 'CLAUDE.md had no Code craft section' '$BASE/s5e.out'"
check "S5e AGENTS.md, which kept the section, is the full Codex contract" cmp -s "$BASE/s5e-agents.full" "$d/AGENTS.md"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --both --no-backup 2>&1)"; rc=$?
check "S5e a second upgrade leaves the contract byte-identical" bash -c "test $rc -eq 0 && cmp -s '$BASE/s5e.expected' '$d/CLAUDE.md'"

d="$BASE/s5f"; mkdir -p "$d"
(cd "$d" && "$KLAWDE/setup.sh" --codex >/dev/null 2>&1)
without_craft "$d/AGENTS.md" > "$BASE/s5f.expected"
{ cat "$BASE/s5f.expected"; echo "STALE LINE"; } > "$d/AGENTS.md"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --codex --no-backup 2>&1)"; rc=$?
check "S5f codex exit 0" test "$rc" -eq 0
check "S5f AGENTS.md is the Codex contract minus exactly the Code craft section" cmp -s "$BASE/s5f.expected" "$d/AGENTS.md"
check "S5f AGENTS.md keeps its title" grepq '^# AGENTS.md$' "$d/AGENTS.md"

d="$BASE/s5g"; mkdir -p "$d"
(cd "$d" && "$KLAWDE/setup.sh" --claude >/dev/null 2>&1)
{ cat "$BASE/s5e.expected"; echo "STALE LINE"; } > "$d/CLAUDE.md"
cp "$d/CLAUDE.md" "$BASE/s5g.before"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --backup 2>&1)"; rc=$?
check "S5g --backup exit 0, section still kept out" bash -c "test $rc -eq 0 && cmp -s '$BASE/s5e.expected' '$d/CLAUDE.md'"
check "S5g the one contract backup is the pre-upgrade contract" \
  bash -c "test \"\$(ls '$d'/CLAUDE.md.bak.* | wc -l)\" -eq 1 && cmp -s '$BASE/s5g.before' '$d'/CLAUDE.md.bak.*"

# The same shape with no klawde files beside it is not recognized: it may be foreign.
d="$BASE/s5h"; mkdir -p "$d"; cp "$BASE/s5e.expected" "$d/CLAUDE.md"
out="$(cd "$d" && printf 'y\n' | "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
echo "$out" > "$BASE/s5h.out"
check "S5h a lone contract of that shape gets the full template" bash -c "test $rc -eq 0 && cmp -s '$KLAWDE/template/CLAUDE.md' '$d/CLAUDE.md'"
check "S5h and the note says the section was installed" grepq 'the upgrade installed it' "$BASE/s5h.out"

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

echo "=== S8: changes.db states ==="
d="$(mkfx s8)"; echo "not a database" > "$d/changes.db"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
echo "$out" > "$BASE/s8.out"
check "S8 garbage changes.db caught in preflight" grepq 'not a readable SQLite database' "$BASE/s8.out"
check "S8 exit nonzero, CLAUDE.md untouched" bash -c "test $rc -ne 0 && grep -q 'OLD CONTRACT' '$d/CLAUDE.md'"
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
check "S8h directory named changes.db refused" bash -c "test $rc -ne 0 && grep -q 'not a readable SQLite database' '$BASE/s8h.out'"
check "S8h CLAUDE.md untouched" grepq 'OLD CONTRACT' "$d/CLAUDE.md"

echo "=== S9: bash 3.2 compatibility (/bin/bash on macOS) ==="
d="$(mkfx s9)"
out="$(cd "$d" && /bin/bash "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
check "S9 upgrade under /bin/bash exit 0" test "$rc" -eq 0
check "S9 close.md upgraded" cmp -s "$KLAWDE/template/close.md" "$d/.claude/commands/close.md"
d="$BASE/s9b"; mkdir -p "$d"
out="$(cd "$d" && /bin/bash "$KLAWDE/setup.sh" --claude 2>&1)"; rc=$?
check "S9 setup under /bin/bash exit 0" test "$rc" -eq 0

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

echo "=== S21: the Codex rewrite leaves no Claude-only reference behind ==="
# rewrite_codex rewrites only backticked /klawde, /close and .claude/commands
# paths and the bare schema and checker paths; anything else survives verbatim.
d1="$BASE/s21"; mkdir -p "$d1"
(cd "$d1" && "$KLAWDE/setup.sh" --codex >/dev/null 2>&1)
left=""
for f in "$d1/AGENTS.md" "$d1"/.agents/skills/*/SKILL.md "$d1/.agents/changes-schema.sql" "$d1/.agents/check-log.sh"; do
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
d="$BASE/s18"; mkdir -p "$d"
grep '^awk ' "$KLAWDE/template/klawde.md" > "$d/klawde.cmd"
grep '^awk ' "$KLAWDE/template/close.md"  > "$d/close.cmd"
check "S18 klawde.md carries exactly one measurement" test "$(wc -l < "$d/klawde.cmd")" -eq 1
check "S18 close.md carries exactly one measurement"  test "$(wc -l < "$d/close.cmd")" -eq 1
check "S18 both commands identical" cmp -s "$d/klawde.cmd" "$d/close.cmd"
# The expected shape comes from the brief template /klawde ships (its first
# fenced block), so adding a field to the template changes this expectation.
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

-  Purpose: two spaces after the dash.
* Current scope: asterisk bullet.
- Key decisions :
  - Postgres SKIP LOCKED over Redis (2026-05-12)
  - single binary, no daemon
- Non-goals: multi-tenant support, real-time sync.
- Areas: import, retry, cli, config.
- Breaking-change context: v0.4 renamed config key `shop_url` to `store_url`.
- Current focus: retry queue hardening.
- Current focus (2026-06-01): backoff cap.
- Next steps: add backoff cap; test double-delivery on restart.
  Also verify the retry table index.

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
check "S18 odd bullet spellings still name the fields" bash -c "case '$out' in *'Shape: Purpose 1, Current scope 1, Key decisions 3,'*) exit 0;; *) exit 1;; esac"
check "S18 continuation line counted, blank line not" bash -c "case '$out' in *'Next steps 2, Open questions 3,'*) exit 0;; *) exit 1;; esac"
check "S18 duplicate Current focus surfaces as a second name" bash -c "case '$out' in *'Current focus 1, Current focus (2026-06-01) 1,'*) exit 0;; *) exit 1;; esac"
check "S18 a column-zero item with a colon measures as a foreign name" bash -c "case '$out' in *'should we pick option A 1,'*) exit 0;; *) exit 1;; esac"
check "S18 a heading after the last field starts Trailing" bash -c "case '$out' in *'Environment quirks 1, Trailing 2'*) exit 0;; *) exit 1;; esac"

echo "=== S19: every earlier schema version upgrades in place to a fresh install's schema ==="
for v in 1 2 3 4 5; do
  d="$(mkfx "s19v$v")"; mk_old_db "$d/changes.db" "$v"
  check "S19 v$v fixture differs from a fresh install" differs_from_fresh "$d/changes.db"
  out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
  echo "$out" > "$BASE/s19v$v.out"
  check "S19 v$v upgrade exit 0, reports the version step" \
    bash -c "test $rc -eq 0 && grep -q 'schema from v$v to v$schema_v' '$BASE/s19v$v.out'"
  check "S19 v$v upgraded schema identical to a fresh install" same_as_fresh "$d/changes.db"
  check "S19 v$v post-upgrade check printed" grepq 'changes.db checked: integrity ok' "$BASE/s19v$v.out"
done
# The lifecycle the contract promises must actually be enforced by an upgraded db.
d="$BASE/s19v2"
sqlite3 "$d/changes.db" "INSERT INTO entries (type,area,description) VALUES ('decision','-','s19 decision');"
sqlite3 "$d/changes.db" "INSERT INTO concerns (concern, ref_serial) VALUES ('s19 concern', 1);"
check "S19 delete refused" bash -c "! sqlite3 '$d/changes.db' 'DELETE FROM concerns;' 2>/dev/null"
check "S19 text edit refused" bash -c "! sqlite3 '$d/changes.db' \"UPDATE concerns SET concern='x' WHERE id=1;\" 2>/dev/null"
check "S19 unknown area refused" bash -c "! sqlite3 '$d/changes.db' \"INSERT INTO concerns (area, concern) VALUES ('nope','y');\" 2>/dev/null"
check "S19 dangling ref_serial refused" bash -c "! sqlite3 '$d/changes.db' \"INSERT INTO concerns (concern, ref_serial) VALUES ('z', 99);\" 2>/dev/null"
check "S19 resolve is one-way" bash -c "sqlite3 '$d/changes.db' \"UPDATE concerns SET resolved=date('now','localtime'), resolution='done' WHERE id=1;\" && ! sqlite3 '$d/changes.db' \"UPDATE concerns SET resolved=NULL, resolution=NULL WHERE id=1;\" 2>/dev/null"
check "S19 entry INSERT OR REPLACE refused" bash -c "! sqlite3 '$d/changes.db' \"INSERT OR REPLACE INTO entries (serial,type,area,description) VALUES (1,'note','-','evil');\" 2>/dev/null"
check "S19 concern INSERT OR REPLACE refused" bash -c "! sqlite3 '$d/changes.db' \"INSERT OR REPLACE INTO concerns (id, concern) VALUES (1,'evil');\" 2>/dev/null"
check "S19 a fresh install refuses an unknown entry area" \
  bash -c "! sqlite3 '$fresh' \"INSERT INTO entries (type,area,description) VALUES ('note','nope','x');\" 2>/dev/null"

echo "=== S20: every sqlite3 statement the templates ship runs against the shipped schema ==="
# Each template gets its own fixture: /klawde starts from no database (its own
# step creates it), the others from a seeded one deep enough for the serials
# the examples name.
s20_run() { # s20_run <template> <seed 0|1>
  local tpl="$1" seed="$2" w="$BASE/s20-$1" n=0 failed=0 i sql
  rm -rf "$w"; mkdir -p "$w/.claude"
  cp "$KLAWDE/template/changes-schema.sql" "$w/.claude/changes-schema.sql"
  if [ "$seed" -eq 1 ]; then
    sqlite3 "$w/changes.db" < "$KLAWDE/template/changes-schema.sql"
    sql="INSERT INTO areas VALUES ('queue'),('api'),('cli'),('import'),('retry'),('config');"
    i=1; while [ "$i" -le 60 ]; do sql="$sql INSERT INTO entries (type,area,description) VALUES ('note','-','filler $i');"; i=$((i+1)); done
    sqlite3 "$w/changes.db" "$sql"
  fi
  cp "$KLAWDE/template/check-log.sh" "$w/.claude/check-log.sh"
  # Extract complete CLI commands, including quoted heredocs.
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

echo "=== S24: a present changes.db is checked and repaired whatever its version ==="
d="$(mkfx s24)"; sqlite3 "$d/changes.db" < "$KLAWDE/template/changes-schema.sql"
sqlite3 "$d/changes.db" 'DROP TRIGGER entries_no_update; DROP TRIGGER entries_no_delete; DROP TRIGGER links_no_update; DROP TRIGGER links_no_delete; DROP TRIGGER areas_no_update; DROP TRIGGER areas_no_delete; DROP TRIGGER entries_no_replace; DROP VIEW concern_lines;'
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
echo "$out" > "$BASE/s24.out"
check "S24 exit 0" test "$rc" -eq 0
check "S24 restored objects reported by name" \
  bash -c "grep -q 'restored missing:.*entries_no_update' '$BASE/s24.out' && grep -q 'restored missing:.*concern_lines' '$BASE/s24.out'"
check "S24 full trigger set back" test "$(tc "$d/changes.db")" = "$have"
check "S24 log protected again" bash -c "sqlite3 '$d/changes.db' \"INSERT INTO entries (type,description) VALUES ('note','x');\" && ! sqlite3 '$d/changes.db' 'DELETE FROM entries;' 2>/dev/null"
check "S24 repaired db identical to a fresh install" same_as_fresh "$d/changes.db"
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
  bash -c "test $rc -ne 0 && echo \"$out\" | grep -q 'lacks the links table' && grep -q 'OLD CONTRACT' '$d/CLAUDE.md'"

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

echo "=== S34: objects the shipped schema does not define ==="
# An extra trigger can silence inserts (RAISE(IGNORE)): refused before any
# write, and sent to git rather than upgrade.sh.
d="$(mkfx s34trig)"; sqlite3 "$d/changes.db" < "$KLAWDE/template/changes-schema.sql"
sqlite3 "$d/changes.db" "CREATE TRIGGER silent_drop BEFORE INSERT ON entries BEGIN SELECT RAISE(IGNORE); END;"
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
# An extra table or view cannot weaken the log: reported, left alone, never dropped by a repair.
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
# A view on its own, with no unexpected table sorting ahead of it, is the case
# that catches a repair dispatching on object kind alone.
d="$(mkfx s34view)"; sqlite3 "$d/changes.db" < "$KLAWDE/template/changes-schema.sql"
sqlite3 "$d/changes.db" "CREATE VIEW my_report AS SELECT serial FROM entries; DROP TRIGGER entries_no_delete;"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
check "S34 upgrade completes with an extra view alone" test "$rc" -eq 0
check "S34 an extra view is never dropped by the repair" \
  test "$(sqlite3 -readonly "$d/changes.db" "SELECT count(*) FROM sqlite_master WHERE name='my_report';")" = "1"
check "S34 its missing trigger was still restored" \
  test "$(sqlite3 -readonly "$d/changes.db" "SELECT count(*) FROM sqlite_master WHERE name='entries_no_delete';")" = "1"

echo "=== S36: a CLAUDE.md with no klawde files beside it is overwritten only after confirmation ==="
d="$BASE/s36"; mkdir -p "$d"; echo "MY OWN CONTRACT" > "$d/CLAUDE.md"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup < /dev/null 2>&1)"; rc=$?
check "S36 non-interactive overwrite refused" bash -c "test $rc -ne 0 && echo \"$out\" | grep -q 'cannot confirm overwriting a possibly foreign CLAUDE.md'"
check "S36 CLAUDE.md untouched" grepq 'MY OWN CONTRACT' "$d/CLAUDE.md"
out="$(cd "$d" && printf 'n\n' | "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
check "S36 declining aborts, nothing written" bash -c "test $rc -ne 0 && grep -q 'MY OWN CONTRACT' '$d/CLAUDE.md' && ! test -e '$d/.claude'"
out="$(cd "$d" && printf 'y\n' | "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
check "S36 confirming overwrites" bash -c "test $rc -eq 0 && cmp -s '$KLAWDE/template/CLAUDE.md' '$d/CLAUDE.md'"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup < /dev/null 2>&1)"; rc=$?
check "S36 a real install is then upgraded without a prompt" test "$rc" -eq 0

echo "=== S37: a CHANGES.md with no changes.db is refused before any write ==="
d="$(mkfx s37)"; echo '2025-01-10: legacy' > "$d/CHANGES.md"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
check "S37 exit nonzero, names the commit that still migrates" bash -c "test $rc -ne 0 && echo \"$out\" | grep -q '185c63a'"
check "S37 nothing written" bash -c "grep -q 'OLD CONTRACT' '$d/CLAUDE.md' && ! test -e '$d/changes.db' && test -f '$d/CHANGES.md'"

echo "=== S38: a v3 log with rows upgrades in place, rows intact, and reports its open concerns ==="
d="$(mkfx s38)"; mk_old_db "$d/changes.db" 3
sqlite3 "$d/changes.db" "INSERT INTO areas VALUES ('cli'); INSERT INTO entries (type,area,description) VALUES ('doc','-','Initialized.'); INSERT INTO entries (type,area,description,refs) VALUES ('decision','cli','Chose A over B; B double-bills','abc1'); INSERT INTO links VALUES (2,1,'closes'); INSERT INTO concerns (area,concern) VALUES ('cli','saw; breaks; settles'); INSERT INTO concerns (area,concern,ref_serial) VALUES ('cli','saw; breaks; settles',2); INSERT INTO concerns (concern) VALUES ('old; old; old'); UPDATE concerns SET resolved=date('now','localtime'), resolution='done' WHERE id=3;"
rows='SELECT * FROM entries; SELECT * FROM links; SELECT * FROM concerns; SELECT * FROM areas;'
before="$(sqlite3 -readonly "$d/changes.db" "$rows")"
out="$(cd "$d" && "$KLAWDE/upgrade.sh" --claude --no-backup 2>&1)"; rc=$?
printf '%s\n' "$out" > "$BASE/s38.out"
check "S38 exit 0" test "$rc" -eq 0
check "S38 schema identical to a fresh install" same_as_fresh "$d/changes.db"
check "S38 every row survives unchanged" test "$before" = "$(sqlite3 -readonly "$d/changes.db" "$rows")"
check "S38 open concerns reported with the untied count" grepq '2 open concern(s), 1 without a log reference' "$BASE/s38.out"
# The retire statement close.md ships must touch only open rows without a reference.
retire="$(sed -n '/^UPDATE concerns SET resolved.*ref_serial IS NULL;$/p' "$KLAWDE/template/close.md")"
check "S38 close.md ships one retire statement" test "$(printf '%s\n' "$retire" | grep -c .)" -eq 1
check "S38 the retire statement resolves only untied open rows" \
  bash -c "sqlite3 '$d/changes.db' \"$retire\" && test \"\$(sqlite3 -readonly '$d/changes.db' 'SELECT count(*) FROM concerns WHERE resolved IS NULL;')\" = 1 && test \"\$(sqlite3 -readonly '$d/changes.db' 'SELECT id FROM concerns WHERE resolved IS NULL;')\" = 2 && test \"\$(sqlite3 -readonly '$d/changes.db' 'SELECT resolution FROM concerns WHERE id=3;')\" = done"

echo "=== S39: /close checks the log before its first write, and again after its last ==="
# A damaged schema can silence an insert or accept one it should refuse, so the
# order of the commands close.md ships is part of the protocol.
s39_line() { grep -n "$1" "$KLAWDE/template/close.md" | cut -d: -f1 | "$2" -1; }
first_check="$(s39_line '^bash \.claude/check-log\.sh' head)"; last_check="$(s39_line '^bash \.claude/check-log\.sh' tail)"
first_write="$(s39_line '^sqlite3 -bail' head)"; last_write="$(s39_line '^sqlite3 -bail' tail)"
check "S39 close.md ships database writes and two checker runs" \
  bash -c "test -n '$first_write' && test \"\$(grep -c '^bash \\.claude/check-log\\.sh' '$KLAWDE/template/close.md')\" -eq 2"
check "S39 the first checker run precedes the first write" test "${first_check:-0}" -lt "${first_write:-0}"
check "S39 the last checker run follows the last write" test "${last_check:-0}" -gt "${last_write:-0}"
# What the early check exists for: both failures exit 0 and only the checker sees them.
d="$BASE/s39"; mkdir -p "$d"
for c in silenced unguarded; do sqlite3 "$d/$c.db" < "$KLAWDE/template/changes-schema.sql"; done
sqlite3 "$d/silenced.db" "CREATE TRIGGER quiet BEFORE INSERT ON entries BEGIN SELECT RAISE(IGNORE); END;"
sqlite3 "$d/unguarded.db" "DROP TRIGGER entries_one_line;"
check "S39 a silenced insert exits 0 and records nothing; the checker refuses that log" \
  bash -c "sqlite3 -bail '$d/silenced.db' \"INSERT INTO entries (type,description) VALUES ('decision','lost');\" && test \"\$(sqlite3 -readonly '$d/silenced.db' 'SELECT count(*) FROM entries;')\" = 0 && ! bash '$KLAWDE/template/check-log.sh' '$d/silenced.db' '$KLAWDE/template/changes-schema.sql' >/dev/null 2>&1"
check "S39 an unguarded log accepts a two-line entry for good; the checker refuses that log" \
  bash -c "sqlite3 -bail '$d/unguarded.db' \"INSERT INTO entries (type,description) VALUES ('note','one'||char(10)||'two');\" && test \"\$(sqlite3 -readonly '$d/unguarded.db' 'SELECT count(*) FROM entries;')\" = 1 && ! bash '$KLAWDE/template/check-log.sh' '$d/unguarded.db' '$KLAWDE/template/changes-schema.sql' >/dev/null 2>&1"

echo "=== S35: every shipped script parses ==="
# bash -n takes one script; each is verified on its own.
for f in setup.sh upgrade.sh lib.sh template/check-log.sh tests/verify.sh; do
  check "S35 $f parses" /bin/bash -n "$KLAWDE/$f"
done

echo ""
echo "RESULT: $pass passed, $fail failed"
exit "$fail"
