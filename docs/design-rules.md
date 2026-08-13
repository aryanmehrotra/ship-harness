# Design rules

Every constraint in this harness exists because of a specific failure. This page is the
reasoning, so you can tell when a rule stops applying to your repo instead of cargo-culting
it — or removing it for the wrong reason.

---

## 1. The plan is a committed file, not a conversation

**Failure it prevents:** the plan drifts. Ten messages later the agent is building something
adjacent to what you agreed, and there is no artifact to point at, because the agreement was
a paragraph in a scrollback nobody can diff.

**How it works:** S2 writes `docs/plans/<TICKET>.md` and stops. You edit it. Your commit is
the approval. S4 reviews the diff *against that file*, by heading.

**Why a commit specifically:** it is unforgeable, timestamped, diffable, and it already means
"I looked at this" in every team on earth. A chat "yes" means none of those things a week
later.

**Bonus property:** because the plan is a file, S7 can diff what the agent proposed against
what you committed. Your edits are the highest-quality training signal available — they are
corrections on concrete work — and they become `docs/conventions.md`.

**Why it is capped at one screen and must contain a diagram:** the plan is load-bearing at
exactly two moments — when you decide whether to approve it, and when a reviewer checks a
diff against it. Both are skim-under-pressure. A two-page plan gets approved unread, which
turns the gate into a formality while it still looks like a gate: strictly worse than not
having one. Length is also where an agent hides uncertainty, because prose can restate a
ticket convincingly without deciding anything; a word budget makes that visible instead of
comfortable. The diagram closes the same gap from the other side — naming the boxes and the
edges forces the decisions prose defers, and it shows blast radius, which is the first thing
round B goes looking for. ASCII specifically, because the plan is read in a terminal, a PR
body and a `git diff`, and it is the only format that survives all three unrendered.

## 2. Precedent before planning, and reuse is binding

**Failure it prevents:** a second date formatter. A third HTTP client. A fourth error type
that is almost the existing one. Each is locally reasonable and collectively fatal.

**How it works:** S0 runs deterministic git mining first, then reads decisions, prior plans,
code, merged-PR discussion and scars — in that order of bindingness. Nothing may be proposed
new without naming the existing thing, why it cannot be extended, and what extending it would
cost.

**Why "cleaner" is not a reason:** consistency beats local quality. The cost of a second way
to do something is paid forever, by everyone reading the repo, while the benefit is captured
once by whoever wrote it. An existing pattern you dislike still wins.

**Why the ranking matters:** where code and docs disagree, the code is the answer. Docs
describe intent; code describes what shipped. A plan built on stale docs is confidently
wrong, which is worse than uncertain.

## 3. Two reviewers, different models, no write tools, capped

**Failure it prevents:** self-approval. An agent asked to review its own work approves it —
not from dishonesty, but because it is evaluating with the same priors that produced the
work.

**How it works:** round A checks correctness (`sonnet` by default), round B checks design and
blast radius (`opus`), only after A approves. Each gets the plan, the diff, and prior
findings — **never the build transcript**. Neither has a write tool. They return JSON as
their final message and the parent writes the file.

**Why no write tools:** "you may not edit" in a prompt is a request. An agent with no Edit
tool cannot edit. Only one of those survives a long context and an inconvenient finding.

**Why never the transcript:** a reviewer that has read your reasoning reviews the reasoning.
Reasoning is persuasive by construction — it was optimised until it sounded right. The diff
is not.

**Why the caps, and why they are yours to set:** an uncapped "review until approval" converges
on approval — the reviewer knows the loop ends when it says APPROVED, and that is sufficient.
At the cap the harness stops and hands the open findings to a human, which is the correct
output for a genuine disagreement.

But a count is a blunt instrument in both directions: it stops a loop still making progress,
and lets a loop going in circles run all the way to the limit. So the numbers are configured
at `init` and **confirmed by you before first use** — the harness refuses to run on budgets
nobody chose. Setting one to `0` removes the count and runs to convergence instead: the loop
ends when a round raises no new finding. The approval bias does not disappear, so two rules
carry the weight the count used to — no round may approve while it is still raising findings,
and every round is logged, which makes "converged on round nine" visible rather than
summarised away.

**Why two tiers rather than two runs of one:** independence. Two runs of the same model share
the same blind spots. This is also why a set `CLAUDE_CODE_SUBAGENT_MODEL` is a real problem
rather than a nit — it silently collapses the tiers.

