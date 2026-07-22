defmodule Tuist.Runners.WorkflowJob do
  @moduledoc """
  Postgres lifecycle row for a GitHub workflow_job — one row per
  `workflow_job_id`, mutated in place through guarded compare-and-set
  transitions (`queued → claimed → running → completed/cancelled`,
  with claim-release paths moving rows back to `queued`).

  This is the control-plane twin of the ClickHouse `runner_jobs`
  ReplacingMergeTree (`Tuist.Runners.Job`), which stays the
  analytics/history store. Unlike the CH table, transitions here are
  single-row UPDATEs guarded on the expected current status, so
  webhook redeliveries and claim races cannot regress a row. See
  `Tuist.Runners.WorkflowJobs` for the operational contract.

  Carries the full dispatch-candidate metadata (repository, shape,
  workflow correlation fields) so the flag-gated Postgres dispatch
  read can return the same candidate map the ClickHouse read does.
  """
  use Ecto.Schema

  alias Tuist.Accounts.Account

  @primary_key {:workflow_job_id, :integer, []}

  schema "runner_workflow_jobs" do
    field :fleet_name, :string
    field :status, :string
    field :conclusion, :string
    field :platform, :string, default: ""
    field :vcpus, :integer, default: 0
    field :memory_gb, :integer, default: 0
    field :repository, :string, default: ""
    field :workflow_run_id, :integer, default: 0
    field :workflow_name, :string, default: ""
    field :run_attempt, :integer, default: 1
    field :job_name, :string, default: ""
    field :head_branch, :string, default: ""
    field :head_sha, :string, default: ""
    field :requested_dispatch_label, :string, default: ""
    field :enqueued_at, :utc_datetime_usec
    field :claimed_at, :utc_datetime_usec
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :pod_name, :string
    field :runner_name, :string
    field :executed_workflow_job_id, :integer

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end
end
