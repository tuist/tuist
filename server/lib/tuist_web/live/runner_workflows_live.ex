defmodule TuistWeb.RunnerWorkflowsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Noora.Filter
  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.Skeleton
  import TuistWeb.PercentileDropdownWidget
  import TuistWeb.Widget

  alias Noora.Filter
  alias Tuist.Authorization
  alias Tuist.Runners.Analytics
  alias Tuist.Runners.Jobs
  alias Tuist.Utilities.DateFormatter

  @page_size 50

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
       "#{dgettext("dashboard_runners", "Workflows")} · #{selected_account.name} · Tuist"
     )
     |> assign(:available_filters, available_filters())
     |> assign(:analytics_selected_widget, "workflow_runs")
     |> assign(:workflow_duration_percentile, "avg")
     |> assign_async(
       [:workflow_runs_count, :failed_workflow_runs_count, :workflows_duration],
       fn ->
         {:ok,
          %{
            workflow_runs_count: Analytics.workflow_runs_count(selected_account.id),
            failed_workflow_runs_count: Analytics.failed_workflow_runs_count(selected_account.id),
            workflows_duration: Analytics.workflows_duration(selected_account.id)
          }}
       end
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = Filter.Operations.decode_filters_from_query(params, socket.assigns.available_filters)

    {:noreply,
     socket
     |> assign(:active_filters, filters)
     |> assign_workflows()}
  end

  @impl true
  def handle_event("select_widget", %{"widget" => widget}, socket) do
    {:noreply, assign(socket, :analytics_selected_widget, widget)}
  end

  def handle_event("select_workflow_duration_percentile", %{"type" => type}, socket) do
    {:noreply, assign(socket, :workflow_duration_percentile, type)}
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params = Filter.Operations.add_filter_to_query(filter_id, socket)

    {:noreply,
     socket
     |> push_patch(to: ~p"/#{socket.assigns.selected_account.name}/runners/workflows?#{updated_params}")
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  @impl true
  def handle_event("update_filter", params, socket) do
    updated_params = Filter.Operations.update_filters_in_query(params, socket)

    {:noreply,
     socket
     |> push_patch(to: ~p"/#{socket.assigns.selected_account.name}/runners/workflows?#{updated_params}")
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
  end

  defp assign_workflows(%{assigns: %{selected_account: account, active_filters: filters}} = socket) do
    opts =
      [limit: @page_size]
      |> add_filter_opt(filters, "repository", :repo)
      |> add_filter_opt(filters, "workflow", :workflow_name)
      |> add_filter_opt(filters, "branch", :head_branch)

    workflows = Jobs.list_workflows_for_account(account.id, opts)
    assign(socket, :workflows, workflows)
  end

  defp add_filter_opt(opts, filters, filter_id, opt_key) do
    case Enum.find(filters, &(&1.id == filter_id)) do
      %{value: value} when is_binary(value) and value != "" -> Keyword.put(opts, opt_key, value)
      _ -> opts
    end
  end

  defp available_filters do
    [
      %Filter.Filter{
        id: "repository",
        field: :repo,
        display_name: dgettext("dashboard_runners", "Repository"),
        type: :text,
        operator: :=~,
        value: ""
      },
      %Filter.Filter{
        id: "workflow",
        field: :workflow_name,
        display_name: dgettext("dashboard_runners", "Workflow"),
        type: :text,
        operator: :=~,
        value: ""
      },
      %Filter.Filter{
        id: "branch",
        field: :head_branch,
        display_name: dgettext("dashboard_runners", "Branch"),
        type: :text,
        operator: :=~,
        value: ""
      }
    ]
  end

  def success_rate(%{success_count: success, total_jobs: total}) when total > 0 do
    rate = success / total * 100

    rate
    |> Float.round(1)
    |> :erlang.float_to_binary(decimals: 1)
    |> Kernel.<>("%")
  end

  def success_rate(_), do: "–"

  def format_duration_ms(value) when is_number(value) and value > 0,
    do: DateFormatter.format_duration_from_milliseconds(round(value))

  def format_duration_ms(_), do: "–"

  def from_now_or_dash(%DateTime{year: 1970}), do: "–"
  def from_now_or_dash(%DateTime{} = ts), do: DateFormatter.from_now(ts)
  def from_now_or_dash(_), do: "–"

  @doc """
  Resolves the per-row link target for the workflows table. Returns
  a detail-page path when both `repo` (in `owner/name` form) and
  `workflow_name` are present; rows missing either field — legacy
  webhook payloads from before `workflow_name` landed — fall back
  to the workflows index so Noora's `row_navigate` still has a
  valid URL to bind.
  """
  def workflow_path(account_name, %{repo: repo, workflow_name: workflow_name})
      when is_binary(repo) and is_binary(workflow_name) and repo != "" and workflow_name != "" do
    case String.split(repo, "/", parts: 2) do
      [owner, name] when owner != "" and name != "" ->
        "/#{account_name}/runners/workflows/#{URI.encode(owner, &URI.char_unreserved?/1)}/#{URI.encode(name, &URI.char_unreserved?/1)}/#{URI.encode(workflow_name, &URI.char_unreserved?/1)}"

      _ ->
        fallback_path(account_name)
    end
  end

  def workflow_path(account_name, _row), do: fallback_path(account_name)

  defp fallback_path(account_name), do: "/#{account_name}/runners/workflows"

  @doc """
  echarts `extra_options` for the workflow-level count charts on
  the analytics card. Matches the single-series count pattern used
  by `RunnerWorkflowLive.chart_options/1` — date-formatted x-axis,
  plain numeric y-axis, no legend.
  """
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
