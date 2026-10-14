use serde::Serialize;
use std::collections::{BTreeMap, BTreeSet};
use std::path::PathBuf;
use tuist_cargo_cache_core::{
    ACTION_PROMISE_MEDIA_TYPE, ACTION_RESULT_BATCH_MEDIA_TYPE, ACTION_RESULT_MEDIA_TYPE,
    AGENT_PROTOCOL_VERSION, ActionPrediction, AgentRequest, AgentResponse, BLOB_MEDIA_TYPE,
    BLOB_PACK_MEDIA_TYPE, BLOB_PACK_RECEIPT_MEDIA_TYPE, CLIENT_METADATA_MEDIA_TYPE, CacheDigest,
    CacheDirectory, CacheFileNode, CcMetadata, DIRECTORY_MEDIA_TYPE, FileDigestResolution,
    FileDigestScope, FileIdentity, FileObjectIdentity, PROTOCOL_VERSION, PinnedFile, PinnedState,
    RecordedFileDigest, RemoteActionResult, RestoreStats, RustcMetadata,
    TASK_ACTION_MANIFEST_MEDIA_TYPE, canonical_json,
};

const AGENT_FIXTURE: &str = include_str!("fixtures/agent-protocol-v11.jsonl");

fn digest() -> CacheDigest {
    CacheDigest {
        algorithm: "blake3".into(),
        hash: "a".repeat(64),
        size: 7,
    }
}

fn restore() -> RestoreStats {
    RestoreStats {
        copied_output_bytes: 17,
        copied_output_files: 16,
        duration_ns: 11,
        avoided_compiler_duration_ns: 10,
        output_files: 12,
        output_bytes: 13,
        reflinked_output_bytes: 15,
        reflinked_output_files: 14,
        hardlinked_output_bytes: 21,
        hardlinked_output_files: 20,
        reused_output_files: 18,
        reused_output_bytes: 19,
    }
}

fn result() -> RemoteActionResult {
    RemoteActionResult {
        action: digest(),
        metadata: None,
        output_root: Some(digest()),
        version: 1,
    }
}

fn prediction() -> ActionPrediction {
    ActionPrediction {
        invocation: digest(),
        action: digest(),
        adapter: "rustc".into(),
        payload: "{}".into(),
    }
}

fn file_identity() -> FileIdentity {
    FileIdentity {
        path: PathBuf::from("target/debug/deps/libserde.rlib"),
        len: 7,
        // A multiple of 100ns: Windows file times carry no finer resolution,
        // and a value it truncates would give this fixture two spellings.
        modified: std::time::SystemTime::UNIX_EPOCH
            + std::time::Duration::new(1_700_000_000, 2_100),
        changed: Some((1_700_000_000, 21)),
        object: None,
    }
}

fn object_file_identity() -> FileIdentity {
    FileIdentity {
        object: Some(FileObjectIdentity {
            device_major: 8,
            device_minor: 1,
            mount_id: 42,
            inode: 99,
        }),
        ..file_identity()
    }
}

fn environment() -> BTreeMap<String, Option<String>> {
    BTreeMap::from([
        ("RUSTFLAGS".into(), Some("-Cdebuginfo=1".into())),
        ("UNSET".into(), None),
    ])
}

macro_rules! define_variant_coverage {
    ($variant_name:ident, $expected:ident, $type:ty, { $($pattern:pat => $name:literal),+ $(,)? }) => {
        const $expected: &[&str] = &[$($name),+];

        fn $variant_name(value: &$type) -> &'static str {
            match value {
                $($pattern => $name),+
            }
        }
    };
}

fn assert_variant_coverage<'a>(
    expected: &[&'a str],
    actual: impl IntoIterator<Item = &'a str>,
    protocol: &str,
) {
    let expected = expected.iter().copied().collect::<BTreeSet<_>>();
    let actual = actual.into_iter().collect::<BTreeSet<_>>();
    assert_eq!(actual, expected, "missing {protocol} golden vectors");
}

