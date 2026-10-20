//! Turning remote cache configuration into a client.
//!
//! The URL's scheme picks the backend: `https` reaches a cache server speaking
//! the tuist_cargo_cache protocol, and `s3` reaches an object store directly. Both are built
//! here so that a build and `tuist_cargo_cache doctor` cannot disagree about what a given
//! configuration means.

use crate::config::Config;
use eyre::{Context as _, Result, bail};
use std::time::{Duration, SystemTime};
use tuist_cargo_cache_core::{
    InstanceRoleCredentials, RemoteCacheClient, RemoteCacheConfig, S3ConditionalWrites,
    S3Credentials, S3RemoteCacheConfig,
};
use url::Url;

/// What the AWS environment variables say, read once at the edge so that
/// everything below is a decision about configuration rather than about this
/// process's environment.
#[derive(Default)]
pub struct AwsEnvironment {
    /// Credentials, absent when neither the environment nor an instance role
    /// supplied any.
    pub credentials: Option<S3Credentials>,
    /// Region named by `AWS_REGION` or `AWS_DEFAULT_REGION`, or failing both,
    /// the one the instance reports.
    pub region: Option<String>,
    /// The instance role `credentials` came from, and when they expire.
    /// Absent when the environment supplied them.
    pub instance_role: Option<(InstanceRoleCredentials, SystemTime)>,
    /// Why no instance role credentials were used, for the refusal message.
    /// Set before any lookup when the environment names a source that comes
    /// ahead of the instance role, and then no lookup is made.
    pub instance_role_failure: Option<String>,
    /// Why the instance's region could not be read, for the refusal message.
    pub region_failure: Option<String>,
}

/// Where a remote's credentials came from, for `tuist_cargo_cache doctor`.
pub enum CredentialOrigin {
    /// `AWS_ACCESS_KEY_ID` and its companions.
    Environment,
    /// The EC2 instance role, renewed before this instant.
    InstanceRole { expires_at: SystemTime },
}

impl CredentialOrigin {
    /// One line saying where the credentials are from and how long they last.
    pub fn describe(&self) -> String {
        match self {
            Self::Environment => "AWS_ACCESS_KEY_ID in the environment".to_string(),
            Self::InstanceRole { expires_at } => {
                match expires_at.duration_since(SystemTime::now()) {
                    Ok(left) => format!(
                        "EC2 instance role, expires in {}, renewed automatically",
                        format_remaining(left)
                    ),
                    Err(_) => "EC2 instance role, credentials have expired".to_string(),
                }
            }
        }
    }
}

fn format_remaining(left: Duration) -> String {
    let minutes = left.as_secs() / 60;
    match (minutes / 60, minutes % 60) {
        (0, minutes) => format!("{minutes}m"),
        (hours, minutes) => format!("{hours}h {minutes}m"),
    }
}

impl AwsEnvironment {
    fn from_env() -> Self {
        Self {
            credentials: S3Credentials::from_env(),
            instance_role: None,
            instance_role_failure: instance_role_blocker(
                |name| std::env::var(name).ok(),
                |name| read_shared_file(name, |name| std::env::var(name).ok()),
            ),
            region_failure: None,
            region: ["AWS_REGION", "AWS_DEFAULT_REGION"]
                .into_iter()
                .find_map(|name| {
                    std::env::var(name)
                        .ok()
                        .map(|region| region.trim().to_string())
                        .filter(|region| !region.is_empty())
                }),
        }
    }
}

