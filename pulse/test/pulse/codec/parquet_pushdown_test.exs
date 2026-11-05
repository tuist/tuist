defmodule Pulse.Codec.ParquetPushdownTest do
  @moduledoc """
  End-to-end tests for the Rust Parquet decode-filter pushdown.

  These call `Pulse.Codec.NIF.encode_log_segment_parquet` /
  `decode_log_segment_parquet` directly, so they exercise the real
  matcher and line-filter pipeline in `native/pulse_codec/src` —
  including `find_label` on JSON resource bytes, the `service` /
  `severity_text` promoted-field fallback, and the line-filter body
  unescape.
  """
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.Record.Log

  defp encode!(records) do
    {:ok, bin, _min, _max, _count} = NIF.encode_log_segment_parquet(records)
    bin
  end

  defp decode!(bin, matchers, line_filters \\ []) do
    {:ok, records} = NIF.decode_log_segment_parquet(bin, nil, nil, nil, matchers, line_filters)
    records
  end

  describe "matcher pushdown against resource JSON" do
    setup do
      records = [
        %Log{
          timestamp_ns: 10,
          service: "api",
          body: "a",
          resource: %{"env" => "prod", "region" => "us"}
        },
        %Log{
          timestamp_ns: 20,
          service: "api",
          body: "b",
          resource: %{"env" => "dev", "region" => "us"}
        },
        %Log{
          timestamp_ns: 30,
          service: "api",
          body: "c",
          resource: %{"env" => "prod", "region" => "eu"}
        }
      ]

      %{bin: encode!(records)}
    end

    test "eq matcher on a resource label", %{bin: bin} do
      result = decode!(bin, [{"env", :eq, "prod"}])
      bodies = Enum.map(result, & &1.body)
      assert Enum.sort(bodies) == ["a", "c"]
    end

    test "regex matcher on a resource label", %{bin: bin} do
      result = decode!(bin, [{"region", :re, "us|eu"}])
      assert length(result) == 3
    end

    test "neq treats an absent label as empty string (Loki semantic)", %{bin: bin} do
      result = decode!(bin, [{"missing", :neq, "anything"}])
      # All records lack "missing", empty != "anything" → all kept.
      assert length(result) == 3
    end
  end

  describe "escape handling in resource JSON values (regression)" do
    test "value with escaped quote is compared decoded" do
      bin =
        encode!([
          %Log{
            timestamp_ns: 10,
            service: "api",
            body: "x",
            resource: %{"env" => "prod\"beta"}
          }
        ])

      # Query for the decoded value — pushdown must unescape before comparing.
      result = decode!(bin, [{"env", :eq, "prod\"beta"}])
      assert length(result) == 1
    end

    test "value with escaped newline is compared decoded" do
      bin =
        encode!([
          %Log{
            timestamp_ns: 10,
            service: "api",
            body: "x",
            resource: %{"msg" => "line\nbreak"}
          }
        ])

      result = decode!(bin, [{"msg", :eq, "line\nbreak"}])
      assert length(result) == 1
    end
  end

  describe "promoted-field lookup (regression)" do
    test "regex on service matches even when resource does not mirror it" do
      bin =
        encode!([
          %Log{timestamp_ns: 10, service: "api-users", body: "a", resource: %{}},
          %Log{timestamp_ns: 20, service: "api-orders", body: "b", resource: %{}},
          %Log{timestamp_ns: 30, service: "db", body: "c", resource: %{}}
        ])

      result = decode!(bin, [{"service", :re, "api-.*"}])
      bodies = Enum.map(result, & &1.body)
      assert Enum.sort(bodies) == ["a", "b"]
    end

    test "level=~ matches when severity_text is set but resource is empty" do
      bin =
        encode!([
          %Log{timestamp_ns: 10, service: "api", severity_text: "INFO", body: "a", resource: %{}},
          %Log{timestamp_ns: 20, service: "api", severity_text: "WARN", body: "b", resource: %{}},
          %Log{timestamp_ns: 30, service: "api", severity_text: "ERROR", body: "c", resource: %{}}
        ])

      result = decode!(bin, [{"level", :re, "INFO|WARN"}])
      bodies = Enum.map(result, & &1.body)
      assert Enum.sort(bodies) == ["a", "b"]
    end
  end

  describe "line-filter body decode (regression)" do
    test "anchored regex matches raw string body, not JSON-quoted form" do
      bin =
        encode!([
          %Log{timestamp_ns: 10, service: "api", body: "hello world", resource: %{}}
        ])

      # `^hello` was the review's key example — pre-fix, this matched
      # nothing because the body bytes stored as `"hello world"` (with
      # a leading `"`), so `^hello` never anchored.
      result = decode!(bin, [], [{:match_re, "^hello"}])
      assert length(result) == 1
    end

    test "substring with a literal quote does NOT match a plain string body" do
      bin =
        encode!([
          %Log{timestamp_ns: 10, service: "api", body: "hello world", resource: %{}}
        ])

      # Pre-fix this matched because the body was stored as `"hello world"`.
      result = decode!(bin, [], [{:contains, "\""}])
      assert result == []
    end
  end
end
