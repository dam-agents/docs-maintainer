# docs-maintainer

An agent for the DAM platform that keeps a documentation site true to the software it
documents. Point it at any two GitHub repositories, on github.com or GitHub Enterprise:
the one the software lives in and the one the docs live in (often the same one). It
works out what has actually shipped, traces every claim to that release, and opens pull
requests only for what it verified.

The rule it is built around: **the site describes the released software, never the
default branch, and a claim reaches the site only after it has been traced at the
release.** Anything it cannot verify waits in a queue instead.

## How it works

- **Weekday sweep** (06:00 UTC, gated). `scripts/preflight.sh sweep` fetches the source
  repo, works out the release boundary, and lists every commit past it that has not been
  triaged. It decides by sha, never by count. The agent triages each commit into
  `work/QUEUE.md`, recording what the docs will need once it ships, or into
  `TRIAGED.log` as no-impact. A published claim it proves wrong is fixed **now**, as its
  own small pull request. A day with nothing new is declined before any model wakes, and
  posts nothing.
- **Release watch** (hourly, gated). Wakes only when a new stable release exists. The
  agent then runs the **release pass**: it reads every commit in the release, re-traces
  every open queue row, and lands **one** pull request covering both. Corrections and
  additions are counted separately, and everything held back is named with its reason.
- **Weekly audit** (Friday 07:00 UTC). Deterministic health checks plus judgment checks,
  reported traffic-light. A verified error left published for more than a day is red.
- **On request**, in chat or from the owner in the channel: a pass now, a status report,
  a deploy.

What counts as a release is configured per instance:

- stable tags matching a pattern, with release candidates excluded and an optional
  package-registry or version-endpoint cross-check;
- or, for projects that ship from their default branch, a batched weekly pass.

The agent reads the source only at the release ref (`git show <tag>:<path>`), never from a
working tree. It leaves anything behind a feature flag undocumented. It queues anything
that depends on code outside the release instead of guessing.

Scripts only **detect**: they compute the worklist and never act. Every edit, pull
request and message is the agent's. The always-loaded core is small: `CLAUDE.md` holds
the contracts and invariants, and the procedures in `docs/` are read only when their work
fires. The definition is versioned through `VERSION` and a `CHANGELOG.md` of per-version
upgrade steps.

## Setup

This repository is its own **Starter Kit** ([`kit.yaml`](kit.yaml)):

1. **Find it under Starter kits** and open it.
2. **Grant the connections it asks for:**
   - **GitHub** or **GitHub Enterprise** (required). One connection per host when the
     source and docs repos live on different hosts. Use a bot or machine account where
     you can, because the pull requests are opened as that account.
   - **Slack** or **Telegram** (optional). Only for reports. Skip it to keep everything
     in chat.
3. **Name the agent and create it.** The platform seeds this definition, creates the three
   schedules, and opens the first session on [`ONBOARDING.md`](ONBOARDING.md).
4. **Answer the onboarding interview.** The agent detects what it can (default branches,
   the docs directory, the build tool, which tags are stable), then asks you to confirm it.
   Its schedules are **held** until it reports itself set up.

Not in a catalog yet? Add one entry to the catalog repository's `catalog.yaml`:

```yaml
kits:
  - url: https://github.com/dam-agents/docs-maintainer
```

### Without the catalog

Create the agent by hand, grant the same connections, then send it its first message:

> Here is a file — read it and set yourself up according to it:
> `https://github.com/<your-org>/docs-maintainer/blob/main/ONBOARDING.md`

Link the copy you actually deploy from: the agent derives its definition repo from that URL.

## Configuration

### Environment variables

| Variable | Required | Description |
| --- | --- | --- |
| `GITHUB_REPO_WORK` | No | `<owner>/<repo>` of a **private** repository that backs up `work/` after every state-changing run. Unset means the queue and notes live on the volume only. |
| `DEF_HOST` | No | Host of this definition repo when it is not `github.com`. |
| Any config key, upper-cased | No | Overrides the stored value (`SOURCE_REPO`, `DOCS_BRANCH`, …). |

### `work/CONFIG.md`

Filled at onboarding. Every key, with its default and missing-key behavior:
[docs/config.md](docs/config.md). The main ones:

| Key | Purpose |
| --- | --- |
| `source_repo`, `docs_repo` | What is documented, and which git repository the docs live in (any GitHub host, or the source repo itself). `[<host>/]<owner>/<repo>`. |
| `docs_branch`, `docs_path` | The branch the docs are built from, and the folder the pages live in. |
| `release_model`, `stable_tag_pattern`, `release_check` | What counts as released. |
| `flags_path` | Where the source lists feature flags. Gated surfaces are never documented. |
| `docs_path`, `build_command`, `deploy_command` | Where the pages are, how they build, how they publish. |
| `reviewers`, `commit_name`, `commit_email`, `commit_trailer` | Who reviews, and how commits are attributed. |
| `structure_changes` | Whether a pass may add, delete or move pages on its own. Default `ask`. |
| `report_channel`, `report_chat`, `owner_member_id` | Optional channel reports. Off by default. |

## Runtime requirements

- **Platform:** the DAM agent infrastructure: `$HOME` at `/home/agent` on a persistent
  volume, the outbound proxy that injects GitHub credentials, and the
  `mcp__platform-outbound__*` tools for schedules and channel messages.
- **Pod tooling:** `bash`, `git`, `jq`, `gh`, GNU `date`, `timeout`. Your build tool, when
  `build_command` uses one (for example `pip install -r requirements.txt` for MkDocs).
- **Identity:** the agent acts as the account behind each GitHub connection. It needs
  read access to the source repo and branch-push plus pull-request access to the docs
  repo. It never needs merge rights. It never merges, and never pushes to the docs
  branch.
- **External surfaces:** pull requests on the docs repo, and messages to the configured
  report channel when there is something to say. With `deploy_command`, the deployed site,
  but only on the owner's request.

## Persistence

`work/` is a plain data directory on the persistent volume. It is never a git repo,
because the shared volume corrupts a `.git` that concurrent runs mutate. With
`GITHUB_REPO_WORK` set, every state-changing run ends by snapshotting `work/` into a
disposable tmpfs clone and pushing it. The source and docs repos are cached under
`/var/tmp/docs-maintainer/`, off the volume, and rebuilt after a pod restart.

The definition updates through the platform's Kit Update, which never touches `work/`.
Versions and migrations happen only in the direct session. Details:
[docs/persistence.md](docs/persistence.md).

## Files

- [`kit.yaml`](kit.yaml): the Starter Kit (seed, connections, schedules).
- [`CLAUDE.md`](CLAUDE.md): the slim core manual loaded on every run.
- [`AGENTS.md`](AGENTS.md): harness entry pointer to `CLAUDE.md`.
- [`ONBOARDING.md`](ONBOARDING.md): first-run interview, `work/` seeds, schedules.
- [`docs/`](docs/): procedures, read on demand. Start with
  [`docs/verification.md`](docs/verification.md).
- [`scripts/`](scripts/): the pre-flight, the precheck gate, the onboarding verifier, the
  backup, logging, and the offline tests.
- [`VERSION`](VERSION) + [`CHANGELOG.md`](CHANGELOG.md): semver and per-version upgrade steps.
- [`LICENSE`](LICENSE): Apache 2.0.
