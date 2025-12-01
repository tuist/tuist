defmodule Tuist.Utilities.DateFormatterTest do
  use ExUnit.Case, async: true

  alias Tuist.Utilities.DateFormatter

  describe "from_now/1" do
    test "formats seconds ago correctly" do
      date = Timex.shift(DateTime.utc_now(), seconds: -45)
      assert DateFormatter.from_now(date) == "45s ago"
    end

    test "formats minutes ago correctly" do
      date = Timex.shift(DateTime.utc_now(), minutes: -5)
      assert DateFormatter.from_now(date) == "5m ago"
    end

    test "formats hours ago correctly" do
      date = Timex.shift(DateTime.utc_now(), hours: -2)
      assert DateFormatter.from_now(date) == "2h ago"
    end

    test "formats days ago correctly" do
      date = Timex.shift(DateTime.utc_now(), days: -3)
      assert DateFormatter.from_now(date) == "3d ago"
    end

    test "formats weeks ago correctly" do
      date = Timex.shift(DateTime.utc_now(), days: -14)
      result = DateFormatter.from_now(date)
      assert result == "14d ago"
    end

    test "formats a single month ago correctly" do
      date = Timex.shift(DateTime.utc_now(), months: -1)
      assert DateFormatter.from_now(date) == "1mo ago"
    end

    test "formats multiple months ago correctly" do
      date = Timex.shift(DateTime.utc_now(), months: -3, days: -1)
      assert DateFormatter.from_now(date) == "3mo ago"
    end

    test "formats years ago correctly" do
      date = Timex.shift(DateTime.utc_now(), years: -1)
      assert DateFormatter.from_now(date) == "1y ago"
    end

    test "formats future dates correctly" do
      date = Timex.shift(DateTime.utc_now(), days: 2)

      result = DateFormatter.from_now(date)
      assert result == "tomorrow"
    end
  end

  describe "format_duration_from_milliseconds/2" do
    test "formats milliseconds only" do
      assert DateFormatter.format_duration_from_milliseconds(500) == "500ms"
    end

    test "formats seconds with milliseconds" do
      assert DateFormatter.format_duration_from_milliseconds(5_500) == "5.5s"
    end

    test "formats minutes with seconds" do
      assert DateFormatter.format_duration_from_milliseconds(125_000) == "2m 5s"
    end

    test "formats hours with minutes and seconds by default" do
      assert DateFormatter.format_duration_from_milliseconds(7_825_000) == "2h 10m 25s"
    end

    test "formats large durations by default" do
      assert DateFormatter.format_duration_from_milliseconds(12_675_400) == "3h 31m 15s"
    end

    test "omits hours when zero" do
      assert DateFormatter.format_duration_from_milliseconds(125_400) == "2m 5s"
    end

    test "omits minutes when zero" do
      assert DateFormatter.format_duration_from_milliseconds(3_600_500) == "1h 0.5s"
    end

    test "handles zero duration" do
      assert DateFormatter.format_duration_from_milliseconds(0) == "0.0s"
    end

    test "formats hours with minutes and seconds when include_seconds: true" do
      assert DateFormatter.format_duration_from_milliseconds(7_825_000, include_seconds: true) == "2h 10m 25s"
    end

    test "formats large durations with seconds when include_seconds: true" do
      assert DateFormatter.format_duration_from_milliseconds(12_675_400, include_seconds: true) == "3h 31m 15s"
    end

    test "omits seconds for hours when include_seconds: false" do
      assert DateFormatter.format_duration_from_milliseconds(7_825_000, include_seconds: false) == "2h 10m"
    end

    test "omits seconds for large durations when include_seconds: false" do
      assert DateFormatter.format_duration_from_milliseconds(12_675_400, include_seconds: false) == "3h 31m"
    end

    test "still includes seconds for minutes when include_seconds: false" do
      assert DateFormatter.format_duration_from_milliseconds(125_000, include_seconds: false) == "2m 5s"
    end

    test "still includes seconds for sub-hour durations when include_seconds: false" do
      assert DateFormatter.format_duration_from_milliseconds(3_500_000, include_seconds: false) == "58m 20s"
    end
  end

  describe "format_full/1" do
    test "formats DateTime with full format including day of week" do
      {:ok, datetime} = DateTime.new(~D[2024-01-15], ~T[14:30:25], "UTC")
      result = DateFormatter.format_full(datetime)
      assert result == "Mon 15 Jan 14:30:25"
    end

    test "handles different days of the week correctly" do
      {:ok, datetime} = DateTime.new(~D[2024-01-16], ~T[09:15:30], "UTC")
      result = DateFormatter.format_full(datetime)
      assert result == "Tue 16 Jan 09:15:30"

      {:ok, datetime} = DateTime.new(~D[2024-01-17], ~T[18:45:00], "UTC")
      result = DateFormatter.format_full(datetime)
      assert result == "Wed 17 Jan 18:45:00"
    end

    test "handles different months correctly" do
      {:ok, datetime} = DateTime.new(~D[2024-02-14], ~T[12:00:00], "UTC")
      result = DateFormatter.format_full(datetime)
      assert result == "Wed 14 Feb 12:00:00"

      {:ok, datetime} = DateTime.new(~D[2024-12-25], ~T[00:01:59], "UTC")
      result = DateFormatter.format_full(datetime)
      assert result == "Wed 25 Dec 00:01:59"
    end

    test "returns 'Unknown' for invalid input" do
      assert DateFormatter.format_full(nil) == "Unknown"
      assert DateFormatter.format_full("invalid") == "Unknown"
      assert DateFormatter.format_full(123) == "Unknown"
    end
  end

  describe "format_iso/1" do
    test "formats DateTime in ISO-like format with UTC" do
      {:ok, datetime} = DateTime.new(~D[2024-01-15], ~T[14:30:25], "UTC")
      result = DateFormatter.format_iso(datetime)
      assert result == "2024-01-15 14:30:25 UTC"
    end

    test "handles different dates and times correctly" do
      {:ok, datetime} = DateTime.new(~D[2023-12-31], ~T[23:59:59], "UTC")
      result = DateFormatter.format_iso(datetime)
      assert result == "2023-12-31 23:59:59 UTC"

      {:ok, datetime} = DateTime.new(~D[2024-06-15], ~T[00:00:00], "UTC")
      result = DateFormatter.format_iso(datetime)
      assert result == "2024-06-15 00:00:00 UTC"
    end

    test "truncates microseconds to seconds" do
      datetime = %DateTime{
        year: 2024,
        month: 1,
        day: 15,
        hour: 14,
        minute: 30,
        second: 25,
        microsecond: {500_000, 6},
        utc_offset: 0,
        std_offset: 0,
        zone_abbr: "UTC",
        time_zone: "Etc/UTC"
      }

      result = DateFormatter.format_iso(datetime)
      assert result == "2024-01-15 14:30:25 UTC"
    end

    test "returns 'Unknown' for invalid input" do
      assert DateFormatter.format_iso(nil) == "Unknown"
      assert DateFormatter.format_iso("invalid") == "Unknown"
      assert DateFormatter.format_iso(123) == "Unknown"
    end
  end

  describe "format_with_timezone/2" do
    test "converts UTC datetime to user timezone correctly" do
      utc_time = ~U[2024-01-15 14:30:25Z]

      # UTC 14:30 in January = EST 09:30 (EST is UTC-5 in January)
      ny_formatted = DateFormatter.format_with_timezone(utc_time, "America/New_York")
      assert ny_formatted == "Mon 15 Jan 09:30:25"

      # UTC 14:30 in January = GMT 14:30 (GMT is UTC+0 in January)
      london_formatted = DateFormatter.format_with_timezone(utc_time, "Europe/London")
      assert london_formatted == "Mon 15 Jan 14:30:25"

      # UTC 14:30 in January = JST 23:30 (JST is UTC+9)
      tokyo_formatted = DateFormatter.format_with_timezone(utc_time, "Asia/Tokyo")
      assert tokyo_formatted == "Mon 15 Jan 23:30:25"
    end

    test "handles daylight saving time correctly" do
      # July date when DST is active
      utc_summer = ~U[2024-07-15 14:30:25Z]

      # UTC 14:30 in July = EDT 10:30 (EDT is UTC-4 during DST)
      ny_summer = DateFormatter.format_with_timezone(utc_summer, "America/New_York")
      assert ny_summer == "Mon 15 Jul 10:30:25"

      # UTC 14:30 in July = BST 15:30 (BST is UTC+1 during DST)
      london_summer = DateFormatter.format_with_timezone(utc_summer, "Europe/London")
      assert london_summer == "Mon 15 Jul 15:30:25"
    end

    test "falls back to UTC when timezone is nil" do
      utc_time = ~U[2024-01-15 14:30:25Z]

      result = DateFormatter.format_with_timezone(utc_time, nil)
      assert result == "Mon 15 Jan 14:30:25 UTC"
    end

    test "falls back to UTC when timezone is invalid" do
      utc_time = ~U[2024-01-15 14:30:25Z]

      result = DateFormatter.format_with_timezone(utc_time, "Invalid/Timezone")
      assert result == "Mon 15 Jan 14:30:25 UTC"
    end

    test "handles NaiveDateTime by assuming UTC" do
      naive_time = ~N[2024-01-15 14:30:25]

      # Should convert NaiveDateTime to UTC DateTime first, then to timezone
      ny_formatted = DateFormatter.format_with_timezone(naive_time, "America/New_York")
      assert ny_formatted == "Mon 15 Jan 09:30:25"
    end

    test "falls back to UTC for NaiveDateTime when timezone is nil" do
      naive_time = ~N[2024-01-15 14:30:25]

      result = DateFormatter.format_with_timezone(naive_time, nil)
      assert result == "Mon 15 Jan 14:30:25 UTC"
    end

    test "returns 'Unknown' for unsupported datetime types" do
      assert DateFormatter.format_with_timezone(nil, "America/New_York") == "Unknown"
      assert DateFormatter.format_with_timezone("invalid", "America/New_York") == "Unknown"
      assert DateFormatter.format_with_timezone(123, "America/New_York") == "Unknown"
    end
  end
end
