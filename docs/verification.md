# Verification

Read on every run that triages, fixes or publishes. This file is the reason the agent
exists: **a claim reaches the site only after you traced it yourself at the release
boundary, in this run.** Every rule below is a way that standard has failed in practice.

## The boundary

The **boundary** is the ref the docs describe. The pre-flight resolves it and hands it to
you in `worklist.boundary`, so never derive it by hand in a gated run.

- `release_model: tags`: the newest tag matching `stable_tag_pattern`. Release
  candidates, betas and other pre-releases never count, whatever the highest tag is.
  A tag version sort puts `v1.2-rc2` above `v1.2` unless you filter first.
- `release_model: branch`: the head of `source_branch`, pinned to a commit sha at the
  start of the pass. There is no "unreleased" work then, only commits since the last
  pass.
- **Cross-check, never trust one signal.** Where `release_check` names a second source
  (a package registry's `latest` tag, a live `/version` endpoint), it must agree with the
  tag before you call a release shipped. A hosting service's Releases page is **not**
  evidence either way: entries lag, stay draft, and point at a different tag than their
  title.
- **A release branch rarely merges back.** Diff from the merge-base, never
  `<tag>..<default-branch>`: `git merge-base <tag> origin/<source_branch>`.
- **A version number on the default branch is the next version, not the current one.** A
  bump commit is not a release.
- **Cherry-picks defeat the ancestor check.** A commit can fail `--is-ancestor` and still
  ship, picked into the release branch under another sha. Before calling a commit
  unreleased, compare `git patch-id --stable` against the release-only set
  (`$BASE..<tag>`). When patch-ids differ, compare the resulting files: a pick applied on
  a different base changes the context lines.
- **A check is a snapshot, never a verdict on the day.** A pre-release cut that morning
  means the release is close. Never report "it didn't ship" from an early check.

## How to read the source

- **Every read is at the boundary**: `git show <ref>:<path>`, `git grep <pat> <ref> --`,
  `git ls-tree -r <ref>`. Never grep a working tree. A stale checkout is silent: it gives
  false positives and false negatives without announcing itself.
- **Prefer the source's own description of a subsystem** (architecture docs, a glossary)
  for the overview, but **the code wins** when the two disagree. Read those docs at the
  boundary too. Design records and decision logs (ADRs, RFCs) say what was *proposed*.
  Never cite them as behavior, and never link them from the site.
- **A glossary term marked proposed, draft or experimental is not shipped.**
- **Count UI files with `--name-only`.** `--stat` elides long paths and undercounts them.

## What counts as verified

- **A user-facing label** (a button, a menu item, a tab, a command): the literal string at
  the boundary, in the UI source or a template. Never from an architecture doc, a commit
  message or memory. **Count its render sites before writing "always"**: the same control
  is often labelled differently on different surfaces.
- **A view component is not a route.** Before writing that a page is reachable (or
  unreachable), follow the navigation code to the view it actually opens.
- **A number** (a cap, a timeout, a limit): trace it to the constant that *enforces* it.
  A number in a toast, a help string or a UI hint is not evidence; those are often stale.
  An operator-configurable value is not a user-facing promise. If no constant enforces a
  figure, write the behavior and drop the figure.
- **A negative or exhaustive claim** (*"there is no way to…"*, *"needs no…"*, *"only A and
  B"*) is the highest-risk sentence on any site. Any later feature falsifies it without
  touching the page. Trace it fully or soften it to what you can show.
- **Who may do something:** read the dispatch order. A check placed after the branch you
  care about does not apply to it.
- **A function exported but never called is not behavior.** Count its call sites.
- **A cross-link is itself a claim.** Open the page you link to and confirm it says what
  your sentence implies.
- **Feature flags.** Shipping is necessary but not sufficient. Where `flags_path` is set,
  read the flag definitions at the boundary. A surface gated behind a flag is **not
  documentable**: write neither the feature nor that a gate exists. Re-read the list every
  pass, because flags come and go between releases.
- **Something outside the boundary** (a template repo, a plugin, a base image, an upstream
  tool) cannot be verified by a tag check. Clone or inspect it at a stated commit, or
  leave the claim out.

## What counts as an error

- **Correction** = the page says something false at the boundary. **Addition** = the page
  is silent. Keep them separate everywhere: in the queue, in PR titles, in reports. Silence
  is not an error, and most "inaccuracies" turn out to be additions.
- **An unreleased fix can prove the site wrong today.** When a commit on the default branch
  fixes a bug, trace the *pre-fix* behavior at the boundary and grep the site. If the page
  promises what the bug breaks, it is a correction now. If the last link of that chain is
  outside the boundary, queue it instead.
- **"No docs impact" is a claim about the site**, not about the diff. Grep the site before
  writing it.
- **A frozen boundary cannot drift.** If a pass "finds new problems" on an unchanged
  release, it is finding its own backlog or re-reporting an earlier mistake. Check the
  queue and git history before calling anything drift.

## Before a pull request

- **Grep each corrected claim site-wide.** Reference pages and concept pages restate each
  other, and a fix to one leaves the other wrong.
- **Trace the whole sentence you touch**, not just the clause you meant to change. A
  retyped clause you never traced is a fresh publication of it. The same goes for a list:
  fixing one bullet does not fix its neighbours.
- **A rename sweep breaks quoted labels.** When a term changes, re-trace every quoted
  control the sweep touched; `sed` cannot tell prose from a label.
- **Re-read your own diff at the boundary.** Read every `+` line as if someone else wrote
  it. The easiest sentence to invent is a flattering one about how careful the system is.
- **Re-trace every subagent finding yourself.** Delegated checks come back confidently
  wrong, sometimes exactly backwards.
- **Build the site** with `build_command` when one is configured. A build that fails, or
  warns about a broken link, blocks the PR.
- **Follow `work/STYLE.md`** for voice, terminology and page conventions. Never coin a term
  the product does not use.
- **The PR body names the boundary** (tag or sha) and cites `path` at that ref for every
  claim, so a reviewer can verify without guessing.
