defmodule PulseWeb.TempoBuilderDiscoveryTest do
  use Pulse.Test.Case, async: true

  alias Pulse.{Auth, Codec.NIF, OTLP.Traces, Runtime, Storage}
  alias Pulse.Auth.SharedSecret
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Test.{CompactionStore, LegacyTraceDiscoveryStorage, RuntimePlug}
  alias Pulse.Traces.{Assembly, SearchExpression, Tempo, TempoDiscovery, TempoSearch}

  @dir Path.expand("../../fixtures/traces/tempo_integration", __DIR__)
  @cases @dir |> Path.join("builder-discovery-oracle.json") |> File.read!() |> Pulse.JSON.decode!()

  defp rows do
    wire = File.read!(Path.join(@dir, "builder-discovery-input.protobuf"))

    assert Base.encode16(:crypto.hash(:sha256, wire), case: :lower) ==
             "11d854b07c8e025d560558a02d62284776e635be1deab3131caff59dc7bf0570"

    assert {:ok, rows, 0} = Traces.decode_protobuf(wire)
    rows
  end

  # The pinned autocomplete implementation ignores the two filters and omits
  # three ID columns. Keep those upstream outputs intact; these are deliberately
  # labelled complete-filter/stored-value extensions, not exact oracle matches.
  defp expected(%{"query" => q, "target" => "span.choice"})
       when q in [
              ~s'{.cached=true}',
              ~s'{event:timeSinceStart=100ns}',
              ~s'{span:parentID="1100000000000001"}',
              ~s'{link:spanID="2200000000000008"}'
            ], do: values(["leaf"])

  defp expected(%{"target" => "span:parentID"}), do: values(["1100000000000001"])
  defp expected(%{"target" => "link:traceID"}), do: values(["22000000000000000000000000000009"])
  defp expected(%{"target" => "link:spanID"}), do: values(["2200000000000008"])
  defp expected(c), do: c["response"]

  defp values(strings), do: %{"tagValues" => Enum.map(strings, &%{"type" => "string", "value" => &1})}

  defp target(target) do
    case String.split(target, ".", parts: 2) do
      [scope, key] when scope in ~w(resource span event instrumentation link) -> {scope, key}
      [_] -> {"intrinsic", target}
    end
  end

  test "Grafana builder filters and typed target dictionaries match real pinned Tempo engine/Parquet outcomes" do
    spans = rows()
    assert length(@cases) == 53
    assert Enum.count(@cases, &(expected(&1) == &1["response"])) == 46

    assert Base.encode16(:crypto.hash(:sha256, File.read!(Path.join(@dir, "builder-discovery-oracle.json"))),
             case: :lower
           ) ==
             "4a56aa0f55826524f37791555817621b6124a8dbd5aed9bbda787887294340be"

    for segments <- [Enum.map(spans, &[&1]), Enum.map(Enum.reverse(spans), &[&1]), [spans ++ spans]], c <- @cases do
      {scope, key} = target(c["target"])
      assert {:ok, {:expression, program}} = SearchExpression.parse(c["query"])
      assert {:ok, state} = NIF.tempo_expression_discovery_new(0, scope, key, program, 0, 0)

      for segment <- segments do
        assert {:ok, blob, _, _} = S3.encode_segment(:traces, segment)
        assert {:ok, count} = NIF.tempo_discovery_add(state, blob)
        assert count == length(segment)
      end

      assert {:ok, json} = NIF.tempo_discovery_finish(state)
      assert Pulse.JSON.decode!(json) == expected(c), inspect(c)
      assert {:ok, reference} = TempoDiscovery.segments_json(segments, scope, key, discovery_query: c["query"])
      assert Pulse.JSON.decode!(reference) == expected(c), inspect(c)
    end
  end

  test "older adapters cannot drop typed filters or truncate the retained context" do
    Runtime.put_env(:pulse, Storage, adapter: LegacyTraceDiscoveryStorage)
    Runtime.put_env(:pulse, TempoSearch, enabled: true)
    assert :ok = Storage.append(:traces, "builder-legacy", rows())

    for query <- [~s'{span.cached=true}', ~s'{rootName="request"}', ~s'{trace:duration>1h}'] do
      assert {:ok, json} = TempoDiscovery.query("builder-legacy", "span", "choice", 2, "json", query)
      wanted = if query == ~s'{span.cached=true}', do: ["leaf"], else: ["leaf", "request"]
      assert Pulse.JSON.decode!(json) == values(wanted)

      assert {:error, :query_scan_limit} =
               Storage.tempo_discovery_json("builder-legacy", "span", "choice",
                 discovery_query: query,
                 max_scan_rows: 2
               )
    end
  end

  test "real HTTP Grafana autocomplete retains root context outside the selected source window" do
    store =
      start_supervised!(
        {Agent,
         fn ->
           %{
             objects: %{},
             reads: [],
             version: 0,
             hook: nil,
             faults: %{},
             barriers: %{},
             lists: 0,
             deletes: [],
             requests: []
           }
         end}
      )

    object_server = start_supervised!({Bandit, plug: {CompactionStore, agent: store}, ip: {127, 0, 0, 1}, port: 0})
    {:ok, {_, object_port}} = ThousandIsland.listener_info(object_server)
    tenant = "builder-#{System.unique_integer([:positive])}"
    token = "builder-test"
    digest = "sha256$" <> Base.encode16(:crypto.hash(:sha256, token), case: :lower)
    Runtime.put_env(:pulse, Auth, module: SharedSecret, tokens: %{tenant => digest})
    Runtime.put_env(:pulse, TempoSearch, enabled: true)
    Runtime.put_env(:pulse, Storage, adapter: S3)

    Runtime.put_env(:pulse, S3,
      bucket: "pulse",
      endpoint: "http://127.0.0.1:#{object_port}",
      region: "us-east-1",
      access_key_id: tenant,
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0
    )

    start_supervised!(ManifestSupervision)
    Runtime.share()

    server =
      start_supervised!(
        {Bandit, plug: {RuntimePlug, plug: PulseWeb.Endpoint, runtime: Runtime.current()}, ip: {127, 0, 0, 1}, port: 0},
        id: :builder_http
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(server)
    url = "http://127.0.0.1:#{port}"
    headers = [{"authorization", "Bearer " <> token}, {"x-scope-orgid", tenant}]
    # Publish each original span separately, preserving the late child's >2h gap.
    for span <- rows() do
      assert {:ok, assembly} = Assembly.json([span], span.trace_id)
      assert {:ok, body} = Tempo.export(assembly, "protobuf")

      assert Req.post!(url <> "/v1/traces", headers: [{"content-type", "application/x-protobuf"} | headers], body: body).status ==
               200
    end

    for c <- @cases do
      response =
        Req.get!(url <> "/api/v2/search/tag/" <> URI.encode(c["target"], &URI.char_unreserved?/1) <> "/values",
          headers: headers,
          params: %{"q" => c["query"], "tag" => URI.encode_www_form(c["target"]), "limit" => 5000}
        )

      assert response.status == 200, inspect({c, response.body})
      assert response.body == expected(c), inspect(c)
    end

    # Authored name-completeness controls, not additional upstream oracle rows.
    for {scope, names} <- [
          {"span", ["a b", "cached", "choice", "count", "score"]},
          {"resource", ["a b", "cached", "service.name"]},
          {"event", ~w(code load message retry)},
          {"link", ~w(code load reason retry)},
          {"instrumentation", ~w(code language load retry)}
        ] do
      response =
        Req.get!(url <> "/api/v2/search/tags",
          headers: headers,
          params: %{"scope" => scope, "q" => "{span.cached=true}", "limit" => 5000}
        )

      assert response.status == 200, inspect(response.body)
      assert response.body == %{"scopes" => [%{"name" => scope, "tags" => names}]}
    end

    for query <- [~s'{rootName="request"}', ~s'{trace:duration>1h}'] do
      before = Agent.get(store, &length(&1.reads))

      response =
        Req.get!(url <> "/api/v2/search/tag/span.choice/values",
          headers: headers,
          params: %{"q" => query, "start" => 7300, "end" => 7301, "limit" => 1}
        )

      assert response.status == 200, inspect(response.body)
      assert response.body == values(["leaf"])

      reads =
        Agent.get(store, &Enum.take(&1.reads, length(&1.reads) - before))
        |> Enum.filter(&String.ends_with?(&1, ".parquet"))

      assert length(reads) == 3
      assert length(Enum.uniq(reads)) == 3
    end

    before = Agent.get(store, & &1.reads)

    for query <- ["{", "{span.cached=true} | count()", "{} >> {}", "{} | select(name)"] do
      assert Req.get!(url <> "/api/v2/search/tag/span.choice/values", headers: headers, params: %{"q" => query}).status ==
               400
    end

    assert Agent.get(store, & &1.reads) == before
  end
end
