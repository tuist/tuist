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

  alias Tuist.ClickHouse.SchemaClone
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
    with {:ok, source, target} <- endpoints(opts),
         {:ok, source_conn} <- connect(source),
         {:ok, target_conn} <- connect(target) do
      tables = Keyword.get_lazy(opts, :tables, fn -> destination_tables(target_conn, target.database) end)

      Logger.info("Backfilling #{length(tables)} table(s) from #{source.database} into #{target.database}")

      results =
        Enum.map(tables, fn table ->
          {table, backfill_table(source_conn, target_conn, source, target, table)}
        end)

      {:ok, Map.new(results)}
    end
  end

  defp backfill_table(source_conn, target_conn, source, target, table) do
    chunks = chunks_for(source_conn, source.database, table)
    Logger.info("#{table}: #{length(chunks)} chunk(s)")

    Enum.reduce(chunks, %{copied: 0, skipped: 0, failed: 0}, fn chunk, acc ->
      case copy_chunk(source_conn, target_conn, source, target, table, chunk) do
        :already_done -> %{acc | skipped: acc.skipped + 1}
        :ok -> %{acc | copied: acc.copied + 1}
        {:error, _} -> %{acc | failed: acc.failed + 1}
      end
    end)
  end

  defp copy_chunk(source_conn, target_conn, source, target, table, chunk) do
    if chunk_done?(table, chunk) do
      :already_done
    else
      claim_chunk(table, chunk)

      statement = """
      INSERT INTO #{quote_ident(target.database)}.#{quote_ident(table)}
      SELECT * FROM remoteSecure(#{literal(native_address(source))}, #{literal(source.database)}, #{literal(table)}, #{literal(source.username)}, #{literal(source.password)})
      WHERE #{predicate(chunk)}
      """

      case Ch.query(target_conn, statement, [], timeout: to_timeout(minute: 30)) do
        {:ok, _} ->
          source_rows = count(source_conn, source.database, table, chunk)
          destination_rows = count(target_conn, target.database, table, chunk)
          finish_chunk(table, chunk, source_rows, destination_rows)

          if source_rows == destination_rows do
            :ok
          else
            # Recorded rather than raised: one mismatched chunk should not stop
            # the run, and the parity report is what gates the stage.
            Logger.error("#{table} #{inspect(chunk)}: source #{source_rows} rows, destination #{destination_rows}")
            :ok
          end

        {:error, error} ->
          fail_chunk(table, chunk, Exception.message(error))
          Logger.error("#{table} #{inspect(chunk)} failed: #{Exception.message(error)}")
          {:error, Exception.message(error)}
      end
    end
  end

  # Divides by month over a time column, or by a hash of the sorting key when
  # the table has none.
  defp chunks_for(conn, database, table) do
    case time_column(conn, database, table) do
      nil ->
        key = sorting_key(conn, database, table)
        Enum.map(0..(@hash_buckets - 1), &{:hash, key, &1, @hash_buckets})

      column ->
        case bounds(conn, database, table, column) do
          {nil, nil} -> []
          {from, to} -> month_chunks(column, from, to)
        end
    end
  end

  defp time_column(conn, database, table) do
    {:ok, result} =
      Ch.query(
        conn,
        """
        SELECT name FROM system.columns
        WHERE database = {database:String} AND table = {table:String} AND name IN {names:Array(String)}
        """,
        %{"database" => database, "table" => table, "names" => @time_columns}
      )

    present = List.flatten(result.rows)
    Enum.find(@time_columns, &(&1 in present))
  end

  defp sorting_key(conn, database, table) do
    {:ok, result} =
      Ch.query(
        conn,
        "SELECT sorting_key FROM system.tables WHERE database = {database:String} AND name = {table:String}",
        %{"database" => database, "table" => table}
      )

    case result.rows do
      [[key]] when is_binary(key) and key != "" -> key |> String.split(",") |> hd() |> String.trim()
      _ -> "1"
    end
  end

  defp bounds(conn, database, table, column) do
    {:ok, result} =
      Ch.query(
        conn,
        "SELECT toStartOfMonth(min(#{quote_ident(column)})), toStartOfMonth(max(#{quote_ident(column)})) FROM #{quote_ident(database)}.#{quote_ident(table)}"
      )

    case result.rows do
      [[from, to]] -> {from, to}
      _ -> {nil, nil}
    end
  end

  defp month_chunks(column, from, to) do
    from
    |> Stream.iterate(&add_month/1)
    |> Stream.take_while(&(Date.compare(&1, to) != :gt))
    |> Enum.map(&{:month, column, &1, add_month(&1)})
  end

  defp add_month(%Date{} = date) do
    date |> Date.beginning_of_month() |> Date.add(Date.days_in_month(date)) |> Date.beginning_of_month()
  end

  defp predicate({:month, column, from, to}) do
    "#{quote_ident(column)} >= toDateTime64('#{from} 00:00:00', 6) AND #{quote_ident(column)} < toDateTime64('#{to} 00:00:00', 6)"
  end

  defp predicate({:hash, key, bucket, buckets}) do
    "cityHash64(#{key}) % #{buckets} = #{bucket}"
  end

  defp count(conn, database, table, chunk) do
    {:ok, result} =
      Ch.query(
        conn,
        "SELECT count() FROM #{quote_ident(database)}.#{quote_ident(table)} WHERE #{predicate(chunk)}"
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

  defp destination_tables(conn, database) do
    {:ok, result} =
      Ch.query(
        conn,
        """
        SELECT name FROM system.tables
        WHERE database = {database:String}
          AND engine LIKE 'Replicated%'
          AND name NOT LIKE '.inner%'
          AND name != 'schema_migrations'
        ORDER BY total_bytes ASC
        """,
        %{"database" => database}
      )

    List.flatten(result.rows)
  end

  defp endpoints(opts) do
    source = Keyword.get_lazy(opts, :source_url, fn -> Tuist.Environment.clickhouse_url() end)
    target = Keyword.get_lazy(opts, :target_url, fn -> Tuist.Environment.clickhouse_bare_metal_url() end)

    cond do
      is_nil(target) or target == "" -> {:error, :no_target_configured}
      is_nil(source) or source == "" -> {:error, :no_source_configured}
      true -> {:ok, SchemaClone.parse_url!(source, "source"), SchemaClone.parse_url!(target, "target")}
    end
  end

  defp connect(endpoint) do
    case Ch.start_link(
           scheme: endpoint.scheme,
           hostname: endpoint.hostname,
           port: endpoint.port,
           database: endpoint.database,
           username: endpoint.username,
           password: endpoint.password,
           timeout: to_timeout(minute: 30)
         ) do
      {:ok, conn} -> {:ok, conn}
      {:error, error} -> {:error, {:unreachable, inspect(error)}}
    end
  end

  # `remoteSecure` speaks the native protocol, which is a different port from
  # the HTTP interface the URL names.
  defp native_address(%{hostname: hostname}), do: "#{hostname}:9440"

  defp literal(value), do: "'" <> String.replace(to_string(value), "'", "\\'") <> "'"

  defp quote_ident(name), do: "`" <> String.replace(to_string(name), "`", "``") <> "`"
end
