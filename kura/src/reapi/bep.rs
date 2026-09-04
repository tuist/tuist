use std::{
    collections::HashMap,
    pin::Pin,
    sync::Arc,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use futures_util::Stream;
use prost::Message;
use prost_types::{Duration as ProtoDuration, Timestamp};
use tokio::sync::{Mutex, mpsc};
use tokio_stream::wrappers::ReceiverStream;
use tonic::{Request, Response, Status, Streaming};
use tracing::warn;

use crate::{
    analytics::BazelInvocationAnalyticsEvent,
    bazel_test_artifacts::{
        BazelTestArtifact, BazelTestArtifactKind, BazelTestInvocationFinished,
        BazelTestResult as DeliveredBazelTestResult, BazelTestSummary as DeliveredBazelTestSummary,
        MAX_BAZEL_TEST_ARTIFACT_BYTES,
    },
    state::SharedState,
};

pub(crate) mod proto {
    include!("bep_proto.rs");
}

use proto::{
    OrderedBuildEvent, PublishBuildToolEventStreamRequest, PublishBuildToolEventStreamResponse,
    PublishLifecycleEventRequest,
    build_event::Event as BuildEventServiceEvent,
    publish_build_event_server::{
        PublishBuildEvent, PublishBuildEventServer as GeneratedPublishBuildEventServer,
    },
};

pub type PublishBuildEventServer = GeneratedPublishBuildEventServer<BuildEventService>;

const BUILD_EVENT_SERVICE_ROUTE: &str =
    "/google.devtools.build.v1.PublishBuildEvent/PublishBuildToolEventStream";
const LIFECYCLE_EVENT_SERVICE_ROUTE: &str =
    "/google.devtools.build.v1.PublishBuildEvent/PublishLifecycleEvent";
const PROJECT_HANDLE_HEADER: &str = "x-tuist-project-handle";
const BAZEL_BUILD_EVENT_TYPE_URL: &str = "type.googleapis.com/build_event_stream.BuildEvent";
const MAX_IN_FLIGHT_INVOCATIONS: usize = 4_096;
const MAX_IN_FLIGHT_INVOCATIONS_PER_PROJECT: usize = 256;
const MAX_INVOCATION_LIFETIME: Duration = Duration::from_secs(24 * 60 * 60);
const MAX_INVOCATION_ID_BYTES: usize = 256;
const MAX_COMMAND_BYTES: usize = 256;
const MAX_TARGET_LABEL_BYTES: usize = 1_024;
const MAX_TEST_ARTIFACTS_PER_RESULT: usize = 2;
const MAX_TARGET_PATTERNS: usize = 128;
const MAX_GIT_REF_BYTES: usize = 1_024;

#[derive(Clone)]
pub struct BuildEventService {
    state: SharedState,
    invocations: Arc<Mutex<HashMap<String, InvocationStart>>>,
}

#[derive(Clone)]
struct InvocationStart {
    account_handle: String,
    project_handle: String,
    invocation_id: String,
    command: String,
    target_patterns: Vec<String>,
    git_branch: String,
    git_commit_sha: String,
    is_ci: bool,
    started_at_ms: u64,
    inserted_at: Instant,
}

struct TestResultContext<'a> {
    account_handle: &'a str,
    project_handle: &'a str,
    invocation_id: &'a str,
    target_label: &'a str,
    is_ci: bool,
    sequence_number: i64,
}

#[derive(Clone, PartialEq, Message)]
struct BazelBuildEvent {
    #[prost(message, optional, tag = "1")]
    id: Option<BazelBuildEventId>,
    #[prost(message, optional, tag = "5")]
    started: Option<BazelBuildStarted>,
    #[prost(message, optional, tag = "9")]
    test_summary: Option<BazelTestSummary>,
    #[prost(message, optional, tag = "10")]
    test_result: Option<BazelTestResult>,
    #[prost(message, optional, tag = "14")]
    finished: Option<BazelBuildFinished>,
    #[prost(message, optional, tag = "16")]
    workspace_status: Option<BazelWorkspaceStatus>,
    #[prost(message, optional, tag = "26")]
    build_metadata: Option<BazelBuildMetadata>,
}

#[derive(Clone, PartialEq, Message)]
struct BazelBuildEventId {
    #[prost(message, optional, tag = "4")]
    pattern: Option<BazelPatternExpandedId>,
    #[prost(message, optional, tag = "7")]
    test_summary: Option<BazelTestSummaryId>,
    #[prost(message, optional, tag = "8")]
    test_result: Option<BazelTestResultId>,
}

#[derive(Clone, PartialEq, Message)]
struct BazelPatternExpandedId {
    #[prost(string, repeated, tag = "1")]
    pattern: Vec<String>,
}

