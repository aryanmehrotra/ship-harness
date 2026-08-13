# Changelog

Notable changes, newest first. Versions follow [semver](https://semver.org). The version in
`.claude-plugin/plugin.json` is what Claude Code installs against — CI fails the build if
this file, that file and the git tag disagree.

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
