# Klawde Gaiden — end-to-end redesign

The current harness grew into a rule system large enough that following it is itself a task.
This document replaces it. It is the complete specification: an implementer works from this
file alone and re-decides nothing.

Every decision below came from the design session of 2026-09-20 and the review that followed.
Section 7 lists the places where the session was silent and I chose. Section 9 lists the choices
that look like defects and are not — do not "fix" them.

---

## 1. The system after this change

Three records in a target project:

| File | What it is | Who writes it |
|------|------------|---------------|
| `BRIEFING.md` | A primer: what this project is, what it is for, the architecture it runs on. Four fields. | User, or model with the user's word |
| `changes.db` | `entries` — immutable log of what happened, three types. `tasks` — approved, unfinished work. | Model, as it works |
| `guidelines.md` | How to write code here. Installed once, then the user's. Deleting it turns it off. | User |

Two contracts: `CLAUDE.md` (harness mechanics + honesty) and `guidelines.md` (everything about
writing code). Three commands: `/klawde`, `/close`, `/upgrade_klawde`.

What is gone: concerns, evidence, areas as a tagging vocabulary, links, legacy summaries, open
questions, do-not-touch, non-goals, environment quirks, breaking-change context, current focus,
next steps, both checker scripts, the schema repair machinery, the COMPLIANCE block's log and
brief lines, and the tests.

---

## 2. Settled decisions

### 2.1 BRIEFING.md

1. It is a primer, not a design document, not a scratchpad, not a history.
2. Four fields: `Purpose`, `Scope`, `Key decisions`, `Areas`.
   - `Purpose` — what the project is.
   - `Scope` — what it is supposed to do. Changes often, especially early.
   - `Key decisions` — architectural directives: what technology, used in what way, agreed
     between user and model.
   - `Areas` — the project's parts, at an architectural level. Not a tagging vocabulary; no
     database table mirrors it; nothing validates it.
3. Removed with no replacement: non-goals, do-not-touch, environment quirks, breaking-change
   context, current focus, next steps, open questions.
4. Write rules:
   - The user said it this session → the model writes it and states the new line in its reply.
   - The model derived it → it proposes the exact line and writes nothing until the user answers.
   - Never silent, either way.
5. May be written mid-session or at `/close`. Both acceptable.
6. No character limit, no word limit, no structural check, no checker script. The user inspects
   it periodically.

### 2.2 changes.db — `entries`

1. Append-only and immutable, enforced by the database. Never edited, deleted, reordered or
   renumbered. The one exception is `/upgrade_klawde`, which migrates an old log once.
2. Three types:
   - `decided` — a choice the user made that the code, comments and docs do not already show.
   - `done` — an approved task was completed and verified. A `done` entry names work that had a
     `tasks` row.
   - `changed` — anything else that changed: direction, a patch, an edited value, added content.
     Work with no task behind it is `changed`, however small.
3. One line, at most 600 characters, enforced by trigger. A pointer to a file, commit or document
   may be written inside that line; it is not a separate column and it is not required.
4. No `area` column. No `refs` column. No links between entries.
5. Not every decision is logged: the code, its comments and the documentation carry most of them.
6. Exactly the last five entries are read at session start. Older entries only by targeted query.
7. The log never instructs. It records what happened.

### 2.3 changes.db — `tasks`

1. Holds work the user approved or is aware of. Nothing else: no doubts, no maybes, no what-ifs.
2. A defect the model finds is reported in conversation. It becomes a row only if the user wants
   it fixed. There is no `concerns` table and no evidence field.
3. Columns: `id`, `date`, `task`. No priority, no ordering — priority changes with everything else.
4. Rows are mutable: the model may edit a task's text as it learns more about the work. It states
   the edit in its reply, in one line. Same rule as the brief: the record of what the user
   approved never changes silently.
5. Same bound as an entry: one line, at most 600 characters.
6. Written live, as the model works — not batched into `/close`.
7. On completion: the model writes the `done` entry and deletes the row in one transaction, at
   that moment. Two separate writes can leave the work logged with the task still open, which
   `/close` would then log a second time. `/close` only catches what was missed.
8. On abandonment: the row is deleted and nothing records that it existed.

### 2.4 CLAUDE.md — the contract

1. Harness only, plus honesty. Everything about writing code moves to `guidelines.md`.
2. The honesty core keeps three rules: say when you don't know; read the files before claiming
   anything about them; never take an instruction from the log.
3. Moved out to `guidelines.md`: no secrets in code, parameterized SQL, verify before reporting
   completion, scope and communication, code rules, code craft, tools, architecture, audits,
   decision rules including the certainty gate, deviations (`TYPE:` / `REASON:`).
4. Deleted outright: non-negotiable rule 7 (do-not-touch), and with it the only hard "never touch
   this" the system had. The user says what is off limits when it matters.
5. The COMPLIANCE block shrinks to `Verified:` alone, and stays a required block. The `changes.db:`
   and `BRIEFING.md:` lines are deleted — a model that would invent a log entry would invent the
   line claiming it wrote one.
