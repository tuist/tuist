defmodule Tuist.Billing.Subscription do
  @moduledoc ~S"""
  A module that represents the subscriptions table.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account

  schema "subscriptions" do
    field :plan, Ecto.Enum, values: [enterprise: 1, air: 2, pro: 3, open_source: 4]
    field :subscription_id, :string
    field :status, :string
    field :default_payment_method, :string
    field :trial_end, :utc_datetime

    belongs_to :account, Account

    # credo:disable-for-next-line Credo.Checks.TimestampsType
    timestamps()
  end

  def create_changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [
      :plan,
      :subscription_id,
      :account_id,
      :status,
      :default_payment_method,
      :trial_end,
      :inserted_at
    ])
    |> validate_required([:plan, :subscription_id, :account_id, :status])
    |> validate_plan()
    |> unique_constraint(:subscription_id, name: "subscriptions_subscription_id_index")
  end

  defp validate_plan(changeset) do
    validate_inclusion(changeset, :plan, [:enterprise, :air, :pro, :open_source])
  end

  def update_changeset(account, attrs) do
    account
    |> cast(attrs, [:plan, :status, :default_payment_method, :trial_end])
    |> validate_plan()
  end
end
