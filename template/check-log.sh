#!/usr/bin/env bash
# Read-only verification shared by session close and upgrade.sh. Only the temporary
# reference database is created; the project database is always opened readonly.
set -euo pipefail

objects_only=0
if [ "${1:-}" = "--objects" ]; then objects_only=1; shift; fi
if [ "$#" -gt 2 ]; then
  echo "Usage: bash check-log.sh [--objects] [changes.db] [changes-schema.sql]" >&2
  exit 1
fi
db="${1:-changes.db}"
schema="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/changes-schema.sql}"
if [ ! -f "$db" ] || [ ! -f "$schema" ]; then
  echo "Error: database or shipped schema missing; run upgrade.sh if the schema is missing." >&2
  exit 1
fi
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
sqlite3 -bail "$scratch/expected.db" < "$schema"
# Quote the path as SQL data. Expanding a variable does not evaluate any shell
# syntax in its value; never build these commands with eval.
expected_path="${scratch//\'/\'\'}/expected.db"
# One line per difference, as object|name|status. The comparison runs both ways:
# the first arm names what the shipped schema defines and this database lacks or
# has altered, the second what this database carries and the schema never
# defined. UNION ALL rather than FULL OUTER JOIN, which needs SQLite 3.39.
drift="$(sqlite3 -bail -readonly "$db" "
  ATTACH DATABASE '$expected_path' AS expected;
  SELECT e.type || '|' || e.name || '|'
      || CASE WHEN a.name IS NULL THEN 'missing' ELSE 'changed' END
    FROM expected.sqlite_master e
    LEFT JOIN main.sqlite_master a ON a.type = e.type AND a.name = e.name
   WHERE e.type IN ('table','trigger','view') AND e.name NOT LIKE 'sqlite_%'
     AND replace(e.sql, 'IF NOT EXISTS ', '') IS NOT replace(a.sql, 'IF NOT EXISTS ', '')
  UNION ALL
  SELECT a.type || '|' || a.name || '|unexpected'
    FROM main.sqlite_master a
    LEFT JOIN expected.sqlite_master e ON e.type = a.type AND e.name = a.name
   WHERE a.type IN ('table','trigger','view') AND a.name NOT LIKE 'sqlite_%'
     AND e.name IS NULL
   ORDER BY 1;
")"
if [ "$objects_only" -eq 1 ]; then
  if [ -n "$drift" ]; then printf '%s\n' "$drift"; fi
  exit 0
fi

# An object the shipped schema does not define is not always damage. An extra
# table or view cannot weaken the log's guarantees, and a project may carry one
# deliberately. An extra trigger can: a BEFORE INSERT trigger raising IGNORE
# makes every INSERT succeed and record nothing, which no protocol could see.
damage="$(printf '%s\n' "$drift" | awk -F'|' 'NF == 3 && ($3 != "unexpected" || $1 == "trigger")')"
extra="$(printf '%s\n' "$drift" | awk -F'|' 'NF == 3 && $3 == "unexpected" && $1 != "trigger"')"
# What upgrade.sh cannot put back: it never rebuilds a table, because only git
# still holds the rows one had, and it never removes an object it does not ship.
unrepairable="$(printf '%s\n' "$damage" | awk -F'|' 'NF == 3 && ($1 == "table" || $3 == "unexpected")')"

version="$(sqlite3 -readonly "$db" 'PRAGMA user_version;')"
want_version="$(sqlite3 -readonly "$scratch/expected.db" 'PRAGMA user_version;')"
integrity="$(sqlite3 -readonly "$db" 'PRAGMA integrity_check;')"
have="$(sqlite3 -readonly "$db" "SELECT count(*) FROM sqlite_master WHERE type='trigger';")"
want="$(sqlite3 -readonly "$scratch/expected.db" "SELECT count(*) FROM sqlite_master WHERE type='trigger';")"
if [ "$integrity" != "ok" ]; then
  echo "Error: changes.db integrity: $integrity. Recover the database from git." >&2
  exit 1
fi
if [ "$version" != "$want_version" ]; then
  echo "Error: changes.db schema v$version; checker expects v$want_version. Run upgrade.sh from a compatible checkout." >&2
  exit 1
fi
if [ -n "$damage" ]; then
  echo "Error: changes.db does not match schema v$want_version (object|name|status):" >&2
  printf '%s\n' "$damage" >&2
  if [ -n "$unrepairable" ]; then
    echo "A trigger the schema does not define, or a missing or changed table, is not repairable: remove the object, or recover changes.db from git." >&2
  else
    echo "Run upgrade.sh to restore the shipped definitions." >&2
  fi
  exit 1
fi
if [ "$have" != "$want" ]; then
  # No definition difference explains this, so there is nothing to restore.
  echo "Error: changes.db carries $have triggers where schema v$want_version defines $want, with no difference in definitions to explain it. Recover changes.db from git." >&2
  exit 1
fi
if [ -n "$extra" ]; then
  echo "Note: changes.db also carries objects the shipped schema does not define (object|name|status):" >&2
  printf '%s\n' "$extra" >&2
  echo "They are left alone; nothing the log guarantees depends on them." >&2
  echo "changes.db checked: integrity ok, $have triggers; shipped definitions match schema v$version, alongside the objects noted above."
  exit 0
fi
echo "changes.db checked: integrity ok, $have triggers; definitions match schema v$version."
