# Changelog

**Migration instructions, not a change log.** Per version, the idempotent **Upgrade**
steps a deployed instance applies when crossing it — what to run, update, or change
(schedules, config keys, state formats). Most versions need nothing. What changed and
why lives in the PR and commit history, not here. Consumed by the version check
([docs/persistence.md](docs/persistence.md) → **Definition version & upgrade**);
authoring rules: [docs/self-modification.md](docs/self-modification.md) §12.

## 3.0.0 — 2026-10-21

**Upgrade:**
1. Re-register `docs-maintainer-sweep-weekday` with the task text in ONBOARDING.md
   Step 5 (create the new one, then delete the old id). The task now names
   `release_due`.
2. If `work/CONFIG.md` says `release_model: main`, `delete_schedule` the
   `docs-maintainer-release-hourly` schedule. Under `main` the sweep runs the baseline.
   With `tags`, keep it.

## 2.0.1 — 2026-10-21

**Upgrade:**
Nothing — docs are re-read per run.

## 2.0.0 — 2026-10-21

**Upgrade:**
1. Re-register `docs-maintainer-sweep-weekday` with the task text in ONBOARDING.md
   Step 5 (create the new one, then delete the old id). The task now names
   `update_due`.
2. `release_model: branch` is replaced by `release_model: main`: commits are documented
   the day they land, in one rolling update PR ([docs/update.md](docs/update.md)),
   instead of being batched weekly. If `work/CONFIG.md` says `branch`, ask the owner
   whether users run main. On yes, write `main` and write the commit the docs describe
   today to `work/BOUNDARY`. Otherwise write `tags`.
3. Delete the `- branch_pass_days:` bullet from `work/CONFIG.md`. It is no longer a key.
4. Triage now works per merged pull request rather than per commit. Nothing to migrate:
   existing `TRIAGED.log` and queue keys are commit shas and stay valid. Create
   `work/UNITS.log` if it is missing (`touch "$HOME/work/UNITS.log"`).
5. Delete the `- run_model:` bullet from `work/CONFIG.md`. The model is the owner's
   choice on the platform. Leave any `model` already set on a schedule alone.
6. Run `bash "$HOME/scripts/verify-onboarding.sh"` and apply every `fix:`.

## 1.0.0 — 2026-10-21

**Upgrade:**
Nothing — initial version; onboarding records it (`work/VERSION`).
