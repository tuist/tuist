//! Exercise process-local developer selection without mutating another test's environment.
#![cfg(target_os = "macos")]

use std::path::Path;
use std::process::Command;

#[test]
fn selected_sdk_is_a_system_path() {
    const CHILD: &str = "TUIST_CARGO_CACHE_TEST_DEVELOPER_DIRECTORY_CHILD";
    if std::env::var_os(CHILD).is_some() {
        let root = std::env::var("DEVELOPER_DIR").unwrap();
        let sdk = Path::new(&root).join("Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/SDKSettings.json");
        assert!(tuist_cargo_cache_cc::is_system_path(&sdk));
        assert!(!tuist_cargo_cache_cc::is_system_path(Path::new(
            "/Applications/Unrelated.app/header.h"
        )));
        return;
    }
    let status = Command::new(std::env::current_exe().unwrap())
        .args(["--exact", "selected_sdk_is_a_system_path"])
        .env(CHILD, "1")
        .env("DEVELOPER_DIR", "/Applications/Xcode-beta.app")
        .status()
        .unwrap();
    assert!(status.success());
}
