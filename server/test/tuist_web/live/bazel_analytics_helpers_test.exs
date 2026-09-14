defmodule TuistWeb.BazelAnalyticsHelpersTest do
  use ExUnit.Case, async: true

  alias TuistWeb.BazelAnalyticsHelpers

  test "formats hourly chart buckets with time labels" do
    period = {~U[2026-09-05 09:00:00Z], ~U[2026-09-05 21:00:00Z]}
    granularity = BazelAnalyticsHelpers.time_series_granularity(period)

    assert granularity == :hour

    assert BazelAnalyticsHelpers.chart_x_axis(["2026-09-05 09:00", "2026-09-05 21:00"], granularity).axisLabel.formatter ==
             "fn:toLocaleDateHour"

    assert BazelAnalyticsHelpers.chart_tooltip("{value}", granularity).dateFormat == "hour"
  end

  test "formats longer chart buckets with date labels" do
    assert BazelAnalyticsHelpers.chart_x_axis(["2026-09-01", "2026-09-05"], :day).axisLabel.formatter ==
             "fn:toLocaleDate"

    refute Map.has_key?(BazelAnalyticsHelpers.chart_tooltip("{value}", :day), :dateFormat)
  end
end
