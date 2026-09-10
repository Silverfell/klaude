# /close: Session Close Protocol

Persist state at session end or as a mid-session checkpoint. Use the project contract's Documentation Updates for SQL forms, record eligibility, and briefing maintenance; this protocol specifies their order and approval flow.

## Steps

1. Read `BRIEFING.md` completely and exactly the last five log entries:

```sh
sqlite3 -readonly changes.db "SELECT line FROM log_lines ORDER BY serial DESC LIMIT 5;"
```

   If either record is missing, create it using the forms in `.claude/commands/klawde.md`, including schema initialization and area seeding. If the schema is missing, stop and recommend `upgrade.sh`. A failed query is not an empty result: report and diagnose it before writing.

2. Recover all session work from the conversation, `git status`, `git diff`, and `git log` for commits made this session. Append each unrecorded change using the contract's Log entries and Writing SQL safely sections. After interruption or compaction, reconcile existing records against the recovered work before inserting; a repeated close must not duplicate already-recorded work. Query older history only when a specific recovered change needs that check.

   Record the last serial before these inserts and read the tail afterward for the closing range. Serial and date assign themselves. A later CLI call's `last_insert_rowid()` is not the earlier call's id. Add a new area using step 4 before writing entries that need it.

   Link superseded decisions and closed notes, retain their original entries, and carry current decisions into the brief. Exclude verification receipts, parameter narration and session conduct as the contract requires. If the work contradicts `Current scope`, `Non-goals`, or `Do-not-touch`, flag it to the user before the closing block; never silently record around it.

3. **Triage every open concern.** First read the open set, then open any qualifying session doubts not already recorded, using the contract's three-part form and optional log reference:

```sh
sqlite3 -readonly changes.db "SELECT line FROM concern_lines WHERE is_resolved = 0 ORDER BY id;"
```

   If concerns are absent, inspect `PRAGMA user_version`: on pre-v3 report `schema pre-v3 — run upgrade.sh` and skip triage; on a newer database report damage and stop. Never create a missing table yourself.

   Recover unconfirmed `ASSUMPTION:` items from the conversation, COMPLIANCE blocks and diff. Raise only those whose being wrong has a nameable consequence. Do not insert them yet. An assumption that answers a user's open question is that question, not an assumption or concern.

   Read the open set again after any inserts; use this query to flag possible malformed concerns:

```sh
sqlite3 -readonly changes.db "SELECT line FROM concern_lines WHERE is_resolved = 0 AND id IN (SELECT id FROM concerns WHERE length(concern) - length(replace(concern, ';', '')) < 2) ORDER BY id;"
```

   Counting semicolons is a first pass; judge the three parts. Restate a doubt still held by inserting a complete concern, reading its id back, then resolving the old row as `restated as #N`. Never edit its frozen text. Resolve a bare fact, task or receipt with the reason it was not a concern. Re-read the open set before disposition so the user sees the corrected set.

   Dispose of every open concern:

   - Resolve it yourself only if this session answered it, made it moot, or you no longer hold it; record the reason. An answer already given at a certainty gate counts. If it decided anything, also append a `[decision]` in step 2. Never resolve a live doubt to shorten the list, or run its proposed check/fix without a user task authorizing that work.
   - Present everything else in one batch, each named with a proposed disposition: resolve (with reason), promote, or keep open. Include consequential unconfirmed assumptions, each named for confirmation. Wait for the reply; do not print "Session closed." while an answer is pending. A vague "ok" or "fine" approves none of the batch: ask again with the items named.
   - Promote only when a user's decision would settle the concern, and propose the exact decision question rather than the concern text. A named yes authorizes that addition to `Open questions` in step 4. If the user answers the question instead, record the decision, resolve the concern, and promote nothing. Deferral keeps the concern open for the next close.
   - A confirmed assumption needs no row. A corrected one becomes a decision and, if it changes code, a next step; no concern row. Only a deferred assumption becomes a three-part concern now. Do not propose promoting assumptions; if the user identifies one as an unmade decision, promote as directed.

   Apply dispositions using the contract's safe SQL forms. After every disposition, measure the remaining open total for the closing block:

```sh
sqlite3 -readonly changes.db "SELECT count(*) FROM concerns WHERE resolved IS NULL;"
```

   Use the query's number, never your tally. A mistyped resolution id leaves its concern open and must be reconciled before finishing.

4. Apply **Briefing maintenance** from the project contract to all nine maintained fields, even those untouched by this session's code. Restore their shape, preserve live state, log unrecorded history, and report restored fields. Insert missing fields in their template positions. Follow the example in `.claude/commands/klawde.md`.

   Handle user fields and extra content separately, exactly under that section's consent rules: approved promotions, decision-backed question removals, verbatim proposals to remove misplaced facts, and exact reshapes. An earlier explicit instruction needs no repeat ask. On refusal, preserve the content and report its measured count. Never complete a proposed edit while its answer is pending.

5. **Check log integrity and schema definitions**, using the shipped read-only checker:

```sh
bash .claude/check-log.sh changes.db
```

   The checker creates only a temporary reference database; it never writes the project log. It compares table, trigger and view definitions, so a same-name no-op trigger fails even when counts match. If the checker or schema file is missing, report the check as unavailable and recommend `upgrade.sh`; never claim integrity ok without a successful check.

   A healthy log reports integrity ok and definitions matching the shipped schema: the trigger count must be `30`, and the object count `7` covers its tables and views. The checker compares against the version it ships with, so never infer a version from a count. It also names the recovery each difference needs: relay its output and that instruction rather than deciding yourself, and never repair the live schema. Some differences point at `upgrade.sh`; a failed integrity check, a missing or changed table, and a trigger the schema does not define need recovery from git instead. On any error, report it and do no further database writes. An object the checker reports as present but not shipped, without failing, is left alone and reported.

6. Write only changed project records. Do not stage or commit. If neither changed, do not rewrite either.

7. **Measure the brief on disk**, after writing, even if it was unchanged:

```sh
awk 'BEGIN { printf "Shape:" } /^#/ && f != "" && f != "Trailing" { printf "%s %s %d", s, f, n; s = ","; f = "Trailing"; n = 0 } /^[-*][[:space:]]+[^:]+:/ && f != "Trailing" { if (f != "") { printf "%s %s %d", s, f, n; s = "," } f = $0; sub(/:.*/, "", f); sub(/^[-*][[:space:]]+/, "", f); sub(/[[:space:]]+$/, "", f); n = 0 } NF { n++ } END { if (f != "") printf "%s %s %d", s, f, n; print "" }' BRIEFING.md
```

   Interpret counts under Briefing maintenance: eleven template fields once each; nine maintained fields must each measure 1 and contain current state, not history. A duplicate or oversized maintained field sends you back to step 4, followed by another write and measurement. Never print the closing block while one still violates shape. User fields over one line, foreign fields and `Trailing` content are retained and reported when the user declined the corresponding proposal. A bullet that belongs to a user field remains that field's, however it measures.

8. Output this format, then stop:

```
Session closed.
changes.db: [N] new entries (serials [X]-[Y] | none); [integrity ok, schema v6 | schema/integrity: <checker error>, <recovery action> | check unavailable, run upgrade.sh].
concerns: [N] open (opened [X], resolved [Y] this session | untouched) [| schema pre-v3 — run upgrade.sh].
BRIEFING.md: [updated | unchanged] [; restored to shape: <fields>] [; user field over one line: <field N>, declined] [; extra content kept: <name N>, declined].
Shape: <the step 7 output, verbatim — Purpose 1, Current scope 1, … Environment quirks 1>
```

   Paste the measured Shape line and concern total, never expected values. Every remaining open concern must have been presented to the user. Include decisions made during triage in the entry count. If nothing recordable changed, confirm both records unchanged; still run and report the checks.
