# <ticket> — <title>

> This file is the contract. Once you commit it, it is what gets built and what the
> reviewers check the diff against. Edit it freely before committing — the edits are
> also the training signal that becomes `docs/conventions.md`.

## Goal

<one sentence — what is true after this ships that is not true now>

## Out of scope

<what this deliberately does not do, so the reviewers do not ask for it>

## Precedent

Every line is tagged and cited. A citation is a path you can open, not a memory.

- `[R]` <decision> — reuses `<path>`
- `[P]` <decision> — settled by `docs/adr/NNNN`, <date>
- `[D]` <decision> — diverges from `<path or PR>`; reason: <…>; blast radius: <…>
- `[N]` <decision> — no precedent found → ADR NNNN drafted

## Acceptance criteria

Each one testable, and each one gets a test committed before the implementation.

1. <testable statement>
2. <testable statement>

## Must not regress

- <flow> — proven by <test or collector case>

## Evidence plan

Which collectors prove this change, and what a reviewer should look at.

- <collector> — <what it will show>

## Rollback

- How: <…>
- Migration reversible: yes / no — <how that was verified, not assumed>

## Open risks I'm accepting

- <…>
