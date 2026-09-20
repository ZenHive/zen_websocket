# Elixir Security Adjudications (host-specific)

Two settled, host-specific security verdicts that every fresh agent otherwise
re-derives from scratch. `@`-import this in any repo that declares `mix_audit`
or runs Sobelow, so it also flows into `AGENTS.md` for the cross-family
reviewers via `sync-agents-md.sh`.

## 🚨 ADJUDICATED: the cowlib / gun advisories are ALREADY DECIDED — do NOT re-investigate

**Read this before spending a single token on a `VULNERABLE!` line mentioning `gun`,
`cowlib`, `GHSA-w4f7-4cxr-rv3c`, or `EEF-CVE-2026-4396x`/`-43971`.** This has been
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

**The verdict — cowlib 2.19.0 reached only via `gun` as a WebSocket client (the
`zen_websocket` stack): not reachable.** Evidence is a call-graph fact, not a judgment
call:

| Advisory | Vulnerable function | Reachability |
|---|---|---|
| `EEF-CVE-2026-43971` | `cow_link:link/1` | **0 references** in `deps/gun/src/` |
| `EEF-CVE-2026-43966` (alias `GHSA-w4f7-4cxr-rv3c`, `CVE-2026-43966`) | `cow_http_struct_hd:escape_string/2` | **0 references** in `deps/gun/src/` |
| `EEF-CVE-2026-43969` | `cow_cookie:cookie/1` | only from `gun_cookies.erl` — gun's **opt-in** cookie store; `zen_websocket` never sets `cookie_store` (the string `cookie` does not appear in its `lib/`) |

cowlib **2.19.0 is the latest release** — there is no fixed version to upgrade to, so
reachability is the only available adjudication.

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
values; or a new cowlib advisory appears that is not one of the three ids above.

**Affected repos (13 declare `mix_audit`; 9 carry `gun` in the lock — `bourse_workbench` retired to the code-archive 2026-08-23):** `bourse`,
`mpp`, `onchain`, `onchain_aave`, `onchain_aerodrome`, `onchain_evm`, `onchain_js`,
`onchain_tempo`, `zen_websocket`. Suppression is inconsistent across them — most carry
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
