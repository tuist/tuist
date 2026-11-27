defmodule Tuist.Runners.PrepaidTopUp do
  @moduledoc """
  Durable request and Stripe checkpoints of a top-up on a live prepaid pool
  (`Tuist.Ops.RunnerBilling.top_up/3`), not a credit ledger: Stripe owns the
  balance. `grant_ids` lists the per-platform grants Stripe has accepted, so a
  resumed request never grants the same platform twice.
  """
  use Ecto.Schema

  alias Tuist.Runners.PrepaidActivation

  schema "runner_prepaid_top_ups" do
    field :account_id, :integer
    belongs_to :activation, PrepaidActivation
    field :change_id, Ecto.UUID
    field :request, :map
    field :principal, :map
    field :before, :map
    field :after, :map
    field :status, :string, default: "pending"
    field :error, :string
    field :grant_ids, {:array, :string}, default: []
    timestamps(type: :utc_datetime)
  end
end
