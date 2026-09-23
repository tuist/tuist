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
    |> assign_async(:build_summary, fn ->
      {:ok, %{build_summary: summary_with_trends(project.id, analytics_period, @build_commands)}}
    end)
    |> assign_async(:test_summary, fn ->
      {:ok, %{test_summary: summary_with_trends(project.id, analytics_period, @test_commands)}}
    end)
  end

  def render(assigns) do
    ~H"""
    <div id="once-overview" class="bazel-overview">
      <div data-part="filters">
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
                JS.dispatch("phx:date-picker-apply", detail: %{id: "once-overview-date-range-picker"})
              }
            />
          </:actions>
        </.date_picker>
      </div>

      <.card
        title={dgettext("dashboard_projects", "Analytics")}
        icon="chart_arcs"
        data-part="analytics-card"
      >
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
              style="primary"
            />
            <.chart
              id="once-overview-cache-hit-rate-chart"
              type="line"
              extra_options={
                %{
                  grid: %{width: "97%", left: "0.4%", height: "80%", top: "5%"},
                  xAxis: chart_x_axis(@cache_hit_rate_analytics.result.dates, @analytics_granularity),
                  yAxis: chart_y_axis("fn:formatPercentage"),
                  tooltip: chart_tooltip("fn:formatPercentage", @analytics_granularity)
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

      <.summary_card
        id="once-overview-builds"
        title={dgettext("dashboard_projects", "Builds")}
        icon="subtask"
        summary={@build_summary}
        passed_label={dgettext("dashboard_projects", "Passed builds")}
        failed_label={dgettext("dashboard_projects", "Failed builds")}
        empty_title={dgettext("dashboard_projects", "No builds yet")}
        navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/once/builds"}
        trend_label={@analytics_trend_label}
      />

      <.summary_card
        id="once-overview-tests"
        title={dgettext("dashboard_projects", "Tests")}
        icon="subtask"
        summary={@test_summary}
        passed_label={dgettext("dashboard_projects", "Passed runs")}
        failed_label={dgettext("dashboard_projects", "Failed runs")}
        empty_title={dgettext("dashboard_projects", "No test runs yet")}
        navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/once/tests"}
        trend_label={@analytics_trend_label}
      />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :icon, :string, required: true
  attr :summary, :map, required: true
  attr :passed_label, :string, required: true
  attr :failed_label, :string, required: true
  attr :empty_title, :string, required: true
  attr :navigate, :string, required: true
  attr :trend_label, :string, required: true

  defp summary_card(assigns) do
    ~H"""
    <.card title={@title} icon={@icon} data-part="builds-card">
      <:actions>
        <.button
          variant="secondary"
          label={dgettext("dashboard_projects", "View more")}
          size="medium"
          navigate={@navigate}
          disabled={@summary.ok? && @summary.result.total == 0}
        />
      </:actions>
      <.card_section :if={!@summary.ok?}>
        <.skeleton_chart />
      </.card_section>
      <.card_section :if={@summary.ok? && @summary.result.total > 0} data-part="widgets">
        <.widget
          id={"#{@id}-passed"}
          loading={false}
          title={@passed_label}
          value={to_string(@summary.result.successful)}
          trend_value={0}
          trend_label={@trend_label}
        />
        <.widget
          id={"#{@id}-failed"}
          loading={false}
          title={@failed_label}
          value={to_string(@summary.result.failed)}
          trend_value={0}
          trend_label={@trend_label}
        />
      </.card_section>
      <.empty_card_section :if={@summary.ok? && @summary.result.total == 0} title={@empty_title}>
        <:image>
          <img src={~p"/images/empty_chart_light.png"} data-theme="light" loading="lazy" />
          <img src={~p"/images/empty_chart_dark.png"} data-theme="dark" loading="lazy" />
        </:image>
      </.empty_card_section>
    </.card>
    """
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
end
