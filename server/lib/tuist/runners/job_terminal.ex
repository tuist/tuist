defmodule Tuist.Runners.JobTerminal do
  @moduledoc """
  Durable terminal marker for GitHub workflow jobs.

  `runner_jobs` remains the ClickHouse-backed lifecycle and history table, but
  queued/completed webhooks need a Postgres row they can lock and query
  atomically so a late `queued` redelivery cannot resurrect terminal work.
  """
  use Ecto.Schema

  alias Tuist.Accounts.Account

  @primary_key {:workflow_job_id, :integer, []}

  schema "runner_job_terminals" do
    field :conclusion, :string
    field :completed_at, :utc_datetime

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end
end
