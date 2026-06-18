use std::{
    collections::{BTreeMap, HashMap},
    error::Error as _,
    path::PathBuf,
    sync::Arc,
    time::{Duration, Instant},
};

use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64};
use hmac::{Hmac, Mac};
use jsonwebtoken::{Algorithm, DecodingKey, Validation, decode};
use mlua::{Function, Lua, LuaSerdeExt, SerializeOptions, Table};

// Map Rust `None` to Lua `nil` rather than mlua's default `null`
// userdata sentinel. The hook is allowed to write idiomatic
// `if ctx.foo ~= nil` checks; without this, optional ExtensionContext
// fields would slip through as userdata and blow up when the hook
// tried to compare or concatenate them.
const SERIALIZE_NONE_AS_NIL: SerializeOptions = SerializeOptions::new()
    .serialize_none_to_null(false)
    .serialize_unit_to_null(false);
use reqwest::{Client, Method, RequestBuilder};
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
const KURA_EXTENSION_CACHE_MAX_ENTRIES: &str = "KURA_EXTENSION_CACHE_MAX_ENTRIES";
const DEFAULT_EXTENSION_CACHE_MAX_ENTRIES: usize = 100_000;

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
    pub server_tenant_id: String,
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
    cache_max_entries: usize,
    signers: Arc<HashMap<String, Signer>>,
    jwt_verifiers: Arc<HashMap<String, JwtVerifier>>,
    http_clients: Arc<HashMap<String, ExtensionHttpClient>>,
    env: Arc<HashMap<String, String>>,
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

#[derive(Clone, Debug, Deserialize)]
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

    // Build an engine from a script file directly, bypassing the global-env
    // parsing of `from_env`. Lets other modules' tests exercise the gRPC/HTTP
    // handlers with a known policy script without racing on process env.
    #[cfg(test)]
    pub(crate) async fn from_script_for_test(
        script_path: PathBuf,
        metrics: Metrics,
    ) -> Result<SharedExtension, String> {
        let config = ExtensionConfig {
            script_path,
            hook_timeout: Duration::from_millis(1000),
            allow_ttl: Duration::from_secs(600),
            deny_ttl: Duration::from_secs(3),
            fail_closed_authenticate: true,
            fail_closed_authorize: true,
            fail_open_response_headers: true,
            cache_max_entries: 1000,
            signers: Arc::new(HashMap::new()),
            jwt_verifiers: Arc::new(HashMap::new()),
            http_clients: Arc::new(HashMap::new()),
            env: Arc::new(HashMap::new()),
        };
        Ok(Arc::new(Self::new(config, metrics).await?))
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
        let runtime = LuaRuntime::load(&script, &config, metrics.clone()).await?;

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
            ctx.server_tenant_id.clone(),
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

    pub async fn clear_caches(&self) -> usize {
        let mut principal_cache = self.principal_cache.write().await;
        let principal_evicted = principal_cache.len();
        principal_cache.clear();
        drop(principal_cache);

        let mut decision_cache = self.decision_cache.write().await;
        let decision_evicted = decision_cache.len();
        decision_cache.clear();

        principal_evicted + decision_evicted
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
            .to_value_with(ctx, SERIALIZE_NONE_AS_NIL)
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
            .to_value_with(ctx, SERIALIZE_NONE_AS_NIL)
            .map_err(|error| format!("failed to serialize authorize context: {error}"))?;
        let principal_value = runtime
            .lua
            .to_value_with(&principal, SERIALIZE_NONE_AS_NIL)
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
            .to_value_with(ctx, SERIALIZE_NONE_AS_NIL)
            .map_err(|error| format!("failed to serialize response context: {error}"))?;
        let principal_value = runtime
            .lua
            .to_value_with(&principal, SERIALIZE_NONE_AS_NIL)
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
        let max_entries = self.config.cache_max_entries;
        if cache.len() >= max_entries && !cache.contains_key(key) {
            evict_expired_authenticate(&mut cache);
            if cache.len() >= max_entries {
                self.metrics
                    .record_extension_cache("authenticate", "rejected");
                return;
            }
        }
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
        let max_entries = self.config.cache_max_entries;
        if cache.len() >= max_entries && !cache.contains_key(key) {
            evict_expired_authorize(&mut cache);
            if cache.len() >= max_entries {
                self.metrics.record_extension_cache("authorize", "rejected");
                return;
            }
        }
        cache.insert(
            key.to_owned(),
            CachedAuthorizeResult {
                expires_at: Instant::now() + ttl,
                result,
            },
        );
    }
}

fn evict_expired_authenticate(cache: &mut HashMap<String, CachedAuthenticateResult>) {
    let now = Instant::now();
    cache.retain(|_, entry| entry.expires_at > now);
}

fn evict_expired_authorize(cache: &mut HashMap<String, CachedAuthorizeResult>) {
    let now = Instant::now();
    cache.retain(|_, entry| entry.expires_at > now);
}