#[derive(Clone, PartialEq, Message)]
struct BazelTestResultId {
    #[prost(string, tag = "1")]
    label: String,
    #[prost(int32, tag = "2")]
    run: i32,
    #[prost(int32, tag = "3")]
    shard: i32,
    #[prost(int32, tag = "4")]
    attempt: i32,
}

#[derive(Clone, PartialEq, Message)]
struct BazelTestSummaryId {
    #[prost(string, tag = "1")]
    label: String,
}

#[derive(Clone, PartialEq, Message)]
struct BazelBuildStarted {
    #[prost(string, tag = "1")]
    uuid: String,
    #[prost(int64, tag = "2")]
    start_time_millis: i64,
    #[prost(string, tag = "5")]
    command: String,
    #[prost(message, optional, tag = "9")]
    start_time: Option<Timestamp>,
}

#[derive(Clone, PartialEq, Message)]
struct BazelBuildFinished {
    #[prost(bool, tag = "1")]
    overall_success: bool,
    #[prost(int64, tag = "2")]
    finish_time_millis: i64,
    #[prost(message, optional, tag = "3")]
    exit_code: Option<BazelExitCode>,
    #[prost(message, optional, tag = "5")]
    finish_time: Option<Timestamp>,
}

#[derive(Clone, PartialEq, Message)]
struct BazelExitCode {
    #[prost(string, tag = "1")]
    name: String,
    #[prost(int32, tag = "2")]
    code: i32,
}

#[derive(Clone, PartialEq, Message)]
struct BazelBuildMetadata {
    #[prost(map = "string, string", tag = "1")]
    metadata: HashMap<String, String>,
}

#[derive(Clone, PartialEq, Message)]
struct BazelWorkspaceStatus {
    #[prost(message, repeated, tag = "1")]
    item: Vec<BazelWorkspaceStatusItem>,
}

#[derive(Clone, PartialEq, Message)]
struct BazelWorkspaceStatusItem {
    #[prost(string, tag = "1")]
    key: String,
    #[prost(string, tag = "2")]
    value: String,
}

#[derive(Clone, PartialEq, Message)]
struct BazelTestResult {
    #[prost(message, repeated, tag = "2")]
    test_action_output: Vec<BazelFile>,
    #[prost(int64, tag = "3")]
    test_attempt_duration_millis: i64,
    #[prost(bool, tag = "4")]
    cached_locally: bool,
    #[prost(enumeration = "BazelTestStatus", tag = "5")]
    status: i32,
    #[prost(int64, tag = "6")]
    test_attempt_start_millis_epoch: i64,
    #[prost(message, optional, tag = "8")]
    execution_info: Option<BazelTestExecutionInfo>,
    #[prost(message, optional, tag = "10")]
    test_attempt_start: Option<Timestamp>,
    #[prost(message, optional, tag = "11")]
    test_attempt_duration: Option<ProtoDuration>,
}

#[derive(Clone, PartialEq, Message)]
struct BazelTestSummary {
    #[prost(int32, tag = "1")]
    total_run_count: i32,
    #[prost(enumeration = "BazelTestStatus", tag = "5")]
    overall_status: i32,
    #[prost(int32, tag = "6")]
    total_num_cached: i32,
    #[prost(int64, tag = "7")]
    first_start_time_millis: i64,
    #[prost(int64, tag = "8")]
    last_stop_time_millis: i64,
    #[prost(int64, tag = "9")]
    total_run_duration_millis: i64,
    #[prost(message, optional, tag = "12")]
    total_run_duration: Option<ProtoDuration>,
    #[prost(message, optional, tag = "13")]
    first_start_time: Option<Timestamp>,
    #[prost(message, optional, tag = "14")]
    last_stop_time: Option<Timestamp>,
}

#[derive(Clone, PartialEq, Message)]
struct BazelFile {
    #[prost(string, tag = "1")]
    name: String,
    #[prost(string, optional, tag = "2")]
    uri: Option<String>,
    #[prost(bytes = "vec", optional, tag = "3")]
    contents: Option<Vec<u8>>,
    #[prost(string, repeated, tag = "4")]
    path_prefix: Vec<String>,
    #[prost(string, tag = "5")]
    digest: String,
    #[prost(int64, tag = "6")]
    length: i64,
}

#[derive(Clone, PartialEq, Message)]
struct BazelTestExecutionInfo {
    #[prost(string, tag = "2")]
    strategy: String,
    #[prost(bool, tag = "6")]
    cached_remotely: bool,
    #[prost(int32, tag = "7")]
    exit_code: i32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, prost::Enumeration)]
