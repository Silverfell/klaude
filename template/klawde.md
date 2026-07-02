# /klawde: Entry Protocol

Run this at the start of every session. Do not proceed with any task until complete.

This command starts the framework in full mode, with the Code craft module active. To start without the programming rules, the user runs `/klaude` instead, which follows these same steps in lean mode.

## Steps

1. Check existence with `ls BRIEFING.md CHANGES.md 2>/dev/null`. Note which printed and which did not. Also run `git status --porcelain 2>/dev/null | head -20` and note any pre-existing uncommitted changes. Dirty state is informational only, never a reason to block: it may be unfinished work from a prior session.

2. If `BRIEFING.md` is missing, create it with:

```markdown
# Briefing

- Purpose:
- Current scope:
- Key decisions:
- Non-goals:
- Breaking-change context:
- Current focus:
- Next steps:
- Open questions:
- Do-not-touch:
- Environment quirks:
```

   When filling fields (step 6 or later), match this shape: short, factual, decision-oriented.

```markdown
# Briefing

- Purpose: CLI tool that syncs Shopify orders into the local ERP.
- Current scope: order import, retry queue, dry-run mode. No refunds yet.
- Key decisions: Postgres SKIP LOCKED over Redis (2026-05-12); single binary, no daemon.
- Non-goals: multi-tenant support, real-time sync.
- Breaking-change context: v0.4 renamed config key `shop_url` to `store_url`.
- Current focus: retry queue hardening.
- Next steps: add backoff cap; test double-delivery on restart.
- Open questions: should dry-run write an audit file?
- Do-not-touch: `legacy/importer.pl` (production cron depends on its exact output).
- Environment quirks: Shopify sandbox throttles hard after ~50 req/min.
```

3. If `CHANGES.md` is missing, create it. Substitute `{today}` with today's ISO date (e.g. 2026-05-21) before writing:

```markdown
# Changes

Format: `YYYY-MM-DD [type] description` (max 200 chars). Types: decision, plan, doc, scope, code, note.

{today} [note] Initialized.
```

4. If `BRIEFING.md` exists but is missing any of the field lines from the step 2 template (an install from an earlier version), append the missing lines empty, without altering existing content.

5. Read `BRIEFING.md` completely.

6. If Purpose or Current scope in `BRIEFING.md` is empty, ask the user: "What is this project's purpose and current scope?" Write the answer into `BRIEFING.md` before continuing.

7. Read `CHANGES.md` (at least the last 30 lines). If the file exceeds ~200 lines (`wc -l < CHANGES.md`), suggest running `/compresschanges` after this protocol completes. Suggest only; do not run it.

8. Compare BRIEFING.md's stated purpose and current scope against the last 30 lines of CHANGES.md. If recent changes appear to contradict the brief (work on something the scope excludes, or a `[scope]` or `[decision]` entry the brief does not reflect), output the specific contradiction, recommend the user reconcile BRIEFING.md or run `/close` first, and stop. Do not output the "OK. Ready." block.

   Separately, check `Current focus` and `Next steps` against those same entries. They are suggestions left by the previous session, not commands: if the journal shows work has already moved past them, this is staleness, not a contradiction. Do not stop for it; note it on the `Focus` line of the output and recommend refreshing them via `/close`.

9. If no drift, output exactly this format, then stop:

```
OK. Ready.
BRIEFING.md: <one-sentence summary of current briefing>
CHANGES.md: <one-sentence summary of recent changes>
Focus: <Current focus and Next steps | unset | stale: reason>
Dirty: <uncommitted files found in step 1 | clean | not a git repo>
Mode: <full (Code craft active) | lean (Code craft inactive), per the command that invoked this protocol>
```

   If the uncommitted changes look related to `Current focus` or `Next steps` (likely unfinished work), add one line after the block saying so.

Do not proceed with any other task until this output is complete.
