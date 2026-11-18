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

**The verdict — cowlib reached only via `gun` as a WebSocket client (the
`zen_websocket` stack): not reachable.** Evidence is a call-graph fact, not a judgment
call:

| Advisory | Vulnerable function | Reachability |
|---|---|---|
| `EEF-CVE-2026-43966` (alias `GHSA-w4f7-4cxr-rv3c`, `CVE-2026-43966`) | `cow_http_struct_hd:escape_string/2` | **0 references** in `deps/gun/src/`; reached only via the structured-header serializers (`cow_http_struct_hd:item/list/dictionary`, `cow_http_hd:variant_key/variants/wt_available_protocols/wt_protocol`), and gun calls only `cow_http_hd:parse_*` |
| `EEF-CVE-2026-113431` (alias `CVE-2026-113431`, HIGH, published 2026-11-06) | `cow_http2_machine:headers_decode/4` (unbounded decoded HPACK header list) | gun runs `cow_http2_machine` only in `gun_http2`/`gun_http3`; the only `:gun.open` caller, `ZenWebsocket.Reconnection.build_gun_opts/1`, forces `protocols: [:http]` and ALPN `["http/1.1"]`. Bandit (the Phoenix server) does not use cowlib |

**Fixed upstream — bump, never re-ignore.** These were removed from the global Hex
ignore list once a fixed cowlib shipped. If one reappears, the repo is on an older
cowlib: bump it.

| Advisory | Function | Fixed in (OSV range) | Removed from ignore list |
|---|---|---|---|
| `EEF-CVE-2026-43971` | `cow_link:link/1` | cowlib 2.20.0 (`>= 2.9.0 < 2.20.0`) | 2026-09-24 |
| `EEF-CVE-2026-43969` | `cow_cookie:cookie/1` | cowlib 2.21.0 (`>= 2.9.0 < 2.21.0`) | 2026-10-31 |

43966 (cowlib 2.21.0 / gun 2.7.0) and 113431 (cowlib 2.21.0) are still reported
(verified 2026-11-07, live `mix hex.audit` in tapakly; OSV lists no fixed cowlib release
for either), so reachability is the only available adjudication. Re-check at the next cowlib release. `hex.audit` in a repo without cowlib
(e.g. harness) warns the ignore "matches no advisory" — that is expected, not a sign it
is resolved.

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
values; any caller opens gun with `http2` / `http3` or advertises `h2` via ALPN
(invalidates 113431); or a new cowlib advisory appears that is not one of the ids above.

**Affected repos (cowlib in the lock):** `bourse`, `mpp`, `tapakly`, `zen_mm`, `zen_websocket`. As
of 2026-10-31 `mpp` and `zen_websocket` lock cowlib 2.21.0; `bourse` and `zen_mm` still
lock 2.20.0 and will now report 43969 on `deps.get` until bumped. The `onchain*` repos no longer lock cowlib. Suppression is inconsistent across them — most carry
`.mix_audit_ignore`, bourse uses an `--ignore-advisory-ids` alias in
`mix.exs`. Standardize on `.mix_audit_ignore` when you touch one.

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
