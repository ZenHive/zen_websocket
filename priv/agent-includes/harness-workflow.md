## Harness Workflow

OTP-native **implement → review → land** loop for roadmap-driven development. An AI orchestrator drives harness; harness dispatches headless implementer agents into isolated git worktrees, then a **cross-family reviewer AI** gates every deliverable (runs the project's checks itself, fixes inline, writes `.harness/review.json`). Optional auto-landing ff-merges approved work; a post-merge audit agent sweeps hygiene.

**Promoted from** `docs/dogfooding-workflow.md` in the harness repo — that file remains the **incubator runbook** for harness-specific history, driver-script templates, and per-batch run logs. This include is the **portfolio-wide contract**. Version-controlled source: `priv/includes/harness-workflow.md` in the harness repo; install to `~/.claude/includes/harness-workflow.md` via `mix harness.install_includes`.

### Relationship to Other Includes (Layered — No Supersession)

| Include | Role relative to harness-workflow |
|---|---|
| `workflow-philosophy.md` | **Foundation.** Evaluator separation, session-per-phase, verification-before-completion. Harness automates the loop while preserving these principles — the **reviewer AI** is the grader, never the implementer's self-report. |
| `task-prioritization.md` | **Task selection.** D/B/U scoring, `rmap next`, parallel markers, refine-don't-duplicate. Harness executes whatever rmap returns; it does not replace prioritization. |
| `worktree-workflow.md` | **Manual parallel sessions.** For hand-build work outside harness dispatch — operator-created worktrees, PR flow, post-merge audit. Harness manages its own per-run worktrees (`harness/<run-id>`); manual worktree rules still apply for hand-build sessions. |
| `dev-lifecycle.md` | **Manual five-phase chain** (`task-driver → worktree → bots → merge → audit-review`). Use when *not* driving through harness. Harness is the automated alternative for dispatchable roadmap tasks; dev-lifecycle still governs plan-and-file, pre-commit review, and post-merge audit. |
| `agent-dispatch.md` / cloud-delegation stack | **Linear/Codex/Cursor PR delegation** without a running harness BEAM. Orthogonal path — projects can use cloud delegation *or* harness; harness subsumes the dispatch+review loop when the OTP node is running. |
| `skills/harness-driver/SKILL.md` (harness repo) | **API surface contract** — MCP tools, `project_eval` patterns, `%LogRecord{}` fields, sharp edges. Load on demand when driving harness; this include covers *workflow*, the skill covers *surfaces*. |

**Adopt per repo:** `@~/.claude/includes/harness-workflow.md` in the project's `CLAUDE.md` (load-on-demand row — not eager; same pattern as `workflow-philosophy.md`).

### The Loop

```
rmap task → implementer AI (worktree) → commit harness/<run-id> → reviewer AI (THE GATE) → done | failed
                                                                              ↓ (done + auto policy)
                                                              MERGE (lander: rebase + ff-push, no re-verify)
                                                                              ↓
                                                              AUDIT (post-merge audit agent, best-effort)
```

One run = one supervised `Harness.Run` gen_statem: fork worktree off target `HEAD`, dispatch implementer, commit diff to `harness/<run-id>`, dispatch cross-family reviewer into the same worktree. The reviewer runs the project's `check_command` hint, fixes what it can, writes `.harness/review.json`. **Success = reviewer `approve`** — never implementer exit code or self-report. There is **no mechanical verification gate** in harness; judgment lives in agents.

Rejections return tasks to pending for an explicit recovery-aware orchestrator decision. Fix-and-approve is the near-absolute default for the reviewer.

**🚨 "Cross-family" is routing doctrine, not a mechanical guarantee.** Harness excludes only the *identical* agent from the reviewer slate (`Harness.Agents.reviewers/1` → `reject_implementer/2`); there is **no family concept in harness code**, so a `cursor` implementer can draw a `grok` reviewer even though both run SpaceXAI weights. The orchestrator owns the separation when it matters. This is deliberate, not an oversight: measured 2026-08-23 over 1,627 harness reviews, controlling for reviewer identity leaves no per-pair signal — review intervention is a **per-reviewer** trait (median `reviewer_diff_size`: Codex 96, Cursor 4, Claude 1, Grok 0), and the most capable reviewer in the ledger finds median 0 in the same work a heavier reviewer rewrites. Don't add a family scheduler to make the code match the older wording.

### When to Dispatch vs Hand-Build

**An rmap task is not automatically a harness run.** Dispatch only when the full
implement→review→land cycle buys meaningful safety, independent verification, or
parallel throughput. Historical run cost stays material even for D≤2 work, so the
old D≤2 / 30-LOC conjunctive exception was too narrow.

**Work inline by default when it is bounded and local:** one coherent surface,
typically D≤4, roughly ≤100 LOC across ≤5 files, focused-testable, and no positive
dispatch trigger below. These are routing hints, not an ALL-of gate — a risky D2
task can earn dispatch, while a routine D4 task can stay inline.

Positive dispatch triggers:

- Signing, money handling, cryptography, security, or authorization
- A public API/schema/contract change or a migration
- Harness runtime, CI/check infrastructure, or a repo-wide invariant
- Live/external-system semantics that need independent evidence
- Multiple subsystems, or genuinely useful parallel execution

Hand-build when harness cannot perform or judge the work:

- Scaffolding that reshapes harness runtime (supervision tree, dep stack, Endpoint) **while the run lifecycle itself is in flux**
- Work requiring live human/browser judgment, such as exploratory visual identity; routine spec-anchored UI remains dispatchable
- A harness gap — file via `rmap new`, fix harness, re-dispatch; do not work around the gap inside the target task

**🚨 The routing gate fires at `assignee =`, not at dispatch time.** rmap requires `assignee` + `model` at task creation, so the inline-vs-dispatch decision is made — and frozen — the moment the task is filed: a task carrying an agent assignee reads as "routing already decided" to every later session, and this section never gets consulted again. Three rules close that hole:

- **Filing a task: run this section BEFORE typing `assignee` — and a FILED task defaults to an agent.** The inline-vs-dispatch question above governs work you can execute *now*: inline-doable work is done inline and never filed. A task that reaches filing is cross-session by definition, so default-route it to a dispatch agent with a pinned `model` (roster spread per § "Roster doctrine"); `assignee = "human"` must be earned by a hand-build reason named in the body — an operator-gated step (license, credential, purchase), no-spec visual identity, harness-loop-in-flux, or the user claiming the work. (A D2 one-file fix is done inline, never filed — filing it is the defect.) Mirrored as question 6 of `task-writing.md`'s Pre-Creation Gate.
- **Reviewer `proposed_tasks` carry no routing authority.** Proposals arrive dispatch-shaped (suggested scores/markers), but the orchestrator owns routing the same way it owns filing — re-route each proposal through this gate instead of inheriting dispatchability from its shape. Sibling of task-writing's "Re-Generalize an Agent's Decomposition": that filters whose *architecture* a task encodes; this filters whose *routing* it encodes.
- **🚨 Under `dispatch_mode: "auto"` there is no such thing as an open decision in a task body — decide it at filing or don't file the task `pending`.** `task-writing.md`'s gate 6 permits a `pending` task to carry named open decisions because "the orchestrator asks before it dispatches." That sentence assumes a human-driven orchestrator seat between the queue and the run. **A cron poller is not that seat**: in `:auto` mode it dispatches the ready set unattended on its schedule, reads no bodies, and asks no one — so the decision reaches an implementer as a question addressed to nobody, and the implementer answers it silently. Before filing into an auto-dispatching project, check `autonomy-status` (per-project `dispatch_mode` + `effective`) and `project_registry-lookup`, then:
  - **Decide it yourself and write the decision in, vetoable.** Name the choice, the reasoning, and the alternatives you rejected. `critical-rules.md` § SURFACE THE OVERRIDE is satisfied by a decision the operator can read and reverse; it does not require a blocking question.
  - **When one premise could genuinely flip the answer, ship the decision with an evidence gate** — "ship (a) unless a live probe disproves X, in which case (b); say in the delivery which you found." That is a decision the implementer can execute, not a question it must route back.
  - **`blocked` is still not the escape hatch.** It hides the task from the queue, so the decision is never surfaced at all — the same failure with a quieter shape. Reserve it for an external blocker with an unblock path.
  - Under `:manual` cron mode the parked-decision drain (`dispatch-pending` / `dispatch-approve`) *does* restore the asking seat, and gate 6 reads as written. Know which mode the project is in before relying on it.

### Integrated audit and QA

The existing post-merge audit worker also performs complete project QA when the
project explicitly configures `qa_command` beside its dispatch `check_command`.
All projects, including aave_sim, use the same split: focused tests and
risk-relevant security/live verification stay with the independent reviewer;
full suites, coverage, Dialyzer, Reach, Sobelow, Credo, Doctor and clone checks
belong to integrated QA where applicable. Full Dialyzer is not mandatory on
every implementation or review. Projects without `qa_command` retain legacy
behavior until explicitly migrated by the operator.

Audit QA pins the integrated SHA/range and persists commands, covered commits,
agent/model, reports and transcripts. Queued/running/passed/failed/incomplete are
facts; only a complete matching agent report advances successful QA progress.
Missing artifacts, missing prerequisites and interruptions never pass. Waiting
jobs coalesce in the audit queue; lands during a run receive a subsequent pass.
QA does not gate deployment, revert, or restart production. The audit AI owns
repair judgment and semantic deduplication; substantial repairs use normal
implementation and review, and undisclosed vulnerability details remain private.

Observe bounded history with `dispatch-qa_status` and evidence slices with
`dispatch-qa_evidence`, or the project settings dashboard. Orchestrators own
configuration migration, skill propagation and activation.

### Running a Task

**Prerequisites:** long-lived harness BEAM (`iex -S mix` in the harness checkout), target project registered in `Harness.ProjectRegistry`, clean `git status` on the target's dispatch branch (runs fork worktrees off `HEAD`). **Roadmap ingest and writeback self-sync when they can.** The run's *code* base is fresh (Task 196: with a `target_branch` set, `Run.Actions.Worktree.worktree_opts/1` fetches and forks off `origin/<target>`). `dispatch-task` / `dispatch-bundle` now also fetch the roadmap branch and fast-forward the `project.roadmap_path` checkout (`Harness.Git.TargetSync.sync_checkout/2`, ff-only, never `--force`) before `rmap` runs, and the writeback path does the same before the `roadmap: task <id> -> in_progress` commit, so a task you filed and pushed from another host is visible without a manual pull. The residual operator action is a **dirty, non-ff-diverged, detached, or self-host** checkout — those skip with a witnessed log and ingest proceeds on the on-disk file; sync them by hand (`git -C <roadmap_path> pull --ff-only`) before dispatching.

**Three dispatch paths** (prefer top to bottom):

1. **Native MCP — default.** `dispatch-task` (fire-and-forget) against `http://localhost:4018/harness/mcp`; wait for the wave by watching `origin/<target>` for the lander's commits, never by blocking on `dispatch-await` / `dispatch-await_runs` (§ "Never block on `dispatch-await*`"). Observe via `dispatch-status`, `dispatch-transcript`, `dispatch-verdict_detail`. `scrub_anthropic_key: true` (default) forces subscription OAuth over inherited `ANTHROPIC_API_KEY`.
2. **Tidewave `project_eval` — escape hatch.** Struct-level control the flat tools don't expose (`retry_policy`, fail-over adapter lists, `subscriber: self()`). Run persists to `Harness.ResultStore` even when the eval process exits.
3. **`mix run` driver script — fallback.** Full transcript + reviewer report to terminal. See harness repo `docs/dogfooding-workflow.md` for the canonical template.

> **Never start a second driver BEAM while runs are in flight.** Boot-time worktree sweeps can prune live sibling worktrees. Drive all parallel batches from one long-lived node.

**In-flight idempotency (Task 286):** a second `dispatch-task` / `dispatch-bundle` of the same `{project, task_id}` while a non-terminal run exists returns the **existing** `run_id` (Oban `conflict?: true`), not a duplicate — a retried dispatch is safe and free.

**Coalesce small related tasks:** `dispatch-coalesce` accepts an explicit task-id list and runs it as one worktree, implementer invocation, reviewer gate, and landing unit. Use it when small tasks share a bundle/surface and separating them would only repeat fixed run costs; keep independent tasks in `dispatch-bundle` so write-disjoint work still parallelizes. Coalesced members share the same landing SHA and never partially land — the reviewer must mark every member `approved` in the verdict's `task_outcomes` or the run fails as a unit. The call returns the coalesced `write_set` (the union of every member's `touches`/`files_to_modify`); serialize the next wave against that union, since harness executes the coalesce but never picks what to coalesce.

