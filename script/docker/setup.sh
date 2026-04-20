#!/usr/bin/env bash
# setup.sh - Auto-detect system parameters and generate .env before build
#
# Features:
#   - User info detection (UID/GID/USER/GROUP)
#   - Hardware architecture detection
#   - Docker Hub username detection
#   - GPU support detection
#   - Image name detection via image_name.conf rule engine
#   - Workspace path detection (sibling scan → path traversal → parent directory fallback)
#   - APT mirror configuration
#   - .env generation
#
# Usage: setup.sh [--base-path <path>] [--lang zh|zh-CN|ja]

# ── i18n messages ──────────────────────────────────────────────
# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/i18n.sh"

_msg() {
  local _key="${1}"
  case "${_LANG}" in
    zh)
      case "${_key}" in
        env_done)      echo ".env 更新完成" ;;
        env_comment)   echo "自動偵測欄位請勿手動修改，如需變更 WS_PATH 可直接編輯此檔案" ;;
        unknown_arg)   echo "未知參數" ;;
      esac ;;
    zh-CN)
      case "${_key}" in
        env_done)      echo ".env 更新完成" ;;
        env_comment)   echo "自动检测字段请勿手动修改，如需变更 WS_PATH 可直接编辑此文件" ;;
        unknown_arg)   echo "未知参数" ;;
      esac ;;
    ja)
      case "${_key}" in
        env_done)      echo ".env 更新完了" ;;
        env_comment)   echo "自動検出フィールドは手動で編集しないでください。WS_PATH の変更はこのファイルを直接編集してください" ;;
        unknown_arg)   echo "不明な引数" ;;
      esac ;;
    *)
      case "${_key}" in
        env_done)      echo ".env updated" ;;
        env_comment)   echo "Auto-detected fields, do not edit manually. Edit WS_PATH if needed" ;;
        unknown_arg)   echo "Unknown argument" ;;
      esac ;;
  esac
}

# Only set strict mode when running directly; when sourced, respect caller's settings
if [[ "${BASH_SOURCE[0]:-}" == "${0:-}" ]]; then
  set -euo pipefail
fi

# ════════════════════════════════════════════════════════════════════
# detect_user_info
#
# Usage: detect_user_info <user_outvar> <group_outvar> <uid_outvar> <gid_outvar>
# ════════════════════════════════════════════════════════════════════
detect_user_info() {
  local -n __dui_user="${1:?"${FUNCNAME[0]}: missing user outvar"}"; shift
  local -n __dui_group="${1:?"${FUNCNAME[0]}: missing group outvar"}"; shift
  local -n __dui_uid="${1:?"${FUNCNAME[0]}: missing uid outvar"}"; shift
  local -n __dui_gid="${1:?"${FUNCNAME[0]}: missing gid outvar"}"

  __dui_user="${USER:-$(id -un)}"
  __dui_group="$(id -gn)"
  __dui_uid="$(id -u)"
  __dui_gid="$(id -g)"
}

# ════════════════════════════════════════════════════════════════════
# detect_hardware
#
# Usage: detect_hardware <outvar>
# ════════════════════════════════════════════════════════════════════
detect_hardware() {
  local -n _outvar="${1:?"${FUNCNAME[0]}: missing outvar"}"
  _outvar="$(uname -m)"
}

# ════════════════════════════════════════════════════════════════════
# detect_docker_hub_user
#
# Tries docker info first, falls back to USER, then id -un
#
# Usage: detect_docker_hub_user <outvar>
# ════════════════════════════════════════════════════════════════════
detect_docker_hub_user() {
  local -n _outvar="${1:?"${FUNCNAME[0]}: missing outvar"}"
  local _name=""
  _name="$(docker info 2>/dev/null | awk '/^[[:space:]]*Username:/{print $2}')" || true
  _outvar="${_name:-${USER:-$(id -un)}}"
}

