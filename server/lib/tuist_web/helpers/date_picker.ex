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
      now = DateTime.truncate(DateTime.utc_now(), :second)
      start_datetime = parse_custom_datetime(params[start_key]) || DateTime.add(now, -default_days, :day)
      end_datetime = parse_custom_datetime(params[end_key]) || now

      %{preset: preset, period: {start_datetime, end_datetime}}
    else
      %{preset: preset, period: period_for_preset(preset)}
    end
  end

  defp period_for_preset(preset) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    start_datetime =
      case preset do
        "last-24-hours" -> DateTime.add(now, -24, :hour)
        "last-7-days" -> DateTime.add(now, -7, :day)
        "last-30-days" -> DateTime.add(now, -30, :day)
        "last-12-months" -> DateTime.add(now, -365, :day)
        _ -> DateTime.add(now, -30, :day)
      end

    {start_datetime, now}
  end

  defp parse_custom_datetime(nil), do: nil

  defp parse_custom_datetime(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
      {:error, _} -> nil
    end
  end
end
