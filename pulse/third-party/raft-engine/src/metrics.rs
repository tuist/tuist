// Copyright 2021 TiKV Project Authors. Licensed under Apache-2.0.

use std::{
    cell::{RefCell, RefMut},
    ops::AddAssign,
    time::{Duration, Instant},
};

use prometheus::*;
use prometheus_static_metric::*;

use crate::util::InstantExt;

pub struct StopWatch<M: TimeMetric> {
    metric: M,
    start: Instant,
}

impl<M: TimeMetric> StopWatch<M> {
    #[inline]
    pub fn new(metric: M) -> Self {
        Self {
            metric,
            start: Instant::now(),
        }
    }

    #[inline]
    pub fn new_with(metric: M, start: Instant) -> Self {
        Self { metric, start }
    }
}

impl<M: TimeMetric> Drop for StopWatch<M> {
    fn drop(&mut self) {
        self.metric.observe(self.start.saturating_elapsed());
    }
}

/// PerfContext records cumulative performance statistics of operations.
///
/// Raft Engine will update the data in the thread-local PerfContext whenever
/// an opeartion is performed.
#[derive(Debug, Clone, Default)]
pub struct PerfContext {
    /// Time spent encoding and compressing log entries.
    pub log_populating_duration: Duration,

    /// Time spent waiting for the write group to form and get processed.
    pub write_wait_duration: Duration,

    /// Time spent writing the logs to files.
    pub log_write_duration: Duration,

    /// Time spent rotating the active log file.
    pub log_rotate_duration: Duration,

    // Time spent synchronizing logs to the disk.
    pub log_sync_duration: Duration,

    // Time spent applying the appended logs.
    pub apply_duration: Duration,
}

impl AddAssign<&'_ PerfContext> for PerfContext {
    fn add_assign(&mut self, rhs: &PerfContext) {
        self.log_populating_duration += rhs.log_populating_duration;
        self.write_wait_duration += rhs.write_wait_duration;
        self.log_write_duration += rhs.log_write_duration;
        self.log_rotate_duration += rhs.log_rotate_duration;
        self.log_sync_duration += rhs.log_sync_duration;
        self.apply_duration += rhs.apply_duration;
    }
}

thread_local! {
    static TLS_PERF_CONTEXT: RefCell<PerfContext> = RefCell::new(PerfContext::default());
}

/// Gets a copy of the thread-local PerfContext.
pub fn get_perf_context() -> PerfContext {
    TLS_PERF_CONTEXT.with(|c| c.borrow().clone())
}

/// Resets the thread-local PerfContext and takes its old value.
pub fn take_perf_context() -> PerfContext {
    TLS_PERF_CONTEXT.with(|c| c.take())
}

/// Sets the value of the thread-local PerfContext.
pub fn set_perf_context(perf_context: PerfContext) {
    TLS_PERF_CONTEXT.with(|c| *c.borrow_mut() = perf_context);
}

pub(crate) struct PerfContextField<P> {
    projector: P,
}

impl<P> PerfContextField<P>
where
    P: Fn(&mut PerfContext) -> &mut Duration,
{
    pub fn new(projector: P) -> Self {
        PerfContextField { projector }
    }
}

#[macro_export]
macro_rules! perf_context {
    ($field: ident) => {
        $crate::metrics::PerfContextField::new(|perf_context| &mut perf_context.$field)
    };
}

pub trait TimeMetric {
    fn observe(&self, duration: Duration);

    fn observe_since(&self, earlier: Instant) -> Duration {
        let dur = earlier.saturating_elapsed();
        self.observe(dur);
        dur
    }
}

impl<'a> TimeMetric for &'a Histogram {
    fn observe(&self, duration: Duration) {
        Histogram::observe(self, duration.as_secs_f64());
    }
}

impl<P> TimeMetric for PerfContextField<P>
where
    P: Fn(&mut PerfContext) -> &mut Duration,
{
    fn observe(&self, duration: Duration) {
        TLS_PERF_CONTEXT.with(|perf_context| {
            *RefMut::map(perf_context.borrow_mut(), &self.projector) += duration;
        })
    }
}

impl<M1, M2> TimeMetric for (M1, M2)
where
    M1: TimeMetric,
    M2: TimeMetric,
{
    fn observe(&self, duration: Duration) {
        self.0.observe(duration);
        self.1.observe(duration);
    }
}

make_static_metric! {
    pub label_enum LogQueueKind {
        rewrite,
        append,
    }

    pub struct LogQueueHistogramVec: Histogram {
        "type" => LogQueueKind,
    }

    pub struct LogQueueCounterVec: IntCounter {
        "type" => LogQueueKind,
    }

    pub struct LogQueueGaugeVec: IntGauge {
        "type" => LogQueueKind,
    }
}

