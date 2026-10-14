//! Native archive timestamp determinism.
//!
//! Apple's `ar` and `ranlib` stamp the current time into an archive's symbol
//! table and member headers. Re-running them over unchanged objects therefore
//! produces different bytes for the same content, and a build script that
//! hands Cargo such an archive hands tuist_cargo_cache a changed input: the archive's digest
//! moves, so every action downstream of it misses even though nothing was
//! recompiled. CMake-based native dependencies hit this routinely because they
//! invoke `/usr/bin/ar` directly rather than going through the `cc` crate,
//! which already sets `ZERO_AR_DATE` for the implementations it knows about.
//!
//! `ZERO_AR_DATE=1` makes those tools write zeros instead, which is the
//! toolchain's own supported way to ask for a reproducible archive. tuist_cargo_cache sets it
//! for the build scripts it runs, subject to [`ArDeterminism`].
//!
//! This only normalizes the timestamp fields. An archive whose *member
//! payloads* differ between builds is a different problem with a different
//! cause, and nothing here addresses it -- see the `archive-stability`
//! benchmark for telling the two apart.

use std::ffi::OsStr;

/// The environment variable Apple's archive tools read.
pub(crate) const ZERO_AR_DATE: &str = "ZERO_AR_DATE";

/// Cargo sets this for every build script it runs.
pub(crate) const PROFILE: &str = "PROFILE";

/// When tuist_cargo_cache normalizes native archive timestamps.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub(crate) enum ArDeterminism {
    /// Normalize for every profile except `release`.
    ///
    /// The cache misses this prevents are worst in the edit-build loop, where
    /// fresh targets are common and a moved archive digest costs a wave of
    /// downstream recompilation. A release build is also the one whose exact
    /// output bytes someone may be signing, publishing, or comparing against a
    /// previous artifact, so the default leaves those exactly as the host
    /// toolchain produced them rather than quietly changing them.
    #[default]
    Auto,
    /// Normalize for every profile, including `release`.
    Always,
    /// Never normalize; leave the toolchain's own behavior alone.
    Off,
}

impl ArDeterminism {
    /// Parse a configured value, falling back to the default when unrecognized.
    ///
    /// Configuration already constrains this to the documented choices; an
    /// unknown value here means some other caller, and the default is the safe
    /// reading of one.
    pub(crate) fn parse(value: &str) -> Self {
        match value {
            "always" => Self::Always,
            "off" => Self::Off,
            _ => Self::Auto,
        }
    }

    pub(crate) fn as_str(self) -> &'static str {
        match self {
            Self::Auto => "auto",
            Self::Always => "always",
            Self::Off => "off",
        }
    }
}

/// Whether tuist_cargo_cache should set `ZERO_AR_DATE` for a build script.
///
/// `profile` is Cargo's `PROFILE` for the build script, and `already_set` is
/// whether the environment already carries `ZERO_AR_DATE`. An explicit setting
/// from the user wins outright: they have said what they want the archive tools
/// to do, and tuist_cargo_cache overriding that would make their own configuration
/// unpredictable.
pub(crate) fn normalizes(mode: ArDeterminism, profile: Option<&str>, already_set: bool) -> bool {
    if already_set {
        return false;
    }
    match mode {
        ArDeterminism::Off => false,
        ArDeterminism::Always => true,
        ArDeterminism::Auto => profile != Some("release"),
    }
}

/// The `ZERO_AR_DATE` a build script will actually see.
///
/// This is what belongs in a build script's cache key, not whether tuist_cargo_cache chose
/// to set it. A cached result carries whatever archives the run that produced
/// it happened to make, so a key that ignores the policy hands back timestamped
/// archives after the policy is turned on -- and normalized ones after it is
/// turned off -- until the store is cleared. Keying on the value the script
/// sees makes each policy its own entry, so changing the setting takes effect
/// on the next build rather than whenever the cache next misses for some other
/// reason. An inherited value is reported as-is because that is what the script
/// will read, whether or not tuist_cargo_cache was the one to put it there.
pub(crate) fn effective_zero_ar_date(
    mode: ArDeterminism,
    profile: Option<&str>,
    inherited: Option<&OsStr>,
) -> Option<String> {
    match inherited {
        Some(value) => Some(key_for(value)),
        None => normalizes(mode, profile, false).then(|| key_for(OsStr::new("1"))),
    }
}

