#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_NAME="bootstrap.sh"
readonly TEMPLATE_REL=".base"
readonly DEFAULT_REMOTE="${TEMPLATE_REMOTE:-https://github.com/ycpss91255-docker/base.git}"

# init.sh locations inside the subtree, newest layout first. bootstrap.sh
# is pinned to nothing -- it is whatever sits on the template repo's main
# when someone creates a repo -- while the base tag it bootstraps is
# arbitrary, so the path is resolved rather than named. base v0.42.0 moved
# init.sh under dist/ (ADR-00000011 section 8 / ADR-00000006 Region A);
# older tags still keep it at the subtree root.
readonly INIT_CANDIDATES=(
  "dist/script/base/init.sh"
  "init.sh"
)

_log() { printf '[%s] INFO: %s\n' "${SCRIPT_NAME}" "$*"; }
_log_err() { printf '[%s] ERROR: %s\n' "${SCRIPT_NAME}" "$*" >&2; }
_error() { _log_err "$*"; exit 1; }

# Rollback state. Both are filled in before the first mutation; the trap
# is armed the moment step 2 commits and disarmed once the last step that
# can fail has succeeded. A non-empty _BOOTSTRAP_PRE_HEAD is what tells
# the exit trap there is a commit to undo. Deliberately NOT readonly --
# clearing _BOOTSTRAP_PRE_HEAD is half of how the trap is disarmed.
_BOOTSTRAP_PRE_HEAD=""
_BOOTSTRAP_PRE_RUN_PATHS=()

_require_git_identity() {
  local _name _email
  _name="$(git config user.name 2>/dev/null || true)"
  _email="$(git config user.email 2>/dev/null || true)"
  if [[ -z "${_name}" || -z "${_email}" ]]; then
    _error "git identity not configured. Set it before bootstrapping:
  git config user.name \"Your Name\"
  git config user.email \"you@example.com\""
  fi
}

_resolve_version() {
  local _requested="${1:-}"
  if [[ -n "${_requested}" ]]; then
    printf '%s' "${_requested}"
    return
  fi
  # ls-remote lists a peeled `<tag>^{}` row for every annotated tag, and
  # version-sort ranks that row above the tag itself -- `head -1` on the
  # raw listing yields `vX.Y.Z^{}`, which is not a ref `git subtree add`
  # accepts. Strip the peel marker, then take the highest tag that is not
  # a semver pre-release (`vX.Y.Z-rc1`), which is never a bootstrap
  # target. awk consumes the whole listing and always exits 0, so an empty
  # result reaches the explicit error below instead of tripping pipefail.
  local _latest
  _latest="$(git ls-remote --tags --sort=-v:refname "${DEFAULT_REMOTE}" 'v*' \
    | awk -F'refs/tags/' '
        NF > 1 && !latest {
          tag = $2
          sub(/\^\{\}$/, "", tag)
          if (tag !~ /-/) { latest = tag }
        }
        END { print latest }')"
  if [[ -z "${_latest}" ]]; then
    _error "could not determine latest tag from ${DEFAULT_REMOTE}"
  fi
  printf '%s' "${_latest}"
}

# The upgrade entry point moved with the layout: pre-dist repos expose
# `just upgrade` at the top level, v0.42.0+ repos expose it under the
# `base` command group. Probe the subtree rather than naming one, for the
# same reason _run_init does.
_upgrade_hint() {
  if [[ -d "${TEMPLATE_REL}/dist" ]]; then
    printf '%s' "just base upgrade"
  else
    printf '%s' "just upgrade"
  fi
}

# Resolve and run the subtree's init.sh. Fails naming every path tried,
# so a future layout move reports what it looked for instead of bash's
# bare "No such file or directory".
_run_init() {
  local _candidate
  local -a _tried=()
  for _candidate in "${INIT_CANDIDATES[@]}"; do
    _tried+=("${TEMPLATE_REL}/${_candidate}")
    if [[ -f "${TEMPLATE_REL}/${_candidate}" ]]; then
      _log "  using ${TEMPLATE_REL}/${_candidate}"
      "./${TEMPLATE_REL}/${_candidate}"
      return
    fi
  done
  _error "no init.sh found in the ${TEMPLATE_REL}/ subtree. Tried: ${_tried[*]}"
}

_require_not_bootstrapped() {
  if git log --all --format=%B | grep -q "git-subtree-dir: ${TEMPLATE_REL}"; then
    _error "already bootstrapped — ${TEMPLATE_REL}/ has subtree history. Use '$(_upgrade_hint)' instead."
  fi
}

_read_snapshot_version() {
  local _version_file="${TEMPLATE_REL}/.version"
  if [[ ! -f "${_version_file}" ]]; then
    _error "${_version_file} not found — is this a template-based repo?"
  fi
  cat "${_version_file}"
}

