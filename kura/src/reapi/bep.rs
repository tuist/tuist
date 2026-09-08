use std::{
    collections::{HashMap, VecDeque},
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
    analytics::{BazelInvocationAnalyticsEvent, BazelInvocationLogAnalyticsEvent},
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
const MAX_ACTION_SPANS: usize = 32;
const MAX_ACTION_DESCRIPTION_BYTES: usize = 256;
const MAX_CRITICAL_PATH_ACTIONS: usize = 32;
const MAX_CRITICAL_PATH_LOG_BYTES: usize = 128 * 1_024;
const MAX_INVOCATION_LOG_ENTRIES: usize = 32;
const MAX_INVOCATION_LOG_BYTES: usize = 32 * 1_024;
const MAX_INVOCATION_LOG_CHUNK_BYTES: usize = 2 * 1_024;
const MAX_BUILD_EVENT_MESSAGE_BYTES: usize = 2 * 1_024 * 1_024;

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
    bazel_version: String,
    cpu_time_ms: u64,
    actions_created: u64,
    actions_executed: u64,
    targets_configured: u64,
    packages_loaded: u64,
    first_action_started_at_ms: Option<u64>,
    action_spans: Vec<ActionSpan>,
    critical_path_duration_ms: u64,
    critical_path_actions: Vec<CriticalPathAction>,
    logs: VecDeque<InvocationLog>,
    log_bytes: usize,
    completion: Option<InvocationCompletion>,
    started_at_ms: u64,
    inserted_at: Instant,
}

#[derive(Clone, Debug)]
struct ActionSpan {
    started_at_ms: u64,
    finished_at_ms: u64,
    duration_ms: u64,
    description: String,
}

#[derive(Clone, Debug)]
struct CriticalPathAction {
    description: String,
    duration_ms: u64,
}

#[derive(Clone, Debug)]
struct InvocationLog {
    sequence_number: u64,
    stream: &'static str,
    message: String,
    observed_at_ms: u64,
}

#[derive(Clone, Debug)]
struct InvocationCompletion {
    status: &'static str,
    exit_code: Option<i32>,
    finished_at_ms: u64,
}

struct BuildTimeline {
    duration_ms: u64,
    lanes: Vec<String>,
    span_lanes: Vec<u8>,
    span_start_ms: Vec<u64>,
    span_durations_ms: Vec<u64>,
    span_categories: Vec<String>,
    span_descriptions: Vec<String>,
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
    #[prost(message, optional, tag = "3")]
    progress: Option<BazelProgress>,
    #[prost(message, optional, tag = "5")]
    started: Option<BazelBuildStarted>,
    #[prost(message, optional, tag = "7")]
    action: Option<BazelActionExecuted>,
    #[prost(message, optional, tag = "9")]
    test_summary: Option<BazelTestSummary>,
    #[prost(message, optional, tag = "10")]
    test_result: Option<BazelTestResult>,
    #[prost(message, optional, tag = "14")]
    finished: Option<BazelBuildFinished>,
    #[prost(message, optional, tag = "16")]
    workspace_status: Option<BazelWorkspaceStatus>,
    #[prost(message, optional, tag = "23")]
    build_tool_logs: Option<BazelBuildToolLogs>,
    #[prost(message, optional, tag = "24")]
    build_metrics: Option<BazelBuildMetrics>,
    #[prost(message, optional, tag = "26")]
    build_metadata: Option<BazelBuildMetadata>,
}

#[derive(Clone, PartialEq, Message)]
struct BazelBuildEventId {
    #[prost(message, optional, tag = "4")]
    pattern: Option<BazelPatternExpandedId>,
    #[prost(message, optional, tag = "6")]
    action_completed: Option<BazelActionCompletedId>,
    #[prost(message, optional, tag = "7")]
    test_summary: Option<BazelTestSummaryId>,
    #[prost(message, optional, tag = "8")]
    test_result: Option<BazelTestResultId>,
}

#[derive(Clone, PartialEq, Message)]
struct BazelActionCompletedId {
    #[prost(string, tag = "2")]
    label: String,
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
    #[prost(string, tag = "3")]
    build_tool_version: String,
    #[prost(string, tag = "5")]
    command: String,
    #[prost(message, optional, tag = "9")]
    start_time: Option<Timestamp>,
}

#[derive(Clone, PartialEq, Message)]
struct BazelProgress {
    #[prost(string, tag = "1")]
    stdout: String,
    #[prost(string, tag = "2")]
    stderr: String,
}

#[derive(Clone, PartialEq, Message)]
struct BazelActionExecuted {
    #[prost(string, tag = "8")]
    action_type: String,
    #[prost(message, optional, tag = "12")]
    start_time: Option<Timestamp>,
    #[prost(message, optional, tag = "13")]
    end_time: Option<Timestamp>,
}

#[derive(Clone, PartialEq, Message)]
struct BazelBuildToolLogs {
    #[prost(message, repeated, tag = "1")]
    log: Vec<BazelBuildToolLog>,
}

#[derive(Clone, PartialEq, Message)]
struct BazelBuildToolLog {
    #[prost(string, tag = "1")]
    name: String,
    #[prost(bytes = "vec", tag = "3")]
    contents: Vec<u8>,
}

