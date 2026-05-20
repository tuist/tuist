defmodule TuistWeb.RunnerWorkflowsLive do
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
  alias TuistWeb.Utilities.Query

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
     |> assign(:repos, Jobs.distinct_repos_for_account(selected_account.id))
     |> assign(:analytics_selected_widget, "workflow_runs")
     |> assign(:workflow_duration_percentile, "avg")}
  end

  @impl true
  def handle_params(params, uri, socket) do
    repository = params["repository"] || "any"
    search = params["search"] || ""
    page = parse_page(params["page"])

    {:noreply,
     socket
     |> assign(:uri, URI.parse(uri))
     |> assign(:repository, repository)
     |> assign(:search, search)
     |> assign(:page, page)
     |> assign_analytics(repository)
     |> assign_workflows(repository, search)}
  end

  @impl true
  def handle_event("select_widget", %{"widget" => widget}, socket) do
    {:noreply, assign(socket, :analytics_selected_widget, widget)}
  end

  def handle_event("select_workflow_duration_percentile", %{"type" => type}, socket) do
    {:noreply, assign(socket, :workflow_duration_percentile, type)}
  end

  def handle_event("search-workflows", %{"search" => search}, %{assigns: %{selected_account: account, uri: uri}} = socket) do
    # Reset to page 1 on every keystroke — leaving page=3 attached
    # while the result set shrinks past page 1 would land the viewer
    # on an empty page until assign_workflows clamps it back.
    query =
      uri.query
      |> Query.put("search", search)
      |> Query.put("page", "1")

    {:noreply, push_patch(socket, to: ~p"/#{account.name}/runners/workflows?#{query}")}
  end

  # Re-runs all three account-level analytics queries whenever the
  # repository scope changes. We wrap in `assign_async` so the chart
  # area can flip to the skeleton while the new query is in flight.
  defp assign_analytics(%{assigns: %{selected_account: account}} = socket, repository) do
    scope_opts = scope_opts(repository)

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

  defp assign_workflows(%{assigns: %{selected_account: account, page: page}} = socket, repository, search) do
    base_opts =
      repository
      |> scope_opts()
      |> maybe_put_search(search)

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

  defp scope_opts("any"), do: []
  defp scope_opts(nil), do: []
  defp scope_opts(""), do: []
  defp scope_opts(repo) when is_binary(repo), do: [repo: repo]

  defp maybe_put_search(opts, ""), do: opts
  defp maybe_put_search(opts, nil), do: opts
  defp maybe_put_search(opts, search) when is_binary(search), do: Keyword.put(opts, :workflow_name, search)

  defp ceil_div(0, _divisor), do: 0
  defp ceil_div(numerator, divisor), do: div(numerator + divisor - 1, divisor)

  defp parse_page(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  defp parse_page(_), do: 1

  @doc """
  Builds the patch URL for the repository dropdown, preserving every
  other query param so a viewer toggling the scope doesn't lose page,
  filter, or chart-selection state.
  """
  def repository_patch(%URI{} = uri, repository) do
    "?" <> Query.put(uri.query, "repository", repository)
  end

  def repository_label("any"), do: dgettext("dashboard_runners", "Any")
  def repository_label(repo) when is_binary(repo), do: repo

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
    "?" <> Query.put(uri.query, "page", Integer.to_string(page))
  end
end
