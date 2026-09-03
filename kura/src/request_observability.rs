use std::{
    future::Future,
    hash::{DefaultHasher, Hash, Hasher},
    sync::{
        Arc, OnceLock,
        atomic::{AtomicU64, Ordering},
    },
    time::{Duration, Instant},
};

use tracing::{Span, info, warn};
use uuid::Uuid;

pub const REQUEST_ID_HEADER: &str = "x-request-id";
const MAX_REQUEST_ID_BYTES: usize = 128;

tokio::task_local! {
    static CURRENT_REQUEST: Arc<RequestContext>;
}

static SLOW_REQUEST_LOG_LIMITER: AtomicLogLimiter = AtomicLogLimiter::new();
static FAILED_REQUEST_LOG_LIMITER: AtomicLogLimiter = AtomicLogLimiter::new();

pub struct RequestContext {
    request_id: String,
    method: String,
    route: String,
    started_at: Instant,
    sampled: bool,
    slow_request_threshold: Duration,
    warning_log_interval: Duration,
    request_span: Span,
}

#[derive(Clone, Copy)]
pub struct RequestLogPolicy {
    pub sample_rate: f64,
    pub slow_request_threshold: Duration,
    pub warning_log_interval: Duration,
}

impl RequestContext {
    pub fn new(
        started_at: Instant,
        request_id: String,
        method: String,
        route: String,
        policy: RequestLogPolicy,
        request_span: Span,
    ) -> Arc<Self> {
        let sampled = request_is_sampled(&request_id, policy.sample_rate);
        Arc::new(Self {
            request_id,
            method,
            route,
            started_at,
            sampled,
            slow_request_threshold: policy.slow_request_threshold,
            warning_log_interval: policy.warning_log_interval,
            request_span,
        })
    }

    pub fn request_id(&self) -> &str {
        &self.request_id
    }

    pub fn started_at(&self) -> Instant {
        self.started_at
    }

    pub fn request_span(&self) -> &Span {
        &self.request_span
    }
}

pub struct RequestCompletion<'a> {
    pub status: u16,
    pub response_bytes: u64,
    pub time_to_first_byte: Duration,
    pub total_duration: Duration,
    pub serving_path: &'a str,
    pub result: &'a str,
    pub error: Option<&'a str>,
}

pub fn request_id(candidate: Option<&str>) -> String {
    candidate
        .filter(|value| valid_request_id(value))
        .map(ToOwned::to_owned)
        .unwrap_or_else(|| Uuid::now_v7().to_string())
}

pub async fn scope_request<F>(context: Arc<RequestContext>, future: F) -> F::Output
where
    F: Future,
{
    CURRENT_REQUEST.scope(context, future).await
}

pub fn current_request() -> Option<Arc<RequestContext>> {
    CURRENT_REQUEST.try_with(Arc::clone).ok()
}

pub fn log_request_completion(context: &RequestContext, completion: RequestCompletion<'_>) {
    let slow = !context.slow_request_threshold.is_zero()
        && completion.total_duration >= context.slow_request_threshold;
    let failed = completion.result != "ok" || completion.status >= 500;
    let limiter = if failed {
        Some(&FAILED_REQUEST_LOG_LIMITER)
    } else if slow {
        Some(&SLOW_REQUEST_LOG_LIMITER)
    } else {
        None
    };
    let warning_permit = limiter.and_then(|limiter| limiter.acquire(context.warning_log_interval));

    if warning_permit.is_none() && !context.sampled {
        return;
    }

    let warning_suppressed = limiter.is_some() && warning_permit.is_none();
    let suppressed_count = warning_permit.unwrap_or(0);
    let time_to_first_byte_ms = completion.time_to_first_byte.as_secs_f64() * 1_000.0;
    let duration_ms = completion.total_duration.as_secs_f64() * 1_000.0;

    if limiter.is_some() && !warning_suppressed {
        warn!(
            parent: context.request_span(),
            event.name = "kura.http.request.completed",
            http.request.id = %context.request_id,
            http.request.method = %context.method,
            http.route = %context.route,
            http.response.status_code = completion.status,
            http.response.body.size = completion.response_bytes,
            kura.response.serving_path = completion.serving_path,
            kura.response.result = completion.result,
            error = completion.error.unwrap_or(""),
            kura.request.time_to_first_byte_ms = time_to_first_byte_ms,
            kura.request.duration_ms = duration_ms,
            kura.log.sampled = context.sampled,
            kura.log.warning_suppressed = false,
            kura.log.suppressed_count = suppressed_count,
            "request completed"
        );
    } else {
        info!(
            parent: context.request_span(),
            event.name = "kura.http.request.completed",
            http.request.id = %context.request_id,
            http.request.method = %context.method,
            http.route = %context.route,
            http.response.status_code = completion.status,
            http.response.body.size = completion.response_bytes,
            kura.response.serving_path = completion.serving_path,
            kura.response.result = completion.result,
            error = completion.error.unwrap_or(""),
            kura.request.time_to_first_byte_ms = time_to_first_byte_ms,
            kura.request.duration_ms = duration_ms,
            kura.log.sampled = context.sampled,
            kura.log.warning_suppressed = warning_suppressed,
            kura.log.suppressed_count = 0_u64,
            "request completed"
        );
    }
}

