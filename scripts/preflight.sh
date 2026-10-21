#!/usr/bin/env bash
# preflight.sh — deterministic pre-flight for docs-maintainer.
#
# The script DETECTS, it NEVER ACTS:
#
#   - NO external writes at all (git fetch / ls-remote / log only),
#   - NO git commit/push (the agent persists at end of run),
#   - local writes only: the bare caches under $CLONE_ROOT, `none` lines in
#     work/TRIAGED.log for commits `triage_ignore` matches, and log lines.
#
#   preflight.sh <sweep|release|audit>  -> one JSON object on stdout; everything else to stderr.
#   .nothing_to_do == true  -> the agent ends the run immediately.
#   otherwise               -> the agent processes the arrays per CLAUDE.md + docs/.
#
# Requires: bash, jq, git, sed/grep/cut/tr/sort, GNU date (Linux pod).

set -u
export LC_ALL=C GIT_TERMINAL_PROMPT=0

MODE="${1:-sweep}"
HOME_DIR="${HOME:-/home/agent}"
WORK="${WORK_DIR:-$HOME_DIR/work}"
CONFIG="$WORK/CONFIG.md"
CLONE_ROOT="${DM_CLONE_ROOT:-/var/tmp/docs-maintainer}"
NOW_EPOCH=$(date -u +%s)
NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)

