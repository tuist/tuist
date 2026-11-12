defmodule Pulse.OTLP.TraceUint32Test do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.IngestLimits
  alias Pulse.OTLP.{JSON, JSONReference, Traces}
  alias Pulse.Runtime
  alias Pulse.Storage.S3

  @directory "test/fixtures/otlp/trace_uint32"
  @fields [
    {"resource", "droppedAttributesCount"},
    {"scope", "droppedAttributesCount"},
    {"span", "droppedAttributesCount"},
    {"span", "droppedEventsCount"},
    {"span", "droppedLinksCount"},
    {"span", "flags"},
    {"event", "droppedAttributesCount"},
    {"link", "droppedAttributesCount"},
    {"link", "flags"}
  ]

  test "public uint32/fixed32 fixtures and producer match their checksum index" do
    manifest = fixture("checksums.json") |> Pulse.JSON.decode!()
    assert manifest["otlp"] == "v1.9.0"
    assert manifest["google_protobuf"] == "v1.36.11"
    assert map_size(manifest["files"]) == 9

    for {name, expected} <- manifest["files"] do
      assert Base.encode16(:crypto.hash(:sha256, fixture(name)), case: :lower) == expected, name
    end
  end

  test "all nine owner fields follow public quoted-integer decisions without changing wire terms" do
    cases = fixture("cases.json") |> Pulse.JSON.decode!()
    assert length(cases) == 306
    assert cases |> Enum.map(&{&1["owner"], &1["field"]}) |> Enum.uniq() |> Enum.sort() == Enum.sort(@fields)
    base = fixture("canonical.json") |> JSON.decode!(:traces)

    for row <- cases do
      path = owner_path(row["owner"]) ++ [row["field"]]
      payload = put_in(base, path, row["literal"])
      body = Pulse.JSON.encode!(payload)
      assert {:ok, native} = NIF.otlp_json_decode_scoped(body, :traces)
      assert native == JSONReference.decode!(body, :traces)
      # Admission must still see the supplied string, not a reclassified
      # scalar. Semantic normalization happens only after that boundary.
      assert get_in(native, path) === row["literal"]

      if row["accepted"] do
        assert {:ok, expected, 0} = Traces.decode(put_in(base, path, row["expected"]))
        assert {:ok, ^expected, 0} = Traces.decode(native)
        assert {:ok, ^expected, 0} = Traces.decode(payload)
      else
        expected = if row["owner"] in ["resource", "scope"], do: {:error, :invalid_otlp}, else: {:ok, [], 1}
        assert Traces.decode(native) == expected, inspect(row)
        assert Traces.decode(payload) == expected, inspect(row)
      end
    end
  end

  test "counts retain rejection of null, wrong shapes and out-of-range direct-map values" do
    base = fixture("canonical.json") |> JSON.decode!(:traces)

    for {owner, field} <- @fields, value <- [nil, true, false, [], %{}, -1, 4_294_967_296, 1.5] do
      expected = if owner in ["resource", "scope"], do: {:error, :invalid_otlp}, else: {:ok, [], 1}
      assert base |> put_in(owner_path(owner) ++ [field], value) |> Traces.decode() == expected
    end
  end

  test "quoted JSON, public canonical JSON and protobuf have identical native Parquet records" do
    assert {:ok, expected, 0} = Traces.decode_protobuf(fixture("request.protobuf"))
    assert [span] = expected
    assert span.resource_dropped_attributes_count == 4_294_967_295
    assert span.scope["dropped_attributes_count"] == 1
    assert span.flags == 4_294_967_295
    assert span.dropped_attributes_count == 1
    assert span.dropped_events_count == 1000
    assert span.dropped_links_count == 4_294_967_295
    assert [%{"dropped_attributes_count" => 4_294_967_295}] = span.events
    assert [%{"flags" => 4_294_967_295, "dropped_attributes_count" => 0}] = span.links

    for name <- ["input.json", "canonical.json"], decoder <- [JSON, JSONReference] do
      assert {:ok, ^expected, 0} = name |> fixture() |> decoder.decode!(:traces) |> Traces.decode()
    end

    assert {:ok, binary, _, _} = S3.encode_segment(:traces, expected)
    assert {:ok, ^expected} = S3.decode_segment(:traces, binary, nil, nil, [])
    # Native ABI and stored formats are unchanged: this is app-level acceptance.
    assert NIF.otlp_wire_api_version() == 3
  end

  test "randomized quoted decimal/exponent forms equal numeric fields without normalizing enums or strings" do
    :rand.seed(:exsss, {19, 32, 64})
    base = fixture("canonical.json") |> JSON.decode!(:traces)

    for _ <- 1..50 do
      {quoted, numeric} =
        Enum.reduce(@fields, {base, base}, fn {owner, field}, {quoted, numeric} ->
          value = :rand.uniform(4_294_967_296) - 1
          path = owner_path(owner) ++ [field]
          literal = Integer.to_string(value) <> "000e-3"
          # A leading-zero mantissa is not a valid spelling, even for zero.
          literal = if value == 0, do: "0.000e3", else: literal
          {put_in(quoted, path, literal), put_in(numeric, path, value)}
        end)

      body = Pulse.JSON.encode!(quoted)
      assert {:ok, native} = NIF.otlp_json_decode_scoped(body, :traces)
      assert native == JSONReference.decode!(body, :traces)
      assert {:ok, expected, 0} = Traces.decode(numeric)
      assert {:ok, ^expected, 0} = Traces.decode(native)
    end

    for {field, value} <- [{"kind", "2"}, {"kind", "SPAN_KIND_SERVER"}, {"status", %{"code" => "1"}}] do
      assert {:ok, [], 1} = base |> put_in(owner_path("span") ++ [field], value) |> Traces.decode()
    end

    attrs = [%{"key" => "literal", "value" => %{"stringValue" => "4294967295"}}]
    payload = put_in(base, owner_path("span") ++ ["attributes"], attrs)
    assert {:ok, [span], 0} = payload |> Pulse.JSON.encode!() |> JSON.decode!(:traces) |> Traces.decode()
    assert span.attributes["literal"] === "4294967295"
    assert span.otlp["attributes"] == attrs
  end

  test "escaped quoted counts and native fallback retain the same semantic result" do
    assert {:ok, expected, 0} = Traces.decode_protobuf(fixture("request.protobuf"))
    body = String.replace(fixture("input.json"), "droppedAttributesCount", ~S(droppedAttributes\u0043ount))
    assert {:ok, native} = NIF.otlp_json_decode_scoped(body, :traces)
    assert {:ok, ^expected, 0} = Traces.decode(native)
    # Unknown out-of-range numbers require the independent fallback. They
    # cannot change how the recognized quoted count fields are normalized.
    fallback = String.replace(body, ~s("resourceSpans":), ~s("future":1e1000000,"resourceSpans":))
    assert :fallback = NIF.otlp_json_decode_scoped(fallback, :traces)
    assert {:ok, ^expected, 0} = fallback |> JSON.decode!(:traces) |> Traces.decode()
  end

  test "quoted counts do not bypass record/node or existing attribute admission" do
    payload = fixture("input.json") |> JSON.decode!(:traces)
    Runtime.put_env(:pulse, IngestLimits, max_trace_nodes: 1)
    assert {:error, :too_many_trace_nodes} = Traces.decode(payload)
    Runtime.put_env(:pulse, IngestLimits, max_records: 1)
    two_spans = update_in(payload, scope_path() ++ ["spans"], &(&1 ++ &1))
    assert {:error, :too_many_records} = Traces.decode(two_spans)
    Runtime.put_env(:pulse, IngestLimits, max_attribute_bytes: 8)
    attrs = [%{"key" => "a", "value" => %{"intValue" => "12345678"}}]
    payload = put_in(payload, owner_path("span") ++ ["attributes"], attrs)
    assert {:error, :attributes_too_large} = Traces.decode(payload)
  end

  defp fixture(name), do: File.read!(Path.join(@directory, name))
  defp owner_path("resource"), do: ["resourceSpans", Access.at(0), "resource"]
  defp owner_path("scope"), do: scope_path() ++ ["scope"]
  defp owner_path("span"), do: scope_path() ++ ["spans", Access.at(0)]
  defp owner_path("event"), do: owner_path("span") ++ ["events", Access.at(0)]
  defp owner_path("link"), do: owner_path("span") ++ ["links", Access.at(0)]
  defp scope_path, do: ["resourceSpans", Access.at(0), "scopeSpans", Access.at(0)]
end
