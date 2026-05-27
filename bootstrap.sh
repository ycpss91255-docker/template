#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_NAME="bootstrap.sh"
readonly TEMPLATE_REL=".base"
readonly DEFAULT_REMOTE="${TEMPLATE_REMOTE:-https://github.com/ycpss91255-docker/base.git}"

_log() { printf '[%s] INFO: %s\n' "${SCRIPT_NAME}" "$*"; }
_error() { printf '[%s] ERROR: %s\n' "${SCRIPT_NAME}" "$*" >&2; exit 1; }

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
  local _latest
  _latest="$(git ls-remote --tags --sort=-v:refname "${DEFAULT_REMOTE}" 'v*' \
    | head -1 | sed 's|.*refs/tags/||')"
  if [[ -z "${_latest}" ]]; then
    _error "could not determine latest tag from ${DEFAULT_REMOTE}"
  fi
  printf '%s' "${_latest}"
}

_require_not_bootstrapped() {
  if git log --all --format=%B | grep -q "git-subtree-dir: ${TEMPLATE_REL}"; then
    _error "already bootstrapped — ${TEMPLATE_REL}/ has subtree history. Use 'make upgrade' instead."
  fi
}

_read_snapshot_version() {
  local _version_file="${TEMPLATE_REL}/.version"
  if [[ ! -f "${_version_file}" ]]; then
    _error "${_version_file} not found — is this a template-based repo?"
  fi
  cat "${_version_file}"
}

main() {
  local target_ver
  target_ver="$(_resolve_version "${1:-}")"

  _require_git_identity
  _require_not_bootstrapped

  local snapshot_ver
  snapshot_ver="$(_read_snapshot_version)"

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

  _log "Step 3/5: git subtree add ${TEMPLATE_REL}/ @ ${target_ver}"
  git subtree add --prefix="${TEMPLATE_REL}" \
    "${DEFAULT_REMOTE}" "${target_ver}" --squash \
    -m "chore: add ${TEMPLATE_REL} subtree ${target_ver}"

  _log "Step 4/5: run init.sh"
  "./${TEMPLATE_REL}/init.sh"

  _log "Step 5/5: remove ${SCRIPT_NAME}"
  git rm -q "${SCRIPT_NAME}"
  git commit -q -m "chore: remove ${SCRIPT_NAME} (bootstrap complete)"

  _log "Done! Bootstrapped with ${TEMPLATE_REL} @ ${target_ver}"
  _log "Future upgrades: make upgrade [VERSION]"
}

main "$@"
