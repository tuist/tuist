defmodule Tuist.Cargo do
  @moduledoc "Cargo build insights. Test results use the shared Tests context."
  import Ecto.Query

  alias Tuist.Cargo.Build
  alias Tuist.Cargo.CacheMetrics
  alias Tuist.Cargo.Compilation
  alias Tuist.ClickHouseRepo
  alias Tuist.Gradle.Analytics, as: BuildAnalytics

  @strings ~w(command rust_version contract_version git_branch git_commit_sha git_ref git_remote_url_origin ci_provider ci_run_id ci_project_handle ci_host)a
  @list_fields Build.__schema__(:fields) -- [:cache_metrics]

  def create_build(attrs) do
    with {:ok, id} <- Ecto.UUID.cast(attrs[:id]),
         {:ok, cache_metrics} <- CacheMetrics.encode(attrs[:cache]),
         true <- attrs[:status] in ["success", "failure"],
         true <- valid_duration?(attrs[:duration_ms]),
         true <- Enum.all?(@strings, &(is_nil(attrs[&1]) or (is_binary(attrs[&1]) and byte_size(attrs[&1]) <= 4096))),
         compilations when is_list(compilations) <- Map.get(attrs, :compilations, []),
         true <- length(compilations) <= 20_000,
         true <- Enum.all?(compilations, &valid_compilation?/1) do
      now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
      strings = Map.new(@strings, &{&1, Map.get(attrs, &1) || ""})

      Build.Buffer.insert(
        Map.merge(strings, %{
          id: id,
          project_id: attrs.project_id,
          account_id: attrs.account_id,
          status: attrs.status,
          duration_ms: attrs.duration_ms,
          cache_metrics: cache_metrics,
          is_ci: Map.get(attrs, :is_ci, false),
          started_at: started_at(attrs[:started_at]),
          inserted_at: now
        })
      )

      rows =
        Enum.map(compilations, fn compilation ->
          compilation
          |> Map.take(~w(name source kind dependencies start_offset_ms duration_ms status)a)
          |> Map.merge(%{
            id: Ecto.UUID.generate(),
            build_id: id,
            project_id: attrs.project_id,
            diagnostics: JSON.encode!(Map.get(compilation, :diagnostics, [])),
            inserted_at: now
          })
        end)

      if rows != [], do: Compilation.Buffer.insert_all(rows)
      {:ok, id}
    else
      _ -> {:error, :invalid_report}
    end
  end

  def get_build(id, project_id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Build{} = build <-
           ClickHouseRepo.one(from(b in Build, where: b.id == ^id and b.project_id == ^project_id, limit: 1)) do
      {:ok, build}
    else
      _ -> {:error, :not_found}
    end
  end

  def list_builds(project_id, params \\ %{}) do
    query = from(b in build_query(project_id), select: struct(b, ^@list_fields))
    Tuist.ClickHouseFlop.validate_and_run!(query, params, for: Build)
  end

  def duration_analytics(project_id, opts \\ []) do
    BuildAnalytics.build_duration_analytics(project_id, Keyword.put(opts, :schema, cohort_query(project_id, opts)))
  end

  def build_analytics(project_id, opts \\ []) do
    analytics_opts = Keyword.put(opts, :schema, cohort_query(project_id, opts))

    %{
      total: BuildAnalytics.build_analytics(project_id, analytics_opts),
      failed: BuildAnalytics.build_analytics(project_id, Keyword.put(analytics_opts, :status, "failure")),
      success: BuildAnalytics.build_success_rate_analytics(project_id, analytics_opts),
      duration: BuildAnalytics.build_duration_analytics(project_id, analytics_opts),
      p50: BuildAnalytics.build_percentile_durations(project_id, 0.5, analytics_opts),
      p90: BuildAnalytics.build_percentile_durations(project_id, 0.9, analytics_opts),
      p99: BuildAnalytics.build_percentile_durations(project_id, 0.99, analytics_opts)
    }
  end

  def build_options(project_id) do
    query = build_query(project_id)

    Map.new([:command, :rust_version], fn key ->
      values =
        ClickHouseRepo.all(
          from(b in query,
            group_by: field(b, ^key),
            order_by: field(b, ^key),
            select: field(b, ^key),
            limit: 100
          )
        )

      {key, Enum.reject(values, &(&1 == ""))}
    end)
  end

  def configuration_insights(project_id, category, opts \\ []) when category in [:rust_version, :command, :is_ci] do
    query = dated_query(project_id, opts)

    ClickHouseRepo.all(
      from(b in query,
        group_by: field(b, ^category),
        order_by: [desc: avg(b.duration_ms)],
        select: %{category: field(b, ^category), value: avg(b.duration_ms)},
        limit: 100
      )
    )
  end

  def build_scatter_data(project_id, group_by, opts \\ []) when group_by in [:command, :rust_version, :is_ci] do
    query = dated_query(project_id, opts)
    builds = ClickHouseRepo.all(from(b in query, order_by: [desc: b.inserted_at, desc: b.id], limit: 10_000))

    %{
      truncated: length(builds) == 10_000,
      oldest_entry: if(length(builds) == 10_000, do: List.last(builds).inserted_at),
      series:
        builds
        |> Enum.group_by(&Map.fetch!(&1, group_by))
        |> Enum.map(fn {key, rows} ->
          %{
            name: key,
            data:
              Enum.map(rows, fn build ->
                %{
                  id: build.id,
                  value: [
                    NaiveDateTime.diff(build.inserted_at, ~N[1970-01-01 00:00:00], :millisecond),
                    build.duration_ms / 1000
                  ]
                }
              end)
          }
        end)
    }
  end

  def recent_builds(project_id, opts \\ []) do
    query = cohort_query(project_id, opts)
    limit = opts |> Keyword.get(:limit, 30) |> min(100) |> max(1)
    query = from(b in query, order_by: [desc: b.inserted_at, desc: b.id], limit: ^limit)

    query =
      Enum.reduce([:start_datetime, :end_datetime, :is_ci], query, fn key, query ->
        case {key, Keyword.get(opts, key)} do
          {:start_datetime, %DateTime{} = value} -> where(query, [b], b.inserted_at >= ^DateTime.to_naive(value))
          {:end_datetime, %DateTime{} = value} -> where(query, [b], b.inserted_at <= ^DateTime.to_naive(value))
          {:is_ci, value} when is_boolean(value) -> where(query, [b], b.is_ci == ^value)
          _ -> query
        end
      end)

    ClickHouseRepo.all(query)
  end

  defp build_query(project_id), do: from(b in Build, where: b.project_id == ^project_id and b.command != "nextest")

  defp cohort_query(project_id, opts) do
    Enum.reduce([:command, :rust_version, :is_ci], build_query(project_id), fn key, query ->
      case Keyword.get(opts, key) do
        nil -> query
        value -> where(query, [b], field(b, ^key) == ^value)
      end
    end)
  end

  defp dated_query(project_id, opts) do
    query = cohort_query(project_id, opts)
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())

    from(b in query,
      where: b.inserted_at >= ^DateTime.to_naive(start_datetime) and b.inserted_at <= ^DateTime.to_naive(end_datetime)
    )
  end

  def compilations(%Build{id: id, project_id: project_id}, limit \\ 20_000) do
    ClickHouseRepo.all(
      from(c in Compilation,
        where: c.project_id == ^project_id and c.build_id == ^id,
        order_by: [asc: c.start_offset_ms, asc: c.id],
        limit: ^limit
      )
    )
  end

  defp valid_duration?(value), do: is_integer(value) and value >= 0 and value <= 4_294_967_295

  defp valid_compilation?(value) when is_map(value) do
    value[:status] in ["success", "failure"] and valid_duration?(value[:duration_ms]) and
      valid_duration?(value[:start_offset_ms]) and
      Enum.all?(~w(name source kind)a, &(is_binary(value[&1]) and byte_size(value[&1]) <= 4096)) and
      valid_dependencies?(value[:dependencies]) and valid_diagnostics?(Map.get(value, :diagnostics, []))
  end

  defp valid_compilation?(_), do: false

  defp valid_dependencies?(values) when is_list(values) do
    length(values) <= 5000 and Enum.all?(values, &(is_binary(&1) and byte_size(&1) <= 1024))
  end

  defp valid_dependencies?(_), do: false

  defp valid_diagnostics?(values) when is_list(values) do
    length(values) <= 100 and Enum.all?(values, &valid_diagnostic?/1)
  end

  defp valid_diagnostics?(_), do: false

  defp valid_diagnostic?(value) when is_map(value) do
    value[:severity] in ["warning", "error"] and is_binary(value[:message]) and byte_size(value[:message]) <= 40_000 and
      (is_nil(value[:file]) or (is_binary(value[:file]) and byte_size(value[:file]) <= 4096)) and
      (is_nil(value[:line]) or valid_duration?(value[:line]))
  end

  defp valid_diagnostic?(_), do: false

  defp started_at(%DateTime{} = timestamp), do: timestamp |> DateTime.to_naive() |> started_at()
  defp started_at(%NaiveDateTime{microsecond: {value, _}} = timestamp), do: %{timestamp | microsecond: {value, 6}}
  defp started_at(nil), do: nil

  defp started_at(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, timestamp, _} -> started_at(timestamp)
      _ -> nil
    end
  end
end
