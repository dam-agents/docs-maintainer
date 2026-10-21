#!/usr/bin/env bash
# test_preflight.sh — offline tests for preflight.sh and precheck.sh against throwaway
# local git repositories (file:// via DM_URL_BASE). No network, no credentials.
set -u
export LC_ALL=C GIT_TERMINAL_PROMPT=0 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

DIR="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home" WORK_DIR="$T/home/work" DM_CLONE_ROOT="$T/cache" TMPDIR="$T/tmp" \
       DM_URL_BASE="file://$T/remote" LOG_RUN_ID=test
mkdir -p "$WORK_DIR/logs" "$TMPDIR" "$T/remote/acme"

fails=0
expect() { # <name> <jq-expr> <json>
  if printf '%s' "$3" | jq -e "$2" >/dev/null 2>&1; then echo "  ok   $1"
  else echo "  FAIL $1 — $2"; printf '%s\n' "$3" | head -c 600; echo; fails=$((fails + 1)); fi
}
pf() { bash "$DIR/preflight.sh" "$1" 2>/dev/null; }

g() { git -C "$T/src" -c user.name=t -c user.email=t@t "$@" >/dev/null 2>&1; }
git init -q -b main "$T/src"
for i in 1 2 3; do echo "$i" > "$T/src/f$i"; g add .; g commit -m "feat: change $i"; done
g tag v1.0.0
echo rc > "$T/src/rc"; g add .; g commit -m "feat: on the rc"; g tag v1.1.0-rc1
echo ci > "$T/src/ci"; g add .; g commit -m "ci: pipeline"
git clone -q --bare "$T/src" "$T/remote/acme/widgets.git"
git clone -q --bare "$T/src" "$T/remote/acme/widgets-docs.git"

cat > "$WORK_DIR/CONFIG.md" <<'EOF'
- source_repo: acme/widgets
- source_branch: main
- docs_repo: acme/widgets-docs
- docs_branch: main
- release_model: tags
- triage_ignore: ^ci:
EOF
cat > "$WORK_DIR/QUEUE.md" <<'EOF'
| id | status | kind | ref | page | note | evidence | updated |
| --- | --- | --- | --- | --- | --- | --- | --- |
EOF
: > "$WORK_DIR/TRIAGED.log"

echo "release: no documented boundary -> baseline pass, rc ignored"
out="$(pf release)"
expect "release due" '.nothing_to_do == false' "$out"
expect "boundary is the stable tag, not the rc" '.release_due[0].boundary == "v1.0.0"' "$out"
expect "baseline flagged" '.release_due[0].baseline == true' "$out"

echo "release: boundary current -> quiet"
echo v1.0.0 > "$WORK_DIR/BOUNDARY"
expect "quiet" '.nothing_to_do == true and (has("error") | not)' "$(pf release)"

echo "sweep: one untriaged commit past the merge-base, ci commit ignored"
out="$(pf sweep)"
expect "work due" '.nothing_to_do == false' "$out"
expect "exactly the rc commit" '(.triage_due | length) == 1 and .triage_due[0].subject == "feat: on the rc"' "$out"
grep -q ' none triage_ignore' "$WORK_DIR/TRIAGED.log" || { echo "  FAIL ci commit not in TRIAGED.log"; fails=$((fails+1)); }
expect "config carried" '.config.source_repo == "acme/widgets"' "$out"

echo "sweep: everything triaged -> quiet"
sha="$(printf '%s' "$out" | jq -r '.triage_due[0].sha')"
printf '%s 2026-01-01T00:00:00Z none test\n' "$sha" >> "$WORK_DIR/TRIAGED.log"
expect "quiet" '.nothing_to_do == true' "$(pf sweep)"

echo "sweep: an open correction is always due"
printf '| Q0001 | open | correction | v1.0.0 | guides/a.md | wrong flag | src/x @ v1.0.0 | 2026-01-01T00:00:00Z |\n' >> "$WORK_DIR/QUEUE.md"
out="$(pf sweep)"
expect "fix due" '.fixes_due[0].id == "Q0001" and .fixes_due[0].page == "guides/a.md"' "$out"
expect "reads fix.md" '.read_set | index("docs/fix.md") != null' "$out"
sed -i 's/| Q0001 | open |/| Q0001 | worked |/' "$WORK_DIR/QUEUE.md"

echo "release: a new stable tag -> due, with commit count"
g tag v1.1.0; git -C "$T/remote/acme/widgets.git" fetch -q "$T/src" '+refs/tags/*:refs/tags/*'
out="$(pf release)"
expect "v1.1.0 due" '.release_due[0].boundary == "v1.1.0" and .release_due[0].previous == "v1.0.0"' "$out"
expect "commit count (rc + ci commits)" '.release_due[0].commits == 2' "$out"

