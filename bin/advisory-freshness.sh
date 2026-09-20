#!/usr/bin/env bash
# Vendored into this repo so `mix deps.audit.gated` proves freshness on a
# portable checkout that does not contain ~/_DATA/code/onchain-stack. Upstream
# source: onchain-stack/bin/advisory-freshness.sh
#
# Fails when the local advisory database mix_audit reads is stale or unable to sync.
#
# Why this exists: mix_audit's Repo.synchronize/0 runs
#   System.cmd("git", ["pull", "--rebase", "--quiet", "origin", "main"])
# and discards the return value. A permanently failing sync is invisible by
# design -- `mix deps.audit` keeps auditing a frozen copy and still prints
# "No vulnerabilities found." Observed 2026-08-01: one hand-edited advisory file
# left the clone dirty, `git pull --rebase` exited 128, and nothing surfaced it.
#
# What this asserts, in order:
#   1. the clone has no modified TRACKED files  (the condition that kills the rebase)
#   2. our copy provably equals upstream's current tip
#   3. if upstream is unreachable, our last SUCCESSFUL sync is recent
#
# It deliberately does NOT gate on the age of upstream's newest commit. That
# measures mirego's publishing cadence, not our sync health: observed gaps
# between consecutive upstream commits reach 96 days (and 33 days in April
# 2026), so a short commit-age limit reds every consumer's `mix ci` during any
# quiet period and trains people to ignore the gate. Commit age is used only as
# a wide abandonment bound.
#
# Run this BEFORE `mix deps.audit` so a dead database fails loudly instead of
# reporting green.
#
# Usage: advisory-freshness.sh [--max-offline-days N] [--abandoned-days N]
#          --max-offline-days  last successful sync must be within N days when
#                              upstream cannot be reached          (default 7)
#          --abandoned-days    upstream's newest commit older than N days means
#                              the importer itself is likely dead  (default 180)

set -euo pipefail

# MixAudit.Repo.path/0 hardcodes this directory and does not honor
# MIX_AUDIT_ADVISORY_PATH. Proving any other clone would be a false green.
MIRROR="$HOME/.local/share/elixir-security-advisories-mirego"
MAX_OFFLINE_DAYS=7
ABANDONED_DAYS=180

while [ $# -gt 0 ]; do
  case "$1" in
    --max-offline-days) MAX_OFFLINE_DAYS="$2"; shift 2 ;;
    --abandoned-days) ABANDONED_DAYS="$2"; shift 2 ;;
    -h|--help) sed -n '2,31p' "$0"; exit 0 ;;
    *) echo "advisory-freshness: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

fail() { echo "advisory-freshness: FAIL - $*" >&2; exit 1; }

# Our own record of the last VERIFIED sync. Git's FETCH_HEAD cannot serve this
# role: a failed `git fetch` still recreates it, so its mtime tracks the last
# fetch ATTEMPT and the offline check below would always read 0d and never fail.
STAMP="$MIRROR/.git/advisory-freshness-last-sync"

# Portable mtime: BSD stat (macOS) and GNU stat (Linux) disagree on flags.
mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null; }

days_since() { echo $(( ( $(date +%s) - $1 ) / 86400 )); }

if [ ! -d "$MIRROR/.git" ]; then
  mkdir -p "$(dirname "$MIRROR")"
  git clone --quiet https://github.com/mirego/elixir-security-advisories.git "$MIRROR" \
    || fail "could not clone advisory mirror to $MIRROR"
fi

# 1. Modifications to TRACKED files are the exact condition that silently kills
# mix_audit's rebase. Untracked paths (a stray .hex-docs/ cache, editor files)
# do not block a rebase, so they must not fail this gate.
if [ -n "$(git -C "$MIRROR" status --porcelain --untracked-files=no)" ]; then
  echo "advisory-freshness: the advisory clone has modified tracked files:" >&2
  git -C "$MIRROR" status --short --untracked-files=no >&2
  fail "this blocks mix_audit's 'git pull --rebase' (exit 128) and freezes the database.
  The clone is generated data -- never hand-edit it. Report the upstream defect instead:
    https://github.com/mirego/elixir-security-advisories
  Recover with: git -C \"$MIRROR\" checkout -- ."
fi

# 2. Reachable upstream is the strong check: pull, then prove we are AT the tip.
# An unreachable upstream is not automatically a failure -- offline work is
# legitimate -- but it downgrades us to the recency check in step 3.
if git -C "$MIRROR" fetch --quiet origin main 2>/dev/null; then
  git -C "$MIRROR" pull --rebase --quiet origin main \
    || fail "'git pull --rebase' failed in $MIRROR -- mix_audit would swallow this and audit a stale copy"

  local_head="$(git -C "$MIRROR" rev-parse HEAD)"
  upstream_head="$(git -C "$MIRROR" rev-parse FETCH_HEAD)"
  [ "$local_head" = "$upstream_head" ] \
    || fail "clone is not at upstream tip after a successful pull (local ${local_head:0:7}, origin ${upstream_head:0:7})"

  head_age=$(days_since "$(git -C "$MIRROR" log -1 --format=%ct)")
  [ "$head_age" -le "$ABANDONED_DAYS" ] \
    || fail "upstream's newest advisory commit is ${head_age}d old (limit ${ABANDONED_DAYS}d) -- the importer itself may be dead"

  date +%s > "$STAMP"
  echo "advisory-freshness: OK - at upstream tip $(git -C "$MIRROR" log -1 --format='%h %cs') (clean)"
  exit 0
fi

# 3. Offline. Fall back to how long ago we last PROVED we were at upstream tip.
# That is the thing we actually control -- unlike upstream's commit cadence.
[ -f "$STAMP" ] || fail "cannot reach upstream and no verified sync has ever been recorded -- cannot establish freshness.
  Run this once with network access to establish a baseline."

sync_age=$(days_since "$(cat "$STAMP")")
[ "$sync_age" -le "$MAX_OFFLINE_DAYS" ] \
  || fail "cannot reach upstream and the last successful sync was ${sync_age}d ago (limit ${MAX_OFFLINE_DAYS}d) -- auditing against a copy of unknown currency"

echo "advisory-freshness: OK - upstream unreachable, last synced ${sync_age}d ago, $(git -C "$MIRROR" log -1 --format='%h %cs') (clean)"