LOGS=()
log() { LOGS+=("$1"); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/config.sh" || { echo "cannot source lib/config.sh" >&2; exit 1; }
LOG_JOB="$MODE"
if ! . "$SCRIPT_DIR/log.sh" 2>/dev/null; then logev() { :; }; fi

iso2epoch() { date -d "$1" +%s 2>/dev/null \
              || date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null || echo 0; }
logs_json() { printf '%s\n' "${LOGS[@]:-}" | jq -R . | jq -s '[.[] | select(length>0)]'; }

fail_out() {  # nothing-to-do JSON with an error; the agent just logs it
  logev error preflight "$MODE: $1"
  jq -n --arg mode "$MODE" --arg err "$1" --argjson logs "$(logs_json)" \
    '{mode:$mode, nothing_to_do:true, error:$err, logs:$logs}'
  exit 0
}

quiet_out() {  # nothing to do, and that IS the answer
  logev info preflight "$MODE: nothing to do — $(printf '%s; ' "${LOGS[@]:-}")"
  jq -n --arg mode "$MODE" --argjson logs "$(logs_json)" \
    '{mode:$mode, nothing_to_do:true, logs:$logs}'
  exit 0
}

# ---------------------------------------------------------------- config ----
# env var (upper-case key) wins, then the stored value, then the default
key() { local k="$1" d="${2:-}" up v; up="$(printf '%s' "$k" | tr '[:lower:]' '[:upper:]')"
        v="${!up:-}"; [ -n "$v" ] || v="$(cfg "$k")"; printf '%s' "${v:-$d}"; }

SOURCE_REPO_V="$(key source_repo)"
SOURCE_BRANCH_V="$(key source_branch main)"
DOCS_REPO_V="$(key docs_repo)"
DOCS_BRANCH_V="$(key docs_branch main)"
DOCS_PATH_V="$(key docs_path docs)"
RELEASE_MODEL_V="$(key release_model tags)"
STABLE_RE="$(key stable_tag_pattern '^v?[0-9]+\.[0-9]+\.[0-9]+$')"
IGNORE_RE="$(key triage_ignore)"
BATCH="$(key triage_batch 50)"
PAGES_N="$(key verify_pages_per_sweep 0)"
PASS_DAYS="$(key branch_pass_days 7)"

config_json() {
  jq -n \
    --arg source_repo "$SOURCE_REPO_V" --arg source_branch "$SOURCE_BRANCH_V" \
    --arg docs_repo "$DOCS_REPO_V" --arg docs_branch "$DOCS_BRANCH_V" --arg docs_path "$DOCS_PATH_V" \
    --arg release_model "$RELEASE_MODEL_V" --arg stable_tag_pattern "$STABLE_RE" \
    --arg release_check "$(key release_check)" --arg flags_path "$(key flags_path)" \
    --arg branch_pass_days "$PASS_DAYS" --arg triage_ignore "$IGNORE_RE" --arg triage_batch "$BATCH" \
    --arg verify_pages_per_sweep "$PAGES_N" --arg structure_changes "$(key structure_changes ask)" \
    --arg build_command "$(key build_command)" --arg deploy_command "$(key deploy_command)" \
    --arg reviewers "$(key reviewers)" --arg commit_name "$(key commit_name)" \
    --arg commit_email "$(key commit_email)" --arg commit_trailer "$(key commit_trailer)" \
    --arg run_model "$(key run_model default)" --arg report_channel "$(key report_channel)" \
    --arg report_chat "$(key report_chat)" --arg owner_member_id "$(key owner_member_id)" \
    --arg audit_report "$(key audit_report disabled)" --arg definition_repo "$(key definition_repo)" \
    --arg log_level "$(key log_level info)" \
    '$ARGS.named'
}

case "$BATCH" in (''|*[!0-9]*) BATCH=50;; esac
case "$PAGES_N" in (''|*[!0-9]*) PAGES_N=0;; esac
case "$PASS_DAYS" in (''|*[!0-9]*) PASS_DAYS=7;; esac

# ---------------------------------------------------------------- git ----
# `[<host>/]<owner>/<repo>` -> clone URL. DM_URL_BASE lets the offline tests use file://.
repo_url() {
  local r="$1" host=github.com path="$1"
  case "$r" in (*/*/*) host="${r%%/*}"; path="${r#*/}";; esac
  printf '%s/%s.git' "${DM_URL_BASE:-https://$host}" "$path"
}

# A bare, blob-less cache per repository: refs and history only, blobs on demand. It
# lives off the home volume (a .git there corrupts under concurrent runs), and a pod
# restart that wipes it costs one re-clone.
SRC="$CLONE_ROOT/source.git"
DOC="$CLONE_ROOT/docs.git"
sync_repo() {  # <dir> <repo> <branch>
  local dir="$1" url; url="$(repo_url "$2")"
  mkdir -p "$CLONE_ROOT" 2>/dev/null || return 1
  if ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
    rm -rf "$dir"
    git clone -q --bare --filter=blob:none "$url" "$dir" 2>/dev/null \
      || git clone -q --bare "$url" "$dir" 2>/dev/null || return 1
  else
    git -C "$dir" remote set-url origin "$url" 2>/dev/null || return 1
  fi
  git -C "$dir" fetch -q --prune --tags origin "+refs/heads/$3:refs/remotes/origin/$3" 2>/dev/null
}

# The newest stable tag. Filter BEFORE sorting: a version sort ranks v1.2-rc2 above v1.2.
stable_tag() {
  git -C "$SRC" tag -l 2>/dev/null | grep -E -- "$STABLE_RE" | sort -V | tail -1
}

# The boundary the docs describe now: a tag name, or a commit sha in branch mode.
resolve_boundary() {
  if [ "$RELEASE_MODEL_V" = branch ]; then
    git -C "$SRC" rev-parse "refs/remotes/origin/$SOURCE_BRANCH_V" 2>/dev/null
  else
    stable_tag
  fi
}

BOUNDARY_FILE="$WORK/BOUNDARY"
LAST_BOUNDARY="$(head -1 "$BOUNDARY_FILE" 2>/dev/null | tr -d '[:space:]')"

# Every sha the agent has already looked at, as 12-char prefixes.
known_shas() {
  { sed -nE 's/^\| Q[0-9]+ \| [a-z]+ \| [a-z]+ \| ([0-9a-f]{7,40}) \|.*/\1/p' "$WORK/QUEUE.md" 2>/dev/null
    sed -nE 's/^([0-9a-f]{7,40})[[:space:]].*/\1/p' "$WORK/TRIAGED.log" 2>/dev/null
  } | cut -c1-12 | sort -u
}

open_rows() {  # [kind] -> the open rows, optionally of one kind
  grep -E "^\| Q[0-9]+ \| open \| ${1:-[a-z]+} \|" "$WORK/QUEUE.md" 2>/dev/null || true
}

READ_SET=()

# ============================================================ SWEEP MODE ====
mode_sweep() {
  [ -f "$CONFIG" ] || fail_out "work/CONFIG.md missing — not onboarded"
  [ -n "$SOURCE_REPO_V" ] && [ -n "$DOCS_REPO_V" ] || fail_out "source_repo or docs_repo unset"
  sync_repo "$SRC" "$SOURCE_REPO_V" "$SOURCE_BRANCH_V" \
    || fail_out "cannot fetch $SOURCE_REPO_V ($SOURCE_BRANCH_V) — check the GitHub connection for its host"

  local head base boundary
  head="$(git -C "$SRC" rev-parse "refs/remotes/origin/$SOURCE_BRANCH_V" 2>/dev/null)" \
    || fail_out "branch $SOURCE_BRANCH_V not found in $SOURCE_REPO_V"
  boundary="$(resolve_boundary)"
  if [ "$RELEASE_MODEL_V" = branch ]; then
    base="${LAST_BOUNDARY:-$head}"
  elif [ -z "$boundary" ]; then
    log "no tag matches stable_tag_pattern — nothing released to compare against"
    base=""
  else
    base="$(git -C "$SRC" merge-base "$boundary" "$head" 2>/dev/null)"
    [ -n "$LAST_BOUNDARY" ] && [ "$boundary" != "$LAST_BOUNDARY" ] \
      && log "release $boundary is newer than the documented $LAST_BOUNDARY — the release run picks it up"
  fi

  # ---- untriaged commits: differenced by sha, never by count
  local triage='[]' known n=0 ignored=0 sha subj
  if [ -n "$base" ]; then
    known="$(known_shas)"
    while IFS="$(printf '\t')" read -r sha subj; do
      [ -n "$sha" ] || continue
      printf '%s\n' "$known" | grep -qxF "${sha:0:12}" && continue
      if [ -n "$IGNORE_RE" ] && printf '%s' "$subj" | grep -qE -- "$IGNORE_RE"; then
        printf '%s %s none triage_ignore\n' "${sha:0:12}" "$NOW_ISO" >> "$WORK/TRIAGED.log"
        ignored=$((ignored + 1)); continue
      fi
      [ "$n" -ge "$BATCH" ] && { n=$((n + 1)); continue; }
      triage="$(printf '%s' "$triage" | jq -c --arg sha "${sha:0:12}" --arg s "$subj" '. + [{id:$sha, sha:$sha, subject:$s}]')"
      n=$((n + 1))
    done <<EOF
$(git -C "$SRC" log --reverse --no-merges --format='%H%x09%s' "$base..$head" 2>/dev/null)
EOF
  fi
  [ "$ignored" -gt 0 ] && log "$ignored commit(s) matched triage_ignore and were logged as triaged"
  [ "$n" -gt "$BATCH" ] && log "$n untriaged commits; this run takes $BATCH, the rest wait for the next sweep"
  log "$( [ "$n" -gt "$BATCH" ] && echo "$BATCH" || echo "$n") commit(s) to triage on $SOURCE_BRANCH_V past ${boundary:-<no release>}"

  # ---- verified corrections waiting to be fixed: never left published
  local fixes
  fixes="$(open_rows correction | sed -E 's/^\| (Q[0-9]+) \| [a-z]+ \| [a-z]+ \| [^|]* \| ([^|]*) \|.*/\1\t\2/' \
    | jq -Rc 'split("\t") | {id:.[0], page:(.[1] // "" | gsub("^ +| +$";""))}' | jq -sc .)"
  [ "$(printf '%s' "$fixes" | jq length)" -gt 0 ] \
    && log "$(printf '%s' "$fixes" | jq length) open correction(s): a verified error is still published"

  # ---- pages due a from-scratch re-verification, oldest-verified first
  local pages='[]'
  if [ "$PAGES_N" -gt 0 ]; then
    if sync_repo "$DOC" "$DOCS_REPO_V" "$DOCS_BRANCH_V"; then
      pages="$(git -C "$DOC" ls-tree -r --name-only "refs/remotes/origin/$DOCS_BRANCH_V" -- "$DOCS_PATH_V" 2>/dev/null \
        | grep -E '\.(md|mdx|rst|adoc)$' | while read -r p; do
            t="$(grep -F " $p" "$WORK/VERIFIED.log" 2>/dev/null | tail -1 | cut -d' ' -f1)"
            printf '%s %s\n' "${t:-0000}" "$p"
          done | sort | head -n "$PAGES_N" | cut -d' ' -f2- | jq -R . | jq -sc .)"
      log "$(printf '%s' "$pages" | jq length) page(s) due re-verification"
    else
      log "cannot fetch $DOCS_REPO_V — page re-verification skipped this run"
    fi
  fi

  local work
  work="$(jq -n --argjson t "$triage" --argjson f "$fixes" --argjson p "$pages" \
    '($t|length) + ($f|length) + ($p|length)')"
  [ "$work" -gt 0 ] || quiet_out

  READ_SET=(docs/verification.md docs/reporting.md)
  [ "$(printf '%s' "$triage" | jq length)" -gt 0 ] && READ_SET+=(docs/queue.md)
  [ "$(printf '%s' "$fixes" | jq length)" -gt 0 ] && READ_SET+=(docs/fix.md)
  [ "$(printf '%s' "$pages" | jq length)" -gt 0 ] && READ_SET+=(docs/queue.md)
  jq -n --arg mode sweep --arg boundary "$boundary" --arg base "$base" --arg head "$head" \
    --argjson triage "$triage" --argjson fixes "$fixes" --argjson pages "$pages" \
    --argjson read_set "$(printf '%s\n' "${READ_SET[@]}" | sort -u | jq -R . | jq -sc .)" \
    --argjson config "$(config_json)" --argjson logs "$(logs_json)" \
    '{mode:$mode, nothing_to_do:false, boundary:$boundary, merge_base:$base, source_head:$head,
      triage_due:$triage, fixes_due:$fixes, pages_due:$pages, read_set:$read_set,
      config:$config, logs:$logs}'
}

