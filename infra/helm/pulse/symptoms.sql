-- Inputs for the Symptoms evaluator (symptoms/README.md, "Inputs"). The
-- deployment smoke (.github/scripts/pulse-smoke.mjs) runs these statements in
-- order after it installs loki-otlp.yaml; every one is idempotent. Flows need a
-- flownode (cluster.flownode in values.yaml). See README.md, "Symptoms inputs".

-- Columns loki-otlp.yaml writes. Native OTLP creates opentelemetry_logs without
-- them, and a Flow cannot reference a column before it exists.
ALTER TABLE opentelemetry_logs ADD COLUMN IF NOT EXISTS "service" STRING;
ALTER TABLE opentelemetry_logs ADD COLUMN IF NOT EXISTS "level" STRING;
ALTER TABLE opentelemetry_logs ADD COLUMN IF NOT EXISTS "template_key" STRING;
ALTER TABLE opentelemetry_logs ADD COLUMN IF NOT EXISTS "template" STRING;
ALTER TABLE opentelemetry_logs ADD COLUMN IF NOT EXISTS "exception_fp" STRING;
-- pulse_trace_v1 adds this column with the first span carrying service.version.
ALTER TABLE opentelemetry_traces ADD COLUMN IF NOT EXISTS "resource_attributes.service.version" STRING;

-- Spans per minute, and those with an error status.
CREATE FLOW IF NOT EXISTS symptoms_trace_counts_1m
SINK TO symptoms_trace_counts_1m
EXPIRE AFTER '1h'
AS SELECT
  service_name,
  span_kind,
  span_name,
  "resource_attributes.service.version" AS service_version,
  date_bin('1 minute'::INTERVAL, "timestamp") AS time_window,
  count(*) AS span_count,
  sum(CASE WHEN span_status_code = 'STATUS_CODE_ERROR' THEN 1 ELSE 0 END) AS error_count
FROM opentelemetry_traces
GROUP BY service_name, span_kind, span_name, service_version, time_window;

-- Span latency histogram per 5 minutes. Bucket b holds durations in
-- [1.1^b, 1.1^(b+1)) ms for b in 1..114; bucket 0 also holds everything under
-- 1.1 ms and bucket 115 everything from 1.1^115 ms (about 57.6 s) up.
CREATE FLOW IF NOT EXISTS symptoms_trace_latency_5m
SINK TO symptoms_trace_latency_5m
EXPIRE AFTER '1h'
AS SELECT
  service_name,
  span_kind,
  span_name,
  "resource_attributes.service.version" AS service_version,
  date_bin('5 minutes'::INTERVAL, "timestamp") AS time_window,
  CAST(greatest(0, least(115, floor(ln(greatest(duration_nano, 1) / 1000000.0) / ln(1.1)))) AS BIGINT) AS latency_bucket,
  count(*) AS span_count
FROM opentelemetry_traces
GROUP BY service_name, span_kind, span_name, service_version, time_window, latency_bucket;

-- Log lines per minute by template, and per service.
CREATE FLOW IF NOT EXISTS symptoms_log_counts_1m
SINK TO symptoms_log_counts_1m
EXPIRE AFTER '1h'
AS SELECT
  "service",
  "level",
  template_key,
  date_bin('1 minute'::INTERVAL, "timestamp") AS time_window,
  count(*) AS line_count
FROM opentelemetry_logs
WHERE template_key IS NOT NULL
GROUP BY "service", "level", template_key, time_window;

CREATE FLOW IF NOT EXISTS symptoms_log_totals_1m
SINK TO symptoms_log_totals_1m
EXPIRE AFTER '1h'
AS SELECT
  "service",
  date_bin('1 minute'::INTERVAL, "timestamp") AS time_window,
  count(*) AS line_count
FROM opentelemetry_logs
WHERE template_key IS NOT NULL
GROUP BY "service", time_window;

-- The evaluator's baselines need 28 days of history; keep 35 whatever the
-- database's TTL (forever in production).
ALTER TABLE symptoms_trace_counts_1m SET 'ttl' = '35d';
ALTER TABLE symptoms_trace_latency_5m SET 'ttl' = '35d';
ALTER TABLE symptoms_log_counts_1m SET 'ttl' = '35d';
ALTER TABLE symptoms_log_totals_1m SET 'ttl' = '35d';
