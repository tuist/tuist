defmodule Tuist.ClickHouse.Parity do
  @moduledoc """
  Compares the two ClickHouse servers during the migration off ClickHouse
  Cloud (spec #73), and is the gate the backfill and the dual writes are
  judged against.

  Row counts alone are a weak check: two tables can hold the same number of
  rows and disagree about every value in them, and a `ReplacingMergeTree`
  whose duplicates have not merged yet reports a count that is right for the
  wrong reason. So each table is also fingerprinted, over the columns whose
  drift would actually be visible to a customer: the numbers the dashboards
  sum, and the time bounds that decide which rows a dashboard's window
  selects.

  Reads both sides through `FINAL` where the engine deduplicates, because that
  is what the application's own reads do and therefore what parity has to mean
  here. Without it a freshly copied chunk fails a comparison that the product
  would have passed.
  """

  alias Tuist.ClickHouse.Endpoints

  require Logger

  @doc """
  Fingerprints every table on the destination and compares it with the source.

  Returns `{:ok, report}` where the report lists matching and differing
  tables, so a caller can gate on `differing == []` rather than reading logs.
  """
  def compare(opts \\ []) do
    Endpoints.with_repos(opts, fn source, target ->
      tables = Keyword.get_lazy(opts, :tables, fn -> comparable_tables(target) end)

      rows =
        Enum.map(tables, fn table ->
          left = fingerprint(source, table)
          right = fingerprint(target, table)

          %{table: table, source: left, destination: right, matches: left == right}
        end)

      {matching, differing} = Enum.split_with(rows, & &1.matches)

      report = %{
        compared: length(rows),
        matching: Enum.map(matching, & &1.table),
        differing: Enum.map(differing, &Map.delete(&1, :matches))
      }

      if report.differing == [] do
        Logger.info("ClickHouse parity: all #{report.compared} table(s) agree")
      else
        Logger.error("ClickHouse parity: #{length(report.differing)} of #{report.compared} table(s) differ")
      end

      {:ok, report}
    end)
  end

  # A count, the time bounds, and a sum over every numeric column. The sum is
  # what catches a copy that moved the right number of rows with the wrong
  # values in them, which a count cannot see.
  #
  # Integer and floating-point columns are summed differently on purpose.
  # Integer addition is exact and order-independent, so `sum` over one is a
  # fingerprint. Floating-point addition is neither: the two servers hold the
  # same rows in different parts and will add them in different orders, so an
  # unrounded float sum differs in its last bits for data that is identical.
  # Rounding absorbs that, and the difference a rounded sum could hide is far
  # smaller than any difference worth failing a migration over.
  defp fingerprint(endpoint, table) do
    {integer, float} = numeric_columns(endpoint, table)
    time = time_column(endpoint, table)

    selects =
      ["count() AS rows"] ++
        Enum.map(integer, fn column -> "sum(#{quote_ident(column)}) AS sum_#{column}" end) ++
        Enum.map(float, fn column -> "round(sum(#{quote_ident(column)}), 4) AS sum_#{column}" end) ++
        if time, do: ["min(#{quote_ident(time)}) AS min_time", "max(#{quote_ident(time)}) AS max_time"], else: []

    statement =
      "SELECT #{Enum.join(selects, ", ")} FROM #{quote_ident(endpoint.database)}.#{quote_ident(table)}#{final_clause(endpoint, table)}"

    %{rows: [values]} = endpoint.repo.query!(statement, [], log: false)
    selects |> Enum.map(&label/1) |> Enum.zip(values) |> Map.new()
  rescue
    error -> %{error: Exception.message(error)}
  end

  # `FINAL` is only valid on an engine that deduplicates, and applying it to a
  # plain MergeTree is an error rather than a no-op.
  defp final_clause(endpoint, table) do
    %{rows: rows} =
      endpoint.repo.query!(
        "SELECT engine FROM system.tables WHERE database = {database:String} AND name = {table:String}",
        %{"database" => endpoint.database, "table" => table},
        log: false
      )

    case rows do
      [[engine]] -> if String.contains?(engine, ["Replacing", "Collapsing"]), do: " FINAL", else: ""
      _ -> ""
    end
  end

  defp numeric_columns(endpoint, table) do
    %{rows: rows} =
      endpoint.repo.query!(
        """
        SELECT name, type FROM system.columns
        WHERE database = {database:String} AND table = {table:String}
          AND (type LIKE 'UInt%' OR type LIKE 'Int%' OR type LIKE 'Float%'
               OR type LIKE 'Nullable(UInt%' OR type LIKE 'Nullable(Int%' OR type LIKE 'Nullable(Float%')
        ORDER BY position
        """,
        %{"database" => endpoint.database, "table" => table},
        log: false
      )

    {float, integer} = Enum.split_with(rows, fn [_name, type] -> String.contains?(type, "Float") end)

    {Enum.map(integer, &hd/1), Enum.map(float, &hd/1)}
  end

  defp time_column(endpoint, table) do
    %{rows: rows} =
      endpoint.repo.query!(
        """
        SELECT name FROM system.columns
        WHERE database = {database:String} AND table = {table:String}
          AND name IN ('inserted_at', 'ran_at', 'ingested_at', 'window_start', 'ts', 'created_at')
        ORDER BY position
        """,
        %{"database" => endpoint.database, "table" => table},
        log: false
      )

    case List.flatten(rows) do
      [] -> nil
      [column | _] -> column
    end
  end

  defp comparable_tables(target) do
    %{rows: rows} =
      target.repo.query!(
        """
        SELECT name FROM system.tables
        WHERE database = {database:String}
          AND engine LIKE 'Replicated%'
          AND name NOT LIKE '.inner%'
          AND name != 'schema_migrations'
        ORDER BY name
        """,
        %{"database" => target.database},
        log: false
      )

    List.flatten(rows)
  end

  defp label(select), do: select |> String.split(" AS ") |> List.last()

  defp quote_ident(name), do: Endpoints.quote_ident(name)
end
