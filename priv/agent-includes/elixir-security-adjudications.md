# Elixir Security Adjudications (host-specific)

Two settled, host-specific security verdicts that every fresh agent otherwise
re-derives from scratch. `@`-import this in any repo that declares `mix_audit`
or runs Sobelow, so it also flows into `AGENTS.md` for the cross-family
reviewers via `sync-agents-md.sh`.

## 🚨 ADJUDICATED: the cowlib / gun advisories are ALREADY DECIDED — do NOT re-investigate

**Read this before spending a single token on a `VULNERABLE!` line mentioning `gun`,
`cowlib`, `GHSA-w4f7-4cxr-rv3c`, or `EEF-CVE-2026-43966`.** This has been
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

**Every cowlib EEF-CVE is fixed upstream — bump, never ignore.** cowlib 2.22.0 fixes the
last two (OSV, verified 2026-11-25). The global Hex ignore list is empty again
(`ignore_advisories` removed from `~/.hex/hex.config` 2026-11-25). If one of these ids
appears, the repo locks an older cowlib: `mix deps.update cowlib gun` (and `cowboy` where
present — cowboy 2.21.0 fixes HIGH `EEF-CVE-2026-115701`).

| Advisory | Function | Fixed in (OSV range) | Removed from ignore list |
|---|---|---|---|
| `EEF-CVE-2026-43971` | `cow_link:link/1` | cowlib 2.20.0 (`>= 2.9.0 < 2.20.0`) | 2026-09-24 |
| `EEF-CVE-2026-43969` | `cow_cookie:cookie/1` | cowlib 2.21.0 (`>= 2.9.0 < 2.21.0`) | 2026-10-31 |
| `EEF-CVE-2026-43966` (alias `GHSA-w4f7-4cxr-rv3c`) | `cow_http_struct_hd:escape_string/2` | cowlib 2.22.0 (`>= 2.9.0 < 2.22.0`) | 2026-11-25 |
| `EEF-CVE-2026-113431` (HIGH) | `cow_http2_machine:headers_decode/4` | cowlib 2.22.0 (`>= 2.7.0 < 2.22.0`) | 2026-11-25 (never globally ignored) |

The former reachability verdict (gun as an HTTP/1.1-only WebSocket client never calls the
struct-header serializers or `cow_http2_machine`) is history; it applied only while no
fixed cowlib existed. Do not resurrect it as a reason to ignore instead of bumping.

**The separate `gun` line from `mix deps.audit` is a mirror bug, still open.** gun's real
vulnerable range for `GHSA-w4f7-4cxr-rv3c` is `< 2.4.0`. The mirego importer groups by
`ghsaId` alone, collapsing a two-package advisory into `packages/gun/GHSA-w4f7-4cxr-rv3c.yml`
carrying **cowboy's** `< 2.16.0` range as well, so every real gun release (latest 2.8.0)
matches a range that was never gun's. There is no gun 2.16.x. Filed as
**`mirego/elixir-security-advisories#8`** (issue) and **#9** (PR), both still open as of
2026-11-25 with the mirror at upstream tip. Repos suppress exactly that one id via
`.mix_audit_ignore`; remove it once the mirror splits the advisory. This is a `mix_audit`
(mirego) finding only — Hex/OSV does not report it.

**🚨 `bandit` is NOT in this adjudication — it has a real fix.** `EEF-CVE-2026-74836`
(HIGH) and `EEF-CVE-2026-75484` on bandit 1.12.4 are genuine; **1.12.5 (2026-08-20) is
the fix**. Bump the dependency; never add a bandit id to an ignore list. Blanket-ignoring
"all the CVE noise" buries a HIGH — suppress **per id**, only after a reachability
argument has been made for that specific id and no fixed release exists.

**cowlib in the lock (2026-11-25):** 2.22.0 in `mpp`, `onchain-stack`, `tapakly`,
`trading_dashboard`, `zen_websocket`. Older (will report 43966 and 113431 on `deps.get`
until bumped): `bourse`, `zen_mm` (2.21), `aave_sim`, `bourse_trading`, `zen_macro`,
`zen_quant` (2.20), and several dormant repos below that. Suppression of the gun mirror bug
is inconsistent: most carry `.mix_audit_ignore`, bourse uses an `--ignore-advisory-ids`
alias in `mix.exs`. Standardize on `.mix_audit_ignore` when you touch one.

