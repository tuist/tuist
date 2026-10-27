defmodule Tuist.IngestRepo.Migrations.MaterializeMinmaxIndexes do
  use Ecto.Migration

  def up do
    # Materialize the indexes on existing data
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE xcode_targets MATERIALIZE INDEX idx_selective_testing_minmax"
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE xcode_targets MATERIALIZE INDEX idx_binary_cache_minmax"
  end

  def down do
    # Materialization cannot be undone
    :ok
  end
end
