defmodule Pulse.Test.RustSDKAssertions do
  @moduledoc false
  import Bitwise
  import ExUnit.Assertions

  alias Pulse.OTLP.Value

  @batch_profile %{"queue" => 64, "maximum_batch" => 64, "scheduled_delay_ms" => 86_400_000}

  def assert_spans(spans, oracle) do
    assert oracle["sdk"] == "rust opentelemetry_sdk 0.31.0 / opentelemetry-otlp 0.31.1 / tracing-opentelemetry 0.32.1"
    assert oracle["rustc"] == "rustc 1.97.1 (8bab26f4f 2026-07-14)"
    assert is_binary(oracle["target"])
    assert oracle["batch_profile"] == @batch_profile
    assert oracle["http_hop_status"] == 503
    assert oracle["received_headers"]["traceparent"] == oracle["propagation"]["traceparent"]
    assert oracle["received_headers"]["tracestate"] == "vendor=opaque"
    assert length(spans) == length(oracle["spans"])

    for source <- oracle["spans"] do
      span = Enum.find(spans, &(&1.span_id == source["span_id"]))
      assert span
      assert span.trace_id == source["trace_id"]
      assert span.parent_span_id == if(source["parent_id"] != "", do: source["parent_id"])
      assert span.name == source["name"]
      assert span.kind == source["kind"]
      assert span.timestamp_ns == String.to_integer(source["start"])
      assert span.end_timestamp_ns == String.to_integer(source["end"])
      assert span.trace_state == source["state"]
      flags(span.flags, source["flags"], source["parent_remote"])
      assert span.status["code"] == source["status"]
      assert span.status["message"] == source["message"]
      assert span.resource_schema_url == source["resource_schema"]
      assert span.scope_schema_url == source["scope"]["schema"]
      assert span.scope["name"] == source["scope"]["name"]
      assert span.scope["version"] == source["scope"]["version"]
      assert span.otlp["resource"] === typed(source["resource"])
      assert span.otlp["scope"] === typed(source["scope"]["attributes"])
      assert span.otlp["attributes"] === typed(source["attributes"])
      assert span.dropped_attributes_count == source["dropped_attributes"]
      assert span.dropped_events_count == source["dropped_events"]
      assert span.dropped_links_count == source["dropped_links"]
      assert length(span.events) == length(source["events"])
      assert length(span.links) == length(source["links"])

      for {{event, metadata}, expected} <- Enum.zip(Enum.zip(span.events, span.otlp["events"]), source["events"]) do
        assert event["name"] == expected["name"]
        assert event["timestamp_ns"] == String.to_integer(expected["time"])
        assert event["dropped_attributes_count"] == expected["dropped"]
        assert metadata === typed(expected["attributes"])
      end

      for {{link, metadata}, expected} <- Enum.zip(Enum.zip(span.links, span.otlp["links"]), source["links"]) do
        assert link["trace_id"] == expected["trace_id"]
        assert link["span_id"] == expected["span_id"]
        assert link["trace_state"] == expected["state"]
        flags(link["flags"], expected["flags"], expected["remote"])
        assert link["dropped_attributes_count"] == expected["dropped"]
        assert metadata === typed(expected["attributes"])
      end
    end

    assert length(spans) == 3
    server = Enum.find(spans, &(&1.name == "rust server"))
    root = Enum.find(spans, &(&1.name == "rust client"))
    assert root.parent_span_id == nil
    assert server.parent_span_id == root.span_id
    assert band(root.flags, 512) == 0
    assert band(server.flags, 512) == 512
    assert server.attributes["typed.int"] == 9_007_199_254_740_993
    assert server.trace_state == "vendor=opaque"
    assert hd(server.links)["trace_state"] == "vendor=opaque"
    assert <<server.attributes["typed.zero"]::float-64>> == <<0x8000000000000000::64>>
    attrs = Map.new(server.otlp["attributes"], &{&1["key"], &1["value"]})
    assert <<attrs["typed.zero"]["doubleValue"]::float-64>> == <<0x8000000000000000::64>>
    zero = attrs["typed.floats"]["arrayValue"]["values"] |> List.last() |> Map.fetch!("doubleValue")
    assert <<zero::float-64>> == <<0x8000000000000000::64>>
    assert attrs["typed.nan"] == %{"doubleValue" => "NaN"}
    assert attrs["typed.bool"] == %{"boolValue" => true}
    assert hd(server.events)["dropped_attributes_count"] == 1
    assert hd(server.links)["dropped_attributes_count"] == 1

    for span <- spans,
        {owner, zero, nan, boolean} <- [
          {"resource", "resource.zero", "resource.nan", "resource.bool"},
          {"scope", "scope.zero", "scope.nan", "scope.enabled"}
        ] do
      values = Map.new(span.otlp[owner], &{&1["key"], &1["value"]})
      assert <<values[zero]["doubleValue"]::float-64>> == <<0x8000000000000000::64>>
      assert values[nan] == %{"doubleValue" => "NaN"}
      assert values[boolean] == %{"boolValue" => true}
    end

    adapter = Enum.find(spans, &(&1.name == "tracing adapter"))
    assert band(adapter.flags, 512) == 0
    assert Path.type(adapter.attributes["code.file.path"]) == :relative

    for event <- adapter.events, path = event["attributes"]["code.file.path"], not is_nil(path) do
      assert Path.type(path) == :relative
    end

    assert adapter.attributes["task"] == "cache-read"
    assert adapter.attributes["answer"] == 9_007_199_254_740_993
    assert adapter.parent_span_id == server.span_id
  end

  def assert_export_error(oracle, tenant) do
    assert oracle["batch_profile"] == @batch_profile

    status =
      case tenant do
        "oversize" -> 413
        "unavailable" -> 503
        "rate" -> 429
        _ -> 401
      end

    assert [error] = oracle["export_errors"]

    if oracle["protocol"] == "grpc" do
      code = %{401 => "Unauthenticated", 413 => "Unknown", 429 => "ResourceExhausted", 503 => "Unavailable"}[status]
      assert String.contains?(error, "rpc error: code = #{code}")
      assert String.contains?(error, "HTTP Status Code #{status}")
    else
      assert String.contains?(error, "kind: Status(#{status},")
    end

    # A scheduled failure can precede a successful force_flush. Check the
    # observed export error and durable storage, not just the flush result.
    assert oracle["shutdown"] == nil
  end

  defp typed(attributes) do
    assert {:ok, _, typed} = Value.attributes(%{"attributes" => attributes})
    typed
  end

  defp flags(actual, low, remote?) do
    assert band(actual, 255) == low
    assert band(actual, 256) == 256
    assert band(actual, 512) != 0 == remote?
  end
end
