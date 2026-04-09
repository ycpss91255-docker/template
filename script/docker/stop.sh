#!/usr/bin/env bash
# stop.sh - Stop and remove Docker containers

set -euo pipefail

FILE_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly FILE_PATH
if [[ -f "${FILE_PATH}/template/script/docker/_lib.sh" ]]; then
  # shellcheck disable=SC1091
  source "${FILE_PATH}/template/script/docker/_lib.sh"
else
  # Fallback for /lint stage. See build.sh for rationale.
  _detect_lang() {
    case "${LANG:-}" in
      zh_TW*) echo "zh" ;;
      zh_CN*|zh_SG*) echo "zh-CN" ;;
      ja*) echo "ja" ;;
      *) echo "en" ;;
    esac
  }
  _LANG="${SETUP_LANG:-$(_detect_lang)}"
fi

usage() {
  case "${_LANG}" in
    zh)
      cat >&2 <<'EOF'
用法: ./stop.sh [-h] [--instance NAME] [--all]

停止並移除容器。預設只停止 default instance。

選項:
  -h, --help        顯示此說明
  --instance NAME   只停止指定的命名 instance
  --all             停止所有 instance(預設 + 全部命名 instance)
EOF
      ;;
    zh-CN)
      cat >&2 <<'EOF'
用法: ./stop.sh [-h] [--instance NAME] [--all]

停止并移除容器。默认只停止 default instance。

选项:
  -h, --help        显示此说明
  --instance NAME   只停止指定的命名 instance
  --all             停止所有 instance(默认 + 全部命名 instance)
EOF
      ;;
    ja)
      cat >&2 <<'EOF'
使用法: ./stop.sh [-h] [--instance NAME] [--all]

コンテナを停止・削除します。デフォルトは default instance のみ。

オプション:
  -h, --help        このヘルプを表示
  --instance NAME   指定された名前付き instance のみ停止
  --all             すべての instance を停止（デフォルト + 全名前付き instance）
EOF
      ;;
    *)
      cat >&2 <<'EOF'
Usage: ./stop.sh [-h] [--instance NAME] [--all]

Stop and remove containers. Default: stop only the default instance.

Options:
  -h, --help        Show this help
  --instance NAME   Stop only the named instance
  --all             Stop ALL instances (default + every named instance)
EOF
      ;;
  esac
  exit 0
}

INSTANCE=""
ALL_INSTANCES=false
PASSTHROUGH=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      ;;
    --instance)
      INSTANCE="${2:?"--instance requires a value"}"
      shift 2
      ;;
    --all)
      ALL_INSTANCES=true
      shift
      ;;
    *)
      PASSTHROUGH+=("$1")
      shift
      ;;
  esac
done

# Load .env so DOCKER_HUB_USER / IMAGE_NAME are available below.
_load_env "${FILE_PATH}/.env"

# _down_one tears down a single instance. _compute_project_name sets and
# exports INSTANCE_SUFFIX so compose.yaml resolves the matching container_name.
#
# Args:
#   $1: instance name (empty for the default instance)
_down_one() {
  local instance="${1}"
  _compute_project_name "${instance}"
  _compose_project down "${PASSTHROUGH[@]}"
}

if [[ "${ALL_INSTANCES}" == true ]]; then
  # Find all docker compose projects whose name starts with our prefix.
  _prefix="${DOCKER_HUB_USER}-${IMAGE_NAME}"
  mapfile -t _projects < <(
    docker ps -a --format '{{.Label "com.docker.compose.project"}}' \
      | sort -u | grep -E "^${_prefix}(\$|-)" || true
  )
  if [[ ${#_projects[@]} -eq 0 ]]; then
    printf "[stop] No instances found for %s\n" "${IMAGE_NAME}" >&2
    exit 0
  fi
  for _proj in "${_projects[@]}"; do
    _suffix="${_proj#"${_prefix}"}"
    # _suffix is "" or "-name"; _down_one expects bare instance, strip the dash.
    _down_one "${_suffix#-}"
  done
elif [[ -n "${INSTANCE}" ]]; then
  _down_one "${INSTANCE}"
else
  _down_one ""
fi
