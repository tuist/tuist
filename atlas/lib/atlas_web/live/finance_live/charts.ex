defmodule AtlasWeb.FinanceLive.Charts do
  @moduledoc false

  use Gettext, backend: AtlasWeb.Gettext

  @default_preset "last-12-months"
  @million Decimal.new("1000000")
  @thousand Decimal.new("1000")
  @zero Decimal.new("0")
  @net_inflow_color "var:noora-chart-tertiary"
  @net_outflow_color "var:noora-chart-destructive"

  def runway_date_range_prefix, do: "runway"

  def runway_default_preset, do: @default_preset

  def runway_date_range_presets do
    [
      %{id: "last-30-days", label: gettext("Last 30 days"), period: {30, :day}},
      %{id: "last-3-months", label: gettext("Last 3 months"), period: {3, :month}},
      %{id: "last-6-months", label: gettext("Last 6 months"), period: {6, :month}},
      %{id: "last-12-months", label: gettext("Last 12 months"), period: {12, :month}},
      %{id: "custom", label: gettext("Custom")}
    ]
  end

  def runway_date_picker_params(params) do
    preset = present_string(params["#{runway_date_range_prefix()}-date-range"]) || @default_preset

    if preset == "custom" do
      custom_period(params, preset)
    else
      %{preset: preset, period: period_for_preset(preset)}
    end
  end

  def history_days_for_period({%DateTime{} = start_datetime, %DateTime{} = end_datetime}) do
    Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))
  end

  def chart_dates(dates), do: Enum.map(dates, &Date.to_iso8601/1)

  def monthly_series_dates([], _period), do: []

  def monthly_series_dates(_monthly_spend, period) do
    period
    |> monthly_period_dates()
    |> chart_dates()
  end

  def scaled_monthly_series([], _period, _scale), do: []

  def scaled_monthly_series(monthly_spend, period, {scale, _suffix}) do
    values_by_date = Map.new(monthly_spend, fn %{date: date, amount_value: value} -> {date, value} end)

    period
    |> monthly_period_dates()
    |> Enum.map(fn date -> [Date.to_iso8601(date), scaled_float(Map.get(values_by_date, date, @zero), scale)] end)
  end

  def monthly_period_dates({%DateTime{} = start_datetime, %DateTime{} = end_datetime}) do
    start_date =
      start_datetime
      |> DateTime.to_date()
      |> Date.beginning_of_month()

    end_date =
      end_datetime
      |> DateTime.to_date()
      |> Date.beginning_of_month()

    do_monthly_period_dates(start_date, end_date, [])
  end

  def chart_series(dates, values) do
    dates
    |> Enum.zip(values)
    |> Enum.map(fn {date, value} -> [Date.to_iso8601(date), decimal_to_float(value)] end)
  end

  def scaled_chart_series(dates, values, {scale, _suffix}) do
    dates
    |> Enum.zip(values)
    |> Enum.map(fn {date, value} -> [Date.to_iso8601(date), scaled_float(value, scale)] end)
  end

  @doc """
  Like `scaled_chart_series/3`, but returns bar data points colored by sign:
  net inflow (>= 0) green, net outflow (< 0) red. Each point carries its own
  `itemStyle`, which the Noora chart hook resolves per bar.
  """
  def signed_bar_series(dates, values, {scale, _suffix}) do
    dates
    |> Enum.zip(values)
    |> Enum.map(fn {date, value} ->
      %{
        value: [Date.to_iso8601(date), scaled_float(value, scale)],
        itemStyle: %{color: net_flow_color(value)}
      }
    end)
  end

  defp net_flow_color(%Decimal{} = value) do
    if Decimal.compare(value, @zero) == :lt, do: @net_outflow_color, else: @net_inflow_color
  end

  defp net_flow_color(_value), do: @net_inflow_color

  @doc """
  Picks an order-of-magnitude scale (1, 1K, or 1M) based on the largest
  absolute value in a list of Decimal values.
  """
  def humanize_scale(values) do
    max_abs =
      Enum.reduce(values, Decimal.new("0"), fn value, acc ->
        case value do
          nil -> acc
          %Decimal{} = decimal -> Decimal.max(acc, Decimal.abs(decimal))
        end
      end)

    cond do
      Decimal.compare(max_abs, @million) != :lt -> {1_000_000, "M"}
      Decimal.compare(max_abs, @thousand) != :lt -> {1_000, "K"}
      true -> {1, ""}
    end
  end

  def currency_format({_scale, ""}, currency), do: "{value} #{currency}"
  def currency_format({_scale, suffix}, currency), do: "{value}#{suffix} #{currency}"

  def chart_options(dates, y_format, opts \\ [])
  def chart_options([], _y_format, _opts), do: %{}

  def chart_options(dates, y_format, opts) do
    # Line series should touch the chart edges (boundaryGap false); bar series
    # need padded category bands so bars don't collide with the axes.
    boundary_gap = Keyword.get(opts, :boundary_gap, false)
    x_axis_values = x_axis_custom_values(dates, opts)

    # Chart text (axes, tooltip) inherits Noora's default `textStyle` font
    # ("Geist Mono"), which is self-hosted via assets/css/fonts.css.
    %{
      grid: %{width: "95%", left: "0.4%", right: "3%", height: "80%", top: "8%"},
      legend: %{show: false},
      xAxis: %{
        boundaryGap: boundary_gap,
        type: "category",
        axisLabel: %{
          color: "var:noora-surface-label-secondary",
          formatter: "fn:toLocaleDate",
          customValues: x_axis_values,
          padding: [10, 0, 0, 0]
        }
      },
      yAxis: %{
        splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
        axisLabel: %{
          color: "var:noora-surface-label-secondary",
          formatter: y_format
        }
      },
      tooltip: %{valueFormat: y_format}
    }
  end

  defp x_axis_custom_values(dates, opts) do
    cond do
      Keyword.has_key?(opts, :x_axis_values) ->
        Keyword.fetch!(opts, :x_axis_values)

      label_count = Keyword.get(opts, :x_axis_label_count) ->
        spread_axis_values(dates, label_count)

      true ->
        [List.first(dates), List.last(dates)]
    end
  end

  defp spread_axis_values(dates, label_count) when label_count >= length(dates), do: dates

  defp spread_axis_values(dates, label_count) when label_count <= 2 do
    [List.first(dates), List.last(dates)]
  end

  defp spread_axis_values(dates, label_count) do
    last_index = length(dates) - 1

    0..(label_count - 1)
    |> Enum.map(fn index -> round(index * last_index / (label_count - 1)) end)
    |> Enum.uniq()
    |> Enum.map(&Enum.at(dates, &1))
  end

  defp custom_period(params, preset) do
    case {
      parse_date(params["#{runway_date_range_prefix()}-start-date"], ~T[00:00:00]),
      parse_date(params["#{runway_date_range_prefix()}-end-date"], ~T[23:59:59])
    } do
      {%DateTime{} = start_datetime, %DateTime{} = end_datetime} ->
        %{preset: preset, period: {start_datetime, end_datetime}}

      _other ->
        %{preset: @default_preset, period: period_for_preset(@default_preset)}
    end
  end

  defp period_for_preset(preset) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    start_datetime =
      case preset do
        "last-30-days" -> DateTime.add(now, -30, :day)
        "last-3-months" -> DateTime.add(now, -90, :day)
        "last-6-months" -> DateTime.add(now, -180, :day)
        "last-12-months" -> DateTime.add(now, -365, :day)
        _other -> DateTime.add(now, -365, :day)
      end

    {start_datetime, now}
  end

  defp parse_date(nil, _fallback_time), do: nil

  defp parse_date(value, fallback_time) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} ->
        DateTime.new!(date, fallback_time, "Etc/UTC")

      {:error, _reason} ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
          {:error, _reason} -> nil
        end
    end
  end

  defp present_string(nil), do: nil

  defp present_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp do_monthly_period_dates(date, end_date, acc) do
    if Date.after?(date, end_date) do
      Enum.reverse(acc)
    else
      date
      |> Date.end_of_month()
      |> Date.add(1)
      |> do_monthly_period_dates(end_date, [date | acc])
    end
  end

  defp decimal_to_float(nil), do: nil
  defp decimal_to_float(%Decimal{} = value), do: value |> Decimal.round(2) |> Decimal.to_float()

  defp scaled_float(nil, _scale), do: nil

  defp scaled_float(%Decimal{} = value, 1), do: decimal_to_float(value)

  defp scaled_float(%Decimal{} = value, scale) do
    value
    |> Decimal.div(Decimal.new(scale))
    |> Decimal.round(2)
    |> Decimal.to_float()
  end
end
