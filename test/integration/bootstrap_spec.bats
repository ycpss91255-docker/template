#!/usr/bin/env bats
#
# Integration tests for bootstrap.sh.
#
# Fixture: a bare "base" remote seeded with tags that span both base
# layouts, and a repo that simulates what GitHub Template produces (files
# copied without git history — no subtree merge metadata).
# Tests drive the real bootstrap.sh against this fake remote and assert
# the resulting git state + working tree.
#
# The `init.sh` stubs each write a marker file into the repo root, so the
# assertions prove which script actually ran rather than that bootstrap.sh
# merely mentions one (asserting on the text is how base#916 stayed
# invisible).

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

# Write an init.sh stub that records, in the repo it is run from, which
# layout it was resolved from, and re-creates the root symlinks into the
# subtree the way the real init.sh does. The symlinks are not decoration:
# "every symlink resolves" is the property that separates a working repo
# from the bricked one issue #10 reported, and nothing asserted it while
# the stub only wrote a marker file.
_write_init_stub() {
  local _rel="$1" _layout="$2" _justfile="$3"
  mkdir -p "${BASE_WORK}/$(dirname -- "${_rel}")"
  cat > "${BASE_WORK}/${_rel}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
echo "${_layout}" > init-ran.txt
ln -sfn ".base/${_justfile}" justfile
ln -sfn ".base/.hadolint.yaml" .hadolint.yaml
EOF
  chmod +x "${BASE_WORK}/${_rel}"
}

# Write an init.sh stub that creates files and THEN fails, the way a real
# init.sh does when it dies partway through seeding a repo. Used by the
# rollback spec: by the time this exits non-zero, bootstrap.sh has already
# committed step 2 and landed the subtree, so recovery means undoing a
# commit AND sweeping what this left behind.
_write_failing_init_stub() {
  local _rel="$1"
  mkdir -p "${BASE_WORK}/$(dirname -- "${_rel}")"
  cat > "${BASE_WORK}/${_rel}" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
ln -sfn ".base/script/docker/justfile" justfile
echo partial > partial-init-output.txt
echo GENERATED=1 > .env
echo "init.sh: deliberate failure" >&2
exit 1
EOF
  chmod +x "${BASE_WORK}/${_rel}"
}

# A justfile the root symlink can point at, so `just --list` is a real
# check (symlink resolves + the target parses) rather than a tautology.
_write_stub_justfile() {
  local _rel="$1"
  mkdir -p "${BASE_WORK}/$(dirname -- "${_rel}")"
  cat > "${BASE_WORK}/${_rel}" <<'EOF'
# Stub container-ops entry point (mirrors .base/script/docker/justfile).
default:
    @echo ok
EOF
}

# Every symlink under the repo that does not resolve, one per line.
# `.git` is pruned: git's own internals are not the repo's surface.
_dangling_symlinks() {
  find . -path ./.git -prune -o -type l ! -exec test -e {} \; -print
}

# Tags are annotated, as base's release-tag.sh cuts them: `git ls-remote`
# then lists an extra peeled `<tag>^{}` row per tag, which version-sort
# ranks above the tag itself.
_tag_base_remote() {
  local _tag="$1"
  echo "${_tag}" > "${BASE_WORK}/.version"
  git -C "${BASE_WORK}" add -A
  git -C "${BASE_WORK}" commit -q -m "${_tag}"
  git -C "${BASE_WORK}" tag -a "${_tag}" -m "${_tag}"
}

