defmodule Tuist.IngestRepo.Migrations.AddModuleCountToXcodeGraphs do
  use Ecto.Migration

  def change do
    alter table(:xcode_graphs) do
      add :project_id, :Int64
      add :modules_count, :"Nullable(UInt32)"
    end

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      """
      ALTER TABLE xcode_graphs ADD PROJECTION module_inventory_by_project (
        SELECT project_id, inserted_at, command_event_id, id, modules_count
        ORDER BY (project_id, inserted_at, command_event_id, id)
      )
      """,
      "ALTER TABLE xcode_graphs DROP PROJECTION IF EXISTS module_inventory_by_project"
    )
  end
end
