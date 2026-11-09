defmodule PulseWeb.TracesEndToEndTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Auth
  alias Pulse.Auth.SharedSecret
  alias Pulse.Codec.NIF
  alias Pulse.OTLP.JSON
  alias Pulse.OTLP.Traces
  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Test.CompactionStore
  alias Pulse.Test.MCPMessages
  alias Pulse.Test.OTLPTraceFixture, as: Fixture
  alias Pulse.Test.RuntimePlug
  alias Pulse.Traces.Protobuf
  alias Pulse.Traces.TempoIntrinsics
  alias Pulse.Traces.TempoSearch

  @intrinsic_names "../../fixtures/traces/tempo_integration/intrinsic-names.json"
                   |> Path.expand(__DIR__)
                   |> File.read!()
                   |> Pulse.JSON.decode!()

  setup do
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
    {:ok, {_ip, object_port}} = ThousandIsland.listener_info(object_server)

    config = %{
      bucket: "pulse",
      endpoint: "http://127.0.0.1:#{object_port}",
      region: "us-east-1",
      access_key_id: "test-#{System.unique_integer([:positive])}",
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0
    }

    tenant = "trace-http-#{System.unique_integer([:positive])}"
    token = "test-token"
    hash = "sha256$" <> Base.encode16(:crypto.hash(:sha256, token), case: :lower)
    Runtime.put_env(:pulse, Auth, module: SharedSecret, tokens: %{tenant => hash})
    Runtime.put_env(:pulse, TempoSearch, enabled: true)
    Runtime.put_env(:pulse, Storage, adapter: S3)
    Runtime.put_env(:pulse, S3, config)
    start_supervised!(ManifestSupervision)

    api_server =
      start_supervised!(
        {Bandit, plug: {RuntimePlug, plug: PulseWeb.Endpoint, runtime: Runtime.current()}, ip: {127, 0, 0, 1}, port: 0},
        id: :trace_api_server
      )

    {:ok, {_ip, api_port}} = ThousandIsland.listener_info(api_server)
    %{store: store, tenant: tenant, token: token, url: "http://127.0.0.1:#{api_port}"}
  end

  defp wire_batches(<<>>), do: []

  defp wire_batches(<<10, rest::binary>> = wire) do
    {length, payload} = wire_length(rest, 0, 0)
    <<_resource::binary-size(^length), remaining::binary>> = payload
    prefix = byte_size(wire) - byte_size(remaining)
    [binary_part(wire, 0, prefix) | wire_batches(remaining)]
  end

  defp wire_length(<<byte, rest::binary>>, value, shift) do
    value = value + Bitwise.bsl(Bitwise.band(byte, 127), shift)
    if byte < 128, do: {value, rest}, else: wire_length(rest, value, shift + 7)
  end

  defp mcp(ctx, method, params, token \\ nil) do
    name = Map.get(params, "name")

    headers = [
      {"authorization", "Bearer #{token || ctx.token}"},
      {"accept", "application/json, text/event-stream"},
      {"mcp-protocol-version", MCPMessages.version()},
      {"mcp-method", method}
    ]

    headers = if name, do: [{"mcp-name", name} | headers], else: headers
    Req.post!(ctx.url <> "/mcp", headers: headers, json: MCPMessages.request(1, method, params))
  end

  defp query(ctx, args, token \\ nil) do
    response =
      mcp(ctx, "tools/call", %{"name" => "query_traces", "arguments" => Map.put_new(args, "tenant", ctx.tenant)}, token)

    assert response.status == 200
    refute response.body["result"]["isError"]
    [%{"type" => "text", "text" => text}] = response.body["result"]["content"]
    Pulse.JSON.decode!(text)
  end

  test "unfiltered scoped Tempo discovery keeps original types, auth and whole-request limits", ctx do
    wire = File.read!(Path.expand("../../fixtures/traces/tempo-discovery-input.protobuf", __DIR__))
    headers = [{"authorization", "Bearer #{ctx.token}"}, {"x-scope-orgid", ctx.tenant}]

    for batch <- wire_batches(wire) do
      assert Req.post!(ctx.url <> "/v1/traces",
               headers: [{"content-type", "application/x-protobuf"} | headers],
               body: batch
             ).status == 200
    end

    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)

    cases =
      File.read!(Path.expand("../../fixtures/traces/tempo-discovery-oracle.json", __DIR__)) |> Pulse.JSON.decode!()

    for c <- cases do
      {path, params} =
        if c["mode"] == "names",
          do: {"/api/v2/search/tags", %{scope: c["scope"]}},
          else: {"/api/v2/search/tag/" <> c["scope"] <> "." <> c["key"] <> "/values", %{q: "{}"}}

      response = Req.get!(ctx.url <> path, headers: headers, params: params)
      assert response.status == 200
      assert response.body == c["response"]
    end

    v1 = Req.get!(ctx.url <> "/api/search/tag/span.cached/values", headers: headers)
    assert v1.status == 200 and v1.body == %{"tagValues" => ["false", "true"]}
    empty = Req.get!(ctx.url <> "/api/search/tag/span.empty/values", headers: headers)
    assert empty.status == 200 and empty.body == %{"tagValues" => [""]}
    names = Req.get!(ctx.url <> "/api/search/tags", headers: headers, params: %{scope: "resource"})
    assert names.status == 200 and "service.name" in names.body["tagNames"]

    proto =
      Req.get!(ctx.url <> "/api/v2/search/tag/span.retries/values",
        headers: [{"accept", "application/protobuf"} | headers]
      )

    assert proto.status == 200 and is_binary(proto.body)
    assert Req.get!(ctx.url <> "/api/v2/search/tag/span.opaque/values", headers: headers).status == 422

    for params <- [
          %{scope: "unknown"},
          %{scope: "span", start: "10"},
          %{scope: "span", q: "{nestedSetParent > 0}"}
        ] do
      assert Req.get!(ctx.url <> "/api/v2/search/tags", headers: headers, params: params).status == 400
    end

    limited_names =
      Req.get!(ctx.url <> "/api/v2/search/tags", headers: headers, params: %{scope: "resource", limit: "1"})

    resource_names = Enum.find(cases, &(&1["mode"] == "names" and &1["scope"] == "resource"))
    assert limited_names.status == 200 and limited_names.body == resource_names["response"]

    assert Req.get!(ctx.url <> "/api/v2/search/tags",
             headers: [{"authorization", "Bearer wrong"}, {"x-scope-orgid", ctx.tenant}],
             params: %{scope: "resource"}
           ).status == 401
  end

  test "Tempo filtered value discovery replays actual engine cases over independently ingested owners and restart",
       ctx do
    wire = File.read!(Path.expand("../../fixtures/traces/tempo-filtered-discovery-input.protobuf", __DIR__))
    headers = [{"authorization", "Bearer #{ctx.token}"}, {"x-scope-orgid", ctx.tenant}]

    for batch <- wire_batches(wire) do
      assert Req.post!(ctx.url <> "/v1/traces",
               headers: [{"content-type", "application/x-protobuf"} | headers],
               body: batch
             ).status == 200
    end

    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)

    cases =
      File.read!(Path.expand("../../fixtures/traces/tempo-filtered-discovery-oracle.json", __DIR__))
      |> Pulse.JSON.decode!()

    for c <- cases do
      path = "/api/v2/search/tag/" <> c["target"] <> "/values"
      response = Req.get!(ctx.url <> path, headers: headers, params: %{q: c["query"]})

      if c["supported"] do
        assert response.status == 200, c["name"]
        assert response.body == c["response"], c["name"]

        assert response.headers["x-pulse-trace-coverage"] == [
                 "all-visible-stored-attributes; exporter-completeness-unknown"
               ]
      else
        assert response.status == 400
      end
    end

    c = hd(cases)
    path = "/api/v2/search/tag/" <> c["target"] <> "/values"
    proto = Req.get!(ctx.url <> path, headers: [{"accept", "application/protobuf"} | headers], params: %{q: c["query"]})
    assert proto.status == 200
    assert proto.body == Protobuf.encode(c["response"], :tag_values_v2)

    v1 =
      Req.get!(ctx.url <> "/api/search/tag/span.cached/values",
        headers: headers,
        params: %{q: ~s'{span.request.kind="api"}'}
      )

    assert v1.status == 200 and v1.body == %{"tagValues" => ["false"]}

    assert Req.get!(ctx.url <> path,
             headers: [{"authorization", "Bearer wrong"}, {"x-scope-orgid", ctx.tenant}],
             params: %{q: c["query"]}
           ).status == 401

    for params <- [
          %{q: "{"},
          %{q: c["query"], start: "10"},
          %{q: "{nestedSetParent > 0}"},
          %{q: c["query"], limit: "-1"}
        ] do
      assert Req.get!(ctx.url <> path, headers: headers, params: params).status == 400
    end

    assert Req.get!(ctx.url <> "/api/v2/search/tag/span.opaque/values",
             headers: headers,
             params: %{q: ~s'{span.request.kind="api"}'}
           ).status == 422

    assert Req.get!(ctx.url <> "/api/v2/search/tag/span.opaque/values",
             headers: headers,
             params: %{q: ~s'{span.request.kind="rpc"}'}
           ).body == %{"tagValues" => []}
  end

  @tag timeout: 180_000
  test "unscoped values, finite floats and filtered stored intrinsic strings roundtrip HTTP after owner restart", ctx do
    headers = [{"authorization", "Bearer #{ctx.token}"}, {"x-scope-orgid", ctx.tenant}]
    wire = File.read!(Path.expand("../../fixtures/traces/tempo-more-discovery-input.protobuf", __DIR__))

    for batches <- Enum.chunk_every(wire_batches(wire), 91) do
      assert Req.post!(ctx.url <> "/v1/traces",
               headers: [{"content-type", "application/x-protobuf"} | headers],
               body: IO.iodata_to_binary(batches)
             ).status == 200
    end

    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)
    dir = Path.expand("../../fixtures/traces", __DIR__)
    plain = File.read!(Path.join(dir, "tempo-more-discovery-oracle.json")) |> Pulse.JSON.decode!()

    filtered =
      File.read!(Path.join(dir, "tempo-dynamic-filters-oracle.json"))
      |> Pulse.JSON.decode!()
      |> Enum.map(&Map.put(&1, "response", &1["complete"]))

    for c <- plain ++ filtered, version <- [1, 2] do
      base = if version == 1, do: "/api/search/tag/", else: "/api/v2/search/tag/"
      path = ctx.url <> base <> URI.encode(c["target"]) <> "/values"
      body = c["response"]

      body =
        if version == 1,
          do: %{"tagValues" => body["tagValues"] |> Enum.map(&Map.get(&1, "value", "")) |> Enum.uniq() |> Enum.sort()},
          else: body

      schema = if version == 1, do: :tag_values, else: :tag_values_v2
      response = Req.get!(path, headers: headers, params: %{q: c["query"]})
      assert response.status == 200 and response.body == body, inspect(c)

      if not String.contains?(c["target"], "."),
        do:
          assert(
            response.headers["x-pulse-trace-coverage"] == ["stored-intrinsic-values; exporter-completeness-unknown"]
          )

      response = Req.get!(path, headers: [{"accept", "application/protobuf"} | headers], params: %{q: c["query"]})
      assert response.status == 200 and response.body == Protobuf.encode(body, schema)
    end

    for target <- [".value", "name"] do
      assert Req.get!(ctx.url <> "/api/v2/search/tag/" <> target <> "/values",
               headers: [{"authorization", "Bearer wrong"}]
             ).status == 401
    end

    for {target, q} <- [
          {".value", ~s'{resource.value="literal"}'},
          {"name", "{nestedSetParent > 0}"}
        ] do
      assert Req.get!(ctx.url <> "/api/v2/search/tag/" <> target <> "/values", headers: headers, params: %{q: q}).status ==
               400
    end

    for target <- ["none.value", ".root.name", ".root.service.name", "trace:unsupported"] do
      assert Req.get!(ctx.url <> "/api/v2/search/tag/" <> target <> "/values", headers: headers).status == 400
    end
  end

  test "omitted empty and none name scopes preserve namespaces, version rules and complete hints", ctx do
    headers = [{"authorization", "Bearer #{ctx.token}"}, {"x-scope-orgid", ctx.tenant}]
    static = %{"scopes" => [%{"name" => "intrinsic", "tags" => @intrinsic_names}]}
    empty = Req.get!(ctx.url <> "/api/v2/search/tags", headers: headers)
    assert empty.status == 200 and empty.body == static
    empty = Req.get!(ctx.url <> "/api/search/tags", headers: headers)
    assert empty.status == 200 and empty.body == %{"tagNames" => []}
    wire = File.read!(Path.expand("../../fixtures/traces/tempo-filtered-names-no-service.protobuf", __DIR__))

    for batch <- wire_batches(wire) do
      assert Req.post!(ctx.url <> "/v1/traces",
               headers: [{"content-type", "application/x-protobuf"} | headers],
               body: batch
             ).status == 200
    end

    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)

    cases =
      File.read!(Path.expand("../../fixtures/traces/tempo-default-names-oracle.json", __DIR__))
      |> Pulse.JSON.decode!()
      |> Enum.filter(&(&1["dataset"] == "no-service"))
      |> Enum.map(fn c ->
        # Only the v2.9 vocabulary is superseded; stored-name oracles stay intact.
        update_in(c, ["complete", "scopes"], fn scopes ->
          for scope <- scopes do
            if scope["name"] == "intrinsic", do: %{scope | "tags" => @intrinsic_names}, else: scope
          end
        end)
      end)

    for c <- cases, scope <- [%{}, %{scope: ""}, %{scope: "none"}], version <- [1, 2] do
      path = if version == 1, do: "/api/search/tags", else: "/api/v2/search/tags"
      expected = if version == 1, do: c["v1"], else: c["complete"]
      schema = if version == 1, do: :tags, else: :tags_v2
      params = Map.put(scope, :q, c["query"])
      response = Req.get!(ctx.url <> path, headers: headers, params: params)
      assert response.status == 200 and response.body == expected, inspect(c)

      expected_coverage =
        if version == 1,
          do: "stored-context-name-hints; not-key-presence",
          else: "stored-context-name-hints-and-static-vocabulary; not-key-presence"

      assert response.headers["x-pulse-trace-coverage"] == [expected_coverage]
      response = Req.get!(ctx.url <> path, headers: [{"accept", "application/protobuf"} | headers], params: params)
      assert response.status == 200 and response.body == Protobuf.encode(expected, schema)
    end

    c = hd(cases)
    response = mcp(ctx, "tools/call", %{"name" => "discover_trace_tags", "arguments" => %{"tenant" => ctx.tenant}})
    assert Pulse.JSON.decode!(hd(response.body["result"]["content"])["text"]) == c["complete"]
    assert Req.get!(ctx.url <> "/api/v2/search/tags", headers: [{"authorization", "Bearer wrong"}]).status == 401

    for params <- [%{start: "10"}, %{scope: "all"}, %{q: "{nestedSetParent > 0}"}, %{q: "{} with (most_recent=true)"}] do
      assert Req.get!(ctx.url <> "/api/v2/search/tags", headers: headers, params: params).status == 400
    end

    assert Req.get!(ctx.url <> "/api/v2/search/tag/.shared/values", headers: headers).status == 200
  end

  test "filtered names preserve complete hints across separate S3 objects and restart", ctx do
    wire = File.read!(Path.expand("../../fixtures/traces/tempo-filtered-names-promoted.protobuf", __DIR__))
    headers = [{"authorization", "Bearer #{ctx.token}"}, {"x-scope-orgid", ctx.tenant}]

    for batch <- wire_batches(wire) do
      assert Req.post!(ctx.url <> "/v1/traces",
               headers: [{"content-type", "application/x-protobuf"} | headers],
               body: batch
             ).status == 200
    end

    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)

    cases =
      File.read!(Path.expand("../../fixtures/traces/tempo-filtered-names-oracle.json", __DIR__))
      |> Pulse.JSON.decode!()
      |> Enum.filter(&(&1["dataset"] == "promoted"))

    assert length(cases) == 45

    for c <- cases do
      params = %{scope: c["scope"], q: c["query"]}
      response = Req.get!(ctx.url <> "/api/v2/search/tags", headers: headers, params: params)
      assert response.status == 200
      assert response.body == c["complete"], inspect(c)
      assert response.headers["x-pulse-trace-coverage"] == ["stored-context-name-hints; not-matching-key-presence"]

      response =
        Req.get!(ctx.url <> "/api/v2/search/tags",
          headers: [{"accept", "application/protobuf"} | headers],
          params: params
        )

      assert response.status == 200 and response.body == Protobuf.encode(c["complete"], :tags_v2)
    end

    c = Enum.find(cases, &(&1["scope"] == "resource" and String.contains?(&1["query"], "absent")))
    params = %{scope: "resource", q: c["query"]}
    names = hd(c["complete"]["scopes"])["tags"]
    response = Req.get!(ctx.url <> "/api/search/tags", headers: headers, params: params)
    assert response.status == 200 and response.body == %{"tagNames" => names}

    response =
      Req.get!(ctx.url <> "/api/search/tags", headers: [{"accept", "application/protobuf"} | headers], params: params)

    assert response.status == 200 and response.body == Protobuf.encode(%{"tagNames" => names}, :tags)

    assert Req.get!(ctx.url <> "/api/v2/search/tags",
             headers: [{"authorization", "Bearer wrong"}, {"x-scope-orgid", ctx.tenant}],
             params: params
           ).status == 401

    for params <- [
          %{scope: "resource", q: "{"},
          %{scope: "span", q: "{} with (most_recent=true)"},
          %{scope: "resource", q: c["query"], start: "10"}
        ] do
      assert Req.get!(ctx.url <> "/api/v2/search/tags", headers: headers, params: params).status == 400
    end

    intrinsic_names =
      Req.get!(ctx.url <> "/api/v2/search/tags", headers: headers, params: %{scope: "intrinsic", q: c["query"]})

    assert intrinsic_names.status == 200 and
             intrinsic_names.body == %{"scopes" => [%{"name" => "intrinsic", "tags" => @intrinsic_names}]}

    response =
      mcp(ctx, "tools/call", %{
        "name" => "discover_trace_tags",
        "arguments" => %{"tenant" => ctx.tenant, "scope" => "resource", "query" => c["query"]}
      })

    assert response.body["result"]["isError"] in [nil, false]
    content = hd(response.body["result"]["content"])
    assert Pulse.JSON.decode!(content["text"]) == c["complete"]
  end

  test "Tempo static intrinsic dictionaries are authenticated and never read tenant object storage", ctx do
    headers = [{"authorization", "Bearer #{ctx.token}"}, {"x-scope-orgid", ctx.tenant}]

    cases =
      File.read!(Path.expand("../../fixtures/traces/tempo-intrinsics-oracle.json", __DIR__)) |> Pulse.JSON.decode!()

    # Keep all seven original value shortcuts; names use the pinned newer helper.
    cases =
      for c <- cases do
        if c["key"] == "",
          do: %{c | "response" => %{"scopes" => [%{"name" => "intrinsic", "tags" => @intrinsic_names}]}},
          else: c
      end

    for c <- cases do
      path =
        if c["key"] == "",
          do: "/api/v2/search/tags?scope=intrinsic",
          else: "/api/v2/search/tag/" <> String.replace(c["key"], ":", "%3A") <> "/values"

      response = Req.get!(ctx.url <> path, headers: headers)
      assert response.status == 200
      assert response.body == c["response"]
      assert response.headers["x-pulse-trace-coverage"] == ["static-protocol-vocabulary; not-stored-values"]
      response = Req.get!(ctx.url <> path, headers: [{"accept", "application/protobuf"} | headers])
      schema = if c["key"] == "", do: :tags_v2, else: :tag_values_v2
      assert response.status == 200 and response.body == Protobuf.encode(c["response"], schema)

      # Static suggestions accept valid filters without claiming stored matches.
      filtered = Req.get!(ctx.url <> path, headers: headers, params: %{q: ~s'{resource.service.name="absent"}'})
      assert filtered.status == 200 and filtered.body == c["response"]
      assert filtered.headers["x-pulse-trace-coverage"] == ["static-protocol-vocabulary; not-stored-values"]

      assert Req.get!(ctx.url <> path, headers: [{"authorization", "Bearer wrong"}, {"x-scope-orgid", ctx.tenant}]).status ==
               401
    end

    names = hd(cases)["response"]["scopes"] |> hd() |> Map.fetch!("tags")
    response = Req.get!(ctx.url <> "/api/search/tags?scope=intrinsic", headers: headers)
    assert response.status == 200 and response.body == %{"tagNames" => names}

    response =
      Req.get!(ctx.url <> "/api/search/tags?scope=intrinsic", headers: [{"accept", "application/protobuf"} | headers])

    assert response.status == 200 and response.body == Protobuf.encode(%{"tagNames" => names}, :tags)

    for path <- [
          "/api/search/tag/status/values",
          "/api/v2/search/tag/trace:unsupported/values",
          "/api/v2/search/tag/intrinsic.kind/values",
          "/api/v2/search/tags?scope=all",
          "/api/v2/search/tag/kind/values?start=10"
        ] do
      assert Req.get!(ctx.url <> path, headers: headers).status == 400, path
    end

    assert Req.get!(ctx.url <> "/api/v2/search/tag/kind/values?start=10&end=20", headers: headers).status == 200

    response =
      mcp(
        ctx,
        "tools/call",
        %{
          "name" => "discover_trace_tag_values",
          "arguments" => %{"tenant" => ctx.tenant, "scope" => "intrinsic", "key" => "kind"}
        },
        "wrong"
      )

    assert response.body["result"]["isError"]
    assert Agent.get(ctx.store, & &1.requests) == []
    assert Agent.get(ctx.store, & &1.reads) == []
    assert Agent.get(ctx.store, & &1.lists) == 0
  end

  test "Tempo discovery preserves five original owner scopes through HTTP, S3 and restart", ctx do
    wire = File.read!(Path.expand("../../fixtures/traces/tempo-scopes-input.protobuf", __DIR__))
    headers = [{"authorization", "Bearer #{ctx.token}"}, {"x-scope-orgid", ctx.tenant}]

    for batch <- wire_batches(wire) do
      assert Req.post!(ctx.url <> "/v1/traces",
               headers: [{"content-type", "application/x-protobuf"} | headers],
               body: batch
             ).status == 200
    end

    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)
    cases = File.read!(Path.expand("../../fixtures/traces/tempo-scopes-oracle.json", __DIR__)) |> Pulse.JSON.decode!()

    for c <- cases do
      {path, params} =
        if c["key"] == "",
          do: {"/api/v2/search/tags", %{scope: c["scope"]}},
          else: {"/api/v2/search/tag/" <> c["scope"] <> "." <> c["key"] <> "/values", %{q: c["query"]}}

      response = Req.get!(ctx.url <> path, headers: headers, params: params)
      assert response.status == 200, inspect(c)
      assert response.body == c["response"], inspect(c)
    end

    for scope <- ["instrumentation", "event", "link"] do
      path = "/api/v2/search/tag/" <> scope <> ".count/values"
      response = Req.get!(ctx.url <> path, headers: [{"accept", "application/protobuf"} | headers])
      expected = Enum.find(cases, &(&1["scope"] == scope and &1["key"] == "count" and &1["query"] == ""))
      assert response.status == 200
      assert response.body == Protobuf.encode(expected["response"], :tag_values_v2)
      assert Req.get!(ctx.url <> "/api/v2/search/tag/" <> scope <> ".opaque/values", headers: headers).status == 422

      assert Req.get!(ctx.url <> path, headers: [{"authorization", "Bearer wrong"}, {"x-scope-orgid", ctx.tenant}]).status ==
               401

      assert Req.get!(ctx.url <> path, headers: headers, params: %{start: "10"}).status == 400
      v1 = Req.get!(ctx.url <> "/api/search/tag/" <> scope <> ".enabled/values", headers: headers)
      assert v1.status == 200 and v1.body == %{"tagValues" => ["false", "true"]}
    end
  end

  @tag timeout: 120_000
  test "filtered unscoped values preserve parent selection through gzip, three S3 sources, restart and both wire versions",
       ctx do
    dir = Path.expand("../../fixtures/traces", __DIR__)
    wire = File.read!(Path.join(dir, "tempo-filtered-unscoped-input.protobuf"))
    headers = [{"authorization", "Bearer #{ctx.token}"}, {"x-scope-orgid", ctx.tenant}]

    for batch <- wire |> wire_batches() |> Enum.chunk_every(91) do
      response =
        Req.post!(ctx.url <> "/v1/traces",
          headers: [{"content-type", "application/x-protobuf"}, {"content-encoding", "gzip"} | headers],
          body: :zlib.gzip(IO.iodata_to_binary(batch))
        )

      assert response.status == 200
    end

    assert Agent.get(ctx.store, fn state -> Enum.count(Map.keys(state.objects), &String.ends_with?(&1, ".parquet")) end) ==
             3

    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)
    cases = File.read!(Path.join(dir, "tempo-filtered-unscoped-oracle.json")) |> Pulse.JSON.decode!()
    for c <- cases, version <- [1, 2], do: assert_discovery_value_wire(ctx, c, version, headers)
    c = Enum.find(cases, &(&1["key"] == "mixed" and &1["query"] == ~s'{resource.service.name="worker"}'))

    response =
      mcp(ctx, "tools/call", %{
        "name" => "discover_trace_tag_values",
        "arguments" => %{
          "tenant" => ctx.tenant,
          "scope" => "none",
          "key" => "mixed",
          "query" => c["query"],
          "start_ts_ns" => 1,
          "end_ts_ns" => 1000
        }
      })

    refute response.body["result"]["isError"]
    assert Pulse.JSON.decode!(hd(response.body["result"]["content"])["text"]) == c["complete"]
    path = ctx.url <> "/api/v2/search/tag/.mixed/values"
    assert Req.get!(path, headers: [{"x-scope-orgid", ctx.tenant}], params: %{q: c["query"]}).status == 401
    assert Req.get!(path, headers: headers, params: %{q: ~s'{resource.mixed="literal"}'}).status == 400
    assert Req.get!(path, headers: headers, params: %{q: c["query"], start: 1, end: 1}).body == %{"tagValues" => []}
  end

  defp assert_discovery_value_wire(ctx, c, version, headers) do
    prefix = if version == 1, do: "/api", else: "/api/v2"
    target = c["target"] || ".#{c["key"]}"
    path = ctx.url <> prefix <> "/search/tag/#{target}/values"
    response = Req.get!(path, headers: headers, params: %{q: c["query"]})

    if c["expected_error"] do
      status = if c["expected_error"] in ["trace_root_unknown", "trace_root_conflict"], do: 409, else: 422
      assert response.status == status
    else
      expected = discovery_values_body(c["complete"], version)
      assert response.status == 200 and response.body == expected
      proto = Req.get!(path, headers: [{"accept", "application/protobuf"} | headers], params: %{q: c["query"]})

      assert proto.status == 200 and
               proto.body == Protobuf.encode(expected, if(version == 1, do: :tag_values, else: :tag_values_v2))
    end
  end

  defp discovery_values_body(body, 2), do: body

  defp discovery_values_body(body, 1),
    do: %{"tagValues" => body["tagValues"] |> Enum.map(&Map.get(&1, "value", "")) |> Enum.uniq() |> Enum.sort()}

  @tag timeout: 120_000
  test "complete retained roots survive gzip, split sources, restart, both wires and exact parent windows", ctx do
    dir = Path.expand("../../fixtures/traces", __DIR__)
    headers = [{"authorization", "Bearer #{ctx.token}"}, {"x-scope-orgid", ctx.tenant}]
    wire = File.read!(Path.join(dir, "tempo-roots-input.protobuf"))
    batches = wire_batches(wire)

    for batch <- batches do
      assert Req.post!(ctx.url <> "/v1/traces",
               headers: [{"content-type", "application/x-protobuf"}, {"content-encoding", "gzip"} | headers],
               body: :zlib.gzip(batch)
             ).status == 200
    end

    assert Agent.get(ctx.store, fn state -> Enum.count(Map.keys(state.objects), &String.ends_with?(&1, ".parquet")) end) ==
             length(batches)

    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)
    cases = Pulse.JSON.decode!(File.read!(Path.join(dir, "tempo-roots-oracle.json")))
    for c <- cases, version <- [1, 2], do: assert_discovery_value_wire(ctx, c, version, headers)
    q = ~s({resource.service.name="worker" && span.case="normal"})

    for key <- ~w(rootName trace:rootName rootServiceName trace:rootService) do
      expected = %{
        "tagValues" => [
          %{"type" => "string", "value" => if(key in ~w(rootName trace:rootName), do: "GET /api", else: "gateway")}
        ]
      }

      path = ctx.url <> "/api/v2/search/tag/#{key}/values"
      response = Req.get!(path, headers: headers, params: %{q: q, start: 20, end: 20})
      assert response.status == 200 and response.body == expected

      assert Req.Response.get_header(response, "x-pulse-trace-coverage") == [
               "complete-retained-trace-roots; exporter-completeness-unknown"
             ]

      assert Req.Response.get_header(response, "x-pulse-trace-discovery-window") == [
               "retained-source-candidates-with-complete-trace-context; not-trace-time-filter"
             ]

      proto =
        Req.get!(path, headers: [{"accept", "application/protobuf"} | headers], params: %{q: q, start: 20, end: 20})

      assert proto.status == 200 and proto.body == Protobuf.encode(expected, :tag_values_v2)

      result =
        mcp(ctx, "tools/call", %{
          "name" => "discover_trace_tag_values",
          "arguments" => %{
            "tenant" => ctx.tenant,
            "scope" => "intrinsic",
            "key" => key,
            "query" => q,
            "start_ts_ns" => 20_000_000_000,
            "end_ts_ns" => 20_000_000_000
          }
        })

      refute result.body["result"]["isError"]
      assert Pulse.JSON.decode!(hd(result.body["result"]["content"])["text"]) == expected
      assert Req.get!(path, headers: [{"authorization", "Bearer wrong"}]).status == 401
      # This broad filter now parses, but the corpus includes unprovable roots.
      assert Req.get!(path, headers: headers, params: %{q: "{trace:rootName=\"GET /api\"}"}).status == 409
    end
  end

  @tag timeout: 120_000
  test "trace duration keeps upstream integer/filtered duration types across gzip, six S3 sources and restart", ctx do
    dir = Path.expand("../../fixtures/traces", __DIR__)
    headers = [{"authorization", "Bearer #{ctx.token}"}, {"x-scope-orgid", ctx.tenant}]
    wire = File.read!(Path.join(dir, "tempo-trace-durations-input.protobuf"))

    for batch <- wire |> wire_batches() |> Enum.chunk_every(95) do
      assert Req.post!(ctx.url <> "/v1/traces",
               headers: [{"content-type", "application/x-protobuf"}, {"content-encoding", "gzip"} | headers],
               body: :zlib.gzip(IO.iodata_to_binary(batch))
             ).status == 200
    end

    assert Agent.get(ctx.store, fn state -> Enum.count(Map.keys(state.objects), &String.ends_with?(&1, ".parquet")) end) ==
             6

    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)
    cases = Pulse.JSON.decode!(File.read!(Path.join(dir, "tempo-trace-durations-oracle.json")))
    for c <- cases, version <- [1, 2], do: assert_discovery_value_wire(ctx, c, version, headers)
    c = Enum.find(cases, &(&1["query"] == ~s({resource.service.name="worker"})))

    response =
      mcp(ctx, "tools/call", %{
        "name" => "discover_trace_tag_values",
        "arguments" => %{
          "tenant" => ctx.tenant,
          "scope" => "intrinsic",
          "key" => "trace:duration",
          "query" => c["query"],
          "start_ts_ns" => 20_000_000_000,
          "end_ts_ns" => 20_000_000_000
        }
      })

    refute response.body["result"]["isError"]
    assert Pulse.JSON.decode!(hd(response.body["result"]["content"])["text"]) == c["complete"]
    path = ctx.url <> "/api/v2/search/tag/trace:duration/values"
    assert Req.get!(path, headers: headers, params: %{q: c["query"], start: 20, end: 20}).body == c["complete"]
    assert Req.get!(path, headers: [{"authorization", "Bearer wrong"}]).status == 401

    filtered = Req.get!(path, headers: headers, params: %{q: "{trace:duration>1s}"})
    assert filtered.status == 200

    assert filtered.body == %{
             "tagValues" =>
               Enum.map(
                 [
                   "1.000000001s",
                   "19.0000001s",
                   "2501h59m59.254740991s",
                   "2501h59m59.254740992s",
                   "2501h59m59.254740993s",
                   "2562047h47m16.854775806s"
                 ],
                 &%{"type" => "duration", "value" => &1}
               )
           }
  end

  test "trace duration replays out-of-window context once without requiring roots", ctx do
    headers = [{"authorization", "Bearer #{ctx.token}"}, {"x-scope-orgid", ctx.tenant}]

    [first, second | _] =
      File.read!(Path.expand("../../fixtures/traces/tempo-trace-durations-input.protobuf", __DIR__)) |> wire_batches()

    for batch <- [first, second] do
      assert Req.post!(ctx.url <> "/v1/traces",
               headers: [{"content-type", "application/x-protobuf"} | headers],
               body: batch
             ).status == 200
    end

    path = ctx.url <> "/api/v2/search/tag/trace:duration/values"
    before = Agent.get(ctx.store, fn state -> Enum.count(state.reads, &String.ends_with?(&1, ".parquet")) end)
    response = Req.get!(path, headers: headers, params: %{q: ~s({resource.service.name="worker"}), start: 20, end: 20})

    assert response.status == 200 and
             response.body == %{"tagValues" => [%{"type" => "duration", "value" => "19.0000001s"}]}

    after_reads = Agent.get(ctx.store, fn state -> Enum.count(state.reads, &String.ends_with?(&1, ".parquet")) end)
    assert after_reads - before == 2

    assert Req.Response.get_header(response, "x-pulse-trace-coverage") == [
             "complete-retained-trace-duration; exporter-completeness-unknown"
           ]

    assert Req.Response.get_header(response, "x-pulse-trace-discovery-window") == [
             "retained-source-candidates-with-complete-trace-context; not-trace-time-filter"
           ]

    assert Req.get!(path, headers: headers, params: %{start: 20, end: 20}).body == %{
             "tagValues" => [%{"type" => "int", "value" => "19000000100"}]
           }
  end

  test "stored event-time offsets keep integer wire values through four S3 sources, restart and parent filters", ctx do
    dir = Path.expand("../../fixtures/traces", __DIR__)
    headers = [{"authorization", "Bearer #{ctx.token}"}, {"x-scope-orgid", ctx.tenant}]
    wire = File.read!(Path.join(dir, "tempo-event-times-input.protobuf"))

    for batch <- wire |> wire_batches() |> Enum.chunk_every(70) do
      response =
        Req.post!(ctx.url <> "/v1/traces",
          headers: [{"content-type", "application/x-protobuf"}, {"content-encoding", "gzip"} | headers],
          body: :zlib.gzip(IO.iodata_to_binary(batch))
        )

      assert response.status == 200
    end

    assert Agent.get(ctx.store, fn state -> Enum.count(Map.keys(state.objects), &String.ends_with?(&1, ".parquet")) end) ==
             4

    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)
    cases = Pulse.JSON.decode!(File.read!(Path.join(dir, "tempo-event-times-oracle.json")))
    for c <- cases, version <- [1, 2], do: assert_discovery_value_wire(ctx, c, version, headers)
    c = Enum.find(cases, &(&1["query"] == ~s'{resource.service.name="worker"}'))

    response =
      mcp(ctx, "tools/call", %{
        "name" => "discover_trace_tag_values",
        "arguments" => %{
          "tenant" => ctx.tenant,
          "scope" => "intrinsic",
          "key" => "event:timeSinceStart",
          "query" => c["query"],
          "start_ts_ns" => 1,
          "end_ts_ns" => 1
        }
      })

    refute response.body["result"]["isError"]
    assert Pulse.JSON.decode!(hd(response.body["result"]["content"])["text"]) == c["complete"]
    path = ctx.url <> "/api/v2/search/tag/event:timeSinceStart/values"
    response = Req.get!(path, headers: headers, params: %{q: c["query"], start: 1, end: 1})
    assert response.status == 200 and response.body == c["complete"]

    assert Req.Response.get_header(response, "x-pulse-trace-coverage") == [
             "stored-intrinsic-values; exporter-completeness-unknown"
           ]

    filtered = Req.get!(path, headers: headers, params: %{q: "{event:timeSinceStart>0ns}"})
    assert filtered.status == 200
    # Every event-bearing parent has a +1ns event except the minimum-offset
    # boundary parent, whose retained events are only the negative offset and 0.
    all = Enum.find(cases, &(&1["query"] == "{}"))["complete"]["tagValues"]
    assert filtered.body == %{"tagValues" => Enum.reject(all, &(&1["value"] == "-9223372036854775807"))}
    assert Req.get!(path, headers: [{"authorization", "Bearer wrong"}]).status == 401
  end

  test "discovery HTTP seconds include the final whole second while MCP nanosecond windows remain exact", ctx do
    wire = File.read!(Path.expand("../../fixtures/traces/tempo-windowed-subsecond-input.protobuf", __DIR__))
    headers = [{"authorization", "Bearer #{ctx.token}"}, {"x-scope-orgid", ctx.tenant}]

    assert Req.post!(ctx.url <> "/v1/traces",
             headers: [{"content-type", "application/x-protobuf"} | headers],
             body: wire
           ).status == 200

    cases =
      File.read!(Path.expand("../../fixtures/traces/tempo-windowed-subsecond-oracle.json", __DIR__))
      |> Pulse.JSON.decode!()

    for c <- cases, version <- [1, 2] do
      path = if version == 1, do: "/api/search/tag/name/values", else: "/api/v2/search/tag/name/values"
      values = Map.get(c["response"], "tagValues", [])
      expected = %{"tagValues" => if(version == 1, do: Enum.map(values, & &1["value"]), else: values)}
      params = %{start: c["start"], end: c["end"]}
      response = Req.get!(ctx.url <> path, headers: headers, params: params)
      assert response.status == 200 and response.body == expected
      response = Req.get!(ctx.url <> path, headers: [{"accept", "application/protobuf"} | headers], params: params)

      assert response.status == 200 and
               response.body == Protobuf.encode(expected, if(version == 1, do: :tag_values, else: :tag_values_v2))
    end

    for {start, finish, values} <- [
          {20_000_000_000, 20_000_000_000, []},
          {20_000_000_000, 20_999_999_999, ["fractional"]},
          {20_950_000_000, 20_999_999_999, []}
        ] do
      response =
        mcp(ctx, "tools/call", %{
          "name" => "discover_trace_tag_values",
          "arguments" => %{
            "tenant" => ctx.tenant,
            "scope" => "intrinsic",
            "key" => "name",
            "start_ts_ns" => start,
            "end_ts_ns" => finish
          }
        })

      refute response.body["result"]["isError"]

      assert Pulse.JSON.decode!(hd(response.body["result"]["content"])["text"]) == %{
               "tagValues" => Enum.map(values, &%{"type" => "string", "value" => &1})
             }
    end
  end

  test "time discovery selects whole immutable object envelopes, including gaps and outside-window parents", ctx do
    assert_windowed_discovery(ctx, false)
  end

  test "separate objects preserve segment-granularity time discovery instead of inferring one global envelope", ctx do
    assert_windowed_discovery(ctx, true)
  end

  defp assert_windowed_discovery(ctx, split) do
    wire = File.read!(Path.expand("../../fixtures/traces/tempo-windowed-discovery-input.protobuf", __DIR__))
    headers = [{"authorization", "Bearer #{ctx.token}"}, {"x-scope-orgid", ctx.tenant}]
    bodies = if split, do: wire_batches(wire), else: [wire]

    for body <- bodies do
      assert Req.post!(ctx.url <> "/v1/traces",
               headers: [{"content-type", "application/x-protobuf"} | headers],
               body: body
             ).status == 200
    end

    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)

    for {start, finish, values} <- window_cases(split) do
      assert_window_versions(ctx, headers, start, finish, values)

      response =
        mcp(ctx, "tools/call", %{
          "name" => "discover_trace_tag_values",
          "arguments" => %{
            "tenant" => ctx.tenant,
            "scope" => "intrinsic",
            "key" => "name",
            "start_ts_ns" => start * 1_000_000_000,
            "end_ts_ns" => finish * 1_000_000_000
          }
        })

      refute response.body["result"]["isError"]

      assert Pulse.JSON.decode!(hd(response.body["result"]["content"])["text"]) == %{
               "tagValues" => Enum.map(values, &%{"type" => "string", "value" => &1})
             }
    end

    assert Req.get!(ctx.url <> "/api/v2/search/tags", headers: headers, params: %{start: 22, end: 23}).body == %{
             "scopes" => [%{"name" => "intrinsic", "tags" => TempoIntrinsics.names()}]
           }

    assert Req.get!(ctx.url <> "/api/search/tags", headers: headers, params: %{start: 22, end: 23}).body == %{
             "tagNames" => []
           }

    for params <- [
          %{start: 10},
          %{end: 20},
          %{start: 0, end: 20},
          %{start: 21, end: 20},
          %{start: "+10", end: 20},
          %{start: 10, end: "20.1"},
          %{start: 10, end: "4294967296"}
        ] do
      assert Req.get!(ctx.url <> "/api/v2/search/tag/name/values", headers: headers, params: params).status == 400
    end

    assert Req.get!(ctx.url <> "/api/v2/search/tag/name/values",
             headers: [{"authorization", "Bearer wrong"}, {"x-scope-orgid", ctx.tenant}],
             params: %{start: 10, end: 20}
           ).status == 401

    static = Req.get!(ctx.url <> "/api/v2/search/tag/kind/values", headers: headers, params: %{start: 22, end: 23})
    assert static.status == 200 and length(static.body["tagValues"]) == 6
    assert static.headers["x-pulse-trace-discovery-window"] == ["static-protocol-vocabulary; window-independent"]

    if !split do
      body = %{
        "resourceSpans" => [
          %{
            "scopeSpans" => [
              %{
                "spans" => [
                  %{
                    "traceId" => String.duplicate("3", 32),
                    "spanId" => String.duplicate("4", 16),
                    "name" => "long",
                    "startTimeUnixNano" => "10000000000",
                    "endTimeUnixNano" => "100000000000"
                  }
                ]
              }
            ]
          }
        ]
      }

      assert Req.post!(ctx.url <> "/v1/traces", headers: headers, json: body).status == 200
      response = Req.get!(ctx.url <> "/api/v2/search/tag/name/values", headers: headers, params: %{start: 90, end: 91})
      assert response.status == 200 and response.body == %{"tagValues" => [%{"type" => "string", "value" => "long"}]}
    end
  end

  defp window_cases(false),
    do: [{9, 9, []}, {9, 10, ["early", "late"]}, {15, 16, ["early", "late"]}, {21, 21, ["early", "late"]}, {22, 23, []}]

  defp window_cases(true), do: [{9, 9, []}, {9, 10, ["early"]}, {15, 16, []}, {21, 21, ["late"]}, {22, 23, []}]

  defp assert_window_versions(ctx, headers, start, finish, values) do
    for version <- [1, 2] do
      path = if version == 1, do: "/api/search/tag/name/values", else: "/api/v2/search/tag/name/values"

      expected = %{
        "tagValues" => if(version == 1, do: values, else: Enum.map(values, &%{"type" => "string", "value" => &1}))
      }

      response = Req.get!(ctx.url <> path, headers: headers, params: %{start: start, end: finish})
      assert response.status == 200 and response.body == expected

      assert response.headers["x-pulse-trace-discovery-window"] == [
               "retention-visible-segment-envelope; not-span-time-filter"
             ]

      response =
        Req.get!(ctx.url <> path,
          headers: [{"accept", "application/protobuf"} | headers],
          params: %{start: start, end: finish}
        )

      assert response.status == 200 and
               response.body == Protobuf.encode(expected, if(version == 1, do: :tag_values, else: :tag_values_v2))
    end
  end

  test "Tempo HTTP search preserves complete retained context, overlap and most-recent before limits with opt-in/auth",
       ctx do
    wire = File.read!(Path.expand("../../fixtures/traces/tempo-search-input.protobuf", __DIR__))
    headers = [{"authorization", "Bearer #{ctx.token}"}, {"x-scope-orgid", ctx.tenant}]

    # Each independently-produced ResourceSpans message becomes its own object,
    # including roots and matches entirely outside the search window.
    for batch <- wire_batches(wire) do
      assert Req.post!(ctx.url <> "/v1/traces",
               headers: [{"content-type", "application/x-protobuf"} | headers],
               body: batch
             ).status == 200
    end

    cases = File.read!(Path.expand("../../fixtures/traces/tempo-search-oracle.json", __DIR__)) |> Pulse.JSON.decode!()
    c = Enum.find(cases, &(&1["name"] == "most-recent-before-limit"))
    params = %{q: c["query"], start: "30", end: "40", limit: "1", spss: "1"}
    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)
    response = Req.get!(ctx.url <> "/api/search", headers: headers, params: params)
    assert response.status == 200
    assert response.body == c["response"]
    full = Req.get!(ctx.url <> "/api/search", headers: headers, params: %{params | limit: "100", spss: "3"})
    expected = Enum.find(cases, &(&1["name"] == "overlap-and-outside-match"))["response"]
    assert MapSet.new(full.body["traces"]) == MapSet.new(expected["traces"])
    proto = Req.get!(ctx.url <> "/api/search", headers: [{"accept", "application/protobuf"} | headers], params: params)
    assert proto.status == 200
    assert is_binary(proto.body) and byte_size(proto.body) > 0

    assert Req.get!(ctx.url <> "/api/search",
             headers: [{"authorization", "Bearer wrong"}, {"x-scope-orgid", ctx.tenant}],
             params: params
           ).status == 401

    for bad <- [
          %{params | start: "41"},
          %{params | q: ~s'{resource.service.name="worker"} with (most_recent=false)'},
          Map.put(params, :tags, "x=y"),
          %{params | spss: "101"},
          %{params | limit: "0"},
          %{params | start: "0"}
        ] do
      assert Req.get!(ctx.url <> "/api/search", headers: headers, params: bad).status == 400
    end

    Runtime.put_env(:pulse, TempoSearch, enabled: false)

    disabled =
      start_supervised!(
        {Bandit, plug: {RuntimePlug, plug: PulseWeb.Endpoint, runtime: Runtime.current()}, ip: {127, 0, 0, 1}, port: 0},
        id: :disabled_tempo_search
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(disabled)
    assert Req.get!("http://127.0.0.1:#{port}/api/search", headers: headers, params: params).status == 501
  end

  test "Tempo v1 HTTP lookup returns independent JSON/protobuf, honors auth, deduplicates retries and never filters by shard hints",
       ctx do
    wire = File.read!(Path.expand("../../fixtures/otlp/protoc-trace-values.protobuf", __DIR__))

    response =
      Req.post!(ctx.url <> "/v1/traces",
        headers: [
          {"authorization", "Bearer #{ctx.token}"},
          {"x-scope-orgid", ctx.tenant},
          {"content-type", "application/x-protobuf"}
        ],
        body: wire
      )

    assert response.status == 200

    response =
      Req.post!(ctx.url <> "/v1/traces",
        headers: [
          {"authorization", "Bearer #{ctx.token}"},
          {"x-scope-orgid", ctx.tenant},
          {"content-type", "application/x-protobuf"}
        ],
        body: wire
      )

    assert response.status == 200
    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)
    id = "30313233343536373839616263646566"
    headers = [{"authorization", "Bearer #{ctx.token}"}, {"x-scope-orgid", ctx.tenant}]

    response =
      Req.get!(ctx.url <> "/api/traces/" <> String.upcase(id),
        headers: [{"accept", "application/protobuf"} | headers],
        params: %{start: "1", end: "2", mode: "all", allowPartialTrace: "false"}
      )

    assert response.status == 200
    assert response.body == File.read!(Path.expand("../../fixtures/traces/tempo-v1-stored-trace.protobuf", __DIR__))
    assert Req.Response.get_header(response, "content-type") |> hd() =~ "application/protobuf"
    response = Req.get!(ctx.url <> "/api/traces/" <> id, headers: [{"accept", "application/json"} | headers])
    assert response.status == 200
    fixture = File.read!(Path.expand("../../fixtures/traces/tempo-v1-stored-trace.json", __DIR__)) |> JSON.decode!()
    assert response.body == fixture
    v2 = Req.get!(ctx.url <> "/api/v2/traces/" <> id, headers: [{"accept", "application/protobuf"} | headers])
    assert v2.status == 200
    assert v2.body == File.read!(Path.expand("../../fixtures/traces/tempo-v2-stored-trace.protobuf", __DIR__))
    v2 = Req.get!(ctx.url <> "/api/v2/traces/" <> id, headers: [{"accept", "application/json"} | headers])
    assert v2.status == 200
    assert v2.body == %{"trace" => %{"resourceSpans" => fixture["batches"]}}

    assert Req.get!(ctx.url <> "/api/traces/" <> id,
             headers: [{"authorization", "Bearer wrong"}, {"x-scope-orgid", ctx.tenant}]
           ).status == 401

    assert Req.get!(ctx.url <> "/api/traces/" <> id,
             headers: [{"authorization", "Bearer #{ctx.token}"}, {"x-scope-orgid", "other"}]
           ).status == 401

    assert Req.get!(ctx.url <> "/api/traces/" <> String.duplicate("f", 32), headers: headers).status == 404

    for params <- [
          %{allowPartialTrace: "true"},
          %{mode: "ingesters"},
          %{blockStart: "x"},
          %{end: "4294967296"},
          %{start: "2", end: "1"},
          %{start: "1.5"}
        ] do
      assert Req.get!(ctx.url <> "/api/traces/" <> id, headers: headers, params: params).status == 400
    end

    assert Req.get!(ctx.url <> "/api/traces/invalid", headers: headers).status == 400
    assert Req.get!(ctx.url <> "/api/traces/" <> id, headers: [{"accept", "text/html"} | headers]).status == 406
    Runtime.put_env(:pulse, Pulse.QueryRunner, max_scan_rows: 1)
    # Endpoint dependencies are immutable snapshots; inject the limited context
    # into a separately owned listener, not the already-running server.
    limited =
      start_supervised!(
        {Bandit, plug: {RuntimePlug, plug: PulseWeb.Endpoint, runtime: Runtime.current()}, ip: {127, 0, 0, 1}, port: 0},
        id: :limited_trace_api_server
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(limited)
    assert Req.get!("http://127.0.0.1:#{port}/api/traces/" <> id, headers: headers).status == 422
  end

  test "public OTLP to native trace-level selector search remains tenant-authorized after cache restart", ctx do
    raw = Fixture.span(10)
    other = Fixture.span(20) |> Map.put("traceId", Base.encode16(<<2::128>>, case: :lower))

    response =
      Req.post!(ctx.url <> "/v1/traces",
        headers: [{"authorization", "Bearer #{ctx.token}"}, {"x-scope-orgid", ctx.tenant}],
        json: Fixture.payload([raw, raw, other])
      )

    assert response.status == 200
    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)

    args = %{
      "tenant" => ctx.tenant,
      "query" =>
        ~s'{resource.service.namespace="tuist" && resource.service.name="tuist-server" && resource.deployment.environment=~"production"} with (most_recent=true)',
      "start_ts_ns" => 0,
      "end_ts_ns" => 30,
      "limit" => 1
    }

    response = mcp(ctx, "tools/call", %{"name" => "search_traces", "arguments" => args})
    assert response.status == 200
    refute response.body["result"]["isError"]
    result = Pulse.JSON.decode!(hd(response.body["result"]["content"])["text"])
    assert result["matched_trace_count"] == 2
    assert [%{"trace_id" => trace, "stored_span_count" => 1}] = result["traces"]
    assert trace == other["traceId"]
    denied = mcp(ctx, "tools/call", %{"name" => "search_traces", "arguments" => args}, "wrong")
    assert denied.body["result"]["isError"]
    assert hd(denied.body["result"]["content"])["text"] =~ "unauthorized"
    forbidden = mcp(ctx, "tools/call", %{"name" => "search_traces", "arguments" => Map.put(args, "tenant", "other")})
    assert forbidden.body["result"]["isError"]
  end

  test "independent protobuf typed values survive gzip, keyed retry, cache restart and MCP assembly", ctx do
    wire = File.read!(Path.expand("../../fixtures/otlp/protoc-trace-values.protobuf", __DIR__))

    headers = [
      {"authorization", "Bearer #{ctx.token}"},
      {"x-scope-orgid", ctx.tenant},
      {"idempotency-key", "typed-fixture"},
      {"content-type", "application/x-protobuf"},
      {"content-encoding", "gzip"}
    ]

    for _ <- 1..2,
        do: assert(Req.post!(ctx.url <> "/v1/traces", headers: headers, body: :zlib.gzip(wire)).status == 200)

    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)
    [span] = query(ctx, %{"trace_id" => "30313233343536373839616263646566"})
    attrs = Map.new(span["otlp"]["attributes"], &{&1["key"], &1["value"]})
    assert attrs["blob"] == %{"bytesValue" => "AP8="}
    assert attrs["text"] == %{"stringValue" => "AP8="}
    assert attrs["minimum"] == %{"intValue" => "-9223372036854775808"}
    assert <<128, 0, 0, 0, 0, 0, 0, 0>> == <<attrs["negative_zero"]["doubleValue"]::float-64>>
    assert query(ctx, %{"fields" => ["otlp"]}) == [%{"otlp" => span["otlp"]}]

    response =
      mcp(ctx, "tools/call", %{
        "name" => "get_trace",
        "arguments" => %{"tenant" => ctx.tenant, "trace_id" => span["trace_id"]}
      })

    refute response.body["result"]["isError"]
    [%{"text" => text}] = response.body["result"]["content"]
    assert Pulse.JSON.decode!(text)["spans"] == [span]
  end

  test "nonfinite trace values survive both gzip transports, keyed retry, restart, MCP and Tempo lookup", ctx do
    wire = File.read!(Path.expand("../../fixtures/traces/tempo-nonfinite-input.protobuf", __DIR__))
    limits = Pulse.IngestLimits.config()

    native =
      {limits.max_records, limits.max_attributes, limits.max_key_bytes, limits.max_value_bytes,
       limits.max_attribute_bytes, limits.max_depth, limits.max_nodes, limits.max_trace_nodes}

    assert {:ok, payload} = NIF.decode_otlp_traces(wire, native)
    auth = [{"authorization", "Bearer #{ctx.token}"}, {"x-scope-orgid", ctx.tenant}]

    for {type, body} <- [{"application/x-protobuf", wire}, {"application/json", Pulse.JSON.encode!(payload)}] do
      headers = auth ++ [{"idempotency-key", "nonfinite-fixture"}, {"content-type", type}, {"content-encoding", "gzip"}]
      assert Req.post!(ctx.url <> "/v1/traces", headers: headers, body: :zlib.gzip(body), retry: false).status == 200
    end

    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)
    trace_id = "00000000000000000000000000000001"
    spans = query(ctx, %{"trace_id" => trace_id})
    assert length(spans) == 6

    assert Enum.any?(spans, fn span ->
             Enum.any?(span["otlp"]["attributes"], &(&1["value"] == %{"doubleValue" => "NaN"}))
           end)

    response =
      mcp(ctx, "tools/call", %{"name" => "get_trace", "arguments" => %{"tenant" => ctx.tenant, "trace_id" => trace_id}})

    refute response.body["result"]["isError"]
    [%{"text" => text}] = response.body["result"]["content"]
    assert Pulse.JSON.decode!(text)["span_count"] == 6
    assert Pulse.JSON.decode!(text)["conflicting_span_ids"] == []
    result = Req.get!(ctx.url <> "/api/traces/" <> trace_id, headers: auth ++ [{"accept", "application/protobuf"}])
    assert result.status == 200
    assert {:ok, exported, 0} = Traces.decode_protobuf(result.body)
    assert length(exported) == 6
    result = Req.get!(ctx.url <> "/api/v2/search/tag/span.value/values", headers: auth)
    assert result.status == 200
    assert %{"type" => "float", "value" => "NaN.0"} in result.body["tagValues"]
    assert %{"type" => "float", "value" => "+Inf.0"} in result.body["tagValues"]
    assert Req.get!(ctx.url <> "/api/traces/" <> trace_id).status == 401
  end

  test "JSON integer-spelled negative zero remains an OTLP double, not a general JSON change", ctx do
    attrs = [
      %{"key" => "zero", "value" => %{"doubleValue" => -0.0}},
      %{"key" => "integer", "value" => %{"intValue" => 0}}
    ]

    payload = Fixture.payload([Map.put(Fixture.span(), "attributes", attrs)])
    json = payload |> Pulse.JSON.encode!() |> String.replace("-0.0", "-0")

    response =
      Req.post!(ctx.url <> "/v1/traces",
        headers: [
          {"authorization", "Bearer #{ctx.token}"},
          {"x-scope-orgid", ctx.tenant},
          {"content-type", "application/json"}
        ],
        body: json
      )

    assert response.status == 200
    [span] = query(ctx, %{})
    values = Map.new(span["otlp"]["attributes"], &{&1["key"], &1["value"]})
    assert <<128, 0, 0, 0, 0, 0, 0, 0>> == <<values["zero"]["doubleValue"]::float-64>>
    assert values["integer"] == %{"intValue" => "0"}
    assert Pulse.JSON.decode!("-0") === 0
  end

  test "a keyed batch with rejected span metadata never acknowledges a valid subset", ctx do
    empty_key = [%{"key" => "", "value" => %{"stringValue" => "a"}}]
    payload = Fixture.payload([Fixture.span(), Map.put(Fixture.span(), "attributes", empty_key)])
    before = Agent.get(ctx.store, & &1.objects)

    headers = [
      {"authorization", "Bearer #{ctx.token}"},
      {"x-scope-orgid", ctx.tenant},
      {"idempotency-key", "no-subset"}
    ]

    response = Req.post!(ctx.url <> "/v1/traces", headers: headers, json: payload)
    assert response.status == 400
    assert Agent.get(ctx.store, & &1.objects) == before
    assert query(ctx, %{}) == []

    response =
      Req.post!(ctx.url <> "/v1/traces",
        headers: Enum.reject(headers, fn {key, _} -> key == "idempotency-key" end),
        json: payload
      )

    assert response.status == 200
    assert response.body["partialSuccess"]["rejectedSpans"] == "1"
    assert length(query(ctx, %{})) == 1
  end

  test "OTLP HTTP ingestion is queryable over public MCP using S3, even after losing all manifest caches", ctx do
    discovery = mcp(ctx, "tools/list", %{})
    assert discovery.status == 200
    assert Enum.any?(discovery.body["result"]["tools"], &(&1["name"] == "query_traces"))

    # Exercise the actual HTTP listener, Rust S3 client and Parquet codec,
    # conditional manifest publication, auth, MCP headers, and query runner.
    # The S3 test double replaces only the remote provider, never signal storage.
    headers = [
      {"authorization", "Bearer #{ctx.token}"},
      {"x-scope-orgid", ctx.tenant},
      {"idempotency-key", "protobuf-retry"},
      {"content-type", "application/x-protobuf"},
      {"content-encoding", "gzip"}
    ]

    payload = :zlib.gzip(Fixture.protobuf())

    for _ <- 1..2 do
      response = Req.post!(ctx.url <> "/v1/traces", headers: headers, body: payload)
      assert response.status == 200
      assert response.body == ""
    end

    [span] = query(ctx, %{"trace_id" => String.upcase(Fixture.trace_id())})
    assert span["service"] == "tuist-server"
    assert span["span_id"] == Fixture.span_id()
    assert span["attributes"]["metrics.skip"] == false
    assert span["attributes"]["negative"] == -42
    assert [%{"name" => "exception"}] = span["events"]
    assert [%{"flags" => 1}] = span["links"]

    # A separate JSON request publishes another segment in the same trace.
    raw =
      Fixture.span(1_700_000_000_123_458_000)
      |> Map.put("spanId", String.duplicate("a", 16))
      |> Map.put("name", "database.query")
      |> Map.put("kind", 3)

    response =
      Req.post!(ctx.url <> "/v1/traces",
        headers: [{"authorization", "Bearer #{ctx.token}"}, {"x-scope-orgid", ctx.tenant}],
        json: Fixture.payload([raw])
      )

    assert response.status == 200
    assert response.body == %{}

    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)
    results = query(ctx, %{"trace_id" => Fixture.trace_id()})
    assert Enum.map(results, & &1["name"]) == ["database.query", "GET /api/builds"]
    assert query(ctx, %{"resource_regex" => %{"deployment.environment" => "production|staging"}}) == results
    assert query(ctx, %{"resource_regex" => %{"deployment.environment" => "prod"}}) == []
    assert Enum.map(results, & &1["timestamp_ns"]) == [1_700_000_000_123_458_000, 1_700_000_000_123_456_789]

    assert query(ctx, %{"trace_id" => Fixture.trace_id(), "fields" => List.duplicate("name", 64)}) ==
             Enum.map(results, &Map.take(&1, ["name"]))

    assembled =
      mcp(ctx, "tools/call", %{
        "name" => "get_trace",
        "arguments" => %{"tenant" => ctx.tenant, "trace_id" => Fixture.trace_id()}
      })

    assert assembled.status == 200
    refute assembled.body["result"]["isError"]
    [%{"text" => text}] = assembled.body["result"]["content"]
    trace = Pulse.JSON.decode!(text)
    assert trace["coverage"] == "all_stored_spans"
    assert trace["span_count"] == 2
    assert trace["spans"] == results
    assert trace["duplicate_span_ids"] == []

    assert [span] ==
             query(ctx, %{
               "span_id" => Fixture.span_id(),
               "service" => "tuist-server",
               "kind" => 2,
               "status_code" => 2,
               "attributes" => %{
                 "auth_account_handle" => "acme",
                 "http.response.status_code" => 500,
                 "metrics.skip" => false
               },
               "resource" => %{"deployment.environment" => "production"}
             })

    assert [span] == query(ctx, %{"start_ts_ns" => span["timestamp_ns"], "end_ts_ns" => span["timestamp_ns"]})
    assert [%{"name" => "database.query"}] = query(ctx, %{"limit" => 1})
    assert [] == query(ctx, %{"service" => "unrelated"})
    assert [] == query(ctx, %{"attributes" => %{"http.response.status_code" => "500"}})

    denied = mcp(ctx, "tools/call", %{"name" => "query_traces", "arguments" => %{"tenant" => ctx.tenant}}, "wrong")
    assert denied.body["result"]["isError"] == true
    assert hd(denied.body["result"]["content"])["text"] =~ "unauthorized"
    other = mcp(ctx, "tools/call", %{"name" => "query_traces", "arguments" => %{"tenant" => "other"}})
    assert other.body["result"]["isError"] == true
    assert hd(other.body["result"]["content"])["text"] =~ "unauthorized"

    objects = Agent.get(ctx.store, &Map.keys(&1.objects))
    assert Enum.count(objects, &String.ends_with?(&1, ".parquet")) == 2
    assert Enum.any?(objects, &String.ends_with?(&1, "/signal=traces/manifest.json"))
  end
end
