# Windows packaging

Windows beta packages are built natively on Windows x64 with Tauri 2. The build
machine needs the normal Tauri development prerequisites; end users do not need
Rust, Node.js, or build tools.

From `crates/minter-desktop`:

```powershell
npm ci
npm run verify:windows-packaging
npm run build:windows
npm run package:windows:portable
```

Expected outputs for the current version are:

```text
../../target/x86_64-pc-windows-msvc/release/bundle/nsis/MINTER_0.3.0-beta.1_x64-setup.exe
../../dist/windows/MINTER_0.3.0-beta.1_x64-portable.zip
```

The NSIS installer is a current-user install and uses Tauri's WebView2 download
bootstrapper when a compatible runtime is missing. Beta packages are unsigned,
so Windows may show a Microsoft Defender SmartScreen reputation warning.

The portable archive contains only `MINTER.exe`. Static UI assets are embedded by
the Tauri build. Runtime data such as `keys.vault`, `config.json`, `.env`, proxies,
tasks, logs, and results must never be added to either package.

Packaging does not migrate or delete user data. Fresh installations use the
existing `%APPDATA%\MINTER` runtime-path behavior; legacy data beside a portable
executable remains supported by the application's existing resolver.
