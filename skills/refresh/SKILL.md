---
name: refresh
description: Re-verify and prune docs/memory against current code, marking stale lines and enforcing the size caps. Use monthly, or whenever the user asks to refresh, prune, verify or clean up precedent memory.
---

# refresh

Run monthly. Every memory line is a grep, so verification is mechanical rather than a
judgement call — which is the only reason this stays cheap enough to actually do.

1. **Re-run each line's grep.** If the count dropped or the cited path is gone, mark the line
   `STALE`. Do not delete it yet: one bad refresh should not silently erase real knowledge.
2. **`STALE` on two consecutive refreshes → delete**, and log the commit that killed it.
3. **`verified:` older than 90 days → re-verify or drop.** An unverified line that keeps
   getting cited is worse than a missing one.
4. **Enforce the caps** from `memoryCaps` in `ship.config.json` (defaults: map 100,
   patterns 60, decisions 40, scars 30, glossary 40). Over cap → merge duplicates first, then
   drop the lowest-confidence lines.

   **Never grow a file to fit.** The cap is the mechanism: it forces the merge-or-drop
   decision that otherwise never gets made, and without it you get a 400-line file that
   nobody trusts and everybody skims within two months.
5. **Promote confidence only on evidence.** `low → high` needs five or more usages, or a
   cited revert, PR or postmortem. Time alone never promotes anything — a line does not
   become true by surviving.
6. **Where memory and code disagree, the code wins.** The memory line is wrong. Fix it now,
   in this pass, rather than noting it.

Commit as `memory: refresh <date>`, separately from any code change, so
`git log -p docs/memory/` stays a readable record of what the harness believed and when it
changed its mind.

## The check worth more than the other six

Are the `[R]` and `[P]` citations in recent plans surviving the user's edits?

```bash
git log --oneline -20 -- docs/plans/
git log -p -10 -- docs/plans/ | grep -E '^[-+].*\[(R|P)\]'
```

A citation the user keeps striking out means the memory is **confidently wrong**, which is
the most expensive state this system can be in — it is being cited in plans, it reads as
evidence, and it survives review because it looks like a fact. Find that line and delete it.
Do not soften it, do not lower its confidence, do not leave it for the next refresh.
