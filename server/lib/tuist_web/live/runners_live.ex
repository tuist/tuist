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
     |> assign(:analytics_selected_widget, "total_jobs")
     |> assign(:job_duration_percentile, "avg")
     |> assign(:workflow_duration_percentile, "avg")
     |> assign(:workflows, Jobs.list_workflows_for_account(selected_account.id, limit: @widget_limit))
     |> assign(:recent_jobs, Jobs.list_for_account(selected_account.id, limit: @widget_limit))
     |> assign_async(
       [:jobs_count, :jobs_duration, :workflows_duration],
       fn ->
         {:ok,
          %{
            jobs_count: Analytics.jobs_count(selected_account.id),
            jobs_duration: Analytics.jobs_duration(selected_account.id),
            workflows_duration: Analytics.workflows_duration(selected_account.id)
          }}
       end
     )}
  end

  @impl true
  def handle_event("select_widget", %{"widget" => widget}, socket) do
    {:noreply, assign(socket, :analytics_selected_widget, widget)}
  end

  def handle_event("select_job_duration_percentile", %{"value" => value}, socket) do
    {:noreply, assign(socket, :job_duration_percentile, value)}
  end

  def handle_event("select_workflow_duration_percentile", %{"value" => value}, socket) do
    {:noreply, assign(socket, :workflow_duration_percentile, value)}
  end

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

  def percentile_series(stats, "p50"), do: Map.get(stats, :p50_values, [])
  def percentile_series(stats, "p90"), do: Map.get(stats, :p90_values, [])
  def percentile_series(stats, "p99"), do: Map.get(stats, :p99_values, [])
  def percentile_series(stats, _), do: Map.get(stats, :avg_values, [])

  def legend_color_for_percentile("p50"), do: "p50"
  def legend_color_for_percentile("p90"), do: "p90"
  def legend_color_for_percentile("p99"), do: "p99"
  def legend_color_for_percentile(_), do: "secondary"

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