pub struct FailureLogThrottle {
    interval: Duration,
    last_emitted_at: Option<Instant>,
    suppressed: u64,
    consecutive_failures: u64,
}

impl FailureLogThrottle {
    pub fn new(interval: Duration) -> Self {
        Self {
            interval,
            last_emitted_at: None,
            suppressed: 0,
            consecutive_failures: 0,
        }
    }

    pub fn record_failure(&mut self) -> Option<u64> {
        self.consecutive_failures = self.consecutive_failures.saturating_add(1);
        let now = Instant::now();
        if self
            .last_emitted_at
            .is_none_or(|last| self.interval.is_zero() || now.duration_since(last) >= self.interval)
        {
            self.last_emitted_at = Some(now);
            return Some(std::mem::take(&mut self.suppressed));
        }

        self.suppressed = self.suppressed.saturating_add(1);
        None
    }

    pub fn record_success(&mut self) -> Option<(u64, u64)> {
        if self.consecutive_failures == 0 {
            return None;
        }

        let failures = std::mem::take(&mut self.consecutive_failures);
        let suppressed = std::mem::take(&mut self.suppressed);
        self.last_emitted_at = None;
        Some((failures, suppressed))
    }

    pub fn consecutive_failures(&self) -> u64 {
        self.consecutive_failures
    }
}

fn valid_request_id(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= MAX_REQUEST_ID_BYTES
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.' | b':'))
}

fn request_is_sampled(request_id: &str, sample_rate: f64) -> bool {
    if sample_rate <= 0.0 {
        return false;
    }
    if sample_rate >= 1.0 {
        return true;
    }

    let mut hasher = DefaultHasher::new();
    request_id.hash(&mut hasher);
    let ratio = hasher.finish() as f64 / u64::MAX as f64;
    ratio < sample_rate
}

struct AtomicLogLimiter {
    next_allowed_millis: AtomicU64,
    suppressed: AtomicU64,
}

impl AtomicLogLimiter {
    const fn new() -> Self {
        Self {
            next_allowed_millis: AtomicU64::new(0),
            suppressed: AtomicU64::new(0),
        }
    }

    fn acquire(&self, interval: Duration) -> Option<u64> {
        if interval.is_zero() {
            return Some(self.suppressed.swap(0, Ordering::Relaxed));
        }

        let now = monotonic_millis();
        let next = self.next_allowed_millis.load(Ordering::Relaxed);
        if now < next {
            self.suppressed.fetch_add(1, Ordering::Relaxed);
            return None;
        }

        let interval_millis = interval.as_millis().min(u64::MAX as u128) as u64;
        match self.next_allowed_millis.compare_exchange(
            next,
            now.saturating_add(interval_millis),
            Ordering::Relaxed,
            Ordering::Relaxed,
        ) {
            Ok(_) => Some(self.suppressed.swap(0, Ordering::Relaxed)),
            Err(_) => {
                self.suppressed.fetch_add(1, Ordering::Relaxed);
                None
            }
        }
    }
}

fn monotonic_millis() -> u64 {
    static START: OnceLock<Instant> = OnceLock::new();
    START
        .get_or_init(Instant::now)
        .elapsed()
        .as_millis()
        .min(u64::MAX as u128) as u64
}

#[cfg(test)]
mod tests {
    use std::{
        io,
        sync::{Arc, Mutex},
    };

    use serde_json::Value;
    use tracing_subscriber::fmt::MakeWriter;

    use super::*;

    #[derive(Clone, Default)]
    struct CaptureWriter(Arc<Mutex<Vec<u8>>>);

    struct CaptureGuard(Arc<Mutex<Vec<u8>>>);

    impl io::Write for CaptureGuard {
        fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
            self.0
                .lock()
                .expect("capture lock")
                .extend_from_slice(bytes);
            Ok(bytes.len())
        }

