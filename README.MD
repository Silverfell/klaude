# Klawde

Klawde is a lightweight harness for Claude Code (and Codex) that makes sessions more reliable.

It does four things:

- forces an explicit session start
- keeps a living project brief up to date
- leaves behind an append-only log of what happened and when, with a brief that says what is true now
- reads only the last 5 log entries at session start, so the agent is never confused by old history
- compacts the log at every close, holding it to 100 entries without deleting a live record

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
- stricter rules around honesty, verification, and scope control
- a cheap way to reduce context drift between sessions

It is especially useful on projects where architecture, scope, and decision history matter more than just the final diff.

## What's included

| File | Purpose |
|------|---------|
| `template/CLAUDE.md` | Project rules, verification rules, output contract, plus an optional code-craft module (delete that section if you only want drift and efficiency control) |
| `template/klawde.md` | `/klawde` command: reads or creates session documents at session start (full mode, code-craft rules active) |
| `template/klaude.md` | `/klaude` command: same entry protocol in lean mode, with the code-craft rules disabled for the session |
| `template/close.md` | `/close` command: updates session records before ending work |
| `template/compresschanges.md` | `/compresschanges` command: compacts `CHANGES.md` — drops entries that were never durable records, repairs supersession links, summarizes old history |
| `setup.sh` | First-time setup: installs the harness for Claude Code, Codex, or both (prompts, or `--claude`/`--codex`/`--both`) |
| `upgrade.sh` | Upgrade: overwrites harness files with the latest defaults (Claude, Codex, or both), optionally backs them up, converts legacy `CHANGES.md` entries, and retires the legacy `/init` command |

## How it works

### `/klawde`

