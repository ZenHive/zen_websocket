#!/usr/bin/env bash
# Vendored into this repo so `mix agents.check` runs on a portable checkout that
# does not contain ~/_DATA/code/claude-marketplace. Upstream source:
# claude-marketplace/scripts/sync-agents-md.sh
#
# Generate AGENTS.md for Codex by inlining @-imports from the project's CLAUDE.md.
#
# Manual tool. Run from inside a target repo. Reads ./CLAUDE.md, recursively
# resolves @-imports (e.g. @~/.claude/includes/critical-rules.md, including
# umbrella includes that themselves @-import other files), inlines their
# content, and writes ./AGENTS.md. Codex doesn't inherit our local Claude Code
# hooks, so AGENTS.md carries the rules those hooks would have enforced.
#
# Note: this used to fire automatically via a PostToolUse hook in the
# `delegation` plugin (`agents-md-sync.sh`). That auto-sync hook was retired in
# the deltahedge→zenhive migration; this standalone generator is the manual
# replacement. The --check mode below is the freshness gate a re-added hook
# wrapper (or a CI step / harness check_command) calls to fail loudly when
# AGENTS.md has drifted from CLAUDE.md — without it, a stale AGENTS.md silently
# makes cross-family reviewers (codex/cursor/grok) gate against rules you've
# already changed.
#
# Recursion depth-limit matches Claude Code's documented @-import behavior
# (https://code.claude.com/docs/en/memory#import-additional-files): 5 levels.
#
# Usage:
#   ./sync-agents-md.sh             # write AGENTS.md
#   ./sync-agents-md.sh --dry-run   # print to stdout instead
#   ./sync-agents-md.sh --check     # exit non-zero if AGENTS.md is stale/missing
#                                   # (compares rendered output, so it catches
#                                   #  drift in transitive @-imports too)
#
# All modes also refuse to let a Hex-publishing repo ship AGENTS.md as ex_doc
# documentation — see check_publish_exposure below. --check fails on it; the
# write/dry-run modes warn.

set -euo pipefail

MODE="write"
case "${1:-}" in
  --dry-run) MODE="dry-run" ;;
  --check)   MODE="check" ;;
  --help|-h)
    cat <<'USAGE'
Generate AGENTS.md by inlining @-imports from ./CLAUDE.md.

Usage:
  sync-agents-md.sh             write AGENTS.md
  sync-agents-md.sh --dry-run   print rendered output to stdout, write nothing
  sync-agents-md.sh --check     exit non-zero if AGENTS.md is stale or missing
  sync-agents-md.sh --help      show this message

--check compares the rendered output (not mtimes), so it catches drift in
transitive @-imports too. Use it as a CI / pre-commit / harness check_command
gate so a stale AGENTS.md fails loudly instead of misleading reviewers.

Every mode also checks that a Hex-publishing repo does not list AGENTS.md in
ex_doc's `extras` — publishing it would put your inlined CLAUDE.md on
hexdocs.pm. --check exits non-zero; write and --dry-run only warn.
USAGE
    exit 0
    ;;
  "") ;;
  *)
    echo "ERROR: unknown argument: $1" >&2
    echo "Usage: $0 [--dry-run | --check | --help]" >&2
    exit 2
    ;;
esac

CLAUDE_MD="./CLAUDE.md"
AGENTS_MD="./AGENTS.md"
MAX_DEPTH=5

if [[ ! -f "$CLAUDE_MD" ]]; then
  echo "ERROR: $CLAUDE_MD not found in current directory" >&2
  echo "Run this script from inside a repo with a CLAUDE.md at its root." >&2
  exit 1
fi

resolve_path() {
  local raw="$1"
  if [[ "$raw" == "~/"* ]]; then
    printf '%s' "$HOME/${raw:2}"
  else
    printf '%s' "$raw"
  fi
}

errors=0
output=""

# inline_file <path> <depth> [<raw_label>]
# Reads <path> line by line; on `@<path>` lines, recursively inlines the target
# (up to MAX_DEPTH levels). Appends to the global $output.
inline_file() {
  local path="$1"
  local depth="$2"
  local raw_label="${3:-$path}"

  if (( depth > MAX_DEPTH )); then
    echo "ERROR: @-import depth exceeded $MAX_DEPTH at $raw_label" >&2
    errors=$((errors + 1))
    return
  fi

  local line nested_raw nested_resolved
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^@([^[:space:]]+)[[:space:]]*$ ]]; then
      nested_raw="${BASH_REMATCH[1]}"
      nested_resolved=$(resolve_path "$nested_raw")

      if [[ ! -r "$nested_resolved" ]]; then
        echo "ERROR: cannot read @-import: $nested_raw (resolved to $nested_resolved)" >&2
        errors=$((errors + 1))
        continue
      fi

      output+="<!-- @-import: ${nested_raw} -->"$'\n'
      inline_file "$nested_resolved" $((depth + 1)) "$nested_raw"
      output+=$'\n'
    else
      output+="${line}"$'\n'
    fi
  done < "$path"
}

