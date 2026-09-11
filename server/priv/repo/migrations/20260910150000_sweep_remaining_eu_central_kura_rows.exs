defmodule Tuist.Repo.Migrations.SweepRemainingEuCentralKuraRows do
  use Ecto.Migration

  alias Tuist.Repo

  # The Postgres half of the rename's second pass. The pre-upgrade migration
  # rewrote every region-scoped row that existed when it ran, but the instances
  # kept reporting the old id until the reconciler re-rendered and rolled them,
  # so a storage rollup landed under `eu-central` in that gap. Every other
  # region-keyed table came through clean.
  #
  # Swept together rather than singling out the one table, because which tables
  # take a write in that window depends on timing rather than on anything
  # structural. Idempotent: a second run matches nothing.
  @region_columns [
    {:kura_servers, :region},
    {:kura_account_region_lifecycles, :service_region},
    {:kura_account_region_policies, :service_region},
    {:kura_placement_proposals, :from_region},
    {:kura_placement_proposals, :to_region},
    {:kura_placer_regions, :region},
    {:kura_egress_limits, :region},
    {:kura_claim_proposals, :region},
    {:kura_registered_endpoints, :region}
  ]

  def up do
    sweep_storage_rollups!(Repo)

    for {table, column} <- @region_columns do
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      execute("UPDATE #{table} SET #{column} = 'eu-west' WHERE #{column} = 'eu-central'")
    end

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "UPDATE kura_deployments SET cluster_id = 'eu-west-1' WHERE cluster_id = 'eu-central-1'"
    )
  end

  def sweep_storage_rollups!(repo) do
    # These are replace-on-refresh aggregates, not additive events. The first
    # rename may already have moved the same observations into the canonical
    # row, so summing would double-count, and medians cannot be merged exactly.
    # Keep the canonical aggregate when both aliases exist; the periodic refresh
    # recomputes recent days from the underlying ClickHouse telemetry.
    # excellent_migrations:safety-assured-for-next-line operation_query
    repo.query!("""
    DELETE FROM kura_storage_rollups AS legacy
    USING kura_storage_rollups AS canonical
    WHERE legacy.region = 'eu-central'
      AND canonical.region = 'eu-west'
      AND legacy.account_id = canonical.account_id
      AND legacy.date = canonical.date
    """)

    # excellent_migrations:safety-assured-for-next-line operation_query
    repo.query!("UPDATE kura_storage_rollups SET region = 'eu-west' WHERE region = 'eu-central'")
  end

  # Not reversible from here: the rename migration's `down` already restores
  # every row it moved, and this pass cannot tell the stragglers it rewrote
  # apart from the rows that were always eu-west.
  def down, do: :ok
end
