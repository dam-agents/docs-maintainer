# The daily update (`release_model: main`)

Read when the worklist carries `update_due`. With `release_model: main`, users run the
head of `source_branch`, so nothing is "unreleased" and new commits are documented the
day they land. The verification standard is unchanged ([verification.md](verification.md)).
The boundary is simply a commit instead of a tag.

## The boundary

- `update_due[0].pin` is the commit this update documents. It was pinned when the
  pre-flight ran. Read every claim at the pin (`git show <pin>:<path>`), never at
  `origin/<source_branch>`, which may have moved since.
- `previous` is the commit the docs described before. The range is `previous..pin`.

## Procedure

1. **Triage first.** Run every `triage_due` change through [queue.md](queue.md) → **Triage**,
   with one difference: in main mode a change is never `unreleased`. A change with docs
   impact is written **now**, in this update. Queue it only when it is `flagged`,
   `external`, or not yet verified.
2. **One open update PR at a time.** Look for an open PR from a branch named
   `update/<docs_branch>`.
   - If one exists, check out that branch, rebase it on the current `docs_branch`, and add
     today's changes to it. Update its title and body to cover the whole range from its
     first `previous` to today's `pin`.
   - If none exists, branch `update/<docs_branch>` off the current `docs_branch`.
3. **Write** the changes from step 1. Run every check in [verification.md](verification.md)
   → **Before a pull request**, against the pin.
4. **Ship** it per [fix.md](fix.md) steps 4–5, with these differences:
   - title: `docs: update for <source_branch>@<pin:12> — N corrections, M additions`;
   - body: the range `previous..pin`, the source pull requests it covers (`#n` each), the
     corrections and additions as separate lists with `path @ pin`, and anything queued
     instead, with the reason.
   - Push the branch, then open the PR, or update the one already open.
5. **Write `pin` to `work/BOUNDARY`** only after the push succeeded. Mark the rows the
   update covers `worked` with the PR number.

A day whose triage found no docs impact opens no PR. The pre-flight advances the pin
itself and the run never wakes.

## When the update PR is merged, closed, or stale

- **Merged:** the next sweep starts a new `update/` branch from the new `docs_branch`.
- **Closed without merging:** that is the owner's verdict on the PR, not on the claims.
  Ask in the direct session before writing the same changes again. Reopen the covered
  rows with the PR number in `note`.
- **Open more than 7 days:** the audit flags it. Keep adding to it. Never open a second
  one beside it.

Verified corrections ([fix.md](fix.md)) still go in their own small PR, opened at once.
They never wait for the update PR to merge.
