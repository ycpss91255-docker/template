#!/usr/bin/env bats
#
# Tests for generate_compose_yaml() in script/docker/setup.sh.
# Verifies conditional inclusion of GPU deploy block, GUI env/volumes,
# extra volumes, and that baseline structural elements always appear.

bats_require_minimum_version 1.5.0

setup() {
  load "${BATS_TEST_DIRNAME}/test_helper"

  # shellcheck disable=SC1091
  source /source/script/docker/setup.sh

  TEMP_DIR="$(mktemp -d)"
  COMPOSE_OUT="${TEMP_DIR}/compose.yaml"
}

teardown() {
  rm -rf "${TEMP_DIR}"
}

# ════════════════════════════════════════════════════════════════════
# Baseline — structural elements that always appear
# ════════════════════════════════════════════════════════════════════

@test "generate_compose_yaml outputs AUTO-GENERATED header" {
  local _extras=()
  generate_compose_yaml "${COMPOSE_OUT}" "myrepo" \
    "false" "host" "host" "true" \
    "false" "0" "gpu" _extras
  run head -n 1 "${COMPOSE_OUT}"
  assert_output --partial "AUTO-GENERATED"
}

@test "generate_compose_yaml always emits workspace volume" {
  local _extras=()
  generate_compose_yaml "${COMPOSE_OUT}" "myrepo" \
    "false" "host" "host" "true" \
    "false" "0" "gpu" _extras
  run grep -F '${WS_PATH}:/home/${USER_NAME}/work' "${COMPOSE_OUT}"
  assert_success
}

@test "generate_compose_yaml always emits /dev:/dev passthrough" {
  local _extras=()
  generate_compose_yaml "${COMPOSE_OUT}" "myrepo" \
    "false" "host" "host" "true" \
    "false" "0" "gpu" _extras
  run grep -F '/dev:/dev' "${COMPOSE_OUT}"
  assert_success
}

@test "generate_compose_yaml always emits network_mode/ipc/privileged env vars" {
  local _extras=()
  generate_compose_yaml "${COMPOSE_OUT}" "myrepo" \
    "false" "host" "host" "true" \
    "false" "0" "gpu" _extras
  run grep 'network_mode: ${NETWORK_MODE:-host}' "${COMPOSE_OUT}"
  assert_success
  run grep 'ipc: ${IPC_MODE:-host}' "${COMPOSE_OUT}"
  assert_success
  run grep 'privileged: ${PRIVILEGED:-true}' "${COMPOSE_OUT}"
  assert_success
}

@test "generate_compose_yaml always emits test service with profiles: [test]" {
  local _extras=()
  generate_compose_yaml "${COMPOSE_OUT}" "myrepo" \
    "false" "host" "host" "true" \
    "false" "0" "gpu" _extras
  run grep -B1 '^    profiles:' "${COMPOSE_OUT}"
  assert_success
  run grep -F -- '- test' "${COMPOSE_OUT}"
  assert_success
}

@test "generate_compose_yaml image field contains repo name" {
  local _extras=()
  generate_compose_yaml "${COMPOSE_OUT}" "myrepo" \
    "false" "host" "host" "true" \
    "false" "0" "gpu" _extras
  run grep 'local}/myrepo:devel' "${COMPOSE_OUT}"
  assert_success
  run grep 'local}/myrepo:test' "${COMPOSE_OUT}"
  assert_success
}

# ════════════════════════════════════════════════════════════════════
# GPU block — conditional
# ════════════════════════════════════════════════════════════════════

@test "generate_compose_yaml GPU enabled => deploy block present" {
  local _extras=()
  generate_compose_yaml "${COMPOSE_OUT}" "myrepo" \
    "false" "host" "host" "true" \
    "true" "all" "gpu" _extras
  run grep -F 'deploy:' "${COMPOSE_OUT}"
  assert_success
  run grep -F 'driver: nvidia' "${COMPOSE_OUT}"
  assert_success
  run grep -F 'count: all' "${COMPOSE_OUT}"
  assert_success
}

