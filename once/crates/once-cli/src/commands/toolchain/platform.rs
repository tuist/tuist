use anyhow::Result;
use serde::Serialize;

#[derive(Debug, Serialize)]
pub(super) struct PlatformView {
    pub os: String,
    pub arch: String,
    pub mise: String,
}

pub(super) fn requested(platform: Option<&str>) -> Result<PlatformView> {
    match platform {
        Some(raw) => parse(raw),
        None => Ok(current()),
    }
}

fn current() -> PlatformView {
    let arch = std::env::consts::ARCH;
    let mise_arch = match arch {
        "x86_64" => "x64",
        "aarch64" => "arm64",
        other => other,
    };
    PlatformView {
        os: std::env::consts::OS.to_string(),
        arch: arch.to_string(),
        mise: format!("{}-{mise_arch}", std::env::consts::OS),
    }
}

fn parse(raw: &str) -> Result<PlatformView> {
    let (os, arch) = raw
        .rsplit_once('-')
        .ok_or_else(|| anyhow::anyhow!("platform must look like os-arch, got `{raw}`"))?;
    if os.is_empty() || arch.is_empty() {
        anyhow::bail!("platform must look like os-arch, got `{raw}`");
    }
    Ok(PlatformView {
        os: os.to_string(),
        arch: arch.to_string(),
        mise: raw.to_string(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_malformed_platform() {
        let err = parse("linux").unwrap_err().to_string();
        assert!(err.contains("os-arch"));
    }
}
