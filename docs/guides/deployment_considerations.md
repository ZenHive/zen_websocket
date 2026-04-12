# Deployment Considerations for Trading Applications

## Overview

This guide is **educational, not prescriptive**. The right deployment shape for a ZenWebsocket-based trading application depends on your strategy, your exchange, your latency budget, and your operational constraints. None of those are library concerns — but they are unavoidable context for running the library well in production.

The goal here is to help you ask the right questions and to make the trade-offs visible. If you find yourself looking for a single "best" answer, re-read the section title: these are *considerations*.

For code-level tuning (timeouts, retry, buffer sizes), see [Performance Tuning](performance_tuning.md). For reconnection diagnostics, see [Troubleshooting Reconnection](troubleshooting_reconnection.md). For supervision topology, see [Supervision Strategy](../supervision_strategy.md).

---

## Latency: Where Microseconds Matter

Network latency between your application and the exchange is dominated by physical distance, not code. No amount of BEAM tuning recovers the ~40ms round-trip between Frankfurt and Tokyo.

### When latency is load-bearing

| Strategy type | Typical sensitivity |
|---------------|---------------------|
| Market making, passive quoting | High — stale quotes = adverse fills |
| Arbitrage (cross-exchange) | High — the slower side loses |
| Aggressive taker flow | High — front-running risk |
| Trend-following, swing | Low — seconds don't matter |
| Analytics, backtesting, research | Negligible |
| Discretionary / manual trading | Negligible |

If you're in the bottom three rows, most of this section is academic — deploy wherever is operationally convenient and move on.

### Orders of magnitude

Rough ranges for round-trip WebSocket message latency (propagation + TLS + exchange processing):

- Same data center / colocation: sub-millisecond to low single-digit ms
- Same metro region (e.g., AWS Frankfurt → Deribit Frankfurt): typically a few ms
- Same continent, different provider: tens of ms
- Cross-continent: 50–300+ ms
- Via consumer ISP / residential: add highly variable jitter

These are ballparks. Measure your actual path — don't plan against rules of thumb.

### Questions to ask yourself

- What is my strategy's actual latency sensitivity, expressed as a cost? ("Every 10ms of added latency costs me X bps on fills.")
- Do I have evidence that latency is the binding constraint, or am I optimizing prematurely?
- Is my latency variability (p99 − p50) a bigger problem than my median latency?
- Am I willing to accept the operational cost (colocation contracts, harder deploys, limited tooling) of the lowest-latency option?

---

## Geographic Proximity

Most crypto exchanges publish their primary matching-engine region. Some publish multiple access points; a few offer colocation. This determines what "close" even means.

### Finding out where the exchange is

- Check the exchange's API documentation for endpoint regions or recommended access points.
- Ask support directly — particularly for institutional programs.
- Measure: from a candidate deployment region, run a simple latency probe (e.g., a ping-pong WebSocket round-trip) for a representative time window that includes both quiet and busy market hours.
- Look for published "colocation" or "direct connectivity" programs — these exist for some venues and are gated by volume.

### Deployment region heuristics

A pragmatic ranking, best → worst, when you care about latency:

1. **Exchange-provided colocation** — cross-connect in the same data center as the matching engine. Rare, expensive, contract-gated.
2. **Cloud region in the same metro** — e.g., AWS `eu-central-1` for a Frankfurt exchange. Usually the sweet spot for small-to-mid-size operators.
3. **Cloud region on the same continent** — acceptable for most strategies; tens of ms of added latency.
4. **Anywhere else, bare-metal with a good ISP** — wide variance.
5. **Residential / office network** — fine for research, unacceptable for live quoting.

The marginal improvement from step 3 → step 2 is often ~20–100ms. From 2 → 1 is typically single-digit ms at much higher cost. Know which gap is actually worth closing.

### Questions to ask yourself

