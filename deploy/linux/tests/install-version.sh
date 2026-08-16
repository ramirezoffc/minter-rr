#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER="$SCRIPT_DIR/../install.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

release_assignment="$(
  grep -F 'MINTER_RELEASE_VERSION="${MINTER_VERSION:-latest}"' "$INSTALLER" || true
)"
[ "$release_assignment" = 'MINTER_RELEASE_VERSION="${MINTER_VERSION:-latest}"' ] || \
  fail "installer release selector assignment is missing or duplicated"

if grep -Eq '\$(\{VERSION\}|VERSION([^_[:alnum:]]|$))' "$INSTALLER"; then
  fail "installer still expands the generic VERSION variable"
fi

grep -Fq 'releases/tags/$MINTER_RELEASE_VERSION' "$INSTALLER" || \
  fail "tag release URL does not use MINTER_RELEASE_VERSION"

fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT
os_release="$fixture_dir/os-release"
printf '%s\n' 'VERSION="24.04.4 LTS (Noble Numbat)"' > "$os_release"

assert_release_selector() (
  requested="$1"
  expected="$2"
  unset MINTER_VERSION MINTER_RELEASE_VERSION VERSION

  if [ "$requested" != "__unset__" ]; then
    MINTER_VERSION="$requested"
  fi

  eval "$release_assignment"
  # shellcheck source=/dev/null
  . "$os_release"

  [ "$MINTER_RELEASE_VERSION" = "$expected" ] || \
    fail "MINTER_VERSION=$requested resolved to $MINTER_RELEASE_VERSION, expected $expected"
)

assert_release_selector "__unset__" "latest"
assert_release_selector "v0.2.2" "v0.2.2"

printf 'PASS: MINTER release selector survives os-release VERSION\n'
