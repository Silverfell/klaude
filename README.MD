# Klawde

Klawde is a lightweight harness for Claude Code (and Codex) that makes sessions more reliable.

It does five things:

- forces an explicit session start
- keeps a living project brief that says what is true now
- keeps an append-only, immutable log of what happened, in a queryable SQLite database that is never pruned
- gives the agent a trigger-guarded parking lot (concerns) for its own doubts — what it saw, what that may break, what would settle it — so they stop leaking into the brief, whose `Open questions` field is yours alone
- bounds every read: a session starts from the brief, the last 5 log entries, and a per-area count of its open concerns, and reaches older history only by targeted query

The goal is simple: less agent drift, less forgotten context, less vague "the model probably remembers" nonsense.

## What problem this solves

Coding agents are useful, but they are sloppy by default.

They lose context across sessions, invent assumptions, skip verification, and leave behind work with no durable record of what changed or why. Klawde adds a minimal operating discipline around that workflow.

It is not a framework.
It is not an IDE plugin.
It is not a memory layer.

It is a small harness that gives Claude Code a stricter contract for how a session begins, how decisions are recorded, how a session closes, and how older history stays usable instead of bloating into noise.

## Who this is for

Klawde is for people who already use Claude Code and want:

- a consistent session protocol
- a living project brief
- a project log that stays useful as it grows, without flooding the agent with history
- stricter rules around honesty, verification, scope control, and plain-English replies with no false confidence
- an agent that asks about genuine unknowns before building — it must be able to state what it is delivering, how it will be judged, and what it touches before it starts; gaps only you can close become batched questions, and minutiae it can sort out itself never do; before it touches an area where it left a doubt, it reads those doubts and states any the task depends on
- a cheap way to reduce context drift between sessions

It is especially useful on projects where architecture, scope, and decision history matter more than just the final diff.

## What's included

| File | Purpose |
|------|---------|
| `template/CLAUDE.md` | Project rules, verification rules, output contract, plus an optional code-craft module (delete that section if you only want drift and efficiency control; `upgrade.sh` restores it and says so, so delete it again after upgrading) |
| `template/klawde.md` | `/klawde` command: reads or creates session documents at session start |
| `template/close.md` | `/close` command: updates session records before ending work |
| `template/changes-schema.sql` | The `changes.db` schema: the log tables with the triggers that enforce append-only immutability, the agent's `concerns` table with its one-way lifecycle, and the `log_lines`/`concern_lines` rendering views |
| `setup.sh` | First-time setup: installs the harness for Claude Code, Codex, or both (prompts, or `--claude`/`--codex`/`--both`) |
| `upgrade.sh` | Upgrade: overwrites harness files with the latest defaults (Claude, Codex, or both), optionally backs them up, migrates a legacy `CHANGES.md` into `changes.db`, upgrades an existing `changes.db` schema in place, and retires the legacy `/init`, `/klaude`, and `/compresschanges` commands |
| `tests/verify.sh` | Regression suite for both scripts: builds throwaway projects in a temp directory and runs the real scripts against them |

## How it works

### `/klawde`

