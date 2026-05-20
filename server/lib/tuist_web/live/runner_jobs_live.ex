defmodule TuistWeb.RunnerJobsLive do
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
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Utilities.Query

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
     |> assign(:repos, Jobs.distinct_repos_for_account(selected_account.id))
     |> assign(:analytics_selected_widget, "jobs")
     |> assign(:jobs_breakdown_type, "total")
     |> assign(:queue_time_percentile, "avg")
     |> assign(:job_duration_percentile, "avg")}
  end

  @impl true
  def handle_params(params, uri, socket) do
    filters = Filter.Operations.decode_filters_from_query(params, socket.assigns.available_filters)
    repository = params["repository"] || "any"
    page = parse_page(params["page"])

    %{preset: preset, period: {start_datetime, end_datetime} = period} =
      DatePicker.date_picker_params(params, "analytics")

    {:noreply,
     socket
     |> assign(:uri, URI.parse(uri))
     |> assign(:active_filters, filters)
     |> assign(:repository, repository)
     |> assign(:page, page)
     |> assign(:analytics_preset, preset)
     |> assign(:analytics_period, period)
     |> assign(:analytics_trend_label, trend_label(preset))
     |> assign_analytics(repository, start_datetime, end_datetime)
     |> assign_jobs(repository)}
  end

  defp assign_analytics(%{assigns: %{selected_account: account}} = socket, repository, start_dt, end_dt) do
    scope_opts =
      []
      |> maybe_repo(repository)
      |> Keyword.put(:start_datetime, start_dt)
      |> Keyword.put(:end_datetime, end_dt)

    assign_async(
      socket,
      [:jobs_breakdown, :cumulative_minutes, :queue_time, :jobs_duration, :live_status_counts],
      fn ->
        {:ok,
         %{
           jobs_breakdown: Analytics.jobs_breakdown(account.id, scope_opts),
           cumulative_minutes: Analytics.cumulative_minutes(account.id, scope_opts),
           queue_time: Analytics.queue_time(account.id, scope_opts),
           jobs_duration: Analytics.jobs_duration(account.id, scope_opts),
           live_status_counts: Jobs.status_counts(account.id)
         }}
      end
    )
  end

  defp maybe_repo(opts, "any"), do: opts
  defp maybe_repo(opts, nil), do: opts
  defp maybe_repo(opts, ""), do: opts
  defp maybe_repo(opts, repo) when is_binary(repo), do: Keyword.put(opts, :repo, repo)

  defp trend_label("last-24-hours"), do: dgettext("dashboard_runners", "since yesterday")
  defp trend_label("last-7-days"), do: dgettext("dashboard_runners", "since last week")
  defp trend_label("last-12-months"), do: dgettext("dashboard_runners", "since last year")
  defp trend_label("custom"), do: dgettext("dashboard_runners", "since last period")
  defp trend_label(_), do: dgettext("dashboard_runners", "since last month")

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

  def handle_event("select_queue_time_percentile", %{"type" => type}, socket) do
    {:noreply, assign(socket, :queue_time_percentile, type)}
  end

  def handle_event("select_job_duration_percentile", %{"type" => type}, socket) do
    {:noreply, assign(socket, :job_duration_percentile, type)}
  end

  def handle_event("select_jobs_breakdown", %{"type" => type}, socket) when type in ["total", "passed", "failed"] do
    {:noreply, assign(socket, :jobs_breakdown_type, type)}
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

  def handle_event(
        "analytics_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        %{assigns: %{selected_account: account, uri: uri}} = socket
      ) do
    query =
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

    {:noreply, push_patch(socket, to: ~p"/#{account.name}/runners/jobs?#{query}")}
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
     |> assign_jobs(socket.assigns.repository)}
  end

  defp assign_jobs(%{assigns: %{selected_account: account, active_filters: filters, page: page}} = socket, repository) do
    base_opts =
      []
      |> maybe_repo(repository)
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

  @doc """
  Patches the URL to swap the repository scope while preserving page
  and filter state — same shape used on the Workflows page so both
  pages stay in lockstep when a viewer hops between them with the
  same scope active.
  """
  def repository_patch(%URI{} = uri, repository) do
    "?" <> Query.put(uri.query, "repository", repository)
  end

  def repository_label("any"), do: dgettext("dashboard_runners", "Any")
  def repository_label(repo) when is_binary(repo), do: repo

  @doc """
  Builds the three-series array (Total / Passed / Failed) for the
  Job runs widget chart. Passed uses the tertiary chart slot — the
  same green Noora uses for the live Running widget legend so the
  two pass/healthy signals on this page read with one colour.
  """
  def jobs_breakdown_chart_series(stats) do
    [
      breakdown_series(stats, "Total", "secondary", :total_values),
      breakdown_series(stats, dgettext("dashboard_runners", "Passed"), "tertiary", :successful_values),
      breakdown_series(stats, dgettext("dashboard_runners", "Failed"), "destructive", :failed_values)
    ]
  end

  @doc """
  Title shown above the Job runs widget. The dropdown lets viewers
  switch between the absolute count of Total runs, Passed runs, or
  Failed runs — the title rotates with the selection so the widget
  reads as a single number with context.
  """
  def jobs_breakdown_title("passed"), do: dgettext("dashboard_runners", "Passed job runs")
  def jobs_breakdown_title("failed"), do: dgettext("dashboard_runners", "Failed job runs")
  def jobs_breakdown_title(_total), do: dgettext("dashboard_runners", "All job runs")

  def jobs_breakdown_value(stats, "passed"), do: Map.get(stats, :successful, 0)
  def jobs_breakdown_value(stats, "failed"), do: Map.get(stats, :failed, 0)
  def jobs_breakdown_value(stats, _total), do: Map.get(stats, :total, 0)

  def jobs_breakdown_trend(stats, "passed"), do: Map.get(stats, :trend_successful, 0.0)
  def jobs_breakdown_trend(stats, "failed"), do: Map.get(stats, :trend_failed, 0.0)
  def jobs_breakdown_trend(stats, _total), do: Map.get(stats, :trend_total, 0.0)

  # `:inverse` for Failed so the trend badge reads "good" when the
  # count drops and "bad" when it climbs; `:regular` for Passed so
  # rising passes are green; `:neutral` for the raw run count where
  # neither direction has an obvious health signal.
  def jobs_breakdown_trend_type("failed"), do: :inverse
  def jobs_breakdown_trend_type("passed"), do: :regular
  def jobs_breakdown_trend_type(_), do: :neutral

  # Legend dot colour rotates with the dropdown selection so the
  # widget header colour matches the value being shown.
  def jobs_breakdown_legend_color("passed"), do: "tertiary"
  def jobs_breakdown_legend_color("failed"), do: "destructive"
  def jobs_breakdown_legend_color(_total), do: "secondary"

  defp breakdown_series(stats, name, color_key, values_key) do
    %{
      color: "var:noora-chart-#{color_key}",
      data:
        stats.dates
        |> Enum.zip(Map.get(stats, values_key, []))
        |> Enum.map(&Tuple.to_list/1),
      name: name,
      type: "line",
      smooth: 0.1,
      symbol: "none"
    }
  end

  @doc """
  echarts `extra_options` for the three-series Jobs breakdown chart.
  Adds a legend below the plot mirroring the duration chart on the
  runners overview so all multi-series charts read the same way.
  """
  def breakdown_chart_options(dates) do
    %{
      legend: %{
        left: "left",
        top: "bottom",
        orient: "horizontal",
        textStyle: %{
          color: "var:noora-surface-label-secondary",
          fontFamily: "monospace",
          fontWeight: 400,
          fontSize: 10,
          lineHeight: 12
        },
        icon:
          "path://M0 6C0 4.89543 0.895431 4 2 4H6C7.10457 4 8 4.89543 8 6C8 7.10457 7.10457 8 6 8H2C0.895431 8 0 7.10457 0 6Z",
        itemWidth: 8,
        itemHeight: 4
      },
      grid: %{width: "97%", left: "0.4%", height: "60%", top: "10%"},
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
      tooltip: %{}
    }
  end

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
