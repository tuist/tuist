defmodule Atlas.Nudges.Analytics.MetricBucket do
  @moduledoc """
  One completed UTC-day bucket of nudge-relevant analytics for one account.

  Buckets are non-overlapping so signals can compute 7- or 28-day rolling
  numerator/denominator by summing the last N rows without double counting.
  A refresh either lands `refresh_status = "ok"` with the four counters
  populated, or `"failed"` with an error string, so the evaluator can tell
  "we did not measure" apart from "genuinely zero."
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Account

  @statuses ~w(ok failed)

  schema "nudge_account_metric_buckets" do
    field :bucket_date, :date

    field :daily_cache_hits, :integer, default: 0
    field :daily_cache_lookups, :integer, default: 0
    field :daily_selective_targets, :integer, default: 0
    field :daily_selective_hits, :integer, default: 0

    field :refresh_status, :string, default: "ok"
    field :refresh_error, :string
    field :computed_at, :utc_datetime

    belongs_to :account, Account

    timestamps()
  end

  def statuses, do: @statuses

  def changeset(bucket, attrs) do
    bucket
    |> cast(attrs, [
      :account_id,
      :bucket_date,
      :daily_cache_hits,
      :daily_cache_lookups,
      :daily_selective_targets,
      :daily_selective_hits,
      :refresh_status,
      :refresh_error,
      :computed_at
    ])
    |> validate_required([:account_id, :bucket_date, :refresh_status, :computed_at])
    |> validate_inclusion(:refresh_status, @statuses)
    |> validate_number(:daily_cache_hits, greater_than_or_equal_to: 0)
    |> validate_number(:daily_cache_lookups, greater_than_or_equal_to: 0)
    |> validate_number(:daily_selective_targets, greater_than_or_equal_to: 0)
    |> validate_number(:daily_selective_hits, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:account_id)
    |> unique_constraint([:account_id, :bucket_date])
    |> check_constraint(:refresh_status,
      name: :nudge_account_metric_buckets_status_check
    )
  end
end
