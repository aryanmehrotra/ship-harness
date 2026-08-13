---
name: review
description: Review someone else's PR by independently planning the ticket first, then comparing that plan against what was actually built. Use when the user says /ship-harness:review, hands you a PR number or branch to review, or asks for a review that holds a contribution to the repo's own standard.
---

# review

Usage: `/ship-harness:review 412` — a PR number, a branch, or a diff.

**This reviews work the harness did not do.** `/ship-harness:ship` reviews its own diff
against a plan it committed; here there is no plan, because someone else wrote the code.
So you write one — independently, from the ticket — and the comparison becomes the review.

Throughout, `<PR>` is what you were given and `$PLUGIN` means `${CLAUDE_PLUGIN_ROOT}`.

**Precedence for every judgement: code > `docs/memory` > docs.** Same as `ship`. A finding
that cannot point at a path is an opinion.

## Why plan first instead of just reading the diff

A reviewer who starts from the diff can only answer *is this right?* — and the answer is
almost always yes, because the code is self-consistent and its framing is persuasive. The
question that catches expensive problems is *is this the simplest thing that would have
worked?*, and you cannot answer that without having thought about the alternative before
seeing the answer.

It also catches the class of defect a diff-only review structurally cannot: **what is
missing**. Nothing in a diff tells you about the failure mode nobody handled.

## Preflight — heal the repo, do not lecture the user

```bash
bash "$PLUGIN/scripts/preflight.sh"
```

`needs[]` comes back ordered. **Do the work yourself**, following
`$PLUGIN/skills/memory/SKILL.md`, and say in one line what you did:

| need | You do |
|---|---|
| `init` | set the repo up — preset, scaffold, ignore rules |
| `confirm-run-mode` | **stop and ask.** Autonomy and budgets — the two you may not decide for the user |
| `backfill` | build `docs/memory/` from history before planning anything |
| `refresh` | re-verify stale lines and work off the open gaps |

Empty `needs[]` → say nothing and continue.

**If `harness.behind` is true, say so once, in one line, and carry on.** Never block a run on
it and never re-raise it later in the same run:

```
ship-harness 0.5.0 → 0.6.0 available · /plugin marketplace update ship-harness
```

The update itself is the user's to run — Claude Code owns the plugin cache, and a script that
edits `installed_plugins.json` behind it is how an install ends up in a state neither side
believes in. A vendored install (`install.sh`) is different: there the files are in-tree, so
offer to re-run the installer.

The check is cached for a day and silent when offline or rate-limited. A version notice that
can fail a run is worse than no version notice.


Only `confirm-budgets` blocks: those numbers decide how many rounds and how much money every
future run spends, and a default nobody chose is the kind of thing noticed after the bill.
Everything else is the harness's own maintenance, and asking a user to type `backfill` is
asking them to remember a chore that has exactly one correct answer.

## R0 — Read the ticket. Do not open the diff yet.

```bash
mkdir -p .evidence/review/<PR>
echo plan > .evidence/phase
bash "$PLUGIN/scripts/tracker.sh" fetch <PR>
```

Read the ticket, the issue it closes, and the PR **description** — but **not the diff, not the
file list, not the commit titles.** Once you have seen the implementation you cannot unsee its
shape, and every "independent" plan you write afterwards will rhyme with it. This ordering is
the whole mechanism; skipping it produces a review that agrees with the PR and calls it
verification.

If the ticket is too thin to plan from, say so and stop. That is itself the most useful review
finding available — a change nobody could have specified cannot be meaningfully reviewed
either.

## R1 — Precedent

```bash
bash "$PLUGIN/scripts/precedent-scan.sh" "<domain terms>" <paths the ticket implies>
cat docs/memory/*.md docs/conventions.md 2>/dev/null
```

Same ranking as `ship` S0: decisions, prior plans, code, merged-PR discussion, scars. You are
building the repo's answer to this ticket, not yours.

### R1.5 — Where the repo is silent, use a real source

`docs/memory/references.md` first — it is the record of what this repo already looked up.
Beyond that, in this order, and only for questions the repo genuinely does not answer:

1. **Installed skills that encode books.** If the environment has domain skills — a Go review
   skill built on *100 Go Mistakes*, a design skill on *Designing Data-Intensive
   Applications*, one on *Building Microservices*, on API design, resiliency, observability —
   invoke the one matching the dimension you are unsure about. They are local, cheap, and
   carry a real bibliography rather than a recollection.
2. **Primary sources.** The paper, the RFC, the language or database's own documentation, the
   spec section. Fetch it and read the relevant part.
3. **Nothing else.** A blog post restating a paper is not the paper.

**Citation discipline, non-negotiable:** name the work, the author, and the chapter, section
or RFC clause. If you cannot name it that precisely, you do not have a citation — say "no
authoritative source found" and make the argument on the repo's own terms instead. Never
invent a page number, a section title, or a paper that would be convenient.

