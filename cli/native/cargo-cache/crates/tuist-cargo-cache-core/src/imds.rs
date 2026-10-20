//! Credentials from an EC2 instance role, through IMDSv2.
//!
//! Three small requests against the instance metadata service: a session
//! token, the name of the attached role, and that role's temporary
//! credentials. The AWS SDKs and CLI do the same as the last step of their
//! credential chain, and a runner on EC2 gets working credentials this way
//! without anything exporting them first.

use crate::sigv4::S3Credentials;
use eyre::{Context as _, Result, bail, eyre};
use reqwest::StatusCode;
use serde::Deserialize;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use url::Url;

/// Where the metadata service lives on every EC2 instance.
const DEFAULT_ENDPOINT: &str = "http://169.254.169.254";
/// Lifetime requested for the session token. It is used within a moment and
/// never kept, so this only has to be a value the service accepts.
const TOKEN_TTL_SECONDS: &str = "21600";
/// How long one request may take. The address is link-local, so anything
/// slower than this means no metadata service is listening: a machine that is
/// not on EC2 fails a lookup in about this long.
const REQUEST_TIMEOUT: Duration = Duration::from_secs(1);
/// Attempts per request. The service throttles per instance, and AWS asks
/// clients to retry with exponential backoff, which matters when several jobs
/// start on one runner at once.
const ATTEMPTS: u32 = 3;
/// Wait before the second attempt; each later wait doubles.
const RETRY_BACKOFF: Duration = Duration::from_millis(200);
/// Appended when the token request times out after connecting, which is what a
/// hop limit of 1 looks like from inside a container.
const HOP_LIMIT_HINT: &str = "the metadata service accepted the connection but never answered. \
    From a container, the instance's metadata hop limit may be 1. Raising \
    HttpPutResponseHopLimit to 2 with `aws ec2 modify-instance-metadata-options` fixes \
    that for every container on the instance, so first consider whether they should all \
    be able to use its role";

const TOKEN_TTL_HEADER: &str = "x-aws-ec2-metadata-token-ttl-seconds";
const TOKEN_HEADER: &str = "x-aws-ec2-metadata-token";

/// Temporary credentials and the instant they stop working.
pub struct TemporaryCredentials {
    /// The credentials to sign with.
    pub credentials: S3Credentials,
    /// When the service will start refusing them.
    pub expires_at: SystemTime,
}

/// A source of credentials for the EC2 instance role attached to this machine.
pub struct InstanceRoleCredentials {
    client: reqwest::Client,
    endpoint: Url,
    backoff: Duration,
}

impl InstanceRoleCredentials {
    /// A provider for the metadata service at `endpoint`.
    pub fn new(endpoint: Url) -> Result<Self> {
        Self::with_timing(endpoint, REQUEST_TIMEOUT, RETRY_BACKOFF)
    }

    fn with_timing(endpoint: Url, timeout: Duration, backoff: Duration) -> Result<Self> {
        let client = reqwest::Client::builder()
            .connect_timeout(timeout)
            .timeout(timeout * 2)
            .redirect(reqwest::redirect::Policy::none())
            // A link-local address is never behind a proxy, and sending role
            // credentials through one would hand them to it.
            .no_proxy()
            .build()?;
        Ok(Self {
            client,
            endpoint,
            backoff,
        })
    }

    /// A provider configured the way the AWS SDKs read it, or `None` when
    /// `AWS_EC2_METADATA_DISABLED` turns instance role lookup off.
    ///
    /// `AWS_EC2_METADATA_SERVICE_ENDPOINT` overrides the address, for a proxy
    /// in front of the service or a test double.
    pub fn from_env() -> Result<Option<Self>> {
        Self::from_vars(|name| std::env::var(name).ok())
    }

