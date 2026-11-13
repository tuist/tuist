// Pulse object store NIF.
//
// A thin wrapper around the `object_store` crate exposing S3-compatible
// put/get/delete/list — plus the conditional variants Pulse's manifest CAS
// relies on — to Elixir.
//
// Every request runs asynchronously on a shared multi-threaded tokio runtime.
// An entry point validates its arguments, spawns the request and returns
// `:ok` at once; the result arrives later as `{reference, result}` in the
// calling process's mailbox (`Pulse.ObjectStore` waits for it). No BEAM
// scheduler, dirty or not, is held while a provider answers, so concurrent
// requests are bounded by the runtime and connection pool rather than by the
// VM's dirty I/O schedulers, and a slow store cannot starve other dirty work
// such as code loading or file I/O.
//
// The Elixir side (`Pulse.ObjectStore.NIF`) always passes an explicit
// `StoreConfig` map; nothing in this crate reads process environment.

mod snapshot;

use bytes::Bytes;
use futures::{FutureExt, StreamExt, TryStreamExt};
use object_store::aws::AmazonS3Builder;
use object_store::path::Path;
use object_store::{
    Error as ObjectStoreError, GetOptions, ObjectStore, PutMode, PutOptions, PutPayload,
    UpdateVersion,
};
use once_cell::sync::Lazy;
use rustler::env::SavedTerm;
use rustler::{Atom, Binary, Encoder, Env, Error, NifResult, OwnedBinary, OwnedEnv, Term};
use std::collections::HashMap;
use std::future::Future;
use std::panic::AssertUnwindSafe;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use tokio::runtime::Runtime;

static RUNTIME: Lazy<Runtime> = Lazy::new(|| {
    tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .expect("failed to build tokio runtime for pulse_object_store")
});

mod counting_alloc;

// Bytes this library currently holds on the native heap (see counting_alloc.rs).
#[rustler::nif]
fn native_allocated_bytes() -> i64 {
    counting_alloc::allocated()
}

mod atoms {
    rustler::atoms! {
        ok,
        error,
        not_found,
        not_modified,
        already_exists,
        precondition_failed,
        response_too_large,
        retention_overloaded,
        timeout
    }
}

// Boot-time ABI fence: older release artifacts must fail before serving ingest.
#[rustler::nif]
fn retention_api_version() -> u32 {
    1
}

#[rustler::nif]
fn keyed_publication_api_version() -> u32 {
    1
}

// Version 1 replies to the caller's mailbox instead of blocking a dirty
// scheduler; the Elixir wrapper must match the calling convention.
#[rustler::nif]
fn async_api_version() -> u32 {
    1
}

#[derive(rustler::NifMap, Clone, PartialEq, Eq, Hash)]
struct StoreConfig {
    bucket: String,
    endpoint: Option<String>,
    region: String,
    access_key_id: String,
    secret_access_key: String,
    allow_http: bool,
}

// A failure that can cross threads: atoms are global and messages are owned,
// unlike `rustler::Error::Term`, which boxes a non-`Send` encoder.
enum Failure {
    Atom(Atom),
    Message(String),
}

impl From<Failure> for Error {
    fn from(failure: Failure) -> Error {
        match failure {
            Failure::Atom(atom) => Error::Term(Box::new(atom)),
            Failure::Message(message) => Error::Term(Box::new(message)),
        }
    }
}

fn nif_error<E: std::fmt::Display>(err: E) -> Failure {
    Failure::Message(err.to_string())
}

// A NotFound response from the object store surfaces as the atom
// `:not_found` on the Elixir side. Everything else stays as a string
// message so the caller keeps the underlying context (permission denied,
// throttling, timeout, etc.).
fn map_object_store_error(err: ObjectStoreError) -> Failure {
    match err {
        ObjectStoreError::NotFound { .. } => Failure::Atom(atoms::not_found()),
        ObjectStoreError::NotModified { .. } => Failure::Atom(atoms::not_modified()),
        ObjectStoreError::AlreadyExists { .. } => Failure::Atom(atoms::already_exists()),
        ObjectStoreError::Precondition { .. } => Failure::Atom(atoms::precondition_failed()),
        other => Failure::Message(other.to_string()),
    }
}

// A completed request's value. Bodies are `OwnedBinary`s, allocated outside
// any process heap and filled while streaming, then released into the reply
// message without another copy.
enum Reply {
    Ok,
    Etag(String),
    Body(OwnedBinary),
    EtagBody(String, OwnedBinary),
    Verified(bool, usize),
    Snapshot(String, u64, OwnedBinary),
    Keys(Vec<String>),
    Page(Vec<String>, Option<String>),
}