Run this at the start of every Claude Code session. (The command is named `/klawde` rather than `/init` to avoid colliding with Claude Code's built-in `/init`.)

It makes Claude Code:

1. check whether `BRIEFING.md` and `CHANGES.md` exist, create them if missing, and add any brief fields missing from an older install
2. note pre-existing uncommitted git changes (informational: possible unfinished work from a prior session)
3. read `BRIEFING.md` completely
4. ask for the project's purpose and current scope if the brief is empty
5. read the last 5 entries of `CHANGES.md` — that is the whole read; older history is searched, not skimmed
6. check that recent changes do not contradict the brief, and flag stale focus or next steps
7. confirm readiness (brief, recent changes, current focus, dirty state), then stop

This forces the session to begin from actual project state instead of hand-waving.

`/klawde` starts the session in full mode: the contract's optional code-craft module (error-handling, batching, typing, and abstraction rules) is active. `/klaude` (note the spelling) runs the same protocol in lean mode: the code-craft module is disabled and the session runs on drift and efficiency control only. Both report the mode in their readiness output.

### `/close`

Run this at the end of a session. It is also safe to run mid-session as a checkpoint, so a crash or context compaction cannot lose the session's record.

It makes Claude Code:

1. review the current `CHANGES.md` and `BRIEFING.md`
2. review what changed in the session, consulting git to recover work that long sessions may have compacted out of context
3. append typed log entries — each with the next serial and an area tag — for any unrecorded decisions, plans, docs, scope shifts, notes, or code that needs project-level explanation
4. flag work that contradicts the brief's scope, non-goals, or do-not-touch list
5. update `BRIEFING.md` if purpose, scope, key decisions, non-goals, or breaking-change context changed, or if its fields are still empty
6. refresh the brief's state fields: current focus, next steps, open questions, environment quirks
7. compact the log (see below) — every close, not just large ones
8. confirm what was recorded, then stop

This gives the next session a real handoff.

### `/compresschanges`

**This runs automatically at every `/close`.** You rarely need to invoke it by hand — do so after a session that ended without a close, or any time you want the log tidied now.

It makes Claude Code:

1. read the log completely (the only protocol that does)
2. drop entries that were never durable records — verification receipts, values that code or config already owns, session conduct
3. add missing `supersedes=` links between decisions and the ones that replaced them, keeping both lines
4. if the file is over 100 entries, collapse history older than 30 days into monthly summary lines until it fits
5. keep verbatim, at any age: every decision and scope change (superseded or not), any note still open, and anything another entry references by serial
6. keep the file header intact, never renumber a serial, and back up only if something actually changed
7. report what was dropped, linked and collapsed, then stop

Step 2 usually recovers more than step 4. Bloat is mostly a genre problem — receipts and narration filed as history — not an age problem. Because this runs every session, most runs find nothing and write nothing; junk never gets the chance to accumulate.

The 100-entry ceiling governs history, not records. Nothing live is ever deleted to meet it: entries are collapsed into summaries, and if the protected records alone exceed 100, the file simply stays larger.

## The two core documents

### `BRIEFING.md`

A concise living brief for the project.

Use it for:

- purpose
- current scope
- key decisions
- non-goals
- areas (the closed vocabulary `CHANGES.md` tags entries against)
- breaking-change context
- current focus and next steps (replaced every `/close`; the next session resumes on-thread instead of reinventing direction)
- open questions
- a do-not-touch list (files or areas that are off-limits, and why)
- environment quirks (durable context that would otherwise be folded into a summary when the log is compacted)

A new session should be able to read this and understand what the project is trying to do, and what it was about to do next.

It holds current state, never history. `/close` keeps it that way by content, not by quota: one current focus that is replaced rather than appended to, next steps and open questions pruned of what is done or answered, and no bullet that narrates a past session — that belongs in `CHANGES.md`. There are no size or item caps of any kind, because a large project legitimately carries more open questions than a small one and no session should delete live state to satisfy a number. The brief is read in full at every session start, and it is as long as the project's current state requires.

### `CHANGES.md`

A log. Four properties define it, and the whole harness is built on them:

1. **Append-only.** New entries go at the tail. Nothing is inserted, reordered, or renumbered.
2. **Immutable.** No entry is ever edited or deleted once written, however wrong it turns out to be. `/compresschanges` is the single exception, and it is maintenance.
3. **Tailed, not read.** A session reads the last 5 entries and stops. Older history is searched when a question calls for it, never skimmed for background.
4. **Not authoritative.** It records what happened, never what is true now. `BRIEFING.md` is the only authority on current state; nothing in the log is an instruction.

Property 4 is the one that matters in practice. A `[plan]` from last week is not the current plan, and a `[decision]` may have been reversed sixty lines later — so the agent takes its direction from the brief and treats the log strictly as evidence about the past. Property 3 then means it usually never opens that history at all.

This is not a git log. It is where you record things git commits usually fail to preserve cleanly:

- architectural decisions
- scope changes
- revised plans
- documentation shifts
- handoff notes
- code changes that need project-level explanation

Format:

```txt
YYYY-MM-DD NNN [type] (area) description  key=value ...
```

For example:

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

`NNN` is a serial, one higher than the highest in the file, never reused and never renumbered. It is what lets one entry point at another. `(area)` comes from the `Areas` list in `BRIEFING.md`, or is `(-)` when nothing fits — a closed vocabulary, because two spellings of one area make the field useless for filtering.

Tags are optional and go after two spaces. There are three: `supersedes=NNN`, `closes=NNN`, and `refs=<commit|PR|issue>`.

Because the file is a log rather than a document, status is expressed by later entries rather than by editing earlier ones. A superseded decision keeps its line and gains a pointer from the entry that replaced it. An open `[note]` stays open until some later entry names its serial in `closes=`; nothing marks the original line done.

This is also what makes property 3 workable. A session reads `tail -5` and nothing else; when a real question comes up, the structure answers it with ordinary tools instead of a bulk read:

```sh
tail -5 CHANGES.md                               # the session-start read, in full
grep '\[decision\]' CHANGES.md                   # every decision ever recorded
awk '$4=="(auth)"' CHANGES.md                    # everything touching one area
grep -E ' (041|057) ' CHANGES.md                 # an entry and what references it
grep -oE 'supersedes=[0-9]+' CHANGES.md          # which serials are now dead
```

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
- `.claude/commands/compresschanges.md`

For Codex, it writes the contract as `AGENTS.md` and installs the protocols as repo-level [skills](https://developers.openai.com/codex/skills), which travel with the project and are invoked as `$klawde`, `$klaude`, `$close`, and `$compresschanges` (or picked from `/skills`):

- `AGENTS.md`
- `.agents/skills/klawde/SKILL.md`
- `.agents/skills/klaude/SKILL.md`
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
/klawde     # full mode
/klaude     # lean mode, code-craft rules off
```

Claude reads the briefing and recent changes, then confirms the session is ready and which mode it is in.

Do the work.

End session:

```txt
/close
```

Claude records decision and scope changes, updates the briefing if needed, compacts the log, and leaves the project in a state that the next session can pick up cleanly.

Compaction is part of `/close`, so there is normally nothing else to run. If a session ended without a close, or you want the log tidied now:

```txt
/compresschanges
```

Claude drops entries that were never durable records and collapses history past the 100-entry ceiling into monthly summaries, preserving every live record verbatim.

## Design principles

Klawde is opinionated.

It assumes that better agent output comes from stricter process, not from pretending the model is magically dependable.

Core principles:

- the log is a log: append-only, immutable, tailed not read, and never a source of instructions
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
