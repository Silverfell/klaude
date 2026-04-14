# /close — Session Close Protocol

Run this at the end of a session to persist state for the next session.

## Steps

1. Read the current `CHANGES.md` and `BRIEFING.md`.

2. Review all work done in this session. For each unrecorded shift in decisions, plans, scope, documents, external context, or code needing project-level explanation:
   - Append a line to `CHANGES.md`: `YYYY-MM-DD [type] description` (one line, max 200 chars)
   - Types: `decision`, `plan`, `doc`, `scope`, `code`, `note`

3. Review whether any of the following changed during this session:
   - Project purpose or scope
   - Key architectural or design decisions
   - Non-goals or explicit exclusions
   - Breaking changes (note reason and impact)

   If any of the above changed, update `BRIEFING.md` accordingly. Keep it concise but sufficient to brief a new contributor.

4. Write both files.

5. Output exactly this, then stop:

```
Session closed.
CHANGES.md: [number] new entries appended.
BRIEFING.md: [updated | unchanged].
```

Do not skip this protocol. If nothing recordable changed, say so and confirm both files are unchanged.