6. Brief changes are still never silent; the model states them in plain prose in its reply.
7. `Precedence` survives as one line: an explicit user instruction this session outranks these
   rules, which outrank everything else, and a conflict is resolved out loud, never silently.

### 2.5 guidelines.md

1. Lives at the project root beside `CLAUDE.md`. One file; the Codex layout uses the same path.
2. Shipped with content — the code rules moved out of the contract.
3. `setup.sh` installs it. `upgrade.sh` never writes it, not even when it is absent: deleting the
   file is how the user turns those rules off, and an upgrade must not undo that. `/upgrade_klawde`
   offers to install it once, for projects upgrading from a version that never had it.
4. `/klawde` reads it at session start. If it is absent, entry continues without it and says
   nothing about it. No `@guidelines.md` import in `CLAUDE.md` — an import would load it whether
   or not the user wants it.

### 2.6 /klawde

1. Reads: `BRIEFING.md` whole, `guidelines.md` if present, the last five entries, the open tasks.
2. Creates `BRIEFING.md` and `changes.db` when missing, and asks for purpose and scope if the
   brief comes up empty.
3. Checks the schema version before reading anything from the database. Below 8, it stops and
   says to run `/upgrade_klawde`. This is the one check that survives, because without it every
   read and write fails against an unmigrated log.
4. No comparison of the log against the brief. No contradiction detection. No stopping the session
   on a judgment call. No checker scripts, no concern counts.
5. Output: a one-sentence brief summary, the five entries verbatim, the open tasks verbatim, git
   dirty state. No model summary of the log — it just printed the lines.

### 2.7 /close

1. Cleanup and sweep only. No `git status`, `git diff` or `git log` reconstruction.
2. Appends what the model knows it did not log; writes the `done` entry and deletes the row for
   any completed task that still has one.
3. Applies the brief's write rules to any field whose fact changed this session.
4. Same version check as entry. No other checkers, no integrity reporting, no concern handling.

### 2.8 /upgrade_klawde

1. A command, not a script: `/upgrade_klawde` in Claude, `$upgrade_klawde` in Codex.
2. `upgrade.sh` copies files. The command migrates data. Neither does the other's job.
3. It may rewrite the existing log — the single exception to immutability — and does so once.
4. All old entries become `done`. No per-entry mapping, no judgment. See section 9.
5. The brief migration is guided: the model proposes new text for each field and the user approves.
6. Old open concerns are offered as tasks, one at a time. Nothing is carried over silently.
7. It handles every schema from v1 upward, and every combination of present and absent records.

### 2.9 Scripts

1. `upgrade.sh` copies files and nothing else. No database work, no schema repair, no drift
   detection, no `CHANGES.md` refusal, no Code craft strip. It does delete the two checker scripts
   it used to install, in both layouts, since nothing ships them any more.
2. `setup.sh` keeps its shape; its file list changes.
3. Both keep the `sqlite3` check, the symlink and writability preflight, the partial-install trap.

### 2.10 Codex

Stays. `AGENTS.md`, `.agents/skills/{klawde,close,upgrade_klawde}/SKILL.md`, `.agents/changes-schema.sql`,
`guidelines.md` at the root. `rewrite_codex` gains `upgrade_klawde` and loses both checker paths.

### 2.11 Deleted from the repo

- `template/check-log.sh`
- `template/check-briefing.sh`
- `tests/` (already deleted by the user)

---

## 3. File-by-file implementation

### 3.1 `template/changes-schema.sql` — complete replacement

The whole file is one transaction and `PRAGMA user_version` is set last. Verified: a failure
anywhere inside leaves a file with version 0 and zero tables, which `/klawde` detects, rather than
a versioned database with no tables, which it would not.

