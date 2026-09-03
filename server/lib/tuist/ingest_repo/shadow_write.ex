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
      mirror(fn -> Tuist.ShadowIngestRepo.query(sql, params, opts) end, statement_kind(sql))
    end

    :ok
  end

  @doc false
  def mirror_insert_all(schema_or_source, entries, opts) do
    if enabled?() do
      mirror(fn -> Tuist.ShadowIngestRepo.insert_all(schema_or_source, entries, opts) end, "insert_all")
    end

    :ok
  end

  @doc false
  def mirror_insert(struct, opts) do
    if enabled?() do
      mirror(fn -> Tuist.ShadowIngestRepo.insert(struct, opts) end, "insert")
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

  defp mirror(fun, kind) do
    fun.()
    :telemetry.execute([:tuist, :clickhouse, :shadow_write], %{count: 1}, %{kind: kind, result: :ok})
  rescue
    error ->
      :telemetry.execute([:tuist, :clickhouse, :shadow_write], %{count: 1}, %{kind: kind, result: :error})

      Logger.error("Shadow ClickHouse write (#{kind}) failed: #{Exception.message(error)}")
      :error
  catch
    :exit, reason ->
      :telemetry.execute([:tuist, :clickhouse, :shadow_write], %{count: 1}, %{kind: kind, result: :error})

      Logger.error("Shadow ClickHouse write (#{kind}) exited: #{inspect(reason)}")
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