type Outcome = Result<Reply, Failure>;

fn encode_outcome<'a>(env: Env<'a>, outcome: Outcome) -> Term<'a> {
    let ok = atoms::ok();
    match outcome {
        Ok(Reply::Ok) => ok.encode(env),
        Ok(Reply::Etag(etag)) => (ok, etag).encode(env),
        Ok(Reply::Body(body)) => (ok, body.release(env)).encode(env),
        Ok(Reply::EtagBody(etag, body)) => (ok, etag, body.release(env)).encode(env),
        Ok(Reply::Verified(matches, read)) => (ok, matches, read).encode(env),
        Ok(Reply::Snapshot(etag, size, body)) => (ok, etag, size, body.release(env)).encode(env),
        Ok(Reply::Keys(keys)) => (ok, keys).encode(env),
        Ok(Reply::Page(keys, cursor)) => (ok, keys, cursor).encode(env),
        Err(Failure::Atom(reason)) => (atoms::error(), reason).encode(env),
        Err(Failure::Message(reason)) => (atoms::error(), reason).encode(env),
    }
}

// Run `work` on the runtime and send `{reference, result}` to the calling
// process when it finishes. A caller that exited meanwhile simply never
// receives it. A panic still answers, so a waiting caller is never stranded.
fn spawn<F, Fut>(env: Env, reference: Term, config: StoreConfig, work: F) -> Atom
where
    F: FnOnce(Arc<dyn ObjectStore>) -> Fut + Send + 'static,
    Fut: Future<Output = Outcome> + Send + 'static,
{
    let pid = env.pid();
    let mut owned = OwnedEnv::new();
    let reference = owned.save(reference);
    RUNTIME.spawn(async move {
        let outcome = AssertUnwindSafe(async move {
            // Neither a cold TLS trust-store load nor a cache lock held by
            // another builder may block a BEAM or Tokio event-loop thread.
            let cached = STORES
                .try_lock()
                .ok()
                .and_then(|stores| stores.get(&config).cloned());
            let store = match cached {
                Some(store) => store,
                None => tokio::task::spawn_blocking(move || build_store(&config))
                    .await
                    .map_err(nif_error)??,
            };
            work(store).await
        })
        .catch_unwind()
        .await
        .unwrap_or_else(|_| Err(nif_error("object store request panicked")));
        let _ = owned.send_and_clear(&pid, |env| {
            (reference.load(env), encode_outcome(env, outcome)).encode(env)
        });
    });
    atoms::ok()
}

// One client per distinct config, reused across calls. Building a store
// per call created a fresh HTTP connection pool every time, so every PUT
// and GET paid a new TCP (and TLS) handshake; a cached store keeps
// connections alive. A config change (e.g. rotated credentials) is a new
// key and gets its own client. Cold construction can read local TLS trust
// stores and is confined to the runtime's blocking pool, including lock waits.
static STORES: Lazy<Mutex<HashMap<StoreConfig, Arc<dyn ObjectStore>>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));

fn build_store(config: &StoreConfig) -> Result<Arc<dyn ObjectStore>, Failure> {
    let mut stores = STORES
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    if let Some(store) = stores.get(config) {
        return Ok(Arc::clone(store));
    }

    let mut builder = AmazonS3Builder::new()
        .with_bucket_name(&config.bucket)
        .with_region(&config.region)
        .with_access_key_id(&config.access_key_id)
        .with_secret_access_key(&config.secret_access_key)
        .with_allow_http(config.allow_http);

    if let Some(endpoint) = &config.endpoint {
        builder = builder.with_endpoint(endpoint);
    }

    let store = builder
        .build()
        .map(|s| Arc::new(s) as Arc<dyn ObjectStore>)
        .map_err(nif_error)?;
    stores.insert(config.clone(), Arc::clone(&store));
    Ok(store)
}

// Hand the Erlang binary to `object_store` without copying it. The
// binary is saved into a process-independent environment, which holds a
// reference to it (a refcount, not a copy, for off-heap binaries), and
// the resulting `Bytes` owns that environment. reqwest may clone the body
// for retries and keep clones past the request; every clone shares the
// owner, so the Erlang binary stays alive until the last one is dropped.
// That is what makes this sound where a lifetime-extended slice was not.
struct ErlangBinary {
    _saved: SavedTerm,
    _env: OwnedEnv,
    ptr: *const u8,
    len: usize,
}

