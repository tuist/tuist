defmodule Tuist.Runners.JobCompletion do
  @moduledoc """
  Durable completion marker for GitHub workflow jobs.

  `runner_jobs` remains the ClickHouse-backed lifecycle and history table, but
  queued/completed webhooks need a Postgres row they can lock and query
  atomically so a late `queued` redelivery cannot resurrect completed work.
  """
  use Ecto.Schema

  alias Tuist.Accounts.Account

  @primary_key {:workflow_job_id, :integer, []}

  schema "runner_job_completions" do
    field :conclusion, :string
    field :completed_at, :utc_datetime

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end
end
