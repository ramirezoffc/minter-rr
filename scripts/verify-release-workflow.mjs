import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptsDir = dirname(fileURLToPath(import.meta.url));
const root = resolve(scriptsDir, "..");
const workflow = readFileSync(join(root, ".github", "workflows", "release.yml"), "utf8");

assert.match(workflow, /^  workflow_dispatch:\s*$/m, "manual dry-run trigger is missing");
assert.match(workflow, /^      - "v\*"\s*$/m, "tag release trigger is missing");
assert.match(workflow, /^permissions:\n  contents: read$/m, "workflow default permission must be read-only");
assert.match(workflow, /^    runs-on: windows-latest$/m, "native Windows release job is missing");
assert.match(workflow, /^    runs-on: ubuntu-22\.04$/m, "compatible native Linux release job is missing");
assert.doesNotMatch(workflow, /softprops\/action-gh-release/, "release publication must not use the legacy third-party action");

const publish = workflow.match(/^  publish:\n([\s\S]+)$/m)?.[0];
assert.ok(publish, "publish job is missing");
assert.match(
  publish,
  /^    if: github\.event_name == 'push' && startsWith\(github\.ref, 'refs\/tags\/v'\)$/m,
  "publish job must run only for a v-prefixed tag push",
);
assert.match(publish, /^    needs: \[metadata, finalize\]$/m, "publish must require finalized native artifacts");
assert.match(publish, /^    permissions:\n      contents: write$/m, "only publish should receive release write permission");
assert.match(publish, /gh "\$\{args\[@\]\}"/, "GitHub CLI release publication is missing");
assert.match(publish, /args\+=\(--prerelease\)/, "SemVer prereleases must be marked as GitHub prereleases");

console.log("Release workflow modes and permissions are valid.");
