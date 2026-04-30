use std::{
    collections::{BTreeMap, HashMap},
    path::PathBuf,
    sync::Arc,
    time::{Duration, Instant},
};

use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64};
use hmac::{Hmac, Mac};
use jsonwebtoken::{Algorithm, DecodingKey, Validation, decode};
use mlua::{Function, Lua, LuaSerdeExt, Table};
use reqwest::{Client, Method};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest as _, Sha256};
use tokio::sync::{Mutex, RwLock};
use tracing::warn;

use crate::metrics::Metrics;

type HmacSha256 = Hmac<Sha256>;

const KURA_EXTENSION_ENABLED: &str = "KURA_EXTENSION_ENABLED";
const KURA_EXTENSION_SCRIPT_PATH: &str = "KURA_EXTENSION_SCRIPT_PATH";
const KURA_EXTENSION_HOOK_TIMEOUT_MS: &str = "KURA_EXTENSION_HOOK_TIMEOUT_MS";
const KURA_EXTENSION_AUTH_CACHE_ALLOW_TTL_SECONDS: &str =
    "KURA_EXTENSION_AUTH_CACHE_ALLOW_TTL_SECONDS";
const KURA_EXTENSION_AUTH_CACHE_DENY_TTL_SECONDS: &str =
    "KURA_EXTENSION_AUTH_CACHE_DENY_TTL_SECONDS";
const KURA_EXTENSION_FAIL_CLOSED_AUTHENTICATE: &str = "KURA_EXTENSION_FAIL_CLOSED_AUTHENTICATE";
const KURA_EXTENSION_FAIL_CLOSED_AUTHORIZE: &str = "KURA_EXTENSION_FAIL_CLOSED_AUTHORIZE";
const KURA_EXTENSION_FAIL_OPEN_RESPONSE_HEADERS: &str = "KURA_EXTENSION_FAIL_OPEN_RESPONSE_HEADERS";

