#!/usr/bin/env bash
# verify-onboarding.sh — one-shot structure verification of an onboarded docs-maintainer.
#
# Runs during ONBOARDING (`--config` right after work/CONFIG.md is written, then
# `--live` at the end) and as an upgrade step whenever a version changes what
# onboarding produces. Shape only: required files, keys, enum values, table headers.
# The data inside is never judged.
#
# Detects, never repairs. Every FAIL line carries a `fix:`; re-run until it prints PASS.
#
#   ok   <check> — <detail>
#   warn <check> — <detail>                      informational, never blocks
#   FAIL <check> — <problem> — fix: <instruction>
#
#   --config   the CONFIG block only (before schedules, work/VERSION and the sentinel exist)
#   (none)     every offline block
#   --live     offline blocks + both repositories reachable + a read-only pass per mode
#
# Exit 0 iff nothing FAILed.

set -u
export LC_ALL=C GIT_TERMINAL_PROMPT=0

LIVE=0; STRUCTURE=1
case "${1:-}" in
  (--live)   LIVE=1;;
  (--config) STRUCTURE=0;;
  ('') ;;
  (*) printf 'usage: %s [--config|--live]\n' "$0" >&2; exit 2;;
esac

HOME_DIR="${HOME:-/home/agent}"
WORK="${WORK_DIR:-$HOME_DIR/work}"
CONFIG="$WORK/CONFIG.md"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if ! . "$SCRIPT_DIR/log.sh" 2>/dev/null; then logev() { :; }; fi

CHECKS=0; FAILS=0; WARNS=0
ok()   { CHECKS=$((CHECKS+1)); printf 'ok   %s — %s\n' "$1" "$2"; }
fail() { CHECKS=$((CHECKS+1)); FAILS=$((FAILS+1)); printf 'FAIL %s — %s — fix: %s\n' "$1" "$2" "$3"; }
warn() { WARNS=$((WARNS+1)); printf 'warn %s — %s\n' "$1" "$2"; }

. "$SCRIPT_DIR/lib/config.sh" || { echo "cannot source lib/config.sh" >&2; exit 1; }

KNOWN_KEYS="source_repo source_branch docs_repo docs_branch docs_path release_model
stable_tag_pattern release_check flags_path triage_ignore triage_batch
verify_pages_per_sweep structure_changes build_command deploy_command reviewers
commit_name commit_email commit_trailer run_model report_channel report_chat
owner_member_id audit_report definition_repo log_level"

