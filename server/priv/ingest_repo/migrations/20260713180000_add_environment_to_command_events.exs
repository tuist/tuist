defmodule Tuist.IngestRepo.Migrations.AddEnvironmentToCommandEvents do
  use Ecto.Migration

  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true

  @implicit_materialized_views ~w(
    command_events_by_ran_at
    command_events_by_duration
    command_events_by_hit_rate
  )

  @materialized_views @implicit_materialized_views ++ ["command_events_by_name_ran_at_mv"]

  def up do
    Enum.each(@implicit_materialized_views, fn view ->
      IngestRepo.query!(
        "ALTER TABLE #{inner_table(view)} ADD COLUMN IF NOT EXISTS environment Map(String, String) DEFAULT map()"
      )
    end)

    IngestRepo.query!(
      "ALTER TABLE command_events_by_name_ran_at ADD COLUMN IF NOT EXISTS environment Map(String, String) DEFAULT map()"
    )

    IngestRepo.query!(
      "ALTER TABLE command_events ADD COLUMN IF NOT EXISTS environment Map(String, String) DEFAULT map()"
    )

    modify_materialized_view_queries("SELECT * FROM command_events")
  end

  def down do
    if column_exists?("command_events", "environment") do
      modify_materialized_view_queries("SELECT * EXCEPT environment FROM command_events")
      IngestRepo.query!("ALTER TABLE command_events DROP COLUMN environment")
    end

    Enum.each(@implicit_materialized_views, fn view ->
      IngestRepo.query!("ALTER TABLE #{inner_table(view)} DROP COLUMN IF EXISTS environment")
    end)

    IngestRepo.query!(
      "ALTER TABLE command_events_by_name_ran_at DROP COLUMN IF EXISTS environment"
    )

    modify_materialized_view_queries("SELECT * FROM command_events")
  end

  defp modify_materialized_view_queries(query) do
    Enum.each(@materialized_views, fn view ->
      IngestRepo.query!("ALTER TABLE #{view} MODIFY QUERY #{query}")
    end)
  end

  defp inner_table(view) do
    %{rows: [[uuid]]} =
      IngestRepo.query!(
        "SELECT toString(uuid) FROM system.tables WHERE database = currentDatabase() AND name = {view:String}",
        %{view: view}
      )

    "`.inner_id.#{uuid}`"
  end

  defp column_exists?(table, column) do
    %{rows: [[count]]} =
      IngestRepo.query!(
        "SELECT count() FROM system.columns WHERE database = currentDatabase() AND table = {table:String} AND name = {column:String}",
        %{table: table, column: column}
      )

    count == 1
  end
end
