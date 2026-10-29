defmodule TuistWeb.CargoOverviewLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Helpers.MixAnalytics

  alias Tuist.Cargo
  alias Tuist.Tests
  alias Tuist.Tests.Analytics, as: TestsAnalytics
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Utilities.Query

  def assign_handle_params(socket, params, uri_path) do
    project = socket.assigns.selected_project
    {analytics, periods} = period(params, "analytics", socket.assigns[:cargo_overview_periods] || %{})
    {builds, periods} = period(params, "builds", periods)
    analytics_environment = environment(params["analytics-environment"])
    builds_environment = environment(params["builds-environment"])
    analytics_opts = period_opts(analytics.period) ++ environment_opts(analytics_environment)
    builds_opts = period_opts(builds.period) ++ environment_opts(builds_environment)

    socket
    |> assign(
      uri: URI.new!("?" <> URI.encode_query(params)),
      uri_path: uri_path,
      cargo_overview_periods: periods,
      analytics_preset: analytics.preset,
      analytics_period: analytics.period,
      analytics_environment: analytics_environment,
      analytics_environment_label: environment_label(analytics_environment),
      analytics_trend_label: analytics_trend_label(analytics.preset),
      builds_preset: builds.preset,
      builds_period: builds.period,
      builds_environment: builds_environment,
      builds_environment_label: environment_label(builds_environment)
    )
    |> load(:cargo_overview_analytics, {project.id, analytics_opts}, fn ->
      %{
        builds: Cargo.duration_analytics(project.id, analytics_opts),
        tests: TestsAnalytics.test_run_duration_analytics(project.id, analytics_opts)
      }
    end)
    |> load(:cargo_recent_tests, project.id, fn -> recent_tests(project) end)
    |> load(:cargo_overview_builds, {project.id, builds_opts}, fn ->
      %{
        recent: project.id |> Cargo.recent_builds(builds_opts) |> Enum.reverse() |> chart_runs(project, :build),
        analytics: Cargo.duration_analytics(project.id, builds_opts)
      }
    end)
  end

  defp load(socket, key, inputs, fetch) do
    cache = socket.assigns[:cargo_overview_inputs] || %{}
    result = socket.assigns[key]

    if cache[key] == inputs && result && !result.failed && (result.ok? || result.loading) do
      socket
    else
      socket
      |> assign(:cargo_overview_inputs, Map.put(cache, key, inputs))
      |> assign_async(key, fn -> {:ok, %{key => fetch.()}} end)
    end
  end

  defp period(params, prefix, cache) do
    inputs = Enum.map(["date-range", "start-date", "end-date"], &params["#{prefix}-#{&1}"])

    value =
      case cache[prefix] do
        {^inputs, value} -> value
        _ -> DatePicker.date_picker_params(params, prefix)
      end

    {value, Map.put(cache, prefix, {inputs, value})}
  end

  defp period_opts({start_datetime, end_datetime}), do: [start_datetime: start_datetime, end_datetime: end_datetime]
  defp environment(value) when value in ["ci", "local"], do: value
  defp environment(_), do: "any"

  defp recent_tests(project) do
    {runs, _meta} =
      Tests.list_test_runs(%{
        last: 40,
        filters: [%{field: :project_id, op: :==, value: project.id}, %{field: :build_system, op: :==, value: "cargo"}],
        order_by: [:ran_at],
        order_directions: [:asc]
      })

    chart_runs(runs, project, :test)
  end

  defp chart_runs(runs, project, kind) do
    %{
      passed: Enum.count(runs, &(&1.status == "success")),
      failed: Enum.count(runs, &(&1.status == "failure")),
      points:
        Enum.map(runs, fn run ->
          color =
            case run.status do
              "success" -> "var:noora-chart-primary"
              "failure" -> "var:noora-chart-destructive"
              _ -> "var:noora-chart-warning"
            end

          %{
            value: if(kind == :build, do: run.duration_ms, else: run.duration),
            itemStyle: %{color: color},
            date: if(kind == :build, do: run.inserted_at, else: run.ran_at),
            url:
              if(kind == :build,
                do: ~p"/#{project.account.name}/#{project.name}/builds/cargo-builds/#{run.id}",
                else: ~p"/#{project.account.name}/#{project.name}/tests/test-runs/#{run.id}"
              )
          }
        end)
    }
  end

  attr(:prefix, :string, required: true)
  attr(:environment, :string, required: true)
  attr(:label, :string, required: true)
  attr(:preset, :string, required: true)
  attr(:period, :any, required: true)
  attr(:uri, :any, required: true)

  defp overview_filters(assigns) do
    ~H"""
    <.dropdown
      id={"cargo-#{@prefix}-environment-dropdown"}
      label={@label}
      secondary_text={dgettext("dashboard_projects", "Environment:")}
    >
      <.dropdown_item
        :for={value <- ["any", "ci", "local"]}
        value={value}
        label={environment_label(value)}
        patch={"?#{Query.put(@uri.query, "#{@prefix}-environment", value)}"}
        data-selected={@environment == value}
      >
        <:right_icon :if={@environment == value}><.check /></:right_icon>
      </.dropdown_item>
    </.dropdown>
    <.date_picker
      id={"cargo-#{@prefix}-date-range-picker"}
      name={"#{@prefix}-date-range"}
      presets={date_presets()}
      selected_preset={@preset}
      period={@period}
      on_period_change={"#{@prefix}_period_changed"}
      max={Date.utc_today()}
    >
      <:actions>
        <.button
          label={dgettext("dashboard_projects", "Cancel")}
          variant="secondary"
          phx-click={
            JS.dispatch("phx:date-picker-cancel", detail: %{id: "cargo-#{@prefix}-date-range-picker"})
          }
        />
        <.button
          label={dgettext("dashboard_projects", "Apply")}
          phx-click={
            JS.dispatch("phx:date-picker-apply", detail: %{id: "cargo-#{@prefix}-date-range-picker"})
          }
        />
      </:actions>
    </.date_picker>
    """
  end

  defp date_presets do
    [
      %{id: "last-24-hours", label: dgettext("dashboard_projects", "Last 24 hours"), period: {24, :hour}},
      %{id: "last-7-days", label: dgettext("dashboard_projects", "Last 7 days"), period: {7, :day}},
      %{id: "last-30-days", label: dgettext("dashboard_projects", "Last 30 days"), period: {30, :day}},
      %{id: "last-12-months", label: dgettext("dashboard_projects", "Last 12 months"), period: {12, :month}},
      %{id: "custom", label: dgettext("dashboard_projects", "Custom")}
    ]
  end

  attr(:id, :string, required: true)
  attr(:runs, :map, required: true)
  attr(:kind, :atom, required: true)

  defp recent_chart(assigns) do
    ~H"""
    <div data-part={if @kind == :build, do: "build-runs-chart", else: "test-runs-chart"}>
      <div data-part="legends">
        <.legend
          title={
            if @kind == :build,
              do: dgettext("dashboard_projects", "Passed builds"),
              else: dgettext("dashboard_projects", "Passed runs")
          }
          value={@runs.passed}
          style="primary"
        />
        <.legend
          title={
            if @kind == :build,
              do: dgettext("dashboard_projects", "Failed builds"),
              else: dgettext("dashboard_projects", "Failed runs")
          }
          value={@runs.failed}
          style="destructive"
        />
      </div>
      <.chart
        id={@id}
        type="bar"
        extra_options={
          %{
            grid: %{width: "93%", left: "0.4%", right: "7%", height: "88%", top: "5%"},
            tooltip: %{valueFormat: "fn:formatMilliseconds", dateFormat: "minute"},
            xAxis: %{axisLabel: %{show: false}, data: Enum.map(@runs.points, & &1.date)},
            yAxis: %{
              splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
              axisLabel: %{
                color: "var:noora-surface-label-secondary",
                formatter: "fn:formatMilliseconds"
              }
            },
            legend: %{show: false}
          }
        }
        series={[
          %{data: @runs.points, name: if(@kind == :build, do: "Build", else: "Test Run"), type: "bar"}
        ]}
        y_axis_min={0}
        grid_lines
        bar_width={8}
        bar_radius={2}
      />
      <span data-part="label">{if @kind == :build,
        do: dgettext("dashboard_projects", "Last 30 runs"),
        else: dgettext("dashboard_projects", "Last 40 runs")}</span>
    </div>
    """
  end

  attr(:id, :string, required: true)
  attr(:analytics, :map, required: true)
  attr(:tests, :map, default: nil)
  attr(:preset, :string, required: true)

  defp duration_chart(assigns) do
    ~H"""
    <.chart
      id={@id}
      type="line"
      extra_options={
        %{
          grid: %{width: "93%", left: "0.4%", right: "7%", height: "88%", top: "5%"},
          xAxis: %{
            boundaryGap: false,
            type: "category",
            axisLabel: %{
              color: "var:noora-surface-label-secondary",
              formatter: "fn:toLocaleDate",
              customValues: [List.first(@analytics.dates), List.last(@analytics.dates)],
              padding: [10, 0, 0, 0]
            }
          },
          yAxis: %{
            splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
            axisLabel: %{color: "var:noora-surface-label-secondary", formatter: "fn:formatSeconds"}
          },
          tooltip:
            if(@preset == "last-24-hours",
              do: %{valueFormat: "fn:formatSeconds", dateFormat: "hour"},
              else: %{valueFormat: "fn:formatSeconds"}
            ),
          legend: %{show: false}
        }
      }
      series={duration_series(@analytics, @tests)}
      y_axis_min={0}
    />
    """
  end

  defp duration_series(builds, tests) do
    series = [
      %{
        data: duration_points(builds),
        name: dgettext("dashboard_projects", "Average build time"),
        itemStyle: %{color: if(tests, do: "var:noora-chart-primary", else: "var:noora-chart-secondary")},
        lineStyle: %{color: if(tests, do: "var:noora-chart-primary", else: "var:noora-chart-secondary")},
        type: "line",
        smooth: 0.1,
        symbol: "none"
      }
    ]

    if tests,
      do:
        series ++
          [
            %{
              data: duration_points(tests),
              name: dgettext("dashboard_tests", "Avg. test run duration"),
              itemStyle: %{color: "var:noora-chart-secondary"},
              lineStyle: %{color: "var:noora-chart-secondary"},
              type: "line",
              smooth: 0.1,
              symbol: "none"
            }
          ],
      else: series
  end

  attr(:title, :string, required: true)
  attr(:chart, :string, default: "line")

  defp empty_chart(assigns) do
    ~H"""
    <.empty_card_section
      title={@title}
      get_started_href="https://tuist.dev/en/docs/guides/get-started/rust-project"
    >
      <:image>
        <img
          src={"/images/empty_#{@chart}_chart_light.png"}
          data-theme="light"
          loading="lazy"
          decoding="async"
        />
        <img
          src={"/images/empty_#{@chart}_chart_dark.png"}
          data-theme="dark"
          loading="lazy"
          decoding="async"
        />
      </:image>
    </.empty_card_section>
    """
  end
end
