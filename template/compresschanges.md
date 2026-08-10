# /compresschanges: Compact CHANGES.md History

Compacts `CHANGES.md` while preserving every real record, including the ones later events overturned.

This runs automatically: `/close` executes steps 1 through 6 at the end of every session. Invoking `/compresschanges` directly does the same work on demand, and is worth doing after a session that ended without a close. Because it runs constantly, most runs will find nothing and write nothing. That is the point — junk never gets a chance to pile up.

Two things it maintains:

- **Genre.** Entries that were never durable records — verification receipts, parameter narration, session conduct — come out, at any age. This is where most of the recovery comes from.
- **The 100-entry working ceiling.** History older than 30 days collapses into monthly `SUM` lines until the file fits. Collapsing is not deleting: the month survives as a summary.

This is the one operation permitted to remove or rewrite lines in the log — property 2 of *CHANGES.md is a log* names it as the single exception. It is maintenance, never authoring. It does not add records, does not reinterpret them, and does not resolve which decision currently holds; that is `BRIEFING.md`'s job and this command never touches the brief. A superseded decision is a durable record: it is history, and it stays.

## Steps

1. Record the entry count: `grep -c '^[0-9]\{4\}-' CHANGES.md`.

   Do not back up yet. Steps 2 through 5 are analysis and write nothing; decide there whether anything actually changes. Back up only if it does, immediately before the write in step 6: `cp CHANGES.md "CHANGES.md.bak.$(date +%Y%m%d-%H%M%S)"`, and if the project is a git repository, ensure `.gitignore` contains the line `CHANGES.md.bak.*` (append it if missing) so backups stay out of version control. This ordering matters because `/close` runs these passes every session — an unconditional backup would leave a file behind after every close.

2. Read `CHANGES.md` completely. Every entry, not the tail. This is the one protocol that does; a session start reads five.

3. **Genre pass — applies at every age, and usually recovers more than the date pass.** Remove entries that were never durable records:
   - Verification receipts: test counts, measured distributions, "0 failures across N runs", clean-console confirmations. Keep one only if the measurement itself is an open decision (an unresolved perf number, a limit nobody has ruled on).
   - Parameter narration: values that code, config or an asset file is authoritative for. The copy here is already at risk of being wrong.
   - Session conduct: frustration, blame, blow-by-blow correction history. Where the failure taught something durable, keep the lesson as a single `[note]` carrying the earliest serial among the lines it replaces, and drop the narrative. Do not edit an existing `[decision]` to absorb it; entries are not rewritten here.

4. **Linking pass.** Find `[decision]` entries later reversed or replaced where the later entry carries no `supersedes=` tag, and add the tag naming the serial it replaced. Both lines stay. Repairing a missing link is the only edit this command may make to an existing entry, and it may not touch that entry's date, serial, type, area, or claim.

   Never delete a superseded decision. The reason an approach was abandoned is the most expensive knowledge in the file, and a reader learns which decision currently holds from `BRIEFING.md`, not from the absence of a line here.

5. **Date pass — the 100-entry ceiling.** If the file holds 100 entries or fewer after steps 3 and 4, do nothing here; history that fits needs no collapsing. Otherwise work oldest-first, and stop the moment the count reaches 100.

   Group the entries being collapsed by month (`YYYY-MM`) and write one summary line per major theme or area of work:

   `YYYY-MM-DD SUM [note] (area) Summary: <concise description of that month's key changes>`

   Use the last day of the month as the date, and the literal `SUM` in the serial column: a summary is a compaction artifact, not a logged event, so it never consumes a serial and never becomes the target of a reference. It does count toward the 100. Use `(-)` where a month's work spans several areas. Never collapse anything under 30 days old, however far over the ceiling the file is. Existing `SUM` lines from earlier runs may be merged into the month's summary, never expanded.

   Three things are never summarized away, at any age:
   - a `[decision]` or `[scope]` entry, superseded or not — keep verbatim;
   - a `[note]` that states something still open, meaning no later entry names its serial in a `closes=` tag;
   - any entry whose serial a surviving line references in `supersedes=` or `closes=`. Summarizing it away leaves a dangling reference.

   If the protected entries alone come to more than 100, the file stays over 100 and that is the correct outcome. The ceiling governs how much *history* is carried, and is never a licence to drop a live record. Do not delete an entry to hit the number.

6. If steps 3 through 5 found nothing to change, stop here: write nothing, create no backup, and report no change. Otherwise back up per step 1, then construct the full new file content (header, format hint, summary lines, preserved entries, recent entries) and write it in a single Write call. Do not use incremental Edits.

   Then verify: serials are unique and unchanged from before the run, no line was renumbered, every `supersedes=` and `closes=` target still exists in the file, every `[decision]` reversed by a later entry is linked from it, and the header block survived intact.

7. When invoked directly, output exactly this format, then stop. (When running as `/close` step 4, skip this block — `/close` reports the outcome on its own closing block.)

```
CHANGES.md compacted.
Entries: [before] -> [after] (ceiling 100)
Dropped: [n] receipts, [n] parameter lines, [n] conduct entries
Linked: [n] supersession references repaired
Collapsed: [n] entries into [n] monthly summaries
Preserved verbatim: [n] decisions/scope changes, [n] open findings
```

If nothing changed, the whole block is replaced by the single line `CHANGES.md: nothing to compact ([n] entries).`

Do not modify BRIEFING.md. Recent entries are not exempt from step 3 — a receipt written yesterday is still a receipt — but do not touch an entry whose subject is still unresolved, whatever its age.
