# /compresschanges: Compact CHANGES.md History

Run this when `CHANGES.md` has grown too large. It compacts the journal while preserving everything still true.

Size, not age, is the trigger: a project can write two hundred entries in a week, and a purely date-based pass will not see them. Run it whenever the file exceeds ~20 KB or ~150 entries, whatever their dates.

## Steps

1. Back up the current file: `cp CHANGES.md "CHANGES.md.bak.$(date +%Y%m%d-%H%M%S)"`. If the project is a git repository, ensure `.gitignore` contains the line `CHANGES.md.bak.*` (append it if missing) so backups stay out of version control. Record the entry count (`grep -c '^[0-9]\{4\}-' CHANGES.md`) and byte count (`wc -c < CHANGES.md`).

2. Read `CHANGES.md` completely. Every entry, not the tail.

3. **Genre pass — applies at every age, and usually recovers more than the date pass.** Remove entries that were never durable records:
   - Verification receipts: test counts, measured distributions, "0 failures across N runs", clean-console confirmations. Keep one only if the measurement itself is an open decision (an unresolved perf number, a limit nobody has ruled on).
   - Parameter narration: values that code, config or an asset file is authoritative for. The copy here is already at risk of being wrong.
   - Session conduct: frustration, blame, blow-by-blow correction history. Where the failure taught something durable, keep the lesson as a single `[note]` or fold it into the related decision as the rejected alternative's reason, and drop the narrative.

4. **Supersession pass.** Find `[decision]` entries later reversed or replaced. Fold each: the surviving decision names what it replaced and why (`X over Y; reason`), and the superseded line is deleted. Do not mark-and-keep — a dead decision left in place reads as live to the next session, which is the failure this pass exists to fix.

   Where several entries record one reversal chain, keep one line per reversal that carries a distinct reason, not one line for the whole chain. The reason an approach failed is the expensive knowledge; the sequence of attempts is not.

5. **Date pass.** For entries older than 30 days that survived steps 3 and 4, group by month (`YYYY-MM`) and write one summary line per major theme or area of work:

   `YYYY-MM-DD [note] Summary: <concise description of that month's key changes>`

   Use the last day of the month as the date. Existing `[note] Summary:` lines from earlier compressions may be merged into the month's summary, never expanded.

   Two things are never summarized away, at any age: a live `[decision]` or `[scope]` entry (keep verbatim), and a `[note]` that states something still open — an unanswered question, an unmitigated finding, an environment trap. Those are the entries a future session most needs and least able to reconstruct.

6. Construct the full new file content (header, format hint, summary lines, preserved entries, recent entries) and write it in a single Write call. Do not use incremental Edits. Then verify: no entry exceeds 200 characters, and every surviving `[decision]` is either still true or has been folded into one that is.

7. Output exactly this format, using the recorded counts, then stop:

```
CHANGES.md compressed.
Entries: [before] -> [after]
Size: [before] -> [after]
Dropped: [n] receipts, [n] parameter lines, [n] conduct entries
Folded: [n] superseded decisions
Preserved verbatim: [n] live decisions/scope changes, [n] open findings
```

Do not modify BRIEFING.md. Recent entries are not exempt from steps 3 and 4 — a receipt written yesterday is still a receipt — but do not touch an entry whose subject is still unresolved, whatever its age.
