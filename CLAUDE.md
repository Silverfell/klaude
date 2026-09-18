# CLAUDE.md

This repo is the source of Klawde, a session harness for Claude Code. There is no application code here. The files under `template/` are shipped artifacts: `setup.sh` and `upgrade.sh` copy them into user projects.

## Layout

- `template/CLAUDE.md`: the harness contract installed into target projects. It governs sessions in those projects, not in this repo.
- `template/klawde.md`, `template/close.md`: slash commands installed to `.claude/commands/` in target projects (as `/klawde`, `/close`). `/klawde` starts a session; `/close` ends it.
- `template/check-log.sh`: read-only integrity and schema-definition checker, installed beside the schema in either layout and shared by close and upgrade. Its temporary reference database is the only database it creates.
- `template/changes-schema.sql`: the schema of `changes.db`, the SQLite project log created in target projects by `/klawde`. Installed to `.claude/changes-schema.sql` (Claude) or `.agents/changes-schema.sql` (Codex). Its triggers are what make the log append-only and immutable and the `concerns` table's lifecycle one-way, so changing them changes the contract.
- `setup.sh`: first-time install, run from the target project directory.
- `upgrade.sh`: overwrites an existing install with the latest defaults and brings an existing `changes.db` to the shipped schema in place.
- `lib.sh`: functions shared by both scripts, sourced after each resolves its own directory.
- `tests/verify.sh`: regression suite for the scripts and templates; builds throwaway projects in a temp dir and runs the real scripts against them.
- `tests/session_eval.py`: opt-in live Codex conversations with assertions against disposable installed projects. See `tests/README.md`; model or runtime failures are failures, never simulated passes.
- `README.MD`: user-facing documentation.

## Rules

- Editing anything in `template/` changes what every user installs. Keep `README.MD` and both scripts consistent with template behavior.
- The entry-protocol command is named `/klawde` (not `/init`) to avoid colliding with Claude Code's built-in `/init`.
- This repo does not use BRIEFING.md or a changes.db itself; those are created in target projects by `/klawde`. `CHANGES.md` is the retired text log: `upgrade.sh` refuses a project that still has one without a `changes.db`, and the migration lives at commit 185c63a.
- Concerns are written only at `/close`, at most three, each with a `ref_serial` naming that session's log entry; the close retires open rows without one and never blocks on the user. The concern definition lives in the contract; the write rules, refusals and SQL forms live in `template/close.md`. A restatement of an older incomplete concern is maintenance, outside those write rules, and keeps the original's `area` and `ref_serial`. A change to any of this is verified with the `authoring`, `consent`, `restraint` and `restated` live scenarios.
- `BRIEFING.md` is the only authority on decisions; the log never is. The contract's Settled decisions rule and the entry protocol's tail comparison both treat a superseded entry as resolved history, and the `superseded` and `contradiction` live scenarios cover them; change them together.
- The harness requires the `sqlite3` CLI; both scripts check for it upfront.
- The log schema is versioned via `PRAGMA user_version`. `upgrade.sh` reads the shipped version from the schema and brings any older log to it by creating the `concerns` table where a pre-v3 log lacks it, restoring every missing or changed trigger and view from the shipped definitions, and setting the version, in one transaction. A schema change therefore only bumps the version and, if it adds a table, teaches that step to create it. The suite asserts that every earlier version upgrades to a schema identical to a fresh install.
- `upgrade.sh` selects what it repairs by what each difference is, so an unknown status can never reach a `DROP`. It refuses in preflight, before any file is written, a missing or changed table (only git still holds the rows) and a trigger the shipped schema does not define (a `RAISE(IGNORE)` trigger silences inserts). An unexpected table or view is reported and left alone. `/close` runs the read-only checker before its first write, stopping with nothing written on any error, and again after its last; it relays the result and never repairs the live schema itself. The suite pins that order in `template/close.md`.
- `upgrade.sh` overwrites the contract whole but keeps a removed Code craft section out. It recognizes one shape: klawde files beside the contract, a `## Deviations` line and no `### Code craft` heading. That is a recognition rule, not proof of intent, so the script reports either outcome whenever the section was absent. Renaming either heading in `template/CLAUDE.md` breaks the rule; the suite pins both and compares the result against an expectation built apart from the production strip.
- After editing `setup.sh`, `upgrade.sh`, `lib.sh` or `template/check-log.sh`, verify each with its own `bash -n` (the flag takes one script) and run `tests/verify.sh`; it must pass under `/bin/bash` 3.2 as well, and the suite covers that.
- The command files and the contract are rewritten for Codex by `rewrite_codex` in `lib.sh`, which rewrites only backticked `/klawde`, `/close`, and `.claude/commands/*.md` references and the bare schema and checker paths. Never name `CLAUDE.md` in a command file (Codex has `AGENTS.md`), and always backtick `/klawde`, `/close`, and `.claude/` paths, including inside code comments. The suite's Codex drift test greps the generated files for leftovers.
