defmodule Pulse.Traces.TempoDefaultNamesTest do
  use Pulse.Test.Case, async: true

  alias Pulse.{Codec.NIF, MCP.Tools, OTLP.Traces, Runtime, Storage}
  alias Pulse.Storage.S3
  alias Pulse.Test.FailingStorage
  alias Pulse.Test.ScopedTraceDiscoveryStorage
  alias Pulse.Traces.{TempoDiscovery, TempoIntrinsics, TempoSearch}

  defp fixture do
    dir = Path.expand("../../fixtures/traces", __DIR__)
    raw = File.read!(Path.join(dir, "tempo-default-names-oracle.json"))

    assert Base.encode16(:crypto.hash(:sha256, raw), case: :lower) ==
             "d72a29397577c847d3abbaffb7b7a2e6f82eb06c2c982713baf7d129392d6287"

    datasets =
      for name <- ~w(promoted generic no-service), into: %{} do
        {:ok, rows, 0} = Traces.decode_protobuf(File.read!(Path.join(dir, "tempo-filtered-names-#{name}.protobuf")))
        {name, rows}
      end

    # Preserve the v2.9 producer bytes and all stored-name expectations. Only
    # its static vocabulary is superseded by the independently pinned v3 list.
    names = File.read!(Path.join(dir, "tempo_integration/intrinsic-names.json")) |> Pulse.JSON.decode!()

    cases =
      for c <- Pulse.JSON.decode!(raw) do
        put_in(c, ["complete", "scopes", Access.filter(&(&1["name"] == "intrinsic")), "tags"], names)
      end

    {datasets, cases}
  end

  defp state(q, floor \\ 0) do
    {:ok, p} = TempoDiscovery.filter("none", "", q)

    if p == [],
      do: NIF.tempo_discovery_new(floor, "none", ""),
      else: NIF.tempo_filtered_discovery_new(floor, "none", "", p)
  end

  defp native(rows, q) do
    {:ok, s} = state(q)
    {:ok, blob, _, _} = S3.encode_segment(:traces, rows)
    with {:ok, _} <- NIF.tempo_discovery_add(s, blob), do: NIF.tempo_discovery_finish(s)
  end

  test "default names preserve scopes and intrinsic suggestions without upstream shared-key omissions" do
    {datasets, cases} = fixture()
    assert length(cases) == 15

    for c <- cases do
      rows = datasets[c["dataset"]]

      for spans <- [rows, Enum.reverse(rows), rows ++ rows] do
        assert {:ok, json} = native(spans, c["query"])
        assert Pulse.JSON.decode!(json) == c["complete"], inspect(c)
        assert {:ok, ref} = TempoDiscovery.json(spans, "none", "", discovery_query: c["query"])
        assert Pulse.JSON.decode!(ref) == c["complete"], inspect(c)
      end

      {:ok, s} = state(c["query"])

      for row <- rows do
        {:ok, blob, _, _} = S3.encode_segment(:traces, [row])
        assert {:ok, 1} = NIF.tempo_discovery_add(s, blob)
      end

      assert {:ok, json} = NIF.tempo_discovery_finish(s)
      assert Pulse.JSON.decode!(json) == c["complete"]
      assert :fallback = NIF.tempo_discovery_finish(s)
    end
  end

  test "omitted MCP scope and old scoped adapters use one bounded complete fallback; v1 deduplicates and excludes intrinsics" do
    {datasets, cases} = fixture()
    Runtime.put_env(:pulse, TempoSearch, enabled: true)
    for {name, rows} <- datasets, do: assert(:ok = Storage.append(:traces, name, rows))
    Runtime.put_env(:pulse, Storage, adapter: ScopedTraceDiscoveryStorage)

    for c <- cases do
      for extra <- [%{}, %{"scope" => "none"}] do
        assert {:ok, [%{"text" => json}]} =
                 Tools.call("discover_trace_tags", Map.merge(%{"tenant" => c["dataset"], "query" => c["query"]}, extra))

        assert Pulse.JSON.decode!(json) == c["complete"]
      end

      assert {:ok, json} = TempoDiscovery.query(c["dataset"], "none", "", 1, "json", c["query"])
      assert Pulse.JSON.decode!(json) == c["v1"]
      assert {:ok, wire} = TempoDiscovery.query(c["dataset"], "none", "", 2, "protobuf", c["query"])
      assert byte_size(wire) > 0
    end

    assert {:ok, _} = TempoDiscovery.query("promoted", "none", "shared")
    assert {:error, :unsupported_trace_discovery} = TempoDiscovery.query("promoted", "none", "", 2, "json", "{true}")
    assert {:ok, unscoped} = NIF.tempo_discovery_new(0, "none", "shared")
    assert {:ok, ~s'{"tagValues":[]}'} = NIF.tempo_discovery_finish(unscoped)
  end

  test "empty visible context retains only static v2 suggestions; legacy and corrupt nonmatches never produce partial suggestions" do
    {datasets, _} = fixture()
    {:ok, s} = state("")
    assert {:ok, json} = NIF.tempo_discovery_finish(s)
    assert json == TempoIntrinsics.json("")
    assert {:ok, json} = TempoDiscovery.json([], "none", "", [])
    assert json == TempoIntrinsics.json("")
    [first | _] = datasets["promoted"]

    assert {:error, :trace_metadata_unknown} = native([%{first | otlp: nil}], ~s'{resource.service.name="absent"}')
    {:ok, bad_state} = state(~s'{resource.service.name="absent"}')
    bad_blob = File.read!(Path.expand("../../fixtures/traces/trace-invalid-version.parquet", __DIR__))
    assert :fallback = NIF.tempo_discovery_add(bad_state, bad_blob)
    assert :fallback = NIF.tempo_discovery_finish(bad_state)

    for row <- [%{first | otlp: nil}, %{first | otlp: Map.put(first.otlp, "version", 99)}] do
      assert {:error, _} = TempoDiscovery.json([row], "none", "", discovery_query: ~s'{resource.service.name="absent"}')
    end

    {:ok, s} = state("", first.timestamp_ns + 1)
    {:ok, blob, _, _} = S3.encode_segment(:traces, [first])
    assert {:ok, 1} = NIF.tempo_discovery_add(s, blob)
    assert {:ok, json} = NIF.tempo_discovery_finish(s)
    assert json == TempoIntrinsics.json("")
    assert {:error, :query_scan_limit} = TempoDiscovery.json([first], "none", "", max_scan_rows: 0)
  end

  test "actual frontend and unscoped-value evidence do not authorize a five-scope value union" do
    dir = Path.expand("../../fixtures/traces", __DIR__)

    for {file, hash} <- [
          {"tempo-default-name-handlers-oracle.json",
           "c5b8635054fe6ad5b7af934baa9ed9fee4c6ee7f9a402a8109ae040d811cf3a2"},
          {"produce_tempo_default_name_handlers.go.txt",
           "5a2505157bc1061184926cc7cea0aa75840e0c3bb9d58d9d7238f0c24dfbd363"},
          {"produce_tempo_default_names.go.txt", "02705939ca47ec1a56d0f54c7fcbddb8a4633c5cd819d4dc62ba999bf2e9761f"},
          {"produce_tempo_unscoped_values.go.txt", "433798a57a0b6fc5d1dd21269505f3340b481c486fb8c868b1246656abeb76a5"},
          {"tempo-unscoped-values-oracle.json", "42108f2c413443d6722c041b49b8ac512ba7a576ed4bb3beadeae53f52b8c31d"}
        ] do
      assert Base.encode16(:crypto.hash(:sha256, File.read!(Path.join(dir, file))), case: :lower) == hash
    end

    handlers = Pulse.JSON.decode!(File.read!(Path.join(dir, "tempo-default-name-handlers-oracle.json")))
    assert handlers["cases"] == 90 and handlers["v1_excludes_intrinsics"] and handlers["v2_adds_intrinsics"]
    assert handlers["backend"] == "owned_stub"
    values = Pulse.JSON.decode!(File.read!(Path.join(dir, "tempo-unscoped-values-oracle.json")))
    assert Enum.all?(Enum.filter(values, &(&1["target"] in ["shared", "http.method"])), &(not &1["valid"]))
    shared = Enum.find(values, &(&1["target"] == ".shared" and &1["query"] == ""))
    assert Enum.map(shared["response"]["tagValues"], & &1["value"]) == ~w(instrumentation resource span)
    assert Enum.all?(Enum.filter(values, &(&1["target"] == ".phase")), &(&1["response"]["tagValues"] == []))
    service = Enum.find(values, &(&1["target"] == ".service.name" and &1["query"] != ""))
    assert Enum.map(service["response"]["tagValues"], & &1["value"]) == ~w(frontend worker)
    assert :ok = TempoDiscovery.validate("none", "shared")
  end

  test "default discovery fails whole on storage errors instead of returning only intrinsic suggestions" do
    Runtime.put_env(:pulse, TempoSearch, enabled: true)
    Runtime.put_env(:pulse, Storage, adapter: FailingStorage)
    assert {:error, :storage_unavailable} = TempoDiscovery.query("default", "none", "")
    assert {:ok, _} = TempoDiscovery.query("default", "intrinsic", "")
    Runtime.put_env(:pulse, TempoSearch, enabled: false)
    assert {:error, :tempo_search_disabled} = TempoDiscovery.query("default", "none", "")
  end

  test "default dictionary bound is global across scopes and includes intrinsic reservations" do
    {datasets, _} = fixture()
    base = hd(datasets["generic"])

    rows =
      for n <- 1..5 do
        attrs = for i <- 1..1000, do: %{"key" => "unique_#{n}_#{i}", "value" => %{"stringValue" => "x"}}
        %{base | attributes: Map.new(attrs, &{&1["key"], "x"}), otlp: Map.put(base.otlp, "attributes", attrs)}
      end

    {:ok, s} = state("")

    for row <- Enum.take(rows, 4) do
      {:ok, blob, _, _} = S3.encode_segment(:traces, [row])
      assert {:ok, 1} = NIF.tempo_discovery_add(s, blob)
    end

    {:ok, blob, _, _} = S3.encode_segment(:traces, [List.last(rows)])
    assert {:error, :query_resource_limit} = NIF.tempo_discovery_add(s, blob)
    assert :fallback = NIF.tempo_discovery_finish(s)
    assert {:error, :query_resource_limit} = TempoDiscovery.json(rows, "none", "", [])
  end

  @tag :name_vocabulary
  test "all 25 pinned intrinsic suggestions reserve capacity before filtered or unfiltered stored names" do
    {:ok, [base], 0} =
      Traces.decode(%{
        "resourceSpans" => [
          %{
            "resource" => %{"attributes" => [%{"key" => "service.name", "value" => %{"stringValue" => "bound"}}]},
            "scopeSpans" => [
              %{
                "spans" => [
                  %{
                    "traceId" => String.duplicate("1", 32),
                    "spanId" => String.duplicate("2", 16),
                    "startTimeUnixNano" => "1",
                    "endTimeUnixNano" => "2"
                  }
                ]
              }
            ]
          }
        ]
      })

    Runtime.put_env(:pulse, TempoSearch, enabled: true)

    # 25 static names + one resource service.name hint leave 4,974 span keys.
    # Each source row stays below normal OTLP per-owner attribute admission.
    for count <- [4974, 4975] do
      rows =
        for chunk <- Enum.chunk_every(1..count, 100) do
          attrs = for i <- chunk, do: %{"key" => "key#{i}", "value" => %{"stringValue" => "x"}}
          %{base | attributes: Map.new(attrs, &{&1["key"], "x"}), otlp: Map.put(base.otlp, "attributes", attrs)}
        end

      tenant = "boundary-#{count}"
      assert :ok = Storage.append(:traces, tenant, rows)

      for q <- ["", ~s'{resource.service.name="bound"}'] do
        for result <- [native(rows, q), TempoDiscovery.json(rows, "none", "", discovery_query: q)] do
          if count == 4974 do
            assert {:ok, json} = result
            scopes = Pulse.JSON.decode!(json)["scopes"]
            assert Enum.sum(Enum.map(scopes, &length(&1["tags"]))) == 5000
            assert Enum.find(scopes, &(&1["name"] == "span"))["tags"] == Enum.sort(for i <- 1..4974, do: "key#{i}")
          else
            assert result == {:error, :query_resource_limit}
          end
        end

        if count == 4974 do
          assert {:ok, json} = TempoDiscovery.query(tenant, "none", "", 1, "json", q)
          assert length(Pulse.JSON.decode!(json)["tagNames"]) == 4975
        else
          assert {:error, :query_resource_limit} = TempoDiscovery.query(tenant, "none", "", 1, "json", q)
        end
      end
    end
  end

  test "default names charge all five scope owners and attrs before false filters under one work ceiling" do
    {:ok, rows, 0} =
      Traces.decode_protobuf(File.read!(Path.expand("../../fixtures/traces/tempo-scopes-input.protobuf", __DIR__)))

    base = hd(rows)

    dense = %{
      base
      | events: List.duplicate(Map.put(hd(base.events), "attributes", %{}), 2000),
        otlp: Map.put(base.otlp, "events", List.duplicate([], 2000))
    }

    meta = dense.otlp

    cost =
      3 + length(meta["resource"]) + length(meta["scope"]) + length(meta["attributes"]) +
        Enum.reduce(meta["events"] ++ meta["links"], 0, &(1 + length(&1) + &2))

    rounds = div(2_000_000, cost)
    q = ~s'{resource.service.name="absent"}'
    {:ok, s} = state(q)
    {:ok, blob, _, _} = S3.encode_segment(:traces, [dense])
    for _ <- 1..rounds, do: assert({:ok, 1} = NIF.tempo_discovery_add(s, blob))
    assert {:error, :trace_discovery_work_limit} = NIF.tempo_discovery_add(s, blob)
    assert :fallback = NIF.tempo_discovery_finish(s)

    assert {:error, :trace_discovery_work_limit} =
             TempoDiscovery.json(List.duplicate(dense, rounds + 1), "none", "", discovery_query: q)

    {:ok, scoped} = NIF.tempo_discovery_new(0, "resource", "")
    for _ <- 1..(rounds + 1), do: assert({:ok, 1} = NIF.tempo_discovery_add(scoped, blob))
    assert {:ok, _} = NIF.tempo_discovery_finish(scoped)
  end
end