impl LuaRuntime {
    async fn load(
        script: &str,
        config: &ExtensionConfig,
        metrics: Metrics,
    ) -> Result<Self, String> {
        let lua = Lua::new();
        install_host_api(&lua, config, metrics).await?;
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

async fn install_host_api(
    lua: &Lua,
    config: &ExtensionConfig,
    metrics: Metrics,
) -> Result<(), String> {
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
            let metrics = metrics.clone();
            async move {
                let request: HttpJsonRequest =
                    lua.from_value(request).map_err(mlua::Error::external)?;
                let response = execute_http_json(&http_clients, &metrics, &id, request)
                    .await
                    .map_err(mlua::Error::external)?;
                lua.to_value(&response)
            }
        })
        .map_err(|error| format!("failed to install http_json host function: {error}"))?;
    kura.set("http_json", http_json)
        .map_err(|error| format!("failed to export http_json: {error}"))?;

    let extension_env = config.env.clone();
    let env = lua
        .create_function(move |lua, key: String| match extension_env.get(&key) {
            Some(value) => Ok(mlua::Value::String(lua.create_string(value)?)),
            None => Ok(mlua::Value::Nil),
        })
        .map_err(|error| format!("failed to install env host function: {error}"))?;
    kura.set("env", env)
        .map_err(|error| format!("failed to export env: {error}"))?;

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
    metrics: &Metrics,
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

    let route = extension_http_route_label(&request.path);
    let normalized_client_id = normalize_id(client_id);
    let mut attempt = 0;
    let response = loop {
        attempt += 1;
        let start = Instant::now();
        let result = build_http_json_request(client, method.clone(), &url, &request)
            .send()
            .await;
        match result {
            Ok(response) => {
                metrics.record_extension_http_client(
                    &normalized_client_id,
                    route,
                    "ok",
                    status_class(response.status().as_u16()),
                    "none",
                    start.elapsed(),
                );
                break response;
            }
            Err(error) => {
                let error_kind = classify_reqwest_error(&error);
                metrics.record_extension_http_client(
                    &normalized_client_id,
                    route,
                    "error",
                    "none",
                    error_kind,
                    start.elapsed(),
                );
                if attempt < 2 && retryable_reqwest_error(error_kind) {
                    tokio::time::sleep(Duration::from_millis(100)).await;
                    continue;
                }
                return Err(format!(
                    "HTTP client '{client_id}' request failed after {attempt} attempt(s): {}",
                    format_reqwest_error(&error)
                ));
            }
        }
    };
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

fn build_http_json_request(
    client: &ExtensionHttpClient,
    method: Method,
    url: &str,
    request: &HttpJsonRequest,
) -> RequestBuilder {
    let mut builder = client.client.request(method, url).query(&request.query);
    for (name, value) in &request.headers {
        builder = builder.header(name, value);
    }
    if let Some(body) = &request.body {
        builder = builder.json(body);
    }
    builder
}

fn extension_http_route_label(path: &str) -> &'static str {
    match path {
        "/oauth2/introspect" => "oauth2_introspect",
        "/api/cache/access" => "api_cache_access",
        _ => "other",
    }
}

fn status_class(status: u16) -> &'static str {
    match status {
        100..=199 => "1xx",
        200..=299 => "2xx",
        300..=399 => "3xx",
        400..=499 => "4xx",
        500..=599 => "5xx",
        _ => "other",
    }
}

fn classify_reqwest_error(error: &reqwest::Error) -> &'static str {
    let chain = error_chain_string(error);
    if error.is_timeout() {
        "timeout"
    } else if chain.contains("dns") {
        "dns"
    } else if chain.contains("tls") || chain.contains("certificate") {
        "tls"
    } else if chain.contains("connection closed")
        || chain.contains("closed for writing")
        || chain.contains("server closed")
    {
        "closed"
    } else if error.is_connect() {
        "connect"
    } else if error.is_request() {
        "request"
    } else if error.is_body() {
        "body"
    } else if error.is_decode() {
        "decode"
    } else {
        "unknown"
    }
}

fn retryable_reqwest_error(error_kind: &str) -> bool {
    matches!(
        error_kind,
        "timeout" | "dns" | "tls" | "closed" | "connect" | "request" | "unknown"
    )
}

fn format_reqwest_error(error: &reqwest::Error) -> String {
    let mut message = format!(
        "{error}; kind={}; is_timeout={}; is_connect={}; is_request={}; is_body={}; is_decode={}; status={}",
        classify_reqwest_error(error),
        error.is_timeout(),
        error.is_connect(),
        error.is_request(),
        error.is_body(),
        error.is_decode(),
        error
            .status()
            .map(|status| status.as_u16().to_string())
            .unwrap_or_else(|| "none".to_owned())
    );

    let mut source = error.source();
    while let Some(current) = source {
        message.push_str("; caused_by=");
        message.push_str(&current.to_string());
        source = current.source();
    }
    message
}

