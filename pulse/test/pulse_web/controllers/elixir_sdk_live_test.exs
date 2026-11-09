defmodule PulseWeb.ElixirSDKLiveTest do
  use Pulse.Test.Case, async: true

  alias Pulse.OTLP.Traces
  alias Pulse.Storage
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Test.ElixirSDKAssertions
  alias Pulse.Test.ExternalCommand
  alias Pulse.Test.SDKIngestHarness
  alias Pulse.Traces.TempoSearch

  @moduletag :elixir_sdk
  @moduletag :tmp_dir
  @moduletag timeout: 120_000

  test "pinned Erlang SDK exports HTTP and gRPC batches into isolated durable tenants", ctx do
    run_profile(ctx, System.fetch_env!("PULSE_TEST_ELIXIR_SDK_DIR"), %{
      "grpcbox" => "0.18.0",
      "opentelemetry_finch" => "0.3.0",
      "phoenix" => "1.8.15"
    })
  end

  test "older grpcbox and Finch instrumentation export through both local transports", ctx do
    run_profile(ctx, System.fetch_env!("PULSE_TEST_ELIXIR_SDK_LEGACY_DIR"), %{
      "grpcbox" => "0.17.1",
      "opentelemetry_finch" => "0.2.0",
      "phoenix" => "1.7.21"
    })
  end

  defp run_profile(ctx, project, versions) do
    assert_producer_sources!(project, versions)
    collector = System.fetch_env!("PULSE_TEST_OTELCOL")
    harness = SDKIngestHarness.start!(ctx.tmp_dir, ~w(http grpc denied oversize unavailable rate))
    {collector_process, grpc_endpoint} = SDKIngestHarness.collector!(harness, collector, "grpc")

    for {protocol, endpoint} <- [{"http", harness.tap <> "/http/v1/traces"}, {"grpc", grpc_endpoint}] do
      {output, oracle} = produce!(ctx, project, protocol, endpoint, protocol)
      assert oracle["export"] == %{"count" => 5, "result" => ":ok"}
      assert oracle["flush"] == ":ok"
      assert Map.take(oracle["versions"], Map.keys(versions)) == versions
      ElixirSDKAssertions.assert_versions(oracle, if(versions["grpcbox"] == "0.18.0", do: "modern", else: "legacy"))
      assert {:ok, exported, 0} = Traces.decode_protobuf(File.read!(output <> "-sdk.protobuf"))
      assert length(exported) == 5
      ElixirSDKAssertions.assert_spans(exported, oracle)
      assert {:ok, stored} = Storage.query(:traces, protocol)
      assert Enum.sort_by(stored, & &1.span_id) === Enum.sort_by(exported, & &1.span_id)
      ElixirSDKAssertions.assert_spans(stored, oracle)
    end

    for {tenant, expected, count} <- [
          {"denied", ":error", 0},
          {"oversize", ":error", 0},
          {"unavailable", ":ok", 5},
          {"rate", ":error", 0}
        ] do
      {_, oracle} = produce!(ctx, project, "http", harness.tap <> "/#{tenant}/v1/traces", tenant)
      assert oracle["export"] == %{"count" => 5, "result" => expected}
      assert oracle["flush"] == ":ok"
      assert {:ok, stored} = Storage.query(:traces, tenant)
      assert length(stored) == count
    end

    assert {0, logs} = ExternalCommand.stop(collector_process)
    File.write!(Path.join(ctx.tmp_dir, "collector.log"), logs)
    entries = Agent.get(harness.capture, &Enum.reverse(&1.requests))
    assert length(entries) == 7

    assert Map.new(Enum.group_by(entries, & &1.tenant), fn {tenant, attempts} ->
             {tenant, Enum.map(attempts, & &1.status)}
           end) == %{
             "http" => [200],
             "grpc" => [200],
             "denied" => [401],
             "oversize" => [413],
             "unavailable" => [503, 200],
             "rate" => [429]
           }

    # This OTP httpc profile retries 503 + Retry-After, but not 429.
    retry = Enum.filter(entries, &(&1.tenant == "unavailable"))
    assert length(Enum.uniq_by(retry, & &1.body)) == 1

    for entry <- Enum.filter(entries, &(&1.status == 200)) do
      assert {"content-encoding", "gzip"} in entry.headers
      bytes = :zlib.gunzip(entry.body)
      File.write!(Path.join(ctx.tmp_dir, entry.tenant <> "-collector.protobuf"), bytes)
      assert {:ok, relayed, 0} = Traces.decode_protobuf(bytes)
      assert {:ok, stored} = Storage.query(:traces, entry.tenant)
      assert Enum.sort_by(relayed, & &1.span_id) === Enum.sort_by(stored, & &1.span_id)
    end

    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)

    for tenant <- ~w(http grpc) do
      response =
        SDKIngestHarness.mcp!(harness, tenant, "get_trace", %{"trace_id" => "0102030405060708090a0b0c0d0e0f10"})

      File.write!(Path.join(ctx.tmp_dir, tenant <> "-mcp.json"), Pulse.JSON.encode!(response))
      assert %{"result" => %{"content" => [%{"text" => text}]}} = response
      refute response["result"]["isError"]
      assembled = Pulse.JSON.decode!(text)
      assert length(assembled["spans"]) == 5
      assert {:ok, rows} = Storage.query(:traces, tenant)
      assert length(rows) == 5
      assert Enum.all?(rows, &(&1.resource["fixture.tenant"] == tenant))

      query =
        ~s|{ resource.service.namespace = "fixture" && resource.service.name = "fixture-registry" && resource.deployment.environment =~ "local" } with (most_recent=true)|

      start = div(Enum.min_by(rows, & &1.timestamp_ns).timestamp_ns, 1_000_000_000) - 1
      finish = div(Enum.max_by(rows, & &1.end_timestamp_ns).end_timestamp_ns, 1_000_000_000) + 1

      search =
        Req.get!(harness.api <> "/api/search",
          headers: SDKIngestHarness.headers(tenant),
          params: [q: query, start: start, end: finish]
        )

      File.write!(Path.join(ctx.tmp_dir, tenant <> "-search.json"), Pulse.JSON.encode!(search.body))
      assert search.status == 200
      assert length(search.body["traces"]) == 1

      workflows = Pulse.JSON.decode!(File.read!(Path.expand("../../fixtures/traces/query-workflows.json", __DIR__)))
      filtered = workflows["accepted"]

      selected =
        Req.get!(harness.api <> "/api/search",
          headers: SDKIngestHarness.headers(tenant),
          params: [q: filtered, start: start, end: finish]
        )

      assert selected.status == 200
      assert [%{"spanSet" => %{"matched" => 1}}] = selected.body["traces"]

      for expression <- workflows["expressions"] do
        response =
          Req.get!(harness.api <> "/api/search",
            headers: SDKIngestHarness.headers(tenant),
            params: [q: expression, start: start, end: finish]
          )

        assert response.status == 200
        assert {:ok, predicates} = TempoSearch.parse(expression)

        assert {:ok, expected} =
                 TempoSearch.json(rows, predicates,
                   trace_start: start * 1_000_000_000,
                   trace_end: finish * 1_000_000_000,
                   limit: 100,
                   spss: 3
                 )

        assert response.body === Pulse.JSON.decode!(expected)
      end

      for unsupported <- workflows["unsupported"] do
        rejected =
          Req.get!(harness.api <> "/api/search",
            headers: SDKIngestHarness.headers(tenant),
            params: [q: unsupported, start: start, end: finish]
          )

        assert rejected.status == 400
      end
    end

    denied =
      SDKIngestHarness.mcp!(harness, "http", "get_trace", %{
        "tenant" => "grpc",
        "trace_id" => "0102030405060708090a0b0c0d0e0f10"
      })

    assert denied["result"]["isError"] == true
  end

  defp assert_producer_sources!(project, versions) do
    fixtures = Path.expand("../../fixtures/traces/elixir_sdk", __DIR__)
    profile = if versions["grpcbox"] == "0.18.0", do: "modern", else: "legacy"

    for name <- ~w(run capture_exporter snapshot fixture_plug router ids repo completion_processor) do
      assert File.read!(Path.join(project, name <> ".exs")) == File.read!(Path.join(fixtures, name <> ".exs.txt"))
    end

    for name <- ~w(mix.exs mix.lock) do
      assert File.read!(Path.join(project, name)) == File.read!(Path.join(fixtures, profile <> "." <> name <> ".txt"))
    end
  end

  defp produce!(ctx, project, protocol, endpoint, tenant) do
    paths = Path.wildcard(Path.join(project, "_build/dev/lib/*/ebin"))
    assert paths != []
    output = Path.join(ctx.tmp_dir, tenant)

    args =
      ["--erl", "+S 2:2"] ++
        Enum.flat_map(paths, &["-pa", &1]) ++ [Path.join(project, "run.exs"), protocol, endpoint, tenant, output]

    producer =
      start_supervised!({ExternalCommand, path: System.fetch_env!("PULSE_TEST_ELIXIR"), args: args, isolate_beam: true},
        id: {:elixir_sdk, tenant}
      )

    assert {0, logs} = ExternalCommand.await(producer)
    File.write!(output <> "-producer.log", logs)
    refute String.contains?(logs, ["has failed", "threw exception"])
    {output, Pulse.JSON.decode!(File.read!(output <> "-oracle.json"))}
  end
end
