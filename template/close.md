# /close: Session Close Protocol

Run this at the end of a session to persist state for the next session. It is also safe to run mid-session as a checkpoint: recording early means a crash or context compaction cannot lose the session's record, and the review below re-anchors the work against the brief.

## Steps

1. Read the current `CHANGES.md` and `BRIEFING.md`. If either is missing, create it first using the formats in `.claude/commands/klawde.md`, then continue.

2. Review all work done in this session. In a long session, earlier work may have been summarized out of your context: run `git status` and `git diff` (plus `git log` for anything committed this session) to recover changes you no longer remember. For each unrecorded shift in decisions, plans, scope, documents, external context, or code needing project-level explanation:
   - Append a line at the bottom of `CHANGES.md`: `{today} [type] description` (one line, max 200 chars). Substitute `{today}` with today's ISO date before writing.
   - Types: `decision`, `plan`, `doc`, `scope`, `code`, `note`. For `decision`, name the rejected alternative when one exists (`X over Y; reason`).

   If any of this session's work contradicts `Current scope`, `Non-goals`, or `Do-not-touch` in BRIEFING.md, flag the contradiction to the user before the closing block; do not silently record around it.

3. Review whether any of the following changed during this session:
   - Project purpose or scope
   - Key architectural or design decisions
   - Non-goals or explicit exclusions
   - Breaking changes (note reason and impact)

   If any of the above changed, update `BRIEFING.md` accordingly. An empty field in `BRIEFING.md` (e.g., Purpose) counts as changed: draft it from what this session revealed. Keep it concise but sufficient to brief a new contributor; match the example brief in `.claude/commands/klawde.md`.

   Regardless of the list above, always maintain the state fields:
   - `Current focus` and `Next steps`: refresh both every close; clear them if nothing is pending. Stale next steps mislead the following session.
   - `Open questions`: add new ones, remove answered ones.
   - `Environment quirks`: promote durable `[note]` context that journal compression would otherwise lose (flaky sandboxes, renamed keys, local oddities); prune quirks that no longer hold; keep the field to five lines or fewer.
   - `Do-not-touch`: change only on explicit user instruction.

4. Write only the file(s) you changed. If neither changed, do not write. Do not stage or commit. Leave changes dirty so the user controls when they enter git history.

5. Output exactly this format, then stop:

```
Session closed.
CHANGES.md: [number] new entries appended.
BRIEFING.md: [updated | unchanged].
```

Do not skip this protocol. If nothing recordable changed, say so and confirm both files are unchanged.
