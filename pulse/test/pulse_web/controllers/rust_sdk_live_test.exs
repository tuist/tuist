defmodule PulseWeb.RustSDKLiveTest do
  use Pulse.Test.Case, async: true

  alias Pulse.OTLP.Traces
  alias Pulse.Storage
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Test.ExternalCommand
  alias Pulse.Test.RustSDKAssertions
  alias Pulse.Test.SDKIngestHarness
  alias Pulse.Traces.Assembly
  alias Pulse.Traces.TempoSearch

  @moduletag :rust_sdk
  @moduletag :tmp_dir
  @moduletag timeout: 120_000
  @trace "0102030405060708090a0b0c0d0e0f10"

  test "pinned Rust SDK exports through HTTP headers, env headers and gRPC into isolated durable tenants", ctx do
    binary = System.fetch_env!("PULSE_TEST_RUST_SDK")
    assert_producer!(ctx, binary, System.fetch_env!("PULSE_TEST_RUST_SDK_DIR"))
    collector = System.fetch_env!("PULSE_TEST_OTELCOL")

    harness =
      SDKIngestHarness.start!(ctx.tmp_dir, ~w(http http-env grpc denied oversize unavailable rate malformed override))

    {collector_process, grpc_endpoint} = SDKIngestHarness.collector!(harness, collector, "grpc")

    for {protocol, endpoint} <- [
          {"http", harness.tap <> "/http/v1/traces"},
          {"http-env", harness.tap <> "/http-env/v1/traces"},
          {"grpc", grpc_endpoint}
        ] do
      {output, oracle} = produce!(ctx, binary, protocol, endpoint, protocol)
      assert oracle["export_errors"] == []
      assert oracle["flush"] == nil
      assert oracle["shutdown"] == nil
      assert {:ok, exported, 0} = Traces.decode_protobuf(File.read!(output <> "-sdk.protobuf"))
      RustSDKAssertions.assert_spans(exported, oracle)
      assert {:ok, stored} = Storage.query(:traces, protocol)
      assert Enum.sort_by(stored, & &1.span_id) === Enum.sort_by(exported, & &1.span_id)
      RustSDKAssertions.assert_spans(stored, oracle)
    end

    stop_collector!(ctx, collector_process, "positive")

    for tenant <- ~w(denied oversize unavailable rate malformed override) do
      protocol = if tenant == "malformed", do: "http-env", else: "http"
      {_, oracle} = produce!(ctx, binary, protocol, harness.tap <> "/#{tenant}/v1/traces", tenant)
      RustSDKAssertions.assert_export_error(oracle, tenant)
      assert {:ok, []} = Storage.query(:traces, tenant)
    end

    for tenant <- ~w(denied oversize unavailable rate) do
      Agent.update(harness.capture, fn state ->
        if tenant in ~w(unavailable rate),
          do: put_in(state, [:failures, tenant], [if(tenant == "unavailable", do: 503, else: 429)]),
          else: state
      end)

      {process, endpoint} = SDKIngestHarness.collector!(harness, collector, tenant)
      {_, oracle} = produce!(ctx, binary, "grpc", endpoint, tenant)
      RustSDKAssertions.assert_export_error(oracle, tenant)
      assert {:ok, []} = Storage.query(:traces, tenant)
      stop_collector!(ctx, process, tenant)
    end

    entries = Agent.get(harness.capture, &Enum.reverse(&1.requests))

    assert Map.new(Enum.group_by(entries, & &1.tenant), fn {tenant, attempts} ->
             {tenant, Enum.map(attempts, & &1.status)}
           end) == %{
             "http" => [200],
             "http-env" => [200],
             "grpc" => [200],
             "denied" => [401, 401],
             "oversize" => [413, 413],
             "unavailable" => [503, 503],
             "rate" => [429, 429],
             "malformed" => [401],
             "override" => [401]
           }

    for tenant <- ~w(denied oversize unavailable rate) do
      encodings =
        entries
        |> Enum.filter(&(&1.tenant == tenant))
        |> Enum.map(fn entry ->
          if {"content-encoding", "gzip"} in entry.headers, do: "gzip"
        end)

      assert Enum.sort(encodings) == [nil, "gzip"]
    end

    assert {:ok, []} = Storage.query(:traces, "untrusted-incoming-tenant")
    malformed = Enum.find(entries, &(&1.tenant == "malformed"))
    refute Enum.any?(malformed.headers, fn {name, _} -> name == "authorization" end)
    overridden = Enum.find(entries, &(&1.tenant == "override"))
    assert {"authorization", "Bearer invalid"} in overridden.headers
    save_observations!(ctx, entries)

    for tenant <- ~w(http http-env grpc) do
      successful = Enum.filter(entries, &(&1.tenant == tenant and &1.status == 200))
      bytes = Enum.map_join(successful, &body/1)
      File.write!(Path.join(ctx.tmp_dir, tenant <> "-delivered.protobuf"), bytes)
      assert {:ok, received, 0} = Traces.decode_protobuf(bytes)
      assert {:ok, stored} = Storage.query(:traces, tenant)
      assert Enum.sort_by(received, & &1.span_id) === Enum.sort_by(stored, & &1.span_id)
    end

    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)

    for tenant <- ~w(http http-env grpc) do
      response = SDKIngestHarness.mcp!(harness, tenant, "get_trace", %{"trace_id" => @trace})
      File.write!(Path.join(ctx.tmp_dir, tenant <> "-mcp.json"), Pulse.JSON.encode!(response))
      assert %{"result" => %{"content" => [%{"text" => text}]}} = response
      refute response["result"]["isError"]
      assert length(Pulse.JSON.decode!(text)["spans"]) == 3
      assert {:ok, rows} = Storage.query(:traces, tenant)
      assert Enum.all?(rows, &(&1.resource["deployment.environment.name"] == tenant))
      assert {:ok, reference} = Assembly.json(rows, @trace)
      assert Pulse.JSON.decode!(text) === Pulse.JSON.decode!(reference)
      start = div(Enum.min_by(rows, & &1.timestamp_ns).timestamp_ns, 1_000_000_000) - 1
      finish = div(Enum.max_by(rows, & &1.end_timestamp_ns).end_timestamp_ns, 1_000_000_000) + 1

      for query <- [
            ~s|{ resource.service.name = "rust-bridge" && span.http.route = "/fixture" } with (most_recent=true)|,
            ~s'{ resource.deployment.environment.name !~ "absent" && (span.http.response.status_code >= 500 || status = error) && duration > 0ns } with (most_recent=true)'
          ] do
        search =
          Req.get!(harness.api <> "/api/search",
            headers: SDKIngestHarness.headers(tenant),
            params: [q: query, start: start, end: finish]
          )

        assert search.status == 200
        assert [%{"spanSet" => %{"matched" => 1}}] = search.body["traces"]
        assert {:ok, predicates} = TempoSearch.parse(query)

        assert {:ok, expected} =
                 TempoSearch.json(rows, predicates,
                   trace_start: start * 1_000_000_000,
                   trace_end: finish * 1_000_000_000,
                   limit: 100,
                   spss: 3
                 )

        assert search.body === Pulse.JSON.decode!(expected)

        mcp =
          SDKIngestHarness.mcp!(harness, tenant, "search_trace_metadata", %{
            "query" => query,
            "start_ts_ns" => start * 1_000_000_000,
            "end_ts_ns" => finish * 1_000_000_000
          })

        assert %{"result" => %{"content" => [%{"text" => result}]}} = mcp
        refute mcp["result"]["isError"]
        assert Pulse.JSON.decode!(result) === Pulse.JSON.decode!(expected)
      end
    end

    denied = SDKIngestHarness.mcp!(harness, "http", "get_trace", %{"tenant" => "grpc", "trace_id" => @trace})
    assert denied["result"]["isError"] == true
  end

  defp assert_producer!(ctx, binary, project) do
    fixtures = Path.expand("../../fixtures/traces", __DIR__)

    for {kind, staged, frozen} <- [
          {"source", "src/main.rs", "produce_rust_sdk.rs.txt"},
          {"manifest", "Cargo.toml", "rust-sdk.Cargo.toml.txt"},
          {"lock", "Cargo.lock", "rust-sdk.Cargo.lock.txt"},
          {"build", "build.rs", "rust-sdk.build.rs.txt"}
        ] do
      expected = File.read!(Path.join(fixtures, frozen))
      assert byte_size(expected) <= 65_536, "embedded provenance exceeds the process output bound"
      assert File.read!(Path.join(project, staged)) == expected

      process =
        start_supervised!({ExternalCommand, path: binary, args: ["--embedded-" <> kind]}, id: {:rust_provenance, kind})

      assert {0, ^expected} = ExternalCommand.await(process)
    end

    File.write!(
      Path.join(ctx.tmp_dir, "producer.sha256"),
      Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower)
    )
  end

  defp stop_collector!(ctx, process, suffix) do
    assert {0, logs} = ExternalCommand.stop(process)
    File.write!(Path.join(ctx.tmp_dir, suffix <> "-collector.log"), logs)
    assert :ok = stop_supervised(:sdk_collector)
  end

  defp produce!(ctx, binary, protocol, endpoint, tenant) do
    suffix = if protocol == "grpc" and tenant != "grpc", do: "grpc-" <> tenant, else: tenant
    output = Path.join(ctx.tmp_dir, suffix)

    headers =
      case {protocol, tenant} do
        {"http-env", "malformed"} -> "authorization,x-scope-orgid=malformed"
        {"http", "override"} -> "authorization=Bearer%20invalid,x-scope-orgid=override"
        {"http-env", _} -> "authorization=Bearer%20token-#{tenant},x-scope-orgid=#{tenant}"
        {"grpc", _} -> "x-scope-orgid=untrusted-incoming-tenant"
        _ -> nil
      end

    process =
      start_supervised!(
        {ExternalCommand, path: binary, args: [protocol, endpoint, tenant, output], otel_trace_headers: headers},
        id: {:rust_sdk, protocol, tenant}
      )

    assert {0, logs} = ExternalCommand.await(process)
    File.write!(output <> "-producer.log", logs)
    {output, Pulse.JSON.decode!(File.read!(output <> "-oracle.json"))}
  end

  defp save_observations!(ctx, entries) do
    attempts =
      Enum.map(entries, fn entry ->
        %{
          "tenant" => entry.tenant,
          "status" => entry.status,
          "encoding" => entry.headers |> List.keyfind("content-encoding", 0, {nil, nil}) |> elem(1),
          "body" => Base.encode64(entry.body)
        }
      end)

    producers =
      Map.new(Path.wildcard(Path.join(ctx.tmp_dir, "*-oracle.json")), fn path ->
        name = path |> Path.basename("-oracle.json")
        oracle = path |> File.read!() |> Pulse.JSON.decode!()
        {name, Map.take(oracle, ~w(protocol export_errors flush shutdown rustc target batch_profile))}
      end)

    counts =
      Map.new(
        ~w(http http-env grpc denied oversize unavailable rate malformed override untrusted-incoming-tenant),
        fn tenant ->
          assert {:ok, rows} = Storage.query(:traces, tenant)
          {tenant, length(rows)}
        end
      )

    File.write!(
      Path.join(ctx.tmp_dir, "observations.json"),
      Pulse.JSON.encode!(%{
        "attempts" => attempts,
        "producers" => producers,
        "stored_counts" => counts
      })
    )
  end

  defp body(entry) do
    if {"content-encoding", "gzip"} in entry.headers, do: :zlib.gunzip(entry.body), else: entry.body
  end
end