**Why the plan gets the same treatment, in S2.5:** the cost curve. A missing failure mode
costs one line of markdown before S3, and the implementation after it. An agent is also the
worst possible judge of a plan it just wrote — not from dishonesty, but because the priors
that produced the plan are the priors it would evaluate it with. So the draft goes through
round 1 (concreteness, correctness, reliability, testability, convention fit) until it
approves, then round 2 (architecture, responsibility, scale, blast radius, rollback) until
it approves — same models, same caps, same no-write-tools, same never-soften rule.

**Why the plan carries a test plan and not just acceptance criteria:** acceptance criteria
describe the change working. Nearly every expensive defect is in the other half — the retry
that double-writes, the map two goroutines share, the query that is fine at a thousand rows
and pathological at a million, the field an attacker controls. Those get tested when they are
named in the contract *before* the code exists, and skipped when they are left to whoever is
staring at a green build at 6pm. So the plan names a mechanism per dimension —
correctness, reliability, concurrency, scale, security, regression — or writes `n/a` with a
reason, which is a decision someone can argue with rather than an omission nobody notices.

**Why scale rows must report the tuple:** an average latency hides exactly the tail where
users feel pain. p50/p95/p99 with error rate and throughput, together, is the smallest
honest description of behaviour under load — and the plan should also name which limit is
expected to bind first, so a load test that exercises the wrong one is visible as wrong.

**Why unknowns become spikes rather than assumptions:** an agent asked to plan under
uncertainty will write a confident sentence, because confident sentences are what planning
documents contain. Thirty lines of throwaway code that returns a number costs less than the
first hour of building on a guess, and it converts the riskiest line in the plan from prose
into a measurement. The spike runs before the human sees the plan, so what reaches the gate
contains the answer rather than the question — and the code is deleted, because an
instrument that ships as an increment is how a probe becomes production code nobody designed.

**Why it does not replace the human gate:** it raises the floor, not the ceiling. Reviewers
check whether a plan is sound, internally consistent and conventional. Only you know whether
it is the thing you actually wanted, and no amount of review rounds converges on that.

**The failure mode it introduces, and the counter:** revision inflates. A one-screen plan
becomes four after three rounds of helpful suggestions, and the word budget was the thing
making it readable at the gate. So every accepted finding replaces a line or removes one,
and a finding that genuinely needs more room becomes an ADR instead.

## 3b. Reviewing someone else's PR means planning it first, then comparing blind

**Failure it prevents:** a diff-only review answers *is this right?* — and the answer is
almost always yes, because the code is self-consistent and its framing is persuasive. It also
cannot see what is missing. Nothing in a diff mentions the failure mode nobody handled.

**How it works:** `/ship-harness:review` reads the ticket, mines precedent, writes its own
plan for the *simplest* thing that satisfies it, runs that plan through the same two review
rounds `ship` uses — and only then opens the diff. The PR is rewritten as a plan in the same
template, and the two are handed to a third model **labelled only A and B**.

**Why blind:** you wrote one of those plans. Every known bias — authorship, not-invented-here,
the sunk cost of having thought it through — points one way, and none of them announce
themselves. Shuffling two documents is the cheapest correction available for all of them.

**Why `equivalent` is a first-class verdict:** most differences between two competent plans
are not defects. A review that flags every divergence is a rewrite request wearing a review's
clothes, and authors correctly learn to discount it. The report lists what it deliberately did
*not* flag, because that is what makes the rest of it credible.

**Why the shadow plan aims at simplest, not best:** an over-engineered yardstick makes every
real PR look reasonable, which silently disables the whole skill.

**Why it is a skill here and not a separate plugin:** it needs the precedent scan, the plan
template, the plan reviewers and `docs/memory`. A standalone review tool would rebuild all
four, and a reviewer with no access to your repo's precedent is a linter with opinions.

## 3c. External claims are verified at the official source, at the pinned version

**Failure it prevents:** a fluent, confident, version-blind sentence about a library's
behaviour. Model recollection of third-party defaults is exactly wrong often enough to matter,
and it reads identically to knowledge — so it survives review and fails in production.

**How it works:** anything the repo did not write — a dependency, an API, a protocol, a cloud
service — is checked against that project's own documentation or source, at the version in the
manifest or lockfile, and cited as `<lib> v<version> — file:symbol` or the vendor's own doc
plus a section. Where behaviour matters, the source beats the prose: docs describe intent, the
code is what runs.

