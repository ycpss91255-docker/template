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
  _run_init

  _log "Step 5/5: remove ${SCRIPT_NAME}"
  git rm -q "${SCRIPT_NAME}"
  git commit -q -m "chore: remove ${SCRIPT_NAME} (bootstrap complete)"

  _log "Done! Bootstrapped with ${TEMPLATE_REL} @ ${target_ver}"
  _log "Future upgrades: $(_upgrade_hint) [VERSION]"
}

main "$@"
