defmodule Tuist.IngestRepo.Migrations.MaterializeExistsProjections do
  use Ecto.Migration

  def up do
    # Materialize the projections so they work on existing data
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE xcode_targets MATERIALIZE PROJECTION proj_selective_testing_lookup"
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE xcode_targets MATERIALIZE PROJECTION proj_binary_cache_lookup"
  end

  def down do
    # Materialization cannot be undone - the projections will remain materialized
    :ok
  end
end