# ════════════════════════════════════════════════════════════════════
# detect_gpu
#
# Checks nvidia-container-toolkit via dpkg-query
#
# Usage: detect_gpu <outvar>
# outvar: "true" or "false"
# ════════════════════════════════════════════════════════════════════
detect_gpu() {
  local -n _outvar="${1:?"${FUNCNAME[0]}: missing outvar"}"
  if dpkg-query -W -f='${db:Status-Abbrev}\n' -- "nvidia-container-toolkit" 2>/dev/null \
    | grep -q '^ii'; then
    _outvar=true
  else
    _outvar=false
  fi
}

# ════════════════════════════════════════════════════════════════════
# Rule applicators (used by detect_image_name)
#
# Each takes the path and rule value, echoes the matched name or nothing.
# ════════════════════════════════════════════════════════════════════

_rule_prefix() {
  local _path="$1" _value="$2"
  local -a _parts=()
  IFS='/' read -ra _parts <<< "${_path}"
  local i _part _last=""
  for (( i=${#_parts[@]}-1; i>=0; i-- )); do
    _part="${_parts[i]}"
    [[ -z "${_part}" ]] && continue
    _last="${_part}"
    break
  done
  if [[ "${_last}" == "${_value}"* ]]; then
    echo "${_last#"${_value}"}"
  fi
}

_rule_suffix() {
  local _path="$1" _value="$2"
  local -a _parts=()
  IFS='/' read -ra _parts <<< "${_path}"
  local i _part
  for (( i=${#_parts[@]}-1; i>=0; i-- )); do
    _part="${_parts[i]}"
    [[ -z "${_part}" ]] && continue
    if [[ "${_part}" == *"${_value}" ]]; then
      echo "${_part%"${_value}"}"
      return
    fi
  done
}

_rule_env_example() {
  local _base="${BASE_PATH:-$1}"
  # If $1 is a path, derive base; if BASE_PATH is set, use it
  local _file="${_base}/.env.example"
  if [[ -f "${_file}" ]]; then
    grep -m1 '^IMAGE_NAME=' "${_file}" 2>/dev/null | cut -d= -f2-
  fi
}

_rule_basename() {
  local _path="$1"
  local -a _parts=()
  IFS='/' read -ra _parts <<< "${_path}"
  local i _part
  for (( i=${#_parts[@]}-1; i>=0; i-- )); do
    _part="${_parts[i]}"
    [[ -z "${_part}" ]] && continue
    echo "${_part}"
    return
  done
}

# ════════════════════════════════════════════════════════════════════
# detect_image_name
#
# Reads rules from image_name.conf (per-repo override or template default).
# Rules applied in order; first match wins.
#
# Conf path resolution:
#   1. ${IMAGE_NAME_CONF} env var (test override)
#   2. ${BASE_PATH}/config/setup/image_name.conf (repo-level override)
#   3. <template>/config/setup/image_name.conf (default)
#
# Usage: detect_image_name <outvar> <path>
# ════════════════════════════════════════════════════════════════════
detect_image_name() {
  local -n _outvar="${1:?"${FUNCNAME[0]}: missing outvar"}"; shift
  local _path="${1:?"${FUNCNAME[0]}: missing path"}"

  # Resolve conf file
  local _conf="${IMAGE_NAME_CONF:-}"
  if [[ -z "${_conf}" ]]; then
    local _base="${BASE_PATH:-${_path}}"
    if [[ -f "${_base}/config/setup/image_name.conf" ]]; then
      _conf="${_base}/config/setup/image_name.conf"
    else
      # Default: template/config/setup/image_name.conf
      local _self_dir
      _self_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
      _conf="${_self_dir}/../../config/setup/image_name.conf"
    fi
  fi

  local _found=""
  if [[ -f "${_conf}" ]]; then
    local _line _type _value
    while IFS= read -r _line || [[ -n "${_line}" ]]; do
      # Skip comments and empty lines
      [[ -z "${_line}" || "${_line}" =~ ^[[:space:]]*# ]] && continue
      # Trim whitespace
      _line="${_line#"${_line%%[![:space:]]*}"}"
      _line="${_line%"${_line##*[![:space:]]}"}"
      [[ -z "${_line}" ]] && continue

      if [[ "${_line}" == prefix:* ]]; then
        _value="${_line#prefix:}"
        _found="$(_rule_prefix "${_path}" "${_value}")"
      elif [[ "${_line}" == suffix:* ]]; then
        _value="${_line#suffix:}"
        _found="$(_rule_suffix "${_path}" "${_value}")"
      elif [[ "${_line}" == "@env_example" ]]; then
        _found="$(BASE_PATH="${BASE_PATH:-${_path}}" _rule_env_example "${_path}")"
      elif [[ "${_line}" == "@basename" ]]; then
        _found="$(_rule_basename "${_path}")"
      elif [[ "${_line}" == @default:* ]]; then
        _found="${_line#@default:}"
        printf "[setup] INFO: IMAGE_NAME using @default:%s\n" "${_found}" >&2
      fi

      [[ -n "${_found}" ]] && break
    done < "${_conf}"
  fi

  if [[ -z "${_found}" ]]; then
    printf "[setup] WARNING: IMAGE_NAME could not be detected. Using 'unknown'.\n" >&2
    _found="unknown"
  fi
  _outvar="${_found,,}"
}

# ════════════════════════════════════════════════════════════════════
# Per-repo setup conf helpers (gpu.conf / gui.conf / network.conf /
# volumes.conf). Each conf lives in template/config/setup/ by default,
# overridable via <repo>/config/setup/<name>.conf or <NAME>_CONF env var.
# ════════════════════════════════════════════════════════════════════

# _load_conf_value <conf_file> <key> <outvar>
#
# Reads INI-style key=value from conf_file. Skips comments (#) and empty
# lines. Trims whitespace around key and value. Sets outvar to "" when
# key not found or file missing.
_load_conf_value() {
  local _file="${1:?"${FUNCNAME[0]}: missing conf_file"}"
  local _key="${2:?"${FUNCNAME[0]}: missing key"}"
  local -n _lcv_out="${3:?"${FUNCNAME[0]}: missing outvar"}"

  _lcv_out=""
  [[ -f "${_file}" ]] || return 0

  # Use function-prefixed locals to avoid shadowing the caller's outvar
  # when the caller uses a short name (e.g. _v) that matches.
  local __lcv_line __lcv_k __lcv_val
  while IFS= read -r __lcv_line || [[ -n "${__lcv_line}" ]]; do
    [[ -z "${__lcv_line}" || "${__lcv_line}" =~ ^[[:space:]]*# ]] && continue
    [[ "${__lcv_line}" != *=* ]] && continue
    __lcv_k="${__lcv_line%%=*}"
    __lcv_val="${__lcv_line#*=}"
    # Trim whitespace
    __lcv_k="${__lcv_k#"${__lcv_k%%[![:space:]]*}"}"
    __lcv_k="${__lcv_k%"${__lcv_k##*[![:space:]]}"}"
    __lcv_val="${__lcv_val#"${__lcv_val%%[![:space:]]*}"}"
    __lcv_val="${__lcv_val%"${__lcv_val##*[![:space:]]}"}"
    if [[ "${__lcv_k}" == "${_key}" ]]; then
      _lcv_out="${__lcv_val}"
      return 0
    fi
  done < "${_file}"
}

# _load_conf_lines <conf_file> <outvar_array>
#
# Reads all non-empty non-comment lines from conf_file into outvar (as
# array). Used for volumes.conf (list of mount specs). Sets outvar to
# empty array when file missing.
_load_conf_lines() {
  local _file="${1:?"${FUNCNAME[0]}: missing conf_file"}"
  local -n _lcl_out="${2:?"${FUNCNAME[0]}: missing outvar"}"

  _lcl_out=()
  [[ -f "${_file}" ]] || return 0

  local __lcl_line
  while IFS= read -r __lcl_line || [[ -n "${__lcl_line}" ]]; do
    [[ -z "${__lcl_line}" || "${__lcl_line}" =~ ^[[:space:]]*# ]] && continue
    # Trim whitespace
    __lcl_line="${__lcl_line#"${__lcl_line%%[![:space:]]*}"}"
    __lcl_line="${__lcl_line%"${__lcl_line##*[![:space:]]}"}"
    [[ -z "${__lcl_line}" ]] && continue
    _lcl_out+=("${__lcl_line}")
  done < "${_file}"
}

# _resolve_conf_path <name> <base_path> <outvar>
#
# Three-tier lookup for per-repo setup conf files:
#   1. <NAME>_CONF env var (uppercase <name>, e.g. GPU_CONF)
#   2. <base_path>/config/setup/<name>.conf
#   3. <template>/config/setup/<name>.conf
_resolve_conf_path() {
  local _name="${1:?"${FUNCNAME[0]}: missing name"}"
  local _base="${2:?"${FUNCNAME[0]}: missing base_path"}"
  local -n _rcp_out="${3:?"${FUNCNAME[0]}: missing outvar"}"

  # Tier 1: env var override (name upper-cased)
  local _env_var="${_name^^}_CONF"
  if [[ -n "${!_env_var:-}" ]]; then
    _rcp_out="${!_env_var}"
    return 0
  fi

  # Tier 2: per-repo override
  local _repo_conf="${_base}/config/setup/${_name}.conf"
  if [[ -f "${_repo_conf}" ]]; then
    _rcp_out="${_repo_conf}"
    return 0
  fi

  # Tier 3: template default
  local _self_dir
  _self_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
  _rcp_out="${_self_dir}/../../config/setup/${_name}.conf"
}

# _load_gpu_conf <base_path> <mode_outvar> <count_outvar> <caps_outvar>
_load_gpu_conf() {
  local _base="${1:?"${FUNCNAME[0]}: missing base_path"}"
  local -n _lgc_mode="${2:?"${FUNCNAME[0]}: missing mode outvar"}"
  local -n _lgc_count="${3:?"${FUNCNAME[0]}: missing count outvar"}"
  local -n _lgc_caps="${4:?"${FUNCNAME[0]}: missing caps outvar"}"

  local _conf=""
  _resolve_conf_path "gpu" "${_base}" _conf
  _load_conf_value "${_conf}" "mode"         _lgc_mode
  _load_conf_value "${_conf}" "count"        _lgc_count
  _load_conf_value "${_conf}" "capabilities" _lgc_caps
  # Sane defaults when conf missing a key
  _lgc_mode="${_lgc_mode:-auto}"
  _lgc_count="${_lgc_count:-all}"
  _lgc_caps="${_lgc_caps:-gpu}"
}

# _load_gui_conf <base_path> <mode_outvar>
_load_gui_conf() {
  local _base="${1:?"${FUNCNAME[0]}: missing base_path"}"
  local -n _lgi_mode="${2:?"${FUNCNAME[0]}: missing mode outvar"}"

  local _conf=""
  _resolve_conf_path "gui" "${_base}" _conf
  _load_conf_value "${_conf}" "mode" _lgi_mode
  _lgi_mode="${_lgi_mode:-auto}"
}

# _load_network_conf <base_path> <mode_outvar> <ipc_outvar> <privileged_outvar>
_load_network_conf() {
  local _base="${1:?"${FUNCNAME[0]}: missing base_path"}"
  local -n _lnc_mode="${2:?"${FUNCNAME[0]}: missing mode outvar"}"
  local -n _lnc_ipc="${3:?"${FUNCNAME[0]}: missing ipc outvar"}"
  local -n _lnc_priv="${4:?"${FUNCNAME[0]}: missing privileged outvar"}"

  local _conf=""
  _resolve_conf_path "network" "${_base}" _conf
  _load_conf_value "${_conf}" "mode"       _lnc_mode
  _load_conf_value "${_conf}" "ipc"        _lnc_ipc
  _load_conf_value "${_conf}" "privileged" _lnc_priv
  _lnc_mode="${_lnc_mode:-host}"
  _lnc_ipc="${_lnc_ipc:-host}"
  _lnc_priv="${_lnc_priv:-true}"
}

# _load_volumes_conf <base_path> <mounts_outvar_array>
_load_volumes_conf() {
  local _base="${1:?"${FUNCNAME[0]}: missing base_path"}"
  local -n _lvc_mounts="${2:?"${FUNCNAME[0]}: missing outvar"}"

  local _conf=""
  _resolve_conf_path "volumes" "${_base}" _conf
  _load_conf_lines "${_conf}" _lvc_mounts
}

# _resolve_gpu <mode> <detected> <enabled_outvar>
#
# Computes whether the GPU deploy block should be emitted:
#   mode=auto   → enabled iff detected==true
#   mode=force  → always enabled
#   mode=off    → always disabled
_resolve_gpu() {
  local _mode="${1:?"${FUNCNAME[0]}: missing mode"}"
  local _detected="${2:?"${FUNCNAME[0]}: missing detected"}"
  local -n _rg_out="${3:?"${FUNCNAME[0]}: missing outvar"}"

  case "${_mode}" in
    force) _rg_out="true" ;;
    off)   _rg_out="false" ;;
    auto|*)
      if [[ "${_detected}" == "true" ]]; then
        _rg_out="true"
      else
        _rg_out="false"
      fi
      ;;
  esac
}

# _resolve_gui <mode> <enabled_outvar>
#
# Computes whether the GUI env/volumes block should be emitted:
#   mode=auto   → enabled iff $DISPLAY or $WAYLAND_DISPLAY is set
#   mode=force  → always enabled
#   mode=off    → always disabled
_resolve_gui() {
  local _mode="${1:?"${FUNCNAME[0]}: missing mode"}"
  local -n _rgu_out="${2:?"${FUNCNAME[0]}: missing outvar"}"

  case "${_mode}" in
    force) _rgu_out="true" ;;
    off)   _rgu_out="false" ;;
    auto|*)
      if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
        _rgu_out="true"
      else
        _rgu_out="false"
      fi
      ;;
  esac
}

# ════════════════════════════════════════════════════════════════════
# generate_compose_yaml
#
# Emits a full compose.yaml reflecting the repo's current effective
# runtime configuration. Network/IPC/privileged values from network.conf
# are baked in as compose defaults (e.g. `${NETWORK_MODE:-host}`), so
# `.env` or runtime env vars can still override on-the-fly.
#
# Conditional sections:
#   - environment + GUI volumes: included iff gui_enabled=true
#   - deploy block (GPU):        included iff gpu_enabled=true
#   - extra volume lines:        one per element in extras_ref
#
# Usage:
#   generate_compose_yaml <out_path> <repo_name> \
#       <gui_enabled> <network_mode> <ipc_mode> <privileged> \
#       <gpu_enabled> <gpu_count> <gpu_caps> \
#       <extras_array_ref>
# ════════════════════════════════════════════════════════════════════
generate_compose_yaml() {
  local _out="${1:?"${FUNCNAME[0]}: missing out_path"}"
  local _name="${2:?"${FUNCNAME[0]}: missing repo_name"}"
  local _gui="${3:?"${FUNCNAME[0]}: missing gui_enabled"}"
  local _network="${4:?"${FUNCNAME[0]}: missing network_mode"}"
  local _ipc="${5:?"${FUNCNAME[0]}: missing ipc_mode"}"
  local _priv="${6:?"${FUNCNAME[0]}: missing privileged"}"
  local _gpu="${7:?"${FUNCNAME[0]}: missing gpu_enabled"}"
  local _gpu_count="${8:?"${FUNCNAME[0]}: missing gpu_count"}"
  local _gpu_caps="${9:?"${FUNCNAME[0]}: missing gpu_caps"}"
  local -n _gcy_extras="${10:?"${FUNCNAME[0]}: missing extras_array_ref}"}"

  # Convert space-separated capabilities to YAML array form [a, b, c]
  local -a _caps_arr=()
  read -ra _caps_arr <<< "${_gpu_caps}"
  local _caps_yaml="["
  local _first=1 _cap
  for _cap in "${_caps_arr[@]}"; do
    if (( _first )); then
      _caps_yaml+="${_cap}"
      _first=0
    else
      _caps_yaml+=", ${_cap}"
    fi
  done
  _caps_yaml+="]"

  {
    cat <<'HEADER'
# AUTO-GENERATED BY setup.sh — DO NOT EDIT.
# Edit conf files in config/setup/ instead. Regenerate via ./build.sh
# or ./template/script/docker/setup.sh.
HEADER
    cat <<YAML
services:
  devel:
    build:
      context: .
      dockerfile: Dockerfile
      target: devel
      args:
        APT_MIRROR_UBUNTU: \${APT_MIRROR_UBUNTU:-tw.archive.ubuntu.com}
        APT_MIRROR_DEBIAN: \${APT_MIRROR_DEBIAN:-mirror.twds.com.tw}
        USER_NAME: \${USER_NAME}
        USER_GROUP: \${USER_GROUP}
        USER_UID: \${USER_UID}
        USER_GID: \${USER_GID}
    image: \${DOCKER_HUB_USER:-local}/${_name}:devel
    container_name: ${_name}\${INSTANCE_SUFFIX:-}
    privileged: \${PRIVILEGED:-${_priv}}
    network_mode: \${NETWORK_MODE:-${_network}}
    ipc: \${IPC_MODE:-${_ipc}}
    stdin_open: true
    tty: true
YAML
    if [[ "${_gui}" == "true" ]]; then
      cat <<'YAML'
    environment:
      - DISPLAY=${DISPLAY:-}
      - WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-}
      - XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/1000}
      - XAUTHORITY=${XAUTHORITY:-}
YAML
    fi
    # volumes block: always present (workspace + /dev at minimum)
    echo "    volumes:"
    if [[ "${_gui}" == "true" ]]; then
      cat <<'YAML'
      - /tmp/.X11-unix:/tmp/.X11-unix:ro
      - ${XDG_RUNTIME_DIR:-/run/user/1000}:${XDG_RUNTIME_DIR:-/run/user/1000}:rw
      - ${XAUTHORITY:-/dev/null}:${XAUTHORITY:-/dev/null}:ro
YAML
    fi
    cat <<'YAML'
      - /dev:/dev
      - ${WS_PATH}:/home/${USER_NAME}/work
YAML
    # Extra volumes from volumes.conf
    local _m
    for _m in "${_gcy_extras[@]}"; do
      echo "      - ${_m}"
    done
    if [[ "${_gpu}" == "true" ]]; then
      cat <<YAML
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: ${_gpu_count}
              capabilities: ${_caps_yaml}
YAML
    fi
    cat <<YAML

  test:
    build:
      context: .
      dockerfile: Dockerfile
      target: test
      args:
        APT_MIRROR_UBUNTU: \${APT_MIRROR_UBUNTU:-tw.archive.ubuntu.com}
        APT_MIRROR_DEBIAN: \${APT_MIRROR_DEBIAN:-mirror.twds.com.tw}
        USER_NAME: \${USER_NAME}
        USER_GROUP: \${USER_GROUP}
        USER_UID: \${USER_UID}
        USER_GID: \${USER_GID}
    image: \${DOCKER_HUB_USER:-local}/${_name}:test
    profiles:
      - test
YAML
  } > "${_out}"
}

# ════════════════════════════════════════════════════════════════════
# detect_ws_path
#
# Workspace detection strategy (in order):
#   1. If current directory is docker_*, use sibling *_ws (strip prefix)
#   2. Traverse path upward looking for a *_ws component
#   3. Fall back to parent directory
#
# Usage: detect_ws_path <outvar> <base_path>
# ════════════════════════════════════════════════════════════════════
detect_ws_path() {
  local -n _outvar="${1:?"${FUNCNAME[0]}: missing outvar"}"; shift
  local _base_path="${1:?"${FUNCNAME[0]}: missing base_path"}"

  # Normalize base_path to an absolute, symlink-resolved path.
  # Strategies below use _base_path/.. — relative or .. segments would
  # produce surprising results without this step.
  if [[ ! -d "${_base_path}" ]]; then
    printf "[setup] ERROR: detect_ws_path: base_path does not exist: %s\n" \
      "${_base_path}" >&2
    return 1
  fi
  _base_path="$(cd "${_base_path}" && pwd -P)"

  local _dirname=""
  _dirname="$(basename "${_base_path}")"

  # Strategy 1: docker_* directory → look for sibling *_ws
  if [[ "${_dirname}" == docker_* ]]; then
    local _name="${_dirname#docker_}"
    local _parent=""
    _parent="$(dirname "${_base_path}")"
    local _sibling="${_parent}/${_name}_ws"
    if [[ -d "${_sibling}" ]]; then
      _outvar="$(cd "${_sibling}" && pwd -P)"
      return 0
    fi
  fi

  # Strategy 2: traverse path upward looking for *_ws component
  local _check="${_base_path}"
  while [[ "${_check}" != "/" && "${_check}" != "." ]]; do
    if [[ "$(basename "${_check}")" == *_ws && -d "${_check}" ]]; then
      _outvar="$(cd "${_check}" && pwd -P)"
      return 0
    fi
    _check="$(dirname "${_check}")"
  done

  # Strategy 3: fall back to parent directory
  _outvar="$(dirname "${_base_path}")"
}

# ════════════════════════════════════════════════════════════════════
# write_env
#
# Usage: write_env <env_file> <user_name> <user_group> <uid> <gid>
#                  <hardware> <docker_hub_user> <gpu_enabled>
#                  <image_name> <ws_path>
# ════════════════════════════════════════════════════════════════════
write_env() {
  local _env_file="${1:?"${FUNCNAME[0]}: missing env_file"}"; shift
  local _user_name="${1}"; shift
  local _user_group="${1}"; shift
  local _uid="${1}"; shift
  local _gid="${1}"; shift
  local _hardware="${1}"; shift
  local _docker_hub_user="${1}"; shift
  local _gpu_enabled="${1}"; shift
  local _image_name="${1}"; shift
  local _ws_path="${1}"; shift
  local _apt_mirror_ubuntu="${1}"; shift
  local _apt_mirror_debian="${1}"

  local _comment=""
  _comment="$(_msg env_comment)"
  cat > "${_env_file}" << EOF
# Auto-generated by setup.sh on $(date '+%Y-%m-%d %H:%M:%S')
# ${_comment}

# ── Auto-detected ────────────────────────────
USER_NAME=${_user_name}
USER_GROUP=${_user_group}
USER_UID=${_uid}
USER_GID=${_gid}
HARDWARE=${_hardware}
DOCKER_HUB_USER=${_docker_hub_user}
GPU_ENABLED=${_gpu_enabled}
IMAGE_NAME=${_image_name}

# ── Workspace ────────────────────────────────
WS_PATH=${_ws_path}

# ── APT Mirror ───────────────────────────────
APT_MIRROR_UBUNTU=${_apt_mirror_ubuntu}
APT_MIRROR_DEBIAN=${_apt_mirror_debian}
EOF
}

# ════════════════════════════════════════════════════════════════════
# main
#
# Usage: main [--base-path <path>] [--lang <en|zh|zh-CN|ja>]
#   --base-path  override script directory (useful for testing)
#   --lang       set message language (default: en)
# ════════════════════════════════════════════════════════════════════
main() {
  local _base_path=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --base-path)
        _base_path="${2:?"--base-path requires a value"}"
        shift 2
        ;;
      --lang)
        _LANG="${2:?"--lang requires a value (en|zh|zh-CN|ja)"}"
        shift 2
        ;;
      *)
        printf "[setup] %s: %s\n" "$(_msg unknown_arg)" "$1" >&2
        return 1
        ;;
    esac
  done

  if [[ -z "${_base_path}" ]]; then
    # setup.sh is at template/script/docker/setup.sh, repo root is ../../../
    _base_path="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../../.." && pwd -P)"
  fi

  local _env_file="${_base_path}/.env"

  # Load existing .env to preserve manually-set values (e.g. WS_PATH)
  if [[ -f "${_env_file}" ]]; then
    set -o allexport
    # shellcheck disable=SC1090
    source "${_env_file}"
    set +o allexport
  fi

  local user_name="" user_group="" user_uid="" user_gid=""
  local hardware="" docker_hub_user="" gpu_enabled="" image_name=""
  local ws_path="${WS_PATH:-}"
  local apt_mirror_ubuntu="${APT_MIRROR_UBUNTU:-tw.archive.ubuntu.com}"
  local apt_mirror_debian="${APT_MIRROR_DEBIAN:-mirror.twds.com.tw}"

  detect_user_info       user_name user_group user_uid user_gid
  detect_hardware        hardware
  detect_docker_hub_user docker_hub_user
  detect_gpu             gpu_enabled
  BASE_PATH="${_base_path}" detect_image_name image_name "${_base_path}"

  if [[ -z "${ws_path}" ]] || [[ ! -d "${ws_path}" ]]; then
    detect_ws_path ws_path "${_base_path}"
  fi
  ws_path="$(cd "${ws_path}" && pwd -P)"

  # ── Per-repo runtime config (gpu/gui/network/volumes confs) ──
  local gpu_mode="" gpu_count_conf="" gpu_caps=""
  local gui_mode=""
  local net_mode="" ipc_mode="" priv=""
  # shellcheck disable=SC2034  # populated via nameref by _load_volumes_conf
  local -a extra_volumes=()
  _load_gpu_conf     "${_base_path}" gpu_mode gpu_count_conf gpu_caps
  _load_gui_conf     "${_base_path}" gui_mode
  _load_network_conf "${_base_path}" net_mode ipc_mode priv
  _load_volumes_conf "${_base_path}" extra_volumes

  # Resolve final enabled states (mode + detection → true/false)
  local gpu_enabled_eff="" gui_enabled_eff=""
  _resolve_gpu "${gpu_mode}" "${gpu_enabled}" gpu_enabled_eff
  _resolve_gui "${gui_mode}" gui_enabled_eff

  write_env "${_env_file}" \
    "${user_name}" "${user_group}" "${user_uid}" "${user_gid}" \
    "${hardware}" "${docker_hub_user}" "${gpu_enabled}" \
    "${image_name}" "${ws_path}" \
    "${apt_mirror_ubuntu}" "${apt_mirror_debian}"

  # Regenerate compose.yaml (also a derived artifact; confs are source of truth)
  generate_compose_yaml "${_base_path}/compose.yaml" "${image_name}" \
    "${gui_enabled_eff}" "${net_mode}" "${ipc_mode}" "${priv}" \
    "${gpu_enabled_eff}" "${gpu_count_conf}" "${gpu_caps}" \
    extra_volumes

  printf "[setup] %s\n" "$(_msg env_done)"
  printf "[setup] USER=%s (%s:%s)  GPU=%s (%s)  GUI=%s  IMAGE=%s  WS=%s\n" \
    "${user_name}" "${user_uid}" "${user_gid}" \
    "${gpu_enabled_eff}" "${gpu_mode}" "${gui_enabled_eff}" \
    "${image_name}" "${ws_path}"
}

# Guard: only run main when executed directly, not when sourced (for testing)
if [[ "${BASH_SOURCE[0]:-}" == "${0:-}" ]]; then
  main "$@"
fi
