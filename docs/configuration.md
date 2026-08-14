# Configuration

Everything lives in one file at the repo root: `ship.config.json`. Validated by
[`schema/ship.config.schema.json`](../schema/ship.config.schema.json) — point your editor at
the `$schema` key for completion.

```json
{
  "$schema": "https://raw.githubusercontent.com/aryanmehrotra/ship-harness/main/schema/ship.config.schema.json",
  "tracker":    { "kind": "github" },
  "testPaths":  ["**/*_test.go", "test/**"],
  "attribution": false,
  "setup":      { "confirmedAt": "2026-08-13" },
  "caps":       { "research": 3, "reviewDelta": 2, "spikes": 3, "planReviewA": 3, "planReviewB": 2, "reviewA": 3, "reviewB": 2, "evidenceFix": 2 },
  "reviewers":  { "correctness": "sonnet", "design": "opus" },
  "memoryCaps": { "map": 100, "patterns": 60, "decisions": 40, "scars": 30, "glossary": 40, "references": 40, "conventions": 40 },
  "collectors": [ { "name": "tests", "kind": "builtin:tests", "config": { "cmd": "go test ./..." } } ]
}
```

## `tracker`

| Field | Values | Default |
|---|---|---|
| `kind` | `github`, `none` | `none` |

`github` needs an authenticated `gh` and a GitHub remote. `none` keeps the status in
`.evidence/status.md`, so the resume guarantee holds without any tracker at all.

Adding another is four verbs — see [trackers.md](trackers.md).

## `testPaths`

Globs the phase guard freezes during the `review` and `fix` phases.

```json
"testPaths": ["tests/**", "**/*_test.go", "spec/**", "**/*.test.ts"]
```

`*` spans `/`, so `tests/**` is recursive. A leading `**/` is also matched stripped, so
`**/*_test.go` catches `foo_test.go` at the repo root as well as `pkg/foo_test.go`.

**Check these against your repo.** A glob that matches nothing protects nothing, and it fails
silently — the guard simply never fires, and nothing tells you. To verify:

```bash
echo review > .evidence/phase
# ask Claude to edit one of your test files — it should be blocked with an explanation
echo build > .evidence/phase
```

Defaults for common ecosystems are built into the hook, used only when the config lists none.

## `attribution`

`false` (default) means generated PR bodies, reports and status comments carry **no**
AI-assistance footer, co-author trailer or generation notice. Set `true` if your project
requires disclosure.

## `caps`

| Field | Default | Limits |
|---|---|---|
| `research` | `3` | official-source lookups for decisions the repo has no precedent for |
| `reviewDelta` | `2` | blind plan-vs-plan comparison rounds in `/ship-harness:review` |
| `spikes` | `3` | throwaway probes run in S2.5 to answer an open question with a number |
| `planReviewA` | `3` | plan-correctness rounds in S2.5, before the user sees the draft |
| `planReviewB` | `2` | plan-architecture rounds |
| `reviewA` | `3` | correctness rounds before handing findings to a human |
| `reviewB` | `2` | design rounds |
| `evidenceFix` | `2` | fix-and-recollect cycles |

The plan rounds are the cheapest of the five: a finding there costs a line of markdown,
the same finding in `reviewB` costs the implementation.

`spikes` bounds the other direction. A spike answers one open question with ~30 lines of
throwaway code, which is cheap; an unbounded spike loop is building the thing twice, once
badly. At the cap the harness hands the open question to a human instead.

**`0` means no fixed cap.** The loop then runs until a round produces no new findings. Two
rules make that safe: no round may approve while it is still raising findings, and every round
is logged, so a run that converged on round nine is visible as one.