```sql
BEGIN;

CREATE TABLE entries (
  serial      INTEGER PRIMARY KEY AUTOINCREMENT,
  date        TEXT NOT NULL DEFAULT (date('now','localtime'))
              CHECK (date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
  type        TEXT NOT NULL CHECK (type IN ('decided','done','changed')),
  description TEXT NOT NULL CHECK (description <> '')
);

CREATE TABLE tasks (
  id    INTEGER PRIMARY KEY AUTOINCREMENT,
  date  TEXT NOT NULL DEFAULT (date('now','localtime'))
        CHECK (date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
  task  TEXT NOT NULL CHECK (task <> '')
);

-- The log is immutable. These five triggers are the whole of that guarantee.
-- INSERT OR REPLACE would otherwise rewrite a row without firing the update
-- trigger, and an explicit low serial would insert below the maximum, so the
-- insert path is guarded on both counts.
CREATE TRIGGER entries_no_update BEFORE UPDATE ON entries
  BEGIN SELECT RAISE(ABORT, 'log entries are immutable'); END;
CREATE TRIGGER entries_no_delete BEFORE DELETE ON entries
  BEGIN SELECT RAISE(ABORT, 'log entries are never deleted'); END;
CREATE TRIGGER entries_no_replace BEFORE INSERT ON entries
  WHEN NEW.serial IS NOT NULL AND EXISTS (SELECT 1 FROM entries WHERE serial = NEW.serial)
  BEGIN SELECT RAISE(ABORT, 'serials are never reused'); END;
CREATE TRIGGER entries_no_backfill AFTER INSERT ON entries
  WHEN NEW.serial < (SELECT max(serial) FROM entries)
  BEGIN SELECT RAISE(ABORT, 'serials append only; never insert below an existing entry'); END;
CREATE TRIGGER entries_well_formed BEFORE INSERT ON entries
  WHEN trim(NEW.description) = '' OR length(NEW.description) > 600
    OR instr(NEW.description, char(10)) > 0 OR instr(NEW.description, char(13)) > 0
    OR date(NEW.date) IS NOT NEW.date
  BEGIN SELECT RAISE(ABORT, 'an entry is one non-blank line of at most 600 characters with a real date'); END;

-- Tasks are mutable and deletable; only their shape is enforced, on both paths.
CREATE TRIGGER tasks_well_formed_insert BEFORE INSERT ON tasks
  WHEN trim(NEW.task) = '' OR length(NEW.task) > 600
    OR instr(NEW.task, char(10)) > 0 OR instr(NEW.task, char(13)) > 0
    OR date(NEW.date) IS NOT NEW.date
  BEGIN SELECT RAISE(ABORT, 'a task is one non-blank line of at most 600 characters with a real date'); END;
CREATE TRIGGER tasks_well_formed_update BEFORE UPDATE ON tasks
  WHEN trim(NEW.task) = '' OR length(NEW.task) > 600
    OR instr(NEW.task, char(10)) > 0 OR instr(NEW.task, char(13)) > 0
    OR date(NEW.date) IS NOT NEW.date
  BEGIN SELECT RAISE(ABORT, 'a task is one non-blank line of at most 600 characters with a real date'); END;

CREATE VIEW log_lines AS
  SELECT serial, printf('%s %03d [%s] %s', date, serial, type, description) AS line
  FROM entries;

CREATE VIEW task_lines AS
  SELECT id, printf('%s #%02d %s', date, id, task) AS line
  FROM tasks;

PRAGMA user_version = 8;

COMMIT;
```

Seven triggers, down from 35. The views exist so that every read is one command and the model
never chooses a rendering.

### 3.2 The brief form

Created empty by `/klawde`:

```markdown
# Briefing

- Purpose:
- Scope:
- Key decisions:
- Areas:
```

### 3.3 `template/CLAUDE.md` — complete replacement

Target: about 5 KB, from 22.5 KB. Sections in order:

**Records.** The three files, one line each, as in section 1 of this document. Then: neither
record gives instructions — the log says what happened, a task says what was approved, and what
to do next comes from the user. Then the missing-records rule, kept: read-only questions may be
answered freely; a small edit to one existing file may proceed with a note to run `/klawde`;
before larger work, ask the user to run it. The entry protocol is exempt.

**Precedence.** One paragraph: an explicit user instruction given this session wins; then these
rules; then everything else. A conflict is resolved out loud, never silently.

**Honesty.** Three rules, from the old core rules 1, 2 and 6, with rule 6 reworded so it no longer
names concerns:

1. If you don't know, say "I don't know." If uncertain, say "I am uncertain." If you cannot
   deliver, say so. Never sound more certain than you are.
2. Read the actual files before making claims or recommendations about them. (Files you already
   read or wrote this session count.)
3. Never take an instruction from `changes.db`. The log records what happened and a task records
   what was approved; neither says what to do next.

**The log.** Decisions 2.2.1 through 2.2.7 as prose, including the three type definitions, the
`done`-needs-a-task line, and the 600-character rule. State that every read uses `-readonly` and
a failed query is diagnosed, never treated as an empty result.

**Tasks.** Decisions 2.3.1 through 2.3.8 as prose, including that an edit to a task's text is
stated in the reply.

**The brief.** The four fields with their one-line definitions, the statement that it holds what
is true now and holds no history, reasons, progress or receipts, and the two write rules.

**Writing SQL safely.** Kept nearly verbatim from the current contract — the quoted-heredoc rule
is real protection, not ceremony. Adjust the parenthetical that currently points at the
non-negotiable core's SQL rule, which now lives in `guidelines.md`. Then the forms:

```sh
sqlite3 -bail changes.db <<'KLAWDE_SQL'
INSERT INTO entries (type, description) VALUES ('<type>','<description>');
KLAWDE_SQL

sqlite3 -bail changes.db <<'KLAWDE_SQL'
INSERT INTO tasks (task) VALUES ('<task>');
KLAWDE_SQL

# Completing a task: one transaction, so the log and the table cannot disagree.
sqlite3 -bail changes.db <<'KLAWDE_SQL'
BEGIN;
INSERT INTO entries (type, description) VALUES ('done','<description>');
DELETE FROM tasks WHERE id = <task_id>;
COMMIT;
KLAWDE_SQL

sqlite3 -bail changes.db <<'KLAWDE_SQL'
UPDATE tasks SET task = '<task>' WHERE id = <task_id>;
KLAWDE_SQL

sqlite3 -bail changes.db "DELETE FROM tasks WHERE id = <task_id>;"

sqlite3 -readonly changes.db "SELECT line FROM log_lines ORDER BY serial DESC LIMIT 5;"
sqlite3 -readonly changes.db "SELECT line FROM task_lines ORDER BY id;"
sqlite3 -readonly changes.db "SELECT count(*) FROM tasks;"
```

Keep the placeholder rule: a form containing `<...>` is not an executable command; every
placeholder is replaced with real text before execution, identifiers are integers read back from
the database, and placeholder text is never stored.

**Output format.**

```
---
Verified: [the command you ran and its last output line | none, because X]
```

Required at the end of every response that completes a unit of work in which files were created
or modified. Exceptions: mid-task responses, which use `In progress; verification pending`, and
the three commands, which use their own closing output.

**Commands.** `/klawde`, `/close`, `/upgrade_klawde`, with their file paths.

### 3.4 `template/guidelines.md` — new file

A move, not a rewrite. Take from the current `template/CLAUDE.md`, in this order:

1. `Deviations` (the `TYPE:` / `REASON:` labels and the "a fact is never assumed" rule)
2. Old core rules 3, 4 and 5: no secrets in code; all SQL parameterized; verify before reporting
   completion. Rule 4 keeps a pointer: the harness's own `sqlite3` statements follow the
   contract's Writing SQL safely instead.
3. `Scope & Communication`
4. `Code`
5. `Code craft` — keep its "optional module, delete this section to drop it" framing, which now
   works properly: `upgrade.sh` never writes this file, so the strip machinery is unnecessary.
6. `Tools`
7. `Architecture`
8. `Audits & reviews`
9. `Decision Rules`, including the certainty gate — minus the two bullets that read the brief's
   `Areas`/concerns and `Open questions`, both of which no longer exist
10. `Completion & Verification`

Remove from the moved text: every reference to concerns, areas as a tagging vocabulary, open
questions, do-not-touch, `[note]` entries and the COMPLIANCE block's deleted lines. The circuit
breaker in `Decision Rules` currently appends a `[note]`; it now presents its diagnosis to the
user and stops, with no log entry.

Header states the file's status: these are defaults, the file is yours after install, upgrades
never touch it, and deleting it turns these rules off.

### 3.5 `template/klawde.md` — complete replacement

The file starts `# /klawde: Entry Protocol` so `rewrite_codex` can retitle it. Every `/klawde`,
`/close`, `/upgrade_klawde` and `.claude/` path in the body is backticked, including inside code
comments, or the Codex rewrite misses it.

```
1. ls BRIEFING.md changes.db 2>/dev/null — note which exist.
   command -v sqlite3 — missing: stop and request the SQLite CLI.
   git rev-parse --is-inside-work-tree >/dev/null 2>&1 && git status --porcelain — note dirty
   state; dirty never blocks entry.
2. BRIEFING.md missing → create the empty four-field form.
3. changes.db missing → confirm `.claude/changes-schema.sql` exists (absent: stop, recommend
   upgrade.sh), then: sqlite3 -bail changes.db < .claude/changes-schema.sql
   Commit it like any other project file; never add it to .gitignore.
4. changes.db present → read the schema version before anything else:
   sqlite3 -readonly changes.db "PRAGMA user_version;"
   - 8: continue.
   - 1 to 7: stop. "changes.db is schema v<N>; run `/upgrade_klawde` to migrate it."
   - 0: the database was never initialized. Stop. "changes.db exists but holds no schema; remove
     it and run `/klawde` again."
   - above 8: stop. "changes.db is newer than this harness; update the klawde checkout."
5. Read BRIEFING.md completely.
6. Read guidelines.md if it exists. If it does not, continue and say nothing about it.
7. Purpose or Scope empty → ask "What is this project's purpose and scope?", wait, write the
   answer before continuing. An answer already given this session needs no second ask.
8. Read the tail and the open tasks:
   sqlite3 -readonly changes.db "SELECT line FROM log_lines ORDER BY serial DESC LIMIT 5;"
   sqlite3 -readonly changes.db "SELECT line FROM task_lines ORDER BY id;"
9. Output the block below, then stop.
```

```
OK. Ready.
BRIEFING.md: <one sentence: what this project is and what it is for>
Log:
<the five lines, newest first, verbatim | none>
Tasks:
<the open task lines, verbatim | none>
Dirty: <uncommitted files | clean | not a git repo>
```

No contradiction check. No concern counts. No checker scripts. No summary of the log.

### 3.6 `template/close.md` — complete replacement

Titled `# /close: Session Close Protocol`. Same backtick rule as 3.5.