#[repr(i32)]
enum BazelTestStatus {
    NoStatus = 0,
    Passed = 1,
    Flaky = 2,
    Timeout = 3,
    Failed = 4,
    Incomplete = 5,
    RemoteFailure = 6,
    FailedToBuild = 7,
    ToolHaltedBeforeTesting = 8,
}

pub fn server(state: SharedState) -> PublishBuildEventServer {
    GeneratedPublishBuildEventServer::new(BuildEventService {
        state,
        invocations: Arc::new(Mutex::new(HashMap::new())),
    })
    .max_decoding_message_size(super::service::REAPI_MAX_DECODING_MESSAGE_SIZE)
}

#[tonic::async_trait]
impl PublishBuildEvent for BuildEventService {
    type PublishBuildToolEventStreamStream =
        Pin<Box<dyn Stream<Item = Result<PublishBuildToolEventStreamResponse, Status>> + Send>>;

    async fn publish_lifecycle_event(
        &self,
        request: Request<PublishLifecycleEventRequest>,
    ) -> Result<Response<()>, Status> {
        let project_handle = project_handle(request.metadata())?;
        let account_handle = super::service::authorize_build_event_request(
            &self.state,
            request.metadata(),
            &project_handle,
            LIFECYCLE_EVENT_SERVICE_ROUTE,
        )
        .await?;

        if let Some(event) = request.into_inner().build_event {
            self.process_event(&account_handle, &project_handle, event)
                .await;
        }

        Ok(Response::new(()))
    }

    async fn publish_build_tool_event_stream(
        &self,
        request: Request<Streaming<PublishBuildToolEventStreamRequest>>,
    ) -> Result<Response<Self::PublishBuildToolEventStreamStream>, Status> {
        let project_handle = project_handle(request.metadata())?;
        let account_handle = super::service::authorize_build_event_request(
            &self.state,
            request.metadata(),
            &project_handle,
            BUILD_EVENT_SERVICE_ROUTE,
        )
        .await?;
        let mut requests = request.into_inner();
        let service = self.clone();
        let (sender, receiver) = mpsc::channel(64);

        tokio::spawn(async move {
            loop {
                let request = match requests.message().await {
                    Ok(Some(request)) => request,
                    Ok(None) => break,
                    Err(error) => {
                        let _ = sender.send(Err(error)).await;
                        break;
                    }
                };

                let Some(event) = request.ordered_build_event else {
                    let _ = sender
                        .send(Err(Status::invalid_argument(
                            "ordered_build_event is required",
                        )))
                        .await;
                    break;
                };

                let response = PublishBuildToolEventStreamResponse {
                    stream_id: event.stream_id.clone(),
                    sequence_number: event.sequence_number,
                };
                service
                    .process_event(&account_handle, &project_handle, event)
                    .await;

                if sender.send(Ok(response)).await.is_err() {
                    break;
                }
            }
        });

        Ok(Response::new(Box::pin(ReceiverStream::new(receiver))))
    }
}

