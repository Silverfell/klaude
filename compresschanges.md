# /compresschanges — Compact CHANGES.md History

Run this when CHANGES.md has grown too large. Compresses the history while preserving a high-level summary of everything to date.

## Steps

1. Read `CHANGES.md` completely.

2. Identify all entries older than 30 days from today's date.

3. Group those older entries by month (YYYY-MM). For each month, write one summary line per major theme or area of work. Use the format:

   `YYYY-MM-DD [note] Summary: <concise description of that month's key changes>`

   Use the last day of the month as the date. Preserve any entry that records a decision, scope change, or breaking change verbatim (do not summarize those away).

4. Replace the old entries with the new summary lines. Keep all entries from the last 30 days untouched.

5. Ensure the file header and format hint line remain intact.

6. Output exactly this, then stop:

```
CHANGES.md compressed.
Original entries: [count]
Compressed to: [count]
Preserved verbatim: [count] (decisions/scope changes)
```

Do not modify BRIEFING.md. Do not alter any entries from the last 30 days.
