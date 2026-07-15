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
  alias Tuist.VCS
  alias TuistWeb.Utilities.Query

  @page_size 20

  @impl true
  def mount(
        %{"repo_owner" => repo_owner, "repo_name" => repo_name, "workflow_name" => workflow_name_param},
        _session,
        %{assigns: %{selected_account: selected_account, current_user: current_user}} = socket
      ) do
    if Authorization.authorize(:runners_read, current_user, selected_account) != :ok or
         not FeatureFlags.runners_enabled?(selected_account) do
      raise TuistWeb.Errors.NotFoundError,
            dgettext("dashboard_runners", "The page you are looking for doesn't exist or has been moved.")
    end

    repository = "#{repo_owner}/#{repo_name}"
    workflow_name = URI.decode(workflow_name_param)

    head_title =
      "#{display_workflow(workflow_name)} · #{repository} · #{dgettext("dashboard_runners", "Workflows")} · #{selected_account.name} · Tuist"

    {:ok,
     socket
     |> assign(:head_title, head_title)
     |> assign(:repository, repository)
     |> assign(:workflow_name, workflow_name)
     |> assign(:github_base_url, VCS.github_base_url_for_account(selected_account.id))
     |> assign(:available_filters, available_filters())
     |> assign(:analytics_selected_widget, "total_jobs")
     |> assign(:job_duration_percentile, "avg")
     |> assign(:queue_time_percentile, "avg")}
  end

  @impl true
  def handle_params(
        params,
        uri,
        %{assigns: %{selected_account: account, repository: repository, workflow_name: workflow_name}} = socket
      ) do
    filters = Filter.Operations.decode_filters_from_query(params, socket.assigns.available_filters)
    page = parse_page(params["page"])
    search = params["search"] || ""
    sort_by = sort_by_param(params["sort_by"])
    sort_order = sort_order_param(params["sort_order"], sort_by)

    scope_opts = [repository: repository, workflow_name: workflow_name]

    socket =
      socket
      |> assign(:uri, URI.parse(uri))
      |> assign(:active_filters, filters)
      |> assign(:search, search)
      |> assign(:page, page)
      |> assign(:sort_by, sort_by)
      |> assign(:sort_order, sort_order)
      |> assign_runs(scope_opts)
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

  # Lists workflow *runs* (grouped by workflow_run_id) for this named
  # workflow, newest activity first. This page is a drill-down from the
  # Workflows list, so runs — not individual jobs — are the rows;
  # clicking a run opens its GitHub Actions run.
  defp assign_runs(
         %{
           assigns: %{
             selected_account: account,
             active_filters: filters,
             page: page,
             repository: repository,
             workflow_name: workflow_name
           }
         } = socket,
         _scope_opts
       ) do
    base_opts = add_filter_opt([], filters, "branch", :head_branch)

    total = Jobs.count_workflow_runs(account.id, repository, workflow_name, base_opts)
    total_pages = max(1, ceil_div(total, @page_size))
    page = min(page, total_pages)
    offset = (page - 1) * @page_size

    paged_opts =
      base_opts
      |> Keyword.put(:limit, @page_size)
      |> Keyword.put(:offset, offset)

    runs = Jobs.list_workflow_runs(account.id, repository, workflow_name, paged_opts)

    socket
    |> assign(:runs, runs)
    |> assign(:page, page)
    |> assign(:total_runs, total)
    |> assign(:total_pages, total_pages)
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

  defp current_path(
         %{assigns: %{selected_account: account, repository: repository, workflow_name: workflow_name}},
         params
       ) do
    [owner, name] = String.split(repository, "/", parts: 2)
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
  def conclusion_badge_props("timed_out"), do: %{label: dgettext("dashboard_runners", "Timed out"), status: "error"}
  def conclusion_badge_props("cancelled"), do: %{label: dgettext("dashboard_runners", "Cancelled"), status: "warning"}
  def conclusion_badge_props("stale"), do: %{label: dgettext("dashboard_runners", "Stale"), status: "warning"}
  def conclusion_badge_props("neutral"), do: %{label: dgettext("dashboard_runners", "Neutral"), status: "warning"}

  def conclusion_badge_props("action_required"),
    do: %{label: dgettext("dashboard_runners", "Action required"), status: "warning"}

  def conclusion_badge_props("skipped"), do: %{label: dgettext("dashboard_runners", "Skipped"), status: "warning"}

  # Any other GitHub conclusion (startup_failure, …) — humanise the raw
  # value rather than dropping it or mislabelling it as skipped.
  def conclusion_badge_props(other) when is_binary(other) and other != "",
    do: %{label: other |> String.replace("_", " ") |> String.capitalize(), status: "warning"}

  def conclusion_badge_props(_), do: nil

  # Run-level status badge: an in-progress run (any job still going)
  # shows Running; a completed run shows its rolled-up conclusion.
  def run_status_badge_props(%{status: "in_progress"}),
    do: %{label: dgettext("dashboard_runners", "Running"), status: "in_progress"}

  def run_status_badge_props(%{status: "completed", conclusion: conclusion}),
    do: conclusion_badge_props(conclusion) || %{label: dgettext("dashboard_runners", "Completed"), status: "success"}

  def run_status_badge_props(_), do: %{label: dgettext("dashboard_runners", "Unknown"), status: "warning"}

  @doc """
  Internal path to a run's detail page. Each runs-list row navigates
  here (the whole row is the link).
  """
  def run_path(account_name, run_id) when is_binary(account_name) and is_integer(run_id) and run_id > 0 do
    "/#{account_name}/runners/runs/#{run_id}"
  end

  def run_path(_, _), do: nil

  # Duration for a run row: elapsed-so-far for an in-progress run,
  # else the completed span. Elapsed time counts from the earliest job
  # `started_at`, not `enqueued_at`, so a run whose only job is still
  # queued reads as 0 (rendered "–") rather than accumulating queue
  # time. The SQL `duration_ms` is only meaningful once the run has a
  # completed job, so guard on a positive value.
  def run_duration_ms(%{status: "in_progress", started_at: started}) when not is_nil(started),
    do: DateFormatter.ms_since(started)

  def run_duration_ms(%{status: "in_progress"}), do: 0
  def run_duration_ms(%{duration_ms: ms}) when is_integer(ms) and ms > 0, do: ms
  def run_duration_ms(_), do: 0

  # Duration label for a run row — an em dash until the run has
  # actually started executing, so a still-queued run doesn't read as
  # "0s". Mirrors the run detail page's treatment.
  def run_duration_label(run) do
    case run_duration_ms(run) do
      ms when is_integer(ms) and ms > 0 -> DateFormatter.format_duration_from_milliseconds(ms)
      _ -> "–"
    end
  end

  @doc """
  GitHub Actions run URL for the run detail's external link. `base_url`
  is the account installation's host (`https://github.com` or a GitHub
  Enterprise Server `client_url`), so the link points at the right host
  for GHES installations rather than always assuming github.com.
  """
  def github_run_url(base_url, repository, run_id)
      when is_binary(base_url) and base_url != "" and is_binary(repository) and is_integer(run_id) do
    case String.split(repository, "/", parts: 2) do
      [owner, name] when owner != "" and name != "" ->
        "#{base_url}/#{owner}/#{name}/actions/runs/#{run_id}"

      _ ->
        "#"
    end
  end

  def github_run_url(_, _, _), do: "#"

  def duration_ms(%{status: "queued", enqueued_at: enqueued}), do: DateFormatter.ms_since(enqueued)
  def duration_ms(%{status: "claimed", claimed_at: claimed}), do: DateFormatter.ms_since(claimed)
  def duration_ms(%{status: "running", started_at: started}), do: DateFormatter.ms_since(started)

  def duration_ms(%{status: "completed", started_at: started, completed_at: completed}) do
    cond do
      is_nil(started) -> 0
      is_nil(completed) -> 0
      true -> DateTime.diff(completed, started, :millisecond)
    end
  end

  def duration_ms(_), do: 0

  @doc """
  Resolves the repository URL for the header badge. `base_url` is the
  account installation's host (`https://github.com` or a GitHub
  Enterprise Server `client_url`); GitHub Actions webhooks always
  deliver `repository` as `<owner>/<name>`, so the URL is
  `<base_url>/<owner>/<name>`. The helper short-circuits to `#` for
  malformed values so the badge still renders without a broken
  outbound link.
  """
  def repository_url(base_url, repository) when is_binary(base_url) and base_url != "" and is_binary(repository) do
    case String.split(repository, "/", parts: 2) do
      [owner, name] when owner != "" and name != "" -> "#{base_url}/#{owner}/#{name}"
      _ -> "#"
    end
  end

  def repository_url(_, _), do: "#"

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
