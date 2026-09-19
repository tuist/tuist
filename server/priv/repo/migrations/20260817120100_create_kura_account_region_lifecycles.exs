defmodule Tuist.Repo.Migrations.CreateKuraAccountRegionLifecycles do
  @moduledoc """
  Demand and archival bookkeeping for one account-region Kura instance.

  Keyed on `(account_id, service_region)` because a single Kura instance serves
  every project of that account in that region, so demand is an account-region
  fact rather than a project one.

  This is a separate table from `kura_servers` because `last_cache_demand_at`
  has to survive archival, when the account has no server row worth keeping
  warm, and separate from `kura_account_region_policies` because that table is
  versioned and audited for region assignment while demand is high-churn.
  """
  use Ecto.Migration

  def change do
    create table(:kura_account_region_lifecycles, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :service_region, :string, null: false

      # The latest qualifying cache request across the account's projects in
      # this region, written at the request boundary (coalesced in memory).
      add :last_cache_demand_at, :timestamptz, null: false

      # An explicit account-region override that holds the instance warm while
      # inactive. Not a plan default: it consumes the instance's full
      # allocation for as long as it is set.
      add :keep_warm, :boolean, null: false, default: false

      # Drain-pending bookkeeping. `drain_started_at` clocks the drain window
      # and is what archive cancellation clears; `teardown_started_at` marks
      # the point of no return, after which new demand cold-provisions instead
      # of cancelling.
      add :drain_started_at, :timestamptz
      add :teardown_started_at, :timestamptz

      # Outcome of the last completed archival, kept for capacity reporting
      # after the server row has been recycled by a cold return.
      add :archived_at, :timestamptz
      add :last_reclaimed_bytes, :bigint
      add :last_drain_duration_ms, :bigint
      add :last_returned_at, :timestamptz

      timestamps(type: :timestamptz)
    end

    # The table is new and empty, so its constraints and indexes cannot block existing writes.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:kura_account_region_lifecycles, [:account_id, :service_region])

    # The archival sweep scans by demand recency within a region.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:kura_account_region_lifecycles, [:service_region, :last_cache_demand_at])
  end
end
