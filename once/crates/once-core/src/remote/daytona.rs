use std::collections::BTreeMap;

use once_cas::{ActionResult, CacheProvider};
use serde::{Deserialize, Serialize};

use super::join_path;
use crate::stream::{self, Destination};
use crate::{Error, Result, WorkspacePath};

#[derive(Debug)]
struct Config {
    sandbox: String,
    api_url: String,
    api_key: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ExecuteRequest {
    command: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    cwd: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    timeout: Option<u64>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ExecuteResponse {
    #[serde(default, alias = "exitCode")]
    exit_code: Option<i32>,
    #[serde(default)]
    result: Option<String>,
    #[serde(default)]
    stdout: Option<String>,
    #[serde(default)]
    stderr: Option<String>,
    #[serde(default)]
    artifacts: Option<Artifacts>,
}

// Daytona has returned output in several shapes. Prefer the structured
// artifact streams, then legacy stdout/stderr, then the older `result`
// stdout fallback.
#[derive(Deserialize)]
struct Artifacts {
    #[serde(default)]
    stdout: Option<String>,
    #[serde(default)]
    stderr: Option<String>,
}

pub(super) async fn execute_command(
    argv: &[String],
    env: &BTreeMap<String, String>,
    cwd: Option<&WorkspacePath>,
    timeout_ms: Option<u64>,
    cache: &CacheProvider,
    stream_to_parent: bool,
) -> Result<ActionResult> {
    let config = config()?;
    let request = ExecuteRequest {
        command: command(argv, env)?,
        cwd: Some(workdir(cwd)),
        timeout: timeout_ms.map(timeout_secs),
    };
    let url = format!(
        "{}/toolbox/{}/process/execute",
        config.api_url.trim_end_matches('/'),
        config.sandbox
    );
    let response = reqwest::Client::new()
        .post(url)
        .bearer_auth(config.api_key)
        .json(&request)
        .send()
        .await
        .map_err(|source| Error::RemoteProviderHttp {
            provider: "daytona".to_string(),
            source,
        })?;
    let status = response.status();
    if !status.is_success() {
        let body = response.text().await.unwrap_or_else(|_| String::new());
        return Err(Error::RemoteProviderApi {
            provider: "daytona".to_string(),
            message: format!("HTTP {status}: {body}"),
        });
    }
    let response =
        response
            .json::<ExecuteResponse>()
            .await
            .map_err(|source| Error::RemoteProviderHttp {
                provider: "daytona".to_string(),
                source,
            })?;
    let exit_code = exit_code(&response)?;
    let (stdout, stderr) = output_streams(response);
    stream::write_parent(&stdout, Destination::Stdout, stream_to_parent).await?;
    stream::write_parent(&stderr, Destination::Stderr, stream_to_parent).await?;
    let stdout = cache.put_blob(&stdout).await?;
    let stderr = cache.put_blob(&stderr).await?;
    Ok(ActionResult {
        exit_code,
        stdout: Some(stdout),
        stderr: Some(stderr),
        outputs: BTreeMap::new(),
    })
}

fn output_streams(response: ExecuteResponse) -> (Vec<u8>, Vec<u8>) {
    let stdout = response
        .artifacts
        .as_ref()
        .and_then(|artifacts| artifacts.stdout.clone())
        .or(response.stdout)
        .or(response.result)
        .unwrap_or_default()
        .into_bytes();
    let stderr = response
        .artifacts
        .and_then(|artifacts| artifacts.stderr)
        .or(response.stderr)
        .unwrap_or_default()
        .into_bytes();
    (stdout, stderr)
}

fn exit_code(response: &ExecuteResponse) -> Result<i32> {
    response.exit_code.ok_or_else(|| Error::RemoteProviderApi {
        provider: "daytona".to_string(),
        message: "Daytona response did not include an exit code".to_string(),
    })
}

fn config() -> Result<Config> {
    Ok(Config {
        sandbox: env("ONCE_DAYTONA_SANDBOX", "the sandbox id or name")?,
        api_url: std::env::var("ONCE_DAYTONA_API_URL")
            .unwrap_or_else(|_| "https://proxy.app.daytona.io".to_string()),
        api_key: std::env::var("ONCE_DAYTONA_API_KEY")
            .or_else(|_| std::env::var("DAYTONA_API_KEY"))
            .map_err(|_| Error::RemoteProviderConfig {
                provider: "daytona".to_string(),
                message: "set ONCE_DAYTONA_API_KEY or DAYTONA_API_KEY".to_string(),
            })?,
    })
}

fn env(name: &str, description: &str) -> Result<String> {
    let value = std::env::var(name).map_err(|_| Error::RemoteProviderConfig {
        provider: "daytona".to_string(),
        message: format!("set {name} to {description}"),
    })?;
    if value.trim().is_empty() {
        return Err(Error::RemoteProviderConfig {
            provider: "daytona".to_string(),
            message: format!("{name} cannot be empty"),
        });
    }
    Ok(value)
}

fn command(argv: &[String], env: &BTreeMap<String, String>) -> Result<String> {
    if argv.is_empty() {
        return Err(Error::EmptyArgv);
    }

    let mut words = Vec::new();
    if !env.is_empty() {
        words.push(shell_word("env"));
        words.push(shell_word("-i"));
        words.extend(
            env.iter()
                .map(|(key, value)| shell_word(&format!("{key}={value}"))),
        );
    }
    words.extend(argv.iter().map(|word| shell_word(word)));

    Ok(words.join(" "))
}

fn workdir(cwd: Option<&WorkspacePath>) -> String {
    let root = std::env::var("ONCE_DAYTONA_WORKDIR").unwrap_or_else(|_| "/workspace".to_string());
    match cwd {
        Some(cwd) => join_path(&root, cwd.as_str()),
        None => root,
    }
}

fn timeout_secs(timeout_ms: u64) -> u64 {
    timeout_ms.div_ceil(1000).max(1)
}

/// Quotes one POSIX sh word with single quotes. Embedded single quotes
/// are represented as the standard close, escaped quote, reopen
/// sequence.
fn shell_word(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\\''"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn response_requires_exit_code() {
        let response = ExecuteResponse {
            exit_code: None,
            result: Some("ok".to_string()),
            stdout: None,
            stderr: None,
            artifacts: None,
        };

        let error = exit_code(&response).unwrap_err();
        assert!(
            matches!(error, Error::RemoteProviderApi { ref provider, .. } if provider == "daytona")
        );
        assert!(error.to_string().contains("exit code"));
    }

    #[test]
    fn command_quotes_argv_and_env() {
        let env = BTreeMap::from([
            ("EMPTY".to_string(), String::new()),
            ("TOKEN".to_string(), "abc'123".to_string()),
        ]);

        let command = command(
            &[
                "printf".to_string(),
                "%s".to_string(),
                "hello world".to_string(),
            ],
            &env,
        )
        .unwrap();

        assert_eq!(
            command,
            "'env' '-i' 'EMPTY=' 'TOKEN=abc'\\''123' 'printf' '%s' 'hello world'"
        );
    }

    #[test]
    fn shell_word_quotes_empty_values() {
        assert_eq!(shell_word(""), "''");
    }

    #[test]
    fn command_quotes_shell_metacharacters_in_env_values() {
        let env = BTreeMap::from([(
            "SPECIAL".to_string(),
            "line 1\n$(echo nope)`uname`;$HOME".to_string(),
        )]);

        let command = command(&["printenv".to_string(), "SPECIAL".to_string()], &env).unwrap();

        assert_eq!(
            command,
            "'env' '-i' 'SPECIAL=line 1\n$(echo nope)`uname`;$HOME' 'printenv' 'SPECIAL'"
        );
    }

    #[test]
    fn output_streams_use_documented_precedence() {
        let response = ExecuteResponse {
            exit_code: Some(0),
            result: Some("result".to_string()),
            stdout: Some("stdout".to_string()),
            stderr: Some("stderr".to_string()),
            artifacts: Some(Artifacts {
                stdout: Some("artifact stdout".to_string()),
                stderr: Some("artifact stderr".to_string()),
            }),
        };

        let (stdout, stderr) = output_streams(response);

        assert_eq!(stdout, b"artifact stdout");
        assert_eq!(stderr, b"artifact stderr");
    }

    #[test]
    fn timeout_uses_at_least_one_second() {
        assert_eq!(timeout_secs(1), 1);
        assert_eq!(timeout_secs(1_001), 2);
    }
}