Run this at the start of every Claude Code session. (The command is named `/klawde` rather than `/init` to avoid colliding with Claude Code's built-in `/init`.)

It makes Claude Code:

1. check whether `BRIEFING.md` and `changes.db` exist, create them if missing (the log from the shipped schema, with its areas seeded from the brief), and insert any brief fields missing from an older install in their template position
2. note pre-existing uncommitted git changes (informational: possible unfinished work from a prior session)
3. read `BRIEFING.md` completely
4. ask for the project's purpose and current scope if the brief is empty
5. read the last 5 entries of `changes.db`, plus a per-area count of open concerns — that is the whole read; older history is queried, not skimmed, and a concern is read only when a task touches its area
6. check that recent changes do not contradict the brief and that every field the harness maintains is still one line — either finding stops the session until the brief is reconciled or `/close` has run; your own two fields, open questions and do-not-touch, are only noted when they run past a line, and stale focus or next steps are only flagged
7. confirm readiness (brief, recent changes, current focus, open-concern counts by area, dirty state), then stop

This forces the session to begin from actual project state instead of hand-waving.

### `/close`

Run this at the end of a session. It is also safe to run mid-session as a checkpoint, so a crash or context compaction cannot lose the session's record.

It makes Claude Code:

1. read `BRIEFING.md` and the last 5 log entries — the same tail as a session start, never the whole log
2. review what changed in the session, consulting git to recover work that long sessions may have compacted out of context
3. insert typed log entries — the serial and date assign themselves — for any unrecorded decisions, plans, docs, scope shifts, notes, or code that needs project-level explanation
4. flag work that contradicts the brief's scope, non-goals, or do-not-touch list
5. triage every open concern — the agent's own doubts parked in the `concerns` table: record new ones the session raised, turn unconfirmed assumptions with a nameable consequence into concerns, restate any written without their three parts, resolve (with a recorded reason) only what the session genuinely settled, and present everything else to you in one batch with a proposed disposition — resolve, promote to the brief's open questions (rewritten as the question you have to answer), or defer; an assumption it made is presented for a one-word confirmation and becomes a concern only if you defer it, never proposed for promotion; the open count it reports is measured after triage, not tallied; a deferred concern stays open and comes back at the next close
6. update `BRIEFING.md` if purpose, scope, key decisions, non-goals, or breaking-change context changed, or if its fields are still empty
7. refresh the brief's state fields: current focus, next steps, environment quirks, and the area vocabulary (new areas are added to the brief and the database together); open questions are yours: the agent proposes a promotion from its concerns, a removal when you decided the question that session, or a one-line reshape when the field has run past a line, and writes only what you explicitly approve
8. check the log's integrity, reading its schema version first: `PRAGMA integrity_check`, the 28 triggers that enforce immutability, the concern lifecycle, and well-formed rows, and the seven tables and views must all be in place for that version; anything missing is reported with a pointer to `upgrade.sh`, which restores it
9. measure the brief's shape and refuse to finish while any field it maintains runs past one line — your two fields are proposed a one-line form and left as you decide — then confirm what was recorded, with every field's line count and the measured open-concern count, and stop

This gives the next session a real handoff.

## The two core documents

### `BRIEFING.md`

A concise living brief for the project.

Use it for:

- purpose
- current scope
- key decisions
- non-goals
- areas (the closed vocabulary `changes.db` tags entries against, mirrored in its `areas` table)
- breaking-change context
- current focus and next steps (replaced every `/close`; the next session resumes on-thread instead of reinventing direction)
- open questions (your list of project decisions still to be made, written as questions; the agent never puts its own doubts here — it proposes at `/close`, you decide)
- a do-not-touch list (files or areas that are off-limits, and why; the contract forbids the agent to touch them, and the certainty gate asks first when a task would)
- environment quirks (durable context the next session should read without having to query for it)

A new session should be able to read this and understand what the project is trying to do, and what it was about to do next.

It holds current state, never history, and it is read in full at every session start — so it is bounded by shape rather than by count. Every field is one bullet on one line: a sentence or a short list of clauses, as in the example brief. There are no item caps, because a large project legitimately carries more open questions than a small one and no session should delete live state to satisfy a number; but every field has an outflow. `/close` enforces it: one current focus that is replaced rather than appended to, next steps pruned of what is done, open questions touched only on your word (a promotion you approved, or a removal when you decided the question that session), key decisions pruned of what has been superseded, breaking-change context and environment quirks pruned of what no longer holds, and no bullet that narrates a past session — that belongs in `changes.db`. The brief is not a scratchpad: findings, progress, and verification results stay in the agent's replies and the log, and the agent's own doubts stay in its `concerns` table. A maintained field that has grown past one line is restored at the next `/close`, which measures every field's line count, prints the counts in its closing block, and will not finish while a field it maintains is over a line; the session-start protocol stops on such a field the same way it stops on a scope contradiction. Your two fields, open questions and do-not-touch, are measured too but never restored by the agent: it proposes the one-line form and writes it only on your yes.

### `changes.db`

A log, kept in a SQLite database in the project root. Four properties define it, and the whole harness is built on them:

1. **Append-only.** New entries are `INSERT`s. Serials assign themselves and are never reused; nothing is inserted between existing entries, reordered, or renumbered.
2. **Immutable.** No entry is ever edited or deleted once written, however wrong it turns out to be. There is no exception.
3. **Tailed, not read.** A session reads the last 5 entries and stops. Older history is queried when a question calls for it, never skimmed for background.
4. **Not authoritative.** It records what happened, never what is true now. `BRIEFING.md` is the only authority on current state; nothing in the log is an instruction.

The first two are not conventions the agent is asked to respect — they are schema. `UPDATE` and `DELETE` on the entry and link tables hit triggers that abort them, and an insert that names an existing serial is refused rather than replacing the row, and `upgrade.sh` restores any trigger or view that goes missing, so "the agent tidied up the log" is not a failure mode the harness leaves open. Areas are a closed vocabulary enforced the same way: an entry tagged with an area that is not in the `areas` table is refused rather than quietly creating a second spelling, and renaming or removing an area is refused outright.

Property 4 is the one that matters in practice. A `[plan]` from last week is not the current plan, and a `[decision]` may have been reversed sixty entries later — so the agent takes its direction from the brief and treats the log strictly as evidence about the past. Property 3 then means it usually never opens that history at all.

The full history is kept forever. Nothing compacts, collapses, or prunes it, because depth costs nothing: every read is a bounded query, and a session start is five rows whether the log holds ten entries or ten thousand.

The database is a project file. Commit it like any other; it is meant to travel with the repo, and diffs of it are opaque by design (it is append-only, so the interesting question is always "what was added", which the tail query answers).

This is not a git log. It is where you record things git commits usually fail to preserve cleanly:

- architectural decisions
- scope changes
- revised plans
- documentation shifts
- handoff notes
- code changes that need project-level explanation

Entries render through a `log_lines` view, one line each:

```txt
2026-05-12 041 [decision] (queue) Switched queue from Redis to Postgres SKIP LOCKED; one less service to operate
2026-06-02 057 [decision] (queue) Retry moved to the gateway; per-client retry double-billed the API  supersedes=041
```

Types:

- `decision`
- `plan`
- `doc`
- `scope`
- `code`
- `note`

The serial is assigned by the database, never reused and never renumbered. It is what lets one entry point at another. The area comes from the `Areas` list in `BRIEFING.md`, or is `-` when nothing fits.

Writing an entry is one statement, and the serial and date fill themselves:

```sh
sqlite3 changes.db "INSERT INTO entries (type, area, description) VALUES ('decision','queue','Retry moved to the gateway; per-client retry double-billed the API');"
```

Because it is a log rather than a document, status is expressed by later entries rather than by editing earlier ones — and relationships live in their own append-only `links` table, so recording one is an insert, never an edit:

```sh
sqlite3 changes.db "INSERT INTO links VALUES (57, 41, 'supersedes');"
```

A superseded decision keeps its entry and gains a pointer from the one that replaced it. An open `[note]` stays open until some later entry links to it with `closes`; nothing marks the original done.

This is also what makes property 3 workable. A session reads five rows and nothing else; when a real question comes up, the log answers it directly:

```sh
# the session-start read, in full
sqlite3 -readonly changes.db "SELECT line FROM log_lines ORDER BY serial DESC LIMIT 5;"
# every decision ever recorded
sqlite3 -readonly changes.db "SELECT line FROM log_lines WHERE serial IN (SELECT serial FROM entries WHERE type='decision');"
# everything touching one area
sqlite3 -readonly changes.db "SELECT line FROM log_lines WHERE serial IN (SELECT serial FROM entries WHERE area='auth');"
# an entry and what references it
sqlite3 -readonly changes.db "SELECT line FROM log_lines WHERE serial IN (SELECT from_serial FROM links WHERE to_serial=41) OR serial=41;"
# notes still open (no later entry closes them)
sqlite3 -readonly changes.db "SELECT line FROM log_lines WHERE serial IN (SELECT serial FROM entries e WHERE type='note' AND NOT EXISTS (SELECT 1 FROM links WHERE to_serial=e.serial AND kind='closes'));"
# live decisions (never superseded)
sqlite3 -readonly changes.db "SELECT line FROM log_lines WHERE serial IN (SELECT serial FROM entries e WHERE type='decision' AND NOT EXISTS (SELECT 1 FROM links WHERE to_serial=e.serial AND kind='supersedes'));"
```

The last two are the ones a text file could never answer in a single pass: "which findings are still open" and "which decisions still hold" both require knowing what *later* entries did to an earlier one, which is a join, not a grep. Under the old text log they were approximated by reading the whole file — which is exactly what property 3 forbids.

#### The `concerns` table

Since schema v3 the database also carries a `concerns` table, and it is deliberately **not** part of the log. A concern is a doubt the agent holds about the project — present tense, where the log is history. It is a fact plus the trouble it implies, in three parts on one line, separated by semicolons: what the agent saw; what that may break or leaves undecided; what would settle it. A line missing any part is not a concern: a bare fact belongs in the log as a `[note]` or nowhere, a worry with nothing seen behind it is not recorded, and a task is a next step. The middle part is allowed to be a guess — the table exists so the agent has somewhere to put a doubt without presenting it to you as a finding.

The table is also what keeps the agent out of your `Open questions`. That field in the brief is yours: the project decisions you have still to make, written as questions. The agent never writes its own doubts there. A concern reaches it only when `/close` proposes it — rewritten as the question you would have to answer — and you say yes.

The discipline is trigger-enforced, like everything else here: a concern is born open, its text is immutable from the moment it is written, resolving it is a one-way update that records the date and the reason exactly once, and nothing is ever deleted. The triggers enforce immutability and one-way resolution; resolving honestly — never emptying the list to shorten it — is a protocol rule, not schema. It can reference the log entry it is about (`ref_serial`), and its `area` comes from the same closed vocabulary as entries.

```sh
sqlite3 changes.db "INSERT INTO concerns (area, concern, ref_serial) VALUES ('queue','Retry cap assumes idempotent consumers, and the export worker is not; a retried export may ship twice; settles when the worker is made idempotent or the user exempts it from retry',41);"
sqlite3 changes.db "UPDATE concerns SET resolved = date('now','localtime'), resolution = 'Export worker made idempotent' WHERE id = 7;"
```

Rendered through `concern_lines`, a concern and a non-concern look like this:

```txt
2026-06-03 #07 (queue) Retry cap assumes idempotent consumers, and the export worker is not; a retried export may ship twice; settles when the worker is made idempotent or the user exempts it from retry  re=041
2026-06-05 #12 (queue) Export worker is not idempotent
```

The second is a fact with nothing it breaks and nothing that settles it. `/close` lists any open concern short of its three parts and has the agent restate or resolve it before triage.

Two rules keep it honest:

- **Never authoritative.** A concern is a note for a later session that has none of the writer's context, not an instruction, and it never overrides the brief. It reaches `Open questions` only through a `/close` proposal that you approve, as a question.
- **Every concern has an outflow.** A session starts by reading a per-area count of open concerns; before a task starts it reads the concerns for the areas that task touches and states any that bears on it, so you see the doubt at the moment it matters. Reading one is not acting on it. `/close` reads every open concern and disposes of each: the agent resolves — with a recorded reason — what the session genuinely settled, and presents everything else to you with a proposed disposition: resolve, promote, or defer. The third part of the concern, what settles it, says which: one a decision of yours settles is proposed for promotion; one a check or a fix settles is the agent's to dispose of at close — resolved if the session's work already settled it, otherwise kept open with the check offered as work you can assign, never run because the concern says so. An assumption the agent made is presented for a one-word confirmation and becomes a concern only if you defer it. The open count in the closing block is measured after triage, not tallied. Deferring keeps it open, and it comes back at the next close, so nothing rots silently and nothing is buried without you seeing it.

Requirements: the `sqlite3` CLI. It is preinstalled on macOS and packaged as `sqlite3` on every mainstream Linux distribution. Nothing else — no server, no extension, no Python.

## Installation

Clone this repo somewhere local:

```bash
git clone https://github.com/Silverfell/klaude.git
```

Move into the project where you want to install the harness:

```bash
cd /path/to/your/project
```

Run the setup script from the Klawde repo. It asks which target to install for; pass a flag to skip the prompt:

```bash
/path/to/klaude/setup.sh            # prompts: [1] claude [2] codex [3] both
/path/to/klaude/setup.sh --claude   # Claude Code
/path/to/klaude/setup.sh --codex    # Codex
/path/to/klaude/setup.sh --both     # both layouts
```

For Claude Code, that copies into the current project:

- `CLAUDE.md`
- `.claude/commands/klawde.md`
- `.claude/commands/close.md`
- `.claude/changes-schema.sql`

For Codex, it writes the contract as `AGENTS.md` and installs the protocols as repo-level [skills](https://developers.openai.com/codex/skills), which travel with the project and are invoked as `$klawde` and `$close` (or picked from `/skills`):

- `AGENTS.md`
- `.agents/skills/klawde/SKILL.md`
- `.agents/skills/close/SKILL.md`
- `.agents/changes-schema.sql`

Skills replace Codex custom prompts, which OpenAI has deprecated.

The `both` option installs both layouts at once: `CLAUDE.md` and `.claude/` for Claude Code, plus `AGENTS.md` and `.agents/` for Codex, each with its own copy of the log schema.

Setup requires the `sqlite3` CLI on your PATH and stops with an install hint if it is missing. It does not create the log itself: `BRIEFING.md` and `changes.db` are created by the entry protocol on its first run.

Both `setup.sh` and `upgrade.sh` refuse to continue when a prompt is reached and stdin has ended — pass the flags for unattended runs. Before writing anything they verify that every template file is present in the source checkout and that every destination can actually be written (writable, not a symlink, not blocked by a stray file where a directory belongs); a `CLAUDE.md` or `AGENTS.md` that is a symlink is always refused, since the two contracts have different content and cannot share one file. On success they print the source version (git commit) they installed from; if a Claude Code session is already open in the project, restart it, since slash commands load at session start.

Then start your tool and run the entry protocol:

```txt
/klawde     # Claude Code
$klawde     # Codex
```

## Upgrading

To overwrite an existing installation with the latest defaults:

```bash
/path/to/klaude/upgrade.sh              # detects the install, then prompts
/path/to/klaude/upgrade.sh --claude     # force Claude Code
/path/to/klaude/upgrade.sh --codex      # force Codex
/path/to/klaude/upgrade.sh --both       # force both layouts
/path/to/klaude/upgrade.sh --no-backup  # skip the backup prompt, create no .bak files
```

With no target flag, the script detects the existing install and offers it as the default; press Enter to accept. Detection looks at the root contracts (`CLAUDE.md` means Claude, `AGENTS.md` means Codex, both present means a combined install) and at klawde's own harness files (its command files and log schema under `.claude/` for Claude, its skills and log schema under `.agents/` for Codex — another tool's `.agents/skills` does not count), so an install whose root contract was renamed or removed is still recognized. If the chosen target leaves a detected install un-upgraded, the script says so before writing anything; and if `AGENTS.md` exists with no `.agents/` klawde files behind it, the file may belong to another tool, so the script asks for confirmation before overwriting it — decline under `both` and only the Claude layout is upgraded; decline under `codex` and nothing is changed.

It then asks whether to create `.bak` backups before overwriting. Answer `n` and no backup files are created. Use `--backup` or `--no-backup` to skip that prompt.

The upgrade script also:

- overwrites the harness files with the latest versions (Claude, Codex, or both layouts), including the log schema, and says so when the overwrite restores a Code craft section you had deleted
- retires klawde's own legacy files only, recognised by the title line (or, for Codex skills, the front-matter name) the shipped versions carried; a file of the same name without it is left in place and reported, and nothing outside the project is ever touched
- removes the legacy `.claude/commands/init.md` (Claude installs only; the entry protocol is now `/klawde`)
- removes the retired `/klaude` command and its Codex skill (the lean mode is gone; `/klawde` is the only entry protocol)
- removes the retired `/compresschanges` command and its Codex skill (the log is never compacted now)
- migrates a legacy text `CHANGES.md` into `changes.db` (see below)
- upgrades an existing `changes.db` schema in place when the shipped schema is newer (tracked by `PRAGMA user_version`; v2 added the triggers that refuse area renames and out-of-order serials, v3 added the `concerns` table, its lifecycle triggers, the `concern_lines` view, and the guards that stop `INSERT OR REPLACE` from rewriting existing rows; v4 added the guards on concern ids, area names — trimmed, never `-`, never a case variant of an existing area — legacy summaries, and well-formed text and dates; v5 added the one-line guards on text and the plain-name guard on areas)
- backs up every harness file it overwrites or removes first, unless you decline backups (`.gitignore` is only appended to, without a backup)
- checks every present `changes.db` before finishing — integrity, tables, triggers, views — restores any trigger or view the shipped schema defines and the database lacks, and fails the run on a missing table or a bad integrity check
- refuses to touch a `changes.db` that is not a klawde log: an empty file, a foreign SQLite database, a directory of that name, or a log missing a table its version should have stops the upgrade before anything is written
- runs the preflight checks described under Setup before writing anything — interactive stdin, complete source templates, writable destinations, no symlinked contracts — plus its own: legacy files it will remove must sit in writable directories, an existing `changes.db` must be a klawde log (readable, with the tables its version should have; writable when a schema upgrade or a repair will touch it; refused outright when its schema version is newer than the checkout supports), and a pending `CHANGES.md` migration must be able to replace `CHANGES.md` (a read-only or symlinked `CHANGES.md` is refused), create the database, and update `.gitignore`, must carry no repeated serial and no two areas that differ only by case, and is rehearsed in full in a scratch directory. Should a write still fail mid-run, it reports that the install may be partially updated instead of dying quietly

### Migrating `CHANGES.md` into `changes.db`

This runs once, on the first upgrade after the log became a database. If `changes.db` already exists the step reports that and does nothing. The whole migration is rehearsed in a scratch directory — normalization, the import into a scratch database, and its verification — before anything in the project is written; an entry the schema refuses stops the upgrade with that entry named and nothing changed.

The migration:

1. normalizes legacy line formats first — Windows (CRLF) line endings are stripped so no carriage return can reach the immutable log, old `YYYY-MM-DD: description` entries become `[note]` entries, and entries written before serials and areas existed get both backfilled. Backfilled serials continue above the highest serial already in the file, so in a file that mixes both eras the oldest entries end up with the highest serials; the migration warns when this happens, and the entry it appends in step 7 records it
2. seeds the `areas` table from the brief's `- Areas:` line and from every area any entry actually used, stripped of markdown formatting; two areas that differ only by case are refused in preflight, before anything is written, because the vocabulary will not hold both
3. imports every numbered entry with its **original serial**, date, type, area, description and `refs`, inside one transaction
4. imports `supersedes=` / `closes=` tags as rows in the `links` table. A tag pointing at a serial an old compaction collapsed away has nothing to link to; it is skipped and reported, rather than aborting the import
5. moves any `SUM` summary lines from old compaction runs into a `legacy_summaries` table, so nothing from the text file is thrown away
6. verifies that the entry count and highest serial in the scratch database match the file. On any mismatch it exits nonzero with nothing written
7. on success, appends a `[doc]` entry recording the migration itself — including, when serials were backfilled, the range that is older than its serial order suggests — so the first post-migration tail read explains what happened
8. only then writes: the verified scratch database becomes `changes.db`, the normalized text becomes `CHANGES.md.migrated` (the original is backed up first when it was normalized and backups are on), `CHANGES.md` goes, and, when the project is a git repository, `CHANGES.md.migrated` is added to `.gitignore`

Delete `CHANGES.md.migrated` once you are satisfied with the database, and commit `changes.db`.

## Example workflow

Start session:

```txt
/klawde
```

Claude reads the briefing and recent changes, then confirms the session is ready.

Do the work.

End session:

```txt
/close
```

Claude records decision and scope changes, triages its open concerns with you, updates the briefing if needed, checks the log's integrity, and leaves the project in a state that the next session can pick up cleanly.

There is nothing else to run. The log is never maintained, tidied, or compacted — it keeps everything, and the reads stay bounded regardless.

## Design principles

Klawde is opinionated.

It assumes that better agent output comes from stricter process, not from pretending the model is magically dependable.

Core principles:

- the log is a log: append-only, immutable, tailed not read, and never a source of instructions — and neither is a concern
- read real files before making claims
- ask before building when only the user can close a gap; never ask what a file or a query can answer
- say "I don't know" when you do not know
- verify before reporting completion
- keep diffs minimal
- avoid speculative improvements unless asked
- preserve durable project context outside the model

## When not to use this

Do not use Klawde if:

- you want a fully autonomous agent stack
- you do not care about session continuity
- your projects are too trivial to justify written context
- you want hidden magic instead of explicit process