**Write-set serialization (Task 292):** `dispatch-bundle` and cron ready-set dispatch compute each task's `touches ∪ files_to_modify` before enqueue. Tasks with overlapping write-sets are logged and serialized into later waves instead of fanned out together. Callers no longer hand-dedupe ready sets; they must keep `touches` / `files_to_modify` accurate because harness does not infer paths from task prose.

**Renderable vs executable:** `rmap delegate --to` renders native prompts for all six harness adapters (`claude`, `codex`, `cursor`, `grok`, `antigravity`, `pi`). `droid` renders but has no harness adapter — rejected at ingest. All six shipped adapters declare `worktree_isolation: true`.

### Routing & Model Management

- **Resolve `assignee` + `model` from facts, not by reading code.** `routing-brief` is the thin task-writer index: dispatchable agent roster, each agent's standing model (`Config.agent_model/1`), model availability/blocks, and per-agent KPI rollups — every metric carries `n`, no ranking. A model-capable agent with no configured model shows `model: nil, model_required: true`.
- **Scout routing (advisory).** `dispatch-recommend` returns the cross-family scout AI's per-facet `:exploit` pick (with rationale) or a safe `:explore` / `:fallback_no_data` when a facet is unmeasured; `dispatch-assess_facets` forces a fresh scout assessment. The caller decides whether to dispatch the pick — legacy composite scores are not used for routing.
- **Model is required, never defaulted.** Implementer precedence: **task `model` → `{:agent_model, agent}` → REJECT** (`{:model_required, agent}`) — harness never falls through to the CLI's ambient default. The **reviewer has no task-pin axis**: its model comes solely from `{:agent_model, agent}` for the reviewer adapter's agent (`Run.reviewer_model/1`), and a model-capable reviewer with no configured model is rejected *before* the reviewer spawns. Antigravity is model-capable as of `agy` 1.0.10 (`--model` + `agy models`); harness validates pins against its catalog because the CLI silently falls back on unknown ids.
- **Block exhausted premium models.** A monthly budget can exhaust (e.g. cursor-Opus) while harness still lists the pair as available and routes to it. `model_availability-block_model` (with a `blocked_until` window) removes the pair from routing/cron; `model_availability-unblock_model` clears it.
- **Cost-aware A/B.** `dispatch-compare` runs one task across N adapters (optional per-adapter model overrides) and returns per-adapter `verdict` / `reviewer_diff_size` / `duration_ms` / `token_usage` for selection.

