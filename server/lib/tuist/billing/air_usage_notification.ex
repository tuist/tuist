defmodule Tuist.Billing.AirUsageNotification do
  @moduledoc """
  Durable delivery tracking for each Air usage threshold and recipient.
  """
  use Ecto.Schema

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User

  schema "air_usage_notifications" do
    belongs_to :account, Account
    belongs_to :user, User
    field :metric, Ecto.Enum, values: [:remote_cache_hits, :runner_minutes], default: :remote_cache_hits
    field :period_start, :utc_datetime
    field :threshold, :integer
    field :usage, :integer
    field :limit, :integer
    field :delivered_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
