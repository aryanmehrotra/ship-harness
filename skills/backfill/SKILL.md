---
name: backfill
description: Build docs/memory from the repository's git history as a citation index of patterns, decisions, scars and file locations. Use once when setting up a repo, or when the user asks to rebuild, bootstrap or regenerate precedent memory.
---

# backfill

Builds `docs/memory/` from history. Run once per repo. The output is **derived and
disposable** — if it ever gets weird, delete `docs/memory/` and run this again.

## 1. Rank deterministically before reading anything

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/precedent-scan.sh" --backfill
```

That gives you churn ranking, revert and hotfix commits, co-change coupling, authorship by
subsystem, and files rewritten three or more times — which is almost always an unresolved
design problem and always worth a line.

Start here rather than reading the tree. Git already knows where the action is; paying a
model to rediscover it produces a worse answer at a much higher price.

## 2. Read only the top slice, in date order

Process history one quarter at a time. Each slice emits candidate lines; merge and dedupe at
the end. Never attempt a single pass over the whole history — it exhausts context and
produces confident mush, which is harder to detect and much harder to undo than an empty
file.

## 3. Write five files, one format

| File | Holds | Cap |
|---|---|---|
| `docs/memory/map.md` | domain → paths. The highest-value file here. | 100 lines |
| `docs/memory/patterns.md` | conventions with two or more usages | 60 lines |
| `docs/memory/decisions.md` | implicit ADRs recovered from history | 40 lines |
| `docs/memory/scars.md` | reverts, hotfixes, rollbacks | 30 lines |
| `docs/memory/glossary.md` | domain term → code symbol | 40 lines |

Every line carries provenance and is re-checkable by a grep:

```
- All HTTP handlers return Result<T, AppError>, never throw.
  seen: 14 files · e.g. src/api/user.ts:22 · since a3f21c9 2025-03 · verified 2026-08-13 · confidence: high

- Feature flags are checked at route level, not component level.
  seen: 2 files · e.g. src/routes/billing.tsx:8 · verified 2026-08-13 · confidence: low — may be copy-paste, verify before relying
```

`confidence: low` at two usages is the honest form and should stay honest. Two usages can be
one decision, or one copy-paste that nobody has questioned yet, and the memory has no way to
tell those apart.

## 4. Two rules that keep this worth having

**Git records what changed, not why.** Do not invent rationale. `decisions.md` only takes
lines with corroboration — a revert, a PR discussion, a postmortem. Everything else goes in
`patterns.md` as an observed regularity with no reasoning attached. A plausible invented
rationale is worse than a missing one: it will be cited in a plan, survive review because it
reads well, and quietly steer a decision it was never evidence for.

**Nothing lives only in memory.** Every line points at code. This is an index that tells you
where to look, never a source of truth. When memory and code disagree, the code is right and
the memory line is a bug to fix now.

Commit as `memory: backfill from history`, on its own, so the first entry in the audit trail
is legible.
