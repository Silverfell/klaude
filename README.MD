# Klawde

Klawde is a small session harness for Claude Code and Codex. It gives a project three records — a four-field primer, an immutable log of what happened, and a table of approved work that is not finished — and three commands that read and write them.

## What it does

- **Forces an explicit session start.** `/klawde` reads the records before any work begins, and creates them the first time.
- **Keeps a primer.** `BRIEFING.md` holds four fields saying what this project is and how it is built, and nothing else.
- **Keeps an immutable log.** `changes.db` records what happened, in three types. Entries are never edited, deleted or renumbered; the database enforces it.
- **Keeps a task table.** `tasks` holds approved, unfinished work. Nothing else: no doubts, no maybes, no ideas nobody asked for.

## Installation

Clone this repo somewhere local:

```bash
git clone https://github.com/Silverfell/klaude.git
```

Move into the project where you want it and run the setup script. It asks which target to install for; a flag skips the prompt:

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
- `.claude/commands/upgrade_klawde.md`
- `.claude/changes-schema.sql`

For Codex, it writes the contract as `AGENTS.md` and installs the protocols as repo-level [skills](https://developers.openai.com/codex/skills), invoked as `$klawde`, `$close` and `$upgrade_klawde` (or picked from `/skills`):

- `AGENTS.md`
- `.agents/skills/klawde/SKILL.md`
- `.agents/skills/close/SKILL.md`
- `.agents/skills/upgrade_klawde/SKILL.md`
- `.agents/changes-schema.sql`

Both layouts also get `guidelines.md` at the project root, written once even under `--both`.

Setup checks every destination before writing anything, and stops if a prompt is reached with stdin closed, so pass the flags for unattended runs. It does not create the records: `/klawde` does that on its first run. Restart any open Claude Code session afterwards, since slash commands load at session start.

## The commands

### `/klawde`

Run it at the start of every session. (The name avoids colliding with Claude Code's built-in `/init`.) It creates the records if they are missing, checks the log's schema version, reads the brief and `guidelines.md` if it is there, then prints the last five entries and the open tasks verbatim, with the git dirty state. It summarizes nothing.

### `/close`

Run it at the end of a session, or mid-session as a checkpoint. It is a sweep, not a reconstruction: it logs finished work that was not logged as it happened, closes any completed task that still has a row, updates any brief field whose fact changed, and reports the new serials and the open task count.

### `/upgrade_klawde`

Run it once after `upgrade.sh`, and only then. It backs up `changes.db`, rewrites the log to the new schema, drops the retired tables, offers each open concern as a task, walks you through the brief's four fields, and offers `guidelines.md` if you have none.

## The records

### `BRIEFING.md`

A primer: not a design document, not a scratchpad, not a history. Four fields, one line each:

- `Purpose` — what the project is.
- `Scope` — what it is supposed to do. This changes often, especially early.
- `Key decisions` — architectural directives: what technology, used in what way, agreed between you and the agent.
- `Areas` — the project's parts, at an architectural level.

It holds what is true now: no reasons, no progress, no receipts, no history. There is no size limit and no checker; you read it now and then and say what to fix. A change is never silent: what you said is written and stated back to you, and what the agent derived is proposed as an exact line and written only once you answer.

### `changes.db`

A SQLite database in the project root, committed like any other project file, holding two tables.

`entries` is the log: append-only and immutable, enforced by triggers, one line of at most 600 characters each. An `UPDATE` or `DELETE` aborts, and so does a reused serial or one below the maximum. Three types:

- `decided` — a choice you made that the code, its comments and the docs do not already show.
- `done` — an approved task was completed and verified.
- `changed` — anything else: direction, a patch, an edited value, added content.

Not everything is logged; the code and its documentation carry most of it. A session reads the last five entries and stops. Older history is queried when a question calls for it, never skimmed for background, and nothing is ever pruned.

`tasks` is approved, unfinished work: `id`, `date`, `task`, one line each, no priority and no ordering. A row appears when you approve work and is deleted when that work is done or abandoned; a completed one becomes a `done` entry. The agent may edit a row's text as it learns more, and says so. A defect it finds is reported in conversation and becomes a row only if you want it fixed.

Both tables render through a view, so a read is one command:

```sh
sqlite3 -readonly changes.db "SELECT line FROM log_lines ORDER BY serial DESC LIMIT 5;"
```

### `guidelines.md`

How code is written in this project: deviation labels, the core code rules, scope and communication, code and code craft, tools, architecture, reviews, decision rules and verification. It ships with klawde's defaults and is yours from that moment. `upgrade.sh` never writes it, not even when it is absent: deleting the file is how you turn those rules off. Only `/klawde` reads it, and it says nothing when it is gone.

## Upgrading

An upgrade is two steps, in this order. First, copy the files:

```bash
/path/to/klaude/upgrade.sh              # detects the install, then prompts
/path/to/klaude/upgrade.sh --claude     # force Claude Code
/path/to/klaude/upgrade.sh --codex      # force Codex
/path/to/klaude/upgrade.sh --both       # force both layouts
/path/to/klaude/upgrade.sh --no-backup  # skip the backup prompt, create no .bak files
```

With no target flag it detects the existing install and offers it as the default. A `CLAUDE.md` or `AGENTS.md` with no klawde files beside it may be your own, so it is overwritten only after you confirm. It optionally backs up what it overwrites, and deletes the two checker scripts older versions installed. It touches no record: `changes.db`, `BRIEFING.md` and `guidelines.md` are left as they are.

Second, in your agent, run `/upgrade_klawde` (`$upgrade_klawde` in Codex). This step is required: the new commands read `PRAGMA user_version` first and refuse to work against an older log. The migration keeps every entry with its serial and date, types them all `done`, folds the old `refs` text into the description, drops the retired tables, and rewrites the brief with your approval on each field. It backs the database up first and says where.

## Requirements

The `sqlite3` CLI, on your PATH. It is preinstalled on macOS and packaged on every mainstream Linux distribution. Nothing else.
