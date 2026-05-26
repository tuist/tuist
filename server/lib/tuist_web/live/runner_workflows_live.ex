defmodule TuistWeb.RunnerWorkflowsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.Skeleton
  import TuistWeb.PercentileDropdownWidget
  import TuistWeb.Widget

  alias Tuist.Authorization
  alias Tuist.FeatureFlags
  alias Tuist.Runners.Analytics
  alias Tuist.Runners.Jobs
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Utilities.Query

  @page_size 20

  @impl true
  def mount(_params, _session, %{assigns: %{selected_account: selected_account, current_user: current_user}} = socket) do
    if Authorization.authorize(:projects_read, current_user, selected_account) != :ok or
         not FeatureFlags.runners_enabled?(selected_account) do
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
    platform = platform_param(params["platform"])
    search = params["search"] || ""
    sort_by = sort_by_param(params["sort_by"])
    sort_order = sort_order_param(params["sort_order"], sort_by)
    page = parse_page(params["page"])

    %{preset: preset, period: {start_datetime, end_datetime} = period} =
      DatePicker.date_picker_params(params, "analytics")

    {:noreply,
     socket
     |> assign(:uri, URI.parse(uri))
     |> assign(:repository, repository)
     |> assign(:platform, platform)
     |> assign(:search, search)
     |> assign(:sort_by, sort_by)
     |> assign(:sort_order, sort_order)
     |> assign(:page, page)
     |> assign(:analytics_preset, preset)
     |> assign(:analytics_period, period)
     |> assign(:analytics_trend_label, trend_label(preset))
     |> assign_analytics(repository, platform, start_datetime, end_datetime)
     |> assign_workflows(repository, platform, search, sort_by, sort_order)}
  end

  defp platform_param(value) when value in ["macos", "linux"], do: value
  defp platform_param(_), do: "any"

  # Bound the sort_by URL param to the values the backend knows how
  # to ORDER BY — anything else falls back to the default so a
  # malformed URL doesn't surface a 500.
  defp sort_by_param(value) when value in ["workflow", "success_rate", "jobs", "avg_duration"], do: value
  defp sort_by_param(_), do: "workflow"

  # Sort order is bounded to asc|desc. The default differs by column
  # so a fresh sort feels right: alphabetical columns lean ascending,
  # numerical columns lean descending (largest counts first).
  defp sort_order_param(value, _sort_by) when value in ["asc", "desc"], do: value
  defp sort_order_param(_, "workflow"), do: "asc"
  defp sort_order_param(_, _), do: "desc"

  @impl true
  def handle_event("select_widget", %{"widget" => widget}, socket) do
    {:noreply, assign(socket, :analytics_selected_widget, widget)}
  end

  def handle_event("select_workflow_duration_percentile", %{"type" => type}, socket) do
    {:noreply, assign(socket, :workflow_duration_percentile, type)}
  end

  def handle_event(
        "analytics_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        %{assigns: %{selected_account: account, uri: uri}} = socket
      ) do
    if_result =
      if preset == "custom" do
        uri.query
        |> Query.put("analytics-date-range", "custom")
        |> Query.put("analytics-start-date", start_date)
        |> Query.put("analytics-end-date", end_date)
      else
        uri.query
        |> Query.put("analytics-date-range", preset)
        |> Query.drop("analytics-start-date")
        |> Query.drop("analytics-end-date")
      end

    query = URI.decode_query(if_result)

    {:noreply, push_patch(socket, to: ~p"/#{account.name}/runners/workflows?#{query}")}
  end

  def handle_event("search-workflows", %{"search" => search}, %{assigns: %{selected_account: account, uri: uri}} = socket) do
    # Reset to page 1 on every keystroke — leaving page=3 attached
    # while the result set shrinks past page 1 would land the viewer
    # on an empty page until assign_workflows clamps it back.
    params =
      uri.query
      |> Query.put("search", search)
      |> Query.put("page", "1")
      |> URI.decode_query()

    {:noreply, push_patch(socket, to: ~p"/#{account.name}/runners/workflows?#{params}")}
  end

  # Re-runs all three account-level analytics queries whenever the
  # repository scope or the date range changes. We wrap in
  # `assign_async` so the chart area can flip to the skeleton while
  # the new query is in flight.
  defp assign_analytics(%{assigns: %{selected_account: account}} = socket, repository, platform, start_dt, end_dt) do
    bucket = Analytics.bucket_for_window(start_dt, end_dt)

    scope_opts =
      repository
      |> scope_opts()
      |> maybe_platform(platform)
      |> Keyword.put(:start_datetime, start_dt)
      |> Keyword.put(:end_datetime, end_dt)
      |> Keyword.put(:bucket, bucket)

    socket
    |> assign(:analytics_bucket, bucket)
    |> assign_async(
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

  defp assign_workflows(
         %{assigns: %{selected_account: account, page: page}} = socket,
         repository,
         platform,
         search,
         sort_by,
         sort_order
       ) do
    base_opts =
      repository
      |> scope_opts()
      |> maybe_platform(platform)
      |> maybe_put_search(search)

    total = Jobs.count_workflows_for_account(account.id, base_opts)
    total_pages = max(1, ceil_div(total, @page_size))
    page = min(page, total_pages)
    offset = (page - 1) * @page_size

    paged_opts =
      base_opts
      |> Keyword.put(:limit, @page_size)
      |> Keyword.put(:offset, offset)
      |> Keyword.put(:sort_by, sort_by)
      |> Keyword.put(:sort_order, sort_order)

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

  defp maybe_platform(opts, "any"), do: opts
  defp maybe_platform(opts, nil), do: opts
  defp maybe_platform(opts, ""), do: opts
  defp maybe_platform(opts, platform) when platform in ["macos", "linux"], do: Keyword.put(opts, :platform, platform)
  defp maybe_platform(opts, _), do: opts

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

  @doc """
  Patches the URL to swap the Platform scope while preserving every
  other piece of state.
  """
  def platform_patch(%URI{} = uri, platform) do
    "?" <> Query.put(uri.query, "platform", platform)
  end

  def platform_label("macos"), do: dgettext("dashboard_runners", "macOS")
  def platform_label("linux"), do: dgettext("dashboard_runners", "Linux")
  def platform_label(_any), do: dgettext("dashboard_runners", "Any")

  def platforms, do: ["macos", "linux"]

  @doc """
  Builds the patch URL for a sortable column header. Clicking the
  column that's already the active sort toggles asc/desc; clicking
  a different column switches to it with its default direction
  (asc for `workflow`, desc otherwise). Always drops `page` so a
  fresh sort starts on page 1.
  """
  def column_sort_patch(assigns, column) do
    new_order =
      cond do
        assigns.sort_by == column -> toggle_sort_order(assigns.sort_order)
        column == "workflow" -> "asc"
        true -> "desc"
      end

    "?" <>
      (assigns.uri.query
       |> Query.put("sort_by", column)
       |> Query.put("sort_order", new_order)
       |> Query.drop("page"))
  end

  defp toggle_sort_order("asc"), do: "desc"
  defp toggle_sort_order(_desc), do: "asc"

  def sort_icon("asc"), do: "square_rounded_arrow_up"
  def sort_icon(_desc), do: "square_rounded_arrow_down"

  def sort_by_label("jobs"), do: dgettext("dashboard_runners", "Jobs")
  def sort_by_label("success_rate"), do: dgettext("dashboard_runners", "Success rate")
  def sort_by_label("avg_duration"), do: dgettext("dashboard_runners", "Avg duration")
  def sort_by_label(_workflow_default), do: dgettext("dashboard_runners", "Workflow")

  # The trend chip on each widget reads "since last <unit>" — pair
  # the unit to the active preset so the comparison label matches
  # the window the analytics are computed over.
  defp trend_label("last-24-hours"), do: dgettext("dashboard_runners", "since yesterday")
  defp trend_label("last-7-days"), do: dgettext("dashboard_runners", "since last week")
  defp trend_label("last-12-months"), do: dgettext("dashboard_runners", "since last year")
  defp trend_label("custom"), do: dgettext("dashboard_runners", "since last period")
  defp trend_label(_), do: dgettext("dashboard_runners", "since last month")

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
  def chart_options(dates, bucket \\ :day) do
    tooltip = if bucket == :hour, do: %{dateFormat: "hour"}, else: %{}

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
      tooltip: tooltip
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
