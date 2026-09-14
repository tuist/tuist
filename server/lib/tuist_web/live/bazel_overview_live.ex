defmodule TuistWeb.BazelOverviewLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.BazelAnalyticsHelpers
  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.Skeleton

  alias Tuist.Bazel
  alias Tuist.ReapiCache
  alias Tuist.Tests
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Utilities.Query

  def assign_handle_params(socket, params, uri_path) do
    project = socket.assigns.selected_project
    uri = URI.new!("?" <> URI.encode_query(params))

    %{preset: analytics_preset, period: analytics_period} =
      DatePicker.date_picker_params(params, "analytics")

    %{preset: invocations_preset, period: invocations_period} =
      DatePicker.date_picker_params(params, "builds")

    invocations_environment = environment_param(params["builds-environment"])
    analytics_environment = environment_param(params["analytics-environment"])
    analytics_opts = environment_opts(period_opts(analytics_period), analytics_environment)
    invocations_opts = environment_opts(period_opts(invocations_period), invocations_environment)

    socket
    |> assign(
      uri: uri,
      uri_path: uri_path,
      analytics_preset: analytics_preset,
      analytics_period: analytics_period,
      analytics_granularity: time_series_granularity(analytics_period),
      analytics_trend_label: analytics_trend_label(analytics_preset),
      analytics_environment: analytics_environment,
      analytics_environment_label: environment_label(analytics_environment),
      invocations_preset: invocations_preset,
      invocations_period: invocations_period,
      invocations_granularity: time_series_granularity(invocations_period),
      invocations_environment: invocations_environment,
      invocations_environment_label: environment_label(invocations_environment)
    )
    |> assign_async(:reapi_cache_summary, fn ->
      {:ok,
       %{
         reapi_cache_summary: cache_summary_with_trends(project.id, analytics_period, analytics_environment)
       }}
    end)
    |> assign_async([:cache_hit_rate_analytics, :has_any_cache_observations], fn ->
      analytics = ReapiCache.hit_rate_analytics(project.id, analytics_opts)

      {:ok,
       %{
         cache_hit_rate_analytics: analytics,
         has_any_cache_observations:
           Enum.any?(analytics.lookup_values, &(&1 > 0)) || ReapiCache.observations_present?(project.id)
       }}
    end)
    |> assign_async(:build_analytics, fn ->
      {:ok,
       %{
         build_analytics: build_duration_with_trend(project.id, analytics_period, analytics_environment)
       }}
    end)
    |> assign_async(:test_analytics, fn ->
      {:ok, %{test_analytics: Tests.Analytics.test_run_average_duration_analytics(project.id, analytics_opts)}}
    end)
    |> assign_async([:recent_builds, :has_any_builds], fn ->
      build_opts = invocations_opts |> Keyword.put(:commands, ["build"]) |> Keyword.put(:limit, 30)
      builds = Bazel.recent_invocations(project.id, build_opts)

      {:ok,
       %{
         recent_builds: recent_invocation_chart_data(builds, project),
         has_any_builds: Enum.any?(builds) || Bazel.invocations_present?(project.id, ["build"])
       }}
    end)
    |> assign_async(:builds_duration_analytics, fn ->
      {:ok,
       %{
         builds_duration_analytics:
           Bazel.duration_analytics(project.id, Keyword.put(invocations_opts, :commands, ["build"]))
       }}
    end)
    |> assign_async([:recent_test_runs, :failed_test_runs_count, :passed_test_runs_count], fn ->
      recent_test_runs = Tests.latest_completed_test_runs(project.id)

      {:ok,
       %{
         recent_test_runs: recent_test_run_chart_data(recent_test_runs, project),
         failed_test_runs_count: Enum.count(recent_test_runs, &(&1.status == "failure")),
         passed_test_runs_count: Enum.count(recent_test_runs, &(&1.status == "success"))
       }}
    end)
  end

  def render(assigns) do
    ~H"""
    <div class="bazel-overview">
      <.card
        title={dgettext("dashboard_projects", "Analytics")}
        icon="chart_arcs"
        data-part="analytics-card"
      >
        <:actions>
          <.dropdown
            id="bazel-overview-analytics-environment-dropdown"
            label={@analytics_environment_label}
            secondary_text={dgettext("dashboard_projects", "Environment:")}
          >
            <.dropdown_item
              :for={{value, label} <- environment_options()}
              value={value}
              label={label}
              patch={"?#{Query.put(@uri.query, "analytics-environment", value)}"}
              data-selected={@analytics_environment == value}
            >
              <:right_icon :if={@analytics_environment == value}><.check /></:right_icon>
            </.dropdown_item>
          </.dropdown>
          <.date_picker
            id="bazel-analytics-date-range-picker"
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
                    detail: %{id: "bazel-analytics-date-range-picker"}
                  )
                }
              />
              <.button
                label={dgettext("dashboard_projects", "Apply")}
                phx-click={
                  JS.dispatch("phx:date-picker-apply",
                    detail: %{id: "bazel-analytics-date-range-picker"}
                  )
                }
              />
            </:actions>
          </.date_picker>
        </:actions>
        <div data-part="analytics-content">
          <div data-part="widgets">
            <.widget
              id="bazel-action-cache-hit-rate"
              loading={!@reapi_cache_summary.ok?}
              title={dgettext("dashboard_projects", "Cache hit rate")}
              description={
                dgettext(
                  "dashboard_projects",
                  "The share of action-cache lookups served from Tuist's remote cache."
                )
              }
              value={
                if @reapi_cache_summary.ok? and @reapi_cache_summary.result.hit_rate,
                  do: "#{@reapi_cache_summary.result.hit_rate}%"
              }
              trend_value={
                if @reapi_cache_summary.ok?, do: @reapi_cache_summary.result.hit_rate_trend
              }
              trend_label={@analytics_trend_label}
              empty={@reapi_cache_summary.ok? && is_nil(@reapi_cache_summary.result.hit_rate)}
            />
            <.widget
              id="bazel-average-build-time"
              loading={!@build_analytics.ok?}
              title={dgettext("dashboard_projects", "Average build time")}
              description={
                dgettext(
                  "dashboard_projects",
                  "The average duration of Bazel build invocations."
                )
              }
              value={
                if @build_analytics.ok?,
                  do:
                    DateFormatter.format_duration_from_milliseconds(
                      @build_analytics.result.total_average_duration
                    )
              }
              trend_value={if @build_analytics.ok?, do: @build_analytics.result.trend}
              trend_label={@analytics_trend_label}
              trend_type={:inverse}
              empty={@build_analytics.ok? && @build_analytics.result.total_average_duration == 0}
            />
            <.widget
              id="bazel-average-test-run-duration"
              loading={!@test_analytics.ok?}
              title={dgettext("dashboard_tests", "Avg. test run duration")}
              description={
                dgettext(
                  "dashboard_tests",
                  "The average test run duration."
                )
              }
              value={
                if @test_analytics.ok?,
                  do:
                    DateFormatter.format_duration_from_milliseconds(
                      @test_analytics.result.total_average_duration
                    )
              }
              trend_value={if @test_analytics.ok?, do: @test_analytics.result.trend}
              trend_label={@analytics_trend_label}
              trend_type={:inverse}
              empty={@test_analytics.ok? && @test_analytics.result.total_average_duration == 0}
            />
          </div>
          <.card_section :if={!@cache_hit_rate_analytics.ok?} data-part="cache-hit-rate-chart-section">
            <div data-part="cache-hit-rate-chart">
              <.skeleton_legend />
              <.skeleton_chart />
            </div>
          </.card_section>
          <.card_section
            :if={
              @cache_hit_rate_analytics.ok? &&
                Enum.any?(@cache_hit_rate_analytics.result.lookup_values, &(&1 > 0))
            }
            data-part="cache-hit-rate-chart-section"
          >
            <div data-part="cache-hit-rate-chart">
              <.legend
                title={dgettext("dashboard_projects", "Action cache hit rate")}
                value={
                  if @cache_hit_rate_analytics.result.hit_rate,
                    do: "#{@cache_hit_rate_analytics.result.hit_rate}%"
                }
                style="primary"
              />
              <.chart
                id="bazel-cache-hit-rate-chart"
                type="line"
                extra_options={
                  cache_hit_rate_chart_options(
                    @cache_hit_rate_analytics.result.dates,
                    @analytics_granularity
                  )
                }
                series={[
                  %{
                    color: "var:noora-chart-primary",
                    data:
                      Enum.zip(
                        @cache_hit_rate_analytics.result.dates,
                        @cache_hit_rate_analytics.result.values
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
            </div>
          </.card_section>
          <.empty_card_section
            :if={
              @cache_hit_rate_analytics.ok? &&
                Enum.all?(@cache_hit_rate_analytics.result.lookup_values, &(&1 == 0))
            }
            title={cache_observations_empty_state_title(@has_any_cache_observations.result)}
            get_started_href={cache_get_started_href(@has_any_cache_observations.result)}
          >
            <:image>
              <img
                src={~p"/images/empty_line_chart_light.png"}
                data-theme="light"
                loading="lazy"
                decoding="async"
              />
              <img
                src={~p"/images/empty_line_chart_dark.png"}
                data-theme="dark"
                loading="lazy"
                decoding="async"
              />
            </:image>
          </.empty_card_section>
        </div>
      </.card>

      <.card
        title={dgettext("dashboard_projects", "Builds")}
        icon="subtask"
        data-part="builds-card"
      >
        <:actions>
          <.dropdown
            id="bazel-overview-builds-environment-dropdown"
            label={@invocations_environment_label}
            secondary_text={dgettext("dashboard_projects", "Environment:")}
          >
            <.dropdown_item
              :for={{value, label} <- environment_options()}
              value={value}
              label={label}
              patch={"?#{Query.put(@uri.query, "builds-environment", value)}"}
              data-selected={@invocations_environment == value}
            >
              <:right_icon :if={@invocations_environment == value}><.check /></:right_icon>
            </.dropdown_item>
          </.dropdown>
          <.date_picker
            id="bazel-invocations-date-range-picker"
            name="builds-date-range"
            presets={date_picker_presets()}
            selected_preset={@invocations_preset}
            period={@invocations_period}
            on_period_change="builds_period_changed"
            max={Date.utc_today()}
          >
            <:actions>
              <.button
                label={dgettext("dashboard_projects", "Cancel")}
                variant="secondary"
                phx-click={
                  JS.dispatch("phx:date-picker-cancel",
                    detail: %{id: "bazel-invocations-date-range-picker"}
                  )
                }
              />
              <.button
                label={dgettext("dashboard_projects", "Apply")}
                phx-click={
                  JS.dispatch("phx:date-picker-apply",
                    detail: %{id: "bazel-invocations-date-range-picker"}
                  )
                }
              />
            </:actions>
          </.date_picker>
        </:actions>
        <div data-part="builds-card-sections">
          <.card_section :if={!@recent_builds.ok?}>
            <div data-part="build-runs-chart">
              <div data-part="legends"><.skeleton_legend /><.skeleton_legend /></div>
              <.skeleton_chart />
            </div>
          </.card_section>
          <.card_section :if={@recent_builds.ok? && Enum.any?(@recent_builds.result)}>
            <div data-part="build-runs-chart">
              <div data-part="legends">
                <.legend
                  title={dgettext("dashboard_projects", "Passed builds")}
                  value={Enum.count(@recent_builds.result, &(&1.status == "success"))}
                  style="primary"
                />
                <.legend
                  title={dgettext("dashboard_projects", "Failed builds")}
                  value={Enum.count(@recent_builds.result, &(&1.status == "failure"))}
                  style="destructive"
                />
              </div>
              <.chart
                data-lazy="true"
                id="bazel-recent-builds-chart"
                type="bar"
                extra_options={recent_invocations_chart_options(@recent_builds.result)}
                series={[%{data: @recent_builds.result, name: "Build", type: "bar"}]}
                y_axis_min={0}
                grid_lines
                bar_width={8}
                bar_radius={2}
              />
              <span data-part="label">{dgettext("dashboard_projects", "Last 30 runs")}</span>
            </div>
          </.card_section>
          <.empty_card_section
            :if={@recent_builds.ok? && Enum.empty?(@recent_builds.result)}
            title={builds_empty_state_title(@has_any_builds.result)}
            get_started_href={builds_get_started_href(@has_any_builds.result)}
          >
            <:image>
              <img
                src={~p"/images/empty_bar_chart_light.png"}
                data-theme="light"
                loading="lazy"
                decoding="async"
              />
              <img
                src={~p"/images/empty_bar_chart_dark.png"}
                data-theme="dark"
                loading="lazy"
                decoding="async"
              />
            </:image>
          </.empty_card_section>
          <.card_section
            :if={!@builds_duration_analytics.ok?}
            data-part="average-build-time-card-section"
          >
            <div data-part="average-build-time-chart">
              <div data-part="legends"><.skeleton_legend /></div>
              <.skeleton_chart />
            </div>
          </.card_section>
          <.card_section
            :if={
              @builds_duration_analytics.ok? &&
                @builds_duration_analytics.result.total_average_duration != 0
            }
            data-part="average-build-time-card-section"
          >
            <div data-part="average-build-time-chart">
              <.button
                data-part="view-more"
                label={dgettext("dashboard_projects", "View more")}
                size="small"
                variant="secondary"
                navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/builds"}
              />
              <div data-part="legends">
                <.legend
                  title={dgettext("dashboard_projects", "Average build time")}
                  value={
                    DateFormatter.format_duration_from_milliseconds(
                      @builds_duration_analytics.result.total_average_duration
                    )
                  }
                  style="secondary"
                />
              </div>
              <.chart
                data-lazy="true"
                id="bazel-overview-average-build-time-chart"
                type="line"
                extra_options={
                  %{
                    grid: %{width: "95%", left: "0.4%", height: "88%", top: "5%"},
                    xAxis:
                      chart_x_axis(
                        @builds_duration_analytics.result.dates,
                        @invocations_granularity
                      ),
                    yAxis: chart_y_axis("fn:formatSeconds"),
                    tooltip: chart_tooltip("fn:formatSeconds", @invocations_granularity),
                    legend: %{show: false}
                  }
                }
                series={[
                  %{
                    color: "var:noora-chart-secondary",
                    data:
                      Enum.zip(
                        @builds_duration_analytics.result.dates,
                        Enum.map(@builds_duration_analytics.result.values, &(&1 / 1000))
                      )
                      |> Enum.map(&Tuple.to_list/1),
                    name: dgettext("dashboard_projects", "Average build time"),
                    type: "line",
                    smooth: 0.1,
                    symbol: "none"
                  }
                ]}
                y_axis_min={0}
              />
            </div>
          </.card_section>
        </div>
      </.card>

      <.card title={dgettext("dashboard_projects", "Tests")} icon="subtask" data-part="tests-card">
        <:actions>
          <.button
            variant="secondary"
            label={dgettext("dashboard_projects", "View more")}
            size="medium"
            navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/tests/test-runs"}
            disabled={!@recent_test_runs.ok? || Enum.empty?(@recent_test_runs.result)}
          />
        </:actions>
        <.card_section :if={!@recent_test_runs.ok?}>
          <div data-part="test-runs-chart">
            <div data-part="legends"><.skeleton_legend /><.skeleton_legend /></div>
            <.skeleton_chart />
          </div>
        </.card_section>
        <.card_section :if={@recent_test_runs.ok? && Enum.any?(@recent_test_runs.result)}>
          <div data-part="test-runs-chart">
            <div data-part="legends">
              <.legend
                title={dgettext("dashboard_projects", "Passed runs")}
                value={@passed_test_runs_count.result}
                style="primary"
              />
              <.legend
                title={dgettext("dashboard_projects", "Failed runs")}
                value={@failed_test_runs_count.result}
                style="destructive"
              />
            </div>
            <.chart
              data-lazy="true"
              id="bazel-recent-test-runs-chart"
              type="bar"
              extra_options={recent_test_runs_chart_options(@recent_test_runs.result)}
              series={[%{data: @recent_test_runs.result, name: "Test Run", type: "bar"}]}
              y_axis_min={0}
              grid_lines
              bar_width={8}
              bar_radius={2}
            />
            <span data-part="label">{dgettext("dashboard_projects", "Last 40 runs")}</span>
          </div>
        </.card_section>
        <.empty_card_section
          :if={@recent_test_runs.ok? && Enum.empty?(@recent_test_runs.result)}
          title={dgettext("dashboard_projects", "Runs: no data yet")}
          get_started_href="https://tuist.dev/en/docs/guides/features/selective-testing"
        >
          <:image>
            <img
              src={~p"/images/empty_bar_chart_light.png"}
              data-theme="light"
              loading="lazy"
              decoding="async"
            />
            <img
              src={~p"/images/empty_bar_chart_dark.png"}
              data-theme="dark"
              loading="lazy"
              decoding="async"
            />
          </:image>
        </.empty_card_section>
      </.card>
    </div>
    """
  end

  defp recent_invocation_chart_data(invocations, project) do
    invocations
    |> Enum.reverse()
    |> Enum.map(fn invocation ->
      %{
        value: invocation.duration_ms,
        itemStyle: %{
          color:
            if(invocation.status == "success",
              do: "var:noora-chart-primary",
              else: "var:noora-chart-destructive"
            )
        },
        date: invocation.finished_at,
        url: ~p"/#{project.account.name}/#{project.name}/builds/invocations/#{invocation.invocation_id}",
        status: invocation.status
      }
    end)
  end

  defp recent_test_run_chart_data(test_runs, project) do
    Enum.map(test_runs, fn test_run ->
      color =
        case test_run.status do
          "success" -> "var:noora-chart-primary"
          "failure" -> "var:noora-chart-destructive"
          "skipped" -> "var:noora-chart-warning"
        end

      %{
        value: test_run.duration / 1000,
        itemStyle: %{color: color},
        date: test_run.ran_at,
        url: ~p"/#{project.account.name}/#{project.name}/tests/test-runs/#{test_run.id}"
      }
    end)
  end

  defp build_duration_with_trend(project_id, {start_datetime, end_datetime} = period, environment) do
    opts = period |> period_opts() |> environment_opts(environment) |> Keyword.put(:commands, ["build"])

    previous_opts =
      start_datetime
      |> previous_period(end_datetime)
      |> period_opts()
      |> environment_opts(environment)
      |> Keyword.put(:commands, ["build"])

    current = Bazel.duration_analytics(project_id, opts)
    previous = Bazel.duration_analytics(project_id, previous_opts)

    Map.put(
      current,
      :trend,
      trend(previous.total_average_duration, current.total_average_duration)
    )
  end

  defp cache_summary_with_trends(project_id, {start_datetime, end_datetime} = period, environment) do
    summary = ReapiCache.summary(project_id, environment_opts(period_opts(period), environment))

    previous_summary =
      ReapiCache.summary(
        project_id,
        environment_opts(period_opts(previous_period(start_datetime, end_datetime)), environment)
      )

    Map.put(summary, :hit_rate_trend, trend(previous_summary.hit_rate, summary.hit_rate))
  end

  defp cache_hit_rate_chart_options(dates, granularity) do
    %{
      grid: %{width: "93%", left: "0.4%", right: "7%", height: "88%", top: "5%"},
      xAxis: chart_x_axis(dates, granularity),
      yAxis: %{
        splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
        axisLabel: %{color: "var:noora-surface-label-secondary", formatter: "{value}%"}
      },
      tooltip: chart_tooltip("{value}%", granularity),
      legend: %{show: false}
    }
  end

  defp recent_invocations_chart_options(invocations) do
    %{
      grid: %{width: "100%", left: "0.4%", height: "88%", top: "5%"},
      tooltip: %{valueFormat: "fn:formatMilliseconds", dateFormat: "minute"},
      xAxis: %{axisLabel: %{show: false}, data: Enum.map(invocations, & &1.date)},
      yAxis: %{
        splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
        axisLabel: %{color: "var:noora-surface-label-secondary", formatter: "fn:formatMilliseconds"}
      },
      legend: %{show: false}
    }
  end

  defp recent_test_runs_chart_options(test_runs) do
    %{
      grid: %{width: "93%", left: "0.4%", right: "7%", height: "88%", top: "5%"},
      tooltip: %{valueFormat: "fn:formatSeconds", dateFormat: "minute"},
      xAxis: %{axisLabel: %{show: false}, data: Enum.map(test_runs, & &1.date)},
      yAxis: %{
        splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
        axisLabel: %{color: "var:noora-surface-label-secondary", formatter: "fn:formatSeconds"}
      },
      legend: %{show: false}
    }
  end

  defp cache_observations_empty_state_title(true),
    do: dgettext("dashboard_projects", "No cache observations in the selected period")

  defp cache_observations_empty_state_title(false), do: dgettext("dashboard_projects", "No cache observations yet")

  defp cache_get_started_href(true), do: nil
  defp cache_get_started_href(false), do: "https://tuist.dev/en/docs/guides/features/cache/bazel-cache"

  defp builds_empty_state_title(true), do: dgettext("dashboard_projects", "No builds in the selected period")

  defp builds_empty_state_title(false), do: dgettext("dashboard_projects", "No builds yet")

  defp builds_get_started_href(true), do: nil
  defp builds_get_started_href(false), do: "https://tuist.dev/en/docs/guides/features/cache/bazel-cache"

  defp environment_param(environment) when environment in ["ci", "local"], do: environment
  defp environment_param(_environment), do: "any"

  defp environment_label("ci"), do: dgettext("dashboard_projects", "CI")
  defp environment_label("local"), do: dgettext("dashboard_projects", "Local")
  defp environment_label(_environment), do: dgettext("dashboard_projects", "Any")

  defp environment_options do
    [
      {"any", dgettext("dashboard_projects", "Any")},
      {"ci", dgettext("dashboard_projects", "CI")},
      {"local", dgettext("dashboard_projects", "Local")}
    ]
  end

  defp environment_opts(opts, "ci"), do: Keyword.put(opts, :is_ci, true)
  defp environment_opts(opts, "local"), do: Keyword.put(opts, :is_ci, false)
  defp environment_opts(opts, _environment), do: opts
end