    fn from_vars(var: impl Fn(&str) -> Option<String>) -> Result<Option<Self>> {
        if var("AWS_EC2_METADATA_DISABLED")
            .is_some_and(|value| value.trim().eq_ignore_ascii_case("true"))
        {
            return Ok(None);
        }
        let endpoint = var("AWS_EC2_METADATA_SERVICE_ENDPOINT")
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty());
        let endpoint = endpoint.as_deref().unwrap_or(DEFAULT_ENDPOINT);
        let endpoint = endpoint
            .parse()
            .wrap_err("invalid AWS_EC2_METADATA_SERVICE_ENDPOINT")?;
        Self::new(endpoint).map(Some)
    }

    /// Ask the metadata service for the role's current credentials.
    ///
    /// The service hands out the same credentials until about five minutes
    /// before they expire, so calling this early returns what a caller already
    /// holds.
    pub async fn fetch(&self) -> Result<TemporaryCredentials> {
        let token = self
            .token()
            .await
            .wrap_err("could not get an IMDSv2 session token")?;
        let roles = self
            .get(&token, "latest/meta-data/iam/security-credentials/")
            .await
            .wrap_err("could not list the instance's IAM roles")?;
        let role = roles
            .lines()
            .map(str::trim)
            .find(|line| !line.is_empty())
            .ok_or_else(|| eyre!("the instance has no IAM role attached"))?;
        let document = self
            .get(
                &token,
                &format!("latest/meta-data/iam/security-credentials/{role}"),
            )
            .await
            .wrap_err_with(|| format!("could not read credentials for role {role}"))?;
        parse_role_document(&document)
    }

    /// The region the instance runs in, for a machine that names none itself.
    ///
    /// The metadata service answers this without any role, so it is a separate
    /// lookup that only runs when the region would otherwise be missing.
    pub async fn region(&self) -> Result<String> {
        let token = self
            .token()
            .await
            .wrap_err("could not get an IMDSv2 session token")?;
        let region = self
            .get(&token, "latest/meta-data/placement/region")
            .await
            .wrap_err("could not read the instance's region")?;
        let region = region.trim();
        if region.is_empty() {
            bail!("the metadata service returned an empty region");
        }
        Ok(region.to_string())
    }

    async fn token(&self) -> Result<String> {
        let request = self
            .client
            .put(self.endpoint.join("latest/api/token")?)
            .header(TOKEN_TTL_HEADER, TOKEN_TTL_SECONDS);
        let token = self.send(request).await.map_err(|error| {
            let unanswered = error
                .downcast_ref::<reqwest::Error>()
                .is_some_and(|error| error.is_timeout() && !error.is_connect());
            if unanswered {
                error.wrap_err(HOP_LIMIT_HINT)
            } else {
                error
            }
        })?;
        Ok(token.trim().to_string())
    }

    async fn get(&self, token: &str, path: &str) -> Result<String> {
        let request = self
            .client
            .get(self.endpoint.join(path)?)
            .header(TOKEN_HEADER, token);
        self.send(request).await
    }

    /// Send a request and return the body of a successful answer.
    ///
    /// Throttling, server errors, and a request that connected but got no
    /// answer are tried again. A refusal to connect is not: nothing is
    /// listening, and waiting would only slow the answer on a machine that is
    /// not on EC2.
    async fn send(&self, request: reqwest::RequestBuilder) -> Result<String> {
        let mut attempt = 1;
        loop {
            let request = request
                .try_clone()
                .expect("a request without a body can be cloned");
            let (error, transient) = match request.send().await {
                Ok(response) if response.status().is_success() => match response.text().await {
                    Ok(body) => return Ok(body),
                    Err(error) => (eyre::Report::new(error), true),
                },
                Ok(response) => {
                    let status = response.status();
                    let transient =
                        status == StatusCode::TOO_MANY_REQUESTS || status.is_server_error();
                    (eyre!("the metadata service answered {status}"), transient)
                }
                Err(error) => {
                    let transient = !error.is_connect();
                    (eyre::Report::new(error), transient)
                }
            };
            if !transient || attempt == ATTEMPTS {
                return Err(error);
            }
            tokio::time::sleep(self.backoff * 2u32.pow(attempt - 1)).await;
            attempt += 1;
        }
    }
}

/// The JSON document under `security-credentials/<role>`.
///
/// Every field is optional because a failing lookup returns a document with a
/// `Code` and none of the credentials.
#[derive(Deserialize)]
#[serde(rename_all = "PascalCase")]
struct RoleDocument {
    code: Option<String>,
    access_key_id: Option<String>,
    secret_access_key: Option<String>,
    token: Option<String>,
    expiration: Option<String>,
}

