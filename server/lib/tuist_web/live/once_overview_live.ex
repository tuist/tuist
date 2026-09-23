defmodule TuistWeb.OnceOverviewLive do
  @moduledoc """
  Overview for Once projects, rendered by `TuistWeb.OverviewLive` the way
  `TuistWeb.BazelOverviewLive` and `TuistWeb.XcodeOverviewLive` are.

  Same three cards as the other build systems (analytics, builds, tests)
  reading from `Tuist.OnceEvents.Analytics` and
  `Tuist.OnceEvents.CacheAnalytics`, so a Once project gets the same
  landing page shape as every other project rather than a redirect.
  """
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.BazelAnalyticsHelpers
  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.Skeleton

  alias Tuist.OnceEvents.Analytics
  alias Tuist.OnceEvents.CacheAnalytics
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Helpers.DatePicker

  @build_commands ["build"]
  @test_commands ["test"]

  def assign_handle_params(socket, params, uri_path) do
    project = socket.assigns.selected_project
    uri = URI.new!("?" <> URI.encode_query(params))

    %{preset: analytics_preset, period: analytics_period} =
      DatePicker.date_picker_params(params, "analytics")

    socket
    |> assign(
      uri: uri,
      uri_path: uri_path,
      analytics_preset: analytics_preset,
      analytics_period: analytics_period,
      analytics_granularity: time_series_granularity(analytics_period),
      analytics_trend_label: analytics_trend_label(analytics_preset)
    )
    |> assign_async(:cache_summary, fn ->
      {:ok, %{cache_summary: cache_summary_with_trend(project.id, analytics_period)}}
    end)
    |> assign_async([:cache_hit_rate_analytics, :has_any_cache_observations], fn ->
      analytics = CacheAnalytics.analytics(project.id, period_opts(analytics_period))

      {:ok,
       %{
         cache_hit_rate_analytics: analytics,
         has_any_cache_observations: Enum.any?(analytics.lookup_values, &(&1 > 0))
       }}
    end)
    |> assign_async([:build_summary, :recent_builds], fn ->
      {:ok,
       %{
         build_summary: summary_with_trends(project.id, analytics_period, @build_commands),
         recent_builds: recent_runs(project, analytics_period, @build_commands)
       }}
    end)
    |> assign_async([:test_summary, :recent_test_runs], fn ->
      {:ok,
       %{
         test_summary: summary_with_trends(project.id, analytics_period, @test_commands),
         recent_test_runs: recent_runs(project, analytics_period, @test_commands)
       }}
    end)
  end

  def render(assigns) do
    ~H"""
    <div id="once-overview" class="bazel-overview">
      <.card
        title={dgettext("dashboard_projects", "Analytics")}
        icon="chart_arcs"
        data-part="analytics-card"
      >
        <:actions>
          <.date_picker
            id="once-overview-date-range-picker"
            name="analytics-date-range"
            presets={date_picker_presets()}
            selected_preset={@analytics_preset}
            period={@analytics_period}
            on_period_change="analytics_period_changed"
            max={Date.utc_today()}
          >
            <:actions>
              <.button
                label={dgettext("dashboard_projects", "Cancel")}
                variant="secondary"
                phx-click={
                  JS.dispatch("phx:date-picker-cancel",
                    detail: %{id: "once-overview-date-range-picker"}
                  )
                }
              />
              <.button
                label={dgettext("dashboard_projects", "Apply")}
                phx-click={
                  JS.dispatch("phx:date-picker-apply",
                    detail: %{id: "once-overview-date-range-picker"}
                  )
                }
              />
            </:actions>
          </.date_picker>
        </:actions>
        <div data-part="analytics-content">
          <div data-part="widgets">
            <.widget
              id="once-cache-hit-rate"
              loading={!@cache_summary.ok?}
              title={dgettext("dashboard_projects", "Cache hit rate")}
              description={
                dgettext(
                  "dashboard_projects",
                  "The share of action-cache lookups served from Tuist's remote cache."
                )
              }
              value={
                if @cache_summary.ok? and @cache_summary.result.hit_rate,
                  do: "#{@cache_summary.result.hit_rate}%"
              }
              trend_value={if @cache_summary.ok?, do: @cache_summary.result.hit_rate_trend, else: 0}
              trend_label={@analytics_trend_label}
              empty={@cache_summary.ok? && is_nil(@cache_summary.result.hit_rate)}
            />
            <.widget
              id="once-average-build-time"
              loading={!@build_summary.ok?}
              title={dgettext("dashboard_projects", "Average build time")}
              description={dgettext("dashboard_projects", "The average duration of Once build runs.")}
              value={
                if @build_summary.ok?,
                  do:
                    DateFormatter.format_duration_from_milliseconds(
                      @build_summary.result.average_duration_ms
                    )
              }
              trend_value={if @build_summary.ok?, do: @build_summary.result.duration_trend, else: 0}
              trend_label={@analytics_trend_label}
              trend_type={:inverse}
              empty={@build_summary.ok? && @build_summary.result.average_duration_ms == 0}
            />
            <.widget
              id="once-average-test-run-time"
              loading={!@test_summary.ok?}
              title={dgettext("dashboard_tests", "Avg. test run duration")}
              description={dgettext("dashboard_projects", "The average duration of Once test runs.")}
              value={
                if @test_summary.ok?,
                  do:
                    DateFormatter.format_duration_from_milliseconds(
                      @test_summary.result.average_duration_ms
                    )
              }
              trend_value={if @test_summary.ok?, do: @test_summary.result.duration_trend, else: 0}
              trend_label={@analytics_trend_label}
              trend_type={:inverse}
              empty={@test_summary.ok? && @test_summary.result.average_duration_ms == 0}
            />
          </div>

          <.card_section :if={!@cache_hit_rate_analytics.ok?} data-part="analytics-chart-section">
            <.skeleton_chart />
          </.card_section>
          <.card_section
            :if={
              @cache_hit_rate_analytics.ok? && @has_any_cache_observations.ok? &&
                @has_any_cache_observations.result
            }
            data-part="analytics-chart-section"
          >
            <.legend
              title={dgettext("dashboard_projects", "Action cache hit rate")}
              value={
                if @cache_summary.ok? and @cache_summary.result.hit_rate,
                  do: "#{@cache_summary.result.hit_rate}%"
              }
              style="primary"
            />
            <.chart
              id="once-overview-cache-hit-rate-chart"
              type="line"
              extra_options={
                %{
                  grid: %{width: "97%", left: "0.4%", height: "80%", top: "5%"},
                  xAxis: chart_x_axis(@cache_hit_rate_analytics.result.dates, @analytics_granularity),
                  yAxis: percentage_y_axis(),
                  tooltip: chart_tooltip("{value}%", @analytics_granularity)
                }
              }
              series={[
                %{
                  color: "var:noora-chart-primary",
                  data:
                    Enum.zip(
                      @cache_hit_rate_analytics.result.dates,
                      @cache_hit_rate_analytics.result.hit_rate_values
                    )
                    |> Enum.map(&Tuple.to_list/1),
                  name: dgettext("dashboard_projects", "Action cache hit rate"),
                  type: "line",
                  smooth: 0.1,
                  symbol: "none"
                }
              ]}
              y_axis_min={0}
              y_axis_max={100}
            />
          </.card_section>
          <.empty_card_section
            :if={
              @cache_hit_rate_analytics.ok? && @has_any_cache_observations.ok? &&
                !@has_any_cache_observations.result
            }
            title={dgettext("dashboard_projects", "No cache activity yet")}
          >
            <:image>
              <img src={~p"/images/empty_chart_light.png"} data-theme="light" loading="lazy" />
              <img src={~p"/images/empty_chart_dark.png"} data-theme="dark" loading="lazy" />
            </:image>
          </.empty_card_section>
        </div>
      </.card>

      <.runs_card
        id="once-overview-builds"
        title={dgettext("dashboard_projects", "Builds")}
        summary={@build_summary}
        runs={@recent_builds}
        passed_label={dgettext("dashboard_projects", "Passed builds")}
        failed_label={dgettext("dashboard_projects", "Failed builds")}
        empty_title={dgettext("dashboard_projects", "No builds yet")}
        navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/once/builds"}
      />

      <.runs_card
        id="once-overview-tests"
        title={dgettext("dashboard_projects", "Tests")}
        summary={@test_summary}
        runs={@recent_test_runs}
        passed_label={dgettext("dashboard_projects", "Passed runs")}
        failed_label={dgettext("dashboard_projects", "Failed runs")}
        empty_title={dgettext("dashboard_projects", "No test runs yet")}
        navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/once/tests"}
      />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :summary, :map, required: true
  attr :runs, :map, required: true
  attr :passed_label, :string, required: true
  attr :failed_label, :string, required: true
  attr :empty_title, :string, required: true
  attr :navigate, :string, required: true

  defp runs_card(assigns) do
    ~H"""
    <.card title={@title} icon="subtask" data-part="builds-card">
      <:actions>
        <.button
          variant="secondary"
          label={dgettext("dashboard_projects", "View more")}
          size="medium"
          navigate={@navigate}
          disabled={@runs.ok? && Enum.empty?(@runs.result)}
        />
      </:actions>
      <.card_section :if={!@runs.ok?}>
        <div data-part="build-runs-chart">
          <div data-part="legends"><.skeleton_legend /><.skeleton_legend /></div>
          <.skeleton_chart />
        </div>
      </.card_section>
      <.card_section :if={@runs.ok? && Enum.any?(@runs.result)}>
        <div data-part="build-runs-chart">
          <div data-part="legends">
            <.legend
              title={@passed_label}
              value={Enum.count(@runs.result, &(&1.status == "success"))}
              style="primary"
            />
            <.legend
              title={@failed_label}
              value={Enum.count(@runs.result, &(&1.status == "failure"))}
              style="destructive"
            />
          </div>
          <.chart
            data-lazy="true"
            id={"#{@id}-chart"}
            type="bar"
            extra_options={recent_runs_chart_options(@runs.result)}
            series={[%{data: @runs.result, name: @title, type: "bar"}]}
            y_axis_min={0}
            grid_lines
            bar_width={8}
            bar_radius={2}
          />
          <span data-part="label">{dgettext("dashboard_projects", "Last 30 runs")}</span>
        </div>
      </.card_section>
      <.empty_card_section :if={@runs.ok? && Enum.empty?(@runs.result)} title={@empty_title}>
        <:image>
          <img src={~p"/images/empty_chart_light.png"} data-theme="light" loading="lazy" />
          <img src={~p"/images/empty_chart_dark.png"} data-theme="dark" loading="lazy" />
        </:image>
      </.empty_card_section>
    </.card>
    """
  end

  # Same point shape the Bazel overview charts: value + per-status colour,
  # newest last so the bars read left to right.
  defp recent_runs(project, period, commands) do
    {runs, _meta} =
      Analytics.list_invocations(
        project.id,
        %{page: 1, page_size: 30, order_by: [:finished_at], order_directions: [:desc]},
        opts(period, commands)
      )

    runs
    |> Enum.reverse()
    |> Enum.map(fn run ->
      %{
        value: run.duration_ms || 0,
        itemStyle: %{
          color:
            if(run.status == "success",
              do: "var:noora-chart-primary",
              else: "var:noora-chart-destructive"
            )
        },
        date: run.finished_at,
        status: run.status
      }
    end)
  end

  defp recent_runs_chart_options(runs) do
    %{
      grid: %{width: "100%", left: "0.4%", height: "88%", top: "5%"},
      tooltip: %{valueFormat: "fn:formatMilliseconds", dateFormat: "minute"},
      xAxis: %{axisLabel: %{show: false}, data: Enum.map(runs, & &1.date)},
      yAxis: %{
        splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
        axisLabel: %{color: "var:noora-surface-label-secondary", formatter: "fn:formatMilliseconds"}
      },
      legend: %{show: false}
    }
  end

  defp summary_with_trends(project_id, {start_dt, end_dt} = period, commands) do
    current = Analytics.summary(project_id, opts(period, commands))
    {prev_start, prev_end} = previous_period(start_dt, end_dt)
    previous = Analytics.summary(project_id, opts({prev_start, prev_end}, commands))

    Map.put(
      current,
      :duration_trend,
      trend(numeric(previous.average_duration_ms), numeric(current.average_duration_ms))
    )
  end

  # The per-run hit rate, which is what the Once cache page charts, rather
  # than `CacheAnalytics.summary/2`, which reports transfer and latency.
  defp cache_summary_with_trend(project_id, {start_dt, end_dt} = period) do
    current = CacheAnalytics.invocation_hit_rate_metrics(project_id, period_opts(period))
    {prev_start, prev_end} = previous_period(start_dt, end_dt)
    previous = CacheAnalytics.invocation_hit_rate_metrics(project_id, period_opts({prev_start, prev_end}))

    %{
      hit_rate: if(current.sample_count > 0, do: current.avg),
      hit_rate_trend: trend(numeric(previous.avg), numeric(current.avg))
    }
  end

  defp opts(period, commands), do: period |> period_opts() |> Keyword.put(:commands, commands)

  # There is no `fn:formatPercentage` in the chart hook, so the label was
  # rendering as that literal string. Percentages use an ECharts template,
  # the way the Xcode overview does it.
  defp percentage_y_axis do
    %{
      splitNumber: 4,
      splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
      axisLabel: %{color: "var:noora-surface-label-secondary", formatter: "{value}%"}
    }
  end
end
