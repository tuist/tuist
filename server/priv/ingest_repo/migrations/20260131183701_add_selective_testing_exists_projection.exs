defmodule Tuist.IngestRepo.Migrations.AddSelectiveTestingExistsProjection do
  use Ecto.Migration

  def up do
    # Add projection optimized for has_selective_testing_data? existence checks
    # Orders by (command_event_id, selective_testing_hash) so that:
    # 1. Rows for a command_event_id are grouped together
    # 2. Within each group, null hashes come first (ClickHouse sorts nulls first by default)
    #    so non-null hashes are at the end, making LIMIT 1 with isNotNull efficient
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE xcode_targets
    ADD PROJECTION proj_selective_testing_lookup (
      SELECT *
      ORDER BY (command_event_id, selective_testing_hash)
    )
    """

    # Add similar projection for has_binary_cache_data? existence checks
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE xcode_targets
    ADD PROJECTION proj_binary_cache_lookup (
      SELECT *
      ORDER BY (command_event_id, binary_cache_hash)
    )
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE xcode_targets DROP PROJECTION IF EXISTS proj_selective_testing_lookup"
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE xcode_targets DROP PROJECTION IF EXISTS proj_binary_cache_lookup"
  end
end