fn parse_role_document(document: &str) -> Result<TemporaryCredentials> {
    // The body is never included in an error: it carries the secret.
    let document: RoleDocument = serde_json::from_str(document).map_err(|_| {
        eyre!("the metadata service returned a credentials document tuist_cargo_cache cannot read")
    })?;
    if let Some(code) = document.code.as_deref().filter(|code| *code != "Success") {
        bail!("the metadata service reported {code} for the instance role");
    }
    let (Some(access_key_id), Some(secret_access_key), Some(expiration)) = (
        document.access_key_id,
        document.secret_access_key,
        document.expiration,
    ) else {
        bail!("the instance role's credentials document is missing fields");
    };
    Ok(TemporaryCredentials {
        credentials: S3Credentials {
            access_key_id,
            secret_access_key,
            session_token: document.token.filter(|token| !token.is_empty()),
        },
        expires_at: parse_timestamp(&expiration)?,
    })
}

/// Parse the `2026-09-29T18:45:12Z` form the metadata service uses.
///
/// A fractional second is accepted and dropped. A numeric UTC offset is not,
/// since the service always answers in UTC.
fn parse_timestamp(text: &str) -> Result<SystemTime> {
    let invalid = || eyre!("the instance role's expiration is not a UTC timestamp");
    let text = text.trim().strip_suffix('Z').ok_or_else(invalid)?;
    let (date, time) = text.split_once('T').ok_or_else(invalid)?;
    let time = time.split_once('.').map_or(time, |(whole, _)| whole);
    let number = |part: &str| part.parse::<i64>().map_err(|_| invalid());
    let date = date.split('-').map(number).collect::<Result<Vec<_>>>()?;
    let time = time.split(':').map(number).collect::<Result<Vec<_>>>()?;
    let [year, month, day] = date[..].try_into().map_err(|_| invalid())?;
    let [hour, minute, second] = time[..].try_into().map_err(|_| invalid())?;
    if !(1..=12).contains(&month)
        || !(1..=31).contains(&day)
        || !(0..24).contains(&hour)
        || !(0..60).contains(&minute)
        || !(0..=60).contains(&second)
    {
        return Err(invalid());
    }
    let seconds = days_from_civil(year, month, day) * 86_400 + hour * 3_600 + minute * 60 + second;
    u64::try_from(seconds)
        .map(|seconds| UNIX_EPOCH + Duration::from_secs(seconds))
        .map_err(|_| invalid())
}

/// The inverse of `civil_from_days` in `sigv4`, from the same source.
fn days_from_civil(year: i64, month: i64, day: i64) -> i64 {
    let year = if month <= 2 { year - 1 } else { year };
    let era = if year >= 0 { year } else { year - 399 } / 400;
    let year_of_era = year - era * 400;
    let shifted_month = if month > 2 { month - 3 } else { month + 9 };
    let day_of_year = (153 * shifted_month + 2) / 5 + day - 1;
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    era * 146_097 + day_of_era - 719_468
}

#[cfg(test)]
mod tests {
    use super::*;

    fn provider(server: &mockito::ServerGuard) -> InstanceRoleCredentials {
        InstanceRoleCredentials::with_timing(
            server.url().parse().unwrap(),
            Duration::from_secs(1),
            Duration::from_millis(1),
        )
        .unwrap()
    }

    fn role_document(expiration: &str) -> String {
        format!(
            r#"{{"Code":"Success","LastUpdated":"2026-09-29T12:00:00Z","Type":"AWS-HMAC","AccessKeyId":"ASIAROLE","SecretAccessKey":"role-secret","Token":"role-token","Expiration":"{expiration}"}}"#
        )
    }

    #[test]
    fn a_timestamp_parses_to_the_instant_it_names() {
        let parsed = parse_timestamp("2026-09-29T18:45:12Z").unwrap();
        assert_eq!(parsed, UNIX_EPOCH + Duration::from_secs(1_790_707_512));
        // The leap day and the epoch itself.
        assert_eq!(parse_timestamp("1970-01-01T00:00:00Z").unwrap(), UNIX_EPOCH);
        assert_eq!(
            parse_timestamp("2024-02-29T00:00:00Z").unwrap(),
            UNIX_EPOCH + Duration::from_secs(1_709_164_800)
        );
        assert_eq!(parse_timestamp("2026-09-29T18:45:12.500Z").unwrap(), parsed);
    }

