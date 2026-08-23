# /close: Session Close Protocol

Run this at the end of a session to persist state for the next session. It is also safe to run mid-session as a checkpoint: recording early means a crash or context compaction cannot lose the session's record, and the review below re-anchors the work against the brief.

## Steps

1. Read `BRIEFING.md` in full and the tail of the log:

```sh
sqlite3 -readonly changes.db "SELECT line FROM log_lines ORDER BY serial DESC LIMIT 5;"
```

   Five entries, exactly as at session start — never the whole log. If either `BRIEFING.md` or `changes.db` is missing, create it first using the forms in `.claude/commands/klawde.md`, then continue.

2. Review all work done in this session. In a long session, earlier work may have been summarized out of your context: run `git status` and `git diff` (plus `git log` for anything committed this session) to recover changes you no longer remember. For each unrecorded shift in decisions, plans, scope, documents, external context, or code needing project-level explanation, insert one entry:

```sh
sqlite3 changes.db "INSERT INTO entries (type, area, description) VALUES ('decision','queue','Retry moved to the gateway; per-client retry double-billed the API');"
sqlite3 changes.db "INSERT INTO entries (type, area, description, refs) VALUES ('code','api','Moved retry logic into ApiClient; callers no longer handle 429s','abc1234');"
```

   - The serial and the date assign themselves. Never pass either by hand, never reuse or renumber one. Several entries take consecutive serials in the order you insert them. Read the serials back from the tail query for the closing block — each `sqlite3` call is its own connection, so `last_insert_rowid()` from a later call tells you nothing.
   - `area` is one of the areas listed in `BRIEFING.md`, or `-` when none fits. A spelling that is not in the `areas` table aborts the insert; that is the vocabulary defending itself, not an error to route around. If the area is genuinely new, add it in step 3 first.
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

3. Review whether any of the following changed during this session:
   - Project purpose or scope
   - Key architectural or design decisions
   - Non-goals or explicit exclusions
   - Breaking changes (note reason and impact)

   If any of the above changed, update `BRIEFING.md` accordingly. An empty field in `BRIEFING.md` (e.g., Purpose) counts as changed: draft it from what this session revealed. Keep it concise but sufficient to brief a new contributor; match the example brief in `.claude/commands/klawde.md`.

   Regardless of the list above, always maintain the state fields. BRIEFING.md holds current state, never history:
   - `Current focus`: **replace** it, never append a second one. There is exactly one, present tense. A brief that has accumulated several dated `Current focus` bullets has stopped being a brief.
   - `Next steps`: rewrite every close; clear it if nothing is pending. Stale next steps mislead the following session.
   - `Open questions`: changed only with the user's explicit consent. If this session raised a question worth listing, or answered one already listed, present the exact addition or removal and ask before writing `BRIEFING.md`; wait for the answer. A change the user explicitly asked for earlier this session needs no second ask. Without a clear yes, leave the field exactly as it is.
   - `Areas`: the closed vocabulary `changes.db` tags against. If it is empty, seed it now from the parts of the project that actually take work (subsystems, not file names — `auth`, `ingest`, `cli`). Add an area when work starts landing somewhere the list does not cover. Whenever the brief gains an area, add it to the database too, or entries tagged with it will be refused:

     ```sh
     sqlite3 changes.db "INSERT OR IGNORE INTO areas VALUES ('ingest');"
     ```

     Never rename or remove one that existing entries already use: the log is immutable, so a rename orphans every entry carrying the old name, and the database refuses both the rename and the removal.
   - `Environment quirks`: promote durable `[note]` context into the brief (flaky sandboxes, renamed keys, local oddities) so the next session reads it without querying for it; prune quirks that no longer hold. The note itself stays in the log; the brief is where the still-true version lives.
   - `Do-not-touch`: change only on explicit user instruction.

   A field is trimmed by removing what is no longer true, never by dropping live state to hit a number. A large project legitimately carries more open questions than a small one. What does not belong at any size: a bullet that narrates a past session rather than stating current state (`Styling pass`, `Auth refactor`, `Cleanup pass`). That is history — move it to `changes.db` or cut it.

4. **Check the log's integrity.** The database is the project's memory and it is committed to git; a corrupt file or a missing trigger is worth catching at the close that caused it rather than three sessions later.

```sh
sqlite3 -readonly changes.db "PRAGMA integrity_check;"
sqlite3 -readonly changes.db "SELECT count(*) FROM sqlite_master WHERE type='trigger';"
```

   The first must print `ok`; the second must print `9`. If triggers are missing, the append-only and immutability guarantees are not being enforced — restore the missing trigger(s) by running their individual `CREATE TRIGGER` statements from `.claude/changes-schema.sql` against the database, and report it on the closing block. If `integrity_check` reports anything other than `ok`, do not attempt a repair: report it and stop, so the user can recover the file from git.

5. Write only the file(s) you changed. If neither changed, do not write. Do not stage or commit. Leave changes dirty so the user controls when they enter git history.

6. Output exactly this format, then stop:

```
Session closed.
changes.db: [N] new entries (serials [X]-[Y] | none); integrity ok [| integrity: <problem>].
BRIEFING.md: [updated | unchanged].
```

Do not skip this protocol. If nothing recordable changed, say so and confirm both files are unchanged.