lazy_static! {
    // Write path.
    pub static ref ENGINE_WRITE_DURATION_HISTOGRAM: Histogram = register_histogram!(
        "raft_engine_write_duration_seconds",
        "Bucketed histogram of Raft Engine write duration",
        exponential_buckets(0.00005, 1.8, 26).unwrap()
    )
    .unwrap();
    pub static ref ENGINE_WRITE_PREPROCESS_DURATION_HISTOGRAM: Histogram = register_histogram!(
        "raft_engine_write_preprocess_duration_seconds",
        "Bucketed histogram of Raft Engine write preprocess duration",
        exponential_buckets(0.00005, 1.8, 26).unwrap()
    )
    .unwrap();
    pub static ref ENGINE_WRITE_LEADER_DURATION_HISTOGRAM: Histogram = register_histogram!(
        "raft_engine_write_leader_duration_seconds",
        "Bucketed histogram of Raft Engine write leader duration",
        exponential_buckets(0.00005, 1.8, 26).unwrap()
    )
    .unwrap();
    pub static ref ENGINE_WRITE_APPLY_DURATION_HISTOGRAM: Histogram = register_histogram!(
        "raft_engine_write_apply_duration_seconds",
        "Bucketed histogram of Raft Engine write apply duration",
        exponential_buckets(0.00005, 1.8, 26).unwrap()
    )
    .unwrap();
    pub static ref ENGINE_WRITE_SIZE_HISTOGRAM: Histogram = register_histogram!(
        "raft_engine_write_size",
        "Bucketed histogram of Raft Engine write size",
        exponential_buckets(256.0, 1.8, 22).unwrap()
    )
    .unwrap();
    pub static ref LOG_ALLOCATE_DURATION_HISTOGRAM: Histogram = register_histogram!(
        "raft_engine_allocate_log_duration_seconds",
        "Bucketed histogram of Raft Engine allocate log duration",
        exponential_buckets(0.00005, 1.8, 26).unwrap()
    )
    .unwrap();
    pub static ref LOG_SYNC_DURATION_HISTOGRAM: Histogram = register_histogram!(
        "raft_engine_sync_log_duration_seconds",
        "Bucketed histogram of Raft Engine sync log duration",
        exponential_buckets(0.00005, 1.8, 26).unwrap()
    )
    .unwrap();
    pub static ref LOG_ROTATE_DURATION_HISTOGRAM: Histogram = register_histogram!(
        "raft_engine_rotate_log_duration_seconds",
        "Bucketed histogram of Raft Engine rotate log duration",
        exponential_buckets(0.00005, 1.8, 26).unwrap()
    )
    .unwrap();
    // Read path.
    pub static ref ENGINE_READ_ENTRY_DURATION_HISTOGRAM: Histogram = register_histogram!(
        "raft_engine_read_entry_duration_seconds",
        "Bucketed histogram of Raft Engine read entry duration",
        exponential_buckets(0.00005, 1.8, 26).unwrap()
    )
    .unwrap();
    pub static ref ENGINE_READ_ENTRY_COUNT_HISTOGRAM: Histogram = register_histogram!(
        "raft_engine_read_entry_count",
        "Bucketed histogram of Raft Engine read entry count",
        exponential_buckets(1.0, 1.8, 22).unwrap()
    )
    .unwrap();
    pub static ref ENGINE_READ_MESSAGE_DURATION_HISTOGRAM: Histogram = register_histogram!(
        "raft_engine_read_message_duration_seconds",
        "Bucketed histogram of Raft Engine read message duration",
        exponential_buckets(0.00005, 1.8, 26).unwrap()
    )
    .unwrap();
    // Misc.
    pub static ref ENGINE_PURGE_DURATION_HISTOGRAM: Histogram = register_histogram!(
        "raft_engine_purge_duration_seconds",
        "Bucketed histogram of Raft Engine purge expired files duration",
        exponential_buckets(0.001, 1.8, 22).unwrap()
    )
    .unwrap();
    pub static ref ENGINE_REWRITE_APPEND_DURATION_HISTOGRAM: Histogram = register_histogram!(
        "raft_engine_rewrite_append_duration_seconds",
        "Bucketed histogram of Raft Engine rewrite append queue duration",
        exponential_buckets(0.001, 1.8, 22).unwrap()
    )
    .unwrap();
    pub static ref ENGINE_REWRITE_REWRITE_DURATION_HISTOGRAM: Histogram = register_histogram!(
        "raft_engine_rewrite_rewrite_duration_seconds",
        "Bucketed histogram of Raft Engine rewrite rewrite queue duration",
        exponential_buckets(0.001, 1.8, 22).unwrap()
    )
    .unwrap();
    pub static ref BACKGROUND_REWRITE_BYTES: LogQueueHistogramVec = register_static_histogram_vec!(
        LogQueueHistogramVec,
        "raft_engine_background_rewrite_bytes",
        "Bucketed histogram of bytes written during background rewrite",
        &["type"],
        exponential_buckets(256.0, 1.8, 22).unwrap()
    )
    .unwrap();
    pub static ref LOG_FILE_COUNT: LogQueueGaugeVec = register_static_int_gauge_vec!(
        LogQueueGaugeVec,
        "raft_engine_log_file_count",
        "Amount of log files in Raft engine",
        &["type"]
    )
    .unwrap();
    pub static ref RECYCLED_FILE_COUNT: LogQueueGaugeVec = register_static_int_gauge_vec!(
        LogQueueGaugeVec,
        "raft_engine_recycled_file_count",
        "Amount of recycled files in Raft engine",
        &["type"]
    )
    .unwrap();
    pub static ref SWAP_FILE_COUNT: IntGauge = register_int_gauge!(
        "raft_engine_swap_file_count",
        "Amount of swap files in Raft engine"
    )
    .unwrap();
    pub static ref LOG_ENTRY_COUNT: LogQueueGaugeVec = register_static_int_gauge_vec!(
        LogQueueGaugeVec,
        "raft_engine_log_entry_count",
        "Number of log entries in Raft engine",
        &["type"]
    )
    .unwrap();
    pub static ref MEMORY_USAGE: IntGauge = register_int_gauge!(
        "raft_engine_memory_usage",
        "Memory in bytes used by Raft engine",
    )
    .unwrap();
}
