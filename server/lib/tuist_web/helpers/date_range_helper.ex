defmodule TuistWeb.Helpers.DateRangeHelper do
  @moduledoc """
  Helper functions for parsing date range parameters from LiveView params.

  This module consolidates the common pattern of parsing date range presets
  and custom date ranges used across multiple LiveView modules.

  Param names use hyphen separators: `{prefix}-date-range`, `{prefix}-start-date`, `{prefix}-end-date`
  """

  @doc """
  Parses date range parameters and returns a map with preset, period, and date boundaries.

  ## Parameters

    * `params` - The params map from LiveView
    * `prefix` - The param name prefix (e.g., "analytics", "bundle-size", "builds")
    * `opts` - Keyword list of options:
      * `:default_preset` - The default preset when none is specified (default: "last-30-days")
      * `:default_days` - Days to subtract for fallback start date (default: 30)

  ## Returns

  A map with the following keys:
    * `:preset` - The selected preset string
    * `:period` - Tuple {start_datetime, end_datetime} for the date picker (nil for non-custom presets)
    * `:start_datetime` - Start DateTime for queries
    * `:end_datetime` - End DateTime for queries (nil for non-custom presets)

  ## Examples

      parse_date_range_params(params, "analytics", default_preset: "last-7-days")
      parse_date_range_params(params, "bundle-size", default_preset: "last-30-days")

  """
  def parse_date_range_params(params, prefix, opts \\ []) do
    default_preset = Keyword.get(opts, :default_preset, "last-30-days")
    default_days = Keyword.get(opts, :default_days, 30)

    range_key = "#{prefix}-date-range"
    start_key = "#{prefix}-start-date"
    end_key = "#{prefix}-end-date"

    preset = params[range_key] || default_preset

    if preset == "custom" do
      today = DateTime.to_date(DateTime.utc_now())
      start_date = parse_custom_date(params[start_key]) || Date.add(today, -default_days)
      end_date = parse_custom_date(params[end_key]) || today

      start_datetime = date_to_start_of_day_datetime(start_date)
      end_datetime = date_to_end_of_day_datetime(end_date)

      %{
        preset: preset,
        period: {start_datetime, end_datetime},
        start_datetime: start_datetime,
        end_datetime: end_datetime
      }
    else
      %{
        preset: preset,
        period: nil,
        start_datetime: start_of_day_for_preset(preset),
        end_datetime: nil
      }
    end
  end

  defp start_of_day_for_preset(preset) do
    normalized = String.replace(preset, "-", "_")
    today = DateTime.to_date(DateTime.utc_now())

    date =
      case normalized do
        "last_24_hours" -> Date.add(today, -1)
        "last_7_days" -> Date.add(today, -7)
        "last_30_days" -> Date.add(today, -30)
        "last_12_months" -> Date.add(today, -365)
        _ -> Date.add(today, -30)
      end

    date_to_start_of_day_datetime(date)
  end

  defp date_to_start_of_day_datetime(%Date{} = date) do
    DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
  end

  defp date_to_end_of_day_datetime(%Date{} = date) do
    DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
  end

  defp parse_custom_date(nil), do: nil

  defp parse_custom_date(date_string) when is_binary(date_string) do
    case DateTime.from_iso8601(date_string) do
      {:ok, datetime, _offset} ->
        DateTime.to_date(datetime)

      {:error, _} ->
        case Date.from_iso8601(date_string) do
          {:ok, date} -> date
          {:error, _} -> nil
        end
    end
  end
end
