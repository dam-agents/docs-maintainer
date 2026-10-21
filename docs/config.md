# Configuration keys (`work/CONFIG.md`)

Read when explaining or changing a value, or when a run has no `config` object. An env var
named after the key in upper case always wins over the stored value. Repository values
are `[<host>/]<owner>/<repo>`; a bare `owner/repo` means `github.com`.

## What is documented, and where

| Key | Default | Missing → | Meaning |
| --- | --- | --- | --- |
| `source_repo` | — | runs stop | The repository the software lives in. |
| `source_branch` | detected at onboarding | `main` | Its default branch: where unreleased work lands. |
| `docs_repo` | — | runs stop | The repository the site lives in. May equal `source_repo`. |
| `docs_branch` | detected at onboarding | `main` | The branch the site is built from. Pull requests target it. |
| `docs_path` | `docs` | `docs` | Directory of the site's pages inside `docs_repo`. |

## What counts as released

| Key | Default | Missing → | Meaning |
| --- | --- | --- | --- |
| `release_model` | `tags` | `tags` | `tags`: the boundary is the newest stable tag. `branch`: the boundary is `source_branch` itself, batched weekly. |
| `stable_tag_pattern` | `^v?[0-9]+\.[0-9]+\.[0-9]+$` | that default | Extended regex a tag must match to count as stable. Pre-releases must **not** match. |
| `release_check` | empty | none | Optional second signal the release pass cross-checks: `npm:<package>`, `pypi:<package>`, or `url:<https URL returning the version>`. |
| `flags_path` | empty | none | Optional path at the boundary that lists feature flags. Gated surfaces are never documented. |
| `branch_pass_days` | `7` | `7` | `release_model: branch` only: days between batched passes. |

## How the agent works

| Key | Default | Missing → | Meaning |
| --- | --- | --- | --- |
| `triage_ignore` | empty | none | Extended regex on a commit subject. Matching commits are logged as triaged with no impact (e.g. `^(ci\|test\|build)(\(.*\))?:`). |
| `triage_batch` | `50` | `50` | Most commits triaged per sweep. The rest wait for the next sweep. |
| `verify_pages_per_sweep` | `0` | `0` | Pages re-verified from scratch per sweep, oldest-verified first. `0` keeps quiet days free; `1` or more means every weekday sweep wakes. |
| `structure_changes` | `ask` | `ask` | `ask`: adding, deleting or moving a page waits for the owner. `allow`: the pass does it. |
| `build_command` | empty | no build | Run in the docs clone before every PR (e.g. `mkdocs build --strict`). A failure blocks the PR. |
| `deploy_command` | empty | publish on merge | Run only on the owner's request ([conversation.md](conversation.md) → **Deploy**). |
| `reviewers` | empty | none | Comma-separated logins asked to review every PR. |
| `commit_name`, `commit_email` | empty | the connection's account | Commit author of every docs commit. |
| `commit_trailer` | empty | none | One trailer line added to every commit (e.g. `Assisted-by: …`). |
| `run_model` | `default` | `default` | The model every scheduled session runs on. |

## Reporting

| Key | Default | Missing → | Meaning |
| --- | --- | --- | --- |
| `report_channel` | empty | no channel messages | `slack` or `telegram`. Empty keeps every report in chat. |
| `report_chat` | empty | no channel messages | The channel or chat id reports go to. |
| `owner_member_id` | empty | channel requests refused | The owner's member id on `report_channel`. Only this sender may ask for a pass or a deploy from the channel. |
| `audit_report` | `disabled` | `disabled` | Send a green audit to the channel too. A red one is always sent when a channel is set. |

## Housekeeping

| Key | Default | Missing → | Meaning |
| --- | --- | --- | --- |
| `definition_repo` | derived | no version check | This definition's repository, for the version check and definition PRs. |
| `log_level` | `info` | `info` | `debug` adds diagnostic events. Never gates behavior. |

Changing `source_repo` or `docs_repo` on a live instance resets the boundary: write the
new value, delete `work/BOUNDARY`, and the next release run does a baseline pass.