    #[test]
    fn a_malformed_timestamp_is_refused() {
        for text in [
            "",
            "2026-09-29",
            "2026-09-29T18:45:12",
            "2026-09-29T18:45:12+02:00",
            "2026-13-29T18:45:12Z",
            "2026-09-29T25:45:12Z",
            "2026-09-29T18:45Z",
            "2026-09-29-01T18:45:12Z",
            "yesterday",
        ] {
            assert!(parse_timestamp(text).is_err(), "{text:?} should be refused");
        }
    }

    #[test]
    fn a_role_document_becomes_credentials() {
        let parsed = parse_role_document(&role_document("2026-09-29T18:45:12Z")).unwrap();
        assert_eq!(parsed.credentials.access_key_id, "ASIAROLE");
        assert_eq!(parsed.credentials.secret_access_key, "role-secret");
        assert_eq!(
            parsed.credentials.session_token.as_deref(),
            Some("role-token")
        );
        assert_eq!(
            parsed.expires_at,
            UNIX_EPOCH + Duration::from_secs(1_790_707_512)
        );
    }

    #[test]
    fn a_failure_document_names_its_code_and_nothing_secret() {
        let error = parse_role_document(r#"{"Code":"AssumeRoleUnauthorizedAccess"}"#)
            .err()
            .unwrap()
            .to_string();
        assert!(error.contains("AssumeRoleUnauthorizedAccess"));

        let error = parse_role_document("not json with SECRET inside")
            .err()
            .unwrap()
            .to_string();
        assert!(!error.contains("SECRET"));
    }

    #[test]
    fn the_environment_can_disable_or_redirect_the_lookup() {
        let vars = |pairs: &'static [(&'static str, &'static str)]| {
            move |name: &str| {
                pairs
                    .iter()
                    .find(|(key, _)| *key == name)
                    .map(|(_, value)| (*value).to_string())
            }
        };

        assert!(
            InstanceRoleCredentials::from_vars(vars(&[("AWS_EC2_METADATA_DISABLED", "TRUE")]))
                .unwrap()
                .is_none()
        );
        // Only "true" disables it, as in the SDKs.
        assert!(
            InstanceRoleCredentials::from_vars(vars(&[("AWS_EC2_METADATA_DISABLED", "false")]))
                .unwrap()
                .is_some()
        );
        let redirected = InstanceRoleCredentials::from_vars(vars(&[(
            "AWS_EC2_METADATA_SERVICE_ENDPOINT",
            "http://127.0.0.1:1338",
        )]))
        .unwrap()
        .unwrap();
        assert_eq!(redirected.endpoint.as_str(), "http://127.0.0.1:1338/");
        assert!(
            InstanceRoleCredentials::from_vars(vars(&[(
                "AWS_EC2_METADATA_SERVICE_ENDPOINT",
                "not a url",
            )]))
            .is_err()
        );
        let default = InstanceRoleCredentials::from_vars(vars(&[]))
            .unwrap()
            .unwrap();
        assert_eq!(default.endpoint.as_str(), "http://169.254.169.254/");
    }

    #[tokio::test]
    async fn the_three_requests_yield_the_roles_credentials() {
        let mut server = mockito::Server::new_async().await;
        let token = server
            .mock("PUT", "/latest/api/token")
            .match_header(TOKEN_TTL_HEADER, TOKEN_TTL_SECONDS)
            .with_body("session-token\n")
            .create_async()
            .await;
        let roles = server
            .mock("GET", "/latest/meta-data/iam/security-credentials/")
            .match_header(TOKEN_HEADER, "session-token")
            .with_body("build-runner\n")
            .create_async()
            .await;
        let credentials = server
            .mock(
                "GET",
                "/latest/meta-data/iam/security-credentials/build-runner",
            )
            .match_header(TOKEN_HEADER, "session-token")
            .with_body(role_document("2026-09-29T18:45:12Z"))
            .create_async()
            .await;

        let fetched = provider(&server).fetch().await.unwrap();

        assert_eq!(fetched.credentials.access_key_id, "ASIAROLE");
        token.assert_async().await;
        roles.assert_async().await;
        credentials.assert_async().await;
    }

