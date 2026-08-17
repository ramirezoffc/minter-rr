import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptsDir = dirname(fileURLToPath(import.meta.url));
const root = resolve(scriptsDir, "..");
const desktopDir = join(root, "crates", "minter-desktop");
const tauriDir = join(desktopDir, "src-tauri");

const config = JSON.parse(readFileSync(join(tauriDir, "tauri.conf.json"), "utf8"));
const packageJson = JSON.parse(readFileSync(join(desktopDir, "package.json"), "utf8"));
const packageLock = JSON.parse(readFileSync(join(desktopDir, "package-lock.json"), "utf8"));
const cargoToml = readFileSync(join(tauriDir, "Cargo.toml"), "utf8");
const cargoVersion = cargoToml.match(/^version\s*=\s*"([^"]+)"/m)?.[1];

assert.equal(config.productName, "MINTER", "productName must match the public Windows product name");
assert.equal(config.mainBinaryName, "MINTER", "the packaged executable must be MINTER.exe");
assert.equal(config.identifier, "com.minter.desktop", "the stable installer identifier changed");
assert.deepEqual(config.bundle.targets, ["nsis"], "Windows packaging must use only NSIS");
assert.equal(config.bundle.windows.nsis.installMode, "currentUser", "NSIS must not require elevation");
assert.equal(
  config.bundle.windows.webviewInstallMode.type,
  "downloadBootstrapper",
  "WebView2 must use the standard download bootstrapper",
);
assert.equal(config.version, cargoVersion, "Tauri and Cargo versions must match");
assert.equal(packageJson.version, cargoVersion, "npm and Cargo versions must match");
assert.equal(packageLock.version, cargoVersion, "npm lockfile and Cargo versions must match");
assert.equal(
  packageLock.packages?.[""]?.version,
  cargoVersion,
  "npm lockfile root package and Cargo versions must match",
);
assert.equal(packageJson.private, true, "the desktop npm package must remain private");
assert.ok(
  packageJson.scripts["build:windows"].includes(
    "--bundles nsis --target x86_64-pc-windows-msvc",
  ),
  "build:windows must produce an x64 NSIS installer",
);
assert.ok(
  packageJson.scripts["package:windows:portable"],
  "the portable packaging command is missing",
);

for (const icon of config.bundle.icon) {
  assert.ok(existsSync(join(tauriDir, icon)), `missing bundle icon: ${icon}`);
}

const frontendDir = resolve(tauriDir, config.build.frontendDist);
assert.ok(existsSync(join(frontendDir, "index.html")), "frontendDist does not contain index.html");
assert.equal(
  config.bundle.windows.nsis.installerHooks,
  undefined,
  "custom NSIS hooks require a separate user-data safety review",
);
assert.equal(
  config.bundle.resources,
  undefined,
  "release bundles must not include unreviewed external resources",
);

console.log("Windows packaging configuration is valid.");
