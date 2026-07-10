#!/usr/bin/env bash
# conventional-commit-first-m.test.sh — bug fix (folded into PR-A). Proves enforce-conventional-commit.sh
# validates the FIRST -m (the SUBJECT), not the LAST. The old greedy sed `.*(-m…)` grabbed the LAST -m,
# so a valid `fix: subj` first -m followed by a non-conventional `-m "body"` was FALSE-DENIED (the real
# footgun the developer hit committing this very wave). Runs the REAL .sh (activation guard satisfied via
# a temp autoloop project marker + CLAUDE_PROJECT_DIR).
# Toolchain: bash + node + grep + sed. Run: bash hooks/tests/conventional-commit-first-m.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOKS_SRC="$(cd "$HERE/.." && pwd)"
HOOK="$HOOKS_SRC/enforce-conventional-commit.sh"

PASS=0; FAIL=0
ok()  { printf '  [PASS] %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
assert_empty()    { if [ -z "$2" ]; then ok "$1"; else bad "$1 — expected ALLOW (empty) | got: $2"; fi; }
assert_contains() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 — expected to contain: $3 | got: $2" ;; esac; }

# temp autoloop project so aal_is_autoloop_project passes (marker = .claude/BACKLOG.md)
PROJ=$(mktemp -d); mkdir -p "$PROJ/.claude"; printf '# BACKLOG (fixture)\n' > "$PROJ/.claude/BACKLOG.md"
cleanup() { rm -rf "$PROJ"; }
trap cleanup EXIT

# run_commit <git-command-string> -> hook stdout (deny JSON or empty=allow). Payload built via node so
# the command's own quotes never fight the fixture's shell quoting.
run_commit() {
  local cmd="$1" payload
  payload=$(C="$cmd" node -e 'process.stdout.write(JSON.stringify({tool_name:"Bash",tool_input:{command:process.env.C}}))')
  printf '%s' "$payload" | env AAL_GATES="commit-hygiene:" CLAUDE_PROJECT_DIR="$PROJ" bash "$HOOK" 2>/dev/null
}

echo "== conventional-commit FIRST -m (subject) =="

# RED: valid conventional SUBJECT in the first -m, then non-conventional bodies. Post-fix → ALLOW.
# Pre-fix (greedy → last -m) → DENY on the body. Asserting ALLOW here FAILS if the greedy bug is present.
OUT=$(run_commit 'git commit -m "fix(hooks): anchor cardPR to delivery arrow" -m "B1: body mentioning PR #500 and more" -m "trailing body line"')
assert_empty "RED multi--m valid subject + non-conv bodies → ALLOW (first -m validated)" "$OUT"

# GREEN-deny: the FIRST -m is genuinely non-conventional → DENY (fix does not weaken enforcement).
OUT=$(run_commit 'git commit -m "just some words" -m "fix: a later conventional-looking body"')
assert_contains "GREEN-deny non-conv FIRST -m → DENY (even if a later -m looks conventional)" "$OUT" "conventional format"

# GREEN-single-ok: a single conventional -m → ALLOW.
OUT=$(run_commit 'git commit -m "feat(scope): add a thing"')
assert_empty "GREEN-single conventional → ALLOW" "$OUT"

# GREEN-single-bad: a single non-conventional -m → DENY (single-message enforcement intact).
OUT=$(run_commit 'git commit -m "wip stuff"')
assert_contains "GREEN-single non-conventional → DENY" "$OUT" "conventional format"

# GREEN-glued: glued -am flag, conventional → ALLOW.
OUT=$(run_commit 'git commit -am "chore(ci): bump"')
assert_empty "GREEN-glued -am conventional → ALLOW" "$OUT"

# GREEN-nonmsg: a -F file commit (no -m) → the extractor finds nothing → hook skips → ALLOW.
OUT=$(run_commit 'git commit -F /some/msg.txt')
assert_empty "GREEN -F (no -m) → ALLOW (unparseable message, hook defers to git)" "$OUT"

echo ""; echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
