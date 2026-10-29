defmodule Tuist.Repo.Migrations.AddLastCacheTrafficAtToKuraAccountRegionLifecycles do
  use Ecto.Migration

  # Seeded from the demand clock so no account-region reads as idle the moment
  # the column appears: each one starts its traffic window from the demand it
  # already had. The table holds one row per account-region (hundreds), so the
  # single update is short.
  def up do
    alter table(:kura_account_region_lifecycles) do
      add :last_cache_traffic_at, :timestamptz
    end

    flush()

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "UPDATE kura_account_region_lifecycles SET last_cache_traffic_at = last_cache_demand_at"
    )
  end

  def down do
    alter table(:kura_account_region_lifecycles) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :last_cache_traffic_at
    end
  end
end
