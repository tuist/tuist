//! Whether a newer internal Luft preview than the running build exists.
use serde_json::{Value, json};
use url::Url;

use crate::client::Result;

/// Luft publishes its previews here (`luft/tuist.toml`).
pub(crate) const SERVER: &str = "https://luft.work/";
pub(crate) const PATH: &str = "api/projects/tuist/luft/previews";
pub(crate) const TRACK: &str = "internal";

/// The build type each installable platform's previews use.
pub(crate) fn build_type(platform: &str) -> Result<&'static str> {
    match platform {
        "ios" => Ok("ipa"),
        "macos" => Ok("app_bundle"),
        "android" => Ok("apk"),
        _ => Err("Unsupported platform"),
    }
}

/// Picks the newest preview whose build for `platform` has a binary identity,
/// the same one the edge computes for itself: the Mach-O UUID on Apple
/// platforms and the APK's SHA-256 on Android. Previews without one (older
/// uploads, ad-hoc duplicates) cannot be compared and are skipped. The running
/// build is current when its identity matches, so republishing an identical
/// binary never offers an update.
pub(crate) fn select(data: &Value, platform: &str, binary_id: &str) -> Result<Value> {
    let kind = build_type(platform)?;
    let previews = data["previews"].as_array().ok_or("Invalid previews")?;
    for preview in previews {
        let Some(build) = preview["builds"]
            .as_array()
            .into_iter()
            .flatten()
            .find(|b| {
                b["type"] == kind
                    && b["supported_platforms"]
                        .as_array()
                        .is_some_and(|p| p.iter().any(|v| v == platform))
                    && b["binary_id"].as_str().is_some_and(|id| !id.is_empty())
            })
        else {
            continue;
        };
        if build["binary_id"]
            .as_str()
            .is_some_and(|id| id.eq_ignore_ascii_case(binary_id))
        {
            return Ok(json!({"update":null}));
        }
        // iOS installs through the preview's OTA manifest; the others download the build.
        let install = if platform == "ios" {
            preview["device_url"].as_str().filter(|url| {
                url.starts_with("itms-services://?action=download-manifest&url=https")
            })
        } else {
            build["url"]
                .as_str()
                .filter(|url| Url::parse(url).is_ok_and(|u| u.scheme() == "https"))
        }
        .ok_or("Invalid preview")?;
        let commit: String = preview["git_commit_sha"]
            .as_str()
            .unwrap_or_default()
            .chars()
            .take(7)
            .collect();
        return Ok(json!({"update":{
            "id": preview["id"],
            "version": preview["version"],
            "commit": if commit.is_empty() { Value::Null } else { json!(commit) },
            "inserted_at": preview["inserted_at"],
            "release_notes": preview["release_notes"],
            "url": preview["url"],
            "install_url": install,
        }}));
    }
    Ok(json!({"update":null}))
}
