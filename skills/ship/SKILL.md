---
name: ship
description: Take a ticket from precedent through plan, build, two-model review, deterministic evidence and a published report. Use whenever the user says /ship, hands you a ticket or issue number, or asks you to take a piece of work from ticket through to a reviewable PR.
---

# ship

Usage: `/ship-harness:ship T-123` — any ticket, issue number, or a pasted description.

**Two invocations.** The first mines precedent, interviews you, writes a plan and stops. You
edit and commit that plan; the commit is the approval. The second invocation builds, reviews,
gathers evidence and publishes.

Throughout, `<TICKET>` means the identifier you were given. `$PLUGIN` means
`${CLAUDE_PLUGIN_ROOT}`.

**Precedence for every decision: code > `docs/memory` > docs.** Never cite a memory line
without opening the file it points at. Memory is an index of where to look; it is never the
answer.

## Before anything

```bash
test -f ship.config.json || echo "NOT INITIALISED — run /ship-harness:init first"
bash "$PLUGIN/scripts/tracker.sh" kind
```

If `ship.config.json` is missing, stop and tell the user to run `/ship-harness:init`. Do not
improvise the layout; every later step reads that config.

Write the phase at every transition. The `phase-guard` hook reads this file, so a stale value
is the difference between tests being frozen and not:

```bash
mkdir -p .evidence && echo plan > .evidence/phase
```

---

## S0 — Precedent (always, never skip)

Write findings to `.evidence/precedent.md` as you go, citing path and date on every line.

```bash
bash "$PLUGIN/scripts/precedent-scan.sh" "<domain terms>" <paths-likely-touched>
bash "$PLUGIN/scripts/tracker.sh" fetch <TICKET>
cat docs/memory/*.md docs/conventions.md 2>/dev/null
```

Then read, in this order — the order is the ranking, from most binding to least:

1. **Decisions** — matching files in `docs/adr/`, `docs/rfc/`, `docs/design/`. Note the
   status. A superseded ADR is evidence of what was tried and rejected; record *why* it was
   superseded, because that reason usually still applies.
2. **Prior plans** — `docs/plans/*.md` matching the terms. This is how the user scopes work
   like this one, which is more predictive than any style guide.
3. **Code precedent** — the two or three closest existing implementations. Where code and
   docs disagree, the code is the answer and the doc is a bug.
4. **Shipped precedent** — merged PRs matching the terms. Read the *review discussion*, not
   just the diff. The real constraints were argued there and never made it into a file.
5. **Scar tissue** — postmortems, reverts and hotfixes touching these paths.

**Reuse inventory.** Before proposing anything new, list every existing candidate with its
path: utilities, base classes, middleware, hooks, error types, config loaders, migration
helpers, test fixtures, CI jobs, and the current dependencies in the manifest.

### The reuse rule — binding

> If the repo already has something that does this, use it. Do not write a second one.

Covers utilities, patterns, abstractions, libraries, naming, file layout, error handling,
logging, config and test structure. Extend or refactor the existing thing.

You may propose something new **only** by writing, in the plan: the existing thing you found
(with its path), the specific reason it cannot be extended, and what extending it would cost
— then asking. "Cleaner", "more modern", "better typed" and "the old one is messy" are not
reasons. An existing pattern you dislike still wins. Consistency beats local quality, because
the cost of a second way to do something is paid by everyone who reads the repo afterwards.

A pattern used in **two or more** places is the convention, documented or not. Anything older
than twelve months: mark `STALE` and verify against current code before relying on it. If
sources conflict, say so — never pick silently. If you find no precedent, say that explicitly
after trying two more search terms.

---

## S1 — Interview (only the residue)

Draft the plan silently first, then classify every decision in it:

| Tag | Meaning | Action |
|---|---|---|
| `[R]` | reuses existing code or pattern | cite the path, do not ask |
| `[P]` | settled by precedent (ADR / PR / postmortem) | cite it, do not ask |
| `[D]` | deliberate divergence from precedent | precedent + reason + blast radius → **ask** |
| `[N]` | no precedent exists | **ask** |

Ask only about `[D]` and `[N]`, and only where a wrong answer costs more than an hour of
rework. **Maximum five questions, in one message**, numbered, multiple-choice where possible,
each carrying your recommendation and what changes if the user picks otherwise.

Never ask what S0 already answered. Never ask about naming, formatting, or anything
reversible in five minutes — those are your call, and asking about them spends the user's
attention on the cheapest decisions in the ticket.

If an `[N]` decision is architectural or hard to reverse, draft
`docs/adr/NNNN-<slug>.md` from `$PLUGIN/templates/adr.md` alongside the plan.

## S2 — Plan, then stop

Write `docs/plans/<TICKET>.md` from `$PLUGIN/templates/plan.md`, headings exactly as in the
template — S4 and S7 both parse them.

Then **stop and say so plainly.** The user edits the plan and commits it. That commit is the
approval gate. On the next invocation, do not proceed if `docs/plans/<TICKET>.md` is missing
or has uncommitted changes:

```bash
git diff --quiet -- "docs/plans/<TICKET>.md" && git ls-files --error-unmatch "docs/plans/<TICKET>.md"
```

## S3 — Build

```bash
git worktree add ../<repo>-<TICKET> -b claude/<TICKET>
echo build > .evidence/phase
```

Write and commit the tests for the acceptance criteria **before** any implementation code.
After that commit, tests are frozen: the `phase-guard` hook blocks edits to `testPaths` once
the phase leaves `build`, and it will explain itself if you try.

