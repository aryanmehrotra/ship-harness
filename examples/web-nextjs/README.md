# Example: Next.js app

Copy `ship.config.json` to your repo root, then install the collector's dependencies:

```bash
npm i -D @playwright/test pixelmatch pngjs && npx playwright install chromium
```

## Recording the baseline

```bash
npm run dev &
bash "${CLAUDE_PLUGIN_ROOT}/scripts/collect.sh" --baseline
git add .evidence/baseline && git commit -m "chore: record baselines"
```

## `routes` is the file

Everything else here has a sensible default. `routes` does not, and it is the line that
decides how much the harness can see. A regression in a viewport, theme or signed-in state
the baseline never captured is invisible to every diff engine ever written.

Worth capturing beyond the happy path:

- the empty state and the error state, not just the populated one
- one route behind auth (use `storageState` in a custom collector if you need a session)
- the widest and narrowest layouts you support — breakpoints are where things actually break

## `mask` rather than a looser threshold

Clocks, relative timestamps, random avatars and carousels will flap forever. The tempting fix
is raising `maxRatio` until they stop; do not. A tolerance wide enough to swallow a clock is
wide enough to swallow a broken layout elsewhere on the same page, and nothing will tell you
it happened. Paint over the flapping element and keep the tolerance tight.
