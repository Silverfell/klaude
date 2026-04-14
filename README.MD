# Klaude

A lightweight harness for AI-assisted coding sessions, built on hard-earned lessons from working with coding agents.

## Philosophy

The core rules enforce honesty and discipline. The coding guidelines draw from personal experience and established sources (notably Andrej Karpathy's "Think before you code").

## What's Included

| File | Purpose |
|------|---------|
| `CLAUDE.md` | Project rules, coding guidelines, and decision protocols |
| `init.md` | `/init` command: reads or creates session documents at session start |
| `close.md` | `/close` command: ensures documents are updated before session end |
| `setup.sh` | First-time setup: copies files into your project |
| `upgrade.sh` | Upgrade: overwrites harness files with latest defaults |

## Session Documents

- **BRIEFING.md**: A living project brief that the agent keeps current.
- **CHANGES.md**: An append-only project journal (decisions, plans, scope, not just code).

## Getting Started

1. Clone this repo.
2. `cd` into your target project directory.
3. Run the setup script:
   ```bash
   /path/to/klawde/setup.sh
   ```
4. Start a Claude Code session and run `/init`.