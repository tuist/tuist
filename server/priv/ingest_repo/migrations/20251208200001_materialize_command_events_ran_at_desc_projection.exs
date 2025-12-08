defmodule Tuist.ClickHouseRepo.Migrations.MaterializeCommandEventsRanAtDescProjection do
  @moduledoc """
  Materializes the projection for existing data.

  This is separated from the projection creation because materialization
  can take significant time for large tables.
  """
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE command_events MATERIALIZE PROJECTION projection_by_project_name_ran_at_desc"
    )
  end

  def down do
    :ok
  end
end
