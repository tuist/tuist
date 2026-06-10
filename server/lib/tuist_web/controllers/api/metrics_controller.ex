defmodule TuistWeb.API.MetricsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Builds
  alias Tuist.Builds.Analytics, as: BuildAnalytics
  alias Tuist.Tests
  alias Tuist.Tests.Analytics, as: TestAnalytics
  alias TuistWeb.API.Authorization.AuthorizationPlug
  alias TuistWeb.API.Schemas.DurationMetrics
  alias TuistWeb.API.Schemas.Error

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)

  plug AuthorizationPlug,
       :build when action in [:build_duration, :build_schemes, :build_configurations]

  plug AuthorizationPlug, :test when action in [:test_duration, :test_schemes]

  tags ["Metrics"]

  @max_range_seconds 366 * 24 * 60 * 60

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

        metrics = BuildAnalytics.build_duration_percentiles_analytics(project.id, opts)
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
        metrics = TestAnalytics.test_run_duration_analytics(project.id, opts)
        json(conn, format_duration_metrics(metrics))

      {:error, message} ->
        bad_request(conn, message)
    end
  end

  operation(:build_schemes,
    summary: "List the schemes seen in a project's recent build runs.",
    operation_id: "buildMetricSchemes",
    parameters: [
      account_handle: [in: :path, type: :string, required: true, description: "The handle of the account."],
      project_handle: [in: :path, type: :string, required: true, description: "The handle of the project."]
    ],
    responses: %{
      ok:
        {"Build schemes", "application/json",
         %Schema{
           type: :object,
           required: [:schemes],
           properties: %{schemes: %Schema{type: :array, items: %Schema{type: :string}}}
         }},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def build_schemes(%{assigns: %{selected_project: project}} = conn, _params) do
    json(conn, %{schemes: Builds.project_build_schemes(project)})
  end

  operation(:build_configurations,
    summary: "List the configurations seen in a project's recent build runs.",
    operation_id: "buildMetricConfigurations",
    parameters: [
      account_handle: [in: :path, type: :string, required: true, description: "The handle of the account."],
      project_handle: [in: :path, type: :string, required: true, description: "The handle of the project."]
    ],
    responses: %{
      ok:
        {"Build configurations", "application/json",
         %Schema{
           type: :object,
           required: [:configurations],
           properties: %{configurations: %Schema{type: :array, items: %Schema{type: :string}}}
         }},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def build_configurations(%{assigns: %{selected_project: project}} = conn, _params) do
    json(conn, %{configurations: Builds.project_build_configurations(project)})
  end

  operation(:test_schemes,
    summary: "List the schemes seen in a project's recent test runs.",
    operation_id: "testMetricSchemes",
    parameters: [
      account_handle: [in: :path, type: :string, required: true, description: "The handle of the account."],
      project_handle: [in: :path, type: :string, required: true, description: "The handle of the project."]
    ],
    responses: %{
      ok:
        {"Test schemes", "application/json",
         %Schema{
           type: :object,
           required: [:schemes],
           properties: %{schemes: %Schema{type: :array, items: %Schema{type: :string}}}
         }},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def test_schemes(%{assigns: %{selected_project: project}} = conn, _params) do
    json(conn, %{schemes: Tests.project_test_schemes(project)})
  end

  defp bad_request(conn, message) do
    conn
    |> put_status(:bad_request)
    |> json(%{message: message})
  end

  defp validate_range(%{from: from, to: to}) do
    cond do
      to <= from ->
        {:error, "`to` must be greater than `from`."}

      to - from > @max_range_seconds ->
        {:error, "The requested time range exceeds the maximum of 366 days."}

      true ->
        {:ok, DateTime.from_unix!(from), DateTime.from_unix!(to)}
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