**tapakly is the exception on the Hex side — global ignores do not reach its gate.**
`mix tapakly.deps.audit` runs `hex.audit` in a throwaway project with a fresh `HEX_HOME`
and empty `HEX_IGNORE_*`, so `mix hex.config ignore_advisories` and the env var have no
effect there. Its only suppression is the committed `.hex_audit_adjudications.json`: one
entry per advisory id + package + exact locked version, with `reason` and `remove_when`.
The gate fails when an id is reported for a locked package the file does not name, or
when a named package no longer carries it at that version (bump / fix / withdrawal) —
so a stale entry re-reds the gate instead of silently lingering. Edit that file, not the
global config, when tapakly's gate reports an adjudicated id.

## ADJUDICATED: assent `EEF-CVE-2026-117656` — not reachable in password-only apps

`EEF-CVE-2026-117656` (CRITICAL; aliases `CVE-2026-117656`, `GHSA-9fr5-g44g-9526`):
`Assent.Strategy.Apple.callback/2` merges the client-controlled `user` callback parameter
over the verified ID-token claims (Sign in with Apple). Affected `>= 0.1.25 < 0.3.2`;
fixed in **assent 0.3.2** (2026-10-28). <https://osv.dev/vulnerability/EEF-CVE-2026-117656>

assent arrives transitively through `ash_authentication`, and **ash_authentication 4.15.1
pins assent `> 0.2.0 and < 0.3.0`**, so the fix is not resolvable (verified 2026-11-07).
The vulnerable code runs only behind an Apple strategy. **Verdict for a repo whose
AshAuthentication config has only the `password` strategy and no direct Assent call
(tapakly, `lib/tapakly/accounts/user.ex`): not reachable.** Do not `override:` assent to
0.3.x under 4.15.1.

**Invalidated when:** the repo adds any `apple` / `oauth2` / `oidc` (or other Assent-backed)
strategy — then the finding is real. **Remove when** an ash_authentication release accepts
assent `>= 0.3.2`: bump both and delete the adjudication entry.

**The meta-lesson this section encodes:** the analysis had in fact been done correctly —
it lived in `zen_websocket/mix.exs` and `.mix_audit_ignore`, where no other repo's agent
ever looks. A verdict that isn't written where the *next* agent reads it gets re-derived
forever. Adjudicate once, then put it in `CLAUDE.md` (which flows into `AGENTS.md` for
the cross-family reviewers) — not only in the repo that happened to notice.

## Suppressing Sobelow False Positives — Annotation for Source, `.sobelow-skips` for Config

Two mechanisms, both honored by `mix sobelow --skip` (sobelow 0.18, verified on tapakly
2026-11-07):

- **Source findings → inline annotation.** `# sobelow_skip ["Check.Module"]` immediately
  above the `def`/`defp`, after any `@doc`/`@spec`, with the trust-boundary reason beside
  it. It moves with the function, so line shifts don't re-red it. (An older note here
  claimed inline comments were ignored, from a 2026-06 hook run; that does not hold for
  `--skip` on sobelow 0.18.)
- **Findings with no function to annotate (e.g. `Config.Secrets` in `config/*.exs`) →
  `.sobelow-skips`**, lines of `FindingType,file:line,HASH`. Commit it with the code.

Before suppressing either way, confirm the finding is a genuine false positive (path is
operator/CLI-derived or a fixed dir + content hash, never untrusted/web input). Real
traversal risk → fix the code.

**Line shifts INVALIDATE `.sobelow-skips` entries** — the line number feeds the hash, so
inserting or deleting lines above a skipped finding re-reds the gate.

**🚨 `--mark-skip-all` ignores inline annotations — it marks EVERY finding.** Observed
tapakly 2026-11-07: `rm .sobelow-skips && mix sobelow --mark-skip-all` wrote 86 entries,
including every annotated source finding — a wholesale suppression that would survive
annotation removal. It also never prunes stale entries. So never commit its raw output.
Regenerate like this: run `mix sobelow --skip --format compact` to see what is actually
outstanding, then `--mark-skip-all` into the file and **cut it down to exactly the
intended entries** (e.g. `grep '^Config.Secrets: '`), verify zero findings with
`mix sobelow --skip --exit low`, and review the diff before committing.

Pairs with `critical-rules.md` § FIX HOOK-FLAGGED ISSUES: suppression IS the fix for a
documented false positive — but via the file, not a comment the hook ignores.
