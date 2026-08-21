# Post-Merge Audit: 4c6ddb8

**Date:** 2026-08-21
**Auditor:** post-merge audit agent (best-effort hygiene, fix-forward only)
**Range end / marker:** `4c6ddb8` — roadmap: task 9 -> in_progress

## Range reviewed

| Task | Delivery and review commits | Surface |
|------|-----------------------------|---------|
| 6 | `adaa6de`, `a9fd63c`, `c4e2819` | Failure-capable network tests, explicit integration/external/local-network tags, coverage gate |
| 2 | `b9d2559`, `a227a75`, `9a41ce7` | Client/Gun reconnect ownership, retry state, caller exits, supervisor child discovery |
| 1 | `4d4c579`, `1d13f0d` | JSON-RPC positional-list parameter typing and examples |
| 8 | `307a2bc` | Reach layering, standalone registry docs, package-content policy |
| 7 | `8b1b22d`, `f61c791` | Public API, commands, architecture, supervision, and version documentation |
| 4 | `453d043`, `a90639d` | Deribit errors, subscription confirmation state, recorder shutdown flush, heartbeat state |

Roadmap-only commits in the supplied range were checked for continuity and left unchanged.

## What I reviewed

- Read the landed source, tests, API metadata, and documentation for dead paths,
  stale contracts, naming drift, debug output, hidden test outcomes, and project
  convention violations.
- Confirmed the reconnect changes keep Gun ownership in `Client`, reject stale
  timer messages, return startup failures to callers, and filter supervisor
  child sentinels.
- Confirmed subscription state changes are driven by outbound operations and
  JSON-RPC confirmations/errors rather than market-data ticks. Deribit auth and
  subscription helpers now reject JSON-RPC error bodies.
- Confirmed the recorder flushes buffered entries on abnormal linked-owner exit
  and the JSON-RPC list-params widening is reflected in tests and examples.
- No leftover `IO.inspect`/`dbg`, no new skipped tests, and no tests that accept
  every outcome were found in the landed additions.
- No reviewer rejections were recorded, so there is no false-rejection note.

## Findings

| # | Category | Description | Resolution |
|---|----------|-------------|------------|
| 1 | changelog-gap | The notable reconnect, Deribit, subscription, recorder, heartbeat, and JSON-RPC contract changes were absent from `[Unreleased]` | **fixed** |
| 2 | stale-spec | `DeribitGenServerAdapter.send_request/3` documented only `:not_connected` and typed error reasons as atoms although transport errors are arbitrary terms | **fixed** |
| 3 | stale-api-metadata | `SubscriptionManager.handle_message/2` discovery metadata still described inbound confirmations only, omitting outbound requests and error cleanup | **fixed** |
| 4 | convention | Touched callback helpers carried bare `TODO:` labels for permanent catch rationale rather than deferred work | **fixed** |
| 5 | file-hygiene | Both touched guide files ended without a final newline | **fixed** |

## What I fixed

- Added concise `[Unreleased]` notes for the public typing change and landed
  runtime fixes.
- Aligned the Deribit GenServer adapter's `send_request/3` docs/spec with its
  actual error surface.
- Updated SubscriptionManager moduledoc, function docs, and Descripex metadata
  to describe request/confirmation/error tracking.
- Reworded two permanent callback safety comments so they are not false TODOs.
- Added final newlines to `docs/gun_integration.md` and
  `docs/supervision_strategy.md`.

## Discoveries filed

None. The findings were bounded hygiene fixes and did not justify follow-up
roadmap work.

## Cold check

Command: `mix deps.get` then `mix check.dispatch` in the intentionally cold
worktree — **passed** after removing the harness-injected, explicitly ephemeral
`AGENTS.md` prefix. The cold invocation compiled dependencies and built the
Dialyzer PLT; its only red step was that prefix failing `agents.check`. The final
check passed with 458 tests, 0 failures, 144 excluded, 73.38% coverage against
the 58% threshold, Dialyzer accepted, and `AGENTS.md` current.

After the final API-metadata edit, focused formatting and
`mix compile --warnings-as-errors` also passed.

## Result

Five hygiene findings, all fixed forward. No behavior was reverted or unmerged,
no roadmap status was edited, and no follow-up task was filed.
