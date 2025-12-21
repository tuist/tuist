defmodule TuistWeb.Helpers.DatePicker do
  @moduledoc """
  Helper functions for parsing date picker parameters from LiveView params.

  This module consolidates the common pattern of parsing date range presets
  and custom date ranges used across multiple LiveView modules.

  Param names use hyphen separators: `{prefix}-date-range`, `{prefix}-start-date`, `{prefix}-end-date`
  """

  @doc """
  Parses date picker parameters and returns a map with preset and period.

  ## Parameters

    * `params` - The params map from LiveView
    * `prefix` - The param name prefix (e.g., "analytics", "bundle-size", "builds")
    * `opts` - Keyword list of options:
      * `:default_preset` - The default preset when none is specified (default: "last-30-days")
      * `:default_days` - Days to subtract for fallback start date (default: 30)

  ## Returns

  A map with the following keys:
    * `:preset` - The selected preset string
    * `:period` - Tuple {start_datetime, end_datetime}

  ## Examples

      date_picker_params(params, "analytics", default_preset: "last-7-days")
      date_picker_params(params, "bundle-size", default_preset: "last-30-days")

  """
  def date_picker_params(params, prefix, opts \\ []) do
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

      %{preset: preset, period: {start_datetime, end_datetime}}
    else
      %{preset: preset, period: period_for_preset(preset)}
    end
  end

  defp period_for_preset(preset) do
    normalized = String.replace(preset, "-", "_")
    now = DateTime.utc_now()
    end_datetime = now

    start_datetime =
      case normalized do
        "last_24_hours" -> DateTime.add(now, -24, :hour)
        "last_7_days" -> DateTime.add(now, -7, :day)
        "last_30_days" -> DateTime.add(now, -30, :day)
        "last_12_months" -> DateTime.add(now, -365, :day)
        _ -> DateTime.add(now, -30, :day)
      end

    {start_datetime, end_datetime}
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