/// Why the instance role must not supply credentials, when the environment
/// names a source that the AWS credential chain consults first.
///
/// tuist_cargo_cache cannot read profiles, web identity, or container credentials itself.
/// Falling through to the instance role would sign as the host's identity,
/// which can be broader than the profile, pod, or task role the environment
/// asks for, so it stops and says what to export instead.
///
/// `shared_file` returns the text of the shared `credentials` or `config`
/// file, `None` when there is no such file, or the reason it could not be read.
/// It is only asked when nothing in the environment already decides.
fn instance_role_blocker(
    var: impl Fn(&str) -> Option<String>,
    shared_file: impl Fn(SharedFile) -> Option<Result<String, String>>,
) -> Option<String> {
    let set = |name: &str| var(name).is_some_and(|value| !value.trim().is_empty());
    if set("AWS_ACCESS_KEY_ID") {
        return Some(
            "AWS_ACCESS_KEY_ID is set without AWS_SECRET_ACCESS_KEY, so the instance role \
             is not used in its place"
                .to_string(),
        );
    }
    let named = [
        "AWS_PROFILE",
        "AWS_WEB_IDENTITY_TOKEN_FILE",
        "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI",
        "AWS_CONTAINER_CREDENTIALS_FULL_URI",
    ]
    .into_iter()
    .find(|name| set(name));
    if let Some(name) = named {
        return Some(format!(
            "{name} is set, and tuist_cargo_cache does not read that credential source. Export its \
             credentials as AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_SESSION_TOKEN, \
             or unset {name} to use the instance role"
        ));
    }
    for file in [SharedFile::Credentials, SharedFile::Config] {
        match shared_file(file) {
            // A file that cannot be inspected might name credentials, so it
            // blocks the instance role like one that does.
            Some(Err(reason)) => {
                return Some(format!(
                    "{reason}, so tuist_cargo_cache cannot tell whether the default AWS profile names \
                     credentials. Fix the file, or point AWS_SHARED_CREDENTIALS_FILE and \
                     AWS_CONFIG_FILE at readable files, to use the instance role"
                ));
            }
            Some(Ok(text)) if default_profile_names_credentials(&text) => {
                return Some(
                    "the default AWS profile names credentials, and tuist_cargo_cache does not read \
                     profiles. Export them as AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and \
                     AWS_SESSION_TOKEN, or point AWS_SHARED_CREDENTIALS_FILE and \
                     AWS_CONFIG_FILE at empty files to use the instance role"
                        .to_string(),
                );
            }
            _ => {}
        }
    }
    None
}

/// The files the AWS tools read profiles from.
#[derive(Clone, Copy)]
enum SharedFile {
    Credentials,
    Config,
}

/// The text of a shared AWS file, from the location the AWS tools would use.
///
/// A file that does not exist is `None`. One that exists but cannot be read,
/// or is not UTF-8, is an error naming the file.
fn read_shared_file(
    file: SharedFile,
    var: impl Fn(&str) -> Option<String>,
) -> Option<Result<String, String>> {
    let (variable, name) = match file {
        SharedFile::Credentials => ("AWS_SHARED_CREDENTIALS_FILE", "credentials"),
        SharedFile::Config => ("AWS_CONFIG_FILE", "config"),
    };
    let path = var(variable)
        .filter(|path| !path.trim().is_empty())
        .map(std::path::PathBuf::from)
        .or_else(|| Some(dirs::home_dir()?.join(".aws").join(name)))?;
    match std::fs::read_to_string(&path) {
        Ok(text) => Some(Ok(text)),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => None,
        Err(error) => Some(Err(format!(
            "{} could not be read: {error}",
            path.display()
        ))),
    }
}

/// Whether a shared file's `default` profile sets a credential source: static
/// keys, a credential process, SSO, or an assumed role.
///
/// A default profile that only sets a region or an output format does not
/// name credentials, and the AWS tools fall through to the instance role past
/// it, so it does not block the lookup here either.
fn default_profile_names_credentials(text: &str) -> bool {
    const CREDENTIAL_KEYS: [&str; 6] = [
        "aws_access_key_id",
        "credential_process",
        "sso_session",
        "sso_start_url",
        "role_arn",
        "web_identity_token_file",
    ];
    let mut in_default = false;
    for line in text.lines().map(str::trim) {
        if line.is_empty() || line.starts_with('#') || line.starts_with(';') {
            continue;
        }
        if let Some(header) = line
            .strip_prefix('[')
            .and_then(|line| line.strip_suffix(']'))
        {
            // The AWS tools accept extra spaces inside the brackets.
            let header: Vec<&str> = header.split_whitespace().collect();
            in_default = matches!(header.as_slice(), ["default"] | ["profile", "default"]);
        } else if in_default {
            let key = line.split('=').next().unwrap_or_default().trim();
            if CREDENTIAL_KEYS.contains(&key) {
                return true;
            }
        }
    }
    false
}