        fn flush(&mut self) -> io::Result<()> {
            Ok(())
        }
    }

    impl<'a> MakeWriter<'a> for CaptureWriter {
        type Writer = CaptureGuard;

        fn make_writer(&'a self) -> Self::Writer {
            CaptureGuard(self.0.clone())
        }
    }

    #[test]
    fn request_ids_are_bounded_and_sanitized() {
        assert_eq!(request_id(Some("request-123")), "request-123");
        assert_ne!(request_id(Some("contains spaces")), "contains spaces");
        assert_ne!(request_id(Some(&"a".repeat(129))), "a".repeat(129));
    }

    #[test]
    fn sampling_boundaries_are_deterministic() {
        assert!(!request_is_sampled("request-123", 0.0));
        assert!(request_is_sampled("request-123", 1.0));
        assert_eq!(
            request_is_sampled("request-123", 0.5),
            request_is_sampled("request-123", 0.5)
        );
    }

    #[test]
    fn request_completion_log_has_the_structured_contract() {
        let writer = CaptureWriter::default();
        let subscriber = tracing_subscriber::fmt()
            .json()
            .flatten_event(true)
            .with_ansi(false)
            .with_writer(writer.clone())
            .finish();

        tracing::subscriber::with_default(subscriber, || {
            let request_span = tracing::info_span!("http.request");
            let context = RequestContext::new(
                Instant::now(),
                "request-123".into(),
                "GET".into(),
                "/api/cache/module/{id}".into(),
                RequestLogPolicy {
                    sample_rate: 1.0,
                    slow_request_threshold: Duration::ZERO,
                    warning_log_interval: Duration::from_secs(60),
                },
                request_span,
            );
            log_request_completion(
                &context,
                RequestCompletion {
                    status: 200,
                    response_bytes: 198_148_895,
                    time_to_first_byte: Duration::from_millis(151),
                    total_duration: Duration::from_secs(72),
                    serving_path: "reader",
                    result: "ok",
                    error: None,
                },
            );
        });

        let bytes = writer.0.lock().expect("capture lock").clone();
        let event: Value = serde_json::from_slice(&bytes).expect("structured log event");
        assert_eq!(event["event.name"], "kura.http.request.completed");
        assert_eq!(event["http.request.id"], "request-123");
        assert_eq!(event["http.request.method"], "GET");
        assert_eq!(event["http.route"], "/api/cache/module/{id}");
        assert_eq!(event["http.response.status_code"], 200);
        assert_eq!(event["http.response.body.size"], 198_148_895_u64);
        assert_eq!(event["kura.response.serving_path"], "reader");
        assert_eq!(event["kura.response.result"], "ok");
        assert_eq!(event["error"], "");
        assert_eq!(event["kura.log.sampled"], true);
    }

    #[test]
    fn ordinary_successes_do_not_log_by_default() {
        let writer = CaptureWriter::default();
        let subscriber = tracing_subscriber::fmt()
            .json()
            .flatten_event(true)
            .with_ansi(false)
            .with_writer(writer.clone())
            .finish();

        tracing::subscriber::with_default(subscriber, || {
            let context = RequestContext::new(
                Instant::now(),
                "request-123".into(),
                "GET".into(),
                "/api/cache/module/{id}".into(),
                RequestLogPolicy {
                    sample_rate: 0.0,
                    slow_request_threshold: Duration::from_secs(30),
                    warning_log_interval: Duration::from_secs(60),
                },
                tracing::Span::none(),
            );
            log_request_completion(
                &context,
                RequestCompletion {
                    status: 200,
                    response_bytes: 1024,
                    time_to_first_byte: Duration::from_millis(10),
                    total_duration: Duration::from_millis(20),
                    serving_path: "reader",
                    result: "ok",
                    error: None,
                },
            );
        });

        assert!(writer.0.lock().expect("capture lock").is_empty());
    }

    #[test]
    fn slow_request_contract_uses_the_warning_level() {
        let writer = CaptureWriter::default();
        let subscriber = tracing_subscriber::fmt()
            .json()
            .flatten_event(true)
            .with_ansi(false)
            .with_writer(writer.clone())
            .finish();

        tracing::subscriber::with_default(subscriber, || {
            let context = RequestContext::new(
                Instant::now(),
                "slow-request-123".into(),
                "GET".into(),
                "/api/cache/module/{id}".into(),
                RequestLogPolicy {
                    sample_rate: 0.0,
                    slow_request_threshold: Duration::from_millis(1),
                    warning_log_interval: Duration::ZERO,
                },
                tracing::Span::none(),
            );
            log_request_completion(
                &context,
                RequestCompletion {
                    status: 200,
                    response_bytes: 1024,
                    time_to_first_byte: Duration::from_millis(1),
                    total_duration: Duration::from_millis(2),
                    serving_path: "reader",
                    result: "ok",
                    error: None,
                },
            );
        });

        let bytes = writer.0.lock().expect("capture lock").clone();
        let event: Value = serde_json::from_slice(&bytes).expect("structured log event");
        assert_eq!(event["level"], "WARN");
        assert_eq!(event["event.name"], "kura.http.request.completed");
        assert_eq!(event["kura.log.sampled"], false);
    }

    #[test]
    fn repeated_failures_are_bounded_and_report_recovery() {
        let mut throttle = FailureLogThrottle::new(Duration::from_secs(60));
        assert_eq!(throttle.record_failure(), Some(0));
        assert_eq!(throttle.record_failure(), None);
        assert_eq!(throttle.record_success(), Some((2, 1)));
        assert_eq!(throttle.record_success(), None);
    }

    #[test]
    fn request_warning_limiter_reports_suppressed_events_without_growing_state() {
        let limiter = AtomicLogLimiter::new();
        assert_eq!(limiter.acquire(Duration::from_secs(60)), Some(0));
        assert_eq!(limiter.acquire(Duration::from_secs(60)), None);
        assert_eq!(limiter.acquire(Duration::ZERO), Some(1));
    }
}
