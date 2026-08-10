# /close: Session Close Protocol

Run this at the end of a session to persist state for the next session. It is also safe to run mid-session as a checkpoint: recording early means a crash or context compaction cannot lose the session's record, and the review below re-anchors the work against the brief.

## Steps

1. Read the current `CHANGES.md` and `BRIEFING.md`. If either is missing, create it first using the formats in `.claude/commands/klawde.md`, then continue.

   This protocol reads the log in full, unlike a session start, which reads only the last five entries. That is not an inconsistency: compaction in step 4 cannot be done from a tail. Reading it here is maintenance, and the entries you pass over are still history — nothing in them is an instruction, and none of them is a reason to reopen settled work.

2. Review all work done in this session. In a long session, earlier work may have been summarized out of your context: run `git status` and `git diff` (plus `git log` for anything committed this session) to recover changes you no longer remember. For each unrecorded shift in decisions, plans, scope, documents, external context, or code needing project-level explanation:
   - Append a line at the bottom of `CHANGES.md`: `{today} NNN [type] (area) description  key=value` (one line). Substitute `{today}` with today's ISO date before writing.
   - `NNN` is the highest serial already in the file plus one, zero-padded to three digits, continuing across every session. Scan the whole file for the maximum; do not assume the last line holds it, and never reuse or renumber a serial. When appending several entries, they take consecutive serials.
   - `(area)` is one of the areas listed in `BRIEFING.md`, or `(-)` when none fits. Do not invent a spelling that is not on that list.
   - Types: `decision`, `plan`, `doc`, `scope`, `code`, `note`. For `decision`, name the rejected alternative when one exists (`X over Y; reason`).
   - Tags, optional, after two spaces: `supersedes=NNN`, `closes=NNN`, `refs=<commit|PR|issue>`. Use `closes=` when this session resolved an open `[note]`; the note's own line is left untouched.

   Three things do **not** go in the log, however much the session produced of them. Verification evidence (test counts, measured distributions, clean-console confirmations) belongs in the COMPLIANCE `Verified:` line of your response — it expires as soon as the code changes. Parameter values that code, config or an asset file already owns — record why, never what. Session conduct: frustration, blame, and the blow-by-blow of your own corrections. Where a failure taught something durable, record the lesson and drop the incident.

   If this session superseded an earlier decision, append the new decision with `supersedes=NNN` naming the entry it replaces, and say why the old one was abandoned — the reason is the expensive part. Leave the superseded line exactly as it is. This is a log: no entry in it is ever edited or deleted, however wrong it later turned out to be. Then carry the live decision into `BRIEFING.md`, which is where a future session reads what currently holds.

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
   - `Areas`: the closed vocabulary `CHANGES.md` tags against. If it is empty, seed it now from the parts of the project that actually take work (subsystems, not file names — `auth`, `ingest`, `cli`). Add an area when work starts landing somewhere the list does not cover. Never rename or remove one that existing entries already use: the log is immutable, so a rename orphans every entry carrying the old name.
   - `Environment quirks`: promote durable `[note]` context that step 4's compaction would otherwise fold into a summary (flaky sandboxes, renamed keys, local oddities); prune quirks that no longer hold. Do this before step 4 runs, not after.
   - `Do-not-touch`: change only on explicit user instruction.

   A field is trimmed by removing what is no longer true, never by dropping live state to hit a number. A large project legitimately carries more open questions than a small one. What does not belong at any size: a bullet that narrates a past session rather than stating current state (`Styling pass`, `Auth refactor`, `Cleanup pass`). That is history — move it to CHANGES.md or cut it.

4. **Compact the log.** Run the passes defined in `.claude/commands/compresschanges.md` (its steps 1 through 6 — everything except its own output block) over `CHANGES.md` now, including the entries this session just appended. This happens at every close, not only when the file has grown — running it every session is what keeps junk from ever accumulating and holds the file at its 100-entry working ceiling.

   Most closes will change nothing here, and that is the expected result: the passes write nothing and create no backup when they find nothing to do. Do not print that command's own output block; report the outcome on the closing block below instead.

   Skip this step only when `CHANGES.md` has five or fewer entries.

5. Write only the file(s) you changed. If neither changed, do not write. Do not stage or commit. Leave changes dirty so the user controls when they enter git history.

6. Output exactly this format, then stop:

```
Session closed.
CHANGES.md: [number] new entries appended ([first serial]-[last serial] | none); [n] entries after compaction [| compaction made no changes | skipped, under 6 entries].
BRIEFING.md: [updated | unchanged].
```

Do not skip this protocol. If nothing recordable changed, say so and confirm both files are unchanged.
