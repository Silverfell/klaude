# Klawde

Klawde is a lightweight harness for Claude Code (and Codex) that makes sessions more reliable.

It does four things:

- forces an explicit session start
- keeps a living project brief that says what is true now
- keeps an append-only, immutable log of what happened, in a queryable SQLite database that is never pruned
- bounds every read: a session starts from the brief plus the last 5 log entries, and reaches older history only by targeted query

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
- an agent that asks about genuine unknowns before building — it must be able to state what it is delivering, how it will be judged, and what it touches before it starts; gaps only you can close become batched questions, and minutiae it can sort out itself never do
- a cheap way to reduce context drift between sessions

It is especially useful on projects where architecture, scope, and decision history matter more than just the final diff.

## What's included

| File | Purpose |
|------|---------|
| `template/CLAUDE.md` | Project rules, verification rules, output contract, plus an optional code-craft module (delete that section if you only want drift and efficiency control) |
| `template/klawde.md` | `/klawde` command: reads or creates session documents at session start (full mode, code-craft rules active) |
| `template/klaude.md` | `/klaude` command: same entry protocol in lean mode, with the code-craft rules disabled for the session |
| `template/close.md` | `/close` command: updates session records before ending work |
| `template/changes-schema.sql` | The `changes.db` log schema: tables, the triggers that enforce append-only immutability, and the `log_lines` rendering view |
| `setup.sh` | First-time setup: installs the harness for Claude Code, Codex, or both (prompts, or `--claude`/`--codex`/`--both`) |
| `upgrade.sh` | Upgrade: overwrites harness files with the latest defaults (Claude, Codex, or both), optionally backs them up, migrates a legacy `CHANGES.md` into `changes.db`, upgrades an existing `changes.db` schema in place, and retires the legacy `/init` and `/compresschanges` commands |
| `tests/verify.sh` | Regression suite for both scripts: builds throwaway projects in a temp directory and runs the real scripts against them |

## How it works

### `/klawde`