const SIGNER_PREFIX: &str = "KURA_EXTENSION_SIGNER_";
const JWT_VERIFIER_PREFIX: &str = "KURA_EXTENSION_JWT_VERIFIER_";
const HTTP_CLIENT_PREFIX: &str = "KURA_EXTENSION_HTTP_CLIENT_";

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct Principal {
    pub id: String,
    pub kind: String,
    #[serde(default)]
    pub attributes: Value,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ExtensionContext {
    pub transport: String,
    pub route: String,
    pub method: String,
    pub operation: String,
    pub tenant_id: Option<String>,
    pub namespace_id: Option<String>,
    pub producer: Option<String>,
    pub artifact_key: Option<String>,
    pub artifact_hash: Option<String>,
    #[serde(default)]
    pub headers: BTreeMap<String, String>,
    #[serde(default)]
    pub query: BTreeMap<String, String>,
    pub status_code: Option<u16>,
}

#[derive(Clone, Debug)]
pub enum AccessDecision {
    Allow(Option<Principal>),
    Deny(DenyDecision),
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct DenyDecision {
    pub status: u16,
    pub message: String,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ResponseHeaders {
    pub headers: BTreeMap<String, String>,
}

pub type SharedExtension = Arc<ExtensionEngine>;

pub struct ExtensionEngine {
    config: ExtensionConfig,
    runtime: Mutex<LuaRuntime>,
    principal_cache: RwLock<HashMap<String, CachedAuthenticateResult>>,
    decision_cache: RwLock<HashMap<String, CachedAuthorizeResult>>,
    metrics: Metrics,
    script_hash: String,
}

struct LuaRuntime {
    lua: Lua,
    has_authenticate: bool,
    has_authorize: bool,
    has_response_headers: bool,
}

#[derive(Clone)]
struct Signer {
    algorithm: SignerAlgorithm,
    // Raw HMAC key bytes. The env var carries this as a base64-encoded
    // string (since env vars are text-only and the keys are arbitrary
    // bytes); we decode at parse time so the HMAC matches whoever else
    // signs with the same underlying key. Tuist's central server, for
    // example, stores the license signing key as base64 and decodes
    // before HMAC — Kura must do the same or signatures diverge.
    secret: Vec<u8>,
}

#[derive(Clone)]
enum SignerAlgorithm {
    HmacSha256,
}

#[derive(Clone)]
struct JwtVerifier {
    algorithm: JwtAlgorithm,
    secret: String,
    issuer: Option<String>,
    audiences: Vec<String>,
}

#[derive(Clone)]
enum JwtAlgorithm {
    Hs256,
    Hs384,
    Hs512,
}

#[derive(Clone)]
struct ExtensionHttpClient {
    base_url: String,
    client: Client,
}

#[derive(Clone)]
struct ExtensionConfig {
    script_path: PathBuf,
    hook_timeout: Duration,
    allow_ttl: Duration,
    deny_ttl: Duration,
    fail_closed_authenticate: bool,
    fail_closed_authorize: bool,
    fail_open_response_headers: bool,
    signers: Arc<HashMap<String, Signer>>,
    jwt_verifiers: Arc<HashMap<String, JwtVerifier>>,
    http_clients: Arc<HashMap<String, ExtensionHttpClient>>,
}

#[derive(Clone)]
struct CachedAuthenticateResult {
    expires_at: Instant,
    result: AuthenticateOutcome,
}

#[derive(Clone)]
struct CachedAuthorizeResult {
    expires_at: Instant,
    result: AuthorizeOutcome,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(untagged)]
enum AuthenticateOutcome {
    Principal {
        principal: Principal,
        #[serde(default)]
        ttl_seconds: Option<u64>,
    },
    Anonymous {
        anonymous: bool,
        #[serde(default)]
        ttl_seconds: Option<u64>,
    },
    Deny {
        deny: DenyDecision,
        #[serde(default)]
        ttl_seconds: Option<u64>,
    },
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(untagged)]
enum AuthorizeOutcome {
    Allow {
        allow: bool,
        #[serde(default)]
        ttl_seconds: Option<u64>,
    },
    Deny {
        deny: DenyDecision,
        #[serde(default)]
        ttl_seconds: Option<u64>,
    },
}

#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
struct ResponseHeadersOutcome {
    #[serde(default)]
    headers: BTreeMap<String, String>,
    #[serde(default)]
    sign: Option<SignInstruction>,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
struct SignInstruction {
    header: String,
    signer: String,
    payload: String,
}

#[derive(Debug, Deserialize)]
struct HttpJsonRequest {
    #[serde(default = "default_http_method")]
    method: String,
    path: String,
    #[serde(default)]
    headers: BTreeMap<String, String>,
    #[serde(default)]
    query: BTreeMap<String, String>,
    #[serde(default)]
    body: Option<Value>,
}

#[derive(Debug, Serialize)]
struct HttpJsonResponse {
    status: u16,
    headers: BTreeMap<String, String>,
    body: Value,
}

fn default_http_method() -> String {
    "GET".to_string()
}

impl ExtensionEngine {
    pub async fn from_env(metrics: Metrics) -> Result<Option<SharedExtension>, String> {
        let Some(config) = ExtensionConfig::from_env()? else {
            return Ok(None);
        };
        let engine = Self::new(config, metrics).await?;
        Ok(Some(Arc::new(engine)))
    }

    async fn new(config: ExtensionConfig, metrics: Metrics) -> Result<Self, String> {
        let script = tokio::fs::read_to_string(&config.script_path)
            .await
            .map_err(|error| {
                format!(
                    "failed to read extension script {}: {error}",
                    config.script_path.display()
                )
            })?;
        let script_hash = fingerprint(&script);
        let runtime = LuaRuntime::load(&script, &config).await?;

        Ok(Self {
            config,
            runtime: Mutex::new(runtime),
            principal_cache: RwLock::new(HashMap::new()),
            decision_cache: RwLock::new(HashMap::new()),
            metrics,
            script_hash,
        })
    }

    pub async fn evaluate_access(&self, ctx: &ExtensionContext) -> AccessDecision {
        let authenticate_cache_key = fingerprint(&(
            self.script_hash.as_str(),
            credentials_fingerprint(&ctx.headers),
        ));
        let authenticate = match self
            .cached_authenticate_result(&authenticate_cache_key)
            .await
        {
            Some(result) => {
                self.metrics.record_extension_cache("authenticate", "hit");
                result
            }
            None => {
                self.metrics.record_extension_cache("authenticate", "miss");
                match self.run_authenticate(ctx).await {
                    Ok(result) => {
                        self.store_authenticate_result(&authenticate_cache_key, result.clone())
                            .await;
                        result
                    }
                    Err(error) => {
                        warn!("extension authenticate hook failed: {error}");
                        self.metrics.record_extension_hook(
                            "authenticate",
                            "error",
                            Duration::from_secs(0),
                        );
                        if self.config.fail_closed_authenticate {
                            return AccessDecision::Deny(DenyDecision {
                                status: 401,
                                message: "Authentication failed".into(),
                            });
                        }
                        AuthenticateOutcome::Anonymous {
                            anonymous: true,
                            ttl_seconds: None,
                        }
                    }
                }
            }
        };

        let principal = match authenticate {
            AuthenticateOutcome::Principal { principal, .. } => Some(principal),
            AuthenticateOutcome::Anonymous { .. } => None,
            AuthenticateOutcome::Deny { deny, .. } => return AccessDecision::Deny(deny),
        };

        let authorize_cache_key = fingerprint(&(
            self.script_hash.as_str(),
            credentials_fingerprint(&ctx.headers),
            principal.clone(),
            ctx.tenant_id.clone(),
            ctx.namespace_id.clone(),
            ctx.operation.clone(),
            ctx.producer.clone(),
            ctx.route.clone(),
            ctx.method.clone(),
        ));
        let authorize = match self.cached_authorize_result(&authorize_cache_key).await {
            Some(result) => {
                self.metrics.record_extension_cache("authorize", "hit");
                result
            }
            None => {
                self.metrics.record_extension_cache("authorize", "miss");
                match self.run_authorize(ctx, principal.as_ref()).await {
                    Ok(result) => {
                        self.store_authorize_result(&authorize_cache_key, result.clone())
                            .await;
                        result
                    }
                    Err(error) => {
                        warn!("extension authorize hook failed: {error}");
                        self.metrics.record_extension_hook(
                            "authorize",
                            "error",
                            Duration::from_secs(0),
                        );
                        if self.config.fail_closed_authorize {
                            return AccessDecision::Deny(DenyDecision {
                                status: 403,
                                message: "Forbidden".into(),
                            });
                        }
                        AuthorizeOutcome::Allow {
                            allow: true,
                            ttl_seconds: None,
                        }
                    }
                }
            }
        };

        match authorize {
            AuthorizeOutcome::Allow { allow, .. } if allow => AccessDecision::Allow(principal),
            AuthorizeOutcome::Allow { .. } => AccessDecision::Deny(DenyDecision {
                status: 403,
                message: "Forbidden".into(),
            }),
            AuthorizeOutcome::Deny { deny, .. } => AccessDecision::Deny(deny),
        }
    }

    pub async fn response_headers(
        &self,
        ctx: &ExtensionContext,
        principal: Option<&Principal>,
    ) -> ResponseHeaders {
        match self.run_response_headers(ctx, principal).await {
            Ok(result) => result,
            Err(error) => {
                warn!("extension response_headers hook failed: {error}");
                self.metrics.record_extension_hook(
                    "response_headers",
                    "error",
                    Duration::from_secs(0),
                );
                if self.config.fail_open_response_headers {
                    ResponseHeaders::default()
                } else {
                    ResponseHeaders {
                        headers: BTreeMap::from([(
                            "x-kura-extension-error".into(),
                            "response_headers".into(),
                        )]),
                    }
                }
            }
        }
    }

    async fn run_authenticate(
        &self,
        ctx: &ExtensionContext,
    ) -> Result<AuthenticateOutcome, String> {
        let runtime = self.runtime.lock().await;
        if !runtime.has_authenticate {
            return Ok(AuthenticateOutcome::Anonymous {
                anonymous: true,
                ttl_seconds: None,
            });
        }

        let start = Instant::now();
        let ctx_value = runtime
            .lua
            .to_value(ctx)
            .map_err(|error| format!("failed to serialize authenticate context: {error}"))?;
        let function: Function = runtime
            .lua
            .globals()
            .get("authenticate")
            .map_err(|error| format!("failed to resolve authenticate hook: {error}"))?;
        let outcome = tokio::time::timeout(self.config.hook_timeout, async {
            function.call_async::<mlua::Value>(ctx_value).await
        })
        .await
        .map_err(|_| "authenticate hook timed out".to_string())?
        .map_err(|error| format!("authenticate hook failed: {error}"))?;
        let parsed = runtime
            .lua
            .from_value(outcome)
            .map_err(|error| format!("invalid authenticate hook response: {error}"))?;
        self.metrics
            .record_extension_hook("authenticate", "ok", start.elapsed());
        Ok(parsed)
    }

    async fn run_authorize(
        &self,
        ctx: &ExtensionContext,
        principal: Option<&Principal>,
    ) -> Result<AuthorizeOutcome, String> {
        let runtime = self.runtime.lock().await;
        if !runtime.has_authorize {
            return Ok(AuthorizeOutcome::Allow {
                allow: true,
                ttl_seconds: None,
            });
        }

        let start = Instant::now();
        let ctx_value = runtime
            .lua
            .to_value(ctx)
            .map_err(|error| format!("failed to serialize authorize context: {error}"))?;
        let principal_value = runtime
            .lua
            .to_value(&principal)
            .map_err(|error| format!("failed to serialize authorize principal: {error}"))?;
        let function: Function = runtime
            .lua
            .globals()
            .get("authorize")
            .map_err(|error| format!("failed to resolve authorize hook: {error}"))?;
        let outcome = tokio::time::timeout(self.config.hook_timeout, async {
            function
                .call_async::<mlua::Value>((ctx_value, principal_value))
                .await
        })
        .await
        .map_err(|_| "authorize hook timed out".to_string())?
        .map_err(|error| format!("authorize hook failed: {error}"))?;
        let parsed = runtime
            .lua
            .from_value(outcome)
            .map_err(|error| format!("invalid authorize hook response: {error}"))?;
        self.metrics
            .record_extension_hook("authorize", "ok", start.elapsed());
        Ok(parsed)
    }

    async fn run_response_headers(
        &self,
        ctx: &ExtensionContext,
        principal: Option<&Principal>,
    ) -> Result<ResponseHeaders, String> {
        let runtime = self.runtime.lock().await;
        if !runtime.has_response_headers {
            return Ok(ResponseHeaders::default());
        }

        let start = Instant::now();
        let ctx_value = runtime
            .lua
            .to_value(ctx)
            .map_err(|error| format!("failed to serialize response context: {error}"))?;
        let principal_value = runtime
            .lua
            .to_value(&principal)
            .map_err(|error| format!("failed to serialize response principal: {error}"))?;
        let function: Function = runtime
            .lua
            .globals()
            .get("response_headers")
            .map_err(|error| format!("failed to resolve response_headers hook: {error}"))?;
        let outcome = tokio::time::timeout(self.config.hook_timeout, async {
            function
                .call_async::<mlua::Value>((ctx_value, principal_value))
                .await
        })
        .await
        .map_err(|_| "response_headers hook timed out".to_string())?
        .map_err(|error| format!("response_headers hook failed: {error}"))?;
        let mut parsed: ResponseHeadersOutcome = runtime
            .lua
            .from_value(outcome)
            .map_err(|error| format!("invalid response_headers hook response: {error}"))?;

        if let Some(sign) = parsed.sign.take() {
            let header_value = sign_payload(&self.config.signers, &sign.signer, &sign.payload)?;
            parsed.headers.insert(sign.header, header_value);
        }

        self.metrics
            .record_extension_hook("response_headers", "ok", start.elapsed());
        Ok(ResponseHeaders {
            headers: parsed.headers,
        })
    }

    async fn cached_authenticate_result(&self, key: &str) -> Option<AuthenticateOutcome> {
        let mut cache = self.principal_cache.write().await;
        match cache.get(key) {
            Some(entry) if entry.expires_at > Instant::now() => Some(entry.result.clone()),
            Some(_) => {
                cache.remove(key);
                None
            }
            None => None,
        }
    }

    async fn store_authenticate_result(&self, key: &str, result: AuthenticateOutcome) {
        let ttl = ttl_for_authenticate(&self.config, &result);
        if ttl.is_zero() {
            return;
        }
        let mut cache = self.principal_cache.write().await;
        cache.insert(
            key.to_owned(),
            CachedAuthenticateResult {
                expires_at: Instant::now() + ttl,
                result,
            },
        );
    }

    async fn cached_authorize_result(&self, key: &str) -> Option<AuthorizeOutcome> {
        let mut cache = self.decision_cache.write().await;
        match cache.get(key) {
            Some(entry) if entry.expires_at > Instant::now() => Some(entry.result.clone()),
            Some(_) => {
                cache.remove(key);
                None
            }
            None => None,
        }
    }

    async fn store_authorize_result(&self, key: &str, result: AuthorizeOutcome) {
        let ttl = ttl_for_authorize(&self.config, &result);
        if ttl.is_zero() {
            return;
        }
        let mut cache = self.decision_cache.write().await;
        cache.insert(
            key.to_owned(),
            CachedAuthorizeResult {
                expires_at: Instant::now() + ttl,
                result,
            },
        );
    }
}

impl LuaRuntime {
    async fn load(script: &str, config: &ExtensionConfig) -> Result<Self, String> {
        let lua = Lua::new();
        install_host_api(&lua, config).await?;
        lua.load(script)
            .set_name("kura-extension")
            .exec_async()
            .await
            .map_err(|error| format!("failed to load extension script: {error}"))?;
        let globals = lua.globals();
        let has_authenticate = has_hook(&globals, "authenticate");
        let has_authorize = has_hook(&globals, "authorize");
        let has_response_headers = has_hook(&globals, "response_headers");
        Ok(Self {
            lua,
            has_authenticate,
            has_authorize,
            has_response_headers,
        })
    }
}

fn has_hook(globals: &Table, name: &str) -> bool {
    matches!(
        globals.get::<mlua::Value>(name),
        Ok(mlua::Value::Function(_))
    )
}

async fn install_host_api(lua: &Lua, config: &ExtensionConfig) -> Result<(), String> {
    let kura = lua
        .create_table()
        .map_err(|error| format!("failed to create extension API table: {error}"))?;

    let signers = config.signers.clone();
    let sign = lua
        .create_function(move |_, (id, payload): (String, String)| {
            sign_payload(&signers, &id, &payload).map_err(mlua::Error::external)
        })
        .map_err(|error| format!("failed to install sign_hmac_base64 host function: {error}"))?;
    kura.set("sign_hmac_base64", sign)
        .map_err(|error| format!("failed to export sign_hmac_base64: {error}"))?;

    let verifiers = config.jwt_verifiers.clone();
    let jwt_verify = lua
        .create_function(move |lua, (id, token): (String, String)| {
            let claims = verify_jwt(&verifiers, &id, &token).map_err(mlua::Error::external)?;
            lua.to_value(&claims)
        })
        .map_err(|error| format!("failed to install jwt_verify host function: {error}"))?;
    kura.set("jwt_verify", jwt_verify)
        .map_err(|error| format!("failed to export jwt_verify: {error}"))?;

    let http_clients = config.http_clients.clone();
    let http_json = lua
        .create_async_function(move |lua, (id, request): (String, mlua::Value)| {
            let http_clients = http_clients.clone();
            async move {
                let request: HttpJsonRequest =
                    lua.from_value(request).map_err(mlua::Error::external)?;
                let response = execute_http_json(&http_clients, &id, request)
                    .await
                    .map_err(mlua::Error::external)?;
                lua.to_value(&response)
            }
        })
        .map_err(|error| format!("failed to install http_json host function: {error}"))?;
    kura.set("http_json", http_json)
        .map_err(|error| format!("failed to export http_json: {error}"))?;

    lua.globals()
        .set("kura", kura)
        .map_err(|error| format!("failed to export extension API: {error}"))?;
    Ok(())
}

fn sign_payload(
    signers: &HashMap<String, Signer>,
    signer_id: &str,
    payload: &str,
) -> Result<String, String> {
    let signer = signers
        .get(&normalize_id(signer_id))
        .ok_or_else(|| format!("unknown signer '{signer_id}'"))?;
    match signer.algorithm {
        SignerAlgorithm::HmacSha256 => {
            let mut mac = HmacSha256::new_from_slice(&signer.secret)
                .map_err(|error| format!("failed to initialize signer '{signer_id}': {error}"))?;
            mac.update(payload.as_bytes());
            Ok(BASE64.encode(mac.finalize().into_bytes()))
        }
    }
}

fn verify_jwt(
    verifiers: &HashMap<String, JwtVerifier>,
    verifier_id: &str,
    token: &str,
) -> Result<Value, String> {
    let verifier = verifiers
        .get(&normalize_id(verifier_id))
        .ok_or_else(|| format!("unknown JWT verifier '{verifier_id}'"))?;
    let algorithm = verifier.algorithm.to_algorithm();
    let key = DecodingKey::from_secret(verifier.secret.as_bytes());
    let mut validation = Validation::new(algorithm);
    if let Some(issuer) = verifier.issuer.as_deref() {
        validation.set_issuer(&[issuer]);
    }
    if !verifier.audiences.is_empty() {
        let audiences = verifier
            .audiences
            .iter()
            .map(String::as_str)
            .collect::<Vec<_>>();
        validation.set_audience(&audiences);
    } else {
        validation.validate_aud = false;
    }
    let token = decode::<Value>(token, &key, &validation).map_err(|error| {
        format!("JWT verification failed for verifier '{verifier_id}': {error}")
    })?;
    Ok(token.claims)
}

async fn execute_http_json(
    http_clients: &HashMap<String, ExtensionHttpClient>,
    client_id: &str,
    request: HttpJsonRequest,
) -> Result<HttpJsonResponse, String> {
    let client = http_clients
        .get(&normalize_id(client_id))
        .ok_or_else(|| format!("unknown HTTP client '{client_id}'"))?;

    let method = request
        .method
        .parse::<Method>()
        .map_err(|error| format!("invalid HTTP method '{}': {error}", request.method))?;
    let mut url = client.base_url.trim_end_matches('/').to_string();
    if request.path.starts_with('/') {
        url.push_str(&request.path);
    } else {
        url.push('/');
        url.push_str(&request.path);
    }

    let mut builder = client.client.request(method, &url).query(&request.query);
    for (name, value) in request.headers {
        builder = builder.header(name, value);
    }
    if let Some(body) = request.body {
        builder = builder.json(&body);
    }

    let response = builder
        .send()
        .await
        .map_err(|error| format!("HTTP client '{client_id}' request failed: {error}"))?;
    let status = response.status();
    let headers = response
        .headers()
        .iter()
        .filter_map(|(name, value)| {
            value
                .to_str()
                .ok()
                .map(|value| (name.as_str().to_string(), value.to_string()))
        })
        .collect::<BTreeMap<_, _>>();
    let body = response
        .json::<Value>()
        .await
        .map_err(|error| format!("HTTP client '{client_id}' returned invalid JSON: {error}"))?;

    Ok(HttpJsonResponse {
        status: status.as_u16(),
        headers,
        body,
    })
}

impl ExtensionConfig {
    fn from_env() -> Result<Option<Self>, String> {
        let enabled = env_truthy(KURA_EXTENSION_ENABLED).unwrap_or(false)
            || std::env::var_os(KURA_EXTENSION_SCRIPT_PATH).is_some();
        if !enabled {
            return Ok(None);
        }

        let script_path = required_env(KURA_EXTENSION_SCRIPT_PATH)?;
        let hook_timeout = Duration::from_millis(
            optional_env_parse(KURA_EXTENSION_HOOK_TIMEOUT_MS)?.unwrap_or(25),
        );
        let allow_ttl = Duration::from_secs(
            optional_env_parse(KURA_EXTENSION_AUTH_CACHE_ALLOW_TTL_SECONDS)?.unwrap_or(600),
        );
        let deny_ttl = Duration::from_secs(
            optional_env_parse(KURA_EXTENSION_AUTH_CACHE_DENY_TTL_SECONDS)?.unwrap_or(3),
        );
        let fail_closed_authenticate =
            env_truthy(KURA_EXTENSION_FAIL_CLOSED_AUTHENTICATE).unwrap_or(true);
        let fail_closed_authorize =
            env_truthy(KURA_EXTENSION_FAIL_CLOSED_AUTHORIZE).unwrap_or(true);
        let fail_open_response_headers =
            env_truthy(KURA_EXTENSION_FAIL_OPEN_RESPONSE_HEADERS).unwrap_or(true);

        Ok(Some(Self {
            script_path: PathBuf::from(script_path),
            hook_timeout,
            allow_ttl,
            deny_ttl,
            fail_closed_authenticate,
            fail_closed_authorize,
            fail_open_response_headers,
            signers: Arc::new(parse_signers()?),
            jwt_verifiers: Arc::new(parse_jwt_verifiers()?),
            http_clients: Arc::new(parse_http_clients()?),
        }))
    }
}

fn parse_signers() -> Result<HashMap<String, Signer>, String> {
    let mut grouped = group_resource_envs(SIGNER_PREFIX, &["ALGORITHM", "SECRET"]);
    let mut signers = HashMap::new();

    for (id, values) in grouped.drain() {
        let algorithm = values
            .get("ALGORITHM")
            .map(String::as_str)
            .unwrap_or("hmac-sha256");
        let secret_b64 = values
            .get("SECRET")
            .ok_or_else(|| format!("missing {SIGNER_PREFIX}{id}_SECRET"))?;
        let secret = BASE64.decode(secret_b64.trim()).map_err(|error| {
            format!(
                "{SIGNER_PREFIX}{id}_SECRET must be base64-encoded raw key bytes: {error}"
            )
        })?;
        let algorithm = match algorithm.to_ascii_lowercase().as_str() {
            "hmac-sha256" | "hmac_sha256" | "hmacsha256" => SignerAlgorithm::HmacSha256,
            _ => {
                return Err(format!(
                    "unsupported signer algorithm '{algorithm}' for signer '{id}'"
                ));
            }
        };
        signers.insert(id, Signer { algorithm, secret });
    }

    Ok(signers)
}

fn parse_jwt_verifiers() -> Result<HashMap<String, JwtVerifier>, String> {
    let mut grouped = group_resource_envs(
        JWT_VERIFIER_PREFIX,
        &["ALGORITHM", "SECRET", "ISSUER", "AUDIENCES"],
    );
    let mut verifiers = HashMap::new();

    for (id, values) in grouped.drain() {
        let algorithm = values
            .get("ALGORITHM")
            .map(String::as_str)
            .unwrap_or("HS256");
        let secret = values
            .get("SECRET")
            .cloned()
            .ok_or_else(|| format!("missing {JWT_VERIFIER_PREFIX}{id}_SECRET"))?;
        let algorithm = JwtAlgorithm::parse(algorithm)?;
        let issuer = values
            .get("ISSUER")
            .cloned()
            .filter(|value| !value.is_empty());
        let audiences = values
            .get("AUDIENCES")
            .map(|value| {
                value
                    .split(',')
                    .map(str::trim)
                    .filter(|value| !value.is_empty())
                    .map(ToOwned::to_owned)
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();

        verifiers.insert(
            id,
            JwtVerifier {
                algorithm,
                secret,
                issuer,
                audiences,
            },
        );
    }

    Ok(verifiers)
}

fn parse_http_clients() -> Result<HashMap<String, ExtensionHttpClient>, String> {
    let mut grouped = group_resource_envs(
        HTTP_CLIENT_PREFIX,
        &["BASE_URL", "CONNECT_TIMEOUT_MS", "REQUEST_TIMEOUT_MS"],
    );
    let mut clients = HashMap::new();

    for (id, values) in grouped.drain() {
        let base_url = values
            .get("BASE_URL")
            .cloned()
            .ok_or_else(|| format!("missing {HTTP_CLIENT_PREFIX}{id}_BASE_URL"))?;
        let connect_timeout_ms = values
            .get("CONNECT_TIMEOUT_MS")
            .map(|value| value.parse::<u64>())
            .transpose()
            .map_err(|error| {
                format!("{HTTP_CLIENT_PREFIX}{id}_CONNECT_TIMEOUT_MS must be a valid u64: {error}")
            })?
            .unwrap_or(500);
        let request_timeout_ms = values
            .get("REQUEST_TIMEOUT_MS")
            .map(|value| value.parse::<u64>())
            .transpose()
            .map_err(|error| {
                format!("{HTTP_CLIENT_PREFIX}{id}_REQUEST_TIMEOUT_MS must be a valid u64: {error}")
            })?
            .unwrap_or(1500);
        let client = Client::builder()
            .connect_timeout(Duration::from_millis(connect_timeout_ms))
            .timeout(Duration::from_millis(request_timeout_ms))
            .build()
            .map_err(|error| format!("failed to build HTTP client '{id}': {error}"))?;
        clients.insert(id, ExtensionHttpClient { base_url, client });
    }

    Ok(clients)
}

fn group_resource_envs(
    prefix: &str,
    suffixes: &[&str],
) -> HashMap<String, HashMap<String, String>> {
    let mut grouped: HashMap<String, HashMap<String, String>> = HashMap::new();

    for (key, value) in std::env::vars() {
        if let Some(stripped) = key.strip_prefix(prefix) {
            for suffix in suffixes {
                let suffix_pattern = format!("_{suffix}");
                if let Some(id) = stripped.strip_suffix(&suffix_pattern) {
                    grouped
                        .entry(normalize_id(id))
                        .or_default()
                        .insert((*suffix).to_string(), value.clone());
                    break;
                }
            }
        }
    }

    grouped
}

fn normalize_id(id: &str) -> String {
    id.trim().to_ascii_uppercase()
}

fn ttl_for_authenticate(config: &ExtensionConfig, result: &AuthenticateOutcome) -> Duration {
    match result {
        AuthenticateOutcome::Principal { ttl_seconds, .. }
        | AuthenticateOutcome::Anonymous { ttl_seconds, .. } => ttl_seconds
            .map(Duration::from_secs)
            .unwrap_or(config.allow_ttl),
        AuthenticateOutcome::Deny { ttl_seconds, .. } => ttl_seconds
            .map(Duration::from_secs)
            .unwrap_or(config.deny_ttl),
    }
}

fn ttl_for_authorize(config: &ExtensionConfig, result: &AuthorizeOutcome) -> Duration {
    match result {
        AuthorizeOutcome::Allow { ttl_seconds, .. } => ttl_seconds
            .map(Duration::from_secs)
            .unwrap_or(config.allow_ttl),
        AuthorizeOutcome::Deny { ttl_seconds, .. } => ttl_seconds
            .map(Duration::from_secs)
            .unwrap_or(config.deny_ttl),
    }
}

fn credentials_fingerprint(headers: &BTreeMap<String, String>) -> String {
    let filtered = headers
        .iter()
        .filter(|(name, _)| {
            !matches!(
                name.as_str(),
                "accept" | "content-length" | "host" | "user-agent" | "x-request-id"
            )
        })
        .collect::<BTreeMap<_, _>>();
    fingerprint(&filtered)
}

fn fingerprint<T: Serialize>(value: &T) -> String {
    let bytes = serde_json::to_vec(value).expect("fingerprint input should serialize");
    hex::encode(Sha256::digest(bytes))
}

fn required_env(key: &str) -> Result<String, String> {
    std::env::var(key).map_err(|_| format!("missing required environment variable {key}"))
}

fn optional_env_parse<T>(key: &str) -> Result<Option<T>, String>
where
    T: std::str::FromStr,
    T::Err: std::fmt::Display,
{
    std::env::var(key)
        .ok()
        .map(|value| {
            value
                .parse::<T>()
                .map_err(|error| format!("{key} must be valid: {error}"))
        })
        .transpose()
}

fn env_truthy(key: &str) -> Option<bool> {
    std::env::var(key).ok().map(|value| {
        matches!(
            value.trim().to_ascii_lowercase().as_str(),
            "1" | "true" | "yes" | "on"
        )
    })
}

impl JwtAlgorithm {
    fn parse(value: &str) -> Result<Self, String> {
        match value.trim().to_ascii_uppercase().as_str() {
            "HS256" => Ok(Self::Hs256),
            "HS384" => Ok(Self::Hs384),
            "HS512" => Ok(Self::Hs512),
            _ => Err(format!("unsupported JWT algorithm '{value}'")),
        }
    }

    fn to_algorithm(&self) -> Algorithm {
        match self {
            Self::Hs256 => Algorithm::HS256,
            Self::Hs384 => Algorithm::HS384,
            Self::Hs512 => Algorithm::HS512,
        }
    }
}

#[cfg(test)]
mod tests {
    use std::{
        path::Path,
        sync::{
            Arc,
            atomic::{AtomicUsize, Ordering},
        },
    };

    use axum::{Json, Router, routing::get};
    use tempfile::tempdir;

    use super::*;

    static ENV_LOCK: std::sync::LazyLock<tokio::sync::Mutex<()>> =
        std::sync::LazyLock::new(|| tokio::sync::Mutex::new(()));

    async fn test_engine(script: &str, configure_env: impl FnOnce(&Path)) -> SharedExtension {
        let _guard = ENV_LOCK.lock().await;
        let keys = std::env::vars()
            .map(|(key, _)| key)
            .filter(|key| key.starts_with("KURA_EXTENSION_"))
            .collect::<Vec<_>>();
        unsafe {
            for key in keys {
                std::env::remove_var(key);
            }
        }
        let temp_dir = tempdir().expect("failed to create temp dir");
        let script_path = temp_dir.path().join("hooks.lua");
        tokio::fs::write(&script_path, script)
            .await
            .expect("failed to write script");

        unsafe {
            std::env::set_var(KURA_EXTENSION_ENABLED, "true");
            std::env::set_var(KURA_EXTENSION_SCRIPT_PATH, &script_path);
            std::env::set_var(KURA_EXTENSION_AUTH_CACHE_ALLOW_TTL_SECONDS, "600");
            std::env::set_var(KURA_EXTENSION_AUTH_CACHE_DENY_TTL_SECONDS, "3");
        }
        configure_env(temp_dir.path());

        ExtensionEngine::from_env(Metrics::new("test".into(), "tenant".into()))
            .await
            .expect("failed to build extension engine")
            .expect("extension should be enabled")
    }

    #[tokio::test]
    async fn response_headers_can_sign_payloads() {
        let engine = test_engine(
            r#"
function response_headers(ctx, principal)
  return {
    sign = {
      header = "x-cache-signature",
      signer = "cache_primary",
      payload = ctx.artifact_hash,
    }
  }
end
"#,
            |_| unsafe {
                std::env::set_var(
                    "KURA_EXTENSION_SIGNER_CACHE_PRIMARY_ALGORITHM",
                    "hmac-sha256",
                );
                // Env carries the key as base64; parser decodes to the
                // raw bytes "super-secret".
                std::env::set_var(
                    "KURA_EXTENSION_SIGNER_CACHE_PRIMARY_SECRET",
                    BASE64.encode(b"super-secret"),
                );
            },
        )
        .await;

        let headers = engine
            .response_headers(
                &ExtensionContext {
                    transport: "http".into(),
                    route: "/api/cache/module/{id}".into(),
                    method: "GET".into(),
                    operation: "artifact.read".into(),
                    tenant_id: Some("acme".into()),
                    namespace_id: Some("ios".into()),
                    producer: Some("module".into()),
                    artifact_key: Some("builds/hash-1/Module.framework".into()),
                    artifact_hash: Some("hash-1".into()),
                    headers: BTreeMap::new(),
                    query: BTreeMap::new(),
                    status_code: Some(200),
                },
                None,
            )
            .await;

        let expected = sign_payload(
            &HashMap::from([(
                "CACHE_PRIMARY".into(),
                Signer {
                    algorithm: SignerAlgorithm::HmacSha256,
                    secret: b"super-secret".to_vec(),
                },
            )]),
            "cache_primary",
            "hash-1",
        )
        .expect("failed to compute expected signature");
        assert_eq!(headers.headers.get("x-cache-signature"), Some(&expected));
    }

    #[tokio::test]
    async fn authenticate_results_are_cached_across_identity_lookups() {
        let calls = Arc::new(AtomicUsize::new(0));
        let calls_for_server = calls.clone();
        let app = Router::new().route(
            "/api/projects",
            get(move || {
                let calls = calls_for_server.clone();
                async move {
                    calls.fetch_add(1, Ordering::SeqCst);
                    Json(serde_json::json!({
                        "principal": {
                            "id": "opaque-user",
                            "kind": "user",
                            "attributes": {
                                "projects": ["acme/ios"]
                            }
                        }
                    }))
                }
            }),
        );
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
            .await
            .expect("failed to bind listener");
        let address = listener
            .local_addr()
            .expect("listener should have local addr");
        tokio::spawn(async move {
            axum::serve(listener, app)
                .await
                .expect("mock server should serve");
        });

        let engine = test_engine(
            r#"
function authenticate(ctx)
  local auth = ctx.headers.authorization
  if auth == nil then
    return { deny = { status = 401, message = "Missing authorization" }, ttl_seconds = 3 }
  end

  local response = kura.http_json("identity", {
    method = "GET",
    path = "/api/projects",
    headers = {
      authorization = auth,
    },
  })

  if response.status ~= 200 then
    return { deny = { status = 401, message = "Unauthorized" }, ttl_seconds = 3 }
  end

  return {
    principal = response.body.principal,
    ttl_seconds = 60,
  }
end

function authorize(ctx, principal)
  for _, project in ipairs(principal.attributes.projects) do
    if project == (ctx.tenant_id .. "/" .. ctx.namespace_id) then
      return { allow = true, ttl_seconds = 60 }
    end
  end

  return { deny = { status = 403, message = "Forbidden" }, ttl_seconds = 3 }
end
"#,
            |_| unsafe {
                std::env::set_var(
                    "KURA_EXTENSION_HTTP_CLIENT_IDENTITY_BASE_URL",
                    format!("http://{address}"),
                );
            },
        )
        .await;

        let context = ExtensionContext {
            transport: "http".into(),
            route: "/api/cache/cas/{id}".into(),
            method: "GET".into(),
            operation: "artifact.read".into(),
            tenant_id: Some("acme".into()),
            namespace_id: Some("ios".into()),
            producer: Some("xcode".into()),
            artifact_key: Some("artifact-1".into()),
            artifact_hash: None,
            headers: BTreeMap::from([("authorization".into(), "Bearer opaque".into())]),
            query: BTreeMap::new(),
            status_code: None,
        };

        let first = engine.evaluate_access(&context).await;
        assert!(matches!(first, AccessDecision::Allow(Some(_))));
        let second = engine.evaluate_access(&context).await;
        assert!(matches!(second, AccessDecision::Allow(Some(_))));
        assert_eq!(calls.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn jwt_verifiers_can_authenticate_requests() {
        let engine = test_engine(
            r#"
function authenticate(ctx)
  local auth = ctx.headers.authorization
  if auth == nil then
    return { anonymous = true }
  end
  local token = string.gsub(auth, "^Bearer%s+", "")
  local claims = kura.jwt_verify("primary", token)
  return {
    principal = {
      id = claims.sub,
      kind = "user",
      attributes = claims,
    },
    ttl_seconds = 60,
  }
end

function authorize(ctx, principal)
  if principal.attributes.namespace_id == ctx.namespace_id then
    return { allow = true, ttl_seconds = 60 }
  end
  return { deny = { status = 403, message = "Forbidden" }, ttl_seconds = 3 }
end
"#,
            |_| unsafe {
                std::env::set_var("KURA_EXTENSION_JWT_VERIFIER_PRIMARY_ALGORITHM", "HS256");
                std::env::set_var("KURA_EXTENSION_JWT_VERIFIER_PRIMARY_SECRET", "jwt-secret");
            },
        )
        .await;

        let token = jsonwebtoken::encode(
            &jsonwebtoken::Header::new(Algorithm::HS256),
            &serde_json::json!({
                "sub": "user-1",
                "namespace_id": "ios",
                "exp": 4_000_000_000u64,
            }),
            &jsonwebtoken::EncodingKey::from_secret("jwt-secret".as_bytes()),
        )
        .expect("failed to sign test token");

        let context = ExtensionContext {
            transport: "http".into(),
            route: "/api/cache/cas/{id}".into(),
            method: "GET".into(),
            operation: "artifact.read".into(),
            tenant_id: Some("acme".into()),
            namespace_id: Some("ios".into()),
            producer: Some("xcode".into()),
            artifact_key: Some("artifact-1".into()),
            artifact_hash: None,
            headers: BTreeMap::from([("authorization".into(), format!("Bearer {token}"))]),
            query: BTreeMap::new(),
            status_code: None,
        };

        let result = engine.evaluate_access(&context).await;
        assert!(matches!(result, AccessDecision::Allow(Some(_))));
    }
}