@test "generate_compose_yaml GPU disabled => no deploy block" {
  local _extras=()
  generate_compose_yaml "${COMPOSE_OUT}" "myrepo" \
    "false" "host" "host" "true" \
    "false" "0" "gpu" _extras
  run grep -F 'deploy:' "${COMPOSE_OUT}"
  assert_failure
  run grep -F 'driver: nvidia' "${COMPOSE_OUT}"
  assert_failure
}

@test "generate_compose_yaml GPU with specific count and capabilities" {
  local _extras=()
  generate_compose_yaml "${COMPOSE_OUT}" "myrepo" \
    "false" "host" "host" "true" \
    "true" "2" "compute utility" _extras
  run grep -F 'count: 2' "${COMPOSE_OUT}"
  assert_success
  run grep -F 'capabilities: [compute, utility]' "${COMPOSE_OUT}"
  assert_success
}

# ════════════════════════════════════════════════════════════════════
# GUI block — conditional
# ════════════════════════════════════════════════════════════════════

@test "generate_compose_yaml GUI enabled => DISPLAY env + X11 volumes present" {
  local _extras=()
  generate_compose_yaml "${COMPOSE_OUT}" "myrepo" \
    "true" "host" "host" "true" \
    "false" "0" "gpu" _extras
  run grep -F 'DISPLAY=${DISPLAY' "${COMPOSE_OUT}"
  assert_success
  run grep -F 'WAYLAND_DISPLAY' "${COMPOSE_OUT}"
  assert_success
  run grep -F '/tmp/.X11-unix:/tmp/.X11-unix:ro' "${COMPOSE_OUT}"
  assert_success
  run grep -F 'XAUTHORITY' "${COMPOSE_OUT}"
  assert_success
}

@test "generate_compose_yaml GUI disabled => no DISPLAY env + no X11 volumes" {
  local _extras=()
  generate_compose_yaml "${COMPOSE_OUT}" "myrepo" \
    "false" "host" "host" "true" \
    "false" "0" "gpu" _extras
  run grep -F 'DISPLAY=${DISPLAY' "${COMPOSE_OUT}"
  assert_failure
  run grep -F '/tmp/.X11-unix:/tmp/.X11-unix:ro' "${COMPOSE_OUT}"
  assert_failure
}

# ════════════════════════════════════════════════════════════════════
# Extra volumes — from volumes.conf
# ════════════════════════════════════════════════════════════════════

@test "generate_compose_yaml extra volumes => appended after baseline" {
  local _extras=("/data:/data" "/etc/machine-id:/etc/machine-id:ro")
  generate_compose_yaml "${COMPOSE_OUT}" "myrepo" \
    "false" "host" "host" "true" \
    "false" "0" "gpu" _extras
  run grep -F -- '- /data:/data' "${COMPOSE_OUT}"
  assert_success
  run grep -F -- '- /etc/machine-id:/etc/machine-id:ro' "${COMPOSE_OUT}"
  assert_success
}

@test "generate_compose_yaml empty extras => no extra volume lines" {
  local _extras=()
  generate_compose_yaml "${COMPOSE_OUT}" "myrepo" \
    "false" "host" "host" "true" \
    "false" "0" "gpu" _extras
  run grep -F -- '- /data:' "${COMPOSE_OUT}"
  assert_failure
}

# ════════════════════════════════════════════════════════════════════
# Fully loaded — everything enabled
# ════════════════════════════════════════════════════════════════════

@test "generate_compose_yaml with GUI+GPU+extras => all sections present" {
  local _extras=("/srv:/srv")
  generate_compose_yaml "${COMPOSE_OUT}" "isaac_sim" \
    "true" "host" "host" "true" \
    "true" "all" "gpu" _extras
  # GUI
  run grep -F 'DISPLAY=${DISPLAY' "${COMPOSE_OUT}"
  assert_success
  # GPU
  run grep -F 'driver: nvidia' "${COMPOSE_OUT}"
  assert_success
  # Extra volume
  run grep -F -- '- /srv:/srv' "${COMPOSE_OUT}"
  assert_success
  # Image name
  run grep -F 'local}/isaac_sim:devel' "${COMPOSE_OUT}"
  assert_success
}
