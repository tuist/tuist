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

  ## Comparing a window rather than everything

  Fingerprinting whole tables is what the backfill has to be judged on, and it
  is far too expensive to repeat on a schedule: summing every numeric column of
  production's largest tables reads the dataset. The recurring check passes a
  `since`, which bounds the comparison to rows written recently, and that is
  also the only part still at risk once the backfill has been verified. A
  mirrored write that is dropped is dropped now, not retroactively.

  Tables with no time column cannot be bounded that way and are skipped when a
  window is given, which is stated in the report rather than left implicit.

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

  # A ceiling for one fingerprint, well below the per-user budget these
  # connections share with the running server (8 GiB in production).
  #
  # That relationship is the whole point, and getting it backwards has already
  # cost a day: an ingest migration once set a per-query ceiling *above* the
  # shared cap, so the ceiling could never bind, the query grew into the pool
  # instead, and the overcommit tracker picked it. That blocked every
  # production deploy until it was fixed. A fingerprint sums every numeric
  # column of a table with `FINAL`, which on the largest ones is the same shape
  # of query, so it gets an explicit ceiling and fails on its own rather than
  # at the expense of the application.
  @max_memory_usage 1024 * 1024 * 1024

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
      since = Keyword.get(opts, :since)

      window = if since, do: " written since #{since}", else: ""
      Logger.info("Comparing #{length(copied)} copied and #{length(derived)} derived table(s)#{window} as of #{as_of}")

      drift = Tables.schema_drift(source, target)

      {matching, differing, skipped} = split(source, target, copied, since, as_of)
      {derived_matching, derived_differing, _} = split(source, target, derived, since, as_of)

      report = %{
        compared: length(copied) - length(skipped),
        skipped: skipped,
        schema: drift,
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

      if drift.missing_on_destination != [] or drift.differing_columns != [] do
        Logger.error(
          "ClickHouse schema drift: #{inspect(Map.take(drift, [:missing_on_destination, :differing_columns]))}"
        )
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

  defp split(source, target, tables, since, as_of) do
    # A windowed run can only speak for tables it can bound, so the ones with
    # no time column are reported as skipped rather than silently compared in
    # full, which would make an hourly check as expensive as a full one.
    {comparable, skipped} =
      if since do
        Enum.split_with(tables, &(time_column(target, &1) != nil))
      else
        {tables, []}
      end

    {matching, differing} =
      comparable
      |> Enum.map(fn table ->
        left = fingerprint(source, table, since, as_of)
        right = fingerprint(target, table, since, as_of)

        %{table: table, source: left, destination: right, matches: left == right}
      end)
      |> Enum.split_with(& &1.matches)

    {matching, differing, skipped}
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
  defp fingerprint(endpoint, table, since, as_of) do
    {integer, float} = numeric_columns(endpoint, table)
    time = time_column(endpoint, table)

    selects =
      ["count() AS rows"] ++
        Enum.map(integer, fn column -> "sum(#{quote_ident(column)}) AS sum_#{column}" end) ++
        Enum.map(float, fn column -> "round(sum(#{quote_ident(column)}), 4) AS sum_#{column}" end) ++
        if time, do: ["min(#{quote_ident(time)}) AS min_time", "max(#{quote_ident(time)}) AS max_time"], else: []

    statement =
      "SELECT #{Enum.join(selects, ", ")} FROM #{quote_ident(endpoint.database)}.#{quote_ident(table)}#{Tables.final_clause(endpoint, table)}#{window_clause(time, since, as_of)}"

    %{rows: [values]} = endpoint.repo.query!(statement, [], settings: [max_memory_usage: @max_memory_usage], log: false)
    selects |> Enum.map(&label/1) |> Enum.zip(values) |> Map.new()
  rescue
    error -> %{error: Exception.message(error)}
  end

  defp window_clause(nil, _since, _as_of), do: ""

  defp window_clause(time, since, as_of) do
    upper = " #{quote_ident(time)} < toDateTime64('#{stamp(as_of)}', 6)"

    if since do
      " WHERE #{quote_ident(time)} >= toDateTime64('#{stamp(since)}', 6) AND#{upper}"
    else
      " WHERE#{upper}"
    end
  end

  defp stamp(at), do: at |> DateTime.to_naive() |> NaiveDateTime.to_string()

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
