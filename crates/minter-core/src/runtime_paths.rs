//! Runtime data paths shared by the core and desktop layers.
//!
//! A process resolves one root and derives every managed path from it. Windows
//! keeps existing cwd-based and portable installations in place; fresh installs
//! use `%APPDATA%\MINTER`. Other platforms retain the historical cwd behavior.

use std::fmt;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;

const LEGACY_MARKERS: &[&str] = &[
    "keys.vault",
    "config.json",
    "tasks.json",
    "wallet_meta.json",
    "runs_history.json",
    "auth_cache.bin",
    "proxies.txt",
];

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RuntimePaths {
    root: PathBuf,
}

impl RuntimePaths {
    pub fn from_root(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn vault(&self) -> PathBuf {
        self.root.join("keys.vault")
    }

    pub fn config(&self) -> PathBuf {
        self.root.join("config.json")
    }

    pub fn legacy_env(&self) -> PathBuf {
        self.root.join(".env")
    }

    pub fn auth_cache(&self) -> PathBuf {
        self.root.join("auth_cache.bin")
    }

    pub fn proxies(&self) -> PathBuf {
        self.root.join("proxies.txt")
    }

    pub fn tasks(&self) -> PathBuf {
        self.root.join("tasks.json")
    }

    pub fn wallet_meta(&self) -> PathBuf {
        self.root.join("wallet_meta.json")
    }

    pub fn runs_history(&self) -> PathBuf {
        self.root.join("runs_history.json")
    }

    pub fn logs(&self) -> PathBuf {
        self.root.join("logs")
    }

    pub fn results(&self) -> PathBuf {
        self.root.join("results")
    }

    pub fn imports(&self) -> PathBuf {
        self.root.join("imports")
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RuntimePathError(String);

impl RuntimePathError {
    fn new(message: impl Into<String>) -> Self {
        Self(message.into())
    }
}

impl fmt::Display for RuntimePathError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for RuntimePathError {}

/// Detect an existing installation without treating a generic `.env` as a
/// MINTER installation. Any one product-specific marker is sufficient.
fn has_legacy_data(dir: &Path) -> bool {
    LEGACY_MARKERS.iter().any(|name| dir.join(name).is_file())
}

/// Pure Windows resolver used by production and unit tests.
///
/// Precedence is legacy cwd, portable executable directory, then a fresh
/// `%APPDATA%\MINTER` root. No files are copied or moved.
pub fn resolve_windows(
    cwd: Option<&Path>,
    exe_dir: Option<&Path>,
    roaming_app_data: Option<&Path>,
) -> Result<RuntimePaths, RuntimePathError> {
    if let Some(cwd) = cwd.filter(|dir| has_legacy_data(dir)) {
        return Ok(RuntimePaths::from_root(cwd));
    }
    if let Some(exe_dir) = exe_dir.filter(|dir| has_legacy_data(dir)) {
        return Ok(RuntimePaths::from_root(exe_dir));
    }
    let app_data = roaming_app_data.ok_or_else(|| {
        RuntimePathError::new(
            "Windows roaming application-data directory is unavailable and no legacy MINTER data was found",
        )
    })?;
    Ok(RuntimePaths::from_root(app_data.join("MINTER")))
}

/// Preserve the historical cwd root on Linux (including the VPS service) and
/// macOS until their desktop storage semantics are addressed separately.
pub fn resolve_non_windows(cwd: Option<&Path>) -> Result<RuntimePaths, RuntimePathError> {
    cwd.map(RuntimePaths::from_root)
        .ok_or_else(|| RuntimePathError::new("cannot resolve working directory"))
}

pub fn resolve_current_process() -> Result<RuntimePaths, RuntimePathError> {
    #[cfg(target_os = "windows")]
    {
        let cwd = std::env::current_dir().ok();
        let exe_dir = std::env::current_exe()
            .ok()
            .and_then(|path| path.parent().map(Path::to_path_buf));
        let app_data = std::env::var_os("APPDATA").map(PathBuf::from);
        resolve_windows(cwd.as_deref(), exe_dir.as_deref(), app_data.as_deref())
    }

    #[cfg(not(target_os = "windows"))]
    {
        let cwd = std::env::current_dir()
            .map_err(|e| RuntimePathError::new(format!("cannot resolve working directory: {e}")))?;
        resolve_non_windows(Some(&cwd))
    }
}

/// Resolve once per process so all subsystems use exactly the same root.
pub fn active() -> &'static RuntimePaths {
    static ACTIVE: OnceLock<RuntimePaths> = OnceLock::new();
    ACTIVE.get_or_init(|| {
        resolve_current_process().unwrap_or_else(|error| {
            let fallback = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            eprintln!(
                "MINTER runtime path resolution failed ({error}); using {}",
                fallback.display()
            );
            RuntimePaths::from_root(fallback)
        })
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::vault::Vault;
    use std::sync::atomic::{AtomicU64, Ordering};

    struct TestTree {
        root: PathBuf,
    }

    impl TestTree {
        fn new(label: &str) -> Self {
            static COUNTER: AtomicU64 = AtomicU64::new(0);
            let sequence = COUNTER.fetch_add(1, Ordering::Relaxed);
            let root = std::env::temp_dir().join(format!(
                "minter_runtime_paths_{}_{}_{}",
                std::process::id(),
                sequence,
                label
            ));
            let _ = std::fs::remove_dir_all(&root);
            std::fs::create_dir_all(&root).unwrap();
            Self { root }
        }

        fn dir(&self, name: &str) -> PathBuf {
            let dir = self.root.join(name);
            std::fs::create_dir_all(&dir).unwrap();
            dir
        }
    }

    impl Drop for TestTree {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.root);
        }
    }

    fn touch(path: impl AsRef<Path>) {
        std::fs::write(path, b"test marker").unwrap();
    }

    #[test]
    fn legacy_cwd_vault_wins() {
        let tree = TestTree::new("cwd_vault");
        let cwd = tree.dir("cwd");
        let exe = tree.dir("exe");
        let app_data = tree.dir("appdata");
        touch(cwd.join("keys.vault"));

        let paths = resolve_windows(Some(&cwd), Some(&exe), Some(&app_data)).unwrap();
        assert_eq!(paths.root(), cwd);
    }

    #[test]
    fn legacy_cwd_config_wins() {
        let tree = TestTree::new("cwd_config");
        let cwd = tree.dir("cwd");
        let exe = tree.dir("exe");
        let app_data = tree.dir("appdata");
        touch(cwd.join("config.json"));

        let paths = resolve_windows(Some(&cwd), Some(&exe), Some(&app_data)).unwrap();
        assert_eq!(paths.root(), cwd);
    }

    #[test]
    fn portable_executable_data_is_preserved() {
        let tree = TestTree::new("portable");
        let cwd = tree.dir("cwd");
        let exe = tree.dir("exe");
        let app_data = tree.dir("appdata");
        touch(exe.join("keys.vault"));
        touch(exe.join("config.json"));

        let paths = resolve_windows(Some(&cwd), Some(&exe), Some(&app_data)).unwrap();
        assert_eq!(paths.root(), exe);
    }

    #[test]
    fn cwd_wins_when_both_legacy_locations_are_populated() {
        let tree = TestTree::new("both");
        let cwd = tree.dir("cwd");
        let exe = tree.dir("exe");
        let app_data = tree.dir("appdata");
        touch(cwd.join("keys.vault"));
        touch(exe.join("keys.vault"));

        let paths = resolve_windows(Some(&cwd), Some(&exe), Some(&app_data)).unwrap();
        assert_eq!(paths.root(), cwd);
        assert_eq!(paths.config(), cwd.join("config.json"));
        assert_ne!(paths.config(), exe.join("config.json"));
    }

    #[test]
    fn fresh_windows_install_uses_roaming_appdata() {
        let tree = TestTree::new("fresh");
        let cwd = tree.dir("cwd");
        let exe = tree.dir("exe");
        let app_data = tree.dir("Some User/МИНТЕР Data");

        let paths = resolve_windows(Some(&cwd), Some(&exe), Some(&app_data)).unwrap();
        assert_eq!(paths.root(), app_data.join("MINTER"));
    }

    #[test]
    fn fresh_windows_install_does_not_require_executable_directory() {
        let tree = TestTree::new("no_exe_dir");
        let cwd = tree.dir("cwd");
        let app_data = tree.dir("appdata");

        let paths = resolve_windows(Some(&cwd), None, Some(&app_data)).unwrap();
        assert_eq!(paths.root(), app_data.join("MINTER"));
    }

    #[test]
    fn fresh_windows_install_without_appdata_fails_clearly() {
        let tree = TestTree::new("no_appdata");
        let cwd = tree.dir("cwd");
        let exe = tree.dir("exe");

        let error = resolve_windows(Some(&cwd), Some(&exe), None).unwrap_err();
        assert!(error.to_string().contains("application-data"));
    }

    #[test]
    fn every_managed_path_is_derived_from_one_root() {
        let tree = TestTree::new("derived");
        let root = tree.dir("Some User/МИНТЕР Data");
        let paths = RuntimePaths::from_root(&root);
        let expected = [
            (paths.vault(), "keys.vault"),
            (paths.config(), "config.json"),
            (paths.legacy_env(), ".env"),
            (paths.auth_cache(), "auth_cache.bin"),
            (paths.proxies(), "proxies.txt"),
            (paths.tasks(), "tasks.json"),
            (paths.wallet_meta(), "wallet_meta.json"),
            (paths.runs_history(), "runs_history.json"),
            (paths.logs(), "logs"),
            (paths.results(), "results"),
            (paths.imports(), "imports"),
        ];
        for (actual, name) in expected {
            assert_eq!(actual, root.join(name));
        }

        std::fs::create_dir_all(paths.logs()).unwrap();
        touch(paths.logs().join("unicode-check.txt"));
        assert!(paths.logs().join("unicode-check.txt").is_file());
    }

    #[test]
    fn vps_working_directory_keeps_all_data_under_var_lib_minter() {
        let paths = resolve_non_windows(Some(Path::new("/var/lib/minter"))).unwrap();
        assert_eq!(paths.vault(), Path::new("/var/lib/minter/keys.vault"));
        assert_eq!(paths.results(), Path::new("/var/lib/minter/results"));
    }

    #[test]
    fn existing_vault_format_opens_after_legacy_resolution() {
        let tree = TestTree::new("vault_compat");
        let cwd = tree.dir("legacy cwd");
        let exe = tree.dir("exe");
        let app_data = tree.dir("appdata");
        let vault = Vault::new(cwd.join("keys.vault"));
        vault
            .generate_burners(1, "runtime_paths_test_password", &[cwd.join("imports")])
            .unwrap();

        let paths = resolve_windows(Some(&cwd), Some(&exe), Some(&app_data)).unwrap();
        let keys = Vault::new(paths.vault())
            .decrypt_keys("runtime_paths_test_password")
            .unwrap();
        assert_eq!(keys.len(), 1);
    }
}