Run this at the start of every Claude Code session. (The command is named `/klawde` rather than `/init` to avoid colliding with Claude Code's built-in `/init`.)

It makes Claude Code:

1. check whether `BRIEFING.md` and `changes.db` exist, create them if missing (the log from the shipped schema), and add any brief fields missing from an older install
2. note pre-existing uncommitted git changes (informational: possible unfinished work from a prior session)
3. read `BRIEFING.md` completely
4. ask for the project's purpose and current scope if the brief is empty
5. read the last 5 entries of `changes.db` — that is the whole read; older history is queried, not skimmed
6. check that recent changes do not contradict the brief, and flag stale focus or next steps
7. confirm readiness (brief, recent changes, current focus, dirty state), then stop

This forces the session to begin from actual project state instead of hand-waving.

`/klawde` starts the session in full mode: the contract's optional code-craft module (error-handling, batching, typing, and abstraction rules) is active. `/klaude` (note the spelling) runs the same protocol in lean mode: the code-craft module is disabled and the session runs on drift and efficiency control only. Both report the mode in their readiness output.

### `/close`

Run this at the end of a session. It is also safe to run mid-session as a checkpoint, so a crash or context compaction cannot lose the session's record.

It makes Claude Code:

1. read `BRIEFING.md` and the last 5 log entries — the same tail as a session start, never the whole log
2. review what changed in the session, consulting git to recover work that long sessions may have compacted out of context
3. insert typed log entries — the serial and date assign themselves — for any unrecorded decisions, plans, docs, scope shifts, notes, or code that needs project-level explanation
4. flag work that contradicts the brief's scope, non-goals, or do-not-touch list
5. update `BRIEFING.md` if purpose, scope, key decisions, non-goals, or breaking-change context changed, or if its fields are still empty
6. refresh the brief's state fields: current focus, next steps, environment quirks, and the area vocabulary (new areas are added to the brief and the database together); open questions are only proposed, and written only if you explicitly say yes
7. check the log's integrity: `PRAGMA integrity_check` and the nine triggers that enforce immutability are still in place
8. confirm what was recorded, then stop

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
- open questions (added to or edited only with your explicit consent: the agent proposes, you decide)
- a do-not-touch list (files or areas that are off-limits, and why)
- environment quirks (durable context the next session should read without having to query for it)

A new session should be able to read this and understand what the project is trying to do, and what it was about to do next.

It holds current state, never history, and it is read in full at every session start — so it is bounded by shape rather than by count. Every field is one bullet on one line: a sentence or a short list of clauses, as in the example brief. There are no item caps, because a large project legitimately carries more open questions than a small one and no session should delete live state to satisfy a number; but every field has an outflow. `/close` enforces it: one current focus that is replaced rather than appended to, next steps pruned of what is done, open questions pruned of what is answered (only once you have agreed to the change), key decisions pruned of what has been superseded, breaking-change context and environment quirks pruned of what no longer holds, and no bullet that narrates a past session — that belongs in `changes.db`. The brief is not a scratchpad: findings, progress, and verification results stay in the agent's replies and the log. A field that has grown past one line is restored at the next `/close`, and the session-start protocol flags it if it sees one.

### `changes.db`

A log, kept in a SQLite database in the project root. Four properties define it, and the whole harness is built on them:

1. **Append-only.** New entries are `INSERT`s. Serials assign themselves and are never reused; nothing is inserted between existing entries, reordered, or renumbered.
2. **Immutable.** No entry is ever edited or deleted once written, however wrong it turns out to be. There is no exception.
3. **Tailed, not read.** A session reads the last 5 entries and stops. Older history is queried when a question calls for it, never skimmed for background.
4. **Not authoritative.** It records what happened, never what is true now. `BRIEFING.md` is the only authority on current state; nothing in the log is an instruction.

The first two are not conventions the agent is asked to respect — they are schema. `UPDATE` and `DELETE` on the entry and link tables hit triggers that abort them, so "the agent tidied up the log" is not a failure mode that exists. Areas are a closed vocabulary enforced the same way: an entry tagged with an area that is not in the `areas` table is refused rather than quietly creating a second spelling, and renaming or removing an area that entries already use is refused outright.

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
- `.claude/commands/klaude.md`
- `.claude/commands/close.md`
- `.claude/changes-schema.sql`

For Codex, it writes the contract as `AGENTS.md` and installs the protocols as repo-level [skills](https://developers.openai.com/codex/skills), which travel with the project and are invoked as `$klawde`, `$klaude`, and `$close` (or picked from `/skills`):

- `AGENTS.md`
- `.agents/skills/klawde/SKILL.md`
- `.agents/skills/klaude/SKILL.md`
- `.agents/skills/close/SKILL.md`
- `.agents/changes-schema.sql`

Skills replace Codex custom prompts, which OpenAI has deprecated.

The `both` option installs both layouts at once: `CLAUDE.md` and `.claude/` for Claude Code, plus `AGENTS.md` and `.agents/` for Codex, each with its own copy of the log schema.

Setup requires the `sqlite3` CLI on your PATH and stops with an install hint if it is missing. It does not create the log itself: `BRIEFING.md` and `changes.db` are created by the entry protocol on its first run.

Both `setup.sh` and `upgrade.sh` refuse to continue when a prompt is reached and stdin is not interactive — pass the flags instead of piping input. Before writing anything they verify that every template file is present in the source checkout and that every destination can actually be written (writable, not a symlink, not blocked by a stray file where a directory belongs); a `CLAUDE.md` or `AGENTS.md` that is a symlink is always refused, since the two contracts have different content and cannot share one file. On success they print the source version (git commit) they installed from; if a Claude Code session is already open in the project, restart it, since slash commands load at session start.

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

- overwrites the harness files with the latest versions (Claude, Codex, or both layouts), including the log schema
- removes the legacy `.claude/commands/init.md` (Claude installs only; the entry protocol is now `/klawde`)
- removes the retired `/compresschanges` command and its Codex skill (the log is never compacted now)
- removes deprecated Codex prompts from earlier versions in `$CODEX_HOME/prompts/` (defaulting to `~/.codex/prompts/`)
- migrates a legacy text `CHANGES.md` into `changes.db` (see below)
- upgrades an existing `changes.db` schema in place when the shipped schema is newer (tracked by `PRAGMA user_version`; v2 added the triggers that refuse area renames and out-of-order serials)
- backs up every file it overwrites or removes first, unless you decline backups
- runs the preflight checks described under Setup before writing anything — interactive stdin, complete source templates, writable destinations, no symlinked contracts — plus its own: legacy files it will remove must sit in writable directories, an existing `changes.db` must be a readable database (writable when a schema upgrade will touch it, and refused outright when its schema version is newer than the checkout supports), and a pending `CHANGES.md` migration must be able to rewrite `CHANGES.md` in place (a read-only or symlinked `CHANGES.md` is refused), create the database, and update `.gitignore`. Should a write still fail mid-run, it reports that the install may be partially updated instead of dying quietly

### Migrating `CHANGES.md` into `changes.db`

This runs once, on the first upgrade after the log became a database. If `changes.db` already exists the step reports that and does nothing.

The migration:

1. normalizes legacy line formats first — Windows (CRLF) line endings are stripped so no carriage return can reach the immutable log, old `YYYY-MM-DD: description` entries become `[note]` entries, and entries written before serials and areas existed get both backfilled. Backfilled serials continue above the highest serial already in the file, so in a file that mixes both eras the oldest entries end up with the highest serials; the migration warns when this happens, and the entry it appends in step 7 records it
2. seeds the `areas` table from the brief's `- Areas:` line and from every area any entry actually used
3. imports every numbered entry with its **original serial**, date, type, area, description and `refs`, inside one transaction
4. imports `supersedes=` / `closes=` tags as rows in the `links` table. A tag pointing at a serial an old compaction collapsed away has nothing to link to; it is skipped and reported, rather than aborting the import
5. moves any `SUM` summary lines from old compaction runs into a `legacy_summaries` table, so nothing from the text file is thrown away
6. verifies that the entry count and highest serial in the database match the file. On any mismatch it deletes the database and exits nonzero; `CHANGES.md` keeps whatever step 1's normalization produced (content-preserving, and backed up first unless backups were declined)
7. on success, appends a `[doc]` entry recording the migration itself — including, when serials were backfilled, the range that is older than its serial order suggests — so the first post-migration tail read explains what happened
8. renames `CHANGES.md` to `CHANGES.md.migrated` and, when the project is a git repository, adds that name to `.gitignore`

Delete `CHANGES.md.migrated` once you are satisfied with the database, and commit `changes.db`.

## Example workflow

Start session:

```txt
/klawde     # full mode
/klaude     # lean mode, code-craft rules off
```

Claude reads the briefing and recent changes, then confirms the session is ready and which mode it is in.

Do the work.

End session:

```txt
/close
```

Claude records decision and scope changes, updates the briefing if needed, checks the log's integrity, and leaves the project in a state that the next session can pick up cleanly.

There is nothing else to run. The log is never maintained, tidied, or compacted — it keeps everything, and the reads stay bounded regardless.

## Design principles

Klawde is opinionated.

It assumes that better agent output comes from stricter process, not from pretending the model is magically dependable.

Core principles:

- the log is a log: append-only, immutable, tailed not read, and never a source of instructions
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
