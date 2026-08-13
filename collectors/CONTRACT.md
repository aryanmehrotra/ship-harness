# The collector contract

A collector is **any executable, in any language**, that answers one question:

> Did the observable behaviour of this thing change in a way nobody intended?

Screenshots are one answer. Request/response pairs, golden CLI output, test logs, query
results before and after a migration, generated files, accessibility violations — all
answer the same question about different surfaces. The harness does not care which one you
wrote. It cares that all of them report in the same shape, because that shape is what lets
the model read a hundred results without reading a hundred artifacts.

## What the harness gives you

Everything arrives as environment variables. No arguments, no config file to locate.

| Variable | Meaning |
|---|---|
| `SHIP_MODE` | `baseline` (record the oracle) or `compare` (check against it) |
| `SHIP_NAME` | this collector's name from `ship.config.json` |
| `SHIP_ROOT` | absolute path to the repo root; you are already `cd`'d here |
| `SHIP_OUT` | the exact file to write your report to |
| `SHIP_EVIDENCE_DIR` | `.evidence/` — put artifacts under `artifacts/<name>/` |
| `SHIP_BASELINE_DIR` | `.evidence/baseline/<name>/` — committed, treat as read-only in compare mode |
| `SHIP_COLLECTOR_CONFIG` | your `config` object from `ship.config.json`, as a JSON string |

## What you must give back

Write JSON to `$SHIP_OUT`:

```json
{
  "collector": "web",
  "status": "PASS",
  "failed": [
    {
      "id": "_checkout__390__dark",
      "why": "1,204 pixels differ (0.31% > 0.10% allowed)",
      "artifacts": [".evidence/baseline/web/_checkout__390__dark.png",
                    ".evidence/artifacts/web/_checkout__390__dark.png"]
    }
  ],
  "artifacts": [".evidence/artifacts/web"],
  "notes": "48 shots · 1 failed"
}
```

And exit with:

| Code | Status | Means |
|---|---|---|
| `0` | `PASS` | nothing changed that shouldn't have |
| `1` | `FAIL` | a real difference — the model will read `failed[]` |
| `2` | `BROKEN` | **you could not do your job** |

### Exit 2 is not a formality

The most expensive failure mode in a harness like this is a collector that cannot run and
reports it as success. The dev server was down; the binary wasn't built; a dependency is
missing. Every downstream signal then says "clean", and the run produces a confident report
about evidence that was never gathered.

Exit `2` whenever you could not actually check: missing dependency, unreachable target,
malformed config, a crash. `collect.sh` propagates it, and the ship pipeline stops rather
than writing a report. Both bundled collectors preflight their target for exactly this
reason.

## Three rules that keep this useful

**Write the `why` for a human who has not seen the artifact.** `"why": "changed"` is
useless. `"why": "size changed 1440x900 → 1440x1180"` tells the reader what happened before
they open anything. `failed[].why` is frequently the only thing anybody reads.

**Only list artifacts a reader would actually open.** The model is instructed to open
nothing except artifacts named inside `failed[]`. If you list all 48 screenshots there, you
have re-created the cost problem this design exists to avoid.

**Normalise narrowly, never loosely.** Redact the id, the timestamp, the duration. Do not
raise a global tolerance to make a flaky field pass — a threshold loose enough to swallow a
clock is loose enough to swallow a layout break on the other side of the page. Mask the
clock instead.

## A complete collector, in twelve lines

```bash
#!/usr/bin/env bash
# Fails if any table lost rows. Add to ship.config.json as {"name":"rowcounts","cmd":"./scripts/rowcounts.sh"}
set -uo pipefail
mkdir -p "$SHIP_BASELINE_DIR" "$SHIP_EVIDENCE_DIR/artifacts"
current="$SHIP_EVIDENCE_DIR/artifacts/rowcounts.txt"
psql -Atc "select relname,n_live_tup from pg_stat_user_tables order by 1" > "$current" || exit 2

[ "$SHIP_MODE" = baseline ] && { cp "$current" "$SHIP_BASELINE_DIR/counts.txt"; \
  jq -n '{collector:"rowcounts",status:"PASS",failed:[],artifacts:[],notes:"recorded"}' > "$SHIP_OUT"; exit 0; }

if d=$(diff -u "$SHIP_BASELINE_DIR/counts.txt" "$current"); then
  jq -n '{collector:"rowcounts",status:"PASS",failed:[],artifacts:[],notes:"unchanged"}' > "$SHIP_OUT"; exit 0
fi
jq -n --arg d "$d" --arg a "$current" '{collector:"rowcounts",status:"FAIL",
  failed:[{id:"rowcounts",why:"table row counts moved",diff:$d,artifacts:[$a]}],
  artifacts:[$a],notes:"row counts changed"}' > "$SHIP_OUT"; exit 1
```

Register it, and it runs in every `/ship-harness:ship` from then on.
