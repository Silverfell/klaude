# CLAUDE.md

This repo is the source of Klawde, a session harness for Claude Code. There is no application code here. The files under `template/` are shipped artifacts: `setup.sh` and `upgrade.sh` copy them into user projects.

## Layout

- `template/CLAUDE.md`: the harness contract installed into target projects. It governs sessions in those projects, not in this repo.
- `template/klawde.md`, `template/klaude.md`, `template/close.md`: slash commands installed to `.claude/commands/` in target projects (as `/klawde`, `/klaude`, `/close`). `/klawde` starts a session in full mode (Code craft module active); `/klaude` is the lean variant that disables it.
- `template/changes-schema.sql`: the schema of `changes.db`, the SQLite project log created in target projects by `/klawde`. Installed to `.claude/changes-schema.sql` (Claude) or `.agents/changes-schema.sql` (Codex). Its triggers are what make the log append-only and immutable, so changing them changes the contract.
- `setup.sh`: first-time install, run from the target project directory.
- `upgrade.sh`: overwrites an existing install with the latest defaults, migrates a legacy text `CHANGES.md` into `changes.db`, upgrades an existing `changes.db` schema in place, and retires the legacy `/init` and `/compresschanges` commands.
- `README.MD`: user-facing documentation.

## Rules

- Editing anything in `template/` changes what every user installs. Keep `README.MD` and both scripts consistent with template behavior.
- The entry-protocol command is named `/klawde` (not `/init`) to avoid colliding with Claude Code's built-in `/init`.
- This repo does not use BRIEFING.md or a changes.db itself; those are created in target projects by `/klawde`. `CHANGES.md` is the retired text log the upgrade path migrates from — it survives only in `upgrade.sh`'s migration code and in the docs describing it.
- The harness requires the `sqlite3` CLI; both scripts check for it upfront.
- The log schema is versioned via `PRAGMA user_version`. Any schema change bumps it, adds a matching in-place migration to `upgrade.sh`, and updates the trigger count in `template/close.md` and `README.MD`.
- After editing `setup.sh` or `upgrade.sh`, verify with `bash -n`.