# ========================================================== RELEASE MODE ====
mode_release() {
  [ -f "$CONFIG" ] || fail_out "work/CONFIG.md missing — not onboarded"
  [ -n "$SOURCE_REPO_V" ] && [ -n "$DOCS_REPO_V" ] || fail_out "source_repo or docs_repo unset"

  # A pass already running: one release, one pull request.
  local marker="$WORK/.release-in-progress" age
  if [ -f "$marker" ]; then
    age=$(( NOW_EPOCH - $(iso2epoch "$(head -1 "$marker")") ))
    if [ "$age" -lt 21600 ]; then log "a release pass is in progress (started $(head -1 "$marker"))"; quiet_out; fi
    log "a release pass marker is $((age / 3600))h old — treating that pass as abandoned"
  fi

  sync_repo "$SRC" "$SOURCE_REPO_V" "$SOURCE_BRANCH_V" \
    || fail_out "cannot fetch $SOURCE_REPO_V ($SOURCE_BRANCH_V) — check the GitHub connection for its host"
  local boundary
  boundary="$(resolve_boundary)"
  [ -n "$boundary" ] || { log "no tag matches stable_tag_pattern"; quiet_out; }
  [ "$boundary" = "$LAST_BOUNDARY" ] && { log "documented boundary $boundary is current"; quiet_out; }

  if [ "$RELEASE_MODEL_V" = branch ]; then
    local last_pass
    last_pass="$(tail -1 "$WORK/logs/RELEASES.log" 2>/dev/null | cut -d' ' -f1)"
    if [ -n "$last_pass" ] && [ $(( (NOW_EPOCH - $(iso2epoch "$last_pass")) / 86400 )) -lt "$PASS_DAYS" ]; then
      log "branch mode: last pass $last_pass, next after $PASS_DAYS day(s)"; quiet_out
    fi
  elif [ -n "$LAST_BOUNDARY" ]; then
    # only a NEWER stable tag is a release; a deleted or re-pointed tag is the audit's
    if [ "$(printf '%s\n%s\n' "$LAST_BOUNDARY" "$boundary" | sort -V | tail -1)" != "$boundary" ]; then
      log "newest stable tag $boundary sorts below the documented $LAST_BOUNDARY — left to the audit"; quiet_out
    fi
  fi

  local commits=0
  [ -n "$LAST_BOUNDARY" ] && commits="$(git -C "$SRC" rev-list --count "$LAST_BOUNDARY..$boundary" 2>/dev/null || echo 0)"
  log "release ${boundary} to document (previous: ${LAST_BOUNDARY:-none — baseline pass}, $commits commit(s) between)"

  READ_SET=(docs/verification.md docs/release-pass.md docs/queue.md docs/reporting.md)
  jq -n --arg mode release --arg b "$boundary" --arg p "$LAST_BOUNDARY" --argjson c "$commits" \
    --argjson open "$(open_rows | wc -l | tr -d ' ')" \
    --argjson read_set "$(printf '%s\n' "${READ_SET[@]}" | jq -R . | jq -sc .)" \
    --argjson config "$(config_json)" --argjson logs "$(logs_json)" \
    '{mode:$mode, nothing_to_do:false,
      release_due:[{id:$b, boundary:$b, previous:$p, baseline:($p == ""), commits:$c, open_queue_rows:$open}],
      read_set:$read_set, config:$config, logs:$logs}'
}

