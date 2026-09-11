defmodule Tuist.Repo.Migrations.CreateKuraOriginRollups do
  use Ecto.Migration

  # Day-grain counts of where an account's cache traffic came from, the only
  # persisted form of the origin signal. Attribution happens inside the request
  # path and the address is discarded there, so what lands here is a coarse
  # label and two counters, per account per day. No per-user or per-device
  # series exists to derive one from.
  #
  # The label is stored as it was measured rather than pre-mapped to a region,
  # so correcting the origin table re-reads this history instead of only
  # changing what comes after it.
  def change do
    create table(:kura_origin_rollups) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :origin, :string, null: false
      add :date, :date, null: false
      # Runs are what placement thresholds count: a build or test run that used
      # the cache, attributed once. Endpoint resolutions are the weaker signal
      # kept beside it, biased in both directions by client-side caching and by
      # the launch agent, and used only to place an account that has nothing
      # running yet.
      add :run_count, :bigint, null: false, default: 0
      add :demand_count, :bigint, null: false, default: 0

      timestamps(type: :timestamptz)
    end

    # The flush upserts on this identity every minute, so today's row
    # accumulates as the day runs.
    # The table is new and empty, so building its unique index inline cannot block writes.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:kura_origin_rollups, [:account_id, :origin, :date])

    # The placer reads a window of recent days across every account it sizes.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:kura_origin_rollups, [:date])
  end
end
