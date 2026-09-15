//! Where the machine's cache endpoint comes from after the proxy has started.
//!
//! The proxy is handed one at exec and then outlives it. It is a per-machine
//! daemon under launchd, while the endpoint belongs to an account whose cache
//! can be moved to another region: the region being left keeps serving for a
//! drain window and is then torn down, taking its hostname out of DNS with it.
//! A proxy still holding that name resolves nothing, and every lookup degrades
//! to a local miss — silently, because a miss is what a cache is allowed to
//! return. The clients that re-resolve on their own ride the drain out; this is
//! how the one that does not gets to.
//!
//! Asked of the CLI rather than of the API directly, so "which endpoint" has
//! one implementation. The CLI already resolves the account's endpoints,
//! probes them for latency and caches the answer under the freshness the
//! server sets; a second resolver here would be a second set of rules to keep
//! in step with it.

use std::process::Command;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResolvedEndpoint {
    /// The endpoint the CLI picked by latency.
    pub url: String,
    /// Every endpoint the server currently serves the account from, or `None`
    /// when the CLI did not report them.
    pub endpoints: Option<Vec<String>>,
}

impl ResolvedEndpoint {
    /// Whether `url` is still one of the account's endpoints. Unknown when the
    /// CLI did not report the list.
    pub fn lists(&self, url: &str) -> Option<bool> {
        self.endpoints.as_ref().map(|endpoints| {
            endpoints
                .iter()
                .any(|endpoint| same_endpoint(endpoint, url))
        })
    }
}

pub fn same_endpoint(a: &str, b: &str) -> bool {
    a.trim_end_matches('/') == b.trim_end_matches('/')
}

/// The endpoint the CLI would use for `full_handle` right now, or `None` when
/// it cannot be asked. `None` is not "no endpoint" — the caller keeps what it
/// has, because a CLI that is missing, unauthenticated or offline says nothing
/// about where the cache moved.
pub fn resolve(
    tuist_bin: &str,
    server_url: Option<&str>,
    full_handle: &str,
) -> Option<ResolvedEndpoint> {
    let mut command = Command::new(tuist_bin);
    // The full handle is positional, not an option.
    command
        .arg("cache")
        .arg("config")
        .arg("--json")
        .arg(full_handle);
    if let Some(url) = server_url {
        command.arg("--url").arg(url);
    }

    let output = command.output().ok()?;
    if !output.status.success() {
        return None;
    }
    resolution_from_json(&String::from_utf8_lossy(&output.stdout))
}

/// The argv `resolve` runs, so the command's shape is asserted rather than
/// discovered the next time someone reads the CLI's help.
#[cfg(test)]
fn argv(tuist_bin: &str, server_url: Option<&str>, full_handle: &str) -> Vec<String> {
    let mut argv = vec![
        tuist_bin.to_string(),
        "cache".to_string(),
        "config".to_string(),
        "--json".to_string(),
        full_handle.to_string(),
    ];
    if let Some(url) = server_url {
        argv.push("--url".to_string());
        argv.push(url.to_string());
    }
    argv
}

/// The `url` and `endpoints` fields of the first JSON object on stdout.
///
/// Read as a stream from the first brace so neither CLI log noise ahead of the
/// payload nor anything printed after it can stop the endpoint being found.
fn resolution_from_json(stdout: &str) -> Option<ResolvedEndpoint> {
    let start = stdout.find('{')?;
    let value = serde_json::Deserializer::from_str(&stdout[start..])
        .into_iter::<serde_json::Value>()
        .next()?
        .ok()?;
    let url = value
        .get("url")?
        .as_str()
        .map(str::trim)
        .filter(|url| !url.is_empty())
        .map(str::to_string)?;
    let endpoints = value
        .get("endpoints")
        .and_then(serde_json::Value::as_array)
        .map(|endpoints| {
            endpoints
                .iter()
                .filter_map(serde_json::Value::as_str)
                .map(str::trim)
                .filter(|endpoint| !endpoint.is_empty())
                .map(str::to_string)
                .collect::<Vec<_>>()
        })
        .filter(|endpoints| !endpoints.is_empty());
    Some(ResolvedEndpoint { url, endpoints })
}