# ============================================================ AUDIT MODE ====
CHECKS='[]'
check() { CHECKS="$(printf '%s' "$CHECKS" | jq -c --arg id "$1" --arg s "$2" --arg d "$3" '. + [{id:$id, status:$s, detail:$d}]')"; }

mode_audit() {
  [ -f "$CONFIG" ] && check config ok "work/CONFIG.md present" \
                   || check config fail "work/CONFIG.md missing — re-run ONBOARDING.md"
  for k in source_repo docs_repo; do
    [ -n "$(key "$k")" ] && check "config_$k" ok "$k set" || check "config_$k" fail "$k unset"
  done

  if sync_repo "$SRC" "$SOURCE_REPO_V" "$SOURCE_BRANCH_V"; then
    check source_reachable ok "$SOURCE_REPO_V fetched"
    local b; b="$(resolve_boundary)"
    if [ -z "$b" ]; then check boundary fail "no tag matches stable_tag_pattern — fix the pattern in work/CONFIG.md"
    elif [ "$b" = "$LAST_BOUNDARY" ]; then check boundary ok "documented boundary $b is current"
    else check boundary warn "boundary ${b} not yet documented (documented: ${LAST_BOUNDARY:-none})"; fi
    [ -n "$LAST_BOUNDARY" ] && [ "$RELEASE_MODEL_V" = tags ] \
      && ! git -C "$SRC" rev-parse -q --verify "refs/tags/$LAST_BOUNDARY" >/dev/null 2>&1 \
      && check boundary_tag fail "documented boundary $LAST_BOUNDARY no longer exists as a tag"
  else
    check source_reachable fail "cannot fetch $SOURCE_REPO_V — check the GitHub connection for its host"
  fi
  git ls-remote -q "$(repo_url "$DOCS_REPO_V")" "refs/heads/$DOCS_BRANCH_V" >/dev/null 2>&1 \
    && check docs_reachable ok "$DOCS_REPO_V reachable" \
    || check docs_reachable fail "cannot reach $DOCS_REPO_V ($DOCS_BRANCH_V)"

  # ---- state invariants
  [ -d "$WORK/.git" ] && check work_not_repo fail "work/.git exists — work/ must be a plain directory" \
                      || check work_not_repo ok "work/ is a plain directory"
  local nfs; nfs="$(find "$WORK" -name '.nfs*' 2>/dev/null | wc -l | tr -d ' ')"
  [ "$nfs" -eq 0 ] && check nfs_junk ok "no .nfs files" || check nfs_junk warn "$nfs .nfs file(s) under work/"
  if head -3 "$WORK/QUEUE.md" 2>/dev/null | grep -qF '| id | status | kind | ref | page | note | evidence | updated |'; then
    check queue_shape ok "QUEUE.md header intact"
  else
    check queue_shape fail "QUEUE.md missing or its header changed — docs/queue.md → Row format"
  fi
  local stale=0 row upd
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    upd="$(printf '%s' "$row" | sed -E 's/.*\| ([0-9T:Z-]+) \|$/\1/')"
    [ $(( NOW_EPOCH - $(iso2epoch "$upd") )) -gt 86400 ] && stale=$((stale + 1))
  done <<EOF
$(open_rows correction)
EOF
  [ "$stale" -eq 0 ] && check open_corrections ok "no verified correction waiting more than a day" \
                     || check open_corrections fail "$stale verified correction(s) open for more than a day — a known error is still published"

  # ---- cadence: the sweep gate logs every weekday, declined or not
  local seen=0 f
  for f in $(ls -1 "$WORK/logs"/events-*.jsonl 2>/dev/null | tail -5); do
    grep -q '"job":"sweep"' "$f" 2>/dev/null && seen=1
  done
  [ "$seen" = 1 ] && check sweep_cadence ok "the sweep ran in the last five log days" \
                  || check sweep_cadence warn "no sweep activity in the last five log days — check the schedule"

  # ---- definition
  if git -C "$HOME_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    [ -z "$(git -C "$HOME_DIR" status --porcelain 2>/dev/null)" ] \
      && check definition_clean ok "definition checkout clean" \
      || check definition_clean warn "definition checkout has local changes"
  fi
  local v_co v_ad
  v_co="$(head -1 "$HOME_DIR/VERSION" 2>/dev/null)"; v_ad="$(head -1 "$WORK/VERSION" 2>/dev/null)"
  [ "$v_co" = "$v_ad" ] && check version ok "adopted $v_ad" \
                        || check version warn "checked out ${v_co:-?}, adopted ${v_ad:-?} — migrate in the direct session"

  # ---- scratch and retention (documented bookkeeping)
  local left; left="$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'docs-maintainer-*' -mmin +180 2>/dev/null | wc -l | tr -d ' ')"
  [ "$left" -eq 0 ] && check tmp_leftovers ok "no leftover scratch" || check tmp_leftovers warn "$left leftover /tmp/docs-maintainer-* path(s)"
  find "$WORK/logs" -name 'events-*.jsonl' -mtime +14 -delete 2>/dev/null || true

  local stats
  stats="$(jq -n --argjson open "$(open_rows | wc -l | tr -d ' ')" \
    --argjson corr "$(open_rows correction | wc -l | tr -d ' ')" \
    --argjson add "$(open_rows addition | wc -l | tr -d ' ')" \
    --argjson unrel "$(open_rows unreleased | wc -l | tr -d ' ')" \
    --argjson flag "$(open_rows flagged | wc -l | tr -d ' ')" \
    --arg boundary "$LAST_BOUNDARY" \
    '{documented_boundary:$boundary, open_rows:$open, open_corrections:$corr, open_additions:$add, open_unreleased:$unrel, open_flagged:$flag}')"
  log "audit: $(printf '%s' "$CHECKS" | jq '[.[] | select(.status=="fail")] | length') fail, $(printf '%s' "$CHECKS" | jq '[.[] | select(.status=="warn")] | length') warn"
  jq -n --argjson checks "$CHECKS" --argjson stats "$stats" \
    --argjson config "$(config_json)" --argjson logs "$(logs_json)" \
    '{mode:"audit", nothing_to_do:false, checks:$checks, stats:$stats,
      read_set:["docs/audit.md","docs/reporting.md"], config:$config, logs:$logs}'
}

case "$MODE" in
  sweep)   mode_sweep ;;
  release) mode_release ;;
  audit)   mode_audit ;;
  *) fail_out "unknown mode: $MODE" ;;
esac