fn requests() -> Vec<(&'static str, AgentRequest)> {
    vec![
        (
            "request.record_wrapper_timing",
            AgentRequest::RecordWrapperTiming {
                timing: {
                    let mut timing = tuist_cargo_cache_core::WrapperTiming::default();
                    timing.unit_id = Some("5d4c3b2a".into());
                    timing.dependencies = vec!["aa11".into(), "run-dd44".into()];
                    timing
                },
            },
        ),
        (
            "request.hello",
            AgentRequest::Hello {
                protocol: AGENT_PROTOCOL_VERSION,
                client_version: "0.3.0".into(),
            },
        ),
        (
            "request.begin_task",
            AgentRequest::BeginTask {
                task: "a".repeat(64),
            },
        ),
        (
            "request.commit_task",
            AgentRequest::CommitTask {
                run: "task-run".into(),
            },
        ),
        (
            "request.find_blob",
            AgentRequest::FindBlob { digest: digest() },
        ),
        (
            "request.find_blobs",
            AgentRequest::FindBlobs {
                digests: vec![digest()],
            },
        ),
        (
            "request.store_blob",
            AgentRequest::StoreBlob {
                digest: digest(),
                source: PathBuf::from("cache/blob"),
            },
        ),
        (
            "request.find_action_result",
            AgentRequest::FindActionResult { action: digest() },
        ),
        (
            "request.record_action_hit",
            AgentRequest::RecordActionHit {
                action: digest(),
                restore: restore(),
                crate_name: Some("serde".into()),
            },
        ),
        (
            "request.record_bypass",
            AgentRequest::RecordBypass {
                kind: "compiler-query".into(),
            },
        ),
        (
            "request.record_unconsulted",
            AgentRequest::RecordUnconsulted,
        ),
        (
            "request.record_warning",
            AgentRequest::RecordWarning {
                message: "cc result was not restored: blob missing".into(),
            },
        ),
        (
            "request.record_debug",
            AgentRequest::RecordDebug {
                target: "tuist_cargo_cache::session".into(),
                message: "rustc cache bypassed: compiler query".into(),
            },
        ),
        (
            "request.record_error",
            AgentRequest::RecordError {
                message: "compilation result was discarded".into(),
            },
        ),
        (
            "request.record_compiler_invocation",
            AgentRequest::RecordCompilerInvocation {
                outcome: "miss".into(),
                crate_name: Some("fixture".into()),
                duration_ns: 19,
            },
        ),
        (
            "request.record_action_verification",
            AgentRequest::RecordActionVerification {
                matched: true,
                restore: restore(),
            },
        ),
        (
            "request.store_action_result",
            AgentRequest::StoreActionResult { result: result() },
        ),
        (
            "request.find_action_prediction",
            AgentRequest::FindActionPrediction {
                task: "task-id".into(),
                invocation: digest(),
            },
        ),
        (
            "request.record_action_prediction",
            AgentRequest::RecordActionPrediction {
                task: "task-id".into(),
                prediction: prediction(),
            },
        ),
        (
            "request.find_executable_identity",
            AgentRequest::FindExecutableIdentity {
                executable: PathBuf::from("bin/rustc"),
                environment: environment(),
            },
        ),
        (
            "request.store_executable_identity",
            AgentRequest::StoreExecutableIdentity {
                executable: PathBuf::from("bin/rustc"),
                environment: environment(),
                stdout: b"rustc".to_vec(),
                pins: vec![PinnedFile {
                    path: PathBuf::from("bin/rustc"),
                    state: Some(PinnedState {
                        len: 5,
                        modified_secs: 6,
                        modified_nanos: 7,
                        changed_secs: 8,
                        changed_nanos: 9,
                        inode: 10,
                        mode: 11,
                    }),
                }],
            },
        ),
        (
            "request.find_file_digests",
            AgentRequest::FindFileDigests {
                scope: FileDigestScope::Content,
                files: vec![file_identity()],
            },
        ),
        (
            "request.record_file_digests",
            AgentRequest::RecordFileDigests {
                scope: FileDigestScope::CcInput,
                entries: vec![RecordedFileDigest {
                    file: file_identity(),
                    digest: digest(),
                }],
            },
        ),
        (
            "request.join_action_promise",
            AgentRequest::JoinActionPromise {
                adapter: "rustc".into(),
                invocation: digest(),
            },
        ),
        (
            "request.complete_action_promise",
            AgentRequest::CompleteActionPromise {
                claim: "claim-1".into(),
                prediction: prediction(),
            },
        ),
        (
            "request.resolve_file_digests",
            AgentRequest::ResolveFileDigests {
                scope: FileDigestScope::Content,
                files: vec![file_identity(), object_file_identity()],
            },
        ),
    ]
}

