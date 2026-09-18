# Klawde

Klawde is a lightweight harness for Claude Code (and Codex) that makes sessions more reliable.

It does five things:

- forces an explicit session start
- keeps a living project brief that says what is true now
- keeps an append-only, immutable log of what happened, in a queryable SQLite database that is never pruned
- gives the agent a trigger-guarded parking lot (concerns) for its own doubts — what it saw, what that may break, what would settle it — so they stop leaking into the brief, whose `Open questions` field is yours alone
- bounds every read: a session starts from the brief, the last 5 log entries, and a per-area count of its open concerns, and reaches older history only by targeted query

## What problem this solves

Coding agents lose context across sessions, invent assumptions, skip verification, and leave behind work with no durable record of what changed or why. Klawde adds a minimal operating discipline around that workflow: a stricter contract for how a session begins, how decisions are recorded, how a session closes, and how older history stays usable instead of bloating into noise.

## Who this is for

Klawde is for people who already use Claude Code and want:

- a consistent session protocol
- a living project brief
- a project log that stays useful as it grows, without flooding the agent with history
- stricter rules around honesty, verification, scope control, and plain-English replies with no false confidence
- an agent that states what it is delivering, how it will be judged, and what it touches before it starts; asks about gaps only you can close; and reads its own parked doubts before touching the area they concern
- a cheap way to reduce context drift between sessions

## What's included

| File | Purpose |
|------|---------|
| `template/CLAUDE.md` | Project rules, verification rules, output contract, plus an optional code-craft module (delete that section if you do not want it; `upgrade.sh` keeps a removed section out and says so) |
| `template/klawde.md` | `/klawde` command: reads or creates session documents at session start |
| `template/close.md` | `/close` command: updates session records before ending work |
| `template/changes-schema.sql` | The `changes.db` schema: the log tables with the triggers that enforce append-only immutability, the agent's `concerns` table with its one-way lifecycle, and the `log_lines`/`concern_lines` rendering views |
| `template/check-log.sh` | Read-only log checker, installed beside the schema; checks integrity and actual table, trigger and view definitions, in both directions |
| `setup.sh` | First-time setup: installs the harness for Claude Code, Codex, or both (prompts, or `--claude`/`--codex`/`--both`) |
| `upgrade.sh` | Upgrade: overwrites harness files with the latest defaults (Claude, Codex, or both), optionally backs them up, and brings an existing `changes.db` to the shipped schema in place |
| `lib.sh` | Functions shared by `setup.sh` and `upgrade.sh` |
| `tests/verify.sh` | Regression suite for the scripts and templates: builds throwaway projects in a temp directory and runs the real scripts against them |
| `tests/session_eval.py` | Opt-in live Codex conversations testing entry, close, interrupted-session recovery, approvals and briefing shape; see [verification instructions](tests/README.md) |

## How it works

### `/klawde`