if [ "$STRUCTURE" = 1 ]; then
  # ------------------------------------------------------------- definition
  if git -C "$HOME_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    ok definition_checkout "$HOME_DIR is a git checkout"
    [ -z "$(git -C "$HOME_DIR" status --porcelain 2>/dev/null)" ] \
      && ok definition_clean "no local changes" \
      || warn definition_clean "the checkout has local changes"
  else
    fail definition_checkout "$HOME_DIR is not a git checkout" "ONBOARDING.md → Step 1"
  fi
  head -1 "$HOME_DIR/.gitignore" 2>/dev/null >/dev/null && grep -qx '/\*' "$HOME_DIR/.gitignore" \
    && ok allowlist ".gitignore is an allowlist" \
    || fail allowlist ".gitignore is not the allowlist" "restore .gitignore from origin/main"
  f="$HOME_DIR/.docs-maintainer-onboarded"
  if [ -f "$f" ] && grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$' "$f"; then
    ok sentinel "onboarded $(cat "$f")"
  else
    fail sentinel "missing or malformed sentinel" "ONBOARDING.md → Step 6"
  fi

  # ------------------------------------------------------------------ work/
  [ -d "$WORK" ] && ok work_dir "work/ present" || fail work_dir "work/ missing" "ONBOARDING.md → Step 2"
  [ -d "$WORK/.git" ] && fail work_not_repo "work/.git exists" "move it away; work/ is never a git repo" \
                      || ok work_not_repo "work/ is a plain directory"
  for s in AGENTS.md QUEUE-counter TRIAGED.log UNITS.log VERIFIED.log STYLE.md MEMORY.md logs/RELEASES.log logs/AUDIT.log; do
    [ -e "$WORK/$s" ] && ok "seed_$s" "present" || fail "seed_$s" "work/$s missing" "ONBOARDING.md → Step 2b"
  done
  if grep -qxF '| id | status | kind | ref | page | note | evidence | updated |' "$WORK/QUEUE.md" 2>/dev/null; then
    ok queue_header "QUEUE.md header intact"
    bad="$(grep -E '^\| Q' "$WORK/QUEUE.md" | grep -cvE '^\| Q[0-9]{4,} \| (open|worked|obsolete|carried) \| (unreleased|correction|addition|flagged|external|upstream) \|' || true)"
    [ "${bad:-0}" -eq 0 ] && ok queue_rows "every row has a known status and kind" \
      || fail queue_rows "$bad row(s) with an unknown status or kind" "docs/queue.md → Row format"
  else
    fail queue_header "QUEUE.md missing or its header changed" "ONBOARDING.md → Step 2b"
  fi
  grep -qE '^[0-9]+$' "$WORK/QUEUE-counter" 2>/dev/null \
    && ok queue_counter "counter $(cat "$WORK/QUEUE-counter")" \
    || fail queue_counter "QUEUE-counter is not a number" "write the highest Q id's number into it"
  [ "$(head -1 "$WORK/VERSION" 2>/dev/null)" = "$(head -1 "$HOME_DIR/VERSION" 2>/dev/null)" ] \
    && ok version "work/VERSION matches the checkout" \
    || fail version "work/VERSION differs from VERSION" "ONBOARDING.md → Step 6, or migrate (docs/persistence.md)"
fi

# ------------------------------------------------------------------- CONFIG
if [ ! -f "$CONFIG" ]; then
  fail config "work/CONFIG.md missing" "ONBOARDING.md → Step 3"
else
  for k in source_repo docs_repo source_branch docs_branch docs_path; do
    [ -n "$(cfg "$k")" ] && ok "config_$k" "$(cfg "$k")" || fail "config_$k" "$k empty" "ONBOARDING.md → Step 3"
  done
  for k in source_repo docs_repo; do
    printf '%s' "$(cfg "$k")" | grep -qE '^([A-Za-z0-9.-]+/)?[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' \
      || fail "format_$k" "$k is not [<host>/]<owner>/<repo>" "write it as acme/widgets or ghe.example.com/acme/widgets"
  done
  enum() { local v; v="$(cfg "$1")"; [ -z "$v" ] && return 0
           printf '%s' " $2 " | grep -qF " $v " && ok "enum_$1" "$v" \
             || fail "enum_$1" "$1 is '$v'" "one of: $2"; }
  enum release_model "tags main"
  enum structure_changes "ask allow"
  enum report_channel "slack telegram"
  enum audit_report "enabled disabled"
  enum log_level "info debug"
  for k in triage_batch verify_pages_per_sweep; do
    v="$(cfg "$k")"; [ -z "$v" ] || printf '%s' "$v" | grep -qE '^[0-9]+$' \
      || fail "number_$k" "$k is '$v'" "a whole number"
  done
  re="$(cfg stable_tag_pattern)"
  if [ -n "$re" ]; then
    printf 'x\n' | grep -E -- "$re" >/dev/null 2>&1; [ $? -le 1 ] \
      && ok stable_tag_pattern "valid regex" \
      || fail stable_tag_pattern "not a valid extended regex" "docs/config.md"
    printf 'v1.2.3-rc1\n1.2.3-beta.1\n' | grep -qE -- "$re" \
      && fail stable_tag_pattern "matches a pre-release tag (v1.2.3-rc1 / 1.2.3-beta.1)" "anchor it, e.g. ^v?[0-9]+\\.[0-9]+\\.[0-9]+\$"
  fi
  if [ -n "$(cfg report_channel)" ]; then
    [ -n "$(cfg report_chat)" ] && ok report_chat "set" \
      || fail report_chat "report_channel set but report_chat empty" "set it from the bound channel (ONBOARDING.md → Step 3), or clear report_channel"
  fi
  # every bullet must be a known key — a typo is invisible to the runtime
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    printf '%s\n' $KNOWN_KEYS | grep -qxF "$k" \
      || fail "unknown_key" "'$k' is not a configuration key" "rename or remove it (docs/config.md)"
  done <<EOF
