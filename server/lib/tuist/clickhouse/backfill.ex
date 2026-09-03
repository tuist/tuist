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
  alias Tuist.Repo

  require Logger

  # First match wins. `inserted_at` is the convention across the ingest
  # tables; the rest are the exceptions, and `command_events` is the reason
  # `ran_at` is here.
  @time_columns ~w(inserted_at ran_at ingested_at window_start ts created_at)

  @hash_buckets 16

  @doc """
  Copies every table the destination has, oldest chunk first.

  Only tables that already exist on the destination are considered, so the
  schema clone is a hard prerequisite: this will not create anything.
  """
  def run(opts \\ []) do
    Endpoints.with_repos(opts, fn source, target ->
      tables = Keyword.get_lazy(opts, :tables, fn -> destination_tables(target) end)

      Logger.info("Backfilling #{length(tables)} table(s) from #{source.database} into #{target.database}")

      results = Enum.map(tables, fn table -> {table, backfill_table(source, target, table)} end)

      {:ok, Map.new(results)}
    end)
  end

  defp backfill_table(source, target, table) do
    chunks = chunks_for(source, table)
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
        target.repo.query!(statement, params, timeout: to_timeout(minute: 30), log: false)

        source_rows = count(source, table, chunk)
        destination_rows = count(target, table, chunk)
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

  # Divides by month over a time column, or by a hash of the sorting key when
  # the table has none.
  defp chunks_for(source, table) do
    case time_column(source, table) do
      nil ->
        key = sorting_key(source, table)
        Enum.map(0..(@hash_buckets - 1), &{:hash, key, &1, @hash_buckets})

      column ->
        case bounds(source, table, column) do
          {nil, nil} -> []
          {from, to} -> month_chunks(column, from, to)
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
  The half-open monthly intervals covering `from` through `to`.

  Public because chunk boundaries are the part of this module that silently
  loses or duplicates rows when wrong, and that is worth testing without a
  ClickHouse to talk to. An overlap double counts; a gap drops rows that no
  later run will look for, because the ledger will say the neighbouring chunks
  are done.
  """
  def month_chunks(column, from, to) do
    from
    |> Stream.iterate(&add_month/1)
    |> Stream.take_while(&(Date.compare(&1, to) != :gt))
    |> Enum.map(&{:month, column, &1, add_month(&1)})
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
  def predicate({:month, column, from, to}) do
    "#{quote_ident(column)} >= toDateTime64('#{from} 00:00:00', 6) AND #{quote_ident(column)} < toDateTime64('#{to} 00:00:00', 6)"
  end

  def predicate({:hash, key, bucket, buckets}) do
    "cityHash64(#{key}) % #{buckets} = #{bucket}"
  end

  defp count(endpoint, table, chunk) do
    result =
      endpoint.repo.query!(
        "SELECT count() FROM #{quote_ident(endpoint.database)}.#{quote_ident(table)} WHERE #{predicate(chunk)}",
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
  defp chunk_key({:month, _column, from, to}) do
    {DateTime.new!(from, ~T[00:00:00]), DateTime.new!(to, ~T[00:00:00])}
  end

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

  defp destination_tables(target) do
    result =
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

    List.flatten(result.rows)
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

  defp quote_ident(name), do: "`" <> String.replace(to_string(name), "`", "``") <> "`"
end
