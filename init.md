# /init — Entry Protocol

Run this at the start of every session. Do not proceed with any task until complete.

## Steps

1. Check if `./BRIEFING.md` exists (list or stat). Check if `./CHANGES.md` exists.

2. If `BRIEFING.md` is missing, create it with:

```markdown
# Briefing

- Purpose:
- Current scope:
- Key decisions:
- Non-goals:
```

3. If `CHANGES.md` is missing, create it with:

```markdown
# Changes

Format: `YYYY-MM-DD [type] description` (max 200 chars). Types: decision, plan, doc, scope, code, note.

YYYY-MM-DD [note] Initialized.
```

(Use today's date.)

4. Read `BRIEFING.md` completely.

5. Read `CHANGES.md` (at least the last 30 lines).

6. Output exactly this, then stop:

```
OK. Ready.
BRIEFING.md: <one-sentence summary of current briefing>
CHANGES.md: <one-sentence summary of recent changes>
```

Do not proceed with any other task until this output is complete.
