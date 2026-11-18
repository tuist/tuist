defmodule Tuist.Runners.PrepaidNotification do
  @moduledoc "Durable per-recipient delivery ledger for prepaid runner pool thresholds."
  use Ecto.Schema

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User
  alias Tuist.Runners.PrepaidActivation

  schema "runner_prepaid_notifications" do
    belongs_to :activation, PrepaidActivation
    belongs_to :account, Account
    belongs_to :user, User
    field :threshold, :integer
    field :usage_cents, :integer
    field :budget_cents, :integer
    field :delivered_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end