If a review finding is genuinely *about* a test, say so out loud, flip the phase back to
`build` for that single edit, and flip it forward again. The flip is visible in the run,
which is the entire mechanism — an agent quietly editing a test to make a finding disappear
is the failure this pipeline is built to prevent.

## S4 — Review (two read-only models, fresh context each round)

```bash
echo review > .evidence/phase
```

Give each reviewer exactly three things: the committed plan, `git diff`, and prior findings.
**Never the build transcript** — a reviewer that has read your reasoning reviews the
reasoning instead of the code.

- **Round A — `reviewer-correctness`.** Cap from `caps.reviewA` (default 3).
- **Round B — `reviewer-design`.** Only after A approves. Cap from `caps.reviewB` (default 2).

Each subagent has no write tools; it returns one JSON object as its final message. **You**
write it to `.evidence/review-a.json` and `.evidence/review-b.json`. That asymmetry is what
makes "reviewers cannot edit" a property of the system rather than a request in a prompt.

```json
{"verdict":"APPROVED|CHANGES_REQUESTED",
 "findings":[{"severity":"blocking|major|minor","file":"","line":0,
              "issue":"","why_it_matters":""}]}
```

Between rounds: `echo fix > .evidence/phase`, fix every `blocking` and `major` finding, then
re-run with fresh context. At the cap, stop and hand the open findings to the user.

**Never approve to end a loop.** If you notice yourself weighing "this is round three" as a
reason to approve, that is the bias the cap exists to catch — stop and hand it over instead.

## S5 — Evidence

```bash
echo evidence > .evidence/phase
bash "$PLUGIN/scripts/collect.sh"
```

Read `.evidence/evidence.json`. **Open only the artifacts named inside `failed[]`** — never
the full artifact set, and never an image that is not in a failed entry. That restriction is
what keeps this step affordable, and it is why collectors are required to explain themselves
in `failed[].why`.

Classify each failure as **INTENDED**, **REGRESSION**, or **NOISE**:

- A console error or a failed network request is a REGRESSION. There is no judgement call to
  make and no context in which one is fine.
- NOISE means the collector is watching something non-deterministic. Fix the collector — add
  a `mask` or a `redact` pattern — do not raise the tolerance. A threshold loose enough to
  swallow a clock is loose enough to swallow a layout break elsewhere on the page.
- INTENDED means the baseline should move. That requires a written reason:
  `echo "<why>" > .evidence/rebaseline-reason`, which the guard checks and the report quotes.

Fix and re-run, capped at `caps.evidenceFix` (default 2).

**`status: "BROKEN"` is not a pass and not a failure.** It means a collector could not do its
job — a dev server that never started, a missing dependency. Fix that first; a report built
on evidence that was never gathered is worse than no report.

Also capture into `.evidence/artifacts/`, raw and unsummarised: the same query before and
after, curl pairs, accessibility violations, anything else the plan's Evidence section
promised. **Never write "looks correct" as evidence.** It is the one sentence that survives
review while proving nothing.

## S6 — Report

```bash
echo report > .evidence/phase
```

Publish one page, in this order:

1. **Verdict line first.** Shipped / blocked / needs a decision.
2. **At most five red flags**, ranked. Not everything you noticed — the five that would
   change someone's mind.
3. **"If you only have two minutes, check these three things"**, with anchor links.
4. Before/after evidence side by side, downscaled.
5. Everything else behind `<details>`.

If `attribution` is `false` in `ship.config.json` (the default), the report, the PR body and
the status comment carry **no** AI-assistance footer, co-author trailer or generation notice.

Post it with `bash "$PLUGIN/scripts/tracker.sh" status <TICKET> <file>`.

## S7 — Learn

Diff the plan you proposed against the plan the user committed. For each change that is a
**rule** rather than a one-off, append one line to `docs/conventions.md`:

```
When X, do Y (not Z). — <TICKET>
```

Keep that file under its `memoryCaps.conventions` limit; merge duplicates.

Then update `docs/memory/` for every line the diff touched: re-run that line's grep, update
`seen:` and `verified:`. A new pattern now at two or more usages is added at
`confidence: low`. A pattern at zero usages is marked `STALE`, not deleted. Anything the user
made you revert is a rule — add it with the commit as its citation.

Commit memory changes separately: `memory: <what changed> (<TICKET>)`. Keeping them out of
the code commit is what makes `git log -p docs/memory/` a readable audit trail of what the
harness believes and when it started believing it.

---

## Always

- **One status comment per ticket**, id kept in `.evidence/comment-id`, edited in place. A
  new comment only at a stage boundary or on failure.
- **On failure, post the exact command and the last twenty lines of output, unsummarised.**
  A summarised error is a second thing to debug.
- **State that is not in the tracker does not exist.** Any run can be killed at any point;
  the next one reads `.evidence/phase` and the status comment and picks up from there.

## Working alongside other skills

- **PlanDB**, if installed: it tracks *execution steps*. `docs/plans/<TICKET>.md` is the
  *contract*. Register S3's build steps as a graph if you like; the plan file stays
  authoritative and the graph never overrides it.
- **superpowers**, if installed: S1–S2 *are* the brainstorming gate, so do not run
  brainstorming inside a ship run. S3 delegates to test-driven-development. S5–S6 satisfy
  verification-before-completion — evidence before assertions is the same rule, and the
  collectors are how this pipeline keeps it.
- **Repo `CLAUDE.md` always wins.** If it contradicts anything here, follow it and note the
  conflict in the report.
