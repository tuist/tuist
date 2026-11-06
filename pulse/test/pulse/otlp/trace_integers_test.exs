defmodule Pulse.OTLP.TraceIntegersTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.IngestLimits
  alias Pulse.OTLP.{JSON, JSONReference, Traces}
  alias Pulse.Runtime
  alias Pulse.Storage.S3

  @directory "test/fixtures/otlp/trace_integers"

  test "quoted trace integer captures and pinned public producer match the checksum index" do
    manifest = read("checksums.json") |> Pulse.JSON.decode!()
    assert manifest["otlp"] == "v1.9.0"
    assert manifest["google_protobuf"] == "v1.36.11"
    assert map_size(manifest["files"]) == 9

    for {path, expected} <- manifest["files"] do
      assert Base.encode16(:crypto.hash(:sha256, read(path)), case: :lower) == expected, path
    end
  end

  test "all trace owners match actual public quoted uint32 and fixed32 decisions without broadening enums" do
    rows = read("cases.json") |> Pulse.JSON.decode!()
    assert length(rows) == 451

    for row <- rows do
      payload = put_in(canonical(), owner_path(row["owner"]) ++ [row["field"]], row["literal"])
      body = Pulse.JSON.encode!(payload)
      assert {:ok, native} = NIF.otlp_json_decode_scoped(body, :traces)
      assert native == JSONReference.decode!(body, :traces)
      result = Traces.decode(native)

      cond do
        # Public ProtoJSON accepts named enum strings, but OTLP requires numeric
        # enum tokens. Even quoted digits are NOT numeric enum tokens.
        row["field"] in ["kind", "code"] ->
          assert result == {:ok, [], 1}, inspect(row)

        row["accepted"] ->
          expected = put_in(payload, owner_path(row["owner"]) ++ [row["field"]], String.to_integer(row["expected"]))
          assert {:ok, spans, 0} = Traces.decode(expected)
          assert result == {:ok, spans, 0}, inspect(row)

        row["owner"] in ["resource", "scope"] ->
          assert result == {:error, :invalid_otlp}, inspect(row)

        true ->
          assert result == {:ok, [], 1}, inspect(row)
      end
    end
  end

  test "public quoted JSON, canonical numeric JSON and protobuf encode identical native segments" do
    assert {:ok, native} = NIF.otlp_json_decode_scoped(read("traces-input.json"), :traces)
    assert native == JSONReference.decode!(read("traces-input.json"), :traces)
    assert {:ok, [span] = spans, 0} = Traces.decode(native)
    assert {:ok, ^spans, 0} = Traces.decode(canonical())
    assert {:ok, ^spans, 0} = Traces.decode_protobuf(read("traces.protobuf"))
    assert span.flags == 4_294_967_295
    assert span.resource_dropped_attributes_count == 1
    assert span.scope["dropped_attributes_count"] == 2
    assert span.dropped_attributes_count == 3
    assert span.dropped_events_count == 0
    assert span.dropped_links_count == 1
    assert [%{"dropped_attributes_count" => 4}] = span.events
    assert [%{"flags" => 257, "dropped_attributes_count" => 5}] = span.links

    assert {:ok, blob, _, _} = S3.encode_segment(:traces, spans)
    assert {:ok, decoded} = S3.decode_segment(:traces, blob, nil, nil, [])
    assert decoded == spans
    assert {:ok, ^blob, _, _} = S3.encode_segment(:traces, decoded)
  end

  test "invalid span integers retain partial-success topology but metadata rejects the whole request" do
    for {owner, field} <- [{"span", "flags"}, {"event", "droppedAttributesCount"}, {"link", "flags"}] do
      payload = put_in(canonical(), owner_path(owner) ++ [field], "1e-1000")
      valid = get_in(canonical(), span_path())
      payload = update_in(payload, scope_path() ++ ["spans"], &(&1 ++ [valid]))
      assert {:ok, [_], 1} = Traces.decode(payload)
    end

    for owner <- ["resource", "scope"] do
      payload = put_in(canonical(), owner_path(owner) ++ ["droppedAttributesCount"], "4294967296")
      assert {:error, :invalid_otlp} = Traces.decode(payload)
    end
  end

  test "quoted strings cannot bypass source nodes, attribute budgets or duplicate-field detection" do
    body = read("traces-input.json")
    Runtime.put_env(:pulse, IngestLimits, max_trace_nodes: 2)
    assert {:error, :too_many_trace_nodes} = body |> JSON.decode!(:traces) |> Traces.decode()
    Runtime.put_env(:pulse, IngestLimits, max_trace_nodes: 262_144, max_attribute_bytes: 1)
    assert {:error, :attributes_too_large} = body |> JSON.decode!(:traces) |> Traces.decode()

    duplicate = String.replace(body, ~s("flags":"4294967295.0"), ~S("flags":"4294967295.0","fl\u0061gs":1))
    assert :fallback = NIF.otlp_json_decode_scoped(duplicate, :traces)
    assert_raise ArgumentError, "duplicate OTLP JSON field flags", fn -> JSON.decode!(duplicate, :traces) end
  end

  test "randomized quoted integer normalization matches numeric records through both JSON paths" do
    :rand.seed(:exsss, {123, 41, 32})
    payload = canonical()

    values = [0, 4_294_967_295 | Enum.map(1..100, fn _ -> :rand.uniform(4_294_967_296) - 1 end)]

    for n <- values do
      zeros = :rand.uniform(10)
      coefficient = if n == 0, do: "0", else: Integer.to_string(n) <> String.duplicate("0", zeros)
      literal = coefficient <> "e-" <> Integer.to_string(zeros)
      quoted = put_in(payload, span_path() ++ ["flags"], literal)
      expected = put_in(payload, span_path() ++ ["flags"], n)
      body = Pulse.JSON.encode!(quoted)
      assert {:ok, native} = NIF.otlp_json_decode_scoped(body, :traces)
      assert native == JSONReference.decode!(body, :traces)
      assert Traces.decode(native) == Traces.decode(expected)
    end
  end

  test "extreme quoted exponents stay bounded and discarded lexemes do not enter stored metadata" do
    for literal <- ["1e" <> String.duplicate("9", 1000), "1e-" <> String.duplicate("9", 1000)] do
      assert {:ok, [], 1} = canonical() |> put_in(span_path() ++ ["flags"], literal) |> Traces.decode()
    end

    # A large accepted zero lexeme is consumed, not retained by the Span record.
    literal = "0e" <> String.duplicate("9", 1000)
    assert {:ok, [span], 0} = canonical() |> put_in(span_path() ++ ["flags"], literal) |> Traces.decode()
    assert span.flags == 0
    refute :erlang.term_to_binary(span) =~ literal
  end

  defp resource_path, do: ["resourceSpans", Access.at(0)]
  defp scope_path, do: resource_path() ++ ["scopeSpans", Access.at(0)]
  defp span_path, do: scope_path() ++ ["spans", Access.at(0)]

  defp owner_path("resource"), do: resource_path() ++ ["resource"]
  defp owner_path("scope"), do: scope_path() ++ ["scope"]
  defp owner_path("span"), do: span_path()
  defp owner_path("event"), do: span_path() ++ ["events", Access.at(0)]
  defp owner_path("link"), do: span_path() ++ ["links", Access.at(0)]
  defp owner_path("status"), do: span_path() ++ ["status"]

  defp canonical, do: read("traces-canonical.json") |> JSON.decode!(:traces)
  defp read(name), do: File.read!(Path.join(@directory, name))
end
