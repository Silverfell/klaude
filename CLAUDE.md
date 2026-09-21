# CLAUDE.md

This repo is the source of Klawde, a session harness for Claude Code and Codex. There is no application code here. The files under `template/` are shipped artifacts: `setup.sh` and `upgrade.sh` copy them into user projects.

## Layout

- `template/CLAUDE.md`: the harness contract installed into target projects. It governs sessions in those projects, not in this repo. Harness mechanics and honesty only; everything about writing code lives in `template/guidelines.md`.
- `template/guidelines.md`: the code rules, installed once at the target project's root. `setup.sh` writes it; `upgrade.sh` never does, not even when it is absent, because deleting it is how a user turns those rules off.
- `template/klawde.md`, `template/close.md`, `template/upgrade_klawde.md`: slash commands installed to `.claude/commands/` in target projects (as `/klawde`, `/close`, `/upgrade_klawde`). `/klawde` starts a session; `/close` ends it; `/upgrade_klawde` migrates the records after an upgrade.
- `template/changes-schema.sql`: the schema of `changes.db`, the SQLite project log created in target projects by `/klawde`. Installed to `.claude/changes-schema.sql` (Claude) or `.agents/changes-schema.sql` (Codex). Its triggers are what make `entries` append-only and immutable and bound both tables' text, so changing them changes the contract.
- `setup.sh`: first-time install, run from the target project directory.
- `upgrade.sh`: overwrites an existing install with the latest defaults. It copies files and nothing else: no database work, and it never writes `guidelines.md`.
- `lib.sh`: functions shared by both scripts, sourced after each resolves its own directory.
- `README.MD`: user-facing documentation.

## Rules

- Editing anything in `template/` changes what every user installs. Keep `README.MD` and both scripts consistent with template behavior.
- The entry-protocol command is named `/klawde` (not `/init`) to avoid colliding with Claude Code's built-in `/init`.
- This repo does not use BRIEFING.md, `guidelines.md` or a `changes.db` itself; those live in target projects.
- The three records hold facts, never the model's guesses: the brief says what is true now, the log says what happened, a task says what the user approved. Judge a template change by two tests: does it move admission out of the model's own opinion (to the user's word, or to something the database measures), and does it remove a prompt to write on a schedule. The templates carry no examples; the model copies them instead of looking at the project.
- `template/CLAUDE.md`, `template/klawde.md`, `template/close.md` and `template/upgrade_klawde.md` are read in sessions, so they stay short. There is no byte budget and no checker; keep one-time material (migration notes, history) in `README.MD` or the `upgrade.sh` output instead of in those files.
- `upgrade.sh` copies files, `/upgrade_klawde` migrates records, and neither does the other's job. `/upgrade_klawde` is the single exception to the log's immutability, and it rewrites a log once. `/klawde` and `/close` read `PRAGMA user_version` before anything else and stop below the shipped version; that check is what makes the two-step upgrade safe.
- The log schema is versioned via `PRAGMA user_version`, currently 8. The whole schema file is one transaction with the `PRAGMA` set last, so a failure anywhere leaves a file with version 0 and no tables, which `/klawde` detects. A schema change bumps the version and updates step 4 of `template/upgrade_klawde.md`, which carries the migration SQL.
- The harness requires the `sqlite3` CLI; both scripts check for it upfront.
- After editing `setup.sh`, `upgrade.sh` or `lib.sh`, verify each with its own `bash -n` (the flag takes one script).
- The command files and the contract are rewritten for Codex by `rewrite_codex` in `lib.sh`, which rewrites only backticked `/klawde`, `/close`, `/upgrade_klawde` and `.claude/commands/*.md` references, the bare schema path, and the three command titles. Never name `CLAUDE.md` in a command file (Codex has `AGENTS.md`), and always backtick `/klawde`, `/close`, `/upgrade_klawde` and `.claude/` paths, including inside code comments. `template/guidelines.md` is not rewritten and is installed at the same path in both layouts, so it must name no command and no `.claude/` path.