#[cfg(test)]
fn url_from_json(stdout: &str) -> Option<String> {
    resolution_from_json(stdout).map(|resolution| resolution.url)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_url_out_of_the_cli_payload() {
        let stdout = r#"{"url":"https://acme-eu-west-1.kura.tuist.dev","token":"t","accountHandle":"acme","projectHandle":"app"}"#;
        assert_eq!(
            url_from_json(stdout).as_deref(),
            Some("https://acme-eu-west-1.kura.tuist.dev")
        );
    }

    #[test]
    fn survives_log_noise_around_the_payload() {
        let stdout = "resolving endpoints...\n{\n  \"url\" : \"https://acme.kura.tuist.dev\",\n  \"token\" : \"t\"\n}\ndone\n";
        assert_eq!(
            url_from_json(stdout).as_deref(),
            Some("https://acme.kura.tuist.dev")
        );
    }

    #[test]
    fn passes_the_full_handle_positionally() {
        // `tuist cache config` takes it as an argument, not an option; passing
        // `--full-handle` fails the command outright and every refresh becomes
        // a silent no-op.
        assert_eq!(
            argv(
                "/usr/bin/tuist",
                Some("https://staging.tuist.dev"),
                "acme/app"
            ),
            vec![
                "/usr/bin/tuist",
                "cache",
                "config",
                "--json",
                "acme/app",
                "--url",
                "https://staging.tuist.dev"
            ]
        );
        assert_eq!(
            argv("/usr/bin/tuist", None, "acme/app"),
            vec!["/usr/bin/tuist", "cache", "config", "--json", "acme/app"]
        );
    }

    #[test]
    fn reads_the_url_out_of_the_cli_payload_as_the_cli_writes_it() {
        // Real `tuist cache config --json` output: snake_case keys, escaped
        // forward slashes, pretty-printed.
        let stdout = "{\n  \"account_handle\" : \"tuist\",\n  \"url\" : \"https:\\/\\/tuist-eu-west-1-staging.kura.tuist.dev\"\n}";
        assert_eq!(
            url_from_json(stdout).as_deref(),
            Some("https://tuist-eu-west-1-staging.kura.tuist.dev")
        );
    }

    #[test]
    fn reads_every_endpoint_the_account_is_served_from() {
        let stdout = "{\n  \"url\" : \"https:\\/\\/acme-us-central-1.kura.tuist.dev\",\n  \"endpoints\" : [\n    \"https:\\/\\/acme-us-central-1.kura.tuist.dev\",\n    \"https:\\/\\/acme-ap-southeast-1.kura.tuist.dev\"\n  ]\n}";
        let resolution = resolution_from_json(stdout).unwrap();

        assert_eq!(resolution.url, "https://acme-us-central-1.kura.tuist.dev");
        assert_eq!(
            resolution.lists("https://acme-ap-southeast-1.kura.tuist.dev/"),
            Some(true)
        );
        assert_eq!(
            resolution.lists("https://acme-eu-west-1.kura.tuist.dev"),
            Some(false)
        );
    }

    #[test]
    fn an_unreported_endpoint_list_is_unknown_not_empty() {
        let resolution = resolution_from_json(r#"{"url":"https://acme.kura.tuist.dev"}"#).unwrap();

        assert_eq!(resolution.endpoints, None);
        assert_eq!(resolution.lists("https://acme.kura.tuist.dev"), None);
    }

    #[test]
    fn is_nothing_when_there_is_no_usable_url() {
        assert_eq!(url_from_json("not json at all"), None);
        assert_eq!(url_from_json(r#"{"token":"t"}"#), None);
        assert_eq!(url_from_json(r#"{"url":"  "}"#), None);
    }
}