// The bytes are immutable and kept alive by `_env`, which is itself
// `Send`; freeing a process-independent environment is allowed from any
// thread.
unsafe impl Send for ErlangBinary {}

impl AsRef<[u8]> for ErlangBinary {
    fn as_ref(&self) -> &[u8] {
        // SAFETY: `ptr`/`len` describe the binary saved in `_env`, which
        // lives as long as `self` and never mutates or moves the data.
        unsafe { std::slice::from_raw_parts(self.ptr, self.len) }
    }
}

fn bytes_from_binary(data: Binary) -> Bytes {
    let env = OwnedEnv::new();
    let saved = env.save(data);
    let (ptr, len) = env.run(|e| {
        let b: Binary = saved.load(e).decode().expect("saved term is a binary");
        (b.as_slice().as_ptr(), b.len())
    });
    Bytes::from_owner(ErlangBinary {
        _saved: saved,
        _env: env,
        ptr,
        len,
    })
}

fn payload_from_binary(data: Binary) -> PutPayload {
    bytes_from_binary(data).into()
}

// The `object_store` crate returns `PutResult { e_tag, version }`. S3
// always supplies an ETag; treat its absence as a hard error rather than
// silently returning an empty string — a CAS caller that trusts a bogus
// ETag would spin forever on `precondition_failed`.
fn etag_or_error(e_tag: Option<String>) -> Result<String, Failure> {
    e_tag.ok_or_else(|| nif_error("object store returned no ETag"))
}

fn put_with(
    env: Env,
    reference: Term,
    config: StoreConfig,
    key: String,
    data: Binary,
    opts: PutOptions,
) -> NifResult<Atom> {
    let payload = payload_from_binary(data);
    Ok(spawn(env, reference, config, move |store| async move {
        let result = store
            .put_opts(&Path::from(key), payload, opts)
            .await
            .map_err(map_object_store_error)?;
        Ok(Reply::Etag(etag_or_error(result.e_tag)?))
    }))
}

#[rustler::nif]
fn put<'a>(
    env: Env<'a>,
    reference: Term<'a>,
    config: StoreConfig,
    key: String,
    data: Binary,
) -> NifResult<Atom> {
    put_with(env, reference, config, key, data, PutOptions::default())
}

// Conditional create: If-None-Match: *. Fails with `:already_exists` if
// the key already has an object. This is how the manifest is first
// written — races between two nodes trying to create the same manifest
// resolve deterministically: exactly one wins, the loser reloads.
#[rustler::nif]
fn put_if_none_match<'a>(
    env: Env<'a>,
    reference: Term<'a>,
    config: StoreConfig,
    key: String,
    data: Binary,
) -> NifResult<Atom> {
    let opts = PutOptions {
        mode: PutMode::Create,
        ..PutOptions::default()
    };
    put_with(env, reference, config, key, data, opts)
}

// Compare one streamed object snapshot with an already-live Erlang binary.
// The expected binary is shared by reference count, not copied, and no
// second full-object binary or Rust buffer is allocated.
#[rustler::nif]
fn verify<'a>(
    env: Env<'a>,
    reference: Term<'a>,
    config: StoreConfig,
    key: String,
    expected: Binary,
    timeout_ms: u64,
) -> NifResult<Atom> {
    if timeout_ms == 0 {
        return Err(Failure::Atom(atoms::timeout()).into());
    }
    let expected = bytes_from_binary(expected);
    Ok(spawn(env, reference, config, move |store| async move {
        let result = tokio::time::timeout(
            std::time::Duration::from_millis(timeout_ms.min(15_000)),
            async {
                let obj = store.get(&Path::from(key)).await?;
                if obj.meta.size != expected.len() as u64 {
                    return Ok((false, 0));
                }
                compare_stream(obj.into_stream(), &expected).await
            },
        )
        .await;
        let (matches, read) = result
            .map_err(|_| Failure::Atom(atoms::timeout()))?
            .map_err(map_object_store_error)?;
        Ok(Reply::Verified(matches, read))
    }))
}

