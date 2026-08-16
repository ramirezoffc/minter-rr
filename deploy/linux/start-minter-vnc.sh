#!/usr/bin/env bash
set -Eeuo pipefail

readonly display_number="${MINTER_DISPLAY_NUMBER:-99}"
readonly display=":${display_number}"
readonly screen="${MINTER_SCREEN:-1440x900x24}"
readonly vnc_port="${MINTER_VNC_PORT:-5901}"
readonly vnc_wait="${MINTER_VNC_WAIT:-5}"
readonly vnc_defer="${MINTER_VNC_DEFER:-5}"
readonly vnc_noxdamage="${MINTER_VNC_NOXDAMAGE:-0}"
readonly bind="${MINTER_NOVNC_BIND:-127.0.0.1:3021}"
readonly binary="${MINTER_BINARY:-/opt/minter/minter-desktop}"
readonly password_file="${MINTER_VNC_PASSWORD_FILE:-/var/lib/minter/.vnc/passwd}"
readonly novnc_web="${MINTER_NOVNC_WEB:-/usr/share/novnc}"
readonly software_rendering="${MINTER_SOFTWARE_RENDERING:-0}"
readonly disable_compositing="${MINTER_WEBKIT_DISABLE_COMPOSITING:-0}"
readonly disable_dmabuf="${MINTER_WEBKIT_DISABLE_DMABUF:-1}"

validate_delay() {
  local name="$1"
  local value="$2"
  if [[ ! "$value" =~ ^[0-9]+$ || ${#value} -gt 4 ]] || ((10#$value > 1000)); then
    printf '%s must be an integer from 0 to 1000 (got %q)\n' "$name" "$value" >&2
    return 1
  fi
}

validate_boolean() {
  local name="$1"
  local value="$2"
  case "$value" in
    0|1) ;;
    *)
      printf '%s must be 0 or 1 (got %q)\n' "$name" "$value" >&2
      return 1
      ;;
  esac
}

validate_delay MINTER_VNC_WAIT "$vnc_wait" || exit 1
validate_delay MINTER_VNC_DEFER "$vnc_defer" || exit 1
validate_boolean MINTER_VNC_NOXDAMAGE "$vnc_noxdamage" || exit 1
validate_boolean MINTER_SOFTWARE_RENDERING "$software_rendering" || exit 1
validate_boolean MINTER_WEBKIT_DISABLE_COMPOSITING "$disable_compositing" || exit 1
validate_boolean MINTER_WEBKIT_DISABLE_DMABUF "$disable_dmabuf" || exit 1

export DISPLAY="$display"
export GDK_BACKEND=x11
export NO_AT_BRIDGE=1

if [[ "$software_rendering" == 1 ]]; then
  export LIBGL_ALWAYS_SOFTWARE=1
else
  unset LIBGL_ALWAYS_SOFTWARE
fi
if [[ "$disable_compositing" == 1 ]]; then
  export WEBKIT_DISABLE_COMPOSITING_MODE=1
else
  unset WEBKIT_DISABLE_COMPOSITING_MODE
fi
if [[ "$disable_dmabuf" == 1 ]]; then
  export WEBKIT_DISABLE_DMABUF_RENDERER=1
else
  unset WEBKIT_DISABLE_DMABUF_RENDERER
fi

vnc_args=(
  -display "$display"
  -localhost
  -rfbport "$vnc_port"
  -rfbauth "$password_file"
  -forever
  -shared
  -repeat
  -wait "$vnc_wait"
  -defer "$vnc_defer"
)
if [[ "$vnc_noxdamage" == 1 ]]; then
  vnc_args+=(-noxdamage)
fi

# Tests source this file to inspect the resolved configuration without starting
# Xvfb, x11vnc, websockify, or the application.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0
fi

children=()

cleanup() {
  trap - EXIT INT TERM
  if ((${#children[@]})); then
    kill "${children[@]}" 2>/dev/null || true
    wait "${children[@]}" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

for required in "$binary" "$password_file" "$novnc_web/vnc.html"; do
  if [[ ! -e "$required" ]]; then
    echo "required path is missing: $required" >&2
    exit 1
  fi
done

Xvfb "$display" -screen 0 "$screen" -nolisten tcp -dpi 96 -noreset &
children+=("$!")

for _ in {1..100}; do
  if xdpyinfo -display "$display" >/dev/null 2>&1; then
    break
  fi
  sleep 0.05
done
if ! xdpyinfo -display "$display" >/dev/null 2>&1; then
  echo "Xvfb did not become ready on $display" >&2
  exit 1
fi

openbox --sm-disable &
children+=("$!")

x11vnc "${vnc_args[@]}" &
children+=("$!")

websockify --web "$novnc_web" "$bind" "127.0.0.1:${vnc_port}" &
children+=("$!")

"$binary" &
children+=("$!")

# Any component exiting makes systemd restart the complete, coherent session.
wait -n "${children[@]}"