- Where does my exchange's matching engine actually live?
- What is the cheapest deployment option that gets me within my latency budget?
- Do I need multi-region redundancy, or would a single well-placed region serve me better?
- If the exchange adds a new region (e.g., an Asia endpoint), is my architecture able to take advantage without a rewrite?

---

## Connection Architecture Choices

ZenWebsocket supports a range of topologies. None is universally correct.

### Patterns

| Pattern | When to reach for it |
|---------|---------------------|
| Single unsupervised `Client.connect/2` | Scripts, experiments, low-stakes integrations |
| Single supervised client (adapter GenServer) | Production bot with one account, one venue |
| `ClientSupervisor` pool | Multiple accounts or multiple markets; parallelize subscriptions |
| One client per account | Hard isolation: an error on account A must not affect account B |
| One client per subscription group | Large subscription counts; shard to respect exchange limits |
| Custom discovery (pg / Horde / :global) | Multi-node distribution, cluster-wide load balancing |

### Single vs pooled clients

A single WebSocket connection is simpler to reason about, simpler to monitor, and — for most retail-scale strategies — sufficient. Exchanges typically allow hundreds of subscriptions per connection.

Reach for a pool when:

- You hit a per-connection subscription limit.
- You want to isolate blast radius per account or per market.
- You want to parallelize message processing across BEAM schedulers.
- You need independent rate-limit buckets per account.

The pool adds operational complexity: more lifecycle events to monitor, more state to reconcile after network partitions. Don't pool for its own sake.

### One client per account

Exchanges commonly scope authentication, rate limits, and order routing to the account. One client per account gives you:

- Clean rate-limit accounting (one bucket per connection).
- Authentication failures that don't cascade.
- Cancel-on-disconnect semantics that affect only one account's orders.

The trade-off is N times the heartbeat and connection overhead. For small N (1–5 accounts) this is negligible.

### Questions to ask yourself

- How many accounts and markets does this process actually need to serve?
- What is the isolation boundary I care about — per-account, per-market, per-strategy?
- Do I need cross-node coordination (multi-BEAM distribution), or will a single node plus a warm standby suffice?
- If a connection drops, what is the minimum scope of work that needs to restart?

---

## Monitoring in Production

You cannot operate what you cannot see. ZenWebsocket emits telemetry; use it.

### Signals worth watching

| Signal | Why it matters |
|--------|---------------|
| Reconnect frequency | Spikes indicate network or exchange-side trouble |
| Time since last frame received | Silent-drop detection (heartbeat catches most but not all) |
| Heartbeat health | Exchange is still talking to you |
| Request round-trip latency (p50, p99) | Your actual experienced latency, not a ping-pong estimate |
| Subscription count vs expected | Detect subscription drift after reconnect |
| Rate-limit rejections | You're hitting exchange-imposed caps |
| Process memory, mailbox length | BEAM-side back-pressure warning signs |

See [Performance Tuning](performance_tuning.md) for the latency-specific tooling and the `get_latency_stats/1` / `get_heartbeat_health/1` APIs.

### Alerting

Alert thresholds are strategy-specific. Some suggestions as starting points, not rules:

- Reconnect rate above your historical p95 sustained for > 5 minutes.
- No frames received for > 2 × `heartbeat_interval`.
- p99 round-trip latency > 3 × your historical median, sustained.
- Subscription count < expected for > 30 seconds after a reconnect event.

Tune these after you have historical baselines. Alerting on "every reconnect" will burn you out fast — transient reconnects are normal.

### Log hygiene

- Keep connection-level events at `info`, not `debug`, so you see them in production.
- Redact credentials from logs. ZenWebsocket already redacts header values in `inspect/1` output (see `CHANGELOG.md`), but your own logging is your responsibility.
- Use structured logging (`:logger` with metadata) — you'll thank yourself when grepping.

### Questions to ask yourself

- What is my normal baseline for reconnects per hour? (If you don't know, you can't detect abnormality.)
- Do I have visibility into *why* a reconnect happened (network vs protocol vs auth)?
- If the exchange silently stops sending data, how long until I notice?
- Are my alerts actionable, or do they fire into the void at 3am?