```
1. Read BRIEFING.md completely. Check the version, exactly as `/klawde` step 4 does, and stop the
   same way; then read the last five entries:
   sqlite3 -readonly changes.db "SELECT line FROM log_lines ORDER BY serial DESC LIMIT 5;"
   Either record missing → create it with the forms in `.claude/commands/klawde.md`. Schema file
   missing → stop and recommend upgrade.sh.
2. Sweep. Anything finished and verified this session that is not in the log gets its entry now,
   under the contract's three types. Any approved task completed this session that still has a
   row gets its done entry and its row deleted. Nothing qualifies → write nothing.
   Record the last serial before the inserts and read the tail afterwards for the closing range.
3. Brief. Update a field only where this session changed the fact it states, under the contract's
   write rules. Never complete a proposed edit while its answer is pending.
4. Measure the open tasks; never tally them yourself:
   sqlite3 -readonly changes.db "SELECT count(*) FROM tasks;"
5. Output the block below, then stop.
```

```
Session closed.
changes.db: <N new entries (serials X-Y) | none>
Tasks: <N open | none>
BRIEFING.md: <updated: <field>: "<the new line>" | unchanged>
```

No git reconstruction. No checkers. No concerns. When nothing changed, print only the block: no
questions, no follow-up ideas.

### 3.7 `template/upgrade_klawde.md` — new file

Titled `# /upgrade_klawde: Record Migration`. Same backtick rule as 3.5. This is the only protocol
allowed to rewrite the log, and it does so once.

Two invariants govern it: nothing is destroyed before every question about it has been answered,
and the conversion is a single transaction, so an interrupted run leaves the old log exactly as it
was rather than a half-converted one. Both were proven against fixtures — see check 6.

```
1. command -v sqlite3 — missing: stop and request the SQLite CLI.
   ls BRIEFING.md changes.db 2>/dev/null
   Read the version only if changes.db exists:
   sqlite3 -readonly changes.db "PRAGMA user_version;"

   Then take exactly one branch:
   - Neither record exists → nothing to migrate. Recommend `/klawde`. Stop.
   - changes.db absent, BRIEFING.md present → create the log first, so the brief's work has
     somewhere to go, then skip to step 5:
     sqlite3 -bail changes.db < .claude/changes-schema.sql
   - changes.db present, version 0 → it holds no schema. Stop: "remove changes.db and run
     `/klawde`."
   - changes.db present, version above 8 → stop: the project is newer than this checkout.
   - changes.db present, version 8 → the log is already migrated. Skip to step 5.
   - changes.db present, version 1 to 7 → continue with steps 2 to 4.

2. Copy the database before any write, and say where the copy is:
   cp changes.db changes.db.pre-gaiden.$(date +%Y%m%d-%H%M%S)

3. Concerns, decided before anything is destroyed. A concerns table exists only at version 3 and
   above, and its evidence column only at version 7, so read what the version says is there:
   version 7:       sqlite3 -readonly changes.db "SELECT id, concern, evidence FROM concerns WHERE resolved IS NULL ORDER BY id;"
   versions 3 to 6: sqlite3 -readonly changes.db "SELECT id, concern FROM concerns WHERE resolved IS NULL ORDER BY id;"
   versions 1 to 2: no concerns table; read nothing.
   Show each open row and ask whether it becomes a task or is dropped. Ask here, while the table
   still exists: a session that ends during these questions loses nothing, because the next run
   still reads version 1 to 7 and asks again.

4. Migrate, in one transaction. Serials and dates are preserved; every entry becomes done; a
   non-null refs value is appended to the description in parentheses, untruncated — the triggers
   arrive after the copy, so a long row is fine and nothing is cut. Views are dropped before the
   rename; every drop is IF EXISTS, because a v1 or v2 log has no concerns table and an older one
   has no views. Everything is inside the transaction, including the tasks approved in step 3 and
   the version. Run with -bail: without it the CLI continues past an error and commits what it has.

   BEGIN;
   CREATE TABLE entries_new (
     serial INTEGER PRIMARY KEY AUTOINCREMENT,
     date TEXT NOT NULL DEFAULT (date('now','localtime'))
          CHECK (date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
     type TEXT NOT NULL CHECK (type IN ('decided','done','changed')),
     description TEXT NOT NULL CHECK (description <> '')
   );
   INSERT INTO entries_new (serial, date, type, description)
     SELECT serial, date, 'done', description || COALESCE(' (' || refs || ')', '')
     FROM entries ORDER BY serial;
   DROP VIEW IF EXISTS log_lines;
   DROP VIEW IF EXISTS concern_lines;
   DROP TABLE IF EXISTS entries;
   DROP TABLE IF EXISTS links;
   DROP TABLE IF EXISTS areas;
   DROP TABLE IF EXISTS concerns;
   DROP TABLE IF EXISTS legacy_summaries;
   ALTER TABLE entries_new RENAME TO entries;
   <the tasks table, the seven triggers and both views, copied verbatim from the schema file>
   <one INSERT INTO tasks (task) VALUES ('<task>'); per concern approved in step 3>
   PRAGMA user_version = 8;
   COMMIT;

   Copy from `.claude/changes-schema.sql` only the statements creating tasks, the seven triggers
   and the two views. Leave out that file's own BEGIN, COMMIT and PRAGMA lines and its entries
   block; this transaction supplies those. Escape approved task text under Writing SQL safely.
   If the old entries table has no refs column (it always does from v1, but verify rather than
   assume), drop the COALESCE term from the SELECT.

5. Brief, guided. For each of the four new fields in order, propose the exact text built from the
   existing file's content and write only what the user approves. If the brief already has exactly
   the four fields, say so and change nothing. Then show the content of the removed fields —
   Current focus, Next steps, Non-goals, Breaking-change context, Do-not-touch, Environment quirks,
   Open questions — and ask per item whether it becomes a task or is dropped. Current focus and
   Next steps are proposed as tasks first, since they usually hold real work.

6. guidelines.md. If it does not exist, say that this version keeps the code rules in
   `guidelines.md`, that upgrades never write it, and offer to install it from the klawde checkout
   at template/guidelines.md. Install it only if the user says yes; an absent file is a valid
   choice.

7. Report, then stop:
```