/// Spell one `ZERO_AR_DATE` value for a cache key.
///
/// Taken as an `OsStr` and tagged rather than passed through as a `String`,
/// because the decision to leave an inherited value alone is made with
/// `var_os`: a value that is not UTF-8 still reaches the build script, so
/// reading it back with `var` and dropping it would key that build as though
/// tuist_cargo_cache had supplied its own "1", and the two would share an entry while their
/// archives disagree. The tags keep a byte spelling from colliding with the
/// text that happens to look like it.
fn key_for(value: &OsStr) -> String {
    use std::fmt::Write as _;

    match value.to_str() {
        Some(text) => format!("text:{text}"),
        None => {
            let mut key = String::from("bytes:");
            for byte in value.as_encoded_bytes() {
                let _ = write!(key, "{byte:02x}");
            }
            key
        }
    }
}

/// Whether this host's archive tools stamp a timestamp tuist_cargo_cache would normalize.
///
/// Answered by running the tools rather than by assuming from the platform:
/// which `ar` and `ranlib` are on `PATH` is a property of the installation, and
/// a toolchain that is already deterministic needs no help. Both archives are
/// built from the same bytes in the same directory and differ only in whether
/// `ZERO_AR_DATE` is set, so a difference between them is the timestamp and
/// nothing else. No delay is needed: the comparison is zeroed-versus-stamped,
/// not one clock reading against a later one.
#[derive(Debug, PartialEq, Eq)]
pub(crate) enum Probe {
    /// The tools stamp a timestamp, and `ZERO_AR_DATE` suppresses it.
    Stamps,
    /// The tools already produce identical bytes for identical input.
    Deterministic,
    /// The probe could not run; the reason is for a human, not for a decision.
    Unavailable(String),
}

pub(crate) fn probe() -> Probe {
    match probe_inner() {
        Ok(true) => Probe::Stamps,
        Ok(false) => Probe::Deterministic,
        Err(error) => Probe::Unavailable(error.to_string()),
    }
}