/// A remote cache client and where its credentials came from.
pub struct ConnectedRemote {
    pub client: RemoteCacheClient,
    /// Absent for a cache server, which authenticates with a token instead.
    pub credentials: Option<CredentialOrigin>,
}

/// Build the client the configuration names, or `None` when none is configured.
pub async fn remote_client(config: &Config) -> Result<Option<RemoteCacheClient>> {
    match connect(config).await {
        Ok(remote) => Ok(remote.map(|remote| remote.client)),
        Err(error) if std::env::var_os("TUIST_CARGO_NATIVE").is_some() => {
            log::debug!("remote cache setup failed; retaining local caching: {error:#}");
            Ok(None)
        }
        Err(error) => Err(error),
    }
}

/// Like [`remote_client`], also reporting where the credentials came from.
///
/// An `s3://` remote with no `AWS_ACCESS_KEY_ID` asks the EC2 metadata service
/// for an instance role before giving up, which is the only reason this is
/// async.
pub async fn connect(config: &Config) -> Result<Option<ConnectedRemote>> {
    let mut aws = AwsEnvironment::from_env();
    let is_s3 = is_s3_remote(config);
    if is_s3 && aws.wants_instance_role() {
        aws.use_instance_role(config.remote.s3_region.is_none())
            .await;
    }
    let credentials = match (&aws.credentials, &aws.instance_role) {
        _ if !is_s3 => None,
        (_, Some((_, expires_at))) => Some(CredentialOrigin::InstanceRole {
            expires_at: *expires_at,
        }),
        (Some(_), None) => Some(CredentialOrigin::Environment),
        (None, None) => None,
    };
    Ok(
        remote_client_with(config, aws)?.map(|client| ConnectedRemote {
            client,
            credentials,
        }),
    )
}

/// Whether the URL names an object store. Read from the parsed URL, which
/// lowercases the scheme, so this agrees with how the client is built.
fn is_s3_remote(config: &Config) -> bool {
    config
        .remote
        .url
        .as_deref()
        .and_then(|url| url.trim().parse::<Url>().ok())
        .is_some_and(|url| url.scheme() == "s3")
}

impl AwsEnvironment {
    /// The instance role is the last resort, for an environment that names no
    /// credential source at all. Anything else that is set is a mistake to
    /// report, not a reason to sign as a different identity.
    fn wants_instance_role(&self) -> bool {
        self.credentials.is_none() && self.instance_role_failure.is_none()
    }

    /// Try the EC2 instance role, filling in credentials when it has some.
    /// With `needs_region`, also asks the instance where it runs when no
    /// region was configured.
    async fn use_instance_role(&mut self, needs_region: bool) {
        let provider = match InstanceRoleCredentials::from_env() {
            Ok(Some(provider)) => provider,
            Ok(None) => {
                self.instance_role_failure =
                    Some("instance role lookup is disabled by AWS_EC2_METADATA_DISABLED".into());
                return;
            }
            Err(error) => {
                self.instance_role_failure = Some(format!("{error:#}"));
                return;
            }
        };
        self.fetch_instance_role(provider, needs_region).await;
    }

    async fn fetch_instance_role(&mut self, provider: InstanceRoleCredentials, needs_region: bool) {
        match provider.fetch().await {
            Ok(fetched) => {
                if needs_region && self.region.is_none() {
                    match provider.region().await {
                        Ok(region) => self.region = Some(region),
                        Err(error) => self.region_failure = Some(format!("{error:#}")),
                    }
                }
                self.credentials = Some(fetched.credentials);
                self.instance_role = Some((provider, fetched.expires_at));
            }
            Err(error) => self.instance_role_failure = Some(format!("{error:#}")),
        }
    }
}