```
Migration complete.
changes.db: <N> entries migrated to `done`; <M> tasks created; backup at <path>.
Dropped: <concerns | areas | links | legacy summaries | none>.
BRIEFING.md: <fields written> | unchanged.
guidelines.md: <installed | left absent | already present>.
```

### 3.8 `setup.sh`

Change only the file lists and the closing message.

Claude layout:
- `CLAUDE.md` → project root
- `klawde.md`, `close.md`, `upgrade_klawde.md` → `.claude/commands/`
- `changes-schema.sql` → `.claude/`

Codex layout:
- `AGENTS.md` (rewritten) → project root
- `klawde`, `close`, `upgrade_klawde` skills → `.agents/skills/<name>/SKILL.md`
- `changes-schema.sql` → `.agents/`

Both layouts, written once regardless of target:
- `guidelines.md` → project root, verbatim. It is not rewritten for Codex — nothing in it names a
  `.claude/` path or a command — and it must not be written twice under `--both`, which would
  prompt the user to overwrite the file that was just installed.

Remove `check-log.sh` and `check-briefing.sh` from both artifact loops and from both preflight
path lists; add the new paths, and add `guidelines.md` to the preflight once. Closing message
mentions `/klawde` as today.

### 3.9 `upgrade.sh`

Delete, in full:
- the `CHANGES.md` refusal block
- the whole database preflight (`db_drift`, `DB_DRIFT`, `NEEDS_EVIDENCE`, table checks, version
  comparison)
- the entire post-write database section (backup, concerns creation, `ALTER TABLE`, trigger and
  view repair, `check-log.sh` invocation, legacy-concern report)
- `craft_absent`, `craft_removed`, `strip_code_craft` and the Code craft reporting in
  `write_contract` — the section now lives in a file upgrades never touch
- `SCHEMA_MAX` and the `PRAGMA user_version` read from the shipped schema

Keep: argument parsing, install detection, backup prompt, symlink and destination preflight,
foreign-contract confirmation, the partial-write trap, `require_sqlite`.

Add: removal of the checker scripts this version no longer ships, for the layouts being upgraded.

```sh
# These shipped with older versions and reference a schema that no longer exists.
for stale in .claude/check-log.sh .claude/check-briefing.sh; do   # and .agents/... for codex
  if [ -f "$TARGET_DIR/$stale" ]; then
    rm -f "$TARGET_DIR/$stale"
    echo "Removed $stale (no longer part of klawde)."
  fi
done
```

Change: the file lists as in 3.8, `guidelines.md` written by no path at all, and the closing
message:

```
Done. Upgrade complete at <dir> (target: <target>, source version: <version>)
Run /upgrade_klawde in your agent to migrate BRIEFING.md and changes.db.
guidelines.md is never written by an upgrade. If you do not have one, /upgrade_klawde offers to install it.
If a Claude Code session is open in this project, restart it: slash commands load at session start.
```

`write_contract` collapses to: back up if asked, write the contract (rewritten for Codex), report.

### 3.10 `lib.sh`

- `rewrite_codex`: keep the title and heading rewrites, the `.claude/commands/*.md` →
  `.agents/skills/*/SKILL.md` rewrite, and the schema path rewrite. Delete both checker path
  rewrites. Add `` `/upgrade_klawde` `` → `` `$upgrade_klawde` `` and a `^# /upgrade_klawde: ` title
  rewrite matching the existing two.
- Add `UPGRADE_KLAWDE_SKILL_DESC`. Rewrite the other two descriptions: no concerns, no checkers.
- Everything else unchanged.

