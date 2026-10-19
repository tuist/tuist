//! The Swift launcher store serializes semantic-version comparisons and only
//! advances this pointer. The daemon never rewrites it or starts a second owner.

use std::path::{Path, PathBuf};

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct LaunchTarget {
    executable: String,
    tuist_version: String,
}

fn read_target(path: &Path) -> Option<LaunchTarget> {
    let target: LaunchTarget = serde_json::from_slice(&std::fs::read(path).ok()?).ok()?;
    semver::Version::parse(&target.tuist_version).ok()?;
    if !Path::new(&target.executable).is_absolute() {
        return None;
    }
    use std::os::unix::fs::PermissionsExt;
    std::fs::metadata(&target.executable)
        .ok()
        .filter(|metadata| metadata.is_file() && metadata.permissions().mode() & 0o111 != 0)?;
    Some(target)
}

pub fn selected_executable(path: &Path) -> Option<PathBuf> {
    read_target(path).map(|target| PathBuf::from(target.executable))
}

pub fn launch_target_changed(path: &Path, current_version: &str) -> bool {
    let Ok(current) = semver::Version::parse(current_version) else {
        return false;
    };
    read_target(path).is_some_and(|target| {
        semver::Version::parse(&target.tuist_version).is_ok_and(|selected| selected > current)
    })
}

/// Run by the NEW proxy after binding its socket, never by generation. Rename
/// preserves dylib images already loaded by Xcode; future frontends use the new
/// plugin. An older proxy starting during another upgrade must not downgrade it.
pub fn refresh_plugin(path: &Path, executable: &Path, version: &str) -> std::io::Result<()> {
    use std::os::fd::AsRawFd;
    let Some(directory) = path.parent() else {
        return Ok(());
    };
    // The same lock as Swift's pointer writer prevents an old starting proxy
    // from copying its plugin after setup has selected and installed a newer one.
    let lock = std::fs::OpenOptions::new()
        .create(true)
        .truncate(false)
        .write(true)
        .open(directory.join("cas-launcher.lock"))?;
    if unsafe { libc::flock(lock.as_raw_fd(), libc::LOCK_EX) } != 0 {
        return Err(std::io::Error::last_os_error());
    }
    let Some(target) = read_target(path) else {
        return Ok(());
    };
    let (Ok(selected), Ok(current)) = (
        semver::Version::parse(&target.tuist_version),
        semver::Version::parse(version),
    ) else {
        return Ok(());
    };
    // An in-place CLI update can run a newer binary before the pointer's version
    // is advanced. It must refresh its plugin, not restart forever on an old target.
    if selected > current || Path::new(&target.executable) != executable {
        return Ok(());
    }
    let Some(bundle) = executable.parent() else {
        return Ok(());
    };
    let source = bundle.join("libtuist_cas_plugin.dylib");
    let destination = directory.join("libtuist_cas_plugin.dylib");
    if std::fs::read(&source)? == std::fs::read(&destination).unwrap_or_default() {
        return Ok(());
    }
    let staged = directory.join(format!(
        "libtuist_cas_plugin.dylib.{}.tmp",
        std::process::id()
    ));
    let result = std::fs::copy(source, &staged).and_then(|_| std::fs::rename(&staged, destination));
    let _ = std::fs::remove_file(staged);
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_new_proxy_refreshes_the_plugin_without_replacing_loaded_images_or_downgrading() {
        use std::io::Read;
        let cli = crate::token::tests::FakeCli::new();
        let state = cli.0.join("state");
        std::fs::create_dir(&state).unwrap();
        let target = state.join("target.json");
        let executable = cli.0.join("tuist");
        std::fs::write(
            &target,
            serde_json::json!({
                "executable": executable, "tuistVersion": "4.214.0"
            })
            .to_string(),
        )
        .unwrap();
        let plugin = state.join("libtuist_cas_plugin.dylib");
        let bundled = cli.0.join("libtuist_cas_plugin.dylib");
        std::fs::write(&plugin, b"old plugin").unwrap();
        std::fs::write(&bundled, b"new plugin").unwrap();
        let mut loaded = std::fs::File::open(&plugin).unwrap();
        refresh_plugin(&target, &executable, "4.213.0").unwrap();
        assert_eq!(std::fs::read(&plugin).unwrap(), b"old plugin");
        refresh_plugin(&target, &executable, "4.214.0").unwrap();
        assert_eq!(std::fs::read(&plugin).unwrap(), b"new plugin");
        let mut original = String::new();
        loaded.read_to_string(&mut original).unwrap();
        assert_eq!(original, "old plugin");
        // Restarting an older proxy, or losing the new bundle, cannot replace it.
        std::fs::write(&bundled, b"older plugin").unwrap();
        refresh_plugin(&target, &executable, "4.213.0").unwrap();
        assert_eq!(std::fs::read(&plugin).unwrap(), b"new plugin");
        // In-place CLI upgrades can start newer than the pointer's recorded version.
        std::fs::write(&bundled, b"in-place upgrade plugin").unwrap();
        refresh_plugin(&target, &executable, "4.215.0").unwrap();
        assert_eq!(std::fs::read(&plugin).unwrap(), b"in-place upgrade plugin");
        std::fs::write(&plugin, b"new plugin").unwrap();
        std::fs::remove_file(&bundled).unwrap();
        assert!(refresh_plugin(&target, &executable, "4.214.0").is_err());
        assert_eq!(std::fs::read(&plugin).unwrap(), b"new plugin");
    }

    #[test]
    fn validates_target_before_requesting_a_restart() {
        let path =
            std::env::temp_dir().join(format!("tuist-proxy-upgrade-{}.json", std::process::id()));
        let write = |version: &str, executable: &str| {
            std::fs::write(
                &path,
                serde_json::json!({
                    "executable": executable, "tuistVersion": version
                })
                .to_string(),
            )
            .unwrap();
        };
        write("4.214.0", "/bin/sh");
        assert!(launch_target_changed(&path, "4.213.0"));
        assert!(!launch_target_changed(&path, "4.214.0"));
        assert!(
            !launch_target_changed(&path, "4.215.0"),
            "an in-place newer CLI must not restart on an old pointer"
        );
        assert!(!launch_target_changed(&path, ""));
        write("4.214.0-rc.2", "/bin/sh");
        assert!(launch_target_changed(&path, "4.214.0-rc.1"));
        assert!(!launch_target_changed(&path, "4.214.0"));
        write("4.214.0", "/missing/tuist");
        assert!(!launch_target_changed(&path, "4.213.0"));
        write("4.214.0", "/tmp");
        assert!(!launch_target_changed(&path, "4.213.0"));
        write("", "/bin/sh");
        assert!(!launch_target_changed(&path, "4.213.0"));
        write("4.214.0", "relative/tuist");
        assert!(selected_executable(&path).is_none());
        std::fs::write(&path, "broken").unwrap();
        assert!(!launch_target_changed(&path, "4.213.0"));
        std::fs::remove_file(&path).unwrap();
        assert!(!launch_target_changed(&path, "4.213.0"));
    }
}
