# /close: Session Close Protocol

Run this at the end of a session to persist state for the next session. It is also safe to run mid-session as a checkpoint: recording early means a crash or context compaction cannot lose the session's record, and the review below re-anchors the work against the brief.

## Steps

1. Read the current `CHANGES.md` and `BRIEFING.md`. If either is missing, create it first using the formats in `.claude/commands/klawde.md`, then continue.

2. Review all work done in this session. In a long session, earlier work may have been summarized out of your context: run `git status` and `git diff` (plus `git log` for anything committed this session) to recover changes you no longer remember. For each unrecorded shift in decisions, plans, scope, documents, external context, or code needing project-level explanation:
   - Append a line at the bottom of `CHANGES.md`: `{today} [type] description` (one line, max 200 chars). Substitute `{today}` with today's ISO date before writing.
   - Types: `decision`, `plan`, `doc`, `scope`, `code`, `note`. For `decision`, name the rejected alternative when one exists (`X over Y; reason`).

   Three things do **not** go in the journal, however much the session produced of them. Verification evidence (test counts, measured distributions, clean-console confirmations) belongs in the COMPLIANCE `Verified:` line of your response — it expires as soon as the code changes. Parameter values that code, config or an asset file already owns — record why, never what. Session conduct: frustration, blame, and the blow-by-blow of your own corrections. Where a failure taught something durable, record the lesson and drop the incident.

   If this session superseded an earlier decision, do not append a contradicting one. Fold: write the new decision so it names what it replaced and why, then delete the superseded line. That is the only entry you may delete, and never one recording something the user asked to keep.

   If any of this session's work contradicts `Current scope`, `Non-goals`, or `Do-not-touch` in BRIEFING.md, flag the contradiction to the user before the closing block; do not silently record around it.

3. Review whether any of the following changed during this session:
   - Project purpose or scope
   - Key architectural or design decisions
   - Non-goals or explicit exclusions
   - Breaking changes (note reason and impact)

   If any of the above changed, update `BRIEFING.md` accordingly. An empty field in `BRIEFING.md` (e.g., Purpose) counts as changed: draft it from what this session revealed. Keep it concise but sufficient to brief a new contributor; match the example brief in `.claude/commands/klawde.md`.

   Regardless of the list above, always maintain the state fields. BRIEFING.md holds current state, never history:
   - `Current focus`: **replace** it, never append a second one. There is exactly one, present tense. A brief that has accumulated several dated `Current focus` bullets has stopped being a brief.
   - `Next steps`: rewrite every close; clear it if nothing is pending. Stale next steps mislead the following session.
   - `Open questions`: add new ones, remove answered ones.
   - `Environment quirks`: promote durable `[note]` context that journal compression would otherwise lose (flaky sandboxes, renamed keys, local oddities); prune quirks that no longer hold; keep the field to five lines or fewer.
   - `Do-not-touch`: change only on explicit user instruction.

   A field is trimmed by removing what is no longer true, never by dropping live state to hit a number. A large project legitimately carries more open questions than a small one. What does not belong at any size: a bullet that narrates a past session rather than stating current state (`Styling pass`, `Auth refactor`, `Cleanup pass`). That is history — move it to CHANGES.md or cut it.

4. Write only the file(s) you changed. If neither changed, do not write. Do not stage or commit. Leave changes dirty so the user controls when they enter git history.

5. Output exactly this format, then stop:

```
Session closed.
CHANGES.md: [number] new entries appended.
BRIEFING.md: [updated | unchanged].
```

Do not skip this protocol. If nothing recordable changed, say so and confirm both files are unchanged.