fn responses() -> Vec<(&'static str, AgentResponse)> {
    vec![
        (
            "response.wrapper_timing_recorded",
            AgentResponse::WrapperTimingRecorded,
        ),
        (
            "response.hello",
            AgentResponse::Hello {
                protocol: AGENT_PROTOCOL_VERSION,
                agent_version: "0.3.0".into(),
            },
        ),
        (
            "response.task_begun",
            AgentResponse::TaskBegun {
                run: "task-run".into(),
            },
        ),
        ("response.task_committed", AgentResponse::TaskCommitted),
        (
            "response.blob",
            AgentResponse::Blob {
                path: Some(PathBuf::from("cache/blob")),
            },
        ),
        ("response.blob_missing", AgentResponse::Blob { path: None }),
        (
            "response.blobs",
            AgentResponse::Blobs {
                paths: vec![Some(PathBuf::from("cache/blob")), None],
            },
        ),
        (
            "response.stored",
            AgentResponse::Stored {
                path: PathBuf::from("cache/blob"),
            },
        ),
        (
            "response.action_result",
            AgentResponse::ActionResult {
                result: Some(result()),
            },
        ),
        (
            "response.action_result_missing",
            AgentResponse::ActionResult { result: None },
        ),
        (
            "response.action_hit_recorded",
            AgentResponse::ActionHitRecorded,
        ),
        (
            "response.action_verification_recorded",
            AgentResponse::ActionVerificationRecorded,
        ),
        ("response.bypass_recorded", AgentResponse::BypassRecorded),
        (
            "response.unconsulted_recorded",
            AgentResponse::UnconsultedRecorded,
        ),
        ("response.warning_recorded", AgentResponse::WarningRecorded),
        ("response.error_recorded", AgentResponse::ErrorRecorded),
        ("response.debug_recorded", AgentResponse::DebugRecorded),
        (
            "response.compiler_invocation_recorded",
            AgentResponse::CompilerInvocationRecorded,
        ),
        (
            "response.action_stored",
            AgentResponse::ActionStored {
                path: PathBuf::from("cache/action"),
            },
        ),
        (
            "response.action_prediction",
            AgentResponse::ActionPrediction {
                prediction: Some(prediction()),
            },
        ),
        (
            "response.action_prediction_missing",
            AgentResponse::ActionPrediction { prediction: None },
        ),
        (
            "response.action_prediction_recorded",
            AgentResponse::ActionPredictionRecorded,
        ),
        (
            "response.executable_identity",
            AgentResponse::ExecutableIdentity {
                stdout: Some(b"rustc".to_vec()),
            },
        ),
        (
            "response.executable_identity_missing",
            AgentResponse::ExecutableIdentity { stdout: None },
        ),
        (
            "response.error",
            AgentResponse::Error {
                message: "incompatible protocol".into(),
            },
        ),
        (
            "response.file_digests",
            AgentResponse::FileDigests {
                digests: vec![Some(digest()), None],
            },
        ),
        (
            "response.file_digests_recorded",
            AgentResponse::FileDigestsRecorded,
        ),
        (
            "response.action_promise_claimed",
            AgentResponse::ActionPromise {
                claim: Some("claim-1".into()),
                prediction: None,
            },
        ),
        (
            "response.action_promise_complete",
            AgentResponse::ActionPromise {
                claim: None,
                prediction: Some(prediction()),
            },
        ),
        (
            "response.action_promise_unavailable",
            AgentResponse::ActionPromise {
                claim: None,
                prediction: None,
            },
        ),
        (
            "response.action_promise_completed",
            AgentResponse::ActionPromiseCompleted,
        ),
        (
            "response.file_digests_resolved",
            AgentResponse::FileDigestsResolved {
                resolutions: vec![
                    FileDigestResolution::Digest(digest()),
                    FileDigestResolution::EmbeddedTimestampMacro,
                    FileDigestResolution::Unresolved,
                ],
            },
        ),
    ]
}

