defmodule TuistWeb.TestRunsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use TuistWeb.Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Runs.RanByBadge

  alias Tuist.CommandEvents
  alias Tuist.Projects
  alias Tuist.Runs.Analytics

  def mount(_params, _session, %{assigns: %{selected_project: project}} = socket) do
    slug = Projects.get_project_slug_from_id(project.id)

    {:ok, assign(socket, :head_title, "#{gettext("Test Runs")} · #{slug} · Tuist")}
  end

  def handle_params(params, _uri, socket) do
    {
      :noreply,
      socket
      |> assign_analytics(params)
      |> assign_test_runs(params)
    }
  end

  defp assign_analytics(%{assigns: %{selected_project: project}} = socket, params) do
    date_range = date_range(params)

    analytics_environment = analytics_environment(params)

    opts = [
      project_id: project.id,
      start_date: start_date(date_range)
    ]

    opts =
      case analytics_environment do
        "ci" -> Keyword.put(opts, :is_ci, true)
        "local" -> Keyword.put(opts, :is_ci, false)
        _ -> opts
      end

    uri =
      URI.new!(
        "?" <>
          URI.encode_query(
            Map.take(params, ["analytics_date_range", "analytics_environment", "analytics_selected_widget"])
          )
      )

    test_runs_analytics =
      Analytics.runs_analytics(project.id, "test", opts)

    failed_test_runs_analytics =
      Analytics.runs_analytics(project.id, "test", Keyword.put(opts, :status, :failure))

    test_runs_duration_analytics =
      Analytics.runs_duration_analytics("test", opts)

    analytics_selected_widget = analytics_selected_widget(params)

    analytics_chart_data =
      case analytics_selected_widget do
        "test_run_count" ->
          %{
            dates: test_runs_analytics.dates,
            values: test_runs_analytics.values,
            name: gettext("Test run count"),
            value_formatter: "{value}"
          }

        "failed_test_run_count" ->
          %{
            dates: failed_test_runs_analytics.dates,
            values: failed_test_runs_analytics.values,
            name: gettext("Failed run count"),
            value_formatter: "{value}"
          }

        "test_run_duration" ->
          %{
            dates: test_runs_duration_analytics.dates,
            values:
              Enum.map(test_runs_duration_analytics.values, &((&1 / 1000) |> Decimal.from_float() |> Decimal.round(1))),
            name: gettext("Avg. test run duration"),
            value_formatter: "{value}s"
          }
      end

    socket
    |> assign(
      :analytics_date_range,
      date_range
    )
    |> assign(
      :analytics_trend_label,
      analytics_trend_label(date_range)
    )
    |> assign(
      :analytics_environment,
      analytics_environment
    )
    |> assign(
      :analytics_environment_label,
      analytics_environment_label(analytics_environment)
    )
    |> assign(
      :analytics_date_range,
      date_range
    )
    |> assign(
      :analytics_selected_widget,
      analytics_selected_widget
    )
    |> assign(
      :test_runs_analytics,
      test_runs_analytics
    )
    |> assign(
      :failed_test_runs_analytics,
      failed_test_runs_analytics
    )
    |> assign(
      :test_runs_duration_analytics,
      test_runs_duration_analytics
    )
    |> assign(
      :analytics_chart_data,
      analytics_chart_data
    )
    |> assign(
      :uri,
      uri
    )
  end

  defp start_date("last_12_months"), do: Date.add(DateTime.utc_now(), -365)
  defp start_date("last_30_days"), do: Date.add(DateTime.utc_now(), -30)
  defp start_date("last_7_days"), do: Date.add(DateTime.utc_now(), -7)

  defp analytics_trend_label("last_7_days"), do: gettext("since last week")
  defp analytics_trend_label("last_12_months"), do: gettext("since last year")
  defp analytics_trend_label(_), do: gettext("since last month")

  defp analytics_environment_label("any") do
    gettext("Any")
  end

  defp analytics_environment_label("local") do
    gettext("Local")
  end

  defp analytics_environment_label("ci") do
    gettext("CI")
  end

  defp date_range(params) do
    analytics_date_range = params["analytics_date_range"]

    if is_nil(analytics_date_range) do
      "last_30_days"
    else
      analytics_date_range
    end
  end

  defp analytics_environment(params) do
    analytics_environment = params["analytics_environment"]

    if is_nil(analytics_environment) do
      "any"
    else
      analytics_environment
    end
  end

  defp analytics_selected_widget(params) do
    analytics_selected_widget = params["analytics_selected_widget"]

    if is_nil(analytics_selected_widget) do
      "test_run_count"
    else
      analytics_selected_widget
    end
  end

  defp assign_test_runs(%{assigns: %{selected_project: project}} = socket, params) do
    {test_runs, test_runs_meta} =
      cond do
        !is_nil(params["after"]) ->
          list_test_runs(project.id, after: params["after"])

        !is_nil(params["before"]) ->
          list_test_runs(project.id, before: params["before"])

        true ->
          list_test_runs(project.id)
      end

    socket
    |> assign(
      :test_runs,
      test_runs
    )
    |> assign(
      :test_runs_meta,
      test_runs_meta
    )
  end

  defp list_test_runs(project_id, attrs \\ []) do
    options = %{
      filters: [
        %{field: :project_id, op: :==, value: project_id},
        %{field: :name, op: :==, value: "test"}
      ],
      order_by: [:created_at],
      order_directions: [:desc]
    }

    options =
      cond do
        not is_nil(Keyword.get(attrs, :before)) ->
          options
          |> Map.put(:last, 20)
          |> Map.put(:before, Keyword.get(attrs, :before))

        not is_nil(Keyword.get(attrs, :after)) ->
          options
          |> Map.put(:first, 20)
          |> Map.put(:after, Keyword.get(attrs, :after))

        true ->
          Map.put(options, :first, 20)
      end

    CommandEvents.list_command_events(options)
  end
end
