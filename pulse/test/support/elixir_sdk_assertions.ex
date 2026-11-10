defmodule Pulse.Test.ElixirSDKAssertions do
  @moduledoc false
  import Bitwise
  import ExUnit.Assertions

  alias Pulse.OTLP.Value

  def assert_versions(oracle, profile) do
    common = %{
      "bandit" => "1.11.1",
      "finch" => "0.21.0",
      "opentelemetry_bandit" => "0.3.0",
      "opentelemetry_ecto" => "2.0.0-beta.1",
      "opentelemetry_phoenix" => "2.0.1",
      "opentelemetry_process_propagator" => "0.3.0"
    }

    specific =
      case profile do
        "modern" -> %{"grpcbox" => "0.18.0", "opentelemetry_finch" => "0.3.0", "phoenix" => "1.8.15", "req" => "0.6.2"}
        "legacy" -> %{"grpcbox" => "0.17.1", "opentelemetry_finch" => "0.2.0", "phoenix" => "1.7.21", "req" => "0.5.17"}
      end

    assert oracle["versions"] == Map.merge(common, specific)
    assert oracle["sdk"] == "erlang SDK1.7/API1.5/exporter1.10"
    assert oracle["otp"] == "29"
    assert oracle["elixir"] == "1.20.4"
  end

  def assert_spans(spans, oracle) do
    assert length(spans) == 5
    assert length(oracle["spans"]) == 5

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
      assert band(span.flags, 255) == expected["flags"]
      assert band(span.flags, 256) == 256
      assert band(span.flags, 512) != 0 == (expected["parent_remote"] == true)
      assert span.resource_schema_url == expected["resource_schema"]
      assert span.scope_schema_url == expected["scope"]["schema"]
      assert span.scope["name"] == expected["scope"]["name"]
      assert span.scope["version"] == expected["scope"]["version"]
      assert span.status == %{"code" => expected["status"], "message" => expected["message"]}
      assert attributes(span.otlp["attributes"]) === attributes(typed(exporter_attributes(expected["attributes"])))
      assert attributes(span.otlp["resource"]) === attributes(typed(exporter_attributes(expected["resource"])))
      assert span.otlp["scope"] == []
      assert span.dropped_attributes_count == expected["dropped_attributes"]
      assert span.dropped_events_count == expected["dropped_events"]
      assert span.dropped_links_count == expected["dropped_links"]
      assert length(span.events) == length(expected["events"])
      assert length(span.links) == length(expected["links"])

      for {{event, metadata}, source} <- Enum.zip(Enum.zip(span.events, span.otlp["events"]), expected["events"]) do
        assert event["name"] == source["name"]
        assert event["timestamp_ns"] == String.to_integer(source["time"])
        # Exporter 1.10.0 omits this SDK record counter before sending OTLP.
        assert source["dropped"] == 1
        assert event["dropped_attributes_count"] == 0
        assert attributes(metadata) === attributes(typed(exporter_attributes(source["attributes"])))
      end

      for {{link, metadata}, source} <- Enum.zip(Enum.zip(span.links, span.otlp["links"]), expected["links"]) do
        assert link["trace_id"] == source["trace_id"]
        assert link["span_id"] == source["span_id"]
        assert link["trace_state"] == source["state"]
        # Exporter 1.10.0 emits zero dropped attributes and known-false remote
        # flags; the SDK link record has no original context flags/remote field.
        assert source["dropped"] == 1
        assert link["dropped_attributes_count"] == 0
        assert link["flags"] == 256
        assert attributes(metadata) === attributes(typed(exporter_attributes(source["attributes"])))
      end
    end

    root = Enum.find(spans, &(&1.name == "SDK client"))
    server = Enum.find(spans, &(&1.scope["name"] == "opentelemetry_bandit"))
    ecto = Enum.find(spans, &(&1.scope["name"] == "opentelemetry_ecto"))
    finch = Enum.find(spans, &(&1.scope["name"] == "opentelemetry_finch"))
    job = Enum.find(spans, &(&1.name == "async job"))
    assert root.parent_span_id == nil
    assert server.parent_span_id == root.span_id
    assert band(server.flags, 512) == 512
    assert server.trace_state == "vendor=opaque"
    assert server.name == "GET /fixture"
    assert server.attributes["http.route"] == "/fixture"
    assert ecto.parent_span_id == server.span_id
    assert job.parent_span_id == server.span_id
    assert finch.parent_span_id == root.span_id
    assert length(server.events) == 1
    assert length(job.links) == 1
    assert server.attributes["typed.int"] == 9_007_199_254_740_993
    assert <<server.attributes["typed.zero"]::float-64>> == <<0x8000000000000000::64>>
    value = attributes(server.otlp["attributes"])["typed.zero"]["doubleValue"]
    assert <<value::float-64>> == <<0x8000000000000000::64>>
    assert <<List.last(server.attributes["typed.floats"])::float-64>> == <<0x8000000000000000::64>>

    typed_zero =
      attributes(server.otlp["attributes"])["typed.floats"]["arrayValue"]["values"]
      |> List.last()
      |> Map.fetch!("doubleValue")

    assert <<typed_zero::float-64>> == <<0x8000000000000000::64>>
  end

  # Exporter 1.10.0 tests is_atom before is_boolean, including array elements.
  # Keep the original SDK snapshot unchanged and account for this precise loss.
  defp exporter_attributes(values),
    do: Enum.map(values, &Map.update!(&1, "value", fn value -> exporter_value(value) end))

  defp exporter_value(%{"boolValue" => value}), do: %{"stringValue" => to_string(value)}

  defp exporter_value(%{"arrayValue" => %{"values" => values}}),
    do: %{"arrayValue" => %{"values" => Enum.map(values, &exporter_value/1)}}

  defp exporter_value(value), do: value

  defp attributes(values), do: Map.new(values, &{&1["key"], &1["value"]})

  defp typed(values) do
    assert {:ok, _, normalized} = Value.attributes(%{"attributes" => values})
    normalized
  end
end
