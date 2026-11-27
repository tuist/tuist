defmodule AtlasWeb.Helpers.DatePicker do
  @moduledoc """
  Parses the query-string parameters produced by Noora's
  `<.date_picker>` and turns them into `{preset, {start_datetime,
  end_datetime}}` for the calling LiveView.

  Ported from `TuistWeb.Helpers.DatePicker` so pages share the same
  preset ids ("last-24-hours", "last-7-days", ...) and query-string
  layout (`{prefix}-date-range`, `{prefix}-start-date`,
  `{prefix}-end-date`).

  Pages that read their range some other way cannot read a typed range,
  so their pickers set `typed_ranges={false}`.
  """

  @doc """
  Parses date picker parameters. Options:

    * `:default_preset` — used when no preset is present (default
      "last-24-hours").
    * `:default_hours` — hours to subtract for the fallback custom
      start (default 24).
  """
  def date_picker_params(params, prefix, opts \\ []) do
    default_preset = Keyword.get(opts, :default_preset, "last-24-hours")
    default_hours = Keyword.get(opts, :default_hours, 24)

    range_key = "#{prefix}-date-range"
    start_key = "#{prefix}-start-date"
    end_key = "#{prefix}-end-date"

    preset = params[range_key] || default_preset

    if preset == "custom" do
      now = DateTime.truncate(DateTime.utc_now(), :second)

      start_datetime =
        parse_custom_datetime(params[start_key]) || DateTime.add(now, -default_hours, :hour)

      end_datetime = parse_custom_datetime(params[end_key]) || now

      %{preset: preset, period: {start_datetime, end_datetime}}
    else
      %{preset: preset, period: period_for_preset(preset, default_hours)}
    end
  end

  defp period_for_preset(preset, default_hours) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    start_datetime =
      case preset do
        "last-1-hour" -> DateTime.add(now, -1, :hour)
        "last-24-hours" -> DateTime.add(now, -24, :hour)
        "last-7-days" -> DateTime.add(now, -7, :day)
        "last-30-days" -> DateTime.add(now, -30, :day)
        "last-12-months" -> DateTime.add(now, -365, :day)
        _ -> relative_start(preset, now) || DateTime.add(now, -default_hours, :hour)
      end

    {start_datetime, now}
  end

  # Ranges typed into the picker, such as "last 10 days", come back as
  # rolling ids like `last-10-days` and keep ending now.
  defp relative_start(preset, now) do
    case Regex.run(~r/^last-(\d{1,4})-(hour|day|week|month|year)s?$/, preset) do
      [_, amount, unit] when amount != "0" ->
        amount = String.to_integer(amount)

        case unit do
          "hour" -> DateTime.add(now, -amount, :hour)
          "day" -> DateTime.add(now, -amount, :day)
          "week" -> DateTime.add(now, -7 * amount, :day)
          "month" -> DateTime.shift(now, month: -amount)
          "year" -> DateTime.shift(now, year: -amount)
        end

      _ ->
        nil
    end
  end

  defp parse_custom_datetime(nil), do: nil

  defp parse_custom_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
      {:error, _} -> nil
    end
  end
end
