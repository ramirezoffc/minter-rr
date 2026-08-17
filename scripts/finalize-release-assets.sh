#!/usr/bin/env bash
set -Eeuo pipefail

version="${1:-}"
asset_dir="${2:-dist}"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]; then
  echo "invalid release version: $version" >&2
  exit 1
fi
[[ -d "$asset_dir" ]] || { echo "release asset directory is missing: $asset_dir" >&2; exit 1; }

assets=(
  "MINTER_${version}_x64-setup.exe"
  "MINTER_${version}_x64-portable.zip"
  "MINTER_${version}_linux-vps-x64.tar.gz"
)

for asset in "${assets[@]}"; do
  [[ -s "$asset_dir/$asset" ]] || {
    echo "required release asset is missing or empty: $asset" >&2
    exit 1
  }
done

actual_files="$(
  find "$asset_dir" -maxdepth 1 -type f ! -name SHA256SUMS.txt -exec basename {} \; | LC_ALL=C sort
)"
expected_files="$(printf '%s\n' "${assets[@]}" | LC_ALL=C sort)"
if [[ "$actual_files" != "$expected_files" ]]; then
  echo "release staging contains unexpected files:" >&2
  printf '%s\n' "$actual_files" | sed 's/^/  /' >&2
  exit 1
fi

checksum_file="$asset_dir/SHA256SUMS.txt"
: > "$checksum_file"
for asset in "${assets[@]}"; do
  if command -v sha256sum >/dev/null 2>&1; then
    hash="$(sha256sum "$asset_dir/$asset" | awk '{print $1}')"
  else
    hash="$(shasum -a 256 "$asset_dir/$asset" | awk '{print $1}')"
  fi
  printf '%s  %s\n' "$hash" "$asset" >> "$checksum_file"
done

while read -r expected asset; do
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$asset_dir/$asset" | awk '{print $1}')"
  else
    actual="$(shasum -a 256 "$asset_dir/$asset" | awk '{print $1}')"
  fi
  [[ "$actual" == "$expected" ]] || {
    echo "checksum verification failed for $asset" >&2
    exit 1
  }
done < "$checksum_file"

echo "Verified release assets and wrote $checksum_file"
cat "$checksum_file"
