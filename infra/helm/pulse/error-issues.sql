-- Durable issue state for `errors` (errors.sql): one row per issue and hour
-- it occurred in, kept after `errors` expires, so first sightings, new issues
-- and regressions are cheap reads (README.md, "Issue lifecycle"). The flow
-- recomputes the hours of the last day from `errors` whenever new events
-- arrive there and when the deployment flushes it, so an hour it missed heals
-- on the next flush. Events that arrive more than a day late are not counted.
-- `events` counts distinct event IDs, because `errors` keeps SDK resends.
CREATE TABLE IF NOT EXISTS "error_issue_hours" (
  "service" STRING,
  "fingerprint" STRING,
  "first_seen" TIMESTAMP(9),
  "last_seen" TIMESTAMP(9),
  "events" BIGINT,
  "time_window" TIMESTAMP(9) NOT NULL,
  "update_at" TIMESTAMP(3),
  TIME INDEX ("time_window"),
  PRIMARY KEY ("service", "fingerprint")
)
WITH (
  ttl = 'forever'
);

CREATE OR REPLACE FLOW "error_issues"
SINK TO "error_issue_hours"
EXPIRE AFTER '1 day'::INTERVAL
AS
SELECT
  "service",
  "fingerprint",
  min("timestamp") AS "first_seen",
  max("timestamp") AS "last_seen",
  count(DISTINCT "event_id") AS "events",
  date_bin('1 hour'::INTERVAL, "timestamp") AS "time_window"
FROM "errors"
GROUP BY "service", "fingerprint", "time_window";
