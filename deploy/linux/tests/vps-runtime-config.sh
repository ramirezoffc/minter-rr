#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LAUNCHER="$SCRIPT_DIR/../start-minter-vnc.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_equal() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  [[ "$actual" == "$expected" ]] || fail "$label: got $actual, expected $expected"
}

has_vnc_arg() {
  local wanted="$1"
  local arg
  for arg in "${vnc_args[@]}"; do
    [[ "$arg" == "$wanted" ]] && return 0
  done
  return 1
}

vnc_arg_value() {
  local wanted="$1"
  local i
  for ((i = 0; i < ${#vnc_args[@]} - 1; i++)); do
    if [[ "${vnc_args[$i]}" == "$wanted" ]]; then
      printf '%s' "${vnc_args[$((i + 1))]}"
      return 0
    fi
  done
  return 1
}

clear_runtime_environment() {
  unset MINTER_VNC_WAIT MINTER_VNC_DEFER MINTER_VNC_NOXDAMAGE
  unset MINTER_SOFTWARE_RENDERING MINTER_WEBKIT_DISABLE_COMPOSITING
  unset MINTER_WEBKIT_DISABLE_DMABUF MINTER_SCREEN
  unset LIBGL_ALWAYS_SOFTWARE WEBKIT_DISABLE_COMPOSITING_MODE
  unset WEBKIT_DISABLE_DMABUF_RENDERER
}

test_default_profile() (
  clear_runtime_environment
  # shellcheck source=/dev/null
  . "$LAUNCHER"

  assert_equal "$(vnc_arg_value -wait)" "5" "default wait"
  assert_equal "$(vnc_arg_value -defer)" "5" "default defer"
  has_vnc_arg -noxdamage && fail "default profile enables -noxdamage"
  [[ -z "${LIBGL_ALWAYS_SOFTWARE+x}" ]] || fail "default profile forces software rendering"
  [[ -z "${WEBKIT_DISABLE_COMPOSITING_MODE+x}" ]] || fail "default profile disables compositing"
  assert_equal "$WEBKIT_DISABLE_DMABUF_RENDERER" "1" "default DMABUF workaround"
  assert_equal "$screen" "1440x900x24" "default screen"
  has_vnc_arg -localhost || fail "x11vnc is not restricted to localhost"
  assert_equal "$bind" "127.0.0.1:3021" "default noVNC bind"
)

test_conservative_profile() (
  clear_runtime_environment
  export MINTER_VNC_NOXDAMAGE=1
  export MINTER_SOFTWARE_RENDERING=1
  export MINTER_WEBKIT_DISABLE_COMPOSITING=1
  # shellcheck source=/dev/null
  . "$LAUNCHER"

  has_vnc_arg -noxdamage || fail "conservative profile is missing -noxdamage"
  assert_equal "$LIBGL_ALWAYS_SOFTWARE" "1" "software rendering fallback"
  assert_equal "$WEBKIT_DISABLE_COMPOSITING_MODE" "1" "compositing fallback"
  assert_equal "$WEBKIT_DISABLE_DMABUF_RENDERER" "1" "conservative DMABUF workaround"
)

test_custom_profile() (
  clear_runtime_environment
  export MINTER_VNC_WAIT=17
  export MINTER_VNC_DEFER=23
  export MINTER_WEBKIT_DISABLE_DMABUF=0
  # shellcheck source=/dev/null
  . "$LAUNCHER"

  assert_equal "$(vnc_arg_value -wait)" "17" "custom wait"
  assert_equal "$(vnc_arg_value -defer)" "23" "custom defer"
  [[ -z "${WEBKIT_DISABLE_DMABUF_RENDERER+x}" ]] || fail "DMABUF workaround cannot be disabled"
)

assert_rejected() {
  local name="$1"
  local value="$2"
  if (
    clear_runtime_environment
    export "$name=$value"
    # shellcheck source=/dev/null
    . "$LAUNCHER"
  ) >/dev/null 2>&1; then
    fail "$name=$value was accepted"
  fi
}

test_default_profile
test_conservative_profile
test_custom_profile
assert_rejected MINTER_VNC_WAIT invalid
assert_rejected MINTER_VNC_DEFER 1001
assert_rejected MINTER_SOFTWARE_RENDERING true

printf 'PASS: Linux VPS runtime configuration profiles\n'
