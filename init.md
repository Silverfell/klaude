# /init — Entry Protocol

Run this at the start of every session. Do not proceed with any task until complete.

## Steps

1. Check existence with `ls BRIEFING.md CHANGES.md 2>/dev/null`. Note which printed and which did not.

2. If `BRIEFING.md` is missing, create it with:

```markdown
# Briefing

- Purpose:
- Current scope:
- Key decisions:
- Non-goals:
```

3. If `CHANGES.md` is missing, create it. Substitute `{today}` with today's ISO date (e.g. 2026-05-21) before writing:

```markdown
# Changes

Format: `YYYY-MM-DD [type] description` (max 200 chars). Types: decision, plan, doc, scope, code, note.

{today} [note] Initialized.
```

4. Read `BRIEFING.md` completely.

5. Read `CHANGES.md` (at least the last 30 lines).

6. Compare BRIEFING.md's stated purpose and current scope against the last 30 lines of CHANGES.md. If recent entries contradict the brief (e.g., scope claims X, recent work is on Y), output the contradiction, recommend the user reconcile BRIEFING.md or run /close first, and stop. Do not output the "OK. Ready." block.

7. If no drift, output exactly this, then stop:

```
OK. Ready.
BRIEFING.md: <one-sentence summary of current briefing>
CHANGES.md: <one-sentence summary of recent changes>
```

Do not proceed with any other task until this output is complete.
