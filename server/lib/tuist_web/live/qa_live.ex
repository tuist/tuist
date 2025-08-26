defmodule TuistWeb.QALive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Previews.PlatformIcon
  import TuistWeb.Components.EmptyCardSection

  alias Tuist.AppBuilds.Preview
  alias Tuist.QA

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    slug = "#{account.name}/#{project.name}"

    socket =
      socket
      |> assign(:head_title, "#{gettext("Tuist QA")} · #{slug} · Tuist")
      |> assign(:qa_runs, [])
      |> assign(:available_apps, QA.available_apps_for_project(project.id))
      |> load_qa_runs()

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    {
      :noreply,
      socket
      |> assign(:current_params, params)
      |> assign_analytics(params)
      |> load_qa_runs()
    }
  end

  defp load_qa_runs(socket) do
    project = socket.assigns.selected_project
    qa_runs = QA.qa_runs_for_project(project, preload: [
      :run_steps,
      app_build: :preview
    ])

    assign(socket, :qa_runs, qa_runs)
  end

  defp assign_analytics(%{assigns: %{selected_project: project}} = socket, params) do
    date_range = date_range(params)
    analytics_app = analytics_app(params)

    opts = [
      project_id: project.id,
      start_date: start_date(date_range),
      app_name: case analytics_app do
        "any" -> nil
        app_name -> app_name
      end
    ]

    uri = URI.new!("?" <> URI.encode_query(params))

    [qa_runs_analytics, qa_issues_analytics, qa_duration_analytics] =
      QA.combined_qa_analytics(project.id, opts)

    analytics_selected_widget = analytics_selected_widget(params)

    analytics_chart_data =
      case analytics_selected_widget do
        "qa_run_count" ->
          %{
            dates: qa_runs_analytics.dates,
            values: qa_runs_analytics.values,
            name: gettext("QA run count"),
            value_formatter: "{value}"
          }

        "qa_issues_count" ->
          %{
            dates: qa_issues_analytics.dates,
            values: qa_issues_analytics.values,
            name: gettext("App issues found"),
            value_formatter: "{value}"
          }

        "qa_duration" ->
          %{
            dates: qa_duration_analytics.dates,
            values:
              Enum.map(
                qa_duration_analytics.values,
                &((&1 / 1000) |> Decimal.from_float() |> Decimal.round(1))
              ),
            name: gettext("Avg. QA duration"),
            value_formatter: "fn:formatSeconds"
          }
      end

    socket
    |> assign(:analytics_date_range, date_range)
    |> assign(:analytics_trend_label, analytics_trend_label(date_range))
    |> assign(:analytics_app, analytics_app)
    |> assign(:analytics_app_label, analytics_app_label(analytics_app))
    |> assign(:analytics_selected_widget, analytics_selected_widget)
    |> assign(:qa_runs_analytics, qa_runs_analytics)
    |> assign(:qa_issues_analytics, qa_issues_analytics)
    |> assign(:qa_duration_analytics, qa_duration_analytics)
    |> assign(:analytics_chart_data, analytics_chart_data)
    |> assign(:uri, uri)
  end

  defp start_date("last_12_months"), do: Date.add(Date.utc_today(), -365)
  defp start_date("last_30_days"), do: Date.add(Date.utc_today(), -30)
  defp start_date("last_7_days"), do: Date.add(Date.utc_today(), -7)

  defp analytics_trend_label("last_7_days"), do: gettext("since last week")
  defp analytics_trend_label("last_12_months"), do: gettext("since last year")
  defp analytics_trend_label(_), do: gettext("since last month")

  defp analytics_app_label("any"), do: gettext("Any")
  defp analytics_app_label(app_name) when is_binary(app_name), do: app_name
  defp analytics_app_label(_), do: gettext("Any")

  defp date_range(params) do
    analytics_date_range = params["analytics_date_range"]

    if is_nil(analytics_date_range) do
      "last_30_days"
    else
      analytics_date_range
    end
  end

  defp analytics_app(params) do
    analytics_app = params["analytics_app"]

    if is_nil(analytics_app) do
      "any"
    else
      analytics_app
    end
  end

  defp analytics_selected_widget(params) do
    analytics_selected_widget = params["analytics_selected_widget"]

    if is_nil(analytics_selected_widget) do
      "qa_run_count"
    else
      analytics_selected_widget
    end
  end

  defp format_datetime(datetime) when is_struct(datetime, DateTime) do
    Timex.from_now(datetime)
  end

  defp format_datetime(_), do: "Unknown"
end