impl BuildEventService {
    async fn process_event(
        &self,
        account_handle: &str,
        project_handle: &str,
        ordered_event: OrderedBuildEvent,
    ) {
        let Some(BuildEventServiceEvent::BazelEvent(bazel_event)) = ordered_event
            .event
            .as_ref()
            .and_then(|event| event.event.as_ref())
        else {
            return;
        };

        if bazel_event.type_url != BAZEL_BUILD_EVENT_TYPE_URL {
            return;
        }

        let Ok(event) = BazelBuildEvent::decode(bazel_event.value.as_slice()) else {
            return;
        };

        if let Some(started) = event.started {
            let invocation_id = truncate_wire_string(
                &invocation_id(&ordered_event, &started.uuid),
                MAX_INVOCATION_ID_BYTES,
            );
            if invocation_id.is_empty() {
                return;
            }

            let start = InvocationStart {
                account_handle: account_handle.to_owned(),
                project_handle: project_handle.to_owned(),
                invocation_id: invocation_id.clone(),
                command: truncate_wire_string(&started.command, MAX_COMMAND_BYTES),
                target_patterns: Vec::new(),
                git_branch: String::new(),
                git_commit_sha: String::new(),
                is_ci: false,
                started_at_ms: timestamp_millis(started.start_time, started.start_time_millis),
                inserted_at: Instant::now(),
            };
            let key = invocation_key(account_handle, project_handle, &invocation_id);
            let mut invocations = self.invocations.lock().await;
            evict_expired_invocations(&mut invocations);

            let project_invocation_count = invocations
                .values()
                .filter(|invocation| {
                    invocation.account_handle == account_handle
                        && invocation.project_handle == project_handle
                })
                .count();
            if !invocations.contains_key(&key)
                && (invocations.len() >= MAX_IN_FLIGHT_INVOCATIONS
                    || project_invocation_count >= MAX_IN_FLIGHT_INVOCATIONS_PER_PROJECT)
            {
                warn!(
                    account_handle,
                    project_handle,
                    "dropping Bazel invocation start because the in-flight state limit was reached"
                );
                return;
            }

            invocations.insert(key, start);
            return;
        }

        let invocation_id =
            truncate_wire_string(&invocation_id(&ordered_event, ""), MAX_INVOCATION_ID_BYTES);
        if invocation_id.is_empty() {
            return;
        }

        if let Some(pattern) = event.id.as_ref().and_then(|id| id.pattern.as_ref()) {
            if let Some(start) = self.invocations.lock().await.get_mut(&invocation_key(
                account_handle,
                project_handle,
                &invocation_id,
            )) {
                start.target_patterns = pattern
                    .pattern
                    .iter()
                    .take(MAX_TARGET_PATTERNS)
                    .map(|pattern| truncate_wire_string(pattern, MAX_TARGET_LABEL_BYTES))
                    .filter(|pattern| !pattern.is_empty())
                    .collect();
            }
            return;
        }

        if let Some(metadata) = event.build_metadata {
            if let Some(start) = self.invocations.lock().await.get_mut(&invocation_key(
                account_handle,
                project_handle,
                &invocation_id,
            )) {
                apply_metadata(start, &metadata.metadata);
            }
            return;
        }

        if let Some(workspace_status) = event.workspace_status {
            if let Some(start) = self.invocations.lock().await.get_mut(&invocation_key(
                account_handle,
                project_handle,
                &invocation_id,
            )) {
                let metadata = workspace_status
                    .item
                    .into_iter()
                    .map(|item| (item.key, item.value))
                    .collect();
                apply_metadata(start, &metadata);
            }
            return;
        }

        if let Some(test_summary) = event.test_summary {
            let Some(test_summary_id) = event.id.as_ref().and_then(|id| id.test_summary.as_ref())
            else {
                self.state.metrics.record_analytics_event(
                    "bazel_test_summary",
                    "missing_target",
                    1,
                );
                return;
            };
            let target_label = truncate_wire_string(&test_summary_id.label, MAX_TARGET_LABEL_BYTES);
            if target_label.is_empty() {
                return;
            }

            if let Some(delivery) = self.state.bazel_test_artifacts.as_ref() {
                delivery.enqueue_test_summary(test_summary_delivery(
                    account_handle,
                    project_handle,
                    &invocation_id,
                    &target_label,
                    &test_summary,
                ));
            }
            return;
        }

        if let Some(test_result) = event.test_result {
            let Some(test_result_id) = event.id.and_then(|id| id.test_result) else {
                self.state.metrics.record_analytics_event(
                    "bazel_test_artifact",
                    "missing_target",
                    1,
                );
                return;
            };
            let target_label = truncate_wire_string(&test_result_id.label, MAX_TARGET_LABEL_BYTES);
            if target_label.is_empty() {
                return;
            }
            let is_ci = self
                .invocations
                .lock()
                .await
                .get(&invocation_key(
                    account_handle,
                    project_handle,
                    &invocation_id,
                ))
                .is_some_and(|start| start.is_ci);

            if let Some(delivery) = self.state.bazel_test_artifacts.as_ref() {
                delivery.enqueue_test_result(test_result_delivery(
                    TestResultContext {
                        account_handle,
                        project_handle,
                        invocation_id: &invocation_id,
                        target_label: &target_label,
                        is_ci,
                        sequence_number: ordered_event.sequence_number,
                    },
                    &test_result_id,
                    &test_result,
                ));
            }
            return;
        }

        if let Some(finished) = event.finished {
            let finished_at_ms =
                timestamp_millis(finished.finish_time, finished.finish_time_millis);

            let start = self.invocations.lock().await.remove(&invocation_key(
                account_handle,
                project_handle,
                &invocation_id,
            ));
            let start = start.unwrap_or_else(|| {
                warn!(
                    account_handle,
                    project_handle,
                    invocation_id,
                    "received a Bazel invocation finish without a local start event"
                );
                InvocationStart {
                    account_handle: account_handle.to_owned(),
                    project_handle: project_handle.to_owned(),
                    invocation_id: invocation_id.clone(),
                    command: "bazel".into(),
                    target_patterns: Vec::new(),
                    git_branch: String::new(),
                    git_commit_sha: String::new(),
                    is_ci: false,
                    started_at_ms: finished_at_ms,
                    inserted_at: Instant::now(),
                }
            });
            let exit_code = finished.exit_code.map(|exit_code| exit_code.code);
            let status = invocation_status(finished.overall_success, exit_code);

            if start.command == "test"
                && let Some(delivery) = self.state.bazel_test_artifacts.as_ref()
            {
                delivery
                    .enqueue_invocation_finished(BazelTestInvocationFinished {
                        account_handle: start.account_handle.clone(),
                        project_handle: start.project_handle.clone(),
                        invocation_id: start.invocation_id.clone(),
                    })
                    .await;
            }

            if let Some(analytics) = self.state.analytics.as_ref() {
                analytics.enqueue_bazel_invocation_event(completed_invocation_event(
                    start,
                    status,
                    exit_code,
                    finished_at_ms,
                ));
            }
        }
    }
}

