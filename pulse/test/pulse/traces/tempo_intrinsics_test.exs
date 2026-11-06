defmodule Pulse.Traces.TempoIntrinsicsTest do
  use Pulse.Test.Case, async: true

  alias Pulse.{MCP.Tools, OTLP.Traces, QueryRunner, Runtime, Storage}
  alias Pulse.Runtime.Task
  alias Pulse.Test.FailingStorage
  alias Pulse.Traces.{TempoDiscovery, TempoSearch}

  defp cases do
    raw = File.read!(Path.expand("../../fixtures/traces/tempo-intrinsics-oracle.json", __DIR__))

    assert Base.encode16(:crypto.hash(:sha256, raw), case: :lower) ==
             "6965837a433969eacc439f6c651a61dcd1ab350f112bd428244d50aab0a4f043"

    # Retain the actual v2.9 oracle, but use the independently frozen v3 names
    # for its vocabulary-only row. The seven value expectations are unchanged.
    names =
      File.read!(Path.expand("../../fixtures/traces/tempo_integration/intrinsic-names.json", __DIR__))
      |> Pulse.JSON.decode!()

    for c <- Pulse.JSON.decode!(raw) do
      if c["key"] == "",
        do: %{c | "response" => %{"scopes" => [%{"name" => "intrinsic", "tags" => names}]}},
        else: c
    end
  end

  test "versioned public vocabulary and seven v2.9 value shortcuts work without a backend" do
    Runtime.put_env(:pulse, TempoSearch, enabled: true)
    Runtime.put_env(:pulse, Storage, adapter: FailingStorage)
    assert length(cases()) == 8

    for c <- cases(), q <- [nil, "", "{}"] do
      assert {:ok, body} = TempoDiscovery.query("static", "intrinsic", c["key"], 2, "json", q)
      assert Pulse.JSON.decode!(body) == c["response"]

      {name, args} =
        if c["key"] == "",
          do: {"discover_trace_tags", %{}},
          else: {"discover_trace_tag_values", %{"key" => c["key"], "query" => q || ""}}

      assert {:ok, [%{"text" => json}]} =
               Tools.call(name, Map.merge(args, %{"tenant" => "static", "scope" => "intrinsic"}))

      assert Pulse.JSON.decode!(json) == c["response"]
    end

    assert {:error, :storage_unavailable} = TempoDiscovery.query("static", "span", "status")

    for scope <- ["intrinsic", "unknown"] do
      assert {:error, :unsupported_trace_discovery} = Storage.tempo_discovery_json("static", scope, "kind", [])
      assert {:error, :unsupported_trace_discovery} = Storage.S3.tempo_discovery_json("static", scope, "kind", [])

      assert {:error, :unsupported_trace_discovery} =
               Storage.S3.tempo_filtered_discovery_json("static", scope, "kind", "{}", [])
    end
  end

  test "static vocabulary validates filters without claiming stored presence; ID dictionaries require storage" do
    Runtime.put_env(:pulse, TempoSearch, enabled: true)
    Runtime.put_env(:pulse, Storage, adapter: FailingStorage)

    for key <- ~w(error status.code) do
      assert {:error, :unsupported_trace_discovery} = TempoDiscovery.query("static", "intrinsic", key)
    end

    for key <- ~w(link:spanID link:traceID span:id span:parentID trace:id), version <- [1, 2] do
      assert {:error, :storage_unavailable} = TempoDiscovery.query("static", "intrinsic", key, version)
    end

    for c <- cases(), q <- [~s'{resource.service.name="absent"}', ~s'{span.cached=true || span.count>1}'] do
      assert {:ok, body} = TempoDiscovery.query("static", "intrinsic", c["key"], 2, "json", q)
      assert Pulse.JSON.decode!(body) == c["response"]
    end

    for key <- ["", "status"], q <- ["{", "{} with (most_recent=true)"] do
      assert {:error, :unsupported_trace_discovery} = TempoDiscovery.query("static", "intrinsic", key, 2, "json", q)
    end

    for key <- ["status", "span:kind", "duration"] do
      assert {:error, :unsupported_trace_discovery} = TempoDiscovery.query("static", "intrinsic", key, 1)
    end

    assert {:error, {:invalid_tenant, "../bad"}} = TempoDiscovery.query("../bad", "intrinsic", "kind")
    Runtime.put_env(:pulse, TempoSearch, enabled: false)
    assert {:error, :tempo_search_disabled} = TempoDiscovery.query("static", "intrinsic", "status")
  end

  test "stored attributes named kind and status stay original values, not keyword enums" do
    Runtime.put_env(:pulse, TempoSearch, enabled: true)
    wire = File.read!(Path.expand("../../fixtures/traces/tempo-scopes-input.protobuf", __DIR__))
    {:ok, [base | _], 0} = Traces.decode_protobuf(wire)
    attrs = for key <- ["kind", "status"], do: %{"key" => key, "value" => %{"stringValue" => "stored-#{key}"}}

    span = %{
      base
      | attributes: Map.merge(base.attributes, %{"kind" => "stored-kind", "status" => "stored-status"}),
        otlp: Map.update!(base.otlp, "attributes", &(&1 ++ attrs))
    }

    assert :ok = Storage.append(:traces, "static", [span])

    for key <- ["kind", "status"] do
      assert {:ok, body} = TempoDiscovery.query("static", "span", key)
      assert Pulse.JSON.decode!(body) == %{"tagValues" => [%{"type" => "string", "value" => "stored-#{key}"}]}
      assert {:ok, body} = TempoDiscovery.query("static", "intrinsic", key)
      refute Enum.any?(Pulse.JSON.decode!(body)["tagValues"], &(&1["value"] == "stored-#{key}"))
    end
  end

  test "recorded time helpers establish routing and cache behavior, not a supported Pulse window" do
    dir = Path.expand("../../fixtures/traces", __DIR__)
    routing = File.read!(Path.join(dir, "tempo-time-routing-oracle.json"))
    cache = File.read!(Path.join(dir, "tempo-time-cache-oracle.json"))

    assert Base.encode16(:crypto.hash(:sha256, routing), case: :lower) ==
             "938eef01325b616dd721c8e67f3dd3f216f9a337511a7479fc131fa3ff77c0ad"

    assert Base.encode16(:crypto.hash(:sha256, cache), case: :lower) ==
             "4d9c7ff4bf8a1687035dfa9c4c82772700d1f473649dadb8923a244e750c1198"

    for c <- Pulse.JSON.decode!(routing) do
      assert c["included"] == (10 <= c["end"] and 21 >= c["start"])
    end

    assert Pulse.JSON.decode!(cache) == %{"different_time_ranges_share_key" => true}
  end

  test "static dictionaries still consume query admission and release it normally" do
    Runtime.put_env(:pulse, TempoSearch, enabled: true)
    parent = self()
    sup = start_supervised!({Task.Supervisor, name: __MODULE__.Callers})

    {:ok, _} =
      Task.Supervisor.start_child(sup, fn ->
        result =
          QueryRunner.run("static", :raw, fn _ ->
            send(parent, {:started, self()})
            receive do: (:release -> {:ok, :released})
          end)

        send(parent, {:finished, result})
      end)

    assert_receive {:started, worker}, 5_000
    assert {:error, :query_overloaded} = TempoDiscovery.query("static", "intrinsic", "status")
    ref = Process.monitor(worker)
    send(worker, :release)
    assert_receive {:DOWN, ^ref, :process, ^worker, :normal}
    assert_receive {:finished, {:ok, :released}}
    assert {:ok, _} = TempoDiscovery.query("static", "intrinsic", "status")
  end
end