### Reading the Verdict

| `state` / `reason` | Meaning | Action |
|---|---|---|
| `:done` / `:approved` | Reviewer AI approved (possibly after inline fixes — check `reviewer_diff_size`). | Deliverable on `harness/<run-id>`. Review diff, integrate (or let auto-lander handle it), `rmap status <id> done`. |
| `:failed` / `{:review_rejected, report}` | Reviewer rejected (degenerate — near-never by design). | Read `report` and retained-branch evidence; explicitly choose resume, rereview, fresh or defer. |
| `:failed` / `{:review_stuck, report}` | No verdict: reviewer unavailable, crashed, or missing/malformed `.harness/review.json`. | Read `report`; choose recovery or defer while the environment is repaired. |
| `:failed` / `{:worktree_failed,_}` `{:agent_spawn_failed,_}` `{:driver_crashed,_}` `{:commit_failed,_}` | Harness-side mechanical failure. | **Harness bug.** File via `rmap new`. |
| `:failed` / `{:checkout_polluted, status}` | Agent wrote outside the run worktree into the main checkout — surfaces as `:failed` **only after bounded AI recovery was exhausted** (see "Self-healing recovery" below). | Read the isolation evidence and retained branch; explicitly select recovery or a justified fresh build on an appropriate adapter. |
| `:failed` / `{:checkout_pollution_check_failed, _}` | Post-run pollution `git status` errored. | Rare; transient git/IO. Re-run; inspect checkout if persistent. |
| `:failed` / `:timed_out` | Lifetime budget elapsed (question-held time counts; the timer is not suspended). | Raise `:lifetime_timeout` or recover the retained worktree (`dispatch-resume_failed` / inspect). |
| run process **crashed** (no settle) | gen_statem died. | **Harness bug.** File via `rmap new`. |

Failed runs retain the worktree at `result.worktree_path` for inspection. Approved runs keep branch `harness/<run-id>` after worktree teardown. Use `dispatch-verdict_detail` for the reviewer report, ratings, checks, concerns, proposed tasks, warning flag, and `reviewer_diff_size` — no harness-run mechanical per-check stdout.

**The verdict artifact** `.harness/review.json` is `{verdict, run_id, review_attempt, report, checks, concerns, proposed_tasks, facets, skills, ratings}`: `verdict` (`approve`/`reject`) is the gate; `run_id` and `review_attempt` fence the file to the reviewer invocation that wrote it (echoed from `HARNESS_RUN_ID` / `HARNESS_REVIEW_ATTEMPT`; a mismatch is treated as missing); `report` is the reviewer's prose; `checks` is the reviewer-written record of commands run and their pass/fail claim; `concerns` is the reviewer's self-flagged caveat list; `proposed_tasks` is an optional list of structured discovery proposals (`title`, `body`, suggested scores/markers, and evidence); **`facets`** (open-vocabulary routing KEY — the kind of task) and **`skills`** (v0_13 two-axis rubric, routing VALUE) feed per-facet capability routing; `ratings` is the legacy flat-score fallback. Harness persists proposals verbatim but never files them. After a run lands, the orchestrator reads them from `dispatch-verdict_detail`, dedupes/merges them against the live pending set, and files only warranted tasks through its own task-writing gate. Reviewers never edit `roadmap/tasks.toml`, `roadmap/data.json`, `ROADMAP.md`, or `CHANGELOG.md`; those files are excluded from delivery commits alongside `.harness/`. Approved runs with non-empty concerns or a reviewer-authored failed check surface a warning fact; harness never auto-blocks or classifies prose. The artifact lives under `.harness/` (excluded from staging) so it never rides in the deliverable commit. The file is removed before every reviewer spawn so a killed reviewer's stale approve cannot settle the run.

**External-system evidence is reviewer-owned judgment.** When acceptance criteria touch an API or external service, the reviewer must look for reality rather than plausibility: a live success call, a relevant live error, the provider's official docs/spec/SDK for semantic meaning, and an integration test pinning the observed domain semantics. Third-party clients, aggregators, wrappers, and reference implementations (including CCXT) are compatibility/reference evidence only; they never establish correctness or override the provider-owned contract. Mocks, fixtures, and the implementer's self-report are not independent evidence. Missing credentials or an unreachable sandbox are surfaced as a failed check/concern (or rejection when the criterion cannot be verified), never silently treated as green. The lander records the reviewer identity plus `harness-run:<run-id>` as rmap verification provenance.

