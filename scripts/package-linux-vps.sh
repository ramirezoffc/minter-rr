#!/usr/bin/env bash
set -Eeuo pipefail

version="${1:-}"
binary="${2:-}"
output_dir="${3:-dist/linux}"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]; then
  echo "invalid release version: $version" >&2
  exit 1
fi
if [[ ! -f "$binary" || ! -x "$binary" ]]; then
  echo "Linux release binary is missing or not executable: $binary" >&2
  exit 1
fi

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_root="$(cd -- "$script_dir/.." && pwd)"
readonly stage_name="minter-desktop-$version-linux-x64"
readonly archive_name="MINTER_${version}_linux-vps-x64.tar.gz"

for required in deploy/linux/start-minter-vnc.sh deploy/linux/minter-vps.service; do
  [[ -f "$repo_root/$required" ]] || {
    echo "required VPS release file is missing: $required" >&2
    exit 1
  }
done

mkdir -p "$output_dir"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
stage="$staging/$stage_name"
mkdir -p "$stage"

install -m 0755 "$binary" "$stage/minter-desktop"
install -m 0755 "$repo_root/deploy/linux/start-minter-vnc.sh" "$stage/start-minter-vnc.sh"
install -m 0644 "$repo_root/deploy/linux/minter-vps.service" "$stage/minter-vps.service"

archive="$output_dir/$archive_name"
rm -f "$archive"
if tar --version 2>/dev/null | grep -q 'GNU tar'; then
  tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
    -cf - -C "$staging" "$stage_name" | gzip -n > "$archive"
else
  COPYFILE_DISABLE=1 tar -cf - -C "$staging" "$stage_name" | gzip -n > "$archive"
fi

expected="$stage_name/minter-desktop
$stage_name/minter-vps.service
$stage_name/start-minter-vnc.sh"
actual="$(tar -tzf "$archive" | sed '/\/$/d' | LC_ALL=C sort)"
if [[ "$actual" != "$expected" ]]; then
  echo "unexpected Linux VPS archive contents:" >&2
  printf '%s\n' "$actual" >&2
  exit 1
fi

echo "Verified Linux VPS archive: $archive"
printf '%s\n' "$actual"
