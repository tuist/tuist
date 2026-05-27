defmodule TuistWeb.RunnersLive do
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

  @table_limit 5
  @chart_limit 30

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
       "#{dgettext("dashboard_runners", "Runners")} · #{selected_account.name} · Tuist"
     )
     |> assign(:repositories, Jobs.distinct_repositories_for_account(selected_account.id))}
  end

  @impl true
  def handle_params(params, uri, %{assigns: %{selected_account: account}} = socket) do
    %{preset: preset, period: {start_datetime, end_datetime} = period} =
      DatePicker.date_picker_params(params, "analytics")

    selected_widget = params["widget"] || "total_jobs"
    job_duration_percentile = params["job-duration"] || "avg"
    workflow_duration_percentile = params["workflow-duration"] || "avg"
    repository = params["repository"] || "any"
    platform = platform_param(params["platform"])

    opts =
      [start_datetime: start_datetime, end_datetime: end_datetime]
      |> maybe_repository(repository)
      |> maybe_platform(platform)

    {:noreply,
     socket
     |> assign(:uri, URI.parse(uri))
     |> assign(:repository, repository)
     |> assign(:platform, platform)
     |> assign(:analytics_preset, preset)
     |> assign(:analytics_period, period)
     |> assign(:analytics_trend_label, trend_label(preset))
     |> assign(:analytics_selected_widget, selected_widget)
     |> assign(:job_duration_percentile, job_duration_percentile)
     |> assign(:workflow_duration_percentile, workflow_duration_percentile)
     |> assign_recent_jobs(account.id, repository, platform)
     |> assign_recent_workflow_runs(account.id, repository, platform)
     |> assign_async(
       [:jobs_count, :jobs_duration, :workflows_duration],
       fn ->
         {:ok,
          %{
            jobs_count: Analytics.jobs_count(account.id, opts),
            jobs_duration: Analytics.jobs_duration(account.id, opts),
            workflows_duration: Analytics.workflows_duration(account.id, opts)
          }}
       end
     )}
  end

  defp maybe_repository(opts, "any"), do: opts
  defp maybe_repository(opts, nil), do: opts
  defp maybe_repository(opts, ""), do: opts
  defp maybe_repository(opts, repository) when is_binary(repository), do: Keyword.put(opts, :repository, repository)

  defp maybe_platform(opts, "any"), do: opts
  defp maybe_platform(opts, nil), do: opts
  defp maybe_platform(opts, ""), do: opts
  defp maybe_platform(opts, platform) when platform in ["macos", "linux"], do: Keyword.put(opts, :platform, platform)
  defp maybe_platform(opts, _), do: opts

  # Bounded set — every fleet's `fleet_name` starts with either
  # `macos-` or `linux-`, so the dropdown only ever needs those two
  # plus the unset `any`.
  defp platform_param(value) when value in ["macos", "linux"], do: value
  defp platform_param(_), do: "any"

  @impl true
  def handle_event("select_widget", %{"widget" => widget}, socket) do
    {:noreply, push_patch_with_param(socket, "widget", widget)}
  end

  def handle_event("select_job_duration_percentile", %{"type" => type}, socket) do
    {:noreply, push_patch_with_param(socket, "job-duration", type)}
  end

  def handle_event("select_workflow_duration_percentile", %{"type" => type}, socket) do
    {:noreply, push_patch_with_param(socket, "workflow-duration", type)}
  end

  def handle_event(
        "analytics_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        socket
      ) do
    query_params =
      if preset == "custom" do
        socket.assigns.uri.query
        |> Query.put("analytics-date-range", "custom")
        |> Query.put("analytics-start-date", start_date)
        |> Query.put("analytics-end-date", end_date)
      else
        Query.put(socket.assigns.uri.query, "analytics-date-range", preset)
      end

    {:noreply, push_patch(socket, to: "/#{socket.assigns.selected_account.name}/runners?#{query_params}")}
  end

  defp push_patch_with_param(socket, key, value) do
    query = Query.put(socket.assigns.uri.query || "", key, value)
    push_patch(socket, to: "/#{socket.assigns.selected_account.name}/runners?#{query}")
  end

  defp assign_recent_jobs(socket, account_id, repository, platform) do
    # The Recent jobs card mirrors the Recent Test Runs card on the
    # Tests page — it's a chronicle of finished work, not a live
    # status board. Filter to completed runs only so the bars carry
    # a real duration and the success/failure legends count
    # something other than zero. The chart spans up to
    # `@chart_limit` so the bar trail conveys a trend, while the
    # table below shows only the freshest `@table_limit` rows.
    opts =
      [status: "completed", limit: @chart_limit]
      |> maybe_repository(repository)
      |> maybe_platform(platform)

    recent_jobs_chart = Jobs.list_for_account(account_id, opts)
    recent_jobs_table = Enum.take(recent_jobs_chart, @table_limit)

    socket
    |> assign(:recent_jobs, recent_jobs_table)
    |> assign(:recent_jobs_chart_data, recent_jobs_chart_data(recent_jobs_chart, socket.assigns.selected_account.name))
    |> assign(:recent_jobs_successful_count, Enum.count(recent_jobs_chart, &(&1.conclusion == "success")))
    |> assign(:recent_jobs_failed_count, Enum.count(recent_jobs_chart, &(&1.conclusion == "failure")))
  end

  defp assign_recent_workflow_runs(socket, account_id, repository, platform) do
    opts =
      [limit: @chart_limit]
      |> maybe_repository(repository)
      |> maybe_platform(platform)

    recent_workflow_runs_chart = Jobs.list_recent_workflow_runs_for_account(account_id, opts)
    recent_workflow_runs_table = Enum.take(recent_workflow_runs_chart, @table_limit)

    socket
    |> assign(:recent_workflow_runs, recent_workflow_runs_table)
    |> assign(
      :recent_workflow_runs_chart_data,
      recent_workflow_runs_chart_data(recent_workflow_runs_chart, socket.assigns.selected_account.name)
    )
    |> assign(
      :recent_workflow_runs_successful_count,
      Enum.count(recent_workflow_runs_chart, &(&1.conclusion == "success"))
    )
    |> assign(
      :recent_workflow_runs_failed_count,
      Enum.count(recent_workflow_runs_chart, &(&1.conclusion == "failure"))
    )
  end

  # Workflow-run bars mirror the recent-jobs chart: one bar per run,
  # height in seconds, colour from the run-level conclusion. We URL
  # the bar to the workflow detail page when the slug fully resolves
  # so clicking drills down naturally; partial-info rows just don't
  # carry a navigate target.
  defp recent_workflow_runs_chart_data(recent_workflow_runs, account_name) do
    recent_workflow_runs
    |> Enum.reverse()
    |> Enum.map(fn run ->
      %{
        value: run_duration_seconds(run),
        itemStyle: %{color: workflow_run_chart_color(run.conclusion)},
        date: run.updated_at,
        url: workflow_run_detail_url(account_name, run)
      }
    end)
  end

  defp run_duration_seconds(%{duration_ms: ms}) when is_integer(ms) and ms > 0, do: div(ms, 1000)
  defp run_duration_seconds(_), do: 0

  defp workflow_run_chart_color("success"), do: "var:noora-chart-primary"
  defp workflow_run_chart_color("failure"), do: "var:noora-chart-destructive"
  defp workflow_run_chart_color("cancelled"), do: "var:noora-chart-warning"
  defp workflow_run_chart_color(_), do: "var:noora-chart-secondary"

  defp workflow_run_detail_url(account_name, %{repository: repository, workflow_name: workflow_name})
       when is_binary(repository) and is_binary(workflow_name) and repository != "" and workflow_name != "" do
    case String.split(repository, "/", parts: 2) do
      [owner, name] when owner != "" and name != "" ->
        "/#{account_name}/runners/workflows/#{URI.encode(owner, &URI.char_unreserved?/1)}/#{URI.encode(name, &URI.char_unreserved?/1)}/#{URI.encode(workflow_name, &URI.char_unreserved?/1)}"

      _ ->
        nil
    end
  end

  defp workflow_run_detail_url(_account_name, _row), do: nil

  # Bars represent each recent job. Y is the duration in seconds (or
  # zero for not-yet-started states), the bar colour mirrors the row's
  # status badge so the chart reads at the same glance as the table.
  defp recent_jobs_chart_data(recent_jobs, account_name) do
    recent_jobs
    |> Enum.reverse()
    |> Enum.map(fn job ->
      seconds = duration_seconds(job)

      %{
        value: seconds,
        itemStyle: %{color: chart_color_for(job)},
        date: job.updated_at,
        url: TuistWeb.RunnerJobLive.path(account_name, job)
      }
    end)
  end

  defp duration_seconds(%{status: "completed", started_at: started, completed_at: completed}) do
    cond do
      is_nil(started) -> 0
      is_nil(completed) -> 0
      true -> div(DateTime.diff(completed, started, :millisecond), 1000)
    end
  end

  defp duration_seconds(%{status: "running", started_at: started}) do
    if is_nil(started),
      do: 0,
      else: div(DateTime.diff(DateTime.utc_now(), started, :millisecond), 1000)
  end

  defp duration_seconds(_), do: 0

  defp chart_color_for(%{status: "completed", conclusion: "success"}), do: "var:noora-chart-primary"
  defp chart_color_for(%{status: "completed", conclusion: "failure"}), do: "var:noora-chart-destructive"
  defp chart_color_for(%{status: "completed", conclusion: "cancelled"}), do: "var:noora-chart-warning"
  defp chart_color_for(%{status: "completed"}), do: "var:noora-chart-secondary"
  defp chart_color_for(%{status: "running"}), do: "var:noora-chart-tertiary"
  defp chart_color_for(%{status: "claimed"}), do: "var:noora-chart-tertiary"
  defp chart_color_for(%{status: "queued"}), do: "var:noora-chart-warning"
  defp chart_color_for(_), do: "var:noora-chart-primary"

  @doc """
  Patches the URL to swap the repository scope. Same shape used on
  the Workflows and Jobs list pages so a viewer hopping between the
  three keeps the same scope active.
  """
  def repository_patch(%URI{} = uri, repository) do
    "?" <> Query.put(uri.query, "repository", repository)
  end

  def repository_label("any"), do: dgettext("dashboard_runners", "Any")
  def repository_label(repository) when is_binary(repository), do: repository

  @doc """
  Same pattern as `repository_patch/2`: toggle the URL's `platform`
  param while leaving every other piece of state intact, so a
  viewer hopping between Repository, Platform and the date picker
  composes filters instead of resetting them.
  """
  def platform_patch(%URI{} = uri, platform) do
    "?" <> Query.put(uri.query, "platform", platform)
  end

  def platform_label("macos"), do: dgettext("dashboard_runners", "macOS")
  def platform_label("linux"), do: dgettext("dashboard_runners", "Linux")
  def platform_label(_any), do: dgettext("dashboard_runners", "Any")

  @platforms ["macos", "linux"]
  def platforms, do: @platforms

  @doc """
  Conclusion label for the Recent workflow_runs table — the rollup
  in `list_recent_workflow_runs_for_account/2` may return `success`,
  `failure`, `cancelled`, or `skipped`. Anything outside that set
  collapses to "Unknown" so a stray value renders cleanly.
  """
  def conclusion_label("success"), do: dgettext("dashboard_runners", "Success")
  def conclusion_label("failure"), do: dgettext("dashboard_runners", "Failure")
  def conclusion_label("cancelled"), do: dgettext("dashboard_runners", "Cancelled")
  def conclusion_label("skipped"), do: dgettext("dashboard_runners", "Skipped")
  def conclusion_label(_), do: dgettext("dashboard_runners", "Unknown")

  def conclusion_status_badge("success"), do: "success"
  def conclusion_status_badge("failure"), do: "error"
  def conclusion_status_badge(_), do: "warning"

  def workflow_run_path(account_name, %{repository: repository, workflow_name: workflow_name})
      when is_binary(repository) and is_binary(workflow_name) and repository != "" and workflow_name != "" do
    case String.split(repository, "/", parts: 2) do
      [owner, name] when owner != "" and name != "" ->
        "/#{account_name}/runners/workflows/#{URI.encode(owner, &URI.char_unreserved?/1)}/#{URI.encode(name, &URI.char_unreserved?/1)}/#{URI.encode(workflow_name, &URI.char_unreserved?/1)}"

      _ ->
        nil
    end
  end

  def workflow_run_path(_account_name, _row), do: nil

  def short_sha(""), do: "–"
  def short_sha(nil), do: "–"
  def short_sha(sha) when is_binary(sha), do: String.slice(sha, 0, 7)

  defp trend_label("last-24-hours"), do: dgettext("dashboard_runners", "since yesterday")
  defp trend_label("last-7-days"), do: dgettext("dashboard_runners", "since last week")
  defp trend_label("last-12-months"), do: dgettext("dashboard_runners", "since last year")
  defp trend_label("custom"), do: dgettext("dashboard_runners", "since last period")
  defp trend_label(_), do: dgettext("dashboard_runners", "since last month")

  # Render helpers ------------------------------------------------------------

  def fmt_duration_ms(nil), do: "–"
  def fmt_duration_ms(0), do: "0s"

  def fmt_duration_ms(ms) when is_integer(ms) and ms > 0, do: DateFormatter.format_duration_from_milliseconds(ms)

  def fmt_duration_ms(_), do: "–"

  @doc """
  Runtime in milliseconds for a recent job row. Mirrors the bar
  chart's `duration_seconds/1` (running / completed branches) so the
  table column and the chart bar represent the same elapsed time.
  """
  def job_duration_ms(%{status: "completed", started_at: started, completed_at: completed}) do
    cond do
      is_nil(started) -> 0
      is_nil(completed) -> 0
      true -> DateTime.diff(completed, started, :millisecond)
    end
  end

  def job_duration_ms(%{status: "running", started_at: started}) do
    if is_nil(started),
      do: 0,
      else: DateTime.diff(DateTime.utc_now(), started, :millisecond)
  end

  def job_duration_ms(_), do: 0

  def percentile_value(stats, "p50"), do: Map.get(stats, :p50)
  def percentile_value(stats, "p90"), do: Map.get(stats, :p90)
  def percentile_value(stats, "p99"), do: Map.get(stats, :p99)
  def percentile_value(stats, _), do: Map.get(stats, :avg)

  def percentile_trend(stats, "p50"), do: Map.get(stats, :trend_p50)
  def percentile_trend(stats, "p90"), do: Map.get(stats, :trend_p90)
  def percentile_trend(stats, "p99"), do: Map.get(stats, :trend_p99)
  def percentile_trend(stats, _), do: Map.get(stats, :trend_avg)

  def percentile_series(stats, "p50"), do: Map.get(stats, :p50_values, [])
  def percentile_series(stats, "p90"), do: Map.get(stats, :p90_values, [])
  def percentile_series(stats, "p99"), do: Map.get(stats, :p99_values, [])
  def percentile_series(stats, _), do: Map.get(stats, :avg_values, [])

  def legend_color_for_percentile("p50"), do: "p50"
  def legend_color_for_percentile("p90"), do: "p90"
  def legend_color_for_percentile("p99"), do: "p99"
  def legend_color_for_percentile(_), do: "secondary"

  def trend_to_int(trend) when is_number(trend), do: round(trend)
  def trend_to_int(_), do: 0

  @doc """
  echarts `extra_options` for a simple count chart — single series,
  no legend, date-formatted x-axis, plain numeric y-axis.
  """
  def count_chart_options(dates, analytics_preset) do
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
      tooltip:
        if analytics_preset == "last-24-hours" do
          %{dateFormat: "hour"}
        else
          %{}
        end
    }
  end

  @doc """
  echarts `extra_options` for a duration chart. Overlays the four
  percentile series (avg + p50/p90/p99) so the chart reads the same
  way as the Tests page: legend at the bottom, ms-formatted y-axis,
  ms-formatted tooltip values.
  """
  def duration_chart_options(dates, analytics_preset, bucket \\ :day) do
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
      grid: %{width: "97%", left: "0.4%", height: "78%", top: "8%"},
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
        axisLabel: %{
          color: "var:noora-surface-label-secondary",
          formatter: "fn:formatMilliseconds"
        }
      },
      tooltip:
        if analytics_preset == "last-24-hours" or bucket == :hour do
          %{valueFormat: "fn:formatMilliseconds", dateFormat: "hour"}
        else
          %{valueFormat: "fn:formatMilliseconds"}
        end
    }
  end

  @doc """
  Builds the four-percentile time-series array (avg + p50/p90/p99)
  for a duration chart, in the order the Tests page renders them.
  """
  def duration_chart_series(stats) do
    [
      duration_series(stats, "Average", "secondary", :avg_values),
      duration_series(stats, "p99", "p99", :p99_values),
      duration_series(stats, "p90", "p90", :p90_values),
      duration_series(stats, "p50", "p50", :p50_values)
    ]
  end

  defp duration_series(stats, name, color_key, values_key) do
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
