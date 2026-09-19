defmodule Tuist.Runners.WorkflowJobTransitionEvent do
  @moduledoc """
  Outbox row for a `runner_workflow_jobs` status transition. Inserted
  in the same Postgres transaction as the transition itself, so the
  event stream is exactly the committed transition stream; a batch
  flusher (`Tuist.Runners.Workers.FlushJobTransitionEventsWorker`)
  replays the payloads as ClickHouse `runner_jobs` INSERTs.

  `payload` is the CH insert shape (`Tuist.Runners.Job` columns) with
  datetimes as ISO-8601 strings; `updated_at` inside it is the
  transition timestamp, so replay order doesn't matter — the RMT's
  argMax-by-`updated_at` read resolves any interleaving with the
  direct CH writes that remain on during rollout.

  `account_id` cascades with the account so deleting an account cannot
  leave payloads behind for a later replay to resurrect.
  """
  use Ecto.Schema

  alias Tuist.Accounts.Account

  schema "runner_workflow_job_transition_events" do
    field :workflow_job_id, :integer
    field :payload, :map

    belongs_to :account, Account

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
