#!/usr/bin/env bash
set -euo pipefail

# Resolve the directory where this script lives (the source of truth)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Target is the current working directory (where the user invokes from)
TARGET_DIR="$(pwd)"

usage() {
  echo "Usage: setup.sh [--claude|--codex|--both]"
  echo "  --claude   Install for Claude Code (CLAUDE.md + .claude/commands/)"
  echo "  --codex    Install for Codex (AGENTS.md + .agents/skills/)"
  echo "  --both     Install both layouts"
  echo "  With no flag, you are prompted to choose."
}

# Parse the target flag. The target flags are mutually exclusive.
TARGET=""
set_target() {
  if [ -n "$TARGET" ]; then
    echo "Error: specify only one of --claude, --codex, or --both." >&2
    exit 1
  fi
  TARGET="$1"
}
for arg in "$@"; do
  case "$arg" in
    --claude) set_target claude ;;
    --codex)  set_target codex ;;
    --both)   set_target both ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Error: unknown argument '$arg'." >&2; usage >&2; exit 1 ;;
  esac
done

if [ "$SCRIPT_DIR" = "$TARGET_DIR" ]; then
  echo "Error: you are already in the source directory. cd to your project first."
  exit 1
fi

# Prompt for the target if no flag was given.
if [ -z "$TARGET" ]; then
  echo "Install for:"
  echo "[1] claude"
  echo "[2] codex"
  echo "[3] both"
  read -r sel
  case "$sel" in
    1|claude) TARGET="claude" ;;
    2|codex)  TARGET="codex" ;;
    3|both)   TARGET="both" ;;
    *) echo "Error: unrecognized selection '$sel'. Expected 1, 2, or 3." >&2; exit 1 ;;
  esac
fi

# Rewrite a template file for the Codex layout, writing to stdout:
#   - retitle the contract (CLAUDE.md -> AGENTS.md) and its command section
#   - retarget command paths to skill paths
#   - rewrite slash invocations to skill ($name) invocations
# Each rule is a no-op on files that lack the matched text.
rewrite_codex() {
  sed -e '1s/^# CLAUDE\.md$/# AGENTS.md/' \
      -e 's/^## Slash Commands$/## Skills/' \
      -e 's#`\.claude/commands/\([A-Za-z]*\)\.md`#`.agents/skills/\1/SKILL.md`#g' \
      -e 's#`/klawde`#`$klawde`#g' \
      -e 's#`/klaude`#`$klaude`#g' \
      -e 's#`/close`#`$close`#g' \
      -e 's#`/compresschanges`#`$compresschanges`#g' \
      "$1"
}

# Build a Codex skill file: SKILL.md with name/description front matter,
# followed by the rewritten protocol body.
build_skill_file() {
  local src="$1" name="$2" desc="$3" dst="$4"
  {
    printf -- '---\n'
    printf 'name: %s\n' "$name"
    printf 'description: "%s"\n' "$desc"
    printf -- '---\n\n'
    rewrite_codex "$src"
  } > "$dst"
}

# Overwrite guard: prompt before clobbering an existing destination.
# Returns 0 when the caller should write, 1 when it should skip.
should_write() {
  local dst="$1"
  if [ -f "$dst" ]; then
    echo "$dst already exists. Overwrite? [y/N]"
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      echo "Skipped $dst."
      return 1
    fi
  fi
  return 0
}

install_claude() {
  local dst="$TARGET_DIR/CLAUDE.md"
  if should_write "$dst"; then
    mkdir -p "$(dirname "$dst")"
    cp "$SCRIPT_DIR/template/CLAUDE.md" "$dst"
    echo "Copied $dst."
  fi
  for cmd in klawde.md klaude.md close.md compresschanges.md; do
    dst="$TARGET_DIR/.claude/commands/$cmd"
    if should_write "$dst"; then
      mkdir -p "$(dirname "$dst")"
      cp "$SCRIPT_DIR/template/$cmd" "$dst"
      echo "Copied $dst."
    fi
  done
}

# name | template file | skill description
install_skill() {
  local name="$1" src="$2" desc="$3"
  local dst="$TARGET_DIR/.agents/skills/$name/SKILL.md"
  if should_write "$dst"; then
    mkdir -p "$(dirname "$dst")"
    build_skill_file "$SCRIPT_DIR/template/$src" "$name" "$desc" "$dst"
    echo "Wrote $dst."
  fi
}

install_codex() {
  local dst="$TARGET_DIR/AGENTS.md"
  if should_write "$dst"; then
    mkdir -p "$(dirname "$dst")"
    rewrite_codex "$SCRIPT_DIR/template/CLAUDE.md" > "$dst"
    echo "Wrote $dst."
  fi
  install_skill klawde klawde.md \
    "Run only when explicitly invoked. Klawde entry protocol (full mode): read or create BRIEFING.md and CHANGES.md and confirm readiness at session start, with the Code craft module active."
  install_skill klaude klaude.md \
    "Run only when explicitly invoked. Klawde entry protocol (lean mode): same as klawde, but with the Code craft module disabled for the session."
  install_skill close close.md \
    "Run only when explicitly invoked. Klawde close protocol: record decisions and scope changes to CHANGES.md and update BRIEFING.md before ending work."
  install_skill compresschanges compresschanges.md \
    "Run only when explicitly invoked. Klawde journal compaction: summarize CHANGES.md entries older than 30 days while preserving decisions and scope changes."
}

case "$TARGET" in
  claude) install_claude ;;
  codex)  install_codex ;;
  both)   install_claude; install_codex ;;
esac

echo ""
echo "Done. Project initialized at $TARGET_DIR (target: $TARGET)"
case "$TARGET" in
  claude)
    echo "Run /klawde in Claude Code to start a session (or /klaude to start without the code-craft rules)." ;;
  codex)
    echo "Wrote AGENTS.md and .agents/skills/ in this project."
    echo "In Codex, run \$klawde (or pick klawde from /skills) to start a session; \$klaude starts without the code-craft rules." ;;
  both)
    echo "Wrote CLAUDE.md + .claude/commands/ (Claude Code) and AGENTS.md + .agents/skills/ (Codex)."
    echo "Run /klawde in Claude Code, or \$klawde in Codex, to start a session; klaude is the variant without the code-craft rules." ;;
esac
