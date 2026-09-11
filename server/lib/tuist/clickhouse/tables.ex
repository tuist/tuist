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
  @collapsing_families ["Replacing", "Collapsing", "Aggregating", "Summing"]

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

  @doc """
  How the two servers' schemas differ: tables one has and the other does not,
  and columns that differ on the tables they share.

  This exists because comparing data cannot see it. Every other check here
  enumerates the destination, so a table that only the source has is not
  compared, not reported, and not missing from any total: it is invisible by
  construction. The way it does surface is a mirrored write failing against a
  column that is not there, which is swallowed by design, so the first real
  symptom would be a rising error counter with nothing pointing at the cause.

  It matters most at the moment the in-cluster server becomes primary. Until
  then a missing column costs a dropped mirror write; after it, the write is
  no longer the mirrored kind and the ingest path breaks.
  """
  def schema_drift(source, target) do
    left = columns_by_table(source)
    right = columns_by_table(target)

    shared = left |> Map.keys() |> Enum.filter(&Map.has_key?(right, &1))

    %{
      missing_on_destination: left |> Map.keys() |> Kernel.--(Map.keys(right)) |> Enum.sort(),
      missing_on_source: right |> Map.keys() |> Kernel.--(Map.keys(left)) |> Enum.sort(),
      differing_columns:
        shared
        |> Enum.flat_map(fn table ->
          {a, b} = {MapSet.difference(left[table], right[table]), MapSet.difference(right[table], left[table])}
          if MapSet.size(a) == 0 and MapSet.size(b) == 0, do: [], else: [{table, MapSet.to_list(a), MapSet.to_list(b)}]
        end)
        |> Enum.sort()
    }
  end

  defp columns_by_table(endpoint) do
    %{rows: rows} =
      endpoint.repo.query!(
        """
        SELECT table, name, type FROM system.columns
        WHERE database = {database:String} AND table NOT LIKE '.inner%'
        """,
        %{"database" => endpoint.database},
        log: false
      )

    rows
    |> Enum.group_by(fn [table, _name, _type] -> table end, fn [_table, name, type] -> "#{name} #{type}" end)
    |> Map.new(fn {table, columns} -> {table, MapSet.new(columns)} end)
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
  ` FINAL` when the table's engine collapses rows on merge, and an empty
  string otherwise.

  Counting without it compares merge schedules rather than data. A freshly
  copied table is small enough that its first merge runs immediately, while
  the source has the same rows spread over parts it has not merged yet, so the
  destination reports fewer rows for data that is identical. That is exactly
  what the first staging backfill saw: 84 rows against 42 on an
  `AggregatingMergeTree`, and 118 against 113 on a `ReplacingMergeTree`.

  `FINAL` is not valid on a plain `MergeTree`, where it is an error rather
  than a no-op, so the engine has to be asked first.
  """
  def final_clause(endpoint, table) do
    %{rows: rows} =
      endpoint.repo.query!(
        "SELECT engine FROM system.tables WHERE database = {database:String} AND name = {table:String}",
        %{"database" => endpoint.database, "table" => table},
        log: false
      )

    case rows do
      [[engine]] -> if String.contains?(engine, @collapsing_families), do: " FINAL", else: ""
      _ -> ""
    end
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
