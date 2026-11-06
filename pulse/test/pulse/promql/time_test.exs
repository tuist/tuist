defmodule Pulse.PromQL.TimeTest do
  use Pulse.Test.Case, async: true

  alias Pulse.PromQL.Time

  test "decimal timestamps remain exact at contemporary millisecond boundaries" do
    for ms <- 0..999 do
      fraction = ms |> Integer.to_string() |> String.pad_leading(3, "0")
      assert Time.parse_seconds("1790000000.#{fraction}") == {:ok, 1_790_000_000_000_000_000 + ms * 1_000_000}
    end

    assert {:ok, 1_790_000_000_001_000_000} = Time.parse_seconds("1.790000000001e9")
    assert {:ok, 500_000_000} = Time.parse_seconds(".5")
    assert {:ok, 5_000_000_000} = Time.parse_seconds("5.")
    assert {:ok, -1} = Time.parse_seconds("-0.0000000005")
  end

  test "timestamps and date-time strings share signed nanosecond bounds" do
    assert {:ok, 9_223_372_036_854_775_807} = Time.parse_seconds("9223372036.854775807")
    assert {:error, _} = Time.parse_seconds("9223372036.854775808")
    assert {:ok, -9_223_372_036_854_775_808} = Time.parse_seconds("-9223372036.854775808")
    assert {:ok, -9_223_372_036_854_775_808} = Time.parse_seconds("-9223372036854775808e-9")
    assert {:error, _} = Time.parse_seconds("-9223372036.854775809")
    assert {:ok, 1_790_000_000_001_000_000} = Time.parse_timestamp("2026-09-21T14:13:20.001Z")

    for value <- ["9999-12-31T00:00:00Z", "1e300", "bad", nil, %{}, "NaN", "Inf"] do
      assert {:error, _} = Time.parse_timestamp(value)
    end
  end
end
