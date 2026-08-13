# Changelog

Notable changes, newest first. Versions follow [semver](https://semver.org). The version in
`.claude-plugin/plugin.json` is what Claude Code installs against — CI fails the build if
this file, that file and the git tag disagree.

## 0.4.0

**A second entry point: `/ship-harness:review` — review someone else's PR by planning the
ticket yourself first, then comparing blind.** And a rule for both skills: anything the repo
did not write gets verified at its official source, at the version it pins.

- `skills/review/SKILL.md` — reads the ticket and mines precedent **before opening the diff**
  (once you have seen the implementation, every "independent" plan rhymes with it), writes a
  shadow plan for the *simplest* thing that satisfies the ticket, runs it through the same
  two plan-review rounds, then rewrites the PR as a plan in the same template and compares.
- `agents/reviewer-delta.md` (opus) — receives the two plans **labelled only A and B**, is
  never told which shipped, and reports which is simpler and where each is weaker. You wrote
  one of them, which makes shuffling the cheapest available correction for authorship bias.
- **`equivalent` is a first-class verdict.** Most differences between two competent plans are
  not defects, and the report lists what it deliberately did *not* flag — a review that only
  lists complaints is a rewrite request no matter how it is worded.
- Deltas where the **PR was stronger** are learned into `docs/memory`, not reported.
- **External claims must cite an official source at the pinned version** — the project's own
  repo or docs, the standards body's own document, the vendor's reference. Tutorials, doc
  mirrors, StackOverflow and AI summaries are pointers, never citations. Where behaviour
  matters, read the source, not the prose. Both plan reviewers and `reviewer-correctness`
  now treat an uncited or unversioned third-party claim as a finding.
- **Where the repo is silent, consult real work**: installed skills that encode books first
  (they carry a bibliography rather than a recollection), then primary sources — papers,
  RFCs, official docs. Capped by `caps.research` (default 3). Literature never outranks a
  convention already in the code; that argument is an ADR.
- `docs/memory/references.md` — new capped memory file recording what was looked up, the
  source, the pinned version and where it was applied. `refresh` verifies these by re-opening
  the citation rather than by grep, and marks a line `STALE` when the pinned version moves on.
- New caps `research` (3) and `reviewDelta` (2); new `memoryCaps.references` (40).
- **Review budgets are yours, and confirmed before first use.** Every cap moves to
  `ship.config.json`, `/ship-harness:init` step 3.5 shows the table and waits for a yes, and
  `ship` and `review` **refuse to run** while `setup.confirmedAt` is null — a budget nobody
  chose is a default nobody owns. `0` removes the count entirely and runs the loop to
  convergence: it ends when a round raises no new finding. Since the approval bias does not
  go away with the count, two rules take its place — no round may approve while it is still
  raising findings, and every round is logged, so "converged on round nine" is visible rather
  than summarised away.
- `test/run.sh`: the wiring test now scans every skill, and asserts each memory template has
  a maintainer.

## 0.3.0

**The plan now says how it will be tested, and measures what it does not know.** Acceptance
criteria describe the change working; nearly every expensive defect lives in the other half.

- `## Test plan` — a required table with a row per dimension: correctness, reliability,
  concurrency, scale, security, regression. Each names a mechanism or writes `n/a — <why>`;
  a blank row is the gap. Reliability rows name an injected failure, concurrency rows mean
  the race detector plus concurrent callers, scale rows carry a multiple and report
  **p50/p95/p99 with error rate and throughput** — an average hides the tail where users
  feel it — and name the limit expected to bind first.
- `## Unknowns → spikes` — anything the interview and precedent could not settle becomes
  ~30 lines of throwaway code that answers **one** question with a number. Spikes run during
  S2.5 in a scratch worktree, **before** the user sees the plan, so what reaches the gate
  holds the answer rather than the question. The measured result is written back and the
  code deleted: an instrument is not an increment. Capped by `caps.spikes` (default 3).
- S3 commits the test-plan rows as real tests in the tests-first commit, and builds the
  smallest load harness that produces the tuple when the scale row needs one.
- Both plan reviewers check the new sections: round A rejects rows that restate an
  acceptance criterion or state a feeling instead of a mechanism, and lines still phrased as
  questions; round B checks the scale row measures the limit that actually binds, and calls
  out numbers asserted with neither a citation nor a spike.
- `reviewer-correctness` now checks the shipped diff against the table row by row — a
  promised mechanism with no corresponding test is a blocking finding.
- Plan budget raised 400 → 500 words to pay for the two new sections.
- `test/run.sh`: `plan-template-shape` asserts the new headings and every dimension row;
  the duplicate `reviewers-read-only` test is folded back into `agents-readonly`.

## 0.2.0

**The plan is reviewed by two models before you ever see it (S2.5).** A missing failure mode
costs a line of markdown before S3 and the implementation after it, and an agent is the worst
available judge of a plan it just wrote.

- `agents/plan-reviewer-correctness.md` (sonnet) — loops until it approves: concreteness,
  correctness, reliability and failure modes, testability of every acceptance criterion,
  convention fit, citation validity, diagram-versus-text agreement.
- `agents/plan-reviewer-architecture.md` (opus) — then loops until it approves: architecture,
  responsibility boundaries, scalability at 10×, blast radius, operability and rollback,
  reversibility, and whether the plan solves the ticket or a nearby easier problem.
- Both are read-only, get fresh context each round, never see your reasoning, and return one
  JSON object the parent writes to `.evidence/plan-review-{a,b}.json`.
- A round-2 fix to `Goal`, `Shape` or `Acceptance criteria` re-opens round 1 **once** — a
  second re-open means the reviewers disagree, which is a fact for the human, not a loop.
- The word budget survives the loop: every accepted finding replaces a line or removes one.
  Anything needing more room becomes an ADR.
- New caps `caps.planReviewA` (3) and `caps.planReviewB` (2), in the schema and every preset.
- `test/run.sh` — `reviewers-read-only` asserts no agent holds a write tool, since that
  property lives in the tool list rather than the prompt; `plan-review-wired` asserts every
  agent is actually dispatched and every cap declared.

## 0.1.2

**Plans are short, precise and drawn.**

- `templates/plan.md` — one screen, ~400 words, bullets and tables only, plus a required
  `## Shape` section: plain ASCII, ≤72 columns, nodes this change touches marked `*`.
- `skills/ship/SKILL.md` — S2 carries the budget and the diagram rules, including the
  escape hatch: if you cannot draw it, go back to S0 rather than covering the gap with
  words.
- `agents/reviewer-design.md` — round B checks the diff against the `Shape` diagram. A
  component touched but never drawn is undeclared blast radius, and is now a finding.
- `test/run.sh` — `plan-template-shape` guards the headings S4 and S7 parse, the diagram
  width and ASCII-ness, and the word budget.

## 0.1.1

**Precedent mining survives a real repo.** Found by running the backfill against a
5,010-commit tree.

- Lockfiles and generated code no longer own the co-change ranking, so genuine couplings
  reach the head cutoff.
- Scars are restricted to the mainline with `--first-parent`; intra-PR "to be reverted"
  work-in-progress no longer drowns out reverts that actually landed.
- One `git log` pass replaces ~400 `git show` forks — backfill on that repo went from ~7s
  to ~1s.

## 0.1.0

Initial release: ticket → precedent → committed plan → build → two-model review →
deterministic evidence → one published report. Pluggable collectors, phase-guard test
freeze, capped and cited memory.