fn test_summary_delivery(
    account_handle: &str,
    project_handle: &str,
    invocation_id: &str,
    target_label: &str,
    test_summary: &BazelTestSummary,
) -> DeliveredBazelTestSummary {
    DeliveredBazelTestSummary {
        account_handle: account_handle.to_owned(),
        project_handle: project_handle.to_owned(),
        invocation_id: invocation_id.to_owned(),
        target_label: target_label.to_owned(),
        status: test_status(test_summary.overall_status),
        total_run_count: test_summary.total_run_count.max(0),
        total_num_cached: test_summary.total_num_cached.max(0),
        duration_ms: proto_duration_millis(
            test_summary.total_run_duration.as_ref(),
            test_summary.total_run_duration_millis,
        ),
        started_at_ms: timestamp_millis(
            test_summary.first_start_time,
            test_summary.first_start_time_millis,
        ),
        finished_at_ms: timestamp_millis(
            test_summary.last_stop_time,
            test_summary.last_stop_time_millis,
        ),
    }
}

fn test_result_delivery(
    context: TestResultContext<'_>,
    test_result_id: &BazelTestResultId,
    test_result: &BazelTestResult,
) -> DeliveredBazelTestResult {
    let status = test_status(test_result.status);
    let duration_ms = proto_duration_millis(
        test_result.test_attempt_duration.as_ref(),
        test_result.test_attempt_duration_millis,
    );
    let started_at_ms = timestamp_millis(
        test_result.test_attempt_start,
        test_result.test_attempt_start_millis_epoch,
    );
    let cached = test_result.cached_locally
        || test_result
            .execution_info
            .as_ref()
            .is_some_and(|info| info.cached_remotely);

    let artifacts = test_result
        .test_action_output
        .iter()
        .filter_map(|output| {
            let artifact_kind = BazelTestArtifactKind::from_output_path(&output.name)?;
            let size = u64::try_from(output.length).ok()?;
            if size == 0
                || size > MAX_BAZEL_TEST_ARTIFACT_BYTES
                || !valid_sha256_digest(&output.digest)
            {
                return None;
            }

            Some(BazelTestArtifact {
                artifact_kind,
                digest: output.digest.clone(),
                size,
            })
        })
        .take(MAX_TEST_ARTIFACTS_PER_RESULT)
        .collect();

    DeliveredBazelTestResult {
        account_handle: context.account_handle.to_owned(),
        project_handle: context.project_handle.to_owned(),
        invocation_id: context.invocation_id.to_owned(),
        target_label: context.target_label.to_owned(),
        run: test_result_id.run,
        shard: test_result_id.shard,
        attempt: test_result_id.attempt,
        status,
        duration_ms,
        started_at_ms,
        cached,
        is_ci: context.is_ci,
        sequence_number: context.sequence_number,
        artifacts,
    }
}

fn test_status(status: i32) -> &'static str {
    match BazelTestStatus::try_from(status) {
        Ok(BazelTestStatus::Passed) => "success",
        Ok(BazelTestStatus::Flaky) => "flaky",
        Ok(BazelTestStatus::NoStatus | BazelTestStatus::Incomplete) => "skipped",
        Ok(
            BazelTestStatus::Timeout
            | BazelTestStatus::Failed
            | BazelTestStatus::RemoteFailure
            | BazelTestStatus::FailedToBuild
            | BazelTestStatus::ToolHaltedBeforeTesting,
        )
        | Err(_) => "failure",
    }
}

fn proto_duration_millis(duration: Option<&ProtoDuration>, legacy_millis: i64) -> u64 {
    if let Some(duration) = duration
        && duration.seconds >= 0
        && duration.nanos >= 0
    {
        return (duration.seconds as u64)
            .saturating_mul(1_000)
            .saturating_add(duration.nanos as u64 / 1_000_000);
    }

    u64::try_from(legacy_millis).unwrap_or_default()
}

