defmodule Tuist.Ops.Database do
  @moduledoc """
  Read-only database inspection helpers used by the `/ops/db` LiveView.
  Replaces the pgweb instance the RFC originally proposed: every query
  runs through `Tuist.Repo` inside an explicit read-only transaction
  AND the query string is whitelisted against a SELECT-only grammar
  before it ever reaches the driver. Two layers, both required to be
  bypassed before any write reaches Postgres.

  `EctoPSQLExtras` powers the canned reports (table sizes, unused
  indexes, long-running queries, locks). The ad-hoc SQL runner is the
  only path that accepts operator input; it goes through `execute/2`.
  """

  alias Tuist.Environment
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Repo

  @max_rows 200
  @statement_timeout_ms 5_000

  @doc """
  High-level info about the cluster the server is currently connected to.
  Mirrors the kind of header pgweb showed: Postgres version, current
  database, server address, and open connection count.
  """
  def cluster_info do
    %{
      version: scalar("SHOW server_version"),
      database: scalar("SELECT current_database()"),
      user: scalar("SELECT current_user"),
      server_addr: scalar("SELECT COALESCE(inet_server_addr()::text, 'local')"),
      uptime: scalar("SELECT date_trunc('second', now() - pg_postmaster_start_time())::text"),
      connections: scalar("SELECT count(*)::text FROM pg_stat_activity"),
      max_connections: scalar("SHOW max_connections"),
      in_recovery: scalar("SELECT pg_is_in_recovery()::text"),
      database_size: scalar("SELECT pg_size_pretty(pg_database_size(current_database()))")
    }
  end

  @doc """
  Top tables by total size (table + indexes + toast).
  """
  def table_sizes(limit \\ 30) do
    :table_size |> psql_extras() |> Enum.take(limit)
  end

  @doc """
  Tables in the database with size + estimated-row stats, ready for the
  /ops/db tables list. Excludes Postgres internals, CNPG operator, and
  TimescaleDB schemas (the `_timescaledb_internal` chunk tables of a
  hypertable would otherwise flood the list) so the operator only sees
  app-owned tables. Ordered by total on-disk size (largest first) —
  matches operator intuition about what's worth opening.

  `estimated_rows` comes from `pg_class.reltuples` and is whatever the
  last ANALYZE recorded; counting exactly would touch every row and
  defeat the point of a quick overview.
  """
  def list_table_overviews do
    {:ok, %{rows: rows, columns: cols}} =
      Repo.query("""
      SELECT
        n.nspname AS schema,
        c.relname AS name,
        pg_size_pretty(pg_total_relation_size(c.oid)) AS size,
        pg_total_relation_size(c.oid) AS size_bytes,
        c.reltuples::bigint AS estimated_rows
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE c.relkind = 'r'
        AND n.nspname NOT IN ('pg_catalog', 'information_schema')
        AND n.nspname NOT LIKE 'pg_%'
        AND n.nspname NOT LIKE 'cnpg_%'
        AND n.nspname NOT LIKE '%timescaledb%'
      ORDER BY pg_total_relation_size(c.oid) DESC
      """)

    rows_to_maps(%{rows: rows, columns: cols})
  end

  @doc """
  Column metadata for a single table — name / type / nullability /
  default. Empty when the table doesn't exist; callers also call
  `table_exists?/2` to decide between "show the page" and "404".
  """
  def list_table_columns(schema, name) do
    {:ok, %{rows: rows, columns: cols}} =
      Repo.query(
        """
        SELECT
          column_name AS name,
          data_type AS type,
          is_nullable AS nullable,
          column_default AS default
        FROM information_schema.columns
        WHERE table_schema = $1 AND table_name = $2
        ORDER BY ordinal_position
        """,
        [schema, name]
      )

    rows_to_maps(%{rows: rows, columns: cols})
  end

  @doc """
  Cheap existence check. Falls back to `information_schema.tables`
  rather than `pg_class` so views + foreign tables show up too if we
  ever expand the page to cover them.
  """
  def table_exists?(schema, name) do
    {:ok, %{num_rows: n}} =
      Repo.query(
        "SELECT 1 FROM information_schema.tables WHERE table_schema = $1 AND table_name = $2",
        [schema, name]
      )

    n > 0
  end

  @doc """
  Paginated preview of a table's rows. Same read-only enforcement as
  the ad-hoc SQL runner: `BEGIN READ ONLY` + `statement_timeout`.

  ## Options

    * `:page` — 1-based page number (default `1`)
    * `:page_size` — rows per page (default `20`)
    * `:sort_column` — column to ORDER BY; defaults to the table's
      first column for stable pagination
    * `:sort_dir` — `:asc` or `:desc` (default `:asc`)
    * `:filters` — list of `%Noora.Filter.Filter{}` structs from
      `Noora.Filter.Operations.decode_filters_from_query/2`. Each is
      translated to a WHERE clause; multiple filters are joined with
      AND. The column name (via `filter.id`) is whitelisted against
      the table's actual columns before splicing; the value is always
      parameterized.
  """
  def preview_table_rows(schema, name, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 20)
    sort_dir = opts |> Keyword.get(:sort_dir, :asc) |> normalize_dir()
    filters = Keyword.get(opts, :filters, [])

    case list_table_columns(schema, name) do
      [] ->
        {:error, :no_columns}

      [%{"name" => first} | _] = columns ->
        column_names = Enum.map(columns, & &1["name"])
        sort_column = pick_column(Keyword.get(opts, :sort_column), column_names, first)
        {where_sql, params} = build_where(filters, column_names)

        run_preview(schema, name, sort_column, sort_dir, where_sql, params, page, page_size)
    end
  end

  defp run_preview(schema, name, sort_column, sort_dir, where_sql, params, page, page_size) do
    offset = (max(page, 1) - 1) * page_size
    limit_index = length(params) + 1
    offset_index = limit_index + 1

    sql =
      "SELECT * FROM #{quote_ident(schema)}.#{quote_ident(name)} " <>
        where_sql <>
        " ORDER BY #{quote_ident(sort_column)} #{sql_dir(sort_dir)} " <>
        " LIMIT $#{limit_index} OFFSET $#{offset_index}"

    bindings = params ++ [page_size, offset]

    Repo.transaction(fn ->
      {:ok, _} = Repo.query("SET TRANSACTION READ ONLY")
      {:ok, _} = Repo.query("SET LOCAL statement_timeout = #{@statement_timeout_ms}")

      case Repo.query(sql, bindings) do
        {:ok, %{columns: cols, rows: rows, num_rows: n}} ->
          columns = cols || []
          %{columns: columns, rows: rows_with_ids(rows, columns), num_rows: n}

        {:error, %Postgrex.Error{} = err} ->
          Repo.rollback(Exception.message(err))

        {:error, reason} ->
          Repo.rollback(inspect(reason))
      end
    end)
  end

  # Postgrex hands rows back as bare lists; Noora's <.table> needs each
  # row to be a map keyed by an `:id`. Wrap once here so both the table
  # preview and the SQL editor share the shape without per-call code.
  defp rows_with_ids(rows, columns) do
    rows
    |> Enum.with_index()
    |> Enum.map(fn {row, idx} ->
      row
      |> Enum.zip(columns)
      |> Map.new(fn {v, c} -> {c, v} end)
      |> Map.put(:id, idx)
    end)
  end

  defp pick_column(nil, _columns, default), do: default

  defp pick_column(col, columns, default) when is_binary(col) do
    if col in columns, do: col, else: default
  end

  defp pick_column(_, _, default), do: default

  defp normalize_dir(:desc), do: :desc
  defp normalize_dir("desc"), do: :desc
  defp normalize_dir(_), do: :asc

  defp sql_dir(:desc), do: "DESC"
  defp sql_dir(_), do: "ASC"

  # Translate Noora.Filter active filters into a parameterized WHERE
  # clause. Each filter contributes one clause; clauses join with AND.
  # Filters whose column isn't on the table (stale URL state) or whose
  # value is empty get skipped silently so the page stays usable.
  defp build_where(filters, column_names) when is_list(filters) do
    {clauses, params, _} =
      Enum.reduce(filters, {[], [], 1}, fn filter, {clauses, params, index} ->
        case filter_clause(filter, column_names, index) do
          :skip ->
            {clauses, params, index}

          {clause, bindings} ->
            {clauses ++ [clause], params ++ bindings, index + length(bindings)}
        end
      end)

    case clauses do
      [] -> {"", []}
      _ -> {"WHERE " <> Enum.join(clauses, " AND "), params}
    end
  end

  defp filter_clause(%{id: id} = filter, column_names, index) do
    if id in column_names do
      to_clause(filter, index)
    else
      :skip
    end
  end

  defp filter_clause(_, _, _), do: :skip

  # The `::text` cast keeps filtering type-agnostic — a numeric `id`
  # column can still be matched by an `==` clause coming from a text
  # input, and ILIKE always needs text semantics. The performance hit
  # is acceptable for an ops inspection surface.
  defp to_clause(%{id: id, operator: :empty}, _idx), do: {"#{quote_ident(id)} IS NULL", []}

  defp to_clause(%{id: id, operator: :not_empty}, _idx), do: {"#{quote_ident(id)} IS NOT NULL", []}

  defp to_clause(%{value: nil}, _idx), do: :skip
  defp to_clause(%{value: ""}, _idx), do: :skip

  defp to_clause(%{id: id, operator: :==, value: value}, idx),
    do: {"#{quote_ident(id)}::text = $#{idx}", [to_string(value)]}

  defp to_clause(%{id: id, operator: :!=, value: value}, idx),
    do: {"#{quote_ident(id)}::text <> $#{idx}", [to_string(value)]}

  defp to_clause(%{id: id, operator: :=~, value: value}, idx),
    do: {"#{quote_ident(id)}::text ILIKE $#{idx}", ["%#{escape_like(to_string(value))}%"]}

  defp to_clause(%{id: id, operator: :"!=~", value: value}, idx),
    do: {"#{quote_ident(id)}::text NOT ILIKE $#{idx}", ["%#{escape_like(to_string(value))}%"]}

  defp to_clause(%{id: id, operator: :<, value: value}, idx),
    do: {"#{quote_ident(id)}::text < $#{idx}", [to_string(value)]}

  defp to_clause(%{id: id, operator: :>, value: value}, idx),
    do: {"#{quote_ident(id)}::text > $#{idx}", [to_string(value)]}

  defp to_clause(%{id: id, operator: :<=, value: value}, idx),
    do: {"#{quote_ident(id)}::text <= $#{idx}", [to_string(value)]}

  defp to_clause(%{id: id, operator: :>=, value: value}, idx),
    do: {"#{quote_ident(id)}::text >= $#{idx}", [to_string(value)]}

  defp to_clause(_, _), do: :skip

  defp escape_like(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  @doc """
  Estimated row count for a single table, sourced from pg_class so the
  pagination footer doesn't trigger a full-table COUNT(*). Returns 0
  when the relation doesn't exist or has never been analyzed.
  """
  def estimated_row_count(schema, name) do
    {:ok, %{rows: rows}} =
      Repo.query(
        """
        SELECT GREATEST(c.reltuples, 0)::bigint
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = $1 AND c.relname = $2
        """,
        [schema, name]
      )

    case rows do
      [[n]] when is_integer(n) -> n
      _ -> 0
    end
  end

  @doc """
  Pretty-printed total relation size for the pagination footer.
  """
  def table_size_pretty(schema, name) do
    {:ok, %{rows: rows}} =
      Repo.query(
        """
        SELECT pg_size_pretty(pg_total_relation_size(format('%I.%I', $1::text, $2::text)::regclass))
        """,
        [schema, name]
      )

    case rows do
      [[v]] when is_binary(v) -> v
      _ -> "—"
    end
  end

  # Quote a Postgres identifier — handle embedded `"` per the SQL spec
  # (double it). Used when an identifier needs to be spliced into a
  # query because Postgres doesn't allow parameterized table / column
  # names. Pair every call with a `table_exists?/2` (or equivalent)
  # check on the upstream parameter source.
  defp quote_ident(name) when is_binary(name) do
    ~s("#{String.replace(name, "\"", "\"\"")}")
  end

  @doc """
  Indexes that have served no scans since the stats were last reset.
  """
  def unused_indexes, do: psql_extras(:unused_indexes)

  @doc "Indexes covering the same column set as another index."
  def duplicate_indexes, do: psql_extras(:duplicate_indexes)

  @doc """
  Queries currently running longer than the LiveDashboard's 200ms
  threshold.
  """
  def long_running_queries, do: psql_extras(:long_running_queries)

  @doc "Active locks. Helps spot contention without a psql session."
  def locks, do: psql_extras(:locks)

  @doc "Buffer cache hit ratio for the heap + indexes."
  def cache_hit, do: psql_extras(:cache_hit)

  @doc """
  Replication slot lag, primary vs replicas. Empty when the cluster has
  no replicas (single-instance preview / dev) — surface that to the
  operator instead of raising.
  """
  def replication do
    {:ok, %{rows: rows, columns: cols}} =
      Repo.query(
        "SELECT application_name, state, sync_state, " <>
          "pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn) AS send_lag, " <>
          "pg_wal_lsn_diff(pg_current_wal_lsn(), write_lsn) AS write_lag, " <>
          "pg_wal_lsn_diff(pg_current_wal_lsn(), flush_lsn) AS flush_lag, " <>
          "pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS replay_lag " <>
          "FROM pg_stat_replication"
      )

    rows_to_maps(%{rows: rows, columns: cols})
  end

  @doc """
  pg_stat_archiver snapshot — the closest signal Postgres exposes to
  "is the backup pipeline alive". CNPG configures `archive_command` to
  push WAL into the barman object store on Tigris; the timestamp in
  `last_archived_time` is when the last WAL segment reached S3, and
  the gap between now and that timestamp is the worst-case data-loss
  window for a point-in-time restore.

  In dev (no archive_command) the row exists but `archived_count` is
  always 0 — the template renders that state as "Not configured".
  """
  def archiver_status do
    {:ok, %{rows: [row], columns: cols}} =
      Repo.query("""
      SELECT
        archived_count,
        last_archived_wal,
        last_archived_time,
        failed_count,
        last_failed_wal,
        last_failed_time,
        stats_reset,
        now() - last_archived_time AS time_since_last_archive
      FROM pg_stat_archiver
      """)

    cols
    |> Enum.zip(row)
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
  end

  @doc """
  Postgres-side archive settings (`archive_mode`, `archive_command`,
  `archive_timeout`). Tells the operator whether continuous archiving
  is on at all — useful next to `archiver_status/0` to disambiguate
  "no archives because off" from "archive_command is failing".
  """
  def archive_settings do
    {:ok, %{rows: rows, columns: cols}} =
      Repo.query("""
      SELECT name, setting, short_desc
      FROM pg_settings
      WHERE name IN ('archive_mode', 'archive_command', 'archive_timeout')
      ORDER BY name
      """)

    rows_to_maps(%{rows: rows, columns: cols})
  end

  @doc """
  Lists the CNPG `Backup` CRs for the in-cluster Postgres cluster via the
  Kubernetes API. Complements `archiver_status/0`: the archiver snapshot
  only reports whether WAL is currently streaming to the object store,
  while this surfaces each base backup's completion phase, method, and
  error — the signal an operator needs to confirm a snapshot actually
  completed (a failed base backup can coexist with healthy WAL archiving).

  Returns `{:ok, backups}` (newest first), `{:error, :not_configured}`
  when the cluster namespace isn't wired (dev, or CNPG not provisioned),
  or `{:error, :unavailable}` when the Kubernetes API can't be reached or
  the read is denied.
  """
  def list_base_backups do
    case Environment.cnpg_namespace() do
      namespace when is_binary(namespace) and namespace != "" ->
        list_base_backups(namespace)

      _ ->
        {:error, :not_configured}
    end
  end

  defp list_base_backups(namespace) do
    case K8sClient.get("/apis/postgresql.cnpg.io/v1/namespaces/#{namespace}/backups") do
      {:ok, %{"items" => items}} when is_list(items) ->
        backups =
          items
          |> Enum.map(&parse_backup/1)
          |> Enum.sort_by(&(&1.created_at || ""), :desc)

        {:ok, backups}

      {:error, _reason} ->
        {:error, :unavailable}
    end
  end

  defp parse_backup(item) do
    status = Map.get(item, "status", %{})
    spec = Map.get(item, "spec", %{})

    %{
      name: get_in(item, ["metadata", "name"]),
      created_at: get_in(item, ["metadata", "creationTimestamp"]),
      cluster: get_in(spec, ["cluster", "name"]),
      method: Map.get(spec, "method") || Map.get(status, "method"),
      phase: Map.get(status, "phase"),
      started_at: Map.get(status, "startedAt"),
      stopped_at: Map.get(status, "stoppedAt"),
      error: Map.get(status, "error")
    }
  end

  @doc """
  Run an operator-supplied SQL statement and return the result rows.

  Two layers of read-only enforcement:

    1. **Grammar gate.** The statement must start with one of
       SELECT / WITH / EXPLAIN / SHOW after whitespace strip; anything
       else fails fast without hitting the driver.
    2. **Transaction gate.** The statement runs inside a `BEGIN READ
       ONLY` transaction with `statement_timeout` clamped to
       `#{@statement_timeout_ms}ms`. Even if the grammar check missed a
       write-shaped SELECT (e.g. `SELECT pg_terminate_backend(...)`),
       Postgres itself blocks side effects at this level.

  Returns `{:ok, %{columns: [...], rows: [[...]], num_rows: n,
  truncated?: bool}}` or `{:error, reason}`.
  """
  def execute(sql, opts \\ []) do
    limit = Keyword.get(opts, :limit, @max_rows)

    with :ok <- validate_grammar(sql) do
      started = System.monotonic_time(:microsecond)

      case run_read_only(sql, limit) do
        {:ok, result} ->
          {:ok, Map.put(result, :duration_us, System.monotonic_time(:microsecond) - started)}

        other ->
          other
      end
    end
  end

  defp validate_grammar(sql) when is_binary(sql) do
    trimmed = sql |> String.trim() |> String.trim_trailing(";")

    cond do
      trimmed == "" ->
        {:error, "Empty query"}

      Regex.match?(~r/^\s*(select|with|explain|show)\b/i, trimmed) ->
        :ok

      true ->
        {:error,
         "Only SELECT, WITH, EXPLAIN, and SHOW statements are allowed in the /ops/db query runner. " <>
           "Writes must go through `kubectl cnpg psql` with the cluster's superuser role."}
    end
  end

  defp validate_grammar(_), do: {:error, "Query must be a string"}

  defp run_read_only(sql, limit) do
    Repo.transaction(fn ->
      {:ok, _} = Repo.query("SET TRANSACTION READ ONLY")
      {:ok, _} = Repo.query("SET LOCAL statement_timeout = #{@statement_timeout_ms}")

      if cursorable?(sql) do
        fetch_via_cursor(sql, limit)
      else
        build_result(Repo.query(sql), limit)
      end
    end)
  end

  # SELECT / WITH go through a server-side cursor so we pull only `limit + 1`
  # rows off the wire instead of materializing the whole result set into the
  # BEAM — a bare `SELECT * FROM huge_table` would otherwise load millions of
  # rows before we truncate to `limit` and could exhaust the web node's memory
  # (the statement_timeout only bounds time, not result size). EXPLAIN / SHOW
  # can't be wrapped in a cursor but their output is inherently small, so they
  # run directly.
  defp cursorable?(sql), do: Regex.match?(~r/^\s*(select|with)\b/i, sql)

  defp fetch_via_cursor(sql, limit) do
    case Repo.query("DECLARE _ops_cursor NO SCROLL CURSOR FOR #{sql}") do
      {:ok, _} ->
        fetched = Repo.query("FETCH FORWARD #{limit + 1} FROM _ops_cursor")
        # Close explicitly on success: under the test SQL sandbox the
        # surrounding Repo.transaction is a savepoint rather than a real
        # commit, so the cursor would otherwise linger and collide with the
        # next query's DECLARE. On a FETCH error the savepoint rollback drops
        # it, so only close when the fetch succeeded.
        if match?({:ok, _}, fetched), do: Repo.query("CLOSE _ops_cursor")
        build_result(fetched, limit)

      {:error, %Postgrex.Error{} = err} ->
        Repo.rollback(Exception.message(err))

      {:error, reason} ->
        Repo.rollback(inspect(reason))
    end
  end

  defp build_result({:ok, %{columns: cols, rows: rows}}, limit) do
    columns = cols || []

    {kept, truncated?} =
      if length(rows) > limit, do: {Enum.take(rows, limit), true}, else: {rows, false}

    %{columns: columns, rows: rows_with_ids(kept, columns), num_rows: length(kept), truncated?: truncated?}
  end

  defp build_result({:error, %Postgrex.Error{} = err}, _limit), do: Repo.rollback(Exception.message(err))
  defp build_result({:error, reason}, _limit), do: Repo.rollback(inspect(reason))

  defp scalar(sql) do
    case Repo.query(sql) do
      {:ok, %{rows: [[v] | _]}} when not is_nil(v) -> to_string(v)
      _ -> "—"
    end
  end

  defp rows_to_maps(%{rows: rows, columns: cols}) do
    keys = Enum.map(cols, &to_string/1)
    Enum.map(rows, &Map.new(Enum.zip(keys, &1)))
  end

  defp psql_extras(name) do
    name |> EctoPSQLExtras.query(Repo, format: :raw) |> rows_to_maps()
  end

  ## Exports
  #
  # Each formatter takes the `result` map returned by `execute/2` and
  # produces a string in the requested shape. Kept on the backend (not
  # in the LiveView) so the conversion stays unit-testable without
  # spinning up a socket.

  @doc "Render the result rows as a Markdown pipe table."
  def to_markdown(%{columns: cols, rows: rows}) do
    header = "| " <> Enum.join(cols, " | ") <> " |"
    separator = "| " <> Enum.map_join(cols, " | ", fn _ -> "---" end) <> " |"

    body =
      Enum.map_join(rows, "\n", fn row ->
        "| " <>
          Enum.map_join(cols, " | ", fn c -> escape_markdown_cell(Map.get(row, c)) end) <>
          " |"
      end)

    Enum.join([header, separator, body], "\n")
  end

  @doc "Render the result rows as JSON (array of column-keyed objects)."
  def to_json(%{columns: cols, rows: rows}) do
    rows
    |> Enum.map(fn row ->
      Map.new(cols, fn c -> {c, json_safe(Map.get(row, c))} end)
    end)
    |> JSON.encode!()
  end

  @doc "Render the result rows as RFC 4180 CSV with a header row."
  def to_csv(%{columns: cols, rows: rows}) do
    header = Enum.map_join(cols, ",", &csv_escape/1)

    body =
      Enum.map_join(rows, "\n", fn row ->
        Enum.map_join(cols, ",", fn c -> row |> Map.get(c) |> csv_value() |> csv_escape() end)
      end)

    Enum.join([header, body], "\n")
  end

  # JSON has no native datetime — coerce to ISO 8601 so the export is
  # round-trippable in any consumer that expects strings for dates.
  defp json_safe(nil), do: nil
  defp json_safe(%NaiveDateTime{} = v), do: NaiveDateTime.to_iso8601(v)
  defp json_safe(%DateTime{} = v), do: DateTime.to_iso8601(v)
  defp json_safe(%Date{} = v), do: Date.to_iso8601(v)
  defp json_safe(%Time{} = v), do: Time.to_iso8601(v)
  defp json_safe(v) when is_binary(v) or is_number(v) or is_boolean(v), do: v
  defp json_safe(v), do: inspect(v)

  defp csv_value(nil), do: ""
  defp csv_value(v) when is_binary(v), do: v
  defp csv_value(v) when is_number(v) or is_boolean(v), do: to_string(v)
  defp csv_value(%NaiveDateTime{} = v), do: NaiveDateTime.to_iso8601(v)
  defp csv_value(%DateTime{} = v), do: DateTime.to_iso8601(v)
  defp csv_value(%Date{} = v), do: Date.to_iso8601(v)
  defp csv_value(%Time{} = v), do: Time.to_iso8601(v)
  defp csv_value(v), do: inspect(v)

  defp csv_escape(value) do
    s = to_string(value)

    if String.contains?(s, [",", "\"", "\n", "\r"]) do
      ~s("#{String.replace(s, "\"", "\"\"")}")
    else
      s
    end
  end

  # Markdown table cells can't contain raw `|` or newlines without
  # breaking the row shape. Escape pipes and collapse newlines into a
  # visible separator instead of dropping rows on the floor.
  defp escape_markdown_cell(nil), do: ""

  defp escape_markdown_cell(v) do
    v
    |> case do
      %NaiveDateTime{} = d -> NaiveDateTime.to_string(d)
      %DateTime{} = d -> DateTime.to_string(d)
      %Date{} = d -> Date.to_string(d)
      %Time{} = d -> Time.to_string(d)
      bin when is_binary(bin) -> bin
      other when is_number(other) or is_boolean(other) -> to_string(other)
      other -> inspect(other)
    end
    |> String.replace("|", "\\|")
    |> String.replace(~r/\r?\n/, " · ")
  end
end