**Why "official" is doing work in that sentence:** a tutorial, a doc mirror, a StackOverflow
answer and an AI summary are all pointers at best. They are also where subtly-wrong claims
come from, and citing one launders it into the plan as evidence.

**Why the version is not a nicety:** a claim with no version cannot be re-checked after the
next upgrade, which is precisely the moment it starts being false. `refresh` re-opens these
citations and marks a line `STALE` when the pinned version has moved, even if it was true when
written.

**Why literature never outranks the code:** books and papers inform decisions this repo has
never made. Citing an author to overrule a pattern already used in two or more places is an
architecture argument that belongs in an ADR, made explicitly — not a review finding
appealing to an authority the repo never agreed to follow.

## 4. A deterministic gate runs before the model looks

**Failure it prevents:** a model asked "does this look right?" says yes. Published benchmarks
put VLM-vs-human agreement on visual fidelity around 0.66 Spearman against 0.78
human-to-human, with a documented bias toward inflated scores.

**How it works:** collectors are ordinary programs. Pixel diffs, exit codes, response bytes,
console errors. They produce `failed[]`. The model only opens what is already in there, and
classifies it INTENDED / REGRESSION / NOISE.

**Why console and network errors carry no judgement call:** they are the part that cannot be
talked out of. A page can look perfect and be throwing on every render. The pixels will not
tell you and the model will not either.

**Why `BROKEN` ≠ `FAIL`:** "the checker crashed" and "the code regressed" are different
facts. A harness that reports them identically will eventually report a dead dev server as a
clean run — with a confident summary attached, because every signal it had said pass.

## 5. Tests are frozen after the build phase — by a hook

**Failure it prevents:** the cheapest way to resolve a failing assertion is to change the
assertion. An agent under instruction to make review findings go away will find that.

**How it works:** S3 writes and commits tests before implementation. `.evidence/phase` then
moves to `review`, and `hooks/phase-guard.sh` blocks writes matching `testPaths` until it
moves back.

**Why a hook and not a settings deny:** a static `deny` on `tests/**` is on during S3 too, so
the harness could never write the tests it requires. The rule is inherently phase-scoped, and
settings have no concept of phase.

**The escape hatch is deliberate:** sometimes a finding *is* about a test. Flip the phase back
to `build`, make the edit, flip it forward. The flip is visible in the run — which is the
whole mechanism. Nothing here prevents a determined edit; it prevents a *silent* one.

## 6. State lives in the tracker and `.evidence/`, never in the session

**Failure it prevents:** a run dies at 80% and takes its context with it. Nobody knows what
was done, so it starts over.

**How it works:** one status comment per ticket, edited in place. `.evidence/phase` holds the
stage. Failures post the exact command and the last twenty lines of output, unsummarised.

**Why unsummarised:** a summarised error is a second thing to debug. The raw output is
already the smallest complete description of what happened.

**Why one comment, edited:** a comment per stage turns the ticket into a changelog nobody
reads, and current state stops being findable — which defeats keeping state there at all.

## 7. Memory is a capped, cited, disposable index

**Failure it prevents:** a memory file that grows to 400 lines, half of it no longer true,
all of it quoted with equal confidence.

**How it works:** every line cites a path and is re-checkable by grep. Files have hard line
caps. `/ship-harness:refresh` re-runs each grep, marks misses `STALE`, deletes on the second
strike, and promotes confidence only on evidence.

**Why caps:** adding is easy and removing takes judgement, so removal never happens without
forcing. The cap is what forces merge-or-drop.

**Why citations:** memory is an index of where to look, never a source of truth. A line that
cannot be re-derived from the repo is a rumour.

**Why `decisions.md` demands corroboration:** git records what changed, not why. An invented
rationale reads exactly like a real one, gets cited in a plan, survives review because it
sounds right, and steers a decision it was never evidence for. Regularities with no known
reason go in `patterns.md`, unexplained.

---

## When to drop a rule

These are load-bearing for *agent-driven* work on a repo with history. Some genuinely do not
apply:

- **A brand-new repo has no precedent.** S0 will say so. Run the harness anyway — S7 starts
  accumulating from your first plan edit.
- **A repo with no observable surface** — a pure library — gets `builtin:tests` and nothing
  else. That is a legitimate config, not a degraded one.
- **Solo work you will review yourself in five minutes** does not need two review rounds. Set
  `caps.reviewB: 1` and let round B be a formality, or skip the harness entirely. It is built
  for changes where being wrong is expensive.

What is *not* a reason to drop one: the harness slowed you down on a change where it turned
out to be right.
