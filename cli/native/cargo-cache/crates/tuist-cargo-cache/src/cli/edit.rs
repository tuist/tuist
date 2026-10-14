use crate::config::config_file_path;
use eyre::{Context, Result};
use std::ffi::{OsStr, OsString};
use std::fs::OpenOptions;
use std::io;
use std::path::Path;
use std::process::{Command, ExitCode, ExitStatus};

pub(super) fn run() -> Result<ExitCode> {
    let path = config_file_path()
        .ok_or_else(|| eyre::eyre!("could not resolve the global configuration path"))?;
    let visual = editor_variable("VISUAL")?;
    let editor = editor_variable("EDITOR")?;
    run_with(&path, visual.as_deref(), editor.as_deref(), launch_editor)
}

/// Resolve the editor the way a shell would, so on Windows `code` finds
/// `code.cmd`, then wait for it. A terminal editor owns Ctrl+C while it runs,
/// so tuist_cargo_cache must outlive the interrupt instead of dying and orphaning it.
fn launch_editor(program: &OsStr, arguments: &[OsString]) -> io::Result<ExitStatus> {
    let resolved = which::which(program).unwrap_or_else(|_| program.into());
    #[cfg(unix)]
    let _interrupt = SurviveInterrupt::install();
    Command::new(resolved).args(arguments).status()
}

#[cfg(unix)]
struct SurviveInterrupt(libc::sighandler_t);

#[cfg(unix)]
impl SurviveInterrupt {
    fn install() -> Self {
        extern "C" fn ignore(_: libc::c_int) {}
        // A handler, not SIG_IGN: handlers reset on exec, so the editor keeps
        // its default Ctrl+C behavior while only tuist_cargo_cache survives.
        let handler: extern "C" fn(libc::c_int) = ignore;
        // SAFETY: the handler does nothing, so it is async-signal-safe.
        Self(unsafe { libc::signal(libc::SIGINT, handler as libc::sighandler_t) })
    }
}

#[cfg(unix)]
impl Drop for SurviveInterrupt {
    fn drop(&mut self) {
        // SAFETY: restores the handler that install replaced.
        unsafe { libc::signal(libc::SIGINT, self.0) };
    }
}

fn editor_variable(name: &str) -> Result<Option<String>> {
    match std::env::var(name) {
        Ok(value) => Ok(Some(value)),
        Err(std::env::VarError::NotPresent) => Ok(None),
        Err(std::env::VarError::NotUnicode(_)) => {
            eyre::bail!("{name} is not valid Unicode")
        }
    }
}

fn run_with<F>(
    path: &Path,
    visual: Option<&str>,
    editor: Option<&str>,
    launch: F,
) -> Result<ExitCode>
where
    F: FnOnce(&OsStr, &[OsString]) -> io::Result<ExitStatus>,
{
    let command = configured_editor(visual, editor);
    let (program, mut arguments) = split_editor_command(command)?;

    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)
            .wrap_err_with(|| format!("failed to create {}", parent.display()))?;
    }
    match OpenOptions::new().write(true).create_new(true).open(path) {
        Ok(_) => {}
        Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {}
        Err(error) => {
            return Err(error).wrap_err_with(|| format!("failed to create {}", path.display()));
        }
    }

    arguments.push(path.as_os_str().to_owned());
    let status = launch(OsStr::new(&program), &arguments)
        .wrap_err_with(|| format!("failed to launch editor `{program}` for {}", path.display()))?;
    if !status.success() {
        eyre::bail!("editor `{program}` exited unsuccessfully: {status}");
    }
    Ok(ExitCode::SUCCESS)
}

fn configured_editor<'a>(visual: Option<&'a str>, editor: Option<&'a str>) -> &'a str {
    visual
        .filter(|value| !value.trim().is_empty())
        .or_else(|| editor.filter(|value| !value.trim().is_empty()))
        .unwrap_or(DEFAULT_EDITOR)
}

#[cfg(windows)]
const DEFAULT_EDITOR: &str = "notepad";
#[cfg(not(windows))]
const DEFAULT_EDITOR: &str = "nano";

fn split_editor_command(editor: &str) -> Result<(String, Vec<OsString>)> {
    let mut parts = split_words(editor, cfg!(windows))
        .wrap_err_with(|| format!("failed to parse editor command {editor:?}"))?
        .into_iter();
    let program = parts
        .next()
        .filter(|program| !program.is_empty())
        .ok_or_else(|| eyre::eyre!("editor command is empty"))?;
    Ok((program, parts.map(Into::into).collect()))
}