**Self-healing recovery (the `:recovering` state).** Before settling `:failed` for an *interpretive* non-rejection failure — checkout pollution is currently the one wired call-site — the run spawns a **bounded cross-family recovery AI** (`:recovering` state, budget 1/run) with minimal context (the error term + the main checkout's `git status` + the implementer transcript tail + the failing-check output, never the full transcript). It writes `.harness/recovery.json` `{outcome: "repaired"|"dead", report, repaired}`; harness reads it mechanically and **decides nothing itself**: `repaired` resumes at `:committing` and **re-runs the reviewer gate** (never skips to `:done`); `dead` / missing / malformed settles `:failed` with the original reason. A genuine `verdict: reject` is never routed through recovery. The `Result` carries `recovery_attempts` / `recovery_outcome` / `recovery_repaired` / `recovery_token_usage`. (Tier-1 mechanical self-heal precedes it: the reviewer is re-prompted once on a missing/malformed `review.json` — `reviewer_reprompt_count`, capped at 1 — and rotates to the next cross-family candidate on a reviewer timeout — `reviewer_rotation_count`.)

### 🚨 Recover, Don't Redo — Never Burn Tokens Re-Implementing Committed Work

**A run that committed to `harness/<run-id>` already paid for the implementer. Recovering that branch costs a fraction of a fresh dispatch — re-dispatching from `pending` throws the work away and makes the agent redo all of it.** The reflex to "reset → pending → dispatch again" is a token bonfire whenever a retained branch with commits exists. Check for the branch *first*; pick the cheapest primitive that fits:

| Run state — committed `harness/<run-id>` branch exists | Recover with | Agent tokens |
|---|---|---|
| Approved but unlanded (land-cap, lander crash) | `dispatch-reland` | **zero** — pure git rebase + push |
| Committed, review-stage failure (work is good) | `dispatch-rereview` | zero implementer — re-enters at the reviewer gate |
| Committed, implement-stage incomplete/`:failed` | `dispatch-resume_failed` (`escalate: true` to re-route agent) | **re-spends implementer tokens** — a fresh implementer invocation branched off the retained commits with the failure report injected (contrast `rereview`, which re-runs only the reviewer) |
| Live `:held` run (paused, not dead) | `dispatch-resume` | none — un-pauses in place. A question-held run requires a prior `dispatch-steer` answer (`:answer_required` otherwise). |
| **No commits / no retained branch** | reset → `pending` + fresh `dispatch-task` | full redo — **the only case where this is correct** |

**Live-run intervention (not recovery of a dead run):** `dispatch-hold` (optionally `interrupt: true`) parks a live run mid-turn, `dispatch-steer` stashes guidance applied on resume, `dispatch-resume` un-pauses in place, `dispatch-cancel` kills it (idempotent). Use hold → steer → resume to force-hand a grinding implementer to the reviewer gate instead of burning the lifetime budget.

**Implementer question channel.** A headless implementer that hits genuinely ambiguous acceptance criteria writes `.harness/question.json` (`question` string, optional `context`, plus `run_id` / `invocation` echoing `$HARNESS_RUN_ID` / `$HARNESS_IMPLEMENTER_ATTEMPT`) and ends its invocation. Harness reads the file mechanically at the agent-invocation boundary: a fenced, unconsumed artifact parks in `:held` (`hold_reason: :question`) and emits a `:question` witness with the question verbatim; empty/malformed/stale/consumed files are ignored-and-logged. The orchestrator answers with `dispatch-steer` (the answer text) then `dispatch-resume` — no new primitives, no dashboard UI, no auto-answer inside harness. Resume injects question + answer into the prompt and consumes that identity via `.harness/question-state.json` (plus an archive under `.harness/questions/`); deleting `question.json` is not the consumption mechanism. A leftover file cannot re-park; a later question with a new identity can. Question-held time stays inside the existing `lifetime_timeout` (the timer is not suspended; expiry is recoverable `:timed_out`). A gen_statem crash while `:held` still settles `:failed`; the retained worktree sidecar is the recovery boundary and cannot leak to a new run. This is an escape hatch, not a substitute for well-written tasks; reviewer/audit questions are out of scope. Explicit `dispatch-resume_failed` recovery restores the selected retained run's pending/answered question state into a held replacement without notifying again; resume uses the saved answer or requires steer. Recovery needs the retained worktree and failed-run record on the same storage. Fresh dispatches do not import it. Notification delivery remains best effort (a crash after persisting the notified flag can lose delivery).

**The gate before any reset-to-pending + re-dispatch:** `git branch -a | grep harness/<run-id>` and `git log --oneline origin/<target>..harness/<run-id>`. Commits present ⇒ explicitly judge whether to resume, re-review or replace; justify discarding them.

**🚨 First, confirm the run actually *didn't* land — check `origin`, not your local checkout.** Under `landing_policy: :auto` the lander pushes to `origin/<target>` from a detached worktree, then `Harness.Git.TargetSync` may fast-forward the operator's local target when that is safe (off-target → ff the branch ref; on-target + clean tree → `merge --ff-only`). It skips — witnessed, never `--force` — when the tree is dirty, the update is not a fast-forward, or the target is this running node's own source tree (self-host: path identity, not the project name). Under dogfooding that self-host skip is the common case, so after an autonomous land your local `tasks.toml` is **stale**: it still reads `in_progress` for a task the lander already marked `done --shipped-in` on origin. **Reading that stale local status as "the run didn't land" is the trap** — it triggers a wasteful reset-to-`pending` + re-dispatch that *duplicate-lands already-shipped work*. Before concluding anything from task status, `git fetch origin <target> && git rebase origin/<target>` (the existing "Sync main before committing" rule) or read ground truth directly:
- `git log --oneline origin/<target>` — does it already show `task <id> -> done (shipped …)` and the agent-delivery commit? Then it **landed**; your local view was just behind. Do nothing but rebase.
- `dispatch-status <run-id>` / `result_store-list_run_records run_id:<id>` — a record with `state: done, verdict: approve` means the run succeeded; cross-check landing against origin before touching the roadmap.

The recovery primitives (`reland`/`rereview`/`resume_failed`) read the persisted `ResultStore` record, which **survives** worktree teardown and node restarts — so a genuinely approved-but-unlanded run (lander hit its land-cap, or a real rebase conflict retained the branch) is recoverable token-free via `dispatch-reland`. Returning to `pending` requests a new AI decision, not a clean-slate retry — and only after confirming against `origin` that the work isn't already shipped.

### Parallel Dispatch

`Harness.Run.Supervisor` is a `DynamicSupervisor` — N crash-isolated runs, each with its own worktree.

- **Batch by dependency graph, then write-set.** Every pending task whose `depends_on` is satisfied can enter the ready set, but harness dispatches only the first wave whose `touches ∪ files_to_modify` are disjoint. Overlapping tasks wait for a later wave after the landed base moves forward.
- **Keep write-set fields accurate.** The dispatcher counts declared path intersections; it does not infer paths from the task body. If two tasks really edit the same function, either let write-set serialization sequence them or fold the coupled work into one rmap task (`task-prioritization.md` § "Refine, Don't Duplicate").
- **One driver BEAM** for all concurrent runs in a wave.
- **Integration order (manual landing):** smallest/isolated diffs onto target first; rebase siblings; consume the post-merge audit + QA evidence on the integrated revision.
- **While a wave is in flight:** do not run `rmap status` / `rmap mark` / `rmap new` in parallel sessions against the same checkout — triggers `:checkout_polluted` false-positive.
- **Repo-wide invariant tasks run EXCLUSIVE.** A task whose real write-set is "the whole surface" — introduce a repo-wide guard/invariant and convert every violating site (e.g. an AST-scan test over all of `test/`) — cannot be write-set-serialized by declared `touches`: any sibling land that adds a new violating site after the fork reddens the guard at landing time. Dispatch such tasks as a solo wave — nothing lands in parallel — or accept that the orchestrator repairs at landing.
- **Land-conflict repair is a standard orchestrator move, not an incident.** When the lander blocks on a rebase conflict (reason retains the branch): fork a repair worktree off `origin/<target>`, cherry-pick the run commits, resolve (for additive `tasks.toml` collisions: renumber the branch-side new task to the next free id on origin **and rewrite in-diff string references to it** — CHANGELOG lines, code comments; then `rmap validate && rmap render`), point the retained `harness/<run-id>` branch at the repaired tip, and `dispatch-reland` — the lander keeps push authority and advances rmap itself. **Do not re-run gates on a roadmap/doc-only repair:** the reviewer already graded the code; renumbering tasks, merging doc entries, and re-rendering the roadmap change nothing the gates measure, and a clean disjoint auto-merge of verified code needs no re-grade (same token-economy rule as everywhere else). Re-run a check ONLY when the repair touched code, or when the conflict overlapped a repo-wide invariant the sibling lands could have violated (e.g. a new suite-wide guard vs tests added after the fork — run just that guard, not the stack). Never reset-to-pending (that redoes paid work), never hand-push to the target when a reland can land it.

### Autonomous Landing

Projects with `landing_policy: :auto` or `:pr` and a non-empty `target_branch`:

1. Approved run enqueues one job on serialized `landing_<name>` Oban queue (limit 1)
2. `Harness.Lander.land/1` rebases `harness/<run-id>` onto `origin/<target>` in a detached worktree
3. **`:auto`** — **ff-pushes without re-verification** — the reviewer already gated the work.
   **`:pr`** — force-with-lease-pushes the rebased tip to `origin/harness/<run-id>` (never the
   target) and opens a GitHub pull request with `gh` (`gh pr create --base <target> --head harness/<run-id>`).
   `Git.TargetSync` is not run. A missing or unauthenticated `gh` fails the landing job with a
   witnessed reason, retains the branch, and never falls back to a direct push.
4. **`:auto`** — successful push enqueues post-merge audit; advances rmap (`done --verified --verified-by <reviewer> --verification-ref harness-run:<run-id> --shipped-in <sha>`).
   **`:pr`** — writeback is deferred: the rmap task stays `in_progress` (`rmap status <id> in_progress --landing-ref <url>` when rmap supports the flag; an older binary is logged and tolerated), the run record stores `pr_url`, and a `:pr_opened` witness fires. `Harness.Lander.PRPoller` (Oban cron, default every 5 minutes) reads `gh pr view --json state,mergeCommit,mergedAt`. MERGED performs the same three effects `:auto` does at push time (rmap `done --shipped-in <merge sha>` + post-merge audit + `:landed`). CLOSED-unmerged marks the task `blocked` with `PR <url> closed unmerged` in the reason and retains the branch — never reset to pending, never re-dispatched. OPEN is a no-op. A run is written back at most once.

Conflict / push-rejected retains the branch for repair — never lands red. Witness notification (read-only sink) alerts the operator; it is **not** a merge gate.

**🚨 Never block on `dispatch-await*` — monitor `origin` for the landing commit instead.**
This is the standing rule for waiting on a wave, not a fallback. `dispatch-await` /
`dispatch-await_runs` hold an MCP request open for the entire run, and an MCP client
kills a tool call that emits no progress for its idle timeout (Claude Code's default is
300s — far shorter than any real run). The call dies, the orchestrator learns nothing,
and the runs keep going regardless. Worse, awaiting the wrong signal: **await returns at
reviewer settle, which fires BEFORE the serialized `landing_<name>` job rebases and
ff-pushes** — so even a successful `approve` means "approved and *queued* to land," never
"on `origin/<target>`." Under `landing_policy: :pr` the same gap is longer: MERGE opens a
PR instead of pushing the target, and rmap `done --shipped-in` waits for that PR to merge.

**The primitive that actually works — watch the target branch for the lander's own
commits.** The lander pushes `task <id> -> done (shipped <sha>)` to `origin/<target>`;
that commit IS the landed signal, it is durable, and it survives a dead MCP call, a
restarted session, and a node bounce. Arm one background watcher per wave and keep
working:

```bash
# one notification per landed task, exits when the whole wave is in
cd <source-checkout>
WAVE="615 623 569 619"; seen=""; BASE=$(git rev-parse origin/<target>)
DEADLINE=$(($(date +%s) + 10800))  # bound the wait; tune to the wave's slowest run
while true; do
  git fetch -q origin <target> || true
  for t in $WAVE; do
    case " $seen " in *" $t "*) continue;; esac
    if git log --oneline "$BASE"..origin/<target> | grep -q "task $t -> done"; then
      echo "LANDED task $t"; seen="$seen $t"
    fi
  done
  [ "$(echo $seen | wc -w)" -eq "$(echo $WAVE | wc -w)" ] && { echo "WAVE COMPLETE"; break; }
  [ "$(date +%s)" -gt "$DEADLINE" ] && {
    echo "DEADLINE EXCEEDED — wave incomplete"
    git log --oneline "$BASE"..origin/<target> | grep "task.*-> done" | sed 's/.*task \([0-9]*\).*/  landed: \1/' || echo "  (no tasks landed in range)"
    for t in $WAVE; do
      case " $seen " in *" $t "*) continue;; esac
      echo "  missing: $t"
    done
    break
  }
  sleep 60
done
```

🚨 **The baseline is load-bearing — grep the range, never the whole log.** A task that
landed before, or was reset and re-dispatched, already carries `roadmap: task <id> -> done
(shipped …)` in history; without `BASE` the watcher reports `LANDED` before the implementer
has written a line.

The deadline branch is the other half. A run that fails review or blocks on a land conflict never
produces a landing commit, so a watcher with no bound waits forever on a wave that is already
dead; on expiry it must print what did land in the range and name what did not, so the missing
tasks get reconciled through `dispatch-status` instead of assumed.

**Do not micromanage in-flight runs.** After dispatch, let the implementer and reviewer
finish. Arm the bounded landing watcher once and wait, or do independent work. Do not
repeatedly read transcripts, inspect intermediate worktree diffs/files/test logs, review
unfinished code, or narrate unchanged status. That duplicates the reviewer and spends
tokens without advancing the task. Inspect the verdict and integrated result after
completion. Intervene only on an explicit operator request, a reported failure, or an
expired watcher deadline — the absence of a landing commit during normal execution is
not a failure signal. Keep waiting mechanical rather than turning every polling interval
into another AI investigation.

Poll `dispatch-status <run-id>` only to diagnose a run that the watcher shows as *not*
landing — a `:failed` verdict, a rebase conflict that retained the branch, a hung
implementer. Status is for diagnosis; git is for waiting.

**Silence is not success** — a run that fails review or blocks on a land conflict never
produces a landing commit, so a watcher greping only for `-> done` stays quiet forever.
Bound every wave watch with a deadline, and when it expires without `WAVE COMPLETE`,
reconcile the missing tasks through `dispatch-status` / `result_store-list_run_records`
before assuming anything.

Same root cause as the duplicate-land trap above, seen from the dispatch side: **origin is
the source of truth for what landed** — not an await return value, not a local
`tasks.toml`, not a transcript.

**Herdr panes are an optional operator convenience for watching, never a harness
surface.** When the orchestrator session runs inside Herdr (`HERDR_ENV=1` — the
operator's default), the wave watcher above and ad-hoc run babysitting can run
*visibly*: `herdr pane split --current --no-focus` + `pane run` for the watcher
loop, an attach pane tailing `dispatch-transcript` for a run under scrutiny,
`herdr worktree open --path <retained-worktree>` to inspect a failed run, and
`herdr notification show "…" --sound done` as a configured witness-notification
sink. Strictly operator-side: dispatched agents stay headless over Ports, and
Herdr's `idle`/`blocked` classification is never a harness signal (adjudicated —
harness repo `docs/orchestration-library-evaluation.md`, Addendum 2026-08-25,
incl. the deliberately unmitigated `HERDR_*` env-inheritance risk for dispatched
agents).

**Cron manual-approval mode.** A per-project cron poller in `:auto` mode dispatches unattended; in `:manual` mode it **parks** each dispatch decision instead of enqueuing — drain the parked decisions with `dispatch-pending` and approve them with `dispatch-approve`, keeping the orchestrator in the loop for autonomous polling.

### Orchestrator Loop — the Architect Seat the Per-Task Reviewer Can't Fill

The sections above document the *mechanisms*; this is the **continuous loop** the driving AI runs across waves:

```
plan wave → dispatch → watch origin for the landing commits → observe post-merge audit + QA evidence
          ↑                                                     + review whole surface vs roadmap intent & domain invariants
          └── reconcile rmap ← encode any whole-surface finding as a criterion/test ←┘
```

Each arrow reuses an existing mechanism — don't restate them here: *watch origin for the landing commits* (§ "Never block on `dispatch-await*`", and § "Recover, Don't Redo" → the duplicate-land trap), *reconcile rmap* (the lander already advanced `done --shipped-in` under auto-land — verify, don't double-write), *next wave* (§ "Parallel Dispatch" + write-set serialization).

**🚨 Three review seats, each blind where the next sees — the orchestrator seat is mandatory, not optional.** The per-task reviewer gates *one diff against one task* and is **structurally blind** to two defect classes that land clean through it (worked evidence: delta_calc tasks 24/25/26, see its `## Review Blind Spots` / `## Domain Invariants`):

| Seat | What it sees | What it CANNOT see |
|---|---|---|
| **Per-task reviewer** (cross-family, the gate) | one diff vs one task's acceptance criteria + mechanical checks, in an isolated worktree off a base | the whole surface; domain ground truth |
| **Post-merge audit AI** (best-effort) | cold build of the merged commit range; hygiene | whether a domain constant is *wrong*; roadmap-intent fit |
| **Orchestrator** (the architect seat — you) | whole integrated surface vs roadmap intent + domain invariants across all landed waves | — (this is the seat of last resort) |

The two blind classes, both real-correctness, both passing every per-task check:

- **Domain ground truth** — a wrong venue constant (`@funding_periods_per_day 3`, overstating Deribit's hourly funding ~8×) is internally consistent and fully tested *because the golden was computed with the same wrong constant* — coverage ratifies the bug. The reviewer has no signal; that knowledge lives in the architect's head.
- **Cross-module global invariants** — write-set-disjoint parallel dispatch means two worktrees can each define `project_payback_timeline` and neither review sees the other; the collision only exists once both have landed on the integrated base. Only a whole-surface seat catches it.

**Post-merge audit + QA owns the full landed-base check.** Follow `~/.claude/includes/verification-policy.md`. The orchestrator reads its revision-bound evidence and reconciles findings against roadmap intent and domain invariants; it does not duplicate the full suite after every wave. Missing QA evidence remains visible as unverified.

**Capture dispatch-check output once, to a unique tmp log.** Dispatch checks are normally verbose. The reviewer should capture the first run instead of re-running for readability: `LOG=$(mktemp -t harness-check-dispatch.XXXXXX.log)` then `mix check.dispatch > "$LOG" 2>&1`; inspect with `tail -200 "$LOG"` / `rg "error|failed|warning" "$LOG"` and record the log path in `.harness/review.json`. The random `mktemp` path prevents parallel agents from clobbering each other's logs.

**Audit + QA is nonblocking.** Full QA is not an implementer/reviewer requirement or a prerequisite for the next wave. The orchestrator owns follow-up and integrated intent review; the reviewer still decides acceptance of the task.

**Two framing guards — keep this consistent with the harness mantra:**

- **It's an agent seat, not harness code.** The mantra ("count facts in code; judge with an AI") forbids *harness* computing meaning — it does **not** forbid the orchestrator AI from reviewing the whole surface or running the suite. This adds no mechanical gate to harness; it's judgment in an agent, which is exactly where judgment belongs.
- **The output crystallizes into encoded invariants — don't leave it a manual sweep.** When the architect seat catches a whole-surface or domain defect, the highest-value move is not the manual catch — it's pushing the rule into an **acceptance criterion or a manifest-wide CI test** (the delta_calc rule) so the per-task gate absorbs that class going forward. Orchestrator review *feeds* the criteria/CI; it must not become a permanent re-review of every diff. A finding caught twice by hand is a missing test.

**Convergence sweep (append-only).** The architect seat's whole-surface pass has a disciplined output shape (inspired by spec-kit's `/speckit.converge`, github/spec-kit): assess the landed code against the **roadmap + acceptance criteria as the sole source of intent** — never against the orchestrator's memory of what it dispatched or what a transcript claimed. Three rules:

- **Sole source of intent.** The gap being measured is code vs. `tasks.toml` ACs and roadmap/milestone intent. If the intent itself was wrong, that's a task edit first, then a sweep against the corrected intent.
- **Append, never rewrite.** Every unmet criterion, partial delivery, or intent gap becomes a **new `rmap new` task** (D/B/U-scored, gated per `task-writing.md`) referencing the task it converges on. Never reopen, rewrite, renumber, or edit the history of existing tasks to make the gap disappear — `attempts`/`implemented` records are evidence, not scratch space.
- **Clean sweep = zero mutations.** When the surface already satisfies the roadmap, the sweep leaves `tasks.toml` **byte-for-byte unchanged** — no empty "convergence" ceremony entries, no touched timestamps. A sweep that always writes something is measuring itself, not the code.

### Portfolio Conventions

- **Agent does not commit unless asked.** Staged-but-uncommitted is the default handoff between implementer and reviewer sessions (`workflow-philosophy.md` § "Implementer / Reviewer Handoff"). Harness runs commit agent work to `harness/<run-id>` automatically — that is harness's deliverable branch, not the operator's main checkout.
- **Reviewer discoveries arrive as proposals, and the ORCHESTRATOR files them post-land.** A reviewer that filed a discovery by editing `roadmap/tasks.toml` in its worktree assigned ids from a stale fork (id collisions that block the lander — observed ccxt_client 2026-07-19), couldn't see the live pending set (so the one-session=one-task merge gate never fired), and made roadmap files a universal write-set overlap across "disjoint" waves. That channel is closed: reviewers now emit `proposed_tasks` in `.harness/review.json`, and `roadmap/tasks.toml`, `roadmap/data.json`, `ROADMAP.md`, and `CHANGELOG.md` are excluded from delivery commits, so a run diff carries only code. After each land, read the proposals via `dispatch-verdict_detail` and file only the warranted ones through your own task-writing gate — dedupe against the live pending set, merge per `task-writing.md`, score with real ids off `origin`. Harness persists proposals verbatim and never files them.
  - **🚨 Default-DECLINE — the proposal pipeline outproduces the backlog's right to grow.** Reviewer + audit agents emit ~1 proposal per run; an orchestrator that files "everything evidenced and cross-session" lands N tasks and files N new ones per wave — net backlog delta ±0, the roadmap never converges. Evidence + cross-session is the FLOOR, not the bar. File a proposal only when ALL THREE hold: (a) real defect or invariant gap with evidence, (b) not foldable into an existing pending task — and when the proposal patches an instance of a class, scope the filing as the CLASS invariant so the next instance can't spawn a sibling task, (c) not inline-doable in minutes by the orchestrator — if it is, DO it now instead of filing. Declined proposals need no ceremony: the verdict record in the ResultStore is their evidence trail.
  - **Report the net backlog delta** (landed − filed) as an explicit number in every wave/session wrap-up. A session trending ±0 or negative-growth is the churn alarm firing — tighten the decline bar, don't normalize it.
- **Witness notification is sakshi (read-only).** Landing outcomes notify via configured command sink; the sink grants no merge capability. Human operator reviews blocked/conflict outcomes — harness does not silently force-push past conflicts.
- **`check_command` is a dispatch-scale hint to the reviewer.** Free text (e.g. explicit format + compile commands for Elixir with focused tests chosen by the reviewer) — the reviewer runs and judges it; harness does not execute it mechanically. Use `verification-policy.md` to select scope; a hint that expands to full QA must not impose it on each run. Full-suite commands like `mix precommit.full` belong on `qa_command` for post-merge audit QA. Operator rollout: `mix harness.projects.rollout_dispatch_qa` (dry-run default). For verbose checks, capture to a per-run `mktemp` log on the first execution; never re-run only to recover truncated output.
- **The cross-family reviewer reads `AGENTS.md`, not your Claude skills/includes.** `AGENTS.md` is generated from `CLAUDE.md` by recursively inlining every `@`-import. **Regenerate it after any `CLAUDE.md` change** (harness: `bash scripts/sync-agents-md.sh`; other repos: `claude-marketplace/scripts/sync-agents-md.sh`, or `--dry-run` to preview) so the reviewer gates against current rules — a stale `AGENTS.md` makes codex/cursor/grok judge against rules you've already changed. **`--check` is the freshness gate** — it re-renders in memory and exits non-zero if `AGENTS.md` has drifted (diffs rendered output, not mtimes, so it catches drift in transitive `@`-imports too); wire it into CI / a pre-commit hook / the `check_command` so staleness fails loudly instead of silently. Consequence under Opus-4.8 skill-on-demand: once `CLAUDE.md` slims to the eager floor, reviewer-critical facts that *were* carried by eager includes (the `check_command` gate; that `mix test.json` / `mix dialyzer.json` emit JSON **by design** — parse for real failures, never flag the envelope; plain `mix dialyzer` is authoritative when the JSON encoder can't serialize a warning) no longer reach `AGENTS.md` via those imports. Put them in a **self-contained `## Toolchain & check commands` section in `CLAUDE.md`** so they survive the slim-down and flow into `AGENTS.md` on regen (ref: `tapakly/CLAUDE.md`, `ccxt_extract/CLAUDE.md`).
- **Roster doctrine.** Prefer `codex`, `cursor`, `grok`. `claude` is dispatched only when the operator has enabled it in the Agents settings; the default is off because the orchestrator session already runs on the same Max subscription. `cursor` and `grok` are one family — pair either with a `codex` reviewer. Spread assignees across the enabled agents; a ledger skewed to one adapter is the tell. A repo may override the roster in its own CLAUDE.md.
- **Model pins.** `model` is required at creation for any non-`human` assignee (`rmap new` rejects a model-less dispatchable task; see `rmap.md` § "Pinning an LLM model"). Read the live standing model per agent from `routing-brief` and the live ids from `model_availability-list_available_models <agent>`; a retired pin fails at dispatch, so re-pin when you touch a task. A newly-probed model lands in the catalog as `selected?: false` — select it before it is dispatchable. New ids carry no ledger data — route to them to *gather* it (`dispatch-compare`), not on a performance claim.

