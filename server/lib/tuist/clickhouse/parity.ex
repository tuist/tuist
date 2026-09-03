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

  alias Tuist.ClickHouse.SchemaClone

  require Logger

  @doc """
  Fingerprints every table on the destination and compares it with the source.

  Returns `{:ok, report}` where the report lists matching and differing
  tables, so a caller can gate on `differing == []` rather than reading logs.
  """
  def compare(opts \\ []) do
    source_url = Keyword.get_lazy(opts, :source_url, fn -> Tuist.Environment.clickhouse_url() end)
    target_url = Keyword.get_lazy(opts, :target_url, fn -> Tuist.Environment.clickhouse_bare_metal_url() end)

    cond do
      is_nil(target_url) or target_url == "" ->
        {:error, :no_target_configured}

      is_nil(source_url) or source_url == "" ->
        {:error, :no_source_configured}

      true ->
        do_compare(
          SchemaClone.parse_url!(source_url, "source"),
          SchemaClone.parse_url!(target_url, "target"),
          opts
        )
    end
  end

  defp do_compare(source, target, opts) do
    {:ok, source_conn} = connect(source)
    {:ok, target_conn} = connect(target)

    tables = Keyword.get_lazy(opts, :tables, fn -> comparable_tables(target_conn, target.database) end)

    rows =
      Enum.map(tables, fn table ->
        left = fingerprint(source_conn, source.database, table)
        right = fingerprint(target_conn, target.database, table)

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
  end

  # A count, the time bounds, and a sum over every numeric column. The sum is
  # what catches a copy that moved the right number of rows with the wrong
  # values in them, which a count cannot see.
  defp fingerprint(conn, database, table) do
    numeric = numeric_columns(conn, database, table)
    time = time_column(conn, database, table)

    selects =
      ["count() AS rows"] ++
        Enum.map(numeric, fn column -> "sum(toFloat64OrZero(toString(#{quote_ident(column)}))) AS sum_#{column}" end) ++
        if time, do: ["min(#{quote_ident(time)}) AS min_time", "max(#{quote_ident(time)}) AS max_time"], else: []

    statement =
      "SELECT #{Enum.join(selects, ", ")} FROM #{quote_ident(database)}.#{quote_ident(table)}#{final_clause(conn, database, table)}"

    case Ch.query(conn, statement) do
      {:ok, %{rows: [values]}} -> selects |> Enum.map(&label/1) |> Enum.zip(values) |> Map.new()
      {:error, error} -> %{error: Exception.message(error)}
    end
  end

  # `FINAL` is only valid on an engine that deduplicates, and applying it to a
  # plain MergeTree is an error rather than a no-op.
  defp final_clause(conn, database, table) do
    {:ok, %{rows: rows}} =
      Ch.query(
        conn,
        "SELECT engine FROM system.tables WHERE database = {database:String} AND name = {table:String}",
        %{"database" => database, "table" => table}
      )

    case rows do
      [[engine]] -> if String.contains?(engine, ["Replacing", "Collapsing"]), do: " FINAL", else: ""
      _ -> ""
    end
  end

  defp numeric_columns(conn, database, table) do
    {:ok, %{rows: rows}} =
      Ch.query(
        conn,
        """
        SELECT name FROM system.columns
        WHERE database = {database:String} AND table = {table:String}
          AND (type LIKE 'UInt%' OR type LIKE 'Int%' OR type LIKE 'Float%'
               OR type LIKE 'Nullable(UInt%' OR type LIKE 'Nullable(Int%' OR type LIKE 'Nullable(Float%')
        ORDER BY position
        """,
        %{"database" => database, "table" => table}
      )

    List.flatten(rows)
  end

  defp time_column(conn, database, table) do
    {:ok, %{rows: rows}} =
      Ch.query(
        conn,
        """
        SELECT name FROM system.columns
        WHERE database = {database:String} AND table = {table:String}
          AND name IN ('inserted_at', 'ran_at', 'ingested_at', 'window_start', 'ts', 'created_at')
        ORDER BY position
        """,
        %{"database" => database, "table" => table}
      )

    case List.flatten(rows) do
      [] -> nil
      [column | _] -> column
    end
  end

  defp comparable_tables(conn, database) do
    {:ok, %{rows: rows}} =
      Ch.query(
        conn,
        """
        SELECT name FROM system.tables
        WHERE database = {database:String}
          AND engine LIKE 'Replicated%'
          AND name NOT LIKE '.inner%'
          AND name != 'schema_migrations'
        ORDER BY name
        """,
        %{"database" => database}
      )

    List.flatten(rows)
  end

  defp label(select), do: select |> String.split(" AS ") |> List.last()

  defp connect(endpoint) do
    Ch.start_link(
      scheme: endpoint.scheme,
      hostname: endpoint.hostname,
      port: endpoint.port,
      database: endpoint.database,
      username: endpoint.username,
      password: endpoint.password,
      timeout: to_timeout(minute: 10)
    )
  end

  defp quote_ident(name), do: "`" <> String.replace(to_string(name), "`", "``") <> "`"
end
