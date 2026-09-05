#!/usr/bin/env bats
#
# Live guard: bootstrap.sh against the REAL base remote, not a model of it.
#
# bootstrap_spec.bats seeds a synthetic bare remote with invented tags
# (v0.9.5 / v0.9.7 / v0.10.0) spanning the two layouts base has shipped.
# That proves bootstrap.sh is correct against a MODEL of base. The model
# and base agree only until base moves something the model does not know
# about -- and on that day the synthetic fixture stays green while a real
# `gh repo create --template` produces a broken repo.
#
# This is not hypothetical. base v0.42.0 relocated init.sh under dist/ and
# broke every v0.41.0 consumer's upgrade. bootstrap.sh survived because its
# author had already added the dist/ candidate ahead of the move.
# Anticipation is not a control. This is the control.
#
# The fixture is this repo's own tracked tree, because that is literally
# what GitHub Template copies. Synthesising a stand-in here would
# reintroduce the modelling gap the file exists to close.
#
# Needs network. Skipped unless BOOTSTRAP_LIVE_BASE=1, so the hermetic
# suite stays runnable offline and a network failure is never mistaken for
# a bootstrap defect.

bats_require_minimum_version 1.5.0

BASE_REMOTE="https://github.com/ycpss91255-docker/base.git"

setup() {
  if [[ "${BOOTSTRAP_LIVE_BASE:-}" != "1" ]]; then
    skip "live base guard: set BOOTSTRAP_LIVE_BASE=1 to run"
  fi
  bats_load_library "bats-support"
  bats_load_library "bats-assert"

  REPO_DIR="${BATS_TEST_TMPDIR}/from_template"
  _seed_from_this_repo
}

# _seed_from_this_repo
#   Reproduce what GitHub Template hands someone: this repo's tracked files,
#   with no git history behind them. `git archive HEAD` is the closest thing
#   to that operation -- it takes exactly the tracked tree and nothing else,
#   so an uncommitted local edit cannot make the guard pass or fail.
_seed_from_this_repo() {
  local _root
  _root="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  mkdir -p "${REPO_DIR}"
  git -C "${_root}" archive HEAD | tar -x -C "${REPO_DIR}"

  git -C "${REPO_DIR}" init -q -b main
  git -C "${REPO_DIR}" config user.email t@t
  git -C "${REPO_DIR}" config user.name t
  # -f, because re-initialising git would otherwise lose tracked-ness that
  # a real generated repo keeps. This repo TRACKS `.base/compose.yaml`
  # while its own .gitignore matches `compose.yaml` at any depth; ignore
  # rules never applied to it, because it was already tracked. A plain
  # `add -A` re-applies them, leaves the file untracked, and bootstrap
  # then correctly refuses to run -- a refusal the real flow never sees.
  git -C "${REPO_DIR}" add -A -f
  git -C "${REPO_DIR}" commit -q -m "initial commit from template"
}

# _newest_stable_tag
#   base's newest stable tag, read from the remote. Shares bootstrap.sh's
#   resolution method on purpose: the question here is "did bootstrap
#   install the newest", not "is our idea of newest right". A disagreement
#   about what `newest` means is a different test and would need a second
#   source of truth (the GitHub release API) plus a token to read it.
_newest_stable_tag() {
  git ls-remote --tags --sort=-v:refname "${BASE_REMOTE}" 'v*' \
    | awk '{ sub(/\^\{\}$/, "", $2); sub(/^refs\/tags\//, "", $2);
             if ($2 != "" && $2 !~ /-/) { print $2; exit } }'
}

# _dangling_symlinks
#   Every symlink whose target does not resolve. `-e` follows the link, so
#   a dangling one reads as absent; test the link itself too or the check
#   silently passes on exactly the shape it is looking for.
_dangling_symlinks() {
  local _l
  while IFS= read -r _l; do
    [[ -n "${_l}" ]] || continue
    [[ -e "${_l}" ]] || printf '%s\n' "${_l}"
  done < <(find "${REPO_DIR}" -path "${REPO_DIR}/.git" -prune -o -type l -print)
}

# why: The whole point -- a repo created from this template against base as
# it is today, not as the hermetic fixture models it, must come out usable.
@test "bootstrap.sh against the live base produces a usable repo" {
  run env -C "${REPO_DIR}" ./bootstrap.sh
  assert_success

  assert [ -f "${REPO_DIR}/.base/.version" ]
  assert [ ! -e "${REPO_DIR}/bootstrap.sh" ]

  run _dangling_symlinks
  assert_output ""

  # init.sh ran and wired the entry point, rather than bootstrap merely
  # having placed a subtree. The justfile is a symlink into the subtree, so
  # its resolving is the difference between a wired repo and a bricked one.
  assert [ -e "${REPO_DIR}/justfile" ]
}

# why: An installed prerelease would reach every repo created that day;
# bootstrap filters them and this proves the filter still holds against
# real tag data rather than the fixture's three invented tags.
@test "the installed version is base's newest stable, not a prerelease" {
  run env -C "${REPO_DIR}" ./bootstrap.sh
  assert_success

  local _installed _newest
  _installed="$(tr -d '[:space:]' < "${REPO_DIR}/.base/.version")"
  _newest="$(_newest_stable_tag)"

  assert [ -n "${_newest}" ]
  assert_equal "${_installed}" "${_newest}"
  refute_output --partial "-rc"
}

# why: The subtree must arrive as subtree history, not a copied directory --
# a copy leaves `just upgrade` with nothing to pull from and is the exact
# state bootstrap exists to convert away from.
@test "the installed .base carries subtree history" {
  run env -C "${REPO_DIR}" ./bootstrap.sh
  assert_success

  run git -C "${REPO_DIR}" log --oneline -- .base
  assert_success
  refute_output ""
}
