#!/usr/bin/env bash
# Tests for scripts/next-version.sh. Each case builds a throwaway git repo in a
# temp dir and asserts the tag printed on stdout and the exit code.
# Usage: scripts/next-version.test.sh
set -uo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/next-version.sh"
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT

# Keep the host's git config out of the throwaway repos.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

pass=0
fail=0
n=0
repo=""

new_repo() {
  n=$((n + 1))
  repo="$root/repo$n"
  git init -q -b main "$repo"
  git -C "$repo" config user.name test
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config commit.gpgsign false
}

# commit <subject> [body]
commit() {
  if [ -n "${2:-}" ]; then
    git -C "$repo" commit -q --allow-empty -m "$1" -m "$2"
  else
    git -C "$repo" commit -q --allow-empty -m "$1"
  fi
}

tag() { git -C "$repo" tag "$1"; }

# check <name> <expected stdout> <expected exit> [args...]
check() {
  local name=$1 want_out=$2 want_rc=$3
  shift 3
  local out rc
  out=$(cd "$repo" && bash "$script" "$@" 2>/dev/null)
  rc=$?
  if [ "$out" = "$want_out" ] && [ "$rc" = "$want_rc" ]; then
    echo "PASS: $name"
    pass=$((pass + 1))
  else
    echo "FAIL: $name (want '$want_out' rc=$want_rc, got '$out' rc=$rc)"
    fail=$((fail + 1))
  fi
}

# --- no tags yet
new_repo; commit "feat: first"
check "no tags, feat -> v0.1.0" v0.1.0 0
new_repo; commit "fix: first"
check "no tags, fix -> v0.0.1" v0.0.1 0
new_repo; commit "chore: first"
check "no tags, chore only -> nothing" "" 0

# --- plain commit types after v1.2.3
new_repo; commit "chore: init"; tag v1.2.3; commit "feat: add x"
check "feat -> minor" v1.3.0 0
new_repo; commit "chore: init"; tag v1.2.3; commit "feat(api): add x"
check "scoped feat -> minor" v1.3.0 0
new_repo; commit "chore: init"; tag v1.2.3; commit "fix: bug"
check "fix -> patch" v1.2.4 0
new_repo; commit "chore: init"; tag v1.2.3; commit "fix: bug"; commit "feat: add x"
check "feat and fix -> minor" v1.3.0 0
new_repo; commit "chore: init"; tag v1.2.3; commit "docs: a"; commit "chore: b"; commit "ci: c"; commit "plain subject"
check "docs/chore/ci/plain only -> nothing" "" 0

# --- breaking changes
new_repo; commit "chore: init"; tag v0.4.2; commit "feat!: drop api"
check "0.y.z: '!:' -> minor" v0.5.0 0
new_repo; commit "chore: init"; tag v0.4.2; commit "fix(core)!: change"
check "0.y.z: scoped fix '!:' -> minor" v0.5.0 0
new_repo; commit "chore: init"; tag v0.4.2; commit "fix: change" "BREAKING CHANGE: gone"
check "0.y.z: BREAKING CHANGE body -> minor" v0.5.0 0
new_repo; commit "chore: init"; tag v1.4.2; commit "feat!: drop api"
check ">=1.0.0: '!:' -> major" v2.0.0 0
new_repo; commit "chore: init"; tag v1.4.2; commit "fix: change" "BREAKING CHANGE: gone"
check ">=1.0.0: BREAKING CHANGE body -> major" v2.0.0 0
new_repo; commit "chore: init"; tag v1.4.2; commit "docs: change" "BREAKING CHANGE: gone"
check ">=1.0.0: BREAKING CHANGE on a docs commit -> major" v2.0.0 0

# --- merge commit carrying the PR title in its body
new_repo; commit "chore: init"; tag v1.2.3
git -C "$repo" checkout -q -b topic; commit "wip"
git -C "$repo" checkout -q main; commit "chore: other"
git -C "$repo" merge -q --no-ff topic -m "Merge pull request #7 from o/topic" -m "feat: add thing"
check "merge commit body 'feat:' -> minor" v1.3.0 0
new_repo; commit "chore: init"; tag v1.2.3
git -C "$repo" checkout -q -b topic; commit "wip"
git -C "$repo" checkout -q main; commit "chore: other"
git -C "$repo" merge -q --no-ff topic -m "Merge pull request #7 from o/topic" -m "docs: tweak"
check "merge commit body 'docs:' -> nothing" "" 0
new_repo; commit "chore: init"; tag v1.2.3
git -C "$repo" checkout -q -b topic; commit "wip"
git -C "$repo" checkout -q main; commit "chore: other"
git -C "$repo" merge -q --no-ff topic -m "Merge pull request #7 from o/topic" -m "fix!: break"
check "merge commit body 'fix!:' at 1.x -> major" v2.0.0 0

# --- forced bump
new_repo; commit "chore: init"; tag v1.2.3; commit "docs: x"
check "forced patch with new commits" v1.2.4 0 patch
check "forced minor with new commits" v1.3.0 0 minor
check "forced major with new commits" v2.0.0 0 major
new_repo; commit "chore: init"; tag v1.2.3; commit "feat: x"
check "forced patch overrides feat" v1.2.4 0 patch
new_repo; commit "chore: init"; tag v1.2.3
check "forced patch, nothing new -> refused" "" 1 patch
check "forced major, nothing new -> refused" "" 1 major
check "auto, nothing new -> nothing" "" 0
new_repo; commit "chore: init"
check "forced minor, no tags -> v0.1.0" v0.1.0 0 minor

# --- pre-release and non-vX.Y.Z tags are ignored
new_repo; commit "chore: init"; tag v0.1.0; commit "fix: a"; tag v1.0.0-rc1; commit "fix: b"
check "pre-release tag ignored" v0.1.1 0
new_repo; commit "chore: init"; tag v1.2.3; commit "fix: a"; tag v2.0.0-rc1
check "only pre-release newer than last tag" v1.2.4 0
new_repo; commit "chore: init"; tag v1.2.3; commit "feat: a"; tag v1.3.0; commit "fix: b"; tag v1.10.0; commit "fix: c"
check "version sort, not lexical" v1.10.1 0

# --- bad arguments
new_repo; commit "feat: x"
check "bad argument -> exit 2" "" 2 bogus
check "bad argument 'Patch' -> exit 2" "" 2 Patch

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