#[derive(Clone, PartialEq, Message)]
struct BazelBuildMetrics {
    #[prost(message, optional, tag = "1")]
    action_summary: Option<BazelActionSummary>,
    #[prost(message, optional, tag = "3")]
    target_metrics: Option<BazelTargetMetrics>,
    #[prost(message, optional, tag = "4")]
    package_metrics: Option<BazelPackageMetrics>,
    #[prost(message, optional, tag = "5")]
    timing_metrics: Option<BazelTimingMetrics>,
}

#[derive(Clone, PartialEq, Message)]
struct BazelActionSummary {
    #[prost(int64, tag = "1")]
    actions_created: i64,
    #[prost(int64, tag = "2")]
    actions_executed: i64,
}

#[derive(Clone, PartialEq, Message)]
struct BazelTargetMetrics {
    #[prost(int64, tag = "2")]
    targets_configured: i64,
}

#[derive(Clone, PartialEq, Message)]
struct BazelPackageMetrics {
    #[prost(int64, tag = "1")]
    packages_loaded: i64,
}

#[derive(Clone, PartialEq, Message)]
struct BazelTimingMetrics {
    #[prost(int64, tag = "1")]
    cpu_time_in_ms: i64,
    #[prost(message, optional, tag = "6")]
    critical_path_time: Option<ProtoDuration>,
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
    .max_decoding_message_size(MAX_BUILD_EVENT_MESSAGE_BYTES)
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
            let mut invocation_id = None;
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
                if let Some(event_invocation_id) = event
                    .stream_id
                    .as_ref()
                    .map(|stream_id| stream_id.invocation_id.as_str())
                    .filter(|invocation_id| !invocation_id.is_empty())
                {
                    let event_invocation_id =
                        truncate_wire_string(event_invocation_id, MAX_INVOCATION_ID_BYTES);
                    if invocation_id
                        .as_ref()
                        .is_some_and(|invocation_id| invocation_id != &event_invocation_id)
                    {
                        let _ = sender
                            .send(Err(Status::invalid_argument(
                                "stream_id.invocation_id must remain constant within a stream",
                            )))
                            .await;
                        break;
                    }
                    invocation_id = Some(event_invocation_id);
                }
                service
                    .process_event(&account_handle, &project_handle, event)
                    .await;

                if sender.send(Ok(response)).await.is_err() {
                    break;
                }
            }

            service
                .finalize_finished_invocation(
                    &account_handle,
                    &project_handle,
                    invocation_id.as_deref(),
                )
                .await;
        });

        Ok(Response::new(Box::pin(ReceiverStream::new(receiver))))
    }
}

impl BuildEventService {
    async fn finalize_finished_invocation(
        &self,
        account_handle: &str,
        project_handle: &str,
        invocation_id: Option<&str>,
    ) {
        let Some(invocation_id) = invocation_id else {
            return;
        };
        let completed_invocation = {
            let mut invocations = self.invocations.lock().await;
            let key = invocation_key(account_handle, project_handle, invocation_id);
            if invocations
                .get(&key)
                .is_some_and(|invocation| invocation.completion.is_some())
            {
                invocations.remove(&key)
            } else {
                None
            }
        };

        let Some(mut invocation) = completed_invocation else {
            return;
        };
        let Some(completion) = invocation.completion.take() else {
            return;
        };

        if invocation.command == "test"
            && let Some(delivery) = self.state.bazel_test_artifacts.as_ref()
        {
            delivery
                .enqueue_invocation_finished(BazelTestInvocationFinished {
                    account_handle: invocation.account_handle.clone(),
                    project_handle: invocation.project_handle.clone(),
                    invocation_id: invocation.invocation_id.clone(),
                })
                .await;
        }

        if let Some(analytics) = self.state.analytics.as_ref() {
            analytics.enqueue_bazel_invocation_event(completed_invocation_event(
                invocation,
                completion.status,
                completion.exit_code,
                completion.finished_at_ms,
            ));
        }
    }

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
                bazel_version: truncate_wire_string(&started.build_tool_version, MAX_COMMAND_BYTES),
                cpu_time_ms: 0,
                actions_created: 0,
                actions_executed: 0,
                targets_configured: 0,
                packages_loaded: 0,
                first_action_started_at_ms: None,
                action_spans: Vec::new(),
                critical_path_duration_ms: 0,
                critical_path_actions: Vec::new(),
                logs: VecDeque::new(),
                log_bytes: 0,
                completion: None,
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

        let key = invocation_key(account_handle, project_handle, &invocation_id);

        if let Some(progress) = event.progress {
            if let Some(start) = self.invocations.lock().await.get_mut(&key) {
                let observed_at_ms = ordered_event_timestamp_millis(&ordered_event);
                append_invocation_log(
                    start,
                    ordered_event.sequence_number,
                    "stderr",
                    &progress.stderr,
                    observed_at_ms,
                );
                append_invocation_log(
                    start,
                    ordered_event.sequence_number,
                    "stdout",
                    &progress.stdout,
                    observed_at_ms,
                );
            }
            return;
        }

        if let Some(metrics) = event.build_metrics {
            if let Some(start) = self.invocations.lock().await.get_mut(&key) {
                apply_build_metrics(start, &metrics);
            }
            return;
        }

