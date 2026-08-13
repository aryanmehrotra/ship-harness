# Getting started

From nothing to a first shipped ticket. Budget about twenty minutes, most of it spent on one
file that matters.

## 0. Requirements

| Need | Why |
|---|---|
| a **git repository** | precedent mining, the plan-commit gate and the build worktree all depend on it |
| `jq` | config parsing in every script |
| `gh`, authenticated | only if you want GitHub as the tracker; `none` works fine without it |
| `node` ≥ 18 | only for the `web-shots` collector |

One thing to check before the first run:

```bash
echo "${CLAUDE_CODE_SUBAGENT_MODEL:-unset}"     # must print: unset
```

If it is set, it overrides per-subagent models and silently collapses the two review tiers
into one model reviewing its own work. The pipeline still runs; it just stops being worth
running.

## 1. Install

```bash
/plugin marketplace add aryanmehrotra/ship-harness
/plugin install ship-harness
```

## 2. Initialise the repo

```bash
cd ~/code/your-repo
/ship-harness:init
```

It detects your stack, picks a preset, writes `ship.config.json`, scaffolds
`docs/{plans,memory,adr}`, appends ignore rules, and — importantly — tells you which fields
it had to guess.

Read what it changed. The test command and `testPaths` are guesses until you confirm them,
and a `testPaths` glob that matches nothing silently protects nothing.

## 3. Record the baseline

The baseline is the oracle. Everything later is a comparison against it, so it has to be
recorded from a working app.

```bash
npm run dev &            # or: go run ./cmd/api &   — whatever brings your app up
bash "$(...)/scripts/collect.sh" --baseline
git add .evidence/baseline && git commit -m "chore: record ship-harness baselines"
```

If that exits `2`, a collector could not run. Fix it before recording — a baseline captured
from a broken app makes the breakage the expected state, and every future run will agree.

## 4. Build the precedent index

```bash
/ship-harness:backfill
```

Reads git history in slices and writes `docs/memory/` — a citation index of patterns,
decisions, scars, and where things live. Every line is a grep you can re-run. Commit it.

Expect this to be imperfect on the first pass. It is derived and disposable; the monthly
`/ship-harness:refresh` is what makes it trustworthy over time.

## 5. Ship something

```bash
/ship-harness:ship T-123
```

**First invocation** mines precedent, asks at most five questions, writes
`docs/plans/T-123.md`, puts that draft through two model review rounds — round 1 for
concreteness, correctness and reliability, round 2 for architecture, scale and blast radius
— and stops. The findings land in `.evidence/plan-review-a.json` and `-b.json` if you want
to see what it argued with itself about.

The plan fits one screen: bullets, no paragraphs, and a `Shape` section with an ASCII
diagram of what the change touches — nodes marked `*` are the ones it adds or modifies.
Read that diagram first; if the boxes are wrong, nothing below them is worth checking.

Now do the part only you can do: read the plan. Look at the `Precedent` section next — the
`[R]` and `[P]` lines are claims about your repo, with paths. Open one or two. If a citation
is wrong, that is worth more than anything else you could correct, because a wrong citation
survives review by looking like evidence.

Fix the plan and commit it. **That commit is the approval.**

```bash
git add docs/plans/T-123.md && git commit -m "plan: T-123"
/ship-harness:ship T-123
```

**Second invocation** builds in a worktree on `claude/T-123` (tests first), runs both review
rounds, collects evidence, and publishes one report.

## 6. What to look at first

Open the report and read in this order:

1. **The verdict line.** Shipped, blocked, or needs a decision.
2. **The three things it says to check.** They have anchor links.
3. **The red flags.** At most five, ranked.

Then, if you want to check the harness rather than the change: open `.evidence/review-b.json`
and see whether round B caught anything round A approved. That is the tier-1 miss count, and
it is the honest measure of whether two rounds are earning their cost in your repo.

## Where things live afterwards

```
docs/plans/T-123.md          the contract, committed
docs/memory/*.md             the precedent index, derived and disposable
docs/conventions.md          rules learned from YOUR edits to its plans
.evidence/baseline/          committed — the oracle
.evidence/evidence.json      last run's aggregate verdict
.evidence/review-{a,b}.json  what each reviewer actually said
.evidence/phase              what stage the run is in (the hook reads this)
```

## If a run dies halfway

Nothing is lost. `.evidence/phase` says where it was, the status comment says what happened,
and the branch has the commits. Re-run the same command.

That is the whole point of the fourth rule: state that is not in the tracker does not exist,
so every run is resumable by construction rather than by luck.