fn fixture() -> BTreeMap<&'static str, &'static str> {
    AGENT_FIXTURE
        .lines()
        .map(|line| {
            line.split_once('\t')
                .expect("fixture line must contain a tab")
        })
        .collect()
}

fn assert_fixture<T: Serialize>(expected: &mut BTreeMap<&str, &str>, name: &str, value: &T) {
    let actual = String::from_utf8(canonical_json(value).unwrap()).unwrap();
    assert_eq!(
        actual,
        expected.remove(name).expect("fixture entry is missing"),
        "{name}"
    );
}

#[test]
fn agent_protocol_v11_shapes_match_the_conformance_fixture() {
    let mut expected = fixture();
    for line in AGENT_FIXTURE.lines() {
        let (name, json) = line
            .split_once('\t')
            .expect("fixture line must contain a tab");
        if name.starts_with("request.") {
            request_variant_name(&serde_json::from_str(json).unwrap());
        } else if name.starts_with("response.") {
            response_variant_name(&serde_json::from_str(json).unwrap());
        }
    }
    let requests = requests();
    assert_variant_coverage(
        EXPECTED_REQUEST_VARIANTS,
        requests
            .iter()
            .map(|(_, request)| request_variant_name(request)),
        "request",
    );
    for (name, request) in requests {
        assert_fixture(&mut expected, name, &request);
    }
    let responses = responses();
    assert_variant_coverage(
        EXPECTED_RESPONSE_VARIANTS,
        responses
            .iter()
            .map(|(_, response)| response_variant_name(response)),
        "response",
    );
    for (name, response) in responses {
        assert_fixture(&mut expected, name, &response);
    }
    assert_fixture(&mut expected, "record.action_result", &result());
    assert_fixture(
        &mut expected,
        "record.directory",
        &CacheDirectory {
            directories: vec![],
            files: vec![CacheFileNode {
                digest: digest(),
                executable: false,
                mode: 0o644,
                name: "lib.rlib".into(),
            }],
            symlinks: vec![],
            version: 1,
        },
    );
    assert_fixture(
        &mut expected,
        "record.rustc_metadata",
        &RustcMetadata {
            version: 1,
            kind: "rustc".into(),
            stdout: digest(),
            stderr: digest(),
        },
    );
    assert_fixture(
        &mut expected,
        "record.cc_metadata",
        &CcMetadata {
            version: 1,
            kind: "cc".into(),
            stdout: digest(),
            stderr: digest(),
        },
    );
    assert!(
        expected.is_empty(),
        "unexercised fixture entries: {expected:?}"
    );
}

#[test]
fn protocol_constants_match_the_contract() {
    assert_eq!(AGENT_PROTOCOL_VERSION, 11);
    assert_eq!(PROTOCOL_VERSION, 1);
    assert_eq!(
        ACTION_RESULT_MEDIA_TYPE,
        "application/vnd.tuist_cargo_cache.cache-action-result.v1+json"
    );
    assert_eq!(
        DIRECTORY_MEDIA_TYPE,
        "application/vnd.tuist_cargo_cache.cache-directory.v1+json"
    );
    assert_eq!(
        CLIENT_METADATA_MEDIA_TYPE,
        "application/vnd.tuist_cargo_cache.cache-client-metadata.v1+json"
    );
    assert_eq!(
        TASK_ACTION_MANIFEST_MEDIA_TYPE,
        "application/vnd.tuist_cargo_cache.cache-task-action-manifest.v1+json"
    );
    assert_eq!(BLOB_MEDIA_TYPE, "application/octet-stream");
    assert_eq!(
        BLOB_PACK_MEDIA_TYPE,
        "application/vnd.tuist_cargo_cache.cache-blob-pack.v1"
    );
    assert_eq!(
        ACTION_RESULT_BATCH_MEDIA_TYPE,
        "application/vnd.tuist_cargo_cache.cache-action-result-batch.v1+json"
    );
    assert_eq!(
        ACTION_PROMISE_MEDIA_TYPE,
        "application/vnd.tuist_cargo_cache.cache-action-promise.v1+json"
    );
    assert_eq!(
        BLOB_PACK_RECEIPT_MEDIA_TYPE,
        "application/vnd.tuist_cargo_cache.cache-blob-pack-receipt.v1+json"
    );
}

