defmodule Pulse.Test.SDKBridgeAssertions do
  @moduledoc false
  import Bitwise
  import ExUnit.Assertions

  alias Pulse.OTLP.Value

  def assert_spans(spans, oracle) do
    assert length(spans) == length(oracle["spans"])

    for expected <- oracle["spans"] do
      span = Enum.find(spans, &(&1.span_id == expected["span_id"]))
      assert span
      assert span.trace_id == expected["trace_id"]
      assert span.parent_span_id == if(expected["parent_id"] != "", do: expected["parent_id"])
      assert span.timestamp_ns == String.to_integer(expected["start"])
      assert span.end_timestamp_ns == String.to_integer(expected["end"])
      assert span.name == expected["name"]
      assert span.kind == expected["kind"]
      assert span.trace_state == expected["state"]
      flags(span.flags, expected["flags"], expected["parent_remote"])
      assert span.status["code"] == expected["status"]
      assert span.status["message"] == expected["message"]
      assert span.resource_schema_url == expected["resource_schema"]
      assert span.scope_schema_url == expected["scope"]["schema"]
      assert span.scope["name"] == expected["scope"]["name"]
      assert span.scope["version"] == expected["scope"]["version"]
      assert span.otlp["attributes"] === typed(expected["attributes"])
      assert span.otlp["resource"] === typed(expected["resource"])
      assert span.otlp["scope"] === typed(expected["scope"]["attributes"])
      assert span.dropped_attributes_count == expected["dropped_attributes"]
      assert span.dropped_events_count == expected["dropped_events"]
      assert span.dropped_links_count == expected["dropped_links"]
      assert length(span.events) == length(expected["events"])
      assert length(span.links) == length(expected["links"])

      for {{actual, metadata}, event} <- Enum.zip(Enum.zip(span.events, span.otlp["events"]), expected["events"]) do
        assert actual["name"] == event["name"]
        assert actual["timestamp_ns"] == String.to_integer(event["time"])
        assert actual["dropped_attributes_count"] == event["dropped"]
        assert metadata == typed(event["attributes"])
      end

      for {{actual, metadata}, link} <- Enum.zip(Enum.zip(span.links, span.otlp["links"]), expected["links"]) do
        assert actual["trace_id"] == link["trace_id"]
        assert actual["span_id"] == link["span_id"]
        # SDK 1.43's OTLP transform omits link tracestate before the Collector.
        # Separate SDK-wire/Collector/storage parity proves Pulse did not drop it.
        assert link["state"] == "vendor=opaque"
        assert actual["trace_state"] == ""
        flags(actual["flags"], link["flags"], link["remote"])
        assert actual["dropped_attributes_count"] == link["dropped"]
        assert metadata == typed(link["attributes"])
      end
    end

    worker = Enum.find(spans, &(&1.name == "worker request"))
    assert worker.dropped_attributes_count == 1
    assert worker.dropped_events_count == 1
    assert worker.dropped_links_count == 1
    assert worker.attributes["typed.int"] == 9_007_199_254_740_993
    assert <<worker.attributes["typed.zero"]::float-64>> == <<0x8000000000000000::64>>
    attributes = Map.new(worker.otlp["attributes"], &{&1["key"], &1["value"]})
    assert <<attributes["typed.zero"]["doubleValue"]::float-64>> == <<0x8000000000000000::64>>
    zero = attributes["typed.floats"]["arrayValue"]["values"] |> List.last() |> Map.fetch!("doubleValue")
    assert <<zero::float-64>> == <<0x8000000000000000::64>>
    assert <<List.last(worker.attributes["typed.floats"])::float-64>> == <<0x8000000000000000::64>>
    assert %{"key" => "typed.nan", "value" => %{"doubleValue" => "NaN"}} in worker.otlp["attributes"]
  end

  defp typed(attributes) do
    assert {:ok, _, normalized} = Value.attributes(%{"attributes" => attributes})
    normalized
  end

  defp flags(actual, expected, remote?) do
    assert band(actual, 255) == expected
    assert band(actual, 256) == 256
    assert band(actual, 512) != 0 == remote?
  end
end