fn probe_inner() -> std::io::Result<bool> {
    use std::process::{Command, Stdio};

    let directory = tempfile::Builder::new()
        .prefix("tuist_cargo_cache-ar-probe-")
        .tempdir()?;
    let member = directory.path().join("member");
    // Any file serves. `ranlib` warns that it is not an object and still
    // rewrites the header this probe is reading, so the archive stays valid
    // for the comparison without needing a compiler on the host.
    std::fs::write(&member, b"tuist_cargo_cache archive probe")?;

    let run = |program: &str, arguments: &[&std::ffi::OsStr], zero: bool| -> std::io::Result<()> {
        let mut command = Command::new(program);
        command
            .args(arguments)
            .current_dir(directory.path())
            .stdout(Stdio::null())
            .stderr(Stdio::null());
        if zero {
            command.env(ZERO_AR_DATE, "1");
        } else {
            command.env_remove(ZERO_AR_DATE);
        }
        let status = command.status()?;
        if status.success() {
            return Ok(());
        }
        Err(std::io::Error::other(format!(
            "{program} exited with {status}"
        )))
    };

    let mut digests = Vec::new();
    for (name, zero) in [("zeroed.a", true), ("stamped.a", false)] {
        let archive = directory.path().join(name);
        run(
            "ar",
            &["rc".as_ref(), archive.as_os_str(), member.as_os_str()],
            zero,
        )?;
        run("ranlib", &[archive.as_os_str()], zero)?;
        digests.push(std::fs::read(&archive)?);
    }
    Ok(digests[0] != digests[1])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_explicit_setting_from_the_user_is_never_overridden() {
        for mode in [
            ArDeterminism::Auto,
            ArDeterminism::Always,
            ArDeterminism::Off,
        ] {
            assert!(!normalizes(mode, Some("debug"), true));
            assert!(!normalizes(mode, Some("release"), true));
        }
    }

    #[test]
    fn auto_leaves_release_archives_as_the_toolchain_made_them() {
        assert!(!normalizes(ArDeterminism::Auto, Some("release"), false));
        assert!(normalizes(ArDeterminism::Auto, Some("debug"), false));
        assert!(normalizes(ArDeterminism::Auto, Some("bench"), false));
    }

    #[test]
    fn a_missing_profile_is_treated_as_a_non_release_build() {
        // Cargo always sets PROFILE, so this is a build script reached some
        // other way. Normalizing is the behavior that keeps the cache honest.
        assert!(normalizes(ArDeterminism::Auto, None, false));
    }

    #[test]
    fn always_and_off_ignore_the_profile() {
        assert!(normalizes(ArDeterminism::Always, Some("release"), false));
        assert!(normalizes(ArDeterminism::Always, Some("debug"), false));
        assert!(!normalizes(ArDeterminism::Off, Some("release"), false));
        assert!(!normalizes(ArDeterminism::Off, Some("debug"), false));
    }

    #[test]
    fn unrecognized_settings_parse_to_the_default() {
        assert_eq!(ArDeterminism::parse("always"), ArDeterminism::Always);
        assert_eq!(ArDeterminism::parse("off"), ArDeterminism::Off);
        assert_eq!(ArDeterminism::parse("auto"), ArDeterminism::Auto);
        assert_eq!(ArDeterminism::parse("nonsense"), ArDeterminism::Auto);
        assert_eq!(ArDeterminism::default(), ArDeterminism::Auto);
    }

    #[test]
    fn the_key_reflects_what_the_script_will_read() {
        // tuist_cargo_cache supplies the value.
        assert_eq!(
            effective_zero_ar_date(ArDeterminism::Auto, Some("debug"), None).as_deref(),
            Some("text:1")
        );
        // Policy declines, so the script sees nothing.
        assert_eq!(
            effective_zero_ar_date(ArDeterminism::Auto, Some("release"), None),
            None
        );
        assert_eq!(
            effective_zero_ar_date(ArDeterminism::Off, Some("debug"), None),
            None
        );
        assert_eq!(
            effective_zero_ar_date(ArDeterminism::Always, Some("release"), None).as_deref(),
            Some("text:1")
        );
    }

    #[test]
    fn an_inherited_value_is_keyed_as_the_script_reads_it() {
        // Including the value, not merely the fact that one was set: two
        // developers with different settings must not share an entry.
        for mode in [
            ArDeterminism::Auto,
            ArDeterminism::Always,
            ArDeterminism::Off,
        ] {
            assert_eq!(
                effective_zero_ar_date(mode, Some("debug"), Some(OsStr::new("0"))).as_deref(),
                Some("text:0")
            );
            assert_eq!(
                effective_zero_ar_date(mode, Some("debug"), Some(OsStr::new("1"))).as_deref(),
                Some("text:1")
            );
        }
    }

    #[cfg(unix)]
    #[test]
    fn a_value_that_is_not_utf8_is_keyed_rather_than_dropped() {
        use std::os::unix::ffi::OsStrExt as _;

        // `apply_ar_determinism` leaves this value alone, so the key has to
        // say so too. Keying it as absent would give this build the same entry
        // as one where tuist_cargo_cache supplied its own "1", and restore the wrong
        // archives into it.
        let inherited = OsStr::from_bytes(&[0x31, 0xff]);
        let keyed = effective_zero_ar_date(ArDeterminism::Auto, Some("debug"), Some(inherited));
        assert!(keyed.is_some());
        assert_ne!(
            keyed,
            effective_zero_ar_date(ArDeterminism::Auto, Some("debug"), None)
        );
        assert_ne!(
            keyed,
            effective_zero_ar_date(ArDeterminism::Auto, Some("debug"), Some(OsStr::new("1")))
        );
    }

    #[cfg(unix)]
    #[test]
    fn a_text_value_cannot_spell_a_byte_value() {
        use std::os::unix::ffi::OsStrExt as _;

        let bytes = effective_zero_ar_date(
            ArDeterminism::Off,
            Some("debug"),
            Some(OsStr::from_bytes(&[0xc3, 0x28])),
        );
        let text =
            effective_zero_ar_date(ArDeterminism::Off, Some("debug"), Some(OsStr::new("c328")));
        assert!(bytes.is_some() && text.is_some());
        assert_ne!(bytes, text);
    }

    #[test]
    fn turning_the_policy_on_or_off_changes_the_key() {
        let on = effective_zero_ar_date(ArDeterminism::Auto, Some("debug"), None);
        let off = effective_zero_ar_date(ArDeterminism::Off, Some("debug"), None);
        assert_ne!(on, off);
    }

    #[test]
    fn every_mode_round_trips_through_its_configured_spelling() {
        for mode in [
            ArDeterminism::Auto,
            ArDeterminism::Always,
            ArDeterminism::Off,
        ] {
            assert_eq!(ArDeterminism::parse(mode.as_str()), mode);
        }
    }
}