echo "release: a pass in progress -> quiet"
date -u +%Y-%m-%dT%H:%M:%SZ > "$WORK_DIR/.release-in-progress"
expect "quiet" '.nothing_to_do == true' "$(pf release)"
rm -f "$WORK_DIR/.release-in-progress"

echo "errors: unreachable source -> error, never a quiet answer"
out="$(DM_URL_BASE="file://$T/nowhere" DM_CLONE_ROOT="$T/cache2" bash "$DIR/preflight.sh" sweep 2>/dev/null)"
expect "error set" '.error != null' "$out"
expect "unknown mode" '.error | test("unknown mode")' "$(pf bogus)"

echo "precheck: exit codes"
echo v1.1.0 > "$WORK_DIR/BOUNDARY"
printf '%s 2026-01-01T00:00:00Z none test\n' "$(git -C "$T/src" rev-parse --short=12 HEAD)" >> "$WORK_DIR/TRIAGED.log"
bash "$DIR/precheck.sh" release >"$T/o" 2>/dev/null; rc=$?
[ "$rc" -eq 1 ] && [ ! -s "$T/o" ] && echo "  ok   quiet release -> exit 1, no output" || { echo "  FAIL quiet release rc=$rc"; cat "$T/o"; fails=$((fails+1)); }
g tag v1.2.0; git -C "$T/remote/acme/widgets.git" fetch -q "$T/src" '+refs/tags/*:refs/tags/*'
bash "$DIR/precheck.sh" release >"$T/o" 2>/dev/null; rc=$?
wl="$(sed -n 's/^worklist: //p' "$T/o")"
[ "$rc" -eq 0 ] && [ -r "$wl" ] && jq -e '.release_due[0].boundary == "v1.2.0"' "$wl" >/dev/null \
  && echo "  ok   new release -> exit 0 with a readable worklist" || { echo "  FAIL new release rc=$rc"; cat "$T/o"; fails=$((fails+1)); }
DM_URL_BASE="file://$T/nowhere" DM_CLONE_ROOT="$T/cache3" bash "$DIR/precheck.sh" sweep >"$T/o" 2>/dev/null; rc=$?
[ "$rc" -eq 2 ] && echo "  ok   broken source -> exit 2 (fails open)" || { echo "  FAIL broken source rc=$rc"; fails=$((fails+1)); }

echo "audit: shape"
out="$(pf audit)"
expect "checks present" '(.checks | length) > 5 and .nothing_to_do == false' "$out"
expect "queue shape ok" '[.checks[] | select(.id=="queue_shape")][0].status == "ok"' "$out"

echo "main mode: the docs follow the branch head"
sed -i 's/^- release_model: tags$/- release_model: main/' "$WORK_DIR/CONFIG.md"
rm -f "$WORK_DIR/BOUNDARY"
out="$(pf release)"
expect "baseline due at the head commit" '.release_due[0].baseline == true and (.release_due[0].boundary | test("^[0-9a-f]{40}$"))' "$out"
expect "sweep waits for the baseline" '.nothing_to_do == true' "$(pf sweep)"
HEAD1="$(git -C "$T/src" rev-parse HEAD)"; echo "$HEAD1" > "$WORK_DIR/BOUNDARY"
expect "release watch quiet once baselined" '.nothing_to_do == true' "$(pf release)"
expect "sweep quiet at the head" '.nothing_to_do == true' "$(pf sweep)"
push() { git -C "$T/remote/acme/widgets.git" fetch -q "$T/src" '+refs/heads/*:refs/heads/*'; }
echo docs > "$T/src/g1"; g add .; g commit -m "feat: new flag --region"; push
out="$(pf sweep)"
expect "new commit triaged today" '(.triage_due | length) == 1 and .triage_due[0].subject == "feat: new flag --region"' "$out"
HEAD2="$(git -C "$T/src" rev-parse HEAD)"
expect "update pinned to the new head" ".update_due[0].pin == \"$HEAD2\" and .update_due[0].previous == \"$HEAD1\"" "$out"
expect "reads update.md" '.read_set | index("docs/update.md") != null' "$out"
printf '%s 2026-01-01T00:00:00Z none test\n' "${HEAD2:0:12}" >> "$WORK_DIR/TRIAGED.log"
echo ci2 > "$T/src/ci2"; g add .; g commit -m "ci: more pipeline"; push
HEAD3="$(git -C "$T/src" rev-parse HEAD)"
expect "only no-impact commits -> quiet" '.nothing_to_do == true' "$(pf sweep)"
[ "$(cat "$WORK_DIR/BOUNDARY")" = "$HEAD3" ] && echo "  ok   pin advanced by the pre-flight" \
  || { echo "  FAIL pin not advanced ($(cat "$WORK_DIR/BOUNDARY"))"; fails=$((fails+1)); }
echo 0000000000000000000000000000000000000000 > "$WORK_DIR/BOUNDARY"
expect "pin off the branch -> error, never quiet" '.error | test("not on")' "$(pf sweep)"

[ "$fails" -eq 0 ]
