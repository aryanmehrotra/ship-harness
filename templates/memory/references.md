# references

External knowledge this repo has actually used: the book, paper, RFC or spec section behind a
decision, and where it was applied. Maintained by `/ship-harness:ship` (S7),
`/ship-harness:review` (R8) and `/ship-harness:refresh`.

**Three rules, and they are what make this file worth reading:**

1. **A source you cannot name precisely does not go here.** Book + author + chapter, paper +
   venue + year, RFC + section, or `<lib> v<version> — <file>:<symbol>`. Never a page number
   you did not see, never "as is well known", never a half-remembered title. A fabricated
   citation is worse than no citation because it survives review by looking like evidence.
   **Official sources only** — the project's own repo or docs, the standards body's own
   document, the vendor's own reference. A tutorial or a mirror is a pointer, not a source.
2. **A line must have been applied.** This is not a reading list. Every entry names the
   decision, plan or PR where the idea changed what got built.
3. **The repo still wins.** These lines inform decisions with no precedent; they never
   override a convention already in the code. When they conflict, that conflict is an ADR,
   not a memory line.

Format — one line each:

```
<claim, one sentence> — <Source, author, chapter/section — or lib v<version>, file:symbol> — applied: <path | PR | ADR>, <date>
```

Anything about a dependency carries **the version this repo pins**. A claim about library
behaviour with no version cannot be re-checked after the next upgrade, which is precisely
when it starts being wrong.

<empty — added as reviews and plans consult real sources>
