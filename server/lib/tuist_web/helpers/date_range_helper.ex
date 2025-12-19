defmodule TuistWeb.Helpers.DateRangeHelper do
  @moduledoc """
  Helper functions for parsing date range parameters from LiveView params.

  This module consolidates the common pattern of parsing date range presets
  and custom date ranges used across multiple LiveView modules.

  Param names use hyphen separators: `{prefix}-date-range`, `{prefix}-start-date`, `{prefix}-end-date`
  """

  @doc """
  Parses date range parameters and returns a map with start_date, end_date,
  and date_picker_value.

  ## Parameters

    * `params` - The params map from LiveView
    * `prefix` - The param name prefix (e.g., "analytics", "bundle-size", "builds")
    * `opts` - Keyword list of options:
      * `:default_preset` - The default preset when none is specified (default: "last-30-days")
      * `:default_days` - Days to subtract for fallback start date (default: 30)

  ## Returns

  A map with the following keys:
    * `:preset` - The selected preset string
    * `:start_date` - The calculated start date
    * `:end_date` - The calculated end date (nil for non-custom presets)
    * `:date_picker_value` - Map with :start and :end for custom ranges, nil otherwise

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

    {start_date, end_date} = parse_dates(params, preset, start_key, end_key, default_days)

    date_picker_value =
      if preset == "custom" && start_date && end_date do
        %{start: start_date, end: end_date}
      end

    %{
      preset: preset,
      start_date: start_date,
      end_date: end_date,
      date_picker_value: date_picker_value
    }
  end

  @doc """
  Parses an ISO 8601 date string into a Date.

  Handles both DateTime strings (with time component) and Date strings.
  Returns nil for nil input or invalid strings.

  ## Examples

      iex> parse_custom_date("2024-01-15")
      ~D[2024-01-15]

      iex> parse_custom_date("2024-01-15T10:30:00Z")
      ~D[2024-01-15]

      iex> parse_custom_date(nil)
      nil

  """
  def parse_custom_date(nil), do: nil

  def parse_custom_date(date_string) when is_binary(date_string) do
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
  # Private functions
  def start_date_for_preset(preset) do
    # Normalize preset to underscore format for matching
    normalized = String.replace(preset, "-", "_")
    today = DateTime.utc_now() |> DateTime.to_date()

    case normalized do
      "last_24_hours" -> Date.add(today, -1)
      "last_7_days" -> Date.add(today, -7)
      "last_30_days" -> Date.add(today, -30)
      "last_12_months" -> Date.add(today, -365)
      _ -> Date.add(today, -30)
    end
  end


  defp parse_dates(params, "custom", start_key, end_key, default_days) do
    today = DateTime.utc_now() |> DateTime.to_date()
    start_date = parse_custom_date(params[start_key]) || Date.add(today, -default_days)
    end_date = parse_custom_date(params[end_key]) || today
    {start_date, end_date}
  end

  defp parse_dates(_params, preset, _start_key, _end_key, _default_days) do
    {start_date_for_preset(preset), nil}
  end
end
