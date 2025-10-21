# Cloudflare Analytics Engine Queries

The `metrics` dataset contains one row per sampled request. Useful columns:
- `timestamp` – capture time
- `blob1` – route label
- `blob2` – HTTP method
- `blob3` – response status code (string)
- `double1` – total latency (ms), measured from when the worker receives the request until it produces the response
- `double2` – origin latency (ms); this tracks time spent in outbound network calls routed through the instrumentation helper (Tuist API fetches, S3 uploads/downloads, and KV namespace operations)
- `double3` – compute latency (ms), i.e. worker execution time on the isolate (`total latency – origin latency`)
- `double5` – KV read latency accumulated inside the request (ms), included in origin latency
- `double6` – KV write latency accumulated inside the request (ms), included in origin latency
- `double7` – S3 fetch latency accumulated inside the request (ms), included in origin latency
- `double8` – Tuist server fetch latency accumulated inside the request (ms), included in origin latency
- `double9` – KV hit count (miss count = `double10 - double9`)
- `double10` – KV read call count
- `double11` – KV write call count
- `double12` – S3 fetch call count
- `double13` – Tuist server fetch call count
- `double4` – sample rate used for the capture
- `_sample_interval` – sampling weight (inverse of sample rate; preferred for aggregations)

Always use `_sample_interval` as the weight when aggregating.

## 1. Route Latency Quantiles (Total vs Origin)
```sql
SELECT
  blob1 AS route,
  blob2 AS method,
  IF(
    SUM(_sample_interval) = 0,
    0.0,
    SUM(double1 * _sample_interval) / SUM(_sample_interval)
  ) AS avg_total_latency_ms,
  quantileWeighted(0.50, double1, _sample_interval) AS p50_total_latency_ms,
  quantileWeighted(0.90, double1, _sample_interval) AS p90_total_latency_ms,
  quantileWeighted(0.99, double1, _sample_interval) AS p99_total_latency_ms,
  quantileWeighted(0.90, double2, _sample_interval) AS p90_origin_latency_ms,
  quantileWeighted(0.90, double3, _sample_interval) AS p90_compute_latency_ms,
  SUM(_sample_interval) AS est_request_count
FROM metrics
WHERE timestamp >= NOW() - INTERVAL '7' DAY
GROUP BY route, method
ORDER BY p99_total_latency_ms DESC;
```

## 2. KV & External Latency Per Operation
```sql
SELECT
  blob1 AS route,
  blob2 AS method,
  IF(
    SUM(double10 * _sample_interval) = 0,
    0.0,
    SUM(double5 * _sample_interval) / SUM(double10 * _sample_interval)
  ) AS avg_kv_read_latency_per_call_ms,
  quantileWeighted(
    0.90,
    IF(double10 > 0, double5 / double10, 0.0),
    IF(double10 > 0, _sample_interval, 0)
  ) AS p90_kv_read_latency_per_request_ms,
  IF(
    SUM(double11 * _sample_interval) = 0,
    0.0,
    SUM(double6 * _sample_interval) / SUM(double11 * _sample_interval)
  ) AS avg_kv_write_latency_per_call_ms,
  quantileWeighted(
    0.90,
    IF(double11 > 0, double6 / double11, 0.0),
    IF(double11 > 0, _sample_interval, 0)
  ) AS p90_kv_write_latency_per_request_ms,
  SUM(double10 * _sample_interval) AS est_kv_read_call_count,
  SUM(double11 * _sample_interval) AS est_kv_write_call_count,
  IF(
    SUM(double12 * _sample_interval) = 0,
    0.0,
    SUM(double7 * _sample_interval) / SUM(double12 * _sample_interval)
  ) AS avg_s3_fetch_latency_per_call_ms,
  quantileWeighted(
    0.90,
    IF(double12 > 0, double7 / double12, 0.0),
    IF(double12 > 0, _sample_interval, 0)
  ) AS p90_s3_fetch_latency_per_request_ms,
  IF(
    SUM(double13 * _sample_interval) = 0,
    0.0,
    SUM(
      IF(
        double8 < 0,
        0.0,
        double8
      ) * _sample_interval
    ) / SUM(double13 * _sample_interval)
  ) AS avg_server_fetch_latency_per_call_ms,
  quantileWeighted(
    0.90,
    IF(
      double13 > 0,
      IF(double8 < 0, 0.0, double8) / double13,
      0.0
    ),
    IF(double13 > 0, _sample_interval, 0)
  ) AS p90_server_fetch_latency_per_request_ms,
  SUM(double12 * _sample_interval) AS est_s3_fetch_call_count,
  SUM(double13 * _sample_interval) AS est_server_fetch_call_count
FROM metrics
WHERE timestamp >= NOW() - INTERVAL '7' DAY
GROUP BY route, method
ORDER BY p90_kv_read_latency_per_request_ms DESC;
```

