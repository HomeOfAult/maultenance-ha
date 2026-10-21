#!/usr/bin/env bash
# Usage: next-version.sh [patch|minor|major]
#
# Prints the next release tag (vX.Y.Z), derived from Conventional Commits since
# the last vX.Y.Z tag, or prints nothing when none of them is releasable.
#
# With a bump argument, that bump is used instead, whatever the commits say: for
# cutting a release by hand when nothing releasable has landed. It refuses (exit
# 1) when there is nothing new since the last tag, so the same commit is not
# released twice. Exit 2 means a bad argument.
#
#   feat:            -> minor
#   fix:             -> patch
#   "!:" in subject, or a BREAKING CHANGE in a body
#                    -> major once past 0.y.z; minor while still in 0.y.z
#   anything else (docs:, chore:, ci:, plain subjects) releases nothing
#
# Each commit subject is read, plus the PR title on the first body line of a
# merge commit (see below).
#
# With no vX.Y.Z tag yet, every commit is considered and the base is v0.0.0.
# Pre-release tags (v1.0.0-rc1) are ignored.
# Run from inside the repository, with tags fetched.
set -euo pipefail

forced="${1:-}"
case "$forced" in
  ''|patch|minor|major) ;;
  *) echo "usage: next-version.sh [patch|minor|major]" >&2; exit 2 ;;
esac

# Only strict vX.Y.Z tags count: a pre-release such as v1.0.0-rc1 would also
# match a glob and then break the arithmetic below, so it is ignored instead.
last_tag=$(git tag --list 'v[0-9]*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n1 || true)
if [ -z "$last_tag" ]; then
  last_tag="v0.0.0"
  range="HEAD"
else
  range="${last_tag}..HEAD"
fi

has_feat=false
has_fix=false
has_breaking=false

classify() {
  case "$1" in
    *'!:'*) has_breaking=true ;;
  esac
  case "$1" in
    feat:*|feat\(*\):*) has_feat=true ;;
    fix:*|fix\(*\):*) has_fix=true ;;
  esac
}

while IFS= read -r subject; do
  [ -z "$subject" ] && continue
  classify "$subject"
done < <(git log "$range" --pretty=tformat:'%s')

# A "Merge pull request" commit has the subject "Merge pull request #N from ...";
# GitHub puts the PR title on the first line of its body. Read that line too, so
# a PR titled "feat: ..." releases when it is merged with a merge commit. (A
# squash merge already carries the PR title in its subject.)
while IFS= read -r merge; do
  merge_body=$(git log -1 --format=%b "$merge")
  title=$(sed -n '/./{p;q}' <<<"$merge_body")
  if [ -n "$title" ]; then
    classify "$title"
  fi
done < <(git rev-list --merges "$range")

# Read the bodies into a variable first: `git log | grep -q` can die of
# SIGPIPE under pipefail once grep exits early, turning a match into a miss.
bodies=$(git log "$range" --pretty=format:'%b')
if grep -q 'BREAKING CHANGE' <<<"$bodies"; then
  has_breaking=true
fi

IFS=. read -r major minor patch <<<"${last_tag#v}"

bump=""
if [ "$has_breaking" = true ] && [ "$major" != "0" ]; then
  bump="major"
elif [ "$has_breaking" = true ] || [ "$has_feat" = true ]; then
  bump="minor"
elif [ "$has_fix" = true ]; then
  bump="patch"
fi

if [ -n "$forced" ]; then
  if [ "$(git rev-list --count "$range")" = "0" ]; then
    echo "Nothing new since ${last_tag}; not releasing the same commit again." >&2
    exit 1
  fi
  bump="$forced"
fi

if [ -z "$bump" ]; then
  echo "No releasable commits since ${last_tag}." >&2
  exit 0
fi

case "$bump" in
  major) major=$((major + 1)); minor=0; patch=0 ;;
  minor) minor=$((minor + 1)); patch=0 ;;
  patch) patch=$((patch + 1)) ;;
esac

echo "Releasing a ${bump} bump from ${last_tag}." >&2
echo "v${major}.${minor}.${patch}"
