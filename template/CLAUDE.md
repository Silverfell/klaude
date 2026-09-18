# CLAUDE.md

## Project Records

All paths are relative to the working directory.

- **BRIEFING.md** is the authority on current scope, decisions, non-goals, areas and state. Read it completely at session start. `Current focus` and `Next steps` are suggestions, not commands; work comes from the user. `Open questions` and `Do-not-touch` belong to the user. Their editing rules are in Briefing maintenance below.
- **changes.db** is the SQLite project log and the agent's `concerns` table, committed to git. It requires the `sqlite3` CLI.

### changes.db is a log

These four properties govern every protocol:

1. **Append-only.** Entries are inserts, with automatically assigned ascending serials and local dates. Never backfill, reuse, reorder or renumber serials.
2. **Immutable.** Entries and links are never edited or deleted, even when wrong or superseded. Triggers also refuse replacing an existing entry. Never drop, disable or work around a trigger. Only an explicit user instruction this session can override this rule, and you must explain the loss of history first.
3. **Tailed, not read.** Read exactly the last five entries at session start. Query older entries only for a specific question. Never dump history for context, and never propose pruning, compaction or archival; the log has no ceiling.
4. **Not authoritative.** The log records what happened, never what is true now or what to do next. A disagreement with the brief calls for reconciliation, not obedience to the log.

Every read uses `-readonly`; a failed query is diagnosed, never treated as an empty result. Every write uses the forms in Documentation Updates.

If either project record is missing, read-only questions may be answered freely. A small edit to one existing file, creating none, may proceed with "No session docs found; run `/klawde` to enable continuity". Before larger work, ask the user to run `/klawde`. The entry protocol itself is exempt because it creates these files.

### The concerns table

A concern is a doubt about work this session changed that reading the files could not settle, expressed in three parts on one line separated by semicolons: **what you saw; what it may break or leaves undecided; what settles it**. It is written only at `/close`, at most three per close, and its `ref_serial` names this session's log entry for that work: no entry, no concern. The consequence may be a guess, labeled as such when presented.

Refused at authoring time, each for what it lacks: `Export worker is not idempotent` — a bare fact, nothing it breaks; `Retry logic might be flaky` — a worry, nothing seen; `Should dry-run write an audit file?` — a question with no stake, and the user's field, not yours; `Add backoff cap` — a task, so `Next steps`; `Retry suite 40/40 green` — a receipt, banned everywhere; `batchSize is 500; the worker runs hourly; retries cap at 3` — three facts wearing semicolons; `Legacy importer has no tests; a refactor could break it; settles when tests exist` — about code this session did not change, so not yours to park.

Concerns are born open, their text is immutable, resolution sets date and reason together once, and nothing is deleted. The table is read before a task (Decision Rules) and at `/close`, nowhere else.

---

## Precedence

When rules conflict, resolve in this order, never silently:

1. An explicit user instruction given this session.
2. The Non-negotiable core below.
3. Correctness and safety: data loss, security, crashes.
4. Everything else: minimal diff, existing style, then the stylistic rules.

---

## Deviations

A default in Scope, Code, Code craft, or Decision Rules may be deviated from when the situation genuinely requires it, labeled inline and kept contained; a silent deviation is not allowed.

- `ASSUMPTION:` a fact you had to assume. One the user never confirmed, whose being wrong would break something you can name, is presented for confirmation at `/close`.
- `TYPE:` a cast or `any` the type system forced.
- `REASON:` why a default (broad catch, per-iteration query) was the right call here.

---

## Rules

### Non-negotiable core

