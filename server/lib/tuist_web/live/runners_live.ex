defmodule TuistWeb.RunnersLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.Skeleton
  import TuistWeb.PercentileDropdownWidget
  import TuistWeb.Widget

  alias Tuist.Authorization
  alias Tuist.Runners.Analytics
  alias Tuist.Runners.Jobs
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Utilities.Query

  @widget_limit 5

  @impl true
  def mount(_params, _session, %{assigns: %{selected_account: selected_account, current_user: current_user}} = socket) do
    if Authorization.authorize(:projects_read, current_user, selected_account) != :ok do
      raise TuistWeb.Errors.NotFoundError,
            dgettext("dashboard_runners", "The page you are looking for doesn't exist or has been moved.")
    end

    {:ok,
     socket
     |> assign(
       :head_title,
       "#{dgettext("dashboard_runners", "Runners")} · #{selected_account.name} · Tuist"
     )
     |> assign(:workflows, Jobs.list_workflows_for_account(selected_account.id, limit: @widget_limit))
     |> assign(:recent_jobs, Jobs.list_for_account(selected_account.id, limit: @widget_limit))}
  end

  @impl true
  def handle_params(params, uri, %{assigns: %{selected_account: account}} = socket) do
    %{preset: preset, period: {start_datetime, end_datetime} = period} =
      DatePicker.date_picker_params(params, "analytics")

    selected_widget = params["widget"] || "total_jobs"
    job_duration_percentile = params["job-duration"] || "avg"
    workflow_duration_percentile = params["workflow-duration"] || "avg"

    opts = [start_datetime: start_datetime, end_datetime: end_datetime]

    {:noreply,
     socket
     |> assign(:uri, URI.parse(uri))
     |> assign(:analytics_preset, preset)
     |> assign(:analytics_period, period)
     |> assign(:analytics_trend_label, trend_label(preset))
     |> assign(:analytics_selected_widget, selected_widget)
     |> assign(:job_duration_percentile, job_duration_percentile)
     |> assign(:workflow_duration_percentile, workflow_duration_percentile)
     |> assign_async(
       [:jobs_count, :jobs_duration, :workflows_duration],
       fn ->
         {:ok,
          %{
            jobs_count: Analytics.jobs_count(account.id, opts),
            jobs_duration: Analytics.jobs_duration(account.id, opts),
            workflows_duration: Analytics.workflows_duration(account.id, opts)
          }}
       end
     )}
  end

  @impl true
  def handle_event("select_widget", %{"widget" => widget}, socket) do
    {:noreply, push_patch_with_param(socket, "widget", widget)}
  end

  def handle_event("select_job_duration_percentile", %{"value" => value}, socket) do
    {:noreply, push_patch_with_param(socket, "job-duration", value)}
  end

  def handle_event("select_workflow_duration_percentile", %{"value" => value}, socket) do
    {:noreply, push_patch_with_param(socket, "workflow-duration", value)}
  end

  def handle_event(
        "analytics_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        socket
      ) do
    query_params =
      if preset == "custom" do
        socket.assigns.uri.query
        |> Query.put("analytics-date-range", "custom")
        |> Query.put("analytics-start-date", start_date)
        |> Query.put("analytics-end-date", end_date)
      else
        Query.put(socket.assigns.uri.query, "analytics-date-range", preset)
      end

    {:noreply, push_patch(socket, to: "/#{socket.assigns.selected_account.name}/runners?#{query_params}")}
  end

  defp push_patch_with_param(socket, key, value) do
    query = Query.put(socket.assigns.uri.query || "", key, value)
    push_patch(socket, to: "/#{socket.assigns.selected_account.name}/runners?#{query}")
  end

  defp trend_label("last-24-hours"), do: dgettext("dashboard_runners", "since yesterday")
  defp trend_label("last-7-days"), do: dgettext("dashboard_runners", "since last week")
  defp trend_label("last-12-months"), do: dgettext("dashboard_runners", "since last year")
  defp trend_label("custom"), do: dgettext("dashboard_runners", "since last period")
  defp trend_label(_), do: dgettext("dashboard_runners", "since last month")

  # Render helpers ------------------------------------------------------------

  def fmt_duration_ms(nil), do: "–"
  def fmt_duration_ms(0), do: "0s"

  def fmt_duration_ms(ms) when is_integer(ms) and ms > 0,
    do: DateFormatter.format_duration_from_milliseconds(ms)

  def fmt_duration_ms(_), do: "–"

  def percentile_value(stats, "p50"), do: Map.get(stats, :p50)
  def percentile_value(stats, "p90"), do: Map.get(stats, :p90)
  def percentile_value(stats, "p99"), do: Map.get(stats, :p99)
  def percentile_value(stats, _), do: Map.get(stats, :avg)

  def percentile_trend(stats, "p50"), do: Map.get(stats, :trend_p50)
  def percentile_trend(stats, "p90"), do: Map.get(stats, :trend_p90)
  def percentile_trend(stats, "p99"), do: Map.get(stats, :trend_p99)
  def percentile_trend(stats, _), do: Map.get(stats, :trend_avg)

  def percentile_series(stats, "p50"), do: Map.get(stats, :p50_values, [])
  def percentile_series(stats, "p90"), do: Map.get(stats, :p90_values, [])
  def percentile_series(stats, "p99"), do: Map.get(stats, :p99_values, [])
  def percentile_series(stats, _), do: Map.get(stats, :avg_values, [])

  def legend_color_for_percentile("p50"), do: "p50"
  def legend_color_for_percentile("p90"), do: "p90"
  def legend_color_for_percentile("p99"), do: "p99"
  def legend_color_for_percentile(_), do: "secondary"

  def trend_to_int(trend) when is_number(trend), do: round(trend)
  def trend_to_int(_), do: 0

  def status_badge_props("queued"), do: %{label: dgettext("dashboard_runners", "Queued"), status: "warning"}
  def status_badge_props("claimed"), do: %{label: dgettext("dashboard_runners", "Claimed"), status: "in_progress"}
  def status_badge_props("running"), do: %{label: dgettext("dashboard_runners", "Running"), status: "in_progress"}
  def status_badge_props("completed"), do: %{label: dgettext("dashboard_runners", "Completed"), status: "success"}
  def status_badge_props(_), do: %{label: dgettext("dashboard_runners", "Unknown"), status: "warning"}

  def conclusion_badge_props("success"), do: %{label: dgettext("dashboard_runners", "Success"), status: "success"}
  def conclusion_badge_props("failure"), do: %{label: dgettext("dashboard_runners", "Failure"), status: "error"}
  def conclusion_badge_props("cancelled"), do: %{label: dgettext("dashboard_runners", "Cancelled"), status: "warning"}
  def conclusion_badge_props("skipped"), do: %{label: dgettext("dashboard_runners", "Skipped"), status: "warning"}
  def conclusion_badge_props(_), do: nil

  def success_rate(%{success_count: success, total_jobs: total}) when total > 0 do
    rate = success / total * 100

    rate
    |> Float.round(1)
    |> :erlang.float_to_binary(decimals: 1)
    |> Kernel.<>("%")
  end

  def success_rate(_), do: "–"

  def from_now(%DateTime{} = ts), do: DateFormatter.from_now(ts)
  def from_now(_), do: "–"

  def from_now_or_dash(%DateTime{year: 1970}), do: "–"
  def from_now_or_dash(%DateTime{} = ts), do: DateFormatter.from_now(ts)
  def from_now_or_dash(_), do: "–"

  def widget_empty_label, do: dgettext("dashboard_runners", "No jobs yet")

  def percentile_metrics_for(stats) when is_map(stats) do
    %{
      avg: fmt_duration_ms(Map.get(stats, :avg)),
      p50: fmt_duration_ms(Map.get(stats, :p50)),
      p90: fmt_duration_ms(Map.get(stats, :p90)),
      p99: fmt_duration_ms(Map.get(stats, :p99))
    }
  end

  def percentile_metrics_for(_), do: nil
end
