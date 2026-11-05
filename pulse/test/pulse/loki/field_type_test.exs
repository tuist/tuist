defmodule Pulse.Loki.FieldTypeTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Loki.FieldType

  # Expectations follow Go's strconv/time parsers and go-humanize, in the
  # order Loki tries them.
  @cases [
    {"42", "int"},
    {"-7", "int"},
    {"+7", "int"},
    {"9223372036854775807", "int"},
    {"9223372036854775808", "float"},
    {"1.5", "float"},
    {".5", "float"},
    {"5.", "float"},
    {"1e3", "float"},
    {"-2.5E-3", "float"},
    {"0x1p-2", "float"},
    {"Inf", "float"},
    {"-infinity", "float"},
    {"NaN", "float"},
    {"1e400", "string"},
    {"1_000", "string"},
    {"true", "boolean"},
    {"F", "boolean"},
    {"yes", "string"},
    {"150ms", "duration"},
    {"1h30m", "duration"},
    {"-1.5h", "duration"},
    {"2µs", "duration"},
    {"1h30", "string"},
    {"5mss", "string"},
    {"10kb", "bytes"},
    {"1.5 MiB", "bytes"},
    {"1,000", "bytes"},
    {"3 GB", "bytes"},
    {"10 apples", "string"},
    {"", "string"},
    {"GET", "string"}
  ]

  test "detects types as Loki does" do
    for {value, type} <- @cases do
      assert {value, FieldType.detect(value)} == {value, type}
    end
  end

  test "parses and formats byte sizes as go-humanize does" do
    assert FieldType.bytes("1.5 MiB") == {:ok, 1_572_864}
    assert FieldType.bytes("1,000") == {:ok, 1000}
    assert FieldType.bytes("5m") == {:ok, 5_000_000}
    assert FieldType.bytes("abc") == :error
    assert FieldType.format_bytes(5) == "5B"
    assert FieldType.format_bytes(1_500_000) == "1.5MB"
    assert FieldType.format_bytes(42_000) == "42kB"
    assert FieldType.format_bytes(5_000_000) == "5.0MB"
  end
end