fn apply_metadata(invocation: &mut InvocationStart, metadata: &HashMap<String, String>) {
    invocation.is_ci |= metadata.iter().any(|(key, value)| {
        matches!(
            key.to_ascii_uppercase().as_str(),
            "CI" | "ROLE" | "TUIST_CI"
        ) && matches!(
            value.to_ascii_lowercase().as_str(),
            "1" | "true" | "yes" | "ci"
        )
    });

    if let Some(branch) =
        metadata_value(metadata, &["BUILD_SCM_BRANCH", "GIT_BRANCH", "BRANCH_NAME"])
    {
        invocation.git_branch = truncate_wire_string(
            branch.strip_prefix("refs/heads/").unwrap_or(branch),
            MAX_GIT_REF_BYTES,
        );
    }
    if let Some(commit_sha) = metadata_value(
        metadata,
        &["BUILD_SCM_REVISION", "GIT_COMMIT", "COMMIT_SHA"],
    ) {
        invocation.git_commit_sha = truncate_wire_string(commit_sha, MAX_GIT_REF_BYTES);
    }
}

fn metadata_value<'a>(metadata: &'a HashMap<String, String>, keys: &[&str]) -> Option<&'a str> {
    keys.iter()
        .find_map(|key| metadata.get(*key))
        .map(String::as_str)
        .filter(|value| !value.is_empty())
}

fn valid_sha256_digest(digest: &str) -> bool {
    digest.len() == 64 && digest.bytes().all(|byte| byte.is_ascii_hexdigit())
}

fn invocation_status(overall_success: bool, exit_code: Option<i32>) -> &'static str {
    if exit_code.unwrap_or(if overall_success { 0 } else { 1 }) == 0 {
        "success"
    } else {
        "failure"
    }
}

fn project_handle(metadata: &tonic::metadata::MetadataMap) -> Result<String, Status> {
    metadata
        .get(PROJECT_HANDLE_HEADER)
        .and_then(|value| value.to_str().ok())
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
        .ok_or_else(|| {
            Status::invalid_argument(
                "x-tuist-project-handle is required for Build Event Service requests",
            )
        })
}

fn invocation_id(event: &OrderedBuildEvent, started_uuid: &str) -> String {
    event
        .stream_id
        .as_ref()
        .map(|stream_id| stream_id.invocation_id.as_str())
        .filter(|invocation_id| !invocation_id.is_empty())
        .or_else(|| (!started_uuid.is_empty()).then_some(started_uuid))
        .unwrap_or_default()
        .to_owned()
}

fn invocation_key(account_handle: &str, project_handle: &str, invocation_id: &str) -> String {
    format!("{account_handle}:{project_handle}:{invocation_id}")
}

fn completed_invocation_event(
    start: InvocationStart,
    status: &str,
    exit_code: Option<i32>,
    finished_at_ms: u64,
) -> BazelInvocationAnalyticsEvent {
    BazelInvocationAnalyticsEvent {
        account_handle: start.account_handle,
        project_handle: start.project_handle,
        invocation_id: start.invocation_id,
        command: start.command,
        target_patterns: start.target_patterns,
        git_branch: start.git_branch,
        git_commit_sha: start.git_commit_sha,
        is_ci: start.is_ci,
        status: status.into(),
        exit_code: exit_code.unwrap_or(if status == "success" { 0 } else { 1 }),
        started_at_ms: start.started_at_ms,
        finished_at_ms,
    }
}

fn truncate_wire_string(value: &str, max_bytes: usize) -> String {
    if value.len() <= max_bytes {
        return value.to_owned();
    }

    value
        .char_indices()
        .take_while(|(index, _)| *index < max_bytes)
        .map(|(_, character)| character)
        .collect()
}

fn evict_expired_invocations(invocations: &mut HashMap<String, InvocationStart>) {
    invocations.retain(|_, invocation| invocation.inserted_at.elapsed() < MAX_INVOCATION_LIFETIME);
}

fn timestamp_millis(timestamp: Option<Timestamp>, legacy_millis: i64) -> u64 {
    if let Some(timestamp) = timestamp
        && timestamp.seconds >= 0
        && timestamp.nanos >= 0
    {
        return timestamp.seconds as u64 * 1_000 + timestamp.nanos as u64 / 1_000_000;
    }

    if legacy_millis > 0 {
        legacy_millis as u64
    } else {
        now_millis()
    }
}

