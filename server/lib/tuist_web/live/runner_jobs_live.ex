defmodule TuistWeb.RunnerJobsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Noora.Filter
  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.Skeleton
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

    if connected?(socket) do
      Tuist.PubSub.subscribe(Jobs.topic(selected_account.id))
    end

    {:ok,
     socket
     |> assign(
       :head_title,
       "#{dgettext("dashboard_runners", "Jobs")} · #{selected_account.name} · Tuist"
     )
     |> assign(:available_filters, available_filters())
     |> assign(:analytics_selected_widget, "cumulative_minutes")
     |> assign_async(
       [:jobs_count, :failed_jobs_count, :cumulative_minutes, :live_status_counts],
       fn ->
         {:ok,
          %{
            jobs_count: Analytics.jobs_count(selected_account.id),
            failed_jobs_count: Analytics.failed_jobs_count(selected_account.id),
            cumulative_minutes: Analytics.cumulative_minutes(selected_account.id),
            live_status_counts: Jobs.status_counts(selected_account.id)
          }}
       end
     )}
  end

  @impl true
  def handle_params(params, uri, socket) do
    filters = Filter.Operations.decode_filters_from_query(params, socket.assigns.available_filters)
    page = parse_page(params["page"])

    {:noreply,
     socket
     |> assign(:uri, URI.parse(uri))
     |> assign(:active_filters, filters)
     |> assign(:page, page)
     |> assign_jobs()}
  end

  defp parse_page(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  defp parse_page(_), do: 1

  @impl true
  def handle_event("select_widget", %{"widget" => widget}, socket) do
    {:noreply, assign(socket, :analytics_selected_widget, widget)}
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params = Filter.Operations.add_filter_to_query(filter_id, socket)

    {:noreply,
     socket
     |> push_patch(to: ~p"/#{socket.assigns.selected_account.name}/runners/jobs?#{updated_params}")
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  def handle_event("update_filter", params, socket) do
    updated_params = Filter.Operations.update_filters_in_query(params, socket)

    {:noreply,
     socket
     |> push_patch(to: ~p"/#{socket.assigns.selected_account.name}/runners/jobs?#{updated_params}")
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
  end

  @impl true
  def handle_info({:runner_jobs_status_changed, _payload}, socket) do
    # Refresh the live Running / Queued counts plus the jobs table on
    # every state transition for the account. Filters and pagination
    # state are preserved via `assign_jobs/1`. Wraps the result in
    # AsyncResult so the template can keep reading `.ok?` / `.result`
    # the same way it did right after the initial `assign_async`.
    counts = Jobs.status_counts(socket.assigns.selected_account.id)

    {:noreply,
     socket
     |> assign(:live_status_counts, Phoenix.LiveView.AsyncResult.ok(counts))
     |> assign_jobs()}
  end

  defp assign_jobs(
         %{
           assigns: %{
             selected_account: account,
             active_filters: filters,
             page: page
           }
         } = socket
       ) do
    base_opts =
      []
      |> add_filter_opt(filters, "repository", :repo)
      |> add_filter_opt(filters, "workflow", :workflow_name)
      |> add_filter_opt(filters, "job", :job_name)
      |> add_filter_opt(filters, "branch", :head_branch)
      |> add_option_opt(filters, "status", :status)
      |> add_option_opt(filters, "conclusion", :conclusion)

    total = Jobs.count_for_account(account.id, base_opts)
    total_pages = max(1, ceil_div(total, @page_size))
    page = min(page, total_pages)
    offset = (page - 1) * @page_size

    paged_opts =
      base_opts
      |> Keyword.put(:limit, @page_size)
      |> Keyword.put(:offset, offset)

    jobs = Jobs.list_for_account(account.id, paged_opts)
    counts = Jobs.status_counts(account.id)

    socket
    |> assign(:jobs, jobs)
    |> assign(:status_counts, counts)
    |> assign(:page, page)
    |> assign(:total_jobs, total)
    |> assign(:total_pages, total_pages)
  end

  defp ceil_div(0, _divisor), do: 0
  defp ceil_div(numerator, divisor), do: div(numerator + divisor - 1, divisor)

  defp add_filter_opt(opts, filters, filter_id, opt_key) do
    case Enum.find(filters, &(&1.id == filter_id)) do
      %{value: value} when is_binary(value) and value != "" -> Keyword.put(opts, opt_key, value)
      _ -> opts
    end
  end

  defp add_option_opt(opts, filters, filter_id, opt_key) do
    case Enum.find(filters, &(&1.id == filter_id)) do
      %{value: value} when not is_nil(value) ->
        Keyword.put(opts, opt_key, to_string(value))

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
        options: [:queued, :claimed, :running, :completed],
        options_display_names: %{
          queued: dgettext("dashboard_runners", "Queued"),
          claimed: dgettext("dashboard_runners", "Claimed"),
          running: dgettext("dashboard_runners", "Running"),
          completed: dgettext("dashboard_runners", "Completed")
        },
        operator: :==,
        value: nil
      },
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
        id: "job",
        field: :job_name,
        display_name: dgettext("dashboard_runners", "Job"),
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
      },
      %Filter.Filter{
        id: "conclusion",
        field: :conclusion,
        display_name: dgettext("dashboard_runners", "Conclusion"),
        type: :option,
        options: [:success, :failure, :cancelled, :skipped],
        options_display_names: %{
          success: dgettext("dashboard_runners", "Success"),
          failure: dgettext("dashboard_runners", "Failure"),
          cancelled: dgettext("dashboard_runners", "Cancelled"),
          skipped: dgettext("dashboard_runners", "Skipped")
        },
        operator: :==,
        value: nil
      }
    ]
  end

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

  @doc """
  Picks the most informative duration for a row depending on its
  status:
    * queued — time spent waiting in the queue
    * claimed — time since claimed (waiting for the runner to mint)
    * running — time the runner has been executing
    * completed — total run duration (started → completed)
  """
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

  def format_duration(ms) when is_integer(ms) and ms > 0, do: DateFormatter.format_duration_from_milliseconds(ms)
  def format_duration(_), do: "–"

  def short_sha(""), do: "–"
  def short_sha(nil), do: "–"
  def short_sha(sha) when is_binary(sha), do: String.slice(sha, 0, 7)

  def trend_to_int(trend) when is_number(trend), do: round(trend)
  def trend_to_int(_), do: 0

  def count_chart_options(dates) do
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
  Returns the query string for a given page number, preserving the
  current filter state in `uri`.
  """
  def page_link(uri, page) do
    query =
      (uri.query || "")
      |> URI.decode_query()
      |> Map.put("page", Integer.to_string(page))
      |> URI.encode_query()

    "?" <> query
  end

  def minutes_chart_options(dates) do
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
