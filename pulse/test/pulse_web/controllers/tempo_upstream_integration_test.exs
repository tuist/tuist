# SPDX-License-Identifier: AGPL-3.0-only
# Adapted from Grafana Tempo integration/api/search/{search,search_tags}_test.go.
# Exact-ID/search cases: integration/api/tracebyid/trace_by_id_test.go.
# Filtering cases: integration/api/tracebyid/trace_by_id_filtering_test.go.
# Metric cases: integration/api/metrics/query_range_test.go.
# Default metric steps: pkg/traceql/engine_metrics_test.go.
# Metric bound parser oracle: pkg/api/http_test.go Test_parseTimestamp.
# Negative metric steps: pkg/api/http_test.go TestParseQueryRangeNegativeStep.
# Invalid metric bounds: pkg/api/http_test.go TestParseQueryRequestInvalidBounds.
# Invalid since: pkg/api/http_test.go Test_determineBounds, selected error row.
# Mixed discovery identifiers: pkg/traceql/parse_test.go TestParseIdentifier, five rows.
# Invalid search limits: pkg/api/http_test.go TestQuerierParseSearchRequest, four rows.
# Invalid spss: pkg/api/http_test.go TestQuerierParseSearchRequest, three rows.
# Invalid search bounds: pkg/api/http_test.go TestQuerierParseSearchRequest, three rows.
# Empty Accept: pkg/api/http_test.go TestMarshalingFormatFromAcceptHeader, one row.
# Source revision, adaptations and license: test/fixtures/traces/tempo_integration/README.md.
defmodule PulseWeb.TempoUpstreamIntegrationTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Auth
  alias Pulse.Auth.SharedSecret
  alias Pulse.Codec.NIF
  alias Pulse.OTLP.Traces
  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Test.CompactionStore
  alias Pulse.Test.MCPMessages
  alias Pulse.Test.OTLPTraceFixture
  alias Pulse.Test.RuntimePlug
  alias Pulse.Traces.Protobuf
  alias Pulse.Traces.Tempo
  alias Pulse.Traces.TempoFilter
  alias Pulse.Traces.TempoSearch

  @cases "../../fixtures/traces/tempo_integration/cases.json"
         |> Path.expand(__DIR__)
         |> File.read!()
         |> Pulse.JSON.decode!()

  @intrinsic_names "../../fixtures/traces/tempo_integration/intrinsic-names.json"
                   |> Path.expand(__DIR__)
                   |> File.read!()
                   |> Pulse.JSON.decode!()

  @math "../../fixtures/traces/tempo_integration/metrics-math.json"
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
    {:ok, {_, object_port}} = ThousandIsland.listener_info(object_server)

    config = %{
      bucket: "pulse",
      endpoint: "http://127.0.0.1:#{object_port}",
      region: "us-east-1",
      access_key_id: "tempo-upstream-#{System.unique_integer([:positive])}",
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0
    }

    tenant = "tempo-upstream-#{System.unique_integer([:positive])}"
    token = "upstream-test-token"
    digest = "sha256$" <> Base.encode16(:crypto.hash(:sha256, token), case: :lower)
    Runtime.put_env(:pulse, Auth, module: SharedSecret, tokens: %{tenant => digest})
    Runtime.put_env(:pulse, TempoSearch, enabled: true)
    Runtime.put_env(:pulse, Storage, adapter: S3)
    Runtime.put_env(:pulse, S3, config)
    start_supervised!(ManifestSupervision)
    Runtime.share()

    server =
      start_supervised!(
        {Bandit, plug: {RuntimePlug, plug: PulseWeb.Endpoint, runtime: Runtime.current()}, ip: {127, 0, 0, 1}, port: 0},
        id: :tempo_upstream_api
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(server)

    %{
      url: "http://127.0.0.1:#{port}",
      headers: [{"authorization", "Bearer " <> token}, {"x-scope-orgid", tenant}],
      tenant: tenant,
      store: store,
      now: System.system_time(:second)
    }
  end

  for {version, prefix} <- [{1, "/api/traces/"}, {2, "/api/v2/traces/"}] do
    @tag :empty_accept
    test "Tempo TestMarshalingFormatFromAcceptHeader empty accept header / v#{version}", ctx do
      # Original row: acceptHeader="", expected=MarshallingFormatJSON.
      # IDs, one-span producer, HTTP200/MIME/body equivalence are adaptations.
      ingest_timestamp_probe(ctx, (ctx.now - 3) * 1_000_000_000)
      path = unquote(prefix) <> String.pad_leading("1", 32, "0")
      before_reads = Agent.get(ctx.store, & &1.reads)
      baseline = Req.get!(ctx.url <> path, headers: ctx.headers)
      assert baseline.status == 200
      assert Agent.get(ctx.store, & &1.reads) != before_reads

      # The owned actual HTTP listener preserves the explicitly present empty
      # header; this is not a request that simply omits Accept.
      response = Req.get!(ctx.url <> path, headers: [{"accept", ""} | ctx.headers])
      assert response.status == 200
      assert Req.Response.get_header(response, "content-type") == ["application/json; charset=utf-8"]
      assert response.body == baseline.body
    end

    @tag :empty_accept
    test "Pulse Accept controls preserve negotiation and no-provider rejects / v#{version}", ctx do
      # Authored preservation controls, not extra imported negotiation oracles.
      ingest_timestamp_probe(ctx, (ctx.now - 3) * 1_000_000_000)
      path = unquote(prefix) <> String.pad_leading("1", 32, "0")
      baseline = Req.get!(ctx.url <> path, headers: ctx.headers)
      assert baseline.status == 200

      for accept <- [
            [{"accept", "application/json"}],
            [{"accept", "*/*"}],
            [{"accept", "application/json;q=0"}],
            [{"accept", "application/protobuf, application/json"}],
            [{"accept", "application/json"}, {"accept", "application/protobuf"}]
          ] do
        response = Req.get!(ctx.url <> path, headers: accept ++ ctx.headers)
        assert response.status == 200
        assert Req.Response.get_header(response, "content-type") == ["application/json; charset=utf-8"]
        assert response.body == baseline.body
      end

      wire = Req.get!(ctx.url <> path, headers: [{"accept", "application/protobuf"} | ctx.headers])
      assert wire.status == 200
      assert Req.Response.get_header(wire, "content-type") == ["application/protobuf; charset=utf-8"]
      assert is_binary(wire.body) and byte_size(wire.body) > 0

      before_requests = Agent.get(ctx.store, & &1.requests)

      for accept <- [
            [{"accept", "text/html"}],
            [{"accept", "application/invalid"}],
            [{"accept", "application/vnd.grafana.llm"}],
            [{"accept", "application/protobuf;q=1"}],
            [{"accept", "application/protobuf, text/html"}],
            [{"accept", ""}, {"accept", ""}],
            [{"accept", ""}, {"accept", "application/protobuf"}]
          ] do
        response = Req.get!(ctx.url <> path, headers: accept ++ ctx.headers)
        assert response.status == 406
        assert response.body == "supported trace response formats: application/json, application/protobuf"
      end

      denied = Req.get!(ctx.url <> path, headers: [{"accept", ""}, {"x-scope-orgid", ctx.tenant}])
      assert denied.status == 401
      assert denied.body == "unauthorized"

      invalid = Req.get!(ctx.url <> path, headers: [{"accept", ""} | ctx.headers], params: %{"mode" => "ingesters"})
      assert invalid.status == 400
      assert invalid.body == "invalid or unsupported trace lookup parameters"
      assert Agent.get(ctx.store, & &1.requests) == before_requests
    end
  end

  for {query, message} <- [
        {"start=-1&end=20", ~s(invalid start: strconv.ParseUint: parsing "-1": invalid syntax)},
        {"start=4294967296&end=4294967297",
         ~s(invalid start: strconv.ParseUint: parsing "4294967296": value out of range)},
        {"start=10&end=-1", ~s(invalid end: strconv.ParseUint: parsing "-1": invalid syntax)}
      ] do
    @tag :search_bound_diagnostics
    test "Tempo TestQuerierParseSearchRequest / #{query}", ctx do
      # Complete original helper URL/error rows. The one-span producer,
      # successful supported selector, HTTP/auth/provider checks are adaptations.
      ingest_timestamp_probe(ctx, (ctx.now - 3) * 1_000_000_000)
      before_reads = Agent.get(ctx.store, & &1.reads)
      result = get(ctx, "/api/search", %{"q" => ~s({ resource.service.name = "my-service" })})
      assert [trace] = result["traces"]
      assert trace["spanSet"]["matched"] == 1
      assert Enum.any?(Agent.get(ctx.store, & &1.reads) -- before_reads, &String.ends_with?(&1, ".parquet"))

      before_requests = Agent.get(ctx.store, & &1.requests)
      path = "/api/search?" <> unquote(query)
      response = Req.get!(ctx.url <> path, headers: ctx.headers)
      assert response.status == 400
      assert response.body == unquote(message)
      denied = Req.get!(ctx.url <> path)
      assert denied.status == 401
      assert denied.body == "unauthorized"
      assert Agent.get(ctx.store, & &1.requests) == before_requests
    end
  end

  @tag :search_bound_diagnostics
  test "Pulse search-bound controls preserve numeric admission window policies and precedence", ctx do
    # Authored producer/results and admission controls, not upstream engine rows.
    ingest_timestamp_probe(ctx, (ctx.now - 3) * 1_000_000_000)
    params = %{"q" => ~s({ resource.service.name = "my-service" })}
    expected = get(ctx, "/api/search", params)
    assert [trace] = expected["traces"]
    assert trace["spanSet"]["matched"] == 1

    for window <- [
          %{"start" => "0", "end" => "0"},
          %{"start" => to_string(ctx.now - 10), "end" => to_string(ctx.now + 10)},
          %{"start" => "1", "end" => "4294967295"},
          %{"start" => "0000000001", "end" => "4294967295"}
        ] do
      assert get(ctx, "/api/search", Map.merge(params, window)) == expected
    end

    before_requests = Agent.get(ctx.store, & &1.requests)
    generic = "invalid or unsupported trace lookup parameters"

    for {window, message} <- [
          {%{"start" => "10"}, generic},
          {%{"end" => "20"}, generic},
          {%{"start" => "bad"}, generic},
          {%{"start" => "0", "end" => "20"}, generic},
          {%{"start" => "10", "end" => "0"}, generic},
          {%{"start" => "20", "end" => "10"}, generic},
          {%{"start" => "+10", "end" => "20"}, generic},
          {%{"start" => "10", "end" => "+20"}, generic},
          {%{"start" => "00000000001", "end" => "20"}, generic},
          {%{"start" => "10", "end" => "99999999999"}, generic},
          {%{"start" => "", "end" => "20"}, ~s(invalid start: strconv.ParseUint: parsing "": invalid syntax)},
          {%{"start" => "10", "end" => "1.5"}, ~s(invalid end: strconv.ParseUint: parsing "1.5": invalid syntax)},
          {%{"start" => "999999999x", "end" => "20"},
           ~s(invalid start: strconv.ParseUint: parsing "999999999x": invalid syntax)},
          {%{"start" => "10", "end" => "9999999999"},
           ~s(invalid end: strconv.ParseUint: parsing "9999999999": value out of range)},
          {%{"start" => "bad", "end" => "also-bad"},
           ~s(invalid start: strconv.ParseUint: parsing "bad": invalid syntax)},
          {%{"start" => "bad", "end" => "20", "unknown" => "value"}, generic},
          {%{"start" => "bad", "end" => "20", "limit" => "0", "spss" => "bad"},
           ~s(invalid start: strconv.ParseUint: parsing "bad": invalid syntax)}
        ] do
      response = Req.get!(ctx.url <> "/api/search", headers: ctx.headers, params: Map.merge(params, window))
      assert response.status == 400
      assert response.body == message
    end

    denied = Req.get!(ctx.url <> "/api/search", params: Map.merge(params, %{"start" => "bad", "end" => "bad"}))
    assert denied.status == 401
    assert denied.body == "unauthorized"
    assert Agent.get(ctx.store, & &1.requests) == before_requests
  end

  for {query, message} <- [
        {"spss=-2", ~s(invalid spss: strconv.ParseUint: parsing "-2": invalid syntax)},
        {"spss=four", ~s(invalid spss: strconv.ParseUint: parsing "four": invalid syntax)},
        {"spss=4294967296", ~s(invalid spss: strconv.ParseUint: parsing "4294967296": value out of range)}
      ] do
    @tag :search_spss_diagnostics
    test "Tempo TestQuerierParseSearchRequest / #{query}", ctx do
      # Complete original helper URL/error rows. Producer, supported selector,
      # HTTP status/auth and native Parquet/provider assertions are adaptations.
      ingest_filter_trace(ctx, [{1, 0, 0}, {2, 1, 0}, {3, 1, 0}, {4, 1, 0}])
      before_reads = Agent.get(ctx.store, & &1.reads)
      result = get(ctx, "/api/search", %{"q" => ~s({ resource.service.name = "filter-test" })})
      assert [trace] = result["traces"]
      assert trace["spanSet"]["matched"] == 4
      assert length(trace["spanSet"]["spans"]) == 3
      assert Agent.get(ctx.store, & &1.reads) != before_reads

      before_requests = Agent.get(ctx.store, & &1.requests)
      path = "/api/search?" <> unquote(query)
      response = Req.get!(ctx.url <> path, headers: ctx.headers)
      assert response.status == 400
      assert response.body == unquote(message)
      denied = Req.get!(ctx.url <> path)
      assert denied.status == 401
      assert denied.body == "unauthorized"
      assert Agent.get(ctx.store, & &1.requests) == before_requests
    end
  end

  @tag :search_spss_diagnostics
  test "Pulse spss sampling controls preserve grammar bounds and admission precedence", ctx do
    # Authored numerical producer/results; not an upstream engine oracle.
    ingest_filter_trace(ctx, [{1, 0, 0}, {2, 1, 0}, {3, 1, 0}, {4, 1, 0}])
    params = %{"q" => ~s({ resource.service.name = "filter-test" })}
    before_reads = Agent.get(ctx.store, & &1.reads)

    for {spss, samples} <- [{nil, 3}, {"1", 1}, {"2", 2}, {"100", 4}, {"+2", 2}, {"0000000002", 2}] do
      query = if spss, do: Map.put(params, "spss", spss), else: params
      assert [trace] = get(ctx, "/api/search", query)["traces"]
      assert trace["spanSet"]["matched"] == 4
      assert length(trace["spanSet"]["spans"]) == samples
    end

    assert Agent.get(ctx.store, & &1.reads) != before_reads
    before_requests = Agent.get(ctx.store, & &1.requests)
    generic = "invalid or unsupported trace lookup parameters"

    for {spss, message} <- [
          {"", ~s(invalid spss: strconv.ParseUint: parsing "": invalid syntax)},
          {"1.5", ~s(invalid spss: strconv.ParseUint: parsing "1.5": invalid syntax)},
          {"1e2", ~s(invalid spss: strconv.ParseUint: parsing "1e2": invalid syntax)},
          {"\"a\n", ~S(invalid spss: strconv.ParseUint: parsing "\"a\n": invalid syntax)},
          {"999999999x", ~s(invalid spss: strconv.ParseUint: parsing "999999999x": invalid syntax)},
          {"9999999999", ~s(invalid spss: strconv.ParseUint: parsing "9999999999": value out of range)},
          {"0", generic},
          {"0000000000", generic},
          {"101", generic},
          {"4294967295", generic},
          {"00000000002", generic},
          {"99999999999", generic}
        ] do
      response = Req.get!(ctx.url <> "/api/search", headers: ctx.headers, params: Map.put(params, "spss", spss))
      assert response.status == 400
      assert response.body == message
    end

    for {changes, message} <- [
          {%{"spss" => "bad", "start" => "bad", "end" => "1700000000"},
           ~s(invalid start: strconv.ParseUint: parsing "bad": invalid syntax)},
          {%{"spss" => "bad", "unknown" => "value"}, generic},
          {%{"spss" => "bad", "limit" => "0"}, "invalid limit: must be a positive number"},
          {%{"spss" => "bad", "limit" => "1010"}, generic},
          {%{"spss" => "bad", "limit" => "five"}, ~s(invalid limit: strconv.ParseUint: parsing "five": invalid syntax)}
        ] do
      response = Req.get!(ctx.url <> "/api/search", headers: ctx.headers, params: Map.merge(params, changes))
      assert response.status == 400
      assert response.body == message
    end

    denied = Req.get!(ctx.url <> "/api/search", params: Map.put(params, "spss", "bad"))
    assert denied.status == 401
    assert denied.body == "unauthorized"
    assert Agent.get(ctx.store, & &1.requests) == before_requests
  end

  for {query, message} <- [
        {"limit=0", "invalid limit: must be a positive number"},
        {"limit=-5", ~s(invalid limit: strconv.ParseUint: parsing "-5": invalid syntax)},
        {"limit=five", ~s(invalid limit: strconv.ParseUint: parsing "five": invalid syntax)},
        {"limit=4294967298", ~s(invalid limit: strconv.ParseUint: parsing "4294967298": value out of range)}
      ] do
    @tag :search_limit_diagnostics
    test "Tempo TestQuerierParseSearchRequest / #{query}", ctx do
      # Complete selected helper request/error rows, without adding q to their URLs.
      # HTTP status, auth, the numeric producer and Parquet reads are adaptations.
      ingest_timestamp_probe(ctx, (ctx.now - 3) * 1_000_000_000)
      before_reads = Agent.get(ctx.store, & &1.reads)
      result = get(ctx, "/api/search", %{"q" => ~s({ resource.service.name = "my-service" }), "limit" => "10"})
      assert length(result["traces"]) == 1
      assert Agent.get(ctx.store, & &1.reads) != before_reads

      before_requests = Agent.get(ctx.store, & &1.requests)
      path = "/api/search?" <> unquote(query)
      response = Req.get!(ctx.url <> path, headers: ctx.headers)
      assert response.status == 400
      assert response.body == unquote(message)
      denied = Req.get!(ctx.url <> path)
      assert denied.status == 401
      assert denied.body == "unauthorized"
      assert Agent.get(ctx.store, & &1.requests) == before_requests
    end
  end

  @tag :search_limit_diagnostics
  test "Pulse search-limit controls preserve grammar caps and admission precedence", ctx do
    # Authored one-span producer/results and controls, not upstream helper oracles.
    ingest_timestamp_probe(ctx, (ctx.now - 3) * 1_000_000_000)
    params = %{"q" => ~s({ resource.service.name = "my-service" })}
    expected = get(ctx, "/api/search", params)
    assert length(expected["traces"]) == 1

    for limit <- ["1", "10", "100", "1000", "+10", "0000000010"] do
      assert get(ctx, "/api/search", Map.put(params, "limit", limit)) == expected
    end

    before_requests = Agent.get(ctx.store, & &1.requests)
    generic = "invalid or unsupported trace lookup parameters"

    for {limit, message} <- [
          {"", ~s(invalid limit: strconv.ParseUint: parsing "": invalid syntax)},
          {"1.5", ~s(invalid limit: strconv.ParseUint: parsing "1.5": invalid syntax)},
          {"1e2", ~s(invalid limit: strconv.ParseUint: parsing "1e2": invalid syntax)},
          {"\"a\n", ~S(invalid limit: strconv.ParseUint: parsing "\"a\n": invalid syntax)},
          {"999999999x", ~s(invalid limit: strconv.ParseUint: parsing "999999999x": invalid syntax)},
          {"0000000000", "invalid limit: must be a positive number"},
          {"1001", generic},
          {"4294967295", generic},
          {"99999999999", generic}
        ] do
      response = Req.get!(ctx.url <> "/api/search", headers: ctx.headers, params: Map.put(params, "limit", limit))
      assert response.status == 400
      assert response.body == message
    end

    for {changes, message} <- [
          {%{"limit" => "0", "start" => "bad", "end" => "1700000000"},
           ~s(invalid start: strconv.ParseUint: parsing "bad": invalid syntax)},
          {%{"limit" => "0", "unknown" => "value"}, generic},
          {%{"limit" => "0", "spss" => "bad"}, "invalid limit: must be a positive number"},
          {%{"limit" => "10", "spss" => "0"}, generic}
        ] do
      response = Req.get!(ctx.url <> "/api/search", headers: ctx.headers, params: Map.merge(params, changes))
      assert response.status == 400
      assert response.body == message
    end

    denied = Req.get!(ctx.url <> "/api/search", params: Map.put(params, "limit", "0"))
    assert denied.status == 401
    assert denied.body == "unauthorized"
    assert Agent.get(ctx.store, & &1.requests) == before_requests
  end

  for endpoint <- ["query", "query_range"] do
    @tag :metric_invalid_since
    test "Tempo Test_determineBounds invalid since / #{endpoint}", ctx do
      # Complete selected helper row. The clock is unused with explicit bounds;
      # zero-time output placeholders are not compared after the upstream error.
      source = %{
        now: ~U[2022-12-18 00:00:00Z],
        start: "2022-12-17T00:00:00Z",
        end: "2022-12-18T00:00:00Z",
        since: "HI!",
        error: "could not parse 'since' parameter:"
      }

      # q, step and HTTP400/no-provider assertions are authored HTTP adaptations,
      # not additional upstream numerical or complete-error-text oracles.
      params = %{
        "q" => "{} | count_over_time()",
        "start" => source.start,
        "end" => source.end,
        "since" => source.since,
        "step" => "1h"
      }

      before_requests = Agent.get(ctx.store, & &1.requests)
      response = Req.get!(ctx.url <> "/api/metrics/" <> unquote(endpoint), headers: ctx.headers, params: params)
      assert response.status == 400
      assert response.body =~ source.error
      assert Agent.get(ctx.store, & &1.requests) == before_requests
    end

    @tag :metric_invalid_since
    test "Pulse since controls: visible Parquet valid auth and precedence / #{endpoint}", ctx do
      # Authored one-span producer and numerical expectations, not the helper row.
      ingest_timestamp_probe(ctx, 1_671_278_400_000_000_000)
      path = "/api/metrics/" <> unquote(endpoint)

      params = %{
        "q" => "{} | count_over_time()",
        "start" => "2022-12-17T00:00:00Z",
        "end" => "2022-12-18T00:00:00Z",
        "step" => "1h"
      }

      before_reads = Agent.get(ctx.store, & &1.reads)
      assert metric_count(get(ctx, path, params)) == 1
      assert Agent.get(ctx.store, & &1.reads) != before_reads

      for since <- ["1h", "1d"] do
        assert metric_count(get(ctx, path, Map.put(params, "since", since))) == 1
      end

      before_requests = Agent.get(ctx.store, & &1.requests)

      for {changes, diagnostic} <- [
            {%{"since" => "HI!"}, "could not parse 'since' parameter:"},
            {%{"since" => "HI!", "start" => "abc"}, "could not parse 'since' parameter:"},
            {%{"since" => "HI!", "end" => "bca"}, "could not parse 'end' parameter"},
            {%{"since" => "HI!", "step" => "-1h"}, "could not parse 'since' parameter:"}
          ] do
        invalid = Map.merge(params, changes)
        response = Req.get!(ctx.url <> path, headers: ctx.headers, params: invalid)
        assert response.status == 400
        assert response.body == diagnostic
        denied = Req.get!(ctx.url <> path, params: invalid)
        assert denied.status == 401
        assert denied.body == "unauthorized"
      end

      assert Agent.get(ctx.store, & &1.requests) == before_requests
    end

    @tag :metric_invalid_since
    test "Pulse since controls: parse failures differ from nonpositive policy errors / #{endpoint}", ctx do
      path = "/api/metrics/" <> unquote(endpoint)

      params = %{
        "q" => "{} | count_over_time()",
        "start" => "2022-12-17T00:00:00Z",
        "end" => "2022-12-18T00:00:00Z",
        "step" => "1h"
      }

      before_requests = Agent.get(ctx.store, & &1.requests)

      for since <- ["garbage", "-garbage", "--1h", "-1d", "-1e999", ""] do
        response = Req.get!(ctx.url <> path, headers: ctx.headers, params: Map.put(params, "since", since))
        assert response.status == 400
        assert response.body == "could not parse 'since' parameter:"
      end

      # These values parse, but fail the existing strictly positive policy.
      for since <- ["0", "-0", "0s", "-0s", "-1h", "-1.5"] do
        response = Req.get!(ctx.url <> path, headers: ctx.headers, params: Map.put(params, "since", since))
        assert response.status == 400
        assert response.body == "invalid or unsupported trace lookup parameters"
      end

      assert Agent.get(ctx.store, & &1.requests) == before_requests
    end

    for {name, start, finish, diagnostic} <- [
          {"invalid start", "abc", "1700000000", "could not parse 'start' parameter"},
          {"invalid end", "1700000000", "bca", "could not parse 'end' parameter"}
        ] do
      @tag :metric_invalid_bounds
      test "Tempo TestParseQueryRequestInvalidBounds / #{endpoint} / #{name}", ctx do
        # Complete original table and both endpoint variants. The source
        # asserts an error containing this substring, not an exact error body.
        params = %{"q" => "{} | rate()", "start" => unquote(start), "end" => unquote(finish)}
        before_requests = Agent.get(ctx.store, & &1.requests)
        response = Req.get!(ctx.url <> "/api/metrics/" <> unquote(endpoint), headers: ctx.headers, params: params)
        assert response.status == 400
        assert response.body =~ unquote(diagnostic)
        assert Agent.get(ctx.store, & &1.requests) == before_requests
      end
    end

    @tag :metric_invalid_bounds
    test "Pulse metric-bound controls: valid Parquet auth precedence and admitted windows / #{endpoint}", ctx do
      # Separately authored numerical producer, not an upstream parser oracle.
      ingest_timestamp_probe(ctx, 1_700_001_800_000_000_000)
      path = "/api/metrics/" <> unquote(endpoint)
      params = %{"q" => "{} | rate()", "start" => "1700000000", "end" => "1700003600", "step" => "1h"}
      before_reads = Agent.get(ctx.store, & &1.reads)
      assert metric_count(get(ctx, path, params)) == 1 / 3600
      assert Agent.get(ctx.store, & &1.reads) != before_reads
      before_requests = Agent.get(ctx.store, & &1.requests)

      for {changes, diagnostic} <- [
            {%{"start" => "abc"}, "could not parse 'start' parameter"},
            {%{"end" => "bca"}, "could not parse 'end' parameter"},
            {%{"start" => "abc", "end" => "bca"}, "could not parse 'end' parameter"},
            {%{"end" => "bca", "since" => "bad"}, "could not parse 'end' parameter"},
            {%{"start" => "abc", "since" => "bad"}, "could not parse 'since' parameter:"}
          ] do
        invalid = Map.merge(params, changes)
        response = Req.get!(ctx.url <> path, headers: ctx.headers, params: invalid)
        assert response.status == 400
        assert response.body == diagnostic
        denied = Req.get!(ctx.url <> path, params: invalid)
        assert denied.status == 401
        assert denied.body == "unauthorized"
      end

      # These timestamps parse successfully; only window validation rejects.
      # They must not be relabelled as timestamp syntax errors.
      for changes <- [
            %{"start" => "1700003600"},
            %{"start" => "1700003601"},
            %{"start" => "1969-12-31T23:59:59.999999999Z"},
            %{"end" => "9223372036854775808"}
          ] do
        response = Req.get!(ctx.url <> path, headers: ctx.headers, params: Map.merge(params, changes))
        assert response.status == 400
        assert response.body == "invalid or unsupported trace lookup parameters"
      end

      assert Agent.get(ctx.store, & &1.requests) == before_requests
    end

    @tag :metric_timestamp_precision
    test "Tempo Test_parseTimestamp RFC3339nano exact 1ns oracle / #{endpoint}", ctx do
      # Original parser-only row: pkg/api/http_test.go Test_parseTimestamp.
      # The timestamp and its time.Date(..., 1, time.UTC) oracle are unchanged;
      # this numerical one-span HTTP consumer is authored, not an upstream metric oracle.
      timestamp = "2009-11-10T23:00:00.000000001Z"
      exact_ns = 1_257_894_000_000_000_001
      ingest_timestamp_probe(ctx, exact_ns)
      path = "/api/metrics/" <> unquote(endpoint)
      params = %{"q" => "{} | count_over_time()", "start" => exact_ns - 2, "step" => "1ns"}

      exact = get(ctx, path, Map.put(params, "end", exact_ns))
      assert metric_count(exact) == 1
      assert get(ctx, path, Map.put(params, "end", timestamp)) == exact

      for same <- ["2009-11-11T00:00:00.000000001+01:00", "2009-11-10T18:00:00.000000001-05:00"] do
        assert get(ctx, path, Map.put(params, "end", same)) == exact
      end

      for {bound, numeric, count} <- [
            {"2009-11-10T23:00:00Z", exact_ns - 1, 0},
            {"2009-11-10T23:00:00.000000000Z", exact_ns - 1, 0},
            {"2009-11-10T23:00:00.000000002Z", exact_ns + 1, 1}
          ] do
        expected = get(ctx, path, Map.put(params, "end", numeric))
        assert metric_count(expected) == count
        assert get(ctx, path, Map.put(params, "end", bound)) == expected
      end
    end

    @tag :metric_timestamp_precision
    test "Pulse authored fractional start and end boundary controls / #{endpoint}", ctx do
      exact_ns = 1_257_894_000_123_456_789
      ingest_timestamp_probe(ctx, exact_ns)
      path = "/api/metrics/" <> unquote(endpoint)

      # Tiny 1ns windows expose both bound tails, without changing Tempo's
      # range alignment (which adds a leading interval) or millisecond output.
      for {bound, numeric} <- [
            {"2009-11-10T23:00:00.123456788Z", exact_ns - 1},
            {"2009-11-10T23:00:00.123456789Z", exact_ns},
            {"2009-11-10T23:00:00.123456790Z", exact_ns + 1},
            {"2009-11-11T00:00:00.123456790+01:00", exact_ns + 1}
          ],
          side <- ["start", "end"] do
        params = %{
          "q" => "{} | count_over_time()",
          "start" => exact_ns - 2,
          "end" => exact_ns + 2,
          "step" => "1ns"
        }

        expected = get(ctx, path, Map.put(params, side, numeric))

        if unquote(endpoint) == "query" do
          count = if (side == "end" and numeric < exact_ns) or (side == "start" and numeric > exact_ns), do: 0, else: 1
          assert metric_count(expected) == count
        end

        assert get(ctx, path, Map.put(params, side, bound)) == expected
      end

      # Existing decimal seconds intentionally truncate at milliseconds;
      # integral seconds and integer nanoseconds retain their distinct meanings.
      for {bound, numeric} <- [
            {"1257894000", 1_257_894_000_000_000_000},
            {"1257894000.123456789", 1_257_894_000_123_000_000},
            {"2009-11-10T23:00:00.123456Z", 1_257_894_000_123_456_000},
            {"2009-11-10T23:00:00.123456789123Z", exact_ns}
          ] do
        params = %{"q" => "{} | count_over_time()", "start" => 1_257_894_000 - 1, "step" => "1s"}
        expected = get(ctx, path, Map.put(params, "end", numeric))
        assert get(ctx, path, Map.put(params, "end", bound)) == expected
      end
    end

    @tag :metric_timestamp_precision
    test "Pulse epoch-zero start and positive 1ns end / #{endpoint}", ctx do
      ingest_timestamp_probe(ctx, 1)
      path = "/api/metrics/" <> unquote(endpoint)
      params = %{"q" => "{} | count_over_time()", "start" => "0", "end" => "00000000001", "step" => "1ns"}
      expected = get(ctx, path, params)
      assert metric_count(expected) == 1

      for start <- ["1970-01-01T00:00:00Z", "1970-01-01T00:00:00.000000000Z"] do
        calendar = %{params | "start" => start, "end" => "1970-01-01T00:00:00.000000001Z"}
        assert get(ctx, path, calendar) == expected
      end
    end

    @tag :metric_timestamp_precision
    test "Pulse timestamp grammar and window rejections precede provider work / #{endpoint}", ctx do
      for invalid <- ["2009-11-10T23:00:00.000000001", "2009-11-31T23:00:00.000000001Z", "we", "-1", ""],
          side <- ["start", "end"] do
        params = %{"q" => "{} | count_over_time()", "start" => "1257893999", "end" => "1257894001", "step" => "1s"}
        before_requests = Agent.get(ctx.store, & &1.requests)

        response =
          Req.get!(ctx.url <> "/api/metrics/" <> unquote(endpoint),
            headers: ctx.headers,
            params: Map.put(params, side, invalid)
          )

        assert response.status == 400
        assert response.body == "could not parse '#{side}' parameter"
        assert Agent.get(ctx.store, & &1.requests) == before_requests
      end

      # Negative/zero windows remain policy errors, not new timestamp syntax.
      for {start, finish} <- [
            {"1969-12-31T23:59:59.999999999Z", "1970-01-01T00:00:01Z"},
            {"2009-11-10T23:00:00.000000001Z", "2009-11-10T23:00:00.000000001Z"}
          ] do
        before_requests = Agent.get(ctx.store, & &1.requests)

        response =
          Req.get!(ctx.url <> "/api/metrics/" <> unquote(endpoint),
            headers: ctx.headers,
            params: %{"q" => "{} | count_over_time()", "start" => start, "end" => finish, "step" => "1ns"}
          )

        assert response.status == 400
        assert response.body == "invalid or unsupported trace lookup parameters"
        assert Agent.get(ctx.store, & &1.requests) == before_requests
      end
    end
  end

  @tag :metric_invalid_bounds
  test "Pulse metric-bound controls: search and discovery retain endpoint-specific errors", ctx do
    before_requests = Agent.get(ctx.store, & &1.requests)

    for {path, message} <- [
          {"/api/search", ~s(invalid start: strconv.ParseUint: parsing "abc": invalid syntax)},
          {"/api/v2/search/tags", "invalid or unsupported trace lookup parameters"}
        ] do
      response =
        Req.get!(ctx.url <> path,
          headers: ctx.headers,
          params: %{"q" => "{}", "start" => "abc", "end" => "1700000000"}
        )

      assert response.status == 400
      assert response.body == message
    end

    assert Agent.get(ctx.store, & &1.requests) == before_requests
  end

  defp ingest_timestamp_probe(ctx, timestamp) do
    ingest(ctx, [
      %{
        "spanCount" => 1,
        "name" => "authored-timestamp-probe",
        "resourceAttr" => "probe",
        "resourceAttVal" => "timestamp",
        "spanAttr" => "probe",
        "spanAttVal" => "timestamp",
        "startNs" => timestamp,
        "durationNs" => 1
      }
    ])
  end

  defp metric_count(%{"series" => series}) do
    Enum.sum_by(series, fn row ->
      Map.get_lazy(row, "value", fn -> Enum.sum_by(row["samples"], & &1["value"]) end)
    end)
  end

  @tag :regex_literals_batch
  test "Go quoted and octal literals agree across retained search discovery and raw queries", ctx do
    inputs = ["ab", "abb", "a.b", ~S"\d", "ĀĀ", "\na", "+", "++"]

    ingest(
      ctx,
      for input <- inputs do
        %{
          "spanCount" => 1,
          "name" => "regex-literals",
          "resourceAttr" => "x",
          "resourceAttVal" => input,
          "spanAttr" => "x",
          "spanAttVal" => input
        }
      end
    )

    patterns = [
      ~S"\Qab\E+",
      ~S"\Qa.b",
      ~S"\Q\d\E",
      ~S"\141+",
      ~S"\400{2}",
      ~S"[\012-\234]\141",
      ~S"\Q+\E+",
      ~S"\Q(?P<fake>x)[\d]{2}\E"
    ]

    controls =
      "test/fixtures/regex/go-controls.json"
      |> File.read!()
      |> Pulse.JSON.decode!()
      |> Enum.filter(&(Map.has_key?(&1, "label_match") and &1["value"] in inputs and &1["pattern"] in patterns))
      |> Enum.group_by(& &1["pattern"])

    assert map_size(controls) == 8

    for {pattern, rows} <- controls do
      matches = for row <- rows, row["label_match"], do: row["value"]
      ids = for {input, index} <- Enum.with_index(inputs, 1), input in matches, do: Integer.to_string(index, 16)

      for scope <- ["resource", "span"] do
        query = "{ #{scope}.x =~ " <> Pulse.JSON.encode!(pattern) <> " }"
        response = get(ctx, "/api/search", %{"q" => query})
        assert Enum.sort(Enum.map(response["traces"], & &1["traceID"])) == Enum.sort(ids), query
        assert_values(ctx, 2, "span.x", Enum.sort(matches), %{"q" => query})
      end

      query = "{ resource.x =~ " <> Pulse.JSON.encode!(pattern) <> " }"

      args = %{
        "tenant" => ctx.tenant,
        "query" => query,
        "start_ts_ns" => (ctx.now - 10) * 1_000_000_000,
        "end_ts_ns" => ctx.now * 1_000_000_000
      }

      result = call_tool(ctx, "search_traces", args)
      expected = Enum.map(ids, &String.pad_leading(&1, 32, "0")) |> Enum.sort()

      assert result |> Map.fetch!("traces") |> Enum.map(& &1["trace_id"]) |> Enum.sort() ==
               expected

      for field <- ["resource_regex", "attributes_regex"] do
        args = %{"tenant" => ctx.tenant, "fields" => ["trace_id"], field => %{"x" => pattern}}
        assert call_tool(ctx, "query_traces", args) |> Enum.map(& &1["trace_id"]) |> Enum.sort() == expected
      end
    end
  end

  # Replays the Go regex corpus; under CI concurrency its native calls queue
  # behind other tests and can exceed ExUnit's 60 s default.
  @tag :regex_admission_batch
  @tag timeout: 300_000
  test "Go repetition classes and raw headers agree in retained trace predicates", ctx do
    inputs = [
      "x",
      String.duplicate("x", 999),
      String.duplicate("x", 1000),
      String.duplicate("x", 1001),
      String.duplicate("y", 500),
      "x{0001}",
      "x{1001",
      "x{,1001}"
    ]

    ingest(
      ctx,
      for input <- inputs do
        %{
          "spanCount" => 1,
          "name" => "regex-admission",
          "resourceAttr" => "x",
          "resourceAttVal" => input,
          "spanAttr" => "x",
          "spanAttVal" => input
        }
      end
    )

    cases =
      Enum.flat_map(
        [
          "admission-controls.json",
          "class-controls.json",
          "range-controls.json",
          "name-controls.json",
          "flag-controls.json",
          "unicode-controls.json",
          "nested-repetition-controls.json",
          "selector-name-controls.json"
        ],
        fn file ->
          ("test/fixtures/regex/" <> file) |> File.read!() |> Pulse.JSON.decode!() |> Map.fetch!("cases")
        end
      )

    for row <- cases, scope <- ["resource", "span"] do
      query = "{ #{scope}.x =~ " <> Pulse.JSON.encode!(row["pattern"]) <> " }"
      before_reads = Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests})
      response = Req.get!(ctx.url <> "/api/search", headers: ctx.headers, params: %{"q" => query})

      if row["valid"] do
        assert response.status == 200, query
        matches = for value <- row["values"], value["label_match"], do: String.duplicate(value["text"], value["repeat"])
        ids = for {input, index} <- Enum.with_index(inputs, 1), input in matches, do: Integer.to_string(index, 16)
        assert Enum.sort(Enum.map(response.body["traces"], & &1["traceID"])) == Enum.sort(ids), query
      else
        assert response.status == 400, query
        assert Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == before_reads
      end
    end
  end

  @tag :regex_properties_batch
  test "Unicode properties and scalar complements match upstream in retained trace search", ctx do
    inputs = [
      "x",
      "X",
      "K",
      "α",
      "\uA7CE",
      "\uA7CF",
      "\u{16EA0}",
      "\u{16EBB}",
      "\u{11DB0}",
      "\u0378",
      "XxX",
      "\u0345",
      "\u0399",
      "\uD7FE",
      "\uD7FF",
      "\uE000",
      "\uE001"
    ]

    ingest(
      ctx,
      for input <- inputs do
        %{
          "spanCount" => 1,
          "name" => "regex-properties",
          "resourceAttr" => "x",
          "resourceAttVal" => input,
          "spanAttr" => "x",
          "spanAttVal" => input
        }
      end
    )

    for path <- ["unicode-property-controls.json", "scalar-complement-controls.json"],
        row <- ("test/fixtures/regex/" <> path) |> File.read!() |> Pulse.JSON.decode!() |> Map.fetch!("cases"),
        Map.get(row, "http", true),
        scope <- ["resource", "span"] do
      query = "{ #{scope}.x =~ " <> Pulse.JSON.encode!(row["pattern"]) <> " }"
      before_reads = Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests})
      response = Req.get!(ctx.url <> "/api/search", headers: ctx.headers, params: %{"q" => query})

      if row["valid"] do
        assert response.status == 200, query
        matches = for value <- row["values"], value["label_match"], do: value["text"]

        ids =
          for {input, index} <- Enum.with_index(inputs, 1),
              input in matches,
              do: index |> Integer.to_string(16) |> String.downcase()

        actual = Enum.sort(Enum.map(response.body["traces"], & &1["traceID"]))
        assert actual == Enum.sort(ids), inspect({query, actual, Enum.sort(ids)})
      else
        assert response.status == 400, query
        assert Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == before_reads
      end
    end
  end

  test "TestTagEndpoints: v1 unscoped names and service values from persisted data", ctx do
    ingest(ctx, @cases["batches"])

    for window <- windows(ctx) do
      assert get(ctx, "/api/search/tags", window) == %{"tagNames" => @cases["tagNames"]}
      assert_values(ctx, 1, "service.name", ["my-service"], window)
    end
  end

  for row <- @cases["names"] do
    @tag :name_vocabulary
    test "TestTagEndpoints: v2 name content / #{row["name"]}", ctx do
      row = unquote(Macro.escape(row))
      ingest(ctx, @cases["batches"])

      # Upstream adds the virtual vocabulary after constructing each scope
      # table, then sorts scopes/tags. Keep that original helper behavior.
      scopes =
        if row["scope"] == "none",
          do: [%{"name" => "intrinsic", "tags" => @intrinsic_names} | row["expected"]],
          else: row["expected"]

      expected = %{"scopes" => Enum.sort_by(scopes, & &1["name"])}

      for window <- windows(ctx) do
        params = Map.merge(window, %{"scope" => row["scope"], "q" => row["query"]})
        assert get(ctx, "/api/v2/search/tags", params) == expected

        response =
          Req.get!(ctx.url <> "/api/v2/search/tags",
            headers: [{"accept", "application/protobuf"} | ctx.headers],
            params: params
          )

        assert response.status == 200
        assert response.body == Protobuf.encode(expected, :tags_v2)
      end
    end
  end

  @tag :name_vocabulary
  test "Pulse controls: current intrinsic names are vocabulary, never ID-value support or unauthenticated access",
       ctx do
    before_requests = Agent.get(ctx.store, & &1.requests)
    expected = %{"scopes" => [%{"name" => "intrinsic", "tags" => @intrinsic_names}]}

    for window <- windows(ctx) do
      params = Map.put(window, "scope", "intrinsic")
      assert get(ctx, "/api/v2/search/tags", params) == expected
      assert get(ctx, "/api/search/tags", params) == %{"tagNames" => @intrinsic_names}
    end

    assert call_tool(ctx, "discover_trace_tags", %{"tenant" => ctx.tenant, "scope" => "intrinsic"}) == expected

    for key <- ~w(link:spanID link:traceID span:id span:parentID trace:id) do
      response = Req.get!(ctx.url <> values_path(2, key), headers: ctx.headers)
      assert response.status == 400
    end

    denied = Req.get!(ctx.url <> "/api/v2/search/tags", params: %{"scope" => "intrinsic"})
    assert denied.status == 401
    assert Agent.get(ctx.store, & &1.requests) == before_requests
  end

  test "TestSearchTraceQL: original resource and span attributes find the persisted trace with default or explicit bounds",
       ctx do
    ingest(ctx, @cases["batches"])

    # Replace the upstream randomly selected original string with one fixed
    # attribute from each owner; trace 1 is the first upstream batch above.
    for key <- ["firstRes", "firstSpan"], window <- windows(ctx) do
      query = ~s({ .#{key} = "bar" })
      response = get(ctx, "/api/search", Map.put(window, "q", query))
      assert Enum.map(response["traces"], & &1["traceID"]) == ["1"]
      assert hd(response["traces"])["rootServiceName"] == "my-service"
      assert hd(response["traces"])["spanSet"]["matched"] == 2
    end
  end

  test "omitted and zero search bounds scan retained context, while malformed or partial bounds reject", ctx do
    ingest(ctx, @cases["batches"])
    query = ~s({ resource.firstRes = "bar" })
    expected = get(ctx, "/api/search", %{"q" => query, "start" => ctx.now - 7200, "end" => ctx.now + 7200})

    for window <- [%{}, %{"start" => 0, "end" => 0}] do
      assert get(ctx, "/api/search", Map.put(window, "q", query)) == expected
    end

    for window <- [
          %{"start" => ctx.now - 10},
          %{"end" => ctx.now + 10},
          %{"start" => 0, "end" => ctx.now + 10},
          %{"start" => "-1", "end" => ctx.now},
          %{"start" => "1.5", "end" => ctx.now},
          %{"start" => 4_294_967_296, "end" => 4_294_967_297},
          %{"start" => ctx.now + 1, "end" => ctx.now}
        ] do
      response = Req.get!(ctx.url <> "/api/search", headers: ctx.headers, params: Map.put(window, "q", query))
      assert response.status == 400, inspect(window)
    end
  end

  test "public-engine unscoped collisions retain exact search metadata after HTTP ingestion and restart", ctx do
    dir = Path.expand("../../fixtures/traces/tempo_integration", __DIR__)
    wire = File.read!(Path.join(dir, "search-input.protobuf"))

    response =
      Req.post!(ctx.url <> "/v1/traces",
        headers: [{"content-type", "application/x-protobuf"} | ctx.headers],
        body: wire
      )

    assert response.status == 200
    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)

    for c <- dir |> Path.join("search-oracle.json") |> File.read!() |> Pulse.JSON.decode!() do
      params = %{"q" => c["query"], "start" => c["Start"], "end" => c["End"]}
      assert get(ctx, "/api/search", params) === c["response"], c["query"]
    end
  end

  @tag :trace_by_id_upstream
  test "TestTraceByIDandTraceQL: all ten original rich traces survive v1/v2 exact-ID reads", ctx do
    fixture = ingest_trace_infos(ctx)

    for phase <- [:published, :fresh_manifest] do
      if phase == :fresh_manifest do
        assert :ok = stop_supervised(ManifestSupervision)
        start_supervised!(ManifestSupervision)
      end

      for row <- fixture["traces"] do
        expected = canonical_trace_info(row["expected"])
        v1 = get(ctx, "/api/traces/" <> row["traceID"], %{})
        v2 = get(ctx, "/api/v2/traces/" <> row["traceID"], %{})
        assert canonical_trace_info(%{"resourceSpans" => v1["batches"]}) === expected
        assert canonical_trace_info(v2["trace"]) === expected
        assert Map.get(v2, "status", "COMPLETE") == "COMPLETE"

        for {prefix, body, schema} <- [
              {"/api/traces/", v1, :export},
              {"/api/v2/traces/", %{"trace" => %{"batches" => v2["trace"]["resourceSpans"]}}, :response}
            ] do
          response =
            Req.get!(ctx.url <> prefix <> row["traceID"],
              headers: [{"accept", "application/protobuf"} | ctx.headers]
            )

          assert response.status == 200
          assert response.body == Protobuf.encode(body, schema)
        end
      end
    end
  end

  @tag :trace_by_id_upstream
  test "Pulse deliberate incompatibility: original multi-root trace searches reject whole", ctx do
    fixture = ingest_trace_infos(ctx)

    # The unchanged upstream helper asserts row["traceID"] is found. Executing
    # that assertion failed with 409 trace_root_conflict (seed 701). Do not
    # relabel these as passing upstream search cases or rewrite the producer's
    # parent graph to evade Pulse's documented fail-whole root-summary policy.
    for phase <- [:published, :fresh_manifest] do
      if phase == :fresh_manifest do
        assert :ok = stop_supervised(ManifestSupervision)
        start_supervised!(ManifestSupervision)
      end

      for row <- fixture["traces"], query <- row["queries"] do
        params = %{"q" => query, "start" => fixture["anchor"] - 3600, "end" => fixture["anchor"] + 3600}
        response = Req.get!(ctx.url <> "/api/search", headers: ctx.headers, params: params)
        assert response.status == 409, inspect({phase, row["traceID"], query})
        assert response.body == "trace_root_conflict"
      end
    end
  end

  test "TestTagEndpoints: six complete v2 value cases retain upstream filters and expected values", ctx do
    ingest(ctx, @cases["batches"])

    for window <- windows(ctx), row <- @cases["values"] do
      assert_values(ctx, 2, row["tag"], row["expected"], Map.put(window, "q", row["query"]))
    end
  end

  for scope <- ["resource", "span"], {window_name, window_index} <- [{"retained", 0}, {"explicit", 1}] do
    @tag :special_characters
    test "TestTagValuesWithSpecialCharacters: all 19 pairs in #{scope} with #{window_name} bounds", ctx do
      batches =
        for [key, value] <- @cases["specialCharacters"] do
          %{
            "spanCount" => 1,
            "name" => "test-service",
            "resourceAttr" => key,
            "resourceAttVal" => value,
            "spanAttr" => key,
            "spanAttVal" => value
          }
        end

      # Retain all 19 pairs together, but give each scope/window its own deadline.
      ingest(ctx, batches)
      window = Enum.at(windows(ctx), unquote(window_index))

      for [key, value] <- @cases["specialCharacters"] do
        # Tempo quotes identifiers containing TraceQL delimiters, not URL delimiters.
        identifier = if Regex.match?(~r/[\s{}()=~!<>&|^,]/u, key), do: Pulse.JSON.encode!(key), else: key
        assert_values(ctx, 2, unquote(scope) <> "." <> identifier, [value], window)
      end
    end
  end

  test "TestTagValuesWithSpecialCharacters: slash works escaped and as a path separator", ctx do
    ingest(ctx, [
      %{
        "spanCount" => 1,
        "name" => "test-service",
        "resourceAttr" => "attr/slash",
        "resourceAttVal" => "val/",
        "spanAttr" => "attr/slash",
        "spanAttVal" => "val/"
      }
    ])

    for window <- windows(ctx) do
      assert_values(ctx, 2, "span.attr/slash", ["val/"], window)

      assert get(ctx, "/api/v2/search/tag/span.attr/slash/values", window) ==
               %{"tagValues" => [%{"type" => "string", "value" => "val/"}]}
    end
  end

  for version <- [1, 2] do
    @tag :segmented_identifiers
    test "Tempo TestParseIdentifier five mixed quoted mappings / v#{version}", ctx do
      # Complete selected parser rows, not upstream HTTP result oracles.
      rows = [
        {~s(."bar z".foo), "bar z.foo", "one"},
        {~s(."bar z".foo."bar"), "bar z.foo.bar", "two"},
        {~s(.foo."bar baz"), "foo.bar baz", "three"},
        {~s(.foo."bar baz".bar), "foo.bar baz.bar", "four"},
        {~s(span."bar z".foo), "bar z.foo", "one"}
      ]

      # Authored one-span producer, values, transport/filter/window controls.
      attributes =
        rows
        |> Enum.uniq_by(&elem(&1, 1))
        |> Enum.map(fn {_, key, value} -> %{"key" => key, "value" => %{"stringValue" => value}} end)

      ingest(ctx, [
        %{
          "spanCount" => 1,
          "name" => "authored-segmented-identifiers",
          "resourceAttr" => "probe",
          "resourceAttVal" => "segmented",
          "spanAttr" => "probe",
          "spanAttVal" => "segmented",
          "extraSpanAttributes" => attributes
        }
      ])

      for {target, key, value} <- rows,
          window <- windows(ctx),
          filter <- [nil, ~s({resource.service.name="my-service"})] do
        params = if filter, do: Map.put(window, "q", filter), else: window
        prefix = if String.starts_with?(target, "span."), do: "span.", else: "."
        assert_values(ctx, unquote(version), prefix <> Pulse.JSON.encode!(key), [value], params)
        assert_values(ctx, unquote(version), target, [value], params)
      end

      before_requests = Agent.get(ctx.store, & &1.requests)

      for {target, _, _} <- rows do
        response = Req.get!(ctx.url <> values_path(unquote(version), target))
        assert response.status == 401
        assert response.body == "unauthorized"
      end

      assert Agent.get(ctx.store, & &1.requests) == before_requests
      assert Enum.any?(Agent.get(ctx.store, & &1.reads), &String.ends_with?(&1, ".parquet"))
    end

    @tag :segmented_identifiers
    test "Pulse mixed identifier escapes decoded byte bounds and malformed admission / v#{version}", ctx do
      long = String.duplicate("é", 127)
      boundary = long <> ".x"
      assert byte_size(boundary) == 256

      # Authored controls informed by the pinned lexer: only quote/backslash
      # escapes are decoded, never JSON newline/hex/Unicode escapes.
      rows = [
        {~S(span.foo."quote\"key"), "foo.quote\"key", "quote"},
        {~S(span.foo."slash\\key"), "foo.slash\\key", "backslash"},
        {~s(span."#{long}".x), boundary, "boundary"}
      ]

      # Preserve the documented whole-key JSON contract, including decoded
      # controls and surrogate pairs accepted by existing key validation.
      whole_rows = [
        {~S(span."unicode\u0020key"), "unicode key", "unicode"},
        {~S(span."bad\n"), "bad\n", "newline"},
        {~S(span."nul\u0000key"), "nul\0key", "nul"},
        {~S(span."surrogate\uD83E\uDD18"), "surrogate🤘", "surrogate"},
        {~s(span.") <> String.duplicate(~S(\u00e9), 127) <> ~s(.x"), boundary, "boundary"}
      ]

      attributes =
        (rows ++ whole_rows)
        |> Enum.uniq_by(&elem(&1, 1))
        |> Enum.map(fn {_, key, value} -> %{"key" => key, "value" => %{"stringValue" => value}} end)

      ingest(ctx, [
        %{
          "spanCount" => 1,
          "name" => "authored-segmented-controls",
          "resourceAttr" => "probe",
          "resourceAttVal" => "segmented",
          "spanAttr" => "probe",
          "spanAttVal" => "segmented",
          "extraSpanAttributes" => attributes
        }
      ])

      for {target, key, value} <- rows ++ whole_rows do
        assert_values(ctx, unquote(version), "span." <> Pulse.JSON.encode!(key), [value], %{})
        assert_values(ctx, unquote(version), target, [value], %{})
      end

      before_requests = Agent.get(ctx.store, & &1.requests)

      for target <- [
            ~s(span."#{long}".xy),
            ~s(span.") <> String.duplicate(~S(\u00e9), 127) <> ~s(.xy"),
            "span.\"" <> String.duplicate("x", 2049) <> "\"",
            ~s(span.foo."unterminated),
            ~s(span.foo."trailing) <> <<92>>,
            ~S(span.foo."bad\q"),
            ~S(span.foo."bad\n"),
            ~S(span.foo."bad\u0041"),
            ~S(span."bad\n".foo),
            ~S(span."bad\u0041".foo),
            "span.foo.\"raw\ncontrol\"",
            "span.\"raw\tcontrol\"",
            ~s(span.foo."bar"suffix),
            ~s(span.foo."bar""baz"),
            ~s(span.foo"bar"),
            ~s(span.foo bar."baz"),
            ~s(span.""),
            ~s[span.foo."bar" | rate()]
          ] do
        response = Req.get!(ctx.url <> values_path(unquote(version), target), headers: ctx.headers)
        assert response.status == 400, inspect({target, response.status, response.body})
        assert response.body == "invalid or unsupported trace lookup parameters"
      end

      # Normalizing the target does not widen discovery's predicate grammar.
      response =
        Req.get!(ctx.url <> values_path(unquote(version), ~S(span.foo."quote\"key")),
          headers: ctx.headers,
          params: %{"q" => ~s({span."probe"="segmented"})}
        )

      assert response.status == 400
      assert response.body == "invalid or unsupported trace lookup parameters"
      assert Agent.get(ctx.store, & &1.requests) == before_requests
    end
  end

  test "TestSearchTagValuesV2_badRequest: unknown attribute scope rejects", ctx do
    response = Req.get!(ctx.url <> "/api/v2/search/tag/app.user.id/values", headers: ctx.headers)
    assert response.status == 400
    assert response.body == "invalid or unsupported trace lookup parameters"
  end

  test "quoted names are exact keys, malformed names reject and credentials still bind the tenant", ctx do
    ingest(ctx, [
      %{
        "spanCount" => 1,
        "name" => "test-service",
        "resourceAttr" => "attr%20literal",
        "resourceAttVal" => "literal",
        "spanAttr" => "attr/values/space",
        "spanAttVal" => "space"
      }
    ])

    assert_values(ctx, 1, "attr%20literal", ["literal"], %{})
    assert_values(ctx, 2, ~s(span."attr/values/space"), ["space"], %{})
    assert_values(ctx, 2, ~s(span."missing key"), [], %{})

    for target <- [~s(span."unterminated), ~s(span."attr space"suffix), ~s(span.""), ~S(span."bad\q")] do
      response = Req.get!(ctx.url <> values_path(2, target), headers: ctx.headers)
      assert response.status == 400, "malformed target #{inspect(target)} returned #{response.status}"
    end

    for path <- ["/api/v2/search/tag/span.attr", "/api/v2/search/tag/span.attr/values/extra"] do
      assert Req.get!(ctx.url <> path, headers: ctx.headers).status == 404
    end

    headers = List.keyreplace(ctx.headers, "authorization", 0, {"authorization", "Bearer wrong"})
    assert Req.get!(ctx.url <> values_path(2, ~s(span."attr/values/space")), headers: headers).status == 401
  end

  test "TestTraceByIDV2Filtering: all 31 depth combinations preserve matched sets and partial status", ctx do
    ingest_filter_trace(ctx)
    path = "/api/v2/traces/1"
    full = get(ctx, path, %{})
    assert filter_ids(full) == [1, 2, 3, 4, 5, 6]
    assert Map.get(full, "status", "COMPLETE") == "COMPLETE"

    cases =
      "../../fixtures/traces/tempo_integration/filter-cases.json"
      |> Path.expand(__DIR__)
      |> File.read!()
      |> Pulse.JSON.decode!()

    assert length(cases) == 31

    for row <- cases do
      query = if row["two_matches"], do: "{ .http.status_code > 0 }", else: "{ .http.status_code = 500 }"
      params = Map.put(row["params"], "q", query)
      response = get(ctx, path, params)
      assert filter_ids(response) == row["ids"], row["name"]

      if row["complete"] do
        assert Map.get(response, "status", "COMPLETE") == "COMPLETE"
        assert Map.get(response, "message", "") == ""
      else
        assert response["status"] == "PARTIAL", row["name"]
        assert response["message"] =~ "only a subset of spans matching the filter"
      end

      # Additional transport control: schema fields 3/4 carry PARTIAL/message.
      trace = %{"batches" => Map.get(response["trace"], "resourceSpans", [])}
      envelope = response |> Map.put("trace", trace)
      wire = Req.get!(ctx.url <> path, headers: [{"accept", "application/protobuf"} | ctx.headers], params: params)
      assert wire.status == 200
      assert wire.body == Protobuf.encode(envelope, :response)

      if !row["complete"] do
        message = "Trace filtered, only a subset of spans matching the filter is returned"
        # Independently check the public TraceByIDResponse field numbers/types,
        # rather than deriving this expectation from Pulse's schema encoder.
        assert String.ends_with?(wire.body, <<0x18, 1, 0x22, byte_size(message)>> <> message)
      end
    end
  end

  test "TestTraceByIDV2Filtering: malformed filters and active depths reject, inactive ancestors are ignored", ctx do
    ingest_filter_trace(ctx)
    path = "/api/v2/traces/1"
    query = "{ .http.status_code = 500 }"

    for params <- [
          %{"q" => "{ .a = }"},
          %{"q" => query, "match_depth" => "-2"},
          %{"q" => query, "match_depth" => "abc"},
          %{"q" => query, "keep_hierarchy" => "true", "ancestor_depth" => "-2"},
          %{"q" => query, "keep_hierarchy" => "true", "ancestor_depth" => "abc"}
        ] do
      response = Req.get!(ctx.url <> path, headers: ctx.headers, params: params)
      assert response.status == 400
    end

    for params <- [
          %{"ancestor_depth" => "-2"},
          %{"ancestor_depth" => "abc"},
          %{"keep_hierarchy" => "false", "ancestor_depth" => "-2"}
        ] do
      assert filter_ids(get(ctx, path, Map.put(params, "q", query))) == [3]
    end

    # The default HTTP server rejects the upstream 150KiB filter at its URI
    # boundary before dispatch; do not relax that transport ceiling for parity.
    oversized = ~s({ span.foo = "#{String.duplicate("x", 150 * 1024)}" })
    assert Req.get!(ctx.url <> path, headers: ctx.headers, params: %{"q" => oversized}).status == 414
    assert {:error, :unsupported_parameters} = TempoFilter.parse(%{"q" => oversized})
  end

  test "Pulse filtering controls: empty selections are explicit, and filtering never mutates the full trace", ctx do
    ingest_filter_trace(ctx)
    path = "/api/v2/traces/1"
    full = get(ctx, path, %{})

    for query <- ["", " \t ", "{}", "{  }"] do
      assert get(ctx, path, %{"q" => query}) == full
    end

    for {query, ids} <- [
          {~s'{ resource.service.name = "filter-test" && (.http.status_code = 500 || .http.status_code = 200) }',
           [3, 4]},
          {~s({ resource.service.name =~ "filter.*" }), [1, 2, 3, 4, 5, 6]},
          {"{ duration = 1ms && status = unset }", [1, 2, 3, 4, 5, 6]},
          {~s({ span.http.status_code = "500" }), []}
        ] do
      assert filter_ids(get(ctx, path, %{"q" => query})) == ids
    end

    assert get(ctx, path, %{"q" => " ", "keep_hierarchy" => "invalid", "match_depth" => "-2"}) == full

    params = %{"q" => "{ .http.status_code = 404 }", "match_depth" => "-1", "keep_hierarchy" => "true"}
    empty = Req.get!(ctx.url <> path, headers: ctx.headers, params: params)
    assert empty.status == 200
    assert empty.body["trace"] == %{}
    assert empty.body["status"] == "PARTIAL"
    assert empty.body["message"] =~ "only a subset of spans matching the filter"

    assert empty.headers["x-pulse-trace-coverage"] == [
             "explicit-filter-subset-of-all-visible-stored-spans; exporter-completeness-unknown"
           ]

    wire = Req.get!(ctx.url <> path, headers: [{"accept", "application/protobuf"} | ctx.headers], params: params)
    assert wire.status == 200
    message = "Trace filtered, only a subset of spans matching the filter is returned"
    assert wire.body == <<10, 0, 24, 1, 34, byte_size(message)>> <> message
    assert get(ctx, path, %{}) == full

    query = %{"q" => "{ .http.status_code = 500 }"}
    assert Req.get!(ctx.url <> "/api/traces/1", headers: ctx.headers, params: query).status == 400

    assert Req.get!(ctx.url <> path, headers: ctx.headers, params: Map.put(query, "allowPartialTrace", "true")).status ==
             400

    assert Req.get!(ctx.url <> path, params: query).status == 401

    for value <- ["-2", "9223372036854775808", "1.5", "1x"] do
      assert Req.get!(ctx.url <> path, headers: ctx.headers, params: Map.put(query, "match_depth", value)).status == 400
    end

    assert Req.get!(ctx.url <> path, headers: ctx.headers, params: %{"q" => "{} >> {}"}).status == 400
    too_many_leaves = "{" <> Enum.join(List.duplicate(".http.status_code = 500", 17), " && ") <> "}"
    assert Req.get!(ctx.url <> path, headers: ctx.headers, params: %{"q" => too_many_leaves}).status == 400

    Runtime.put_env(:pulse, Pulse.QueryRunner, max_scan_rows: 1)
    assert {:ok, filter} = TempoFilter.parse(params)
    assert {:error, :query_scan_limit} = Tempo.lookup(ctx.tenant, String.pad_leading("1", 32, "0"), "json_v2", filter)
  end

  test "Pulse filtering controls: bounded graph walks terminate on cycles and do not invent missing parents", ctx do
    ingest_filter_trace(ctx, [
      {1, 2, 0},
      {2, 3, 0},
      {3, 1, 500},
      {4, 3, 0},
      {5, 4, 200},
      {6, 99, 500},
      {7, 6, 0},
      {8, 0, 0}
    ])

    path = "/api/v2/traces/1"
    query = %{"q" => "{ .http.status_code = 500 }"}

    for {params, ids} <- [
          {%{}, [3, 6]},
          {%{"match_depth" => "1"}, [2, 3, 4, 6, 7]},
          {%{"keep_hierarchy" => "true", "ancestor_depth" => "1"}, [1, 3, 6]},
          {%{"keep_hierarchy" => "true", "ancestor_depth" => "1", "match_depth" => "1"}, [1, 2, 3, 4, 6, 7]},
          {%{"match_depth" => "-1"}, [1, 2, 3, 4, 5, 6, 7]},
          {%{"match_depth" => "9223372036854775807"}, [1, 2, 3, 4, 5, 6, 7]},
          {%{"keep_hierarchy" => "true"}, [1, 2, 3, 6]}
        ] do
      result = get(ctx, path, Map.merge(query, params))
      assert filter_ids(result) == ids
      assert result["status"] == "PARTIAL"
    end
  end

  for {change, reason} <- [{:legacy, "trace_metadata_unknown"}, {:conflict, "trace_span_id_conflict"}] do
    test "Pulse filtering controls: nonmatching #{change} spans still fail the entire lookup", ctx do
      ingest_filter_trace(ctx)
      assert {:ok, spans} = Storage.query(:traces, ctx.tenant, [])
      nonmatch = Enum.find(spans, &(&1.span_id == "0000000000000004"))
      changed = if unquote(change) == :legacy, do: %{nonmatch | otlp: nil}, else: %{nonmatch | name: "conflicting"}
      assert :ok = Storage.append(:traces, ctx.tenant, [changed])

      for query <- ["{ .http.status_code = 500 }", "{ .http.status_code = 404 }"] do
        response = Req.get!(ctx.url <> "/api/v2/traces/1", headers: ctx.headers, params: %{"q" => query})
        assert response.status == 409
        assert response.body =~ unquote(reason)
      end
    end
  end

  for owner <- [:links, :events] do
    test "Pulse filtering controls: malformed nonmatching #{owner} still fail the entire lookup", ctx do
      ingest_filter_trace(ctx)
      assert filter_ids(get(ctx, "/api/v2/traces/1", %{"q" => "{ .http.status_code = 500 }"})) == [3]

      assert {:ok, [rich], 0} =
               Traces.decode(OTLPTraceFixture.payload([OTLPTraceFixture.span((ctx.now - 3) * 1_000_000_000)]))

      changed = %{rich | trace_id: String.pad_leading("1", 32, "0"), span_id: "0000000000000007"}

      changed =
        case unquote(owner) do
          :links -> %{changed | links: [Map.put(hd(changed.links), "trace_id", "not-a-trace-id")]}
          :events -> %{changed | events: [Map.put(hd(changed.events), "timestamp_ns", -1)]}
        end

      assert :ok = Storage.append(:traces, ctx.tenant, [changed])

      for query <- [nil, "{ .http.status_code = 500 }", "{ .http.status_code = 404 }"],
          accept <- ["application/json", "application/protobuf"] do
        params = if query, do: %{"q" => query}, else: %{}

        response =
          Req.get!(ctx.url <> "/api/v2/traces/1",
            headers: [{"accept", accept} | ctx.headers],
            params: params,
            retry: false
          )

        assert response.status == 500
        assert response.body == "stored trace cannot be exported faithfully"
      end
    end
  end

  # integration/api/metrics/query_range_test.go: TestQueryRangeExemplars
  # contains these metric-only subtests too. No exemplar assertion is selected.
  describe "TestQueryRangeExemplars / metric-only tables" do
    setup ctx do
      # Freeze twenty half-second producer ticks and random UUIDs. A minute
      # boundary keeps every batch inside both aligned upstream query windows.
      now = div(ctx.now, 60) * 60
      ctx = %{ctx | now: now}
      ingest_metric_batches(ctx)
      %{now: now}
    end

    for {name, offset_ns, step, intervals} <- [
          {"aligned", 0, "1m", 3},
          {"unaligned", 500_000_000, "1m", 4},
          {"default step", 500_000_000, nil, 122}
        ] do
      test "intervals / #{name}", ctx do
        finish = ctx.now * 1_000_000_000 + unquote(offset_ns)
        params = %{"q" => "{} | count_over_time()", "start" => finish - 120_000_000_000, "end" => finish}
        params = if unquote(step), do: Map.put(params, "step", unquote(step)), else: params
        assert %{"series" => [series]} = get(ctx, "/api/metrics/query_range", params)
        assert length(series["samples"]) == unquote(intervals)
        # Independent control: the exact frozen input is sixty single spans.
        assert Enum.sum_by(series["samples"], & &1["value"]) == 60
      end
    end

    for query <- [
          "{status=error} | count_over_time()",
          ~s'{span.randomattr = "doesnotexist"} | count_over_time()'
        ] do
      test "empty results / #{query}", ctx do
        params = %{"q" => unquote(query), "start" => ctx.now - 300, "end" => ctx.now + 60, "step" => "5s"}
        result = get(ctx, "/api/metrics/query_range", params)
        assert [_ | _] = result["series"]
        assert Enum.sum_by(result["series"], &length(Map.get(&1, "exemplars", []))) == 0
      end
    end

    for {name, step} <- [{"step=0 (default step)", "0"}, {"step=0s (default step)", "0s"}, {"small step", "35ms"}] do
      @tag :metric_step_validation
      test "HTTP validation / #{name}", ctx do
        params = %{
          "q" => "{} | count_over_time()",
          "start" => ctx.now - 300,
          "end" => ctx.now + 60,
          "step" => unquote(step)
        }

        before_requests = Agent.get(ctx.store, & &1.requests)
        response = Req.get!(ctx.url <> "/api/metrics/query_range", headers: ctx.headers, params: params)
        assert response.status == 400

        if unquote(step) == "35ms" do
          assert response.body =~ "step of 35ms is too small, minimum step for given range is 36ms"
        end

        assert Agent.get(ctx.store, & &1.requests) == before_requests
      end
    end

    for {name, query, step, reduction, expected} <- [
          {"count_over_time", "{} | count_over_time()", "1s", :sum, 60},
          {"sum_over_time", "{} | sum_over_time(duration)", "1s", :sum, 0.00006},
          {"max_over_time", "{} | max_over_time(duration)", "1s", :max, 0.000001},
          {"min_over_time", "{} | min_over_time(duration)", "1s", :min, 0.000001},
          {"1m step", "{} | count_over_time()", "1m", :sum, 60}
        ] do
      test "instant and range / #{name}", ctx do
        params = %{"q" => unquote(query), "start" => ctx.now - 300, "end" => ctx.now + 60, "step" => unquote(step)}
        assert %{"series" => [range]} = get(ctx, "/api/metrics/query_range", params)
        assert %{"series" => [instant]} = get(ctx, "/api/metrics/query", params)
        values = Enum.map(range["samples"], & &1["value"])

        reduced =
          case unquote(reduction) do
            :sum -> Enum.sum(values)
            :max -> Enum.max(values)
            :min -> Enum.min(values)
          end

        assert_in_delta instant["value"], reduced, 1.0e-12
        assert_in_delta instant["value"], unquote(expected), 1.0e-12
      end
    end

    test "avg_over_time instant query", ctx do
      params = %{"start" => ctx.now - 300, "end" => ctx.now + 60}

      results =
        Map.new(["avg", "sum", "count"], fn op ->
          argument = if op == "count", do: "", else: "duration"
          query = "{} | #{op}_over_time(#{argument})"
          assert %{"series" => [series]} = get(ctx, "/api/metrics/query", Map.put(params, "q", query))
          {op, series["value"]}
        end)

      assert results["count"] == 60
      assert_in_delta results["avg"], results["sum"] / results["count"], 1.0e-12
      assert_in_delta results["avg"], 0.000001, 1.0e-12
    end

    for {name, query, count} <- [
          {"top 1 by span attribute", "{ } | rate() by (span.span_high_cardinality) | topk(1)", 1},
          {"top 10 by span attribute", "{ } | rate() by (span.span_high_cardinality) | topk(10)", 10},
          {"top 2 by resource attribute", "{ } | rate() by (resource.res_high_cardinality) | topk(2)", 2},
          {"bottom 1 by resource attribute", "{ } | rate() by (resource.res_high_cardinality) | bottomk(1)", 1},
          {"bootom 10 by resource attribute", "{ } | rate() by (resource.res_high_cardinality) | bottomk(10)", 10},
          {"bottom 2 by span attribute", "{ } | rate() by (span.span_high_cardinality) | bottomk(2)", 2}
        ] do
      test "ranking / #{name}", ctx do
        params = %{"q" => unquote(query), "start" => ctx.now - 300, "end" => ctx.now + 60, "step" => "1m"}
        result = get(ctx, "/api/metrics/query", params)
        assert length(result["series"]) == unquote(count)
      end
    end
  end

  for step <- ["-1h", "-30m", "-1.5", "-0.001"] do
    @tag :metric_negative_step
    test "Tempo TestParseQueryRangeNegativeStep / #{step}", ctx do
      # Complete original table: pkg/api/http_test.go:1276-1287. No numeric
      # producer is required by this request-parser rejection oracle.
      params = %{"q" => "{} | rate()", "start" => "1700000000", "end" => "1700003600", "step" => unquote(step)}
      before_requests = Agent.get(ctx.store, & &1.requests)
      response = Req.get!(ctx.url <> "/api/metrics/query_range", headers: ctx.headers, params: params)
      assert response.status == 400
      assert response.body =~ "step must be positive"
      assert response.body == ~s(cannot parse "#{unquote(step)}": step must be positive)
      assert Agent.get(ctx.store, & &1.requests) == before_requests
    end
  end

  @tag :metric_negative_step
  test "Pulse negative-step controls: positive S3 execution and instant ignoring", ctx do
    # Authored producer/control, not part of the upstream parser test.
    ingest_timestamp_probe(ctx, 1_700_001_800_000_000_000)
    params = %{"q" => "{} | rate()", "start" => "1700000000", "end" => "1700003600", "step" => "1h"}
    before_reads = Agent.get(ctx.store, & &1.reads)
    assert metric_count(get(ctx, "/api/metrics/query_range", params)) == 1 / 3600
    assert Agent.get(ctx.store, & &1.reads) != before_reads
    expected = get(ctx, "/api/metrics/query", params)
    assert metric_count(expected) == 1 / 3600

    for step <- ["-1h", "-30m", "-1.5", "-0.001", "0", "malformed"] do
      assert get(ctx, "/api/metrics/query", Map.put(params, "step", step)) == expected
    end

    # Even with visible Parquet, negative range steps and unauthorized requests
    # reject before contacting the provider.
    before_requests = Agent.get(ctx.store, & &1.requests)

    for step <- ["-1h", "-30m", "-1.5", "-0.001"] do
      negative = Map.put(params, "step", step)
      response = Req.get!(ctx.url <> "/api/metrics/query_range", headers: ctx.headers, params: negative)
      assert response.status == 400
      assert response.body =~ "step must be positive"
      denied = Req.get!(ctx.url <> "/api/metrics/query_range", params: negative)
      assert denied.status == 401
      assert denied.body == "unauthorized"
    end

    assert Agent.get(ctx.store, & &1.requests) == before_requests
  end

  @tag :metric_negative_step
  test "Pulse negative-step controls: malformed zero since and minimum-step policies stay distinct", ctx do
    params = %{"q" => "{} | rate()", "start" => "1700000000", "end" => "1700003600", "step" => "1h"}
    before_requests = Agent.get(ctx.store, & &1.requests)

    for {key, value} <- [
          {"step", "0"},
          {"step", "0s"},
          {"step", "-0"},
          {"step", "-0s"},
          {"step", "--1h"},
          {"step", "-+1h"},
          {"step", "--1.5"},
          {"step", "-1d"},
          {"step", "-garbage"},
          {"step", "-1xs"},
          {"step", "-1e999"},
          {"since", "-1h"},
          {"since", "-1.5"},
          {"since", "0"}
        ] do
      response =
        Req.get!(ctx.url <> "/api/metrics/query_range", headers: ctx.headers, params: Map.put(params, key, value))

      assert response.status == 400
      assert response.body == "invalid or unsupported trace lookup parameters"
    end

    # Malformed since is a parsing error, unlike the admitted nonpositive
    # since values above, which retain their generic safety-policy rejection.
    response =
      Req.get!(ctx.url <> "/api/metrics/query_range", headers: ctx.headers, params: Map.put(params, "since", "garbage"))

    assert response.status == 400
    assert response.body == "could not parse 'since' parameter:"

    small = %{params | "step" => "35ms", "end" => "1700000360"}
    response = Req.get!(ctx.url <> "/api/metrics/query_range", headers: ctx.headers, params: small)
    assert response.status == 400
    assert response.body == "step of 35ms is too small, minimum step for given range is 36ms"
    assert Agent.get(ctx.store, & &1.requests) == before_requests
  end

  @tag :metric_step_validation
  test "Pulse metric step controls: diagnostics normalize durations and reject before storage or authorization bypass",
       ctx do
    before_requests = Agent.get(ctx.store, & &1.requests)

    for {range_ns, step, diagnostic} <- [
          {360_000_000_000, "0.035", "step of 35ms is too small, minimum step for given range is 36ms"},
          {10_001, "1ns", "step of 1ns is too small, minimum step for given range is 1ns"},
          {10_010_999, "1000ns", "step of 1µs is too small, minimum step for given range is 1.001µs"},
          {10_001_000_000_000, "1s", "step of 1s is too small, minimum step for given range is 1.0001s"},
          {600_060_000_000_000, "1m", "step of 1m0s is too small, minimum step for given range is 1m0.006s"}
        ] do
      params = %{
        "q" => "{} | count_over_time()",
        "start" => "1000",
        "end" => Integer.to_string(1_000_000_000_000 + range_ns),
        "step" => step
      }

      response = Req.get!(ctx.url <> "/api/metrics/query_range", headers: ctx.headers, params: params)
      assert response.status == 400
      assert response.body == diagnostic

      denied = Req.get!(ctx.url <> "/api/metrics/query_range", params: params)
      assert denied.status == 401
      assert denied.body == "unauthorized"
    end

    for step <- ["0", "0s", "garbage", "1xs"] do
      params = %{"q" => "{} | count_over_time()", "start" => "1000", "end" => "1360", "step" => step}
      response = Req.get!(ctx.url <> "/api/metrics/query_range", headers: ctx.headers, params: params)
      assert response.status == 400
      assert response.body == "invalid or unsupported trace lookup parameters"
    end

    negative = %{"q" => "{} | count_over_time()", "start" => "1000", "end" => "1360", "step" => "-1s"}
    response = Req.get!(ctx.url <> "/api/metrics/query_range", headers: ctx.headers, params: negative)
    assert response.status == 400
    assert response.body == ~s(cannot parse "-1s": step must be positive)
    assert Agent.get(ctx.store, & &1.requests) == before_requests
  end

  @tag :metric_step_validation
  test "Pulse metric step controls: requested boundary and remainder remain accepted before alignment", ctx do
    for {finish, count} <- [{"1010", 10_001}, {"1010000999999", 10_002}] do
      params = %{"q" => "{} | count_over_time()", "start" => "1000", "end" => finish, "step" => "1ms"}
      assert %{"series" => [%{"samples" => samples}]} = get(ctx, "/api/metrics/query_range", params)
      assert length(samples) == count
      assert Enum.all?(samples, &(&1["value"] == 0))
    end

    params = %{"q" => "{} | count_over_time()", "start" => "1000", "end" => "1010.001", "step" => "1ms"}
    before_requests = Agent.get(ctx.store, & &1.requests)
    response = Req.get!(ctx.url <> "/api/metrics/query_range", headers: ctx.headers, params: params)
    assert response.status == 400
    assert response.body == "step of 1ms is too small, minimum step for given range is 1.0001ms"
    assert Agent.get(ctx.store, & &1.requests) == before_requests

    for step <- ["1ms", "0", "malformed"] do
      assert %{"series" => [%{"value" => 0}]} = get(ctx, "/api/metrics/query", Map.put(params, "step", step))
    end
  end

  test "TestQueryRangeTypeHandling / metric-only: string and integer attributes do not lose span-ID series", ctx do
    batches =
      for {id, value} <- [{"00000000000000ab", %{"stringValue" => "123"}}, {"7fffffffffffffff", %{"intValue" => "123"}}] do
        %{
          "spanCount" => 1,
          "name" => "my operation",
          "resourceAttr" => "xx",
          "resourceAttVal" => "",
          "spanAttr" => "x",
          "spanAttVal" => "y",
          "spanId" => id,
          "extraSpanAttributes" => [%{"key" => "foo", "value" => value}]
        }
      end

    ingest(ctx, batches)
    params = %{"q" => "{} | rate() by (span:id)", "start" => ctx.now - 300, "end" => ctx.now, "step" => "5s"}
    result = get(ctx, "/api/metrics/query_range", params)
    assert Map.get(result, "status", "COMPLETE") == "COMPLETE"
    assert length(result["series"]) == 2

    # Pulse control: cardinality alone cannot detect lost ID bits or a wrong label.
    assert Enum.sort(Enum.map(result["series"], & &1["labels"])) == [
             [%{"key" => "span:id", "value" => %{"stringValue" => "00000000000000ab"}}],
             [%{"key" => "span:id", "value" => %{"stringValue" => "7fffffffffffffff"}}]
           ]

    for series <- result["series"] do
      assert_in_delta Enum.sum_by(series["samples"], & &1["value"]), 0.2, 1.0e-12
    end
  end

  test "TestQueryRangeMaxSeriesDisabled / metric-cardinality selection: every frozen producer span returns a series",
       ctx do
    batches =
      for tick <- 1..10 do
        %{
          "spanCount" => 1,
          "name" => "my operation",
          "resourceAttr" => "xx",
          "resourceAttVal" => "",
          "spanAttr" => "x",
          "spanAttVal" => "y",
          "spanId" => tick |> Integer.to_string(16) |> String.pad_leading(16, "0"),
          "startNs" => (ctx.now - 8) * 1_000_000_000 + tick * 500_000_000
        }
      end

    ingest(ctx, batches)
    params = %{"q" => "{} | rate() by (span:id)", "start" => ctx.now - 300, "end" => ctx.now, "step" => "5s"}
    result = get(ctx, "/api/metrics/query_range", params)
    assert Map.get(result, "status", "COMPLETE") == "COMPLETE"
    assert length(result["series"]) == 10
  end

  test "Pulse metric controls: span IDs are core strings, not user attributes or trace-local identities", ctx do
    ctx = %{ctx | now: div(ctx.now, 60) * 60 - 30}

    batches =
      for {id, value} <- [
            {"00000000000000ab", %{"stringValue" => "123"}},
            {"00000000000000ab", %{"intValue" => "123"}},
            {"fedcba9876543210", %{"stringValue" => "123"}}
          ] do
        %{
          "spanCount" => 1,
          "name" => "my operation",
          "resourceAttr" => "id",
          "resourceAttVal" => "resource-id",
          "spanAttr" => "id",
          "spanAttVal" => "attribute-id",
          "spanId" => String.upcase(id),
          "extraSpanAttributes" => [%{"key" => "foo", "value" => value}]
        }
      end

    ingest(ctx, batches)

    for endpoint <- ["query", "query_range"],
        {group, expected} <- [
          {"span:id", %{%{"stringValue" => "00000000000000ab"} => 2, %{"stringValue" => "fedcba9876543210"} => 1}},
          {"span.id", %{%{"stringValue" => "attribute-id"} => 3}},
          {"resource.id", %{%{"stringValue" => "resource-id"} => 3}},
          {"span.foo", %{%{"stringValue" => "123"} => 2, %{"intValue" => "123"} => 1}}
        ] do
      params = %{
        "q" => "{} | count_over_time() by (#{group})",
        "start" => ctx.now - 300,
        "end" => ctx.now,
        "step" => "5s"
      }

      result = get(ctx, "/api/metrics/" <> endpoint, params)

      actual =
        Map.new(result["series"], fn series ->
          assert [%{"key" => ^group, "value" => value}] = series["labels"]
          count = if endpoint == "query", do: series["value"], else: Enum.sum_by(series["samples"], & &1["value"])
          {value, count}
        end)

      assert actual == expected
      assert length(result["series"]) == map_size(expected)
    end

    for query <- [
          "{} | rate() by (id)",
          "{} | rate() by (trace:id)",
          "{} | sum_over_time(span:id)",
          "{} | quantile_over_time(span:id, 0.5)"
        ] do
      response =
        Req.get!(ctx.url <> "/api/metrics/query",
          headers: ctx.headers,
          params: %{"q" => query, "start" => ctx.now - 300, "end" => ctx.now}
        )

      assert response.status == 400
    end
  end

  for {op, labels} <- [{"bottomk", ["y", "z"]}, {"topk", ["x", "y"]}],
      mode <- [:standalone, :arithmetic_leaf] do
    @tag :metric_ranking_ties
    test "#{if op == "bottomk", do: "TestTiesInBottomK / all values tied", else: "Pulse topk tie control"} / #{mode}",
         ctx do
      start = div(ctx.now, 60) * 60 - 60

      # The original engine table supplies series, not spans. Nine one-span
      # batches construct its complete x/y/z = [5, 5, 5] arrays through HTTP.
      batches =
        for label <- ["x", "y", "z"], offset <- [1, 2, 3] do
          %{
            "spanCount" => 1,
            "name" => "tied-ranking",
            "resourceAttr" => "unused",
            "resourceAttVal" => "unused",
            "spanAttr" => "label",
            "spanAttVal" => label,
            "extraSpanAttributes" => [%{"key" => "v", "value" => %{"intValue" => "5"}}],
            "startNs" => (start + offset) * 1_000_000_000
          }
        end

      ingest(ctx, batches)
      query = "{} | max_over_time(span.v) by (span.label) | #{unquote(op)}(2)"
      query = if unquote(mode) == :arithmetic_leaf, do: "(#{query}) + 0", else: query

      result =
        get(ctx, "/api/metrics/query_range", %{
          "q" => query,
          "start" => start,
          "end" => start + 3,
          "step" => "1s"
        })

      expected =
        for label <- unquote(labels) do
          %{
            "labels" => [%{"key" => "span.label", "value" => %{"stringValue" => label}}],
            "samples" =>
              for offset <- [1, 2, 3] do
                %{"timestampMs" => Integer.to_string((start + offset) * 1000), "value" => 5}
              end
          }
        end

      assert result == %{"series" => expected}
      assert NIF.trace_metrics_api_version() == 6
    end
  end

  for {query, groups} <- [
        {"{ } | rate() > 10 | topk(5)", [{"__name__", "rate", 18}]},
        {"{ } | rate() by(name) >= 5.5 | bottomk(3)", [{"name", "high", 11}, {"name", "middle", 6}]},
        {"{ } | count_over_time() != 0 | topk(10)", [{"__name__", "count_over_time", 18}]}
      ],
      mode <- [:standalone, :arithmetic_leaf] do
    @tag :metric_prefilter_ranking
    test "TestMetricsSecondStage parser acceptance / #{query} / #{mode}", ctx do
      start = ingest_prefilter_ranking(ctx)
      # Original query and acceptance oracle: parse_test.go:1866-1894.
      # That table has no spans or numeric oracle. This producer and complete
      # response expectation are authored Pulse controls, not upstream values.
      query = unquote(query)
      query = if unquote(mode) == :arithmetic_leaf, do: "(#{query}) + 0", else: query

      result =
        get(ctx, "/api/metrics/query_range", %{
          "q" => query,
          "start" => start,
          "end" => start + 3,
          "step" => "1s"
        })

      expected =
        for {key, value, count} <- unquote(Macro.escape(groups)) do
          %{
            "labels" => [%{"key" => key, "value" => %{"stringValue" => value}}],
            "samples" => [%{"timestampMs" => Integer.to_string((start + 1) * 1000), "value" => count}]
          }
        end

      assert result == %{"series" => expected}
    end
  end

  @tag :metric_prefilter_ranking
  test "Pulse prefilter ranking controls: order matters and leaves share one provider scan", ctx do
    start = ingest_prefilter_ranking(ctx)
    source = "{} | rate() by(name)"
    params = %{"start" => start, "end" => start + 3, "step" => "1s"}
    before = Agent.get(ctx.store, &length(&1.reads))

    for query <- [source <> " >= 5.5 | bottomk(1)", "(" <> source <> " >= 5.5 | bottomk(1)) + 0"] do
      assert get(ctx, "/api/metrics/query_range", Map.put(params, "q", query)) == %{
               "series" => [
                 %{
                   "labels" => [%{"key" => "name", "value" => %{"stringValue" => "middle"}}],
                   "samples" => [%{"timestampMs" => Integer.to_string((start + 1) * 1000), "value" => 6}]
                 }
               ]
             }
    end

    inverse = source <> " | bottomk(1) >= 5.5"

    for query <- [inverse, "(#{inverse}) + 0"] do
      assert get(ctx, "/api/metrics/query_range", Map.put(params, "q", query)) == %{"series" => []}
    end

    query = "(" <> source <> " >= 5.5 | bottomk(1)) + (" <> source <> " >= 6 | bottomk(2))"

    assert get(ctx, "/api/metrics/query_range", Map.put(params, "q", query)) == %{
             "series" => [
               %{
                 "labels" => [%{"key" => "name", "value" => %{"stringValue" => "middle"}}],
                 "samples" => [%{"timestampMs" => Integer.to_string((start + 1) * 1000), "value" => 12.0}]
               }
             ]
           }

    reads =
      Agent.get(ctx.store, &Enum.take(&1.reads, length(&1.reads) - before))
      |> Enum.filter(&String.ends_with?(&1, ".parquet"))

    # Five requests, including two distinct leaves in the final expression,
    # each fetching the three immutable source objects once.
    assert length(reads) == 15
    assert Enum.sort(Map.values(Enum.frequencies(reads))) == [5, 5, 5]

    instant = Map.put(params, "q", source <> " >= 1.5 | bottomk(1)")
    assert %{"series" => [%{"value" => 2}]} = get(ctx, "/api/metrics/query", instant)

    Runtime.put_env(:pulse, Pulse.QueryRunner, max_scan_rows: 1)

    response =
      Req.get!(ctx.url <> "/api/metrics/query_range", headers: ctx.headers, params: Map.put(params, "q", query))

    assert response.status == 422
  end

  @tag :metric_prefilter_ranking
  test "Pulse prefilter ranking controls: unsupported stages reject before provider work", ctx do
    before = Agent.get(ctx.store, & &1.requests)

    for query <- [
          "{} | rate() > 10 | topk(0)",
          "{} | rate() > 10 | bottomk(-1)",
          "{} | rate() > 1e999 | topk(1)",
          "{} | rate() > NaN | topk(1)",
          "{} | rate() > ({} | rate()) | topk(1)",
          "{} | rate() > 10 | unknown(1)",
          "{} | rate() > 10 | topk(1) | bottomk(1)",
          "{} | rate() > 10 < 20 | topk(1)",
          "({} | rate()) + ({} | rate()) > 10 | topk(1)"
        ] do
      response =
        Req.get!(ctx.url <> "/api/metrics/query_range",
          headers: ctx.headers,
          params: %{"q" => query, "start" => 1, "end" => 3, "step" => "1s"}
        )

      assert response.status == 400, query
    end

    assert Agent.get(ctx.store, & &1.requests) == before
  end

  defp ingest_prefilter_ranking(ctx) do
    start = div(ctx.now, 60) * 60 - 60

    batches =
      for {name, count} <- [{"low", 1}, {"middle", 6}, {"high", 11}] do
        %{
          "spanCount" => count,
          "name" => name,
          "resourceAttr" => "unused",
          "resourceAttVal" => "unused",
          "spanAttr" => "unused",
          "spanAttVal" => "unused",
          "startNs" => (start + 1) * 1_000_000_000
        }
      end

    ingest(ctx, batches)
    start
  end

  test "Pulse metric controls: ranking selects actual extremes, not arbitrary k series", ctx do
    ctx = %{ctx | now: div(ctx.now, 60) * 60 - 30}

    batches =
      for {value, count} <- [{"small", 1}, {"middle", 3}, {"large", 5}] do
        %{
          "spanCount" => count,
          "name" => "operation",
          "resourceAttr" => "res_high_cardinality",
          "resourceAttVal" => value,
          "spanAttr" => "span_high_cardinality",
          "spanAttVal" => value
        }
      end

    ingest(ctx, batches)

    for {scope, key} <- [{"span", "span_high_cardinality"}, {"resource", "res_high_cardinality"}],
        {op, value, count} <- [{"topk", "large", 5}, {"bottomk", "small", 1}],
        endpoint <- ["query", "query_range"] do
      label = scope <> "." <> key
      query = "{} | count_over_time() by (#{label}) | #{op}(1)"
      # Every input is in one minute. Empty range intervals may retain another
      # zero-valued tie winner; compare the actual nonzero ranking separately.
      finish = div(ctx.now, 60) * 60 + 60
      params = %{"q" => query, "start" => finish - 60, "end" => finish, "step" => "1m"}
      result = get(ctx, "/api/metrics/" <> endpoint, params)

      if endpoint == "query" do
        assert result["series"] == [
                 %{"labels" => [%{"key" => label, "value" => %{"stringValue" => value}}], "value" => count}
               ]
      else
        assert [series] = Enum.filter(result["series"], &Enum.any?(&1["samples"], fn point -> point["value"] > 0 end))
        assert series["labels"] == [%{"key" => label, "value" => %{"stringValue" => value}}]
        assert Enum.sum_by(series["samples"], & &1["value"]) == count
      end
    end
  end

  test "Pulse metric controls: instant duration averages weight spans, not occupied intervals", ctx do
    start = div(ctx.now, 60) * 60 - 60

    batches =
      for {offset, count, duration_ms} <- [{5, 1, 100}, {15, 3, 200}, {25, 5, 700}] do
        %{
          "spanCount" => count,
          "name" => "operation",
          "resourceAttr" => "res_attr",
          "resourceAttVal" => "res_val",
          "spanAttr" => "span_attr",
          "spanAttVal" => "span_val",
          "startNs" => (start + offset) * 1_000_000_000,
          "durationNs" => duration_ms * 1_000_000
        }
      end

    ingest(ctx, batches)

    for {op, expected, values} <- [
          {"sum", 4.2, [0.1, 0.6, 3.5]},
          {"avg", 4.2 / 9, [0.1, 0.2, 0.7]},
          {"min", 0.1, [0.1, 0.2, 0.7]},
          {"max", 0.7, [0.1, 0.2, 0.7]}
        ] do
      params = %{"q" => "{} | #{op}_over_time(duration)", "start" => start, "end" => start + 30, "step" => "10s"}
      assert %{"series" => [instant]} = get(ctx, "/api/metrics/query", params)
      assert_in_delta instant["value"], expected, 1.0e-12
      assert %{"series" => [range]} = get(ctx, "/api/metrics/query_range", params)
      assert length(range["samples"]) == 3

      for {sample, value, offset} <- Enum.zip([range["samples"], values, [10, 20, 30]]) do
        assert sample["timestampMs"] == Integer.to_string((start + offset) * 1000)
        assert_in_delta sample["value"], value, 1.0e-12
      end
    end
  end

  describe "TestDefaultQueryRangeStep / HTTP sample spacing" do
    setup ctx do
      # Upstream tests only the window/step table. One persisted span makes
      # the same policy observable through the real HTTP/native query path.
      batch = @cases["batches"] |> hd() |> Map.merge(%{"spanCount" => 1, "startNs" => 1_000_000_000})
      ingest(ctx, [batch])
      :ok
    end

    for {name, seconds, step_ms} <- [
          {"59s", 59, 200},
          {"1m", 60, 1000},
          {"5m", 300, 1000},
          {"15m", 900, 3000},
          {"30m", 1800, 5000},
          {"1h", 3600, 15_000},
          {"3h", 10_800, 45_000},
          {"6h", 21_600, 60_000},
          {"12h", 43_200, 180_000},
          {"24h - 1s", 86_399, 300_000},
          {"24h", 86_400, 300_000},
          {"2d", 172_800, 600_000},
          {"7d", 604_800, 2_400_000},
          {"14d", 1_209_600, 3_600_000},
          {"30d", 2_592_000, 10_800_000}
        ] do
      test "#{name}", ctx do
        params = %{"q" => "{} | count_over_time()", "start" => 0, "end" => unquote(seconds) * 1_000_000_000}
        assert %{"series" => [series]} = get(ctx, "/api/metrics/query_range", params)
        timestamps = Enum.map(series["samples"], &String.to_integer(&1["timestampMs"]))

        assert length(timestamps) > 1
        assert hd(timestamps) == unquote(step_ms)
        assert Enum.uniq(Enum.zip_with(timestamps, tl(timestamps), &(&2 - &1))) == [unquote(step_ms)]
        assert Enum.sum_by(series["samples"], & &1["value"]) == 1
      end
    end
  end

  test "Pulse default-step controls: minimum, rounding and minute boundary at a shifted epoch", ctx do
    start = 1_700_000_000_000_000_000
    batch = @cases["batches"] |> hd() |> Map.merge(%{"spanCount" => 1, "startNs" => start + 1})
    ingest(ctx, [batch])

    for {window_ns, step_ms} <- [
          {1, 50},
          {11_999_999_999, 50},
          {24_000_000_000, 100},
          {59_999_999_999, 200},
          {60_000_000_000, 1000}
        ] do
      params = %{"q" => "{} | count_over_time()", "start" => start, "end" => start + window_ns}
      assert %{"series" => [series]} = get(ctx, "/api/metrics/query_range", params)
      timestamps = Enum.map(series["samples"], &String.to_integer(&1["timestampMs"]))

      assert length(timestamps) > 1
      assert hd(timestamps) == div(start, 1_000_000)
      assert Enum.uniq(Enum.zip_with(timestamps, tl(timestamps), &(&2 - &1))) == [step_ms]
      assert Enum.sum_by(series["samples"], & &1["value"]) == 1
    end
  end

  test "Pulse default-step controls: explicit steps, instant values and interval admission stay independent", ctx do
    batch = @cases["batches"] |> hd() |> Map.merge(%{"spanCount" => 1, "startNs" => 1_000_000_000})
    ingest(ctx, [batch])
    params = %{"q" => "{} | count_over_time()", "start" => 0, "end" => 59_000_000_000, "step" => "700ms"}
    assert %{"series" => [series]} = get(ctx, "/api/metrics/query_range", params)
    timestamps = Enum.map(series["samples"], &String.to_integer(&1["timestampMs"]))
    assert length(timestamps) == 85
    assert hd(timestamps) == 700
    assert Enum.uniq(Enum.zip_with(timestamps, tl(timestamps), &(&2 - &1))) == [700]
    assert Enum.sum_by(series["samples"], & &1["value"]) == 1

    assert %{"series" => [%{"value" => 1}]} = get(ctx, "/api/metrics/query", Map.put(params, "step", "ignored"))

    response =
      Req.get!(ctx.url <> "/api/metrics/query_range", headers: ctx.headers, params: Map.put(params, "step", "1ms"))

    assert response.status == 400
  end

  @tag :trace_math_batch
  test "TestScalarMath: every engine oracle survives authenticated HTTP and native Parquet", ctx do
    batches =
      for span <- @math["scalar"]["spans"] do
        [%{"name" => "foo", "value" => value}] = span["span_attributes"]

        %{
          "spanCount" => 1,
          "name" => "span",
          "resourceAttr" => "unused",
          "resourceAttVal" => "unused",
          "spanAttr" => "foo",
          "spanAttVal" => value,
          "startNs" => span["start_time_unix_nano"],
          "durationNs" => span["duration_nano"]
        }
      end

    ingest(ctx, batches)

    for row <- @math["scalar"]["cases"] do
      # Eleven digits select integer nanoseconds even near the Unix epoch.
      response =
        get(ctx, "/api/metrics/query_range", %{
          "q" => row["query"],
          "start" => "00000000001",
          "end" => "0003000000000",
          "step" => "1s"
        })

      actual =
        Map.new(response["series"], fn series ->
          assert [%{"key" => "span.foo", "value" => %{"stringValue" => value}}] = series["labels"]
          {value, Enum.map(series["samples"], &{String.to_integer(&1["timestampMs"]), &1["value"]})}
        end)

      expected =
        Map.new(row["expected"], fn {key, values} ->
          {key, Enum.zip(@math["scalar"]["timestamps_ms"], values) |> Enum.reject(&(elem(&1, 1) == "NaN"))}
        end)
        |> Map.reject(fn {_, values} -> values == [] end)

      assert length(response["series"]) == map_size(expected), row["query"]
      assert Enum.sort(Map.keys(actual)) == Enum.sort(Map.keys(expected)), row["query"]

      for {key, samples} <- expected do
        assert Enum.map(actual[key], &elem(&1, 0)) == Enum.map(samples, &elem(&1, 0)), row["query"]

        for {{_, value}, {_, expected}} <- Enum.zip(actual[key], samples) do
          case expected do
            "+Inf" -> assert value == "Infinity"
            "-Inf" -> assert value == "-Infinity"
            number -> assert_in_delta value, number, max(abs(number) * 1.0e-12, 1.0e-12), row["query"]
          end
        end
      end
    end
  end

  @tag :trace_math_batch
  test "Pulse metric expression controls: branches share object reads and fail-whole scan quotas", ctx do
    batches =
      for {offset, count, duration} <- [{1, 2, 100_000_000}, {15, 1, 900_000_000}] do
        %{
          "spanCount" => count,
          "name" => "span",
          "resourceAttr" => "unused",
          "resourceAttVal" => "unused",
          "spanAttr" => "foo",
          "spanAttVal" => "bar",
          "startNs" => (1000 + offset) * 1_000_000_000,
          "durationNs" => duration
        }
      end

    ingest(ctx, batches)
    query = "({} | sum_over_time(duration)) / ({} | count_over_time())"
    params = %{"q" => query, "start" => 1000, "end" => 1060, "step" => "10s"}
    before = Agent.get(ctx.store, &length(&1.reads))
    assert %{"series" => [series]} = get(ctx, "/api/metrics/query_range", params)
    assert Enum.map(series["samples"], & &1["timestampMs"]) == ["1010000", "1020000"]
    assert [first, second] = Enum.map(series["samples"], & &1["value"])
    assert_in_delta first, 0.1, 1.0e-12
    assert_in_delta second, 0.9, 1.0e-12

    reads =
      Agent.get(ctx.store, &Enum.take(&1.reads, length(&1.reads) - before))
      |> Enum.filter(&String.ends_with?(&1, ".parquet"))

    assert length(reads) == 2
    assert length(Enum.uniq(reads)) == 2

    assert %{"series" => [%{"value" => value}]} = get(ctx, "/api/metrics/query", params)
    assert_in_delta value, 1.1 / 3, 1.0e-12

    Runtime.put_env(:pulse, Pulse.QueryRunner, max_scan_rows: 2)
    response = Req.get!(ctx.url <> "/api/metrics/query_range", headers: ctx.headers, params: params)
    assert response.status == 422
  end

  @tag :trace_math_batch
  test "Pulse metric expression controls: invalid and over-complex queries reject before storage", ctx do
    before = Agent.get(ctx.store, & &1.requests)

    extra = [
      "1 + 2",
      "-({} | rate())",
      "({} | rate()) == 1",
      "1 > ({} | rate())",
      "({} | rate()) > ({} | rate())",
      "({} | rate()) % 2",
      "({} | rate()) ^ 2",
      "({} | rate()) * (1/0)",
      String.duplicate("(", 33) <> "{} | rate()" <> String.duplicate(")", 33)
    ]

    for query <- Enum.map(@math["grammar"]["negative"], & &1["query"]) ++ extra do
      response =
        Req.get!(ctx.url <> "/api/metrics/query",
          headers: ctx.headers,
          params: %{"q" => query, "start" => 1, "end" => 3}
        )

      assert response.status == 400, query
    end

    assert Agent.get(ctx.store, & &1.requests) == before
  end

  defp ingest_metric_batches(ctx) do
    batches =
      for tick <- 0..19,
          {name, resource_key, resource_value, span_key, span_value} <- [
            {"my operation", "res_attr", "res_val", "span_attr", "span_val"},
            {"my operation", "res_attr", "res_val2", "span_attr", "span_val2"},
            {"operation with high cardinality", "res_high_cardinality", "resource-#{tick}", "span_high_cardinality",
             "span-#{tick}"}
          ] do
        %{
          "spanCount" => 1,
          "name" => name,
          "resourceAttr" => resource_key,
          "resourceAttVal" => resource_value,
          "spanAttr" => span_key,
          "spanAttVal" => span_value,
          "startNs" => (ctx.now - 13) * 1_000_000_000 + tick * 500_000_000
        }
      end

    ingest(ctx, batches)
  end

  defp ingest_filter_trace(ctx, graph \\ [{1, 0, 0}, {2, 1, 0}, {3, 2, 500}, {4, 1, 200}, {5, 3, 0}, {6, 5, 0}]) do
    spans =
      for {id, parent, code} <- graph do
        span = %{
          "traceId" => String.pad_leading("1", 32, "0"),
          "spanId" => id |> Integer.to_string(16) |> String.pad_leading(16, "0"),
          "name" => "span",
          "startTimeUnixNano" => Integer.to_string((ctx.now - 3) * 1_000_000_000),
          "endTimeUnixNano" => Integer.to_string((ctx.now - 3) * 1_000_000_000 + 1_000_000),
          "attributes" =>
            if(code == 0, do: [], else: [%{"key" => "http.status_code", "value" => %{"intValue" => to_string(code)}}])
        }

        if parent == 0,
          do: span,
          else: Map.put(span, "parentSpanId", parent |> Integer.to_string(16) |> String.pad_leading(16, "0"))
      end

    body = %{
      "resourceSpans" => [
        %{
          "resource" => %{"attributes" => [%{"key" => "service.name", "value" => %{"stringValue" => "filter-test"}}]},
          "scopeSpans" => [%{"spans" => spans}]
        }
      ]
    }

    assert Req.post!(ctx.url <> "/v1/traces", headers: ctx.headers, json: body).status == 200
    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)
  end

  defp filter_ids(response) do
    for resource <- Map.get(response["trace"], "resourceSpans", []),
        scope <- resource["scopeSpans"],
        span <- scope["spans"] do
      span["spanId"] |> Base.decode64!() |> :binary.last()
    end
    |> Enum.sort()
  end

  defp ingest_trace_infos(ctx) do
    bytes =
      "../../fixtures/traces/tempo_integration/trace-by-id.json"
      |> Path.expand(__DIR__)
      |> File.read!()

    assert Base.encode16(:crypto.hash(:sha256, bytes), case: :lower) ==
             "e4c37ec95b0bd97bbd00e01876b14422c55ee669799a1e3a791c05cad93cef43"

    fixture = Pulse.JSON.decode!(bytes)
    assert length(fixture["traces"]) == 10

    for row <- fixture["traces"] do
      response =
        Req.post!(ctx.url <> "/v1/traces",
          headers: [{"content-type", "application/x-protobuf"} | ctx.headers],
          body: Base.decode64!(row["wire"])
        )

      assert response.status == 200
    end

    fixture
  end

  # Like upstream SortTraceAndAttributes, compare all owners/fields while
  # ignoring collection order. Never sort AnyValue arrays or discard duplicates.
  defp canonical_trace_info(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      value = canonical_trace_info(value)

      if key in ["resourceSpans", "scopeSpans", "spans", "attributes", "events", "links"] do
        {key, Enum.sort(value)}
      else
        {key, value}
      end
    end)
  end

  defp canonical_trace_info(list) when is_list(list), do: Enum.map(list, &canonical_trace_info/1)
  defp canonical_trace_info(value), do: value

  defp ingest(ctx, batches) do
    for {batch, i} <- Enum.with_index(batches, 1) do
      attributes = fn key, value -> [%{"key" => key, "value" => %{"stringValue" => value}}] end
      start = Map.get(batch, "startNs", (ctx.now - 3) * 1_000_000_000)

      spans =
        for j <- 1..batch["spanCount"] do
          %{
            "traceId" => i |> Integer.to_string(16) |> String.pad_leading(32, "0"),
            "spanId" => Map.get(batch, "spanId", j |> Integer.to_string(16) |> String.pad_leading(16, "0")),
            "name" => batch["name"],
            "startTimeUnixNano" => Integer.to_string(start),
            "endTimeUnixNano" => Integer.to_string(start + Map.get(batch, "durationNs", 1000)),
            "attributes" =>
              attributes.(batch["spanAttr"], batch["spanAttVal"]) ++ Map.get(batch, "extraSpanAttributes", [])
          }
        end

      body = %{
        "resourceSpans" => [
          %{
            "resource" => %{
              "attributes" =>
                attributes.("service.name", "my-service") ++ attributes.(batch["resourceAttr"], batch["resourceAttVal"])
            },
            "scopeSpans" => [%{"spans" => spans}]
          }
        ]
      }

      assert Req.post!(ctx.url <> "/v1/traces", headers: ctx.headers, json: body).status == 200
    end

    # Acknowledgements already publish Parquet; fresh supervision removes local manifest state.
    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)
  end

  defp windows(ctx), do: [%{}, %{"start" => ctx.now - 7200, "end" => ctx.now + 7200}]

  defp values_path(version, target) do
    prefix = if version == 1, do: "/api", else: "/api/v2"
    prefix <> "/search/tag/" <> URI.encode(target, &URI.char_unreserved?/1) <> "/values"
  end

  defp assert_values(ctx, version, target, values, params) do
    expected = %{
      "tagValues" => if(version == 1, do: values, else: Enum.map(values, &%{"type" => "string", "value" => &1}))
    }

    path = values_path(version, target)
    assert get(ctx, path, params) == expected

    response = Req.get!(ctx.url <> path, headers: [{"accept", "application/protobuf"} | ctx.headers], params: params)
    assert response.status == 200
    assert response.body == Protobuf.encode(expected, if(version == 1, do: :tag_values, else: :tag_values_v2))
  end

  defp get(ctx, path, params) do
    response = Req.get!(ctx.url <> path, headers: ctx.headers, params: params)
    assert response.status == 200, "#{path}: #{inspect(response.body)}"
    response.body
  end

  defp call_tool(ctx, name, args) do
    headers =
      ctx.headers ++
        [
          {"accept", "application/json, text/event-stream"},
          {"mcp-protocol-version", MCPMessages.version()},
          {"mcp-method", "tools/call"},
          {"mcp-name", name}
        ]

    body = MCPMessages.request(1, "tools/call", %{"name" => name, "arguments" => args})
    response = Req.post!(ctx.url <> "/mcp", headers: headers, json: body)
    assert response.status == 200
    refute response.body["result"]["isError"], inspect(response.body)
    [%{"text" => text}] = response.body["result"]["content"]
    Pulse.JSON.decode!(text)
  end
end
