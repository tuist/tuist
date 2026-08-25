defmodule Tuist.Kura.StorageRollup do
  @moduledoc """
  One day of storage telemetry for one Kura account-region: how much the ring
  evicted, how young the shed content was, and how full the ring got. Rolled
  up hourly from ClickHouse; claim sizing reads only these rows.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account

  schema "kura_storage_rollups" do
    field :region, :string
    field :date, :date
    field :eviction_count, :integer, default: 0
    field :evicted_bytes, :integer, default: 0
    field :evicted_artifact_count, :integer, default: 0
    field :min_shed_age_seconds, :integer
    field :median_shed_age_seconds, :integer
    field :median_ring_span_seconds, :integer
    field :snapshot_count, :integer, default: 0
    field :max_occupancy_percent, :integer
    field :max_live_segment_bytes, :integer
    field :last_ring_budget_bytes, :integer

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end

  def changeset(rollup, attrs) do
    rollup
    |> cast(attrs, [
      :account_id,
      :region,
      :date,
      :eviction_count,
      :evicted_bytes,
      :evicted_artifact_count,
      :min_shed_age_seconds,
      :median_shed_age_seconds,
      :median_ring_span_seconds,
      :snapshot_count,
      :max_occupancy_percent,
      :max_live_segment_bytes,
      :last_ring_budget_bytes
    ])
    |> validate_required([:account_id, :region, :date])
    |> foreign_key_constraint(:account_id)
    |> unique_constraint([:account_id, :region, :date])
  end
end
