# Klawde

Klawde is a lightweight harness for Claude Code (and Codex) that makes sessions more reliable.

It does four things:

- forces an explicit session start
- keeps a living project brief up to date
- leaves behind an append-only decision log for the next session
- compresses older change history when the journal gets too large

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
- an append-only project journal
- stricter rules around honesty, verification, and scope control
- a cheap way to reduce context drift between sessions

It is especially useful on projects where architecture, scope, and decision history matter more than just the final diff.

## What's included

| File | Purpose |
|------|---------|
| `template/CLAUDE.md` | Project rules, coding discipline, verification rules, and output contract |
| `template/klawde.md` | `/klawde` command: reads or creates session documents at session start |
| `template/close.md` | `/close` command: updates session records before ending work |
| `template/compresschanges.md` | `/compresschanges` command: compacts older `CHANGES.md` history into summaries |
| `setup.sh` | First-time setup: installs the harness for Claude Code, Codex, or both (prompts, or `--claude`/`--codex`/`--both`) |
| `upgrade.sh` | Upgrade: overwrites harness files with the latest defaults (Claude, Codex, or both), optionally backs them up, converts legacy `CHANGES.md` entries, and retires the legacy `/init` command |

## How it works

### `/klawde`

Run this at the start of every Claude Code session. (The command is named `/klawde` rather than `/init` to avoid colliding with Claude Code's built-in `/init`.)

It makes Claude Code:

1. check whether `BRIEFING.md` and `CHANGES.md` exist, and create them if missing
2. read `BRIEFING.md` completely
3. ask for the project's purpose and current scope if the brief is empty
4. read at least the last 30 lines of `CHANGES.md`
5. check that recent changes do not contradict the brief
6. confirm readiness, then stop

This forces the session to begin from actual project state instead of hand-waving.

### `/close`

Run this at the end of a session.

It makes Claude Code:

1. review the current `CHANGES.md` and `BRIEFING.md`
2. review what changed in the session
3. append typed journal entries for any unrecorded decisions, plans, docs, scope shifts, notes, or code that needs project-level explanation
4. update `BRIEFING.md` if purpose, scope, key decisions, non-goals, or breaking-change context changed, or if its fields are still empty
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

For example: `2026-05-12 [decision] Switched queue from Redis to Postgres SKIP LOCKED; one less service to operate`

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
- `.claude/commands/compresschanges.md`

For Codex, it writes the contract as `AGENTS.md` and installs the protocols as repo-level [skills](https://developers.openai.com/codex/skills), which travel with the project and are invoked as `$klawde`, `$close`, and `$compresschanges` (or picked from `/skills`):

- `AGENTS.md`
- `.agents/skills/klawde/SKILL.md`
- `.agents/skills/close/SKILL.md`
- `.agents/skills/compresschanges/SKILL.md`

Skills replace Codex custom prompts, which OpenAI has deprecated.

The `both` option installs both layouts at once: `CLAUDE.md` and `.claude/commands/` for Claude Code, plus `AGENTS.md` and `.agents/skills/` for Codex.

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

With no target flag, the script detects the existing install (`CLAUDE.md` means Claude, `AGENTS.md` means Codex, both present means a combined install) and offers it as the default; press Enter to accept.

It then asks whether to create `.bak` backups before overwriting. Answer `n` and no backup files are created. Use `--backup` or `--no-backup` to skip that prompt.

The upgrade script also:

- overwrites the harness files with the latest versions (Claude, Codex, or both layouts)
- removes the legacy `.claude/commands/init.md` (Claude installs only; the entry protocol is now `/klawde`)
- removes deprecated Codex prompts from earlier versions in `$CODEX_HOME/prompts/` (defaulting to `~/.codex/prompts/`)
- converts legacy `CHANGES.md` lines from `YYYY-MM-DD: description` to `YYYY-MM-DD [note] description`
- adds the format hint to `CHANGES.md` if it is missing
- backs up every file it overwrites or removes first, unless you decline backups

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

Claude records decision and scope changes, updates the briefing if needed, and leaves the project in a state that the next session can pick up cleanly.

If the journal gets too large:

```txt
/compresschanges
```

Claude compacts older history into monthly summaries while preserving high-value records verbatim.

## Design principles

Klawde is opinionated.

It assumes that better agent output comes from stricter process, not from pretending the model is magically dependable.

Core principles:

- read real files before making claims
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
