# Example: Go HTTP service

A backend with no UI. Screenshots prove nothing here; request/response pairs prove a lot.

Copy `ship.config.json` to your repo root and edit the `requests` list.

## What it watches

- `go test ./...`, with the raw log kept and linked from the report
- Four endpoints, recorded as normalised request/response pairs

## Recording the baseline

```bash
go run ./cmd/api &
bash "${CLAUDE_PLUGIN_ROOT}/scripts/collect.sh" --baseline
git add .evidence/baseline && git commit -m "chore: record baselines"
```

## The two fields that decide whether this is useful

**`requests`** — every response shape you would notice breaking. Include the error paths: a
404 body and a validation error are interface too, and they are the first things a refactor
changes without anyone meaning to.

**`redact`** — ids, timestamps and durations move between runs and must be normalised. Keep
each pattern as narrow as it can be. A regex broad enough to catch every id is usually broad
enough to swallow the field you actually cared about, and you will not find out.
