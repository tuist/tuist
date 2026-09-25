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
  So are tables whose window would still read more than a billion rows, as
  ClickHouse estimates it before reading anything. A time filter only saves
  reads when the table's partitions, primary key or skip indexes are built on
  that column; otherwise the "window" is the whole table, which for
  `build_files` on production is 26 billion rows.

  ## Why the newest rows are excluded

  Both servers are taking live writes, and the two sides of a comparison are
  read one after the other, so a row that arrives in between is on the second
  side and not the first. Every table is therefore compared only up to a
  moment safely in the past, which is what stops a healthy mirror from being
  reported as a difference. Tables with no time column cannot be bounded that
  way; the ones that applies to either collapse duplicates by key or have not
  been written to in months.

  ## Why rows close to their TTL are left out

  A table with a TTL deletes expired rows only when a merge reaches them, and
  the two servers merge on their own schedules, so for a while one of them
  still holds rows the other has already dropped. Counting those fails a table
  whose data agrees. Both sides are therefore compared only over the rows that
  are more than a day from expiring.

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

  # How long one fingerprint may run, in seconds, enforced by the server so a
  # slow one fails there with TIMEOUT_EXCEEDED. The client waits longer than
  # that, and does not retry: when the client gives up first, the driver asks
  # DBConnection to retry on a fresh connection, and ClickHouse keeps running
  # every abandoned read to the end. That turned one slow fingerprint into four
  # concurrent full scans of the same table.
  #
  # A windowed run only compares tables whose window is small, so the recurring
  # check gets the short ceiling. A full comparison sums every row of the
  # largest tables and gets the long one.
  @windowed_max_execution_time 120
  @full_max_execution_time 1800

  # The most rows a windowed fingerprint may read. Production's tables read in
  # a couple of seconds up to about a billion rows; the four above it took
  # between 40 seconds and 8 minutes each.
  @windowed_max_rows 1_000_000_000

  @doc """
  Fingerprints every table on the destination and compares it with the source.

  Returns `{:ok, report}` where the report lists matching and differing
  tables, so a caller can gate on `differing == []` rather than reading logs.
  Its `migrations` entry lists the `schema_migrations` versions each server
  holds and the other does not.
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
      migrations = migration_drift(source, target)

      {matching, differing, skipped} = split(source, target, copied, since, as_of)
      {derived_matching, derived_differing, _} = split(source, target, derived, since, as_of)

      report = %{
        compared: length(copied) - length(skipped),
        skipped: skipped,
        schema: drift,
        migrations: migrations,
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

      if migrations.missing_on_destination != [] or migrations.only_on_destination != [] do
        Logger.error("ClickHouse schema_migrations drift: #{inspect(migrations)}")
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

  defp migration_drift(source, target) do
    left = migration_versions(source)
    right = migration_versions(target)

    %{
      missing_on_destination: left |> MapSet.difference(right) |> Enum.sort(),
      only_on_destination: right |> MapSet.difference(left) |> Enum.sort()
    }
  end

  defp migration_versions(endpoint) do
    statement = "SELECT DISTINCT version FROM #{quote_ident(endpoint.database)}.schema_migrations"
    %{rows: rows} = endpoint.repo.query!(statement, [], log: false)

    rows |> List.flatten() |> MapSet.new()
  end

  defp split(source, target, tables, since, as_of) do
    # A windowed run can only speak for tables it can bound, so the ones it
    # cannot are reported as skipped rather than silently compared in full,
    # which would make an hourly check as expensive as a full one.
    {comparable, skipped} =
      if since do
        Enum.split_with(tables, &windowable?(source, target, &1, since, as_of))
      else
        {tables, []}
      end

    {matching, differing} =
      comparable
      |> Enum.map(fn table ->
        ttl = ttl(target, table)
        left = fingerprint(source, table, since, as_of, ttl)
        right = fingerprint(target, table, since, as_of, ttl)

        # Two fingerprints that failed identically are not a match. Without
        # this, a comparison where both sides timed out reports `differing:
        # []`, and a check that verified nothing would clear a cutover.
        %{
          table: table,
          source: left,
          destination: right,
          matches: verified?(left) and verified?(right) and same_fingerprint?(left, right)
        }
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
  # Integer addition is exact and order-independent, so `sum` over an integer
  # column is a fingerprint. Floating-point addition is neither: the two
  # servers hold the same rows in different parts and add them in different
  # orders, so a float sum differs in its last bits for data that is identical.
  # Those are compared within a relative tolerance in `same_fingerprint?/2`.
  defp fingerprint(endpoint, table, since, as_of, ttl) do
    {selects, statement} = fingerprint_statement(endpoint, table, since, as_of, ttl)
    max_execution_time = if since, do: @windowed_max_execution_time, else: @full_max_execution_time

    %{rows: [values]} =
      endpoint.repo.query!(statement, [],
        settings: [max_memory_usage: @max_memory_usage, max_execution_time: max_execution_time],
        timeout: to_timeout(second: max_execution_time + 60),
        checkout_retries: 0,
        log: false
      )

    selects |> Enum.map(&label/1) |> Enum.zip(values) |> Map.new()
  rescue
    error -> %{error: Exception.message(error)}
  end

  defp fingerprint_statement(endpoint, table, since, as_of, ttl) do
    {integer, float} = numeric_columns(endpoint, table)
    time = time_column(endpoint, table)

    selects =
      ["count() AS rows"] ++
        Enum.map(integer ++ float, fn column -> "sum(#{quote_ident(column)}) AS sum_#{column}" end) ++
        if time, do: ["min(#{quote_ident(time)}) AS min_time", "max(#{quote_ident(time)}) AS max_time"], else: []

    statement =
      "SELECT #{Enum.join(selects, ", ")} FROM #{quote_ident(endpoint.database)}.#{quote_ident(table)}#{Tables.final_clause(endpoint, table)}#{window_clause(time, since, as_of, ttl)}"

    {selects, statement}
  end

  defp verified?(%{error: _}), do: false
  defp verified?(_fingerprint), do: true

  @doc """
  Whether two fingerprints describe the same rows.

  Float sums are equal when they agree to within a part in a trillion. Rounding
  to a fixed number of decimals does not work for them: a double carries about
  16 significant digits, so a sum around 10^12 has none left for the fourth
  decimal, and two sums of the same rows on production differed there by a
  part in 10^15. A relative bound sits the same distance above that noise
  whatever the magnitude.
  """
  def same_fingerprint?(left, right) do
    map_size(left) == map_size(right) and
      Enum.all?(left, fn {key, value} ->
        case Map.fetch(right, key) do
          {:ok, other} -> same_value?(value, other)
          :error -> false
        end
      end)
  end

  defp same_value?(left, right) when is_float(left) and is_float(right),
    do: abs(left - right) <= 1.0e-12 * max(abs(left), abs(right))

  defp same_value?(left, right), do: left == right

  # Whether a table's window is small enough for the recurring check. Asked of
  # the source, which holds every row the destination does and is the server
  # whose load matters, and answered by ClickHouse's own index analysis:
  # partitions, primary key and skip indexes, before anything is read.
  #
  # A table the source cannot estimate, typically one only the destination
  # has, is compared anyway, so the fingerprint fails and reports it as a
  # difference rather than the whole comparison failing on the estimate.
  defp windowable?(source, target, table, since, as_of) do
    if time_column(target, table) do
      {_selects, statement} = fingerprint_statement(source, table, since, as_of, ttl(target, table))

      case estimated_rows(source, statement) do
        {:ok, rows} -> rows <= @windowed_max_rows
        {:error, _reason} -> true
      end
    else
      false
    end
  end

  defp estimated_rows(endpoint, statement) do
    with {:ok, %{columns: columns, rows: rows}} <- endpoint.repo.query("EXPLAIN ESTIMATE " <> statement, [], log: false) do
      index = Enum.find_index(columns, &(&1 == "rows"))
      {:ok, rows |> Enum.map(&Enum.at(&1, index)) |> Enum.sum()}
    end
  end

  defp window_clause(time, since, as_of, ttl) do
    conditions =
      Enum.reject(
        [
          time && since && "#{quote_ident(time)} >= toDateTime64('#{stamp(since)}', 6)",
          time && "#{quote_ident(time)} < toDateTime64('#{stamp(as_of)}', 6)",
          ttl && "(#{ttl}) > toDateTime64('#{stamp(as_of)}', 6) + INTERVAL 1 DAY"
        ],
        &(&1 in [nil, false])
      )

    if conditions == [], do: "", else: " WHERE " <> Enum.join(conditions, " AND ")
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

  defp ttl(endpoint, table) do
    %{rows: rows} =
      endpoint.repo.query!(
        "SELECT engine_full FROM system.tables WHERE database = {database:String} AND name = {table:String}",
        %{"database" => endpoint.database, "table" => table},
        log: false
      )

    case rows do
      [[engine_full]] when is_binary(engine_full) -> ttl_expression(engine_full)
      _ -> nil
    end
  end

  @doc """
  The expression a table's TTL deletes rows by, read from its `engine_full`, or
  `nil` when it has no TTL or its TTL does more than delete rows by a single
  expression.

  Public because it parses ClickHouse's own description of a table, and a
  wrong parse is silent: the table goes back to being compared over rows each
  server deletes on its own schedule.
  """
  def ttl_expression(engine_full) do
    with [_, clause] <- Regex.run(~r/\sTTL\s+(.+?)(?:\s+SETTINGS\s|$)/, engine_full),
         expression = String.replace(clause, ~r/\s+DELETE$/i, ""),
         false <- String.contains?(expression, ","),
         false <- Regex.match?(~r/\s(TO|GROUP BY|WHERE|SET|RECOMPRESS)\s/i, " #{expression} ") do
      expression
    else
      _ -> nil
    end
  end

  defp label(select), do: select |> String.split(" AS ") |> List.last()

  defp quote_ident(name), do: Endpoints.quote_ident(name)
end
