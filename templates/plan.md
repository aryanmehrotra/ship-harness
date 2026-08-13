# <ticket> — <title>

> The contract. Your commit approves it; the reviewers check the diff against these
> headings. Keep it to one screen — **~500 words, bullets, tables and diagrams, no prose
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

## Unknowns → spikes

Only what precedent and the interview could not settle. A spike is throwaway code that
answers **one** question; its measured answer is written back here before this is committed.
`none` is a valid and common answer.

- <question> → probe: <what it measures, ~30 lines> → **measured:** <result> → decides: <which line below>

## Acceptance criteria

Testable, and each gets a test committed before the implementation.

1. <testable statement>
2. <testable statement>

## Test plan

Every row names a mechanism or says `n/a — <why>`. A row with neither is the gap.

| Dimension | Proven by | Gate |
|---|---|---|
| correctness | <table tests on the real branch points> | must pass |
| reliability | <injected: timeout · partial write · retry · restart mid-flight> | must pass |
| concurrency | <race detector · N concurrent callers on the shared state> | must pass |
| scale | <N× rows/callers; report p50/p95/p99 + error rate + throughput> | <budget> |
| security | <untrusted input: injection · authz · traversal> | must pass |
| regression | <collector case, before/after> | must pass |

## Must not regress

- <flow> — proven by <test or collector case>

## Evidence plan

- <collector> — <what it will show>

## Rollback

- How: <…>
- Migration reversible: yes / no — <how that was verified, not assumed>

## Open risks I'm accepting

- <…>
