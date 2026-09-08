# /close: Session Close Protocol

Run this at the end of a session to persist state for the next session. It is also safe to run mid-session as a checkpoint: recording early means a crash or context compaction cannot lose the session's record, and the review below re-anchors the work against the brief.

## Steps

1. Read `BRIEFING.md` in full and the tail of the log:

```sh
sqlite3 -readonly changes.db "SELECT line FROM log_lines ORDER BY serial DESC LIMIT 5;"
```

   Five entries, exactly as at session start — never the whole log. If either `BRIEFING.md` or `changes.db` is missing, create it first using the forms in `.claude/commands/klawde.md` — for `changes.db` that includes seeding its `areas` table from the brief's `Areas` line — then continue. A missing `changes.db` needs the shipped schema file; if that is missing too, stop as `/klawde` does and tell the user to run `upgrade.sh`.

2. Review all work done in this session. In a long session, earlier work may have been summarized out of your context: run `git status` and `git diff` (plus `git log` for anything committed this session) to recover changes you no longer remember. For each unrecorded shift in decisions, plans, scope, documents, external context, or code needing project-level explanation, insert one entry:

```sh
sqlite3 changes.db "INSERT INTO entries (type, area, description) VALUES ('decision','queue','Retry moved to the gateway; per-client retry double-billed the API');"
sqlite3 changes.db "INSERT INTO entries (type, area, description, refs) VALUES ('code','api','Moved retry logic into ApiClient; callers no longer handle 429s','abc1234');"
```

   - The serial and the date assign themselves. Never pass either by hand, never reuse or renumber one. Several entries take consecutive serials in the order you insert them: the step 1 tail shows the last serial before this run's inserts, so your range starts one above it, and the tail query after inserting shows the last five. Each `sqlite3` call is its own connection, so `last_insert_rowid()` from a later call tells you nothing.
   - `area` is one of the areas listed in `BRIEFING.md`, or `-` when none fits. A spelling that is not in the `areas` table aborts the insert; that is the vocabulary defending itself, not an error to route around. If the area is genuinely new, add it in step 4 first.
   - Types: `decision`, `plan`, `doc`, `scope`, `code`, `note`. For `decision`, name the rejected alternative when one exists (`X over Y; reason`).
   - Double every single quote inside the text (`don''t`).
   - Relationships are separate inserts, never edits of an entry. Use `closes` when this session resolved an open `[note]`; the note itself is left exactly as it is.

```sh
sqlite3 changes.db "INSERT INTO links VALUES (57, 41, 'supersedes');"
sqlite3 changes.db "INSERT INTO links VALUES (58, 43, 'closes');"
```

   Three things do **not** go in the log, however much the session produced of them. Verification evidence (test counts, measured distributions, clean-console confirmations) belongs in the COMPLIANCE `Verified:` line of your response — it expires as soon as the code changes. Parameter values that code, config or an asset file already owns — record why, never what. Session conduct: frustration, blame, and the blow-by-blow of your own corrections. Where a failure taught something durable, record the lesson and drop the incident.

   Refuse these at authoring time. Nothing removes an entry later: the log keeps its full history forever and the database will not let you take one back.

   If this session superseded an earlier decision, insert the new decision, then insert a `supersedes` link naming the entry it replaces, and say why the old one was abandoned — the reason is the expensive part. Leave the superseded entry exactly as it is. This is a log: no entry in it is ever edited or deleted, however wrong it later turned out to be. Then carry the live decision into `BRIEFING.md`, which is where a future session reads what currently holds.

   If any of this session's work contradicts `Current scope`, `Non-goals`, or `Do-not-touch` in BRIEFING.md, flag the contradiction to the user before the closing block; do not silently record around it.

3. **Triage every open concern.** A concern is a doubt about the project in three parts on one line, separated by semicolons: what you saw; what it may break or leaves undecided; what settles it. A line missing a part is not a concern and is not written. Nothing of yours reaches the brief's `Open questions` except through this step. Read what is open first, so no doubt is opened twice:

```sh
sqlite3 -readonly changes.db "SELECT line FROM concern_lines WHERE is_resolved = 0 ORDER BY id;"
```

   Open one for any doubt this session left you holding that is not already there, with `ref_serial` naming the log entry it is about where one exists:

```sh
sqlite3 changes.db "INSERT INTO concerns (area, concern, ref_serial) VALUES ('queue','Retry cap assumes idempotent consumers, and the export worker is not; a retried export may ship twice; settles when the worker is made idempotent or the user exempts it from retry',41);"
```

   Check the three parts before inserting. A bare fact (`export worker is not idempotent`) names nothing it breaks: say what, or it is a `[note]` in step 2 if it is external context and nothing if it is a fact about the code. A worry with nothing seen behind it (`retry might be flaky`) is not recorded. A task goes to `Next steps` in step 4, and a verification receipt goes nowhere. The second part is allowed to be a guess — that is what the table is for.

   Then list every `ASSUMPTION:` you marked this session that the user did not confirm and whose being wrong would break something you can name; recover them from your COMPLIANCE blocks and, in a long session, from `git diff`, where an assumption shows in the code. One with no nameable consequence (a name, a format, a default between equivalents) is not raised. Do not insert them yet: they are presented for a one-word confirmation in the batch below, and only one the user defers becomes a concern, in three parts — what you assumed; what breaks if it is wrong; settles when the user confirms or corrects it. An assumption that answers an item in the brief's `Open questions` is that question: raise it as such and record nothing.

```sh
sqlite3 changes.db "INSERT INTO concerns (area, concern) VALUES ('retry','Assumed the export worker reads the shared backoff config; if it has its own, the new cap never reached it; settles when the user confirms which config it reads');"
```

   Then read everything open, and list the ones short of three parts:

```sh
sqlite3 -readonly changes.db "SELECT line FROM concern_lines WHERE is_resolved = 0 ORDER BY id;"
sqlite3 -readonly changes.db "SELECT line FROM concern_lines WHERE is_resolved = 0 AND id IN (SELECT id FROM concerns WHERE length(concern) - length(replace(concern, ';', '')) < 2) ORDER BY id;"
```

   (If either fails because the table does not exist, the database predates schema v3: note it in the closing block, recommend `upgrade.sh`, and skip this step. Do not alter the schema yourself.)

   The second query counts semicolons — a first pass, not the judgment. Text is immutable, a resolved concern is frozen, and nothing is deleted; the triggers refuse all three, so nothing is fixed in place. A doubt you still hold whose three parts lack their semicolons, or that lacks a part, is opened again in full, its id read back — never from `last_insert_rowid()` — and the old one resolved as `restated as #N`; one that was never a concern — a bare fact, a task, a receipt — is resolved saying so. Do this before triage, so the user sees concerns, not fragments; then run the first query again and dispose from that read.

```sh
sqlite3 changes.db "INSERT INTO concerns (area, concern) VALUES ('queue','Export worker is not idempotent; a retried export may ship twice; settles when the worker is made idempotent or the user exempts it from retry');"
sqlite3 -readonly changes.db "SELECT line FROM concern_lines ORDER BY id DESC LIMIT 1;"
sqlite3 changes.db "UPDATE concerns SET resolved = date('now','localtime'), resolution = 'restated as #12' WHERE id = 4;"
```

   Dispose of every one; none is skipped silently. The third part says which way each goes:

   - **Resolve it yourself** only when this session genuinely answered it, made it moot, or you no longer hold it, and say why: the reason is recorded forever. Never resolve a live concern to shorten the list. A concern the user answered when it was raised at a certainty gate this session is resolved here, and if the answer decided anything it is a `[decision]` entry in step 2.

```sh
sqlite3 changes.db "UPDATE concerns SET resolved = date('now','localtime'), resolution = 'Export worker made idempotent this session' WHERE id = 7;"
```

   - **Present the rest to the user in one batched block**, each with a proposed disposition — resolve (say why), promote, or keep open — and the unconfirmed assumptions in the same batch, each named, for a one-word confirmation. Propose promotion only for a concern that a decision of the user's settles, written as the question the user has to answer (`should dry-run write an audit file?`), never as the concern's own text; never propose promoting an assumption. Wait for the answer. A defer keeps a concern open for the next close, by design. A clear yes to a named promotion carries into step 4's `Open questions` edit; a vague reply to the batch ("ok", "fine") is consent for none of them — ask again, each item named, in one batch. If the user answers a proposed question instead of approving the promotion, that is a decision: insert the `[decision]` entry now in step 2's form, count it in the closing block, resolve the concern with it, and promote nothing. A confirmed assumption needs no row. A corrected one is a `[decision]` entry in step 2's form and, if it changes code, a next step — no row either. One the user defers is inserted now as a concern, in the form above, and stays open; one the user says is a decision they have not made is promoted as they direct.

   When every disposition is applied, count what is still open:

```sh
sqlite3 -readonly changes.db "SELECT count(*) FROM concerns WHERE resolved IS NULL;"
```

   That number is the closing block's `concerns:` open figure, pasted in as the `Shape` line is. A resolve that changed nothing — a mistyped id — shows here as a concern still open.

