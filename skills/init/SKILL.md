---
name: init
description: Set up the current repository for the ship-harness — detect the stack, write ship.config.json, scaffold docs/plans, docs/memory, docs/adr and .evidence, and append the ignore rules. Use when the user says /ship-harness:init, asks to set up or onboard a repo for the harness, or runs /ship-harness:ship in a repo with no ship.config.json.
---

# init

Run once per repo. Idempotent — running it again fixes what is missing and touches nothing
that already exists.

## 1. Look before you write

```bash
git rev-parse --show-toplevel || echo "NOT A GIT REPO"
ls package.json go.mod Cargo.toml pyproject.toml pom.xml Gemfile 2>/dev/null
test -f ship.config.json && echo "ALREADY INITIALISED"
```

The harness needs a git repository — precedent mining, the plan-commit approval gate and the
worktree all depend on it. If there is no repo, say so and stop rather than scaffolding files
that cannot work.

If `ship.config.json` already exists, do not overwrite it. Report what is present, create
only the missing pieces, and stop.

## 2. Pick a preset, then correct it

| Signal | Preset | Gives you |
|---|---|---|
| `package.json` with a web framework, or an `app/`/`pages/` dir | `web.json` | tests + screenshots |
| `go.mod`, or a service with HTTP handlers and no UI | `service.json` | tests + request/response pairs |
| a binary entrypoint, `cmd/`, `bin/`, or a published CLI | `cli.json` | tests + golden CLI output |
| anything else, or you are not sure | `minimal.json` | tests only |

```bash
cp "${CLAUDE_PLUGIN_ROOT}/templates/presets/<preset>.json" ship.config.json
```

Then **fix the three fields a preset cannot guess**, and tell the user you changed them:

1. **`collectors[].config.cmd`** — the repo's real test command. Find it in `package.json`
   scripts, the `Makefile`, or CI. A preset default that does not run is worse than no
   collector, because it fails on the first run and teaches the user to ignore failures.
2. **`testPaths`** — the globs that actually match this repo's tests. Check where the test
   files really live; the defaults cover common cases and will silently protect nothing if
   this repo is unusual.
3. **`tracker.kind`** — `github` if `gh auth status` succeeds and the repo has a GitHub
   remote, otherwise `none`.

For a web preset, leave `routes` as `["/"]` and say clearly that this is the file that
decides how much the harness can actually see. No agent can write it — nobody but the user
knows which routes, viewports, themes and signed-in states matter. It is the highest-leverage
file in the setup, and an unedited default is the most likely reason a real regression slips
through.

## 3. Scaffold

```bash
mkdir -p docs/plans docs/memory docs/adr .evidence
cp -n "${CLAUDE_PLUGIN_ROOT}/templates/memory/"*.md docs/memory/
cp -n "${CLAUDE_PLUGIN_ROOT}/templates/conventions.md" docs/conventions.md
cp -n "${CLAUDE_PLUGIN_ROOT}/templates/adr.md" docs/adr/0000-template.md
echo plan > .evidence/phase
```

`cp -n` throughout: never clobber a `docs/conventions.md` or a memory file that already has
content in it.

## 3.5 Confirm the loop budgets — do not skip, do not assume

**The harness refuses to run until the user has confirmed these.** A budget nobody chose is a
default nobody owns, and these decide how many rounds — and how much money — every future run
spends.

Show the table, say what each one buys, and ask for a yes or a change. **One message, then
wait for the answer.** Do not proceed because the defaults look reasonable.

| Cap | Default | What it bounds |
|---|---|---|
| `planReviewA` / `planReviewB` | 3 / 2 | rounds reviewing the plan before the user sees it |
| `reviewA` / `reviewB` | 3 / 2 | rounds reviewing the diff |
| `reviewDelta` | 2 | blind plan-vs-plan rounds in `/ship-harness:review` |
| `spikes` | 3 | throwaway probes that answer an open question with a number |
| `research` | 3 | official-source lookups where the repo has no precedent |
| `evidenceFix` | 2 | fix-and-recollect cycles |

**`0` means no fixed cap** — the loop runs until a round produces **no new findings**, then
stops. Say the tradeoff out loud when you ask, because it is a real one:

> A count stops a loop that is still making progress, and lets a loop going in circles run
> all the way to the limit; convergence is the better signal. But a reviewer knows the loop
> ends when it approves, so an unbounded loop drifts toward approval. Uncapped, no round may
> approve while it is still raising findings, and every round is logged — so a run that
> "converged" on round nine is visible as one.

Record the answer, and only then is the repo initialised:

```bash
jq --arg d "$(date -u +%Y-%m-%d)" '.setup = {confirmedAt: $d}' ship.config.json > .tmp \
  && mv .tmp ship.config.json
```

If the user would rather not decide now, leave `confirmedAt: null` and tell them plainly that
`ship` and `review` will stop and ask on first use. That is the design, not a bug.

## 4. Ignore rules — append, never replace

```bash
grep -q 'ship-harness' .gitignore 2>/dev/null \
  || cat "${CLAUDE_PLUGIN_ROOT}/templates/gitignore-snippet" >> .gitignore
```

Check the negation actually holds, because this is the one setup step whose failure is
invisible until the repo is full of screenshots:

```bash
mkdir -p .evidence/baseline && touch .evidence/baseline/.keep .evidence/probe.json
git check-ignore -v .evidence/probe.json          # expect: ignored
git check-ignore -v .evidence/baseline/.keep      # expect: NOT ignored (exit 1)
rm -f .evidence/probe.json
```

Baselines are committed on purpose — they are the oracle every later run is compared against.
Everything else under `.evidence/` is disposable.

## 5. Record the baseline

Only possible once the app runs. Walk the user through it rather than guessing:

```bash
# start the dev server / build the binary / bring the service up, then:
bash "${CLAUDE_PLUGIN_ROOT}/scripts/collect.sh" --baseline
git add .evidence/baseline && git commit -m "chore: record ship-harness baselines"
```

If `collect.sh` exits `2`, a collector could not run — an unreachable server or a missing
dependency. Fix that before recording anything: a baseline captured from a broken app
enshrines the breakage as the expected state, and every future run will agree with it.

## 6. Report what you did

Print the created files, the preset chosen, **each field you corrected and why**, and the
next two commands:

```
/ship-harness:backfill      # once — builds docs/memory from git history
/ship-harness:ship <TICKET> # the daily loop
```

Finally, check for a `CLAUDE_CODE_SUBAGENT_MODEL` environment variable. If it is set, warn
loudly: it overrides per-subagent models and silently collapses the two review tiers into one
model reviewing itself, which removes the independence that makes round B worth running.
