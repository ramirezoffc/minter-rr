import assert from "node:assert/strict";
import { appendFileSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptsDir = dirname(fileURLToPath(import.meta.url));
const root = resolve(scriptsDir, "..");

function read(path) {
  return readFileSync(join(root, path), "utf8");
}

function cargoVersion(path) {
  const version = read(path).match(/^version\s*=\s*"([^"]+)"/m)?.[1];
  assert.ok(version, `missing Cargo package version in ${path}`);
  return version;
}

function lockedCargoVersion(name) {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = read("Cargo.lock").match(
    new RegExp(`\\[\\[package\\]\\]\\nname = "${escaped}"\\nversion = "([^"]+)"`),
  );
  assert.ok(match, `missing ${name} in Cargo.lock`);
  return match[1];
}

const coreVersion = cargoVersion("crates/minter-core/Cargo.toml");
const desktopVersion = cargoVersion("crates/minter-desktop/src-tauri/Cargo.toml");
const tauri = JSON.parse(read("crates/minter-desktop/src-tauri/tauri.conf.json"));
const packageJson = JSON.parse(read("crates/minter-desktop/package.json"));
const packageLock = JSON.parse(read("crates/minter-desktop/package-lock.json"));

const version = desktopVersion;
const sources = {
  "minter-core Cargo.toml": coreVersion,
  "minter-desktop Cargo.toml": desktopVersion,
  "minter-core Cargo.lock": lockedCargoVersion("minter-core"),
  "minter-desktop Cargo.lock": lockedCargoVersion("minter-desktop"),
  "tauri.conf.json": tauri.version,
  "package.json": packageJson.version,
  "package-lock.json": packageLock.version,
  "package-lock.json root package": packageLock.packages?.[""]?.version,
};

assert.match(
  version,
  /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$/,
  "application version is not valid SemVer",
);
for (const [source, sourceVersion] of Object.entries(sources)) {
  assert.equal(sourceVersion, version, `${source} version does not match ${version}`);
}

assert.equal(tauri.productName, "MINTER", "release productName changed");
assert.equal(tauri.mainBinaryName, "MINTER", "release binary name changed");
assert.equal(tauri.identifier, "com.minter.desktop", "release identifier changed");

const expectedTag = `v${version}`;
const releaseTag = (process.env.RELEASE_TAG ?? "").trim();
if (releaseTag) {
  assert.match(releaseTag, /^v\d+\.\d+\.\d+(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$/, "release tag must be v-prefixed SemVer");
  assert.equal(releaseTag, expectedTag, `tag ${releaseTag} does not match project version ${version}`);
}

const metadata = {
  version,
  expected_tag: expectedTag,
  prerelease: String(version.includes("-")),
  windows_setup: `MINTER_${version}_x64-setup.exe`,
  windows_portable: `MINTER_${version}_x64-portable.zip`,
  linux_vps: `MINTER_${version}_linux-vps-x64.tar.gz`,
};

if (process.argv.includes("--github-output")) {
  assert.ok(process.env.GITHUB_OUTPUT, "GITHUB_OUTPUT is required with --github-output");
  appendFileSync(
    process.env.GITHUB_OUTPUT,
    `${Object.entries(metadata).map(([key, value]) => `${key}=${value}`).join("\n")}\n`,
    "utf8",
  );
}

console.log(`Release metadata is consistent for ${metadata.expected_tag}.`);
console.log(`Windows NSIS: ${metadata.windows_setup}`);
console.log(`Windows portable: ${metadata.windows_portable}`);
console.log(`Linux VPS: ${metadata.linux_vps}`);
