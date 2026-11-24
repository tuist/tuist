CREATE TABLE IF NOT EXISTS "errors" (
  "timestamp" TIMESTAMP(9) NOT NULL,
  "service" STRING,
  "fingerprint" STRING,
  "event_id" STRING SKIPPING INDEX,
  "level" STRING,
  "environment" STRING,
  "release" STRING,
  "platform" STRING,
  "server_name" STRING,
  "transaction" STRING,
  "logger" STRING,
  "exception_type" STRING,
  "exception_value" STRING,
  "title" STRING,
  "culprit" STRING,
  "trace_id" STRING SKIPPING INDEX,
  "account_handle" STRING,
  "sdk" STRING,
  "event" JSON,
  TIME INDEX ("timestamp"),
  PRIMARY KEY ("service", "fingerprint")
)
WITH (
  append_mode = 'true'
)
