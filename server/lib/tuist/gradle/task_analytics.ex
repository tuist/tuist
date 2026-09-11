defmodule Tuist.Gradle.TaskAnalytics do
  @moduledoc """
  Task rankings across comparable Gradle builds. Cumulative task
  duration is work observed across executions, not elapsed build time saved.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Gradle.Build
  alias Tuist.Gradle.Task
  alias Tuist.Repo

  @max_entities 10_000

  def analytics(project_id, opts \\ []) do
    start_at = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_at = Keyword.get(opts, :end_datetime, DateTime.utc_now())
    opts = Keyword.merge(opts, start_datetime: start_at, end_datetime: end_at)

    period =
      cond do
        DateTime.diff(end_at, start_at, :hour) <= 24 -> :hour
        DateTime.diff(end_at, start_at, :day) >= 60 -> :month
        true -> :day
      end

    format =
      case period do
        :hour -> "%Y-%m-%d %H:00:00"
        :day -> "%Y-%m-%d"
        :month -> "%Y-%m"
      end

    query = task_query(project_id, opts)
    total = query |> select_metrics() |> ClickHouseRepo.one() |> normalize_metrics()

    buckets =
      query
      |> group_by([_t, b], fragment("formatDateTime(?, ?, 'UTC')", b.inserted_at, ^format))
      |> select_metrics()
      |> select_merge([_t, b], %{date: fragment("formatDateTime(?, ?, 'UTC')", b.inserted_at, ^format)})
      |> ClickHouseRepo.all()
      |> Map.new(fn point -> {point.date, normalize_metrics(point)} end)

    previous_opts =
      Keyword.merge(opts,
        start_datetime: DateTime.add(start_at, -DateTime.diff(end_at, start_at, :microsecond), :microsecond),
        end_datetime: DateTime.add(start_at, -1, :microsecond)
      )

    previous = project_id |> task_query(previous_opts) |> select_metrics() |> ClickHouseRepo.one() |> normalize_metrics()

    zero = %{
      tasks: 0,
      builds: 0,
      executions: 0,
      hits: 0,
      hit_rate: nil,
      cacheability: :unknown,
      misses: 0,
      avg_duration_ms: nil,
      p50_duration_ms: nil,
      p90_duration_ms: nil,
      p99_duration_ms: nil
    }

    points =
      Enum.map(bucket_dates(start_at, end_at, period, format), fn date ->
        Map.put(Map.get(buckets, date, zero), :date, date)
      end)

    %{total: total, previous: previous, points: points, period: period}
  end

  defp select_metrics(query) do
    select(query, [t, b], %{
      tasks: fragment("uniqExact(tuple(?, ?, ?, ?))", b.root_project_name, t.build_path, t.task_path, t.task_type),
      builds: fragment("uniqExact(?)", t.gradle_build_id),
      executions: fragment("countIf(? = 'executed')", t.outcome),
      misses: fragment("countIf(?)", t.remote_cache_miss),
      hits: fragment("countIf(? = 'remote_hit')", t.outcome),
      observations: count(),
      cacheable_observations:
        fragment(
          "countIf((? = '' AND ?) OR ? = 'cacheable' OR ? IN ('remote_hit', 'local_hit', 'cache_hit') OR ?)",
          t.cacheability,
          t.cacheable,
          t.cacheability,
          t.outcome,
          t.remote_cache_miss
        ),
      non_cacheable_observations:
        fragment("countIf(? = 'disabled' OR (? = '' AND NOT ?))", t.cacheability, t.cacheability, t.cacheable),
      avg_duration_ms: fragment("avgIf(?, ? = 'executed')", t.duration_ms, t.outcome),
      p50_duration_ms: fragment("quantileIf(0.5)(?, ? = 'executed')", t.duration_ms, t.outcome),
      p90_duration_ms: fragment("quantileIf(0.9)(?, ? = 'executed')", t.duration_ms, t.outcome),
      p99_duration_ms: fragment("quantileIf(0.99)(?, ? = 'executed')", t.duration_ms, t.outcome)
    })
  end

  defp normalize_metrics(metrics) do
    cacheability = if metrics.observations == 0, do: :unknown, else: cacheability(metrics)
    lookups = metrics.hits + metrics.misses

    hit_rate =
      cond do
        lookups > 0 -> Float.round(metrics.hits / lookups * 100, 1)
        cacheability == :cacheable -> 0.0
        true -> nil
      end

    metrics =
      metrics
      |> Map.drop([:observations, :cacheable_observations, :non_cacheable_observations])
      |> Map.merge(%{hit_rate: hit_rate, cacheability: cacheability})

    Enum.reduce([:avg_duration_ms, :p50_duration_ms, :p90_duration_ms, :p99_duration_ms], metrics, fn field, metrics ->
      Map.update!(metrics, field, &if(metrics.executions > 0 and is_number(&1), do: round(&1)))
    end)
  end

  defp bucket_dates(start_at, end_at, :hour, format) do
    start_at = %{start_at | minute: 0, second: 0, microsecond: {0, 0}}

    Enum.map(0..DateTime.diff(end_at, start_at, :hour), fn offset ->
      start_at |> DateTime.add(offset, :hour) |> Calendar.strftime(format)
    end)
  end

  defp bucket_dates(start_at, end_at, _period, format) do
    start_at
    |> DateTime.to_date()
    |> Date.range(DateTime.to_date(end_at))
    |> Enum.map(&Calendar.strftime(&1, format))
    |> Enum.uniq()
  end

  def list(project_id, opts \\ []) do
    query = task_query(project_id, opts)

    query =
      from [t, b] in query,
        group_by: [b.root_project_name, t.build_path, t.task_path, t.task_type],
        select: %{
          root_project_name: b.root_project_name,
          build_path: t.build_path,
          name: t.task_path,
          task_type: t.task_type
        }

    rows =
      query
      |> select_merge([t, b], %{
        executions: fragment("countIf(? = 'executed')", t.outcome),
        misses: fragment("countIf(?)", t.remote_cache_miss),
        remote_hits: fragment("countIf(? = 'remote_hit')", t.outcome),
        observations: count(),
        cacheable_observations:
          fragment(
            "countIf((? = '' AND ?) OR ? = 'cacheable' OR ? IN ('remote_hit', 'local_hit', 'cache_hit') OR ?)",
            t.cacheability,
            t.cacheable,
            t.cacheability,
            t.outcome,
            t.remote_cache_miss
          ),
        non_cacheable_observations:
          fragment("countIf(? = 'disabled' OR (? = '' AND NOT ?))", t.cacheability, t.cacheability, t.cacheable),
        cumulative_duration_ms: fragment("sumIf(?, ? = 'executed')", t.duration_ms, t.outcome),
        p50_duration_ms: fragment("quantileIf(0.5)(?, ? = 'executed')", t.duration_ms, t.outcome),
        p90_duration_ms: fragment("quantileIf(0.9)(?, ? = 'executed')", t.duration_ms, t.outcome),
        p99_duration_ms: fragment("quantileIf(0.99)(?, ? = 'executed')", t.duration_ms, t.outcome)
      })
      |> order_by([t], desc: fragment("sumIf(?, ? = 'executed')", t.duration_ms, t.outcome))
      |> limit(^(@max_entities + 1))
      |> ClickHouseRepo.all()

    %{
      rows: rows |> Enum.take(@max_entities) |> Enum.map(&normalize/1),
      truncated: length(rows) > @max_entities
    }
  end

  def task_executions(project_id, name, opts \\ []) do
    query = project_id |> task_query(opts) |> where([t], t.task_path == ^name)
    search = Keyword.get(opts, :execution_search, "")

    query =
      if search == "" do
        query
      else
        where(
          query,
          [_t, b],
          fragment(
            "positionCaseInsensitiveUTF8(concat(?, ' ', ?, ' ', ?), ?) > 0",
            b.root_project_name,
            b.git_branch,
            b.git_commit_sha,
            ^search
          )
        )
      end

    count = query |> select([t], count(t.id)) |> ClickHouseRepo.one()
    total_pages = max(ceil(count / 25), 1)
    page = min(max(Keyword.get(opts, :execution_page, 1), 1), total_pages)
    sort = Keyword.get(opts, :execution_sort, "ran_at")
    order = if Keyword.get(opts, :execution_order) == "asc", do: :asc, else: :desc

    query =
      if sort == "duration" do
        order_by(query, [t], [{^order, t.duration_ms}])
      else
        order_by(query, [t, b], [{^order, fragment("coalesce(?, ?)", t.started_at, b.inserted_at)}])
      end

    rows =
      query
      |> order_by([t], desc: t.id)
      |> select([t, b], %{
        id: t.id,
        build_id: b.id,
        build: struct(b, [:id, :root_project_name, :custom_tags, :account_id, :is_ci]),
        git_branch: b.git_branch,
        outcome: t.outcome,
        duration_ms: t.duration_ms,
        ran_at: fragment("coalesce(?, ?)", t.started_at, b.inserted_at)
      })
      |> limit(25)
      |> offset(^((page - 1) * 25))
      |> ClickHouseRepo.all()

    builds = Repo.preload(Enum.map(rows, & &1.build), :built_by_account)
    rows = Enum.zip_with(rows, builds, &Map.put(&1, :build, &2))

    %{rows: rows, page: page, total_pages: total_pages}
  end

  defp build_query(project_id, opts) do
    start_at = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_at = Keyword.get(opts, :end_datetime, DateTime.utc_now())

    from(b in Build,
      where: b.project_id == ^project_id and b.inserted_at >= ^start_at and b.inserted_at <= ^end_at
    )
    |> filter(opts, :is_ci)
    |> filter(opts, :git_branch)
    |> filter(opts, :root_project_name)
    |> cohort_filters(Keyword.get(opts, :filters, []))
  end

  defp task_query(project_id, opts) do
    builds =
      project_id
      |> build_query(opts)
      |> select(
        [b],
        struct(b, [
          :id,
          :root_project_name,
          :inserted_at,
          :custom_tags,
          :account_id,
          :is_ci,
          :git_branch,
          :git_commit_sha
        ])
      )

    start_at = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_at = Keyword.get(opts, :end_datetime, DateTime.utc_now())

    tasks =
      from(t in Task,
        where: t.project_id == ^project_id and t.inserted_at >= ^start_at and t.inserted_at <= ^end_at,
        select: %{
          id: t.id,
          gradle_build_id: t.gradle_build_id,
          build_path: t.build_path,
          task_path: t.task_path,
          task_type: t.task_type,
          outcome: t.outcome,
          duration_ms: t.duration_ms,
          cacheable: t.cacheable,
          cacheability: t.cacheability,
          remote_cache_miss: t.remote_cache_miss,
          started_at: t.started_at
        }
      )

    query = from(t in subquery(tasks), join: b in subquery(builds), on: b.id == t.gradle_build_id)

    Enum.reduce([:task_type, :build_path, :task_path], query, fn key, query ->
      case Keyword.get(opts, key) do
        value when is_binary(value) -> where(query, [t], field(t, ^key) == ^value)
        _ -> query
      end
    end)
  end

  defp cohort_filters(query, filters), do: Enum.reduce(filters, query, &cohort_filter/2)

  defp cohort_filter(%{field: :is_ci, op: op, value: value}, query) when value in [:ci, :local] do
    is_ci = value == :ci

    case op do
      :== -> where(query, [b], b.is_ci == ^is_ci)
      :!= -> where(query, [b], b.is_ci != ^is_ci)
      _ -> query
    end
  end

  defp cohort_filter(%{field: field, op: op, value: value}, query) when field == :git_branch and is_binary(value) do
    case op do
      :== -> where(query, [b], field(b, ^field) == ^value)
      :=~ -> where(query, [b], fragment("positionCaseInsensitiveUTF8(?, ?) > 0", field(b, ^field), ^value))
      :not_ilike -> where(query, [b], fragment("positionCaseInsensitiveUTF8(?, ?) = 0", field(b, ^field), ^value))
      _ -> query
    end
  end

  defp cohort_filter(_filter, query), do: query

  defp filter(query, opts, key) do
    case Keyword.get(opts, key) do
      value when value in [nil, ""] ->
        query

      value when is_binary(value) or (key == :is_ci and is_boolean(value)) ->
        where(query, [b], field(b, ^key) == ^value)

      _ ->
        query
    end
  end

  defp normalize(row) do
    lookups = row.remote_hits + row.misses
    cacheability = cacheability(row)

    hit_rate =
      cond do
        lookups > 0 -> Float.round(row.remote_hits / lookups * 100, 1)
        cacheability == :cacheable -> 0.0
        true -> nil
      end

    row
    |> Map.put(:id, JSON.encode!([row.root_project_name, row.build_path, row.name, Map.get(row, :task_type)]))
    |> Map.put(:cacheability, cacheability)
    |> Map.put(:hit_rate, hit_rate)
    |> Map.drop([:observations, :cacheable_observations, :non_cacheable_observations, :remote_hits])
    |> normalize_percentiles()
  end

  defp normalize_percentiles(row) do
    Enum.reduce([:p50_duration_ms, :p90_duration_ms, :p99_duration_ms], row, fn field, row ->
      Map.update!(row, field, &if(row.executions > 0 and is_number(&1), do: round(&1)))
    end)
  end

  defp cacheability(row) do
    cond do
      row.cacheable_observations > 0 -> :cacheable
      row.non_cacheable_observations == row.observations -> :not_cacheable
      true -> :unknown
    end
  end
end
