# CLAUDE.md

This repo is the source of Klawde, a session harness for Claude Code. There is no application code here. The files under `template/` are shipped artifacts: `setup.sh` and `upgrade.sh` copy them into user projects.

## Layout

- `template/CLAUDE.md`: the harness contract installed into target projects. It governs sessions in those projects, not in this repo.
- `template/klawde.md`, `template/close.md`, `template/compresschanges.md`: slash commands installed to `.claude/commands/` in target projects (as `/klawde`, `/close`, `/compresschanges`).
- `setup.sh`: first-time install, run from the target project directory.
- `upgrade.sh`: overwrites an existing install with the latest defaults, migrates legacy `CHANGES.md` entries, and retires the legacy `/init` command.
- `README.MD`: user-facing documentation.

## Rules

- Editing anything in `template/` changes what every user installs. Keep `README.MD` and both scripts consistent with template behavior.
- The entry-protocol command is named `/klawde` (not `/init`) to avoid colliding with Claude Code's built-in `/init`.
- This repo does not use BRIEFING.md or CHANGES.md itself; those files are created in target projects by `/klawde`.
- After editing `setup.sh` or `upgrade.sh`, verify with `bash -n`.
