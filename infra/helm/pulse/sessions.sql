CREATE TABLE IF NOT EXISTS "sessions" (
  "started" TIMESTAMP(3) NOT NULL,
  "service" STRING,
  "release" STRING,
  "environment" STRING,
  "session_id" STRING,
  "distinct_id" STRING,
  "status" STRING,
  "errors" BIGINT,
  "duration" DOUBLE,
  "sessions" BIGINT,
  "errored" BIGINT,
  "crashed" BIGINT,
  "abnormal" BIGINT,
  "unhandled" BIGINT,
  "seq" BIGINT UNSIGNED,
  "updated" TIMESTAMP(9),
  TIME INDEX ("started"),
  PRIMARY KEY ("service", "release", "environment", "session_id")
)
WITH (
  append_mode = 'true'
)
