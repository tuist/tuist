defmodule TuistWeb.Helpers.DatePickerTest do
  use ExUnit.Case, async: true

  alias TuistWeb.Helpers.DatePicker

  describe "date_picker_params/3" do
    test "returns DateTime values without microseconds for default preset" do
      # Given
      params = %{}

      # When
      %{period: {start_datetime, end_datetime}} = DatePicker.date_picker_params(params, "analytics")

      # Then - DateTimes should have no microseconds to be compatible with ClickHouse DateTime type
      assert start_datetime.microsecond == {0, 0}
      assert end_datetime.microsecond == {0, 0}
    end

    test "returns DateTime values without microseconds for last-24-hours preset" do
      # Given
      params = %{"analytics-date-range" => "last-24-hours"}

      # When
      %{period: {start_datetime, end_datetime}} = DatePicker.date_picker_params(params, "analytics")

      # Then
      assert start_datetime.microsecond == {0, 0}
      assert end_datetime.microsecond == {0, 0}
    end

    test "returns DateTime values without microseconds for last-7-days preset" do
      # Given
      params = %{"analytics-date-range" => "last-7-days"}

      # When
      %{period: {start_datetime, end_datetime}} = DatePicker.date_picker_params(params, "analytics")

      # Then
      assert start_datetime.microsecond == {0, 0}
      assert end_datetime.microsecond == {0, 0}
    end

    test "returns DateTime values without microseconds for last-12-months preset" do
      # Given
      params = %{"analytics-date-range" => "last-12-months"}

      # When
      %{period: {start_datetime, end_datetime}} = DatePicker.date_picker_params(params, "analytics")

      # Then
      assert start_datetime.microsecond == {0, 0}
      assert end_datetime.microsecond == {0, 0}
    end

    test "returns DateTime values without microseconds for custom date range" do
      # Given
      params = %{
        "analytics-date-range" => "custom",
        "analytics-start-date" => "2024-01-01T00:00:00Z",
        "analytics-end-date" => "2024-01-31T23:59:59Z"
      }

      # When
      %{period: {start_datetime, end_datetime}} = DatePicker.date_picker_params(params, "analytics")

      # Then
      assert start_datetime.microsecond == {0, 0}
      assert end_datetime.microsecond == {0, 0}
    end

    test "returns DateTime values without microseconds when custom dates include microseconds" do
      # Given - ISO8601 with microseconds
      params = %{
        "analytics-date-range" => "custom",
        "analytics-start-date" => "2024-01-01T00:00:00.123456Z",
        "analytics-end-date" => "2024-01-31T23:59:59.654321Z"
      }

      # When
      %{period: {start_datetime, end_datetime}} = DatePicker.date_picker_params(params, "analytics")

      # Then - microseconds should be truncated
      assert start_datetime.microsecond == {0, 0}
      assert end_datetime.microsecond == {0, 0}
    end

    test "returns DateTime values without microseconds when custom start date is missing" do
      # Given - missing start date should use fallback
      params = %{
        "analytics-date-range" => "custom",
        "analytics-end-date" => "2024-01-31T23:59:59Z"
      }

      # When
      %{period: {start_datetime, end_datetime}} = DatePicker.date_picker_params(params, "analytics")

      # Then
      assert start_datetime.microsecond == {0, 0}
      assert end_datetime.microsecond == {0, 0}
    end
  end
end
