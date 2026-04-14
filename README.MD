# Klaude

Klaude is a lightweight harness for Claude Code that makes sessions more reliable.

It does four things:

- forces an explicit session start
- keeps a living project brief up to date
- leaves behind an append-only decision log for the next session
- compresses older change history when the journal gets too large

The goal is simple: less agent drift, less forgotten context, less vague "the model probably remembers" nonsense.

## What problem this solves

Coding agents are useful, but they are sloppy by default.

They lose context across sessions, invent assumptions, skip verification, and leave behind work with no durable record of what changed or why. Klaude adds a minimal operating discipline around that workflow.

It is not a framework.
It is not an IDE plugin.
It is not a memory layer.

It is a small harness that gives Claude Code a stricter contract for how a session begins, how decisions are recorded, how a session closes, and how older history stays usable instead of bloating into noise.

## Who this is for

Klaude is for people who already use Claude Code and want:

- a consistent session protocol
- a living project brief
- an append-only project journal
- stricter rules around honesty, verification, and scope control
- a cheap way to reduce context drift between sessions

It is especially useful on projects where architecture, scope, and decision history matter more than just the final diff.

## What's included

| File | Purpose |
|------|---------|
| `CLAUDE.md` | Project rules, coding discipline, verification rules, and output contract |
| `init.md` | `/init` command: reads or creates session documents at session start |
| `close.md` | `/close` command: updates session records before ending work |
| `compresschanges.md` | `/compresschanges` command: compacts older `CHANGES.md` history into summaries |
| `setup.sh` | First-time setup: copies the harness files into your project |
| `upgrade.sh` | Upgrade: overwrites harness files with the latest defaults and converts legacy `CHANGES.md` entries |

## How it works

### `/init`

Run this at the start of every Claude Code session.

It makes Claude Code:

1. check whether `BRIEFING.md` exists
2. check whether `CHANGES.md` exists
3. create them if missing
4. read `BRIEFING.md` completely
5. read at least the last 30 lines of `CHANGES.md`
6. confirm readiness, then stop

This forces the session to begin from actual project state instead of hand-waving.

### `/close`

Run this at the end of a session.

It makes Claude Code:

1. review the current `CHANGES.md` and `BRIEFING.md`
2. review what changed in the session
3. append typed journal entries for any unrecorded decisions, plans, docs, scope shifts, notes, or code that needs project-level explanation
4. update `BRIEFING.md` if purpose, scope, key decisions, non-goals, or breaking-change context changed
5. confirm what was recorded, then stop

This gives the next session a real handoff.

### `/compresschanges`

Run this when `CHANGES.md` has grown too large.

It makes Claude Code:

1. read `CHANGES.md` completely
2. identify entries older than 30 days
3. group those older entries by month
4. replace older low-level history with summary lines by major theme or area of work
5. preserve decision entries, scope changes, and breaking-change context verbatim
6. leave the last 30 days untouched
7. keep the file header and format hint intact
8. report how many lines were compressed and preserved, then stop

This keeps the journal useful instead of letting it become an unreadable dump.

## The two core documents

### `BRIEFING.md`

A concise living brief for the project.

Use it for:

- purpose
- current scope
- key decisions
- non-goals
- breaking-change context

A new session should be able to read this and understand what the project is trying to do.

### `CHANGES.md`

An append-only journal for project-level context.

This is not a git log. It is where you record things git commits usually fail to preserve cleanly:

- architectural decisions
- scope changes
- revised plans
- documentation shifts
- handoff notes
- code changes that need project-level explanation

Format:

```txt
YYYY-MM-DD [type] description
```

Types:

- `decision`
- `plan`
- `doc`
- `scope`
- `code`
- `note`

## Installation

Clone this repo somewhere local:

```bash
git clone https://github.com/Silverfell/klaude.git
```

Move into the project where you want to install the harness:

```bash
cd /path/to/your/project
```

Run the setup script from the Klaude repo:

```bash
/path/to/klaude/setup.sh
```

That will copy:

- `CLAUDE.md`
- `.claude/commands/init.md`
- `.claude/commands/close.md`
- `.claude/commands/compresschanges.md`

Then start Claude Code and run:

```txt
/init
```

## Upgrading

To overwrite an existing installation with the latest defaults:

```bash
/path/to/klaude/upgrade.sh
```

The upgrade script also:

- overwrites the harness files with the latest versions
- converts legacy `CHANGES.md` lines from `YYYY-MM-DD: description` to `YYYY-MM-DD [note] description`
- adds the format hint to `CHANGES.md` if it is missing
- backs up the old `CHANGES.md` first

## Example workflow

Start session:

```txt
/init
```

Claude reads the briefing and recent changes, then confirms the session is ready.

Do the work.

End session:

```txt
/close
```

Claude records decision and scope changes, updates the briefing if needed, and leaves the project in a state that the next session can pick up cleanly.

If the journal gets too large:

```txt
/compresschanges
```

Claude compacts older history into monthly summaries while preserving high-value records verbatim.

## Design principles

Klaude is opinionated.

It assumes that better agent output comes from stricter process, not from pretending the model is magically dependable.

Core principles:

- read real files before making claims
- say "I don't know" when you do not know
- verify before reporting completion
- keep diffs minimal
- avoid speculative improvements unless asked
- preserve durable project context outside the model

## When not to use this

Do not use Klaude if:

- you want a fully autonomous agent stack
- you do not care about session continuity
- your projects are too trivial to justify written context
- you want hidden magic instead of explicit process
