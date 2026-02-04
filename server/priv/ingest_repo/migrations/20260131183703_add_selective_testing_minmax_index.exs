defmodule Tuist.IngestRepo.Migrations.AddSelectiveTestingMinmaxIndex do
  use Ecto.Migration

  def up do
    # Add minmax index on selective_testing_hash to quickly skip granules
    # where all values are null. This optimizes the isNotNull() check.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE xcode_targets
    ADD INDEX idx_selective_testing_minmax selective_testing_hash TYPE minmax GRANULARITY 1
    """

    # Add similar index for binary_cache_hash
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE xcode_targets
    ADD INDEX idx_binary_cache_minmax binary_cache_hash TYPE minmax GRANULARITY 1
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE xcode_targets DROP INDEX IF EXISTS idx_selective_testing_minmax"
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE xcode_targets DROP INDEX IF EXISTS idx_binary_cache_minmax"
  end
end