4. Review whether any of the following changed during this session:
   - Project purpose or scope
   - Key architectural or design decisions
   - Non-goals or explicit exclusions
   - Breaking changes (note reason and impact)

   If any of the above changed, update `BRIEFING.md` accordingly. An empty field among the nine you maintain (e.g., Purpose) counts as changed: draft it from what this session revealed; an empty `Open questions` or `Do-not-touch` stays empty. Keep it concise but sufficient to brief a new contributor; match the example brief in `.claude/commands/klawde.md`.

   Regardless of the list above, always maintain the state fields that are yours. Two fields are the user's and are not in this sweep — `Open questions` and `Do-not-touch`; they are handled after it, and the sweep never touches them. BRIEFING.md holds current state, never history, and it is bounded by shape: one bullet per field, one line each, a sentence or a short list of clauses. Before writing, check every field you maintain against that shape. A field that has grown sub-bullets, paragraphs, or dated entries is restored to one line: what is still true is condensed into the line, what narrates a past session becomes a log entry in step 2 if the log does not already hold it, and working notes — findings, progress, verification results, things tried — are dropped, because they were never the brief's to keep. Report a restored field on the closing block. A line whose name is not one of the eleven, and text under a heading after the last field (the measure reports it as `Trailing`), is not yours to drop: propose what to do with it — moved into the template field it belongs to, moved into the log, or removed — and write only on a clear yes; on a no, leave it and report its count on the closing block. A line directly under `Open questions` or `Do-not-touch` that reads as one of that field's items is that field's, however it measures, and belongs in the reshape proposal below. A template field missing entirely is inserted empty, in its template position. Step 7 measures the result; a maintained field it finds still over one line sends you back here.
   - `Current focus`: **replace** it, never append a second one. There is exactly one, present tense. A brief that has accumulated several dated `Current focus` bullets has stopped being a brief.
   - `Next steps`: rewrite every close; clear it if nothing is pending. Stale next steps mislead the following session.
   - `Areas`: the closed vocabulary `changes.db` tags against. If it is empty, seed it now from the parts of the project that actually take work (subsystems, not file names — `auth`, `ingest`, `cli`). Add an area when work starts landing somewhere the list does not cover. Whenever the brief gains an area, add it to the database too, or entries tagged with it will be refused:

     ```sh
     sqlite3 changes.db "INSERT OR IGNORE INTO areas VALUES ('ingest');"
     ```

     Never rename or remove one that existing entries already use: the log is immutable, so a rename orphans every entry carrying the old name, and the database refuses both the rename and the removal.
   - `Key decisions`: the decisions that currently hold, not the history of deciding. When this session superseded a decision, the replacement enters and the old one leaves — the log keeps both, plus the `supersedes` link, so nothing is lost by removing it here.
   - `Breaking-change context`: only what a new contributor still has to know to work on the code today. Once the old form is gone from every place a session could meet it (no code, config, docs, or data still carry it), remove the entry; the log has the record.
   - `Environment quirks`: promote durable `[note]` context into the brief (flaky sandboxes, renamed keys, local oddities) so the next session reads it without querying for it; remove quirks that no longer hold. The note itself stays in the log; the brief is where the still-true version lives.
   A field is trimmed by removing what is no longer true, never by dropping live state to hit a number. A large project legitimately carries more open questions than a small one. What does not belong at any size: a bullet that narrates a past session rather than stating current state (`Styling pass`, `Auth refactor`, `Cleanup pass`). That is history — move it to `changes.db` or cut it.

   The user's two fields are not maintained; they are read, and changed only on the user's word. The shape rule applies to them too, but you never restore them yourself: if either measures over one line, propose the exact one-line rewrite — the same items joined as clauses, nothing dropped and nothing added — and write it only on a clear yes. On a no, leave it and report the measured count on the closing block; step 7 does not send you back for it, and the proposal recurs at the next close if the field is still over one line.
   - `Do-not-touch`: change only on explicit user instruction, or by the one-line reshape above with the user's yes.
   - `Open questions`: the project decisions the user has still to make, each written as a question. It is never a home for your doubts, findings, or facts — those are concerns and were handled in step 3. It changes only in these ways, each with the user's explicit consent asked for before you write `BRIEFING.md`: a promotion the user approved in step 3, written as the question the user approved and never as the concern's text; a removal, proposed only when a `[decision]` entry in the log answers it, this session's or an earlier one's — you do not judge whether a question is answered, a recorded decision does; a removal of a line that is a finding or a fact rather than a question, proposed verbatim, since a past session probably left it; and the one-line reshape above. A change the user explicitly asked for earlier this session needs no second ask. Without a clear yes, leave the field exactly as it is.