/// Split an editor command into words. POSIX rules honor single quotes and
/// backslash escapes. Windows rules honor only double quotes, so the backslashes
/// in `C:\Program Files\Editor\editor.exe` stay literal.
fn split_words(input: &str, windows: bool) -> Result<Vec<String>> {
    let mut words = Vec::new();
    let mut word = String::new();
    let mut started = false;
    let mut quote = None;
    let mut chars = input.chars();
    while let Some(c) = chars.next() {
        match (quote, c) {
            (Some('\''), '\'') => quote = None,
            (Some('"'), '"') => quote = None,
            (Some('"'), '\\') if !windows => match chars.next() {
                Some('\n') => {}
                Some(next @ ('"' | '\\' | '$' | '`')) => word.push(next),
                Some(next) => {
                    word.push('\\');
                    word.push(next);
                }
                None => eyre::bail!("unterminated double quote"),
            },
            (Some(_), _) => word.push(c),
            (None, '"') => {
                quote = Some('"');
                started = true;
            }
            (None, '\'') if !windows => {
                quote = Some('\'');
                started = true;
            }
            (None, '\\') if !windows => match chars.next() {
                Some('\n') => {}
                Some(next) => {
                    word.push(next);
                    started = true;
                }
                None => eyre::bail!("trailing backslash"),
            },
            (None, c) if c.is_whitespace() => {
                if started {
                    words.push(std::mem::take(&mut word));
                    started = false;
                }
            }
            (None, c) => {
                word.push(c);
                started = true;
            }
        }
    }
    if quote.is_some() {
        eyre::bail!("unterminated quote");
    }
    if started {
        words.push(word);
    }
    Ok(words)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn visual_precedes_editor_and_empty_visual_falls_back() {
        assert_eq!(configured_editor(Some("code"), Some("vim")), "code");
        assert_eq!(configured_editor(Some("  "), Some("vim")), "vim");
        assert_eq!(configured_editor(None, Some("")), DEFAULT_EDITOR);
    }

    #[test]
    fn parses_arguments_and_a_quoted_executable_path() {
        let (program, arguments) =
            split_editor_command(r#""/Applications/My Editor.app/editor" --wait"#).unwrap();
        assert_eq!(program, "/Applications/My Editor.app/editor");
        assert_eq!(arguments, [OsString::from("--wait")]);
    }

    #[test]
    fn windows_rules_keep_backslashes_in_executable_paths() {
        assert_eq!(
            split_words(
                r#""C:\Program Files\Notepad++\notepad++.exe" -multiInst"#,
                true
            )
            .unwrap(),
            [r"C:\Program Files\Notepad++\notepad++.exe", "-multiInst"]
        );
        assert_eq!(
            split_words(r"C:\Tools\edit.exe --wait", true).unwrap(),
            [r"C:\Tools\edit.exe", "--wait"]
        );
    }

    #[test]
    fn posix_rules_honor_single_quotes_and_escapes() {
        assert_eq!(
            split_words(r#"'/my dir/ed' a\ b "c \" d""#, false).unwrap(),
            ["/my dir/ed", "a b", "c \" d"]
        );
        assert_eq!(
            split_words("code \\\n--wait \"a\\\nb\"", false).unwrap(),
            ["code", "--wait", "ab"]
        );
        assert!(split_words("'open", false).is_err());
        assert!(split_words("\"open", true).is_err());
    }

    #[cfg(unix)]
    #[test]
    fn rejects_a_non_unicode_variable() {
        use std::os::unix::ffi::OsStringExt as _;
        let name = "TUIST_CARGO_CACHE_EDIT_TEST_NON_UNICODE";
        // SAFETY: the variable name is unique to this test.
        unsafe { std::env::set_var(name, OsString::from_vec(vec![0xff, b'x'])) };
        let error = editor_variable(name).unwrap_err().to_string();
        unsafe { std::env::remove_var(name) };
        assert!(error.contains("not valid Unicode"));
    }

    #[cfg(unix)]
    #[test]
    fn survives_an_interrupt_delivered_while_the_editor_runs() {
        let arguments = [
            OsString::from("-c"),
            OsString::from("kill -INT $PPID; sleep 0.1"),
        ];
        let status = launch_editor(OsStr::new("sh"), &arguments).unwrap();
        assert!(status.success());
    }

    #[test]
    fn rejects_an_empty_quoted_editor() {
        assert!(split_editor_command(r#""""#).is_err());
        assert!(split_editor_command(r#"""#).is_err());
    }

    #[test]
    fn creates_a_missing_file_and_passes_a_spaced_path_as_one_argument() {
        let root = tempfile::tempdir().unwrap();
        let path = root
            .path()
            .join("config root/tuist_cargo_cache/config.toml");

        let result = run_with(&path, Some("code --wait"), None, |program, arguments| {
            assert_eq!(program, "code");
            assert_eq!(arguments, [OsString::from("--wait"), path.clone().into()]);
            assert_eq!(std::fs::read(&path).unwrap(), b"");
            Ok(exit_status(0))
        });

        assert_eq!(result.unwrap(), ExitCode::SUCCESS);
    }

    #[test]
    fn leaves_an_existing_file_untouched_before_launch() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("config.toml");
        std::fs::write(&path, "not valid toml = [").unwrap();

        let result = run_with(&path, None, Some("vim"), |_, _| {
            assert_eq!(
                std::fs::read_to_string(&path).unwrap(),
                "not valid toml = ["
            );
            Ok(exit_status(0))
        });

        assert_eq!(result.unwrap(), ExitCode::SUCCESS);
        assert_eq!(std::fs::read_to_string(path).unwrap(), "not valid toml = [");
    }

    #[test]
    fn reports_launch_and_unsuccessful_exit_failures() {
        let first = tempfile::tempdir().unwrap();
        let path = first.path().join("config.toml");
        let error = run_with(&path, Some("missing-editor"), None, |_, _| {
            Err(io::Error::new(io::ErrorKind::NotFound, "not found"))
        })
        .unwrap_err()
        .to_string();
        assert!(error.contains("failed to launch editor `missing-editor`"));

        let second = tempfile::tempdir().unwrap();
        let path = second.path().join("config.toml");
        let error = run_with(&path, Some("false"), None, |_, _| Ok(exit_status(7)))
            .unwrap_err()
            .to_string();
        assert!(error.contains("editor `false` exited unsuccessfully"));
    }

    #[cfg(unix)]
    fn exit_status(code: i32) -> ExitStatus {
        use std::os::unix::process::ExitStatusExt as _;
        ExitStatus::from_raw(code << 8)
    }

    #[cfg(windows)]
    fn exit_status(code: i32) -> ExitStatus {
        use std::os::windows::process::ExitStatusExt as _;
        ExitStatus::from_raw(code as u32)
    }
}