### Known Sharp Edges

- **Fresh worktrees lack `deps/` / `_build/`.** Implementer and reviewer each run project bootstrap (e.g. `mix deps.get`) when needed — budget timeouts for cold worktrees.
- **Reviewer runs the checks.** No mechanical check stack. Correct-but-not-pristine work → reviewer fixes and approves (`reviewer_diff_size` > 0).
- **Cold dialyzer PLT** belongs to the full post-merge QA budget, not routine reviewer checks.
- **Nested Claude auth.** `ANTHROPIC_API_KEY` shadows subscription OAuth — scrub per run (`scrub_anthropic_key: true` or `env: %{"ANTHROPIC_API_KEY" => false}`).
- **Parallel-session rmap mutations** during a run can false-positive `:checkout_polluted` — wait for the wave or use a separate worktree.

### Repo-Specific Detail

| Need | Where |
|---|---|
| Harness API surfaces, MCP tool shapes | `skills/harness-driver/SKILL.md` in harness repo |
| Driver script template, cutover history, run log | `docs/dogfooding-workflow.md` in harness repo |
| Agent-gate architecture spec | `docs/agent-gate-workflow.md` in harness repo |
| Cross-checkout consumer setup | `skills/harness-driver/SKILL.md` § "Context A" |
| D/B/U scoring, task writing | `task-prioritization.md`, `task-writing.md` |
| Manual session/PR/audit chain | `dev-lifecycle.md`, `worktree-workflow.md` |