---

## Resilience Considerations

Reconnection is not just about re-establishing a TCP connection — it is about re-establishing a *trading state*.

### The cancel-on-disconnect interaction

Many exchanges support "cancel-on-disconnect" (CoD) as an account-level setting. When enabled, your open orders are cancelled if your WebSocket drops. Interactions:

- CoD protects you from stale quotes if your process dies.
- CoD means every transient reconnect creates a burst of cancellations and re-placements, which has real cost (rate limits, fee tier impact, market impact on thin books).
- CoD is often scoped to the *connection*, not the account — reconnecting with a new session may or may not clear the cancellation, depending on the venue.

There is no right answer. Operators running into a cancel storm during a noisy network window should consider either tightening reconnection (to fail over faster) or disabling CoD and handling cleanup in-process. Both are defensible.

### Restart strategies

- `ClientSupervisor` with a bounded restart intensity catches the common case: the client crashes, supervisor restarts it, subscriptions restore.
- If your strategy has trading state (open orders, positions) that needs reconciling after restart, that logic belongs in *your* adapter or GenServer, not in the client. The client reconnects the transport; only you know what the business-level recovery means.
- Consider a "cold start" mode on boot: before placing any orders, pull current open orders and positions from REST, reconcile, then start streaming. This catches the case where you restart after an uncontrolled shutdown.

### State restoration semantics

ZenWebsocket restores subscriptions across reconnect by default (`restore_subscriptions: true`). It does *not* know about:

- Pending orders you sent but never got an ack for.
- Private channel authentication state (your adapter typically re-authenticates).
- Exchange-specific session cookies or sequence numbers (venue-dependent).

See [Troubleshooting Reconnection](troubleshooting_reconnection.md) for details on what is and isn't preserved.

### Questions to ask yourself

- If my process dies mid-order-placement, do I know what happened to that order?
- Is cancel-on-disconnect on, and do I want it on given my reconnect frequency?
- When I reconnect, how do I reconcile local state vs exchange state?
- Have I actually tested a full process restart against the live (or testnet) venue?

---

## Deployment Checklist — Questions, Not Answers

Work through these before going live. If you can't answer one, that's the item to investigate first.

**Placement**

- [ ] Where is the exchange's matching engine, and where am I deploying?
- [ ] What is my measured p50/p99 round-trip latency to the exchange from this location?
- [ ] Is that latency good enough for my strategy, with margin?

**Architecture**

- [ ] How many connections do I need, and why that number (not more, not fewer)?
- [ ] What is my isolation boundary — per account, per market, per strategy?
- [ ] Am I using a pool, and if so, what am I getting from it that a single client wouldn't give me?

**Reliability**

- [ ] What is my reconnection policy, and does it match the exchange's expectations?
- [ ] Is cancel-on-disconnect enabled? Do I know what that costs me during a reconnect burst?
- [ ] What happens to my open orders / positions if this process dies right now?

**Observability**

- [ ] Can I see reconnect rate, heartbeat health, and latency percentiles in production?
- [ ] Do I have alerts tied to meaningful business thresholds, not just technical ones?
- [ ] Are my logs structured and scrubbed of credentials?

**Operational**

- [ ] Do I have a tested deployment procedure — including a rollback — that I can execute under pressure?
- [ ] Is there a warm standby, or will downtime last as long as it takes me to notice and respond?
- [ ] Who gets paged, and with what runbook, when the market is moving at 3am?

---

## See Also

- [Performance Tuning](performance_tuning.md) — timeout, retry, and buffer configuration
- [Building Adapters](building_adapters.md) — exchange-specific adapter patterns
- [Troubleshooting Reconnection](troubleshooting_reconnection.md) — diagnostic flows for connection issues
- [Supervision Strategy](../supervision_strategy.md) — OTP supervision topology choices
