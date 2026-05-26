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
    field :claimed_at, Ch, type: "DateTime64(6, 'UTC')"
    field :started_at, Ch, type: "DateTime64(6, 'UTC')"
    field :completed_at, Ch, type: "DateTime64(6, 'UTC')"

    field :pod_name, Ch, type: "String", default: ""
    field :runner_name, Ch, type: "String", default: ""

    # RMT version column. Every state-transition INSERT advances
    # this; merge keeps the row with the latest `updated_at` for
    # each `workflow_job_id`.
    field :updated_at, Ch, type: "DateTime64(6, 'UTC')"
  end
end