    #[tokio::test]
    async fn the_instances_region_is_read_from_placement_metadata() {
        let mut server = mockito::Server::new_async().await;
        server
            .mock("PUT", "/latest/api/token")
            .with_body("session-token")
            .create_async()
            .await;
        server
            .mock("GET", "/latest/meta-data/placement/region")
            .match_header(TOKEN_HEADER, "session-token")
            .with_body("eu-west-1\n")
            .create_async()
            .await;

        assert_eq!(provider(&server).region().await.unwrap(), "eu-west-1");
    }

    #[tokio::test]
    async fn a_service_that_refuses_the_token_is_reported() {
        let mut server = mockito::Server::new_async().await;
        let token = server
            .mock("PUT", "/latest/api/token")
            .with_status(403)
            .expect(1)
            .create_async()
            .await;

        let error = format!("{:#}", provider(&server).fetch().await.err().unwrap());

        assert!(error.contains("session token"), "{error}");
        assert!(error.contains("403"), "{error}");
        // A refusal is an answer, so it is not asked again.
        token.assert_async().await;
    }

    #[tokio::test]
    async fn throttling_and_server_errors_are_retried() {
        for status in [429, 503] {
            let mut server = mockito::Server::new_async().await;
            let throttled = server
                .mock("PUT", "/latest/api/token")
                .with_status(status)
                .expect(2)
                .create_async()
                .await;
            let token = server
                .mock("PUT", "/latest/api/token")
                .with_body("session-token")
                .expect(1)
                .create_async()
                .await;
            server
                .mock("GET", "/latest/meta-data/placement/region")
                .with_body("eu-west-1")
                .create_async()
                .await;

            assert_eq!(provider(&server).region().await.unwrap(), "eu-west-1");

            throttled.assert_async().await;
            token.assert_async().await;
        }
    }

    #[tokio::test]
    async fn retries_stop_after_the_last_attempt() {
        let mut server = mockito::Server::new_async().await;
        let token = server
            .mock("PUT", "/latest/api/token")
            .with_status(503)
            .expect(ATTEMPTS as usize)
            .create_async()
            .await;

        let error = format!("{:#}", provider(&server).fetch().await.err().unwrap());

        assert!(error.contains("503"), "{error}");
        token.assert_async().await;
    }

    #[tokio::test]
    async fn a_token_request_that_connects_but_gets_no_answer_mentions_the_hop_limit() {
        // Accepts connections and never replies, as a hop limit of 1 does.
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let held = tokio::spawn(async move {
            let mut connections = Vec::new();
            while let Ok((connection, _)) = listener.accept().await {
                connections.push(connection);
            }
        });
        let provider = InstanceRoleCredentials::with_timing(
            format!("http://{address}").parse().unwrap(),
            Duration::from_millis(50),
            Duration::from_millis(1),
        )
        .unwrap();

        let error = format!("{:#}", provider.fetch().await.err().unwrap());
        held.abort();

        assert!(error.contains("HttpPutResponseHopLimit"), "{error}");
    }

    #[tokio::test]
    async fn an_instance_without_a_role_is_reported() {
        let mut server = mockito::Server::new_async().await;
        server
            .mock("PUT", "/latest/api/token")
            .with_body("session-token")
            .create_async()
            .await;
        server
            .mock("GET", "/latest/meta-data/iam/security-credentials/")
            .with_body("")
            .create_async()
            .await;

        let error = format!("{:#}", provider(&server).fetch().await.err().unwrap());

        assert!(error.contains("no IAM role"), "{error}");
    }

    #[tokio::test]
    async fn nothing_listening_fails_within_the_timeout() {
        // Bind and drop to get a port nothing answers on.
        let port = std::net::TcpListener::bind("127.0.0.1:0")
            .unwrap()
            .local_addr()
            .unwrap()
            .port();
        let provider =
            InstanceRoleCredentials::new(format!("http://127.0.0.1:{port}").parse().unwrap())
                .unwrap();

        let started = std::time::Instant::now();
        assert!(provider.fetch().await.is_err());
        assert!(started.elapsed() < Duration::from_secs(3));
    }
}
