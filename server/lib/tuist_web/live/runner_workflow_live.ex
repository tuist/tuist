defmodule TuistWeb.RunnerWorkflowLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.Skeleton
  import TuistWeb.PercentileDropdownWidget
  import TuistWeb.Widget

  alias Noora.Filter
  alias Tuist.Authorization
  alias Tuist.FeatureFlags
  alias Tuist.Runners.Analytics
  alias Tuist.Runners.Jobs
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Utilities.Query

  @page_size 20

  @impl true
  def mount(
        %{"repo_owner" => repo_owner, "repo_name" => repo_name, "workflow_name" => workflow_name_param},
        _session,
        %{assigns: %{selected_account: selected_account, current_user: current_user}} = socket
      ) do
    if Authorization.authorize(:projects_read, current_user, selected_account) != :ok or
         not FeatureFlags.runners_enabled?(selected_account) do
      raise TuistWeb.Errors.NotFoundError,
            dgettext("dashboard_runners", "The page you are looking for doesn't exist or has been moved.")
    end

    repo = "#{repo_owner}/#{repo_name}"
    workflow_name = URI.decode(workflow_name_param)

    head_title =
      "#{display_workflow(workflow_name)} · #{repo} · #{dgettext("dashboard_runners", "Workflows")} · #{selected_account.name} · Tuist"

    {:ok,
     socket
     |> assign(:head_title, head_title)
     |> assign(:repo, repo)
     |> assign(:workflow_name, workflow_name)
     |> assign(:available_filters, available_filters())
     |> assign(:analytics_selected_widget, "total_jobs")
     |> assign(:job_duration_percentile, "avg")
     |> assign(:queue_time_percentile, "avg")}
  end

  @impl true
  def handle_params(params, uri, %{assigns: %{selected_account: account, repo: repo, workflow_name: workflow_name}} = socket) do
    filters = Filter.Operations.decode_filters_from_query(params, socket.assigns.available_filters)
    page = parse_page(params["page"])
    search = params["search"] || ""
    sort_by = sort_by_param(params["sort_by"])
    sort_order = sort_order_param(params["sort_order"], sort_by)

    scope_opts = [repo: repo, workflow_name: workflow_name]

    socket =
      socket
      |> assign(:uri, URI.parse(uri))
      |> assign(:active_filters, filters)
      |> assign(:search, search)
      |> assign(:page, page)
      |> assign(:sort_by, sort_by)
      |> assign(:sort_order, sort_order)
      |> assign_jobs(scope_opts)
      |> assign_async(
        [:jobs_count, :failed_jobs_count, :jobs_duration, :queue_time],
        fn ->
          {:ok,
           %{
             jobs_count: Analytics.jobs_count(account.id, scope_opts),
             failed_jobs_count: Analytics.failed_jobs_count(account.id, scope_opts),
             jobs_duration: Analytics.jobs_duration(account.id, scope_opts),
             queue_time: Analytics.queue_time(account.id, scope_opts)
           }}
        end
      )

    {:noreply, socket}
  end

  defp assign_jobs(
         %{
           assigns: %{
             selected_account: account,
             active_filters: filters,
             page: page,
             search: search,
             sort_by: sort_by,
             sort_order: sort_order
           }
         } = socket,
         scope_opts
       ) do
    base_opts =
      scope_opts
      |> maybe_put_search(search)
      |> add_filter_opt(filters, "branch", :head_branch)
      |> add_status_filter_opt(filters)
      |> Keyword.put(:sort_by, sort_by)
      |> Keyword.put(:sort_order, sort_order)

    total = Jobs.count_for_account(account.id, base_opts)
    total_pages = max(1, ceil_div(total, @page_size))
    page = min(page, total_pages)
    offset = (page - 1) * @page_size

    paged_opts =
      base_opts
      |> Keyword.put(:limit, @page_size)
      |> Keyword.put(:offset, offset)

    jobs = Jobs.list_for_account(account.id, paged_opts)

    socket
    |> assign(:jobs, jobs)
    |> assign(:page, page)
    |> assign(:total_jobs, total)
    |> assign(:total_pages, total_pages)
  end

  defp maybe_put_search(opts, ""), do: opts
  defp maybe_put_search(opts, nil), do: opts
  defp maybe_put_search(opts, value) when is_binary(value), do: Keyword.put(opts, :search, value)

  defp add_filter_opt(opts, filters, filter_id, opt_key) do
    case Enum.find(filters, &(&1.id == filter_id)) do
      %{value: value} when is_binary(value) and value != "" -> Keyword.put(opts, opt_key, value)
      _ -> opts
    end
  end

  # Status filter routes the picked value to either `:status` (queued/
  # claimed/running) or `:conclusion` (success/failure/cancelled/
  # skipped) — same pattern as the Jobs page.
  defp add_status_filter_opt(opts, filters) do
    case Enum.find(filters, &(&1.id == "status")) do
      %{value: value} when not is_nil(value) ->
        value = to_string(value)

        cond do
          value in ~w(success failure cancelled skipped) ->
            opts |> Keyword.put(:conclusion, value) |> Keyword.put(:status, "completed")

          value in ~w(queued claimed running completed) ->
            Keyword.put(opts, :status, value)

          true ->
            opts
        end

      _ ->
        opts
    end
  end

  defp available_filters do
    [
      %Filter.Filter{
        id: "status",
        field: :status,
        display_name: dgettext("dashboard_runners", "Status"),
        type: :option,
        options: [:queued, :claimed, :running, :success, :failure, :cancelled, :skipped],
        options_display_names: %{
          queued: dgettext("dashboard_runners", "Queued"),
          claimed: dgettext("dashboard_runners", "Claimed"),
          running: dgettext("dashboard_runners", "Running"),
          success: dgettext("dashboard_runners", "Success"),
          failure: dgettext("dashboard_runners", "Failure"),
          cancelled: dgettext("dashboard_runners", "Cancelled"),
          skipped: dgettext("dashboard_runners", "Skipped")
        },
        operator: :==,
        value: nil
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

  @impl true
  def handle_event("select_widget", %{"widget" => widget}, socket) do
    {:noreply, assign(socket, :analytics_selected_widget, widget)}
  end

  def handle_event("select_job_duration_percentile", %{"type" => type}, socket) do
    {:noreply, assign(socket, :job_duration_percentile, type)}
  end

  def handle_event("select_queue_time_percentile", %{"type" => type}, socket) do
    {:noreply, assign(socket, :queue_time_percentile, type)}
  end

  def handle_event("search-jobs", %{"search" => search}, %{assigns: %{uri: uri}} = socket) do
    params =
      uri.query
      |> Query.put("search", search)
      |> Query.drop("page")
      |> URI.decode_query()

    {:noreply, push_patch(socket, to: current_path(socket, params))}
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params = Filter.Operations.add_filter_to_query(filter_id, socket, decoded_query(socket))

    {:noreply,
     socket
     |> push_patch(to: current_path(socket, updated_params))
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  def handle_event("update_filter", params, socket) do
    updated_params = Filter.Operations.update_filters_in_query(params, socket, decoded_query(socket))

    {:noreply,
     socket
     |> push_patch(to: current_path(socket, updated_params))
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
  end

  # Noora's `Filter.Operations` calls `URI.decode_query(socket.assigns.uri.query)`
  # by default, which crashes when `uri.query` is `nil` (the case on
  # first page load with no `?`). Pass a defensively-decoded params
  # map so the very first filter click on a fresh URL doesn't take
  # down the LiveView.
  defp decoded_query(%{assigns: %{uri: %URI{query: nil}}}), do: %{}
  defp decoded_query(%{assigns: %{uri: %URI{query: query}}}), do: URI.decode_query(query)

  defp current_path(%{assigns: %{selected_account: account, repo: repo, workflow_name: workflow_name}}, params) do
    [owner, name] = String.split(repo, "/", parts: 2)
    workflow = URI.encode(workflow_name, &URI.char_unreserved?/1)

    ~p"/#{account.name}/runners/workflows/#{owner}/#{name}/#{workflow}?#{params}"
  end

  # Bound the sort_by URL param. Default lands on the Enqueued at
  # column so the freshest jobs surface first; the Workflow sort is
  # omitted because the page is already scoped to one workflow.
  defp sort_by_param(value) when value in ["enqueued", "job", "duration"], do: value
  defp sort_by_param(_), do: "enqueued"

  defp sort_order_param(value, _sort_by) when value in ["asc", "desc"], do: value
  defp sort_order_param(_, "job"), do: "asc"
  defp sort_order_param(_, _numerical), do: "desc"

  def sort_by_label("job"), do: dgettext("dashboard_runners", "Job")
  def sort_by_label("duration"), do: dgettext("dashboard_runners", "Duration")
  def sort_by_label(_enqueued_default), do: dgettext("dashboard_runners", "Enqueued at")

  def sort_icon("asc"), do: "square_rounded_arrow_up"
  def sort_icon(_desc), do: "square_rounded_arrow_down"

  def column_sort_patch(assigns, column) do
    new_order =
      cond do
        assigns.sort_by == column -> toggle_sort_order(assigns.sort_order)
        column in ["job", "workflow"] -> "asc"
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

  defp parse_page(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  defp parse_page(_), do: 1

  defp ceil_div(0, _divisor), do: 0
  defp ceil_div(numerator, divisor), do: div(numerator + divisor - 1, divisor)

  def page_link(%URI{} = uri, page) do
    "?" <> Query.put(uri.query, "page", Integer.to_string(page))
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

  def format_duration_ms(ms) when is_integer(ms) and ms > 0, do: DateFormatter.format_duration_from_milliseconds(ms)

  def format_duration_ms(_), do: "–"

  def format_relative_time(%DateTime{} = ts) do
    if epoch?(ts), do: "–", else: DateFormatter.from_now(ts)
  end

  def format_relative_time(_), do: "–"

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
  Resolves the public repository URL for the header badge. GitHub
  Actions webhooks always deliver `repo` as `<owner>/<name>` so the
  canonical URL is just `https://github.com/<owner>/<name>`. The
  helper short-circuits to `#` for malformed values so the badge
  still renders without a broken outbound link.
  """
  def repo_url(repo) when is_binary(repo) do
    case String.split(repo, "/", parts: 2) do
      [owner, name] when owner != "" and name != "" -> "https://github.com/#{owner}/#{name}"
      _ -> "#"
    end
  end

  def repo_url(_), do: "#"

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
