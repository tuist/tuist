-- One hour of span parent edges: for every span whose parent is in the same
-- trace, one edge from the parent's (service, span name) to the child's,
-- counted per hour of the child's start. A Flow cannot join, so the Symptoms
-- evaluator runs this read-only query every hour for the hour that ended at
-- least 10 minutes earlier, replacing {{hour_start}} with that hour's start as
-- an RFC 3339 UTC timestamp ('2026-11-16T15:00:00Z'), and keeps the result in
-- its own database. It writes nothing to Pulse. A parent that started more
-- than an hour before its hour's window is not joined.
SELECT
  parent.service_name AS caller_service,
  parent.span_name AS caller_span_name,
  child.service_name AS callee_service,
  child.span_name AS callee_span_name,
  count(*) AS edge_count
FROM opentelemetry_traces AS child
JOIN opentelemetry_traces AS parent
  ON parent.trace_id = child.trace_id AND parent.span_id = child.parent_span_id
WHERE child."timestamp" >= CAST('{{hour_start}}' AS TIMESTAMP(9))
  AND child."timestamp" < CAST('{{hour_start}}' AS TIMESTAMP(9)) + INTERVAL '1 hour'
  AND parent."timestamp" >= CAST('{{hour_start}}' AS TIMESTAMP(9)) - INTERVAL '1 hour'
  AND parent."timestamp" < CAST('{{hour_start}}' AS TIMESTAMP(9)) + INTERVAL '1 hour'
  AND child.parent_span_id IS NOT NULL
  AND child.parent_span_id <> ''
GROUP BY parent.service_name, parent.span_name, child.service_name, child.span_name
