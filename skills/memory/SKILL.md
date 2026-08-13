---
name: memory
description: Set up a repo for the harness, build docs/memory from git history, re-verify and prune it, or learn one specific thing on demand. Figures out which of those the repo needs. Use when the user says /ship-harness:memory, asks to set up, onboard, backfill, refresh, prune or teach the harness a repo, or when a ship or review run reports work owed.
---

# memory

Usage: `/ship-harness:memory` — with no argument, it works out what this repo needs and does
it. Or name one: `setup`, `build`, `refresh`, `learn <topic>`, `gaps`.

**You should rarely need to type this.** `ship` and `review` run the same preflight and heal
what they find, because a harness that requires you to know that `backfill` exists has moved
its own maintenance onto you.

## What does this repo need?

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/preflight.sh"
```

`needs[]` comes back ordered, and each entry is a precondition for the next:

| need | Means | Do |
|---|---|---|
| `init` | no `ship.config.json` | **Set up**, below |
| `confirm-budgets` | `setup.confirmedAt` is null | **Confirm the budgets**, below |
| `backfill` | memory is empty and the repo has real history | **Build**, below |
| `refresh` | memory is 30+ days unverified, or gaps are open | **Refresh**, below |

Empty `needs[]` means the repo is ready; say so in one line rather than finding work.

---

## Set up

### 1. Look before you write

```bash
git rev-parse --show-toplevel || echo "NOT A GIT REPO"
ls package.json go.mod Cargo.toml pyproject.toml pom.xml Gemfile 2>/dev/null
```

The harness needs a git repository — precedent mining, the plan-commit gate and the build
worktree all depend on it. No repo: say so and stop, rather than scaffolding files that
cannot work.

Never overwrite an existing `ship.config.json`. Create only what is missing.

### 2. Pick a preset, then correct it

| Signal | Preset | Gives you |
|---|---|---|
| `package.json` with a web framework, or `app/`/`pages/` | `web.json` | tests + screenshots |
| `go.mod`, or a service with HTTP handlers and no UI | `service.json` | tests + request/response pairs |
| a binary entrypoint, `cmd/`, `bin/`, a published CLI | `cli.json` | tests + golden CLI output |
| anything else, or unsure | `minimal.json` | tests only |

```bash
cp "${CLAUDE_PLUGIN_ROOT}/templates/presets/<preset>.json" ship.config.json
mkdir -p docs/plans docs/memory docs/adr .evidence
cp -n "${CLAUDE_PLUGIN_ROOT}/templates/memory/"*.md docs/memory/
cp -n "${CLAUDE_PLUGIN_ROOT}/templates/conventions.md" docs/conventions.md
cp -n "${CLAUDE_PLUGIN_ROOT}/templates/adr.md" docs/adr/0000-template.md
echo plan > .evidence/phase
grep -q 'ship-harness' .gitignore 2>/dev/null \
  || cat "${CLAUDE_PLUGIN_ROOT}/templates/gitignore-snippet" >> .gitignore
```

`cp -n` throughout: never clobber a memory file or a `conventions.md` that already has
content.

Then fix the three fields a preset cannot guess, and **say which you changed**:

1. **`collectors[].config.cmd`** — the repo's real test command, from `package.json`, the
   `Makefile`, or CI. A default that does not run is worse than no collector: it fails on the
   first run and teaches the user to ignore failures.
2. **`testPaths`** — globs that actually match this repo's tests. A glob matching nothing
   protects nothing, and it fails silently.
3. **`tracker.kind`** — `github` if `gh auth status` succeeds and there is a GitHub remote,
   else `none`.

For a web preset, `routes` decides how much the harness can see, and no agent can write it —
only the user knows which routes, viewports, themes and signed-in states matter.

### 3. Verify the ignore rules

The one setup step whose failure stays invisible until the repo is full of screenshots:

```bash
mkdir -p .evidence/baseline && touch .evidence/baseline/.keep .evidence/probe.json
git check-ignore -v .evidence/probe.json          # expect: ignored
git check-ignore -v .evidence/baseline/.keep      # expect: NOT ignored (exit 1)
rm -f .evidence/probe.json
```

Baselines are committed on purpose — they are the oracle. Everything else in `.evidence/` is
disposable.

### 4. Baselines

Only possible once the app runs, so walk the user through it rather than guessing:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/collect.sh" --baseline
git add .evidence/baseline && git commit -m "chore: record ship-harness baselines"
```