# Tag timeline, oldest first. It deliberately spans both base layouts,
# because "works against the newest tag" is the assumption base#916 broke:
#
#   v0.9.0  malformed   no init.sh anywhere
#   v0.9.1  pre-dist    an init.sh that creates files and then FAILS
#   v0.9.5  pre-dist    init.sh at the subtree root
#   v0.9.7  pre-dist    + a new file (used by the subtree-pull tests)
#   v0.9.9  both        root init.sh AND dist/script/base/init.sh
#   v0.10.0 dist-only   dist/script/base/init.sh (mirrors base v0.42.0)
#   v0.10.1-rc1         a pre-release, which is not a bootstrap target
#
# v0.10.0 is the highest released tag, so the no-argument run resolves to
# it -- past the pre-release and past the peeled `^{}` rows.
_seed_base_remote() {
  mkdir -p "${BASE_WORK}/script/docker/lib"
  git -C "${BASE_WORK}" init -q -b main
  git -C "${BASE_WORK}" config user.email t@t
  git -C "${BASE_WORK}" config user.name t

  # v0.9.0 — a tag carrying neither layout.
  printf '#!/usr/bin/env bash\nexit 0\n' > "${BASE_WORK}/upgrade.sh"
  chmod +x "${BASE_WORK}/upgrade.sh"
  _tag_base_remote v0.9.0

  # v0.9.1 — an init.sh that dies after creating files. v0.9.5 below
  # replaces it with the working stub, so only a run that names this tag
  # explicitly sees the failure.
  _write_failing_init_stub "init.sh"
  _tag_base_remote v0.9.1

  # v0.9.5 — pre-dist layout.
  _write_init_stub "init.sh" "root" "script/docker/justfile"
  _write_stub_justfile "script/docker/justfile"
  printf 'ignored:\n  - DL3008\n' > "${BASE_WORK}/.hadolint.yaml"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${BASE_WORK}/script/docker/setup.sh"
  chmod +x "${BASE_WORK}/script/docker/setup.sh"
  _tag_base_remote v0.9.5

  # v0.9.7 — pre-dist layout with an extra file.
  printf '#!/usr/bin/env bash\nexit 0\n' > "${BASE_WORK}/script/docker/new_script.sh"
  chmod +x "${BASE_WORK}/script/docker/new_script.sh"
  _tag_base_remote v0.9.7

  # v0.9.9 — transitional: both layouts shipped at once.
  _write_init_stub "dist/script/base/init.sh" "dist" "dist/script/docker/justfile"
  _write_stub_justfile "dist/script/docker/justfile"
  _tag_base_remote v0.9.9

  # v0.10.0 — dist layout only, as of base v0.42.0.
  git -C "${BASE_WORK}" rm -q "init.sh"
  _tag_base_remote v0.10.0

  # v0.10.1-rc1 — a release candidate on top of the newest release.
  printf '#!/usr/bin/env bash\nexit 0\n' > "${BASE_WORK}/script/docker/rc_only.sh"
  chmod +x "${BASE_WORK}/script/docker/rc_only.sh"
  _tag_base_remote v0.10.1-rc1

  git init --bare -q "${BASE_BARE}"
  git -C "${BASE_WORK}" push -q "${BASE_BARE}" --tags main
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

  # The template's managed .gitignore block. It is fixture, not decoration:
  # the paths `just setup` / `just build` generate are IGNORED, which is
  # precisely why `git rm -r .base/` leaves them behind and why the specs
  # below can distinguish "untracked" from "ignored" (issue #10).
  cat > "${REPO_DIR}/.gitignore" <<'EOF'
# managed by template (do not remove)
.env
.env.generated
compose.yaml
EOF

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

  # init.sh was executed (the stub drops a marker; the real init.sh would
  # create the scaffolding)
  assert_output --partial "init.sh"
  [ "$(cat init-ran.txt)" = "root" ]

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

# The documented default path. It resolves to the newest tag, which today
# carries the dist layout — the exact combination base#916 broke.
@test "bootstrap.sh (no arg): picks latest tag from remote" {
  cd "${REPO_DIR}"

  run env TEMPLATE_REMOTE="file://${BASE_BARE}" ./bootstrap.sh
  assert_success

  # Should have picked v0.10.0: the highest released tag, not the peeled
  # `v0.10.0^{}` row and not the v0.10.1-rc1 pre-release.
  [ "$(cat .base/.version)" = "v0.10.0" ]
  [ ! -f ".base/script/docker/rc_only.sh" ]
  [ "$(cat init-ran.txt)" = "dist" ]
  [ ! -f "bootstrap.sh" ]
}

# What "it worked" actually means to the person who just created the repo:
# the wrappers resolve and the entry point they type next runs. Issue #10's
# bricked repo also had nine dangling symlinks and a `just` that could not
# even list its recipes, and no spec noticed, because exit status was all
# anything asserted.
@test "a completed bootstrap dangles no symlink and leaves just --list working" {
  cd "${REPO_DIR}"

  run env TEMPLATE_REMOTE="file://${BASE_BARE}" ./bootstrap.sh
  assert_success

  [ -L "justfile" ]
  [ -L ".hadolint.yaml" ]
  [ -z "$(_dangling_symlinks)" ]

  run just --list
  assert_success
}

# ── init.sh path resolution across base layouts ────────────────────────────

@test "bootstrap.sh v0.10.0 (dist layout): resolves dist/script/base/init.sh" {
  cd "${REPO_DIR}"

  run env TEMPLATE_REMOTE="file://${BASE_BARE}" ./bootstrap.sh v0.10.0
  assert_success

  [ "$(cat .base/.version)" = "v0.10.0" ]
  [ ! -f ".base/init.sh" ]
  [ -f ".base/dist/script/base/init.sh" ]

  # Step 4 ran the dist init.sh, and step 5 was reached (self-delete).
  [ "$(cat init-ran.txt)" = "dist" ]
  [ ! -f "bootstrap.sh" ]

  # The dist layout exposes upgrade under the `base` command group.
  assert_output --partial "Future upgrades: just base upgrade"
  refute_output --partial "make upgrade"
}

@test "bootstrap.sh v0.9.5 (pre-dist layout): still resolves the root init.sh" {
  cd "${REPO_DIR}"

  run env TEMPLATE_REMOTE="file://${BASE_BARE}" ./bootstrap.sh v0.9.5
  assert_success

  [ "$(cat .base/.version)" = "v0.9.5" ]
  [ ! -d ".base/dist" ]

  [ "$(cat init-ran.txt)" = "root" ]
  [ ! -f "bootstrap.sh" ]

  # The pre-dist layout exposes upgrade at the top level.
  assert_output --partial "Future upgrades: just upgrade"
  refute_output --partial "make upgrade"
}

@test "bootstrap.sh prefers the dist init.sh when a tag ships both layouts" {
  cd "${REPO_DIR}"

  run env TEMPLATE_REMOTE="file://${BASE_BARE}" ./bootstrap.sh v0.9.9
  assert_success

  [ -f ".base/init.sh" ]
  [ -f ".base/dist/script/base/init.sh" ]
  [ "$(cat init-ran.txt)" = "dist" ]
  [ ! -f "bootstrap.sh" ]
}

@test "bootstrap.sh fails naming both paths when no init.sh exists" {
  cd "${REPO_DIR}"

  run env TEMPLATE_REMOTE="file://${BASE_BARE}" ./bootstrap.sh v0.9.0
  assert_failure

  assert_output --partial ".base/dist/script/base/init.sh"
  assert_output --partial ".base/init.sh"

  # Not bash's bare "No such file or directory".
  refute_output --partial "No such file or directory"
  [ ! -f "init-ran.txt" ]
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

  # Points at the upgrade entry the repo actually has (v0.9.7 is pre-dist).
  assert_output --partial "just upgrade"
  refute_output --partial "make upgrade"
}

# ── A failed bootstrap must leave a bootstrappable repo (issue #10) ───────
#
# `git rm -r .base/` removes only TRACKED files, so one untracked or
# ignored file keeps the directory alive, `git subtree add` refuses the
# existing prefix, and the failure lands AFTER step 2 has committed. The
# repo was then neither old nor new and `bootstrap.sh` refused to re-run,
# because the precondition it checks is the snapshot the previous run
# deleted. Asserting a non-zero exit is what let that ship; these specs
# assert the repo itself.

# Record what "unchanged" means for the assertions below.
_record_pre_state() {
  PRE_HEAD="$(git rev-parse HEAD)"
  PRE_STATUS="$(git status --porcelain)"
}

# The repo is exactly as the template shipped it: same commit, no extra
# commit, snapshot intact, working tree unchanged, and a bootstrap.sh that
# is both still here and still runnable.
_assert_pre_bootstrap_state() {
  [ "$(git rev-parse HEAD)" = "${PRE_HEAD}" ]
  [ "$(git rev-list --count HEAD)" = "1" ]
  [ "$(git status --porcelain)" = "${PRE_STATUS}" ]
  [ "$(cat .base/.version)" = "v0.9.5" ]
  [ -f ".base/init.sh" ]
  [ -x "bootstrap.sh" ]
  [ -f "README.md" ]
  [ -d "doc" ]
  [ -d ".github" ]
  [ -d "test" ]
  [ -z "$(_dangling_symlinks)" ]
}

@test "bootstrap.sh refuses when .base/ holds an ignored file, and changes nothing" {
  cd "${REPO_DIR}"

  # The reported trigger: `just setup` / `just build` before bootstrapping
  # generates .base/.env, which the managed .gitignore block hides.
  echo "GENERATED=1" > .base/.env
  git check-ignore -q .base/.env
  _record_pre_state

  run env TEMPLATE_REMOTE="file://${BASE_BARE}" ./bootstrap.sh v0.9.7
  assert_failure
  assert_output --partial ".base/.env"

  _assert_pre_bootstrap_state
  # Refusing means refusing: the file is the user's, not ours to delete.
  [ -f ".base/.env" ]

  # Still runnable — clear the blocker and the same command goes through.
  rm .base/.env
  run env TEMPLATE_REMOTE="file://${BASE_BARE}" ./bootstrap.sh v0.9.7
  assert_success
  [ "$(cat .base/.version)" = "v0.9.7" ]
}

@test "bootstrap.sh refuses when .base/ holds an untracked file, and changes nothing" {
  cd "${REPO_DIR}"

  mkdir -p .base/scratch
  echo "notes" > .base/scratch/notes.md
  _record_pre_state

  run env TEMPLATE_REMOTE="file://${BASE_BARE}" ./bootstrap.sh v0.9.7
  assert_failure
  assert_output --partial ".base/scratch/notes.md"

  _assert_pre_bootstrap_state
  [ -f ".base/scratch/notes.md" ]
}

@test "a failure after step 2 has committed rolls the repo all the way back" {
  cd "${REPO_DIR}"

  # Two files the user owns, one merely untracked and one ignored. A
  # rollback sweeps what the aborted run created; these are neither.
  echo "keep" > keep-me.txt
  echo "keep" > compose.yaml
  _record_pre_state

  # v0.9.1's init.sh creates a symlink, a file and an ignored file, then
  # exits 1 — by which point the step-2 commit and the subtree are in.
  run env TEMPLATE_REMOTE="file://${BASE_BARE}" ./bootstrap.sh v0.9.1
  assert_failure

  _assert_pre_bootstrap_state
  [ ! -d ".base/dist" ]

  # `git reset --hard` restores tracked content and says nothing about new
  # files; without the sweep these three survive a "restored" repo.
  [ ! -e "justfile" ]
  [ ! -e "partial-init-output.txt" ]
  [ ! -e ".env" ]

  # The user's own files are not collateral.
  [ "$(cat keep-me.txt)" = "keep" ]
  [ "$(cat compose.yaml)" = "keep" ]

  # And the documented recovery — run it again — actually works.
  run env TEMPLATE_REMOTE="file://${BASE_BARE}" ./bootstrap.sh v0.9.7
  assert_success
  [ "$(cat .base/.version)" = "v0.9.7" ]
  [ -z "$(_dangling_symlinks)" ]
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
