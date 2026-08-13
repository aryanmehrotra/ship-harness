# Trackers

The pipeline needs somewhere durable to put run state, so that killing a run loses nothing.
That is the only thing a tracker is for here, and it is why the interface is four verbs.

`scripts/tracker.sh` is the only file in the harness that knows what a tracker is.

## The four verbs

```bash
tracker.sh kind                    # print the configured kind
tracker.sh fetch  <id>             # print the ticket and its discussion
tracker.sh status <id> <file>      # upsert THE single status comment from <file>
tracker.sh link   <id>             # print a URL (or local path) for the report
```

`status` is an **upsert**, and that matters. One comment per ticket, edited in place. A
pipeline that posts a comment per stage turns the ticket into a changelog nobody reads and
current state stops being findable — which defeats the point of keeping state there.

## Bundled

### `github`

Needs an authenticated `gh` and a GitHub remote. `fetch` tries `gh issue view --comments`,
then `gh pr view --comments`. `status` stores the comment id in `.evidence/comment-id` and
`PATCH`es it thereafter; if that comment was deleted, it posts a new one rather than dropping
the update.

Numeric ids are extracted from whatever you pass, so `123`, `#123` and `T-123` all work.

### `none`

No tracker. `status` writes `.evidence/status.md`, `fetch` prints the last local status,
`link` returns the local path.

The resume guarantee still holds — `.evidence/` is on disk and `.evidence/phase` still says
where the run was. What you lose is teammates seeing it.

## Adding one

Implement the four verbs. Nothing else in the harness changes.

```bash
# scripts/tracker-linear.sh
case "$1" in
  kind)   echo linear ;;
  fetch)  linear issue view "$2" ;;
  status) # upsert: reuse the stored id, or create and store one
          if [ -s .evidence/comment-id ]; then
            linear comment update "$(cat .evidence/comment-id)" --body-file "$3"
          else
            linear comment create "$2" --body-file "$3" --json | jq -r .id > .evidence/comment-id
          fi ;;
  link)   linear issue url "$2" ;;
esac
```

Then either add a branch to `scripts/tracker.sh` and set `tracker.kind`, or — until that
lands upstream — point the ship skill at your script.

Two things to get right, because they are what the pipeline actually relies on:

1. **`status` must be idempotent.** It is called at every stage boundary. Creating a new
   comment each time is the failure mode described above.
2. **Failures must be loud.** Exit non-zero and say why. A tracker that silently swallows an
   update means the run's state exists only in a session that is about to end — which is the
   exact condition rule 4 exists to prevent.

## Why not just use the PR body

You can, and for solo work it is fine.

It stops working when the run dies before the PR exists — which is precisely when durable
state earns its keep. The issue exists from the start; the PR does not.