## 3. KV Hit/Miss Rate by Route
```sql
SELECT
  blob1 AS route,
  blob2 AS method,
  SUM(double9 * _sample_interval) AS kv_hit_call_count,
  IF(
    SUM(double10 * _sample_interval) - SUM(double9 * _sample_interval) < 0,
    0.0,
    SUM(double10 * _sample_interval) - SUM(double9 * _sample_interval)
  ) AS kv_miss_call_count,
  SUM(double10 * _sample_interval) AS total_kv_read_call_count,
  IF(
    SUM(double10 * _sample_interval) = 0,
    0.0,
    SUM(double9 * _sample_interval) / SUM(double10 * _sample_interval)
  ) AS kv_hit_rate
FROM metrics
WHERE timestamp >= NOW() - INTERVAL '7' DAY
GROUP BY route, method
ORDER BY kv_hit_rate ASC;
```

## 4. Tuist Server Latency on KV Misses
```sql
SELECT
  blob1 AS route,
  blob2 AS method,
  quantileWeighted(
    0.50,
    IF(double13 > 0, double8 / double13, 0.0),
    _sample_interval
  ) AS p50_server_fetch_latency_ms,
  quantileWeighted(
    0.90,
    IF(double13 > 0, double8 / double13, 0.0),
    _sample_interval
  ) AS p90_server_fetch_latency_ms,
  SUM(double13 * _sample_interval) AS est_server_fetch_call_count
FROM metrics
WHERE timestamp >= NOW() - INTERVAL '7' DAY
  AND double13 > 0
GROUP BY route, method
ORDER BY p90_server_fetch_latency_ms DESC;
```

## 5. KV Miss Rate Impact on Latency
```sql
SELECT
  blob1 AS route,
  blob2 AS method,
  quantileWeighted(0.90, double1, _sample_interval) AS p90_total_latency_ms,
  quantileWeighted(0.90, double2, _sample_interval) AS p90_origin_latency_ms,
  quantileWeighted(0.90, double3, _sample_interval) AS p90_compute_latency_ms,
  quantileWeighted(0.90, double10, _sample_interval) AS p90_kv_reads_per_request,
  quantileWeighted(
    0.90,
    IF(double10 > 0, (double10 - double9) / double10, 0.0),
    _sample_interval
  ) AS p90_kv_miss_ratio
FROM metrics
WHERE timestamp >= NOW() - INTERVAL '7' DAY
GROUP BY route, method
ORDER BY p90_total_latency_ms DESC;
```

## 6. Origin Component Breakdown
```sql
SELECT
  blob1 AS route,
  blob2 AS method,
  quantileWeighted(0.90, double1, _sample_interval) AS p90_total_latency_ms,
  quantileWeighted(0.90, double2, _sample_interval) AS p90_origin_latency_ms,
  quantileWeighted(0.90, double3, _sample_interval) AS p90_compute_latency_ms,
  SUM(double2 * _sample_interval) / SUM(_sample_interval) AS avg_origin_latency_ms,
  SUM(double5 * _sample_interval) / SUM(_sample_interval) AS avg_kv_read_latency_ms,
  SUM(double6 * _sample_interval) / SUM(_sample_interval) AS avg_kv_write_latency_ms,
  SUM(double7 * _sample_interval) / SUM(_sample_interval) AS avg_s3_fetch_latency_ms,
  SUM(double8 * _sample_interval) / SUM(_sample_interval) AS avg_server_fetch_latency_ms,
  quantileWeighted(0.90, double5, _sample_interval) AS p90_kv_read_latency_ms,
  quantileWeighted(0.90, double6, _sample_interval) AS p90_kv_write_latency_ms,
  quantileWeighted(0.90, IF(double12 > 0, double7 / double12, 0.0), _sample_interval) AS p90_s3_fetch_latency_ms,
  quantileWeighted(
    0.90,
    IF(double13 > 0, double8 / double13, 0.0),
    _sample_interval
  ) AS p90_server_fetch_latency_ms,
  SUM(double10 * _sample_interval) AS est_kv_read_call_count,
  SUM(double11 * _sample_interval) AS est_kv_write_call_count,
  SUM(double12 * _sample_interval) AS est_s3_fetch_call_count,
  SUM(double13 * _sample_interval) AS est_server_fetch_call_count
FROM metrics
WHERE timestamp >= NOW() - INTERVAL '7' DAY
GROUP BY route, method
ORDER BY p90_total_latency_ms DESC;
```

Adjust any `WHERE` window (`INTERVAL '7' DAY`) to target different time ranges or environments.
