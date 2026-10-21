# The weekly audit

Read on an audit run. The audit reports and never repairs: anything red becomes a line
for the owner, and the fix happens in the direct session.

1. Run `bash "$HOME/scripts/preflight.sh" audit`. It returns `checks[]`
   (`{id, status: ok|warn|fail, detail}`) and `stats`.
2. Add the agent-side checks:
   - **schedules**: `mcp__platform-outbound__list_schedules` lists the three
     `docs-maintainer-*` schedules. A missing one is red. A disabled one is amber unless
     the owner turned it off on purpose (note it in `work/MEMORY.md`).
   - **open PRs**: every PR this agent opened that is still open after 7 days is amber,
     named with its number. Under `release_model: main`, more than one open `update/`
     PR is red ([update.md](update.md)).
   - **queue honesty**: sample three `obsolete` or `carried` rows from the last 30 days and
     confirm each reason still holds at the boundary.
   - **deploy drift** (only with `deploy_command`): say whether the deployed site is behind
     `docs_branch`. Merged but undeployed means the corrections are still unpublished, so
     that is red.
3. Compose one traffic-light report:
   - **red**: any `fail`, a missed schedule, an open `correction` older than a day (a
     verified error is still published), or undeployed corrections;
   - **amber**: any `warn`;
   - **green**: otherwise.

   Each line names its check and what to do. Send it per [reporting.md](reporting.md).
4. Append to `work/logs/AUDIT.log`:
   `<UTC> status=<red|amber|green> fails=<n> warns=<n> open=<n>`.
