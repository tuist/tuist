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

  ## Why the newest rows are excluded

  Both servers are taking live writes, and the two sides of a comparison are
  read one after the other, so a row that arrives in between is on the second
  side and not the first. Every table is therefore compared only up to a
  moment safely in the past, which is what stops a healthy mirror from being
  reported as a difference. Tables with no time column cannot be bounded that
  way; the ones that applies to either collapse duplicates by key or have not
  been written to in months.

  ## Why only the copied tables are a gate

  The tables a materialized view writes into are not transferred. They are
  recomputed on the destination, by the destination's own views, from the rows
  the backfill delivers. Two things follow, and neither is a fault worth
  blocking a migration on. The order differs, so a `ReplacingMergeTree` target
  can keep a different row of a duplicated key than the source kept. And a
  base table with a TTL has since dropped rows that its derived table still
  counts on the source but cannot count again here. So those tables are
  compared and reported, and only the copied ones decide the outcome.
  """

  alias Tuist.ClickHouse.Endpoints
  alias Tuist.ClickHouse.Tables

  require Logger

  @doc """
  Fingerprints every table on the destination and compares it with the source.

  Returns `{:ok, report}` where the report lists matching and differing
  tables, so a caller can gate on `differing == []` rather than reading logs.
  """
  def compare(opts \\ []) do
    Endpoints.with_repos(opts, fn source, target ->
      copied = Keyword.get_lazy(opts, :tables, fn -> Tables.copied(target) end)
      derived = Keyword.get_lazy(opts, :derived, fn -> Tables.derived(target) end)
      as_of = Keyword.get_lazy(opts, :as_of, &default_as_of/0)

      Logger.info("Comparing #{length(copied)} copied and #{length(derived)} derived table(s) as of #{as_of}")

      {matching, differing} = split(source, target, copied, as_of)
      {derived_matching, derived_differing} = split(source, target, derived, as_of)

      report = %{
        compared: length(copied),
        matching: Enum.map(matching, & &1.table),
        differing: Enum.map(differing, &Map.delete(&1, :matches)),
        derived: %{
          compared: length(derived),
          matching: Enum.map(derived_matching, & &1.table),
          differing: Enum.map(derived_differing, &Map.delete(&1, :matches))
        }
      }

      if report.differing == [] do
        Logger.info("ClickHouse parity: all #{report.compared} copied table(s) agree")
      else
        Logger.error("ClickHouse parity: #{length(report.differing)} of #{report.compared} copied table(s) differ")
      end

      if report.derived.differing != [] do
        # Reported with both fingerprints rather than by name. These tables are
        # recomputed rather than copied, so some difference is expected, and
        # the question is only ever how much: a percent on a rebuilt aggregate
        # is the design working, and half the rows is not.
        Logger.warning(
          "ClickHouse parity: #{length(report.derived.differing)} of #{report.derived.compared} derived table(s) differ, which is reported and not a gate: #{inspect(report.derived.differing)}"
        )
      end

      {:ok, report}
    end)
  end

  defp split(source, target, tables, as_of) do
    tables
    |> Enum.map(fn table ->
      left = fingerprint(source, table, as_of)
      right = fingerprint(target, table, as_of)

      %{table: table, source: left, destination: right, matches: left == right}
    end)
    |> Enum.split_with(& &1.matches)
  end

  # Far enough back that a write in flight when the comparison started has
  # certainly landed on both servers, and near enough that the mirror is being
  # judged on current traffic rather than on history.
  defp default_as_of do
    DateTime.utc_now() |> DateTime.add(-5, :minute) |> DateTime.truncate(:second)
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
  defp fingerprint(endpoint, table, as_of) do
    {integer, float} = numeric_columns(endpoint, table)
    time = time_column(endpoint, table)

    selects =
      ["count() AS rows"] ++
        Enum.map(integer, fn column -> "sum(#{quote_ident(column)}) AS sum_#{column}" end) ++
        Enum.map(float, fn column -> "round(sum(#{quote_ident(column)}), 4) AS sum_#{column}" end) ++
        if time, do: ["min(#{quote_ident(time)}) AS min_time", "max(#{quote_ident(time)}) AS max_time"], else: []

    statement =
      "SELECT #{Enum.join(selects, ", ")} FROM #{quote_ident(endpoint.database)}.#{quote_ident(table)}#{Tables.final_clause(endpoint, table)}#{cutoff_clause(time, as_of)}"

    %{rows: [values]} = endpoint.repo.query!(statement, [], log: false)
    selects |> Enum.map(&label/1) |> Enum.zip(values) |> Map.new()
  rescue
    error -> %{error: Exception.message(error)}
  end

  defp cutoff_clause(nil, _as_of), do: ""

  defp cutoff_clause(time, as_of) do
    stamp = as_of |> DateTime.to_naive() |> NaiveDateTime.to_string()

    " WHERE #{quote_ident(time)} < toDateTime64('#{stamp}', 6)"
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

  defp label(select), do: select |> String.split(" AS ") |> List.last()

  defp quote_ident(name), do: Endpoints.quote_ident(name)
end
