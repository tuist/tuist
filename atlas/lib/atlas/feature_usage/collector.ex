defmodule Atlas.FeatureUsage.Collector do
  @moduledoc """
  Computes per-feature usage for an account by querying the Tuist server's
  read-only proxies.

  Attribution to an account is resolved through the **Postgres** proxy (Tuist
  account id + the account's project ids), exactly like
  `Tuist.CommandEvents.account_month_usage/2` does server-side, and then usage is
  aggregated through the **ClickHouse** proxy. The proxy calls are injectable
  seams (`:pg_query` / `:ch_query`) so tests can stub them without global state.

  `:configuration` features (see `Atlas.FeatureUsage.Catalog`) are the exception:
  their signal is a row in Postgres rather than an event stream, so they are
  counted through the Postgres proxy as well.
  """

  alias Atlas.FeatureUsage.Catalog
  alias Atlas.Grafana.Loki
  alias Atlas.TuistServer

  require Logger

  # Scan window. Kept small (just past the 7-day usage window) because
  # `command_events` is not indexed by `project_id`, so an account's query scans
  # every project's rows in the range; a wider window trips the Tuist ClickHouse
  # ops endpoint's execution limit for high-volume accounts. Churn is detected
  # day-over-day from consecutive snapshots, so the prior-7d bucket is not scanned.
  @lookback_days 8

  # Tuist account handles are lowercase slugs; be strict since the handle is
  # interpolated into the (param-less) Postgres proxy query.
  @handle_pattern ~r/\A[a-zA-Z0-9._-]+\z/

  @doc """
  Resolve a Tuist account handle to
  `%{account_handle: binary, account_id: integer, project_ids: [integer]}`.

  Returns `{:error, :not_found}` when no Tuist account matches the handle and
  `{:error, :invalid_handle}` when the handle is not a plain slug.
  """
  def resolve(handle, opts \\ []) when is_binary(handle) do
    pg_query = Keyword.get(opts, :pg_query, &TuistServer.query/2)

    if Regex.match?(@handle_pattern, handle) do
      sql = """
      SELECT a.id AS account_id,
             array_remove(array_agg(p.id), NULL) AS project_ids
      FROM accounts a
      LEFT JOIN projects p ON p.account_id = a.id
      WHERE a.name = '#{escape(handle)}'
      GROUP BY a.id
      """

      case pg_query.(sql, limit: 1) do
        {:ok, %{"rows" => [row | _]}} ->
          {:ok,
           %{
             account_handle: handle,
             account_id: to_integer(Map.get(row, "account_id")),
             project_ids: to_integer_list(Map.get(row, "project_ids"))
           }}

        {:ok, %{"rows" => []}} ->
          {:error, :not_found}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :invalid_handle}
    end
  end

  @doc """
  Measure every catalog feature for a resolved account.

  Returns `{:ok, [metrics]}` where each entry is
  `%{feature: slug, events_last_24h:, events_last_7d:, events_prior_7d:, last_used_at:}`.
  Features that cannot be attributed (e.g. an account with no projects for a
  project-scoped feature) report zeroes rather than failing the whole batch.
  """
  def measure(resolution, opts \\ []) when is_map(resolution) do
    ch_query = Keyword.get(opts, :ch_query, &TuistServer.clickhouse_query/2)
    pg_query = Keyword.get(opts, :pg_query, &TuistServer.query/2)
    loki_query = Keyword.get(opts, :loki_query, &Loki.mcp_usage/1)

    # Every (feature, source) pair, grouped so sources that hit the same table
    # with the same attribution and time expression are answered by a single
    # scan with conditional aggregation. This matters most for `command_events`,
    # which backs several features/probes — one scan instead of one per source.
    members = for feature <- Catalog.tracked(), source <- feature.sources, do: {feature.slug, source}
    {postgres_members, remaining_members} = Enum.split_with(members, &postgres?/1)
    {loki_members, clickhouse_members} = Enum.split_with(remaining_members, &loki?/1)
    groups = Enum.group_by(clickhouse_members, fn {_slug, source} -> group_key(source) end)

    queries =
      Enum.map(groups, fn {_key, group_members} -> fn -> run_group_query(group_members, resolution, ch_query) end end) ++
        Enum.map(postgres_members, fn member -> fn -> run_postgres_query(member, resolution, pg_query) end end) ++
        Enum.map(loki_members, fn member -> fn -> run_loki_query(member, resolution, loki_query) end end)

    queries
    |> Enum.reduce_while({:ok, initial_metrics()}, fn run, {:ok, acc} ->
      case run.() do
        {:ok, results} -> {:cont, {:ok, accumulate(acc, results)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, by_slug} -> {:ok, Enum.map(Catalog.tracked(), &Map.fetch!(by_slug, &1.slug))}
      {:error, reason} -> {:error, reason}
    end
  end

  defp postgres?({_slug, source}), do: Map.get(source, :store, :clickhouse) == :postgres
  defp loki?({_slug, source}), do: Map.get(source, :store, :clickhouse) == :loki

  defp group_key(source) do
    {source.table, source.attribution, Map.get(source, :account_column), source.time_expr,
     Map.get(source, :index_column)}
  end

  defp initial_metrics do
    Map.new(Catalog.tracked(), fn feature -> {feature.slug, empty_metrics(feature.slug)} end)
  end

  # A feature can span several sources (e.g. Apple + Android builds), so we sum
  # each source's metrics into the feature, keeping the most recent "last used".
  defp accumulate(by_slug, results) do
    Enum.reduce(results, by_slug, fn {slug, metrics}, acc ->
      Map.update!(acc, slug, &merge_metrics(&1, metrics))
    end)
  end

  defp run_group_query(members, resolution, ch_query) do
    [{_slug, sample} | _] = members

    case attribution_clause(sample, resolution) do
      :zero ->
        {:ok, Enum.map(members, fn {slug, _source} -> {slug, empty_metrics(nil)} end)}

      {where, params} ->
        # Bound the scan on the primary/sort column when the source names one
        # (`command_events` sorts by `created_at`), so ClickHouse prunes parts
        # instead of scanning the whole table; otherwise bound on the timestamp.
        bound_column = Map.get(sample, :index_column) || sample.time_expr
        selects = members |> Enum.with_index() |> Enum.flat_map(&member_selects/1)

        sql = """
        SELECT #{Enum.join(selects, ", ")}
        FROM #{sample.table}
        WHERE #{where}
          AND #{bound_column} >= now() - INTERVAL #{@lookback_days} DAY
        """

        case ch_query.(sql, params: params, limit: 1) do
          {:ok, %{"rows" => [row | _]}} ->
            {:ok, members |> Enum.with_index() |> Enum.map(fn {{slug, _source}, i} -> {slug, parse_member(row, i)} end)}

          {:ok, %{"rows" => []}} ->
            {:ok, Enum.map(members, fn {slug, _source} -> {slug, empty_metrics(nil)} end)}

          {:error, reason} ->
            Logger.warning("Feature usage query failed for #{sample.table}: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  # A `:configuration` source is a state, not a stream: count the rows the
  # account has set up rather than events over a window. `events_last_7d` holds
  # the in-use (e.g. enabled) rows, so the shared `active = events_last_7d > 0`
  # rule keeps working; `events_last_24h` holds the total including rows that
  # are set up but turned off, unless the source supplies a narrower
  # `:total_predicate`; and `last_used_at` is the last change.
  defp run_postgres_query({slug, source}, resolution, pg_query) do
    case postgres_scope(source, resolution) do
      :zero ->
        {:ok, [{slug, empty_metrics(nil)}]}

      {:ok, where} ->
        predicate = source.predicate || "TRUE"
        total_predicate = Map.get(source, :total_predicate, "TRUE")

        sql = """
        SELECT count(*) FILTER (WHERE #{predicate}) AS in_use_count,
               count(*) FILTER (WHERE #{total_predicate}) AS total_count,
               max(#{source.time_expr}) FILTER (WHERE #{predicate}) AS last_changed_at
        FROM #{source.table}
        WHERE #{where}
        """

        case pg_query.(sql, limit: 1) do
          {:ok, %{"rows" => [row | _]}} ->
            {:ok, [{slug, parse_postgres_row(row)}]}

          {:ok, %{"rows" => []}} ->
            {:ok, [{slug, empty_metrics(nil)}]}

          {:error, reason} ->
            Logger.warning("Feature usage query failed for #{source.table}: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  defp run_loki_query({slug, _source}, %{account_handle: account_handle}, loki_query) when is_binary(account_handle) do
    case loki_query.(account_handle) do
      {:ok, metrics} ->
        {:ok, [{slug, metrics}]}

      {:error, reason} ->
        Logger.warning("Feature usage query failed for Grafana Loki: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp run_loki_query({slug, _source}, _resolution, _loki_query), do: {:ok, [{slug, empty_metrics(slug)}]}

  # The Postgres proxy takes no bound parameters, so ids are inlined; they come
  # from `resolve/2` as integers and are re-checked here so nothing else can
  # reach the SQL string.
  defp postgres_scope(%{attribution: :project_ids}, %{project_ids: [_ | _] = ids}) do
    if Enum.all?(ids, &is_integer/1) do
      {:ok, "project_id IN (#{Enum.map_join(ids, ", ", &Integer.to_string/1)})"}
    else
      :zero
    end
  end

  defp postgres_scope(%{attribution: :account_id} = source, %{account_id: account_id}) when is_integer(account_id),
    do: {:ok, "#{source.account_column} = #{account_id}"}

  defp postgres_scope(_source, _resolution), do: :zero

  defp parse_postgres_row(row) do
    %{
      feature: nil,
      events_last_24h: to_integer(Map.get(row, "total_count")),
      events_last_7d: to_integer(Map.get(row, "in_use_count")),
      events_prior_7d: 0,
      last_used_at: to_datetime(Map.get(row, "last_changed_at"))
    }
  end

  defp attribution_clause(%{attribution: :project_ids}, %{project_ids: []}), do: :zero

  defp attribution_clause(%{attribution: :project_ids}, %{project_ids: ids}),
    do: {"project_id IN {project_ids:Array(Int64)}", %{"project_ids" => ids}}

  defp attribution_clause(%{attribution: :account_id} = source, %{account_id: account_id}) when is_integer(account_id),
    do: {"#{source.account_column} = {account_id:Int64}", %{"account_id" => account_id}}

  defp attribution_clause(_source, _resolution), do: :zero

  # Conditional aggregation columns for one group member (feature/probe), scoped
  # to its own predicate so a single scan answers every member independently.
  defp member_selects({{_slug, source}, index}) do
    time = source.time_expr
    predicate = source.predicate || "1"

    [
      "countIf((#{time} >= now() - INTERVAL 1 DAY) AND (#{predicate})) AS c#{index}_24h",
      "countIf((#{time} >= now() - INTERVAL 7 DAY) AND (#{predicate})) AS c#{index}_7d",
      "maxIf(#{time}, #{predicate}) AS c#{index}_last"
    ]
  end

  # The prior-7d bucket is intentionally not scanned (see @lookback_days); churn
  # is detected day-over-day, so it is always reported as zero.
  defp parse_member(row, index) do
    %{
      events_last_24h: to_integer(Map.get(row, "c#{index}_24h")),
      events_last_7d: to_integer(Map.get(row, "c#{index}_7d")),
      events_prior_7d: 0,
      last_used_at: to_datetime(Map.get(row, "c#{index}_last"))
    }
  end

  defp merge_metrics(acc, source) do
    %{
      acc
      | events_last_24h: acc.events_last_24h + source.events_last_24h,
        events_last_7d: acc.events_last_7d + source.events_last_7d,
        events_prior_7d: acc.events_prior_7d + source.events_prior_7d,
        last_used_at: latest(acc.last_used_at, source.last_used_at)
    }
  end

  defp latest(nil, other), do: other
  defp latest(one, nil), do: one
  defp latest(one, other), do: if(DateTime.after?(one, other), do: one, else: other)

  defp empty_metrics(slug) do
    %{feature: slug, events_last_24h: 0, events_last_7d: 0, events_prior_7d: 0, last_used_at: nil}
  end

  defp escape(handle), do: String.replace(handle, "'", "''")

  defp to_integer(value) when is_integer(value), do: value
  defp to_integer(value) when is_binary(value), do: value |> Integer.parse() |> elem_or_zero()
  defp to_integer(_value), do: 0

  defp elem_or_zero({int, _rest}), do: int
  defp elem_or_zero(:error), do: 0

  defp to_integer_list(list) when is_list(list), do: Enum.map(list, &to_integer/1)

  # The Postgres proxy serializes array columns (e.g. `array_agg(p.id)`) as a
  # JSON string like "[1227]" rather than a native list, so decode it.
  defp to_integer_list(value) when is_binary(value) do
    case JSON.decode(value) do
      {:ok, list} when is_list(list) -> Enum.map(list, &to_integer/1)
      _ -> []
    end
  end

  defp to_integer_list(_value), do: []

  # ClickHouse serializes DateTime64 as a string; a zero/epoch value means "never".
  defp to_datetime(nil), do: nil
  defp to_datetime(""), do: nil

  defp to_datetime(value) when is_binary(value) do
    case parse_datetime(value) do
      %DateTime{year: year} = datetime when year > 1970 -> DateTime.truncate(datetime, :second)
      _ -> nil
    end
  end

  defp to_datetime(_value), do: nil

  defp parse_datetime(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        datetime

      {:error, _reason} ->
        # ClickHouse commonly returns "YYYY-MM-DD HH:MM:SS[.ffffff]" (no zone).
        case NaiveDateTime.from_iso8601(String.replace(value, " ", "T")) do
          {:ok, naive} -> DateTime.from_naive!(naive, "Etc/UTC")
          {:error, _reason} -> nil
        end
    end
  end
end