## Recovery-aware cron decisions

A singleton with no persisted attempts may dispatch directly. Any task with
history, and every multi-task wave, goes to the orchestrator AI with project/task
identity, fingerprints, reviewer evidence, retained branch tips and origin
ancestry. A failed history read stops the tick; it never means "no attempts".

`.harness/cron-plan.json` dispatch entries support `action` (`fresh`, `resume`,
`rereview`), `source_run_id` for recovery, `adapter`, `model` and `reason`.
History requires an explicit action, model and rationale. The AI decides whether
commits are useful; `fresh` must explain why prior work is being discarded.
`skip` defers. No error-prose classifier, retry count or escalation ladder chooses
this policy.

Cron, parked manual approvals, `dispatch-resume_failed(run_id, escalate)` and
`dispatch-rereview(run_id)` enqueue through the project Oban queue. Public recovery
returns the queued run id, not a promise that an agent has already started.
Resume pins the retained SHA and injects the exact reviewer report; rereview
enters the reviewer gate without an implementer. Existing live `dispatch-resume`
and approved-work `dispatch-reland` retain their distinct meanings.

Approval retains action, source SHA, fingerprint, selected agent/model, rationale
and secret scrubbing. The worker revalidates identity, history, routing, branch
availability/tip and origin ancestry before spawning. Stale selections cancel
visibly for re-planning; there is no fallback to a clean run. Coalesced recovery
is rejected rather than narrowing membership; legacy membership is checked from
retained Oban job data when absent from the run record. Unknown membership or
missing fingerprints cannot establish safe recovery identity.

