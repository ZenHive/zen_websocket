<!-- Auto-generated from CLAUDE.md by claude-marketplace/scripts/sync-agents-md.sh — do not edit manually -->

# CLAUDE.md

<!-- @-import: ~/.claude/includes/verification-policy.md -->
## Verification scope — focused runs, full post-merge QA

This is the canonical policy for **when** checks run. Project command catalogs describe **how** to run them; an alias name such as `precommit` or `check.dispatch` does not require its execution. Apply this policy to implementers, reviewers, orchestrators and hooks. Explicit operator requests and concrete task acceptance criteria can require additional checks.

| Work / role | Required verification |
|---|---|
| Docs, roadmap, comments, text-only changes | Validate the changed artifact (for example rmap validation or AGENTS generation); no code suite, coverage or analyzers. |
| Implementation | Format changed code, compile where relevant, and add/run focused tests for the changed behavior and regression. |
| Reviewer | Independently assess the diff and acceptance criteria; run focused checks for affected behavior and relevant integration boundaries. The reviewer remains the acceptance gate. |
| Post-merge audit + QA | On the landed revision, run the full project suite, coverage and applicable analyzers: Dialyzer, Reach, Sobelow, Credo, Doctor, clone detection and language-specific equivalents. Review the integrated surface against roadmap intent and domain invariants. |

- **Commit, push, PR creation, reviewer handoff, branch switch, rebase, merge and `deps.get` are not by themselves reasons to run full QA.** Do not run full-project gates on every small change or every implementer/reviewer run. No project exception, including aave_sim.
- **Choose checks by changed behavior and risk.** Signing, money, authorization, crypto and external-provider changes still require their relevant security, boundary and live integration tests before acceptance. Missing credentials or failed checks are reported honestly, never converted into a green result. Preserve tests and thresholds; change when they run.
- **Broaden only for a named reason:** explicit request/acceptance criterion, or concrete evidence that focused checks cannot resolve a cross-module regression. State that reason and run the smallest additional check that resolves it. “To be safe” or an alias name is not a reason.
- **Coverage belongs to full QA.** Keep project thresholds (at least 80% standard / 95% critical unless a documented project baseline applies). Do not demand a whole-module coverage uplift before an unrelated edit. Add meaningful tests for the behavior being changed.
- **Inspect aliases before using them.** If `check.dispatch`, `precommit`, `ci`, a registered hint or an inherited hook bundles full tests/coverage/analyzers, use the explicit scoped commands for the run and report the configuration mismatch. Do not claim the alias became lightweight merely because the instructions changed.
- **Reuse evidence for the same revision and scope.** Capture command output once; do not rerun solely for readable logs or to repeat a passed check. A reviewer supplies independent judgment and relevant verification, not an automatic full-suite repetition.
- **Full QA is a separate, nonblocking post-merge audit responsibility.** Record revision/range, commands, results and missing checks. Failures produce visible findings and repair work; they do not retroactively unmerge or become a blanket next-wave/deployment gate. If automatic QA is not configured or has not run, say so; never infer success from the existence of this policy.

Maintain this policy in `~/.claude/includes/verification-policy.md`. Import it from project `CLAUDE.md`; regenerate `AGENTS.md` with `claude-marketplace/scripts/sync-agents-md.sh`. Keep scheduling rules here, project-specific commands and justified risk checks in the project. Do not duplicate the policy in project prose.


<!-- @-import: ~/.claude/includes/critical-rules.md -->
## Answer in short text

Short, pointed text — explanation, proposal, pushback, summary alike. Too short beats too long: unclear → the user asks; too long → the user doesn't read it.

## Be a real partner, not a yes-sayer

- Challenge what seems wrong, risky, or suboptimal. Not every request is a good idea.
- Flawed approach → "I'd push back because…". Better alternative → present it with reasoning.
- Scope too big *or too small* → flag it.
- Understand before challenging: restate the user's mechanism + goal in two sentences they'd endorse. Can't → ask, don't challenge.
- Partial understanding → questions only. "Seems wrong" without naming what you understood is noise.
- "Not how software is normally built" is not an objection.
- Direct, not combative. Make the case once.
- Made your case and the user still wants it → commit fully. Pushback ≠ blocking.

### Think As an AI, Not Only As a Developer

| Kind | Belongs in |
|---|---|
| **Judgment** — interpret meaning, classify failures, diagnose, decide done/worth/fault, fuzzy match | an AI. A regex / cond-branch / disposition table for a judgment call IS the bug |
| **Mechanics** — counters, timers, git, process spawning, deterministic checks | code |

Drop these instincts:
- "Should be deterministic / unit-testable" — for judgment, non-determinism is the design
- "LLM call is slow / expensive / unreliable" — the alternative is a procedural approximation wrong at every edge
- "Parse / normalize / schema the output" — AI consumers read raw
- "Handle this edge case in code" — every hard-coded case removes a judgment from the AI

