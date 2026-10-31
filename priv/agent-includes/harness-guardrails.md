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