Run records and status/verdict responses expose `dispatch_decision`; durable
`task_ids` preserves coalesced membership. Deploy migration
`20260918230000_add_dispatch_decision_to_run_records` before activating this code.
The driving orchestrator owns runtime activation and installed-skill propagation.

### Graceful shutdown recovery

Application shutdown settles runs in `Harness.Application.prep_stop/1`, before
Oban, the endpoint, task supervision or storage stop. Stopping
`Harness.Run.Supervisor` directly uses the same admission fence. Its shutdown
child closes admission before the inner DynamicSupervisor terminates run children
concurrently; the admission process remains alive until settlement finishes.
Run processes trap supervisor exits and persist `state: :failed` with
`reason: {:shutdown, interrupted_state}`. Dispatch jobs retain that reason in
their cancellation error; this is an interrupted attempt, not an operator cancel.

Admission is serialized at the agent-driver boundary, including reviewer
reprompts/rotation, recovery and the in-run grader. Already-admitted invocations
have five seconds to deliver their spawn handle; no new invocation is admitted
after the fence closes. A hung pre-spawn driver is killed and logged. The fence
child has a seven-second shutdown budget, run children have thirty seconds in
parallel, and admission teardown has one second: a 38-second run-layer budget,
below the documented 120-second service stop timeout. This budget does not cover
transport drain or promise persistence when storage/callbacks exceed the budget;
OTP reports forced termination. Store errors are logged and spill through the
existing ResultStore dead-letter/replay path. A spill failure remains a visible
persistence failure, never a successful write.

Retained branches and worktrees are recovery evidence. After restart, inspect the
shutdown record and compare its branch with `origin`; use `dispatch-rereview` for
review-ready commits or `dispatch-resume_failed` for incomplete implementation.
Both operations validate and pin the retained commit through the ordinary queue.
A missing branch returns `source_unavailable_or_landed`; shutdown does not invent
a commit or justify a hand-built `start_run`. If persistence spilled, repair the
store and replay the spill before using record-based recovery. SIGKILL and power
loss cannot run these callbacks and carry no graceful-cleanup guarantee.
