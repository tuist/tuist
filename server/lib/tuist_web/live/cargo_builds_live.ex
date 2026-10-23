defmodule TuistWeb.CargoBuildsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.ChartTypeToggle
  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.ScatterChart
  import TuistWeb.Helpers.MixAnalytics
  import TuistWeb.PercentileDropdownWidget
  import TuistWeb.Runs.RanByBadge

  alias Phoenix.LiveView.AsyncResult
  alias Tuist.Cargo
  alias Tuist.Repo
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Utilities.Query

  def assign_mount(socket), do: assign(socket, :cargo_build_scatter, AsyncResult.ok(:line))

  def assign_handle_params(socket, params) do
    project_id = socket.assigns.selected_project.id
    params = Map.delete(params, "analytics-command")
    period_inputs = Enum.map(["date-range", "start-date", "end-date"], &params["analytics-#{&1}"])

    selection =
      if socket.assigns[:cargo_build_period_inputs] == period_inputs,
        do: socket.assigns.cargo_build_period,
        else: DatePicker.date_picker_params(params, "analytics")

    selection = %{selection | period: bounded_period(selection.period)}
    {start_datetime, end_datetime} = selection.period
    environment = choice(params["analytics-environment"], ["any", "ci", "local"], "any")
    opts = [start_datetime: start_datetime, end_datetime: end_datetime] ++ environment_opts(environment)

    opts =
      Enum.reduce([:rust_version], opts, fn key, opts ->
        case params["analytics-#{key |> to_string() |> String.replace("_", "-")}"] do
          value when is_binary(value) and value != "any" and byte_size(value) <= 4096 -> Keyword.put(opts, key, value)
          _ -> opts
        end
      end)

    category = category_field(params["configuration-insights-type"])
    group_by = category_field(params["build-duration-scatter-group-by"])
    chart_type = choice(params["build-duration-chart-type"], ["line", "scatter"], "line")

    socket =
      socket
      |> assign(
        uri: URI.new!("?" <> URI.encode_query(params)),
        current_params: params,
        cargo_build_period_inputs: period_inputs,
        cargo_build_period: selection,
        analytics_period: selection.period,
        analytics_preset: selection.preset,
        analytics_trend_label: analytics_trend_label(selection.preset),
        analytics_environment: environment,
        analytics_selected_widget:
          choice(
            params["analytics-selected-widget"],
            ["build-duration", "total-builds", "failed-builds", "build-success-rate"],
            "build-duration"
          ),
        selected_build_duration_type: choice(params["build-duration-type"], ["avg", "p50", "p90", "p99"], "avg"),
        configuration_insights_type: category_name(category),
        build_duration_scatter_group_by: category_name(group_by),
        build_duration_chart_type: chart_type
      )
      |> load(:cargo_build_options, project_id, fn -> Cargo.build_options(project_id) end)
      |> load(:cargo_build_analytics, {project_id, opts}, fn -> Cargo.build_analytics(project_id, opts) end)
      |> load(:cargo_build_configuration, {project_id, opts, category}, fn ->
        Cargo.configuration_insights(project_id, category, opts)
      end)
      |> load(:cargo_recent_builds, {project_id, opts}, fn ->
        project_id |> Cargo.recent_builds(Keyword.put(opts, :limit, 40)) |> Repo.preload(:ran_by_account)
      end)

    if chart_type == "scatter" do
      load(socket, :cargo_build_scatter, {project_id, opts, group_by}, fn ->
        data = Cargo.build_scatter_data(project_id, group_by, opts)

        {:scatter,
         %{data | series: Enum.map(data.series, fn series -> %{series | name: category_label(series.name)} end)}}
      end)
    else
      socket
    end
  end

  def handle_event("select_widget", %{"widget" => widget}, socket),
    do:
      patch(
        socket,
        "analytics-selected-widget",
        choice(widget, ["build-duration", "total-builds", "failed-builds", "build-success-rate"], "build-duration")
      )

  def handle_event("select_build_duration_chart_type", %{"type" => type}, socket),
    do: patch(socket, "build-duration-chart-type", choice(type, ["line", "scatter"], "line"))

  def handle_event("select_build_duration_type", %{"type" => type}, socket),
    do: patch(socket, "build-duration-type", choice(type, ["avg", "p50", "p90", "p99"], "avg"))

  defp patch(socket, key, value) do
    params = socket.assigns.uri.query |> URI.decode_query() |> Map.put(key, value)

    {:noreply,
     push_patch(socket,
       to: ~p"/#{socket.assigns.selected_account.name}/#{socket.assigns.selected_project.name}/builds?#{params}",
       replace: true
     )}
  end

  defp load(socket, key, inputs, fetch) do
    cache = socket.assigns[:cargo_build_inputs] || %{}
    result = socket.assigns[key]

    if cache[key] == inputs && result && !result.failed && (result.ok? || result.loading) do
      socket
    else
      socket
      |> assign(:cargo_build_inputs, Map.put(cache, key, inputs))
      |> assign_async(key, fn -> {:ok, %{key => fetch.()}} end)
    end
  end

  defp bounded_period({start_datetime, end_datetime}) do
    end_datetime = Enum.min([end_datetime, DateTime.utc_now()], DateTime)
    earliest = DateTime.add(end_datetime, -365, :day)
    start_datetime = Enum.max([start_datetime, earliest], DateTime)

    if DateTime.before?(start_datetime, end_datetime),
      do: {start_datetime, end_datetime},
      else: {DateTime.add(end_datetime, -30, :day), end_datetime}
  end

  defp choice(value, options, fallback), do: if(value in options, do: value, else: fallback)
  defp category_field("environment"), do: :is_ci
  defp category_field(_), do: :rust_version
  defp category_name(:is_ci), do: "environment"
  defp category_name(:rust_version), do: "rust-version"
  defp category_label(true), do: "CI"
  defp category_label(false), do: dgettext("dashboard_builds", "Local")
  defp category_label(""), do: dgettext("dashboard_builds", "Unknown")
  defp category_label(value), do: value

  defp duration_metric(result, "p50"), do: %{value: result.p50.total_percentile_duration, trend: result.p50.trend}
  defp duration_metric(result, "p90"), do: %{value: result.p90.total_percentile_duration, trend: result.p90.trend}
  defp duration_metric(result, "p99"), do: %{value: result.p99.total_percentile_duration, trend: result.p99.trend}
  defp duration_metric(result, _), do: %{value: result.duration.total_average_duration, trend: result.duration.trend}

  defp duration_series(result) do
    Enum.map(
      [{:duration, "Average", "secondary"}, {:p99, "p99", "p99"}, {:p90, "p90", "p90"}, {:p50, "p50", "p50"}],
      fn {key, name, color} ->
        %{
          name: name,
          color: "var:noora-chart-#{color}",
          data: duration_points(Map.fetch!(result, key)),
          type: "line",
          smooth: 0.1,
          symbol: "none"
        }
      end
    )
  end

  defp count_chart(result, "total-builds"),
    do: %{
      name: dgettext("dashboard_builds", "Build runs"),
      data: Enum.zip(result.total.dates, result.total.values),
      formatter: "{value}",
      color: "primary"
    }

  defp count_chart(result, "failed-builds"),
    do: %{
      name: dgettext("dashboard_builds", "Failed builds"),
      data: Enum.zip(result.failed.dates, result.failed.values),
      formatter: "{value}",
      color: "destructive"
    }

  defp count_chart(result, _),
    do: %{
      name: dgettext("dashboard_builds", "Build success rate"),
      data: Enum.zip(result.success.dates, Enum.map(result.success.values, &(&1 * 100))),
      formatter: "{value}%",
      color: "primary"
    }

  defp chart_options(dates, formatter, legend \\ false) do
    %{
      legend: %{show: legend, left: "left", top: "bottom", icon: "roundRect", itemWidth: 8, itemHeight: 4},
      grid: %{width: "97%", left: "0.4%", height: if(legend, do: "60%", else: "88%"), top: "10%", containLabel: true},
      xAxis: %{
        boundaryGap: false,
        type: "category",
        axisLabel: %{
          formatter: "fn:toLocaleDate",
          customValues: [List.first(dates), List.last(dates)],
          padding: [10, 0, 0, 0],
          color: "var:noora-surface-label-secondary"
        }
      },
      yAxis: %{
        axisLabel: %{formatter: formatter, color: "var:noora-surface-label-secondary"},
        splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}}
      },
      tooltip: %{valueFormat: formatter}
    }
  end

  defp recent_points(builds, account, project) do
    builds
    |> Enum.reverse()
    |> Enum.map(fn build ->
      %{
        value: build.duration_ms,
        date: build.inserted_at,
        itemStyle: %{
          color: if(build.status == "success", do: "var:noora-chart-primary", else: "var:noora-chart-destructive")
        },
        url: ~p"/#{account.name}/#{project.name}/builds/cargo-builds/#{build.id}"
      }
    end)
  end

  attr(:id, :string, required: true)
  attr(:label, :string, required: true)
  attr(:key, :string, required: true)
  attr(:choices, :list, required: true)
  attr(:uri, :any, required: true)
  attr(:value, :string, default: "any")

  defp build_filter(assigns) do
    ~H"""
    <.dropdown id={@id} label={category_label(@value)} secondary_text={@label}>
      <.dropdown_item
        :for={value <- ["any" | @choices]}
        value={value}
        label={
          if value == "any", do: dgettext("dashboard_builds", "Any"), else: category_label(value)
        }
        patch={"?#{Query.put(@uri.query, @key, value)}"}
        data-selected={@value == value}
      >
        <:right_icon :if={@value == value}><.check /></:right_icon>
      </.dropdown_item>
    </.dropdown>
    """
  end
end