5. **Check the log's integrity.** The database is the project's memory and it is committed to git; a corrupt file or a missing trigger is worth catching at the close that caused it rather than three sessions later.

```sh
sqlite3 -readonly changes.db "PRAGMA user_version;"
sqlite3 -readonly changes.db "PRAGMA integrity_check;"
sqlite3 -readonly changes.db "SELECT count(*) FROM sqlite_master WHERE type='trigger';"
sqlite3 -readonly changes.db "SELECT count(*) FROM sqlite_master WHERE name IN ('areas','entries','links','legacy_summaries','concerns','log_lines','concern_lines');"
```

   Read the version first; it decides what the counts must be. Integrity must print `ok`. The trigger count must be `28` on a v5 database, `24` on v4, `17` on v3, `9` on v2 and `7` on v1; the object count `7` from v3 up and `5` before. Never infer the version from a count: a v5 database that has lost its seven immutability triggers counts 17, exactly like a healthy v3. A version below 5 means the database predates this contract; a count below what its version requires means a trigger or view has gone missing and the guarantees are not being enforced. In either case you repair nothing here: report it on the closing block and recommend `upgrade.sh`, which upgrades the schema and restores any missing trigger or view, idempotently. If `integrity_check` reports anything other than `ok`, or a table is missing, say so and stop after the block, so the user can recover the file from git: only git still holds the rows a table had.

6. Write only the file(s) you changed. If neither changed, do not write. Do not stage or commit. Leave changes dirty so the user controls when they enter git history.

7. **Measure the brief's shape.** Run this against the file as it now stands on disk — after the write in step 6, never from memory, and even when the brief was not touched this session:

```sh
awk 'BEGIN { printf "Shape:" } /^#/ && f != "" && f != "Trailing" { printf "%s %s %d", s, f, n; s = ","; f = "Trailing"; n = 0 } /^[-*][[:space:]]+[^:]+:/ && f != "Trailing" { if (f != "") { printf "%s %s %d", s, f, n; s = "," } f = $0; sub(/:.*/, "", f); sub(/^[-*][[:space:]]+/, "", f); sub(/[[:space:]]+$/, "", f); n = 0 } NF { n++ } END { if (f != "") printf "%s %s %d", s, f, n; print "" }' BRIEFING.md
```

   It prints one `Field N` pair per field, `N` being the non-blank lines that field occupies. The shape is every count exactly 1, and exactly the eleven field names of the template, once each. A count above 1 is a sub-bullet, a wrapped paragraph, a dated entry on its own line, or text after the last field, which the measure counts into it unless a heading starts it, in which case it is reported separately as `Trailing`; a repeated name is a second `Current focus`; a name the template does not have is a foreign field. On one of the nine fields you maintain, a count above 1 or a repeat means step 4 missed it: go back to it, restore that field to one line (what is still true condensed into the line, what narrates a past session into the log via step 2, working notes dropped), write again, and measure again. The closing block is not printed while any count on those nine is not 1. A count above 1 on `Open questions` or `Do-not-touch`, a foreign field, and a `Trailing` count are different: step 4 proposed what to do with each, and if the user declined, it is reported as it measures. This protocol does not finish with a sub-bullet in a field it maintains.

8. Output exactly this format, then stop:

```
Session closed.
changes.db: [N] new entries (serials [X]-[Y] | none); integrity ok [| schema v<N>, run upgrade.sh] [| <have> of <want> triggers, run upgrade.sh] [| integrity: <problem>].
concerns: [N] open (opened [X], resolved [Y] this session | untouched) [| schema pre-v3 — run upgrade.sh].
BRIEFING.md: [updated | unchanged] [; restored to shape: <fields>] [; user field over one line: <field N>, declined] [; extra content kept: <name N>, declined].
Shape: <the step 7 output, verbatim — Purpose 1, Current scope 1, … Environment quirks 1>
```

   The `Shape` line is the measurement's own output pasted in, never typed from expectation. It reads all 1s on the nine fields you maintain by construction: any other number there was printed against step 7, and a number above 1 on a user field, a foreign name, or a `Trailing` count is explained by the `BRIEFING.md` line. The `concerns` line's open count is step 3's measured count pasted in, never your tally; an open concern the user never saw contradicts this block.

Do not skip this protocol. If nothing recordable changed, say so and confirm both files are unchanged; the `Shape` line is still measured and printed.
