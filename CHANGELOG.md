# Changelog

Notable changes, newest first. Versions follow [semver](https://semver.org). The version in
`.claude-plugin/plugin.json` is what Claude Code installs against — CI fails the build if
this file, that file and the git tag disagree.

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