pub(crate) fn remote_client_with(
    config: &Config,
    aws: AwsEnvironment,
) -> Result<Option<RemoteCacheClient>> {
    let Some(url) = config
        .remote
        .url
        .as_deref()
        .map(str::trim)
        .filter(|url| !url.is_empty())
    else {
        return Ok(None);
    };
    let url: Url = url.parse().wrap_err("invalid remote cache URL")?;
    let namespace = namespace(config)?;
    if url.scheme() == "s3" {
        return s3_client(config, &url, namespace, aws).map(Some);
    }
    if config.remote.s3_endpoint.is_some()
        || config.remote.s3_region.is_some()
        || config.remote.s3_force_path_style.is_some()
        || config.remote.s3_conditional_writes != S3ConditionalWrites::default()
    {
        bail!("remote.s3_* settings apply to an s3:// remote cache URL, but remote.url is {url}");
    }
    Ok(Some(
        RemoteCacheClient::new(RemoteCacheConfig {
            base_url: url,
            namespace,
            token: config.remote.token.clone(),
            token_file: config.remote.token_file.clone(),
            oidc_audience: config.remote.oidc_audience.clone(),
            connect_timeout: config.http.timeout,
            read_timeout: config.http.timeout,
            download_timeout: config.http.download_timeout,
            retries: config.http.retries,
        })?
        .with_read_stall_budget(config.http.read_stall_budget),
    ))
}

/// The namespace, which isolates one project's cache and is always required.
fn namespace(config: &Config) -> Result<String> {
    config
        .remote
        .namespace
        .as_deref()
        .map(str::trim)
        .filter(|namespace| !namespace.is_empty())
        .map(str::to_string)
        .ok_or_else(|| eyre::eyre!("a remote cache namespace is required when a URL is set"))
}

/// Build a client for `s3://bucket[/prefix]`.
fn s3_client(
    config: &Config,
    url: &Url,
    namespace: String,
    aws: AwsEnvironment,
) -> Result<RemoteCacheClient> {
    // A bearer token or an OIDC audience authenticates to a cache server. An
    // object store authenticates with AWS credentials and would ignore them, so
    // a configuration naming both is a mistake worth reporting rather than
    // quietly half-honouring.
    if config.remote.token.is_some()
        || config.remote.token_file.is_some()
        || config.remote.oidc_audience.is_some()
    {
        bail!(
            "an s3:// remote cache authenticates with AWS credentials; \
             remove remote.token, remote.token_file, and remote.oidc_audience, and set \
             AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY instead"
        );
    }
    let bucket = url
        .host_str()
        .filter(|host| !host.is_empty())
        .ok_or_else(|| eyre::eyre!("an s3:// remote cache URL must name a bucket"))?
        .to_string();
    let endpoint = config
        .remote
        .s3_endpoint
        .as_deref()
        .map(str::trim)
        .filter(|endpoint| !endpoint.is_empty())
        .map(|endpoint| {
            endpoint
                .parse::<Url>()
                .wrap_err("invalid remote.s3_endpoint")
        })
        .transpose()?;
    if let Some(endpoint) = &endpoint {
        validate_endpoint(endpoint)?;
    }
    let Some(credentials) = aws.credentials else {
        let instance_role = aws
            .instance_role_failure
            .map(|reason| format!(" No EC2 instance role was used: {reason}."))
            .unwrap_or_default();
        bail!(
            "an s3:// remote cache needs AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY, or an EC2 \
             instance role.{instance_role} On GitHub Actions, \
             aws-actions/configure-aws-credentials exports credentials from an OIDC role \
             assumption"
        );
    };
    let config = S3RemoteCacheConfig {
        bucket,
        prefix: url.path().to_string(),
        namespace,
        region: region(
            config,
            &aws.region,
            aws.region_failure.as_deref(),
            endpoint.is_some(),
        )?,
        endpoint,
        force_path_style: config.remote.s3_force_path_style,
        conditional_writes: config.remote.s3_conditional_writes,
        credentials,
        connect_timeout: config.http.timeout,
        read_timeout: config.http.timeout,
        download_timeout: config.http.download_timeout,
        retries: config.http.retries,
    };
    match aws.instance_role {
        Some((provider, expires_at)) => {
            RemoteCacheClient::new_s3_with_instance_role(config, provider, expires_at)
        }
        None => RemoteCacheClient::new_s3(config),
    }
}

