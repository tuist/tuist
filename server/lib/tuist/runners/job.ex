defmodule Tuist.Runners.Job do
  @moduledoc """
  A workflow_job's lifecycle record. One logical row per
  `workflow_job_id`, stored in ClickHouse (`runner_jobs`) as a
  ReplacingMergeTree where each state transition is an INSERT
  with an advanced `updated_at`. See `Tuist.Runners.Jobs` for
  the operational contract + `Tuist.IngestRepo.Migrations.CreateRunnerJobs`
  for the schema rationale.
  """
  use Ecto.Schema

  @primary_key false

  schema "runner_jobs" do
    field :workflow_job_id, Ch, type: "Int64"
    field :account_id, Ch, type: "Int64"
    field :fleet_name, Ch, type: "LowCardinality(String)"
    field :repository, Ch, type: "String"

    field :workflow_run_id, Ch, type: "Int64", default: 0
    field :workflow_name, Ch, type: "String", default: ""
    field :run_attempt, Ch, type: "Int32", default: 1
    field :job_name, Ch, type: "String", default: ""
    field :head_branch, Ch, type: "String", default: ""
    field :head_sha, Ch, type: "String", default: ""

    field :status, Ch, type: "LowCardinality(String)"

    field :conclusion, Ch, type: "LowCardinality(String)", default: ""

    field :enqueued_at, Ch, type: "DateTime64(6, 'UTC')"
    field :claimed_at, Ch, type: "Nullable(DateTime64(6, 'UTC'))", default: nil
    field :started_at, Ch, type: "Nullable(DateTime64(6, 'UTC'))", default: nil
    field :completed_at, Ch, type: "Nullable(DateTime64(6, 'UTC'))", default: nil

    field :pod_name, Ch, type: "String", default: ""
    field :runner_name, Ch, type: "String", default: ""

    # Captured-log lifecycle. Per-line logs live in `runner_job_logs`;
    # these mirror their state onto the job row so the detail page can
    # decide between a live tail and a finished read. See
    # `Tuist.Runners.Jobs.set_log_state/3`.
    field :log_state, Ch, type: "LowCardinality(String)", default: ""
    field :log_line_count, Ch, type: "UInt32", default: 0

    # S3 object key of the gzipped full-log archive, set by
    # `Tuist.Runners.Workers.ArchiveLogsWorker` once the job finishes.
    # Empty while logs are still streaming or before the archive is
    # built; the download endpoint streams ClickHouse directly in that
    # window. See `Tuist.Runners.Jobs.set_log_archive_key/2`.
    field :log_archive_key, Ch, type: "String", default: ""

    # RMT version column. Every state-transition INSERT advances
    # this; merge keeps the row with the latest `updated_at` for
    # each `workflow_job_id`.
    field :updated_at, Ch, type: "DateTime64(6, 'UTC')"
  end
end