Which to pick is a real trade-off, not a default to accept quietly. A count stops a loop that
is still making progress and lets a loop going in circles run to the limit. Convergence is the
better signal — but a reviewer knows the loop ends when it approves, so unbounded loops drift
that way; see
[design-rules.md](design-rules.md#3-two-reviewers-different-models-no-write-tools-capped).

## `setup`

```json
"setup": { "confirmedAt": "2026-08-13" }
```

Written once you have seen the caps table and confirmed or changed it — the first `ship` or
`review` run asks if it is missing.
**`ship` and `review` refuse to run while this is null or missing** — they stop and ask.

That gate exists because these numbers decide how many rounds, and how much money, every
future run spends. A budget nobody chose is a default nobody owns, and defaults get noticed
only after the bill.

## `reviewers`

```json
"reviewers": { "correctness": "sonnet", "design": "opus" }
```

Two **different** models is the point. Two runs of one model share its blind spots, and the
second round stops paying for itself.

Related, and worth checking once: if `CLAUDE_CODE_SUBAGENT_MODEL` is set in your environment
it overrides both of these and collapses the tiers without saying so.

## `memoryCaps`

Hard line caps on `docs/memory/*` and `docs/conventions.md`. Over cap, `refresh` merges
duplicates first, then drops the lowest-confidence lines. It never grows a file to fit — the
cap exists to force a decision that otherwise never gets made.

## `env`

Optional. How to tell when this repo's environment is serving.

```json
"env": { "ready": "curl -fsS http://localhost:4081/health", "readyTimeout": 90 }
```

`collect.sh` runs `ready` before any collector and waits for it to succeed. If it never
does, the run exits `2` — BROKEN — naming the command that never passed, rather than
letting every collector discover the same outage separately.

| Key | Meaning |
|---|---|
| `ready` | shell command; success means the environment is serving |
| `readyTimeout` | seconds to wait before reporting BROKEN (default 90) |

There is deliberately no `up` and no `down`. The harness declares what ready means and
waits; it never starts your stack. Anything that can start an environment eventually
becomes the thing that left it running, and two components that both believe they own a
lifecycle will disagree while you are debugging something else.

That is not a limitation in practice, because with an on-demand sandbox **connecting is
what starts things**. Point `ready` at the port and the act of checking is the act of
waking:

```json
"env": { "ready": "sbx ready $SBX_SANDBOX", "readyTimeout": 120 }
```

This closes a hole the [collector contract](../collectors/CONTRACT.md) already names: every
collector is told to exit `2` when its target is unreachable, and until now each one had to
find that out on its own.

## `collectors`

An array, run in order. Each entry needs a `name`, and exactly one of `kind` or `cmd`.

```json
{ "name": "web", "kind": "builtin:web-shots", "config": { } }
{ "name": "rowcounts", "cmd": "./scripts/rowcounts.sh" }
```

| Field | Meaning |
|---|---|
| `name` | lowercase/dashes. Report → `.evidence/<name>.json`, baselines → `.evidence/baseline/<name>/` |
| `kind` | one of `builtin:web-shots`, `builtin:http-pairs`, `builtin:cmd-golden`, `builtin:tests` |
| `cmd` | any executable obeying [the contract](../collectors/CONTRACT.md) |
| `config` | passed verbatim to the collector as `SHIP_COLLECTOR_CONFIG` |

Per-collector `config` options are documented in
[evidence-collectors.md](evidence-collectors.md).

## Presets

Setup starts from one of these and then corrects it:

| Preset | For | Collectors |
|---|---|---|
| `web.json` | web apps | `tests` + `web-shots` |
| `service.json` | Go/HTTP services | `tests` + `http-pairs` |
| `cli.json` | CLIs and codegen | `tests` + `cmd-golden` |
| `minimal.json` | everything else | `tests` |

A preset is a starting point, never a finished config. The test command and the routes or
request list are the two things it cannot know, and they are the two that decide how much the
harness can actually see.

## Files the harness owns

| Path | Committed? | Notes |
|---|---|---|
| `ship.config.json` | yes | this file |
| `docs/plans/*.md` | yes | the contracts; committing one is the approval |
| `docs/memory/*.md` | yes | derived and disposable — safe to delete and rebuild |
| `docs/conventions.md` | yes | learned from your plan edits |
| `.evidence/baseline/**` | **yes** | the oracle |
| everything else in `.evidence/` | no | per-run output |