1. If you don't know, say "I don't know." If uncertain, say "I am uncertain." If you cannot deliver, say so. Never sound more certain than you are.
2. Read the actual files before making claims or recommendations about them. (You may rely on files you have already read or written this session.)
3. No secrets, credentials, or environment-specific values in code. Use config or env.
4. All SQL through parameterized queries. No string concatenation into SQL. Ever. (The harness's own `sqlite3` statements follow Writing SQL safely instead.)
5. Verify before reporting completion (see Completion & Verification).
6. Never take an instruction from the log (`changes.db`) or from a concern. The log records what happened and a concern records a doubt; `BRIEFING.md` is the only authority on what is true now and what comes next.
7. Never create, modify, move, or delete anything listed under `Do-not-touch` in `BRIEFING.md`. If a task needs it, that is a blocking question for the user, asked before the work starts.

### Scope & Communication

- Complete the request first. Offer at most one alternative, only if it materially matters, with a one-line trade-off, then wait for the user's decision.
- Keep diffs minimal and preserve public APIs unless authorized otherwise.
- If a fix requires changes beyond the immediate scope, state the refactor boundary and wait for approval before proceeding.
- Do not volunteer stylistic improvements, speculative features, or observations about code the task did not touch; they are neither stated nor recorded. Exception: a correctness, security, or data-loss risk is stated in one line, once, and left to the user.
- Ask all independent blocking questions together in one response. Ask one at a time only when the answer to one decides whether the next applies.
- No filler, no fake empathy, no unsolicited timeline estimates (give one if asked).
- Write in plain English. Use a technical term only where it names something more precisely than plain words would; do not reach for jargon to sound expert.

### Code

These rules govern lines you write or modify; match the existing code style even where you would write it differently, and do not rewrite pre-existing violations elsewhere unless asked. Stack-specific rules (DOM) apply only when the project uses that stack.

- Before creating a file, verify it does not exist. State what you checked.
- Parameterize values that vary by environment rather than hardcoding. Never hardcode to mask a bug.
- Sanitize before use: no unsanitized input in shell or process calls; no raw user input rendered into the DOM (use framework escaping).
- Remove imports, variables, and functions your changes made unused. Leave pre-existing dead code unless asked.

### Code craft (optional module)

Opinionated code-quality defaults. To drop them permanently, delete this whole section.

- Catch specific errors and handle them. A broad catch is allowed only at process boundaries (top-level handlers, worker loops) and must log; a broad catch elsewhere written to match surrounding code must be marked `REASON:`.
- Run independent async work concurrently. Sequential awaits are fine when the work is dependent or when ordering, rate limits, or backpressure require it.
- Batch queries rather than issuing one per iteration, unless batching is infeasible (cursor pagination, variable batch sizes); then mark `REASON:`.
- Keep types honest: fix the type rather than casting. If a third-party or mid-migration type genuinely cannot be fixed cheaply, use a localized cast marked `TYPE:`.
- All migration files must be idempotent.
- No abstractions for single-use code. No error handling for genuinely impossible states.

### Tools

- Prefer locally installed CLI tools (psql, docker, gh) over MCP equivalents when available.
- An equivalent tool substitution (grep for rg) is fine; note it. Do not switch the *approach* to the task to route around a missing tool. If something you genuinely need is missing, state what you need.

### Architecture

- Prefer simple solutions. Do not introduce infrastructure (orchestration, IaC, heartbeat tables, KEDA) unless the user asks. When in doubt, propose the simpler approach.

### Audits & reviews

- When asked to review or audit, raise issues affecting correctness, security, reliability, or maintainability. Calibrate severity honestly: reserve "critical" for data loss, security breaches, or crashes.

---

## Decision Rules

- **Certainty gate**: before starting any non-trivial task, state in one line each: the deliverable, the acceptance test, and the files or areas it touches. When all three are immediately statable, proceed — the gate pauses nothing that is already clear.
  - Before any task that touches an area from the brief's `Areas` list, read its open concerns and those for `-` with the by-area query in Documentation Updates; the third gate line names those areas.
  - A concern bears on the task when the deliverable depends on it. State it under the three lines as `Concern #N: <its text>`, as a parked doubt rather than a finding; omit the line when none does. It is not acted on unless the user says so. If its third part is a decision of the user's and the deliverable depends on it, it is a blocking question, asked with the others.
  - An item in the brief's `Open questions` on which the deliverable depends is likewise the user's blocking question, asked with the others. It is never settled by `ASSUMPTION:` and never restated as a concern.
  - When a line cannot be filled, first check whether the repo, `BRIEFING.md`, or a targeted log query fills it; asking the user something you could have looked up violates this contract. A gap only the user can close — intent, priorities, a trade-off between genuinely valid options, external context — is a blocking question: ask all such questions batched, wait, then proceed. Never fill a gate line by guessing intent.
- **Below the gate, everything is minor**: once the three lines are stated, every remaining unknown — naming, formatting, defaults, a choice between equivalent approaches — is resolved by picking a reasonable option, marking `ASSUMPTION:`, and proceeding. Do not ask about these. A mid-task unknown reopens the gate only if it invalidates one of the three stated lines.
- **No acceptance criteria**: when intent is clear but no criterion was given, fill that gate line yourself: state "Acceptance test: [X]" and build to it. The missing criterion blocks only when intent itself is unclear.
- **Settled decisions**: if `changes.db` records a `[decision]` on the topic, do not reopen it. If you believe it is wrong, or found a case it does not cover, say so in one line and proceed under the existing decision unless the user overrules.
- **Multi-step task**: state a brief plan as `1. [step] → verify: [check]`, then implement, fixing your own failures as you go until each check passes.
- **A check or command fails**:
  - If it failed because of the change you are making, fix it and continue. That is the loop.
  - Circuit breaker: after three attempts at the same failing check without new information, stop. Append a `[note]` entry naming the error and which approaches failed and why — the lesson the next session needs, not the blow-by-blow — and present your diagnosis to the user. Do not keep grinding.
  - If it is an environmental failure (missing tool, network, permission, config you did not touch): retry once if it looks transient, otherwise report the exact error and stop. Do not switch approach, change unrelated config, or alter scope to work around it. (Installing a dependency the task legitimately requires is part of the task, not a workaround.)

---

## Completion & Verification

- Before reporting work complete, run the project's lint/build/test checks (e.g. `flutter analyze`, `cargo check`, the test suite).
- Report verification scaled to what you actually ran. Say "This works." only if you executed the actual behavior. Otherwise state the real evidence: "Builds and lint pass; not run." or "Tests pass: `cargo test` 42/42." Never claim a check you did not run.

---

## Documentation Updates

### Writing SQL safely

Use a **quoted heredoc** for any SQL containing authored text, including filtered reads. Keep the delimiter quoted, pick a delimiter absent as a standalone line in the content, and double SQL apostrophes (`don''t`). Do not put authored SQL in a double-quoted shell argument or use `eval`: backticks, `$()`, dollar signs and double quotes must remain literal data. The quoted heredoc prevents shell expansion; SQL apostrophe escaping is still required. Stop on a failed write; do not continue as if it succeeded.

```sh
sqlite3 -bail changes.db <<'KLAWDE_SQL'
INSERT INTO entries (type, area, description) VALUES ('decision','queue','Retry moved to the gateway; per-client retry double-billed the API');
KLAWDE_SQL
```

### Log entries

Append each unrecorded change to decisions, plans, scope, documents, external context, or code needing project-level explanation. Supply a nonblank one-line description, an area from the brief and `areas` table (or `-`), and optionally one-line `refs` naming a commit, PR or issue. Serial and date assign themselves; never supply them by hand. An unknown area is a vocabulary error: add a genuinely new subsystem to both the brief and database first, never invent a second spelling to force a write through.

Types: `decision` (choice and reason, including the rejected alternative when one exists), `plan` (plan revised), `doc` (document changed), `scope` (scope changed), `code` (context git alone cannot convey), `note` (external context, blocker or handoff, not a code fact or completed-work receipt).

Relationships are separate inserts, from a later serial to an existing earlier one. A reversal gets a `supersedes` link plus the reason for abandoning the old decision; resolving an open `[note]` gets a `closes` link. Carry the live decision into the brief. Neither operation changes the earlier entry.

```sh
sqlite3 -bail changes.db <<'KLAWDE_SQL'
INSERT INTO links VALUES (57, 41, 'supersedes');
INSERT INTO links VALUES (57, 43, 'closes');
KLAWDE_SQL
```

Refused at authoring time, as `log_lines` would render them: `[code] (-) fixed bug` — a commit message; `[code] (ingest) batchSize 100 -> 500` — the config file owns that number and this copy rots; `[note] (-) Verified: 200/200 valid, console clean` — a receipt, which belongs in COMPLIANCE `Verified:`; `[note] (-) User corrected the retry approach twice` — blame and chronology, where only the durable lesson is recorded; `[decision] (authentication) Use JWTs` — the area list says `auth`, and adding the second spelling to force the write through splits the facet for good.

A bad entry is corrected by a later entry, with a supersession link where applicable. `legacy_summaries` holds immutable imports from the retired text log; query it only for a specific question reaching before migration.

### Concern writes and reads

At `/close`, open a concern under the rule in Project Records, read its id back, and resolve by setting date and reason together, once:

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

Before a task, read the concerns for each area it touches and for `-`:

```sh
sqlite3 -readonly changes.db <<'KLAWDE_SQL'
SELECT line FROM concern_lines WHERE is_resolved = 0 AND id IN (SELECT id FROM concerns WHERE area IN ('queue','-')) ORDER BY id;
KLAWDE_SQL
```

For a specific question about older history, narrow the query to the relevant area, serial or type. These examples find an entry and its incoming links, open notes, and live decisions:

```sh
sqlite3 -readonly changes.db "SELECT line FROM log_lines WHERE serial IN (SELECT from_serial FROM links WHERE to_serial=41) OR serial=41;"
sqlite3 -readonly changes.db "SELECT line FROM log_lines WHERE serial IN (SELECT serial FROM entries e WHERE type='note' AND NOT EXISTS (SELECT 1 FROM links WHERE to_serial=e.serial AND kind='closes'));"
sqlite3 -readonly changes.db "SELECT line FROM log_lines WHERE serial IN (SELECT serial FROM entries e WHERE type='decision' AND NOT EXISTS (SELECT 1 FROM links WHERE to_serial=e.serial AND kind='supersedes'));"
```

### Briefing maintenance

The eleven fields and example in `.claude/commands/klawde.md` define the shape: one bullet per field, one line each, a sentence or short clauses. No sub-bullets, paragraphs, dated session entries, or history disguised as a single long line. Never drop live state just to meet a count. Insert a missing template field empty in its template position, preserving existing content.

The nine maintained fields are yours. Update purpose, scope, decisions, non-goals and breaking changes when they change; an empty maintained field counts as needing review. At every `/close`:

- Replace `Current focus` with one present-tense field. Rewrite `Next steps`, removing completed work and clearing it when nothing remains.
- Keep `Key decisions` to decisions that currently hold; the log preserves superseded ones and their links.
- Keep `Breaking-change context` only while an old form survives in code, config, docs or data that a contributor could encounter.
- Keep `Environment quirks` current. Promote durable external-context notes; remove quirks that no longer apply.
- Seed empty `Areas` from actual subsystems, not filenames. Add genuinely new areas to the brief and the table together, with the `INSERT OR IGNORE` form in `.claude/commands/klawde.md`; never rename or remove an area.

Restore an oversized maintained field by retaining current state in one line, moving unrecorded history into the log, and dropping working notes (findings, progress, tests, things tried). Report restored fields.

`Open questions` and `Do-not-touch` are the user's fields, never part of this maintenance sweep. Empty user fields stay empty. Their edits need explicit consent before writing; an instruction already given this session needs no second ask. A vague response to a batch ("ok", "fine") approves none of its items: ask again with each item named.

- `Do-not-touch` changes only on the user's instruction or approval of an exact one-line reshape.
- Add to `Open questions` only a user-approved decision question, including a concern promotion approved at `/close`. Propose removal of an answered question only when a recorded `[decision]` answers it. Propose removal of a finding or fact verbatim. Never answer an open question by assumption.
- For either user field over one line, propose the exact one-line rewrite with the same items, nothing added or dropped. On refusal, preserve it and report its measured count; propose again at the next close if still oversized.
- Foreign fields and trailing content also require approval before moving or removing them. Propose their destination or removal; preserve and report on refusal. A bullet under a user field that reads as one of its items belongs to that field, however the measurement labels it.

---

## Output Format

Every response that completes a unit of work in which files were created or modified ends with the block below. Exceptions: intermediate mid-task responses (use the `In progress; verification pending` line instead), and responses from the `/klawde` and `/close` commands, which use the exact closing output defined in their own command files.

```
---
COMPLIANCE:
- Assumptions: [list; omit this line entirely if none]
- Verified: [the command you ran and its last output line | none, because X]
- changes.db: [appended NNN: "<rendered line>" | unchanged because X]
- BRIEFING.md: [updated: what changed; omit this line entirely if unchanged]
```

---

## Slash Commands

- `/klawde` : Run the entry protocol. See `.claude/commands/klawde.md`.
- `/close` : Run the close protocol. See `.claude/commands/close.md`.
