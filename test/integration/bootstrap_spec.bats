#!/usr/bin/env bats
#
# Integration tests for bootstrap.sh.
#
# Fixture: a bare "base" remote seeded with two tags (v0.9.5, v0.9.7),
# and a repo that simulates what GitHub Template produces (files copied
# without git history — no subtree merge metadata).
# Tests drive the real bootstrap.sh against this fake remote and assert
# the resulting git state + working tree.

bats_require_minimum_version 1.5.0

setup() {
  bats_load_library "bats-support"
  bats_load_library "bats-assert"

  BOOTSTRAP="${BATS_TEST_DIRNAME}/../../bootstrap.sh"

  BASE_WORK="${BATS_TEST_TMPDIR}/base_work"
  BASE_BARE="${BATS_TEST_TMPDIR}/base.git"
  REPO_DIR="${BATS_TEST_TMPDIR}/from_template"

  _seed_base_remote
  _seed_template_repo
}

# ── Fixture helpers ─────────────────────────────────────────────────────────

_seed_base_remote() {
  mkdir -p "${BASE_WORK}/script/docker/lib"
  git -C "${BASE_WORK}" init -q -b main
  git -C "${BASE_WORK}" config user.email t@t
  git -C "${BASE_WORK}" config user.name t

  # v0.9.5
  echo "v0.9.5" > "${BASE_WORK}/.version"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${BASE_WORK}/init.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${BASE_WORK}/script/docker/setup.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${BASE_WORK}/upgrade.sh"
  chmod +x "${BASE_WORK}/init.sh" "${BASE_WORK}/script/docker/setup.sh" "${BASE_WORK}/upgrade.sh"
  git -C "${BASE_WORK}" add -A
  git -C "${BASE_WORK}" commit -q -m "v0.9.5"
  git -C "${BASE_WORK}" tag v0.9.5

  # v0.9.7
  echo "v0.9.7" > "${BASE_WORK}/.version"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${BASE_WORK}/script/docker/new_script.sh"
  chmod +x "${BASE_WORK}/script/docker/new_script.sh"
  git -C "${BASE_WORK}" add -A
  git -C "${BASE_WORK}" commit -q -m "v0.9.7"
  git -C "${BASE_WORK}" tag v0.9.7

  git init --bare -q "${BASE_BARE}"
  git -C "${BASE_WORK}" push -q "${BASE_BARE}" v0.9.5 v0.9.7 main
}

# Simulate GitHub Template: copy .base/ files into a fresh repo with
# no subtree merge history (single initial commit).
_seed_template_repo() {
  mkdir -p "${REPO_DIR}"
  git -C "${REPO_DIR}" init -q -b main
  git -C "${REPO_DIR}" config user.email t@t
  git -C "${REPO_DIR}" config user.name t

  # Copy base content as .base/ (simulating what the template ships)
  git clone -q "${BASE_BARE}" "${BATS_TEST_TMPDIR}/base_clone"
  git -C "${BATS_TEST_TMPDIR}/base_clone" checkout -q v0.9.5
  cp -a "${BATS_TEST_TMPDIR}/base_clone/." "${REPO_DIR}/.base/"
  rm -rf "${REPO_DIR}/.base/.git"

  # Place bootstrap.sh from the source under test
  cp "${BOOTSTRAP}" "${REPO_DIR}/bootstrap.sh"
  chmod +x "${REPO_DIR}/bootstrap.sh"

  # Template-specific files (should be cleaned up by bootstrap)
  echo "# Template README" > "${REPO_DIR}/README.md"
  mkdir -p "${REPO_DIR}/doc"
  echo "# Template zh-TW" > "${REPO_DIR}/doc/README.zh-TW.md"
  echo "# Template zh-CN" > "${REPO_DIR}/doc/README.zh-CN.md"
  echo "# Template ja" > "${REPO_DIR}/doc/README.ja.md"
  mkdir -p "${REPO_DIR}/.github/workflows"
  echo "name: CI" > "${REPO_DIR}/.github/workflows/ci.yaml"
  mkdir -p "${REPO_DIR}/test/integration"
  echo "# stub" > "${REPO_DIR}/test/integration/bootstrap_spec.bats"

  git -C "${REPO_DIR}" add -A
  git -C "${REPO_DIR}" commit -q -m "initial (from template)"
}

