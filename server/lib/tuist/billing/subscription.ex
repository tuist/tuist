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
    field :past_due_since, :utc_datetime
    field :stripe_event_created_at, :utc_datetime
    field :payment_grace_expiry_notified_at, :utc_datetime
    field :default_payment_method, :string
    field :trial_end, :utc_datetime
    field :cancel_at_period_end, :boolean, default: false

    # Mirrored from Stripe by the subscription webhooks so that anything
    # attributing usage to the period the next invoice covers can read it
    # without a request per render.
    field :current_period_start, :utc_datetime
    field :current_period_end, :utc_datetime

    belongs_to :account, Account

    # credo:disable-for-next-line Credo.Checks.TimestampsType
    timestamps()
  end

  @payment_grace_period_days 7

  def payment_grace_period_days, do: @payment_grace_period_days

  def payment_grace_ends_at(%{status: "past_due", past_due_since: %DateTime{} = since}) do
    DateTime.add(since, @payment_grace_period_days, :day)
  end

  # During a rolling deployment an older replica can still insert a past_due
  # row without an anchor. Its persisted update time gives it a bounded grace.
  def payment_grace_ends_at(%{status: "past_due", updated_at: %NaiveDateTime{} = updated_at}) do
    updated_at
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.add(@payment_grace_period_days, :day)
  end

  def payment_grace_ends_at(_subscription), do: nil

  def entitled?(subscription, now \\ DateTime.utc_now())

  def entitled?(%{status: status}, _now) when status in ["active", "trialing"], do: true

  def entitled?(%{status: "past_due"} = subscription, now) do
    case payment_grace_ends_at(subscription) do
      %DateTime{} = deadline -> DateTime.before?(now, deadline)
      nil -> false
    end
  end

  def entitled?(_subscription, _now), do: false

  def create_changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [
      :plan,
      :subscription_id,
      :account_id,
      :status,
      :past_due_since,
      :stripe_event_created_at,
      :payment_grace_expiry_notified_at,
      :default_payment_method,
      :trial_end,
      :cancel_at_period_end,
      :current_period_start,
      :current_period_end,
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
    |> cast(attrs, [
      :plan,
      :status,
      :past_due_since,
      :stripe_event_created_at,
      :payment_grace_expiry_notified_at,
      :default_payment_method,
      :trial_end,
      :cancel_at_period_end,
      :current_period_start,
      :current_period_end
    ])
    |> validate_plan()
  end
end
