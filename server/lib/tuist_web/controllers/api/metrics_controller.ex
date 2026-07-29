defmodule TuistWeb.API.MetricsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Builds
  alias Tuist.Builds.Analytics, as: BuildAnalytics
  alias Tuist.KeyValueStore
  alias Tuist.Tests
  alias Tuist.Tests.Analytics, as: TestAnalytics
  alias TuistWeb.API.Authorization.AuthorizationPlug
  alias TuistWeb.API.Schemas.DurationMetrics
  alias TuistWeb.API.Schemas.Error

  plug TuistWeb.Plugs.MetricsRateLimitPlug

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)

  plug AuthorizationPlug, :build when action in [:build_duration, :build_dimension_values]

  plug AuthorizationPlug, :test when action in [:test_duration, :test_dimension_values]

  tags ["Metrics"]

  @max_range_seconds 366 * 24 * 60 * 60
  @duration_cache_ttl_seconds 60
  @dimension_cache_ttl_seconds 600

  operation(:build_duration,
    summary: "Time-bucketed build duration percentiles for a project.",
    operation_id: "buildDurationMetrics",
    parameters: [
      account_handle: [in: :path, type: :string, required: true, description: "The handle of the account."],
      project_handle: [in: :path, type: :string, required: true, description: "The handle of the project."],
      from: [
        in: :query,
        type: %Schema{type: :integer, format: :int64},
        required: true,
        description: "Start of the time range as a Unix timestamp in seconds."
      ],
      to: [
        in: :query,
        type: %Schema{type: :integer, format: :int64},
        required: true,
        description: "End of the time range as a Unix timestamp in seconds."
      ],
      is_ci: [in: :query, type: :boolean, description: "Filter to runs executed on CI (true) or locally (false)."],
      scheme: [in: :query, type: :string, description: "Filter by scheme."],
      configuration: [in: :query, type: :string, description: "Filter by build configuration."],
      category: [
        in: :query,
        type: %Schema{type: :string, enum: ["clean", "incremental"]},
        description: "Filter by build category."
      ],
      status: [
        in: :query,
        type: %Schema{type: :string, enum: ["success", "failure"]},
        description: "Filter by build status."
      ],
      tag: [in: :query, type: :string, description: "Filter by a custom tag."]
    ],
    responses: %{
      ok: {"Build duration metrics", "application/json", DurationMetrics},
      bad_request: {"The request was invalid", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def build_duration(%{assigns: %{selected_project: project}} = conn, _params) do
    case validate_range(conn.params) do
      {:ok, start_datetime, end_datetime} ->
        opts =
          build_opts(start_datetime, end_datetime, conn.params, [
            :is_ci,
            :scheme,
            :configuration,
            :category,
            :status,
            :tag
          ])

        metrics =
          cached_duration_metrics(:builds, project.id, opts, fn ->
            BuildAnalytics.build_duration_percentiles_analytics(project.id, opts)
          end)

        json(conn, format_duration_metrics(metrics))

      {:error, message} ->
        bad_request(conn, message)
    end
  end

  operation(:test_duration,
    summary: "Time-bucketed test run duration percentiles for a project.",
    operation_id: "testDurationMetrics",
    parameters: [
      account_handle: [in: :path, type: :string, required: true, description: "The handle of the account."],
      project_handle: [in: :path, type: :string, required: true, description: "The handle of the project."],
      from: [
        in: :query,
        type: %Schema{type: :integer, format: :int64},
        required: true,
        description: "Start of the time range as a Unix timestamp in seconds."
      ],
      to: [
        in: :query,
        type: %Schema{type: :integer, format: :int64},
        required: true,
        description: "End of the time range as a Unix timestamp in seconds."
      ],
      is_ci: [in: :query, type: :boolean, description: "Filter to runs executed on CI (true) or locally (false)."],
      scheme: [in: :query, type: :string, description: "Filter by scheme."]
    ],
    responses: %{
      ok: {"Test duration metrics", "application/json", DurationMetrics},
      bad_request: {"The request was invalid", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def test_duration(%{assigns: %{selected_project: project}} = conn, _params) do
    case validate_range(conn.params) do
      {:ok, start_datetime, end_datetime} ->
        opts = build_opts(start_datetime, end_datetime, conn.params, [:is_ci, :scheme])

        metrics =
          cached_duration_metrics(:tests, project.id, opts, fn ->
            TestAnalytics.test_run_duration_analytics(project.id, opts)
          end)

        json(conn, format_duration_metrics(metrics))

      {:error, message} ->
        bad_request(conn, message)
    end
  end

  operation(:build_dimension_values,
    summary: "List the values seen for a build filter dimension.",
    operation_id: "buildMetricDimensionValues",
    parameters: [
      account_handle: [in: :path, type: :string, required: true, description: "The handle of the account."],
      project_handle: [in: :path, type: :string, required: true, description: "The handle of the project."],
      dimension: [
        in: :path,
        type: %Schema{type: :string, enum: ["scheme", "configuration"]},
        required: true,
        description: "The build dimension to list values for."
      ]
    ],
    responses: %{
      ok:
        {"Dimension values", "application/json",
         %Schema{
           type: :object,
           required: [:values],
           properties: %{values: %Schema{type: :array, items: %Schema{type: :string}}}
         }},
      bad_request: {"The request was invalid", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def build_dimension_values(%{assigns: %{selected_project: project}} = conn, %{dimension: dimension}) do
    case dimension do
      "scheme" ->
        values = cached_dimension_values(:builds, project.id, :scheme, fn -> Builds.project_build_schemes(project) end)
        json(conn, %{values: values})

      "configuration" ->
        values =
          cached_dimension_values(:builds, project.id, :configuration, fn ->
            Builds.project_build_configurations(project)
          end)

        json(conn, %{values: values})

      _ ->
        bad_request(conn, "Unknown build dimension: #{dimension}.")
    end
  end

  operation(:test_dimension_values,
    summary: "List the values seen for a test filter dimension.",
    operation_id: "testMetricDimensionValues",
    parameters: [
      account_handle: [in: :path, type: :string, required: true, description: "The handle of the account."],
      project_handle: [in: :path, type: :string, required: true, description: "The handle of the project."],
      dimension: [
        in: :path,
        type: %Schema{type: :string, enum: ["scheme"]},
        required: true,
        description: "The test dimension to list values for."
      ]
    ],
    responses: %{
      ok:
        {"Dimension values", "application/json",
         %Schema{
           type: :object,
           required: [:values],
           properties: %{values: %Schema{type: :array, items: %Schema{type: :string}}}
         }},
      bad_request: {"The request was invalid", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def test_dimension_values(%{assigns: %{selected_project: project}} = conn, %{dimension: dimension}) do
    case dimension do
      "scheme" ->
        values = cached_dimension_values(:tests, project.id, :scheme, fn -> Tests.project_test_schemes(project) end)
        json(conn, %{values: values})

      _ ->
        bad_request(conn, "Unknown test dimension: #{dimension}.")
    end
  end

  defp bad_request(conn, message) do
    conn
    |> put_status(:bad_request)
    |> json(%{message: message})
  end

  # Short-lived cache so a dashboard refreshing many panels (or several viewers on
  # the same dashboard) collapses to a single ClickHouse query per
  # project/range/filters within the window. The window is floored to the cache
  # TTL grid for the key so that *sequential* refreshes — each of which sends a
  # slightly later `to` — share a key within the TTL, not only concurrent ones.
  defp cached_duration_metrics(entity, project_id, opts, func) do
    key_opts =
      opts
      |> Keyword.update!(:start_datetime, &floor_to_cache_grid/1)
      |> Keyword.update!(:end_datetime, &floor_to_cache_grid/1)

    KeyValueStore.get_or_update(
      [:metrics_duration, entity, project_id, :erlang.phash2(key_opts)],
      [ttl: to_timeout(second: @duration_cache_ttl_seconds)],
      func
    )
  end

  defp floor_to_cache_grid(%DateTime{} = datetime) do
    unix = DateTime.to_unix(datetime)
    DateTime.from_unix!(unix - rem(unix, @duration_cache_ttl_seconds))
  end

  # Scheme/configuration lists change slowly, so they get a longer TTL. This takes
  # the recurring CheckHealth probes and query-editor refetches off ClickHouse.
  defp cached_dimension_values(entity, project_id, dimension, func) do
    KeyValueStore.get_or_update(
      [:metrics_dimension, entity, project_id, dimension],
      [ttl: to_timeout(second: @dimension_cache_ttl_seconds)],
      func
    )
  end

  defp validate_range(%{from: from, to: to}) do
    cond do
      from < 0 or to < 0 ->
        {:error, "`from` and `to` must be non-negative Unix timestamps."}

      to <= from ->
        {:error, "`to` must be greater than `from`."}

      to - from > @max_range_seconds ->
        {:error, "The requested time range exceeds the maximum of 366 days."}

      true ->
        case {DateTime.from_unix(from), DateTime.from_unix(to)} do
          {{:ok, start_datetime}, {:ok, end_datetime}} -> {:ok, start_datetime, end_datetime}
          _ -> {:error, "`from` and `to` must be valid Unix timestamps."}
        end
    end
  end

  defp build_opts(start_datetime, end_datetime, params, keys) do
    Enum.reduce(keys, [start_datetime: start_datetime, end_datetime: end_datetime], fn key, acc ->
      case Map.get(params, key) do
        nil -> acc
        value -> Keyword.put(acc, key, value)
      end
    end)
  end

  defp format_duration_metrics(metrics) do
    %{
      dates: Enum.map(metrics.dates, &date_to_unix/1),
      average: %{values: metrics.values, total: metrics.total_average_duration},
      p50: %{values: metrics.p50_values, total: metrics.p50},
      p90: %{values: metrics.p90_values, total: metrics.p90},
      p99: %{values: metrics.p99_values, total: metrics.p99},
      trend: metrics.trend
    }
  end

  defp date_to_unix(%DateTime{} = datetime), do: DateTime.to_unix(datetime)

  defp date_to_unix(%NaiveDateTime{} = naive), do: naive |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()

  defp date_to_unix(%Date{} = date), do: date |> DateTime.new!(~T[00:00:00], "Etc/UTC") |> DateTime.to_unix()
end
