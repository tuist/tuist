defmodule Tuist.ClickHouse.Tables do
  @moduledoc """
  Splits the destination's tables into the ones the migration copies and the
  ones it lets ClickHouse rebuild.

  A materialized view is an insert trigger, so copying rows into a base table
  on the destination fires every view that reads it, and those views write the
  derived tables themselves. Copying a derived table as well would count its
  rows twice, and on the `AggregatingMergeTree` targets it would do so
  invisibly: two copies of an aggregate state merge into one state holding
  double the counts, rather than into a duplicate row somebody could notice.

  So the migration copies base tables and nothing else, and the derived tables
  come back the way they were built in the first place. Views whose storage is
  implicit are already handled this way, since their inner tables were never
  cloned; this extends the same rule to the views that name a target.
  """

  @doc """
  The tables to copy: everything on the destination that no materialized view
  writes into.
  """
  def copied(target) do
    derived = view_targets(target)

    target
    |> all_tables()
    |> Enum.reject(&MapSet.member?(derived, &1))
  end

  @doc """
  The tables a materialized view writes into, which the destination rebuilds
  for itself.
  """
  def derived(target) do
    derived = view_targets(target)

    target |> all_tables() |> Enum.filter(&MapSet.member?(derived, &1))
  end

  defp all_tables(target) do
    %{rows: rows} =
      target.repo.query!(
        """
        SELECT name FROM system.tables
        WHERE database = {database:String}
          AND engine LIKE 'Replicated%'
          AND name NOT LIKE '.inner%'
          AND name != 'schema_migrations'
        ORDER BY total_bytes ASC
        """,
        %{"database" => target.database},
        log: false
      )

    List.flatten(rows)
  end

  defp view_targets(target) do
    %{rows: rows} =
      target.repo.query!(
        """
        SELECT create_table_query FROM system.tables
        WHERE database = {database:String} AND engine = 'MaterializedView'
        """,
        %{"database" => target.database},
        log: false
      )

    rows
    |> List.flatten()
    |> Enum.flat_map(&List.wrap(view_target(&1, target.database)))
    |> MapSet.new()
  end

  @doc """
  The table a materialized view writes into, or `nil` when its storage is
  implicit and it therefore owns an inner table instead.

  Public because this is a parse of someone else's DDL, and getting it wrong
  is silent: a target that is not recognised gets copied on top of the rows
  its own view just wrote.
  """
  def view_target(ddl, database) do
    case Regex.run(~r/\sTO\s+`?#{Regex.escape(database)}`?\.`?([A-Za-z0-9_]+)`?/i, ddl) do
      [_, table] -> table
      nil -> nil
    end
  end
end