async fn compare_stream(
    mut stream: impl futures::Stream<Item = Result<Bytes, ObjectStoreError>> + Unpin,
    expected: &[u8],
) -> Result<(bool, usize), ObjectStoreError> {
    let mut offset = 0usize;
    while let Some(chunk) = stream.try_next().await? {
        // The sum cannot overflow: offset <= expected.len(), and both are
        // slices whose individual allocations fit isize::MAX.
        let end = offset + chunk.len();
        if end > expected.len() {
            return Err(verification_length_error(end, expected.len()));
        }
        if expected[offset..end] != chunk {
            return Ok((false, end));
        }
        offset = end;
    }
    if offset != expected.len() {
        return Err(verification_length_error(offset, expected.len()));
    }
    Ok((true, offset))
}

fn verification_length_error(actual: usize, expected: usize) -> ObjectStoreError {
    // The header matched expected.len(). A body/header disagreement is a
    // transport/provider failure, NOT a permanent stored-content conflict.
    ObjectStoreError::Generic {
        store: "pulse_object_store",
        source: format!("verification body/header length mismatch ({actual} != {expected})").into(),
    }
}

// Conditional update: If-Match: <etag>. Fails with `:precondition_failed`
// if the current object's ETag differs from the caller's expected one.
// This is the manifest CAS primitive: every legitimate update carries the
// ETag it read; a stale writer loses to a fresher one.
#[rustler::nif]
fn put_if_match<'a>(
    env: Env<'a>,
    reference: Term<'a>,
    config: StoreConfig,
    key: String,
    data: Binary,
    etag: String,
) -> NifResult<Atom> {
    let opts = PutOptions {
        mode: PutMode::Update(UpdateVersion {
            e_tag: Some(etag),
            version: None,
        }),
        ..PutOptions::default()
    };
    put_with(env, reference, config, key, data, opts)
}

// Streams a GET body into one `OwnedBinary` sized from the response headers:
// a single full-payload allocation and no intermediate Rust-side copy. The
// alternative `GetResult::bytes()` first collects every chunk into a
// `BytesMut`, which would still have to be copied into an Erlang binary.
async fn read_body(obj: object_store::GetResult) -> Result<(String, OwnedBinary), Failure> {
    let e_tag = etag_or_error(obj.meta.e_tag.clone())?;
    let size = usize::try_from(obj.meta.size).map_err(nif_error)?;
    let mut body =
        OwnedBinary::new(size).ok_or_else(|| nif_error("could not allocate object body"))?;
    let dst = body.as_mut_slice();
    let mut offset: usize = 0;
    let mut stream = obj.into_stream();
    while let Some(chunk) = stream.try_next().await.map_err(map_object_store_error)? {
        let end = offset + chunk.len();
        if end > size {
            return Err(nif_error(format!(
                "body exceeded declared size ({} > {})",
                end, size
            )));
        }
        dst[offset..end].copy_from_slice(&chunk);
        offset = end;
    }
    if offset != size {
        return Err(nif_error(format!(
            "body shorter than declared size ({} < {})",
            offset, size
        )));
    }
    Ok((e_tag, body))
}

#[rustler::nif]
fn get<'a>(env: Env<'a>, reference: Term<'a>, config: StoreConfig, key: String) -> NifResult<Atom> {
    Ok(spawn(env, reference, config, move |store| async move {
        let obj = store
            .get(&Path::from(key))
            .await
            .map_err(map_object_store_error)?;
        let (_etag, body) = read_body(obj).await?;
        Ok(Reply::Body(body))
    }))
}

// Conditional GET: if `etag` is non-empty, sends `If-None-Match: <etag>`.
// - Object unchanged → `:not_modified` (no body transferred). This is how
//   the query path avoids re-downloading a manifest every time.
// - Object changed or no etag was supplied → `{:ok, new_etag, body}`.
// - Missing key → `{:error, :not_found}`.
//
// The empty string sentinel avoids allocating an option on the Elixir
// side just to say "no cached ETag."
#[rustler::nif]
fn get_if_none_match<'a>(
    env: Env<'a>,
    reference: Term<'a>,
    config: StoreConfig,
    key: String,
    etag: String,
) -> NifResult<Atom> {
    get_limited(env, reference, config, key, etag, None)
}

// Reject oversized metadata before allocating its body.
#[rustler::nif]
fn get_bounded<'a>(
    env: Env<'a>,
    reference: Term<'a>,
    config: StoreConfig,
    key: String,
    etag: String,
    limit: u64,
) -> NifResult<Atom> {
    get_limited(env, reference, config, key, etag, Some(limit))
}

