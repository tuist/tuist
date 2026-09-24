defmodule Atlas.Nudges.Analytics.AirStatus do
  @moduledoc """
  Per-billing-period Air (`runner_minutes`) notification status for one
  account. Populated by resolving the Atlas account to its Tuist server
  account id and counting the distinct thresholds delivered in the current
  billing period.

  `distinct_thresholds_delivered` is the enterprise-fit signal's numerator
  — one row can appear per recipient/threshold on the server, so the
  refresh worker collapses to `count(DISTINCT threshold)` on the server
  side before writing here.
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Account

  @statuses ~w(ok failed)

  schema "nudge_account_air_status" do
    field :period_start, :date
    field :metric, :string
    field :distinct_thresholds_delivered, :integer, default: 0
    field :first_crossed_at, :utc_datetime

    field :refresh_status, :string, default: "ok"
    field :refresh_error, :string
    field :computed_at, :utc_datetime

    belongs_to :account, Account

    timestamps()
  end

  def statuses, do: @statuses

  def changeset(status, attrs) do
    status
    |> cast(attrs, [
      :account_id,
      :period_start,
      :metric,
      :distinct_thresholds_delivered,
      :first_crossed_at,
      :refresh_status,
      :refresh_error,
      :computed_at
    ])
    |> validate_required([:account_id, :period_start, :metric, :refresh_status, :computed_at])
    |> validate_inclusion(:refresh_status, @statuses)
    |> validate_number(:distinct_thresholds_delivered, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:account_id)
    |> unique_constraint([:account_id, :period_start, :metric])
    |> check_constraint(:refresh_status,
      name: :nudge_account_air_status_status_check
    )
  end
end
