defmodule Tuist.ClickHouseRepo.Migrations.AddCommandEventsRanAtDescProjection do
  @moduledoc """
  Adds a projection to optimize queries that filter by project_id and name,
  then order by ran_at DESC with a LIMIT.

  Without this projection, such queries read ALL matching rows from ALL parts
  (e.g., 309K rows / 3.38 GB), merge-sort them, then return just 21 rows.

  With this projection, ClickHouse can read data already sorted by ran_at DESC
  and stop early after finding the LIMIT rows.
  """
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE command_events ADD PROJECTION projection_by_project_name_ran_at_desc
    (
      SELECT *
      ORDER BY project_id, name, ran_at DESC
    )
    """)
  end

  def down do
    execute(
      "ALTER TABLE command_events DROP PROJECTION IF EXISTS projection_by_project_name_ran_at_desc"
    )
  end
end
