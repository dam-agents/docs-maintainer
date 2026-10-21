# A verified error fix

Read when a published claim is verified wrong at the boundary. **A known error is never
left published** to wait for a release pass. Fix it now, in its own small pull request.

## When this shape applies

- The page states something false **at the boundary**, and you traced the truth there in
  this run ([verification.md](verification.md)).
- It is a **correction**, not an addition. A missing topic waits for the release pass,
  unless the owner asks for it now.
- A *suspicion* is not a fix. It goes in the queue with what still needs tracing.
- A closed earlier PR about the same claim is not a verdict on the claim. Open a fresh one
  off the current `docs_branch`; never reopen or re-push an old branch, which can quietly
  revert later work.

## Procedure

1. Clone or refresh the docs repo under `/var/tmp/docs-maintainer/docs` and branch from
   the current `docs_branch`: `fix/<short-slug>`. Never reuse a stale branch.
2. Make the smallest edit that makes the page true. Grep the claim site-wide and fix every
   page that restates it, in the same PR. Do not bundle a re-audit into it.
3. Run the **Before a pull request** checks in [verification.md](verification.md),
   including the build.
4. Commit as the configured identity (`commit_name`/`commit_email`, falling back to
   the connection's account), and add `commit_trailer` when one is set. Never add
   `Co-Authored-By`.
5. Push the branch and open the PR against `docs_branch`:
   - title: `docs: fix <what was wrong>`;
   - body: the boundary, the claim as published, the truth, and `path @ ref` for each;
   - request review from `reviewers` when it is set. When the token's own account is a
     reviewer the request is refused, so assign them instead.
6. Mark the queue row `worked` with the PR number. Report per [reporting.md](reporting.md).

Never merge the PR yourself. Never push to `docs_branch`.
