defmodule TuistWeb.Utilities.DateFormatterTest do
  use ExUnit.Case, async: true

  alias TuistWeb.Utilities.DateFormatter

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
end