fn error_chain_string(error: &reqwest::Error) -> String {
    let mut chain = error.to_string().to_lowercase();
    let mut source = error.source();
    while let Some(current) = source {
        chain.push_str("; ");
        chain.push_str(&current.to_string().to_lowercase());
        source = current.source();
    }
    chain
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
        let cache_max_entries = optional_env_parse(KURA_EXTENSION_CACHE_MAX_ENTRIES)?
            .unwrap_or(DEFAULT_EXTENSION_CACHE_MAX_ENTRIES);
        if cache_max_entries == 0 {
            return Err(format!(
                "{KURA_EXTENSION_CACHE_MAX_ENTRIES} must be greater than 0"
            ));
        }

        Ok(Some(Self {
            script_path: PathBuf::from(script_path),
            hook_timeout,
            allow_ttl,
            deny_ttl,
            fail_closed_authenticate,
            fail_closed_authorize,
            fail_open_response_headers,
            cache_max_entries,
            signers: Arc::new(parse_signers()?),
            jwt_verifiers: Arc::new(parse_jwt_verifiers()?),
            http_clients: Arc::new(parse_http_clients()?),
            env: Arc::new(std::env::vars().collect()),
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
            format!("{SIGNER_PREFIX}{id}_SECRET must be base64-encoded raw key bytes: {error}")
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

// Hook results are cached per credentials, so the fingerprint must only cover
// headers that can carry credentials. Hashing the remaining headers instead
// would key the cache on per-request noise such as `grpc-timeout` (REAPI
// clients send the remaining deadline on every RPC) or `traceparent`, turning
// almost every request into a cache miss and an authentication backend call.
const CREDENTIAL_HEADER_NAMES: [&str; 4] = [
    "authorization",
    "proxy-authorization",
    "cookie",
    "x-api-key",
];

fn credentials_fingerprint(headers: &BTreeMap<String, String>) -> String {
    let filtered = headers
        .iter()
        .filter(|(name, _)| CREDENTIAL_HEADER_NAMES.contains(&name.as_str()))
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
                    server_tenant_id: "acme".into(),
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
    async fn scripts_can_read_environment_variables() {
        let engine = test_engine(
            r#"
function authorize(ctx, principal)
  if kura.env("TUIST_EXTENSION_TEST_VALUE") == "available" then
    return { allow = true, ttl_seconds = 60 }
  end

  return { deny = { status = 403, message = "missing env" }, ttl_seconds = 3 }
end
"#,
            |_| unsafe {
                std::env::set_var("TUIST_EXTENSION_TEST_VALUE", "available");
            },
        )
        .await;

        let decision = engine
            .evaluate_access(&ExtensionContext {
                transport: "http".into(),
                route: "/api/cache/module/{id}".into(),
                method: "GET".into(),
                operation: "artifact.read".into(),
                server_tenant_id: "acme".into(),
                tenant_id: Some("acme".into()),
                namespace_id: Some("ios".into()),
                producer: Some("module".into()),
                artifact_key: Some("artifact-1".into()),
                artifact_hash: None,
                headers: BTreeMap::new(),
                query: BTreeMap::new(),
                status_code: None,
            })
            .await;

        assert!(matches!(decision, AccessDecision::Allow(None)));
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
            server_tenant_id: "acme".into(),
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

        // Per-request noise headers (REAPI deadlines, trace propagation) must
        // not key the cache: same credentials, varying noise → still cached.
        for (noise_name, noise_value) in [
            ("grpc-timeout", "119999996u"),
            ("grpc-timeout", "119231422u"),
            (
                "traceparent",
                "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01",
            ),
        ] {
            let mut noisy = context.clone();
            noisy.headers.insert(noise_name.into(), noise_value.into());
            let decision = engine.evaluate_access(&noisy).await;
            assert!(matches!(decision, AccessDecision::Allow(Some(_))));
        }
        assert_eq!(calls.load(Ordering::SeqCst), 1);

        // Different credentials must not share the cached result.
        let mut other_credentials = context.clone();
        other_credentials
            .headers
            .insert("authorization".into(), "Bearer other".into());
        let decision = engine.evaluate_access(&other_credentials).await;
        assert!(matches!(decision, AccessDecision::Allow(Some(_))));
        assert_eq!(calls.load(Ordering::SeqCst), 2);
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
            server_tenant_id: "acme".into(),
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

    /// Exercises `kura/ops/helm/kura/hooks/tuist.lua` end-to-end through
    /// the real mlua engine. The hook lives in the chart so adopters
    /// can read it; these tests are how we keep its contracts honest:
    ///
    ///   * `authenticate` — first try Tuist Guardian JWTs locally, then
    ///     fall back to `/oauth2/introspect` when the token is opaque or
    ///     the JWT claim set does not prove the requested cache action.
    ///     Project-scoped requests can still use `/api/cache/access`
    ///     while the introspection client rolls out.
    ///   * `authorize` — resolve the request's target scope from
    ///     `ctx.tenant_id` and `ctx.namespace_id`, require the tenant to
    ///     match `ctx.server_tenant_id`, and then check it against
    ///     action-specific cache grants.
    mod tuist_hook {
        use super::*;
        use axum::{
            Json, Router,
            http::{HeaderMap, StatusCode},
            routing::{get, post},
        };
        use serde_json::{Map, Value, json};
        use std::sync::Mutex;

        const HOOK: &str = include_str!("../../ops/helm/kura/hooks/tuist.lua");

        fn script() -> String {
            HOOK.to_owned()
        }

        async fn spawn_tuist_auth_mock<FIntrospect, FCache>(
            introspect_handler: FIntrospect,
            cache_access_handler: FCache,
        ) -> String
        where
            FIntrospect: Fn(HeaderMap, Value) -> (StatusCode, Value) + Send + Sync + 'static,
            FCache: Fn(HeaderMap) -> (StatusCode, Value) + Send + Sync + 'static,
        {
            let introspect_handler = Arc::new(introspect_handler);
            let cache_access_handler = Arc::new(cache_access_handler);
            let app = Router::new()
                .route(
                    "/oauth2/introspect",
                    post(move |headers: HeaderMap, Json(payload): Json<Value>| {
                        let introspect_handler = introspect_handler.clone();
                        async move {
                            let (status, payload) = introspect_handler(headers, payload);
                            (status, Json(payload))
                        }
                    }),
                )
                .route(
                    "/api/cache/access",
                    get(move |headers: HeaderMap| {
                        let cache_access_handler = cache_access_handler.clone();
                        async move {
                            let (status, payload) = cache_access_handler(headers);
                            (status, Json(payload))
                        }
                    }),
                );

            let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
                .await
                .expect("bind tuist auth mock");
            let address = listener.local_addr().expect("tuist auth mock addr");
            tokio::spawn(async move {
                axum::serve(listener, app)
                    .await
                    .expect("tuist auth mock serve");
            });
            format!("http://{address}")
        }

        async fn engine_pointing_at(base_url: &str, introspection_client: bool) -> SharedExtension {
            engine_pointing_at_with_timeout(base_url, introspection_client, "4000").await
        }

        async fn engine_pointing_at_with_timeout(
            base_url: &str,
            introspection_client: bool,
            request_timeout_ms: &str,
        ) -> SharedExtension {
            engine_pointing_at_with_options(
                base_url,
                introspection_client,
                request_timeout_ms,
                false,
            )
            .await
        }

        async fn engine_pointing_at_with_shared_tenants(base_url: &str) -> SharedExtension {
            engine_pointing_at_with_options(base_url, true, "4000", true).await
        }

        async fn engine_pointing_at_with_options(
            base_url: &str,
            introspection_client: bool,
            request_timeout_ms: &str,
            shared_tenants: bool,
        ) -> SharedExtension {
            let url = base_url.to_owned();
            let request_timeout_ms = request_timeout_ms.to_owned();
            test_engine(&script(), move |_| unsafe {
                std::env::set_var("KURA_EXTENSION_HTTP_CLIENT_TUIST_BASE_URL", &url);
                std::env::set_var("KURA_EXTENSION_HOOK_TIMEOUT_MS", "5000");
                std::env::set_var("KURA_EXTENSION_JWT_VERIFIER_TUIST_ALGORITHM", "HS512");
                std::env::set_var(
                    "KURA_EXTENSION_JWT_VERIFIER_TUIST_SECRET",
                    "tuist-guardian-secret",
                );
                std::env::set_var("KURA_EXTENSION_JWT_VERIFIER_TUIST_ISSUER", "tuist");
                std::env::set_var(
                    "KURA_EXTENSION_HTTP_CLIENT_TUIST_REQUEST_TIMEOUT_MS",
                    &request_timeout_ms,
                );

                if shared_tenants {
                    std::env::set_var("KURA_EXTENSION_TUIST_ALLOW_SHARED_TENANTS", "1");
                }

                if introspection_client {
                    std::env::set_var(
                        "KURA_EXTENSION_TUIST_INTROSPECT_CLIENT_ID",
                        "00000000-0000-0000-0000-000000000001",
                    );
                    std::env::set_var(
                        "KURA_EXTENSION_TUIST_INTROSPECT_CLIENT_SECRET",
                        "kura-secret",
                    );
                }
            })
            .await
        }

        fn ctx() -> ExtensionContext {
            ExtensionContext {
                transport: "http".into(),
                route: "/api/cache/gradle/{cache_key}".into(),
                method: "GET".into(),
                operation: "artifact.read".into(),
                server_tenant_id: "acme".into(),
                tenant_id: None,
                namespace_id: None,
                producer: Some("gradle".into()),
                artifact_key: None,
                artifact_hash: None,
                headers: BTreeMap::new(),
                query: BTreeMap::new(),
                status_code: None,
            }
        }

        fn cache_access_payload(accounts: &[&str], projects: &[&str]) -> Value {
            json!({
                "accounts": accounts,
                "projects": projects,
            })
        }

        fn cache_grants_payload(
            account_read: &[&str],
            account_write: &[&str],
            project_read: &[&str],
            project_write: &[&str],
        ) -> Value {
            json!({
                "account": {
                    "read": account_read,
                    "write": account_write,
                },
                "project": {
                    "read": project_read,
                    "write": project_write,
                },
            })
        }

        fn introspection_payload(grants: Value) -> Value {
            json!({
                "active": true,
                "sub": "subject-1",
                "principal_kind": "account",
                "cache_grants": grants,
            })
        }

        fn guardian_jwt(claims: Value) -> String {
            let mut claims = match claims {
                Value::Object(map) => map,
                _ => Map::new(),
            };
            claims.insert("sub".into(), json!("user-1"));
            claims.insert("iss".into(), json!("tuist"));
            claims.insert("exp".into(), json!(4_000_000_000u64));

            jsonwebtoken::encode(
                &jsonwebtoken::Header::new(Algorithm::HS512),
                &Value::Object(claims),
                &jsonwebtoken::EncodingKey::from_secret("tuist-guardian-secret".as_bytes()),
            )
            .expect("failed to sign guardian test token")
        }

        #[tokio::test]
        async fn denies_when_authorization_header_is_missing() {
            let engine = engine_pointing_at("http://127.0.0.1:1", true).await;

            let decision = engine.evaluate_access(&ctx()).await;

            let deny = expect_deny(decision);
            assert_eq!(deny.status, 401);
            assert!(deny.message.contains("Missing Authorization"));
        }

        #[tokio::test]
        async fn allows_when_introspection_returns_project_grants() {
            let base = spawn_tuist_auth_mock(
                |_headers, _payload| {
                    (
                        StatusCode::OK,
                        introspection_payload(cache_grants_payload(
                            &[],
                            &[],
                            &["acme/ios"],
                            &["acme/ios"],
                        )),
                    )
                },
                |_| (StatusCode::OK, cache_access_payload(&[], &[])),
            )
            .await;
            let engine = engine_pointing_at(&base, true).await;

            let mut context = ctx();
            context.tenant_id = Some("acme".into());
            context
                .headers
                .insert("authorization".into(), "Bearer opaque-token".into());
            context.tenant_id = Some("acme".into());
            context.namespace_id = Some("ios".into());

            let decision = engine.evaluate_access(&context).await;
            assert!(matches!(decision, AccessDecision::Allow(Some(_))));
        }

        #[tokio::test]
        async fn allows_namespace_only_grpc_requests_for_bazel() {
            let base = spawn_tuist_auth_mock(
                |_headers, _payload| {
                    (
                        StatusCode::OK,
                        introspection_payload(cache_grants_payload(
                            &[],
                            &[],
                            &["acme/bazel"],
                            &["acme/bazel"],
                        )),
                    )
                },
                |_| (StatusCode::OK, cache_access_payload(&[], &[])),
            )
            .await;
            let engine = engine_pointing_at(&base, true).await;

            let mut context = ctx();
            context.transport = "grpc".into();
            context.route =
                "build.bazel.remote.execution.v2.ContentAddressableStorage/FindMissingBlobs".into();
            context.method = "RPC".into();
            context.tenant_id = None;
            context.namespace_id = Some("bazel".into());
            context
                .headers
                .insert("authorization".into(), "Bearer opaque-token".into());

            let decision = engine.evaluate_access(&context).await;
            assert!(matches!(decision, AccessDecision::Allow(Some(_))));
        }

        #[tokio::test]
        async fn denies_namespace_only_http_project_requests() {
            let base = spawn_tuist_auth_mock(
                |_headers, _payload| {
                    (
                        StatusCode::OK,
                        introspection_payload(cache_grants_payload(
                            &[],
                            &[],
                            &["acme/ios"],
                            &["acme/ios"],
                        )),
                    )
                },
                |_| (StatusCode::OK, cache_access_payload(&[], &["acme/ios"])),
            )
            .await;
            let engine = engine_pointing_at(&base, true).await;

            let mut context = ctx();
            context.tenant_id = None;
            context.namespace_id = Some("ios".into());
            context
                .headers
                .insert("authorization".into(), "Bearer opaque-token".into());

            let deny = expect_deny(engine.evaluate_access(&context).await);
            assert_eq!(deny.status, 400);
            assert!(deny.message.contains("Missing tenant_id"));
        }

        #[tokio::test]
        async fn allows_when_introspection_returns_account_grants() {
            let base = spawn_tuist_auth_mock(
                |_headers, _payload| {
                    (
                        StatusCode::OK,
                        introspection_payload(cache_grants_payload(&["acme"], &["acme"], &[], &[])),
                    )
                },
                |_| (StatusCode::OK, cache_access_payload(&[], &[])),
            )
            .await;
            let engine = engine_pointing_at(&base, true).await;

            let mut context = ctx();
            context.tenant_id = Some("acme".into());
            context
                .headers
                .insert("authorization".into(), "Bearer opaque-token".into());

            let decision = engine.evaluate_access(&context).await;
            assert!(matches!(decision, AccessDecision::Allow(Some(_))));
        }

        #[tokio::test]
        async fn allows_account_writes_when_introspection_returns_write_grants() {
            let base = spawn_tuist_auth_mock(
                |_headers, _payload| {
                    (
                        StatusCode::OK,
                        introspection_payload(cache_grants_payload(&[], &["acme"], &[], &[])),
                    )
                },
                |_| (StatusCode::OK, cache_access_payload(&[], &[])),
            )
            .await;
            let engine = engine_pointing_at(&base, true).await;

            let mut context = ctx();
            context.method = "POST".into();
            context.operation = "artifact.write".into();
            context.tenant_id = Some("acme".into());
            context
                .headers
                .insert("authorization".into(), "Bearer opaque-token".into());

            let decision = engine.evaluate_access(&context).await;
            assert!(matches!(decision, AccessDecision::Allow(Some(_))));
        }

        #[tokio::test]
        async fn denies_project_writes_when_introspection_only_returns_read_grants() {
            let base = spawn_tuist_auth_mock(
                |_headers, _payload| {
                    (
                        StatusCode::OK,
                        introspection_payload(cache_grants_payload(&[], &[], &["acme/ios"], &[])),
                    )
                },
                |_| (StatusCode::OK, cache_access_payload(&[], &[])),
            )
            .await;
            let engine = engine_pointing_at(&base, true).await;

            let mut context = ctx();
            context.method = "POST".into();
            context.operation = "artifact.write".into();
            context.tenant_id = Some("acme".into());
            context.namespace_id = Some("ios".into());
            context
                .headers
                .insert("authorization".into(), "Bearer opaque-token".into());

            let deny = expect_deny(engine.evaluate_access(&context).await);
            assert_eq!(deny.status, 403);
            assert!(deny.message.contains("project 'acme/ios'"));
        }

        #[tokio::test]
        async fn authorizes_from_local_jwt_cache_grants_without_introspection() {
            let engine = engine_pointing_at("http://127.0.0.1:1", false).await;
            let token = guardian_jwt(json!({
                "type": "account",
                "cache_grants": cache_grants_payload(&[], &[], &["acme/ios"], &["acme/ios"]),
                "scopes": ["project:cache:read"],
            }));

            let mut context = ctx();
            context.tenant_id = Some("acme".into());
            context
                .headers
                .insert("authorization".into(), format!("Bearer {token}"));
            context.namespace_id = Some("ios".into());

            let decision = engine.evaluate_access(&context).await;
            assert!(matches!(decision, AccessDecision::Allow(Some(_))));
        }

        #[tokio::test]
        async fn falls_back_to_introspection_when_jwt_cache_grants_do_not_cover_requested_project()
        {
            let calls = Arc::new(Mutex::new(0usize));
            let calls_for_handler = calls.clone();
            let base = spawn_tuist_auth_mock(
                move |_headers, _payload| {
                    *calls_for_handler.lock().unwrap() += 1;
                    (
                        StatusCode::OK,
                        introspection_payload(cache_grants_payload(
                            &[],
                            &[],
                            &["acme/ios"],
                            &["acme/ios"],
                        )),
                    )
                },
                |_| (StatusCode::OK, cache_access_payload(&[], &[])),
            )
            .await;
            let engine = engine_pointing_at(&base, true).await;
            let token = guardian_jwt(json!({
                "type": "account",
                "cache_grants": cache_grants_payload(&[], &[], &["acme/android"], &["acme/android"]),
                "scopes": ["project:cache:read"],
            }));

            let mut context = ctx();
            context.tenant_id = Some("acme".into());
            context
                .headers
                .insert("authorization".into(), format!("Bearer {token}"));
            context.namespace_id = Some("ios".into());

            let decision = engine.evaluate_access(&context).await;
            assert!(matches!(decision, AccessDecision::Allow(Some(_))));
            assert_eq!(*calls.lock().unwrap(), 1);
        }

        #[tokio::test]
        async fn falls_back_to_legacy_cache_access_when_active_introspection_grants_do_not_cover_project()
         {
            let calls = Arc::new(Mutex::new(0usize));
            let calls_for_handler = calls.clone();
            let base = spawn_tuist_auth_mock(
                |_headers, _payload| {
                    (
                        StatusCode::OK,
                        introspection_payload(cache_grants_payload(
                            &[],
                            &[],
                            &["acme/android"],
                            &["acme/android"],
                        )),
                    )
                },
                move |_| {
                    *calls_for_handler.lock().unwrap() += 1;
                    (StatusCode::OK, cache_access_payload(&[], &["acme/ios"]))
                },
            )
            .await;
            let engine = engine_pointing_at(&base, true).await;

            let mut context = ctx();
            context.tenant_id = Some("acme".into());
            context
                .headers
                .insert("authorization".into(), "Bearer opaque-token".into());
            context.namespace_id = Some("ios".into());

            let decision = engine.evaluate_access(&context).await;
            assert!(matches!(decision, AccessDecision::Allow(Some(_))));
            assert_eq!(*calls.lock().unwrap(), 1);
        }

        #[tokio::test]
        async fn retries_introspection_transport_failures_once() {
            let calls = Arc::new(Mutex::new(0usize));
            let calls_for_handler = calls.clone();
            let base = spawn_tuist_auth_mock(
                move |_headers, _payload| {
                    let mut calls = calls_for_handler.lock().unwrap();
                    *calls += 1;
                    if *calls == 1 {
                        std::thread::sleep(Duration::from_millis(50));
                    }
                    (
                        StatusCode::OK,
                        introspection_payload(cache_grants_payload(
                            &[],
                            &[],
                            &["acme/ios"],
                            &["acme/ios"],
                        )),
                    )
                },
                |_| (StatusCode::OK, cache_access_payload(&[], &[])),
            )
            .await;
            let engine = engine_pointing_at_with_timeout(&base, true, "10").await;

            let mut context = ctx();
            context.tenant_id = Some("acme".into());
            context.namespace_id = Some("ios".into());
            context
                .headers
                .insert("authorization".into(), "Bearer opaque-token".into());

            let decision = engine.evaluate_access(&context).await;
            assert!(matches!(decision, AccessDecision::Allow(Some(_))));
            assert_eq!(*calls.lock().unwrap(), 2);
        }

        #[tokio::test]
        async fn falls_back_to_legacy_cache_access_for_project_requests_when_introspection_client_is_missing()
         {
            let calls = Arc::new(Mutex::new(0usize));
            let calls_for_handler = calls.clone();
            let base = spawn_tuist_auth_mock(
                |_headers, _payload| {
                    (
                        StatusCode::OK,
                        introspection_payload(cache_grants_payload(&[], &[], &[], &[])),
                    )
                },
                move |_| {
                    *calls_for_handler.lock().unwrap() += 1;
                    (StatusCode::OK, cache_access_payload(&[], &["acme/ios"]))
                },
            )
            .await;
            let engine = engine_pointing_at(&base, false).await;

            let mut context = ctx();
            context.tenant_id = Some("acme".into());
            context
                .headers
                .insert("authorization".into(), "Bearer opaque-token".into());
            context.namespace_id = Some("ios".into());

            let decision = engine.evaluate_access(&context).await;
            assert!(matches!(decision, AccessDecision::Allow(Some(_))));
            assert_eq!(*calls.lock().unwrap(), 1);
        }

        #[tokio::test]
        async fn does_not_reuse_legacy_project_fallback_for_account_requests() {
            let calls = Arc::new(Mutex::new(0usize));
            let calls_for_handler = calls.clone();
            let base = spawn_tuist_auth_mock(
                |_headers, _payload| {
                    (
                        StatusCode::OK,
                        introspection_payload(cache_grants_payload(&[], &[], &[], &[])),
                    )
                },
                move |_| {
                    *calls_for_handler.lock().unwrap() += 1;
                    (
                        StatusCode::OK,
                        cache_access_payload(&["acme"], &["acme/ios"]),
                    )
                },
            )
            .await;
            let engine = engine_pointing_at(&base, false).await;

            let mut project_context = ctx();
            project_context.tenant_id = Some("acme".into());
            project_context.namespace_id = Some("ios".into());
            project_context
                .headers
                .insert("authorization".into(), "Bearer opaque-token".into());

            let project_decision = engine.evaluate_access(&project_context).await;
            assert!(matches!(project_decision, AccessDecision::Allow(Some(_))));

            let mut account_context = ctx();
            account_context.tenant_id = Some("acme".into());
            account_context
                .headers
                .insert("authorization".into(), "Bearer opaque-token".into());

            let deny = expect_deny(engine.evaluate_access(&account_context).await);
            assert_eq!(deny.status, 403);
            assert_eq!(*calls.lock().unwrap(), 1);
        }

        #[tokio::test]
        async fn denies_account_scoped_requests_when_introspection_client_is_missing() {
            let base = spawn_tuist_auth_mock(
                |_headers, _payload| {
                    (
                        StatusCode::OK,
                        introspection_payload(cache_grants_payload(&["acme"], &["acme"], &[], &[])),
                    )
                },
                |_| (StatusCode::OK, cache_access_payload(&["acme"], &[])),
            )
            .await;
            let engine = engine_pointing_at(&base, false).await;

            let mut context = ctx();
            context.tenant_id = Some("acme".into());
            context
                .headers
                .insert("authorization".into(), "Bearer opaque-token".into());

            let deny = expect_deny(engine.evaluate_access(&context).await);
            assert_eq!(deny.status, 503);
        }

        #[tokio::test]
        async fn forwards_introspection_credentials_and_token() {
            let captured = Arc::new(Mutex::new(None::<Value>));
            let captured_for_handler = captured.clone();
            let base = spawn_tuist_auth_mock(
                move |_headers, payload| {
                    *captured_for_handler.lock().unwrap() = Some(payload);
                    (
                        StatusCode::OK,
                        introspection_payload(cache_grants_payload(
                            &[],
                            &[],
                            &["acme/ios"],
                            &["acme/ios"],
                        )),
                    )
                },
                |_| (StatusCode::OK, cache_access_payload(&[], &[])),
            )
            .await;
            let engine = engine_pointing_at(&base, true).await;

            let mut context = ctx();
            context.tenant_id = Some("acme".into());
            context
                .headers
                .insert("authorization".into(), "Bearer opaque-token".into());
            context.namespace_id = Some("ios".into());

            let _ = engine.evaluate_access(&context).await;

            assert_eq!(
                *captured.lock().unwrap(),
                Some(json!({
                    "client_id": "00000000-0000-0000-0000-000000000001",
                    "client_secret": "kura-secret",
                    "token": "opaque-token",
                }))
            );
        }

        #[tokio::test]
        async fn falls_back_to_legacy_cache_access_when_introspection_marks_project_token_inactive()
        {
            let calls = Arc::new(Mutex::new(0usize));
            let calls_for_handler = calls.clone();
            let base = spawn_tuist_auth_mock(
                |_headers, _payload| (StatusCode::OK, json!({ "active": false })),
                move |_| {
                    *calls_for_handler.lock().unwrap() += 1;
                    (StatusCode::OK, cache_access_payload(&[], &["acme/ios"]))
                },
            )
            .await;
            let engine = engine_pointing_at(&base, true).await;

            let mut context = ctx();
            context.tenant_id = Some("acme".into());
            context
                .headers
                .insert("authorization".into(), "Bearer legacy-token".into());
            context.namespace_id = Some("ios".into());

            let decision = engine.evaluate_access(&context).await;
            assert!(matches!(decision, AccessDecision::Allow(Some(_))));
            assert_eq!(*calls.lock().unwrap(), 1);
        }

        #[tokio::test]
        async fn denies_when_introspection_returns_inactive() {
            let base = spawn_tuist_auth_mock(
                |_headers, _payload| (StatusCode::OK, json!({ "active": false })),
                |_| {
                    (
                        StatusCode::UNAUTHORIZED,
                        json!({ "message": "Invalid or expired token" }),
                    )
                },
            )
            .await;
            let engine = engine_pointing_at(&base, true).await;

            let mut context = ctx();
            context.tenant_id = Some("acme".into());
            context
                .headers
                .insert("authorization".into(), "Bearer bad-token".into());
            context.namespace_id = Some("ios".into());

            let deny = expect_deny(engine.evaluate_access(&context).await);
            assert_eq!(deny.status, 401);
        }

        #[tokio::test]
        async fn denies_when_introspection_backend_is_unavailable() {
            let base = spawn_tuist_auth_mock(
                |_headers, _payload| (StatusCode::INTERNAL_SERVER_ERROR, json!({})),
                |_| (StatusCode::OK, cache_access_payload(&[], &[])),
            )
            .await;
            let engine = engine_pointing_at(&base, true).await;

            let mut context = ctx();
            context.tenant_id = Some("acme".into());
            context
                .headers
                .insert("authorization".into(), "Bearer bad-token".into());
            context.namespace_id = Some("ios".into());

            let deny = expect_deny(engine.evaluate_access(&context).await);
            assert_eq!(deny.status, 503);
        }

        #[tokio::test]
        async fn authorizes_case_insensitively_like_current_cache_nodes() {
            let base = spawn_tuist_auth_mock(
                |_headers, _payload| {
                    (
                        StatusCode::OK,
                        introspection_payload(cache_grants_payload(
                            &[],
                            &[],
                            &["Acme/iOS"],
                            &["Acme/iOS"],
                        )),
                    )
                },
                |_| (StatusCode::OK, cache_access_payload(&[], &[])),
            )
            .await;
            let engine = engine_pointing_at(&base, true).await;

            let mut context = ctx();
            context
                .headers
                .insert("authorization".into(), "Bearer opaque-token".into());
            context.query.insert("account_handle".into(), "ACME".into());
            context.query.insert("project_handle".into(), "IOS".into());

            let decision = engine.evaluate_access(&context).await;
            assert!(matches!(decision, AccessDecision::Allow(Some(_))));
        }

        #[tokio::test]
        async fn denies_when_request_tenant_does_not_match_server_tenant() {
            let base = spawn_tuist_auth_mock(
                |_headers, _payload| {
                    (
                        StatusCode::OK,
                        introspection_payload(cache_grants_payload(
                            &["someone-else"],
                            &["someone-else"],
                            &["someone-else/ios"],
                            &["someone-else/ios"],
                        )),
                    )
                },
                |_| {
                    (
                        StatusCode::OK,
                        cache_access_payload(&["someone-else"], &["someone-else/ios"]),
                    )
                },
            )
            .await;
            let engine = engine_pointing_at(&base, true).await;

            let mut context = ctx();
            context
                .headers
                .insert("authorization".into(), "Bearer opaque-token".into());
            context
                .query
                .insert("account_handle".into(), "someone-else".into());
            context.query.insert("project_handle".into(), "ios".into());

            let deny = expect_deny(engine.evaluate_access(&context).await);
            assert_eq!(deny.status, 403);
            assert!(deny.message.contains("server for"));
        }

        #[tokio::test]
        async fn allows_different_request_tenant_when_shared_tenants_are_enabled() {
            let base = spawn_tuist_auth_mock(
                |_headers, _payload| {
                    (
                        StatusCode::OK,
                        introspection_payload(cache_grants_payload(
                            &["someone-else"],
                            &["someone-else"],
                            &["someone-else/ios"],
                            &["someone-else/ios"],
                        )),
                    )
                },
                |_| (StatusCode::OK, cache_access_payload(&[], &[])),
            )
            .await;
            let engine = engine_pointing_at_with_shared_tenants(&base).await;

            let mut context = ctx();
            context
                .headers
                .insert("authorization".into(), "Bearer opaque-token".into());
            context
                .query
                .insert("account_handle".into(), "someone-else".into());
            context.query.insert("project_handle".into(), "ios".into());

            let decision = engine.evaluate_access(&context).await;
            assert!(matches!(decision, AccessDecision::Allow(Some(_))));
        }

        fn expect_deny(decision: AccessDecision) -> DenyDecision {
            match decision {
                AccessDecision::Deny(deny) => deny,
                AccessDecision::Allow(_) => panic!("expected deny, got allow"),
            }
        }
    }
}
