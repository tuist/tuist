defmodule Tuist.Runners.PrepaidActivation do
  @moduledoc """
  Durable order activation and external-effect checkpoints, not a credit ledger.

  The original request survives a failed Stripe call so an operator can resume
  the same change instead of granting the money twice. Stripe owns the balance.
  """
  use Ecto.Schema

  schema "runner_prepaid_activations" do
    field :account_id, :integer
    field :change_id, Ecto.UUID
    field :request, :map
    field :principal, :map
    field :before, :map
    field :after, :map
    field :status, :string, default: "pending"
    field :error, :string
    field :grant_id, :string
    field :subscription_schedule_id, :string
    field :activated_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end
