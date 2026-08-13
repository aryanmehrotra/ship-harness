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
  "caps":       { "planReviewA": 3, "planReviewB": 2, "reviewA": 3, "reviewB": 2, "evidenceFix": 2 },
  "reviewers":  { "correctness": "sonnet", "design": "opus" },
  "memoryCaps": { "map": 100, "patterns": 60, "decisions": 40, "scars": 30, "glossary": 40, "conventions": 40 },
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
| `planReviewA` | `3` | plan-correctness rounds in S2.5, before the user sees the draft |
| `planReviewB` | `2` | plan-architecture rounds |
| `reviewA` | `3` | correctness rounds before handing findings to a human |
| `reviewB` | `2` | design rounds |
| `evidenceFix` | `2` | fix-and-recollect cycles |

The plan rounds are the cheapest of the five: a finding there costs a line of markdown,
the same finding in `reviewB` costs the implementation.

Raising these does not buy more quality. An uncapped review loop converges on approval,
because the reviewer knows the loop ends when it approves — see
[design-rules.md](design-rules.md#3-two-reviewers-different-models-no-write-tools-capped).

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

`/ship-harness:init` starts from one of these and then corrects it:

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