        if let Some(action) = event.action {
            if let Some(start) = self.invocations.lock().await.get_mut(&key)
                && let Some(action_span) = action_span(event.id.as_ref(), &action)
            {
                start.first_action_started_at_ms = Some(
                    start
                        .first_action_started_at_ms
                        .map_or(action_span.started_at_ms, |first| {
                            first.min(action_span.started_at_ms)
                        }),
                );
                retain_action_span(start, action_span);
            }
            return;
        }

        if let Some(build_tool_logs) = event.build_tool_logs {
            if let Some(start) = self.invocations.lock().await.get_mut(&key)
                && let Some((duration_ms, actions)) = critical_path(&build_tool_logs)
            {
                if start.critical_path_duration_ms == 0 {
                    start.critical_path_duration_ms = duration_ms;
                }
                start.critical_path_actions = actions;
            }
            return;
        }

        if let Some(pattern) = event.id.as_ref().and_then(|id| id.pattern.as_ref()) {
            if let Some(start) = self.invocations.lock().await.get_mut(&key) {
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
            if let Some(start) = self.invocations.lock().await.get_mut(&key) {
                apply_metadata(start, &metadata.metadata);
            }
            return;
        }

        if let Some(workspace_status) = event.workspace_status {
            if let Some(start) = self.invocations.lock().await.get_mut(&key) {
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
                .get(&key)
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
            let exit_code = finished.exit_code.map(|exit_code| exit_code.code);
            let completion = InvocationCompletion {
                status: invocation_status(finished.overall_success, exit_code),
                exit_code,
                finished_at_ms,
            };
            let mut invocations = self.invocations.lock().await;

            if let Some(start) = invocations.get_mut(&key) {
                start.completion = Some(completion);
            } else {
                warn!(
                    account_handle,
                    project_handle,
                    invocation_id,
                    "received a Bazel invocation finish without a local start event"
                );

                let project_invocation_count = invocations
                    .values()
                    .filter(|invocation| {
                        invocation.account_handle == account_handle
                            && invocation.project_handle == project_handle
                    })
                    .count();
                if invocations.len() >= MAX_IN_FLIGHT_INVOCATIONS
                    || project_invocation_count >= MAX_IN_FLIGHT_INVOCATIONS_PER_PROJECT
                {
                    return;
                }

                invocations.insert(
                    key,
                    InvocationStart {
                        account_handle: account_handle.to_owned(),
                        project_handle: project_handle.to_owned(),
                        invocation_id: invocation_id.clone(),
                        command: "bazel".into(),
                        target_patterns: Vec::new(),
                        git_branch: String::new(),
                        git_commit_sha: String::new(),
                        is_ci: false,
                        bazel_version: String::new(),
                        cpu_time_ms: 0,
                        actions_created: 0,
                        actions_executed: 0,
                        targets_configured: 0,
                        packages_loaded: 0,
                        first_action_started_at_ms: None,
                        action_spans: Vec::new(),
                        critical_path_duration_ms: 0,
                        critical_path_actions: Vec::new(),
                        logs: VecDeque::new(),
                        log_bytes: 0,
                        completion: Some(completion),
                        started_at_ms: finished_at_ms,
                        inserted_at: Instant::now(),
                    },
                );
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
            let (digest, size) = bazel_file_digest_and_size(output)?;
            if size == 0 || size > MAX_BAZEL_TEST_ARTIFACT_BYTES || !valid_sha256_digest(&digest) {
                return None;
            }

            Some(BazelTestArtifact {
                artifact_kind,
                digest,
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

fn bazel_file_digest_and_size(file: &BazelFile) -> Option<(String, u64)> {
    if !file.digest.is_empty() {
        return Some((file.digest.clone(), u64::try_from(file.length).ok()?));
    }

    let uri = file.uri.as_deref()?;
    let url = reqwest::Url::parse(uri).ok()?;
    if url.scheme() != "bytestream" {
        return None;
    }

    let segments = url.path_segments()?.collect::<Vec<_>>();
    let blobs_index = segments.iter().rposition(|segment| *segment == "blobs")?;
    if segments.len() != blobs_index + 3 {
        return None;
    }

    let digest = segments[blobs_index + 1];
    let size = segments[blobs_index + 2].parse::<u64>().ok()?;
    Some((digest.to_owned(), size))
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

fn apply_build_metrics(invocation: &mut InvocationStart, metrics: &BazelBuildMetrics) {
    if let Some(action_summary) = metrics.action_summary.as_ref() {
        invocation.actions_created = non_negative_u64(action_summary.actions_created);
        invocation.actions_executed = non_negative_u64(action_summary.actions_executed);
    }
    if let Some(target_metrics) = metrics.target_metrics.as_ref() {
        invocation.targets_configured = non_negative_u64(target_metrics.targets_configured);
    }
    if let Some(package_metrics) = metrics.package_metrics.as_ref() {
        invocation.packages_loaded = non_negative_u64(package_metrics.packages_loaded);
    }
    if let Some(timing_metrics) = metrics.timing_metrics.as_ref() {
        invocation.cpu_time_ms = non_negative_u64(timing_metrics.cpu_time_in_ms);
        if let Some(critical_path_time) = timing_metrics.critical_path_time.as_ref() {
            invocation.critical_path_duration_ms =
                proto_duration_millis(Some(critical_path_time), 0);
        }
    }
}

fn non_negative_u64(value: i64) -> u64 {
    u64::try_from(value).unwrap_or_default()
}

fn action_span(
    event_id: Option<&BazelBuildEventId>,
    action: &BazelActionExecuted,
) -> Option<ActionSpan> {
    let started_at_ms = strict_timestamp_millis(action.start_time.as_ref()?)?;
    let finished_at_ms = strict_timestamp_millis(action.end_time.as_ref()?)?;
    if finished_at_ms < started_at_ms {
        return None;
    }

    let target_label = event_id
        .and_then(|id| id.action_completed.as_ref())
        .map(|id| id.label.as_str())
        .unwrap_or_default();
    let description = [action.action_type.as_str(), target_label]
        .into_iter()
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>()
        .join(" ");
    if description.is_empty() {
        return None;
    }

    Some(ActionSpan {
        started_at_ms,
        finished_at_ms,
        duration_ms: finished_at_ms.saturating_sub(started_at_ms).max(1),
        description: truncate_wire_string(&description, MAX_ACTION_DESCRIPTION_BYTES),
    })
}

fn retain_action_span(invocation: &mut InvocationStart, span: ActionSpan) {
    if invocation.action_spans.len() < MAX_ACTION_SPANS {
        invocation.action_spans.push(span);
        return;
    }

    let Some((shortest_index, shortest)) = invocation
        .action_spans
        .iter()
        .enumerate()
        .min_by_key(|(_, retained)| retained.duration_ms)
    else {
        return;
    };
    if span.duration_ms > shortest.duration_ms {
        invocation.action_spans[shortest_index] = span;
    }
}

fn append_invocation_log(
    invocation: &mut InvocationStart,
    ordered_sequence_number: i64,
    stream: &'static str,
    message: &str,
    observed_at_ms: u64,
) {
    if message.is_empty() {
        return;
    }

    let message = truncate_wire_string_tail(message, MAX_INVOCATION_LOG_CHUNK_BYTES);
    let stream_offset = u64::from(stream == "stdout");
    let sequence_number = u64::try_from(ordered_sequence_number)
        .unwrap_or_default()
        .saturating_mul(2)
        .saturating_add(stream_offset);

    while invocation.logs.len() >= MAX_INVOCATION_LOG_ENTRIES
        || invocation.log_bytes.saturating_add(message.len()) > MAX_INVOCATION_LOG_BYTES
    {
        let Some(removed) = invocation.logs.pop_front() else {
            break;
        };
        invocation.log_bytes = invocation.log_bytes.saturating_sub(removed.message.len());
    }

    invocation.log_bytes = invocation.log_bytes.saturating_add(message.len());
    invocation.logs.push_back(InvocationLog {
        sequence_number,
        stream,
        message,
        observed_at_ms,
    });
}

fn critical_path(logs: &BazelBuildToolLogs) -> Option<(u64, Vec<CriticalPathAction>)> {
    let contents = logs
        .log
        .iter()
        .find(|log| log.name.eq_ignore_ascii_case("critical path"))
        .map(|log| log.contents.as_slice())?;
    if contents.len() > MAX_CRITICAL_PATH_LOG_BYTES {
        return None;
    }

    let contents = std::str::from_utf8(contents).ok()?;
    let duration_ms = contents
        .split("Critical Path:")
        .nth(1)
        .and_then(|suffix| suffix.split_whitespace().next())
        .and_then(duration_token_millis)
        .unwrap_or_default();
    let actions = contents
        .lines()
        .filter_map(|line| {
            let mut parts = line.trim().splitn(2, char::is_whitespace);
            let duration_ms = duration_token_millis(parts.next()?)?;
            let description = critical_path_action_description(parts.next()?.trim());
            if description.is_empty() {
                return None;
            }

            Some(CriticalPathAction {
                description: truncate_wire_string(description, MAX_ACTION_DESCRIPTION_BYTES),
                duration_ms,
            })
        })
        .take(MAX_CRITICAL_PATH_ACTIONS)
        .collect::<Vec<_>>();

    if duration_ms == 0 && actions.is_empty() {
        None
    } else {
        Some((duration_ms, actions))
    }
}

fn duration_token_millis(token: &str) -> Option<u64> {
    let token = token.trim_end_matches(',');
    let (value, multiplier) = if let Some(value) = token.strip_suffix("ms") {
        (value, 1.0)
    } else if let Some(value) = token.strip_suffix('s') {
        (value, 1_000.0)
    } else {
        return None;
    };
    let value = value.parse::<f64>().ok()?;
    if !value.is_finite() || value < 0.0 || value * multiplier > u64::MAX as f64 {
        return None;
    }

    Some((value * multiplier).round() as u64)
}

fn critical_path_action_description(description: &str) -> &str {
    let has_spawn_metrics = ["Remote (", "Local (", "Worker (", "Other ("]
        .iter()
        .any(|prefix| description.starts_with(prefix));
    if has_spawn_metrics {
        description
            .split_once("] ")
            .map(|(_, description)| description)
            .unwrap_or_default()
    } else {
        description
    }
}

fn build_timeline(invocation: &InvocationStart, finished_at_ms: u64) -> BuildTimeline {
    let duration_ms = finished_at_ms.saturating_sub(invocation.started_at_ms);
    let mut spans = invocation
        .action_spans
        .iter()
        .filter_map(|span| {
            let started_at_ms = span.started_at_ms.max(invocation.started_at_ms);
            let finished_at_ms = span.finished_at_ms.min(finished_at_ms);
            (finished_at_ms >= started_at_ms).then(|| ActionSpan {
                started_at_ms,
                finished_at_ms,
                duration_ms: finished_at_ms.saturating_sub(started_at_ms).max(1),
                description: span.description.clone(),
            })
        })
        .collect::<Vec<_>>();
    spans.sort_by_key(|span| (span.started_at_ms, span.finished_at_ms));

    let mut lane_ends = Vec::<u64>::new();
    let mut assigned = Vec::<(u8, &'static str, ActionSpan)>::with_capacity(spans.len() + 1);
    for span in spans {
        let lane = lane_ends
            .iter()
            .position(|end| *end <= span.started_at_ms)
            .unwrap_or(lane_ends.len());
        if lane == lane_ends.len() {
            lane_ends.push(span.finished_at_ms);
        } else {
            lane_ends[lane] = span.finished_at_ms;
        }
        assigned.push((u8::try_from(lane).unwrap_or(u8::MAX), "execution", span));
    }

    let setup_finished_at_ms = invocation
        .first_action_started_at_ms
        .unwrap_or(invocation.started_at_ms)
        .min(finished_at_ms);
    let has_setup = setup_finished_at_ms > invocation.started_at_ms;
    let lane_offset = u8::from(has_setup);
    if has_setup {
        assigned.insert(
            0,
            (
                0,
                "analysis",
                ActionSpan {
                    started_at_ms: invocation.started_at_ms,
                    finished_at_ms: setup_finished_at_ms,
                    duration_ms: setup_finished_at_ms.saturating_sub(invocation.started_at_ms),
                    description: "Loading and analysis".into(),
                },
            ),
        );
    }

    let mut lanes = Vec::with_capacity(lane_ends.len() + usize::from(has_setup));
    if has_setup {
        lanes.push("Loading and analysis".into());
    }
    lanes.extend((1..=lane_ends.len()).map(|lane| format!("Execution lane {lane}")));

    BuildTimeline {
        duration_ms,
        lanes,
        span_lanes: assigned
            .iter()
            .map(|(lane, category, _)| {
                if *category == "analysis" {
                    *lane
                } else {
                    lane.saturating_add(lane_offset)
                }
            })
            .collect(),
        span_start_ms: assigned
            .iter()
            .map(|(_, _, span)| span.started_at_ms.saturating_sub(invocation.started_at_ms))
            .collect(),
        span_durations_ms: assigned
            .iter()
            .map(|(_, _, span)| span.duration_ms)
            .collect(),
        span_categories: assigned
            .iter()
            .map(|(_, category, _)| (*category).into())
            .collect(),
        span_descriptions: assigned
            .into_iter()
            .map(|(_, _, span)| span.description)
            .collect(),
    }
}

fn strict_timestamp_millis(timestamp: &Timestamp) -> Option<u64> {
    if timestamp.seconds < 0 || !(0..1_000_000_000).contains(&timestamp.nanos) {
        return None;
    }

    Some(
        (timestamp.seconds as u64)
            .saturating_mul(1_000)
            .saturating_add(timestamp.nanos as u64 / 1_000_000),
    )
}

fn ordered_event_timestamp_millis(event: &OrderedBuildEvent) -> u64 {
    event
        .event
        .as_ref()
        .and_then(|event| event.event_time.as_ref())
        .and_then(strict_timestamp_millis)
        .unwrap_or_else(now_millis)
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
    let timeline = build_timeline(&start, finished_at_ms);

    BazelInvocationAnalyticsEvent {
        account_handle: start.account_handle,
        project_handle: start.project_handle,
        invocation_id: start.invocation_id,
        command: start.command,
        target_patterns: start.target_patterns,
        git_branch: start.git_branch,
        git_commit_sha: start.git_commit_sha,
        is_ci: start.is_ci,
        bazel_version: start.bazel_version,
        cpu_time_ms: start.cpu_time_ms,
        actions_created: start.actions_created,
        actions_executed: start.actions_executed,
        targets_configured: start.targets_configured,
        packages_loaded: start.packages_loaded,
        build_timeline_duration_ms: timeline.duration_ms,
        build_timeline_lanes: timeline.lanes,
        build_timeline_span_lanes: timeline.span_lanes,
        build_timeline_span_start_ms: timeline.span_start_ms,
        build_timeline_span_durations_ms: timeline.span_durations_ms,
        build_timeline_span_categories: timeline.span_categories,
        build_timeline_span_descriptions: timeline.span_descriptions,
        critical_path_duration_ms: start.critical_path_duration_ms,
        critical_path_action_descriptions: start
            .critical_path_actions
            .iter()
            .map(|action| action.description.clone())
            .collect(),
        critical_path_action_durations_ms: start
            .critical_path_actions
            .iter()
            .map(|action| action.duration_ms)
            .collect(),
        logs: start
            .logs
            .into_iter()
            .map(|log| BazelInvocationLogAnalyticsEvent {
                sequence_number: log.sequence_number,
                stream: log.stream,
                message: log.message,
                observed_at_ms: log.observed_at_ms,
            })
            .collect(),
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

fn truncate_wire_string_tail(value: &str, max_bytes: usize) -> String {
    if value.len() <= max_bytes {
        return value.to_owned();
    }

    let mut start = value.len().saturating_sub(max_bytes);
    while !value.is_char_boundary(start) {
        start = start.saturating_add(1);
    }
    value[start..].to_owned()
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

    #[tokio::test]
    async fn accepts_generated_bazel_cjk_output_chunks_over_the_wire() {
        let context = test_context(|_| {}).await;
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
            .await
            .expect("test listener should bind");
        let address = listener
            .local_addr()
            .expect("listener should have an address");
        let (shutdown_sender, shutdown_receiver) = tokio::sync::oneshot::channel();
        let server_task = tokio::spawn(async move {
            tonic::transport::Server::builder()
                .add_service(server(context.state))
                .serve_with_incoming_shutdown(
                    tokio_stream::wrappers::TcpListenerStream::new(listener),
                    async {
                        let _ = shutdown_receiver.await;
                    },
                )
                .await
        });

        let mut client = proto::publish_build_event_client::PublishBuildEventClient::connect(
            format!("http://{address}"),
        )
        .await
        .expect("build event client should connect");
        let output = "界".repeat(262_144);
        let events = [
            BazelBuildEvent {
                id: None,
                progress: None,
                started: Some(BazelBuildStarted {
                    uuid: "started-uuid".into(),
                    start_time_millis: 1_700_000_000_000,
                    build_tool_version: "9.1.0".into(),
                    command: "build".into(),
                    start_time: None,
                }),
                action: None,
                test_summary: None,
                test_result: None,
                finished: None,
                workspace_status: None,
                build_tool_logs: None,
                build_metrics: None,
                build_metadata: None,
            },
            BazelBuildEvent {
                id: None,
                progress: Some(BazelProgress {
                    stdout: output,
                    stderr: String::new(),
                }),
                started: None,
                action: None,
                test_summary: None,
                test_result: None,
                finished: None,
                workspace_status: None,
                build_tool_logs: None,
                build_metrics: None,
                build_metadata: None,
            },
            BazelBuildEvent {
                id: None,
                progress: None,
                started: None,
                action: None,
                test_summary: None,
                test_result: None,
                finished: Some(BazelBuildFinished {
                    overall_success: true,
                    finish_time_millis: 1_700_000_001_000,
                    exit_code: Some(BazelExitCode {
                        name: "SUCCESS".into(),
                        code: 0,
                    }),
                    finish_time: None,
                }),
                workspace_status: None,
                build_tool_logs: None,
                build_metrics: None,
                build_metadata: None,
            },
        ]
        .into_iter()
        .enumerate()
        .map(|(index, event)| PublishBuildToolEventStreamRequest {
            ordered_build_event: Some(OrderedBuildEvent {
                stream_id: Some(proto::StreamId {
                    build_id: "build-1".into(),
                    invocation_id: "invocation-1".into(),
                    component: 3,
                }),
                sequence_number: (index + 1) as i64,
                event: Some(proto::BuildEvent {
                    event_time: None,
                    event: Some(BuildEventServiceEvent::BazelEvent(prost_types::Any {
                        type_url: BAZEL_BUILD_EVENT_TYPE_URL.into(),
                        value: event.encode_to_vec(),
                    })),
                }),
            }),
            project_id: String::new(),
        })
        .collect::<Vec<_>>();
        assert!(events[1].encoded_len() <= MAX_BUILD_EVENT_MESSAGE_BYTES);

        let mut request = Request::new(tokio_stream::iter(events));
        request
            .metadata_mut()
            .insert(PROJECT_HANDLE_HEADER, "ios".parse().unwrap());
        let mut responses = client
            .publish_build_tool_event_stream(request)
            .await
            .expect("bounded UTF-8 output should be accepted")
            .into_inner();

        for expected_sequence_number in 1..=3 {
            let response = responses
                .message()
                .await
                .expect("response stream should remain valid")
                .expect("each event should be acknowledged");
            assert_eq!(response.sequence_number, expected_sequence_number);
        }
        assert!(
            responses
                .message()
                .await
                .expect("response stream should close cleanly")
                .is_none()
        );

        drop(responses);
        drop(client);
        let _ = shutdown_sender.send(());
        server_task
            .await
            .expect("server task should finish")
            .expect("server should shut down cleanly");
    }

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
                        progress: None,
                        started: Some(BazelBuildStarted {
                            uuid: "started-uuid".into(),
                            start_time_millis: 1_700_000_000_000,
                            build_tool_version: "9.1.0".into(),
                            command: "test".into(),
                            start_time: None,
                        }),
                        action: None,
                        test_summary: None,
                        test_result: None,
                        finished: None,
                        workspace_status: None,
                        build_tool_logs: None,
                        build_metrics: None,
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
                        progress: None,
                        started: None,
                        action: None,
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
                        build_tool_logs: None,
                        build_metrics: None,
                        build_metadata: None,
                    },
                ),
            )
            .await;

        service
            .process_event(
                "acme",
                "ios",
                ordered_bazel_event(
                    "invocation-1",
                    BazelBuildEvent {
                        id: None,
                        progress: None,
                        started: None,
                        action: None,
                        test_summary: None,
                        test_result: None,
                        finished: None,
                        workspace_status: None,
                        build_tool_logs: None,
                        build_metrics: Some(BazelBuildMetrics {
                            action_summary: Some(BazelActionSummary {
                                actions_created: 11,
                                actions_executed: 10,
                            }),
                            target_metrics: None,
                            package_metrics: None,
                            timing_metrics: None,
                        }),
                        build_metadata: None,
                    },
                ),
            )
            .await;
        service
            .process_event(
                "acme",
                "ios",
                ordered_bazel_event(
                    "invocation-1",
                    BazelBuildEvent {
                        id: None,
                        progress: None,
                        started: None,
                        action: None,
                        test_summary: None,
                        test_result: None,
                        finished: None,
                        workspace_status: None,
                        build_tool_logs: Some(BazelBuildToolLogs {
                            log: vec![BazelBuildToolLog {
                                name: "critical path".into(),
                                contents: b"Critical Path: 1s\n  1s Link //app:app\n".to_vec(),
                            }],
                        }),
                        build_metrics: None,
                        build_metadata: None,
                    },
                ),
            )
            .await;

        let starts = service.invocations.lock().await;
        let start = starts
            .get("acme:ios:invocation-1")
            .expect("a finished invocation should remain until its stream closes");
        assert_eq!(start.actions_created, 11);
        assert_eq!(start.actions_executed, 10);
        assert_eq!(start.critical_path_duration_ms, 1_000);
        drop(starts);

        service
            .finalize_finished_invocation("acme", "ios", Some("invocation-1"))
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
                bazel_version: "9.1.0".into(),
                cpu_time_ms: 1_250,
                actions_created: 11,
                actions_executed: 10,
                targets_configured: 4,
                packages_loaded: 2,
                first_action_started_at_ms: None,
                action_spans: Vec::new(),
                critical_path_duration_ms: 0,
                critical_path_actions: Vec::new(),
                logs: VecDeque::new(),
                log_bytes: 0,
                completion: None,
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
        assert_eq!(event.bazel_version, "9.1.0");
        assert_eq!(event.cpu_time_ms, 1_250);
        assert_eq!(event.actions_created, 11);
        assert_eq!(event.actions_executed, 10);
        assert_eq!(event.targets_configured, 4);
        assert_eq!(event.packages_loaded, 2);
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
        assert_eq!(truncate_wire_string_tail("abécd", 4), "écd");
    }

    #[test]
    fn maps_build_metrics_without_accepting_negative_counts() {
        let mut invocation = test_invocation_start();
        apply_build_metrics(
            &mut invocation,
            &BazelBuildMetrics {
                action_summary: Some(BazelActionSummary {
                    actions_created: 11,
                    actions_executed: -1,
                }),
                target_metrics: Some(BazelTargetMetrics {
                    targets_configured: 4,
                }),
                package_metrics: Some(BazelPackageMetrics { packages_loaded: 2 }),
                timing_metrics: Some(BazelTimingMetrics {
                    cpu_time_in_ms: 1_250,
                    critical_path_time: Some(ProtoDuration {
                        seconds: 2,
                        nanos: 500_000_000,
                    }),
                }),
            },
        );

        assert_eq!(invocation.actions_created, 11);
        assert_eq!(invocation.actions_executed, 0);
        assert_eq!(invocation.targets_configured, 4);
        assert_eq!(invocation.packages_loaded, 2);
        assert_eq!(invocation.cpu_time_ms, 1_250);
        assert_eq!(invocation.critical_path_duration_ms, 2_500);
    }

    #[test]
    fn retains_only_the_longest_bounded_action_spans() {
        let mut invocation = test_invocation_start();

        for duration_ms in 1..=MAX_ACTION_SPANS as u64 + 1 {
            retain_action_span(
                &mut invocation,
                ActionSpan {
                    started_at_ms: 1_700_000_000_000,
                    finished_at_ms: 1_700_000_000_000 + duration_ms,
                    duration_ms,
                    description: format!("action {duration_ms}"),
                },
            );
        }

        assert_eq!(invocation.action_spans.len(), MAX_ACTION_SPANS);
        assert!(
            invocation
                .action_spans
                .iter()
                .all(|span| span.duration_ms > 1)
        );
        assert!(
            invocation
                .action_spans
                .iter()
                .any(|span| span.duration_ms == MAX_ACTION_SPANS as u64 + 1)
        );
    }

    #[test]
    fn parses_a_bounded_critical_path_report() {
        let logs = BazelBuildToolLogs {
            log: vec![BazelBuildToolLog {
                name: "critical path".into(),
                contents: b"Critical Path: 1.25s, Remote (80.00% of the time): [queue: 1.00%, setup: 2.00%, process: 77.00%]\n  250ms, Remote (100.00% of the time): [queue: 0.00%, setup: 1.00%, process: 99.00%, input files: 4, input bytes: 512, memory bytes: 1024] Compile //app:one\n  1s Link //app:app\n".to_vec(),
            }],
        };

        let (duration_ms, actions) = critical_path(&logs).expect("critical path should parse");

        assert_eq!(duration_ms, 1_250);
        assert_eq!(actions.len(), 2);
        assert_eq!(actions[0].description, "Compile //app:one");
        assert_eq!(actions[0].duration_ms, 250);
        assert_eq!(actions[1].description, "Link //app:app");
        assert_eq!(actions[1].duration_ms, 1_000);
    }

    #[test]
    fn keeps_a_bounded_tail_of_progress_output() {
        let mut invocation = test_invocation_start();

        for sequence_number in 0..MAX_INVOCATION_LOG_ENTRIES + 8 {
            append_invocation_log(
                &mut invocation,
                sequence_number as i64,
                "stdout",
                &format!("{sequence_number}:{}", "x".repeat(1_100)),
                1_700_000_000_000,
            );
        }

        assert!(invocation.logs.len() <= MAX_INVOCATION_LOG_ENTRIES);
        assert!(invocation.log_bytes <= MAX_INVOCATION_LOG_BYTES);
        assert_eq!(
            invocation.log_bytes,
            invocation
                .logs
                .iter()
                .map(|log| log.message.len())
                .sum::<usize>()
        );
        assert!(
            invocation
                .logs
                .back()
                .is_some_and(|log| log.message.starts_with("39:"))
        );
    }

    #[test]
    fn builds_analysis_and_parallel_execution_lanes() {
        let mut invocation = test_invocation_start();
        invocation.started_at_ms = 1_000;
        invocation.first_action_started_at_ms = Some(1_200);
        invocation.action_spans = vec![
            ActionSpan {
                started_at_ms: 1_200,
                finished_at_ms: 1_500,
                duration_ms: 300,
                description: "Compile //app:one".into(),
            },
            ActionSpan {
                started_at_ms: 1_300,
                finished_at_ms: 1_400,
                duration_ms: 100,
                description: "Compile //app:two".into(),
            },
        ];

        let timeline = build_timeline(&invocation, 1_600);

        assert_eq!(timeline.duration_ms, 600);
        assert_eq!(
            timeline.lanes,
            [
                "Loading and analysis",
                "Execution lane 1",
                "Execution lane 2"
            ]
        );
        assert_eq!(timeline.span_lanes, [0, 1, 2]);
        assert_eq!(timeline.span_start_ms, [0, 200, 300]);
        assert_eq!(timeline.span_durations_ms, [200, 300, 100]);
        assert_eq!(
            timeline.span_categories,
            ["analysis", "execution", "execution"]
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
                        uri: Some(format!("bytestream://cache/ios/blobs/{digest}/123")),
                        contents: None,
                        path_prefix: Vec::new(),
                        digest: String::new(),
                        length: 0,
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
    fn rejects_non_bytestream_and_malformed_test_artifact_uris() {
        for uri in [
            "file:///tmp/test.xml",
            "https://cache/ios/blobs/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/123",
            "bytestream://cache/ios/blobs/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "bytestream://cache/ios/blobs/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/123/trailing",
        ] {
            let result = test_result_delivery(
                TestResultContext {
                    account_handle: "acme",
                    project_handle: "ios",
                    invocation_id: "invocation-1",
                    target_label: "//app:tests",
                    is_ci: false,
                    sequence_number: 1,
                },
                &BazelTestResultId {
                    label: "//app:tests".into(),
                    run: 1,
                    shard: 1,
                    attempt: 1,
                },
                &BazelTestResult {
                    test_action_output: vec![BazelFile {
                        name: "test.xml".into(),
                        uri: Some(uri.into()),
                        contents: None,
                        path_prefix: Vec::new(),
                        digest: String::new(),
                        length: 0,
                    }],
                    test_attempt_duration_millis: 1,
                    cached_locally: false,
                    status: BazelTestStatus::Passed as i32,
                    test_attempt_start_millis_epoch: 1,
                    execution_info: None,
                    test_attempt_start: None,
                    test_attempt_duration: None,
                },
            );

            assert!(result.artifacts.is_empty(), "accepted {uri}");
        }
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
            bazel_version: String::new(),
            cpu_time_ms: 0,
            actions_created: 0,
            actions_executed: 0,
            targets_configured: 0,
            packages_loaded: 0,
            first_action_started_at_ms: None,
            action_spans: Vec::new(),
            critical_path_duration_ms: 0,
            critical_path_actions: Vec::new(),
            logs: VecDeque::new(),
            log_bytes: 0,
            completion: None,
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

    fn test_invocation_start() -> InvocationStart {
        InvocationStart {
            account_handle: "acme".into(),
            project_handle: "ios".into(),
            invocation_id: "invocation-1".into(),
            command: "build".into(),
            target_patterns: Vec::new(),
            git_branch: String::new(),
            git_commit_sha: String::new(),
            is_ci: false,
            bazel_version: "9.1.0".into(),
            cpu_time_ms: 0,
            actions_created: 0,
            actions_executed: 0,
            targets_configured: 0,
            packages_loaded: 0,
            first_action_started_at_ms: None,
            action_spans: Vec::new(),
            critical_path_duration_ms: 0,
            critical_path_actions: Vec::new(),
            logs: VecDeque::new(),
            log_bytes: 0,
            completion: None,
            started_at_ms: 1_700_000_000_000,
            inserted_at: Instant::now(),
        }
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
