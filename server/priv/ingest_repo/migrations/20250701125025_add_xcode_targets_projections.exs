defmodule Tuist.ClickHouseRepo.Migrations.AddXcodeTargetsProjections do
  use Ecto.Migration

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE xcode_targets
    ADD PROJECTION proj_by_project_and_hit (
      SELECT
        id,
        name,
        binary_cache_hash,
        binary_cache_hit,
        binary_build_duration,
        selective_testing_hash,
        selective_testing_hit,
        xcode_project_id,
        inserted_at
      ORDER BY xcode_project_id, selective_testing_hit, binary_cache_hit
    )
    """

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE xcode_targets MATERIALIZE PROJECTION proj_by_project_and_hit"
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE xcode_targets DROP PROJECTION IF EXISTS proj_by_project_and_hit"
  end
end
