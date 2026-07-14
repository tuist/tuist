defmodule Tuist.IngestRepo.Migrations.AddEnvironmentToCommandEvents do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    exclude_environment_from_materialized_views()

    execute "ALTER TABLE command_events ADD COLUMN IF NOT EXISTS environment Map(String, String) DEFAULT map()"
  end

  def down do
    execute "ALTER TABLE command_events DROP COLUMN IF EXISTS environment"

    include_all_columns_in_materialized_views()
  end

  defp exclude_environment_from_materialized_views do
    execute "ALTER TABLE command_events_by_ran_at MODIFY QUERY SELECT * EXCEPT environment FROM command_events"

    execute "ALTER TABLE command_events_by_duration MODIFY QUERY SELECT * EXCEPT environment FROM command_events"

    execute "ALTER TABLE command_events_by_hit_rate MODIFY QUERY SELECT * EXCEPT environment FROM command_events"

    execute "ALTER TABLE command_events_by_name_ran_at_mv MODIFY QUERY SELECT * EXCEPT environment FROM command_events"
  end

  defp include_all_columns_in_materialized_views do
    execute "ALTER TABLE command_events_by_ran_at MODIFY QUERY SELECT * FROM command_events"
    execute "ALTER TABLE command_events_by_duration MODIFY QUERY SELECT * FROM command_events"
    execute "ALTER TABLE command_events_by_hit_rate MODIFY QUERY SELECT * FROM command_events"

    execute "ALTER TABLE command_events_by_name_ran_at_mv MODIFY QUERY SELECT * FROM command_events"
  end
end
