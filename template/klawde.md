# /klawde: Entry Protocol

Run at session start. Complete this protocol before any other task, then stop. The project contract's Project Records, Writing SQL safely, and Briefing maintenance sections define the shared rules.

## Steps

1. Run `ls BRIEFING.md changes.db 2>/dev/null` and note which files exist. Run `command -v sqlite3`; if missing, stop and request installation of the SQLite CLI. Run `git rev-parse --is-inside-work-tree >/dev/null 2>&1 && git status --porcelain`: distinguish a non-repository from a clean one, and note pre-existing changes. Dirty state never blocks entry.

2. If `BRIEFING.md` is missing, create the empty form below. The example shows the required concise shape; its project details are examples, not defaults.

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

   Preserve the user's ownership of `Open questions` and `Do-not-touch` as defined in Briefing maintenance.

3. If `changes.db` is missing, first confirm `.claude/changes-schema.sql` exists. If absent, stop and recommend `upgrade.sh` from the klawde checkout. Never invent the schema or run an insert against an uninitialized database. Create it and its first entry:

```sh
sqlite3 -bail changes.db < .claude/changes-schema.sql
sqlite3 -bail changes.db <<'KLAWDE_SQL'
INSERT INTO entries (type, area, description) VALUES ('doc','-','Initialized.');
KLAWDE_SQL
```

   Seed `areas` from the actual names in the brief's `Areas` line, removing Markdown formatting and list punctuation. An empty field seeds nothing; do not insert the example names unless they are the project's areas. For the example brief:

```sh
sqlite3 -bail changes.db <<'KLAWDE_SQL'
INSERT OR IGNORE INTO areas VALUES ('import'),('retry'),('cli'),('config');
KLAWDE_SQL
```

   Commit the database like any other project file; never add it to `.gitignore`.

4. Insert any missing template fields empty in their template positions, preserving existing content. Leave a missing `Areas` field empty for `/close` to fill.

5. Read `BRIEFING.md` completely.

6. If Purpose or Current scope is empty, ask: "What is this project's purpose and current scope?" Wait for the answer and write it before continuing. An answer already supplied by the user this session needs no second ask.

7. Read exactly the last five log entries and open-concern counts:

```sh
sqlite3 -readonly changes.db "SELECT line FROM log_lines ORDER BY serial DESC LIMIT 5;"
sqlite3 -readonly changes.db "SELECT area, count(*) FROM concerns WHERE resolved IS NULL GROUP BY area ORDER BY area;"
sqlite3 -readonly changes.db "SELECT count(*) FROM concerns WHERE resolved IS NULL;"
```

   These are the entire session-start database reads. No older-history skim, concern texts, or triage. Paste the measured total into the output; never tally it yourself. If concerns are absent on a pre-v3 schema, report `schema pre-v3 — run upgrade.sh` and continue without altering the schema. A missing table on a newer schema is damage, not an older version: report it and stop. Diagnose a failed query instead of treating it as an empty result.

8. Compare the five entries against the brief. A purpose/scope contradiction or an unreflected `[scope]` or `[decision]` change stops entry: name the disagreement, recommend reconciling the brief or running `/close`, and omit "OK. Ready." The log never wins the disagreement. Work already beyond `Current focus` or `Next steps` is merely stale focus: note it and recommend `/close`, but continue.

   Measure the brief:

```sh
awk 'BEGIN { printf "Shape:" } /^#/ && f != "" && f != "Trailing" { printf "%s %s %d", s, f, n; s = ","; f = "Trailing"; n = 0 } /^[-*][[:space:]]+[^:]+:/ && f != "Trailing" { if (f != "") { printf "%s %s %d", s, f, n; s = "," } f = $0; sub(/:.*/, "", f); sub(/^[-*][[:space:]]+/, "", f); sub(/[[:space:]]+$/, "", f); n = 0 } NF { n++ } END { if (f != "") printf "%s %s %d", s, f, n; print "" }' BRIEFING.md
```

   Each `Field N` gives its nonblank line count. Expect the eleven template names once each, normally all 1. A duplicate maintained field, count above 1, or history disguised as one line is a violation: report fields and counts, recommend `/close`, and stop without the Ready block. Do not repair it here; closing preserves unrecorded history before reshaping.

   User fields over one line, foreign fields, and `Trailing` content are reported on the `BRIEFING.md` line, not repaired and not blocking. Interpret bullets belonging to user fields as the contract specifies. Text after the last field counts into it unless a heading makes it `Trailing`.

9. If no check stopped entry, output this format, then stop:

```
OK. Ready.
BRIEFING.md: <one-sentence summary of current briefing>
changes.db: <one-sentence summary of recent changes>
Focus: <Current focus and Next steps | unset | stale: reason>
Concerns: <N open: <area> N, <area> N | none | schema pre-v3 — run upgrade.sh>
Dirty: <uncommitted files found in step 1 | clean | not a git repo>
```

   After the block, add a line if dirty files appear to be unfinished focus/next-step work. Add a line if `Open questions` contains a finding or fact instead of a question; only the user can authorize its removal. Empty is valid.
