# <ticket> — <title>

> The contract. Your commit approves it; the reviewers check the diff against these
> headings. Keep it to one screen — **~400 words, bullets and diagrams, no prose
> paragraphs**. One line per item. A section with nothing true to say gets `none`.

## Goal

<one sentence — what is true after this ships that is not true now>

## Out of scope

- <what this deliberately does not do, so the reviewers do not ask for it>

## Shape

Required. Plain ASCII, ≤72 columns. Mark every node this change adds or modifies with `*`.
Label edges with what flows across them. Add a `before / after` pair only when an existing
flow is re-routed.

```text
  client
    |  POST /session
    v
+-----------+   token   +--------------+
| handler * |---------->| store (new) *|
+-----------+           +--------------+
    |  err
    v
  logger
```

## Precedent

Tagged, one line each. A citation is a path you can open, not a memory.

- `[R]` <decision> — reuses `<path>`
- `[P]` <decision> — settled by `docs/adr/NNNN`, <date>
- `[D]` <decision> — diverges from `<path>`; why: <…>; blast radius: <…>
- `[N]` <decision> — none found → ADR NNNN drafted

## Acceptance criteria

Testable, and each gets a test committed before the implementation.

1. <testable statement>
2. <testable statement>

## Must not regress

- <flow> — proven by <test or collector case>

## Evidence plan

- <collector> — <what it will show>

## Rollback

- How: <…>
- Migration reversible: yes / no — <how that was verified, not assumed>

## Open risks I'm accepting

- <…>
