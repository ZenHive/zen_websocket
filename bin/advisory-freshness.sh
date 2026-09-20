#!/usr/bin/env bash
# Prove the exact mirror consumed by MixAudit.Repo equals the live upstream tip.
# mix_audit ignores its own git sync exit status, so this gate must fail closed.
set -euo pipefail

MIRROR="$HOME/.local/share/elixir-security-advisories-mirego"
UPSTREAM="https://github.com/mirego/elixir-security-advisories.git"
ABANDONED_DAYS=180

fail() { echo "advisory-freshness: FAIL - $*" >&2; exit 1; }

if [ ! -d "$MIRROR/.git" ]; then
  mkdir -p "$(dirname "$MIRROR")"
  git clone --quiet "$UPSTREAM" "$MIRROR" \
    || fail "could not clone advisory mirror to $MIRROR"
fi

[ "$(git -C "$MIRROR" remote get-url origin)" = "$UPSTREAM" ] \
  || fail "mirror origin is not the provider-owned upstream"

if [ -n "$(git -C "$MIRROR" status --porcelain --untracked-files=no)" ]; then
  git -C "$MIRROR" status --short --untracked-files=no >&2
  fail "advisory mirror has modified tracked files; mix_audit cannot synchronize it"
fi

# A previous successful sync cannot prove freshness in this invocation.
git -C "$MIRROR" fetch --quiet origin main \
  || fail "cannot reach upstream; freshness was not proven in this invocation"
git -C "$MIRROR" merge --ff-only --quiet FETCH_HEAD \
  || fail "mirror cannot fast-forward to upstream"

local_head="$(git -C "$MIRROR" rev-parse HEAD)"
upstream_head="$(git -C "$MIRROR" rev-parse FETCH_HEAD)"
[ "$local_head" = "$upstream_head" ] \
  || fail "mirror is not at upstream tip"

head_age=$(( ( $(date +%s) - $(git -C "$MIRROR" log -1 --format=%ct) ) / 86400 ))
[ "$head_age" -le "$ABANDONED_DAYS" ] \
  || fail "upstream's newest advisory commit is ${head_age}d old (limit ${ABANDONED_DAYS}d)"

echo "advisory-freshness: OK - at upstream tip $(git -C "$MIRROR" log -1 --format='%h %cs') (clean)"
