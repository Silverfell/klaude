# /close: Session Close Protocol

Persist state at session end or as a mid-session checkpoint. Use the project contract's Documentation Updates for log SQL forms, log eligibility, and briefing maintenance; concern writes are defined in step 3. This protocol specifies their order and approval flow.

## Steps

1. Read `BRIEFING.md` completely and exactly the last five log entries:

```sh
sqlite3 -readonly changes.db "SELECT line FROM log_lines ORDER BY serial DESC LIMIT 5;"
```

   If either record is missing, create it using the forms in `.claude/commands/klawde.md`, including schema initialization and area seeding. If the schema is missing, stop and recommend `upgrade.sh`.

   Then check the log before the first write, using the shipped read-only checker:

```sh
bash .claude/check-log.sh changes.db
```

   A damaged schema can silence an insert or accept one the log should refuse, so on any error stop here: write nothing to the database or the brief, never repair the live schema, and output only this, with the checker's error and the recovery it names:

```
Close stopped; nothing was written.
changes.db: <checker error>, <recovery action>. Run `/close` again once the log is repaired.
```

   If the checker or schema file is missing, report the check as unavailable, recommend `upgrade.sh`, and continue.

2. Recover all session work from the conversation, `git status`, `git diff`, and `git log` for commits made this session. Append each unrecorded change using the contract's Log entries section. After interruption or compaction, reconcile existing records against the recovered work before inserting; a repeated close must not duplicate already-recorded work.

   Record the last serial before these inserts and read the tail afterward for the closing range. Add a new area (step 4) before writing entries that need it.

   Link superseded decisions and closed notes, and carry current decisions into the brief. If the work contradicts `Current scope`, `Non-goals`, or `Do-not-touch`, flag it to the user before the closing block.

3. **Triage open concerns.** Read the open set:

```sh
sqlite3 -readonly changes.db "SELECT line FROM concern_lines WHERE is_resolved = 0 ORDER BY id;"
```

   If the `concerns` table is absent, inspect `PRAGMA user_version`: on pre-v3 report `schema pre-v3 — run upgrade.sh` and skip this step; on a newer database report damage and stop.

   - Resolve every open concern without a `ref_serial` in one statement; they predate the rule that ties a concern to recorded work:

```sh
sqlite3 -bail changes.db <<'KLAWDE_SQL'
UPDATE concerns SET resolved = date('now','localtime'), resolution = 'retired; not attached to recorded work' WHERE resolved IS NULL AND ref_serial IS NULL;
KLAWDE_SQL
```

   - Resolve what this session answered, made moot, or you no longer hold, with the reason. An answer given at a certainty gate counts; one that decided anything also gets a `[decision]` in step 2. Never resolve a live doubt to shorten the list. A concern short of its three parts is restated as a complete one and resolved as `restated as #N`, or resolved with the reason it was not a concern. A restatement is maintenance, not authoring: it carries the original's `area` and `ref_serial` unchanged, claims nothing the original did not beyond completing its parts, replaces exactly one row, and stands outside the three-per-close cap and the this-session rule below. One that cannot be completed truthfully was not a concern; resolve it with that reason.
   - Write the doubts you still hold about work this session changed: at most three per close, each in the contract's three parts, each with `ref_serial` naming that work's entry from step 2 (no entry, no concern), none about code the session did not change. Recover unconfirmed `ASSUMPTION:` items from the conversation and diff; one whose being wrong has a nameable consequence is presented for confirmation below and becomes a concern only if the user defers it.

     Refused at authoring time, each for what it lacks: `Export worker is not idempotent` — a bare fact, nothing it breaks; `Retry logic might be flaky` — a worry, nothing seen; `Should dry-run write an audit file?` — a question with no stake, and the user's field, not yours; `Add backoff cap` — a task, so `Next steps`; `batchSize is 500; the worker runs hourly; retries cap at 3` — three facts wearing semicolons; `Legacy importer has no tests; a refactor could break it; settles when tests exist` — about code this session did not change, so not yours to park.

   - Present what is still open in one batch, each with a proposed disposition (resolve with reason, promote, or keep open) and each consequential assumption named for confirmation. A concern whose third part is a decision of the user's is proposed for promotion, as the exact question it would add. The close does not wait for the reply: keep open is the default, and dispositions the user gives afterwards are applied with the forms below. Promote only on a named yes, as the exact decision question rather than the concern text, into `Open questions`; if the user answers the question instead, record the decision and resolve the concern. A confirmed assumption needs no row; a corrected one becomes a decision and, if it changes code, a next step.

   Open a concern, read its id back, and resolve by setting date and reason together, once:

```sh
sqlite3 -bail changes.db <<'KLAWDE_SQL'
INSERT INTO concerns (area, concern, ref_serial) VALUES ('queue','Export worker is not idempotent; a retried export may ship twice; settles when the worker is made idempotent or the user exempts it from retry',41);
KLAWDE_SQL
sqlite3 -readonly changes.db "SELECT line FROM concern_lines ORDER BY id DESC LIMIT 1;"
sqlite3 -bail changes.db <<'KLAWDE_SQL'
UPDATE concerns SET resolved = date('now','localtime'), resolution = 'Export worker made idempotent' WHERE id = 7;
KLAWDE_SQL
```

   Each CLI call is its own connection: `last_insert_rowid()` in a later call cannot identify an earlier insert; use the one-row read-back.

   Measure the open total for the closing block; use the query's number, never your tally:

```sh
sqlite3 -readonly changes.db "SELECT count(*) FROM concerns WHERE resolved IS NULL;"
```

4. Apply the contract's **Briefing maintenance** to all nine maintained fields, even those untouched by this session's code, and report restored fields.

   Handle user fields and extra content under that section's consent rules. Never complete a proposed edit while its answer is pending.

5. **Check the log again**, now that the writes are done; the closing block reports this result:

```sh
bash .claude/check-log.sh changes.db
```

   If the check was unavailable in step 1, it still is: report it so and recommend `upgrade.sh`; never claim integrity ok without a successful check. Relay the checker's output and the recovery it names; never repair the live schema. On any error, do no further database writes.

6. Write only changed project records. Do not stage or commit. If neither changed, do not rewrite either.

7. **Measure the brief on disk**, after writing, even if it was unchanged:

```sh
awk 'BEGIN { printf "Shape:" } /^#/ && f != "" && f != "Trailing" { printf "%s %s %d", s, f, n; s = ","; f = "Trailing"; n = 0 } /^[-*][[:space:]]+[^:]+:/ && f != "Trailing" { if (f != "") { printf "%s %s %d", s, f, n; s = "," } f = $0; sub(/:.*/, "", f); sub(/^[-*][[:space:]]+/, "", f); sub(/[[:space:]]+$/, "", f); n = 0 } NF { n++ } END { if (f != "") printf "%s %s %d", s, f, n; print "" }' BRIEFING.md
```

   The nine maintained fields must each measure 1. A duplicate or oversized one sends you back to step 4, then another write and measurement; never print the closing block while one still violates shape. User fields over one line, foreign fields and `Trailing` content are retained and reported when the user declined the corresponding proposal.

8. Output this format, then stop:

```
Session closed.
changes.db: [N] new entries (serials [X]-[Y] | none); [integrity ok, schema v<N> | schema/integrity: <checker error>, <recovery action> | check unavailable, run upgrade.sh].
concerns: [N] open (opened [X], resolved [Y] this session | untouched) [| schema pre-v3 — run upgrade.sh].
BRIEFING.md: [updated | unchanged] [; restored to shape: <fields>] [; user field over one line: <field N>, declined] [; extra content kept: <name N>, declined].
Shape: <the step 7 output, verbatim — Purpose 1, Current scope 1, … Environment quirks 1>
```

   Paste the measured Shape line and concern total, never expected values. Include decisions made during triage in the entry count. If nothing recordable changed, confirm both records unchanged; still run and report the checks.