$(sed -nE 's/^- ([a-z_]+):.*/\1/p' "$CONFIG")
EOF
fi

# --------------------------------------------------------------------- live
if [ "$LIVE" = 1 ]; then
  for k in source_repo docs_repo; do
    r="$(cfg "$k")"; [ -n "$r" ] || continue
    host=github.com; path="$r"; case "$r" in (*/*/*) host="${r%%/*}"; path="${r#*/}";; esac
    if git ls-remote -q "https://$host/$path.git" HEAD >/dev/null 2>&1; then
      ok "reach_$k" "$r readable"
    else
      fail "reach_$k" "cannot read $r" "grant a GitHub connection for $host that can see it"
    fi
  done
  d="$(cfg docs_repo)"; dh=github.com; dp="$d"; case "$d" in (*/*/*) dh="${d%%/*}"; dp="${d#*/}";; esac
  if command -v gh >/dev/null 2>&1 && [ -n "$d" ]; then
    perm="$(gh api --hostname "$dh" "repos/$dp" --jq '.permissions.push' 2>/dev/null)"
    case "$perm" in
      (true)  ok docs_write "can push branches to $d";;
      (false) fail docs_write "no write access to $d" "give the connection's account write (or fork-and-PR) access";;
      (*)     warn docs_write "could not read permissions on $d";;
    esac
  else
    warn docs_write "gh unavailable — write access unchecked"
  fi
  for m in sweep release audit; do
    out="$(bash "$SCRIPT_DIR/preflight.sh" "$m" 2>/dev/null)"
    if printf '%s' "$out" | jq -e 'type=="object" and has("nothing_to_do")' >/dev/null 2>&1; then
      e="$(printf '%s' "$out" | jq -r '.error // empty')"
      [ -z "$e" ] && ok "preflight_$m" "valid worklist" || fail "preflight_$m" "$e" "fix the cause it names, then re-run"
    else
      fail "preflight_$m" "no JSON worklist" "run scripts/preflight.sh $m and read its stderr"
    fi
  done
  for m in sweep release; do
    t0=$(date +%s); bash "$SCRIPT_DIR/precheck.sh" "$m" >/dev/null 2>&1; rc=$?; dt=$(( $(date +%s) - t0 ))
    case "$rc" in
      (0|1) [ "$dt" -lt 90 ] && ok "precheck_$m" "exit $rc in ${dt}s" \
              || warn "precheck_$m" "exit $rc but took ${dt}s — near the two-minute limit";;
      (*)   fail "precheck_$m" "exit $rc — the gate is broken and fails open" "run scripts/precheck.sh $m and read its output";;
    esac
  done
fi

# ------------------------------------------------------------------- summary
if [ "$LIVE" = 1 ]; then SCOPE="structure+live"
elif [ "$STRUCTURE" = 1 ]; then SCOPE="structure"
else SCOPE="config"; fi
if [ "$FAILS" -eq 0 ]; then
  printf 'PASS (%s) — %d checks passed, %d warning(s)\n' "$SCOPE" "$CHECKS" "$WARNS"
  logev info onboarding_verify "PASS $SCOPE ($CHECKS checks, $WARNS warnings)"
  exit 0
else
  printf 'RESULT (%s): %d of %d checks FAILED — apply each fix above, then re-run this script until it prints PASS.\n' "$SCOPE" "$FAILS" "$CHECKS"
  logev error onboarding_verify "FAILED $SCOPE ($FAILS of $CHECKS checks)"
  exit 1
fi
