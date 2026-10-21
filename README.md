# docs-maintainer

A DAM Starter Kit that keeps documentation up to date with the software it documents.

Point it at a source repository and a documentation repository on GitHub or GitHub Enterprise. The agent checks what your users actually run, verifies documentation against it, and opens pull requests for fixes and updates.

**The rule:** Documentation must reflect what users run. If a change can't be verified, it waits in a queue until it can.

Onboarding asks which of two ways your users get the software:

- **Tagged releases:** docs describe the latest stable release. New changes wait in the queue until a release ships them, then each release gets one pull request.
- **Main:** docs describe the main branch as it is. New changes are documented the day they land, in one rolling update pull request.

## How it works

- **Daily:** Reviews new source changes. With tagged releases it queues documentation updates; with main it adds them to the open update pull request. Fixes verified errors in existing docs immediately.
- **On release** (tagged releases only): Checks the release, re-verifies queued items, and opens a pull request with the necessary updates.
- **Weekly:** Audits documentation health and reports issues.
- **On request:** Runs a review, reports status, or deploys the site.

The agent never guesses. It leaves unreleased and feature-flagged changes undocumented and flags changes it can't verify.

## Setup

This repository is available as a DAM Starter Kit through `kit.yaml`.

1. Find `docs-maintainer` in Starter Kits and open it.
2. Grant access to GitHub or GitHub Enterprise. Connect each host if the source and docs repositories use different hosts.
3. Optionally connect Slack or Telegram for reports.
4. Name the agent and create it.
5. Complete the onboarding interview to confirm the repositories, release process, and documentation settings.

The agent configures its schedules after onboarding is complete.

### Without the Starter Kit catalog

Create the agent manually, grant the required connections, and send it this message:

> Read `ONBOARDING.md` in the deployed repository and follow its setup instructions:
> `https://github.com/<your-org>/docs-maintainer/blob/main/ONBOARDING.md`

Use the URL for the copy you actually deploy.

## Configuration

The agent creates `work/CONFIG.md` during onboarding.

Key settings include:

| Setting | Purpose |
| --- | --- |
| `source_repo` | Repository containing the software |
| `docs_repo` | Repository containing the documentation |
| `docs_branch`, `docs_path` | Documentation branch and directory |
| `release_model`, `stable_tag_pattern` | Tagged releases or main, and which tags count as stable |
| `build_command`, `deploy_command` | How docs are built and published |
| `reviewers` | Pull request reviewers |
| `structure_changes` | Whether the agent can create, delete, or move pages |

See [docs/config.md](docs/config.md) for all settings and defaults.

Optional environment variables:

- `GITHUB_REPO_WORK`: Private repository used to back up agent state.
- `DEF_HOST`: Git host for the Starter Kit definition when not using `github.com`.
- Environment variables matching configuration keys override stored values.

## Requirements and permissions

- Runs on the DAM agent platform with persistent storage and GitHub credential access.
- Requires `bash`, `git`, `jq`, `gh`, GNU `date`, and `timeout`, plus any tools needed to build the documentation.
- Needs read access to the source repository and permission to push branches and open pull requests in the docs repository.
- Never merges pull requests or pushes directly to the documentation branch.
- Deploys the site only when explicitly requested.

## Files

- [`kit.yaml`](kit.yaml): Starter Kit definition and schedules.
- [`CLAUDE.md`](CLAUDE.md): Core agent instructions.
- [`ONBOARDING.md`](ONBOARDING.md): Setup and initial configuration.
- [`docs/`](docs/): Detailed procedures, including [verification](docs/verification.md), [configuration](docs/config.md), and [persistence](docs/persistence.md).
- [`scripts/`](scripts/): Preflight checks, validation, backups, and tests.
- [`VERSION`](VERSION) and [`CHANGELOG.md`](CHANGELOG.md): Versioning and upgrade instructions.
- [`LICENSE`](LICENSE): Apache 2.0.
