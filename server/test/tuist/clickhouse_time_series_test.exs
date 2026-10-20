defmodule Tuist.ClickHouseTimeSeriesTest do
  use ExUnit.Case, async: true

  alias Tuist.ClickHouseTimeSeries

  test "uses hourly buckets for short periods" do
    start_datetime = ~U[2026-09-05 10:35:00Z]
    end_datetime = ~U[2026-09-05 12:15:00Z]

    assert ClickHouseTimeSeries.granularity(start_datetime, end_datetime) == :hour

    assert ClickHouseTimeSeries.buckets(start_datetime, end_datetime, :hour) == [
             "2026-09-05 10:00",
             "2026-09-05 11:00",
             "2026-09-05 12:00"
           ]
  end

  test "uses daily buckets for medium periods" do
    start_datetime = ~U[2026-09-01 10:35:00Z]
    end_datetime = ~U[2026-09-03 12:15:00Z]

    assert ClickHouseTimeSeries.granularity(start_datetime, end_datetime) == :day

    assert ClickHouseTimeSeries.buckets(start_datetime, end_datetime, :day) == [
             "2026-09-01",
             "2026-09-02",
             "2026-09-03"
           ]
  end

  test "uses monthly buckets for long periods" do
    start_datetime = ~U[2026-01-15 10:35:00Z]
    end_datetime = ~U[2026-04-20 12:15:00Z]

    assert ClickHouseTimeSeries.granularity(start_datetime, end_datetime) == :month

    assert ClickHouseTimeSeries.buckets(start_datetime, end_datetime, :month) == [
             "2026-01",
             "2026-02",
             "2026-03",
             "2026-04"
           ]
  end
end