fn get_limited(
    env: Env,
    reference: Term,
    config: StoreConfig,
    key: String,
    etag: String,
    limit: Option<u64>,
) -> NifResult<Atom> {
    let opts = GetOptions {
        if_none_match: if etag.is_empty() { None } else { Some(etag) },
        ..GetOptions::default()
    };
    Ok(spawn(env, reference, config, move |store| async move {
        // 304 comes back as `ObjectStoreError::NotModified`, mapped to
        // `:not_modified`. Callers pattern-match on that and skip parsing.
        let obj = store
            .get_opts(&Path::from(key), opts)
            .await
            .map_err(map_object_store_error)?;
        if limit.is_some_and(|limit| obj.meta.size > limit) {
            return Err(Failure::Atom(atoms::response_too_large()));
        }
        let (etag, body) = read_body(obj).await?;
        Ok(Reply::EtagBody(etag, body))
    }))
}

// A lexical start-after cursor remains valid when earlier objects are deleted.
// Never collect the whole provider stream; a call returns at most 1,000 keys.
// Jump over each tenant's entire subtree instead of walking its telemetry.
// The next ASCII character after '/' is '0'. With Pulse's tenant alphabet,
// `<tenant>0` sorts past `<tenant>/...` but before every subsequent tenant's
// keys, including `<tenant>0/...`. Each provider request has a bounded page.
#[rustler::nif]
fn discover_tenants<'a>(
    env: Env<'a>,
    reference: Term<'a>,
    config: StoreConfig,
    after: String,
    limit: usize,
) -> NifResult<Atom> {
    if limit == 0 || limit > 64 {
        return Err(nif_error("invalid discovery limit").into());
    }
    Ok(spawn(env, reference, config, move |store| async move {
        let prefix = Path::from("tenants/");
        let mut cursor = if after.is_empty() { None } else { Some(after) };
        let mut tenants = Vec::new();
        for _ in 0..limit {
            let offset = cursor.as_ref().map(|t| Path::from(format!("tenants/{t}0")));
            let mut stream = match &offset {
                Some(path) => store.list_with_offset(Some(&prefix), path),
                None => store.list(Some(&prefix)),
            };
            let object = stream.try_next().await.map_err(map_object_store_error)?;
            let Some(object) = object else {
                return Ok(Reply::Page(tenants, None));
            };
            let key = object.location.to_string();
            let tenant = key
                .strip_prefix("tenants/")
                .and_then(|k| k.split('/').next())
                .ok_or_else(|| nif_error("invalid tenant listing"))?
                .to_string();
            if tenant.is_empty() {
                return Err(nif_error("invalid tenant listing"));
            }
            cursor = Some(tenant.clone());
            if tenant.len() <= 128
                && tenant
                    .bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b"_.-".contains(&b))
            {
                tenants.push(tenant);
            }
        }
        Ok(Reply::Page(tenants, cursor))
    }))
}

#[rustler::nif]
fn list_page<'a>(
    env: Env<'a>,
    reference: Term<'a>,
    config: StoreConfig,
    prefix: String,
    after: String,
    limit: usize,
) -> NifResult<Atom> {
    if limit == 0 || limit > 1000 {
        return Err(nif_error("invalid list page limit").into());
    }
    Ok(spawn(env, reference, config, move |store| async move {
        let path = Path::from(prefix);
        let offset = Path::from(after);
        let stream = if offset.as_ref().is_empty() {
            store.list(Some(&path))
        } else {
            store.list_with_offset(Some(&path), &offset)
        };
        let objects: Vec<_> = stream
            .take(limit + 1)
            .try_collect()
            .await
            .map_err(map_object_store_error)?;
        let more = objects.len() > limit;
        let keys: Vec<String> = objects
            .into_iter()
            .take(limit)
            .map(|obj| obj.location.to_string())
            .collect();
        let cursor = if more { keys.last().cloned() } else { None };
        Ok(Reply::Page(keys, cursor))
    }))
}

// Native slots outlive a killed BEAM caller: a DOWN message cannot release an
// I/O operation that is still running on the Tokio runtime, so the slot is
// held by the request itself.
static RETENTION_DELETES: AtomicUsize = AtomicUsize::new(0);
struct DeleteSlot;
impl Drop for DeleteSlot {
    fn drop(&mut self) {
        RETENTION_DELETES.fetch_sub(1, Ordering::SeqCst);
    }
}