define_variant_coverage!(request_variant_name, EXPECTED_REQUEST_VARIANTS, AgentRequest, {
    AgentRequest::Hello { .. } => "hello",
    AgentRequest::BeginTask { .. } => "begin_task",
    AgentRequest::CommitTask { .. } => "commit_task",
    AgentRequest::FindBlob { .. } => "find_blob",
    AgentRequest::FindBlobs { .. } => "find_blobs",
    AgentRequest::StoreBlob { .. } => "store_blob",
    AgentRequest::FindActionResult { .. } => "find_action_result",
    AgentRequest::RecordActionHit { .. } => "record_action_hit",
    AgentRequest::RecordBypass { .. } => "record_bypass",
    AgentRequest::RecordUnconsulted => "record_unconsulted",
    AgentRequest::RecordWarning { .. } => "record_warning",
    AgentRequest::RecordError { .. } => "record_error",
    AgentRequest::RecordDebug { .. } => "record_debug",
    AgentRequest::RecordCompilerInvocation { .. } => "record_compiler_invocation",
    AgentRequest::RecordActionVerification { .. } => "record_action_verification",
    AgentRequest::StoreActionResult { .. } => "store_action_result",
    AgentRequest::FindActionPrediction { .. } => "find_action_prediction",
    AgentRequest::RecordActionPrediction { .. } => "record_action_prediction",
    AgentRequest::FindExecutableIdentity { .. } => "find_executable_identity",
    AgentRequest::StoreExecutableIdentity { .. } => "store_executable_identity",
    AgentRequest::FindFileDigests { .. } => "find_file_digests",
    AgentRequest::RecordFileDigests { .. } => "record_file_digests",
    AgentRequest::JoinActionPromise { .. } => "join_action_promise",
    AgentRequest::CompleteActionPromise { .. } => "complete_action_promise",
    AgentRequest::ResolveFileDigests { .. } => "resolve_file_digests",
    AgentRequest::RecordWrapperTiming { .. } => "record_wrapper_timing",
});

define_variant_coverage!(response_variant_name, EXPECTED_RESPONSE_VARIANTS, AgentResponse, {
    AgentResponse::Hello { .. } => "hello",
    AgentResponse::TaskBegun { .. } => "task_begun",
    AgentResponse::TaskCommitted => "task_committed",
    AgentResponse::Blob { .. } => "blob",
    AgentResponse::Blobs { .. } => "blobs",
    AgentResponse::Stored { .. } => "stored",
    AgentResponse::ActionResult { .. } => "action_result",
    AgentResponse::ActionHitRecorded => "action_hit_recorded",
    AgentResponse::ActionVerificationRecorded => "action_verification_recorded",
    AgentResponse::BypassRecorded => "bypass_recorded",
    AgentResponse::UnconsultedRecorded => "unconsulted_recorded",
    AgentResponse::WarningRecorded => "warning_recorded",
    AgentResponse::ErrorRecorded => "error_recorded",
    AgentResponse::DebugRecorded => "debug_recorded",
    AgentResponse::CompilerInvocationRecorded => "compiler_invocation_recorded",
    AgentResponse::ActionStored { .. } => "action_stored",
    AgentResponse::ActionPrediction { .. } => "action_prediction",
    AgentResponse::ActionPredictionRecorded => "action_prediction_recorded",
    AgentResponse::ExecutableIdentity { .. } => "executable_identity",
    AgentResponse::Error { .. } => "error",
    AgentResponse::FileDigests { .. } => "file_digests",
    AgentResponse::FileDigestsRecorded => "file_digests_recorded",
    AgentResponse::ActionPromise { .. } => "action_promise",
    AgentResponse::ActionPromiseCompleted => "action_promise_completed",
    AgentResponse::FileDigestsResolved { .. } => "file_digests_resolved",
    AgentResponse::WrapperTimingRecorded => "wrapper_timing_recorded",
});
