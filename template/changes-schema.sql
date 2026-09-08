PRAGMA user_version = 5;

CREATE TABLE areas (
  name TEXT PRIMARY KEY CHECK (name <> '')
) WITHOUT ROWID;

CREATE TABLE entries (
  serial      INTEGER PRIMARY KEY AUTOINCREMENT,
  date        TEXT NOT NULL DEFAULT (date('now','localtime'))
              CHECK (date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
  type        TEXT NOT NULL CHECK (type IN ('decision','plan','doc','scope','code','note')),
  area        TEXT NOT NULL DEFAULT '-',
  description TEXT NOT NULL CHECK (description <> ''),
  refs        TEXT
);

CREATE TABLE links (
  from_serial INTEGER NOT NULL,
  to_serial   INTEGER NOT NULL,
  kind        TEXT NOT NULL CHECK (kind IN ('supersedes','closes')),
  PRIMARY KEY (from_serial, to_serial, kind),
  CHECK (from_serial > to_serial)
) WITHOUT ROWID;

CREATE TABLE legacy_summaries (
  month TEXT NOT NULL, area TEXT NOT NULL, description TEXT NOT NULL
);

-- The agent's parking lot: open questions, doubts about deferred work,
-- exceptions noticed to settled decisions. Working state, not log history:
-- born open, text frozen at insert, resolved exactly once, never deleted.
CREATE TABLE concerns (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  opened     TEXT NOT NULL DEFAULT (date('now','localtime'))
             CHECK (opened GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
  area       TEXT NOT NULL DEFAULT '-',
  concern    TEXT NOT NULL CHECK (concern <> ''),
  ref_serial INTEGER,
  resolved   TEXT CHECK (resolved IS NULL OR resolved GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
  resolution TEXT CHECK (resolution IS NULL OR resolution <> ''),
  CHECK ((resolved IS NULL) = (resolution IS NULL))
);

CREATE TRIGGER entries_no_update BEFORE UPDATE ON entries
  BEGIN SELECT RAISE(ABORT, 'log entries are immutable'); END;
CREATE TRIGGER entries_no_delete BEFORE DELETE ON entries
  BEGIN SELECT RAISE(ABORT, 'log entries are never deleted'); END;
CREATE TRIGGER links_no_update BEFORE UPDATE ON links
  BEGIN SELECT RAISE(ABORT, 'links are immutable'); END;
CREATE TRIGGER links_no_delete BEFORE DELETE ON links
  BEGIN SELECT RAISE(ABORT, 'links are never deleted'); END;
CREATE TRIGGER areas_no_update BEFORE UPDATE ON areas
  BEGIN SELECT RAISE(ABORT, 'areas are never renamed; log entries reference them'); END;
CREATE TRIGGER areas_no_delete BEFORE DELETE ON areas
  BEGIN SELECT RAISE(ABORT, 'areas are never removed; log entries reference them'); END;

CREATE TRIGGER entries_area_known BEFORE INSERT ON entries
  WHEN NEW.area <> '-' AND NOT EXISTS (SELECT 1 FROM areas WHERE name = NEW.area)
  BEGIN SELECT RAISE(ABORT, 'unknown area; add it to BRIEFING.md and the areas table first'); END;
CREATE TRIGGER entries_no_backfill AFTER INSERT ON entries
  WHEN NEW.serial < (SELECT max(serial) FROM entries)
  BEGIN SELECT RAISE(ABORT, 'serials append only; never insert between or below existing entries'); END;
CREATE TRIGGER entries_no_replace BEFORE INSERT ON entries
  WHEN NEW.serial IS NOT NULL AND EXISTS (SELECT 1 FROM entries WHERE serial = NEW.serial)
  BEGIN SELECT RAISE(ABORT, 'serials are never reused; INSERT OR REPLACE cannot rewrite an entry'); END;
CREATE TRIGGER links_serials_exist BEFORE INSERT ON links
  WHEN NOT EXISTS (SELECT 1 FROM entries WHERE serial = NEW.from_serial)
    OR NOT EXISTS (SELECT 1 FROM entries WHERE serial = NEW.to_serial)
  BEGIN SELECT RAISE(ABORT, 'link names a serial that does not exist'); END;

CREATE TRIGGER concerns_no_delete BEFORE DELETE ON concerns
  BEGIN SELECT RAISE(ABORT, 'concerns are resolved, never deleted'); END;
CREATE TRIGGER concerns_immutable_text BEFORE UPDATE ON concerns
  WHEN NEW.id <> OLD.id OR NEW.opened <> OLD.opened OR NEW.area <> OLD.area
    OR NEW.concern <> OLD.concern
    OR COALESCE(NEW.ref_serial, -1) <> COALESCE(OLD.ref_serial, -1)
  BEGIN SELECT RAISE(ABORT, 'a concern''s text is immutable; only its resolution may be set'); END;
CREATE TRIGGER concerns_resolve_once BEFORE UPDATE ON concerns
  WHEN OLD.resolved IS NOT NULL
  BEGIN SELECT RAISE(ABORT, 'a resolved concern is frozen; open a new concern instead'); END;
CREATE TRIGGER concerns_born_open BEFORE INSERT ON concerns
  WHEN NEW.resolved IS NOT NULL
  BEGIN SELECT RAISE(ABORT, 'a concern is born open; resolving it is a separate update'); END;
CREATE TRIGGER concerns_area_known BEFORE INSERT ON concerns
  WHEN NEW.area <> '-' AND NOT EXISTS (SELECT 1 FROM areas WHERE name = NEW.area)
  BEGIN SELECT RAISE(ABORT, 'unknown area; add it to BRIEFING.md and the areas table first'); END;
CREATE TRIGGER concerns_ref_exists BEFORE INSERT ON concerns
  WHEN NEW.ref_serial IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM entries WHERE serial = NEW.ref_serial)
  BEGIN SELECT RAISE(ABORT, 'ref_serial names a log entry that does not exist'); END;
CREATE TRIGGER concerns_no_replace BEFORE INSERT ON concerns
  WHEN NEW.id IS NOT NULL AND EXISTS (SELECT 1 FROM concerns WHERE id = NEW.id)
  BEGIN SELECT RAISE(ABORT, 'concern ids are never reused; INSERT OR REPLACE cannot rewrite a concern'); END;

-- v4 guards: concern ids append only; area names trimmed, never '-', and never
-- a case variant of an existing area (a second spelling would split a facet
-- for good); legacy summaries frozen; text and dates well formed, because the
-- GLOB checks above accept '9999-99-99' and a blank made of spaces.
CREATE TRIGGER concerns_no_backfill AFTER INSERT ON concerns
  WHEN NEW.id < (SELECT max(id) FROM concerns)
  BEGIN SELECT RAISE(ABORT, 'concern ids append only; never insert below an existing id'); END;
CREATE TRIGGER areas_name_clean BEFORE INSERT ON areas
  WHEN NEW.name <> trim(NEW.name) OR NEW.name = '-'
    OR EXISTS (SELECT 1 FROM areas WHERE lower(name) = lower(NEW.name) AND name <> NEW.name)
  BEGIN SELECT RAISE(ABORT, 'area names are trimmed, never ''-'', and never a case variant of an existing area'); END;
CREATE TRIGGER legacy_summaries_no_update BEFORE UPDATE ON legacy_summaries
  BEGIN SELECT RAISE(ABORT, 'legacy summaries are never edited'); END;
CREATE TRIGGER legacy_summaries_no_delete BEFORE DELETE ON legacy_summaries
  BEGIN SELECT RAISE(ABORT, 'legacy summaries are never deleted'); END;
CREATE TRIGGER entries_well_formed BEFORE INSERT ON entries
  WHEN trim(NEW.description) = '' OR date(NEW.date) IS NOT NEW.date
  BEGIN SELECT RAISE(ABORT, 'an entry needs a non-blank description and a real date'); END;
CREATE TRIGGER concerns_well_formed BEFORE INSERT ON concerns
  WHEN trim(NEW.concern) = '' OR date(NEW.opened) IS NOT NEW.opened
  BEGIN SELECT RAISE(ABORT, 'a concern needs non-blank text and a real opened date'); END;
CREATE TRIGGER concerns_resolution_well_formed BEFORE UPDATE ON concerns
  WHEN NEW.resolved IS NOT NULL AND (date(NEW.resolved) IS NOT NEW.resolved OR trim(NEW.resolution) = '')
  BEGIN SELECT RAISE(ABORT, 'a resolution needs a real date and a non-blank reason'); END;

-- v5 guards: every text is one line, and an area name can round-trip through
-- the brief's comma-separated Areas line and the log's (area) rendering.
CREATE TRIGGER entries_one_line BEFORE INSERT ON entries
  WHEN instr(NEW.description, char(10)) > 0 OR instr(NEW.description, char(13)) > 0
  BEGIN SELECT RAISE(ABORT, 'an entry is one line; no newline in its description'); END;
CREATE TRIGGER concerns_one_line BEFORE INSERT ON concerns
  WHEN instr(NEW.concern, char(10)) > 0 OR instr(NEW.concern, char(13)) > 0
  BEGIN SELECT RAISE(ABORT, 'a concern is one line; no newline in its text'); END;
CREATE TRIGGER concerns_resolution_one_line BEFORE UPDATE ON concerns
  WHEN NEW.resolution IS NOT NULL
    AND (instr(NEW.resolution, char(10)) > 0 OR instr(NEW.resolution, char(13)) > 0)
  BEGIN SELECT RAISE(ABORT, 'a resolution is one line; no newline in its reason'); END;
CREATE TRIGGER areas_name_plain BEFORE INSERT ON areas
  WHEN NEW.name GLOB '*[,;()]*' OR instr(NEW.name, char(10)) > 0 OR instr(NEW.name, char(13)) > 0
  BEGIN SELECT RAISE(ABORT, 'an area name holds no comma, semicolon, parenthesis or newline; the brief lists areas comma-separated and the log renders them in parentheses'); END;

CREATE VIEW log_lines AS
  SELECT e.serial,
    printf('%s %03d [%s] (%s) %s', e.date, e.serial, e.type, e.area, e.description)
    || COALESCE('  ' || (SELECT group_concat(l.kind || '=' || printf('%03d', l.to_serial), ' ')
                         FROM links l WHERE l.from_serial = e.serial), '')
    || COALESCE('  refs=' || e.refs, '') AS line
  FROM entries e;

CREATE VIEW concern_lines AS
  SELECT c.id, (c.resolved IS NOT NULL) AS is_resolved,
    printf('%s #%02d (%s) %s', c.opened, c.id, c.area, c.concern)
    || CASE WHEN c.ref_serial IS NULL THEN ''
            ELSE '  re=' || printf('%03d', c.ref_serial) END
    || COALESCE('  resolved ' || c.resolved || ': ' || c.resolution, '') AS line
  FROM concerns c;
