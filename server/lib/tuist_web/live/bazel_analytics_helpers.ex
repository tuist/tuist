defmodule TuistWeb.BazelAnalyticsHelpers do
  @moduledoc false

  use Gettext, backend: TuistWeb.Gettext

  alias Tuist.Builds.Analytics
  alias Tuist.ClickHouseTimeSeries
  alias TuistWeb.Utilities.Query

  def previous_period(start_datetime, end_datetime) do
    duration = DateTime.diff(end_datetime, start_datetime, :second)
    {DateTime.add(start_datetime, -duration, :second), start_datetime}
  end

  def trend(previous_value, current_value) do
    Analytics.trend(
      previous_value: numeric(previous_value),
      current_value: numeric(current_value)
    )
  end

  def numeric(nil), do: 0
  def numeric(%Decimal{} = value), do: Decimal.to_float(value)
  def numeric(value) when is_number(value), do: value

  def analytics_trend_label("last-24-hours"), do: dgettext("dashboard_projects", "since yesterday")
  def analytics_trend_label("last-7-days"), do: dgettext("dashboard_projects", "since last week")
  def analytics_trend_label("last-12-months"), do: dgettext("dashboard_projects", "since last year")
  def analytics_trend_label("custom"), do: dgettext("dashboard_projects", "since last period")
  def analytics_trend_label(_), do: dgettext("dashboard_projects", "since last month")

  def date_picker_presets do
    [
      %{id: "last-24-hours", label: dgettext("dashboard_projects", "Last 24 hours"), period: {24, :hour}},
      %{id: "last-7-days", label: dgettext("dashboard_projects", "Last 7 days"), period: {7, :day}},
      %{id: "last-30-days", label: dgettext("dashboard_projects", "Last 30 days"), period: {30, :day}},
      %{id: "last-12-months", label: dgettext("dashboard_projects", "Last 12 months"), period: {12, :month}},
      %{id: "custom", label: dgettext("dashboard_projects", "Custom")}
    ]
  end

  def time_series_granularity({start_datetime, end_datetime}) do
    ClickHouseTimeSeries.granularity(start_datetime, end_datetime)
  end

  def chart_x_axis(dates, granularity \\ :day) do
    %{
      boundaryGap: false,
      type: "category",
      axisLabel: %{
        color: "var:noora-surface-label-secondary",
        formatter: if(granularity == :hour, do: "fn:toLocaleDateHour", else: "fn:toLocaleDate"),
        customValues: [List.first(dates), List.last(dates)],
        padding: [10, 0, 0, 0]
      }
    }
  end

  def chart_y_axis(formatter) do
    %{
      splitNumber: 4,
      splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
      axisLabel: %{color: "var:noora-surface-label-secondary", formatter: formatter}
    }
  end

  def chart_tooltip(value_format, :hour), do: %{valueFormat: value_format, dateFormat: "hour"}
  def chart_tooltip(value_format, _granularity), do: %{valueFormat: value_format}

  def target_patterns_label([]), do: dgettext("dashboard_projects", "No targets reported")

  def target_patterns_label([first_target | remaining_targets]) do
    case length(remaining_targets) do
      0 -> first_target
      count -> "#{first_target} +#{count}"
    end
  end

  def parse_page(value), do: Query.positive_integer(value)

  def period_opts({start_datetime, end_datetime}) do
    [start_datetime: start_datetime, end_datetime: end_datetime]
  end

  def period_opts(period, commands), do: Keyword.put(period_opts(period), :commands, commands)

  def sort_direction("asc"), do: :asc
  def sort_direction(_), do: :desc
end
