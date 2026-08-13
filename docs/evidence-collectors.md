# Evidence collectors

The pipeline's claim is "here is what changed, proven". A collector is the thing that does
the proving. This page covers configuring the four bundled ones and writing your own.

The contract itself — env vars, output shape, exit codes — is
**[collectors/CONTRACT.md](../collectors/CONTRACT.md)**. Read that before writing one.

## How they run

```bash
scripts/collect.sh              # compare against committed baselines
scripts/collect.sh --baseline   # record the oracle
scripts/collect.sh --only web   # one collector, by name
```

Each collector writes `.evidence/<name>.json`. `collect.sh` merges them into
`.evidence/evidence.json` and exits `0` (all passed), `1` (something regressed) or `2` (a
collector is broken).

The ship skill reads the aggregate and **opens only the artifacts named inside `failed[]`**.
That is the property that makes running fifty checks on every change affordable.

---

## `builtin:tests`

Wraps your test command and keeps the raw output as a linked artifact.

```json
{ "name": "tests", "kind": "builtin:tests",
  "config": { "cmd": "go test ./...", "timeoutSec": 900 } }
```

The value is not learning that tests exist. It is that the report links 400 unedited lines
instead of asserting "tests pass" — which matters precisely in the cases where the assertion
would have been wrong. A timeout reports `BROKEN`, not `FAIL`: a suite that never finished
tells you nothing about the code.

## `builtin:web-shots`

Routes × widths × themes, screenshotted and pixel-diffed. Console errors and failed requests
are hard failures with no judgement call.

```json
{ "name": "web", "kind": "builtin:web-shots",
  "config": {
    "baseUrl": "http://localhost:3000",
    "routes": ["/", "/login", "/settings", "/checkout?step=2"],
    "widths": [390, 768, 1440],
    "themes": ["light", "dark"],
    "fullPage": true,
    "settleMs": 300,
    "waitFor": "[data-testid=app-ready]",
    "threshold": 0.1,
    "maxRatio": 0.001,
    "mask": [".timestamp", "[data-testid=avatar]"],
    "ignoreRequests": ["favicon.ico", "googletagmanager"],
    "ignoreConsole": ["React DevTools"]
  } }
```

Needs, in your repo: `npm i -D @playwright/test pixelmatch pngjs && npx playwright install chromium`.

**`routes` is the highest-leverage line in your config.** No diff engine catches a regression
in a state it never captured. Nobody but you knows which routes matter, which need a
signed-in session, or which viewport your users actually have — and no agent can write this
for you.

**Use `mask`, not a looser `threshold`.** A clock, a random avatar, a relative timestamp will
each flap forever. The tempting fix is raising `maxRatio` until they stop. Do not: a
tolerance wide enough to swallow a clock is wide enough to swallow a broken layout on the
other side of the same page, and you will never find out. Paint over the flapping element
instead and keep the tolerance tight.

**On flake generally.** Animations, transitions and carets are already killed. If a shot
still flaps, the cause is real non-determinism — chase it rather than tolerating it.
Baselines that flap get re-recorded, and a baseline that gets re-recorded routinely has
stopped being an oracle.

## `builtin:http-pairs`

Real request/response pairs, normalised and diffed. The backend equivalent of a screenshot,
and much cheaper to store and read.

```json
{ "name": "api", "kind": "builtin:http-pairs",
  "config": {
    "baseUrl": "http://localhost:8080",
    "requests": [
      { "name": "health", "method": "GET", "path": "/health" },
      { "name": "list-users", "method": "GET", "path": "/users?limit=2" },
      { "name": "create-user", "method": "POST", "path": "/users",
        "headers": { "Content-Type": "application/json" },
        "body": "{\"name\":\"ada\"}" }
    ],
    "includeHeaders": ["content-type"],
    "redact": [
      "\"id\"[[:space:]]*:[[:space:]]*\"[^\"]*\"",
      "\"(createdAt|updatedAt)\"[[:space:]]*:[[:space:]]*\"[^\"]*\""
    ]
  } }
```

JSON bodies are sorted and pretty-printed before diffing, so a one-field change shows up as a
one-line diff rather than one enormous line.

`redact` patterns are POSIX extended regexes. **Redact narrowly.** Every pattern you add is a
field this collector stops watching, and a regex broad enough to catch every id is usually
broad enough to catch the value you cared about.

## `builtin:cmd-golden`

Captures stdout, stderr and exit code per case, and diffs against a golden file.

```json
{ "name": "cli", "kind": "builtin:cmd-golden",
  "config": {
    "cases": [
      { "name": "help",         "cmd": "./bin/app --help" },
      { "name": "migrate-plan", "cmd": "./bin/app migrate --dry-run" },
      { "name": "bad-flag",     "cmd": "./bin/app --nope" }
    ],
    "redact": ["[0-9]+(\\.[0-9]+)?(ms|s)\\b", "/Users/[^/ ]+", "/home/[^/ ]+"]
  } }
```

Include the error cases. Help text and failure messages are interface, they are what users
actually read, and they are the first thing a refactor breaks silently.

---

## Writing your own

Any executable, any language. Read env vars, write one JSON file, exit `0`/`1`/`2`:

```json
{ "name": "rowcounts", "cmd": "./scripts/rowcounts.sh" }
```

A worked twelve-line example is at the bottom of
[CONTRACT.md](../collectors/CONTRACT.md). Ideas that pay off quickly:

- **Migration reversibility** — row counts and checksums before, after, and after rollback.
  The plan claims the migration is reversible; this is the collector that checks.
- **Bundle size** — fails when a route's JS grows past a budget.
- **Accessibility** — `axe-core` violations per route, as `failed[]` entries.
- **Generated files** — regenerate and diff. Catches "someone edited the generated file".
- **OpenAPI/schema drift** — dump the live schema, diff against the committed one.

## Three rules that keep collectors honest

**Exit `2` when you could not check.** The most expensive bug in a harness like this is a
collector that cannot run and reports success: every downstream signal says clean, and the
report is confident about evidence that was never gathered. Both bundled network collectors
preflight their target for exactly this reason.

**Write `failed[].why` for someone who has not seen the artifact.** `"changed"` is useless.
`"size changed 1440x900 → 1440x1180"` is often the only thing anyone reads.

**Only list artifacts worth opening.** Everything in `failed[].artifacts` is something the
model will read. List all forty-eight screenshots there and you have rebuilt the cost problem
this design exists to avoid.