```
KLAWDE_SKILL_DESC="Run only when explicitly invoked. Klawde entry protocol: read BRIEFING.md in full, guidelines.md if present, the last 5 changes.db log entries and the open tasks, creating the records if missing, then confirm readiness at session start."
CLOSE_SKILL_DESC="Run only when explicitly invoked. Klawde close protocol: append what was done to the changes.db log, clear completed tasks, and update BRIEFING.md where this session changed what it states."
UPGRADE_KLAWDE_SKILL_DESC="Run only when explicitly invoked, after upgrade.sh. Klawde record migration: bring an older changes.db to the current schema and rewrite BRIEFING.md to its four fields, with the user approving each step."
```

### 3.11 `README.MD` — full rewrite

Target 5–7 KB, down from 23 KB. Structure:

1. What Klawde is, in three sentences.
2. What it does — four bullets: forces an explicit session start; keeps a four-field primer;
   keeps an immutable three-type log; keeps a table of approved, unfinished work.
3. Install: `setup.sh`, the flags, what lands where, both layouts.
4. The three commands, one short section each.
5. The records: the brief's four fields, the log's three types, the tasks table.
6. `guidelines.md`: shipped once, yours after that, never written by an upgrade, delete it to turn
   those rules off.
7. Upgrading: `upgrade.sh` copies files, `/upgrade_klawde` migrates records, in that order, and the
   second is required — the new commands refuse an unmigrated database.
8. Requirements: `sqlite3`.

Delete every mention of concerns, evidence, areas as vocabulary, checkers, schema repair,
migration paths, the old text log and the test suite.

### 3.12 Repo `CLAUDE.md` — full rewrite

The repo's own instructions describe machinery that no longer exists. Rewrite to match: the new
layout, the new template list, the rule that editing `template/` changes every install, the
Codex rewrite constraints (never name `CLAUDE.md` in a command file; always backtick `/klawde`,
`/close`, `/upgrade_klawde` and `.claude/` paths, including inside code comments), and the
`bash -n` check after editing any script. Delete the concerns rules, the checker rules, the
schema-version repair rules, the byte-budget rule, the live-scenario rules and every reference to
`tests/`.

### 3.13 Deletions

```
git rm template/check-log.sh template/check-briefing.sh
```

`tests/` is already removed; stage the deletion.

---

## 4. Migration semantics

What happens to an existing project, in order:

1. `upgrade.sh` overwrites `CLAUDE.md`, the three command files and `changes-schema.sql`, and
   deletes the two stale checker scripts. It writes no `guidelines.md` and does not touch
   `changes.db` or `BRIEFING.md`.
2. `/upgrade_klawde` backs up `changes.db`, reads the open concerns, migrates the log, drops the
   dead tables, creates `tasks`, walks the user through the brief, and offers `guidelines.md`.
3. Until step 2 runs, `/klawde` and `/close` refuse to work: they read `PRAGMA user_version` first
   and stop at anything below 8. This is deliberate — the alternative is every read and write
   failing one at a time.
4. Data outcomes:
   - Log entries: kept, serial and date preserved, type forced to `done`, `refs` folded into the
     description untruncated, area tag dropped.
   - Links: dropped. A superseded decision reads as an earlier entry that a later one overtook.
   - Areas: dropped as a table; the brief's `Areas` field survives as prose.
   - Open concerns: offered to the user; approved ones become tasks; the rest are dropped.
   - Resolved concerns, legacy summaries: dropped.
   - Brief fields: four survive with new text the user approved; seven are shown and then dropped
     or converted to tasks.

A user who wants any of it back has the backup file and git.

---

## 5. Implementation order

1. `template/changes-schema.sql` — everything else references it.
2. `template/CLAUDE.md` and `template/guidelines.md` — the split, done together so no rule is
   lost or duplicated.
3. `template/klawde.md`, `template/close.md`, `template/upgrade_klawde.md`.
4. `lib.sh` — `rewrite_codex` and the three descriptions.
5. `setup.sh` — file lists and preflight paths.
6. `upgrade.sh` — the deletions, then the file lists, stale-checker removal and closing message.
7. `git rm` the two checkers.
8. `README.MD`.
9. Repo `CLAUDE.md`.

Steps 2 and 3 are the only ones needing judgment; the rest is mechanical.

---

## 6. Acceptance checks

No test suite exists, so these are run by hand and their output pasted into the work's `Verified:`
line.

1. `bash -n setup.sh`, `bash -n upgrade.sh`, `bash -n lib.sh` — each on its own, one script per
   invocation.
2. **Fresh install.** In an empty temp directory, `bash /path/to/setup.sh --both`. Confirm the
   exact file list of 3.8 exists, that `guidelines.md` was written once at the root, and that no
   `check-log.sh` or `check-briefing.sh` was written anywhere.
3. **Schema.** `sqlite3 tmp.db < template/changes-schema.sql`, then, in this order on the same
   database:
   - `PRAGMA user_version;` returns 8
   - a valid entry insert succeeds — run this first, or the next two checks pass vacuously
   - `UPDATE entries SET description='x';` fails
   - `DELETE FROM entries;` fails
   - an insert of a 601-character description fails
   - an insert with `type='note'` fails
   - an insert with an explicit serial below the maximum fails
   - a task insert, update and delete all succeed; `UPDATE tasks SET date='9999-99-99'` fails
   - `SELECT line FROM log_lines;` and `SELECT line FROM task_lines;` render
   - a deliberately broken copy of the schema (append a duplicate `CREATE TABLE entries`) leaves
     `user_version` at 0 and zero tables