# _require_pristine_snapshot
#   Refuse, before anything moves, when ${TEMPLATE_REL}/ holds a file git
#   is not tracking.
#
#   Step 2 removes the snapshot with `git rm -r`, which removes TRACKED
#   files only. One untracked or ignored file therefore keeps the
#   directory alive, and step 3's `git subtree add` refuses a prefix that
#   already exists -- after step 2 has committed. Failing here costs the
#   user one `rm`; failing there used to cost them the repo.
#
#   `git ls-files --others` deliberately WITHOUT --exclude-standard: the
#   usual offenders are ${TEMPLATE_REL}/.env, /compose.yaml and
#   /.env.generated, which the template's own .gitignore covers. Being
#   ignored is why `git rm` skips them, so ignoring them here would look
#   past the exact files that break the run.
#
#   Scope is ${TEMPLATE_REL}/ only. The repo-root files step 1 removes
#   (README.md, doc/, .github/, test/) have no such failure mode -- a
#   stray file merely survives in a directory nothing later re-creates --
#   and refusing over one would block a bootstrap for a note the user
#   dropped in the repo they are creating.
_require_pristine_snapshot() {
  local -a _stray=()
  mapfile -t _stray < <(git ls-files --others -- "${TEMPLATE_REL}/")
  if [[ ${#_stray[@]} -eq 0 ]]; then
    return 0
  fi

  local _list
  _list="$(printf '  %s\n' "${_stray[@]}")"
  _error "${TEMPLATE_REL}/ holds files that git is not tracking:

${_list}

Nothing has been changed yet.

Bootstrapping replaces ${TEMPLATE_REL}/ with a git subtree, and git refuses to
create one over a directory that already exists. Only tracked files get
removed for you, so the files above would survive and take the run down
in the middle of it.

Files like ${TEMPLATE_REL}/.env, ${TEMPLATE_REL}/compose.yaml and
${TEMPLATE_REL}/.env.generated are generated by 'just setup', 'just build' and
'just run'. If you ran one of those before bootstrapping, delete them --
they are rebuilt on demand -- and run ./${SCRIPT_NAME} again.

Anything above you want to keep, move it out of ${TEMPLATE_REL}/ first:
bootstrapping replaces that directory wholesale."
}

# _restore_pre_bootstrap_state <pre_head_sha>
#   Put the repo back the way this run found it: hard-reset to the
#   pre-bootstrap commit, then delete the paths the aborted run created.
#
#   The sweep is not optional. `git reset --hard` restores TRACKED content
#   and says nothing about anything new, so without it the "restored" tree
#   still carries the aborted run's symlinks into a subtree that is no
#   longer there -- which is the bricked repo, minus the commit. Only
#   paths that were absent before the run are removed, so a file the user
#   already had is never collateral.
#
#   Disarms the trap on the way in: this IS the rollback, and it must not
#   be re-entered by the exit that follows it.
#
#   Exits (does not return) when the reset itself fails. That must not be
#   swallowed: it runs when the tree is already damaged, and a reassuring
#   "restored" the user then builds on top of is worse than the truth.
_restore_pre_bootstrap_state() {
  local _pre_head="$1"
  _BOOTSTRAP_PRE_HEAD=""
  trap - EXIT

  _log_err "rolling back to ${_pre_head:0:12} ..."
  if ! git reset --hard "${_pre_head}" >/dev/null 2>&1; then
    _log_err "rollback FAILED — could not reset to ${_pre_head:0:12}.
The working tree is NOT restored. Recover it by hand:
  git reset --hard ${_pre_head}"
    exit 1
  fi
  _remove_paths_created_by_this_run
  _log_err "bootstrap aborted; the repo is back to its pre-bootstrap state.
Fix the cause reported above, then run ./${SCRIPT_NAME} again."
}

# _remove_paths_created_by_this_run
#   Delete every path git does not track that was not there before the
#   run. Runs AFTER the reset, so the listing describes the restored tree.
#
#   Ignored files are included on both sides of the comparison (no
#   --exclude-standard, matching the pre-run snapshot). Two reasons: the
#   run rewrites both the repo's .gitignore and the whole of
#   ${TEMPLATE_REL}/, so mid-run ignore rules cannot be trusted to
#   classify anything; and the files an aborted run most often leaves
#   inside ${TEMPLATE_REL}/ are ignored ones -- the very class that would
#   make the next run refuse.
_remove_paths_created_by_this_run() {
  local _path
  while IFS= read -r _path; do
    if [[ -z "${_path}" ]]; then
      continue
    fi
    if _was_present_before_bootstrap "${_path}"; then
      continue
    fi
    # Paths are relative to the repo root, which is this script's working
    # directory throughout; `--` keeps a leading dash a filename.
    rm -f -- "${_path}"
  done < <(git ls-files --others)
}

# _was_present_before_bootstrap <path>
#   Membership test against the pre-run listing. In-shell rather than
#   `grep -q` over a printf: a reader that stops at its first match
#   strands the writer with SIGPIPE, and under `pipefail` that 141 becomes
#   the pipeline's status -- a successful match reported as "not found",
#   which here would delete a file the user owns.
_was_present_before_bootstrap() {
  local _path="$1"
  local _known
  for _known in "${_BOOTSTRAP_PRE_RUN_PATHS[@]}"; do
    if [[ "${_known}" == "${_path}" ]]; then
      return 0
    fi
  done
  return 1
}

# _bootstrap_exit_trap
#   Armed the moment step 2 has COMMITTED, disarmed once every step that
#   can fail has succeeded. In between, the repo is mid-flight: the
#   template files and the vendored snapshot are gone from history, and
#   the subtree that replaces them is not in yet.
#
#   Leaving that state behind is the bug this trap exists for: the repo is
#   neither the template nor a bootstrapped repo, every wrapper symlink
#   dangles, and ./bootstrap.sh cannot be re-run because the snapshot its
#   own precondition reads is the one step 2 deleted.
#
#   Arming it exactly here, and not earlier, is deliberate. A rollback is
#   `git reset --hard`, which is only safe once everything in the tree is
#   this run's doing. Before step 2's commit that is not true -- the user
#   may have had staged or modified work of their own -- and steps 1 and 2
#   fail, when they fail, without having committed anything, which is
#   recoverable with the `git checkout` git itself suggests.
_bootstrap_exit_trap() {
  local _status=$?
  trap - EXIT
  if (( _status == 0 )) || [[ -z "${_BOOTSTRAP_PRE_HEAD}" ]]; then
    exit "${_status}"
  fi
  _log_err "bootstrap failed (exit ${_status}) after step 2 had committed.
Undoing that commit, so the repo is not left half-bootstrapped."
  _restore_pre_bootstrap_state "${_BOOTSTRAP_PRE_HEAD}"
  exit "${_status}"
}

main() {
  local target_ver
  target_ver="$(_resolve_version "${1:-}")"

  _require_git_identity
  _require_not_bootstrapped

  local snapshot_ver
  snapshot_ver="$(_read_snapshot_version)"
  _require_pristine_snapshot

  # The commit to come back to, and the paths that were already here. Both
  # are read before the first mutation, so a rollback restores what the
  # user had rather than some mid-run approximation of it.
  local _pre_head
  _pre_head="$(git rev-parse HEAD 2>/dev/null)" \
    || _error "this repo has no commits yet, so there is nothing to bootstrap
from and nothing to roll back to. Commit the template files first."
  mapfile -t _BOOTSTRAP_PRE_RUN_PATHS < <(git ls-files --others)

  _log "Bootstrapping: snapshot ${snapshot_ver} -> target ${target_ver}"

  _log "Step 1/5: remove template-specific files"
  local _template_files=(
    README.md
    doc/
    .github/
    test/
  )
  for _f in "${_template_files[@]}"; do
    if git ls-files --error-unmatch "${_f}" &>/dev/null; then
      git rm -r -q "${_f}"
    fi
  done

  _log "Step 2/5: remove snapshot ${TEMPLATE_REL}/"
  git rm -r -q "${TEMPLATE_REL}/"
  git commit -q -m "chore: remove template files + ${TEMPLATE_REL} snapshot for subtree re-add"

  # That commit is the point of no return: the template is gone from the
  # working tree and the subtree that replaces it is not in yet. Arm the
  # rollback before the first step that can fail from here on -- see
  # _bootstrap_exit_trap for why this is the right place for it.
  _BOOTSTRAP_PRE_HEAD="${_pre_head}"
  trap _bootstrap_exit_trap EXIT

  _log "Step 3/5: git subtree add ${TEMPLATE_REL}/ @ ${target_ver}"
  git subtree add --prefix="${TEMPLATE_REL}" \
    "${DEFAULT_REMOTE}" "${target_ver}" --squash \
    -m "chore: add ${TEMPLATE_REL} subtree ${target_ver}"

  _log "Step 4/5: run init.sh"
  _run_init

  _log "Step 5/5: remove ${SCRIPT_NAME}"
  git rm -q "${SCRIPT_NAME}"
  git commit -q -m "chore: remove ${SCRIPT_NAME} (bootstrap complete)"

  # Every step that can fail has succeeded, and the last of them was
  # itself a commit -- undoing anything now would undo a finished
  # bootstrap. Disarm before the closing log lines.
  _BOOTSTRAP_PRE_HEAD=""
  trap - EXIT

  _log "Done! Bootstrapped with ${TEMPLATE_REL} @ ${target_ver}"
  _log "Future upgrades: $(_upgrade_hint) [VERSION]"
}

main "$@"
