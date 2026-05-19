defmodule TuistWeb.RunnerWorkflowLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.Skeleton
  import TuistWeb.Widget

  alias Tuist.Authorization
  alias Tuist.Runners.Analytics
  alias Tuist.Runners.Jobs
  alias Tuist.Utilities.DateFormatter

  @recent_jobs_limit 25

  @impl true
  def mount(
        %{"repo_owner" => repo_owner, "repo_name" => repo_name, "workflow_name" => workflow_name_param},
        _session,
        %{assigns: %{selected_account: selected_account, current_user: current_user}} = socket
      ) do
    if Authorization.authorize(:projects_read, current_user, selected_account) != :ok do
      raise TuistWeb.Errors.NotFoundError,
            dgettext("dashboard_runners", "The page you are looking for doesn't exist or has been moved.")
    end

    repo = "#{repo_owner}/#{repo_name}"
    workflow_name = URI.decode(workflow_name_param)

    head_title =
      "#{display_workflow(workflow_name)} · #{repo} · #{dgettext("dashboard_runners", "Workflows")} · #{selected_account.name} · Tuist"

    scope_opts = [repo: repo, workflow_name: workflow_name]

    socket =
      socket
      |> assign(:head_title, head_title)
      |> assign(:repo, repo)
      |> assign(:workflow_name, workflow_name)
      |> assign(:analytics_selected_widget, "total_jobs")
      |> assign(
        :recent_jobs,
        Jobs.list_for_account(selected_account.id, scope_opts ++ [limit: @recent_jobs_limit])
      )
      |> assign_async(
        [:jobs_count, :failed_jobs_count, :jobs_duration, :success_rate],
        fn ->
          {:ok,
           %{
             jobs_count: Analytics.jobs_count(selected_account.id, scope_opts),
             failed_jobs_count: Analytics.failed_jobs_count(selected_account.id, scope_opts),
             jobs_duration: Analytics.jobs_duration(selected_account.id, scope_opts),
             success_rate: Analytics.success_rate(selected_account.id, scope_opts)
           }}
        end
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("select_widget", %{"widget" => widget}, socket) do
    {:noreply, assign(socket, :analytics_selected_widget, widget)}
  end

  def display_workflow(""), do: dgettext("dashboard_runners", "Unknown")
  def display_workflow(nil), do: dgettext("dashboard_runners", "Unknown")
  def display_workflow(value) when is_binary(value), do: value

  def status_badge_props("queued"), do: %{label: dgettext("dashboard_runners", "Queued"), status: "warning"}
  def status_badge_props("claimed"), do: %{label: dgettext("dashboard_runners", "Claimed"), status: "in_progress"}
  def status_badge_props("running"), do: %{label: dgettext("dashboard_runners", "Running"), status: "in_progress"}
  def status_badge_props("completed"), do: %{label: dgettext("dashboard_runners", "Completed"), status: "success"}
  def status_badge_props(_), do: %{label: dgettext("dashboard_runners", "Unknown"), status: "warning"}

  def conclusion_badge_props("success"), do: %{label: dgettext("dashboard_runners", "Success"), status: "success"}
  def conclusion_badge_props("failure"), do: %{label: dgettext("dashboard_runners", "Failure"), status: "error"}
  def conclusion_badge_props("cancelled"), do: %{label: dgettext("dashboard_runners", "Cancelled"), status: "warning"}
  def conclusion_badge_props("skipped"), do: %{label: dgettext("dashboard_runners", "Skipped"), status: "warning"}

  def conclusion_badge_props(other) when is_binary(other) and other != "",
    do: %{label: String.capitalize(other), status: "warning"}

  def conclusion_badge_props(_), do: nil

  def format_success_rate(nil), do: "–"

  def format_success_rate(value) when is_number(value), do: :erlang.float_to_binary(value / 1, decimals: 1) <> "%"

  def format_duration_ms(ms) when is_integer(ms) and ms > 0, do: DateFormatter.format_duration_from_milliseconds(ms)

  def format_duration_ms(_), do: "–"

  def duration_ms(%{status: "queued", enqueued_at: enqueued}), do: ms_since(enqueued)
  def duration_ms(%{status: "claimed", claimed_at: claimed}), do: ms_since(claimed)
  def duration_ms(%{status: "running", started_at: started}), do: ms_since(started)

  def duration_ms(%{status: "completed", started_at: started, completed_at: completed}) do
    cond do
      is_nil(started) or epoch?(started) -> 0
      is_nil(completed) or epoch?(completed) -> 0
      true -> DateTime.diff(completed, started, :millisecond)
    end
  end

  def duration_ms(_), do: 0

  defp ms_since(nil), do: 0

  defp ms_since(%DateTime{} = ts) do
    if epoch?(ts), do: 0, else: DateTime.diff(DateTime.utc_now(), ts, :millisecond)
  end

  defp epoch?(%DateTime{year: 1970, month: 1, day: 1}), do: true
  defp epoch?(_), do: false

  def short_sha(""), do: "–"
  def short_sha(nil), do: "–"
  def short_sha(sha) when is_binary(sha), do: String.slice(sha, 0, 7)

  @doc """
  Builds the Jobs-page URL pre-seeded with the Noora filter params
  matching this workflow. The `?filter_<id>_op` + `?filter_<id>_val`
  pair is the shape `decode_filters_from_query/2` expects, so the
  Jobs view rehydrates with both filters already active.
  """
  def jobs_filter_path(account_name, repo, workflow_name) do
    query =
      URI.encode_query(%{
        "filter_repository_op" => "=~",
        "filter_repository_val" => repo,
        "filter_workflow_op" => "=~",
        "filter_workflow_val" => workflow_name
      })

    "/#{account_name}/runners/jobs?#{query}"
  end

  def chart_options(dates) do
    %{
      grid: %{width: "97%", left: "0.4%", height: "88%", top: "5%"},
      xAxis: %{
        boundaryGap: false,
        type: "category",
        axisLabel: %{
          color: "var:noora-surface-label-secondary",
          formatter: "fn:toLocaleDate",
          customValues: [List.first(dates), List.last(dates)],
          padding: [10, 0, 0, 0]
        }
      },
      yAxis: %{
        splitNumber: 4,
        splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
        axisLabel: %{color: "var:noora-surface-label-secondary"}
      },
      legend: %{show: false},
      tooltip: %{}
    }
  end
end
