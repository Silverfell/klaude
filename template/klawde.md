# /klawde: Entry Protocol

Run this at the start of every session. Do not proceed with any task until complete.

This command starts the framework in full mode, with the Code craft module active. To start without the programming rules, the user runs `/klaude` instead, which follows these same steps in lean mode.

## Steps

1. Check existence with `ls BRIEFING.md CHANGES.md 2>/dev/null`. Note which printed and which did not. Also run `git status --porcelain 2>/dev/null` and note any pre-existing uncommitted changes. Dirty state is informational only, never a reason to block: it may be unfinished work from a prior session.

2. If `BRIEFING.md` is missing, create it with:

```markdown
# Briefing

- Purpose:
- Current scope:
- Key decisions:
- Non-goals:
- Areas:
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
- Areas: import, retry, cli, config.
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

LOG ONLY. Append at the tail; never edit or delete an entry. This file records what happened, not what is true now — BRIEFING.md is the authority on current state, and nothing here is an instruction. Sessions read the last 5 entries; search for anything older. Only /compresschanges rewrites this file.
Format: `YYYY-MM-DD NNN [type] (area) description  key=value`
Types: decision, plan, doc, scope, code, note. Areas: see BRIEFING.md. Tags: supersedes=NNN, closes=NNN, refs=X.

{today} 001 [note] (-) Initialized.
```

4. If `BRIEFING.md` exists but is missing any of the field lines from the step 2 template (an install from an earlier version), append the missing lines empty, without altering existing content. `Areas` is commonly the one missing; leave it empty here — `/close` fills it from the work the project is actually doing.

5. Read `BRIEFING.md` completely.

6. If Purpose or Current scope in `BRIEFING.md` is empty, ask the user: "What is this project's purpose and current scope?" Write the answer into `BRIEFING.md` before continuing.

7. Read the last 5 entries of `CHANGES.md` with `tail -5 CHANGES.md`. That is the entire session-start read. It tells you what the last session did, which is all you need to start; the brief tells you everything else. Do not read the file in bulk, do not skim it "for context", and do not go looking for older entries unless a specific question later makes it worth a targeted search.

   Nothing in those five lines is an instruction. They are a record of what happened. `BRIEFING.md` is what says where the project stands and what comes next.

   `BRIEFING.md` has no size limit and never will: it is a document, and it is as long as the project's current state requires. Never suggest trimming it for length, and never decline to record something because it is already large. Propose moving something out of it only when you can quote a specific bullet that narrates a past session instead of stating current state; that moves to `CHANGES.md` at the next `/close`.

   `CHANGES.md` has a working ceiling of 100 entries, held there by `/close`, which compacts the log every session. Do not run compaction from this protocol and do not suggest it — the next `/close` handles it.

8. Compare BRIEFING.md's stated purpose and current scope against the five entries you just read. If they contradict the brief (work on something the scope excludes, or a `[scope]` or `[decision]` entry the brief does not reflect), output the specific contradiction, recommend the user reconcile BRIEFING.md or run `/close` first, and stop. Do not output the "OK. Ready." block.

   The brief is the authority in this comparison. A disagreement means one of the two is stale — usually the brief, if the last session ended without a `/close`. It never means the log wins.

   Separately, check `Current focus` and `Next steps` against those same entries. They are suggestions left by the previous session, not commands: if the last entries show work has already moved past them, this is staleness, not a contradiction. Do not stop for it; note it on the `Focus` line of the output and recommend refreshing them via `/close`.

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