# AGENTS.md inlines CLAUDE.md's @-imports, so it carries the maintainer's global
# rules, harness workflow, and references to unrelated private projects. That is
# correct for a reviewer reading it in-repo, and wrong for anything published:
# listing it in ex_doc's `extras` ships all of it to hexdocs.pm as consumer
# documentation. Observed 2026-08-22 on zen_websocket, where agents.html had been
# live across six releases (0.3.1–0.6.1) under the "Getting Started" group; no
# gate flagged it, because --check only ever asked whether AGENTS.md was FRESH,
# never whether it belonged in the docs at all.
#
# Only Hex-publishing repos are affected — a private repo may list AGENTS.md in
# its docs harmlessly, so the guard requires both signals before it fires.
check_publish_exposure() {
  [[ -f ./mix.exs ]] || return 0

  # Strip whole-line comments so an explanatory comment naming AGENTS.md (the
  # usual way a repo records WHY it is excluded) can never trip the guard.
  local code
  code=$(sed 's/^[[:space:]]*#.*$//' ./mix.exs)

  grep -qE '(^|[^_[:alnum:]])package:|defp[[:space:]]+package' <<<"$code" || return 0

  # Only an occurrence INSIDE a `files:` / `extras:` / `groups_for_extras` list
  # counts. Two false signals must not fire the guard:
  #   * a repo whose aliases run this very script ("AGENTS.md freshness check")
  #   * a repo documenting the exclusion in a trailing comment
  # And the match must be delimiter-agnostic: a Hex `files:` list is usually a
  # ~w() sigil where the entry is a bare word, not a quoted string. Requiring
  # quotes missed dialyzer_json, which shipped AGENTS.md inside the package
  # tarball across all four of its releases.
  awk '
    function opens(s,  n,i,c) { n=0; for (i=1;i<=length(s);i++) { c=substr(s,i,1)
      if (c=="(" || c=="[" || c=="{") n++
      else if (c==")" || c=="]" || c=="}") n-- }
      return n }
    {
      line=$0
      if (!collecting && match(line, /(^|[^a-zA-Z_])(files|extras)[[:space:]]*:|groups_for_extras/)) {
        collecting=1; depth=0; seen=0; span=0
        line=substr(line, RSTART+RLENGTH-1)
      }
      if (collecting) {
        span++
        if (line ~ /(^|[^[:alnum:]_\/.-])AGENTS\.md/) { found=1 }
        d=opens(line); depth+=d; if (d>0) seen=1
        if ((seen && depth<=0) || span>60) collecting=0
      }
    }
    END { exit(found ? 0 : 1) }
  ' <<<"$code" || return 0

  echo "EXPOSED: ./mix.exs publishes to Hex and lists AGENTS.md in files:/extras:." >&2
  echo "  AGENTS.md inlines CLAUDE.md's @-imports — publishing it puts your global rules" >&2
  echo "  and unrelated internal project references on hexdocs.pm and inside the package." >&2
  echo "  Remove it from ex_doc's \`extras\` (and \`groups_for_extras\`) AND from the Hex" >&2
  echo "  \`files:\` list; keep the file in the repo for reviewers." >&2
  echo "  Already published? \`mix hex.publish docs --revert VSN\` drops the docs page;" >&2
  echo "  a tarball can only be corrected by a new release." >&2
  return 1
}

output+="<!-- Auto-generated from CLAUDE.md by claude-marketplace/scripts/sync-agents-md.sh — do not edit manually -->"$'\n'
output+=$'\n'

inline_file "$CLAUDE_MD" 1 "./CLAUDE.md"

if [[ "$errors" -gt 0 ]]; then
  echo "Aborting — $errors @-import(s) unreadable." >&2
  exit 1
fi

case "$MODE" in
  dry-run)
    printf '%s' "$output"
    echo ""
    echo "--- Summary ---" >&2
    echo "Dry run — would write to $AGENTS_MD" >&2
    check_publish_exposure || true
    ;;
  check)
    # Exposure is checked before freshness: a published AGENTS.md is a leak
    # whether or not it is current, and "up to date" must never read as "fine".
    check_publish_exposure || exit 1
    if [[ ! -f "$AGENTS_MD" ]]; then
      echo "STALE: $AGENTS_MD is missing — run sync-agents-md.sh" >&2
      exit 1
    fi
    if ! diff -q <(printf '%s' "$output") "$AGENTS_MD" >/dev/null; then
      echo "STALE: $AGENTS_MD has drifted from CLAUDE.md (+@-imports) — run sync-agents-md.sh" >&2
      exit 1
    fi
    echo "OK: $AGENTS_MD is up to date"
    ;;
  write)
    printf '%s' "$output" > "$AGENTS_MD"
    echo "Wrote $AGENTS_MD"
    # Warn but never fail: regenerating the file is how you FIX a stale
    # AGENTS.md, so blocking the write would strand a repo that trips the guard.
    check_publish_exposure || true
    ;;
esac