/// The region requests are signed for.
///
/// A signature is scoped to a region whether or not the store has one, so it is
/// always needed. The AWS variables are consulted before giving up, since a
/// machine set up for the AWS tools has already answered this.
fn region(
    config: &Config,
    environment: &Option<String>,
    lookup_failure: Option<&str>,
    has_endpoint: bool,
) -> Result<String> {
    let configured = config
        .remote
        .s3_region
        .as_deref()
        .map(str::trim)
        .filter(|region| !region.is_empty())
        .map(str::to_string)
        .or_else(|| environment.clone());
    match configured {
        Some(region) => Ok(region),
        // A store reached through an endpoint usually has no region of its own,
        // and signs against whatever it is given.
        None if has_endpoint => Ok("us-east-1".to_string()),
        None => {
            let lookup = lookup_failure
                .map(|reason| format!(" The instance's region could not be read: {reason}."))
                .unwrap_or_default();
            bail!(
                "an s3:// remote cache needs a region; set TUIST_CARGO_CACHE_REMOTE_S3_REGION or AWS_REGION, or run `tuist_cargo_cache settings set remote.s3_region <region>`.{lookup}"
            )
        }
    }
}

/// Refuse an endpoint that would carry credentials over plain HTTP.
///
/// The same rule the protocol client applies to its own URL: a signature and
/// the objects it fetches are readable in transit without TLS, and a developer
/// running MinIO on loopback is the one case where that does not matter.
fn validate_endpoint(endpoint: &Url) -> Result<()> {
    if endpoint.scheme() == "https" {
        return Ok(());
    }
    let loopback = endpoint.host().is_some_and(|host| match host {
        url::Host::Domain(host) => host.eq_ignore_ascii_case("localhost"),
        url::Host::Ipv4(address) => address.is_loopback(),
        url::Host::Ipv6(address) => address.is_loopback(),
    });
    if endpoint.scheme() == "http" && loopback {
        Ok(())
    } else {
        bail!("remote.s3_endpoint must use HTTPS except for loopback development servers")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::RemoteSettings;

    fn aws() -> AwsEnvironment {
        AwsEnvironment {
            credentials: Some(S3Credentials {
                access_key_id: "AKIDEXAMPLE".into(),
                secret_access_key: "secret".into(),
                session_token: None,
            }),
            region: Some("us-west-2".into()),
            ..AwsEnvironment::default()
        }
    }

    fn s3_remote() -> RemoteSettings {
        RemoteSettings {
            url: Some("s3://cache-bucket".into()),
            namespace: Some("acme".into()),
            ..RemoteSettings::default()
        }
    }

    /// The message a configuration is refused with. A client has no `Debug`,
    /// deliberately, so `unwrap_err` is not available here.
    fn refusal(remote: RemoteSettings, aws: AwsEnvironment) -> String {
        match client(remote, aws) {
            Err(error) => error.to_string(),
            Ok(_) => panic!("this configuration should have been refused"),
        }
    }

    fn client(remote: RemoteSettings, aws: AwsEnvironment) -> Result<Option<RemoteCacheClient>> {
        let directory = tempfile::tempdir().unwrap();
        remote_client_with(
            &Config {
                remote,
                ..Config::for_test(directory.path())
            },
            aws,
        )
    }

    #[test]
    fn an_s3_url_builds_an_object_store_client() {
        assert!(client(s3_remote(), aws()).unwrap().is_some());
    }

    #[test]
    fn no_remote_url_builds_no_client() {
        assert!(client(RemoteSettings::default(), aws()).unwrap().is_none());
    }

    #[test]
    fn a_remote_cache_always_needs_a_namespace() {
        let refusal = refusal(
            RemoteSettings {
                namespace: None,
                ..s3_remote()
            },
            aws(),
        );

        assert!(refusal.contains("namespace is required"));
    }

    #[test]
    fn an_s3_remote_without_credentials_says_which_variables_to_set() {
        let refusal = refusal(
            s3_remote(),
            AwsEnvironment {
                credentials: None,
                ..aws()
            },
        );

        assert!(refusal.contains("AWS_ACCESS_KEY_ID"));
    }

    #[test]
    fn a_missing_instance_role_is_named_in_the_refusal() {
        let refusal = refusal(
            s3_remote(),
            AwsEnvironment {
                credentials: None,
                instance_role_failure: Some("the metadata service answered 404".into()),
                ..aws()
            },
        );

        assert!(refusal.contains("AWS_ACCESS_KEY_ID"));
        assert!(refusal.contains("EC2 instance role"));
        assert!(refusal.contains("the metadata service answered 404"));
    }

    #[tokio::test]
    async fn an_instance_role_supplies_credentials_the_environment_lacks() {
        let mut metadata = mockito::Server::new_async().await;
        metadata
            .mock("PUT", "/latest/api/token")
            .with_body("session-token")
            .create_async()
            .await;
        metadata
            .mock("GET", "/latest/meta-data/iam/security-credentials/")
            .with_body("build-runner")
            .create_async()
            .await;
        metadata
            .mock(
                "GET",
                "/latest/meta-data/iam/security-credentials/build-runner",
            )
            .with_body(
                r#"{"Code":"Success","AccessKeyId":"ASIAROLE","SecretAccessKey":"secret","Token":"token","Expiration":"2999-01-01T00:00:00Z"}"#,
            )
            .create_async()
            .await;
        metadata
            .mock("GET", "/latest/meta-data/placement/region")
            .with_body("eu-west-1")
            .create_async()
            .await;
        let provider = InstanceRoleCredentials::new(metadata.url().parse().unwrap()).unwrap();
        let mut environment = AwsEnvironment {
            credentials: None,
            region: None,
            ..aws()
        };

        environment.fetch_instance_role(provider, true).await;

        let credentials = environment.credentials.as_ref().unwrap();
        assert_eq!(credentials.access_key_id, "ASIAROLE");
        assert!(environment.instance_role.is_some());
        // The instance names its own region, so no AWS_REGION is needed.
        assert_eq!(environment.region.as_deref(), Some("eu-west-1"));
        assert!(client(s3_remote(), environment).unwrap().is_some());
    }

    #[test]
    fn a_failed_region_lookup_is_named_in_the_refusal() {
        let refusal = refusal(
            s3_remote(),
            AwsEnvironment {
                region: None,
                region_failure: Some("the metadata service answered 404".into()),
                ..aws()
            },
        );

        assert!(refusal.contains("needs a region"));
        assert!(refusal.contains("the metadata service answered 404"));
    }

    #[test]
    fn a_credential_source_the_instance_role_would_outrank_blocks_the_lookup() {
        let vars = |pairs: &'static [(&'static str, &'static str)]| {
            move |name: &str| {
                pairs
                    .iter()
                    .find(|(key, _)| *key == name)
                    .map(|(_, value)| (*value).to_string())
            }
        };

        assert!(instance_role_blocker(vars(&[]), |_| None).is_none());
        assert!(instance_role_blocker(vars(&[("AWS_ACCESS_KEY_ID", " ")]), |_| None).is_none());
        // AWS_ACCESS_KEY_ID without its secret yields no credentials, but the
        // environment is still the source and the refusal should say so.
        assert!(
            instance_role_blocker(vars(&[("AWS_ACCESS_KEY_ID", "AKIDEXAMPLE")]), |_| None)
                .unwrap()
                .contains("without AWS_SECRET_ACCESS_KEY")
        );
        // EKS IRSA, ECS, and Pod Identity name a narrower identity than the node's.
        for (name, value) in [
            ("AWS_PROFILE", "dev"),
            ("AWS_WEB_IDENTITY_TOKEN_FILE", "/token"),
            (
                "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI",
                "/v2/credentials/x",
            ),
            (
                "AWS_CONTAINER_CREDENTIALS_FULL_URI",
                "http://169.254.170.23/v1/credentials",
            ),
        ] {
            let blocker =
                instance_role_blocker(|asked| (asked == name).then(|| value.to_string()), |_| None);
            assert!(blocker.unwrap().contains(name));
        }
        // A blank AWS_PROFILE names nothing.
        assert!(instance_role_blocker(vars(&[("AWS_PROFILE", " ")]), |_| None).is_none());

        let blocked = AwsEnvironment {
            instance_role_failure: Some("blocked".into()),
            ..AwsEnvironment::default()
        };
        assert!(AwsEnvironment::default().wants_instance_role());
        assert!(!blocked.wants_instance_role());
        assert!(!aws().wants_instance_role());
    }

    #[test]
    fn a_default_profile_with_credentials_blocks_the_lookup() {
        let credentials = "[default]\naws_access_key_id = AKIDEXAMPLE\naws_secret_access_key = x\n";
        let blocker = instance_role_blocker(
            |_| None,
            |file| matches!(file, SharedFile::Credentials).then(|| Ok(credentials.to_string())),
        );
        assert!(blocker.unwrap().contains("default AWS profile"));

        let config = "[default]\nsso_session = work\n";
        assert!(
            instance_role_blocker(
                |_| None,
                |file| matches!(file, SharedFile::Config).then(|| Ok(config.to_string())),
            )
            .is_some()
        );
    }

    #[test]
    fn a_default_profile_without_credentials_leaves_the_instance_role_alone() {
        for text in [
            "",
            "[default]\nregion = eu-west-1\noutput = json\n",
            "# aws_access_key_id = commented\n[default]\nregion = eu-west-1\n",
            "[profile dev]\naws_access_key_id = AKIDEXAMPLE\n[default]\nregion = eu-west-1\n",
            "[other]\ncredential_process = /bin/creds\n",
            "[profile default extra]\ncredential_process = /bin/creds\n",
        ] {
            assert!(!default_profile_names_credentials(text), "{text:?}");
        }
        for text in [
            "[default]\naws_access_key_id=AKIDEXAMPLE\n",
            "[profile default]\ncredential_process = /bin/creds\n",
            "[ profile   default ]\ncredential_process = /bin/creds\n",
            "[  default]\naws_access_key_id = AKIDEXAMPLE\n",
            "[dev]\nregion = x\n[default]\n  ; note\n  role_arn = arn:aws:iam::1:role/x\n",
        ] {
            assert!(default_profile_names_credentials(text), "{text:?}");
        }
    }

    #[test]
    fn shared_files_are_read_from_the_paths_the_aws_tools_use() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("creds");
        std::fs::write(&path, "[default]\naws_access_key_id = AKIDEXAMPLE\n").unwrap();
        let path = path.to_string_lossy().to_string();

        let text = read_shared_file(SharedFile::Credentials, |name| {
            (name == "AWS_SHARED_CREDENTIALS_FILE").then(|| path.clone())
        });
        assert!(text.unwrap().unwrap().contains("AKIDEXAMPLE"));
        // A path that does not exist is no file, not an error.
        assert!(
            read_shared_file(SharedFile::Config, |name| {
                (name == "AWS_CONFIG_FILE").then(|| "/nonexistent/aws-config".to_string())
            })
            .is_none()
        );
    }

    #[test]
    fn a_shared_file_that_cannot_be_read_blocks_the_lookup() {
        let directory = tempfile::tempdir().unwrap();
        // Not UTF-8, and a directory where a file should be.
        let binary = directory.path().join("binary");
        std::fs::write(&binary, [0xff, 0xfe, 0x00]).unwrap();
        for path in [binary.as_path(), directory.path()] {
            let path = path.to_string_lossy().to_string();
            let blocker = instance_role_blocker(
                |_| None,
                |file| {
                    read_shared_file(file, |name| {
                        (name == "AWS_SHARED_CREDENTIALS_FILE").then(|| path.clone())
                    })
                },
            );
            let blocker = blocker.unwrap();
            assert!(blocker.contains("could not be read"), "{blocker}");
            assert!(blocker.contains(&path), "{blocker}");
        }
    }

    #[test]
    fn the_scheme_is_matched_the_way_the_url_parser_reads_it() {
        let config = |url: &str| Config {
            remote: RemoteSettings {
                url: Some(url.into()),
                ..RemoteSettings::default()
            },
            ..Config::for_test(std::path::Path::new("."))
        };

        assert!(is_s3_remote(&config("s3://cache-bucket")));
        assert!(is_s3_remote(&config("S3://cache-bucket")));
        assert!(is_s3_remote(&config("  s3://cache-bucket ")));
        assert!(!is_s3_remote(&config("https://cache.example")));
        assert!(!is_s3_remote(&Config::for_test(std::path::Path::new("."))));
    }

    #[tokio::test]
    async fn an_unreachable_metadata_service_leaves_the_refusal_to_explain() {
        let mut environment = AwsEnvironment {
            credentials: None,
            ..aws()
        };
        // Nothing listens on a port that was just released.
        let port = std::net::TcpListener::bind("127.0.0.1:0")
            .unwrap()
            .local_addr()
            .unwrap()
            .port();
        let provider =
            InstanceRoleCredentials::new(format!("http://127.0.0.1:{port}").parse().unwrap())
                .unwrap();

        environment.fetch_instance_role(provider, true).await;

        assert!(environment.credentials.is_none());
        assert!(environment.instance_role_failure.is_some());
    }

    #[test]
    fn the_credential_origin_says_when_an_instance_role_expires() {
        assert_eq!(
            CredentialOrigin::Environment.describe(),
            "AWS_ACCESS_KEY_ID in the environment"
        );
        let in_six_hours = CredentialOrigin::InstanceRole {
            expires_at: SystemTime::now() + Duration::from_secs(6 * 3_600 - 30),
        };
        assert_eq!(
            in_six_hours.describe(),
            "EC2 instance role, expires in 5h 59m, renewed automatically"
        );
        let lapsed = CredentialOrigin::InstanceRole {
            expires_at: SystemTime::now() - Duration::from_secs(1),
        };
        assert!(lapsed.describe().contains("expired"));
    }

    #[test]
    fn an_s3_remote_falls_back_to_the_aws_environment_for_its_region() {
        let without_region = || AwsEnvironment {
            region: None,
            ..aws()
        };

        // Nothing names a region, and there is no endpoint to excuse it.
        assert!(
            refusal(s3_remote(), without_region()).contains("TUIST_CARGO_CACHE_REMOTE_S3_REGION")
        );

        // The environment names one.
        assert!(client(s3_remote(), aws()).unwrap().is_some());

        // A store behind an endpoint signs against a default instead.
        assert!(
            client(
                RemoteSettings {
                    s3_endpoint: Some("http://127.0.0.1:9000".into()),
                    ..s3_remote()
                },
                without_region(),
            )
            .unwrap()
            .is_some()
        );
    }

    #[test]
    fn bearer_credentials_and_an_object_store_are_not_combined() {
        let refusal = refusal(
            RemoteSettings {
                token: Some("a-token".into()),
                ..s3_remote()
            },
            aws(),
        );

        assert!(refusal.contains("AWS credentials"));
    }

    #[test]
    fn s3_settings_on_a_protocol_url_are_refused() {
        // A setting that quietly does nothing is worse than one that is
        // refused, so every S3-only key is checked, including the one with a
        // default that makes its absence look like its presence.
        for remote in [
            RemoteSettings {
                s3_region: Some("us-west-2".into()),
                ..RemoteSettings::default()
            },
            RemoteSettings {
                s3_endpoint: Some("https://store.example.com".into()),
                ..RemoteSettings::default()
            },
            RemoteSettings {
                s3_force_path_style: Some(true),
                ..RemoteSettings::default()
            },
            RemoteSettings {
                s3_conditional_writes: S3ConditionalWrites::Required,
                ..RemoteSettings::default()
            },
        ] {
            let refusal = refusal(
                RemoteSettings {
                    url: Some("https://cache.example.com".into()),
                    namespace: Some("acme".into()),
                    ..remote
                },
                aws(),
            );
            assert!(refusal.contains("apply to an s3:// remote"), "{refusal}");
        }
    }

    #[test]
    fn a_protocol_url_is_accepted_with_the_s3_settings_left_alone() {
        assert!(
            client(
                RemoteSettings {
                    url: Some("https://cache.example.com".into()),
                    namespace: Some("acme/project".into()),
                    ..RemoteSettings::default()
                },
                aws(),
            )
            .unwrap()
            .is_some()
        );
    }

    #[test]
    fn a_plaintext_endpoint_is_refused_unless_it_is_loopback() {
        let endpoint = |endpoint: &str| {
            client(
                RemoteSettings {
                    s3_endpoint: Some(endpoint.into()),
                    ..s3_remote()
                },
                aws(),
            )
        };

        assert!(endpoint("http://127.0.0.1:9000").unwrap().is_some());
        assert!(endpoint("http://localhost:9000").unwrap().is_some());
        assert!(endpoint("https://store.example.com").unwrap().is_some());
        assert!(
            refusal(
                RemoteSettings {
                    s3_endpoint: Some("http://store.example.com".into()),
                    ..s3_remote()
                },
                aws(),
            )
            .contains("must use HTTPS")
        );
    }
}
