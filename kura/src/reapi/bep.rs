use std::{
    collections::HashMap,
    pin::Pin,
    sync::Arc,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use futures_util::Stream;
use prost::Message;
use prost_types::Timestamp;
use tokio::sync::{Mutex, mpsc};
use tokio_stream::wrappers::ReceiverStream;
use tonic::{Request, Response, Status, Streaming};
use tracing::warn;

use crate::{analytics::BazelInvocationAnalyticsEvent, state::SharedState};

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
    started_at_ms: u64,
    inserted_at: Instant,
}

#[derive(Clone, PartialEq, Message)]
struct BazelBuildEvent {
    #[prost(message, optional, tag = "5")]
    started: Option<BazelBuildStarted>,
    #[prost(message, optional, tag = "14")]
    finished: Option<BazelBuildFinished>,
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

        if let Some(finished) = event.finished {
            let invocation_id =
                truncate_wire_string(&invocation_id(&ordered_event, ""), MAX_INVOCATION_ID_BYTES);
            if invocation_id.is_empty() {
                return;
            }

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
                    started_at_ms: finished_at_ms,
                    inserted_at: Instant::now(),
                }
            });
            let exit_code = finished.exit_code.map(|exit_code| exit_code.code);
            let status = invocation_status(finished.overall_success, exit_code);

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
                        started: Some(BazelBuildStarted {
                            uuid: "started-uuid".into(),
                            start_time_millis: 1_700_000_000_000,
                            command: "test".into(),
                            start_time: None,
                        }),
                        finished: None,
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
                        started: None,
                        finished: Some(BazelBuildFinished {
                            overall_success: true,
                            finish_time_millis: 1_700_000_015_000,
                            exit_code: Some(BazelExitCode {
                                name: "SUCCESS".into(),
                                code: 0,
                            }),
                            finish_time: None,
                        }),
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
