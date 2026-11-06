# Optional public-Tempo consumer fixture emitter, not a runtime dependency.
alias Pulse.Codec.NIF
alias Pulse.OTLP.Traces
alias Pulse.Storage.S3
alias Pulse.Traces.{Protobuf, TempoDiscovery}

output =
  case System.argv() do
    [path] -> Path.expand(path)
    _ -> raise "usage: MIX_ENV=test mix run scripts/trace_nonfinite_conformance.exs OUTPUT_DIRECTORY"
  end

File.mkdir_p!(output)
fixtures = Path.expand("../test/fixtures/traces", __DIR__)
{:ok, rows, 0} = Traces.decode_protobuf(File.read!(Path.join(fixtures, "tempo-nonfinite-input.protobuf")))
{:ok, blob, _, _} = S3.encode_segment(:traces, rows)
oracle = Pulse.JSON.decode!(File.read!(Path.join(fixtures, "tempo-nonfinite-oracle.json")))

for {entry, i} <- Enum.with_index(oracle["cases"]) do
  {scope, key} =
    case entry["target"] do
      "." <> key -> {"none", key}
      target -> target |> String.split(".", parts: 2) |> List.to_tuple()
    end

  {:ok, predicates} = TempoDiscovery.filter(scope, key, entry["query"])

  {:ok, state} =
    if predicates == [],
      do: NIF.tempo_discovery_new(0, scope, key),
      else: NIF.tempo_filtered_discovery_new(0, scope, key, predicates)

  {:ok, _} = NIF.tempo_discovery_add(state, blob)
  {:ok, json} = NIF.tempo_discovery_finish(state)
  response = Pulse.JSON.decode!(json)
  if response != entry["response"], do: raise("dictionary mismatch at case #{i}")
  number = i |> Integer.to_string() |> String.pad_leading(2, "0")
  File.write!(Path.join(output, "result-#{number}.protobuf"), Protobuf.encode(response, :tag_values_v2))
end

trace_id = hd(rows).trace_id
{:ok, state} = NIF.trace_query_new_trace(trace_id, nil, 100)
{:ok, _} = NIF.trace_query_add(state, blob)
{:ok, assembly} = NIF.trace_query_finish_trace(state, 100, trace_id)

for {name, format} <- [{"v1", "protobuf"}, {"v2", "protobuf_v2"}] do
  {:ok, body} = NIF.tempo_trace_export(assembly, format)
  File.write!(Path.join(output, "export-#{name}.protobuf"), body)
end

IO.puts("emitted #{length(oracle["cases"])} native discovery responses and 2 native trace exports")
