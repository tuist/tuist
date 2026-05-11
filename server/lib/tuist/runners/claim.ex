defmodule Tuist.Runners.Claim do
  @moduledoc """
  Thin Postgres claim-lock for the dispatch path. See
  `Tuist.Runners.Claims` for the operational API and the
  `runner_claims` migration for the schema rationale.

  Note the primary key is `workflow_job_id`, not the implicit
  `id` — the PK doubles as the atomic-claim primitive (`INSERT
  … ON CONFLICT DO NOTHING`).
  """
  use Ecto.Schema

  alias Tuist.Accounts.Account

  @primary_key {:workflow_job_id, :integer, []}

  schema "runner_claims" do
    field :fleet_name, :string
    field :pod_name, :string
    field :claimed_at, :utc_datetime_usec

    belongs_to :account, Account
  end
end
