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

  @page_size 25

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
     |> assign(:page_filters, page_filters())
     |> assign(:card_filters, card_filters())
     |> assign(:analytics_selected_widget, "workflow_runs")
     |> assign(:workflow_duration_percentile, "avg")}
  end

  @impl true
  def handle_params(params, uri, socket) do
    filters = Filter.Operations.decode_filters_from_query(params, socket.assigns.available_filters)
    repo = find_filter_value(filters, "repository")
    page = parse_page(params["page"])

    {:noreply,
     socket
     |> assign(:uri, URI.parse(uri))
     |> assign(:active_filters, filters)
     |> assign(:page, page)
     |> assign_analytics(repo)
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

  # Re-runs all three account-level analytics queries whenever the
  # repository scope changes. We wrap in `assign_async` so the chart
  # area can flip to the skeleton while the new query is in flight.
  defp assign_analytics(%{assigns: %{selected_account: account}} = socket, repo) do
    scope_opts = if repo, do: [repo: repo], else: []

    assign_async(
      socket,
      [:workflow_runs_count, :failed_workflow_runs_count, :workflows_duration],
      fn ->
        {:ok,
         %{
           workflow_runs_count: Analytics.workflow_runs_count(account.id, scope_opts),
           failed_workflow_runs_count: Analytics.failed_workflow_runs_count(account.id, scope_opts),
           workflows_duration: Analytics.workflows_duration(account.id, scope_opts)
         }}
      end
    )
  end

  defp assign_workflows(%{assigns: %{selected_account: account, active_filters: filters, page: page}} = socket) do
    base_opts =
      []
      |> add_filter_opt(filters, "repository", :repo)
      |> add_filter_opt(filters, "workflow", :workflow_name)
      |> add_filter_opt(filters, "branch", :head_branch)

    total = Jobs.count_workflows_for_account(account.id, base_opts)
    total_pages = max(1, ceil_div(total, @page_size))
    page = min(page, total_pages)
    offset = (page - 1) * @page_size

    paged_opts =
      base_opts
      |> Keyword.put(:limit, @page_size)
      |> Keyword.put(:offset, offset)

    workflows = Jobs.list_workflows_for_account(account.id, paged_opts)

    socket
    |> assign(:workflows, workflows)
    |> assign(:page, page)
    |> assign(:total_workflows, total)
    |> assign(:total_pages, total_pages)
  end

  defp ceil_div(0, _divisor), do: 0
  defp ceil_div(numerator, divisor), do: div(numerator + divisor - 1, divisor)

  defp parse_page(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  defp parse_page(_), do: 1

  defp find_filter_value(filters, id) do
    case Enum.find(filters, &(&1.id == id)) do
      %{value: value} when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp add_filter_opt(opts, filters, filter_id, opt_key) do
    case Enum.find(filters, &(&1.id == filter_id)) do
      %{value: value} when is_binary(value) and value != "" -> Keyword.put(opts, opt_key, value)
      _ -> opts
    end
  end

  # Repository scope lives at the page level — it gates both the
  # analytics widgets AND the workflows table, so collapsing it into
  # a single chip on the top filter bar avoids the awkward "two
  # filter rows do almost the same thing" arrangement.
  defp page_filters do
    [
      %Filter.Filter{
        id: "repository",
        field: :repo,
        display_name: dgettext("dashboard_runners", "Repository"),
        type: :text,
        operator: :=~,
        value: ""
      }
    ]
  end

  # Workflow name and branch only narrow the table — analytics
  # already operate at the workflow-run granularity, so keeping them
  # inside the card avoids surprising the viewer when the widgets
  # don't react to a workflow-name search.
  defp card_filters do
    [
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

  defp available_filters, do: page_filters() ++ card_filters()

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

  @doc """
  Returns the query string for a given workflows-table page number,
  preserving the current filter state pulled from `uri`.
  """
  def page_link(uri, page) do
    query =
      (uri.query || "")
      |> URI.decode_query()
      |> Map.put("page", Integer.to_string(page))
      |> URI.encode_query()

    "?" <> query
  end
end