Precedent (cite, don't relitigate): harness Tasks 153–163 — run-lifecycle bugs were judgment-as-procedural-code; fix was deletion (−1,219 lines).

## No engagement farming — the turn ends when the work does

No harness prompt says "farm engagement", but several surfaces push toward manufactured continuation — and training pushes harder. Named here because the failure mode is not noticing.

Never, unasked:
- **Closing offers.** "Want me to also…?", "Should I go ahead and…?", "Let me know if…". Finished work ends with the result. A real blocker is a statement, not an offer.
- **Assessment, not affect.** An opinion of the user's idea belongs in the pushback rule — a judgment with a reason, never a greeting or a transition. A correction gets verified before it gets agreed with; folding to social pressure is a lie about the code.
- **Padding for substance.** Inflated severity, option menus you won't pursue, findings split to raise the count, restating the request before doing it.
- **A question in place of a derivable decision.** See `response-conventions.md` § Derive Before You Ask.
- **Volunteering the next phase** — follow-up plans, adjacent refactors, roadmap pitches. Discoveries go to `rmap new`, not into chat as a proposal.
- **Proactive artifacts / diagrams / dataviz.** Tool text calling proactive publishing "fine" is a default, not a mandate. Publish when asked, or when the artifact *is* the deliverable.
- **Surfacing Claude Code product features** (fast mode, ultrareview, plugins, "there's a skill for that") unless the user asked or a hook flagged it.
- **Artificial checkpointing.** Three things asked, one delivered, "weiter?". Authorized work runs to the end of the scope in one turn. Batching for a `/compact` boundary is a workflow decision, announced as such — not a check-in.
- **Announcing instead of doing.** "Lass mich das mal prüfen…" as the last line of a turn. The tools are in this turn. Use them, then report.
- **Teasers.** "Ich habe da etwas Beunruhigendes gefunden…" before naming it. Finding first, context after.
- **A completion is a fact, stated flat.** Emoji outside a diff, never.
- **Hedged non-answers** force a second turn to get the first answer. Name the dependency *and* the pick.
- **Deferring what fits in this turn** to a "nächster Schritt". Later only means blocked, out of scope, or genuinely too large.

**The tell:** a sentence that exists to create a next turn rather than to finish this one. Delete it. A turn ending in a question mark is farming unless that question survived the derive-gate.

Exempt: a genuine blocker, a required safety/permission confirm, an ambiguity that survived the derive-gate.

## Surface the override — don't decide silently

Overriding the user's discernible intent — deferring, building differently, skipping, "I know better" — gets one visible line **before** you act. Never act silently and rationalize after.

- Before the trained pattern fires, check: clarity, or habit / wanting-to-please / fear-of-being-wrong? Only clarity earns a silent decision.
- Surface ≠ block: "doing X instead of Y because Z — say if wrong", then proceed. Don't gate on a question.
- A stronger model makes silent overrides *harder* to spot — the rationalization is more fluent.

## Stack is chosen per idea — never by default

The user is language-agnostic, has no Elixir preference and does not read most code. "The user's repos are Elixir" is never a reason.

**Assume web, desktop and mobile will be wanted** unless the user explicitly rules them out. Never pick a stack that silently forecloses a platform.

Decide in this order:
1. **Platforms → UI stack.** Multi-platform → TypeScript (React + Expo + Tauri/Electron) or Flutter. Elixir/LiveView only for explicitly web-only.
2. **Official SDKs.** Use maintained official libraries (ccxt, viem, alloy, go-ethereum, protocol SDKs) in their language. Never port them.
3. **Known over own.** Product code sits directly on libraries AI agents know from training. Every library the user would own needs explicit approval, with the reason nothing known solves it stated in the task.
4. **Backend by main workload:**
   - multi-platform app → TypeScript end to end (chain via viem, exchanges via ccxt)
   - many long-lived stateful connections → Elixir
   - standalone integration service / worker with official SDKs in Go → Go
   - bounded core: EVM simulation (revm), heavy compute, Tauri backend → Rust
   - research / quant / ML → Python, not as default for long-running services
   - one backend language per app; a second only for a bounded core
5. **Maintenance cost.** Every library, package and publish is a permanent obligation.

Existing Elixir apps keep their backend; new clients (mobile/desktop) attach via API (e.g. Ash JSON API) in the UI stack of rule 1. No rewrite without an oracle.

State the stack and the deciding criterion. A Hex publish as "distribution bet" (`portfolio-strategy.md`) is not approval.

Evidence (2026-09 audit): 21 Hex packages, no external dependents, ~99 releases in 90 days; ~62 in `onchain-stack` + `mpp`, which reimplement alloy/revm/viem and the official MPP SDKs. `bourse` (113k LOC) duplicates `ccxt` (official Rust + Go + TS for all 11 venues). LiveView Native is still pre-1.0 (0.4.0-rc.1, 2026-03), Android unfinished, online-only.

## Never start the Phoenix server

Always already running. Never `mix phx.server`. Assume localhost:4000. To verify behavior, ask the user to check the browser.

## Always write tests

Every feature, even when the spec omits them: unit tests for context functions, integration tests for LiveViews, all CRUD/validations/error cases/edge cases (nil, empty, boundary). No tests → not complete.

## Against an API, the provider-owned contract is the authority

Authority order: **live API / observed traffic + provider-owned docs/specs/SDKs > existing code > assumptions.** Third-party clients, aggregators, wrappers, reference impls (incl. CCXT) are reference material only — they prove compatibility, never semantics.

- Hit the live API FIRST, then mock only what you've already seen. A mock encodes your guess; it passes green while the real call 400s.
- Tidewave `project_eval` to explore → `@moduletag :integration` test to pin. Flunk on missing creds, never skip silently.
- Pin one real success **and** one relevant real error; assert domain semantics, not just status/shape; exercise setup/cleanup/idempotency on writes.
- Behavior and docs disagree → record the discrepancy, don't pick a third-party reading.
- Can't reach the API → say so and `flunk`. Never a mock that ratifies a guess.
- A green claim names the independent evaluator + durable evidence (harness run, CI URL, review artifact). Self-report is not verification.

## 🚨 LIVE E2E FIRST — A RECORDING IS NEVER AN ORACLE

**Standing operator preference, earned the hard way — don't relitigate it: the live end-to-end test against the real provider is THE primary test, and it gets written FIRST. Mocks, fixtures and recordings come afterwards, never instead, and never as the thing that grades correctness.**

Refines the section above for the case it doesn't cover: a recording captured from **real** traffic — not a guess, and still not an oracle.

*Reproducible* (same input → same output) is not *determinate* (has a settled truth value). A replay's passing is only conditionally true — conditional on an external fact it no longer checks. The live call is the determinate one: at any instant the provider has exactly one answer and you get it. **Change frequency is irrelevant** — never argue "the world only changes monthly, so replay is the stable layer."

The deciding asymmetry is the *kind* of failure, not the amount: live gives **loud, bounded false-REDs** (host down, rate limit, sandbox reset); replay gives **silent, unbounded false-GREENs** — once the provider changes, every replay stays green and is a lie from then on, precisely where it was meant to warn you. False green is the worse failure mode.

- A recording is a **regression detector on your own code** ("did our parsing change in this refactor?"), never a grader of external semantics.
- **Expiry does not create truth** — a freshness window bounds staleness; an unexpired recording is still only a claim about the past.
- Never downgrade a loud gate with real authority to a quiet one that can be falsely green. Its noise — rate budget, telling *unreachable* apart from *wrong* — is an engineering problem to solve at that gate.

## Verification scope and coverage

Follow `~/.claude/includes/verification-policy.md` for check scope and coverage timing. Write tests for changed behavior; full-project coverage is evaluated in post-merge audit + QA.

## 🚨 NEVER HIDE TEST FAILURES

A test that passes on every outcome is lying. Never `{:error, _} -> assert true`, never a catch-all `{:error, _} -> :ok`, never `IO.puts` + `assert true`.

```elixir
case result do
  {:ok, data} -> assert is_map(data)
  {:error, :insufficient_balance} -> :ok          # this specific error is expected
  {:error, other} -> flunk("Unexpected error: #{inspect(other)}")
end
```

- Don't know what error to expect → don't write the test yet. Explore via Tidewave, then assert.
- Integration tests: never `:skip` on missing credentials. Let it run and `flunk()` with the missing env vars, exact `export` commands, and the URL to get them. "0 failures" from 0 tests is a lie.

## Fix hook-flagged issues on files you touch

Hook fires → fix → re-run → stage. No planning around it, no asking, no discussing whether to. Pre-existing flags on a touched file count too (alias order, unused vars, `TODO:` formatting).

- Scope is only the files your change touched, not the project.
- Generated files → fix the generator.
- Never move the fix to ROADMAP or a follow-up. This commit.
- Don't re-run a check the hook just ran on the same files. Check scope and rerun triggers are defined in `verification-policy.md`; lifecycle events alone do not trigger full QA.

## Read to the answer — don't use the runner as an oracle

Reason to the fix by reading code; run once to CONFIRM, not to DISCOVER.

- Read the code path before the test that exercises it.
- Treat a failure as a SURVEY: enumerate every plausible cause from output + one read, fix in a batch, run once.
- Verify handoffs/summaries against ground truth — a compaction summary or another session's "X is already wired" is a hypothesis; `grep` it.
- Flaky terminal → sequential and simple: one command → file → Read. No parallel batches of dependent calls.

## Flaky tests & test-run token economy

- 1–2 failures out of hundreds, in a file your diff didn't touch → flaky **hypothesis**. Re-run that test alone (`mix test.json <file>:<line>` or `--failed`). Passes alone → proceed. One isolated re-run is the whole investigation.
- NEVER `Process.sleep` to fix a flake. Use `assert_receive`/`refute_receive`, `Process.monitor` + `{:DOWN, …}`, `start_supervised!`, or poll-until-condition.
- Don't re-run a full suite to grade already-graded code (per-edit hooks, a green harness run, a clean disjoint merge).
- Bound output: `--cover` dumps hundreds of KB. Always `--output /tmp/cov.json` + `jq`. Triage with `--max-failures 1` / `--failed` / one `file:line`.

## No pseudo-rigorous hedging

You have no consumer telemetry, no usage counts, no demand signal. Don't gate user-requested work behind evidence you cannot obtain. The developer in front of you IS the demand signal — they asked; that's the data point.

STOP if about to write:
- "Demand for X is unproven"
- "We should wait until…"
- "Is this widely needed?"
- "Only worth doing if a Nth+ case is imminent"
- "Bet on usage data before building"

**A legitimate "wait" names an external blocker with an unblock path** — a missing dep, an unreleased upstream, an unactivated market. **"Nobody has asked yet" is not a trigger.** Neither is "it's additive, cheap to add later."

Instead: name actual technical risks ("the macro grows more knobs than the duplication it removes"), cite concrete precedents, or score the task honestly low. Honest framing: *"I don't know if you'll use this 12 more times — that's your call."*

Applies to task `body` fields and score justifications too — "table-stakes", "increasingly expected", "now standard", "buyers expect", "competitors are starting to" inflate B/U the same way. Required: a concrete named reason, or an honest low score.

## Git Commit / Push / PR-Create — Allowed by Default

Commit, push, open PRs without asking when the task calls for it. Announce in one line, then act.

Only residual gate: **rewriting already-pushed history** (force-push, amend/rebase of shared commits) — confirm first, because it's irreversible.

### Stage path-scoped — the working tree is shared

- NEVER `git add -A` / `git add .` / `git commit -a`. Stage explicitly (`git add <path>`) or commit path-scoped (`git commit <path>`).
- Verify before every commit: `git diff --cached --name-only`. A path you didn't touch is someone else's.
- Pre-commit hook trips on a foreign file → path-scoped-stash only their paths (`git stash push -- <paths>`), commit yours, `git stash pop`, re-stage what was staged before. Never format or fix work that isn't yours to clear a hook.
- Untracked files you didn't create: leave them. No `-u` stash, no `add`.

## 🚨 NEVER BROADCAST AN UNPATCHED VULNERABILITY IN A COMMITTED FILE

A committed file is a public file — and permanent in git history. Exploit-actionable detail (attack mechanism, trigger value, PoC, unpublished GHSA/CVE id) never goes into `roadmap/tasks.toml`, `ROADMAP.md`, `CHANGELOG.md`, code comments, or commit messages.

- **Open + undisclosed → out of git.** Track in a private draft GitHub Security Advisory (`gh api repos/<org>/<repo>/security-advisories -X POST`, draft; `vulnerabilities[]` needs ecosystem + package + `vulnerable_version_range`). One per issue, full detail there and only there.
- **Fixed AND advisory published → fine to reference.** The gate is both, not either.
- **Need to schedule the work?** File the rmap task with a sanitized body: `"harden Tempo fee-payer gas bounds — see private advisory <id>"`. Never the mechanism.
- **Embargo window:** commit messages and CHANGELOG describe the shape of the fix, not the hole.
- **Inbound reports hide in one place:** privately-reported vulns appear ONLY under Security → Advisories (`gh api repos/<org>/<repo>/security-advisories`) — not Dependabot, not code/secret scanning, not the notifications inbox. Always query it; act on `triage` and `draft`.
- **Public ledgers carry only ✓ closed / 📋 tracked rows** plus a generic open-item count. Never an enumerated map of unpatched weaknesses.
- **On fix:** patch → release → publish the advisory naming the patched version, same day.
- Already committed = already leaked. Redact now and treat git history as compromised (rotate/patch), don't just stop going forward.

## Shell Safety

`rm` is permitted. Before an irreversible delete, glance at the target — no unexpanded `$VAR`, no wildcard catching more than you mean, not a path you didn't create. `git rm` for tracked files keeps the removal in the diff.

## 🚨 NEVER RUN DESTRUCTIVE DEPENDENCY COMMANDS

Never without explicit consent: `mix deps.clean` (incl. `--all`), `mix deps.unlock --all`, `rm -rf _build`, `rm -rf deps`, `mix clean`.

Instead: compile error → retry `mix compile` / `mix test`. Specific dep → `mix deps.compile <dep> --force`. Most "corrupt cache" issues are transient.

## 🚨 NEVER PIN A DEPENDENCY TO GIT OR PATH — RELEASE IT

A `github:` / `git:` / `path:` dependency in `mix.exs` (or the equivalent in `package.json`, `Cargo.toml`, `pyproject.toml`) is a rejection, not a solution. It applies to our own libraries above all: a library change needed by an app is a task in the **library's** repo, released through Hex (or the registry of its ecosystem) with a version bump, and then consumed as `{:lib, "~> x.y.z"}`. Pinning the app to a branch commit ships unreviewed library code through the app's review, freezes the app on a moving PR, and leaves a repo the operator has to remember to release later.

- **Implementer:** the fix belongs in the library → stop and report "blocked on a `<lib>` release: needs `<change>`". Do not open a PR against the library from inside the app run and pin its head. Do not vendor the code into the app either.
- **Reviewer:** a new `github:` / `git:` / `path:` dep on a package we maintain is a `reject` with that reason, regardless of how good the rest of the diff is. A new pin on a third-party package is a `reject` unless the task body names the pin and why no release exists.
- **Only exceptions:** `in_umbrella: true` inside one umbrella, and a pin the task body explicitly authorizes with the upstream release it waits for.
- **Precedent:** aave_sim task 148 pinned `bourse` to a branch head of its own open PR; the reviewer approved it, and the release still had not happened a week later.

## No scope-sequencing qualifiers in durable artifacts

Never write "X first", "starting with X", "initially", "for now", "MVP: X" into repo descriptions, READMEs, moduledocs, code/config comments, commit messages, or vision one-liners. They metastasize and become unremovable. Sequencing lives in the roadmap only (milestones, task bodies, `out_of_scope`). Elsewhere describe what the system IS: "Coverage: Robinhood Chain tokenized equities", not "starting with Robinhood Chain".

## Integrity and accuracy

- Never fabricate information, experience, metrics, timelines, or stats.
- Distinguish codebase observation / general knowledge / best practice / speculation.
- No false authority: no "we learned" without repo evidence, no "after X years in production".
- Uncertain → say so, give ranges over false precision, suggest a validation path.
- Trace sources: "Based on the code in file.ex…", "According to docs/FILE.md…", "Common practice in Elixir…".

## Research before asserting on niche technical claims

Outside reliable training coverage, research proactively — unasked. WebFetch when the canonical URL is known, WebSearch to find one. **Cite what you fetched.**

Research:
- **Wire formats / encodings** — RLP, ABI, SSZ, Protobuf, BLS, BIP-32/39/44, EIP-712, CBOR, ASN.1/DER. Never claim byte order, length-prefix, padding, or canonical form from memory.
- **Protocol details** — EIPs, RFCs, JSON-RPC shapes/error codes, opcode gas, exchange API quirks.
- **Niche / recent library APIs** — about to write `# probably something like`? Fetch the docs.
- **Cross-implementation edge cases** — check ≥2 reference impls; one impl's behavior can be a bug, agreement across two is the spec in practice.

Don't research: pure Elixir/OTP, stdlib, mainstream Phoenix/LiveView/Ecto/Ash, generic REST/HTTP/JSON/SQL/shell, anything in the codebase or an imported CLAUDE.md.

Fetch fails or is ambiguous → say so and lower confidence. Never fall back to "well, I think…" silently.

## No evasion — sit with the hard thing

Hitting a wall → silently moving to easier work is the failure. Stay with it; say "this is hard because X".

Don't use without explicit user approval:
- "let's move on to", "we can defer this", "skip this for now", "let's come back to this later", "let's table this"
- "to keep things simple, I'll skip", "for brevity, I won't", "that's out of scope", "not strictly necessary"
- "that should be enough", "the rest is straightforward", "I'll leave the rest as an exercise"
- "you might want to", "you could manually", "you'll need to handle"

- Blocked → name it: "blocked on X because Y. Options: A, B, C."
- Never a silent workaround. Tempted to add a fallback/nil-guard for missing data → should it come from upstream? Then stop and report.
- Must move on → leave a tracked TODO, not a silent gap.

<!-- @-import: ~/.claude/includes/elixir-security-adjudications.md -->
# Elixir Security Adjudications (host-specific)

Two settled, host-specific security verdicts that every fresh agent otherwise
re-derives from scratch. `@`-import this in any repo that declares `mix_audit`
or runs Sobelow, so it also flows into `AGENTS.md` for the cross-family
reviewers via `sync-agents-md.sh`.

## 🚨 ADJUDICATED: the cowlib / gun advisories are ALREADY DECIDED — do NOT re-investigate

**Read this before spending a single token on a `VULNERABLE!` line mentioning `gun`,
`cowlib`, `GHSA-w4f7-4cxr-rv3c`, or `EEF-CVE-2026-43966`/`-43969`.** This has been
adjudicated repeatedly by many sessions — local Claude instances, and every harness
implementer / reviewer / auditor that ran `mix deps.get` in a fresh worktree. Each one
found the same unbudgeted alarm and redid the same analysis. **The verdict is below.
Cite it; don't re-derive it.**

**Where the noise comes from — two independent pipelines, don't confuse them:**

| Source | Reports | Silenced by |
|---|---|---|
| **Hex core**, during `mix deps.get` / `deps.update` / `hex.audit` | OSV incl. the EEF-CVE program | `mix hex.config ignore_advisories "<ids>"` (global, `~/.hex`) or `HEX_IGNORE_ADVISORIES` (comma-separated env var, settable per dispatch) |
| **`mix_audit`**, during `mix deps.audit` | mirego's GHSA mirror | per-repo `.mix_audit_ignore` (the marketplace hook reads it via `--ignore-file`) |

Removing `mix_audit` does **not** silence the `mix deps.get` output — that is Hex, and
every fresh harness worktree runs `deps.get`. That is precisely why every dispatched
agent sees it.

**The verdict — cowlib reached only via `gun` as a WebSocket client (the
`zen_websocket` stack): not reachable.** Evidence is a call-graph fact, not a judgment
call:

| Advisory | Vulnerable function | Reachability |
|---|---|---|
| `EEF-CVE-2026-43966` (alias `GHSA-w4f7-4cxr-rv3c`, `CVE-2026-43966`) | `cow_http_struct_hd:escape_string/2` | **0 references** in `deps/gun/src/` |
| `EEF-CVE-2026-43969` | `cow_cookie:cookie/1` | only from `gun_cookies.erl` — gun's **opt-in** cookie store; `zen_websocket` never sets `cookie_store` (the string `cookie` does not appear in its `lib/`) |

**`EEF-CVE-2026-43971` (`cow_link:link/1`) is FIXED in cowlib 2.20.0 (2026-09-08)**
(EEF CNA: affected `>= 2.9.0 < 2.20.0`) and was removed from the global Hex ignore list
2026-09-24. If it reappears, the repo is on cowlib < 2.20.0: bump it, don't re-ignore it.
The other two are still reported against cowlib 2.20.0 / gun 2.6.0 (verified 2026-09-24,
`HEX_HOME=<empty> mix hex.audit` in bourse); no fixed release exists, so reachability is
the only available adjudication. The 43969 fix is upstream (`177953d` "Preliminary patch",
"Validate cookie domain/path") but unreleased. Re-check at the next cowlib release.
`hex.audit` in a repo without cowlib (e.g. harness) warns the two ignores "match no
advisory" — that is expected, not a sign they're resolved.

**The separate `gun 2.5.0` line is a mirror bug, already reported upstream.** gun's real
vulnerable range is `< 2.4.0`; gun 2.5.0 is patched. The mirego importer groups by
`ghsaId` alone, collapsing a two-package advisory into `packages/gun/…yml` carrying
**cowboy's** `< 2.16.0` range, so gun 2.5.0 matches a range that was never gun's. There
is no gun 2.16.x. Filed as **`mirego/elixir-security-advisories#8`** (issue + PR open);
`zen_websocket/.mix_audit_ignore` carries the full write-up and the removal condition.
That gun never calls `cow_http_struct_hd` at all corroborates it independently.

**🚨 `bandit` is NOT in this adjudication — it has a real fix.** `EEF-CVE-2026-74836`
(HIGH) and `EEF-CVE-2026-75484` on bandit 1.12.4 are genuine; **1.12.5 (2026-08-20) is
the fix**. Bump the dependency; never add a bandit id to an ignore list. Blanket-ignoring
"all the CVE noise" buries a HIGH — suppress **per id**, only after the reachability
argument above has been made for that specific id.

**What invalidates this verdict — re-adjudicate if any becomes true:** a repo takes
`cowboy` as a **runtime** (not `only: :test`) dependency; gun's `cookie_store` option is
enabled anywhere; gun is used as a general HTTP client with caller-supplied header
values; or a new cowlib advisory appears that is not one of the two ids above.

**Affected repos (cowlib in the lock as of 2026-09-24, all on 2.20.0):** `bourse`, `mpp`,
`zen_websocket`. The `onchain*` repos no longer lock cowlib. Suppression is inconsistent across them — most carry
`.mix_audit_ignore`, bourse uses an `--ignore-advisory-ids` alias in
`mix.exs`. Standardize on `.mix_audit_ignore` when you touch one.

**The meta-lesson this section encodes:** the analysis had in fact been done correctly —
it lived in `zen_websocket/mix.exs` and `.mix_audit_ignore`, where no other repo's agent
ever looks. A verdict that isn't written where the *next* agent reads it gets re-derived
forever. Adjudicate once, then put it in `CLAUDE.md` (which flows into `AGENTS.md` for
the cross-family reviewers) — not only in the repo that happened to notice.

## Suppressing Sobelow False Positives — Use `.sobelow-skips`, NOT Inline Comments

When the PostToolUse hook flags a Sobelow false positive (e.g. `Traversal.FileModule`
on an operator-supplied CLI path, not web input), the **inline `# sobelow_skip
["FindingType"]` comment does NOT suppress it** under this host's hook invocation —
verified on tapakly 2026-06: comments placed correctly above both the `def` (with
`@spec` between) and a bare `defp` still re-flagged at the same lines. The hook
honors only the **hash-based `.sobelow-skips` file**, read via `mix sobelow --skip`.

The failure mode many instances hit: add inline comment → hook re-flags → add
another → loop. Stop. The working mechanism:

1. **Confirm the finding is genuinely a false positive** (path is operator/CLI-derived
   or a fixed dir + content hash, never untrusted/web input). Real traversal risk → fix the code.
2. **Check the total outstanding count** — `mix sobelow --format compact`. `--mark-skip-all`
   marks *every* current finding as skipped, so it's only safe when the outstanding set
   IS exactly the false positives you intend to skip. Otherwise you'd silently bury a real one.
3. **Generate the skip file:** `mix sobelow --mark-skip-all` → writes `.sobelow-skips`
   (lines of `FindingType,file:line,HASH`).
4. **Verify suppression with the flag the hook uses:** `mix sobelow --skip --format compact`
   — a plain `mix sobelow` (no `--skip`) still prints them; that's expected, not a failure.
5. **Commit `.sobelow-skips`** alongside the code (it's not gitignored — it's the
   persisted project suppression record so CI / other devs don't re-flag).

**Line shifts INVALIDATE skips, and `--mark-skip-all` never prunes — regenerate, don't accumulate.**
Each entry pins `FindingType,file:line,HASH`, and the line number feeds the hash:
deleting or inserting lines *above* a suppressed finding re-reds the gate even though the
flagged code never changed. Re-running `--mark-skip-all` leaves the dead entry behind
forever — sobelow ≤0.14 appends a new generation; 0.15+ rewrites merged+deduped+sorted
(`--legacy-skips` restores append) but still keeps entries with no live finding
(observed ccxt_client 2026-07-22 under 0.14: 57 entries on file, 9 live findings —
48 stale). The cadence: whenever a skip-related
re-red appears (or an audit notices bloat), **regenerate wholesale** — confirm every
currently-outstanding finding (`mix sobelow --no-skip --format compact`) is a genuine
false positive per step 1, then `rm .sobelow-skips && mix sobelow --mark-skip-all`,
verify zero with `--skip`, commit. Never regenerate while an unconfirmed finding is
outstanding — that buries it.

Pairs with `critical-rules.md` § FIX HOOK-FLAGGED ISSUES: suppression IS the fix for a
documented false positive — but via the file, not a comment the hook ignores.

<!-- @-import: ~/.claude/includes/harness-guardrails.md -->
## Harness Guardrails (eager)

Always-on floor for repos that dispatch through harness. These rules fail by non-recognition — the moment they apply doesn't feel like a moment to look anything up — so they stay ambient. Everything else (loop, dispatch-vs-hand-build, verdict table, routing, landing mechanics, orchestrator loop) lives in the **`harness:harness-workflow` skill**: invoke it before planning, dispatching, reading a verdict or recovering a run. API surface: `harness:harness-driver`.

**🚨 Origin is the source of truth for what landed** — not a local `tasks.toml`, not an await return, not a transcript. Under auto-land the lander pushes from a detached worktree and `TargetSync` often skips your checkout (dirty tree, non-ff, self-host), so local status lags. Before concluding "didn't land": `git fetch origin <target>` and check `git log --oneline origin/<target>` for `task <id> -> done (shipped …)`. Misreading stale local status re-dispatches and **duplicate-lands shipped work**.

**🚨 Settle ≠ landed.** `state: :done, verdict: approve` means *queued to land*; the serialized lander rebases and pushes afterwards (under `:pr`, `done --shipped-in` waits for the PR merge). Don't gate the next wave on approval — confirm the land on origin.

**🚨 Never block on `dispatch-await*` for real runs.** The MCP idle timeout (Claude Code: 300 s) kills the call while the run keeps going. Arm one bounded background watcher that greps `$BASE..origin/<target>` (baseline is load-bearing — never the whole log) and has a deadline. Don't micromanage in-flight runs; `dispatch-status` is for diagnosing a run that isn't landing.

**🚨 Recover, don't redo — committed work is paid for.** Before any reset-to-`pending` + re-dispatch, check `git log --oneline origin/<target>..harness/<run-id>`. Commits present ⇒ recover:

| Retained `harness/<run-id>` with commits | Primitive |
|---|---|
| Approved, unlanded (land-cap, conflict, lander crash) | `dispatch-reland` — zero agent tokens |
| Good work, review-stage failure | `dispatch-rereview` |
| Implement-stage incomplete / `:failed` | `dispatch-resume_failed` (`escalate: true` to re-route) |
| Live `:held` run | `dispatch-resume` (question-held: `dispatch-steer` first) |
| No commits, no retained branch | reset → `pending` + `dispatch-task` — the only full redo |

Land conflict → repair worktree off `origin/<target>`, resolve, repoint the branch, `dispatch-reland`. Never hand-push to the target when a reland can land it.


<!--
  Selective-load (Opus 4.8): the eager floor is `critical-rules` (hard guardrails
  that must stay ambient) + `harness-workflow` (implement -> review -> land loop —
  zen_websocket is a registered harness dispatch target). Everything else is
  skill-on-demand: `elixir:ex-unit-json`, `elixir:dialyzer-json`,
  `elixir:zen-websocket`, `elixir:code-style`, `tasks:rmap`,
  `workflow:git-worktrees`. Re-add an `@`-import here only if Opus is observed
  failing on that surface.
-->

---

## Project Overview

**ZenWebsocket** is a robust WebSocket client library for Elixir, specifically designed for financial APIs (particularly Deribit cryptocurrency trading). Built on Gun transport with reconnection, heartbeat, rate limiting, and request/response correlation.

**Financial Development Principle**: Start simple, add complexity only when necessary based on real data.

## Project-Specific Commands

```bash
# Code Quality (use JSON output for AI-friendly results)
mix test.json                                  # Run tests (see logs/warnings)
mix test.json --quiet                          # Run tests (clean JSON only)
mix test.json --quiet --failed --first-failure # Iterate on failures
mix dialyzer.json --quiet                      # Type checking
mix credo --strict --format json               # Static analysis
mix security                                   # Sobelow security scan

# Testing (integration tests excluded by default)
mix test.json --quiet --summary-only   # Quick health check
mix test --include integration         # Include integration tests (MockWebSockServer / Gun)
mix test --include external_network    # Tests requiring internet (Deribit testnet, etc.)
mix zen_websocket.usage                # Export usage rules
mix zen_websocket.validate_usage       # Check Client API usage against the public surface
```

## Toolchain & check commands

Self-contained so it survives into `AGENTS.md` on regen — cross-family reviewers (codex / cursor / grok) read `AGENTS.md`, not the Claude skill set.

- **Dispatch check:** `mix check.dispatch` — format and compile only. Reviewers select focused behavior tests and risk-relevant live/security checks. It does not run the full suite, coverage, Dialyzer, Reach, Sobelow, Credo, Doctor, or clone detection.
- **Full post-merge QA:** `mix precommit.full` (alias `mix ci`). No GitHub Actions workflows run on push. Select implementation/review checks using the imported verification policy; the comprehensive alias is not a per-push requirement. `ci` / `precommit.full` do not depend on `check.dispatch`.
- `mix precommit.full` runs, in order: `compile --warnings-as-errors`, `format --check-formatted`, `credo --strict` (ignoring TODO/FIXME tags), `doctor --raise`, `ex_dna --max-clones 0` (zero-clone budget), `reach.check --arch --smells` (policy in `.reach.exs`), `sobelow --skip`, `deps.audit.gated`, `test.json --cover --cover-threshold 90 --exclude integration --include local_network` (`MIX_ENV=test`), `dialyzer` (forced `MIX_ENV=dev` — see below), `agents.check`.
- **`mix ex_dna --max-clones 0` is not a byte-identical-function detector.** The gate (and the same defaults on `ExDNA.Credo` during `mix credo`) is Type I + Type II with `literal_mode: :keep`, `min_mass: 30`, Type III off (`min_similarity: 1.0`). Comments add no mass. Cross-module comparison works; what it misses are fragments below 30 AST nodes (the shared callback wrapper was mass 22–26; the shared heartbeat `if` was mass 22) and above-threshold functions whose ASTs still differ after Type-II keep — `__MODULE__` vs a qualified alias, local vs remote call, reversed argument order (`build_client_struct/2` was mass 35–36 and still silent). Type II `--literal-mode abstract` also missed those three; Type III at 0.85 flagged unrelated descripex `api()` wrappers, not them. A green zero-clone run means nothing crossed *that* boundary, not that duplication is absent. See the comment on `"ex_dna --max-clones 0"` in `mix.exs`.
- **The coverage floor is a measured ratchet, not an aspiration.** 90 is core-library coverage measured 2026-08-21 (`mix test.json --cover --exclude integration --include local_network` after honoring `test_coverage: ignore_modules`), rounded down. The previous 58 measured the diluted suite because ex_unit_json 0.6.0 ignores regexes in that list. Raise it in lockstep with real core coverage; never pad it.
- **`mix test.json` (`ex_unit_json`) and `mix dialyzer.json` (`dialyzer_json`) emit JSON by design — this is NOT a build failure.** Parse the JSON for real failures; never flag the envelope itself. Plain `mix dialyzer` is the authoritative dialyzer check when the JSON encoder can't serialize a warning shape.
- **The gate's dialyzer step forces `MIX_ENV=dev`, not `:test`.** Under `:test`, the test-only mock-server stack (`cowboy`, `plug_cowboy`, `websock`, `x509`, `temp`, `stream_data`) joins this repo's `plt_add_deps: :apps_direct` analyzed set and produces false `unknown_function` warnings against the OOM-tuned PLT (see `defp dialyzer` in `mix.exs`). `preferred_envs` in `def cli` is ignored inside alias steps, so the dev override is an explicit `cmd env MIX_ENV=dev mix dialyzer`.
- **`reach.check --arch --smells` gates from `.reach.exs`** (`smells: [strict: true]`). Smell findings must be fixed for real, never added to an ignore list.
- **`deps.audit.gated` proves the local mix_audit advisory mirror is fresh (`bin/advisory-freshness.sh` in this repo) before running `mix deps.audit --ignore-file .mix_audit_ignore`.** `mix_audit` discards its own sync exit status (`mirego/mix_audit#61`), so a frozen mirror would otherwise report a false "No vulnerabilities found." The prover uses MixAudit.Repo's hardcoded clone path and clones it when absent; it requires live upstream access in each invocation and does not accept an offline sync timestamp. `.mix_audit_ignore` carries exactly one verified false positive (GHSA-w4f7-4cxr-rv3c on `gun`); do not add other advisory ids there — a real finding gets reported, never suppressed.
- **`agents.check` runs `bin/sync-agents-md.sh --check` from this repo.** It re-renders CLAUDE.md plus transitive `@`-imports and diffs `AGENTS.md`; a missing in-repo script fails the step instead of skipping. When canonical home imports are absent, the generator uses verbatim snapshots in `priv/agent-includes`; refresh those snapshots from the canonical includes when regenerating instructions.

## Documentation

Use the existing docs instead of re-explaining patterns from scratch:

- `README.md` for package overview and top-level discovery
- `AGENTS.md` for contributor workflow and verification expectations
- `docs/guides/building_adapters.md` for adapter patterns
- `docs/guides/performance_tuning.md` for telemetry and tuning
- `docs/guides/troubleshooting_reconnection.md` for reconnect diagnostics
- `docs/guides/deployment_considerations.md` for production deployment trade-offs

## Architecture

### Module Structure
```
lib/zen_websocket/
├── client.ex               # Main client interface (GenServer + public API)
├── client/                 # Nested as ZenWebsocket.Client.*
│   ├── call_facade.ex      # Client.CallFacade — process-down-safe GenServer.call + connect await
│   ├── callbacks.ex        # Client.Callbacks — handle_call/handle_info clause routing
│   ├── correlation.ex      # Client.Correlation — JSON-RPC response/timeout correlation
│   ├── connection.ex       # Client.Connection — Gun open, upgrade, attempt-identity timers
│   ├── frames.ex           # Client.Frames — WebSocket frame routing and dispatch
│   ├── reconnect.ex        # Client.Reconnect — explicit reconnect target and options
│   ├── recorder.ex         # Client.Recorder — session recorder lifecycle
│   ├── retry.ex            # Client.Retry — disconnect retry, backoff, stop-with-error
│   ├── retry_policy.ex     # Client.RetryPolicy — retry eligibility and error normalization
│   └── transport_errors.ex # Client.TransportErrors — Gun error/down logging and retry dispatch
├── client_supervisor.ex    # DynamicSupervisor for pooled connections
├── config.ex               # Configuration struct and validation
├── frame.ex                # WebSocket frame encoding/decoding
├── connection_registry.ex  # ETS-based connection tracking
├── reconnection.ex         # Exponential backoff retry logic
├── message_handler.ex      # Message parsing and routing
├── error_handler.ex        # Error categorization and recovery
├── json_rpc.ex             # JSON-RPC 2.0 protocol support
├── request_correlator.ex   # Request/response correlation
├── rate_limiter.ex         # API rate limit management
├── heartbeat_manager.ex    # Heartbeat lifecycle
├── heartbeat_interval.ex   # Shared interval-pong telemetry + state update
├── subscription_manager.ex # Subscription tracking and restoration
├── latency_stats.ex        # Latency percentile tracking
├── pool_router.ex          # Health-based pool routing
├── recorder.ex             # Session recording (pure functions)
├── recorder_server.ex      # Async file I/O for recording
├── debug.ex                # Conditional debug logging
├── safe_callback.ex        # Crash-safe lifecycle callback wrapper
├── testing.ex              # Consumer-facing test utilities
├── testing/
│   └── server.ex           # Mock WebSocket server used by Testing
├── helpers/
│   └── deribit.ex          # Deribit helper functions
└── examples/
    └── deribit_adapter.ex  # Deribit platform integration (plus other in-tree examples)
```

### Public API
```elixir
# Connection lifecycle
ZenWebsocket.Client.connect(url, opts)
ZenWebsocket.Client.send_message(client, message)
ZenWebsocket.Client.subscribe(client, channels)
ZenWebsocket.Client.get_state(client)
ZenWebsocket.Client.close(client)
ZenWebsocket.Client.reconnect(client)

# Monitoring
ZenWebsocket.Client.get_heartbeat_health(client)
ZenWebsocket.Client.get_state_metrics(client)
ZenWebsocket.Client.get_latency_stats(client)

# Public but @doc false — used internally by ClientSupervisor.start_client/2
ZenWebsocket.Client.build_client_struct(state, pid)
```

### Project Constraints
- Maximum 5 functions per module (new modules)
- Maximum 15 lines per function
- Direct Gun API usage - no wrapper layers
- Real API testing only - zero mocks

### Example Code Policy
All examples are written and tested in-tree under `lib/zen_websocket/examples/` with matching tests in `test/`. Validate with compile, Dialyzer, Credo, and tests before considering an example done. Keep examples in this tree — a separate mix project under `examples/<name>/` was tried (R026) and reverted.
- **Executable examples**: Live in `lib/zen_websocket/examples/` without a per-file line limit
- **Packaging**: Examples and `Mix.Tasks.ZenWebsocket.*` ship in the Hex package; removing them would make existing example modules and tasks unavailable to consumers

## Configuration

### Environment Setup
```bash
export DERIBIT_CLIENT_ID="your_client_id"
export DERIBIT_CLIENT_SECRET="your_client_secret"
```

### ZenWebsocket.Config Options
- `url` - WebSocket endpoint URL
- `headers` - Connection headers
- `timeout` - Connection timeout (default: 5000ms)
- `retry_count` - Maximum retry attempts (default: 3)
- `retry_delay` - Initial retry delay (default: 1000ms)
- `heartbeat_interval` - Ping interval (default: 30000ms)

## Testing Strategy

### Test Coverage Requirements
**When modifying any module, ensure it has both:**
1. **Unit tests** - Pure function logic, no network/I/O, fast execution
2. **Integration tests** - Real connections via MockWebSockServer or external APIs

If either is missing, create them before completing the task.

### Test Tagging
- `:integration` - Tests using MockWebSockServer, Gun, or external APIs. Excluded from default `mix test`; excluded from coverage unless paired with `:local_network`.
- `:external_network` - Tests requiring internet access. Excluded from default `mix test` and the coverage gate.
- `:local_network` - Mock-server socket tests retained in the coverage ratchet. Always paired with `:integration`, so default `mix test` still excludes them.
- Default `mix test` excludes every socket-opening test.

### Real API Testing Policy
**NO MOCKS ALLOWED** - Only real API testing:
- `test.deribit.com` for Deribit integration
- Local mock servers using `MockWebSockServer`
- Real network conditions and error scenarios

**Rationale**: Financial software requires testing against real conditions. Mocks hide edge cases that cause financial losses.

#### Narrow exceptions

Two fenced carve-outs. Everything else remains prohibited.

##### 1. Opaque Gun transport message shapes

Test doubles are permitted for **Gun transport message tuples only** — the four shapes `:gun_upgrade`, `:gun_ws`, `:gun_down`, `:gun_error`.

**What is permitted:**
- Constructing the four Gun tuple shapes for unit-level tests of pure functions that consume them (e.g., `MessageHandler.handle_message/2`)
- Fixtures must use **real** `pid()` values (from `self()` or `spawn`) and **real** `reference()` values (from `make_ref/0`). No fake opaque values.

**Why this is not a real mock:** Gun's `pid` and `stream_ref` are opaque BEAM primitives with no public contract. There is no behavior for a fixture to drift against — only a tuple shape. Shape-only fixtures enable property-based testing of routing totality without stubbing any behavior.

##### 2. ClientSupervisor routing stand-in

A test-only GenServer that answers **only** the three `Client` calls `send_balanced/2` uses (`:send_message`, `:get_state_metrics`, `:get_latency_stats`) is permitted in `client_supervisor_send_balanced_test.exs`. `send_balanced/2` reaches candidates solely through `GenServer.call/2` on `server_pid`; the stand-in has no Gun connection, no frame handling, and no exchange semantics. It exists to drive failover and load-balancing deterministically (injected `:ok` / `{:ok, map()}` / `{:error, reason}` replies) without a live socket.

**What is permitted:**
- A `start_supervised/1` GenServer that replies to those three calls
- Injecting the exact reply `Client.send_message/2` would return

**What is NOT allowed** (either exception):
- API response fixtures (Deribit, Binance, any exchange)
- Authentication flow simulation
- Exchange behavior simulation (subscription acks, order responses, heartbeats)
- Stubbing Gun, cowboy, or WebSocket frames
- Using the routing stand-in to test `Client` GenServer state, reconnection, or message handling
- Any fixture with semantic content beyond the raw transport-frame shape or the three `send_balanced/2` call replies

**Source of truth unchanged:** `MockWebSockServer` (real cowboy/websock stack) and real-API tests remain the source of truth for all business logic. `client_supervisor_test.exs` covers `send_balanced/2` end-to-end against a real connection. Any test touching `Client` GenServer state, reconnection, subscription semantics, or exchange behavior continues to require `MockWebSockServer` or a real endpoint.

### Test Support Modules
- `MockWebSockServer` - Controlled WebSocket server (`test/support/mock_websock_server.ex`)
- `CertificateHelper` - TLS certificate generation (`test/support/certificate_helper.ex`)
- `GunStub` - Shape-only constructors for Gun transport tuples (`test/support/gun_stub.ex`)

## WebSocket Connection Architecture

### Connection Model
- WebSocket connections are Gun processes managed by `ZenWebsocket.Client`
- Connection processes monitored via `Process.monitor/1`
- Failures classified by exit reasons

### Reconnection Pattern
```elixir
{:ok, client} = ZenWebsocket.Client.connect(url, [
  timeout: 5000,
  retry_count: 3,
  retry_delay: 1000,
  heartbeat_interval: 30000
])
```

## Platform Integration

### Deribit Adapter
Located in `lib/zen_websocket/examples/deribit_adapter.ex`:
- Authentication flow
- Subscription management
- Heartbeat/test_request handling
- JSON-RPC 2.0 formatting
- Cancel-on-disconnect protection

**Supervised Pattern (production):**
```elixir
connect_opts = [
  reconnect_on_error: false,  # Adapter handles reconnection
  heartbeat_config: %{...}
]
```

**Standalone Pattern (simple use):**
```elixir
{:ok, client} = Client.connect(url)  # reconnect_on_error: true (default)
```

## Key Dependencies

### Core Runtime
- `gun ~> 2.4` - HTTP/2 and WebSocket client (bound requires the GHSA-w4f7-4cxr-rv3c fix, not just permits it)
- `jason ~> 1.4` - JSON encoding/decoding
- `telemetry ~> 1.3` - Metrics and monitoring

### Development
- `credo`, `dialyxir`, `sobelow`, `ex_doc`, `ex_dna` (code duplication detection)

### Testing
- `cowboy ~> 2.10`, `websock ~> 0.5`, `stream_data ~> 1.0`, `x509 ~> 0.8`

## Task Management

### Roadmap
Tasks live in `roadmap/tasks.toml` and are rendered to `ROADMAP.md` by `rmap`. Use `rmap` to list, create, score, and prioritize work.

### Task ID Format
Current ids are numeric (`7`, `8`, …). Historical ids use `R0NN` (`R026`, `R052`). There is no `WNX####` scheme.

### Task Tracking
`rmap` is the substrate. Status, scores, and write-sets live in `roadmap/tasks.toml`; `ROADMAP.md` is a generated view.

Priority uses D/B/U scoring (Difficulty / Benefit / Urgency). `rmap next` selects work from those scores.

### WebSocket-Specific Requirements
- All connection tasks must include real API testing
- Platform integration tasks reference Deribit adapter patterns
- Frame handling tasks include malformed data testing
- Reconnection tasks test real network interruptions