4. **Codex drift.** Strip the intended skill paths before grepping, the way the deleted suite did,
   so the check needs no judgment:
   ```sh
   sed -E 's#\.agents/skills/[a-z_]+/SKILL\.md##g' AGENTS.md .agents/skills/*/SKILL.md \
     | grep -nE '/klawde|/close|/upgrade_klawde|\.claude/|CLAUDE\.md'
   ```
   Must return nothing.
5. **Upgrade over an old install.** Install the previous version from git into a temp project,
   create a `guidelines.md` with a marker line in it, create a v7 database with a few rows, run
   the new `upgrade.sh`. Confirm: the database file is byte-identical afterwards, `guidelines.md`
   still holds the marker, and both checker scripts are gone.
6. **Migration.** Build three fixtures — a v2 log (no concerns table), a v6 log (concerns without
   `evidence`), a v7 log with open and resolved concerns and an entry carrying `refs` — and run
   the step-4 SQL of 3.7 against each. Confirm each reaches `user_version = 8` with the shipped
   object list, serials preserved, every type `done`, and `refs` text intact at the end of its
   description. Then run the same SQL against a fresh copy of a fixture with an error injected
   before `COMMIT`, and confirm that copy is untouched — old version, old tables, `refs` column
   still present — which is what makes a failed migration safe to re-run. This is the only
   destructive step in the system and the only check that covers it.
7. **Live.** Run `/klawde` in a scratch project and confirm the output block matches 3.5 exactly.
   Then run it against an unmigrated v7 database and confirm it stops with the version message.

---

## 7. Choices made where the session was silent

Each is reversible in one edit.

1. **Schema version 8.** Continues the existing 1–7 chain so `/klawde` and `/upgrade_klawde` can
   detect an old database with one `PRAGMA` read. Resetting to 1 would make old and new
   indistinguishable.
2. **No seed entry.** `/klawde` no longer inserts `Initialized.` on creating the database. An
   empty log reads as zero lines, which is accurate, and the output block says `none`.
3. **Field names** `Purpose`, `Scope`, `Key decisions`, `Areas`. The old name was `Current scope`;
   `Scope` is shorter and the field is current by definition.
4. **`refs` folded into the description** during migration rather than dropped, since it held real
   pointers, and untruncated, since the triggers are installed after the copy.
5. **Serials preserved** during migration rather than renumbered, so any entry text that names a
   serial still points at the right row.
6. **Backup name** `changes.db.pre-gaiden.<timestamp>`, left in place for the user to delete.
7. **Both views kept** (`log_lines`, `task_lines`). They are two lines of SQL each and they stop
   the model from inventing its own rendering of a record.
8. **Repo byte budget dropped.** The old rule capped the three session-read files at 34,500 bytes
   and required commits to state their net change. The new files are a fraction of that; the rule
   is replaced by a plain statement that these files are read every session and stay short.
9. **A version check survives in `/klawde` and `/close`.** Every other check was deleted. This one
   exists because the file copy and the data migration are now separate steps, so there is a
   window in which the new commands face an old database.

---

## 8. What this removes

| | Before | After |
|---|---|---|
| Contract | 22,546 bytes | ~5,000 bytes + `guidelines.md` |
| Command files | 2 | 3 |
| Schema | 11,601 bytes, 35 triggers, 5 tables, 2 views | ~2,500 bytes, 7 triggers, 2 tables, 2 views |
| Checker scripts | 2 | 0 |
| `upgrade.sh` | 15,979 bytes | ~9,000 bytes |
| Brief fields | 11, with a word and byte budget | 4, unbounded |
| Log types | 6 | 3 |
| Entry columns | serial, date, type, area, description, refs | serial, date, type, description |
| Tables tracking problems | `concerns`, with five admission points and required evidence | `tasks`, holding only approved work |
| Tests | 78 KB | 0 |

---

## 9. Deliberate choices that look like defects

A reviewer flagged each of these. They are the user's decisions and they stand. Do not implement
the alternatives.

1. **Every migrated entry becomes `done`**, including old `note` entries that recorded failures.
   A per-type mapping was proposed and rejected: the migration takes one flat cut, and the old log
   is history rather than a record to be re-interpreted.
2. **`/close` does not reconstruct the session from git.** Tasks are logged the moment they
   complete, so the end-of-session sweep carries far less than it used to.
3. **`guidelines.md` is not imported by `CLAUDE.md`.** It loads only when `/klawde` reads it. That
   is the point: deleting the file turns the code rules off, and only `/klawde` needs to know it
   may be absent.
4. **The `area` column is gone** and nothing replaces it as a query key for old history. Areas
   survive as prose in the brief.
