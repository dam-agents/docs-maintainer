# The release pass

Read on a release run. A new stable release is the event the work is planned around. Do
the whole review in one sitting and land **one** pull request covering **both** halves:
everything the release changed, and the entire open queue. The bar is that the release is
**finished**, not sampled.

## Pin the boundary

- `worklist.release_due` names the new boundary and the previous one. Record both in
  `work/RELEASES.log` before anything else, with the real UTC time.
- Re-confirm the boundary per [verification.md](verification.md) → **The boundary**,
  including `release_check` where it is set.
- **Diff the two boundaries first.** A release can carry no user-visible change (a
  rebuild, a version bump, a CI fix). The pass still runs, because it is also when the
  queue gets worked.

## Read every commit, not just the queue

The queue is a floor, never the scope. List the full range and read every change in it,
one merged pull request at a time (`--first-parent` keeps each one together):

```bash
git -C "$SRC" log --oneline --first-parent <previous>..<new>
git -C "$SRC" log --oneline "$(git -C "$SRC" merge-base <new> origin/<source_branch>)..<new>"
```

The second list is the release-only set: version bumps and any cherry-picks. Check each
pick against the queue by patch-id.

## Work the queue

At the start, list every `open` row whose `ref` is now inside the boundary, plus every
`correction` and `addition` row. Re-trace each one at the new boundary, because a
queue note's own wording is not evidence. Re-read the flag definitions too: a flag
that has been removed makes its `flagged` rows documentable.

## Write

- One branch (`release/<boundary>`) off the current `docs_branch`, and one PR.
- **Page-structure work** (a page added, deleted, merged or moved in `nav`) waits for the
  owner's go-ahead when `structure_changes: ask`. Ask in the direct session and continue
  with the rest of the pass while you wait.
- A new page is invisible until it is in the site's navigation, when the site has one.
- Run every check in [verification.md](verification.md) → **Before a pull request**. The
  re-read of your own diff is not optional on the largest PR of the release.

## The PR

- Title: `docs: <boundary> release pass — N corrections, M additions`.
- Body:
  - the boundary and the previous one;
  - corrections and additions in separate lists, each with `path @ ref` and the source
    pull request it came from;
  - what was held back, as unreleased, flagged, external or carried, with the reason.
- Request review from `reviewers`. When the token's own account is a reviewer the
  request is refused, so assign them instead.

## Close the queue

Every row the pass touched becomes `worked` (with the PR number), `obsolete` (with the
reason) or `carried` (with the reason). At the end, confirm no row in scope is still
`open`. A pass that silently drops a queued item is the failure this step exists for.

## Afterwards

Write the boundary to `work/BOUNDARY` (one line: the ref), remove
`work/.release-in-progress`, and report per [reporting.md](reporting.md). Merging is the
owner's. A merged PR is not yet published wherever the site needs a separate deploy step
([conversation.md](conversation.md) → **Deploy**).
