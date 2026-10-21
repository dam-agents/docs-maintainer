# The queue (`work/QUEUE.md`)

Read for triage and for any read or write of the queue. The queue is where every finding
lives until it is worked. On an ordinary day it is the only thing the agent changes.

## Row format

One markdown table, one row per finding, appended. Never reorder or delete a row.

```markdown
| id | status | kind | ref | page | note | evidence | updated |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Q0001 | open | unreleased | a1b2c3d4 | guides/install.md | install needs --region once it ships | src/cli/install.ts @ main | 2026-01-07T06:02:11Z |
```

- `id`: `Q` + a 4-digit counter from `work/QUEUE-counter`. Never reused.
- `status`: `open` | `worked` | `obsolete` | `carried`.
  - `worked`: a merged-or-open PR covers it, so `note` names the PR.
  - `obsolete`: re-traced, and nothing is left to write. The reason goes in `note`.
  - `carried`: deliberately held past a release pass. The reason goes in `note`.
- `kind`:
  - `unreleased`: on the default branch, past the boundary;
  - `correction` / `addition`: about the released site;
  - `flagged`: shipped, but behind a feature flag (name the flag in `note`);
  - `external`: depends on something outside the boundary;
  - `upstream`: a product bug or a stale product string, never a docs claim.
- `ref`: the change's `key` (a 12-char commit sha) for `unreleased`. Name the pull request
  in `note` when the change has one. For a released-site finding, the boundary it was
  verified at.
- `page`: the docs path, or `—` when there is no page yet.
- `evidence`: `<path> @ <ref>`. For an `unreleased` row that has no page impact, `—`.

Changes the sweep judged to have **no docs impact** go to `work/TRIAGED.log`, one line each
(`<key> <UTC> none <one-line reason>`). Every change's `key` the agent has looked at appears
in exactly one of `QUEUE.md` or `TRIAGED.log`. That is how the pre-flight knows which shas
are new.

## Triage (`triage_due`)

Each `triage_due` entry is **one change as it landed**: a merged pull request (`pr` set,
`kind` `squash`, `merge` or `rebase`), or a commit pushed straight to the branch (`kind`
`commit`). `range` covers every commit in it. For each, oldest first:

1. Read the change: `git log` and `git diff --name-only` over its `range`, then the diff
   of any file that could reach a user. Where `pr` is set, read the pull request's
   description too (`gh pr view <pr> -R <source_repo>`), for **context only**: it says what
   the author meant, and it is often stale by merge. Every claim is still traced in the
   code at the boundary (verification.md → **How to read the source**).
2. Grep the site for every user-facing term the change touches. "No docs impact" needs that
   grep (verification.md → **What counts as an error**).
3. Decide:
   - **Nothing a user could observe, or nothing the site says or should say** → one
     `TRIAGED.log` line under the `key`, with the reason.
   - **The docs will need to change once it ships** → an `unreleased` row with one line on
     what they will then need to say. Under `release_model: main` nothing is unreleased:
     the change is written today ([update.md](update.md)), so no row is needed unless it
     is `flagged`, `external`, or not yet verified.
   - **It proves the released site wrong today** → a `correction` row with evidence at the
     boundary, and fix it this run ([fix.md](fix.md)).
   - **Gated behind a flag** → a `flagged` row with the flag id.
4. Record the decision under the entry's `key`, once for the whole change. Merge into
   existing rows rather than duplicating: a change touching a sentence already queued
   updates that row's `note`.

**Derive the untriaged set from the shas, never from a count.** The pre-flight does this
for you. A count can stay the same while new changes land and others are rebased away.

## Released-site findings

Anything you notice about the published site goes in as a `correction` or `addition` row
with its evidence. A correction you have *verified* is fixed now ([fix.md](fix.md)). An
addition waits for the release pass. A suspicion you have not verified is an `open` row
whose note says what still needs tracing.

## Closing rows

At the end of a release pass every `open` row is either `worked`, `obsolete` or `carried`.
None stays silently open ([release-pass.md](release-pass.md) → **Close the queue**).
Update `updated` with the real UTC time of each change.