If `collect.sh` exits `2` a collector could not run. Fix that first: a baseline captured from
a broken app enshrines the breakage as expected, and every later run will agree with it.

Finally, warn loudly if `CLAUDE_CODE_SUBAGENT_MODEL` is set — it overrides per-subagent models
and silently collapses the two review tiers into one model reviewing itself.

---

## Confirm the budgets — do not skip, do not assume

**`ship` and `review` refuse to run until this is answered.** These numbers decide how many
rounds, and how much money, every future run spends. A budget nobody chose is a default nobody
owns.

Show the table, say what each buys, ask for a yes or a change — **one message, then wait.**

| Cap | Default | What it bounds |
|---|---|---|
| `planReviewA` / `planReviewB` | 3 / 2 | rounds reviewing the plan before the user sees it |
| `reviewA` / `reviewB` | 3 / 2 | rounds reviewing the diff |
| `reviewDelta` | 2 | blind plan-vs-plan rounds in `review` |
| `spikes` | 3 | throwaway probes that answer an open question with a number |
| `research` | 3 | official-source lookups where the repo has no precedent |
| `evidenceFix` | 2 | fix-and-recollect cycles |

**`0` means no fixed cap** — the loop runs until a round produces no new findings. Say the
tradeoff out loud, because it is real:

> A count stops a loop still making progress, and lets a loop going in circles run to the
> limit; convergence is the better signal. But a reviewer knows the loop ends when it
> approves, so an unbounded loop drifts that way. Uncapped, no round may approve while it is
> still raising findings, and every round is logged — so a run that "converged" on round nine
> looks like one.

```bash
jq --arg d "$(date -u +%Y-%m-%d)" '.setup = {confirmedAt: $d}' ship.config.json > .tmp \
  && mv .tmp ship.config.json
```

If the user would rather not decide, leave it null and say plainly that the next run will ask
again. That is the design.

---

## Build — `docs/memory/` from history

Derived and disposable: if it ever gets weird, delete `docs/memory/` and rebuild.

### 1. Rank deterministically before reading anything

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/precedent-scan.sh" --backfill
```

Churn ranking, reverts and hotfixes, co-change coupling, authorship by subsystem, and files
rewritten three or more times — which is almost always an unresolved design problem and always
worth a line. Git already knows where the action is; paying a model to rediscover it produces
a worse answer at a much higher price.

### 2. Read only the top slice, in date order

One quarter at a time; merge and dedupe at the end. Never a single pass over the whole
history — it exhausts context and produces confident mush, which is harder to detect and much
harder to undo than an empty file.

### 3. Six files, one format

| File | Holds | Cap |
|---|---|---|
| `docs/memory/map.md` | domain → paths. The highest-value file here. | 100 lines |
| `docs/memory/patterns.md` | conventions with two or more usages | 60 lines |
| `docs/memory/decisions.md` | implicit ADRs recovered from history | 40 lines |
| `docs/memory/scars.md` | reverts, hotfixes, rollbacks | 30 lines |
| `docs/memory/glossary.md` | domain term → code symbol | 40 lines |
| `docs/memory/references.md` | official sources a decision rested on | 40 lines |

`references.md` is the one file this step leaves empty: git records what was decided, not
which RFC section was open at the time. It fills as `ship` and `review` consult real sources
— inventing entries would be inventing citations.

Every line carries provenance and is re-checkable by grep:

```
- All HTTP handlers return Result<T, AppError>, never throw.
  seen: 14 files · e.g. src/api/user.ts:22 · since a3f21c9 2025-03 · verified 2026-08-13 · confidence: high
