defmodule Tuist.Runners.RunnerSession do
  @moduledoc """
  Append-only billing record for every runner Pod we
  provisioned. One row per (workflow_job_id, claim) — re-claims
  create new rows so retries are billed for the time the
  customer actually held a Pod.

  See `priv/repo/migrations/20260525120000_create_runner_sessions.exs`
  for the schema rationale and `Tuist.Runners.Billing` for the
  query API that aggregates over these rows.
  """
  use Ecto.Schema

  alias Tuist.Accounts.Account

  schema "runner_sessions" do
    field :workflow_job_id, :integer
    field :fleet_name, :string
    field :platform, Ecto.Enum, values: [:linux, :macos]
    field :vcpus, :integer
    field :memory_gb, :integer
    # Cost-weighted machine factor in basis points, frozen at open time so
    # a later rate-card change can't reprice usage that already happened.
    field :billing_multiplier, :integer
    field :pod_name, :string, default: ""
    field :runner_name, :string, default: ""
    # The workflow_job GitHub actually ran on this runner, learned
    # from the `in_progress` / `completed` webhook. Durable ground
    # truth that outlives the pod; NULL until GitHub proves it.
    field :executed_workflow_job_id, :integer
    field :repository, :string, default: ""
    field :workflow_name, :string, default: ""
    field :started_at, :utc_datetime_usec
    field :ended_at, :utc_datetime_usec

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end
end
