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

  ## Why only one may run at a time

  The ledger stops a *finished* chunk being redone; it does not stop two runs
  claiming the same unfinished one. That mattered less when the copy only
  inserted, and matters now that each chunk clears its range first: two runs
  overlapping could have one deleting rows the other had just written. Once
  the copy is a background Job rather than a deploy hook, nothing about how it
  is launched prevents a second one, so the guard belongs here rather than in
  whatever starts it. A Postgres advisory lock is the right shape because it
  is released when the connection holding it goes away, so a Job that is
  killed does not leave the next one locked out.

  ## Why there is a ledger

  `INSERT ... SELECT` is not idempotent. Re-running a chunk against a
  `MergeTree` duplicates its rows, and a `ReplacingMergeTree` collapses them
  only on a merge that may not have run yet, so a naive retry silently inflates
  counts. Progress is therefore recorded in Postgres, which is neither the
  source nor the destination of the copy and so survives the failures that
  make resuming necessary.

  ## Why a re-copy fills gaps rather than replacing a range

  A chunk the destination holds nothing for is copied straight in. A chunk it
  already holds rows for is copied by inserting only the rows it lacks.

  Replacing the range would be simpler, and was what this did first: delete
  the destination's rows for the chunk, then re-copy. That is wrong in a way
  row counts cannot see. A materialized view is an insert trigger, so
  re-inserting a row contributes to its aggregate targets a second time, while
  the delete does not unwind the first, because ClickHouse mutations do not
  propagate to a view's target. The base tables would agree while the
  aggregates behind them inflated, and the parity gate would not catch it,
  since derived tables are reported rather than gated.

  Filling gaps means the views fire exactly once per row, on the copy that
  first delivers it, which is what they would have done had nothing gone
  wrong. It also removes the need to reason about the dual write's boundary
  separately: a row the mirror already delivered is one the copy skips.

  See `identity_columns/1` and `lacking/3` for what the destination "lacking"
  a row means.

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
  with no usable time column are divided by a hash of the sorting key
  instead. Both give deterministic, half-open intervals, so two adjacent
  chunks cannot claim the same row and a resumed run cannot skip one.

  A month holding more rows than one chunk should is sliced into equal spans
  of time; see `slices/2`. And a table listed in `Tables.history_days/1` is
  copied only over that many days before the cutoff, sliced the same way.
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

  # Arbitrary but fixed: an advisory lock key is only ever compared with
  # itself, and every pod that might start a backfill has to choose the same
  # one.
  @lock_key 738_412_001

  # Bounds a `FINAL` count, which merges a chunk's parts at read time. Below
  # the per-user budget these connections share with the running server, so it
  # binds before the shared pool does; see `Tuist.ClickHouse.Parity`.
  @max_memory_usage 1024 * 1024 * 1024

  # Bounds one chunk's copy, which without this can cost more than the whole
  # server has. Production's first backfill lost three chunks of
  # `test_case_runs_recent_500_per_case` and one of the table after it to
  #
  #   Code: 241. (total) memory limit exceeded: would use 26.88 GiB, current
  #   RSS: 28.80 GiB, maximum: 28.80 GiB ... While executing Remote
  #
  # while both replicas idle at 1.7 GiB of their 32Gi limit. So it is one
  # statement, not a server sized too small, and the memory is the insert
  # side's: `SELECT *` off a wide table arrives in million-row blocks that are
  # sorted by the destination's key before they are written, once per reading
  # thread, and `max_threads` defaults to the host's core count because the
  # container has no CPU limit for ClickHouse to read a smaller number from.
  # Two multipliers, so both are bounded here.
  #
  # `max_memory_usage` is the backstop rather than the fix. It is per query,
  # so a chunk that still does not fit fails alone instead of driving the
  # server-wide tracker to a ceiling that live traffic is also allocating
  # against: shadow writes share this server, and one that fails after its
  # retries is counted `error` and lost for good, having been written after
  # the cutoff that any later backfill would copy up to.
  #
  # `max_execution_time` bounds a statement on the server, and the client
  # waits longer than that and never retries; see `statement_options/0`.
  @copy_settings [
    max_memory_usage: 8 * 1024 * 1024 * 1024,
    max_threads: 4,
    max_insert_block_size: 65_536,
    min_insert_block_size_rows: 65_536,
    min_insert_block_size_bytes: 64 * 1024 * 1024,
    max_execution_time: 5_400
  ]

  # The most rows one chunk may hold before it is sliced, about fifteen to
  # twenty minutes of copying at the rate production sustained. Two things
  # set it, and neither is the time limit.
  #
  # A chunk that fails part-way is repaired by copying only what the
  # destination lacks, which holds a hash per destination row for that chunk
  # in memory. Past a few hundred million rows that no longer fits under
  # `max_memory_usage`, and a chunk too large to repair is one that can only
  # be redone by hand.
  #
  # And on the tables that are not ordered by time, every chunk reads the
  # whole table on the source whatever its size, so smaller is not free
  # either. This keeps `build_files` to a handful of such reads.
  @max_chunk_rows 300_000_000

  @doc """
  Copies every table the destination has, oldest chunk first.

  Only tables that already exist on the destination are considered, so the
  schema clone is a hard prerequisite: this will not create anything.
  """
  def run(opts \\ []) do
    Endpoints.with_repos(opts, fn source, target ->
      with_single_flight(fn -> backfill(source, target, opts) end)
    end)
  end

  # Held on one pinned connection for the length of the run rather than inside
  # a transaction: the copy takes hours, and an open transaction for hours is
  # its own problem.
  #
  # `timeout: :infinity` because that is how long the connection is held, not
  # how long any query on it runs. The default is 15 seconds, so DBConnection
  # killed the pinned connection fifteen seconds into a copy and took the run
  # down with it, mid-enumeration, no matter how healthy the copy was. Staging
  # passed only because its dataset finished inside the window; canary's did
  # not. The run's real bound is the Job's `activeDeadlineSeconds`.
  defp with_single_flight(fun) do
    Repo.checkout(
      fn ->
        case Repo.query!("SELECT pg_try_advisory_lock($1)", [@lock_key]) do
          %{rows: [[true]]} ->
            try do
              fun.()
            after
              Repo.query!("SELECT pg_advisory_unlock($1)", [@lock_key])
            end

          _ ->
            Logger.warning("Another ClickHouse backfill holds the lock; leaving it to finish")
            {:error, :already_running}
        end
      end,
      timeout: :infinity
    )
  end

  defp backfill(source, target, opts) do
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

      params = %{
        "address" => source_address(source),
        "database" => source.database,
        "table" => table,
        "user" => source_credential(source, :username),
        "password" => source_credential(source, :password)
      }

      try do
        copy(source, target, table, chunk, params)

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
        column
        |> time_chunks(source, table, cutoff)
        |> Enum.flat_map(&sized(source, table, &1))
    end
  end

  defp time_chunks(column, source, table, cutoff) do
    case Tables.history_days(table) do
      nil ->
        case bounds(source, table, column) do
          {nil, nil} -> []
          {from, to} -> month_chunks(column, from, to, cutoff)
        end

      days ->
        Logger.info("#{table}: copying the #{days} days before the cutoff, not its whole history")
        [{:range, column, DateTime.add(cutoff, -days * 86_400, :second), cutoff}]
    end
  end

  # A chunk already copied keeps its shape, so a run after this one skips it
  # rather than re-slicing it into keys the ledger has never seen.
  defp sized(source, table, chunk) do
    if chunk_done?(table, chunk), do: [chunk], else: slices(chunk, count(source, table, chunk))
  end

  @doc """
  Splits a time chunk holding `rows` rows on the source into equal spans of
  time, as many as it takes to bring each under the per-chunk limit.

  Public for the same reason as `month_chunks/4`. The slices are contiguous
  and half-open, begin where the chunk begins and end where it ends, and fall
  on whole seconds, because a chunk's bounds are rendered to the second.
  Equal spans of time rather than of rows, so a busy slice can run over the
  limit; it bounds the typical chunk, not every one.
  """
  def slices({:range, column, from, to} = chunk, rows) do
    count = div(rows + @max_chunk_rows - 1, @max_chunk_rows)

    if count <= 1 do
      [chunk]
    else
      span = DateTime.diff(to, from, :second)
      boundary = fn i -> if i == count, do: to, else: DateTime.add(from, div(i * span, count), :second) end

      Enum.map(0..(count - 1), &{:range, column, boundary.(&1), boundary.(&1 + 1)})
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
        [settings: [max_execution_time: Keyword.fetch!(@copy_settings, :max_execution_time)], log: false] ++
          statement_options()
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

  # Straight in when the destination holds nothing for this range, which is
  # every chunk of a first backfill, and gap-filling when it holds something,
  # which is a repair or the overlap the dual write leaves behind.
  #
  # The credentials are query parameters rather than interpolated text, so the
  # statement carries no secret even if something logs it. `log: false` as
  # well, because a driver-level error can echo the parameters too.
  defp copy(source, target, table, chunk, params) do
    destination = "#{quote_ident(target.database)}.#{quote_ident(table)}"
    from = "remoteSecure({address:String}, {database:String}, {table:String}, {user:String}, {password:String})"

    case count(target, table, chunk) do
      0 ->
        run!(target, "INSERT INTO #{destination} SELECT * FROM #{from} WHERE #{predicate(chunk)}", params)

      destination_rows ->
        Logger.info("#{table} #{inspect(chunk)}: destination already holds rows here, copying only what it lacks")
        shape = shape(target, table)
        where = lacking(identity_columns(shape), destination, chunk)

        if not Tables.collapsing?(shape.engine) do
          %{rows: [[lacking_rows]]} = run!(target, "SELECT count() FROM #{from} WHERE #{where}", params)
          refuse_duplicates!(lacking_rows, count(source, table, chunk) - destination_rows)
        end

        run!(target, "INSERT INTO #{destination} SELECT * FROM #{from} WHERE #{where}", params)
    end
  end

  @doc """
  The settings every statement a copy issues carries.

  Public for the same reason as `predicate/1`: when it is wrong nothing says
  so at the call site, and the failure lands on the server rather than on the
  statement that caused it.
  """
  def copy_settings, do: @copy_settings

  @doc """
  The options every statement that reads a chunk is sent with, the copy and
  the counts alike.

  The client waits longer than the server's `max_execution_time` and never
  retries. The other way round was the default, and it was unsafe in a way
  that only large chunks reach: when the client gave up first, the driver
  asked DBConnection to retry on a fresh connection, and ClickHouse does not
  cancel an `INSERT` whose client has gone, so one slow chunk became up to
  four concurrent copies of the same rows into the destination. With the
  server giving up first, a chunk that runs too long fails once, is recorded
  as failed, and is repaired by the next run.
  """
  def statement_options do
    [timeout: to_timeout(second: Keyword.fetch!(@copy_settings, :max_execution_time) + 300), checkout_retries: 0]
  end

  defp run!(target, statement, params) do
    target.repo.query!(statement, params, [settings: @copy_settings, log: false] ++ statement_options())
  end

  # On a plain `MergeTree` the destination cannot lack more rows than it is
  # short of. When more look missing, some rows it already holds do not match
  # their source copy under the identity, and inserting them would duplicate
  # them and fire every view that reads the table a second time, neither of
  # which a later step can take back. Raised, so the chunk is recorded as
  # failed instead of copied.
  #
  # Collapsing engines are left out because their raw counts move with merges
  # on either side while the data stays the same.
  defp refuse_duplicates!(lacking_rows, shortfall) when lacking_rows > shortfall do
    raise "#{lacking_rows} row(s) look missing but the destination is only #{shortfall} short, so some rows it already holds do not match their source copy and would be copied twice"
  end

  defp refuse_duplicates!(_lacking_rows, _shortfall), do: :ok

  @doc """
  The `WHERE` clause selecting the rows of a chunk whose identity the
  destination does not hold.

  The identity is hashed as a single tuple. A hash of a NULL argument is NULL,
  and `NULL NOT IN (...)` is not true, so hashing the columns as separate
  arguments skips every row with a NULL in any of them. A tuple is never NULL
  itself, so every row gets a hash, and a NULL still hashes differently from
  an empty value.

  `GLOBAL NOT IN` rather than `NOT IN`: the subquery reads the destination,
  and without `GLOBAL` it is sent to the source to run, where that table does
  not exist.

  Public for the same reason as `predicate/1`: when it is wrong, rows go
  missing without any error.
  """
  def lacking(identity, destination, chunk) do
    hash = "cityHash64(tuple(#{Enum.map_join(identity, ", ", &quote_ident/1)}))"

    "#{predicate(chunk)} AND #{hash} GLOBAL NOT IN (SELECT #{hash} FROM #{destination} WHERE #{predicate(chunk)})"
  end

  @doc """
  What makes a row the same row, for deciding which ones the destination is
  missing, given a table's engine, sorting key and columns.

  On an engine that collapses by its sorting key, that key is the identity the
  engine itself uses, together with the columns the engine is told to tell
  versions apart by: the version of a `ReplacingMergeTree`, the sign of a
  `CollapsingMergeTree`. Without the version, a destination holding an older
  version of a row counts as holding the row, and the newer one is never
  copied.

  On a plain `MergeTree` nothing is unique, because duplicate rows are legal
  and meaningful, so identity is every column the writer supplies. The cost is
  that two genuinely identical rows are treated as one and only one is copied.
  That is a narrower failure than the alternative: `build_files` sorts by
  project, so a sorting-key identity would make most missing rows look present
  and they would never be copied at all.

  Columns with a default are left out of that. When a write omits one, each
  server fills it in for itself and the two need not agree, as
  `command_events.legacy_id` did while it came from a per-server counter, and
  a row the destination holds would then look missing. If every column has a
  default, all of them are used.
  """
  def identity_columns(%{engine: engine, engine_full: engine_full, sorting_key: sorting_key, columns: columns}) do
    if Tables.collapsing?(engine) and sorting_key != "" do
      Enum.uniq(split_columns(sorting_key) ++ engine_columns(engine_full))
    else
      case for({name, ""} <- columns, do: name) do
        [] -> Enum.map(columns, &elem(&1, 0))
        written -> written
      end
    end
  end

  defp shape(endpoint, table) do
    params = %{"database" => endpoint.database, "table" => table}

    %{rows: [[engine, engine_full, sorting_key]]} =
      endpoint.repo.query!(
        "SELECT engine, engine_full, sorting_key FROM system.tables WHERE database = {database:String} AND name = {table:String}",
        params,
        log: false
      )

    %{rows: columns} =
      endpoint.repo.query!(
        """
        SELECT name, default_kind FROM system.columns
        WHERE database = {database:String} AND table = {table:String}
        ORDER BY position
        """,
        params,
        log: false
      )

    %{engine: engine, engine_full: engine_full, sorting_key: sorting_key, columns: Enum.map(columns, &List.to_tuple/1)}
  end

  defp split_columns(key), do: key |> String.split(",") |> Enum.map(&String.trim/1)

  # The engine's own column arguments, after the Keeper path and replica name
  # a replicated engine carries:
  # `ReplicatedReplacingMergeTree('/clickhouse/tables/{uuid}/{shard}', '{replica}', inserted_at)`
  # names `inserted_at`. `SummingMergeTree` takes arguments too, but they are
  # the values it adds up rather than anything that identifies a row.
  defp engine_columns(engine_full) do
    case Regex.run(~r/(?:Replacing|Collapsing)MergeTree\(([^)]*)\)/, engine_full) do
      [_, arguments] ->
        arguments
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "'")))
        |> Enum.map(&String.trim(&1, "`"))

      nil ->
        []
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
        [
          settings: [
            max_memory_usage: @max_memory_usage,
            max_execution_time: Keyword.fetch!(@copy_settings, :max_execution_time)
          ],
          log: false
        ] ++ statement_options()
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