**Precedence does not change: code > `docs/memory` > repo docs > literature.** A book is how
you reason about a decision the repo has never made. It is never a reason to overrule a
convention that is already in the code two or more times — that argument is an ADR, made
explicitly, not a review finding citing an author the repo never agreed to follow.

Cap the lookups at `caps.research` (default 3). Research is the easiest possible way to spend
an hour producing nothing a reviewer can act on.

### Record what you had to learn — immediately, not at the end

The moment you look something up to get unstuck — a dependency's real behaviour, a protocol
rule, a subsystem nobody documented — write it into `docs/memory/` **before you use it**, and
append the question to `.evidence/memory-gaps.md`:

```
- <what was needed> — needed by: <TICKET>, <date> — resolved: <memory line | still open>
```

Deferring this to the end is how it never happens: by then the answer feels obvious and no
longer worth writing down, which is exactly the illusion that makes the next run pay for it
again. The gap list is also what makes the next `refresh` targeted rather than generic — it
is the harness's own to-do list, and it is the difference between getting better at a repo
and merely getting older in it.

**Memory is loaded whole, never retrieved from.** The caps exist so the entire set fits in
context — a few hundred lines. Do not build a retrieval step over something that small; read
all of `docs/memory/` at the start of the run and keep it there.


### R1.6 — Verify every external claim at its source — binding

> Any statement about something this repo did not write — a dependency, an API, a protocol,
> a database, a cloud service, a CLI — is verified against **that thing's own official
> documentation or source code, at the version this repo pins**, and cited.

This binds you *and* the PR:

- **Read the version the repo depends on**, from the manifest or lockfile, then open the
  vendored copy, the module cache, `node_modules`, or the tagged source. A default that
  changed three releases ago is exactly what recollection gets wrong.
- **Official only.** The project's own repo or docs site, the standards body's own document
  (IETF, W3C, ISO, OWASP), the vendor's own reference. Tutorials, doc mirrors, StackOverflow
  and AI summaries are pointers, never citations — open the real thing and cite that.
- **Prefer source to prose** when behaviour matters: the error returned, whether a call
  retries, whether a context is honoured. Docs describe intent; code is what runs.
- **Cite with a version**: `<lib> v<version> — <file>:<symbol>`, or
  `<official doc title> (v<version>, <section>)` with the vendor URL.
- **A finding that rests on remembered library behaviour is not a finding.** Open it first.
  Filing "this API doesn't work that way" and being wrong costs the author an argument and
  costs you the next three reviews' worth of credibility.

The same standard applies to the PR under review: an assumption about external behaviour
that neither the code nor the description grounds in an official source is a legitimate
finding — name the claim and the doc that should have settled it.

## R2 — The shadow plan: the simplest thing that satisfies the ticket

Write `.evidence/review/<PR>/shadow-plan.md` from `$PLUGIN/templates/plan.md` — same
headings, same budget, same required `Shape` diagram and `Test plan` table.

It does **not** go in `docs/plans/`. That directory is for work this repo committed to; a
shadow plan is an instrument.

**Simplest, not best.** You are establishing a floor, not showing off:

- Fewest moving parts that satisfy every acceptance criterion in the ticket.
- Maximum reuse — if the repo has a thing that does this, your plan uses it.
- No speculative generality. No abstraction whose second caller does not exist yet.
- If the honest simplest answer is "extend the existing X in place", write that.

An over-engineered shadow plan makes every real PR look sensible by comparison, which
silently disables this entire skill.

## R3 — Self-review the shadow plan

Run it through the same two rounds `ship` uses at S2.5, and run any spikes it declares:

- `plan-reviewer-correctness` — budget `caps.planReviewA`
- `plan-reviewer-architecture` — budget `caps.planReviewB`

`0` means no fixed limit: run until a round raises no new finding. No round may approve while
it is still raising findings, and every round is logged.

A first-draft plan is a bad yardstick: it will be missing the same things the PR is missing,
and the review will find nothing. Fix every `blocking` and `major` finding before continuing.

**Then freeze it.** Commit it to `.evidence/review/<PR>/shadow-plan.md` and do not edit it
after the next step begins. A yardstick you adjust after measuring is not a yardstick — and
the temptation to "improve" it into agreement with the PR is real and constant.

## R4 — Now read the diff, and write what it actually did

```bash
gh pr diff <PR> > .evidence/review/<PR>/pr.diff     # or: git diff <base>...<branch>
```

Reconstruct the PR as a plan **in the same template**, at
`.evidence/review/<PR>/as-built.md`. Same headings, same diagram, same test-plan table —
filled in from the code, not from the PR description. Where the diff gives no answer for a
row, write `not covered`, and resist the urge to be generous: a test that exists but exercises
only the happy path does not fill the reliability row.

