defmodule Tuist.Repo.Migrations.DropUnusedObanJobsMetaIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  # The GIN index on `oban_jobs.meta` serves `meta @> ...` containment
  # lookups. Nothing in this deployment issues them (pg_stat_user_indexes
  # reported idx_scan = 0), yet it is maintained on every insert and on
  # every non-HOT update (Oban indexes `state`, so each state transition
  # is non-HOT and rewrites all indexes). Dropping it removes that write
  # amplification from the hottest table in the database. The args GIN
  # index is kept: it backs the `unique` checks and is actively used.
  def up do
    drop_if_exists(index(:oban_jobs, [:meta], name: "oban_jobs_meta_index"), concurrently: true)
  end

  def down do
    create_if_not_exists(
      index(:oban_jobs, [:meta], name: "oban_jobs_meta_index", using: "gin"),
      concurrently: true
    )
  end
end
