defmodule Tuist.Repo.Migrations.CreateKuraStorageRollups do
  use Ecto.Migration

  # Day-grain storage telemetry per Kura account-region, rolled up hourly from
  # the ClickHouse eviction and snapshot streams. Claim sizing reads only these
  # rows: the decision windows span up to 90 days, and keeping the inputs in
  # Postgres keeps the decision next to the lifecycle rows it acts on.
  #
  # The eviction columns are null when a day saw no capacity evictions, which
  # is itself signal (an unfilled ring never evicts); the snapshot columns are
  # null when no snapshots arrived that day (an instance that wasn't running).
  def change do
    create table(:kura_storage_rollups) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :region, :string, null: false
      add :date, :date, null: false
      add :eviction_count, :bigint, null: false, default: 0
      add :evicted_bytes, :bigint, null: false, default: 0
      add :evicted_artifact_count, :bigint, null: false, default: 0
      add :min_shed_age_seconds, :bigint
      add :median_shed_age_seconds, :bigint
      add :median_ring_span_seconds, :bigint
      add :snapshot_count, :bigint, null: false, default: 0
      add :max_occupancy_percent, :integer
      add :max_live_segment_bytes, :bigint
      add :last_ring_budget_bytes, :bigint

      timestamps(type: :timestamptz)
    end

    # The rollup upserts on this identity every sweep, so today's row converges
    # as the day accumulates.
    # The table is new and empty, so building its unique index inline cannot block writes.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:kura_storage_rollups, [:account_id, :region, :date])
  end
end