#[rustler::nif]
fn delete_bounded<'a>(
    env: Env<'a>,
    reference: Term<'a>,
    config: StoreConfig,
    key: String,
) -> NifResult<Atom> {
    RETENTION_DELETES
        .fetch_update(Ordering::SeqCst, Ordering::SeqCst, |n| {
            if n < 4 {
                Some(n + 1)
            } else {
                None
            }
        })
        .map_err(|_| Error::from(Failure::Atom(atoms::retention_overloaded())))?;
    let slot = DeleteSlot;
    Ok(spawn(env, reference, config, move |store| async move {
        let _slot = slot;
        store
            .delete(&Path::from(key))
            .await
            .map_err(map_object_store_error)?;
        Ok(Reply::Ok)
    }))
}

#[rustler::nif]
fn delete<'a>(
    env: Env<'a>,
    reference: Term<'a>,
    config: StoreConfig,
    key: String,
) -> NifResult<Atom> {
    Ok(spawn(env, reference, config, move |store| async move {
        store
            .delete(&Path::from(key))
            .await
            .map_err(map_object_store_error)?;
        Ok(Reply::Ok)
    }))
}

#[rustler::nif]
fn list<'a>(
    env: Env<'a>,
    reference: Term<'a>,
    config: StoreConfig,
    prefix: String,
) -> NifResult<Atom> {
    Ok(spawn(env, reference, config, move |store| async move {
        let path = if prefix.is_empty() {
            None
        } else {
            Some(Path::from(prefix))
        };
        let mut stream = store.list(path.as_ref());
        let mut keys = Vec::new();
        while let Some(meta) = stream.try_next().await.map_err(nif_error)? {
            keys.push(meta.location.to_string());
        }
        Ok(Reply::Keys(keys))
    }))
}

// Delimiter listing discovers tenant directories without downloading every
// segment key. The object_store client follows provider pagination internally.
#[rustler::nif]
fn list_prefixes<'a>(
    env: Env<'a>,
    reference: Term<'a>,
    config: StoreConfig,
    prefix: String,
) -> NifResult<Atom> {
    Ok(spawn(env, reference, config, move |store| async move {
        let result = store
            .list_with_delimiter(Some(&Path::from(prefix)))
            .await
            .map_err(map_object_store_error)?;
        let prefixes = result
            .common_prefixes
            .into_iter()
            .map(|path| path.to_string())
            .collect();
        Ok(Reply::Keys(prefixes))
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn streamed_verification_is_exact_across_chunks_and_lengths() {
        for width in 1..=16 {
            let expected = b"zero\0utf8\xc2\xb5last";
            let chunks = expected
                .chunks(width)
                .map(|part| Ok(Bytes::copy_from_slice(part)));
            assert_eq!(
                RUNTIME
                    .block_on(compare_stream(futures::stream::iter(chunks), expected))
                    .unwrap(),
                (true, expected.len())
            );
        }
        for (body, expected, result) in [
            (&b""[..], &b""[..], (true, 0)),
            (&b"axc"[..], &b"abc"[..], (false, 3)),
        ] {
            let stream = futures::stream::iter([Ok(Bytes::copy_from_slice(body))]);
            assert_eq!(
                RUNTIME.block_on(compare_stream(stream, expected)).unwrap(),
                result
            );
        }
    }

    #[test]
    fn verification_stops_at_mismatch_and_propagates_incomplete_stream_errors() {
        for (body, expected) in [(&b"abc"[..], &b"ab"[..]), (&b"ab"[..], &b"abc"[..])] {
            let stream = futures::stream::iter([Ok(Bytes::copy_from_slice(body))]);
            assert!(RUNTIME.block_on(compare_stream(stream, expected)).is_err());
        }
        let stream = futures::stream::iter([
            Ok(Bytes::from_static(b"abc")),
            Err(ObjectStoreError::Generic {
                store: "test",
                source: "unreachable".into(),
            }),
        ]);
        assert_eq!(
            RUNTIME.block_on(compare_stream(stream, b"xbc")).unwrap(),
            (false, 3)
        );
        let stream = futures::stream::iter([
            Ok(Bytes::from_static(b"abc")),
            Err(ObjectStoreError::Generic {
                store: "test",
                source: "truncated".into(),
            }),
        ]);
        assert!(RUNTIME.block_on(compare_stream(stream, b"abcd")).is_err());
    }

    #[test]
    fn a_pending_verification_stream_can_be_cancelled_by_its_deadline() {
        let result = RUNTIME.block_on(async {
            tokio::time::timeout(
                std::time::Duration::from_millis(1),
                compare_stream(futures::stream::pending(), b"not delivered"),
            )
            .await
        });
        assert!(result.is_err());
    }
}

rustler::init!("Elixir.Pulse.ObjectStore.NIF");