Describing the code in the plan's own vocabulary is what makes the two comparable. It also
tends to surface the omissions on its own, before any comparison happens.

## R5 — Compare blind

Dispatch `reviewer-delta` with: the ticket, and the two plans **labelled only A and B**.

- **Randomise which is which** and record the mapping in `.evidence/review/<PR>/ab-map.json`.
- Do not tell it which one shipped, and do not include the diff, the PR description, the
  author, or your reasoning about either plan.
- Budget from `caps.reviewDelta` (default 2; `0` runs until a round adds no new delta).

You wrote one of these plans, which makes you the worst available judge of which is better.
An unlabelled comparison is the cheapest possible fix for that, and it costs one shuffle.

Write its JSON to `.evidence/review/<PR>/delta.json`, then de-anonymise using the map.

Each delta lands in exactly one bucket:

| Bucket | What it means | What you do |
|---|---|---|
| **PR stronger** | it knew a constraint your plan missed | **learn it** — append to `docs/memory/`, cite the PR. Not a finding. |
| **Equivalent** | two valid shapes, no risk difference | **say so in the report.** Never a finding. |
| **PR weaker** | a named cost: failure mode, limit, convention, irreversibility | a finding, with the cheapest fix |
| **PR silent** | your plan has a row the diff has no answer for | usually the most valuable finding you have |

## R6 — Evidence, not adjectives

```bash
echo evidence > .evidence/phase
bash "$PLUGIN/scripts/collect.sh"
```

Run the repo's own collectors against the PR branch. A review that says "this looks correct"
proves nothing and survives anyway — which is why the harness never lets a model's impression
be the artifact. Open only what lands in `failed[]`.

For any `PR weaker` finding you can demonstrate, demonstrate it: the failing input, the
concurrent case, the query plan, the before/after pair. A finding with a reproduction is a
fact; the same finding without one is a preference, and it will be argued with.

## R7 — Report

Publish one page, in this order:

1. **Verdict** — approve / approve with follow-ups / changes requested. One line.
2. **The simplest shape**, as the `Shape` diagram from whichever plan the blind round called
   simpler, with one line on what the difference costs. If that was the PR's, say so plainly
   — that is a real result and reporting it is what makes the rest of the review credible.
3. **At most five findings**, ranked, each with: the cost, the cheapest fix, and a
   reproduction where one exists.
4. **Omissions table** — the `Test plan` rows the diff has no answer for.
5. **"Differences I am not flagging"** — the equivalent choices, listed. This is not padding:
   an author needs to know which of their decisions survived scrutiny, and a review that only
   lists complaints reads as a rewrite request no matter how it is worded.
6. Both plans and the raw evidence behind `<details>`.

Post with `bash "$PLUGIN/scripts/tracker.sh" status <PR> <file>`. If `attribution` is `false`
(the default), no AI-assistance footer.

**Never open with the count of findings.** Five minor findings and one blocking finding are
not "six issues", and an author reading a number first reads everything after it defensively.

## R8 — Learn

Every `PR stronger` delta is a thing this repo knows and you did not:

```
memory: <what the PR knew that the shadow plan missed> (<PR>)
```

Add it to `docs/memory/patterns.md` or `decisions.md` with the PR as its citation, inside the
`memoryCaps` limits. Over several reviews this is what makes the shadow plans stop being
wrong in the same places — and a review skill that never learns is one that argues with the
same contributor twice about the same thing.

If the author pushes back and is right, that is also a `PR stronger` delta. Record it the same
way.

**Every source R1.5 actually used gets one line in `docs/memory/references.md`:**

```
<claim> — <Source, author, chapter/section> — applied: <PR>, <date>
```

Only what changed a finding. A reading list nobody acted on is the fastest way to make this
file unreadable, and the second-fastest is a line whose source cannot be opened. The next
review reads this file before it searches anything, so a good line saves the lookup and a
fabricated one poisons every review after it.

Commit memory changes separately, `memory: <what changed> (<PR>)`, so
`git log -p docs/memory/` stays a readable record of what the harness believes and when it
started believing it.

## Working alongside the rest of the harness

- **`ship` and `review` are the same pipeline pointed in opposite directions.** `ship` plans
  then builds; `review` plans then reads what someone else built. They share the precedent
  scan, the plan template, the plan reviewers and `docs/memory`, which is why this is a skill
  here and not a separate plugin — a standalone reviewer would have to rebuild all four, and
  a reviewer without your repo's precedent is just a linter with opinions.
- **Reviewing a `ship` PR:** skip R2 and R3 and use the committed `docs/plans/<TICKET>.md` as
  plan A. It was already reviewed by two models; re-deriving it wastes the round.
- **Repo `CLAUDE.md` always wins**, and a `PR weaker` finding that contradicts it is wrong —
  check before you file it.
