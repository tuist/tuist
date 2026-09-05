defmodule Tuist.IngestRepo.ShadowWrite do
  @moduledoc """
  Mirrors `Tuist.IngestRepo`'s writes onto `Tuist.ShadowIngestRepo` so that,
  during the migration off ClickHouse Cloud (spec #73), both servers receive
  every new row.

  ## Why this lives in the repository

  There are 34 structured write call sites and 4 raw ones across `lib`, plus
  the RowBinary buffers. Fanning out at each of them would be 40 edits to keep
  in step forever, and the one that gets forgotten is invisible until a parity
  check months later. The repository is the one place all of them already pass
  through.

  ## Which statements are mirrored

  `insert/1,2` and `insert_all/2,3` are unambiguously writes and are always
  mirrored.

  Raw `query/1,2,3` and `query!/1,2,3` are not: the same functions carry the
  `INSERT` that flushes a buffer, the `ALTER TABLE ... DELETE` that erases a
  deleted project's rows, and a metadata introspection `SELECT` that
  `Tuist.CommandEvents` routes through this repository specifically to bypass
  the sandboxed read repo. So statements are matched against a whitelist of
  write forms rather than a blacklist of reads. A statement nobody recognised
  is not mirrored, which risks a missing row that parity will catch, rather
  than mirroring a read, which would double every metadata query's cost for
  no benefit.

  ## Why inserts are mirrored off the request

  Several of these call sites run inside a request rather than in one of the
  buffers, so a synchronous mirror puts a second ClickHouse round trip in the
  customer's path, and a slow destination spends the whole connection queue
  timeout there before giving up. Staging showed exactly that: the writes that
  failed in the seconds after a pod started had waited 5.5 seconds first, in a
  request that had nothing to do with the migration.

  Inserts are therefore handed to a bounded task supervisor. Cloud has already
  taken the write by then, so there is nothing for the caller to wait for. The
  bound is what keeps a destination that has stopped answering from turning
  into unbounded memory: past it, the mirror is dropped and counted, which is
  the same outcome as a failed write and is what parity is there to catch.

  Mutations stay synchronous. `ALTER TABLE ... DELETE` erases a deleted
  project's rows, and running it concurrently with the inserts around it could
  put the delete before the rows it is meant to remove. They are rare enough
  that their latency does not matter.

  ## Retrying

  A mirrored write is attempted three times before it is given up on. The
  failures worth retrying are the ones staging produced: for about twenty
  seconds after a pod starts, its connection pool is not ready and writes are
  dropped from the queue. One such drop cost `kura_storage_snapshots` a single
  row, which the parity check then caught, so the alternative to retrying is a
  permanent divergence for every deploy.

  Retrying an `INSERT` is safe here because every table on the destination is
  a `Replicated*` engine, which deduplicates identical blocks by checksum for
  a week by default. A retry that follows a request the server actually
  applied is therefore discarded rather than doubled. That property is
  guaranteed rather than assumed: the destination is configured to reject a
  non-replicated engine outright.

  ## Failure

  A mirrored write that fails is logged, counted through telemetry, and
  otherwise ignored. Cloud is the system of record for the whole of this
  stage, so a request must not fail because the destination is unreachable,
  and it must not be slowed by retrying against it. The counter going above
  zero is what says the mirror is unhealthy; the parity report is what says
  whether it actually lost anything.
  """

  require Logger

  # `INSERT` covers both the ORM writes and the buffer flushes.
  # `ALTER TABLE` covers the mutation-based deletes, which have to be mirrored
  # or the destination keeps rows the source has erased.
  @write_prefixes ["insert", "alter table"]

  # Started by `Tuist.Application`, which is also where the bound on it lives.
  @supervisor __MODULE__.TaskSupervisor

  @attempts 3

  # How long a mutation waits for the inserts before it, in the request that
  # issued it.
  @drain_timeout_ms 5_000

  defmacro __before_compile__(_env) do
    quote do
      alias Tuist.IngestRepo.ShadowWrite

      defoverridable query: 1, query: 2, query: 3, query!: 1, query!: 2, query!: 3

      def query(sql, params \\ [], opts \\ []) do
        result = super(sql, params, opts)
        ShadowWrite.mirror_statement(sql, params, opts)
        result
      end

      def query!(sql, params \\ [], opts \\ []) do
        result = super(sql, params, opts)
        ShadowWrite.mirror_statement(sql, params, opts)
        result
      end
    end
  end

  @doc false
  def mirror_statement(sql, params, opts) do
    if enabled?() and write?(sql) do
      kind = statement_kind(sql)
      run = fn -> Tuist.ShadowIngestRepo.query(sql, params, opts) end

      if kind == "insert" do
        detach(run, kind)
      else
        # Mutations are ordered against the inserts that came before them, not
        # merely run synchronously. Making the delete itself synchronous is not
        # enough: the inserts it is meant to erase are detached tasks that may
        # still be queued, so the delete can overtake them and the row it
        # removed is written back immediately afterwards.
        await_inflight_mirrors()
        mirror(run, kind)
      end
    end

    :ok
  end

  @doc false
  def mirror_insert_all(schema_or_source, entries, opts) do
    if enabled?() do
      detach(fn -> Tuist.ShadowIngestRepo.insert_all(schema_or_source, entries, opts) end, "insert_all")
    end

    :ok
  end

  @doc false
  def mirror_insert(struct, opts) do
    if enabled?() do
      detach(fn -> Tuist.ShadowIngestRepo.insert(struct, opts) end, "insert")
    end

    :ok
  end

  @doc """
  Whether a raw statement is one of the write forms that must be mirrored.

  Public so the whitelist is testable without a ClickHouse to talk to, which
  is the part that decides whether a write is silently dropped.
  """
  def write?(sql) when is_binary(sql) do
    normalized = sql |> String.trim_leading() |> String.downcase()
    Enum.any?(@write_prefixes, &String.starts_with?(normalized, &1))
  end

  def write?(_sql), do: false

  defp detach(fun, kind) do
    case Task.Supervisor.start_child(@supervisor, fn -> mirror(fun, kind) end) do
      {:ok, _pid} ->
        :ok

      {:error, :max_children} ->
        :telemetry.execute([:tuist, :clickhouse, :shadow_write], %{count: 1}, %{kind: kind, result: :dropped})

        Logger.error("Shadow ClickHouse write (#{kind}) dropped: too many already in flight")
        :error

      {:error, reason} ->
        :telemetry.execute([:tuist, :clickhouse, :shadow_write], %{count: 1}, %{kind: kind, result: :error})

        Logger.error("Shadow ClickHouse write (#{kind}) could not start: #{inspect(reason)}")
        :error
    end
  catch
    # Starting a child is a call into the supervisor, so its absence is an
    # exit rather than an error tuple, and an exit here would reach the
    # caller: a request whose primary write has already succeeded, or a
    # release task that never started the supervision tree at all. Both are
    # cases where the mirror must not be the thing that fails.
    #
    # It runs inline instead of being dropped. The supervisor is missing
    # exactly where latency does not matter: under `bin/tuist eval`, and
    # during shutdown once it has stopped but the ingest buffers have not yet
    # made their final flush.
    :exit, _reason -> mirror(fun, kind)
  end

  # Bounded, because this runs in the request that issued the mutation, and a
  # mirror that is wedged must not hold that request open indefinitely. Timing
  # out means the delete goes ahead unordered, which is the same risk as
  # before and strictly rarer.
  defp await_inflight_mirrors do
    deadline = System.monotonic_time(:millisecond) + @drain_timeout_ms

    @supervisor
    |> Task.Supervisor.children()
    |> Enum.each(fn pid ->
      remaining = deadline - System.monotonic_time(:millisecond)

      if remaining > 0 do
        reference = Process.monitor(pid)

        receive do
          {:DOWN, ^reference, :process, ^pid, _reason} -> :ok
        after
          remaining -> Process.demonitor(reference, [:flush])
        end
      end
    end)
  catch
    :exit, _reason -> :ok
  end

  defp mirror(fun, kind, attempt \\ 1) do
    # Matched rather than ignored. The raw mirrors call `query/3`, which
    # answers `{:error, exception}` instead of raising, so a rejected write
    # would otherwise be counted as a success and never retried: exactly the
    # silent loss the counter exists to make visible. This covers the buffer
    # flushes and the mutation-based deletes.
    case fun.() do
      {:error, error} ->
        retry_or_give_up(fun, kind, attempt, "was rejected: #{inspect(error)}")

      _ ->
        :telemetry.execute([:tuist, :clickhouse, :shadow_write], %{count: 1}, %{kind: kind, result: :ok})
    end
  rescue
    error -> retry_or_give_up(fun, kind, attempt, "failed: #{Exception.message(error)}")
  catch
    :exit, reason -> retry_or_give_up(fun, kind, attempt, "exited: #{inspect(reason)}")
  end

  defp retry_or_give_up(fun, kind, attempt, _reason) when attempt < @attempts do
    # Counted rather than logged: the failure worth retrying is a pool that is
    # not ready yet, and it produces a burst of them at once, so a log line per
    # attempt would bury the deploy it happened on.
    :telemetry.execute([:tuist, :clickhouse, :shadow_write], %{count: 1}, %{kind: kind, result: :retried})

    Process.sleep(attempt * 1000)
    mirror(fun, kind, attempt + 1)
  end

  defp retry_or_give_up(_fun, kind, _attempt, reason) do
    :telemetry.execute([:tuist, :clickhouse, :shadow_write], %{count: 1}, %{kind: kind, result: :error})

    Logger.error("Shadow ClickHouse write (#{kind}) #{reason}")
    :error
  end

  # Two conditions, not one. The repository is only in the supervision tree
  # when a destination is configured, which makes this inert everywhere except
  # an environment that is mid-migration; and mirroring is switched on
  # separately, once that destination has a schema to accept the writes.
  defp enabled? do
    Tuist.Environment.clickhouse_shadow_writes_enabled?()
  end

  defp statement_kind(sql) do
    sql |> String.trim_leading() |> String.split(" ", parts: 2) |> hd() |> String.downcase()
  end
end
