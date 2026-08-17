# Release pipeline

The `Windows and VPS beta release` workflow builds the Windows x64 NSIS
installer, the Windows x64 portable archive, and the Linux VPS x64 package from
the same commit.

## Production packaging dry-run

After the release changes are merged to `main`:

1. Open **Actions → Windows and VPS beta release**.
2. Select **Run workflow** on `main`.
3. Wait for the Windows, Linux, and finalize jobs to pass.
4. Download the `release-candidate-<version>-<run-id>` workflow artifact.

The manual workflow never creates a GitHub Release. Its consolidated artifact
contains exactly:

```text
MINTER_<version>_x64-setup.exe
MINTER_<version>_x64-portable.zip
MINTER_<version>_linux-vps-x64.tar.gz
SHA256SUMS.txt
```

Use these files for clean Windows and VPS acceptance testing before creating a
tag.

## Tag publication

The release tag must be `v` followed by the exact version in the project
metadata. A mismatch fails before native packaging begins. For example, project
version `0.3.0-beta.1` accepts only:

```text
v0.3.0-beta.1
```

A tag push runs the same native packaging and validation jobs as the manual
dry-run. Only after both builds and checksum validation pass does the final job
create the GitHub Release. Versions with a SemVer prerelease suffix are marked
as GitHub prereleases.

Do not create or push a release tag until the manual production packaging run
and clean-machine acceptance tests have passed.
