#!/usr/bin/env bash
set -Eeuo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd)"
readonly version="$(
  node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).version)' \
    "$repo_root/crates/minter-desktop/src-tauri/tauri.conf.json"
)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fake_binary="$tmp/minter-desktop"
printf '#!/usr/bin/env bash\nexit 0\n' > "$fake_binary"
chmod 0755 "$fake_binary"

bash "$repo_root/scripts/package-linux-vps.sh" "$version" "$fake_binary" "$tmp/assets"
linux_asset="$tmp/assets/MINTER_${version}_linux-vps-x64.tar.gz"
[[ -s "$linux_asset" ]] || { echo "Linux VPS package test did not create its artifact" >&2; exit 1; }

printf 'test NSIS bytes\n' > "$tmp/assets/MINTER_${version}_x64-setup.exe"
printf 'test portable bytes\n' > "$tmp/assets/MINTER_${version}_x64-portable.zip"
bash "$repo_root/scripts/finalize-release-assets.sh" "$version" "$tmp/assets"

[[ "$(wc -l < "$tmp/assets/SHA256SUMS.txt" | tr -d ' ')" == "3" ]] || {
  echo "SHA256SUMS.txt must contain exactly three entries" >&2
  exit 1
}

RELEASE_TAG="v$version" node "$repo_root/scripts/verify-release-metadata.mjs" >/dev/null
if RELEASE_TAG="v999.0.0" node "$repo_root/scripts/verify-release-metadata.mjs" >/dev/null 2>&1; then
  echo "mismatched release tag was accepted" >&2
  exit 1
fi
node "$repo_root/scripts/verify-release-workflow.mjs" >/dev/null

printf 'PASS: release metadata, artifact naming, Linux layout and checksums\n'