# ── Tracer bullet: bootstrap with explicit version ─────────────────────────

@test "bootstrap.sh v0.9.7: rebuilds subtree, runs init.sh, self-deletes" {
  cd "${REPO_DIR}"

  run env TEMPLATE_REMOTE="file://${BASE_BARE}" ./bootstrap.sh v0.9.7
  assert_success

  # Subtree history established: .base/.version updated to target
  [ "$(cat .base/.version)" = "v0.9.7" ]

  # New content from v0.9.7 arrived
  [ -f ".base/script/docker/new_script.sh" ]

  # init.sh was executed (stub exits 0; real init.sh would create scaffolding)
  assert_output --partial "init.sh"

  # bootstrap.sh and all template-specific files removed
  [ ! -f "bootstrap.sh" ]
  [ ! -f ".github/workflows/ci.yaml" ]
  [ ! -f "test/integration/bootstrap_spec.bats" ]
  [ ! -d "doc" ]
  [ ! -f "README.md" ]

  # Subsequent subtree pull works (proving subtree history is intact)
  run git subtree pull --prefix=.base "file://${BASE_BARE}" v0.9.7 --squash \
    -m "test: verify subtree pull works"
  assert_success
}

# ── No-arg: queries remote for latest tag ──────────────────────────────────

@test "bootstrap.sh (no arg): picks latest tag from remote" {
  cd "${REPO_DIR}"

  run env TEMPLATE_REMOTE="file://${BASE_BARE}" ./bootstrap.sh
  assert_success

  # Should have picked v0.9.7 (latest semver tag)
  [ "$(cat .base/.version)" = "v0.9.7" ]
  [ -f ".base/script/docker/new_script.sh" ]
  [ ! -f "bootstrap.sh" ]
}

# ── Error guard: no git identity ───────────────────────────────────────────

@test "bootstrap.sh fails fast when git identity is missing" {
  cd "${REPO_DIR}"

  git config --unset user.email
  git config --unset user.name

  run env TEMPLATE_REMOTE="file://${BASE_BARE}" \
    HOME="${BATS_TEST_TMPDIR}" \
    GIT_CONFIG_GLOBAL=/dev/null \
    GIT_CONFIG_SYSTEM=/dev/null \
    ./bootstrap.sh v0.9.7
  assert_failure
  assert_output --partial "git identity not configured"

  # .base/ untouched
  [ "$(cat .base/.version)" = "v0.9.5" ]
}

# ── Error guard: already bootstrapped ──────────────────────────────────────

@test "bootstrap.sh refuses to run when subtree history already exists" {
  cd "${REPO_DIR}"

  # First bootstrap succeeds
  env TEMPLATE_REMOTE="file://${BASE_BARE}" ./bootstrap.sh v0.9.7 >/dev/null

  # Re-place bootstrap.sh (it self-deleted)
  cp "${BOOTSTRAP}" bootstrap.sh
  chmod +x bootstrap.sh
  git add bootstrap.sh
  git commit -q -m "re-add bootstrap for test"

  # Second run should refuse
  run env TEMPLATE_REMOTE="file://${BASE_BARE}" ./bootstrap.sh v0.9.7
  assert_failure
  assert_output --partial "already bootstrapped"
}

# ── Post-bootstrap: subtree pull (upgrade path) works ─────────────────────

@test "after bootstrap at v0.9.5, subtree pull to v0.9.7 succeeds" {
  cd "${REPO_DIR}"

  env TEMPLATE_REMOTE="file://${BASE_BARE}" ./bootstrap.sh v0.9.5 >/dev/null
  [ "$(cat .base/.version)" = "v0.9.5" ]

  run git subtree pull --prefix=.base "file://${BASE_BARE}" v0.9.7 --squash \
    -m "chore: upgrade .base subtree to v0.9.7"
  assert_success

  [ "$(cat .base/.version)" = "v0.9.7" ]
  [ -f ".base/script/docker/new_script.sh" ]
}