Run this at the start of every Claude Code session. (The command is named `/klawde` rather than `/init` to avoid colliding with Claude Code's built-in `/init`.)

It makes Claude Code:

1. check whether `BRIEFING.md` and `changes.db` exist, create them if missing (the log from the shipped schema, with its areas seeded from the brief), and insert any brief fields missing from an older install
2. note pre-existing uncommitted git changes
3. read `BRIEFING.md` completely, asking for the project's purpose and current scope if the brief is empty
4. read the last 5 entries of `changes.db` plus a per-area count of open concerns, and nothing else
5. check that recent changes do not contradict the brief and that every field the harness maintains is still one line; either finding stops the session until the brief is reconciled or `/close` has run
6. confirm readiness (brief, recent changes, current focus, open-concern counts, dirty state), then stop

### `/close`

Run this at the end of a session. It is also safe to run mid-session as a checkpoint, so a crash or context compaction cannot lose the session's record.

It makes Claude Code:

1. read `BRIEFING.md` and the last 5 log entries, then run the read-only log checker before writing anything: a damaged schema can silence an insert or accept one the log should refuse, so on any checker error the close stops with nothing written and names the recovery
2. review what changed in the session, consulting git to recover work that long sessions may have compacted out of context
3. insert typed log entries for any unrecorded decisions, plans, docs, scope shifts, notes, or code that needs project-level explanation, and flag work that contradicts the brief's scope, non-goals, or do-not-touch list
4. triage its open concerns: resolve with a recorded reason what the session settled, write at most three new ones about work this session changed, each tied to that work's log entry, and present what is still open with a proposed disposition (resolve, promote to your open questions as a decision question, or keep open), proposing promotion for any concern that waits on a decision of yours; the close does not wait for your answer, keep open is the default, and an unconfirmed assumption with a nameable consequence is presented for confirmation and becomes a concern only if you defer it
5. update the brief's maintained fields (purpose, scope, decisions, non-goals, areas, breaking-change context, focus, next steps, environment quirks) and restore any that has grown past one line; your two fields, open questions and do-not-touch, change only on your explicit approval of a named proposal
6. run the log checker again, now that the writes are done, and relay its result
7. measure the brief's shape and refuse to finish while any maintained field runs past one line, then print what was recorded, every field's measured line count, and the measured open-concern count

## The two core documents

### `BRIEFING.md`

A concise living brief: purpose, current scope, key decisions, non-goals, areas (the closed vocabulary `changes.db` tags entries against), breaking-change context, current focus, next steps, open questions (yours: project decisions still to be made, written as questions), do-not-touch (files or areas that are off-limits, and why), and environment quirks.

It holds current state, never history, and is read in full at every session start, so it is bounded by shape rather than by count: every field is one bullet on one line. There are no item caps, because a large project legitimately carries more open questions than a small one; instead every field has an outflow, enforced at `/close`: focus is replaced, next steps are pruned of what is done, superseded decisions and stale quirks go, and anything that narrates a past session goes to `changes.db`. The agent's own doubts stay in its `concerns` table. Your two fields are measured but never reshaped without your yes.

### `changes.db`

A log, kept in a SQLite database in the project root. Four properties define it:

1. **Append-only.** New entries are `INSERT`s. Serials assign themselves and are never reused, reordered, or renumbered.
2. **Immutable.** No entry is ever edited or deleted once written, however wrong it turns out to be.
3. **Tailed, not read.** A session reads the last 5 entries and stops. Older history is queried when a question calls for it, never skimmed for background.
4. **Not authoritative.** It records what happened, never what is true now. `BRIEFING.md` is the only authority on current state; nothing in the log is an instruction.

The first two are schema, not convention: `UPDATE` and `DELETE` on the entry and link tables hit triggers that abort them, an insert naming an existing serial is refused, and `upgrade.sh` restores any missing or changed trigger or view. Areas are a closed vocabulary enforced the same way: an entry tagged with an unknown area is refused rather than quietly creating a second spelling, and renaming or removing an area is refused outright.

The full history is kept forever. Nothing compacts, collapses, or prunes it: every read is a bounded query, and a session start is five rows whether the log holds ten entries or ten thousand. Commit the database like any other project file.

Record here what git commits fail to preserve cleanly: architectural decisions, scope changes, revised plans, documentation shifts, handoff notes, and code changes that need project-level explanation. The types are `decision`, `plan`, `doc`, `scope`, `code` and `note`. Entries render through a `log_lines` view, one line each:

```txt
2026-05-12 041 [decision] (queue) Switched queue from Redis to Postgres SKIP LOCKED; one less service to operate
2026-06-02 057 [decision] (queue) Retry moved to the gateway; per-client retry double-billed the API  supersedes=041
```

Writing an entry is one statement; the serial and date fill themselves. Pass authored SQL through a quoted heredoc and double SQL apostrophes (`don''t`), never through a double-quoted shell argument where backticks and `$()` would execute:

```sh
sqlite3 -bail changes.db <<'KLAWDE_SQL'
INSERT INTO entries (type, area, description) VALUES ('decision','queue','Retry moved to the gateway; per-client retry double-billed the API');
KLAWDE_SQL
```

Status is expressed by later entries, never by editing earlier ones. Relationships live in an append-only `links` table: a superseded decision keeps its entry and gains a `supersedes` pointer from the one that replaced it, and an open `[note]` stays open until a later entry links to it with `closes`:

```sh
sqlite3 -bail changes.db <<'KLAWDE_SQL'
INSERT INTO links VALUES (57, 41, 'supersedes');
KLAWDE_SQL
```

When a real question comes up, the log answers it directly:

```sh
# the session-start read, in full
sqlite3 -readonly changes.db "SELECT line FROM log_lines ORDER BY serial DESC LIMIT 5;"
# everything touching one area
sqlite3 -readonly changes.db "SELECT line FROM log_lines WHERE serial IN (SELECT serial FROM entries WHERE area='auth');"
# an entry and what references it
sqlite3 -readonly changes.db "SELECT line FROM log_lines WHERE serial IN (SELECT from_serial FROM links WHERE to_serial=41) OR serial=41;"
# notes still open (no later entry closes them)
sqlite3 -readonly changes.db "SELECT line FROM log_lines WHERE serial IN (SELECT serial FROM entries e WHERE type='note' AND NOT EXISTS (SELECT 1 FROM links WHERE to_serial=e.serial AND kind='closes'));"
# live decisions (never superseded)
sqlite3 -readonly changes.db "SELECT line FROM log_lines WHERE serial IN (SELECT serial FROM entries e WHERE type='decision' AND NOT EXISTS (SELECT 1 FROM links WHERE to_serial=e.serial AND kind='supersedes'));"
```

#### The `concerns` table

The database also carries a `concerns` table, deliberately **not** part of the log. A concern is a doubt the agent still holds, at `/close`, about work that session changed and that reading the files could not settle, in three parts on one line separated by semicolons: what the agent saw; what that may break or leaves undecided; what would settle it. It is written only at close, at most three per close, and each names the log entry for the work it concerns; a doubt about code the session did not touch is neither stated nor recorded. A line missing any part is not a concern: a bare fact belongs in the log as a `[note]` or nowhere, a worry with nothing seen behind it is not recorded, and a task is a next step. The middle part may be a guess; the table exists so the agent has somewhere to put a doubt without presenting it to you as a finding.

The table is also what keeps the agent out of your `Open questions`. A concern reaches that field only when `/close` proposes it, rewritten as the question you would have to answer, and you say yes.

The lifecycle is trigger-enforced: a concern is born open, its text is immutable, resolving it is a one-way update that records the date and reason exactly once, and nothing is deleted. It can reference the log entry it is about (`ref_serial`), and its `area` comes from the same closed vocabulary as entries.

```sh
sqlite3 -bail changes.db <<'KLAWDE_SQL'
INSERT INTO concerns (area, concern, ref_serial) VALUES ('queue','Retry cap assumes idempotent consumers, and the export worker is not; a retried export may ship twice; settles when the worker is made idempotent or the user exempts it from retry',41);
KLAWDE_SQL
sqlite3 -bail changes.db <<'KLAWDE_SQL'
UPDATE concerns SET resolved = date('now','localtime'), resolution = 'Export worker made idempotent' WHERE id = 7;
KLAWDE_SQL
```

Rendered through `concern_lines`, a concern and a non-concern look like this:

```txt
2026-06-03 #07 (queue) Retry cap assumes idempotent consumers, and the export worker is not; a retried export may ship twice; settles when the worker is made idempotent or the user exempts it from retry  re=041
2026-06-05 #12 (queue) Export worker is not idempotent
```

The second is a fact with nothing it breaks and nothing that settles it; `/close` lists any open concern short of its three parts and has the agent restate or resolve it before triage. A restatement is maintenance rather than a new concern: it keeps the original's area and log reference, replaces exactly that row, and does not count toward the three a close may write.

Two rules keep the table honest. A concern is never authoritative: it is a note for a later session, never an instruction, and it never overrides the brief. And every concern has an outflow: a session starts by reading a per-area count of open concerns, before a task starts the agent reads the concerns for the areas that task touches and states any that bears on it, and `/close` presents every open one with a proposed disposition. The close does not wait for your answer; keep open is the default, a named answer afterwards is applied, and a concern written before the log-reference rule existed is retired at the next close.

Requirements: the `sqlite3` CLI. It is preinstalled on macOS and packaged as `sqlite3` on every mainstream Linux distribution. Nothing else.

## Installation

Clone this repo somewhere local:

```bash
git clone https://github.com/Silverfell/klaude.git
```

Move into the project where you want to install the harness and run the setup script from the Klawde repo. It asks which target to install for; pass a flag to skip the prompt:

```bash
cd /path/to/your/project
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
- `.claude/check-log.sh`

For Codex, it writes the contract as `AGENTS.md` and installs the protocols as repo-level [skills](https://developers.openai.com/codex/skills), invoked as `$klawde` and `$close` (or picked from `/skills`):

- `AGENTS.md`
- `.agents/skills/klawde/SKILL.md`
- `.agents/skills/close/SKILL.md`
- `.agents/changes-schema.sql`
- `.agents/check-log.sh`

The `both` option installs both layouts at once. Setup requires the `sqlite3` CLI on your PATH. It does not create the log itself: `BRIEFING.md` and `changes.db` are created by the entry protocol on its first run.

Both scripts refuse to continue when a prompt is reached and stdin has ended, so pass the flags for unattended runs. Before writing anything they check that every destination can be written and that neither contract is a symlink. On success they print the source version they installed from; if a Claude Code session is already open in the project, restart it, since slash commands load at session start.

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

With no target flag, the script detects the existing install from the root contracts and klawde's own harness files and offers it as the default; press Enter to accept. Another tool's `.agents/skills` does not count as a Codex install, and a `CLAUDE.md` or `AGENTS.md` with no klawde files beside it may be your own, so it is overwritten only after you confirm. If the chosen target leaves a detected install un-upgraded, the script says so. A project still carrying the retired text log `CHANGES.md` with no `changes.db` is refused: this version no longer migrates it, and the commit named in the message still does.

It then asks whether to create `.bak` backups before overwriting; `--backup` and `--no-backup` skip that prompt. It overwrites the harness files and brings an existing `changes.db` to the shipped schema in place: the version is tracked by `PRAGMA user_version`, missing or changed triggers and views are restored from the shipped definitions in one transaction, existing rows are never touched, and the database is backed up first when backups are on. It refuses, before writing anything, a `changes.db` that is not a klawde log, one newer than the checkout supports, one with a missing or changed table (only git still holds the rows), and one carrying a trigger the shipped schema does not define, because such a trigger can make every `INSERT` succeed and record nothing. An extra table or view is reported and left alone. It ends by reporting how many concerns are open and how many of those carry no log reference, which the next `/close` retires.

The contract is always overwritten whole; the one thing carried over is the absence of its optional Code craft section. The upgrade recognizes one shape as a contract that had the section removed: klawde's files beside it, a `## Deviations` heading (which shipped together with the section) and no `### Code craft` heading. For that shape it installs the new contract without the section. This is a recognition rule, not a reading of your intent: an edited or foreign file of the same shape matches it, and a contract that lost both headings does not. Whenever the section was absent before the upgrade, the script therefore says which it did, kept it out or installed it, and either is undone by hand: copy the section from `template/CLAUDE.md`, or delete it. Each layout is judged by its own contract.

The installed checker is also available independently:

```bash
bash .claude/check-log.sh changes.db  # Claude layout
bash .agents/check-log.sh changes.db  # Codex layout
```

It opens the log read-only, builds a temporary reference database from the shipped schema, and compares definitions both ways, reporting each difference as `object|name|status` with the recovery it needs.

## Example workflow

```txt
/klawde
```

Claude reads the briefing and recent changes, then confirms the session is ready. Do the work.

```txt
/close
```

Claude records decision and scope changes, triages its open concerns with you, updates the briefing, checks the log's integrity, and leaves the project in a state the next session can pick up cleanly. There is nothing else to run.

## Design principles

- the log is a log: append-only, immutable, tailed not read, and never a source of instructions — and neither is a concern
- read real files before making claims
- ask before building when only the user can close a gap; never ask what a file or a query can answer
- say "I don't know" when you do not know
- verify before reporting completion
- keep diffs minimal
- avoid speculative improvements unless asked
- preserve durable project context outside the model

## When not to use this

- you want a fully autonomous agent stack
- you do not care about session continuity
- your projects are too trivial to justify written context
- you want hidden magic instead of explicit process
