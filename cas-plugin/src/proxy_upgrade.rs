//! Pointer selection and startup reconciliation share Swift's launcher lock.
//! Only the accepting proxy refreshes the plugin; it never starts a second owner.

use std::path::{Path, PathBuf};

#[derive(serde::Deserialize, serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct LaunchTarget {
    executable: String,
    tuist_version: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    highest_tuist_version: Option<String>,
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
/// plugin. A proxy from an installation no longer selected must not replace it.
pub fn refresh_plugin(
    path: &Path,
    executable: &Path,
    version: &str,
    source: Option<&Path>,
) -> std::io::Result<()> {
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
    let Some(mut target) = read_target(path) else {
        return Ok(());
    };
    let Ok(current) = semver::Version::parse(version) else {
        return Ok(());
    };
    let executable = std::fs::canonicalize(executable)?;
    if std::fs::canonicalize(&target.executable)? != executable {
        return Ok(());
    }
    // The wrapper reports the version actually exec'd. Reconcile mutable paths
    // in both directions so an in-place rollback cannot cause a relaunch loop.
    // Retain the high-water mark so another checkout cannot undo an upgrade
    // that started before generation recorded the replacement binary's version.
    let highest = target
        .highest_tuist_version
        .as_deref()
        .unwrap_or(&target.tuist_version);
    let highest = semver::Version::parse(highest)
        .map_err(|error| std::io::Error::new(std::io::ErrorKind::InvalidData, error))?
        .max(current);
    target.highest_tuist_version = Some(highest.to_string());
    target.tuist_version = version.to_owned();
    // Preserve the invoked alias: package-manager cleanup may remove the
    // canonical versioned directory while leaving that alias usable.
    let staged_target = directory.join(format!("cas-launch-target.{}.tmp", std::process::id()));
    let result = std::fs::write(&staged_target, serde_json::to_vec(&target)?)
        .and_then(|_| std::fs::rename(&staged_target, path));
    let _ = std::fs::remove_file(staged_target);
    result?;
    // The wrapper resolves bundle layout (including Homebrew's lib directory).
    let Some(source) = source else {
        return Ok(());
    };
    let destination = directory.join("libtuist_cas_plugin.dylib");
    if std::fs::read(source)? == std::fs::read(&destination).unwrap_or_default() {
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
        let older = crate::token::tests::FakeCli::new();
        refresh_plugin(&target, &older.0.join("tuist"), "4.213.0", Some(&bundled)).unwrap();
        assert_eq!(std::fs::read(&plugin).unwrap(), b"old plugin");
        refresh_plugin(&target, &executable, "4.214.0", Some(&bundled)).unwrap();
        assert_eq!(std::fs::read(&plugin).unwrap(), b"new plugin");
        let mut original = String::new();
        loaded.read_to_string(&mut original).unwrap();
        assert_eq!(original, "old plugin");
        // Restarting an older proxy, or losing the new bundle, cannot replace it.
        std::fs::write(&bundled, b"older plugin").unwrap();
        refresh_plugin(&target, &older.0.join("tuist"), "4.213.0", Some(&bundled)).unwrap();
        assert_eq!(std::fs::read(&plugin).unwrap(), b"new plugin");
        // In-place CLI upgrades can start newer than the pointer's recorded version.
        std::fs::write(&bundled, b"in-place upgrade plugin").unwrap();
        refresh_plugin(&target, &executable, "4.215.0", Some(&bundled)).unwrap();
        assert_eq!(std::fs::read(&plugin).unwrap(), b"in-place upgrade plugin");
        let recorded = read_target(&target).unwrap();
        assert_eq!(recorded.tuist_version, "4.215.0");
        assert_eq!(recorded.highest_tuist_version.as_deref(), Some("4.215.0"));
        assert!(!launch_target_changed(&target, "4.215.0"));
        // An explicit in-place rollback is usable, but retains the high-water
        // mark against older checkouts switching this still-usable installation.
        refresh_plugin(&target, &executable, "4.214.0", Some(&bundled)).unwrap();
        assert!(!launch_target_changed(&target, "4.214.0"));
        assert_eq!(
            read_target(&target)
                .unwrap()
                .highest_tuist_version
                .as_deref(),
            Some("4.215.0")
        );
        std::fs::write(&plugin, b"new plugin").unwrap();
        std::fs::remove_file(&bundled).unwrap();
        assert!(refresh_plugin(&target, &executable, "4.214.0", Some(&bundled)).is_err());
        assert_eq!(std::fs::read(&plugin).unwrap(), b"new plugin");
    }

    #[test]
    fn refresh_matches_symlinked_bundle_paths() {
        let cli = crate::token::tests::FakeCli::new();
        let state = cli.0.join("state");
        std::fs::create_dir(&state).unwrap();
        let alias = cli.0.join("alias");
        std::os::unix::fs::symlink(&cli.0, &alias).unwrap();
        let target = state.join("target.json");
        std::fs::write(
            &target,
            serde_json::json!({
                "executable": alias.join("tuist"), "tuistVersion": "4.214.0"
            })
            .to_string(),
        )
        .unwrap();
        std::fs::write(cli.0.join("libtuist_cas_plugin.dylib"), b"plugin").unwrap();
        refresh_plugin(
            &target,
            &cli.0.join("tuist"),
            "4.214.0",
            Some(&cli.0.join("libtuist_cas_plugin.dylib")),
        )
        .unwrap();
        assert_eq!(
            std::fs::read(state.join("libtuist_cas_plugin.dylib")).unwrap(),
            b"plugin"
        );
        assert_eq!(
            PathBuf::from(read_target(&target).unwrap().executable),
            alias.join("tuist")
        );
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