```

`confidence: low` at two usages is the honest form. Two usages can be one decision, or one
copy-paste nobody has questioned, and memory cannot tell those apart.

### 4. Two rules that keep this worth having

**Git records what changed, not why.** Do not invent rationale. `decisions.md` takes only
corroborated lines — a revert, a PR discussion, a postmortem. Everything else is an observed
regularity in `patterns.md`, unexplained. An invented rationale is worse than a missing one:
it gets cited in a plan, survives review because it reads well, and steers a decision it was
never evidence for.

**Nothing lives only in memory.** Every line points at code. When memory and code disagree,
the code is right and the line is a bug to fix now.

Commit as `memory: backfill from history`, on its own.

---

## Refresh — re-verify and prune

Every memory line is a grep, so verification is mechanical rather than a judgement call —
which is the only reason this stays cheap enough to actually happen.

1. **Re-run each line's grep.** Count dropped or path gone → mark `STALE`. Do not delete yet:
   one bad refresh should not silently erase real knowledge.

   **`references.md` is the exception** — its lines cite things outside the repo, so a grep
   proves nothing. For a dependency claim, check the version still matches the manifest and
   re-open the cited `file:symbol`; for a doc, paper or RFC, re-open the cited section. A line
   whose pinned version has moved on is `STALE` even if it was true when written — an upgrade
   is exactly when library behaviour stops matching what someone remembered. A citation that
   cannot be opened at all is deleted on the first pass: an unopenable source is not
   knowledge, and leaving it lends it credibility it never earned.
2. **`STALE` twice running → delete**, and log the commit that killed it.
3. **`verified:` older than 90 days → re-verify or drop.**
4. **Enforce `memoryCaps`.** Over cap → merge duplicates first, then drop the
   lowest-confidence lines. **Never grow a file to fit**; the cap is what forces the
   merge-or-drop decision that otherwise never gets made.
5. **Promote confidence only on evidence.** `low → high` needs five or more usages or a cited
   revert, PR or postmortem. A line does not become true by surviving.
6. **Where memory and code disagree, the code wins.** Fix it in this pass.

### The check worth more than the other six

```bash
git log -p -10 -- docs/plans/ | grep -E '^[-+].*\[(R|P)\]'
```

A citation the user keeps striking out means the memory is **confidently wrong** — the most
expensive state this system can be in, because it is being cited in plans, it reads as
evidence, and it survives review by looking like a fact. Delete that line. Do not soften it,
do not lower its confidence, do not leave it for next time.

Commit as `memory: refresh <date>`, separately from any code change.

---

## Learn — close one gap on demand

`/ship-harness:memory learn <topic>` when you want the harness to understand something
specific before it works on it: a subsystem, a dependency, a protocol, a failure everyone
already knows about.

1. **Repo first.** `precedent-scan.sh "<topic>"`, then read the closest code. Most "the
   harness doesn't understand X" is really "nobody has pointed it at X yet".
2. **Then official sources**, under the same rules `ship` and `review` follow: the project's
   own docs or source at the version this repo pins, the standards body's own document.
   Tutorials, mirrors, StackOverflow and AI summaries are pointers, never citations.
3. **Write what you learned as memory lines**, in the right file, with provenance — not as a
   summary in the chat, which evaporates. A `learn` that ends in prose taught nobody anything.
4. **Close the gap** in `.evidence/memory-gaps.md` if it was open.

## Gaps — the harness's own to-do list

`.evidence/memory-gaps.md` holds questions a previous run could not answer from memory. `ship`
and `review` append to it whenever they have to research something the repo should have known:

```
- <what was needed> — needed by: <TICKET|PR>, <date> — resolved: <memory line | still open>
```

This is the difference between a harness that gets better at a repo and one that merely gets
older. Work them off in `refresh`, oldest first, and delete the line when the knowledge lands
in `docs/memory/`.
