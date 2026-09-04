defmodule Tuist.ClickHouse.Backfill do
  @moduledoc """
  Copies existing rows from the ClickHouse that is the system of record onto
  the in-cluster one, chunk by chunk, resumably (spec #73).

  ## How the rows move

  The destination pulls, using ClickHouse's own `remoteSecure` table function,
  rather than the rows being streamed through the application. Two reasons.
  The copy stays inside ClickHouse, so it runs at the servers' pace instead of
  the BEAM's and does not hold a connection open per chunk in the web pods.
  And the destination is the only side that has to be reachable from the
  other, which is the direction that already works: the bare-metal node has
  public egress, while nothing outside the cluster can reach it.

  ## Why there is a ledger

  `INSERT ... SELECT` is not idempotent. Re-running a chunk against a
  `MergeTree` duplicates its rows, and a `ReplacingMergeTree` collapses them
  only on a merge that may not have run yet, so a naive retry silently inflates
  counts. Progress is therefore recorded in Postgres, which is neither the
  source nor the destination of the copy and so survives the failures that
  make resuming necessary.

  ## Why a chunk is cleared before it is copied

  The copy is authoritative for its range rather than additive to it: each
  chunk deletes the destination's rows for that range before inserting the
  source's. This is what makes the boundary with the dual write exact even
  though the deploy that switches dual writes on has both old and new pods
  writing for a moment. See `clear_destination/3`.

  ## Where the copy stops

  The backfill is the second half of the cutover, not the first. Shadow writes
  are switched on first, and from that instant every new row reaches both
  servers; the backfill then copies what was written before it. So it needs to
  know that instant, and it is given it rather than guessing: a bound taken
  when the backfill starts would copy rows the dual write had already
  delivered, and no bound at all would leave the rows written between the two
  steps on the source alone. Tables with no time column cannot be bounded this
  way, and are copied whole; see `chunks_for/3` for why that is safe for the
  few tables it applies to.

  ## How a table is divided

  By month over a time column when the table has one, which is also how most
  of these tables are partitioned, so a chunk maps onto whole parts. Tables
  with no usable time column, of which `build_files` is the large one, are
  divided by a hash of the sorting key instead. Both give deterministic,
  half-open intervals, so two adjacent chunks cannot claim the same row and a
  resumed run cannot skip one.
  """

  import Ecto.Query

  alias Tuist.ClickHouse.Endpoints
  alias Tuist.ClickHouse.Tables
  alias Tuist.Environment
  alias Tuist.Repo

  require Logger

  # First match wins, and the order is write time before event time. The
  # cutoff divides rows by when they were written, so a column recording when
  # something happened is the wrong one to bound by: `command_events` carries
  # both, and a run that started before the cutoff can be reported minutes
  # after it, which would put the row on both sides of the boundary.
  @time_columns ~w(inserted_at created_at ingested_at ts window_start ran_at)

  @hash_buckets 16

  @doc """
  Copies every table the destination has, oldest chunk first.

  Only tables that already exist on the destination are considered, so the
  schema clone is a hard prerequisite: this will not create anything.
  """
  def run(opts \\ []) do
    Endpoints.with_repos(opts, fn source, target ->
      case Keyword.get_lazy(opts, :cutoff, &Environment.clickhouse_backfill_cutoff/0) do
        nil ->
          {:error, :no_cutoff_configured}

        cutoff ->
          tables = Keyword.get_lazy(opts, :tables, fn -> Tables.copied(target) end)

          Logger.info(
            "Backfilling #{length(tables)} table(s) from #{source.database} into #{target.database}, up to #{DateTime.to_iso8601(cutoff)}"
          )

          results = Enum.map(tables, fn table -> {table, backfill_table(source, target, table, cutoff)} end)

          {:ok, Map.new(results)}
      end
    end)
  end

  defp backfill_table(source, target, table, cutoff) do
    chunks = chunks_for(source, table, cutoff)
    Logger.info("#{table}: #{length(chunks)} chunk(s)")

    Enum.reduce(chunks, %{copied: 0, skipped: 0, failed: 0}, fn chunk, acc ->
      case copy_chunk(source, target, table, chunk) do
        :already_done -> %{acc | skipped: acc.skipped + 1}
        :ok -> %{acc | copied: acc.copied + 1}
        {:error, _} -> %{acc | failed: acc.failed + 1}
      end
    end)
  end

  defp copy_chunk(source, target, table, chunk) do
    if chunk_done?(table, chunk) do
      :already_done
    else
      claim_chunk(table, chunk)

      # The credentials are query parameters rather than interpolated text, so
      # the statement carries no secret even if something logs it. `log: false`
      # as well, because a driver-level error can echo the parameters too.
      statement = """
      INSERT INTO #{quote_ident(target.database)}.#{quote_ident(table)}
      SELECT * FROM remoteSecure({address:String}, {database:String}, {table:String}, {user:String}, {password:String})
      WHERE #{predicate(chunk)}
      """

      params = %{
        "address" => source_address(source),
        "database" => source.database,
        "table" => table,
        "user" => source_credential(source, :username),
        "password" => source_credential(source, :password)
      }

      try do
        clear_destination(target, table, chunk)
        target.repo.query!(statement, params, timeout: to_timeout(minute: 30), log: false)

        {source_rows, destination_rows} = verify(source, target, table, chunk)
        finish_chunk(table, chunk, source_rows, destination_rows)

        if source_rows == destination_rows do
          :ok
        else
          # Recorded rather than raised: one mismatched chunk should not stop
          # the run, and the parity report is what gates the stage.
          Logger.error("#{table} #{inspect(chunk)}: source #{source_rows} rows, destination #{destination_rows}")
          :ok
        end
      rescue
        error ->
          fail_chunk(table, chunk, Exception.message(error))
          Logger.error("#{table} #{inspect(chunk)} failed: #{Exception.message(error)}")
          {:error, Exception.message(error)}
      end
    end
  end

  # Divides by month over a time column up to the cutoff, or by a hash of the
  # sorting key when the table has none.
  #
  # A hash-divided table is copied whole, because there is no column to bound
  # it by. That is safe for the tables it applies to and not by luck: they are
  # `runner_jobs`, which is a `ReplacingMergeTree` keyed on the job id and so
  # collapses a row delivered twice, and four `test_case_runs_recent_*` tables
  # that no materialized view feeds and nothing has written to since July.
  # A new table with no time column would not be covered by either argument,
  # which is what the log line is for.
  defp chunks_for(source, table, cutoff) do
    case time_column(source, table) do
      nil ->
        Logger.info("#{table}: no time column, copying whole")
        key = sorting_key(source, table)
        Enum.map(0..(@hash_buckets - 1), &{:hash, key, &1, @hash_buckets})

      column ->
        case bounds(source, table, column) do
          {nil, nil} -> []
          {from, to} -> month_chunks(column, from, to, cutoff)
        end
    end
  end

  defp time_column(source, table) do
    result =
      source.repo.query!(
        """
        SELECT name FROM system.columns
        WHERE database = {database:String} AND table = {table:String} AND name IN {names:Array(String)}
        """,
        %{"database" => source.database, "table" => table, "names" => @time_columns},
        log: false
      )

    present = List.flatten(result.rows)
    Enum.find(@time_columns, &(&1 in present))
  end

  defp sorting_key(source, table) do
    result =
      source.repo.query!(
        "SELECT sorting_key FROM system.tables WHERE database = {database:String} AND name = {table:String}",
        %{"database" => source.database, "table" => table},
        log: false
      )

    case result.rows do
      [[key]] when is_binary(key) and key != "" -> key |> String.split(",") |> hd() |> String.trim()
      _ -> "1"
    end
  end

  defp bounds(source, table, column) do
    result =
      source.repo.query!(
        "SELECT toStartOfMonth(min(#{quote_ident(column)})), toStartOfMonth(max(#{quote_ident(column)})) FROM #{quote_ident(source.database)}.#{quote_ident(table)}",
        [],
        log: false
      )

    case result.rows do
      [[from, to]] -> {from, to}
      _ -> {nil, nil}
    end
  end

  @doc """
  The half-open intervals covering `from` through `to`, one per month, ending
  at `cutoff`.

  Public because chunk boundaries are the part of this module that silently
  loses or duplicates rows when wrong, and that is worth testing without a
  ClickHouse to talk to. An overlap double counts; a gap drops rows that no
  later run will look for, because the ledger will say the neighbouring chunks
  are done.

  The month holding the cutoff is emitted as a partial interval, since the
  cutover cannot wait for a month boundary to come round.
  """
  def month_chunks(column, from, to, cutoff) do
    from
    |> Stream.iterate(&add_month/1)
    |> Stream.take_while(&(Date.compare(&1, to) != :gt))
    |> Enum.flat_map(&clip(column, &1, add_month(&1), cutoff))
  end

  defp clip(column, from, to, cutoff) do
    start = DateTime.new!(from, ~T[00:00:00])
    finish = DateTime.new!(to, ~T[00:00:00])

    cond do
      DateTime.compare(start, cutoff) != :lt -> []
      DateTime.compare(finish, cutoff) != :gt -> [{:range, column, start, finish}]
      true -> [{:range, column, start, cutoff}]
    end
  end

  defp add_month(%Date{} = date) do
    date |> Date.beginning_of_month() |> Date.add(Date.days_in_month(date)) |> Date.beginning_of_month()
  end

  @doc """
  The `WHERE` clause selecting a chunk, used identically for the copy and for
  both sides' row counts. One function on purpose: if the copy and the count
  could disagree about which rows a chunk holds, the parity check would be
  comparing different things and would pass while the data diverged.
  """
  def predicate({:range, column, from, to}) do
    "#{quote_ident(column)} >= toDateTime64('#{stamp(from)}', 6) AND #{quote_ident(column)} < toDateTime64('#{stamp(to)}', 6)"
  end

  def predicate({:hash, key, bucket, buckets}) do
    "cityHash64(#{key}) % #{buckets} = #{bucket}"
  end

  # Makes the copy authoritative for its range rather than additive to it.
  #
  # A rolling deploy is what switches dual writes on, and during it the old
  # pods and the new ones write at the same time, so there is a window whose
  # rows reached the destination only if the pod that wrote them had already
  # restarted. No single cutoff can describe that window: put it before and
  # the rows the old pods wrote are lost, put it after and the rows the new
  # ones mirrored are copied twice. Deleting the destination's rows for a
  # chunk before copying it settles the question, because the system of record
  # holds every row in that range either way.
  #
  # The count is what keeps this cheap. The destination is empty for all but
  # the last chunk or two of each table, and a mutation is only worth issuing
  # where there is something to remove. It also makes re-running a chunk safe
  # on any engine, so the ledger is an optimisation rather than the thing
  # standing between a retry and duplicated rows.
  defp clear_destination(target, table, chunk) do
    if count(target, table, chunk) > 0 do
      Logger.info("#{table} #{inspect(chunk)}: clearing the destination's rows before copying")

      target.repo.query!(
        "ALTER TABLE #{quote_ident(target.database)}.#{quote_ident(table)} DELETE WHERE #{predicate(chunk)}",
        [],
        settings: [mutations_sync: 2],
        timeout: to_timeout(minute: 30),
        log: false
      )
    end
  end

  # Raw counts first, and only if they disagree are both sides counted again
  # through `FINAL`.
  #
  # `FINAL` is what makes the comparison meaningful, because the two servers
  # merge on their own schedules and a table that has just been written is not
  # comparable with one that has been sitting there. But it is also what makes
  # it expensive: on a table the size of production's it merges the chunk's
  # parts at read time, twice per chunk, for a question that almost always has
  # the same answer either way.
  defp verify(source, target, table, chunk) do
    source_rows = count(source, table, chunk)
    destination_rows = count(target, table, chunk)

    if source_rows == destination_rows do
      {source_rows, destination_rows}
    else
      {count(source, table, chunk, collapsed: true), count(target, table, chunk, collapsed: true)}
    end
  end

  defp count(endpoint, table, chunk, opts \\ []) do
    final = if Keyword.get(opts, :collapsed, false), do: Tables.final_clause(endpoint, table), else: ""

    result =
      endpoint.repo.query!(
        "SELECT count() FROM #{quote_ident(endpoint.database)}.#{quote_ident(table)}#{final} WHERE #{predicate(chunk)}",
        [],
        log: false
      )

    case result.rows do
      [[n]] -> n
      _ -> 0
    end
  end

  # The ledger is keyed on a time interval, so a hash chunk is mapped onto a
  # synthetic one. It never has to be interpreted as a date, only matched.
  defp chunk_key({:range, _column, from, to}), do: {from, to}

  defp chunk_key({:hash, _key, bucket, buckets}) do
    epoch = ~D[1970-01-01]

    {DateTime.new!(Date.add(epoch, bucket), ~T[00:00:00]), DateTime.new!(Date.add(epoch, buckets), ~T[00:00:00])}
  end

  defp chunk_done?(table, chunk) do
    {from, to} = chunk_key(chunk)

    Repo.exists?(
      from c in "clickhouse_backfill_chunks",
        where:
          c.table_name == ^table and c.chunk_start == ^from and c.chunk_end == ^to and
            c.status == "done"
    )
  end

  defp claim_chunk(table, chunk) do
    {from, to} = chunk_key(chunk)
    now = DateTime.truncate(DateTime.utc_now(), :second)

    Repo.insert_all(
      "clickhouse_backfill_chunks",
      [
        [
          table_name: table,
          chunk_start: from,
          chunk_end: to,
          status: "running",
          started_at: now,
          inserted_at: now,
          updated_at: now
        ]
      ],
      on_conflict: {:replace, [:status, :started_at, :updated_at, :error]},
      conflict_target: [:table_name, :chunk_start, :chunk_end]
    )
  end

  defp finish_chunk(table, chunk, source_rows, destination_rows) do
    update_chunk(table, chunk,
      status: "done",
      source_rows: source_rows,
      destination_rows: destination_rows,
      error: nil,
      finished_at: DateTime.truncate(DateTime.utc_now(), :second)
    )
  end

  defp fail_chunk(table, chunk, message) do
    update_chunk(table, chunk,
      status: "failed",
      error: message,
      finished_at: DateTime.truncate(DateTime.utc_now(), :second)
    )
  end

  defp update_chunk(table, chunk, fields) do
    {from, to} = chunk_key(chunk)
    fields = Keyword.put(fields, :updated_at, DateTime.truncate(DateTime.utc_now(), :second))

    Repo.update_all(
      from(c in "clickhouse_backfill_chunks",
        where: c.table_name == ^table and c.chunk_start == ^from and c.chunk_end == ^to
      ),
      set: fields
    )
  end

  # `remoteSecure` speaks the native protocol, which is a different port from
  # the HTTP interface the repository is configured with.
  defp source_address(source) do
    config = source.repo.config()
    "#{Keyword.fetch!(config, :hostname)}:9440"
  end

  defp source_credential(source, key) do
    source.repo.config() |> Keyword.get(key, "") |> to_string()
  end

  defp stamp(%DateTime{} = at),
    do: at |> DateTime.to_naive() |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_string()

  defp quote_ident(name), do: "`" <> String.replace(to_string(name), "`", "``") <> "`"
end
