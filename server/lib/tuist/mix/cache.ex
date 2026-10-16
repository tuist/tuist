defmodule Tuist.Mix.Cache do
  @moduledoc "Dependency-cache ingestion and project-scoped analytics for Mix."

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Mix.Build
  alias Tuist.Mix.CacheEvent
  alias Tuist.Repo

  @outcomes ~w(local_hit remote_hit miss bypass)
  @reasons ~w(not_enabled local_dependency custom_compiler unmodeled_input inputs_changed store_failed)
  @max_events 5_000
  @scatter_limit 10_000
  @uint32 4_294_967_295
  @int64 9_223_372_036_854_775_807

  def validate(events) when is_list(events) and length(events) <= @max_events do
    names = Enum.map(events, &field(&1, :dependency))

    if Enum.all?(events, &valid?/1) and length(Enum.uniq(names)) == length(names),
      do: :ok,
      else: {:error, :invalid_dependency_cache}
  end

  def validate(_events), do: {:error, :invalid_dependency_cache}

  def insert(attrs, now) do
    attrs
    |> Map.get(:dependency_cache, [])
    |> Enum.map(fn event ->
      %{
        project_id: attrs.project_id,
        build_id: attrs.id,
        dependency: field(event, :dependency),
        outcome: field(event, :outcome),
        reason: field(event, :reason) || "",
        key: field(event, :key) || "",
        duration_ms: field(event, :duration_ms),
        saved_duration_ms: field(event, :saved_duration_ms),
        read_bytes: field(event, :read_bytes),
        write_bytes: field(event, :write_bytes),
        read_source: field(event, :read_source),
        write_source: field(event, :write_source),
        read_duration_us: field(event, :read_duration_us),
        write_duration_us: field(event, :write_duration_us),
        is_ci: Map.get(attrs, :is_ci, false),
        mix_env: Map.get(attrs, :mix_env) || "",
        git_branch: Map.get(attrs, :git_branch) || "",
        inserted_at: DateTime.from_naive!(now, "Etc/UTC")
      }
    end)
    |> CacheEvent.Buffer.insert_all()
  end

  def summary(project_id, opts) do
    project_id |> query(opts) |> totals() |> ClickHouseRepo.one() |> rates()
  end

  def timeseries(project_id, opts) do
    project_id
    |> query(opts)
    |> group_by([e], fragment("toDate(?)", e.inserted_at))
    |> order_by([e], asc: fragment("toDate(?)", e.inserted_at))
    |> totals()
    |> select_merge([e], %{date: fragment("toDate(?)", e.inserted_at)})
    |> ClickHouseRepo.all()
    |> Enum.map(&rates/1)
  end

  def hit_rate_analytics(project_id, opts) do
    current = project_id |> lookup_rates(opts) |> hit_rate_statistics()
    start_datetime = Keyword.fetch!(opts, :start_datetime)
    end_datetime = Keyword.fetch!(opts, :end_datetime)
    seconds = NaiveDateTime.diff(naive_datetime(end_datetime), naive_datetime(start_datetime), :second)

    previous_opts =
      opts
      |> Keyword.put(:start_datetime, shift_datetime(start_datetime, -seconds))
      |> Keyword.put(:end_datetime, start_datetime)

    previous = project_id |> lookup_rates(previous_opts) |> hit_rate_statistics()
    trends = Map.new(current, fn {metric, value} -> {metric, rate_trend(value, Map.fetch!(previous, metric))} end)

    series =
      ClickHouseRepo.all(
        from(b in subquery(lookup_rates(project_id, opts)),
          group_by: fragment("toDate(?)", b.inserted_at),
          order_by: [asc: fragment("toDate(?)", b.inserted_at)],
          select: %{
            date: fragment("toDate(?)", b.inserted_at),
            avg: avg(b.hit_rate),
            p50: fragment("quantileExact(0.50)(?)", b.hit_rate),
            p90: fragment("quantileExact(0.90)(?)", b.hit_rate),
            p99: fragment("quantileExact(0.99)(?)", b.hit_rate)
          }
        )
      )

    %{metrics: current, trends: trends, series: series}
  end

  defp lookup_rates(project_id, opts) do
    project_id
    |> query(opts)
    |> group_by([e], e.build_id)
    |> having([e], fragment("countIf(? IN ('local_hit', 'remote_hit', 'miss')) > 0", e.outcome))
    |> select([e], %{
      inserted_at: fragment("max(?)", e.inserted_at),
      hit_rate:
        fragment(
          "countIf(? IN ('local_hit', 'remote_hit')) / countIf(? IN ('local_hit', 'remote_hit', 'miss')) * 100.0",
          e.outcome,
          e.outcome
        )
    })
  end

  defp hit_rate_statistics(query) do
    ClickHouseRepo.one(
      from(b in subquery(query),
        select: %{
          avg: fragment("avgOrNull(?)", b.hit_rate),
          p50: fragment("quantileExactOrNull(0.50)(?)", b.hit_rate),
          p90: fragment("quantileExactOrNull(0.90)(?)", b.hit_rate),
          p99: fragment("quantileExactOrNull(0.99)(?)", b.hit_rate)
        }
      )
    )
  end

  defp naive_datetime(%DateTime{} = value), do: DateTime.to_naive(value)
  defp naive_datetime(value), do: value
  defp shift_datetime(%DateTime{} = value, seconds), do: DateTime.add(value, seconds, :second)
  defp shift_datetime(value, seconds), do: NaiveDateTime.add(value, seconds, :second)
  defp rate_trend(nil, _), do: nil
  defp rate_trend(_, nil), do: nil
  defp rate_trend(current, previous) when previous > 0, do: (current - previous) / previous * 100
  defp rate_trend(current, previous) when current == 0 and previous == 0, do: 0
  defp rate_trend(_, _), do: nil

  def io_analytics(project_id, opts) do
    current = project_id |> query(opts) |> io_totals() |> ClickHouseRepo.one() |> io_metrics()
    start_datetime = Keyword.fetch!(opts, :start_datetime)

    seconds =
      NaiveDateTime.diff(naive_datetime(Keyword.fetch!(opts, :end_datetime)), naive_datetime(start_datetime), :second)

    previous_opts =
      opts
      |> Keyword.put(:start_datetime, shift_datetime(start_datetime, -seconds))
      |> Keyword.put(:end_datetime, start_datetime)

    previous = project_id |> query(previous_opts) |> io_totals() |> ClickHouseRepo.one() |> io_metrics()

    daily =
      project_id
      |> query(opts)
      |> group_by([e], fragment("toDate(?)", e.inserted_at))
      |> order_by([e], asc: fragment("toDate(?)", e.inserted_at))
      |> io_totals()
      |> select_merge([e], %{date: fragment("toDate(?)", e.inserted_at)})
      |> ClickHouseRepo.all()

    Map.new(current, fn {widget, metrics} ->
      trends = Map.new(metrics, fn {type, value} -> {type, rate_trend(value, previous[widget][type])} end)
      series = Enum.map(daily, &Map.put(io_metrics(&1)[widget], :date, &1.date))
      {widget, %{metrics: metrics, trends: trends, series: series}}
    end)
  end

  defp io_totals(query) do
    select(query, [e], %{
      read_bytes: fragment("sumOrNull(?)", e.read_bytes),
      write_bytes: fragment("sumOrNull(?)", e.write_bytes),
      read_us: fragment("sumOrNull(?)", e.read_duration_us),
      write_us: fragment("sumOrNull(?)", e.write_duration_us),
      reads: fragment("countIf(isNotNull(?))", e.read_duration_us),
      writes: fragment("countIf(isNotNull(?))", e.write_duration_us)
    })
  end

  defp io_metrics(row) do
    bytes = sum_available(row.read_bytes, row.write_bytes)
    duration = sum_available(row.read_us, row.write_us)

    %{
      transfer: %{"combined" => bytes, "downloads" => row.read_bytes, "uploads" => row.write_bytes},
      latency: %{
        "combined" => average_latency(duration, row.reads + row.writes),
        "read" => average_latency(row.read_us, row.reads),
        "write" => average_latency(row.write_us, row.writes)
      },
      throughput: %{
        "combined" => bytes_per_second(bytes, duration),
        "downloads" => bytes_per_second(row.read_bytes, row.read_us),
        "uploads" => bytes_per_second(row.write_bytes, row.write_us)
      }
    }
  end

  defp sum_available(nil, nil), do: nil
  defp sum_available(left, right), do: (left || 0) + (right || 0)
  defp average_latency(nil, _), do: nil
  defp average_latency(duration, operations) when operations > 0, do: duration / operations / 1_000
  defp average_latency(_, _), do: nil

  defp bytes_per_second(bytes, duration) when is_number(bytes) and is_number(duration) and duration > 0,
    do: bytes / duration * 1_000_000

  defp bytes_per_second(_, _), do: nil

  def hit_rate_scatter_data(project_id, opts) do
    results =
      project_id
      |> query(opts)
      |> group_by([e], e.build_id)
      |> having([e], fragment("countIf(? IN ('local_hit', 'remote_hit', 'miss')) > 0", e.outcome))
      |> order_by([e], desc: fragment("max(?)", e.inserted_at), desc: e.build_id)
      |> limit(^(@scatter_limit + 1))
      |> totals()
      |> select_merge([e], %{
        id: e.build_id,
        inserted_at: fragment("max(?)", e.inserted_at),
        is_ci: fragment("argMax(?, ?)", e.is_ci, e.inserted_at)
      })
      |> ClickHouseRepo.all()

    rows = Enum.take(results, @scatter_limit)
    truncated = length(results) > @scatter_limit

    series =
      rows
      |> Enum.group_by(& &1.is_ci)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {is_ci, builds} ->
        %{
          name: is_ci,
          data:
            Enum.map(builds, fn build ->
              %{
                id: build.id,
                value: [DateTime.to_unix(build.inserted_at, :millisecond), rates(build).hit_rate]
              }
            end)
        }
      end)

    %{
      series: series,
      truncated: truncated,
      oldest_entry: if(truncated, do: rows |> List.last() |> Map.fetch!(:inserted_at) |> DateTime.to_naive())
    }
  end

  def recent_builds(project_id, opts) do
    start_datetime = Keyword.fetch!(opts, :start_datetime)
    end_datetime = Keyword.fetch!(opts, :end_datetime)

    builds_query =
      from b in Build,
        where: b.project_id == ^project_id and b.inserted_at >= ^start_datetime and b.inserted_at < ^end_datetime,
        order_by: [desc: b.inserted_at, desc: b.id]

    builds_query =
      case Keyword.get(opts, :is_ci) do
        value when is_boolean(value) -> where(builds_query, [b], b.is_ci == ^value)
        _ -> builds_query
      end

    limit = opts |> Keyword.get(:limit, 7) |> max(1) |> min(50)
    # ClickHouse applies DISTINCT before ORDER BY; sort retries in the subquery first.
    builds =
      from(b in subquery(builds_query), distinct: b.id, order_by: [desc: b.inserted_at, desc: b.id], limit: ^limit)
      |> ClickHouseRepo.all()
      |> Repo.preload(:ran_by_account)

    recent_build_rows(builds, project_id, opts)
  end

  def recent_hit_rate(rows) do
    rates = rows |> Enum.map(& &1.cache.hit_rate) |> Enum.reject(&is_nil/1)
    if rates != [], do: Enum.sum(rates) / length(rates)
  end

  defp recent_build_rows([], _project_id, _opts), do: []

  defp recent_build_rows(builds, project_id, opts) do
    ids = Enum.map(builds, & &1.id)

    observations =
      project_id
      |> query(opts)
      |> where([e], e.build_id in ^ids)
      |> group_by([e], e.build_id)
      |> totals()
      |> select_merge([e], %{build_id: e.build_id})
      |> ClickHouseRepo.all()
      |> Map.new(&{&1.build_id, rates(&1)})

    empty = rates(%{hits: 0, misses: 0, bypasses: 0, savings_observations: 0, saved_duration_ms: 0})
    Enum.map(builds, &%{build: &1, cache: Map.get(observations, &1.id, empty)})
  end

  def build_summary(project_id, build_id) do
    project_id
    |> build_query(build_id)
    |> totals()
    |> select_merge([e], %{
      local_hits: fragment("countIf(? = 'local_hit')", e.outcome),
      remote_hits: fragment("countIf(? = 'remote_hit')", e.outcome),
      read_bytes: fragment("sumOrNull(?)", e.read_bytes),
      write_bytes: fragment("sumOrNull(?)", e.write_bytes),
      avg_read_duration_us: fragment("avgOrNull(?)", e.read_duration_us),
      p50_read_duration_us: fragment("quantileExactOrNull(0.50)(?)", e.read_duration_us),
      p90_read_duration_us: fragment("quantileExactOrNull(0.90)(?)", e.read_duration_us),
      p99_read_duration_us: fragment("quantileExactOrNull(0.99)(?)", e.read_duration_us),
      avg_write_duration_us: fragment("avgOrNull(?)", e.write_duration_us),
      p50_write_duration_us: fragment("quantileExactOrNull(0.50)(?)", e.write_duration_us),
      p90_write_duration_us: fragment("quantileExactOrNull(0.90)(?)", e.write_duration_us),
      p99_write_duration_us: fragment("quantileExactOrNull(0.99)(?)", e.write_duration_us)
    })
    |> ClickHouseRepo.one()
    |> rates()
  end

  def build_events(project_id, build_id, opts \\ []) do
    project_id |> build_query(build_id) |> event_page(opts)
  end

  def events(project_id, opts) do
    project_id |> query(opts) |> event_page(opts)
  end

  defp build_query(project_id, build_id) do
    from e in CacheEvent, hints: ["FINAL"], where: e.project_id == ^project_id and e.build_id == ^build_id
  end

  defp event_page(base, opts) do
    page = max(Keyword.get(opts, :page, 1), 1)
    search = Keyword.get(opts, :search, "")
    base = where(base, [e], fragment("positionCaseInsensitive(?, ?) > 0", e.dependency, ^search))

    base =
      case Keyword.get(opts, :outcome) do
        outcome when outcome in @outcomes -> where(base, [e], e.outcome == ^outcome)
        _ -> base
      end

    total = ClickHouseRepo.aggregate(base, :count)

    base =
      case Keyword.get(opts, :sort_order) do
        direction when direction in [:asc, :desc] ->
          order_by(base, [e], [{^direction, e.dependency}, desc: e.inserted_at, asc: e.build_id])

        _ ->
          order_by(base, [e], desc: e.inserted_at, asc: e.build_id, asc: e.dependency)
      end

    rows =
      base
      |> limit(20)
      |> offset(^((page - 1) * 20))
      |> ClickHouseRepo.all()

    %{rows: rows, total: total, page: page}
  end

  defp query(project_id, opts) do
    start_datetime = Keyword.fetch!(opts, :start_datetime)
    end_datetime = Keyword.fetch!(opts, :end_datetime)

    query =
      from e in CacheEvent,
        hints: ["FINAL"],
        where: e.project_id == ^project_id and e.inserted_at >= ^start_datetime and e.inserted_at < ^end_datetime

    case Keyword.get(opts, :is_ci) do
      value when is_boolean(value) -> where(query, [e], e.is_ci == ^value)
      _ -> query
    end
  end

  defp totals(query) do
    select(query, [e], %{
      hits: fragment("countIf(? IN ('local_hit', 'remote_hit'))", e.outcome),
      misses: fragment("countIf(? = 'miss')", e.outcome),
      bypasses: fragment("countIf(? = 'bypass')", e.outcome),
      saved_duration_ms: fragment("sumIf(?, ? IN ('local_hit', 'remote_hit'))", e.saved_duration_ms, e.outcome),
      savings_observations:
        fragment("countIf(? IN ('local_hit', 'remote_hit') AND isNotNull(?))", e.outcome, e.saved_duration_ms)
    })
  end

  defp rates(row) do
    lookups = row.hits + row.misses

    row
    |> Map.put(:hit_rate, if(lookups > 0, do: row.hits / lookups * 100))
    |> Map.update!(:saved_duration_ms, fn value -> if row.savings_observations > 0, do: value end)
  end

  defp valid?(event) when is_map(event) do
    outcome = field(event, :outcome)
    reason = field(event, :reason) || ""
    key = field(event, :key) || ""
    name = field(event, :dependency)

    valid_name?(name) and outcome in @outcomes and reason in ["" | @reasons] and
      valid_key?(key, outcome) and valid_metrics?(event, outcome)
  end

  defp valid?(_), do: false

  defp valid_metrics?(event, outcome) do
    uint32?(field(event, :duration_ms)) and valid_savings?(field(event, :saved_duration_ms), outcome) and
      valid_io?(event, :read_bytes, :read_duration_us, outcome in ["local_hit", "remote_hit"]) and
      valid_io?(event, :write_bytes, :write_duration_us, outcome == "miss") and
      valid_source?(event, :read_source, :read_bytes, read_source(outcome)) and
      valid_source?(event, :write_source, :write_bytes, if(outcome == "miss", do: ["local", "remote"], else: []))
  end

  defp valid_io?(event, bytes_key, duration_key, allowed) do
    case {field(event, bytes_key), field(event, duration_key)} do
      {nil, nil} -> true
      {bytes, duration} -> allowed and non_negative_int64?(bytes) and non_negative_int64?(duration)
    end
  end

  defp read_source("local_hit"), do: ["local"]
  defp read_source("remote_hit"), do: ["remote"]
  defp read_source(_), do: []

  defp valid_source?(event, source_key, bytes_key, allowed) do
    source = field(event, source_key)
    is_nil(source) or (source in allowed and not is_nil(field(event, bytes_key)))
  end

  defp non_negative_int64?(value), do: is_integer(value) and value >= 0 and value <= @int64
  defp valid_name?(name) when is_binary(name), do: byte_size(name) in 1..1_024
  defp valid_name?(_), do: false
  defp valid_savings?(nil, _), do: true
  defp valid_savings?(value, outcome) when outcome in ["local_hit", "remote_hit"], do: uint32?(value)
  defp valid_savings?(_, _), do: false
  defp valid_key?("", "bypass"), do: true
  defp valid_key?(key, _) when is_binary(key), do: Regex.match?(~r/^[a-f0-9]{64}$/, key)
  defp valid_key?(_, _), do: false
  defp uint32?(value), do: is_integer(value) and value >= 0 and value <= @uint32
  defp field(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp field(_, _), do: nil
end
