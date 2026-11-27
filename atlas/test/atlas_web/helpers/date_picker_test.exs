defmodule AtlasWeb.Helpers.DatePickerTest do
  use ExUnit.Case, async: true

  alias AtlasWeb.Helpers.DatePicker

  test "reads typed rolling ranges as ending now" do
    for {preset, expected_start} <- [
          {"last-10-days", &DateTime.add(&1, -10, :day)},
          {"last-36-hours", &DateTime.add(&1, -36, :hour)},
          {"last-2-weeks", &DateTime.add(&1, -14, :day)},
          {"last-1-month", &DateTime.shift(&1, month: -1)},
          {"last-3-years", &DateTime.shift(&1, year: -3)}
        ] do
      %{preset: ^preset, period: {start_datetime, end_datetime}} =
        DatePicker.date_picker_params(%{"errors-date-range" => preset}, "errors")

      assert_in_delta DateTime.to_unix(end_datetime), System.os_time(:second), 2
      assert start_datetime == expected_start.(end_datetime)
    end
  end

  test "falls back to the default window for unknown or zero-length ranges" do
    for preset <- ["last-0-days", "last-10-fortnights", "next-10-days"] do
      %{period: {start_datetime, end_datetime}} =
        DatePicker.date_picker_params(%{"errors-date-range" => preset}, "errors")

      assert start_datetime == DateTime.add(end_datetime, -24, :hour)
    end
  end
end