fn now_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis().try_into().unwrap_or(u64::MAX))
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    use crate::test_support::test_context;

    #[test]
    fn extracts_invocation_identity_from_the_build_event_stream() {
        let event = OrderedBuildEvent {
            stream_id: Some(proto::StreamId {
                build_id: "build-1".into(),
                invocation_id: "invocation-1".into(),
                component: 3,
            }),
            sequence_number: 1,
            event: None,
        };

        assert_eq!(invocation_id(&event, "started-uuid"), "invocation-1");
        assert_eq!(
            invocation_key("acme", "project", "invocation-1"),
            "acme:project:invocation-1"
        );
    }

    #[test]
    fn uses_the_modern_build_event_timestamp() {
        assert_eq!(
            timestamp_millis(
                Some(Timestamp {
                    seconds: 1_700_000_000,
                    nanos: 123_000_000,
                }),
                0
            ),
            1_700_000_000_123
        );
    }

    #[test]
    fn reports_a_failed_build_when_bazel_marks_it_unsuccessful() {
        assert_eq!(invocation_status(false, Some(0)), "success");
        assert_eq!(invocation_status(true, Some(1)), "failure");
        assert_eq!(invocation_status(false, None), "failure");
        assert_eq!(invocation_status(true, None), "success");
    }

    #[tokio::test]
    async fn tracks_a_completed_invocation_from_bazel_build_events() {
        let context = test_context(|_| {}).await;
        let service = BuildEventService {
            state: context.state,
            invocations: Arc::new(Mutex::new(HashMap::new())),
        };

        service
            .process_event(
                "acme",
                "ios",
                ordered_bazel_event(
                    "invocation-1",
                    BazelBuildEvent {
                        id: None,
                        started: Some(BazelBuildStarted {
                            uuid: "started-uuid".into(),
                            start_time_millis: 1_700_000_000_000,
                            command: "test".into(),
                            start_time: None,
                        }),
                        test_summary: None,
                        test_result: None,
                        finished: None,
                        workspace_status: None,
                        build_metadata: None,
                    },
                ),
            )
            .await;

        let starts = service.invocations.lock().await;
        let start = starts
            .get("acme:ios:invocation-1")
            .expect("a BuildStarted event should create invocation state");
        assert_eq!(start.account_handle, "acme");
        assert_eq!(start.command, "test");
        drop(starts);

        service
            .process_event(
                "acme",
                "ios",
                ordered_bazel_event(
                    "invocation-1",
                    BazelBuildEvent {
                        id: None,
                        started: None,
                        test_summary: None,
                        test_result: None,
                        finished: Some(BazelBuildFinished {
                            overall_success: true,
                            finish_time_millis: 1_700_000_015_000,
                            exit_code: Some(BazelExitCode {
                                name: "SUCCESS".into(),
                                code: 0,
                            }),
                            finish_time: None,
                        }),
                        workspace_status: None,
                        build_metadata: None,
                    },
                ),
            )
            .await;

        assert!(service.invocations.lock().await.is_empty());
    }

    #[test]
    fn maps_a_completed_invocation_to_analytics() {
        let event = completed_invocation_event(
            InvocationStart {
                account_handle: "acme".into(),
                project_handle: "ios".into(),
                invocation_id: "invocation-1".into(),
                command: "test //app:tests".into(),
                target_patterns: vec!["//app:tests".into()],
                git_branch: "main".into(),
                git_commit_sha: "abc123".into(),
                is_ci: false,
                started_at_ms: 1_700_000_000_000,
                inserted_at: Instant::now(),
            },
            "failure",
            None,
            1_700_000_015_000,
        );

        assert_eq!(event.account_handle, "acme");
        assert_eq!(event.project_handle, "ios");
        assert_eq!(event.invocation_id, "invocation-1");
        assert_eq!(event.command, "test //app:tests");
        assert_eq!(event.target_patterns, ["//app:tests"]);
        assert_eq!(event.git_branch, "main");
        assert_eq!(event.git_commit_sha, "abc123");
        assert_eq!(event.status, "failure");
        assert_eq!(event.exit_code, 1);
        assert_eq!(event.started_at_ms, 1_700_000_000_000);
        assert_eq!(event.finished_at_ms, 1_700_000_015_000);
    }

    #[test]
    fn bounds_retained_wire_strings_without_breaking_unicode() {
        assert_eq!(truncate_wire_string("aébc", 3), "aé");
        assert_eq!(
            truncate_wire_string(&"x".repeat(MAX_COMMAND_BYTES + 1), MAX_COMMAND_BYTES).len(),
            MAX_COMMAND_BYTES
        );
    }

    #[test]
    fn maps_bazel_test_result_facts_and_conventional_artifacts() {
        let digest = "a".repeat(64);
        let result = test_result_delivery(
            TestResultContext {
                account_handle: "acme",
                project_handle: "ios",
                invocation_id: "invocation-1",
                target_label: "//app:tests",
                is_ci: true,
                sequence_number: 42,
            },
            &BazelTestResultId {
                label: "//app:tests".into(),
                run: 2,
                shard: 1,
                attempt: 3,
            },
            &BazelTestResult {
                test_action_output: vec![
                    BazelFile {
                        name: "test.xml".into(),
                        uri: Some("bytestream://cache/blobs/report/123".into()),
                        contents: None,
                        path_prefix: Vec::new(),
                        digest: digest.clone(),
                        length: 123,
                    },
                    BazelFile {
                        name: "undeclared_outputs.zip".into(),
                        uri: None,
                        contents: None,
                        path_prefix: Vec::new(),
                        digest: "b".repeat(64),
                        length: 456,
                    },
                ],
                test_attempt_duration_millis: 10,
                cached_locally: false,
                status: BazelTestStatus::Flaky as i32,
                test_attempt_start_millis_epoch: 1_700_000_000_000,
                execution_info: Some(BazelTestExecutionInfo {
                    strategy: "remote".into(),
                    cached_remotely: true,
                    exit_code: 0,
                }),
                test_attempt_start: None,
                test_attempt_duration: Some(ProtoDuration {
                    seconds: 1,
                    nanos: 250_000_000,
                }),
            },
        );

        assert_eq!(result.status, "flaky");
        assert_eq!(result.duration_ms, 1_250);
        assert_eq!(result.started_at_ms, 1_700_000_000_000);
        assert!(result.cached);
        assert!(result.is_ci);
        assert_eq!(result.sequence_number, 42);
        assert_eq!(result.artifacts.len(), 1);
        assert_eq!(result.artifacts[0].digest, digest);
        assert_eq!(
            result.artifacts[0].artifact_kind,
            BazelTestArtifactKind::Junit
        );
    }

    #[test]
    fn maps_bazel_test_summary_facts() {
        let summary = test_summary_delivery(
            "acme",
            "ios",
            "invocation-1",
            "//app:tests",
            &BazelTestSummary {
                total_run_count: 3,
                overall_status: BazelTestStatus::Flaky as i32,
                total_num_cached: 1,
                first_start_time_millis: 1_700_000_000_000,
                last_stop_time_millis: 1_700_000_004_000,
                total_run_duration_millis: 25,
                total_run_duration: Some(ProtoDuration {
                    seconds: 3,
                    nanos: 500_000_000,
                }),
                first_start_time: None,
                last_stop_time: None,
            },
        );

        assert_eq!(summary.target_label, "//app:tests");
        assert_eq!(summary.status, "flaky");
        assert_eq!(summary.total_run_count, 3);
        assert_eq!(summary.total_num_cached, 1);
        assert_eq!(summary.duration_ms, 3_500);
        assert_eq!(summary.started_at_ms, 1_700_000_000_000);
        assert_eq!(summary.finished_at_ms, 1_700_000_004_000);
    }

    #[test]
    fn applies_build_metadata_without_erasing_prior_values() {
        let mut invocation = InvocationStart {
            account_handle: "acme".into(),
            project_handle: "ios".into(),
            invocation_id: "invocation-1".into(),
            command: "test".into(),
            target_patterns: Vec::new(),
            git_branch: String::new(),
            git_commit_sha: String::new(),
            is_ci: false,
            started_at_ms: 0,
            inserted_at: Instant::now(),
        };
        apply_metadata(
            &mut invocation,
            &HashMap::from([
                ("ROLE".into(), "CI".into()),
                ("BUILD_SCM_BRANCH".into(), "refs/heads/main".into()),
                ("BUILD_SCM_REVISION".into(), "abc123".into()),
            ]),
        );
        apply_metadata(&mut invocation, &HashMap::new());

        assert!(invocation.is_ci);
        assert_eq!(invocation.git_branch, "main");
        assert_eq!(invocation.git_commit_sha, "abc123");
    }

    fn ordered_bazel_event(invocation_id: &str, event: BazelBuildEvent) -> OrderedBuildEvent {
        OrderedBuildEvent {
            stream_id: Some(proto::StreamId {
                build_id: "build-1".into(),
                invocation_id: invocation_id.into(),
                component: 3,
            }),
            sequence_number: 1,
            event: Some(proto::BuildEvent {
                event_time: None,
                event: Some(BuildEventServiceEvent::BazelEvent(prost_types::Any {
                    type_url: BAZEL_BUILD_EVENT_TYPE_URL.into(),
                    value: event.encode_to_vec(),
                })),
            }),
        }
    }
}
