# SPDX-License-Identifier: AGPL-3.0-only
# Adapted from Grafana Loki integration tests, copyright Grafana Labs contributors.
# Modified for Pulse's Elixir HTTP/S3 harness on 2026-10-25.
# Also includes Go duration/numeric tables (copyright 2009 The Go Authors, BSD-3-Clause)
# and template tables (copyright 2011 The Go Authors, BSD-3-Clause),
# and go-humanize byte tables (copyright Dustin Sallings, MIT). Original notices
# are retained in Go-LICENSE and go-humanize-LICENSE beside the fixture README.
# Prometheus common duration tables: Copyright 2013 The Prometheus Authors,
# Apache-2.0; original license in Prometheus-common-LICENSE. Modified for Pulse.
# Sprig v3.3.0 template tables: Copyright (C) 2013-2020 Masterminds, MIT;
# original notice retained in Sprig-LICENSE. Modified for Pulse's HTTP harness.
# Source revision, case mapping, adaptations and license: test/fixtures/logs/loki-upstream/README.md.
defmodule PulseWeb.LokiUpstreamIntegrationTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Auth
  alias Pulse.Auth.SharedSecret
  alias Pulse.Codec.NIF
  alias Pulse.LogQL.AST.RangeAgg
  alias Pulse.LogQL.MetricEval
  alias Pulse.LogQL.Parser
  alias Pulse.LogQL.QueryValidation
  alias Pulse.Loki.FieldType
  alias Pulse.Loki.PushProto
  alias Pulse.Loki.Tail
  alias Pulse.PromQL.Evaluator
  alias Pulse.PromQL.QuerySlots
  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Test.BlockingMetricStorage
  alias Pulse.Test.CompactionStore
  alias Pulse.Test.LokiLabelBuilderFixture
  alias Pulse.Test.LokiPipelineFixture
  alias Pulse.Test.LokiSampleExtractorFixture
  alias Pulse.Test.MetricEvalReference
  alias Pulse.Test.RuntimePlug
  alias Pulse.Test.WebSocketClient

  @second 1_000_000_000
  @minute 60 * @second
  @week 7 * 24 * 60 * @minute

  @http_parameters_path "test/fixtures/logs/loki-upstream/http-parameters.json"
  @external_resource @http_parameters_path
  @http_parameter_rows @http_parameters_path |> File.read!() |> JSON.decode!() |> Map.fetch!("rows")

  @http_errors_path "test/fixtures/logs/loki-upstream/http-errors.json"
  @external_resource @http_errors_path
  @http_error_rows @http_errors_path
                   |> File.read!()
                   |> JSON.decode!()
                   |> Map.fetch!("rows")
                   |> Map.new(&{&1["name"], &1["expected"]})

  @error_classification_path "test/fixtures/logs/loki-upstream/error-classification.json"
  @external_resource @error_classification_path
  @wrapped_limit_rows @error_classification_path
                      |> File.read!()
                      |> JSON.decode!()
                      |> Map.fetch!("rows")
                      |> Enum.filter(&(&1["table"] == "TestWrappedLimitErrorStatusPreserved"))
                      |> Map.new(&{&1["name"], &1["expected"]})

  setup do
    Runtime.share()

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

    server = start_supervised!({Bandit, plug: {CompactionStore, agent: store}, ip: {127, 0, 0, 1}, port: 0})
    {:ok, {_, port}} = ThousandIsland.listener_info(server)

    config = %{
      bucket: "pulse",
      endpoint: "http://127.0.0.1:#{port}",
      region: "us-east-1",
      access_key_id: "loki-upstream-#{System.unique_integer([:positive])}",
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0
    }

    tenant = "loki-upstream-#{System.unique_integer([:positive])}"
    token = "test-token"
    digest = "sha256$" <> Base.encode16(:crypto.hash(:sha256, token), case: :lower)
    Runtime.put_env(:pulse, Auth, module: SharedSecret, tokens: %{tenant => digest})
    Runtime.put_env(:pulse, Storage, adapter: S3)
    Runtime.put_env(:pulse, S3, config)
    start_supervised!(ManifestSupervision)

    api =
      start_supervised!(
        {Bandit, plug: {RuntimePlug, plug: PulseWeb.Endpoint, runtime: Runtime.current()}, ip: {127, 0, 0, 1}, port: 0}
      )

    {:ok, {_, api_port}} = ThousandIsland.listener_info(api)

    # Preserve upstream relative times, but keep the +3s label-access input in
    # the past so its default-time label APIs cannot race the wall clock.
    %{
      url: "http://127.0.0.1:#{api_port}",
      tenant: tenant,
      token: token,
      now: System.system_time(:nanosecond) - 10 * @second,
      store: store
    }
  end

  test "Grafana health and shifted log-volume requests preserve client boundaries", ctx do
    # Current Grafana Loki datasource healthcheck.go and logs_volume.go,
    # not additional Loki upstream integration scenarios.
    base = div(ctx.now, @second) * @second
    before = Agent.get(ctx.store, & &1.requests)
    health = request(ctx, "/query", [query: "vector(1)+vector(1)", time: to_string(base)], 200)

    assert health["data"]["resultType"] == "vector"
    assert health["data"]["result"] == [%{"metric" => %{}, "value" => [div(base, @second), "2"]}]

    assert Agent.get(ctx.store, & &1.requests) == before

    for {time, line} <- [
          {base - 1, "before"},
          {base, "start one"},
          {base, "start two"},
          {base + 5 * @second, "middle"},
          {base + 10 * @second, "next window"}
        ] do
      push(ctx, line, time, %{"job" => "grafana-volume"})
    end

    for method <- [&request/4, &request_form/4] do
      response =
        method.(
          ctx,
          "/query_range",
          [
            query: ~s/sum(count_over_time({job="grafana-volume"}[10s] offset 1ns))/,
            start: to_string(base + 10 * @second),
            end: to_string(base + 20 * @second),
            step: "10000ms"
          ],
          200
        )

      assert response["data"]["resultType"] == "matrix"

      assert response["data"]["result"] == [
               %{"metric" => %{}, "values" => [[div(base, @second) + 10, "3"], [div(base, @second) + 20, "1"]]}
             ]
    end

    assert_parquet(ctx, 5)
  end

  @tag :sort_grouping_batch
  test "complete Loki named-sort rejection table rejects before provider work", ctx do
    # Original Test_SampleExpr_Sort_Fail has no loads. Keep both original
    # queries and the literal rejection-substring oracle unchanged.
    originals = [
      ~s/sort(sum by(a) (rate( ( {job="mysql"} |="error" !="timeout" ) [10s] ) )) by (app)/,
      ~s/sort_desc(sum by(a) (rate( ( {job="mysql"} |="error" !="timeout" ) [10s] ) )) by (app)/
    ]

    # Authored placements exercise recursive admission, not additional
    # upstream rows. An outer valid expression must not hide an invalid sort.
    authored = [
      ~s/sort by(app)(rate({job="mysql"}[10s]))/,
      ~s/sort_desc without(app)(rate({job="mysql"}[10s]))/,
      ~s/sort(rate({job="mysql"}[10s])) without(app)/,
      ~s/sum(#{hd(originals)})/,
      ~s/vector(1) + (#{List.last(originals)})/,
      ~s/label_replace(#{hd(originals)}, "copied", "$1", "a", "(.*)")/
    ]

    for seeded? <- [false, true] do
      if seeded? do
        # Separately authored producer: preserve the original empty setup
        # first, then prove rejection does not depend on absent storage.
        push(ctx, "error", ctx.now - @second, %{"job" => "mysql", "a" => "one", "app" => "api"})
        assert_parquet(ctx, 1)
      end

      before = Agent.get(ctx.store, & &1.requests)

      for query <- originals ++ authored,
          path <- ["/query", "/query_range"],
          method <- [&request/4, &request_form/4] do
        response =
          method.(
            ctx,
            path,
            [query: query, time: to_string(ctx.now), start: to_string(ctx.now), end: to_string(ctx.now), step: "1"],
            400
          )

        assert response["status"] == "error"
        assert response["error"] == "parse_error"
        assert response["message"] =~ "sort and sort_desc doesn't allow grouping by"
      end

      assert Agent.get(ctx.store, & &1.requests) == before
    end

    response =
      Req.get!(ctx.url <> "/loki/api/v1/query",
        headers: [{"x-scope-orgid", ctx.tenant}],
        params: [query: hd(originals), time: to_string(ctx.now)],
        retry: false
      )

    assert response.status == 401
    refute_parquet_read(ctx)
  end

  @tag :sort_grouping_batch
  test "authored sort controls retain empty grouping, asymmetric order and ordinary grouping", ctx do
    ctx = %{ctx | now: div(ctx.now, @second) * @second}

    push_streams(ctx, [
      %{
        "stream" => %{"job" => "mysql", "a" => "one", "app" => "api"},
        "values" => [
          [to_string(ctx.now - @second), "error"],
          [to_string(ctx.now - 2 * @second), "error timeout"]
        ]
      },
      %{
        "stream" => %{"job" => "mysql", "a" => "two", "app" => "api"},
        "values" => [
          [to_string(ctx.now - @second), "error"],
          [to_string(ctx.now - 2 * @second), "error"]
        ]
      }
    ])

    assert_parquet(ctx, 1)
    inner = ~s/sum by(a) (rate( ( {job="mysql"} |="error" !="timeout" ) [10s] ) )/
    timestamp = div(ctx.now, @second) * 1.0

    for op <- ["sort", "sort_desc"],
        grouping <- ["", "by ()", "without ()"],
        placement <- [:before, :after],
        method <- [&request/4, &request_form/4] do
      query =
        case placement do
          :before -> "#{op} #{grouping}(#{inner})"
          :after -> "#{op}(#{inner}) #{grouping}"
        end

      response = method.(ctx, "/query", [query: query, time: to_string(ctx.now)], 200)

      ascending = [
        %{"metric" => %{"a" => "one"}, "value" => [timestamp, "0.1"]},
        %{"metric" => %{"a" => "two"}, "value" => [timestamp, "0.2"]}
      ]

      assert response["data"]["resultType"] == "vector"

      if grouping == "without ()" do
        # Pinned VectorAggEvaluator hashes all retained labels for without().
        # These singleton groups have no global directional-order guarantee.
        assert Enum.sort_by(response["data"]["result"], & &1["metric"]["a"]) == ascending
      else
        assert response["data"]["result"] == if(op == "sort", do: ascending, else: Enum.reverse(ascending))
      end

      response =
        method.(
          ctx,
          "/query_range",
          [query: query, start: to_string(ctx.now), end: to_string(ctx.now + 20 * @second), step: "10"],
          200
        )

      assert response["data"]["resultType"] == "matrix"

      assert Enum.sort_by(response["data"]["result"], & &1["metric"]["a"]) == [
               %{"metric" => %{"a" => "one"}, "values" => [[timestamp, "0.1"]]},
               %{"metric" => %{"a" => "two"}, "values" => [[timestamp, "0.2"]]}
             ]
    end

    for method <- [&request/4, &request_form/4] do
      response = method.(ctx, "/query", [query: inner, time: to_string(ctx.now)], 200)
      assert values(response) == %{%{"a" => "one"} => "0.1", %{"a" => "two"} => "0.2"}
    end

    assert_parquet_read(ctx)
  end

  @tag :formatter_error_ownership_batch
  test "complete Loki formatter error block retains all loads and four original oracles", ctx do
    ctx = %{ctx | now: ctx.now - 120 * @second}
    push_formatter_error_rows(ctx)

    for method <- [&request/4, &request_form/4] do
      failed =
        method.(
          ctx,
          "/query",
          [
            query: ~s/count_over_time({app="a"} | label_format __error__="mine" [1m])/,
            time: to_string(ctx.now + 60 * @second)
          ],
          400
        )

      assert failed["status"] == "error"
      assert failed["message"] =~ "error_label_cannot_be_formatted"

      response =
        method.(
          categorize(ctx),
          "/query_range",
          [
            query: ~s/{app="a"} | label_format __error_details__="mine"/,
            start: to_string(ctx.now),
            end: to_string(ctx.now + 60 * @second),
            direction: "forward"
          ],
          200
        )

      assert Enum.sort_by(response["data"]["result"], & &1["stream"]["pod"]) == [
               %{
                 "stream" => %{"app" => "a", "pod" => "p1"},
                 "values" => [
                   [
                     to_string(ctx.now + 40 * @second),
                     "{",
                     %{"structuredMetadata" => %{"n" => "7"}, "parsed" => %{"__error_details__" => "mine"}}
                   ]
                 ]
               },
               %{
                 "stream" => %{"app" => "a", "pod" => "p2"},
                 "values" => [
                   [
                     to_string(ctx.now + 20 * @second),
                     ~s/{"ok":1}/,
                     %{"structuredMetadata" => %{"n" => "5"}, "parsed" => %{"__error_details__" => "mine"}}
                   ]
                 ]
               }
             ]

      for stages <- [
            ~s/| label_format __error_details__="mine" | json/,
            ~s/| json | label_format __error_details__="mine"/
          ] do
        query = ~s/first_over_time({app="a"} #{stages} | __error__!="" | unwrap n [1m]) by (__error_details__)/
        response = method.(ctx, "/query", [query: query, time: to_string(ctx.now + 60 * @second)], 200)

        assert response["data"]["result"] == [
                 %{
                   "metric" => %{"__error__" => "JSONParserErr", "__error_details__" => "Malformed JSON error"},
                   "value" => [(ctx.now + 60 * @second) / @second, "7"]
                 }
               ]
      end
    end

    assert_parquet_read(ctx)
  end

  @tag :formatter_error_ownership_batch
  test "authored formatter ownership controls distinguish hidden labels and authoritative errors", ctx do
    ctx = %{ctx | now: ctx.now - 120 * @second}
    push_formatter_error_rows(ctx)
    error = %{"__error__" => "JSONParserErr", "__error_details__" => "Malformed JSON error"}
    prefix = ~s/{app="a",pod="p1"} | json | label_format __error_details__="mine"/

    controls = [
      {prefix, error},
      {prefix <> " | drop __error_details__", %{error | "__error_details__" => "mine"}},
      {prefix <> " | drop __error__", Map.delete(error, "__error__")},
      {prefix <> " | drop __error__,__error_details__", %{"__error_details__" => "mine"}},
      {prefix <> " | label_format saved=__error_details__", Map.put(error, "saved", "mine")},
      {prefix <> ~s/ | label_format saved="{{.__error_details__}}"/, Map.put(error, "saved", "Malformed JSON error")},
      {prefix <> ~s/ | drop __error_details__="mine"/, error},
      {prefix <> ~s/ | drop __error_details__="Malformed JSON error"/, %{error | "__error_details__" => "mine"}},
      {prefix <> " | keep app | drop __error_details__", %{error | "__error_details__" => "mine"}},
      {prefix <> ~s/ | __error_details__="mine"/, error},
      {prefix <> ~s/ | line_format "{{.__error_details__}}"/, error},
      {~s/{app="a",pod="p1"} | json | label_format __error_details__="mine",saved="{{.__error_details__}}" | drop __error_details__/,
       %{"__error__" => "JSONParserErr", "__error_details__" => "mine", "saved" => "Malformed JSON error"}},
      {prefix <> ~S/ | line_format "broken=\"" | logfmt --strict | drop __error_details__/,
       %{"__error__" => "LogfmtParserErr", "__error_details__" => "mine"}}
    ]

    for {query, expected} <- controls, method <- [&request/4, &request_form/4] do
      response =
        method.(
          categorize(ctx),
          "/query_range",
          [query: query, start: to_string(ctx.now), end: to_string(ctx.now + 60 * @second)],
          200
        )

      assert [%{"values" => [[_, _, categories]]}] = response["data"]["result"], query
      assert categories["parsed"] == expected, query
    end

    for {template, expected} <- [
          {"{{.__error_details__}}", "mine"},
          {"{{.__error_details__ | print}}", "Malformed JSON error"}
        ],
        method <- [&request/4, &request_form/4] do
      query = prefix <> " | line_format " <> Pulse.JSON.encode!(template)

      response =
        method.(
          categorize(ctx),
          "/query_range",
          [query: query, start: to_string(ctx.now), end: to_string(ctx.now + 60 * @second)],
          200
        )

      assert [%{"values" => [[_, ^expected, _]]}] = response["data"]["result"]
    end

    for method <- [&request/4, &request_form/4] do
      query = prefix <> ~s/ | line_format "{{div 1 0}}"/

      response =
        method.(
          categorize(ctx),
          "/query_range",
          [query: query, start: to_string(ctx.now), end: to_string(ctx.now + 60 * @second)],
          200
        )

      assert [%{"values" => [[_, "{", %{"parsed" => parsed}]]}] = response["data"]["result"]
      assert parsed["__error__"] == "TemplateFormatErr"
      assert parsed["__error_details__"] =~ "divide by zero"
    end

    for {suffix, expected} <- [
          {" | drop __error_details__", %{"__error__" => "JSONParserErr"}},
          {" | drop __error__", %{"__error_details__" => "mine"}},
          {" | drop __error__,__error_details__", %{"__error_details__" => "mine"}}
        ] do
      query = ~s/first_over_time(#{prefix} | __error__!="" #{suffix} | unwrap n [1m]) by (__error_details__)/
      assert_metric(ctx, query, 60, %{expected => [{60, "7"}]})
      assert_metric(ctx, query, {60, 120, 60}, %{expected => [{60, "7"}]})
    end

    query =
      ~s/first_over_time(#{prefix} | label_format v="oops" | unwrap v | __error__!="" [1m]) by (__error_details__)/

    assert_metric(ctx, query, 60, %{
      %{
        "__error__" => "SampleExtractionErr",
        "__error_details__" => ~s/strconv.ParseFloat: parsing "oops": invalid syntax/
      } => [{60, "0"}]
    })

    assert_parquet_read(ctx)
  end

  @tag :formatter_error_ownership_batch
  test "error-detail ownership never suppresses template output or work exhaustion", ctx do
    ctx = %{ctx | now: ctx.now - 120 * @second}
    push_formatter_error_rows(ctx)
    prefix = ~s/{app="a",pod="p1"} | json | label_format __error_details__=/

    for template <- [~s/{{repeat 16777217 "x"}}/, "{{range 100}}x{{end}}"],
        method <- [&request/4, &request_form/4] do
      if template =~ "range", do: Runtime.put_env(:pulse, Evaluator, max_work: 5)
      query = ~s/count_over_time(#{prefix}#{Pulse.JSON.encode!(template)} | __error__!="" [1m])/
      response = method.(ctx, "/query", [query: query, time: to_string(ctx.now + 60 * @second)], 422)
      assert response["error"] == "query_limit"
      refute Map.has_key?(response, "data")
    end

    assert_parquet_read(ctx)
  end

  defp push_formatter_error_rows(ctx) do
    push_streams(
      ctx,
      for {app, pod, line, second, n} <- [
            {"a", "p1", "{", 40, "7"},
            {"a", "p2", ~s/{"ok":1}/, 20, "5"},
            {"noise", "p3", ~s/{"ok":1}/, 20, "9"}
          ] do
        %{
          "stream" => %{"app" => app, "pod" => pod},
          "values" => [[to_string(ctx.now + second * @second), line, %{"n" => n}]]
        }
      end
    )

    assert_parquet(ctx, 1)
  end

  @tag :http_errors_batch
  test "Loki parse and interval errors retain upstream client-error status", ctx do
    for method <- [&request/4, &request_form/4], path <- ["/query", "/query_range"] do
      response = method.(ctx, path, [{"query", "{"} | range(ctx)], @http_error_rows["parse error"]["status"])
      assert response["error"] == "parse_error"
      refute Map.has_key?(response, "data")

      limited = query_limits(ctx, ~s({"maxQueryInterval":"1s"}))

      response =
        method.(
          limited,
          path,
          [{"query", ~s'count_over_time({job="fake"}[2s])'} | range(ctx)],
          @http_error_rows["interval limit"]["status"]
        )

      assert response["error"] == "query_limit"
      assert response["message"] =~ @http_error_rows["interval limit"]["body"]
      refute Map.has_key?(response, "data")
    end

    assert Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == {[], 0, []}
  end

  @tag :http_errors_batch
  test "finite Loki reads retain upstream deadline status with a sanitized JSON body", ctx do
    Runtime.put_env(:pulse, Storage, adapter: BlockingMetricStorage)
    Runtime.put_env(:pulse, BlockingMetricStorage, {:error, :query_timeout})

    for {path, extra} <- finite_reads(), method <- [&request/4, &request_form/4] do
      params =
        extra ++
          [{"time", to_string(ctx.now)}, {"start", to_string(ctx.now - @minute)}, {"end", to_string(ctx.now)}]

      assert method.(ctx, path, params, @http_error_rows["deadline"]["status"]) == %{
               "status" => "error",
               "error" => "query_timeout",
               "message" => "Query timed out."
             }
    end
  end

  @tag :http_errors_batch
  test "finite Loki reads retain upstream internal status after worker failure", ctx do
    Runtime.put_env(:pulse, Storage, adapter: BlockingMetricStorage)
    Runtime.put_env(:pulse, BlockingMetricStorage, self())

    for {path, extra} <- finite_reads(), method <- [&request/4, &request_form/4] do
      params =
        extra ++
          [{"time", to_string(ctx.now)}, {"start", to_string(ctx.now - @minute)}, {"end", to_string(ctx.now)}]

      caller = Pulse.Runtime.Task.async(fn -> method.(ctx, path, params, @http_error_rows["internal"]["status"]) end)
      assert_receive {:blocked_metric_query, worker, tenant}, 1000
      assert tenant == ctx.tenant
      ref = Process.monitor(worker)
      Process.exit(worker, :simulated_query_failure)
      assert_receive {:DOWN, ^ref, :process, ^worker, :simulated_query_failure}, 1000

      assert Task.await(caller) == %{
               "status" => "error",
               "error" => "query_failed",
               "message" => "Query execution failed."
             }
    end
  end

  @tag :http_errors_batch
  test "finite Loki reads sanitize storage failures consistently", ctx do
    Runtime.put_env(:pulse, Storage, adapter: BlockingMetricStorage)
    Runtime.put_env(:pulse, BlockingMetricStorage, {:error, {:provider_failure, "private-provider-detail"}})

    for {path, extra} <- finite_reads(), method <- [&request/4, &request_form/4] do
      params =
        extra ++
          [{"time", to_string(ctx.now)}, {"start", to_string(ctx.now - @minute)}, {"end", to_string(ctx.now)}]

      assert method.(ctx, path, params, 503) == %{
               "status" => "error",
               "error" => "storage_unavailable",
               "message" => "Storage is unavailable."
             }
    end

    assert Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == {[], 0, []}

    Runtime.put_env(:pulse, Storage, adapter: S3)
    push(ctx, "recovered", ctx.now, %{"job" => "fake"})
    assert lines(request(ctx, "/query_range", [{"query", ~s({job="fake"})} | range(ctx)])) == ["recovered"]
    assert_parquet_read(ctx)
  end

  @tag :http_parameter_controls
  test "Loki HTTP parameters reject malformed supplied values before provider access", ctx do
    push(ctx, "control", ctx.now, %{"job" => "http-parameters"})

    for {path, additions} <- [
          {"/query", [{"limit", "h"}]},
          {"/query", [{"direction", "fw"}]},
          {"/query_range", [{"limit", "4294967296"}]},
          {"/query_range", [{"direction", "fw"}]},
          {"/query_range", [{"step", "h"}]},
          {"/query_range", [{"step", "-1"}]},
          {"/query_range", [{"interval", "-1"}]},
          {"/query_range", [{"interval", "nonsense"}]}
        ],
        method <- [&request/4, &request_form/4] do
      params = Map.new([{"query", ~s({job="http-parameters"})} | range(ctx)] ++ additions)
      before = Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests})
      response = method.(ctx, path, params, 400)
      assert response["error"] == "invalid_parameter"
      assert Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == before
    end
  end

  @tag :http_calendar_batch
  test "Go calendar timestamp spellings retain exact HTTP bounds and native evaluation times", ctx do
    # Go 1.27.3 time.Parse(RFC3339Nano) oracles, not Elixir ISO conversions.
    cases = [
      {"2020-01-02T3:04:05Z", 1_577_934_245_000_000_000},
      {"2020-01-02T03:04:05+24:00", 1_577_847_845_000_000_000},
      {"2020-01-02T03:04:05+00:60", 1_577_930_645_000_000_000},
      {"2020-01-02T03:04:05-24:60", 1_578_024_245_000_000_000},
      {"2020-01-02T03:04:05,123456789Z", 1_577_934_245_123_456_789},
      {"2020-01-02T03:04:05.1234567899Z", 1_577_934_245_123_456_789}
    ]

    push_streams(
      ctx,
      for {{_input, ns}, index} <- Enum.with_index(cases) do
        %{
          "stream" => %{"job" => "calendar", "case" => to_string(index)},
          "values" => [[to_string(ns - 1), "before"], [to_string(ns), "on"], [to_string(ns + 1), "after"]]
        }
      end
    )

    for {{input, ns}, index} <- Enum.with_index(cases), method <- [&request/4, &request_form/4] do
      selector = ~s({job="calendar",case="#{index}"})

      # Instant remains inclusive. Range checks exercise the same calendar
      # spelling once as the inclusive start and once as the exclusive end.
      for {path, bounds, expected} <- [
            {"/query", [time: input, start: input, end: input], [[to_string(ns), "on"]]},
            {"/query_range", [start: input, end: to_string(ns + 1)], [[to_string(ns), "on"]]},
            {"/query_range", [start: to_string(ns - 1), end: input], [[to_string(ns - 1), "before"]]}
          ] do
        response = method.(ctx, path, [query: selector] ++ bounds, 200)
        assert [stream] = response["data"]["result"]
        assert stream["values"] == expected
      end

      response = method.(ctx, "/query", [query: "count_over_time(#{selector}[1s])", time: input], 200)
      assert [%{"value" => [time, "2"]}] = response["data"]["result"]
      assert time == ns / @second
    end

    for input <- [
          "2020-01-02T03:04:05+25:00",
          "2020-01-02T03:04:05+00:61",
          "2020-01-02t03:04:05z",
          "2262-04-11T23:47:16.854775808Z",
          "1677-09-21T00:12:43.145224191Z",
          "2020-01-02T03:04:05." <> String.duplicate("1", 108) <> "Z"
        ],
        method <- [&request/4, &request_form/4],
        {path, field} <- [{"/query", :time}, {"/query_range", :start}, {"/query_range", :end}] do
      params = Keyword.put([query: ~s({job="calendar"}), start: "0", end: "0"], field, input)
      before = Agent.get(ctx.store, & &1.requests)
      response = method.(ctx, path, params, 400)
      assert response["error"] == "invalid_parameter"
      assert Agent.get(ctx.store, & &1.requests) == before
    end

    assert_parquet(ctx, 1)
    assert_parquet_read(ctx)
  end

  @tag :http_parameter_controls
  test "Loki HTTP interval samples globally before the limit in either direction", ctx do
    base = div(ctx.now, @second) * @second

    # Separate immutable objects have overlapping time envelopes.
    for stream <- [
          %{
            "stream" => %{"job" => "interval", "owner" => "a"},
            "values" => for(n <- [0, 2, 4, 6], do: [to_string(base + n * @second), "a#{n}"])
          },
          %{
            "stream" => %{"job" => "interval", "owner" => "b"},
            "values" => for(n <- [1, 3, 5], do: [to_string(base + n * @second), "b#{n}"])
          }
        ],
        do: push_streams(ctx, [stream])

    for method <- [&request/4, &request_form/4],
        {direction, expected} <- [{"FORWARD", ["a0", "b3", "a6"]}, {"BACKWARD", ["a6", "b3", "a0"]}] do
      params = [
        {"query", ~s({job="interval"})},
        {"start", to_string(base)},
        {"end", to_string(base + 7 * @second)},
        {"direction", direction},
        {"step", "0.5"},
        {"interval", "3"},
        {"limit", "3"}
      ]

      response = method.(ctx, "/query_range", params, 200)
      values = Enum.flat_map(response["data"]["result"], & &1["values"])
      order = if direction == "FORWARD", do: :asc, else: :desc

      assert values |> Enum.sort_by(fn [ts | _] -> String.to_integer(ts) end, order) |> Enum.map(&Enum.at(&1, 1)) ==
               expected

      # Pipelines still run before interval selection and retain source times.
      formatted =
        List.keyreplace(params, "query", 0, {"query", ~s({job="interval"} !~ "[25]$" | line_format "{{__line__}}!")})

      response = method.(ctx, "/query_range", formatted, 200)
      values = Enum.flat_map(response["data"]["result"], & &1["values"])

      assert values |> Enum.sort_by(fn [ts | _] -> String.to_integer(ts) end, order) |> Enum.map(&Enum.at(&1, 1)) ==
               Enum.map(expected, &(&1 <> "!"))
    end
  end

  # Component-only rows replay in HTTPParamsTest. These complete request tables
  # additionally exercise real authentication, form decoding and native S3 reads.
  @tag :http_parameter_controls
  test "interval collection fails whole on sample and work ceilings, while zero keeps ordinary top-k", ctx do
    for n <- 0..2, do: push(ctx, "keep #{n}", ctx.now + n * @second, %{"job" => "interval-budget"})
    push(ctx, "drop", ctx.now + 3 * @second, %{"job" => "interval-budget"})

    params = [
      {"query", ~s({job="interval-budget"} |= "keep" | line_format "{{__line__}}!")},
      {"start", to_string(ctx.now)},
      {"end", to_string(ctx.now + 4 * @second)},
      {"limit", "1"},
      {"interval", "1"}
    ]

    for limits <- [[max_log_samples: 2], [max_work: 1]], method <- [&request/4, &request_form/4] do
      Runtime.put_env(:pulse, Evaluator, limits)
      response = method.(ctx, "/query_range", params, 422)
      assert response["error"] == "query_limit"
      refute Map.has_key?(response, "data")
    end

    Runtime.put_env(:pulse, Evaluator, max_log_samples: 2)

    for method <- [&request/4, &request_form/4] do
      response = method.(ctx, "/query_range", List.keyreplace(params, "interval", 0, {"interval", "0"}), 200)

      assert Enum.flat_map(response["data"]["result"], & &1["values"]) == [
               [to_string(ctx.now + 2 * @second), "keep 2!"]
             ]
    end
  end

  @tag :http_parameter_controls
  test "decimal timestamps, since windows and fractional volume steps affect retained HTTP results", ctx do
    base = 1_571_332_130 * @second
    for n <- [0, 1, 2, 3], do: push(ctx, "abc", base + n * 1_000_000, %{"job" => "decimal"})

    for method <- [&request/4, &request_form/4] do
      params = [query: ~s({job="decimal"}), start: "1571332130.0004", end: "1571332130.0016", direction: "forward"]
      response = method.(ctx, "/query_range", params, 200)

      # Decimal parameter rounding is unchanged: the admitted end rounds to
      # base+2ms, which is now correctly excluded from raw range results.
      assert Enum.flat_map(response["data"]["result"], & &1["values"]) ==
               for(n <- [0, 1], do: [to_string(base + n * 1_000_000), "abc"])

      assert method.(ctx, "/labels", [end: to_string(base + @second), since: "1s"], 200)["data"] == ["job"]
      assert method.(ctx, "/labels", [end: to_string(base + 2 * @second), since: "1s"], 200)["data"] == []
    end

    response =
      request(ctx, "/index/volume_range",
        query: ~s({job="decimal"}),
        start: to_string(base),
        end: to_string(base + @second),
        step: "0.5"
      )

    assert [%{"metric" => %{"job" => "decimal"}, "values" => samples}] = response["data"]["result"]
    # The first evaluation includes the start event; the next includes the
    # other three events. Four three-byte lines must contribute exactly once.
    assert Enum.sum_by(samples, fn [_, value] -> String.to_integer(value) end) == 12
  end

  @tag :index_stats_range_admission
  test "index stats admits range parameters before manifest reads without using them to truncate statistics", ctx do
    push(ctx, "first", ctx.now, %{"job" => "stats"})
    push(ctx, "second", ctx.now, %{"job" => "stats"})
    assert_parquet(ctx, 2)

    params = [query: ~s({job="stats"}), start: to_string(ctx.now - @second), end: to_string(ctx.now + @second)]

    for method <- [&request/4, &request_form/4] do
      expected = method.(ctx, "/index/stats", params, 200)
      assert %{"streams" => 0, "chunks" => 2, "entries" => 2, "bytes" => bytes} = expected
      assert bytes > 0

      for invalid <- [
            [step: "0"],
            [step: "-1"],
            [step: "invalid"],
            [step: "NaN"],
            [step: "+Inf"],
            [step: "1ns"],
            [limit: "0"],
            [limit: "-1"],
            [limit: "4294967296"],
            [limit: "invalid"],
            [direction: "sideways"],
            [interval: "-1"],
            [interval: "invalid"],
            [start: "invalid"],
            [start: to_string(ctx.now + 2 * @second)],
            [start: to_string(ctx.now - 11_001 * @second), end: to_string(ctx.now), step: "1"]
          ] do
        before = Agent.get(ctx.store, & &1.requests)
        response = method.(ctx, "/index/stats", Keyword.merge(params, invalid), 400)
        refute Map.has_key?(response, "entries")
        assert Agent.get(ctx.store, & &1.requests) == before
      end

      for valid <- [
            [limit: "1", direction: "forward", step: "0.5", interval: "1h"],
            [limit: "4294967295", direction: "BACKWARD", interval: "0"],
            [limit: "", direction: "", step: "", interval: ""],
            [start: to_string(ctx.now), end: to_string(ctx.now)],
            [start: to_string(ctx.now - 11_000 * @second - 999_999_999), end: to_string(ctx.now), step: "1"]
          ] do
        assert method.(ctx, "/index/stats", Keyword.merge(params, valid), 200) == expected
      end
    end

    refute_parquet_read(ctx)
  end

  @tag :discovery_scalar_precedence
  test "discovery takes the first scalar value, with form values before URL values", ctx do
    a = %{"job" => "a", "only_a" => "yes"}
    b = %{"job" => "b", "only_b" => "yes"}
    push(ctx, "recent", ctx.now, a)
    push(ctx, "older", ctx.now - 120 * @second, b)
    assert_parquet(ctx, 2)

    start = to_string(ctx.now - 180 * @second)
    finish = to_string(ctx.now + @second)
    recent = to_string(ctx.now - @second)
    bounds = [{"start", start}, {"end", finish}]

    routes = [
      {"/labels", ["job", "only_a"], ["job", "only_a", "only_b"]},
      {"/label/job/values", ["a"], ["a", "b"]},
      {"/series", [a], [a, b]}
    ]

    for {path, one, both} <- routes, method <- [&request/4, &request_form/4] do
      for {params, expected} <- [
            {[{"start", start}, {"start", recent}, {"end", finish}], both},
            {[{"start", recent}, {"start", "invalid"}, {"end", finish}], one},
            {[{"start", start}, {"end", finish}, {"end", to_string(ctx.now - 60 * @second)}], both},
            {[{"start", start}, {"end", finish}, {"end", "invalid"}], both},
            {[{"end", finish}, {"since", "180s"}, {"since", "1s"}], both},
            {[{"end", finish}, {"since", "1s"}, {"since", "invalid"}], one},
            {[{"start", ""}, {"start", "invalid"}, {"end", finish}, {"since", "1s"}], one},
            {[{"start", start}, {"end", ""}, {"end", "invalid"}], both},
            {[{"end", finish}, {"since", ""}, {"since", "invalid"}], both}
          ] do
        assert method.(ctx, path, params, 200)["data"] == expected
      end

      for {name, valid} <- [{"start", start}, {"end", finish}, {"since", "1s"}] do
        before = Agent.get(ctx.store, & &1.requests)
        response = method.(ctx, path, [{name, "invalid"}, {name, valid}], 400)
        refute Map.has_key?(response, "data")
        assert Agent.get(ctx.store, & &1.requests) == before
      end
    end

    for {path, one, both} <- Enum.take(routes, 2), method <- [&request/4, &request_form/4] do
      assert method.(ctx, path, [{"query", ~s({job="a"})}, {"query", ~s({job="b"})} | bounds], 200)["data"] == one
      assert method.(ctx, path, [{"query", ""}, {"query", ~s({job="a"})} | bounds], 200)["data"] == both

      before = Agent.get(ctx.store, & &1.requests)
      response = method.(ctx, path, [{"query", "invalid"}, {"query", ~s({job="a"})} | bounds], 400)
      refute Map.has_key?(response, "data")
      assert Agent.get(ctx.store, & &1.requests) == before
    end

    for {path, one, _both} <- routes do
      url = path <> "?" <> URI.encode_query(start: "invalid", end: "invalid", since: "invalid")
      assert request_form(ctx, url, [{"start", ""}, {"end", finish}, {"since", "1s"}])["data"] == one

      before = Agent.get(ctx.store, & &1.requests)
      url = path <> "?" <> URI.encode_query(bounds)
      response = request_form(ctx, url, [{"start", "invalid"}], 400)
      refute Map.has_key?(response, "data")
      assert Agent.get(ctx.store, & &1.requests) == before
    end

    for {path, _one, both} <- Enum.take(routes, 2) do
      url = path <> "?" <> URI.encode_query([{"query", "invalid"} | bounds])
      assert request_form(ctx, url, [{"query", ""}])["data"] == both

      before = Agent.get(ctx.store, & &1.requests)
      url = path <> "?" <> URI.encode_query([{"query", ~s({job="a"})} | bounds])
      response = request_form(ctx, url, [{"query", "invalid"}], 400)
      refute Map.has_key?(response, "data")
      assert Agent.get(ctx.store, & &1.requests) == before
    end

    # Repeated selectors are a union, never scalar first-value selection.
    for method <- [&request/4, &request_form/4] do
      response = method.(ctx, "/series", [{"match", ~s({job="a"})}, {"match[]", ~s({job="b"})} | bounds], 200)
      assert Enum.sort(response["data"]) == Enum.sort([a, b])
    end

    url = "/series?" <> URI.encode_query([{"match", ~s({job="a"})} | bounds])
    assert request_form(ctx, url, [{"match[]", ~s({job="b"})}])["data"] |> Enum.sort() == Enum.sort([a, b])

    assert_parquet_read(ctx)
  end

  @tag :discovery_literal_scalars
  test "discovery ignores bracketed names instead of expanding them into scalar parameters", ctx do
    a = %{"job" => "a", "only_a" => "yes"}
    b = %{"job" => "b", "only_b" => "yes"}
    push(ctx, "recent", ctx.now, a)
    push(ctx, "older", ctx.now - 120 * @second, b)

    bounds = [
      {"start", to_string(ctx.now - 180 * @second)},
      {"end", to_string(ctx.now + @second)},
      {"since", "180s"}
    ]

    routes = [
      {"/labels", ["job", "only_a", "only_b"]},
      {"/label/job/values", ["a", "b"]},
      {"/series", [a, b]}
    ]

    for {path, expected} <- routes, method <- [&request/4, &request_form/4] do
      for name <- ["start", "end", "since"], suffix <- ["[]", "[ignored]"] do
        params = Enum.reject(bounds, fn {key, _} -> key == name end) ++ [{name <> suffix, "invalid"}]
        assert method.(ctx, path, params, 200)["data"] == expected
      end

      for {name, value} <- bounds do
        params = List.keyreplace(bounds, name, 0, {name, "invalid"}) ++ [{name <> "[]", value}]
        before = Agent.get(ctx.store, & &1.requests)
        response = method.(ctx, path, params, 400)
        refute Map.has_key?(response, "data")
        assert Agent.get(ctx.store, & &1.requests) == before
      end
    end

    for {path, expected} <- Enum.take(routes, 2), method <- [&request/4, &request_form/4] do
      for suffix <- ["[]", "[ignored]"] do
        assert method.(ctx, path, [{"query" <> suffix, ~s({job="a"})} | bounds], 200)["data"] == expected
      end

      before = Agent.get(ctx.store, & &1.requests)
      response = method.(ctx, path, [{"query", "invalid"}, {"query[]", ~s({job="a"})} | bounds], 400)
      refute Map.has_key?(response, "data")
      assert Agent.get(ctx.store, & &1.requests) == before
    end

    assert_parquet(ctx, 2)
    assert_parquet_read(ctx)
  end

  for row <- @http_parameter_rows,
      row["table"] in ["TestParseRangeQuery", "TestParseInstantQuery", "TestHttp_ParseRangeQuery_Step"] do
    @tag :http_parameters_batch
    test "HTTP parameter query table #{row["table"]}/#{row["name"]}", ctx do
      row = unquote(Macro.escape(row))
      params = http_parameter_params(row)
      path = if row["table"] == "TestParseInstantQuery", do: "/query", else: "/query_range"

      included_ts =
        if !row["error"]["reject"] do
          fields = row["expected"]["fields"]
          finish = String.to_integer(fields["End_ns"] || fields["Ts_ns"])
          # These are authored execution seeds, not source table inputs.
          # Keep the original HTTP parameters/struct oracles unchanged: range
          # inclusion is 1ns before its exclusive end, instant inclusion at time.
          included = if path == "/query_range", do: finish - 1, else: finish
          push(ctx, "included", included, %{"foo" => "bar"})
          push(ctx, "excluded", included + 1, %{"foo" => "bar"})
          included
        end

      for method <- [&request/4, &request_form/4] do
        before = Agent.get(ctx.store, & &1.requests)
        response = method.(ctx, path, params, if(row["error"]["reject"], do: 400, else: 200))

        if row["error"]["reject"] do
          assert Agent.get(ctx.store, & &1.requests) == before
        else
          assert Enum.flat_map(response["data"]["result"], & &1["values"]) ==
                   [[to_string(included_ts), "included"]]

          assert_parquet_read(ctx)
        end
      end
    end
  end

  for row <- @http_parameter_rows, row["table"] == "TestParseLabelQuery" do
    @tag :http_parameters_batch
    test "HTTP parameter label table #{row["name"]}", ctx do
      row = unquote(Macro.escape(row))
      fields = row["expected"]["fields"]
      path = if fields && fields["Values"], do: "/label/#{fields["Name"]}/values", else: "/labels"

      if fields do
        push(ctx, "inside", String.to_integer(fields["Start_ns"]), %{"test" => "inside"})
        push(ctx, "outside", String.to_integer(fields["End_ns"]) + 1, %{"test" => "outside"})
      end

      for method <- [&request/4, &request_form/4] do
        before = Agent.get(ctx.store, & &1.requests)
        response = method.(ctx, path, http_parameter_params(row), if(row["error"]["reject"], do: 400, else: 200))

        if row["error"]["reject"] do
          assert Agent.get(ctx.store, & &1.requests) == before
        else
          assert response["data"] == if(fields["Values"], do: ["inside"], else: ["test"])
          assert_parquet_read(ctx)
        end
      end
    end
  end

  for row <- @http_parameter_rows, row["table"] == "TestParseAndValidateSeriesQuery" do
    @tag :http_parameters_batch
    test "HTTP parameter series table #{row["name"]}", ctx do
      row = unquote(Macro.escape(row))
      fields = row["expected"]["fields"]
      start = String.to_integer(fields["Start_ns"])
      finish = String.to_integer(fields["End_ns"])
      a = %{"a" => "1"}
      b = %{"b" => "2", "c" => "3", "d" => "5"}
      noise = %{"other" => "noise"}
      for labels <- [a, b, noise], do: push(ctx, "inside", start, labels)
      push(ctx, "outside", finish + 1, %{"a" => "1", "outside" => "true"})

      expected =
        case fields["Groups"] do
          [] -> [a, b, noise]
          [~s({foo=""})] -> [a, b, noise]
          _ -> [a, b]
        end

      for method <- [&request/4, &request_form/4] do
        response = method.(ctx, "/series", http_parameter_params(row), 200)
        assert Enum.sort(response["data"]) == Enum.sort(expected)
      end

      assert_parquet_read(ctx)
    end
  end

  for row <- @http_parameter_rows, row["table"] == "TestParseTailQuery" do
    @tag :http_parameters_batch
    test "HTTP parameter tail table #{row["name"]}", ctx do
      row = unquote(Macro.escape(row))
      params = http_parameter_params(row)

      if !row["error"]["reject"] do
        start = String.to_integer(row["expected"]["fields"]["Start_ns"])
        push(ctx, "excluded", start - 1, %{"foo" => "bar"})
        push(ctx, "history", start, %{"foo" => "bar"})
      end

      before = Agent.get(ctx.store, & &1.requests)
      path = "/loki/api/v1/tail?" <> URI.encode_query(params)
      result = WebSocketClient.connect(URI.parse(ctx.url).port, path, headers(ctx))

      if row["error"]["reject"] do
        assert {:error, {400, _}} = result
        assert Agent.get(ctx.store, & &1.requests) == before
      else
        assert {:ok, socket} = result

        try do
          assert tail_values(socket, 1) == [[row["expected"]["fields"]["Start_ns"], "history"]]
        after
          WebSocketClient.close(socket)
        end

        assert_parquet_read(ctx)
      end
    end
  end

  for row <- @http_parameter_rows, row["table"] == "TestParsePatternsQuery" do
    @tag :http_parameters_batch
    test "HTTP parameter patterns table #{row["name"]}", ctx do
      row = unquote(Macro.escape(row))
      params = http_parameter_params(row)
      fields = row["expected"]["fields"]

      if fields do
        start = String.to_integer(fields["Start_ns"])
        push(ctx, "parameter pattern", start + 1_000_000, %{"foo" => "bar"})
        push(ctx, "parameter pattern", String.to_integer(fields["End_ns"]) - 1_000_000, %{"foo" => "bar"})
        push(ctx, "excluded", String.to_integer(fields["End_ns"]) + 1, %{"foo" => "bar"})
      end

      before = Agent.get(ctx.store, & &1.requests)
      response = request(ctx, "/patterns", params, if(row["error"]["reject"], do: 400, else: 200))

      if row["error"]["reject"] do
        assert Agent.get(ctx.store, & &1.requests) == before
      else
        start = String.to_integer(fields["Start_ns"])
        step = String.to_integer(fields["Step_ns"])

        samples =
          [start + 1_000_000, String.to_integer(fields["End_ns"]) - 1_000_000]
          |> Enum.frequencies_by(&div(start + div(&1 - start, step) * step, @second))
          |> Enum.sort()
          |> Enum.map(fn {ts, count} -> [ts, count] end)

        assert response["data"] == [%{"pattern" => "parameter pattern", "samples" => samples}]
        assert_parquet_read(ctx)
      end
    end
  end

  for row <- @http_parameter_rows, row["table"] in ["Test_ParseVolumeInstantQuery", "Test_ParseVolumeRangeQuery"] do
    @tag :http_parameters_batch
    test "HTTP parameter volume table #{row["table"]}/#{row["name"]}", ctx do
      row = unquote(Macro.escape(row))
      params = http_parameter_params(row)
      path = if row["table"] == "Test_ParseVolumeInstantQuery", do: "/index/volume", else: "/index/volume_range"

      if !row["error"]["reject"] do
        # Partial aggregateBy oracles remain partial. The shared original bounds
        # come from the complete row, not from the parser under test.
        complete = Enum.find(@http_parameter_rows, &(&1["table"] == row["table"] and &1["name"] == ""))
        finish = String.to_integer(complete["expected"]["fields"]["End_ns"])
        push(ctx, "abc", finish - @second, %{"foo" => "bar", "bar" => "baz", "noise" => "unused"})
        push(ctx, "excluded", finish + @second, %{"foo" => "bar", "bar" => "baz"})
      end

      before = Agent.get(ctx.store, & &1.requests)
      response = request(ctx, path, params, if(row["error"]["reject"], do: 400, else: 200))

      if row["error"]["reject"] do
        assert response["message"] == row["error"]["equals"]
        assert Agent.get(ctx.store, & &1.requests) == before
      else
        labels? = row["expected"]["AggregateBy"] == "labels"
        expected_labels = if labels?, do: [%{"bar" => ""}, %{"foo" => ""}], else: [%{"foo" => "bar", "bar" => "baz"}]
        result = response["data"]["result"]
        assert Enum.sort(Enum.map(result, & &1["metric"])) == Enum.sort(expected_labels)

        for series <- result do
          samples = if path == "/index/volume", do: [series["value"]], else: series["values"]
          assert Enum.sum_by(samples, fn [_, value] -> String.to_integer(value) end) == 3
        end

        assert_parquet_read(ctx)
      end
    end
  end

  @tag :correlation_labels_batch
  test "correlation IDs survive Loki push as metadata, not stream labels", ctx do
    ids = [
      %{"trace_id" => "t1", "span_id" => "s1"},
      %{"trace_id" => "t1", "span_id" => "s2"},
      %{"trace_id" => "t2", "span_id" => "s1"},
      %{},
      %{"trace_id" => "", "span_id" => ""}
    ]

    line = "trace_id=parsed span_id=parsed"
    base = %{"app" => "correlation"}

    rows =
      for {metadata, index} <- Enum.with_index(ids) do
        {to_string(ctx.now + index * @second), metadata}
      end

    push_streams(ctx, [%{"stream" => base, "values" => for({ts, metadata} <- rows, do: [ts, line, metadata])}])

    for categorized? <- [false, true], path <- ["/query", "/query_range"], method <- [&request/4, &request_form/4] do
      params = [query: ~s'{app="correlation"}', start: to_string(ctx.now), end: to_string(ctx.now + 4 * @second)]

      params =
        if path == "/query_range", do: Keyword.put(params, :end, to_string(ctx.now + 4 * @second + 1)), else: params

      response = method.(if(categorized?, do: categorize(ctx), else: ctx), path, params, 200)

      actual =
        for %{"stream" => stream, "values" => values} <- response["data"]["result"],
            [ts, ^line | extra] <- values,
            into: %{},
            do: {ts, {stream, extra}}

      expected =
        Map.new(rows, fn {ts, metadata} ->
          metadata = if metadata == %{"trace_id" => "", "span_id" => ""}, do: %{}, else: metadata
          extra = if metadata == %{}, do: %{}, else: %{"structuredMetadata" => metadata}
          value = if categorized?, do: {base, [extra]}, else: {Map.merge(base, metadata), []}
          {ts, value}
        end)

      assert actual == expected
    end

    expected = %{
      %{"trace_id" => "t1", "span_id" => "s1"} => [{4, "1"}],
      %{"trace_id" => "t1", "span_id" => "s2"} => [{4, "1"}],
      %{"trace_id" => "t2", "span_id" => "s1"} => [{4, "1"}],
      %{} => [{4, "2"}]
    }

    query = ~s'sum by (trace_id,span_id) (count_over_time({app="correlation"}[1m]))'
    assert_metric(ctx, query, 4, expected)
    assert_metric(ctx, query, {4, 4, "1"}, expected)

    for {stages, count} <- [
          {~s'| trace_id="t1" | span_id="s2"', "1"},
          {~s'| logfmt | trace_id="t1" | trace_id_extracted="parsed" | span_id_extracted="parsed"', "2"},
          {~s'| logfmt | trace_id="parsed" | span_id="parsed"', "2"}
        ] do
      assert_metric(ctx, "sum(count_over_time({app=\"correlation\"} #{stages} [1m]))", 4, %{%{} => [{4, count}]})
    end

    assert_metric(ctx, ~s'count_over_time({app="correlation",trace_id="t1"}[1m])', 4, %{})
    assert_parquet(ctx, 1)
  end

  @tag :sample_extractors_batch
  test "Loki label sample-extractor observations survive HTTP and native Parquet", ctx do
    rows = LokiSampleExtractorFixture.cases(LokiSampleExtractorFixture.load())

    rows =
      Enum.filter(
        rows,
        &(&1.function in [
            "Test_labelSampleExtractor_Extract",
            "Test_Extract_ExpectedLabels",
            "TestLabelExtractorWithStages"
          ])
      )

    assert length(rows) == 41
    replay_sample_extractors(ctx, rows)
  end

  @tag :sample_extractors_batch
  test "Loki line and distinct sample-extractor observations survive HTTP and native Parquet", ctx do
    rows = LokiSampleExtractorFixture.cases(LokiSampleExtractorFixture.load())

    rows =
      Enum.reject(
        rows,
        &(&1.function in [
            "Test_labelSampleExtractor_Extract",
            "Test_Extract_ExpectedLabels",
            "TestLabelExtractorWithStages"
          ])
      )

    assert length(rows) == 47
    replay_sample_extractors(ctx, rows)
  end

  @tag :sample_extractors_batch
  test "Loki sample extraction isolates interleaved stream and metadata owners", ctx do
    # Original A -> B -> A regression input. B's nonmatching metadata must
    # not replace A's own namespace. This checks public isolation, not Go types.
    a = %{"app" => "a", "namespace" => "dev"}
    b = %{"app" => "b"}

    push_streams(ctx, [
      %{"stream" => a, "values" => [[to_string(ctx.now), "line"], [to_string(ctx.now + 2 * @second), "line"]]},
      %{"stream" => b, "values" => [[to_string(ctx.now + @second), "line", %{"namespace" => "prod"}]]}
    ])

    query = ~s'sum by (app) (count_over_time({} | namespace="dev" [1s]))'
    assert_metric(ctx, query, {0, 2, "1"}, %{%{"app" => "a"} => [{0, "1"}, {2, "1"}]})
    assert_metric(ctx, query, 2, %{%{"app" => "a"} => [{2, "1"}]})

    # An authored whole-window control observes both original accepted calls.
    assert_metric(ctx, ~s'sum by (app) (count_over_time({} | namespace="dev" [3s]))', 2, %{
      %{"app" => "a"} => [{2, "2"}]
    })

    assert_parquet(ctx, 1)
  end

  @tag :label_builder_batch
  test "Loki builder literal lookups, maps and Add error categories survive public ingestion", ctx do
    fixture = LokiLabelBuilderFixture.load()
    errors = LokiLabelBuilderFixture.error_case(fixture)
    lookalikes = %{"__error___extracted" => "ordinary", "__error_details___extracted" => "other"}

    control = %{
      errors
      | metadata: Map.merge(errors.metadata, lookalikes),
        checks:
          Enum.map(errors.checks, fn
            {:labels, name, labels} -> {:labels, name, Map.merge(labels, lookalikes)}
            {:structured_metadata, name, _} -> {:structured_metadata, name, lookalikes}
            check -> check
          end)
    }

    rows = push_builder_rows(ctx, LokiLabelBuilderFixture.log_cases(fixture) ++ [errors, control])
    assert length(rows) == 12

    for {row, at} <- rows,
        categorized? <- [false, true],
        path <- ["/query", "/query_range"],
        method <- [&request/4, &request_form/4] do
      timestamp = to_string(at.now)
      params = [query: row.query, start: timestamp, end: timestamp, time: timestamp]
      params = if path == "/query_range", do: Keyword.put(params, :end, to_string(at.now + 1)), else: params
      response = method.(if(categorized?, do: categorize(at), else: at), path, params, 200)
      assert [%{"stream" => stream, "values" => [value]}] = response["data"]["result"]
      assert Enum.take(value, 2) == [timestamp, "label-builder"]
      actual = {stream, if(categorized?, do: Enum.at(value, 2), else: %{})}

      for {kind, name, expected} <- row.checks, categorized? or kind in [:labels, :present, :value] do
        assert LokiLabelBuilderFixture.observation(kind, name, actual) == expected, inspect({row.query, kind, name})
      end
    end

    assert_parquet(ctx, 1)
    assert_parquet_read(ctx)
  end

  @tag :label_builder_batch
  test "Loki builder grouping snapshots reach native Parquet metric queries", ctx do
    rows = push_builder_rows(ctx, LokiLabelBuilderFixture.group_cases(LokiLabelBuilderFixture.load()), 120 * @second)
    assert length(rows) == 13

    for {row, at} <- rows do
      expected = %{row.expected => [{0, "1"}]}
      assert_metric(at, row.query, 0, expected)
      assert_metric(at, row.query, {0, 0, "1"}, expected)
    end
  end

  @tag :label_builder_batch
  test "all Loki preserve-error category and grouping identities remain ordinary labels", ctx do
    rows = push_builder_rows(ctx, LokiLabelBuilderFixture.preserve_cases(LokiLabelBuilderFixture.load()), 120 * @second)
    assert length(rows) == 9

    for {row, at} <- rows, path <- ["/query", "/query_range"], method <- [&request/4, &request_form/4] do
      timestamp = to_string(at.now)
      params = [query: row.query, time: timestamp, start: timestamp, end: timestamp, step: "1"]
      response = method.(at, path, params, 200)
      assert [%{"metric" => labels} = series] = response["data"]["result"]
      samples = if path == "/query", do: [series["value"]], else: series["values"]
      assert samples == [[at.now / @second, "0"]]
      assert labels["__error__"] == "SampleExtractionErr"

      if row.expected == false,
        do: refute(Map.has_key?(labels, "__preserve_error__")),
        else: assert(labels["__preserve_error__"] == row.expected)

      # A caller-supplied label cannot grant error-preservation permission.
      failed = method.(at, path, Keyword.put(params, :query, row.unpreserved_query), 400)
      assert failed["error"] == "evaluation_failed"
      assert failed["message"] =~ "sample_extraction_error"
      refute Map.has_key?(failed, "data")
    end
  end

  @tag :label_builder_batch
  test "the original Loki colliding label pair keeps distinct public log and metric identities", ctx do
    labels = LokiLabelBuilderFixture.collision_labels(LokiLabelBuilderFixture.load())
    assert length(labels) == 2
    timestamp = to_string(ctx.now)
    push_streams(ctx, Enum.map(labels, &%{"stream" => &1, "values" => [[timestamp, "label-builder"]]}))

    for categorized? <- [false, true], path <- ["/query", "/query_range"], method <- [&request/4, &request_form/4] do
      params = [query: "{}", start: timestamp, end: timestamp, time: timestamp]
      params = if path == "/query_range", do: Keyword.put(params, :end, to_string(ctx.now + 1)), else: params
      response = method.(if(categorized?, do: categorize(ctx), else: ctx), path, params, 200)
      value = if categorized?, do: [timestamp, "label-builder", %{}], else: [timestamp, "label-builder"]

      assert Enum.sort(response["data"]["result"]) ==
               Enum.sort(Enum.map(labels, &%{"stream" => &1, "values" => [value]}))
    end

    expected = Map.new(labels, &{&1, [{0, "1"}]})
    assert_metric(ctx, "count_over_time({}[1m])", 0, expected)
    assert_metric(ctx, "count_over_time({}[1m])", {0, 0, "1"}, expected)
    assert_parquet(ctx, 1)
  end

  @tag :pipeline_ownership_batch
  test "complete Loki ordinary pipeline ownership survives authenticated Parquet HTTP", ctx do
    fixture = File.read!("test/fixtures/logs/loki-upstream/pipeline-ownership.json") |> Pulse.JSON.decode!()
    assert fixture["execution_count"] == 30

    rows =
      fixture["executions"]
      |> Enum.with_index(1)
      |> Enum.map(fn {row, index} ->
        {row, Integer.to_string(ctx.now - index * @second)}
      end)

    streams =
      Enum.map(rows, fn {row, timestamp} ->
        %{
          "stream" => Map.new(row["stream_labels"], &{&1["name"], &1["value"]}),
          "values" => [
            [
              timestamp,
              Base.decode64!(row["input_line_bytes_base64"]),
              Map.new(row["structured_metadata"], &{&1["name"], &1["value"]})
            ]
          ]
        }
      end)

    push_streams(ctx, streams)
    assert_parquet(ctx, 1)

    for {row, timestamp} <- rows,
        categorized? <- [false, true],
        path <- ["/query", "/query_range"],
        send_request <- [&request/4, &request_form/4] do
      query = LokiPipelineFixture.query(row["table"], row["source_index"])
      params = %{query: query, start: timestamp, end: timestamp, time: timestamp}
      params = if path == "/query_range", do: %{params | end: to_string(String.to_integer(timestamp) + 1)}, else: params
      response = send_request.(if(categorized?, do: categorize(ctx), else: ctx), path, params, 200)

      expected =
        if row["expected_match"] == false do
          []
        else
          # Drop's original executor does not assert its output line. Keeping
          # that input unchanged is a separate public transport control.
          line = Base.decode64!(row["expected_line_bytes_base64"] || row["input_line_bytes_base64"])

          if categorized? do
            categories =
              Map.new(row["expected_categories"], fn {name, pairs} ->
                {name, Map.new(pairs, &{&1["name"], &1["value"]})}
              end)

            extra =
              %{"structuredMetadata" => categories["structured_metadata"], "parsed" => categories["parsed"]}
              |> Map.reject(fn {_key, labels} -> labels == %{} end)

            [%{"stream" => categories["stream"], "values" => [[timestamp, line, extra]]}]
          else
            [
              %{
                "stream" => Map.new(row["expected_labels"], &{&1["name"], &1["value"]}),
                "values" => [[timestamp, line]]
              }
            ]
          end
        end

      assert response["data"]["resultType"] == "streams"
      assert response["data"]["result"] == expected, row["execution_id"]
    end

    assert_parquet_read(ctx)
    assert_parquet(ctx, 1)
  end

  @tag :formatter_roundtrip_batch
  test "complete Loki formatter query spellings reach public admission with explicit boundaries", ctx do
    fixture = File.read!("test/fixtures/logs/loki-upstream/formatter-roundtrip.json") |> Pulse.JSON.decode!()
    assert fixture["literal_query_count"] == 185

    for table <- fixture["tables"], row <- table["rows"], row["query_is_direct_input"] do
      status =
        case {table["name"], row["source_index"]} do
          {"Test_SampleExpr_String", 49} -> 400
          {"TestStringer", index} when index in [15, 36] -> 400
          {"TestJSONSerializationRoundTrip", 12} -> 400
          {"Test_formatQueryHandlerResponse", 1} -> 400
          _ -> 200
        end

      spellings =
        if row["expected_is_same_expression"] and row["expected_bytes_base64"],
          do: [row["query_bytes_base64"], row["expected_bytes_base64"]],
          else: [row["query_bytes_base64"]]

      for bytes <- spellings, path <- ["/query", "/query_range"], method <- [&request/4, &request_form/4] do
        params = [
          {"query", Base.decode64!(bytes)},
          {"time", to_string(ctx.now)},
          {"start", to_string(ctx.now - @second)},
          {"end", to_string(ctx.now)},
          {"step", "1"}
        ]

        before = Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests})
        response = method.(ctx, path, params, status)

        if status == 400 do
          refute Map.has_key?(response, "data")
          assert Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == before
        else
          assert response["status"] == "success"
        end
      end
    end
  end

  @tag :formatter_roundtrip_batch
  test "Loki stringer literal pairs preserve nonempty native query results", ctx do
    fixture = File.read!("test/fixtures/logs/loki-upstream/formatter-roundtrip.json") |> Pulse.JSON.decode!()
    tables = Map.new(fixture["tables"], &{&1["name"], &1["rows"]})
    assert length(tables["TestStringer"]) == 38

    lines = [
      "foo",
      "bar",
      "baz",
      "car",
      "qux",
      "test",
      "fizz",
      "buzz",
      "127.0.0.1",
      "10.1.2.3",
      "192.168.1.2",
      "foo payload baz",
      "foo tail",
      "foo car"
    ]

    push_streams(ctx, [
      %{
        "stream" => %{"app" => "foo"},
        "values" => Enum.with_index(lines, fn line, index -> [to_string(ctx.now - index * @second), line] end)
      },
      %{
        "stream" => %{"foo" => "bar"},
        "values" => [[to_string(ctx.now), "one"], [to_string(ctx.now - @second), "two"]]
      },
      %{"stream" => %{"region" => "us-east1", "name" => "live"}, "values" => [[to_string(ctx.now), "ranked"]]}
    ])

    for row <- tables["TestStringer"] do
      original = Base.decode64!(row["query_bytes_base64"])
      expected = Base.decode64!(row["expected_bytes_base64"])

      params = [
        {"time", to_string(ctx.now)},
        {"start", to_string(ctx.now - @minute)},
        {"end", to_string(ctx.now)},
        {"step", "60"}
      ]

      # Loki supplies a literal equivalent expression, not a Pulse formatter
      # result. These reads check semantics; the formatting surface stays open.
      for path <- ["/query", "/query_range"], method <- [&request/4, &request_form/4] do
        status = if row["source_index"] in [15, 36], do: 400, else: 200
        before = Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests})

        assert method.(ctx, path, [{"query", original} | params], status) ==
                 method.(ctx, path, [{"query", expected} | params], status),
               inspect({row["source_index"], original, expected})

        if status == 400, do: assert(Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == before)
      end
    end

    # These are original rejection oracles, explicitly not passing ports.
    # A nonempty ranked source distinguishes accepting zero from data absence.
    for row <- tables["Test_SampleExpr_String_Fail"] do
      assert row["reject"]
      query = Base.decode64!(row["query_bytes_base64"])
      assert_metric(ctx, query, 0, %{})
      assert_metric(ctx, query, {0, 0, "1"}, %{})
    end

    assert_parquet(ctx, 1)
    assert_parquet_read(ctx)
  end

  @tag :formatter_roundtrip_batch
  test "original no-op and escaped regex spellings retain actual lines and rates", ctx do
    fixture = File.read!("test/fixtures/logs/loki-upstream/formatter-roundtrip.json") |> Pulse.JSON.decode!()
    tables = Map.new(fixture["tables"], &{&1["name"], &1["rows"]})
    labels = %{"cluster" => "beep", "namespace" => "boop"}
    quoted = "`a\"`"
    line = "msg=" <> Pulse.JSON.encode!(quoted)
    push(ctx, "metadata request", ctx.now - 2 * @second, labels, %{"msg" => "GET /loki/api/123a/query_range"})
    push(ctx, "escaped matcher", ctx.now, labels, %{"msg" => "word"})
    push(ctx, line, ctx.now, %{"foo" => "bar"})
    push(ctx, "missing foo still matches", ctx.now, %{"container_name" => "app"})

    for row <- tables["TestParseSampleExpr_String"] do
      spellings =
        if row["expected_bytes_base64"],
          do: [row["query_bytes_base64"], row["expected_bytes_base64"]],
          else: [row["query_bytes_base64"]]

      if !row["expected_bytes_base64"], do: assert(row["expected_reference"] == "query")

      for bytes <- spellings, path <- ["/query", "/query_range"], method <- [&request/4, &request_form/4] do
        params = [
          {"query", Base.decode64!(bytes)},
          {"time", to_string(ctx.now)},
          {"start", to_string(ctx.now)},
          {"end", to_string(ctx.now)},
          {"step", "1"}
        ]

        params =
          if path == "/query_range" and row["source_index"] in [1, 2],
            do: List.keyreplace(params, "end", 0, {"end", to_string(ctx.now + 1)}),
            else: params

        response = method.(ctx, path, params, 200)

        case row["source_index"] do
          0 ->
            [%{"metric" => %{}} = result] = response["data"]["result"]
            [_timestamp, value] = if path == "/query", do: result["value"], else: hd(result["values"])
            # One matching entry in the original one-day rate window.
            assert String.to_float(value) == 1 / 86_400

          1 ->
            assert_streams(response, [{Map.put(labels, "msg", "word"), ["escaped matcher"]}])

          2 ->
            assert_streams(response, [{%{"foo" => "bar", "msg" => quoted}, [line]}])
        end
      end
    end

    [noop] = tables["TestNoOpLabelToString"]

    for method <- [&request/4, &request_form/4] do
      params = [{"query", Base.decode64!(noop["query_bytes_base64"])} | range(ctx)]

      assert_streams(
        method.(ctx, "/query_range", params, 200),
        [{%{"container_name" => "app"}, ["missing foo still matches"]}]
      )
    end

    assert_parquet(ctx, 4)
    assert_parquet_read(ctx)
  end

  @tag :label_parsing_batch
  test "complete Loki label sets retain original discovery results through protobuf and Parquet", ctx do
    fixture = File.read!("test/fixtures/logs/loki-upstream/label-parsing.json") |> Pulse.JSON.decode!()
    table = Enum.find(fixture["tables"], &(&1["name"] == "TestParseLabels"))
    assert length(table["rows"]) == 4

    for row <- table["rows"] do
      time = ctx.now - row["source_index"] * @second
      labels = Base.decode64!(row["query_bytes_base64"])
      push_protobuf(ctx, labels, time, "label-case-#{row["source_index"]}")
      expected = Map.new(row["expected_labels"], &{&1["name"], &1["value"]})
      params = [{"match[]", ~s/{job="foo"}/}, {"start", to_string(time)}, {"end", to_string(time)}]

      for method <- [&request/4, &request_form/4] do
        assert method.(ctx, "/series", params, 200)["data"] == [expected]
      end
    end

    # Source preservation differs from Loki's write-time empty-label removal;
    # prove the distinction survives actual Parquet storage, not just decoding.
    assert {:ok, records} = Storage.query(:logs, ctx.tenant, start_ts: ctx.now - 4 * @second, end_ts: ctx.now)
    assert length(records) == 4
    assert Enum.find(records, &(&1.body == "label-case-3")).resource == %{"job" => "foo", "bar" => ""}
    assert_parquet(ctx, 4)
    assert_parquet_read(ctx)
  end

  @tag :label_parsing_batch
  test "complete Loki unreserved-label table admits original queries with native result controls", ctx do
    fixture = File.read!("test/fixtures/logs/loki-upstream/label-parsing.json") |> Pulse.JSON.decode!()
    assert fixture["revision"] == "5aa4b9212d64d723f63b2770452054aa23df114d"
    table = Enum.find(fixture["tables"], &(&1["name"] == "TestParseUnreservedWordsAsLabelNames"))
    assert length(table["rows"]) == 4
    first = %{"variants" => "a", "of" => "a", "foo" => "other"}
    second = %{"variants" => "b", "of" => "a", "foo" => "bar"}
    push(ctx, "first", ctx.now, first)
    push(ctx, "second", ctx.now, second)

    for row <- table["rows"] do
      refute row["reject"]
      query = Base.decode64!(row["query_bytes_base64"])

      if row["source_index"] == 2 do
        # Upstream asserts admission only; these values are authored controls.
        expected = %{%{"variants" => "b", "of" => "a"} => [{0, "1"}]}
        assert_metric(ctx, query, 0, expected)
        assert_metric(ctx, query, {0, 0, "1"}, expected)
      else
        expected =
          case row["source_index"] do
            0 -> [{first, ["first"]}]
            1 -> [{first, ["first"]}, {second, ["second"]}]
            3 -> [{second, ["second"]}]
          end

        params = [
          {"query", query},
          {"time", to_string(ctx.now)},
          {"start", to_string(ctx.now)},
          {"end", to_string(ctx.now)}
        ]

        for path <- ["/query", "/query_range"], method <- [&request/4, &request_form/4] do
          params =
            if path == "/query_range",
              do: List.keyreplace(params, "end", 0, {"end", to_string(ctx.now + 1)}),
              else: params

          assert_streams(method.(ctx, path, params, 200), expected)
        end
      end
    end

    assert_parquet_read(ctx)
  end

  @tag :label_parsing_batch
  test "original oversized label input rejects before publication at the public body cap", ctx do
    fixture = File.read!("test/fixtures/logs/loki-upstream/label-parsing.json") |> Pulse.JSON.decode!()
    [control] = fixture["controls"]
    assert control["reject"]
    labels = :binary.copy(Base.decode64!(control["repeat_bytes_base64"]), control["repeat_count"])
    before = Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests, &1.objects})
    response = push_protobuf(ctx, labels, ctx.now, "oversized", 413)
    assert Pulse.JSON.decode!(response.body) == %{"error" => "payload_too_large"}
    assert Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests, &1.objects}) == before

    # A smaller malformed label set takes the existing per-entry drop path,
    # rather than making the size rejection look like exact parser-error parity.
    response = push_protobuf(ctx, "a", ctx.now, "malformed")
    assert Req.Response.get_header(response, "x-pulse-rejected-records") == ["1"]
    assert Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests, &1.objects}) == before
    push_protobuf(ctx, ~s/{job="foo"}/, ctx.now, "recovered")
    assert_streams(query(ctx, ~s/{job="foo"}/), [{%{"job" => "foo"}, ["recovered"]}])
    assert_parquet(ctx, 1)
    assert_parquet_read(ctx)
  end

  @tag :matcher_admission_batch
  test "complete Loki matcher-admission tables replay through selector and query endpoints", ctx do
    fixture = File.read!("test/fixtures/logs/loki-upstream/matcher-admission.json") |> Pulse.JSON.decode!()
    assert fixture["row_count"] == 30

    # Empty storage isolates admission from data-dependent pipeline results.
    for table <- fixture["tables"], row <- table["rows"] do
      {paths, parameter, policy_difference?} =
        case table["name"] do
          "TestParseMatchers" ->
            {["/series"], "match[]", false}

          "TestParseSampleExpr_equalityMatcher" ->
            {["/query", "/query_range"], "query", row["source_index"] in [1, 4, 6, 7, 8, 10, 15, 16, 17]}

          "TestParseLogSelectorExpr_equalityMatcher" ->
            {["/query", "/query_range"], "query", row["source_index"] in [1, 4, 6]}
        end

      # The component replay independently pins each original rejection and
      # explicitly accepted policy exception. No source expectation is rewritten.
      reject? = row["reject"] and not policy_difference?
      query = Base.decode64!(row["query_bytes_base64"])

      params = [
        {parameter, query},
        {"time", to_string(ctx.now)},
        {"start", to_string(ctx.now - @second)},
        {"end", to_string(ctx.now)},
        {"step", "1"}
      ]

      for path <- paths, method <- [&request/4, &request_form/4] do
        before = Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests})
        response = method.(ctx, path, params, if(reject?, do: 400, else: 200))

        if reject? do
          refute Map.has_key?(response, "data"), inspect({table["name"], row["source_index"], response})
          assert Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == before, inspect(query)
        else
          assert response["status"] == "success", inspect({table["name"], row["source_index"], response})
        end
      end
    end
  end

  @tag :matcher_admission_batch
  test "matcher controls preserve full-value regexes and negative-selector execution on native storage", ctx do
    fixture = File.read!("test/fixtures/logs/loki-upstream/matcher-admission.json") |> Pulse.JSON.decode!()
    tables = Map.new(fixture["tables"], &{&1["name"], &1["rows"]})

    # Authored values, not source result oracles. Prefix/suffix near-misses,
    # negative regexes and missing labels distinguish plausible wrong matchers.
    labels = [
      %{"app" => "foo", "cluster" => "prodbar", "bar" => "nope", "foo" => "bar"},
      %{"app" => "other", "cluster" => "prodbar", "bar" => "nope", "foo" => "baz"},
      %{"app" => "other", "cluster" => "prodbar", "bar" => "xboo", "foo" => "bar"},
      %{"app" => "foo", "cluster" => "prodbar-tail", "bar" => "nope", "foo" => "bar"},
      %{"app" => "foo", "cluster" => "bar", "bar" => "nope", "foo" => "bar"},
      %{"app" => "other", "cluster" => "prodbar", "bar" => "yboo-tail", "foo" => "qux"},
      %{"app" => "other", "cluster" => "other", "bar" => "nope"}
    ]

    for {stream, index} <- Enum.with_index(labels), do: push(ctx, "line-#{index}", ctx.now, stream)

    for {row, selected} <- Enum.zip(Enum.take(tables["TestParseMatchers"], 2), [[0], [1, 5]]) do
      params = [{"match[]", Base.decode64!(row["query_bytes_base64"])} | range(ctx)]
      expected = Enum.map(selected, &Enum.at(labels, &1)) |> Enum.sort()

      for method <- [&request/4, &request_form/4] do
        assert Enum.sort(method.(ctx, "/series", params, 200)["data"]) == expected
      end
    end

    negative_metric = Enum.at(tables["TestParseSampleExpr_equalityMatcher"], 1)
    assert negative_metric["reject"]
    expected = Map.new([1, 5, 6], &{Enum.at(labels, &1), [{0, "1"}]})
    assert_metric(ctx, Base.decode64!(negative_metric["query_bytes_base64"]), 0, expected)

    negative_log = Enum.at(tables["TestParseLogSelectorExpr_equalityMatcher"], 1)
    assert negative_log["reject"]
    params = [{"query", Base.decode64!(negative_log["query_bytes_base64"])}, {"time", to_string(ctx.now)} | range(ctx)]
    expected = Enum.map([1, 5, 6], &{Enum.at(labels, &1), ["line-#{&1}"]})

    for path <- ["/query", "/query_range"], method <- [&request/4, &request_form/4] do
      assert_streams(method.(ctx, path, params, 200), expected)
    end

    assert_parquet(ctx, 7)
    assert_parquet_read(ctx)
  end

  @tag :syntax_admission_batch
  test "complete Loki syntax table reaches HTTP admission with explicit policy differences", ctx do
    fixture = File.read!("test/fixtures/logs/loki-upstream/syntax-admission.json") |> Pulse.JSON.decode!()
    assert length(fixture["rows"]) == 206

    # Invalid UTF-8 makes Phoenix render a 400 and re-raise, then Bandit closes
    # the socket. Do not pool it between cases before that close is observed.
    ctx = Map.put(ctx, :extra_headers, [{"connection", "close"}])

    # Empty owned storage isolates admission from runtime data-dependent errors.
    # Neither these success statuses nor the symbolic source ASTs are value oracles.
    for row <- fixture["rows"], path <- ["/query", "/query_range"], method <- [&request/4, &request_form/4] do
      query = Base.decode64!(row["query_bytes_base64"])
      # The component replay pins these two policy differences independently;
      # see syntax-admission.md. Original fixture expectations remain unchanged.
      reject? = if row["source_index"] in [0, 42], do: not row["reject"], else: row["reject"]

      params = [
        {"query", query},
        {"time", to_string(ctx.now)},
        {"start", to_string(ctx.now - @second)},
        {"end", to_string(ctx.now)},
        {"step", "1"}
      ]

      before = Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests})
      response = method.(ctx, path, params, if(reject?, do: 400, else: 200))

      if reject? do
        refute Map.has_key?(response, "data"), inspect({row["source_index"], query, response})
        assert Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == before, inspect(query)
      else
        assert response["status"] == "success", inspect({row["source_index"], query, response})
      end
    end

    # Authored nonempty control: the same admitted count query reads Parquet,
    # counts two matching lines, and excludes a differently labelled source.
    push(ctx, "one", ctx.now - @second, %{"foo" => "bar"})
    push(ctx, "two", ctx.now, %{"foo" => "bar"})
    push(ctx, "noise", ctx.now, %{"foo" => "other"})
    assert_metric(ctx, ~s/count_over_time({foo="bar"}[1m])/, 0, %{%{"foo" => "bar"} => [{0, "2"}]})
  end

  @tag :reserved_label_comparisons_batch
  test "Loki reserved-label comparison matrix preserves every original admission oracle over HTTP", ctx do
    fixture = File.read!("test/fixtures/logs/loki-upstream/reserved-label-comparisons.json") |> Pulse.JSON.decode!()
    rows = fixture["rows"]
    assert length(rows) == 68
    assert Enum.count(rows, & &1["reject"]) == 56
    assert fixture["revision"] == "5aa4b9212d64d723f63b2770452054aa23df114d"

    # Upstream supplies parser admission oracles, not log-value oracles. Nonempty
    # storage separately proves accepted requests reach native Parquet/S3 reads.
    push(ctx, "latency=2s size=1000000 bytes=2", ctx.now, %{"app" => "foo"})

    for row <- rows, path <- ["/query", "/query_range"], method <- [&request/4, &request_form/4] do
      params = [
        {"query", row["query"]},
        {"time", to_string(ctx.now + @second)},
        {"start", to_string(ctx.now - @minute)},
        {"end", to_string(ctx.now + @second)},
        {"step", "1"}
      ]

      before = Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests})
      status = if row["reject"], do: 400, else: 200
      response = method.(ctx, path, params, status)

      if row["reject"] do
        assert response["error"] == "parse_error", inspect({row["query"], response})

        for fragment <- Map.get(row, "error_contains", []) do
          assert response["message"] =~ fragment, row["query"]
        end

        assert Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == before, row["query"]
      else
        assert response["status"] == "success", row["query"]
      end
    end

    assert_parquet(ctx, 1)
    assert_parquet_read(ctx)
  end

  @tag :decolorize_batch
  test "Loki TestDecolorizer: both original table rows replay through HTTP and Parquet", ctx do
    rows = File.read!("test/fixtures/logs/loki-upstream/decolorize.json") |> Pulse.JSON.decode!()

    push_streams(
      ctx,
      for row <- rows["upstream"] do
        %{"stream" => %{"job" => "decolorize", "case" => row["name"]}, "values" => [[to_string(ctx.now), row["line"]]]}
      end
    )

    expected = for row <- rows["upstream"], do: {%{"job" => "decolorize", "case" => row["name"]}, [row["expected"]]}
    params = [{"query", ~s({job="decolorize"} | decolorize)} | range(ctx)]
    assert_streams(request(ctx, "/query_range", params), expected)
    assert_streams(request_form(ctx, "/query_range", params), expected)
    assert_parquet(ctx, 1)
    assert_parquet_read(ctx)
  end

  @tag :decolorize_batch
  test "Pulse controls: decolorize preserves unmatched text and matches the pinned escape profile", ctx do
    rows = File.read!("test/fixtures/logs/loki-upstream/decolorize.json") |> Pulse.JSON.decode!()
    controls = rows["controls"]

    push_streams(
      ctx,
      for row <- controls do
        %{"stream" => %{"job" => "decolorize", "case" => row["name"]}, "values" => [[to_string(ctx.now), row["line"]]]}
      end
    )

    expected = for row <- controls, do: {%{"job" => "decolorize", "case" => row["name"]}, [row["expected"]]}
    params = [{"query", ~s({job="decolorize"} | decolorize)}, {"limit", "1000"} | range(ctx)]
    assert_streams(request(ctx, "/query_range", params), expected)
    assert_streams(request_form(ctx, "/query_range", params), expected)

    # Formatting sees the rewritten line; filters do not silently discard
    # an unmatched marker, even when a later valid sequence can be removed.
    row = Enum.find(controls, &(&1["name"] == "boundary-27"))
    expression = ~s({job="decolorize",case="boundary-27"} | decolorize | line_format "[{{__line__}}]")
    assert lines(query(ctx, expression)) == ["[" <> row["expected"] <> "]"]

    expression = ~s'sum(count_over_time({job="decolorize"} | decolorize |= "☃" [1m]))'
    count = Enum.count(controls, &String.contains?(&1["expected"], "☃"))
    assert values(instant(ctx, expression)) == %{%{} => to_string(count)}
    assert_parquet(ctx, 1)
    assert_parquet_read(ctx)
  end

  @tag :regex_hex_batch
  test "Pulse controls: braced hex repetition matches Go through HTTP and Parquet", ctx do
    inputs = ["a", "aa", "aaa", "aab", "aabb", "éé", "Éé", "Ā"]

    push_streams(
      ctx,
      for(
        input <- inputs,
        do: %{"stream" => %{"job" => "regex-hex", "x" => input}, "values" => [[to_string(ctx.now), input]]}
      )
    )

    controls =
      "test/fixtures/regex/go-controls.json"
      |> File.read!()
      |> Pulse.JSON.decode!()
      |> Enum.filter(
        &(&1["value"] in inputs and
            &1["pattern"] in [~S"^\x{61}+$", ~S"^\x{000061}{2}$", ~S"(?i)^\x{c9}{2}$", ~S"^\x{100}{0,1}$"])
      )
      |> Enum.group_by(& &1["pattern"])

    for {pattern, rows} <- controls, matches? <- [true, false] do
      quoted = Pulse.JSON.encode!(pattern)
      operator = if matches?, do: "=~", else: "!~"
      line_operator = if matches?, do: "|~", else: "!~"

      expected =
        for row <- rows, row["match"] == matches?, do: {%{"job" => "regex-hex", "x" => row["value"]}, [row["value"]]}

      for expression <- [
            ~s({job="regex-hex",x#{operator}#{quoted}}),
            ~s({job="regex-hex"} #{line_operator} #{quoted}),
            ~s({job="regex-hex"} | line_format "{{__line__}}" #{line_operator} #{quoted}),
            ~s({job="regex-hex"} | x#{operator}#{quoted})
          ] do
        params = [{"query", expression} | range(ctx)]
        response = request(ctx, "/query_range", params)
        assert_streams(response, expected)
        assert request_form(ctx, "/query_range", params) == response
      end

      expression = ~s'sum(count_over_time({job="regex-hex"} #{line_operator} #{quoted} [1m]))'
      expected_count = if expected == [], do: %{}, else: %{%{} => to_string(length(expected))}
      assert values(instant(ctx, expression)) == expected_count
    end

    assert_parquet(ctx, 1)
    assert_parquet_read(ctx)
  end

  @tag :regex_literals_batch
  test "Go quoted and octal regex literals retain line and whole-label semantics", ctx do
    inputs = [
      "a",
      "aa",
      "ab",
      "abb",
      "a.b",
      "axb",
      ~S"\d",
      "\\",
      "\\\\",
      "+|*?{[",
      "+",
      "++",
      "ĀĀ",
      "\na",
      "prefixabsuffix"
    ]

    push_streams(
      ctx,
      for input <- inputs do
        %{"stream" => %{"job" => "regex-literals", "x" => input}, "values" => [[to_string(ctx.now), input]]}
      end
    )

    controls =
      "test/fixtures/regex/go-controls.json"
      |> File.read!()
      |> Pulse.JSON.decode!()
      |> Enum.filter(&(Map.has_key?(&1, "label_match") and &1["value"] in inputs))
      |> Enum.group_by(& &1["pattern"])

    assert map_size(controls) == 30

    for {pattern, rows} <- controls, matches? <- [true, false] do
      quoted = Pulse.JSON.encode!(pattern)
      operator = if matches?, do: "=~", else: "!~"
      line_operator = if matches?, do: "|~", else: "!~"

      for {expression, key} <- [
            {~s({job="regex-literals",x#{operator}#{quoted}}), "label_match"},
            {~s({job="regex-literals"} | x#{operator}#{quoted}), "label_match"},
            {~s({job="regex-literals"} #{line_operator} #{quoted}), "match"},
            {~s({job="regex-literals"} | line_format "{{__line__}}" #{line_operator} #{quoted}), "match"}
          ] do
        expected =
          for row <- rows, row[key] == matches?, do: {%{"job" => "regex-literals", "x" => row["value"]}, [row["value"]]}

        params = [{"query", expression} | range(ctx)]
        response = request(ctx, "/query_range", params)
        assert_streams(response, expected)
        assert request_form(ctx, "/query_range", params) == response
      end

      expected_count = Enum.count(rows, &(&1["match"] == matches?))
      expected = if expected_count == 0, do: %{}, else: %{%{} => to_string(expected_count)}

      assert values(instant(ctx, ~s'sum(count_over_time({job="regex-literals"} #{line_operator} #{quoted} [1m]))')) ==
               expected
    end

    expression = ~S'{job="regex-literals"} | regexp "(?P<got>\\141+)" | got!=""'

    assert_streams(
      request(ctx, "/query_range", [{"query", expression} | range(ctx)]),
      for input <- inputs, String.contains?(input, "a") do
        got = if input == "aa", do: "aa", else: "a"
        {%{"job" => "regex-literals", "x" => input, "got" => got}, [input]}
      end
    )

    for pattern <- [~S"\Qa.b", ~S"\Qab\E+", ~S"\141+"] do
      matches = for row <- controls[pattern], row["label_match"], do: row["value"]

      expected =
        Map.new(inputs, fn input ->
          labels = %{"job" => "regex-literals", "x" => input}
          labels = if input in matches, do: Map.put(labels, "out", "hit"), else: labels
          {labels, "1"}
        end)

      query =
        ~s'label_replace(count_over_time({job="regex-literals"} [1m]), "out", "hit", "x", #{Pulse.JSON.encode!(pattern)})'

      params = [query: query, time: to_string(ctx.now + @second)]
      response = request(ctx, "/query", params)
      assert values(response) == expected
      assert request_form(ctx, "/query", params) == response
    end

    assert_parquet(ctx, 1)
    assert_parquet_read(ctx)
  end

  # Replays the Go regex corpus; under CI concurrency its native calls queue
  # behind other tests and can exceed ExUnit's 60 s default.
  @tag :regex_admission_batch
  @tag timeout: 300_000
  test "Go repetition class and raw-header admission agree through log Parquet", ctx do
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

    push_streams(
      ctx,
      for input <- inputs do
        %{"stream" => %{"job" => "regex-admission", "x" => input}, "values" => [[to_string(ctx.now), input]]}
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

    for row <- cases, matches? <- [true, false] do
      pattern = Pulse.JSON.encode!(row["pattern"])
      operator = if matches?, do: "=~", else: "!~"
      line_operator = if matches?, do: "|~", else: "!~"

      for {query, key} <- [
            {~s({job="regex-admission",x#{operator}#{pattern}}), "label_match"},
            {~s({job="regex-admission"} #{line_operator} #{pattern}), "match"}
          ] do
        before_reads = Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests})
        params = [{"query", query} | range(ctx)]
        status = if row["valid"], do: 200, else: 400
        response = request(ctx, "/query_range", params, status)
        assert request_form(ctx, "/query_range", params, status) == response

        if row["valid"] do
          expected =
            for value <- row["values"],
                input = String.duplicate(value["text"], value["repeat"]),
                input in inputs and value[key] == matches?,
                do: {%{"job" => "regex-admission", "x" => input}, [input]}

          assert_streams(response, expected)
        else
          assert Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == before_reads
        end
      end
    end

    assert_parquet(ctx, 1)
    assert_parquet_read(ctx)
  end

  @tag :regex_properties_batch
  test "Unicode properties and scalar complements match upstream in log selectors and pipelines", ctx do
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

    push_streams(
      ctx,
      for input <- inputs do
        %{"stream" => %{"job" => "regex-properties", "x" => input}, "values" => [[to_string(ctx.now), input]]}
      end
    )

    for path <- ["unicode-property-controls.json", "scalar-complement-controls.json"],
        row <- ("test/fixtures/regex/" <> path) |> File.read!() |> Pulse.JSON.decode!() |> Map.fetch!("cases"),
        Map.get(row, "http", true),
        matches? <- [true, false] do
      pattern = Pulse.JSON.encode!(row["pattern"])
      operator = if matches?, do: "=~", else: "!~"
      line_operator = if matches?, do: "|~", else: "!~"

      for {query, key} <- [
            {~s({job="regex-properties",x#{operator}#{pattern}}), "label_match"},
            {~s({job="regex-properties"} #{line_operator} #{pattern}), "match"}
          ] do
        before_reads = Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests})
        params = [{"query", query} | range(ctx)]
        status = if row["valid"], do: 200, else: 400
        response = request(ctx, "/query_range", params, status)
        assert request_form(ctx, "/query_range", params, status) == response

        if row["valid"] do
          expected =
            for value <- row["values"],
                value["text"] in inputs,
                value[key] == matches?,
                do: {%{"job" => "regex-properties", "x" => value["text"]}, [value["text"]]}

          assert_streams(response, expected)
        else
          assert Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == before_reads
        end
      end
    end

    assert_parquet(ctx, 1)
    assert_parquet_read(ctx)
  end

  @tag :regex_selector_names_batch
  test "numeric parser labels and repeated replacement aliases retain their distinct contracts", ctx do
    inputs = ["x", "y", "xy", "hi", "bye", "aba", "xx"]
    base = %{"job" => "regex-names", "out" => "existing", "_1" => "stream"}

    push_streams(
      ctx,
      for input <- inputs do
        %{"stream" => Map.put(base, "probe", input), "values" => [[to_string(ctx.now), input]]}
      end
    )

    fixture = "test/fixtures/regex/selector-name-controls.json" |> File.read!() |> Pulse.JSON.decode!()

    for row <- fixture["cases"] do
      pattern = Pulse.JSON.encode!(row["pattern"])
      query = ~s/{job="regex-names"} | regexp / <> pattern
      before_reads = Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests})

      if row["parser_valid"] do
        expected =
          for value <- row["values"], value["text"] in inputs do
            labels = Map.put(base, "probe", value["text"])

            labels =
              Enum.reduce(value["named_captures"] || %{}, labels, fn {name, capture}, labels ->
                Map.put(labels, if(Map.has_key?(base, name), do: name <> "_extracted", else: name), capture)
              end)

            {labels, [value["text"]]}
          end

        params = [{"query", query} | range(ctx)]
        response = request(ctx, "/query_range", params)
        assert request_form(ctx, "/query_range", params) == response
        assert_streams(response, expected)

        assert values(instant(ctx, "count_over_time(" <> query <> " [1m])")) ==
                 Map.new(expected, fn {labels, _} -> {labels, "1"} end)
      else
        params = [{"query", query} | range(ctx)]
        assert request(ctx, "/query_range", params, 400) == request_form(ctx, "/query_range", params, 400)
        assert request(ctx, "/query", params, 400) == request_form(ctx, "/query", params, 400)
        assert Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == before_reads
      end

      if row["valid"] do
        query =
          ~s/label_replace(count_over_time({job="regex-names"}[1m]), "out", #{Pulse.JSON.encode!(fixture["replacement"])}, "probe", #{pattern})/

        expected =
          for value <- row["values"], value["text"] in inputs, into: %{} do
            labels = base |> Map.put("probe", value["text"]) |> Map.put("out", value["expanded"] || "existing")
            {labels, "1"}
          end

        assert values(instant(ctx, query)) == expected, row["pattern"]
      end
    end

    assert_parquet(ctx, 1)
    assert_parquet_read(ctx)
  end

  @tag :regex_parser_flags_batch
  test "regexp parser flags retain Go capture values without PCRE admission", ctx do
    inputs = ["x", "xx", "X", "xX", "XX", "xy", "xY", "k", "K", "[x", "\n"]

    push_streams(
      ctx,
      for input <- inputs do
        %{
          "stream" => %{"job" => "regex-parser-flags", "probe" => input},
          "values" => [[to_string(ctx.now), input]]
        }
      end
    )

    cases =
      ["flag-controls.json", "unicode-controls.json", "nested-repetition-controls.json"]
      |> Enum.flat_map(fn file ->
        ("test/fixtures/regex/" <> file) |> File.read!() |> Pulse.JSON.decode!() |> Map.fetch!("cases")
      end)
      |> Enum.filter(&(&1["valid"] and &1["capture_names"] != []))

    assert length(cases) == 24

    for row <- cases do
      stage = "regexp " <> Pulse.JSON.encode!(row["pattern"])
      query = ~s/{job="regex-parser-flags"} | / <> stage

      values =
        row["values"]
        |> Map.new(fn value -> {String.duplicate(value["text"], value["repeat"]), value["named_captures"]} end)

      expected =
        for input <- inputs do
          labels = Map.merge(%{"job" => "regex-parser-flags", "probe" => input}, Map.fetch!(values, input) || %{})
          {labels, [input]}
        end

      params = [{"query", query} | range(ctx)]
      result = request(ctx, "/query_range", params)
      assert request_form(ctx, "/query_range", params) == result
      assert_streams(result, expected)

      name = hd(row["capture_names"])
      count = Enum.count(inputs, fn input -> get_in(values, [input, name]) not in [nil, ""] end)
      metric = ~s/sum(count_over_time(#{query} | #{name}!="" [1m]))/
      points = if count == 0, do: %{}, else: %{%{} => [{1, to_string(count)}]}
      assert_metric(ctx, metric, 1, points)
    end

    assert_parquet(ctx, 1)
    assert_parquet_read(ctx)
  end

  @tag :regex_erased_capture_batch
  test "erased regexp captures retain empty labels and first-extraction ownership", ctx do
    inputs = ["a", "c", "ac", "xc", "y", "é🙂", "🙂", "(?P<fake>x)c", "(c", "a(?P<fake>x){0}c"]

    push_streams(
      ctx,
      for input <- inputs do
        %{
          "stream" => %{"job" => "regex-erased", "probe" => input},
          "values" => [[to_string(ctx.now), input]]
        }
      end
    )

    cases =
      "test/fixtures/regex/erased-capture-controls.json"
      |> File.read!()
      |> Pulse.JSON.decode!()
      |> Map.fetch!("cases")
      |> Enum.filter(&(&1["capture_names"] != []))

    assert length(cases) == 23

    for row <- cases do
      name = hd(row["capture_names"])
      query = ~s/{job="regex-erased"} | regexp / <> Pulse.JSON.encode!(row["pattern"])

      values =
        Map.new(row["values"], fn value ->
          {String.duplicate(value["text"], value["repeat"]), value["named_captures"] || %{}}
        end)

      # A later parser may fill a missing label, but not overwrite an empty
      # capture that the earlier expression declared and matched.
      for {expression, overwrite?} <- [
            {query, false},
            {query <> " | regexp " <> Pulse.JSON.encode!("(?P<#{name}>.+)"), true}
          ] do
        expected =
          for input <- inputs do
            captures = Map.fetch!(values, input)
            captures = if overwrite?, do: Map.put_new(captures, name, input), else: captures
            {Map.merge(%{"job" => "regex-erased", "probe" => input}, captures), [input]}
          end

        params = [{"query", expression} | range(ctx)]
        result = request(ctx, "/query_range", params)
        assert request_form(ctx, "/query_range", params) == result
        assert_streams(result, expected)

        if overwrite? do
          for empty? <- [true, false] do
            count = Enum.count(expected, fn {labels, _} -> labels[name] == "" == empty? end)
            filter = name <> if(empty?, do: "=", else: "!=") <> ~s("")
            metric = ~s/sum(count_over_time(#{expression} | #{filter} [1m]))/
            points = if count == 0, do: %{}, else: %{%{} => [{1, to_string(count)}]}
            assert_metric(ctx, metric, 1, points)
          end
        end
      end
    end

    assert_parquet(ctx, 1)
    assert_parquet_read(ctx)
  end

  @tag :template_json_batch
  test "template JSON values retain typed objects arrays and numbers through HTTP", ctx do
    # Complete Sprig v3.3.0 defaults_test.go:127-141 TestFromJson oracles.
    source_rows = [
      {"{{.Input | fromJson}}", "map[foo:55]"},
      {"{{(.Input | fromJson).foo}}", "55"}
    ]

    controls = [
      {~S'{{fromJson `{"z":null,"a":[1,true,"x"],"o":{"b":2}}`}}', "map[a:[1 true x] o:map[b:2] z:<nil>]"},
      {~S'{{(fromJson `{"nested":{"name":"é"}}`).nested.name}}', "é"},
      {~S'{{(fromJson `{}`).missing}}', "<no value>"},
      {~S'{{index (fromJson `{"http.method":"POST"}`) "http.method"}}', "POST"},
      {~S'{{index (fromJson `{"a":[{"name":"x"}]}`) "a" 0 "name"}}', "x"},
      {~S'{{len (fromJson `[1,null,true]`)}}/{{len (fromJson `{"a":1}`)}}', "3/1"},
      {~S'{{len (fromJson `"é"`)}}/{{index (fromJson `"é"`) 0}}', "2/195"},
      {~S'{{range $i,$v := (fromJson `["z",null,{"n":2}]`)}}{{$i}}={{$v}};{{end}}', "0=z;1=<no value>;2=map[n:2];"},
      {~S'{{range $k,$v := (fromJson `{"z":2,"a":1}`)}}{{$k}}={{$v}};{{end}}', "a=1;z=2;"},
      {~S'{{with (fromJson `{"name":"x"}`)}}{{.name}}/{{$.Input}}{{end}}', ~S'x/{"foo": 55}'},
      {~S'{{if (fromJson `[]`)}}bad{{else}}empty{{end}}/{{if (fromJson `{}`)}}bad{{else}}empty{{end}}', "empty/empty"},
      {~S'{{default "fallback" (fromJson `null`)}}/{{default "fallback" (fromJson `false`)}}', "fallback/fallback"},
      {~S'{{default "fallback" (fromJson `0`)}}/{{default "fallback" (fromJson `""`)}}', "fallback/fallback"},
      {~S'{{eq (fromJson `2`) 2.0}}/{{add (fromJson `2.9`) 1}}', "true/3"},
      {~S'{{fromJson `9007199254740993`}}/{{fromJson `-0`}}', "9.007199254740992e+15/-0"},
      {~S'{{fromJson `-0.0`}}/{{fromJson `-0e100`}}/{{fromJson `1e-9999`}}', "-0/-0/0"},
      {~S'{{fromJson `{"a":1,"a":2}`}}/{{fromJson `{"a":{"x":1},"a":{"y":2}}`}}', "map[a:2]/map[a:map[y:2]]"},
      {~S'{{fromJson `1e9999`}}/{{fromJson `[1e9999,2]`}}/{{fromJson `{"a":1e9999,"b":3}`}}', "0/[0 2]/map[a:0 b:3]"},
      {~S'{{fromJson `{"a":1} garbage`}}/{{fromJson `{"a":1`}}/{{fromJson `01`}}', "<no value>/<no value>/<no value>"},
      {~S'{{fromJson `NaN`}}/{{fromJson ``}}/{{fromJson `{"a":1,}`}}', "<no value>/<no value>/<no value>"},
      {~S'{{fromJson `"\ud800"`}}/{{fromJson `"\udc00"`}}/{{fromJson `"\ud83d\ude00"`}}', "�/�/😀"},
      {~S'{{fromJson `"\ud800x\ud800\udc00"`}}/{{fromJson `"\\ud800"`}}', ~S'�x𐀀/\ud800'},
      {~S'{{eq (fromJson `{}`) nil}}/{{eq (fromJson `[]`) nil}}/{{eq (fromJson `null`) nil}}', "false/false/true"},
      {~S'{{index (fromJson `{}`) "missing"}}/{{print (index (fromJson `{}`) "missing")}}', "<no value>/<nil>"},
      {~S'{{(index (fromJson `{}`) "missing").more}}/{{(fromJson `null`).more}}', "<no value>/<no value>"},
      {~S'{{int (fromJson `[1]`)}}/{{float64 (fromJson `{"a":1}`)}}', "0/0"},
      {~S'{{$x := fromJson `{"items":[1,2,3]}`}}{{range $x.items}}{{if eq . 2.0}}{{continue}}{{end}}{{.}}{{end}}',
       "13"},
      {~S'{{range (fromJson `[]`)}}bad{{else}}empty{{end}}/{{range (fromJson `null`)}}bad{{else}}nil{{end}}',
       "empty/nil"},
      {~S'{{if false}}{{fromJson 1}}{{else}}safe{{end}}', "safe"}
    ]

    labels = %{"job" => "json-values", "Input" => ~S'{"foo": 55}'}
    push(ctx, "original", ctx.now, labels)

    for {template, expected} <- source_rows ++ controls, stage <- [:line, :label] do
      format = if stage == :line, do: "line_format ", else: "label_format out="
      expression = ~s/{job="json-values"} | / <> format <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      result = if stage == :line, do: {labels, [expected]}, else: {Map.put(labels, "out", expected), ["original"]}
      assert_streams(response, [result])
      assert request_form(ctx, "/query_range", params) == response
    end

    expression = ~S'{job="json-values"} | line_format "{{(.Input | fromJson).foo}}"'
    assert_metric(ctx, "sum(bytes_over_time(#{expression} [1m]))", 1, %{%{} => [{1, "2"}]})
    assert_parquet_read(ctx)
  end

  @tag :template_json_batch
  test "template JSON type errors preserve inputs instead of treating decoded values as labels", ctx do
    labels = %{"job" => "json-errors", "out" => "unchanged"}
    push(ctx, "original", ctx.now, labels)

    for template <- [
          ~S'{{fromJson 1}}',
          ~S'{{fromJson}}',
          ~S'{{fromJson "{}" "{}"}}',
          ~S'{{eq (fromJson `2`) 2}}',
          ~S'{{eq (fromJson `[1]`) (fromJson `[1]`)}}',
          ~S'{{eq (fromJson `{}`) (fromJson `{}`)}}',
          ~S'{{index (fromJson `[1]`) 1}}',
          ~S'{{index (fromJson `[1]`) -1}}',
          ~S'{{index (fromJson `[1]`) 0.0}}',
          ~S'{{index (fromJson `{}`) 0}}',
          ~S'{{index (fromJson `null`) "x"}}',
          ~S'{{(fromJson `[1]`).name}}',
          ~S'{{(fromJson `{}`).missing.more}}',
          ~S'{{(fromJson `{"a":null}`).a.name}}',
          ~S'{{(fromJson `{}`).missing (div 1 0)}}',
          ~S'{{(fromJson `{"a":1}`).a.name}}',
          ~S'{{range (fromJson `2`)}}bad{{end}}',
          ~S'{{repeat (fromJson `2`) "x"}}',
          ~S'{{upper (fromJson `true`)}}'
        ],
        stage <- ["line_format ", "label_format out="] do
      expression = ~s/{job="json-errors"} | / <> stage <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      assert [%{"stream" => stream, "values" => [[_, "original"]]}] = response["data"]["result"]
      assert stream["out"] == "unchanged"
      assert stream["__error__"] == "TemplateFormatErr"
      assert request_form(ctx, "/query_range", params) == response
      assert_metric(ctx, ~s/sum(bytes_over_time(#{expression} | __error__!="" [1m]))/, 1, %{%{} => [{1, "8"}]})
    end

    assert_parquet_read(ctx)
  end

  @tag :template_array_slice_batch
  test "Go array slices preserve decoded backing values and explicit capacity through HTTP", ctx do
    # Original Go 1.27.3 exec_test.go:544-546 success oracles. The Go []int
    # field becomes a decoded JSON []interface{} with the same values.
    source_rows = [
      {"{{slice .SI}}", "[3 4 5]"},
      {"{{slice .SI 1}}", "[4 5]"},
      {"{{slice .SI 1 2}}", "[4]"}
    ]

    controls = [
      {"{{slice .SI 0 3 3}}", "[3 4 5]"},
      {"{{slice .SI 3}}", "[]"},
      {"{{slice .SI 2 2}}", "[]"},
      {"{{slice (slice .SI 0 1) 1 3}}", "[4 5]"},
      {"{{slice (slice .SI 1 1) 0 2}}", "[4 5]"},
      {"{{slice (slice .SI 1 2 3) 0 2}}", "[4 5]"},
      {"{{slice (slice .SI 1 2 2) 1 1}}", "[]"},
      {"{{len (slice .SI 1 1)}}/{{if (slice .SI 1 1)}}bad{{else}}empty{{end}}", "0/empty"},
      {"{{index (slice .SI 1 3) 0}}/{{index (slice .SI 1 3) 1}}", "4/5"},
      {"{{range $i,$v := (slice .SI 1 3)}}{{$i}}:{{$v}};{{end}}", "0:4;1:5;"},
      {"{{range (slice .SI 1 1)}}bad{{else}}empty{{end}}", "empty"},
      {~S'{{slice .SI (index "\x01" 0) (index "\x03" 0)}}', "[4 5]"},
      {"{{.SI | slice}}", "[3 4 5]"},
      {"{{print (slice .SI 1 3)}}/{{int (slice .SI 1)}}/{{float64 (slice .SI 1)}}", "[4 5]/0/0"},
      {~S'{{slice (fromJson `[null,{"x":1},[2,3]]`) 1}}', "[map[x:1] [2 3]]"},
      {~S'{{index (slice (fromJson `[{"x":[3,4,5]}]`) 0 1) 0 "x" 2}}', "5"},
      {~S'{{slice (fromJson `[]`) 0 0 0}}', "[]"},
      {~S'{{if false}}{{slice .SI -1}}{{else}}safe{{end}}', "safe"}
    ]

    labels = %{"job" => "array-slice", "payload" => ~S'{"SI":[3,4,5]}'}
    push(ctx, "original", ctx.now, labels)

    for {template, expected} <- source_rows ++ controls, stage <- [:line, :label] do
      template = "{{with (fromJson .payload)}}" <> template <> "{{end}}"
      format = if stage == :line, do: "line_format ", else: "label_format out="
      expression = ~s/{job="array-slice"} | / <> format <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      result = if stage == :line, do: {labels, [expected]}, else: {Map.put(labels, "out", expected), ["original"]}
      assert_streams(response, [result])
      assert request_form(ctx, "/query_range", params) == response
    end

    expression = ~S'{job="array-slice"} | line_format "{{slice (fromJson `[3,4,5]`) 1 3}}"'
    assert_metric(ctx, "sum(bytes_over_time(#{expression} [1m]))", 1, %{%{} => [{1, "5"}]})
    assert_parquet_read(ctx)
  end

  @tag :template_array_slice_batch
  test "array slice bounds and typed indices retain formatting error policies", ctx do
    # Complete Go 1.27.3 exec_test.go:547-553 failure oracles, same JSON fixture.
    source_rows = [
      "{{slice .SI -1}}",
      "{{slice .SI 1 -2}}",
      "{{slice .SI 1 2 -1}}",
      "{{slice .SI 2 1}}",
      "{{slice .SI 2 2 1}}",
      "{{slice .SI 4 5}}",
      "{{slice .SI 2 2 5}}"
    ]

    controls = [
      "{{slice (slice .SI 1 2 2) 0 2}}",
      "{{slice (slice .SI 1 1 1) 0 1}}",
      "{{index (slice .SI 1 1) 0}}",
      "{{index (slice .SI 1 2) 1}}",
      "{{slice .SI 0 1 2 3}}",
      "{{slice .SI 1.0}}",
      "{{slice .SI (fromJson `1`)}}",
      "{{slice .SI `1`}}",
      "{{slice .SI true}}",
      "{{slice .SI nil}}",
      "{{slice .SI 0i}}",
      "{{slice (fromJson `{}`) 0}}",
      "{{slice (fromJson `null`)}}"
    ]

    # Deliberate profile boundary: do not expose Go's allocator-dependent
    # fourth spare cell after decoding three elements.
    profile_rejections = ["{{slice .SI 0 4}}", "{{slice .SI 0 0 4}}"]

    labels = %{"job" => "array-slice-errors", "out" => "unchanged", "payload" => ~S'{"SI":[3,4,5]}'}
    push(ctx, "original", ctx.now, labels)

    for template <- source_rows ++ controls ++ profile_rejections, stage <- ["line_format ", "label_format out="] do
      template = "{{with (fromJson .payload)}}" <> template <> "{{end}}"
      expression = ~s/{job="array-slice-errors"} | / <> stage <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      assert [%{"stream" => stream, "values" => [[_, "original"]]}] = response["data"]["result"]
      assert stream["out"] == "unchanged"
      assert stream["__error__"] == "TemplateFormatErr"
      assert request_form(ctx, "/query_range", params) == response
      params = [query: "bytes_over_time(#{expression} [1m])", time: to_string(ctx.now + @second)]
      assert request(ctx, "/query", params, 400)["message"] =~ "pipeline_error"
      assert_metric(ctx, ~s/sum(bytes_over_time(#{expression} | __error__!="" [1m]))/, 1, %{%{} => [{1, "8"}]})
    end

    assert_parquet_read(ctx)
  end

  @tag :template_variables_batch
  @tag :template_nested_bindings_batch
  test "Go template declarations and assignments preserve lexical scopes through HTTP", ctx do
    # Complete root-independent Go 1.27.3 exec_test.go:336-343 assignment rows.
    source_rows = [
      {"{{$x := 2}}{{$x = 3}}{{$x}}", "3"},
      {"{{$x := 2}}{{if true}}{{$x = 3}}{{end}}{{$x}}", "3"},
      {"{{$x := 1}}{{if true}}{{$x := 2}}{{if true}}{{$x = 3}}{{end}}{{end}}{{$x}}", "1"}
    ]

    controls = [
      {~s'{{$x:=.text}}{{$x}}', "hello"},
      {~s'{{$x := .text | upper}}{{$x}}', "HELLO"},
      {~s'{{$x := .text}}{{$x := upper $x}}{{$x}}', "HELLO"},
      {~s'{{$x := "outer"}}{{if true}}{{$x := "inner"}}{{$x}}{{end}}/{{$x}}', "inner/outer"},
      {~s'{{$x := "outer"}}{{if false}}{{$x = "inner"}}{{else}}{{$x = "else"}}{{end}}{{$x}}', "else"},
      {~s'{{$x := "outer"}}{{if $x := .missing}}bad{{else}}<{{$x}}>{{end}}/{{$x}}', "<>/outer"},
      {~s'{{$x := "outer"}}{{if $x = .missing}}bad{{else}}empty{{end}}/{{$x}}', "empty/"},
      {~s'{{with $x := .text}}{{$x}}/{{.}}/{{$.text}}{{end}}', "hello/hello/hello"},
      {~s'{{$x := "outer"}}{{with $x := .missing}}bad{{else}}<{{$x}}>/{{.text}}{{end}}/{{$x}}', "<>/hello/outer"},
      {~s'{{$x := "outer"}}{{with .text}}{{$x = upper .}}{{end}}{{$x}}', "HELLO"},
      {~s'{{if $x := false}}bad{{else if $y := .text}}{{$x}}/{{$y}}{{end}}', "false/hello"},
      {~s'{{with $x := .missing}}bad{{else with $y := .text}}<{{$x}}>/{{$y}}/{{.}}{{end}}', "<>/hello/hello"},
      {~s'{{$ := .text}}{{.text}}/{{$}}', "hello/hello"},
      {~s'{{with .text}}{{$ := "inner"}}{{$}}{{end}}/{{$.text}}', "inner/hello"},
      {~s'{{$root := $}}{{with .text}}{{$root.text}}/{{index $root "text"}}{{end}}', "hello/hello"},
      {~s'{{$x := true}}{{if $x}}yes{{end}}/{{$x}}', "yes/true"},
      {~s'{{$x := (and nil true)}}{{default "fallback" $x}}/{{$x}}', "fallback/<no value>"},
      {~s'{{$x := 2.0}}{{addf $x 0.5}}', "2.5"},
      {~s'{{$x := 2i}}{{eq $x 2i}}/{{$x}}', "true/(0+2i)"},
      {~s'{{$x := .text}}{{upper $x}}/{{$x | upper}}', "HELLO/HELLO"},
      {~s'{{$é := .text}}{{$é}}/{{$1 := 7}}{{$1}}', "hello/7"},
      {~s'{{$x := 1 -}} \n {{- $x = 2 -}} \n {{$x}}', "2"},
      {~s'{{if true}}ok{{else}}{{$x = 1}}{{$x}}{{end}}', "ok"},
      {~s'{{if true}}{{$x := 1}}{{$x}}{{else}}{{$x}}{{end}}', "1"},
      {~s'{{$x := "old"}}{{if true}}{{$x := $x}}{{$x = "local"}}{{end}}{{$x}}', "old"},
      {~s'{{$x := .text}}{{$x = ""}}{{$x}}{{.text}}', "hello"},
      {~s'{{upper ($x := .text)}}/{{$x}}', "HELLO/hello"},
      {~s'{{($x := .text)}}/{{$x}}', "hello/hello"},
      {~s'{{$x := "old"}}{{print ($x = "first") ($x = "second")}}/{{$x}}', "firstsecond/second"},
      {~s'{{print ($x := .text) $x}}', "hellohello"},
      {~s'{{print ($x := "first") ($x := upper $x) $x}}', "firstFIRSTFIRST"},
      {~s'{{$x := "outer"}}{{if true}}{{upper ($x := .text)}}/{{$x}}{{end}}/{{$x}}', "HELLO/hello/outer"},
      {~s'{{$x := "outer"}}{{if true}}{{upper ($x = .text)}}{{end}}/{{$x}}', "HELLO/hello"},
      {~s'{{if and ($x := true) ($y := .text)}}{{$x}}/{{$y}}{{end}}', "true/hello"},
      {~s'{{and false ($x := "skipped")}}', "false"},
      {~s'{{$x := "old"}}{{or true ($x = "skipped")}}/{{$x}}', "true/old"},
      {~s'{{$x := "old"}}{{and false ($x = "skipped")}}/{{$x}}', "false/old"},
      {~s'{{$x := "old"}}{{and ($x = "") ($y := true)}}<{{$x}}>', "<>"},
      {~s'{{with ($x := .text)}}{{$x}}/{{.}}{{end}}', "hello/hello"},
      {~s'{{$x := "outer"}}{{with (and false ($x := .text))}}bad{{else}}{{$x}}{{end}}', "outer"},
      {~s'{{($x := .text | upper)}}/{{$x}}', "HELLO/HELLO"},
      {~s'{{($x := .text) | upper}}/{{$x}}', "HELLO/hello"},
      {~s'{{$x := print ($y := "inner") $y}}{{$x}}/{{$y}}', "innerinner/inner"},
      {~s'{{$x := "outer"}}{{if true}}{{($x = ($x := "inner"))}}/{{$x}}{{end}}/{{$x}}', "inner/inner/outer"},
      {~s'{{upper ($ := .text)}}/{{$}}/{{.text}}', "HELLO/hello/hello"},
      {~s'{{eq ($x := 1) $x}}/{{$x}}', "true/1"},
      {~s'{{eq ($x := 1) ($x = 2)}}/{{$x}}', "false/2"},
      {~s'{{default ($x := "fallback") ($x := "")}}<{{$x}}>', "fallback<>"}
    ]

    labels = %{"job" => "variables", "text" => "hello"}
    push(ctx, "original", ctx.now, labels)

    for {template, expected} <- source_rows ++ controls, stage <- [:line, :label] do
      format = if stage == :line, do: "line_format ", else: "label_format out="
      expression = ~s/{job="variables"} | / <> format <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      result = if stage == :line, do: {labels, [expected]}, else: {Map.put(labels, "out", expected), ["original"]}
      assert_streams(response, [result])
      assert request_form(ctx, "/query_range", params) == response
    end

    expression = ~s'{job="variables"} | line_format "{{$x := .text}}{{$x}}"'
    assert_metric(ctx, "sum(bytes_over_time(#{expression} [1m]))", 1, %{%{} => [{1, "5"}]})

    # Bindings never survive another destination or entry. Root reassignment
    # is local to this template, not a mutation of the stage's label snapshot.
    push(ctx, "second", ctx.now - @second, labels)

    expression =
      ~s'{job="variables"} | label_format first="{{$x := $.text}}{{$ = true}}{{$x}}",again="{{$.text}}"'

    params = [{"query", expression} | range(ctx)]
    response = request(ctx, "/query_range", params)
    expected = Map.merge(labels, %{"first" => "hello", "again" => "hello"})
    assert_streams(response, [{expected, ["original", "second"]}])
    assert request_form(ctx, "/query_range", params) == response
    assert_parquet_read(ctx)
  end

  @tag :template_variables_batch
  @tag :template_nested_bindings_batch
  test "template variable failures preserve inputs and unknown references reject before storage", ctx do
    labels = %{"job" => "variable-errors", "text" => "hello", "out" => "unchanged"}
    push(ctx, "original", ctx.now, labels)

    for template <- [
          ~s'{{$x = 1}}',
          ~s'{{$x := $x}}{{$x}}',
          ~s'{{if false}}{{$x := 1}}{{else}}{{$x}}{{end}}',
          ~s'{{if false}}{{$x := 1}}{{else}}{{$x = 2}}{{end}}',
          ~s'{{$x := 2.0}}{{repeat $x "x"}}',
          ~s'{{$x := .text}}{{$x.text}}',
          ~s'{{$x := nil}}',
          ~s'{{$x := .text}}{{$x 1}}',
          ~s'{{$ := true}}{{$.text}}',
          ~s'{{$x := "ok"}}{{$x = div 1 0}}{{$x}}',
          ~s'{{or true ($x := "skipped")}}{{$x}}',
          ~s'{{and false ($x := "skipped")}}{{$x}}',
          ~s'{{print ($x = 1)}}',
          ~s'{{print ($x := $x)}}',
          ~s'{{repeat ($x := 2.0) "x"}}',
          ~s'{{with .text}}{{upper ($x := .)}}{{$x.text}}{{end}}'
        ],
        stage <- ["line_format ", "label_format out="] do
      expression = ~s/{job="variable-errors"} | / <> stage <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      assert [%{"stream" => stream, "values" => [[_, "original"]]}] = response["data"]["result"]
      assert stream["out"] == "unchanged"
      assert stream["__error__"] == "TemplateFormatErr"
      assert request_form(ctx, "/query_range", params) == response
      params = [query: "bytes_over_time(#{expression} [1m])", time: to_string(ctx.now + @second)]
      assert request(ctx, "/query", params, 400)["message"] =~ "pipeline_error"
      assert_metric(ctx, ~s/sum(bytes_over_time(#{expression} | __error__!="" [1m]))/, 1, %{%{} => [{1, "8"}]})
    end

    for template <- [
          ~s'{{$unknown}}',
          ~s'{{if false}}{{$unknown}}{{end}}',
          ~s'{{$x := $other}}',
          ~s'{{if true}}{{$x := 1}}{{end}}{{$x}}',
          ~s'{{with $x := .text}}{{.}}{{end}}{{$x}}',
          ~s'{{$x :=}}',
          ~s'{{$x, $y := .text}}',
          ~s'{{.text := "bad"}}',
          ~s'{{print ($x := $unknown)}}',
          ~s'{{if true}}{{upper ($x := .text)}}{{end}}{{$x}}',
          ~s'{{print $x ($x := 1)}}',
          ~s'{{print ($x := $y) ($y := 1)}}',
          ~s'{{upper ($x :=)}}'
        ] do
      before = Agent.get(ctx.store, & &1.reads)
      expression = ~s/{job="variable-errors"} |= "absent" | line_format / <> Pulse.JSON.encode!(template)
      params = [query: expression, time: to_string(ctx.now)]
      assert request(ctx, "/query", params, 400)["status"] == "error"
      assert request_form(ctx, "/query", params, 400)["status"] == "error"
      assert Agent.get(ctx.store, & &1.reads) == before
    end

    assert_parquet_read(ctx)
  end

  @tag :template_range_batch
  test "template ranges iterate label maps and integers with scoped loop control through HTTP", ctx do
    labels = %{"job" => "iteration", "text" => "hello"}
    push(ctx, "original", ctx.now, labels)

    controls = [
      {~s'{{range 3}}[{{.}}]{{end}}', "[0][1][2]"},
      {~s'{{range 0}}bad{{else}}{{.text}}{{end}}', "hello"},
      {~s'{{range -2}}bad{{else}}empty{{end}}', "empty"},
      {~s'{{range (and nil true)}}bad{{else}}nil{{end}}', "nil"},
      {~s'{{range $x, $y := (and nil true)}}bad{{else}}{{$x}}/{{$y}}{{end}}', "<no value>/<no value>"},
      {~s'{{range (index "\x03" 0)}}{{.}}{{end}}', "012"},
      {~s'{{range (index "\x02" 0)}}{{eq . 0}}{{end}}', "truefalse"},
      {~s'{{range $}}{{.}};{{end}}', "iteration;hello;"},
      {~s'{{range $k, $v := $}}{{$k}}={{$v}};{{end}}', "job=iteration;text=hello;"},
      {~s'{{range $v := $}}{{$v}}/{{.}};{{end}}', "iteration/iteration;hello/hello;"},
      {~s'{{$v := "outer"}}{{range $v := 2}}{{$v}}{{end}}/{{$v}}', "01/outer"},
      {~s'{{$v := "outer"}}{{range $v = 3}}{{$v}}{{end}}/{{$v}}', "012/2"},
      {~s'{{range $v := 0}}bad{{else}}{{$v}}{{end}}', "0"},
      {~s'{{$v := "old"}}{{range $v = 0}}bad{{else}}{{$v}}{{end}}/{{$v}}', "0/0"},
      {~s'{{$n := 0}}{{range 4}}{{$n = add $n .}}{{end}}{{$n}}', "6"},
      {~s'{{range 4}}{{if eq . 2}}{{break}}{{end}}{{.}}{{end}}/{{.text}}', "01/hello"},
      {~s'{{range 4}}{{if eq . 1}}{{continue}}{{end}}{{.}}{{end}}', "023"},
      {~s'{{range 2}}[{{.}}:{{range 3}}{{.}}{{break}}{{end}}]{{end}}', "[0:0][1:0]"},
      {~s'{{range 2}}{{range 0}}{{else}}{{continue}}{{end}}bad{{end}}ok', "ok"},
      {~s'{{range 3}}{{with true}}{{break}}{{end}}bad{{else}}empty{{end}}ok', "ok"},
      {~s'{{$x := "outer"}}{{range 2}}{{$x := .}}{{$x}}{{end}}/{{$x}}', "01/outer"},
      {~s'{{range $k, $k := $}}{{$k}};{{end}}', "iteration;hello;"},
      {~s'{{$k := "old"}}{{$v := "old"}}{{range $k, $v = $}}{{$k}}={{$v}};{{end}}/{{$k}}/{{$v}}',
       "job=iteration;text=hello;/text/hello"},
      {~s'{{range 1}}{{$.text}}/{{__line__}}{{end}}', "hello/original"},
      {~s'{{range $v := (or false 2)}}{{upper ($x := $.text)}}{{$v}}{{end}}', "HELLO0HELLO1"},
      {String.duplicate("{{range 1}}", 64) <> "ok" <> String.duplicate("{{end}}", 64), "ok"}
    ]

    for {template, expected} <- controls, stage <- [:line, :label] do
      format = if stage == :line, do: "line_format ", else: "label_format out="
      expression = ~s/{job="iteration"} | / <> format <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      result = if stage == :line, do: {labels, [expected]}, else: {Map.put(labels, "out", expected), ["original"]}
      assert_streams(response, [result])
      assert request_form(ctx, "/query_range", params) == response
    end

    # Original Go 1.27.3 parse/parse_test.go:222-241 syntax, not value oracles.
    # The source's struct/slice fields are intentionally not invented as labels.
    for template <- [
          "{{range .X}}hello{{end}}",
          "{{range .X.Y.Z}}hello{{end}}",
          "{{range .X}}hello{{range .Y}}goodbye{{end}}{{end}}",
          "{{range .X}}true{{else}}false{{end}}",
          "{{range .X|.M}}true{{else}}false{{end}}",
          "{{range .SI}}{{.}}{{end}}",
          "{{range $x := .SI}}{{.}}{{end}}",
          "{{range $x, $y := .SI}}{{.}}{{end}}",
          "{{range .SI}}{{.}}{{break}}{{end}}",
          "{{range .SI}}{{.}}{{continue}}{{end}}"
        ] do
      expression = ~s/{job="iteration"} |= "absent" | line_format / <> Pulse.JSON.encode!(template)
      assert request(ctx, "/query_range", [{"query", expression} | range(ctx)])["data"]["result"] == []
    end

    assert_parquet_read(ctx)
  end

  @tag :template_range_batch
  test "template range type errors preserve inputs and invalid loop control rejects before storage", ctx do
    labels = %{"job" => "iteration-errors", "out" => "unchanged"}
    push(ctx, "original", ctx.now, labels)

    for template <- [
          ~s'{{range "abc"}}bad{{end}}',
          ~s'{{range true}}bad{{end}}',
          ~s'{{range 2.0}}bad{{end}}',
          ~s'{{range 1i}}bad{{end}}',
          ~s'{{range $x, $y := 2}}bad{{end}}',
          ~s'{{range $x, $y := 0}}bad{{end}}',
          ~s'{{range $x = 0}}bad{{end}}',
          ~s'{{range 2}}{{if eq . 0}}{{$x := 1}}{{else}}{{$x}}{{end}}{{end}}',
          ~s'{{range .missing}}bad{{end}}',
          ~s'{{range (index "\x02" 0)}}{{repeat . "x"}}{{end}}'
        ],
        stage <- ["line_format ", "label_format out="] do
      expression = ~s/{job="iteration-errors"} | / <> stage <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      assert [%{"stream" => stream, "values" => [[_, "original"]]}] = response["data"]["result"]
      assert stream["out"] == "unchanged"
      assert stream["__error__"] == "TemplateFormatErr"
      assert request_form(ctx, "/query_range", params) == response
      assert_metric(ctx, ~s/sum(bytes_over_time(#{expression} | __error__!="" [1m]))/, 1, %{%{} => [{1, "8"}]})
    end

    for template <- [
          "{{break}}",
          "{{continue}}",
          "{{range}}x{{end}}",
          "{{range 0}}x{{else}}{{break}}{{end}}",
          "{{range 1}}{{break 1}}{{end}}",
          "{{range 1}}{{continue 1}}{{end}}",
          "{{range 1}}{{else if true}}bad{{end}}",
          "{{range $x, $y, $z := $}}{{end}}",
          "{{range $x := 1}}{{end}}{{$x}}"
        ] do
      before = Agent.get(ctx.store, & &1.reads)
      expression = ~s/{job="iteration-errors"} |= "absent" | line_format / <> Pulse.JSON.encode!(template)
      params = [query: expression, time: to_string(ctx.now)]
      assert request(ctx, "/query", params, 400)["status"] == "error"
      assert request_form(ctx, "/query", params, 400)["status"] == "error"
      assert Agent.get(ctx.store, & &1.reads) == before
    end

    # The existing 64-expression ceiling also covers nested ranges.
    before = Agent.get(ctx.store, & &1.reads)
    template = String.duplicate("{{range 0}}", 65) <> "bad" <> String.duplicate("{{end}}", 65)
    expression = ~s/{job="iteration-errors"} | line_format / <> Pulse.JSON.encode!(template)
    assert request(ctx, "/query", [query: expression, time: to_string(ctx.now)], 400)["status"] == "error"
    assert Agent.get(ctx.store, & &1.reads) == before

    assert_parquet_read(ctx)
  end

  @tag :template_field_chains_batch
  test "template field chains preserve label-map access through HTTP", ctx do
    labels = %{"job" => "field-chains", "text" => "hello", "cause" => "neglect"}
    push(ctx, "original", ctx.now, labels)

    # Go 1.27.3 exec_test.go:707, the complete original bug9 oracle.
    source_rows = [{"{{.cause}}", "neglect"}]

    controls = [
      {~s'{{($).text}}', "hello"},
      {~s'{{(.).text}}', "hello"},
      {~s'{{((($))).text}}', "hello"},
      {~s'{{(or false $).text}}', "hello"},
      {~s'{{(and true $).text | upper}}', "HELLO"},
      {~s'{{upper ($).text}}', "HELLO"},
      {~s'{{$x := $}}{{($x).text}}/{{$x.text}}', "hello/hello"},
      {~s'{{($x := $).text}}/{{$x.text}}', "hello/hello"},
      {~s'{{with .text}}{{($).text}}/{{.}}{{end}}', "hello/hello"},
      {~s'{{with (or false $).text}}{{upper .}}{{end}}', "HELLO"},
      {~s'{{($).missing}}', ""},
      {~s'{{if false}}{{.text.more}}{{else}}{{($).text}}{{end}}', "hello"},
      {~s'{{(and nil true).text.more}}', "<no value>"},
      {~s'{{$x := "old"}}{{(and nil true).text ($x = "new")}}/{{$x}}', "<no value>/old"}
    ]

    for {template, expected} <- source_rows ++ controls, stage <- [:line, :label] do
      format = if stage == :line, do: "line_format ", else: "label_format out="
      expression = ~s/{job="field-chains"} | / <> format <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      result = if stage == :line, do: {labels, [expected]}, else: {Map.put(labels, "out", expected), ["original"]}
      assert_streams(response, [result])
      assert request_form(ctx, "/query_range", params) == response
    end

    assert_parquet_read(ctx)
  end

  @tag :template_field_chains_batch
  test "template field-chain failures preserve inputs and syntax rejects before storage", ctx do
    labels = %{"job" => "chain-errors", "text" => "hello", "out" => "unchanged"}
    push(ctx, "original", ctx.now, labels)

    # Complete original Go 1.27.3 exec_test.go:720-722 bug14a/b/c templates.
    source_errors = [
      "{{(nil).True}}",
      "{{$x := nil}}{{$x.anything}}",
      ~s'{{$x := (1.0)}}{{$y := ("hello")}}{{$x.anything}}{{$y.true}}'
    ]

    for template <-
          source_errors ++
            [
              ~s'{{.text.more}}',
              ~s'{{.missing.more}}',
              ~s'{{$.text.more}}',
              ~s'{{($).text.more}}',
              ~s'{{($).missing.more}}',
              ~s'{{__line__.text}}',
              ~s'{{("hello").text}}',
              ~s'{{(true).text}}',
              ~s'{{($).text "argument"}}',
              ~s'{{($) .text}}'
            ],
        stage <- ["line_format ", "label_format out="] do
      expression = ~s/{job="chain-errors"} | / <> stage <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      assert [%{"stream" => stream, "values" => [[_, "original"]]}] = response["data"]["result"]
      assert stream["out"] == "unchanged"
      assert stream["__error__"] == "TemplateFormatErr"
      assert request_form(ctx, "/query_range", params) == response
      assert_metric(ctx, ~s/sum(bytes_over_time(#{expression} | __error__!="" [1m]))/, 1, %{%{} => [{1, "8"}]})
    end

    for template <- [
          ~s'{{true.text}}',
          ~s'{{"hello".text}}',
          ~s'{{nil.text}}',
          ~s'{{$.}}',
          ~s'{{($).}}',
          ~s'{{unknown.text}}',
          ~s'{{($unknown).text}}'
        ] do
      before = Agent.get(ctx.store, & &1.reads)
      expression = ~s/{job="chain-errors"} |= "absent" | line_format / <> Pulse.JSON.encode!(template)
      params = [query: expression, time: to_string(ctx.now)]
      assert request(ctx, "/query", params, 400)["status"] == "error"
      assert request_form(ctx, "/query", params, 400)["status"] == "error"
      assert Agent.get(ctx.store, & &1.reads) == before
    end

    assert_parquet_read(ctx)
  end

  @tag :template_with_batch
  test "Go with actions scope dot while preserving root labels through HTTP", ctx do
    # Complete root-independent Go 1.27.3 exec_test.go:580-584,586,588-589,599-600
    # rows retain their original templates and expected output. Typed struct,
    # slice/map fields and variable declarations are not label-map fixtures.
    source_rows = [
      {"{{with true}}{{.}}{{end}}", "true"},
      {"{{with false}}{{.}}{{else}}FALSE{{end}}", "FALSE"},
      {"{{with 1}}{{.}}{{else}}ZERO{{end}}", "1"},
      {"{{with 0}}{{.}}{{else}}ZERO{{end}}", "ZERO"},
      {"{{with 1.5}}{{.}}{{else}}ZERO{{end}}", "1.5"},
      {"{{with 1.5i}}{{.}}{{else}}ZERO{{end}}", "(0+1.5i)"},
      {"{{with ``}}{{.}}{{else}}EMPTY{{end}}", "EMPTY"},
      {"{{with `notempty`}}{{.}}{{else}}EMPTY{{end}}", "notempty"},
      {"{{with 0}}{{.}}{{else with true}}{{.}}{{end}}", "true"},
      {"{{with 0}}{{.}}{{else with false}}{{.}}{{else with `notempty`}}{{.}}{{end}}", "notempty"}
    ]

    controls = [
      {~s'{{$.text}}/{{index $ "text"}}/{{eq .text $.text}}', "hello/hello/true"},
      {~s'{{with .text}}{{.}}/{{$.text}}/{{upper .}}{{end}}/{{.text}}', "hello/hello/HELLO/hello"},
      {~s'{{with .text}}{{with "inner"}}{{.}}/{{$.text}}{{end}}/{{.}}{{end}}', "inner/hello/hello"},
      {~s'{{with .text}}{{if true}}{{.}}{{else}}bad{{end}}{{end}}', "hello"},
      {~s'{{with .text}}{{with false}}bad{{else}}{{.}}{{end}}{{end}}', "hello"},
      {~s'{{with .missing}}bad{{else}}{{.text}}/{{$.text}}{{end}}', "hello/hello"},
      {~s'{{with false}}bad{{else with .text}}{{.}}{{else}}bad{{end}}', "hello"},
      {~s'{{with .text}}{{with 0}}bad{{else with .}}{{upper .}}{{end}}{{end}}', "HELLO"},
      {~s'{{with (and nil true)}}bad{{else}}{{.text}}{{end}}', "hello"},
      {~s'{{with (float64 "0")}}bad{{else}}{{.text}}{{end}}', "hello"},
      {~s'{{with 0i}}bad{{else}}{{.text}}{{end}}', "hello"},
      {~s'{{with (index "\u0000" 0)}}bad{{else}}{{.text}}{{end}}', "hello"},
      {~s'{{with (float64 "NaN")}}{{.}}{{end}}', "NaN"},
      {~s'{{with (float64 "+Inf")}}{{.}}{{end}}', "+Inf"},
      {~s'{{with $}}{{index . "text"}}/{{.text}}{{end}}', "hello/hello"},
      {~s'{{with .text | upper}}{{.}}{{end}}', "HELLO"},
      {~s'{{with true}}{{__line__}}{{end}}', "original"},
      {~s'{{with true}}ok{{else}}{{nil}}{{end}}', "ok"},
      {~s'{{with false}}{{upper true}}{{else}}ok{{end}}', "ok"},
      {~s'{{with .text}}{{with true}}yes{{end}}{{end}}/{{.text}}', "yes/hello"},
      {~s'{{with true -}} \n {{.}} \n {{- else -}} no {{- end}}', "true"},
      {String.duplicate("{{with true}}", 64) <> "ok" <> String.duplicate("{{end}}", 64), "ok"}
    ]

    labels = %{"job" => "with-scope", "text" => "hello"}
    push(ctx, "original", ctx.now, labels)

    for {template, expected} <- source_rows ++ controls, stage <- [:line, :label] do
      format = if stage == :line, do: "line_format ", else: "label_format out="
      expression = ~s/{job="with-scope"} | / <> format <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      result = if stage == :line, do: {labels, [expected]}, else: {Map.put(labels, "out", expected), ["original"]}
      assert_streams(response, [result])
      assert request_form(ctx, "/query_range", params) == response
    end

    expression = ~s/{job="with-scope"} | line_format / <> Pulse.JSON.encode!(~s'{{with .text}}{{.}}{{end}}')
    assert_metric(ctx, "sum(bytes_over_time(#{expression} [1m]))", 1, %{%{} => [{1, "5"}]})

    expression =
      ~s'{job="with-scope"} | label_format text="changed",root="{{with $.text}}{{.}}{{end}}",again="{{$.text}}"'

    params = [{"query", expression} | range(ctx)]
    response = request(ctx, "/query_range", params)
    expected = Map.merge(labels, %{"text" => "changed", "root" => "hello", "again" => "hello"})
    assert_streams(response, [{expected, ["original"]}])
    assert request_form(ctx, "/query_range", params) == response

    expression =
      ~s'{job="with-scope"} | label_format text="changed" | line_format "{{with $.text}}{{.}}{{end}}"'

    params = [{"query", expression} | range(ctx)]
    response = request(ctx, "/query_range", params)
    assert_streams(response, [{Map.put(labels, "text", "changed"), ["changed"]}])
    assert request_form(ctx, "/query_range", params) == response

    expression = ~s'{job="with-scope"} | drop job,text | line_format "{{with $}}bad{{else}}empty{{end}}"'
    params = [{"query", expression} | range(ctx)]
    response = request(ctx, "/query_range", params)
    assert_streams(response, [{%{}, ["empty"]}])
    assert request_form(ctx, "/query_range", params) == response
    assert_parquet_read(ctx)
  end

  @tag :template_with_batch
  test "with action errors preserve input and validate skipped branches before storage", ctx do
    labels = %{"job" => "with-errors", "text" => "hello", "out" => "unchanged"}
    push(ctx, "original", ctx.now, labels)

    for template <- [
          ~s'{{with nil}}bad{{end}}',
          ~s'{{with (nil)}}bad{{end}}',
          ~s'{{with .text}}{{.text}}{{end}}',
          ~s'{{with true}}{{.missing}}{{end}}',
          ~s'{{with .text}}{{len nil}}{{end}}',
          ~s'{{with false}}ok{{else with nil}}bad{{end}}',
          ~s'{{with .text}}{{slice . 99}}{{end}}',
          ~s'{{with true}}{{$.text 1}}{{end}}'
        ],
        stage <- ["line_format ", "label_format out="] do
      expression = ~s/{job="with-errors"} | / <> stage <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      assert [%{"stream" => stream, "values" => [[_, "original"]]}] = response["data"]["result"]
      assert stream["out"] == "unchanged"
      assert stream["__error__"] == "TemplateFormatErr"
      assert request_form(ctx, "/query_range", params) == response
      params = [query: "bytes_over_time(#{expression} [1m])", time: to_string(ctx.now + @second)]
      assert request(ctx, "/query", params, 400)["message"] =~ "pipeline_error"
      assert_metric(ctx, ~s/sum(bytes_over_time(#{expression} | __error__!="" [1m]))/, 1, %{%{} => [{1, "8"}]})
    end

    for template <- [
          "{{with true}}",
          "{{with}}{{end}}",
          "{{with false}}ok{{else if true}}bad{{end}}",
          "{{if false}}ok{{else with true}}bad{{end}}",
          "{{with false}}{{unknown .}}{{end}}",
          "{{with true}}ok{{else}}{{unknown .}}{{end}}",
          String.duplicate("{{with true}}", 65) <> "ok" <> String.duplicate("{{end}}", 65)
        ] do
      before = Agent.get(ctx.store, & &1.reads)
      expression = ~s/{job="with-errors"} | line_format / <> Pulse.JSON.encode!(template)
      params = [query: expression, time: to_string(ctx.now)]
      assert request(ctx, "/query", params, 400)["status"] == "error"
      assert request_form(ctx, "/query", params, 400)["status"] == "error"
      assert Agent.get(ctx.store, & &1.reads) == before
    end

    assert_parquet_read(ctx)
  end

  @tag :template_js_batch
  test "Go JavaScript escaping preserves Unicode, typed joining and error policies through HTTP", ctx do
    # Complete Go 1.27.3 exec_test.go:1037-1044 JSEscapeString table.
    # Wrap each unchanged input/oracle in {{js .text}} for both formatters.
    original = [
      {"a", "a"},
      {"'foo", "\\'foo"},
      {~s'Go "jump" ' <> <<92>>, ~S'Go \"jump\" ' <> <<92, 92>>},
      {~s'Yukihiro says "今日は世界"', ~S'Yukihiro says \"今日は世界\"'},
      {"unprintable \uFFFE", ~S'unprintable \uFFFE'},
      {"<html>", ~S'\u003Chtml\u003E'},
      {"no = in attributes", ~S'no \u003D in attributes'},
      {"&#x27; does not become HTML entity", ~S'\u0026#x27; does not become HTML entity'}
    ]

    for {text, expected} <- original do
      labels = %{"job" => "js-source", "text" => text}
      push(ctx, "original", ctx.now, labels)

      for stage <- [:line, :label] do
        format = if stage == :line, do: "line_format ", else: "label_format out="

        expression =
          ~s/{job="js-source",text=/ <>
            Pulse.JSON.encode!(text) <> "} | " <> format <> Pulse.JSON.encode!("{{js .text}}")

        params = [{"query", expression} | range(ctx)]
        response = request(ctx, "/query_range", params)
        result = if stage == :line, do: {labels, [expected]}, else: {Map.put(labels, "out", expected), ["original"]}
        assert_streams(response, [result])
        assert request_form(ctx, "/query_range", params) == response
      end
    end

    controls = [
      {~s'{{js}}', ""},
      {~s'{{js 1 nil 2 true}}', ~S'1\u003Cno value\u003E2 true'},
      {~s'{{js "é☃🙂"}}', "é☃🙂"},
      {~S'{{js "\x00\t\n\r\u001f"}}', ~S'\u0000\u0009\u000A\u000D\u001F'},
      {~S'{{js "\x7f\u0085\u00a0\u200b\u2028\u2029\uFEFF\uFFFE"}}',
       "\x7f" <> ~S'\u0085\u00A0\u200B\u2028\u2029\uFEFF\uFFFE'},
      {~S'{{js "\u088f\u1acf\U00011db0\U0001faea"}}', "\u088f\u1acf\u{11db0}\u{1faea}"},
      {~S'{{js "\ue000\U000e0001\U0010ffff"}}', ~S'\uE000\uE0001\u10FFFF'},
      {~S|{{js "\"" "'" "\\" "<>&="}}|, ~S|\"\'\\\u003C\u003E\u0026\u003D|},
      {~s'{{js 1 2 "x+y"}}', "1 2x+y"},
      {~s'{{js 1+2i (index "x" 0)}}', "(1+2i) 120"},
      {~s'{{js .missing}}', ""},
      {~s'{{.text | js | html}}', "It\\&#39;d be nice."},
      {~s'{{if false}}{{js (slice "x" 9)}}{{else}}ok{{end}}', "ok"},
      {~s'{{js (repeat 4095 "x") "é&"}}', String.duplicate("x", 4095) <> ~S'é\u0026'}
    ]

    labels = %{"job" => "js-controls", "text" => "It'd be nice."}
    push(ctx, "original", ctx.now, labels)

    for {template, expected} <- controls, stage <- [:line, :label] do
      format = if stage == :line, do: "line_format ", else: "label_format out="
      expression = ~s/{job="js-controls"} | / <> format <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      result = if stage == :line, do: {labels, [expected]}, else: {Map.put(labels, "out", expected), ["original"]}
      assert_streams(response, [result])
      assert request_form(ctx, "/query_range", params) == response
    end

    for template <- [~s'{{js (slice "x" 9)}}', ~s'{{js (len nil)}}', ~s'{{js (nil)}}'],
        stage <- ["line_format ", "label_format out="] do
      expression = ~s/{job="js-controls"} | / <> stage <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      assert [%{"stream" => stream, "values" => [[_, "original"]]}] = response["data"]["result"]
      assert stream["__error__"] == "TemplateFormatErr"
      refute Map.has_key?(stream, "out")
      assert request_form(ctx, "/query_range", params) == response
      params = [query: "bytes_over_time(#{expression} [1m])", time: to_string(ctx.now + @second)]
      assert request(ctx, "/query", params, 400)["message"] =~ "pipeline_error"
      assert_metric(ctx, ~s/sum(bytes_over_time(#{expression} | __error__!="" [1m]))/, 1, %{%{} => [{1, "8"}]})
    end

    expression = ~s/{job="js-controls"} | line_format / <> Pulse.JSON.encode!(~s'{{js "&"}}')
    assert_metric(ctx, "sum(bytes_over_time(#{expression} [1m]))", 1, %{%{} => [{1, "6"}]})
    assert_parquet_read(ctx)
  end

  @tag :template_nil_batch
  test "template nil values preserve Go truthiness, equality and printing through HTTP", ctx do
    # Original Go 1.27.3 exec_test.go:476 print-nil case. The remaining rows
    # exercise untyped nil, not Go pointers or arbitrary interface values.
    rows = [
      {~s'{{print nil}}', "<nil>"},
      {~s'{{print nil nil 1}}', "<nil> <nil> 1"},
      {~s'{{println nil nil 1}}', "<nil> <nil> 1\n"},
      {~s'{{html nil nil 1}}', "&lt;no value&gt;&lt;no value&gt;1"},
      {~s'{{urlquery nil nil 1}}', "%3Cno+value%3E%3Cno+value%3E1"},
      {~s'{{and nil true}}/{{or false nil}}', "<no value>/<no value>"},
      {~s'{{if and nil true}}bad{{else}}empty{{end}}', "empty"},
      {~s'{{not nil}}/{{or nil "fallback"}}/{{default "fallback" nil}}', "true/fallback/fallback"},
      {~s'{{default nil ""}}/{{default "fallback" (and nil 1)}}', "<no value>/fallback"},
      {~s'{{eq nil nil}}/{{ne nil nil}}/{{eq nil ""}}/{{eq nil .missing}}', "true/false/false/false"},
      {~s'{{eq nil .}}/{{eq . nil}}/{{eq nil 0}}/{{eq false nil}}', "false/false/false/false"},
      {~s'{{eq nil 1 0 nil}}/{{eq 1 nil 1}}/{{eq nil 0i}}/{{eq nil (float64 "NaN")}}', "true/true/false/false"},
      {~s'{{int nil}}/{{float64 nil}}/{{add nil 3}}/{{addf nil 1.5}}', "0/0/3/1.5"},
      {~s'{{and nil true | print}}', "<nil>"},
      {~s'{{and nil true | html}}', "&lt;no value&gt;"},
      {~s'{{print (default nil "")}}', "<nil>"},
      {~s'{{repeat 2 (print nil)}}', "<nil><nil>"},
      {~s'{{if false}}{{nil}}{{else}}ok{{end}}', "ok"},
      {~s'{{and nil (slice "x" 9)}}', "<no value>"},
      {~s'{{or true (len nil)}}', "true"},
      {~s'{{print .missing}}/{{html .missing}}/{{eq (index . "absent") nil}}', "//false"},
      {~s'{{if .missing}}bad{{else if not nil}}ok{{end}}', "ok"},
      {~s'{{html 1 nil 2 true}}', "1&lt;no value&gt;2 true"},
      {~s'{{print 1 nil 2 true}}', "1 <nil> 2 true"}
    ]

    labels = %{"job" => "template-nil"}
    push(ctx, "original", ctx.now, labels)

    for {template, expected} <- rows, stage <- [:line, :label] do
      format = if stage == :line, do: "line_format ", else: "label_format out="
      expression = ~s/{job="template-nil"} | / <> format <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      result = if stage == :line, do: {labels, [expected]}, else: {Map.put(labels, "out", expected), ["original"]}
      assert_streams(response, [result])
      assert request_form(ctx, "/query_range", params) == response
    end

    expression = ~s/{job="template-nil"} | line_format / <> Pulse.JSON.encode!(~s'{{print nil}}')
    assert_metric(ctx, "sum(bytes_over_time(#{expression} [1m]))", 1, %{%{} => [{1, "5"}]})
    assert_parquet_read(ctx)
  end

  @tag :template_nil_batch
  test "nil commands and typed arguments fail at execution without losing original inputs", ctx do
    push(ctx, "original", ctx.now, %{"job" => "nil-errors", "out" => "unchanged"})

    # First two are original Go exec_test.go:293,448 runtime errors, not
    # constructor failures. A skipped nil command must remain admissible.
    for template <- [
          ~s'{{nil}}',
          ~s'{{if nil}}TRUE{{end}}',
          ~s'{{(nil)}}',
          ~s'{{print (nil)}}',
          ~s'{{nil | print}}',
          ~s'{{nil 1}}',
          ~s'{{len nil}}',
          ~s'{{index nil}}',
          ~s'{{index . nil}}',
          ~s'{{index "x" nil}}',
          ~s'{{slice nil}}',
          ~s'{{slice "x" nil}}',
          ~s'{{lt nil nil}}',
          ~s'{{le nil 1}}',
          ~s'{{ge 1 nil}}',
          ~s'{{upper nil}}',
          ~s'{{repeat nil "x"}}',
          ~s'{{repeat 1 nil}}',
          ~s'{{round 1.2 nil}}',
          ~s'{{bytes nil}}',
          ~s'{{eq nil}}'
        ],
        stage <- ["line_format ", "label_format out="] do
      expression = ~s/{job="nil-errors"} | / <> stage <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      assert [%{"stream" => labels, "values" => [[_, "original"]]}] = response["data"]["result"]
      assert labels["out"] == "unchanged"
      assert labels["__error__"] == "TemplateFormatErr"
      assert request_form(ctx, "/query_range", params) == response
      params = [query: "bytes_over_time(#{expression} [1m])", time: to_string(ctx.now + @second)]
      assert request(ctx, "/query", params, 400)["message"] =~ "pipeline_error"
      assert_metric(ctx, ~s/sum(bytes_over_time(#{expression} | __error__!="" [1m]))/, 1, %{%{} => [{1, "8"}]})
    end

    for template <- [~s'{{print nil | nil}}', ~s'{{and nil (unknown nil)}}'] do
      expression = ~s/{job="nil-errors"} | line_format / <> Pulse.JSON.encode!(template)
      params = [query: expression, time: to_string(ctx.now)]
      before = Agent.get(ctx.store, & &1.requests)
      response = request(ctx, "/query", params, 400)
      assert request_form(ctx, "/query", params, 400) == response
      assert Agent.get(ctx.store, & &1.requests) == before
    end
  end

  @tag :template_print_escape_batch
  test "Go printing and escaping preserve typed argument spacing through Loki HTTP", ctx do
    # Go 1.27.3 exec_test.go:474-475,477,490-491,502,676-677.
    # Go structs/nil/methods, printf and the js table remain outside this port.
    original = [
      {~s'{{print "hello, print"}}', "hello, print"},
      {~s'{{print 1 2 3}}', "1 2 3"},
      {~s'{{println 1 2 3}}', "1 2 3\n"},
      {~S'{{html "<script>alert(\"XSS\");</script>"}}', "&lt;script&gt;alert(&#34;XSS&#34;);&lt;/script&gt;"},
      {~s'{{"http://www.example.org/"|urlquery}}', "http%3A%2F%2Fwww.example.org%2F"},
      {~s'{{print 1_2_3_4 7.5_00_00_00}}', "1234 7.5"},
      {~s'{{print 1234 0x0_1.e_0p+02}}', "1234 7.5"}
    ]

    controls = [
      {~s'{{print}}|{{println}}|{{html}}|{{urlquery}}', "|\n||"},
      {~s'{{print 1 "x" 2 3 "" 4 true}}', "1x2 34 true"},
      {~s'{{println 1 "x" 2 3 "" 4 true}}', "1 x 2 3  4 true\n"},
      {~S'{{html "\x00\"\u0027<>&"}}', "�&#34;&#39;&lt;&gt;&amp;"},
      {~s'{{html "&amp;"}}', "&amp;amp;"},
      {~s'{{html 1 2 "<" 3}}', "1 2&lt;3"},
      {~s'{{urlquery 1 2 "x+y z" true}}', "1+2x%2By+ztrue"},
      {~s'{{urlquery "é+☃ /"}}', "%C3%A9%2B%E2%98%83+%2F"},
      {~s'{{print 1+2i (index "x" 0) true}}', "(1+2i) 120 true"},
      {~s'{{print (float64 "NaN") (float64 "+Inf")}}', "NaN +Inf"},
      {~s'{{.foo | html}}', "a&amp;b"},
      {~s'{{html .}}', "map[foo:a&amp;b job:print-escape]"},
      {~s'{{urlquery .}}', "map%5Bfoo%3Aa%26b+job%3Aprint-escape%5D"},
      {~s'{{"end" | print 1 2}}', "1 2end"},
      {~s'{{print .missing 1 .missing 2}}', "12"},
      {~s'{{html (repeat 4095 "x") "é&"}}', String.duplicate("x", 4095) <> "é&amp;"},
      {~s'{{if false}}{{html (slice "x" 9)}}{{else}}ok{{end}}', "ok"}
    ]

    labels = %{"job" => "print-escape", "foo" => "a&b"}
    push(ctx, "original", ctx.now, labels)

    for {template, expected} <- original ++ controls, stage <- [:line, :label] do
      format = if stage == :line, do: "line_format ", else: "label_format out="
      expression = ~s/{job="print-escape"} | / <> format <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      result = if stage == :line, do: {labels, [expected]}, else: {Map.put(labels, "out", expected), ["original"]}
      assert_streams(response, [result])
      assert request_form(ctx, "/query_range", params) == response
    end

    expression = ~s/{job="print-escape"} | line_format / <> Pulse.JSON.encode!(~s'{{println 1 2 3}}')
    assert_metric(ctx, "sum(bytes_over_time(#{expression} [1m]))", 1, %{%{} => [{1, "6"}]})
    assert_parquet_read(ctx)
  end

  @tag :template_slice_batch
  test "Go string slices preserve byte bounds and default indices through Loki HTTP", ctx do
    # Complete string rows in Go 1.27.3 exec_test.go:564-567, with
    # tVal.S="xyz" projected into a string label rather than a Go struct.
    original = [
      {~s'{{slice .S}}', "xyz"},
      {~s'{{slice .S 0 1}}', "x"},
      {~s'{{slice .S 1}}', "yz"},
      {~s'{{slice .S 1 2}}', "y"}
    ]

    controls = [
      {~s'{{slice ""}}', ""},
      {~s'{{slice "abcd" 4}}', ""},
      {~s'{{slice "abcd" 1 3}}', "bc"},
      {~s'{{slice "abcd" 2 2}}', ""},
      {~s'{{slice "abcd" 0 4}}', "abcd"},
      {~s'{{slice "aé🙂z" 1 3}}', "é"},
      {~s'{{slice "aé🙂z" 3 7}}', "🙂"},
      {~s'{{slice .S (int "1") (len .S)}}', "yz"},
      {~S'{{slice .S (index "\x01" 0) (index "\x03" 0)}}', "yz"},
      {~s'{{slice (index . "S") 1}}', "yz"},
      {~s'{{slice .S | upper}}', "XYZ"},
      {~s'{{.S | slice}}', "xyz"},
      {~s'{{slice (slice .S 1) 0 1}}', "y"},
      {~s'{{if false}}{{slice .S -1}}{{else}}ok{{end}}', "ok"}
    ]

    labels = %{"job" => "template-slice", "S" => "xyz"}
    push(ctx, "original", ctx.now, labels)

    for {template, expected} <- original ++ controls, stage <- [:line, :label] do
      format = if stage == :line, do: "line_format ", else: "label_format out="
      expression = ~s/{job="template-slice"} | / <> format <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      result = if stage == :line, do: {labels, [expected]}, else: {Map.put(labels, "out", expected), ["original"]}
      assert_streams(response, [result])
      assert request_form(ctx, "/query_range", params) == response
    end

    expression = ~s/{job="template-slice"} | line_format / <> Pulse.JSON.encode!(~s'{{slice "aé🙂z" 3 7}}')
    assert_metric(ctx, "sum(bytes_over_time(#{expression} [1m]))", 1, %{%{} => [{1, "4"}]})
    assert_parquet_read(ctx)
  end

  @tag :template_slice_batch
  test "slice type and bounds failures preserve inputs and metric-error policies", ctx do
    push(ctx, "original", ctx.now, %{"job" => "slice-errors", "S" => "xyz", "out" => "unchanged"})

    # The first two errors are the original Go exec_test.go:568-569 rows.
    for template <- [
          ~s'{{slice .S 1 5}}',
          ~s'{{slice .S 1 2 2}}',
          ~s'{{slice .S -1}}',
          ~s'{{slice .S 2 1}}',
          ~s'{{slice .S 4}}',
          ~s'{{slice .S 0.0}}',
          ~s'{{slice .S 0i}}',
          ~s'{{slice .S "1"}}',
          ~s'{{slice .S true}}',
          ~s'{{slice .}}',
          ~s'{{slice 1}}',
          ~s'{{slice}}',
          ~s'{{slice .S 0 1 2 3}}',
          # Deliberate stricter rejection: byte strings cannot flow between
          # actions yet, including when b64enc could repair the UTF-8 split.
          ~s'{{slice "é" 0 1}}',
          ~s'{{slice "é" 0 1 | b64enc}}'
        ],
        stage <- ["line_format ", "label_format out="] do
      expression = ~s/{job="slice-errors"} | / <> stage <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      assert [%{"stream" => labels, "values" => [[_, "original"]]}] = response["data"]["result"]
      assert labels["out"] == "unchanged"
      assert labels["__error__"] == "TemplateFormatErr"
      assert request_form(ctx, "/query_range", params) == response
      params = [query: "bytes_over_time(#{expression} [1m])", time: to_string(ctx.now + @second)]
      assert request(ctx, "/query", params, 400)["message"] =~ "pipeline_error"
      assert_metric(ctx, ~s/sum(bytes_over_time(#{expression} | __error__!="" [1m]))/, 1, %{%{} => [{1, "8"}]})
    end
  end

  @tag :template_index_batch
  test "template index preserves root labels and unsigned string-byte values through HTTP", ctx do
    # Original Go 1.27.3 exec_test.go:1302-1303 comparison regressions.
    original = [
      {~s|{{eq (index `x` 0) 'x'}}|, "true"},
      {~s|{{eq (index `x` 0) 'y'}}|, "false"}
    ]

    controls = [
      {~s'{{index . "foo"}}/{{index . "missing" | default "none"}}', "aé/none"},
      {~s'{{index . "foo" 0}}/{{index . "foo" 2}}', "97/169"},
      {~s'{{index "aé" 1}}/{{index "aé" 2}}', "195/169"},
      {~s'{{len .}}/{{index .}}', "2/map[foo:aé job:template-index]"},
      {~s'{{.}}/{{if .}}yes{{end}}/{{int .}}/{{float64 .}}', "map[foo:aé job:template-index]/yes/0/0"},
      {~s'{{eq (index "x" 0) 120}}/{{lt -1 (index "x" 0)}}', "true/true"},
      {~s'{{add (index "x" 0) 1}}/{{float64 (index "x" 0)}}', "121/120"},
      {~S'{{index "abc" (index "\x01" 0)}}', "98"},
      {~S'{{if (index "\x00" 0)}}bad{{else}}zero{{end}}', "zero"},
      {~s'{{index "abc"}}/{{index "abc" | len}}', "abc/3"},
      {~S'{{repeat (int (index "\x02" 0)) "x"}}', "xx"},
      {~s'{{if false}}{{index "x" 10}}{{else}}ok{{end}}', "ok"}
    ]

    labels = %{"job" => "template-index", "foo" => "aé"}
    push(ctx, "original", ctx.now, labels)

    for {template, expected} <- original ++ controls, stage <- [:line, :label] do
      format = if stage == :line, do: "line_format ", else: "label_format out="
      expression = ~s/{job="template-index"} | / <> format <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      result = if stage == :line, do: {labels, [expected]}, else: {Map.put(labels, "out", expected), ["original"]}
      assert_streams(response, [result])
      assert request_form(ctx, "/query_range", params) == response
    end

    expression =
      ~s/{job="template-index"} | label_format foo=/ <>
        Pulse.JSON.encode!(~s'{{upper (index . "foo")}}') <>
        ",out=" <> Pulse.JSON.encode!(~s'{{index . "foo"}}')

    assert_streams(query(ctx, expression), [{%{labels | "foo" => "AÉ"} |> Map.put("out", "aé"), ["original"]}])

    expression =
      ~s/{job="template-index"} | label_format foo="changed" | line_format / <>
        Pulse.JSON.encode!(~s'{{index . "foo"}}')

    assert_streams(query(ctx, expression), [{%{labels | "foo" => "changed"}, ["changed"]}])

    push(ctx, "other", ctx.now, %{"job" => "index-metadata"}, %{"http.method" => "GET", "odd name" => "safe"})

    expression =
      ~s/{job="index-metadata"} | line_format / <>
        Pulse.JSON.encode!(~s'{{index . "http.method"}}/{{index . "odd name"}}')

    assert_streams(query(ctx, expression), [
      {%{"job" => "index-metadata", "http.method" => "GET", "odd name" => "safe"}, ["GET/safe"]}
    ])
  end

  @tag :template_index_batch
  test "index failures preserve inputs and byte values require explicit typed conversion", ctx do
    push(ctx, "original", ctx.now, %{"job" => "index-errors", "out" => "unchanged"})

    for template <- [
          ~s'{{index "x" 1}}',
          ~s'{{index "x" -1}}',
          ~s'{{index "x" 0.0}}',
          ~s'{{index "x" 0i}}',
          ~s'{{index "x" "0"}}',
          ~s'{{index . 0}}',
          ~s'{{index . "missing" 0}}',
          ~s'{{index "x" 0 0}}',
          ~s'{{index}}',
          ~S'{{repeat (index "\x02" 0) "x"}}',
          ~s'{{eq (index "x" 0) 120.0}}',
          ~s'{{eq . .}}'
        ],
        stage <- ["line_format ", "label_format out="] do
      expression = ~s/{job="index-errors"} | / <> stage <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      assert [%{"stream" => labels, "values" => [[_, "original"]]}] = response["data"]["result"]
      assert labels["out"] == "unchanged"
      assert labels["__error__"] == "TemplateFormatErr"
      assert request_form(ctx, "/query_range", params) == response
      params = [query: "bytes_over_time(#{expression} [1m])", time: to_string(ctx.now + @second)]
      assert request(ctx, "/query", params, 400)["message"] =~ "pipeline_error"
      assert_metric(ctx, ~s/sum(bytes_over_time(#{expression} | __error__!="" [1m]))/, 1, %{%{} => [{1, "8"}]})
    end

    expression =
      ~s/{job="index-errors"} |= "absent" | line_format / <> Pulse.JSON.encode!(~s'{{if false}}{{"x" | .}}{{end}}')

    reads = Agent.get(ctx.store, & &1.requests)
    assert request(ctx, "/query", [query: expression, time: to_string(ctx.now)], 400)["status"] == "error"
    assert Agent.get(ctx.store, & &1.requests) == reads
  end

  @tag :template_complex_batch
  test "Go complex constants retain types and signed components through Loki HTTP", ctx do
    # Complete Go 1.27.3 parse/parse_test.go:55-65 complex-number rows.
    original = [
      {"4i", "(0+4i)"},
      {"-1.2+4.2i", "(-1.2+4.2i)"},
      {"073i", "(0+73i)"},
      {"0i", "(0+0i)"},
      {"-1.2+0i", "(-1.2+0i)"},
      {"-12+0i", "(-12+0i)"},
      {"13+0i", "(13+0i)"}
    ]

    controls = [
      {"-0-0i", "(-0-0i)"},
      {"-0i", "(0-0i)"},
      {"1e3-2e-2i", "(1000-0.02i)"},
      {"0x_1p4+0x_1p-4i", "(16+0.0625i)"},
      {"1_2+3_4i", "(12+34i)"},
      {"-0x1p-1075+0x1p-1074i", "(-0+5e-324i)"}
    ]

    rows = Enum.map(original ++ controls, fn {literal, expected} -> {"{{#{literal}}}", expected} end)

    rows =
      rows ++
        [
          {~s'{{if 0i}}bad{{else}}zero{{end}}/{{if -0-0i}}bad{{else}}zero{{end}}', "zero/zero"},
          {~s'{{if 0+2i}}yes{{end}}/{{if 2+0i}}yes{{end}}/{{not 0i}}', "yes/yes/true"},
          {~s'{{default "empty" -0-0i}}/{{default "bad" 2i}}', "empty/(0+2i)"},
          {~s'{{and 2i 3+4i}}/{{or 0i -2i}}', "(3+4i)/(0-2i)"},
          {~s'{{eq 1+2i 1+3i 1+2i}}/{{ne 1+2i 1+3i}}/{{eq -0-0i 0i}}', "true/true/true"},
          {~s'{{int 2+0i}}/{{float64 2+0i}}/{{add 2i 7}}/{{addf 2i 0.1}}', "0/0/7/0.1"},
          {~s'{{repeat 2+0i "é"}}/{{"x" | repeat 2+0i}}/{{trunc 2+0i "abcd"}}', "éé/xx/ab"},
          {~s'{{round 1.25 1+0i 0.4+0i}}/{{repeat (int 2+0i) "x"}}', "1.3/"},
          {~s'{{if false}}{{repeat 2+3i "x"}}{{else}}ok{{end}}', "ok"}
        ]

    push(ctx, "original", ctx.now, %{"job" => "complex-constants"})

    for {template, expected} <- rows, stage <- [:line, :label] do
      labels = %{"job" => "complex-constants"}
      format = if stage == :line, do: "line_format ", else: "label_format out="
      expression = ~s/{job="complex-constants"} | / <> format <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      result = if stage == :line, do: {labels, [expected]}, else: {Map.put(labels, "out", expected), ["original"]}
      assert_streams(response, [result])
      assert request_form(ctx, "/query_range", params) == response
    end

    expression = ~s/{job="complex-constants"} | line_format / <> Pulse.JSON.encode!(~s'{{repeat 2+0i "é"}}')
    assert_metric(ctx, "sum(bytes_over_time(#{expression} [1m]))", 1, %{%{} => [{1, "4"}]})
  end

  @tag :template_complex_batch
  test "complex admission and runtime errors retain template failure boundaries", ctx do
    push(ctx, "original", ctx.now, %{"job" => "complex-errors", "out" => "unchanged"})

    for literal <- [
          "1i+2i",
          "1i-2i",
          "0x10+2i",
          "0o7i",
          "1+0o7i",
          "1+-2i",
          "1+2ii",
          "1+2i+3i",
          "1e309+2i",
          "1+2e309i",
          "0x1p1024i"
        ],
        stage <- ["line_format ", "label_format out="] do
      template = "{{if false}}{{#{literal}}}{{end}}"
      expression = ~s/{job="complex-errors"} |= "absent" | / <> stage <> Pulse.JSON.encode!(template)
      params = [query: expression, time: to_string(ctx.now)]
      reads = Agent.get(ctx.store, & &1.requests)
      response = request(ctx, "/query", params, 400)
      assert request_form(ctx, "/query", params, 400) == response
      assert Agent.get(ctx.store, & &1.requests) == reads
    end

    for template <- [
          ~s'{{repeat 2+3i "x"}}',
          ~s'{{repeat 2.5+0i "x"}}',
          ~s'{{repeat (2+0i) "x"}}',
          ~s'{{round 1.25 1 (0.4+0i)}}',
          ~s'{{round 1.25 1 0.4+1i}}',
          ~s'{{eq 0i 0}}',
          ~s'{{eq 2+0i 2.0}}',
          ~s'{{lt 1+0i 2+0i}}',
          ~s'{{upper 2i}}',
          ~s'{{len 2i}}'
        ],
        stage <- ["line_format ", "label_format out="] do
      expression = ~s/{job="complex-errors"} | / <> stage <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      assert [%{"stream" => labels, "values" => [[_, "original"]]}] = response["data"]["result"]
      assert labels["out"] == "unchanged"
      assert labels["__error__"] == "TemplateFormatErr"
      assert request_form(ctx, "/query_range", params) == response
      params = [query: "bytes_over_time(#{expression} [1m])", time: to_string(ctx.now + @second)]
      assert request(ctx, "/query", params, 400)["message"] =~ "pipeline_error"
      assert_metric(ctx, ~s/sum(bytes_over_time(#{expression} | __error__!="" [1m]))/, 1, %{%{} => [{1, "8"}]})
    end
  end

  @tag :template_decimal_batch
  test "Loki decimal arithmetic retains upstream formatter results through HTTP", ctx do
    # Complete original mathfloat/mathfloatround rows, fmt_test.go:244-261.
    original = [
      {~s'{{ addf .foo 1.5 | subf .bar 1.5 | mulf .baz | divf .bazz }}',
       %{"foo" => "1.5", "bar" => "5", "baz" => "10.5", "bazz" => "20.2"}, "3.8476190476190477"},
      {~s'{{ round (addf .foo 1.5 | subf .bar | mulf .baz | divf .bazz) 5 .2}}',
       %{"foo" => "1.5", "bar" => "3.5", "baz" => "10.5", "bazz" => "20.4"}, "3.88572"}
    ]

    controls = [
      {~s'{{addf 0.1 0.2 0.3}}/{{mulf 0.1 0.2 0.3}}', "0.6/0.006"},
      {~s'{{addf 1e16 1 -1e16}}/{{subf 1e16 -1 1e16}}', "1/1"},
      {~s'{{subf 10 2 3}}/{{divf 48 2 3}}/{{mulf 2 3 5}}', "5/8/30"},
      {~s'{{addf}}/{{subf 2.5}}/{{mulf 2.5}}/{{divf 2.5}}', "0/2.5/2.5/2.5"},
      {~s'{{addf true false "bad" "1e309" " 2" "0x1.8p1"}}', "4"},
      {~s'{{divf 1 3}}/{{divf 1 3 3}}/{{mulf (divf 1 3) 3}}',
       "0.3333333333333333/0.1111111111111111/0.9999999999999999"},
      {~s'{{divf "1e-16" 2}}/{{divf "-1e-16" 2}}/{{divf "1e-17" 2}}', "1e-16/-1e-16/0"},
      {~s'{{mulf "-0" 1}}/{{addf "-0"}}/{{divf "-0" 1}}', "0/0/0"},
      {~s'{{mulf "1e308" 10}}/{{mulf "-1e308" 10}}/{{mulf "-1e-300" "1e-100"}}', "+Inf/-Inf/-0"},
      {~s'{{mulf "1e308" "1e308" "1e-308"}}', "1e+308"},
      {~s'{{addf "9007199254740993" 1}}/{{addf 9007199254740993 1}}', "9.007199254740992e+15/9.007199254740992e+15"},
      {~s'{{eq (addf 0.1 0.2) 0.3}}/{{default "empty" (subf 1 1)}}', "true/empty"},
      {~s'{{repeat (int (mulf 1.5 2)) "x"}}', "xxx"}
    ]

    rows = original ++ Enum.map(controls, fn {template, expected} -> {template, %{}, expected} end)

    for {{template, fields, expected}, index} <- Enum.with_index(rows) do
      labels = Map.put(fields, "job", "decimal-#{index}")
      push(ctx, "", ctx.now, labels)

      for stage <- [:line, :label] do
        format = if stage == :line, do: "line_format ", else: "label_format out="
        expression = ~s/{job="decimal-#{index}"} | / <> format <> Pulse.JSON.encode!(template)
        params = [{"query", expression} | range(ctx)]
        response = request(ctx, "/query_range", params)
        result = if stage == :line, do: {labels, [expected]}, else: {Map.put(labels, "out", expected), [""]}
        assert_streams(response, [result])
        assert request_form(ctx, "/query_range", params) == response
      end
    end
  end

  @tag :template_decimal_batch
  test "decimal arithmetic failures preserve inputs and selected metric errors", ctx do
    push(ctx, "original", ctx.now, %{"job" => "decimal-errors", "out" => "unchanged"})

    for template <- [
          ~s'{{divf 1 0}}',
          ~s'{{divf 1 "bad"}}',
          ~s'{{addf "NaN"}}',
          ~s'{{subf "+Inf" 1}}',
          ~s'{{mulf 1 "-Inf"}}',
          ~s'{{addf (mulf "1e308" 10) 1}}',
          ~s'{{subf}}',
          ~s'{{mulf}}',
          ~s'{{divf}}',
          ~s'{{upper (addf 1 2)}}'
        ],
        stage <- ["line_format ", "label_format out="] do
      expression = ~s/{job="decimal-errors"} | / <> stage <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      assert [%{"stream" => labels, "values" => [[_, "original"]]}] = response["data"]["result"]
      assert labels["out"] == "unchanged"
      assert labels["__error__"] == "TemplateFormatErr"
      assert request_form(ctx, "/query_range", params) == response
      params = [query: "bytes_over_time(#{expression} [1m])", time: to_string(ctx.now + @second)]
      assert request(ctx, "/query", params, 400)["message"] =~ "pipeline_error"
      assert_metric(ctx, ~s/sum(bytes_over_time(#{expression} | __error__!="" [1m]))/, 1, %{%{} => [{1, "8"}]})
    end

    expression =
      ~s/{job="decimal-errors"} | line_format / <>
        Pulse.JSON.encode!(~s'{{if false}}{{divf 1 0}}{{else}}ok{{end}}')

    assert_streams(query(ctx, expression), [{%{"job" => "decimal-errors", "out" => "unchanged"}, ["ok"]}])
  end

  @tag :template_float_helpers_batch
  test "Loki floating coercion extrema and rounding replay through HTTP", ctx do
    # Complete pinned fmt_test.go:271-288,298-306 rows; original input is empty.
    original = [
      {~s'minf is {{ minf .foo .bar .baz }} and maxf is {{maxf .foo .bar .baz}}',
       %{"foo" => "5.3", "bar" => "10.5", "baz" => "15.2"}, "minf is 5.3 and maxf is 15.2"},
      {~s'ceil is {{ ceil .foo }} and floor is {{floor .foo }}', %{"foo" => "5.3"}, "ceil is 6 and floor is 5"},
      {~s'{{ "2.5" | float64 | int | add 10}}', %{"foo" => "2.5"}, "12"}
    ]

    controls = [
      {~s'{{float64 true}}/{{float64 false}}/{{float64 "bad"}}/{{float64 " 2"}}/{{float64 "1e309"}}', "1/0/0/0/0"},
      {~s'{{float64 "0x1.8p1"}}/{{float64 "1_2.5"}}/{{float64 "-0"}}', "3/12.5/-0"},
      {~s'{{ceil -1.2}}/{{floor -1.2}}/{{ceil -0.2}}/{{floor -0.0}}', "-1/-2/-0/-0"},
      {~s'{{minf -0.0 0.0}}/{{maxf -0.0 0.0}}/{{eq (float64 "2") 2.0}}', "-0/0/true"},
      {~s'{{float64 "NaN"}}/{{ceil "+Inf"}}/{{floor "-Inf"}}', "NaN/+Inf/-Inf"},
      {~s'{{minf "NaN" "-Inf"}}/{{maxf "NaN" "+Inf"}}/{{minf "NaN" 1}}', "-Inf/+Inf/NaN"},
      {~s'{{eq (float64 "NaN") (float64 "NaN")}}/{{ne (float64 "NaN") (float64 "NaN")}}', "false/true"},
      {~s'{{lt (float64 "NaN") 0.0}}/{{le (float64 "NaN") 0.0}}/{{gt (float64 "NaN") 0.0}}/{{ge (float64 "NaN") 0.0}}',
       "false/false/true/true"},
      {~s'{{default "zero" (float64 "-0")}}/{{if float64 "NaN"}}yes{{end}}', "zero/yes"},
      # Pinned Loki's Go compiler fuses the fractional residual: its first
      # result differs from Sprig's older static TestRound oracle (123.556).
      {~s'{{round 123.5555 3}}/{{round "123.55555" 3}}', "123.555/123.556"},
      {~s'{{round 123.500001 0}}/{{round 123.49999999 0}}', "124/123"},
      {~s'{{round 123.2329999 2 .3}}/{{round 123.233 2 .3}}', "123.23/123.24"},
      {~s'{{round -1.2 0}}/{{round -1.2 0 -0.3}}/{{round 125 -1}}', "-2/-1/130"},
      {~s'{{round 2.125 2.0}}/{{round 2.125 2 0.2 0.9}}', "2.13/2.13"},
      {~s'{{round "NaN" 2}}/{{round "+Inf" 2}}/{{round 1 309}}/{{round 1 -324}}', "NaN/+Inf/NaN/NaN"},
      {~s'{{repeat (int (ceil "5.3")) "1"}}', "111111"}
    ]

    rows = original ++ Enum.map(controls, fn {template, expected} -> {template, %{}, expected} end)

    for {{template, fields, expected}, index} <- Enum.with_index(rows) do
      labels = Map.put(fields, "job", "float-helpers-#{index}")
      push(ctx, "", ctx.now, labels)

      for stage <- [:line, :label] do
        format = if stage == :line, do: "line_format ", else: "label_format out="
        expression = ~s/{job="float-helpers-#{index}"} | / <> format <> Pulse.JSON.encode!(template)
        params = [{"query", expression} | range(ctx)]
        response = request(ctx, "/query_range", params)
        result = if stage == :line, do: {labels, [expected]}, else: {Map.put(labels, "out", expected), [""]}
        assert_streams(response, [result])
        assert request_form(ctx, "/query_range", params) == response
      end
    end
  end

  @tag :template_float_helpers_batch
  test "floating helper type failures preserve inputs and skipped branches stay lazy", ctx do
    push(ctx, "original", ctx.now, %{"job" => "float-helper-errors", "out" => "unchanged"})

    for template <- [
          ~s'{{float64}}',
          ~s'{{minf}}',
          ~s'{{round 1}}',
          ~s'{{round 1 (2.0)}}',
          ~s'{{round 1 2 "0.3"}}',
          ~s'{{round 1 2 (1)}}',
          ~s'{{upper (ceil 1.2)}}',
          ~s'{{repeat (float64 "2") "x"}}',
          ~s'{{eq (float64 "2") 2}}',
          ~s'{{int (float64 "NaN")}}'
        ],
        stage <- ["line_format ", "label_format out="] do
      expression = ~s/{job="float-helper-errors"} | / <> stage <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      assert [%{"stream" => labels, "values" => [[_, "original"]]}] = response["data"]["result"]
      assert labels["out"] == "unchanged"
      assert labels["__error__"] == "TemplateFormatErr"
      assert request_form(ctx, "/query_range", params) == response
      params = [query: "bytes_over_time(#{expression} [1m])", time: to_string(ctx.now + @second)]
      assert request(ctx, "/query", params, 400)["message"] =~ "pipeline_error"
      assert_metric(ctx, ~s/sum(bytes_over_time(#{expression} | __error__!="" [1m]))/, 1, %{%{} => [{1, "8"}]})
    end

    expression =
      ~s/{job="float-helper-errors"} | line_format / <>
        Pulse.JSON.encode!(~s'{{if false}}{{round 1 (2.0)}}{{else}}ok{{end}}')

    assert_streams(query(ctx, expression), [{%{"job" => "float-helper-errors", "out" => "unchanged"}, ["ok"]}])
  end

  @tag :template_floats_batch
  test "Go template float constants preserve spelling-dependent types through Loki HTTP", ctx do
    # Complete non-complex floating rows, Go 1.27.3 parse/parse_test.go:45-54.
    original = [
      {"1e9", "1e+09"},
      {"-1e9", "-1e+09"},
      {"-1.2", "-1.2"},
      {"1e19", "1e+19"},
      {"1e1_9", "1e+19"},
      {"1E19", "1e+19"},
      {"-1e19", "-1e+19"},
      {"0x_1p4", "16"},
      {"0X_1P4", "16"},
      {"0x_1p-4", "0.0625"}
    ]

    controls = [
      {".5", "0.5"},
      {"-.5", "-0.5"},
      {"08e0", "8"},
      {"01.0", "1"},
      {"1.", "1"},
      {"-0.0", "-0"},
      {"0x1p-1074", "5e-324"},
      {"-0x1p-1075", "-0"},
      {"0x1.fffffffffffffp1023", "1.7976931348623157e+308"}
    ]

    rows = Enum.map(original ++ controls, fn {literal, expected} -> {"{{#{literal}}}", expected} end)

    rows =
      rows ++
        [
          {~s'{{repeat 2.0 "é"}}/{{"x" | repeat 2e0}}', "éé/xx"},
          {~s'{{trunc 2.0 "abcd"}}/{{substr 1.0 3e0 "abcd"}}', "ab/bc"},
          {~s'{{Replace "banana" "a" "X" 2.0}}/{{alignRight 3.0 "é"}}', "bXnXna/  é"},
          {~s'{{indent 2.0 "x"}}/{{nindent 1e0 "y"}}', "  x/\n y"},
          {~s'{{eq 2.0 (duration "2s")}}/{{lt .5 1.0}}/{{int -2.9}}/{{add 1.5 2.5}}', "true/true/-2/3"},
          {~s'{{default "zero" -0.0}}/{{if -0.0}}bad{{else}}zero{{end}}', "zero/zero"},
          {~s'{{if false}}{{repeat 2.5 "x"}}{{else}}ok{{end}}', "ok"}
        ]

    push(ctx, "original", ctx.now, %{"job" => "float-constants"})

    for {template, expected} <- rows, stage <- [:line, :label] do
      labels = %{"job" => "float-constants"}
      format = if stage == :line, do: "line_format ", else: "label_format out="
      expression = ~s/{job="float-constants"} | / <> format <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      result = if stage == :line, do: {labels, [expected]}, else: {Map.put(labels, "out", expected), ["original"]}
      assert_streams(response, [result])
      assert request_form(ctx, "/query_range", params) == response
    end

    expression = ~s/{job="float-constants"} | line_format / <> Pulse.JSON.encode!(~s'{{repeat 2.0 "é"}}')
    assert_metric(ctx, "sum(bytes_over_time(#{expression} [1m]))", 1, %{%{} => [{1, "4"}]})
  end

  @tag :template_floats_batch
  test "float literal admission and typed integer failures preserve Go template boundaries", ctx do
    push(ctx, "original", ctx.now, %{"job" => "float-errors", "out" => "unchanged"})

    for literal <- ["1e.", "0x123.", "1e309", "0x1p1024", "1__0.0", "1._0", "0x1p", "NaN", "+Inf"],
        stage <- ["line_format ", "label_format out="] do
      template = "{{if false}}{{#{literal}}}{{end}}"
      expression = ~s/{job="float-errors"} |= "absent" | / <> stage <> Pulse.JSON.encode!(template)
      params = [query: expression, time: to_string(ctx.now)]
      reads = Agent.get(ctx.store, & &1.requests)
      response = request(ctx, "/query", params, 400)
      assert request_form(ctx, "/query", params, 400) == response
      assert Agent.get(ctx.store, & &1.requests) == reads
    end

    for template <- [
          ~s'{{repeat (2.0) "x"}}',
          ~s'{{repeat 2.5 "x"}}',
          ~s'{{repeat 0x1p63 "x"}}',
          ~s'{{eq 2.0 2}}',
          ~s'{{upper 2.0}}',
          ~s'{{"x" | 2.0}}'
        ],
        stage <- ["line_format ", "label_format out="] do
      expression = ~s/{job="float-errors"} | / <> stage <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      # A constant after a pipe is a parse-time error, even in a skipped branch.
      if template == ~s'{{"x" | 2.0}}' do
        reads = Agent.get(ctx.store, & &1.requests)
        assert request(ctx, "/query_range", params, 400)["status"] == "error"
        assert Agent.get(ctx.store, & &1.requests) == reads
      else
        response = request(ctx, "/query_range", params)
        assert [%{"stream" => labels, "values" => [[_, "original"]]}] = response["data"]["result"]
        assert labels["out"] == "unchanged"
        assert labels["__error__"] == "TemplateFormatErr"
        assert request_form(ctx, "/query_range", params) == response
        params = [query: "bytes_over_time(#{expression} [1m])", time: to_string(ctx.now + @second)]
        assert request(ctx, "/query", params, 400)["message"] =~ "pipeline_error"
        assert_metric(ctx, ~s/sum(bytes_over_time(#{expression} | __error__!="" [1m]))/, 1, %{%{} => [{1, "8"}]})
      end
    end
  end

  @tag :template_runes_batch
  test "Go template character constants retain integer values through Loki HTTP", ctx do
    # Complete Go 1.27.3 parse/parse_test.go:68-75 character-number rows.
    original = [
      {~S|'a'|, "97"},
      {~S|'\n'|, "10"},
      {~S|'\\'|, "92"},
      {~S|'\''|, "39"},
      {~S|'\xFF'|, "255"},
      {"'パ'", "12497"},
      {~S|'\u30d1'|, "12497"},
      {~S|'\U000030d1'|, "12497"}
    ]

    controls = [
      # Two additional character tokens from lex_test.go:157-174.
      {~S|'\u00FF'|, "255"},
      {"'本'", "26412"},
      {~S|'\000'|, "0"},
      {~S|'\377'|, "255"},
      {~S|'\x80'|, "128"},
      {~S|'\uD7FF'|, "55295"},
      {~S|'\uE000'|, "57344"},
      {~S|'\U0010FFFF'|, "1114111"},
      {"'🙂'", "128578"},
      {"'é'", "233"},
      {~S|'"'|, "34"},
      {"'\r'", "13"}
    ]

    rows = Enum.map(original ++ controls, fn {literal, expected} -> {"{{#{literal}}}", expected} end)

    rows =
      rows ++
        [
          {~S|{{add 'a' '\001'}}/{{repeat '\002' "é"}}|, "98/éé"},
          {~S|{{eq '.' 46}}/{{eq 'e' (int "101")}}/{{eq 'P' 80}}|, "true/true/true"},
          {~S|{{default "zero" '\000'}}/{{if '\000'}}bad{{else}}zero{{end}}|, "zero/zero"},
          {~S|{{if false}}{{upper 'a'}}{{else}}ok{{end}}|, "ok"},
          {"{{'\\n' | add 7}}", "17"}
        ]

    push(ctx, "original", ctx.now, %{"job" => "rune-constants"})

    for {template, expected} <- rows, stage <- [:line, :label] do
      labels = %{"job" => "rune-constants"}
      format = if stage == :line, do: "line_format ", else: "label_format out="
      expression = ~s/{job="rune-constants"} | / <> format <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      result = if stage == :line, do: {labels, [expected]}, else: {Map.put(labels, "out", expected), ["original"]}
      assert_streams(response, [result])
      assert request_form(ctx, "/query_range", params) == response
    end

    expression = ~s/{job="rune-constants"} | line_format / <> Pulse.JSON.encode!(~S|{{'\xFF'}}|)
    assert_metric(ctx, "sum(bytes_over_time(#{expression} [1m]))", 1, %{%{} => [{1, "3"}]})
  end

  @tag :template_runes_batch
  test "malformed rune constants reject before storage and rune type errors preserve inputs", ctx do
    push(ctx, "original", ctx.now, %{"job" => "rune-errors", "out" => "unchanged"})

    for literal <- [
          # All three original malformed character-number rows, parse_test.go:82-84.
          "'x",
          "'xx'",
          "'433937734937734969526500969526500'",
          "''",
          "'a\n'",
          "'é́'",
          ~S|'\400'|,
          ~S|'\7'|,
          ~S|'\x0'|,
          ~S|'\uD800'|,
          ~S|'\uDFFF'|,
          ~S|'\U00110000'|,
          ~S|'\UFFFFFFFF'|,
          ~S|'\z'|,
          ~S|'\"'|
        ],
        stage <- ["line_format ", "label_format out="] do
      template = "{{if false}}{{#{literal}}}{{end}}"
      expression = ~s/{job="rune-errors"} |= "absent" | / <> stage <> Pulse.JSON.encode!(template)
      params = [query: expression, time: to_string(ctx.now)]
      reads = Agent.get(ctx.store, & &1.requests)
      response = request(ctx, "/query", params, 400)
      assert request_form(ctx, "/query", params, 400) == response
      assert Agent.get(ctx.store, & &1.requests) == reads
    end

    for template <- [~S|{{upper 'A'}}|, ~S|{{len 'é'}}|, ~S|{{'a' 'b'}}|, ~S|{{eq 'a' "97"}}|],
        stage <- ["line_format ", "label_format out="] do
      expression = ~s/{job="rune-errors"} | / <> stage <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      assert [%{"stream" => labels, "values" => [[_, "original"]]}] = response["data"]["result"]
      assert labels["out"] == "unchanged"
      assert labels["__error__"] == "TemplateFormatErr"
      assert request_form(ctx, "/query_range", params) == response
      params = [query: "bytes_over_time(#{expression} [1m])", time: to_string(ctx.now + @second)]
      assert request(ctx, "/query", params, 400)["message"] =~ "pipeline_error"
      assert request_form(ctx, "/query", params, 400)["message"] =~ "pipeline_error"
      assert_metric(ctx, ~s/sum(bytes_over_time(#{expression} | __error__!="" [1m]))/, 1, %{%{} => [{1, "8"}]})
    end
  end

  @tag :template_regex_replace_batch
  test "Loki regex replacement rows and capture expansion controls replay through HTTP", ctx do
    # Complete pinned Loki fmt_test.go:187-204. Timestamp is unused; the
    # upstream nil line becomes an original sentinel, with job isolation.
    original = [
      {~s'{{ regexReplaceAll "(p)" .foo "t" }}', %{"foo" => "BLIp", "bar" => "blop"}, "BLIt"},
      {~s'{{ regexReplaceAllLiteral "(p)" .foo "${1}" }}', %{"foo" => "BLIp", "bar" => "blop"}, "BLI${1}"}
    ]

    controls = [
      {~s'{{regexReplaceAll "a+" "banana" "($0)/${0}"}}', "b(a)/an(a)/an(a)/a"},
      {~s'{{regexReplaceAll "hello, (.+)" "hello, world" "<$0><$1><$2><$3>"}}', "<hello, world><world><><>"},
      {~s'{{regexReplaceAll "(?P<word>[a-z]+)" "hi 12 bye" "${word}!"}}', "hi! 12 bye!"},
      {~s'{{regexReplaceAll "(a)" "a" "$1x/${1}x/$01/${01}/$0"}}', "/ax///a"},
      {~s'{{regexReplaceAll "a" "a" "$$/$/${oops/${}/$-/$é/$١/$²"}}', "$/$/${oops/${}/$-///$²"},
      {~s'{{regexReplaceAll "a" "aaa" "${oops"}}', "${oops${oops${oops"},
      {~S'{{regexReplaceAllLiteral "a" "banana" "$$${1}\\x"}}', ~S'b$$${1}\xn$$${1}\xn$$${1}\x'},
      {~s'{{regexReplaceAll "(x)?" "123" "$1"}}', "123"},
      {~s'{{regexReplaceAll "" "é🙂" "x"}}/{{regexReplaceAll "" "" "x"}}', "xéx🙂x/x"},
      {~s'{{regexReplaceAll "a*" "aab" "x"}}/{{regexReplaceAll "a*" "aa" "x"}}', "xbx/x"},
      {~s'{{regexReplaceAll "a*?" "aa" "x"}}/{{regexReplaceAll "aa" "aaa" "x"}}', "xaxax/xa"},
      {~S'{{regexReplaceAll "(?m)^.*$" "a\nb\n" "x"}}', "x\nx\nx"},
      {~S'{{regexReplaceAll ".$" "a\n" "x"}}/{{regexReplaceAll `\d` "١2٣4" "x"}}', "a\n/١x٣x"},
      {~S'{{regexReplaceAll `\b` "éa🙂" "x"}}/{{regexReplaceAll `\p{Greek}` "a\u0301bΣ" "x"}}', "éxax🙂/ábx"},
      {~s'{{regexReplaceAll "a" "banana" "x" | upper}}/{{"x" | regexReplaceAll "a" "banana"}}', "BXNXNX/bxnxnx"},
      {~s'{{regexReplaceAll "a" .missing "x"}}/{{regexReplaceAll "" .missing "x"}}', "/x"},
      {~s'{{or "safe" (regexReplaceAll "[" "a" "x")}}/{{if false}}{{regexReplaceAllLiteral "[" "a" "x"}}{{else}}safe{{end}}',
       "safe/safe"},
      {~s'{{regexReplaceAll "(?P<x>a)|(?<x>b)" "abba" "<$x>"}}', "<a><b><b><a>"},
      {~s'{{regexReplaceAll "(?P<x>a)(?P<x>b)" "ab" "$x/$1/$2"}}', "a/a/b"},
      {~s'{{regexReplaceAll "(?P<x>a)?(?P<x>b)" "b" "$x/$1/$2"}}', "b//b"},
      {~s'{{regexReplaceAll "(?P<x>a?)(?P<x>b)" "b" "|$x|$1|$2|"}}', "|||b|"},
      {~s'{{regexReplaceAll "(?:z)?((?P<x>a)|(?P<x>b))(c)" "bc" "$x/$1/$2/$3/$4"}}', "b/b//b/c"},
      {~s'{{regexReplaceAll "(x)(?P<1>a)(?<01>b)(?P<1000000000>c)" "xabc" "$1/${01}/${1000000000}/$0"}}', "x/b/c/xabc"},
      {~s'{{regexReplaceAll "(z)(?P<0>x)(?P<18446744073709551616>y)" "zxy" "$0/${18446744073709551616}"}}', "zxy/y"},
      {~s'{{regexReplaceAll "[(?P<x>)](?P<x>a)" "?a" "$1/$x"}}', "a/a"},
      {~s'{{regexReplaceAll "[](?P<x>]+(?P<x>a)" "](?P<x>a" "$1/$x"}}', "a/a"},
      {~S'{{regexReplaceAll `\(\?P<x>(?P<x>a)` "(?P<x>a" "$1/$x"}}', "a/a"},
      {~s'{{count "(?P<x>a)|(?<x>b)" "abbc"}}/{{count "(?P<01>a)" "aaa"}}', "3/3"},
      # All five Go 1.27.3 regexp/syntax parse_test.go:152-156 quoted-literal
      # patterns, exercised by matching rather than asserting private ASTs.
      {~S'{{regexReplaceAll `\Q+|*?{[\E` "0+|*?{[1" "x"}}', "0x1"},
      {~S'{{regexReplaceAll `\Q+\E+` "+++" "x"}}', "x"},
      {~S'{{regexReplaceAll `\Qab\E+` "abbb ab abab" "x"}}', "x x xx"},
      {~S'{{regexReplaceAll `\Q\\E` `\ \` "x"}}', "x x"},
      {~S'{{regexReplaceAll `\Q\\\E` `\\ \` "x"}}', "x \\"},
      {~S'{{regexReplaceAll `\Q\d\E` `\d 1` "x"}}', "x 1"},
      {~S'{{regexReplaceAll `\Q[[]\E` "[[]" "x"}}', "x"},
      {~S'{{regexReplaceAll `\Q(?P<x>a)\E(?P<x>b)` "(?P<x>a)b" "$x/$1"}}', "b/b"},
      {~S'{{regexReplaceAll `(?i)\Qé[Σ]\E` "É[σ]" "x"}}', "x"},
      {~S'{{regexReplaceAll `\Qunterminated.*` "unterminated.*" "x"}}', "x"},
      {~S'{{count `\Q+|*?{[\E` "+|*?{[ +|*?{["}}', "2"},
      # Complete Go 1.27.3 regexp/syntax parse_test.go:123-124 hex/octal
      # patterns, with controls on both sides of their original ranges.
      {~S'{{regexReplaceAll `[\012-\234]\141` "\ta \na \u009ca \u009da" "x"}}', "\ta x x \u009da"},
      {~S'{{regexReplaceAll `[\x{41}-\x7a]\x61` "@a Aa za {a" "x"}}', "@a x x {a"},
      {~S'{{regexReplaceAll `\141+` "baaa c" "x"}}', "bx c"},
      {~S'{{regexReplaceAll `[\141-\143]+` "abczade" "x"}}', "xzxde"},
      {~S'{{count `\0` "\x00a\x00"}}', "2"},
      {~S'{{regexReplaceAll `\08` "\x008 \x009" "x"}}', "x \0" <> "9"},
      {~S'{{regexReplaceAll `\1234` "S4 S" "x"}}', "x S"},
      {~S'{{regexReplaceAll `\400|\777` "Āǿÿ" "x"}}', "xxÿ"},
      {~S'{{regexReplaceAll `(?i)\141` "aAá" "x"}}', "xxá"},
      {~S'{{regexReplaceAll `[^\0-\07]+` "\x00abc\x07xyz" "x"}}', "\0x\ax"},
      {~S'{{regexReplaceAll `(\141)(?P<x>\142)|(?P<x>\143)` "ab c" "$1/$x"}}', "a/b /c"},
      {~S'{{regexReplaceAllLiteral `\141` "a" `\141$1`}}', ~S'\141$1'},
      {~S'{{regexReplaceAll `\Q\141\E` `\141 a` "x"}}', "x a"},
      {~S'{{regexReplaceAll `\\141` `\141 a` "x"}}', "x a"}
    ]

    rows = original ++ Enum.map(controls, fn {template, expected} -> {template, %{}, expected} end)

    push_streams(
      ctx,
      for(
        {{_, fields, _}, index} <- Enum.with_index(rows),
        do: %{
          "stream" => Map.put(fields, "job", "regex-replace-#{index}"),
          "values" => [[to_string(ctx.now), "original"]]
        }
      )
    )

    for {{template, fields, expected}, index} <- Enum.with_index(rows) do
      labels = Map.put(fields, "job", "regex-replace-#{index}")

      for stage <- [:line, :label] do
        format = if stage == :line, do: "line_format ", else: "label_format out="
        expression = ~s/{job="regex-replace-#{index}"} | / <> format <> Pulse.JSON.encode!(template)
        params = [{"query", expression} | range(ctx)]
        response = request(ctx, "/query_range", params)
        result = if stage == :line, do: {labels, [expected]}, else: {Map.put(labels, "out", expected), ["original"]}
        assert_streams(response, [result])
        assert request_form(ctx, "/query_range", params) == response
      end
    end

    assert_parquet(ctx, 1)
    assert_parquet_read(ctx)
  end

  @tag :template_regex_replace_batch
  test "Go replacement tables retain their original oracles through HTTP", ctx do
    rows =
      "test/fixtures/logs/loki-upstream/regex-replace.json"
      |> File.read!()
      |> Pulse.JSON.decode!()
      |> Map.fetch!("rows")

    rows = Enum.with_index(rows)

    push_streams(
      ctx,
      Enum.map(rows, fn {row, index} ->
        %{"stream" => %{"job" => "go-regex-replace-#{index}"}, "values" => [[to_string(ctx.now), row["input"]]]}
      end)
    )

    for {row, index} <- rows, stage <- [:line, :label] do
      labels = %{"job" => "go-regex-replace-#{index}"}
      function = if row["literal"], do: "regexReplaceAllLiteral", else: "regexReplaceAll"

      template =
        "{{#{function} #{Pulse.JSON.encode!(row["pattern"])} (__line__) #{Pulse.JSON.encode!(row["replacement"])}}}"

      format = if stage == :line, do: "line_format ", else: "label_format out="
      expression = ~s/{job="go-regex-replace-#{index}"} | / <> format <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)

      expected =
        if stage == :line,
          do: {labels, [row["output"]]},
          else: {Map.put(labels, "out", row["output"]), [row["input"]]}

      assert_streams(response, [expected])
      assert request_form(ctx, "/query_range", params) == response
    end
  end

  @tag :template_regex_replace_batch
  test "regex replacement failures preserve inputs and metric error selection", ctx do
    push(ctx, "original", ctx.now, %{"job" => "regex-replace-errors", "out" => "unchanged"})

    for template <- [
          # Original Loki fmt_test.go:794-807 direct invalid-function calls.
          ~S'{{regexReplaceAll `a|b|\q` "input" "replacement"}}',
          ~S'{{regexReplaceAllLiteral `\h` "input" "replacement"}}',
          ~s'{{regexReplaceAll "[" "a" "x"}}',
          ~s'{{regexReplaceAllLiteral "(?=a)" "a" "x"}}',
          ~s'{{regexReplaceAll "(?P<é>a)" "a" "x"}}',
          ~s'{{regexReplaceAllLiteral "(?P<>a)" "a" "x"}}',
          ~S'{{regexReplaceAll `[\Qabc\E]` "a" "x"}}',
          # Original Go regexp/syntax parse_test.go:500 rejection.
          ~S'{{regexReplaceAllLiteral `\Q\E*` "a" "x"}}',
          ~S'{{regexReplaceAll `\1` "a" "x"}}',
          ~S'{{regexReplaceAllLiteral `\8` "a" "x"}}',
          ~S'{{regexReplaceAll `\18` "a" "x"}}',
          ~S'{{regexReplaceAllLiteral `[\1]` "a" "x"}}',
          ~s'{{regexReplaceAll "a" "a"}}',
          ~s'{{regexReplaceAllLiteral "a" "a" "x" "y"}}',
          ~s'{{regexReplaceAll true "a" "x"}}',
          ~s'{{regexReplaceAll "a" 1 "x"}}',
          ~s'{{regexReplaceAllLiteral "a" "a" false}}'
        ],
        stage <- ["line_format ", "label_format out="] do
      expression = ~s/{job="regex-replace-errors"} | / <> stage <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      assert [%{"stream" => labels, "values" => [[_, "original"]]}] = response["data"]["result"]
      assert labels["out"] == "unchanged"
      assert labels["__error__"] == "TemplateFormatErr"
      assert request_form(ctx, "/query_range", params) == response
      params = [query: "bytes_over_time(#{expression} [1m])", time: to_string(ctx.now + @second)]
      assert request(ctx, "/query", params, 400)["message"] =~ "pipeline_error"
      assert request_form(ctx, "/query", params, 400)["message"] =~ "pipeline_error"
      assert_metric(ctx, ~s/sum(bytes_over_time(#{expression} | __error__!="" [1m]))/, 1, %{%{} => [{1, "8"}]})
    end
  end

  @tag :template_count_batch
  test "Loki regex count formatter rows and empty-match controls replay through HTTP", ctx do
    # Complete pinned fmt_test.go:26-47,645-659. Label formatter harness
    # always supplies "test line"; nil line inputs use an original sentinel.
    original = [
      {~s'{{.foo | count "abc" }}', %{"foo" => "abc abc abc", "bar" => "blop"}, "original", "3", :line},
      {~s'{{.foo | count "a|b|c" }}', %{"foo" => "abc abc abc", "bar" => "blop"}, "original", "9", :line},
      {~s'{{ __line__ | count "test" }}', %{"foo" => "blip", "bar" => "blop"}, "test line", "1", {:label, "count"}},
      {~s'{{ __line__ | count "notmatching.*" }}', %{}, "test line", "0", {:label, "count"}}
    ]

    controls = [
      {~s'{{count "" "é🙂"}}/{{count "" ""}}', "3/1"},
      {~s'{{count "a*" "aab"}}/{{count "a*" "aa"}}/{{count "a*" "ba"}}', "2/1/2"},
      {~s'{{count "a*?" "aa"}}/{{count "ab|a" "aba"}}/{{count "aa" "aaa"}}', "3/2/1"},
      {~S'{{count "(?m)^|$" "a\nb\n"}}/{{count ".$" "a\n"}}', "5/0"},
      {~S'{{count "(?m)^.*$" "a\nb\n"}}/{{count "(?m)^.*$" "\n"}}', "3/2"},
      {~S'{{count "." "é🙂\n"}}/{{count "(?s)." "é🙂\n"}}', "2/3"},
      {~S'{{count `\d` "١2٣4"}}/{{count `\s` "\v\t\n "}}', "2/3"},
      {~S'{{count `\b` "éa🙂"}}/{{count `\B` "éa🙂"}}', "2/2"},
      {~s'{{count "(?i)k" "KkK"}}/{{count "[[:alpha:]]" "éab1"}}', "3/2"},
      {~S'{{count `\p{Greek}` "a\u0301bΣ"}}', "1"},
      {~s'{{count "^(?:(a|aa)+b|a+c)$" "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaac"}}', "1"},
      {~s'{{count "a" .missing}}/{{count "" .missing}}', "0/1"},
      {~s'{{add (count "a" "banana") 2}}/{{repeat (count "a" "banana") "x"}}', "5/xxx"},
      {~s'{{if count "x" "abc"}}bad{{else}}zero{{end}}/{{eq (count "a" "banana") 3}}', "zero/true"},
      {~s'{{or "safe" (count "[" "x")}}/{{if false}}{{count "[" "x"}}{{else}}safe{{end}}', "safe/safe"}
    ]

    controls =
      for {template, expected} <- controls,
          stage <- [:line, {:label, "out"}],
          do: {template, %{}, "original", expected, stage}

    for {{template, fields, line, expected, stage}, index} <- Enum.with_index(original ++ controls) do
      labels = Map.put(fields, "job", "regex-count-#{index}")
      push(ctx, line, ctx.now, labels)
      format = if stage == :line, do: "line_format ", else: "label_format #{elem(stage, 1)}="
      query = ~s/{job="regex-count-#{index}"} | / <> format <> Pulse.JSON.encode!(template)
      params = [{"query", query} | range(ctx)]
      response = request(ctx, "/query_range", params)
      result = if stage == :line, do: {labels, [expected]}, else: {Map.put(labels, elem(stage, 1), expected), [line]}
      assert_streams(response, [result])
      assert request_form(ctx, "/query_range", params) == response
    end
  end

  @tag :template_count_batch
  test "count regex and argument failures preserve inputs and remain metric pipeline errors", ctx do
    push(ctx, "original", ctx.now, %{"job" => "regex-count-errors", "out" => "unchanged"})

    for template <- [
          # Original fmt_test.go:808-813 invalid-count pattern, adapted to a template.
          ~S'{{count `a|b|\K` "input"}}',
          ~s'{{count "[" "input"}}',
          ~s'{{count "(?=a)" "a"}}',
          ~S'{{count `(a)\1` "aa"}}',
          ~s'{{count "a"}}',
          ~s'{{count "a" "a" "a"}}',
          ~s'{{count true "a"}}',
          ~s'{{count "a" 1}}',
          ~s'{{upper (count "a" "a")}}',
          ~s'{{eq (count "a" "a") "1"}}'
        ],
        stage <- ["line_format ", "label_format out="] do
      expression = ~s/{job="regex-count-errors"} | / <> stage <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      assert [%{"stream" => labels, "values" => [[_, "original"]]}] = response["data"]["result"]
      assert labels["out"] == "unchanged"
      assert labels["__error__"] == "TemplateFormatErr"
      assert request_form(ctx, "/query_range", params) == response
      params = [query: "bytes_over_time(#{expression} [1m])", time: to_string(ctx.now + @second)]
      assert request(ctx, "/query", params, 400)["message"] =~ "pipeline_error"
      assert request_form(ctx, "/query", params, 400)["message"] =~ "pipeline_error"
      assert_metric(ctx, ~s/sum(bytes_over_time(#{expression} | __error__!="" [1m]))/, 1, %{%{} => [{1, "8"}]})
    end
  end

  @tag :template_quantities_batch
  test "Loki quantity formatter rows and typed conversion controls replay through HTTP", ctx do
    # Complete pinned fmt_test.go:383-418. Original inputs/outputs; timestamp
    # is unused by these helpers and translated to the test-owned clock.
    original = [
      {"{{ .foo | bytes }}", "3 kB", "3000"},
      {"{{ .foo | bytes }}", "3MB", "3e+06"},
      {"{{ .foo | duration }}", "3ms", "0.003"},
      {"{{ .foo | duration_seconds }}", "3m10s", "190"}
    ]

    controls = [
      {~s'{{bytes "1,024 KiB"}}/{{bytes "0.5B"}}/{{bytes "1.9 B"}}', "1.048576e+06/0/1"},
      {~s'{{bytes "9007199254740993B"}}/{{bytes "18446744073709551615B"}}',
       "9.007199254740992e+15/1.8446744073709552e+19"},
      {~s'{{duration "1ns"}}/{{duration "100us"}}/{{duration "100000ns"}}/{{duration "-2.5s"}}',
       "1e-09/0.0001/0.0001/-2.5"},
      {~s'{{duration "1µs"}}/{{duration "1μs"}}/{{duration_seconds "1m0.1s"}}', "1e-06/1e-06/60.1"},
      {~s'{{duration "9223372036854775807ns"}}/{{duration "-9223372036854775808ns"}}',
       "9.223372036854776e+09/-9.223372036854776e+09"},
      {~s'{{if duration "0s"}}bad{{else}}zero{{end}}/{{not (bytes "0B")}}/{{duration "0s" | default "empty"}}',
       "zero/true/empty"},
      {~s'{{or (bytes "0B") (duration "2s")}}/{{and (duration "0s") (bytes "bad")}}', "2/0"},
      {~s'{{eq (duration "2s") (bytes "2B")}}/{{lt (duration "-1s") (bytes "0B")}}', "true/true"},
      {~s'{{int (duration "-2.9s")}}/{{add (duration "2.9s") 3}}/{{repeat (int (bytes "3B")) "x"}}', "-2/5/xxx"},
      {~s'{{int (bytes "9223372036854774784B")}}/{{int (duration "-9223372036854775808ns")}}',
       "9223372036854774784/-9223372036"},
      {~s'{{min (duration "-2.9s") 1}}/{{max (bytes "1.9B") 0}}', "-2/1"},
      {~s'{{or "safe" (duration "bad")}}/{{if false}}{{bytes "bad"}}{{else}}safe{{end}}', "safe/safe"}
    ]

    rows = Enum.map(original, fn {template, field, expected} -> {template, %{"foo" => field}, "1", expected} end)
    rows = rows ++ Enum.map(controls, fn {template, expected} -> {template, %{}, "original", expected} end)

    for {{template, fields, line, expected}, index} <- Enum.with_index(rows) do
      labels = Map.put(fields, "job", "quantity-format-#{index}")
      push(ctx, line, ctx.now, labels)

      for stage <- [:line, :label] do
        format = if stage == :line, do: "line_format ", else: "label_format out="
        expression = ~s/{job="quantity-format-#{index}"} | / <> format <> Pulse.JSON.encode!(template)
        params = [{"query", expression} | range(ctx)]
        response = request(ctx, "/query_range", params)
        result = if stage == :line, do: {labels, [expected]}, else: {Map.put(labels, "out", expected), [line]}
        assert_streams(response, [result])
        assert request_form(ctx, "/query_range", params) == response
      end
    end

    assert_metric(
      ctx,
      ~s'sum(bytes_over_time({job="quantity-format-0"} | line_format "{{duration `3ms`}}" [1m]))',
      1,
      %{
        %{} => [{1, "5"}]
      }
    )
  end

  @tag :template_quantities_batch
  test "quantity formatter failures preserve inputs and typed floats require explicit conversions", ctx do
    push(ctx, "original", ctx.now, %{"job" => "quantity-format-errors", "out" => "unchanged"})

    for template <- [
          ~s'{{bytes "bad"}}',
          ~s'{{bytes "-1B"}}',
          ~s'{{bytes "18446744073709551616B"}}',
          ~s'{{duration "1d"}}',
          ~s'{{duration "9223372036854775808ns"}}',
          ~s'{{duration_seconds .missing}}',
          "{{bytes}}",
          "{{duration 1}}",
          ~s'{{duration_seconds "1s" "2s"}}',
          ~s'{{upper (bytes "1B")}}',
          ~s'{{repeat (bytes "1B") "x"}}',
          ~s'{{len (duration "1s")}}',
          ~s'{{eq (duration "1s") 1}}',
          ~s'{{lt 1 (bytes "2B")}}',
          ~s'{{duration "1s" | bytes}}',
          ~s'{{add (duration "bad") 3}}',
          # Go's float-to-integer overflow is implementation-dependent. Reject
          # instead of choosing a CPU-specific value; plain rendering works.
          ~s'{{int (bytes "9223372036854775807B")}}',
          ~s'{{add (bytes "18446744073709551615B") 1}}'
        ],
        stage <- ["line_format ", "label_format out="] do
      expression = ~s/{job="quantity-format-errors"} | / <> stage <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      assert [%{"stream" => labels, "values" => [[_, "original"]]}] = response["data"]["result"]
      assert labels["out"] == "unchanged"
      assert labels["__error__"] == "TemplateFormatErr"
      assert request_form(ctx, "/query_range", params) == response
      params = [query: "bytes_over_time(#{expression} [1m])", time: to_string(ctx.now + @second)]
      assert request(ctx, "/query", params, 400)["message"] =~ "pipeline_error"
      assert request_form(ctx, "/query", params, 400)["message"] =~ "pipeline_error"

      assert_metric(ctx, ~s/sum by (job) (bytes_over_time(#{expression} | __error__!="" [1m]))/, 1, %{
        %{"job" => "quantity-format-errors"} => [{1, "8"}]
      })
    end
  end

  @tag :template_integer_math_batch
  test "Loki integer arithmetic formatter rows and coercion controls replay through HTTP", ctx do
    # Complete pinned fmt_test.go rows:235-243,262-270,289-297,594-599.
    original = [
      {"{{ add .foo 1 | sub .bar | mul .baz | div .bazz}}",
       %{"foo" => "1", "bar" => "3", "baz" => "10", "bazz" => "20"}, "2", [:line, :label]},
      {"min is {{ min .foo .bar .baz }} and max is {{ max .foo .bar .baz }}",
       %{"foo" => "5", "bar" => "10", "baz" => "15"}, "min is 5 and max is 15", [:line, :label]},
      {"mod is {{ mod .foo 3 }}", %{"foo" => "20"}, "mod is 2", [:line, :label]},
      {"{{div .status 100 }}", %{"status" => "200"}, "2", [{:label, "status"}]}
    ]

    controls = [
      {~s'{{int "010"}}/{{int "0x10"}}/{{int "0o10"}}/{{int "0b10"}}/{{int "1_000"}}', "8/16/8/2/1000"},
      {~s'{{int "2.9"}}/{{int "-2.9"}}/{{int "+.9"}}/{{int ".9"}}/{{int "1."}}', "2/-2/0/0/1"},
      {~s'{{int "010.9"}}/{{int "08.9"}}/{{int "0xA.0"}}', "8/0/0"},
      {~s'{{int "1e3"}}/{{int " 12"}}/{{int "12 "}}/{{int "NaN"}}/{{int .missing}}', "0/0/0/0/0"},
      {~s'{{int "9223372036854775808"}}/{{int "-9223372036854775809"}}', "0/0"},
      {~s'{{int "9223372036854775807.9"}}/{{int "-9223372036854775808.9"}}',
       "9223372036854775807/-9223372036854775808"},
      {~s'{{add 9223372036854775807 1}}/{{sub -9223372036854775808 1}}/{{mul 9223372036854775807 2}}',
       "-9223372036854775808/9223372036854775807/-2"},
      {~s'{{mul 9223372036854775807 9223372036854775807}}/{{add 9223372036854775807 9223372036854775807 2}}', "1/0"},
      {~s'{{div -9223372036854775808 -1}}/{{mod -9223372036854775808 -1}}', "-9223372036854775808/0"},
      {~s'{{div -7 3}}/{{div 7 -3}}/{{mod -7 3}}/{{mod 7 -3}}', "-2/-2/-1/1"},
      {~s'{{add}}/{{mul 3}}/{{min -7}}/{{max -7 -9 -2}}/{{min true 3 false}}', "0/3/-7/-2/0"},
      {~s'{{3 | sub 10}}/{{sub 9 2 | div 100}}/{{mod 20 3 | div 2}}', "7/14/1"},
      {~s'{{repeat (add 1 2) "x"}}/{{if eq (int "2.9") 2}}yes{{else}}bad{{end}}', "xxx/yes"},
      {~s'{{or "safe" (div 1 0)}}/{{and false (mod 1 0)}}', "safe/false"},
      {~s'{{int true}}/{{int false}}/{{add true 7 false}}/{{int "0009"}}/{{int "0x_10"}}/{{int "0_7"}}',
       "1/0/8/0/16/7"},
      {~s'{{add "bad" 7}}/{{mul "bad" 7}}/{{min "bad" 7}}/{{max "bad" -7}}', "7/0/0/0"}
    ]

    controls = Enum.map(controls, fn {template, expected} -> {template, %{}, expected, [:line, :label]} end)

    for {{template, fields, expected, stages}, index} <- Enum.with_index(original ++ controls) do
      labels = Map.put(fields, "job", "integer-math-#{index}")
      push(ctx, "original", ctx.now, labels)

      for stage <- stages do
        destination = if match?({:label, _}, stage), do: elem(stage, 1), else: "out"
        format = if stage == :line, do: "line_format ", else: "label_format #{destination}="
        expression = ~s/{job="integer-math-#{index}"} | / <> format <> Pulse.JSON.encode!(template)
        params = [{"query", expression} | range(ctx)]
        response = request(ctx, "/query_range", params)

        result =
          if stage == :line, do: {labels, [expected]}, else: {Map.put(labels, destination, expected), ["original"]}

        assert_streams(response, [result])
        assert request_form(ctx, "/query_range", params) == response
      end
    end

    assert_metric(ctx, ~s'sum(bytes_over_time({job="integer-math-0"} | line_format "{{div 99 10}}" [1m]))', 1, %{
      %{} => [{1, "1"}]
    })
  end

  @tag :template_integer_math_batch
  test "integer arithmetic runtime errors preserve inputs and unsupported math rejects before storage", ctx do
    push(ctx, "original", ctx.now, %{"job" => "integer-math-errors", "out" => "unchanged"})

    for template <- [
          "{{div 1 0}}",
          "{{mod 1 0}}",
          ~s'{{div 9 "bad"}}',
          "{{int}}",
          "{{int 1 2}}",
          "{{sub 1}}",
          "{{div 1}}",
          "{{mod 1 2 3}}",
          "{{mul}}",
          "{{min}}",
          "{{max}}",
          ~s'{{add 1 (substr 99 -1 "x")}}'
        ],
        stage <- ["line_format ", "label_format out="] do
      expression = ~s/{job="integer-math-errors"} | / <> stage <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      assert [%{"stream" => labels, "values" => [[_, "original"]]}] = response["data"]["result"]
      assert labels["out"] == "unchanged"
      assert labels["__error__"] == "TemplateFormatErr"
      assert request_form(ctx, "/query_range", params) == response
      params = [query: "bytes_over_time(#{expression} [1m])", time: to_string(ctx.now + @second)]
      assert request(ctx, "/query", params, 400)["message"] =~ "pipeline_error"
      assert request_form(ctx, "/query", params, 400)["message"] =~ "pipeline_error"

      assert_metric(ctx, ~s/sum by (job) (bytes_over_time(#{expression} | __error__!="" [1m]))/, 1, %{
        %{"job" => "integer-math-errors"} => [{1, "8"}]
      })
    end

    for template <- ["{{add1 2}}", "{{if false}}{{add1 2}}{{end}}"],
        stage <- ["line_format ", "label_format out="] do
      expression = ~s/{job="integer-math-errors"} |= "not present" | / <> stage <> Pulse.JSON.encode!(template)
      params = [query: expression, time: to_string(ctx.now)]
      before_reads = Agent.get(ctx.store, & &1.requests)
      response = request(ctx, "/query", params, 400)
      assert request_form(ctx, "/query", params, 400) == response
      assert Agent.get(ctx.store, & &1.requests) == before_reads
    end
  end

  @tag :template_whitespace_batch
  test "Go template comment and trim rows replay through Loki HTTP formatters", ctx do
    # Go 1.27.3 text/template/parse: parse_test.go:186-187,257-263,270-271;
    # lex_test.go:94-99,308-321. AST/token expectations become rendered strings.
    original = [
      {"{{/*\n\n\n*/}}", ""},
      {"x \r\n\t{{- 3}}", "x3"},
      {"{{3 -}}\n\n\ty", "3y"},
      {"x \r\n\t{{- 3 -}}\n\n\ty", "x3y"},
      {"x\n{{-  3   -}}\ny", "x3y"},
      {"x \r\n\t{{- /* hi */}}", "x"},
      {"{{/* hi */ -}}\n\n\ty", "y"},
      {"x \r\n\t{{- /* */ -}}\n\n\ty", "xy"},
      {"{{/*\nhello\n*/}}", ""},
      {"{{-\n/*\nhello\n*/\n-}}", ""},
      {"hello-{{/* this is a comment */}}-world", "hello--world"},
      {"hello- {{- 3 -}} -world", "hello-3-world"},
      {"hello- {{- /* hello */ -}} -world", "hello--world"}
    ]

    controls = [
      {"A \t\u00a0 \r{{- .foo -}}\n \u2003\t B", "A \t\u00a0BLIp\u2003\t B"},
      {"A\v\f {{- .foo -}} \v\fB", "A\v\fBLIp\v\fB"},
      {~s'{{" \t"}} \n{{- .foo -}}\n {{ "\r " }}', " \tBLIp\r "},
      {"A \t{{/*x*/}}{{- .foo}}", "A \tBLIp"},
      {"{{.foo -}}{{/*x*/}} \tB", "BLIp \tB"},
      {~s'{{"{{/* not comment */}}"}}', "{{/* not comment */}}"},
      {"{{` X -}} Y {{/*Z*/}} `}}", " X -}} Y {{/*Z*/}} "},
      {"X {{-3}} Y", "X -3 Y"},
      {"X \t{{- -3 -}}\r\nY", "X-3Y"},
      {"A{{/* {{nosuchfunc}} }} {{if}} */}}B", "AB"},
      {"A{{/* outer /* inner */}}B", "AB"},
      {"A \n{{- if false -}}\nno \t{{- else if .foo -}}\n yes \t{{- else -}} no {{- end -}} \n B", "AyesB"},
      {"{{if true}} kept {{else -}} skipped {{end}}", " kept "},
      {"{{if false}}{{/* {{nosuchfunc}} */}}{{else}}safe{{end}}", "safe"},
      {"prefix{{/**/}}{{/**/}}suffix", "prefixsuffix"},
      {"A \t{{- /**/ -}} \n B", "AB"}
    ]

    labels = %{"job" => "whitespace-format", "foo" => "BLIp"}
    push(ctx, "original", ctx.now, labels)

    for {template, expected} <- original ++ controls, stage <- [:line, :label] do
      format = if stage == :line, do: "line_format ", else: "label_format out="
      expression = ~s/{job="whitespace-format"} | / <> format <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      result = if stage == :line, do: {labels, [expected]}, else: {Map.put(labels, "out", expected), ["original"]}
      assert_streams(response, [result])
      assert request_form(ctx, "/query_range", params) == response
    end

    template = "x \n{{- .foo -}}\t y{{/* ignored */}}"
    expression = ~s/{job="whitespace-format"} | line_format / <> Pulse.JSON.encode!(template)
    assert_metric(ctx, "sum(bytes_over_time(#{expression} [1m]))", 1, %{%{} => [{1, "6"}]})
  end

  @tag :template_whitespace_batch
  test "malformed comments and trim delimiters reject before storage while trimmed actions preserve runtime errors",
       ctx do
    push(ctx, "original", ctx.now, %{"job" => "whitespace-error", "out" => "unchanged"})

    for template <- [
          # Original Go lexer rejection rows, lex_test.go:378-385.
          "hello-{{/*/}}-world",
          "hello-{{/* */ }}-world",
          "{{ /*comment*/}}",
          "{{\n/*comment*/}}",
          "{{-  /*comment*/}}",
          "{{/*x*/\t -}}",
          "{{/*x*/ - }}",
          "{{/* outer /* inner */ trailing */}}",
          "{{-}}",
          "{{- }}",
          "{{ -}}",
          ~s'{{"x"-}}',
          "{{-if true}}x{{end}}",
          "{{if true -}}x",
          "{{if false}}{{- nosuchfunc -}}{{end}}",
          "{{/* ignored */ -}} {{nosuchfunc}}"
        ],
        stage <- ["line_format ", "label_format out="] do
      expression = ~s/{job="whitespace-error"} |= "not present" | / <> stage <> Pulse.JSON.encode!(template)
      params = [query: expression, time: to_string(ctx.now)]
      before_reads = Agent.get(ctx.store, & &1.requests)
      response = request(ctx, "/query", params, 400)
      assert request_form(ctx, "/query", params, 400) == response
      assert Agent.get(ctx.store, & &1.requests) == before_reads
    end

    for stage <- ["line_format ", "label_format out="] do
      template = "{{/* {{nosuchfunc}} is inert */}}{{- substr 99 -1 .out -}}"
      expression = ~s/{job="whitespace-error"} | / <> stage <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      assert [%{"stream" => labels, "values" => [[_, "original"]]}] = response["data"]["result"]
      assert labels["out"] == "unchanged"
      assert labels["__error__"] == "TemplateFormatErr"
      assert request_form(ctx, "/query_range", params) == response
      params = [query: "bytes_over_time(#{expression} [1m])", time: to_string(ctx.now + @second)]
      assert request(ctx, "/query", params, 400)["message"] =~ "pipeline_error"
      assert request_form(ctx, "/query", params, 400)["message"] =~ "pipeline_error"

      assert_metric(ctx, ~s/sum by (job) (bytes_over_time(#{expression} | __error__!="" [1m]))/, 1, %{
        %{"job" => "whitespace-error"} => [{1, "8"}]
      })
    end
  end

  @tag :template_conditionals_batch
  test "Loki conditional formatter rows and lazy boolean controls replay through HTTP", ctx do
    # Complete fmt_test.go:160-186 at the pinned Loki revision.
    original = [
      {~s'{{ if  .foo | contains "p"}}yes{{end}}-{{ if  .foo | contains "z"}}no{{end}}', "yes-"},
      {~s'{{ if  .foo | hasPrefix "BL" }}yes{{end}}-{{ if  .foo | hasPrefix "p"}}no{{end}}', "yes-"},
      {~s'{{ if  .foo | hasSuffix "Ip" }}yes{{end}}-{{ if  .foo | hasSuffix "pw"}}no{{end}}', "yes-"}
    ]

    controls = [
      {~s'前{{if .foo}}T{{if false}}bad{{else}}F{{end}}{{else}}bad{{end}}後', "前TF後"},
      {~s'{{if .missing}}bad{{else if false}}bad{{else if .foo}}yes{{else}}bad{{end}}', "yes"},
      {~s'{{if false}}bad{{else if 0}}bad{{else if ""}}bad{{else}}empty{{end}}', "empty"},
      {~s'{{if -9223372036854775808}}negative{{end}}/{{if "0"}}string{{end}}/{{if " "}}space{{end}}',
       "negative/string/space"},
      {~s'{{not true}} {{not false}}/{{and false 0}} {{and 1 0}} {{and 0 true}} {{and 1 1}}', "false true/false 0 0 1"},
      {~s'{{or 0 0}} {{or 1 0}} {{or 0 true}} {{or 1 1}}/{{1 | and 1}}/{{0 | and 1}}/{{1 | or 0}}/{{0 | or 0}}',
       "0 1 true 1/1/0/1/0"},
      {~s'{{and false (substr 99 -1 "x")}}/{{or "safe" (substr 99 -1 "x")}}', "false/safe"},
      {~s'{{"tail" | and false (substr 99 -1 "x")}}/{{"tail" | or "safe" (substr 99 -1 "x")}}', "false/safe"},
      {~s'{{eq 3 4 5 3}}/{{eq "x" "x" 1}}/{{ne false true}}/{{eq .missing ""}}', "true/true/true/true"},
      {~s'{{lt "10" "2"}}/{{lt 10 2}}/{{le 2 2}}/{{gt "é" "z"}}/{{ge -3 -2}}', "true/false/true/true/false"},
      {~s'{{if and (hasPrefix "BL" .foo) (not (hasSuffix "z" .foo))}}yes{{end}}', "yes"},
      {~s'{{if eq .foo "BLIp"}}yes{{else}}no{{end}}/{{"é́😀" | len}}/{{len .missing}}', "yes/8/0"},
      {~s'{{if false}}{{repeat 16777217 "x"}}{{else}}safe{{end}}', "safe"},
      {~s'{{or "safe" (repeat 16777217 "x")}}/{{and false (repeat 16777217 "x")}}', "safe/false"},
      {String.duplicate("{{if true}}", 64) <> "deep" <> String.duplicate("{{end}}", 64), "deep"},
      {String.duplicate("{{if true}}", 63) <> "{{(upper .foo)}}" <> String.duplicate("{{end}}", 63), "BLIP"},
      {"{{if false}}bad" <> String.duplicate("{{else if false}}bad", 63) <> "{{else}}last{{end}}", "last"}
    ]

    labels = %{"job" => "conditional-format", "foo" => "BLIp", "bar" => "blop"}
    push(ctx, "original", ctx.now, labels)

    for {template, expected} <- original ++ controls, stage <- [:line, :label] do
      format = if stage == :line, do: "line_format ", else: "label_format out="
      expression = ~s/{job="conditional-format"} | / <> format <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      result = if stage == :line, do: {labels, [expected]}, else: {Map.put(labels, "out", expected), ["original"]}
      assert_streams(response, [result])
      assert request_form(ctx, "/query_range", params) == response
    end

    assert_metric(
      ctx,
      ~s'sum(bytes_over_time({job="conditional-format"} | line_format "{{if .foo}}yes{{else}}no{{end}}" [1m]))',
      1,
      %{
        %{} => [{1, "3"}]
      }
    )
  end

  @tag :template_conditionals_batch
  test "conditional admission checks all branches while only selected runtime failures affect entries", ctx do
    push(ctx, "original", ctx.now, %{"job" => "conditional-error", "out" => "unchanged"})

    for template <- [
          ~s'{{if true}}partial{{substr 99 -1 "x"}}{{else}}safe{{end}}',
          ~s'{{if false}}safe{{else if substr 99 -1 "x"}}bad{{end}}',
          ~s'{{and true (substr 99 -1 "x")}}',
          ~s'{{or false (substr 99 -1 "x")}}',
          ~s'{{substr 99 -1 "x" | or "safe"}}',
          ~s'{{eq "x" "x" (substr 99 -1 "x")}}',
          ~s'{{eq 1 "1"}}',
          ~s'{{lt true false}}',
          ~s'{{len 1}}',
          "{{and}}",
          "{{or}}",
          "{{eq 1}}",
          "{{ne 1 1 1}}"
        ],
        stage <- ["line_format ", "label_format out="] do
      expression = ~s/{job="conditional-error"} | / <> stage <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      assert [%{"stream" => labels, "values" => [[_, "original"]]}] = response["data"]["result"]
      assert labels["out"] == "unchanged"
      assert labels["__error__"] == "TemplateFormatErr"
      assert request_form(ctx, "/query_range", params) == response
      params = [query: "bytes_over_time(#{expression} [1m])", time: to_string(ctx.now + @second)]
      assert request(ctx, "/query", params, 400)["message"] =~ "pipeline_error"
      assert request_form(ctx, "/query", params, 400)["message"] =~ "pipeline_error"

      assert_metric(ctx, ~s/sum by (job) (bytes_over_time(#{expression} | __error__!="" [1m]))/, 1, %{
        %{"job" => "conditional-error"} => [{1, "8"}]
      })
    end

    for template <- [
          "{{if true}}missing end",
          "{{if}}{{end}}",
          "{{else}}",
          "{{end}}",
          "{{if true}}{{else}}{{else}}{{end}}",
          "{{if true}}{{else 1}}{{end}}",
          "{{if true}}{{end 1}}",
          "{{if false}}{{nosuchfunc}}{{end}}",
          "{{or true (nosuchfunc)}}",
          "{{if false}}{{range}}x{{end}}{{end}}",
          String.duplicate("{{if false}}", 65) <> "x" <> String.duplicate("{{end}}", 65),
          String.duplicate("{{if true}}", 64) <> "{{(upper .foo)}}" <> String.duplicate("{{end}}", 64),
          "{{if true}}x" <> String.duplicate("{{else if false}}x", 64) <> "{{end}}"
        ],
        stage <- ["line_format ", "label_format out="] do
      expression = ~s/{job="conditional-error"} |= "not present" | / <> stage <> Pulse.JSON.encode!(template)
      params = [query: expression, time: to_string(ctx.now)]
      before_reads = Agent.get(ctx.store, & &1.requests)
      response = request(ctx, "/query", params, 400)
      assert request_form(ctx, "/query", params, 400) == response
      assert Agent.get(ctx.store, & &1.requests) == before_reads
    end
  end

  @tag :template_decode_slice_batch
  test "Loki Base64 decoding and public byte-slicing formatter rows replay through HTTP", ctx do
    # Complete fmt_test.go rows 84-94, 455-472 and 712-727.
    # Public trunc/substr use Sprig, not Loki's unused rune-based helpers.
    original = [
      {~s'{{.foo | substr 1 3 }} {{ .bar  | trunc 1 }} {{ .bar  | trunc 3 }}', %{"foo" => "blip", "bar" => "blop"}, "",
       "li b blo", [:line, :label]},
      {"{{ .foo | b64dec }}", %{"foo" => "aSdtIGEgc3RyaW5nLCBlbmNvZGUgbWUh"}, "1", "i'm a string, encode me!",
       [:line, :label]},
      {"{{ .foo | b64dec }} {{ .bar | b64dec }}", %{"foo" => "Zm9vYmE", "bar" => "Zm9vYg"}, "1", "fooba foob",
       [:line, :label]},
      {"{{ .foo | b64dec }}", %{"foo" => "aSdtIGEgc3RyaW5nLCBlbmNvZGUgbWUh", "bar" => "blop"}, "test line",
       "i'm a string, encode me!", [:label]},
      {"{{ .foo | b64dec }}", %{"foo" => "Zm9vYmE", "bar" => "blop"}, "test line", "fooba", [:label]}
    ]

    controls = [
      {~s'{{trunc 2 .foo}}/{{trunc -2 .foo}}/{{trunc -6 .foo}}/{{trunc -9223372036854775808 .foo}}', %{"foo" => "é😀xy"},
       "", "é/xy/😀xy/é😀xy", [:line, :label]},
      {~s'{{substr 2 6 .foo}}/{{substr 2 -1 .foo}}/{{substr -1 2 .foo}}/{{substr 8 -1 .foo}}', %{"foo" => "é😀xy"}, "",
       "😀/😀xy/é/", [:line, :label]},
      {~s'{{trunc 0 .foo}}/{{trunc -3 .foo}}/{{substr 0 999 .foo}}/{{substr -1 0 .foo}}', %{"foo" => "abc"}, "",
       "/abc/abc/", [:line, :label]},
      {~s'{{.foo | b64enc | b64dec}}/{{b64dec .missing}}', %{"foo" => "é́😀"}, "", "é́😀/", [:line, :label]},
      {~s'{{b64dec "AA=="}}/{{b64dec "Zh=="}}/{{b64dec "Zm9="}}', %{}, "", "\0/f/fo", [:line, :label]},
      {~S'{{b64dec "Zg=\n="}}/{{b64dec "Zg==\n"}}/{{b64dec "Zg\n=="}}', %{}, "", "f/f/f", [:line, :label]},
      {~s'{{b64dec "Zg=" | upper}}/{{substr 0 2 (b64dec "w6k=") | default "empty"}}', %{}, "", "F/é", [:line, :label]}
    ]

    # Frozen actual pinned pipeline probes: invalid Base64 is ordinary text,
    # not TemplateFormatErr. Padding uses original byte length before CR/LF removal.
    corrupt = [
      {"Zg\n", "illegal base64 data at input byte 4"},
      {"Zg\r\n==", "illegal base64 data at input byte 6"},
      {"Zg===", "illegal base64 data at input byte 4"},
      {"Zg=Z", "illegal base64 data at input byte 2"},
      {"Z", "illegal base64 data at input byte 0"},
      {"=", "illegal base64 data at input byte 0"},
      {"Z g==", "illegal base64 data at input byte 1"},
      {"Zg\t==", "illegal base64 data at input byte 2"},
      {"Z\n", "illegal base64 data at input byte 2"},
      {"Zm9v\r\n", "illegal base64 data at input byte 6"},
      {"é", "illegal base64 data at input byte 0"},
      {"Zg-_", "illegal base64 data at input byte 2"},
      {"/w===", "illegal base64 data at input byte 4"}
    ]

    controls =
      controls ++
        for({input, expected} <- corrupt, do: {"{{b64dec .foo}}", %{"foo" => input}, "", expected, [:line, :label]})

    cases =
      for {{template, labels, line, expected, stages}, index} <- Enum.with_index(original ++ controls),
          do: {template, Map.put(labels, "job", "decode-slice-#{index}"), line, expected, stages}

    push_streams(
      ctx,
      for({_, labels, line, _, _} <- cases, do: %{"stream" => labels, "values" => [[to_string(ctx.now), line]]})
    )

    for {template, labels, line, expected, stages} <- cases, stage <- stages do
      format = if stage == :line, do: "line_format ", else: "label_format bar="
      expression = ~s/{job="#{labels["job"]}"} | / <> format <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      result = if stage == :line, do: {labels, [expected]}, else: {Map.put(labels, "bar", expected), [line]}
      assert_streams(response, [result])
      assert request_form(ctx, "/query_range", params) == response
    end

    assert_metric(ctx, ~s'sum(bytes_over_time({job="decode-slice-1"} | line_format "{{b64dec .foo}}" [1m]))', 1, %{
      %{} => [{1, "24"}]
    })
  end

  @tag :template_decode_slice_batch
  test "slice bounds types and non-UTF-8 results preserve inputs and metric error policy", ctx do
    push(ctx, "original", ctx.now, %{"job" => "decode-slice-error", "out" => "unchanged", "foo" => "é"})

    for template <- [
          "{{substr 3 -1 .foo}}",
          "{{substr -1 -1 .foo}}",
          "{{substr -1 3 .foo}}",
          "{{substr 2 1 .foo}}",
          ~s'{{substr "0" 1 .foo}}',
          "{{trunc true .foo}}",
          "{{b64dec false}}",
          "{{substr 0 .foo}}",
          "{{b64dec}}",
          # Deliberately stricter until downstream byte strings are supported.
          "{{trunc 1 .foo}}",
          "{{substr 0 1 .foo}}",
          ~s'{{b64dec "/w=="}}',
          ~s'{{trunc 1 .foo | b64enc}}'
        ],
        stage <- ["line_format ", "label_format out="] do
      expression = ~s/{job="decode-slice-error"} | / <> stage <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      assert [%{"stream" => labels, "values" => [[_, "original"]]}] = response["data"]["result"]
      assert labels["out"] == "unchanged"
      assert labels["__error__"] == "TemplateFormatErr"
      assert labels["__error_details__"] != ""
      assert request_form(ctx, "/query_range", params) == response

      params = [query: "bytes_over_time(#{expression} [1m])", time: to_string(ctx.now + @second)]
      assert request(ctx, "/query", params, 400)["message"] =~ "pipeline_error"
      assert request_form(ctx, "/query", params, 400)["message"] =~ "pipeline_error"

      assert_metric(ctx, ~s/sum by (job) (bytes_over_time(#{expression} | __error__!="" [1m]))/, 1, %{
        %{"job" => "decode-slice-error"} => [{1, "8"}]
      })

      assert_metric(ctx, ~s/bytes_over_time(#{expression} | __error__="" [1m])/, 1, %{})
    end
  end

  @tag :template_integer_functions_batch
  test "Loki counted replacement repetition indentation and alignment rows replay through HTTP", ctx do
    # Complete fmt_test.go rows 57-65, 133-159 and 473-490 at the pinned revision.
    # Nil unit inputs become empty lines; unique jobs isolate the original rows.
    original = [
      {~s'foo{{.foo}}buzz{{ Replace .bar "blop" "bar" -1 }}', %{"foo" => "blip", "bar" => "blop"}, "",
       "fooblipbuzzbar"},
      {~s'{{ "foo" | repeat 3 }}', %{"foo" => "BLIp", "bar" => "blop"}, "", "foofoofoo"},
      {~S'{{ "foo\n bar" | indent 4 }}', %{"foo" => "BLIp", "bar" => "blop"}, "", "    foo\n     bar"},
      {~s'{{ "foo" | nindent 2 }}', %{"foo" => "BLIp", "bar" => "blop"}, "", "\n  foo"},
      {"{{ alignLeft 4 .foo }}", %{"foo" => "hello"}, "1", "hell"},
      {"{{ alignRight 4 .foo }}", %{"foo" => "hello"}, "1", "ello"}
    ]

    controls = [
      {~s'{{alignLeft 3 .foo}}/{{alignRight 3 .foo}}/{{alignLeft 7 .foo}}/{{alignRight 7 .foo}}', %{"foo" => "é́😀xy"},
       "", "é́😀/😀xy/é́😀xy  /  é́😀xy"},
      {~s'{{alignLeft -1 .foo}}/{{alignRight -9223372036854775808 .foo}}/{{alignLeft 0 .foo}}/{{alignRight 5 .foo}}',
       %{"foo" => "é́😀xy"}, "", "é́😀xy/é́😀xy//é́😀xy"},
      {~s'{{repeat 0 .foo}}/{{repeat 3 .foo}}/{{repeat 9223372036854775807 .missing}}', %{"foo" => "é"}, "", "/ééé/"},
      {~S'{{__line__ | indent 2}}', %{}, "a\r\nb\n", "  a\r\n  b\n  "},
      {~s'{{indent 2 .missing}}/{{nindent 0 .missing}}', %{}, "", "  /\n"},
      {~s'{{Replace .foo "" "-" 2}}/{{Replace .foo "" "-" -1}}/{{Replace .foo "" "-" 0}}', %{"foo" => "é́😀"}, "",
       "-é-́😀/-é-́-😀-/é́😀"},
      {~s'{{Replace .foo "aa" "$1" 1}}/{{Replace .foo "aa" "$1" -1}}/{{Replace .foo "aa" "$1" 0}}', %{"foo" => "aaaaa"},
       "", "$1aaa/$1$1a/aaaaa"},
      {~s'{{repeat +0x_2 .foo}}/{{repeat 0b10 .foo}}/{{repeat 0o2 .foo}}/{{repeat 02 .foo}}/{{repeat 0_2 .foo}}',
       %{"foo" => "é"}, "", "éé/éé/éé/éé/éé"},
      {~s'{{0 | default "fallback"}}/{{-0x8000000000000000}}/{{0x7fff_ffff_ffff_ffff}}/{{1_234}}', %{}, "",
       "fallback/-9223372036854775808/9223372036854775807/1234"}
    ]

    cases =
      for {{template, labels, line, expected}, index} <- Enum.with_index(original ++ controls),
          do: {template, Map.put(labels, "job", "integer-formatter-#{index}"), line, expected}

    push_streams(
      ctx,
      for({_, labels, line, _} <- cases, do: %{"stream" => labels, "values" => [[to_string(ctx.now), line]]})
    )

    for {template, labels, line, expected} <- cases, stage <- [:line, :label] do
      format = if stage == :line, do: "line_format ", else: "label_format out="
      expression = ~s/{job="#{labels["job"]}"} | / <> format <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      result = if stage == :line, do: {labels, [expected]}, else: {Map.put(labels, "out", expected), [line]}
      assert_streams(response, [result])
      assert request_form(ctx, "/query_range", params) == response
    end

    assert_metric(
      ctx,
      ~s'sum(bytes_over_time({job="integer-formatter-1"} | line_format "{{repeat 3 `foo`}}" [1m]))',
      1,
      %{
        %{} => [{1, "9"}]
      }
    )
  end

  @tag :template_integer_functions_batch
  @tag :template_runes_batch
  @tag :template_floats_batch
  test "integer formatter failures preserve inputs while invalid literals reject before storage", ctx do
    push(ctx, "original", ctx.now, %{"job" => "integer-formatter-error", "out" => "unchanged", "count" => "2"})

    for template <- [
          ~s'{{repeat -1 .missing}}',
          ~s'{{indent -1 .out}}',
          ~s'{{nindent -1 .missing}}',
          ~s'{{repeat .count .out}}',
          ~s'{{indent "2" .out}}',
          ~s'{{alignLeft true .out}}',
          ~s'{{alignRight 2 false}}',
          ~s'{{Replace .out "a" "b" .count}}',
          ~s'{{Replace 2 "a" "b" -1}}',
          ~s'{{repeat 2}}',
          ~s'{{upper 2}}'
        ],
        stage <- ["line_format ", "label_format out="] do
      expression = ~s/{job="integer-formatter-error"} | / <> stage <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      assert [%{"stream" => labels, "values" => [[_, "original"]]}] = response["data"]["result"]
      assert labels["out"] == "unchanged"
      assert labels["__error__"] == "TemplateFormatErr"
      assert labels["__error_details__"] != ""
      assert request_form(ctx, "/query_range", params) == response

      params = [query: "bytes_over_time(#{expression} [1m])", time: to_string(ctx.now + @second)]
      assert request(ctx, "/query", params, 400)["message"] =~ "pipeline_error"
      assert request_form(ctx, "/query", params, 400)["message"] =~ "pipeline_error"

      assert_metric(ctx, ~s/sum by (job) (bytes_over_time(#{expression} | __error__!="" [1m]))/, 1, %{
        %{"job" => "integer-formatter-error"} => [{1, "8"}]
      })

      assert_metric(ctx, ~s/bytes_over_time(#{expression} | __error__="" [1m])/, 1, %{})
    end

    for literal <- [
          "9223372036854775808",
          "-9223372036854775809",
          "0x8000000000000000",
          "0x",
          "08",
          "1__0",
          "2_",
          "0b2"
        ] do
      for stage <- ["line_format ", "label_format out="] do
        template = "{{repeat #{literal} .out}}"
        expression = ~s/{job="integer-formatter-error"} |= "absent" | / <> stage <> Pulse.JSON.encode!(template)
        params = [query: expression, time: to_string(ctx.now + @second)]
        reads = Agent.get(ctx.store, & &1.requests)
        response = request(ctx, "/query", params, 400)
        assert request_form(ctx, "/query", params, 400) == response
        assert Agent.get(ctx.store, & &1.requests) == reads
      end
    end
  end

  @tag :template_string_transforms_batch
  test "Loki replacement trimming title and encoding formatter rows replay through HTTP", ctx do
    # Complete fmt_test.go rows: replace, title, trim, urlencode, urldecode,
    # base64encode (line), base64encode (label). The label error row is below.
    url =
      ~s'/loki/api/v1/query?query=sum(count_over_time({stream_filter="some_stream",environment="prod", host=~"someec2.*"}'

    escaped =
      "%2Floki%2Fapi%2Fv1%2Fquery%3Fquery%3Dsum%28count_over_time%28%7Bstream_filter%3D%22some_stream%22%2Cenvironment%3D%22prod%22%2C+host%3D~%22someec2.%2A%22%7D"

    original = [
      {~s'foo{{.foo}}buzz{{ .bar | replace "blop" "bar" }}', %{"foo" => "blip", "bar" => "blop"}, "", "fooblipbuzzbar",
       [:line, :label]},
      {"{{.foo | title }}", %{"foo" => "blip", "bar" => "blop"}, "", "Blip", [:line, :label]},
      {~s'{{.foo | trim }} {{ .bar  | trimAll "op" }} {{ .bar  | trimPrefix "b" }} {{ .bar  | trimSuffix "p" }}',
       %{"foo" => "  blip ", "bar" => "blop"}, "", "blip bl lop blo", [:line, :label]},
      {"{{.foo | urlencode }} {{ urlencode .foo }}", %{"foo" => url}, "", escaped <> " " <> escaped, [:line, :label]},
      {"{{.foo | urldecode }} {{ urldecode .foo }}", %{"foo" => escaped}, "", url <> " " <> url, [:line, :label]},
      {"{{ .foo | b64enc }}", %{"foo" => "i'm a string, encode me!"}, "1", "aSdtIGEgc3RyaW5nLCBlbmNvZGUgbWUh",
       [:line, :label]},
      {"{{ .foo | b64enc }}", %{"foo" => "i'm a string, encode me!", "bar" => "blop"}, "test line",
       "aSdtIGEgc3RyaW5nLCBlbmNvZGUgbWUh", [:label]}
    ]

    # Independent controls distinguish Unicode scalar/cutset behavior from
    # Elixir's grapheme/subsequence operations, and query from path escaping.
    controls = [
      {~s'{{trimAll "ab" .foo}}/{{Trim .foo "ab"}}/{{TrimLeft .foo "ab"}}/{{TrimRight .foo "ab"}}',
       %{"foo" => "abbacXcbaab"}, "", "cXc/cXc/cXcbaab/abbacXc", [:line, :label]},
      {~s'{{trimAll "é́" .foo}}/{{trimAll "" .foo}}', %{"foo" => "́éXé́"}, "", "X/́éXé́", [:line, :label]},
      {~s'{{replace "" "-" .foo}}', %{"foo" => "é́😀"}, "", "-é-́-😀-", [:line, :label]},
      {~S'{{replace "aba" "$1\\x" .foo}}', %{"foo" => "ababa"}, "", "$1\\xba", [:line, :label]},
      {~s'{{replace "" "." .missing}}/{{replace "" "" .foo}}', %{"foo" => "é́"}, "", "./é́", [:line, :label]},
      {"{{.foo | title}}", %{"foo" => "hello-world foo_bar 9foo foo/bar foo’bar foo bar foo​bar ᾀ ß é́x"}, "",
       "Hello-World Foo_bar 9foo Foo/Bar Foo’bar Foo Bar Foo​bar ᾈ ß É́x", [:line, :label]},
      {"{{.foo | urlencode}}", %{"foo" => "a +/~!*é"}, "", "a+%2B%2F~%21%2A%C3%A9", [:line, :label]},
      {~s'{{urldecode "%c3%a9+%2b"}}/{{.foo | urlencode | urldecode}}', %{"foo" => " +é/"}, "", "é +/ +é/",
       [:line, :label]},
      {"{{b64enc .foo}}/{{.missing | b64enc}}", %{"foo" => "é"}, "", "w6k=/", [:line, :label]}
    ]

    cases =
      for {{template, labels, line, expected, stages}, index} <- Enum.with_index(original ++ controls) do
        {template, Map.put(labels, "job", "string-transform-#{index}"), line, expected, stages}
      end

    streams = for {_, labels, line, _, _} <- cases, do: %{"stream" => labels, "values" => [[to_string(ctx.now), line]]}
    push_streams(ctx, streams)

    for {template, labels, line, expected, stages} <- cases, stage <- stages do
      format = if stage == :line, do: "line_format ", else: "label_format bar="
      expression = ~s/{job="#{labels["job"]}"} | / <> format <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      result = if stage == :line, do: {labels, [expected]}, else: {Map.put(labels, "bar", expected), [line]}
      assert_streams(response, [result])
      assert request_form(ctx, "/query_range", params) == response
    end
  end

  @tag :template_string_transforms_batch
  test "replacement arity and URL failures preserve inputs and metric error policy", ctx do
    # Complete label formatter template-error row, fmt_test.go:608-617.
    push(ctx, "test line", ctx.now, %{"job" => "string-transform-error", "foo" => "blip", "bar" => "blop"})

    for template <-
          [~s'{{replace "test" .foo}}', ~s'{{replace "a" "b" true}}', ~s'{{trimAll true .foo}}'] ++
            Enum.map(["%", "%1", "%gg", "ok%20bad%2z", "%FF"], &("{{urldecode " <> Pulse.JSON.encode!(&1) <> "}}")),
        stage <- ["line_format ", "label_format bar="] do
      expression = ~s/{job="string-transform-error"} | / <> stage <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      assert [%{"stream" => labels, "values" => [[_, "test line"]]}] = response["data"]["result"]

      assert Map.drop(labels, ["__error__", "__error_details__"]) ==
               %{"job" => "string-transform-error", "foo" => "blip", "bar" => "blop"}

      assert labels["__error__"] == "TemplateFormatErr"
      assert labels["__error_details__"] != ""
      assert request_form(ctx, "/query_range", params) == response

      metric = "bytes_over_time(#{expression} [1m])"
      params = [query: metric, time: to_string(ctx.now + @second)]
      assert request(ctx, "/query", params, 400)["message"] =~ "pipeline_error"
      assert request_form(ctx, "/query", params, 400)["message"] =~ "pipeline_error"

      assert_metric(ctx, ~s/sum by (job) (bytes_over_time(#{expression} | __error__!="" [1m]))/, 1, %{
        %{"job" => "string-transform-error"} => [{1, "9"}]
      })

      assert_metric(ctx, ~s/bytes_over_time(#{expression} | __error__="" [1m])/, 1, %{})
    end
  end

  @tag :template_functions_batch
  test "Loki line formatter interpolates labels and runs case functions before filtering", ctx do
    ctx = %{ctx | now: ctx.now - 240 * @second}

    # formatters.logqltest:1-29, complete first eight evaluations. The three
    # now() runtime-error evaluations at 33-39 remain outside this string batch.
    for {level, first, count} <- [{"error", 20, 4}, {"warn", 30, 2}], i <- 0..(count - 1) do
      push(ctx, "x", ctx.now + (first + i * 20) * @second, %{"app" => "a", "level" => level})
    end

    # HTTP ingestion additionally promotes a stream level, unlike the engine fixture.
    error = %{"app" => "a", "level" => "error", "detected_level" => "error"}
    query = ~s/count_over_time({app="a"} | line_format "L={{.level}}" |= "L=error" [1m])/
    assert_metric(ctx, query, 60, %{error => [{60, "3"}]})
    assert_metric(ctx, query, {40, 80, 20}, %{error => [{40, "2"}, {60, "3"}, {80, "3"}]})
    assert_metric(ctx, query, {60, 180, 120}, %{error => [{60, "3"}]})
    assert_metric(ctx, ~s/count_over_time({app="a"} |= "L=error" [1m])/, 60, %{})

    assert_metric(ctx, ~s/count_over_time({app="a"} | line_format "{{.level | upper}}" |= "ERROR" [1m])/, 60, %{
      error => [{60, "3"}]
    })

    assert_metric(ctx, ~s/bytes_over_time({app="a", level="error"} | line_format "{{.level}}" [1m])/, 60, %{
      error => [{60, "15"}]
    })

    assert_metric(ctx, ~s/bytes_over_time({app="a", level="error"} | line_format "V={{.missing}}" [1m])/, 60, %{
      error => [{60, "6"}]
    })

    params = [query: ~s/bytes_over_time({app="a"} | line_format "{{ nosuchfunc }}" [1m])/, time: to_string(ctx.now)]
    reads = Agent.get(ctx.store, & &1.requests)
    response = request(ctx, "/query", params, 400)
    assert inspect(response) =~ "not defined"
    assert request_form(ctx, "/query", params, 400) == response
    assert Agent.get(ctx.store, & &1.requests) == reads
  end

  @tag :template_functions_batch
  test "Loki formatter reads metadata and validates label templates", ctx do
    ctx = %{ctx | now: ctx.now - 240 * @second}

    # Complete metadata block, formatters.logqltest:41-54.
    for {level, first, count} <- [{"error", 20, 4}, {"warn", 30, 2}], i <- 0..(count - 1) do
      push(ctx, "x", ctx.now + (first + i * 20) * @second, %{"app" => "a"}, %{"level" => level})
    end

    error = %{"app" => "a", "level" => "error"}
    query = ~s/count_over_time({app="a"} | line_format "L={{.level}}" |= "L=error" [1m])/
    assert_metric(ctx, query, 60, %{error => [{60, "3"}]})
    assert_metric(ctx, query, {40, 80, 20}, %{error => [{40, "2"}, {60, "3"}, {80, "3"}]})
    assert_metric(ctx, query, {60, 180, 120}, %{error => [{60, "3"}]})

    assert_metric(ctx, ~s/bytes_over_time({app="a"} | level="error" | line_format "{{.level}}" [1m])/, 60, %{
      error => [{60, "15"}]
    })

    # Complete assignment block, formatters.logqltest:56-83, including noise.
    for {stream, metadata, first, count} <- [
          {%{"app" => "b", "method" => "get"}, %{}, 20, 4},
          {%{"app" => "b"}, %{"method" => "post"}, 30, 2},
          {%{"app" => "noise"}, %{}, 30, 2}
        ],
        i <- 0..(count - 1) do
      push(ctx, "msg", ctx.now + (first + i * 20) * @second, stream, metadata)
    end

    query = ~s/count_over_time({app="b"} | label_format verb=method [1m])/
    get = %{"app" => "b", "verb" => "get"}
    post = %{"app" => "b", "verb" => "post"}
    assert_metric(ctx, query, 60, %{get => [{60, "3"}], post => [{60, "2"}]})

    assert_metric(ctx, query, {40, 80, 20}, %{
      get => [{40, "2"}, {60, "3"}, {80, "3"}],
      post => [{40, "1"}, {60, "2"}, {80, "2"}]
    })

    assert_metric(ctx, query, {60, 180, 120}, %{get => [{60, "3"}], post => [{60, "2"}]})

    for {assignment, key, suffix} <- [
          {~s/route="{{.method}}-ok"/, "route", "-ok"},
          {~s/method="{{.method}}!"/, "method", "!"}
        ] do
      expected =
        for {method, value} <- [{"get", "3"}, {"post", "2"}], into: %{} do
          {%{"app" => "b", "method" => method} |> Map.put(key, method <> suffix), [{60, value}]}
        end

      assert_metric(ctx, ~s/count_over_time({app="b"} | label_format #{assignment} [1m])/, 60, expected)
    end

    params = [query: ~s/count_over_time({app="b"} | label_format x="{{" [1m])/, time: to_string(ctx.now)]
    reads = Agent.get(ctx.store, & &1.requests)
    response = request(ctx, "/query", params, 400)
    assert inspect(response) =~ "unclosed action"
    assert request_form(ctx, "/query", params, 400) == response
    assert Agent.get(ctx.store, & &1.requests) == reads
  end

  @tag :template_functions_batch
  test "Loki string template functions preserve lines labels and Go Unicode casing", ctx do
    # Six complete line-formatter rows: combining, lower and upper, missing,
    # function, line, default. fmt_test.go:48-56,106-114,217-234,334-351.
    original = [
      {"foo{{.foo}}buzz{{  .bar  }}", %{"foo" => "blip", "bar" => "blop"}, "", "fooblipbuzzblop"},
      {"{{.foo | lower }} {{ .bar | upper }}", %{"foo" => "BLIp", "bar" => "blop"}, "", "blip BLOP"},
      {"foo {{.foo}}buzz{{  .bar  }}", %{"bar" => "blop"}, "", "foo buzzblop"},
      {"foo {{.foo | ToUpper }} buzz{{  .bar  }}", %{"foo" => "blip", "bar" => "blop"}, "", "foo BLIP buzzblop"},
      {"{{ __line__ }} bar {{ .bar }}", %{"bar" => "2"}, "1", "1 bar 2"},
      {~s/{{.foo | default "-" }}{{.bar | default "-"}}{{.unknown | default "-"}}/, %{"foo" => "blip", "bar" => ""}, "",
       "blip--"}
    ]

    # Independently checked against the actual pinned pipeline; these are
    # controls, not additional original upstream rows.
    controls = [
      {~s/é{{upper .foo}}✓{{lower .bar}}/, %{"foo" => "ßᾀıﬃ", "bar" => "İΣẞ"}, "", "éßᾈIﬃ✓iσß"},
      {~s/{{.foo | trim | upper | trimPrefix "PRE-" | trimSuffix "-END"}}/, %{"foo" => "\u0085 pre-Mid-end\u2003"}, "",
       "MID"},
      {~s'{{TrimSpace .foo}}/{{TrimPrefix .bar "pre-"}}/{{TrimSuffix .bar "-end"}}',
       %{"foo" => "\u00a0 x \t", "bar" => "pre-mid-end"}, "", "x/mid-end/pre-mid"},
      {~s'{{.foo | contains "mid"}}/{{.foo | hasPrefix "mid"}}/{{.foo | hasSuffix "end"}}', %{"foo" => "pre-mid-end"},
       "", "true/false/true"},
      {~s/{{upper (trim (.missing | default " fallback "))}}/, %{}, "", "FALLBACK"},
      {~S'{{"a|}}b" | upper}}/{{"\x41\101\u00e9\U0001f600"}}', %{}, "", "A|}}B/AAé😀"},
      {"{{`a\rb`}}/{{\"a\rb\"}}", %{}, "", "ab/a\rb"},
      {~S'{{upper "\xc3\xa9"}}/{{lower "\xc3\x89"}}', %{}, "", "É/é"},
      {"{{" <> String.duplicate("(", 64) <> ".foo" <> String.duplicate(")", 64) <> "}}", %{"foo" => "deep"}, "",
       "deep"},
      {~s/{{__line__ | upper}}/, %{}, "current line", "CURRENT LINE"}
    ]

    for {{template, input, line, expected}, index} <- Enum.with_index(original ++ controls) do
      job = "string-template-#{index}"
      stream = Map.put(input, "job", job)
      push(ctx, line, ctx.now, stream)

      expression = ~s/{job="#{job}"} | line_format / <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      assert_streams(response, [{stream, [expected]}])
      assert request_form(ctx, "/query_range", params) == response

      expression = ~s/{job="#{job}"} | label_format out=/ <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      assert_streams(response, [{Map.put(stream, "out", expected), [line]}])
      assert request_form(ctx, "/query_range", params) == response
    end
  end

  @tag :template_time_batch
  test "Loki timestamp and Unix conversion formatter rows replay through HTTP and Parquet", ctx do
    # Complete fmt_test.go:361-369 and 636-644 timestamp_unix rows, and all
    # five unixToTime rows at 728-772. Freeze their time.Local outputs in UTC.
    original = [
      {:line, nil, "{{ __timestamp__ | unixEpoch }} bar {{ .bar }}", %{"bar" => "2"}, 1_656_353_124_120_000_000, "1",
       "1656353124 bar 2"},
      {:label, "ts", "{{ __timestamp__ | unixEpoch }}", %{"foo" => "blip", "bar" => "blop"}, 1_661_518_453_244_672_570,
       "test line", "1661518453"},
      {:label, "foo", "{{ .bar | unixToTime }}", %{"foo" => "", "bar" => "19503"}, 1_661_518_453_244_672_570,
       "test line", "2023-05-26 00:00:00 +0000 UTC"},
      {:label, "foo", "{{ .bar | unixToTime }}", %{"foo" => "", "bar" => "1679577215"}, 1_661_518_453_244_672_570,
       "test line", "2023-03-23 13:13:35 +0000 UTC"},
      {:label, "foo", "{{ .bar | unixToTime }}", %{"foo" => "", "bar" => "1257894000000"}, 1_661_518_453_244_672_570,
       "test line", "2009-11-10 23:00:00 +0000 UTC"},
      {:label, "foo", "{{ .bar | unixToTime }}", %{"foo" => "", "bar" => "1673798889902000"}, 1_661_518_453_244_672_570,
       "test line", "2023-01-15 16:08:09.902 +0000 UTC"},
      {:label, "foo", "{{ .bar | unixToTime }}", %{"foo" => "", "bar" => "1000000000000000000"},
       1_661_518_453_244_672_570, "test line", "2001-09-09 01:46:40 +0000 UTC"}
    ]

    for {{kind, destination, template, labels, timestamp, line, expected}, index} <- Enum.with_index(original) do
      stream = Map.put(labels, "job", "time-upstream-#{index}")
      push(ctx, line, timestamp, stream)
      row_ctx = %{ctx | now: timestamp}

      {stage, expected_labels, expected_line} =
        case kind do
          :line -> {"line_format ", stream, expected}
          :label -> {"label_format #{destination}=", Map.put(stream, destination, expected), line}
        end

      expression = ~s/{job="#{stream["job"]}"} | / <> stage <> Pulse.JSON.encode!(template)

      for path <- ["/query", "/query_range"] do
        params = [{"query", expression} | range(row_ctx)]
        response = request(ctx, path, params)
        assert_streams(response, [{expected_labels, [expected_line]}])
        assert request_form(ctx, path, params) == response
      end
    end

    assert_parquet(ctx, 7)
    assert_parquet_read(ctx)
  end

  @tag :template_time_batch
  test "timestamp formatters retain source nanoseconds and typed time across rewritten lines", ctx do
    cases = [
      {1_656_353_124_999_999_999, "1656353124 1656353124999 1656353124999999999"},
      {1_656_353_125_000_000_001, "1656353125 1656353125000 1656353125000000001"}
    ]

    for {{timestamp, expected}, index} <- Enum.with_index(cases) do
      stream = %{"job" => "time-control-#{index}"}
      push(ctx, "original", timestamp, stream)
      row_ctx = %{ctx | now: timestamp}

      template = "{{unixEpoch __timestamp__}} {{unixEpochMillis __timestamp__}} {{unixEpochNanos __timestamp__}}"

      for stage <- ["line_format ", "label_format out="] do
        expression = ~s/{job="#{stream["job"]}"} | / <> stage <> Pulse.JSON.encode!(template)
        params = [{"query", expression} | range(row_ctx)]
        response = request(ctx, "/query_range", params)

        if stage == "line_format " do
          assert_streams(response, [{stream, [expected]}])
        else
          assert_streams(response, [{Map.put(stream, "out", expected), ["original"]}])
        end

        assert request_form(ctx, "/query_range", params) == response
      end

      template = "{{$t := __timestamp__}}{{with $t}}{{if eq . $t}}{{unixEpochNanos .}}{{end}}{{end}} {{__line__}}"
      expression = ~s/{job="#{stream["job"]}"} | line_format "changed" | line_format / <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(row_ctx)]
      response = request(ctx, "/query_range", params)
      assert_streams(response, [{stream, ["#{timestamp} changed"]}])
      assert request_form(ctx, "/query_range", params) == response
    end

    # Signed values retain floor-based seconds/milliseconds, byte-length unit
    # selection, int64 wrapping and typed-time truthiness, not string coercion.
    controls = [
      {~s/{{unixToTime "-000000000000000001" | unixEpoch}} {{unixToTime "-000000000000000001" | unixEpochMillis}}/,
       "-1 -1"},
      {~s/{{unixToTime "9999999999" | unixEpochNanos}}/, "-8446744074709551616"},
      {~s/{{unixToTime "00000"}}/, "1970-01-01 00:00:00 +0000 UTC"},
      {~s/{{if (unixToTime "00000")}}time{{end}} {{int __timestamp__}} {{float64 __timestamp__}}/, "time 0 0"}
    ]

    stream = %{"job" => "time-unix-controls"}
    push(ctx, "original", ctx.now, stream)

    for {template, expected} <- controls do
      expression = ~s/{job="time-unix-controls"} | line_format / <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      assert_streams(response, [{stream, [expected]}])
      assert request_form(ctx, "/query_range", params) == response
    end
  end

  @tag :template_time_batch
  test "Unix conversion errors preserve formatter inputs and honor metric error selection", ctx do
    stream = %{"job" => "time-errors", "out" => "unchanged"}
    push(ctx, "original", ctx.now, stream)

    # Both original TestInvalidUnixTimes inputs, fmt_test.go:980-986.
    # Other values are separate local overflow/type/arity controls.
    for template <- [
          ~s/{{unixToTime "abc"}}/,
          ~s/{{unixToTime "464"}}/,
          ~s/{{unixToTime "9223372036854775808"}}/,
          ~s/{{unixToTime "1e000"}}/,
          "{{unixEpoch .out}}",
          "{{unixEpochMillis 1}}",
          "{{unixEpochNanos true}}",
          "{{__timestamp__ 1}}",
          "{{unixToTime}}"
        ],
        stage <- ["line_format ", "label_format out="] do
      expression = ~s/{job="time-errors"} | / <> stage <> Pulse.JSON.encode!(template)
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      assert [%{"stream" => labels, "values" => [[_, "original"]]}] = response["data"]["result"]
      assert labels["out"] == "unchanged"
      assert labels["__error__"] == "TemplateFormatErr"
      assert labels["__error_details__"] != ""
      assert request_form(ctx, "/query_range", params) == response
    end

    expression = ~s/{job="time-errors"} | line_format "{{unixToTime .out}}"/
    assert values(instant(ctx, "sum(count_over_time(" <> expression <> ~s/ | __error__!="" [1m]))/)) == %{%{} => "1"}

    params = [query: "count_over_time(" <> expression <> " [1m])", time: to_string(ctx.now + @second)]
    assert request(ctx, "/query", params, 400) == request_form(ctx, "/query", params, 400)
    assert_parquet_read(ctx)
  end

  @tag :template_functions_batch
  test "template execution failures retain input and honor metric error selection", ctx do
    push(ctx, "original", ctx.now, %{"job" => "template-error", "out" => "unchanged"})

    for template <- ["before {{upper}} after", "{{upper true}}", "{{.out .out}}", "{{__line__ .out}}"],
        stage <- ["line_format " <> Pulse.JSON.encode!(template), "label_format out=" <> Pulse.JSON.encode!(template)] do
      expression = ~s/{job="template-error"} | / <> stage
      params = [{"query", expression} | range(ctx)]
      response = request(ctx, "/query_range", params)
      assert [%{"stream" => labels, "values" => [[_, "original"]]}] = response["data"]["result"]
      assert labels["out"] == "unchanged"
      assert labels["__error__"] == "TemplateFormatErr"
      assert labels["__error_details__"] != ""
      assert request_form(ctx, "/query_range", params) == response

      metric = "bytes_over_time(#{expression} [1m])"
      params = [query: metric, time: to_string(ctx.now + @second)]
      response = request(ctx, "/query", params, 400)
      assert request_form(ctx, "/query", params, 400) == response
      assert response["message"] =~ "pipeline_error"

      assert_metric(ctx, ~s/sum by (job) (bytes_over_time(#{expression} | __error__!="" [1m]))/, 1, %{
        %{"job" => "template-error"} => [{1, "8"}]
      })

      assert_metric(ctx, ~s/bytes_over_time(#{expression} | __error__="" [1m])/, 1, %{})
    end

    for template <- [
          "{{",
          "{{nosuchfunc}}",
          "{{.out |}}",
          "{{(upper .out}}",
          "{{.out)}}",
          ~s/{{.out | "literal"}}/,
          ~S/{{"\uD800"}}/,
          ~S/{{"\x+1"}}/,
          "{{range}}yes{{end}}",
          # Deliberate admission fences, not upstream syntax failures.
          ~S/{{"\xff"}}/,
          "{{" <> String.duplicate("(", 65) <> ".out" <> String.duplicate(")", 65) <> "}}"
        ] do
      for stage <- ["line_format ", "label_format out="] do
        expression = ~s/{job="template-error"} |= "not present" | / <> stage <> Pulse.JSON.encode!(template)
        params = [query: expression, time: to_string(ctx.now + @second)]
        reads = Agent.get(ctx.store, & &1.requests)
        response = request(ctx, "/query", params, 400)
        assert request_form(ctx, "/query", params, 400) == response
        assert Agent.get(ctx.store, & &1.requests) == reads
      end
    end
  end

  @tag :label_format_assignment_batch
  test "Loki label formatter rejects duplicate and error destinations before storage", ctx do
    # Complete Test_validate table, pkg/logql/log/fmt_test.go:817-834.
    for {assignments, status} <- [
          {"foo=bar, bar=foo", 200},
          {"foo=bar, foo=blip", 400},
          {"__error__=bar", 400},
          # Local controls cover template destinations and unreachable stages.
          {~s/foo="one", foo=bar/, 400},
          {~s/__error__="mine"/, 400}
        ] do
      params = [query: ~s/{app="a"} |= "missing" | label_format / <> assignments, time: to_string(ctx.now)]
      before_reads = Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests})
      response = request(ctx, "/query", params, status)
      assert response == request_form(ctx, "/query", params, status)
      if status == 400, do: assert(Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == before_reads)
    end
  end

  @tag :label_format_assignment_batch
  test "Loki label assignments use first-template snapshots and ordered renames", ctx do
    ctx = %{ctx | now: ctx.now - 120 * @second}

    # First four Test_labelsFormatter_Format rows (no template functions),
    # plus controls checked against the actual pinned pipeline runtime.
    cases = [
      {"baz=foo", %{"foo" => "blip", "bar" => "blop"}, %{"bar" => "blop", "baz" => "blip"}},
      {"bar=foo", %{"foo" => "blip", "bar" => "blop"}, %{"bar" => "blip"}},
      {~s/foo="{{.foo}} and {{.bar}}"/, %{"foo" => "blip", "bar" => "blop"},
       %{"foo" => "blip and blop", "bar" => "blop"}},
      {~s/blip="{{.foo}} and {{.bar}}", bar=foo/, %{"foo" => "blip", "bar" => "blop"},
       %{"blip" => "blip and blop", "bar" => "blip"}},
      {"x=x, absent=missing", %{"x" => "v"}, %{}},
      {~s/x="new", y="{{.x}}"/, %{"x" => "old"}, %{"x" => "new", "y" => "old"}},
      {~s/x=src, y="{{.x}}", z="{{.src}}"/, %{"src" => "v", "x" => "old"}, %{"x" => "v", "y" => "v", "z" => ""}},
      {~s/y="{{.src}}", x=src, z="{{.src}}"/, %{"src" => "v"}, %{"x" => "v", "y" => "v", "z" => "v"}},
      {~s/x="new", y="{{.x}}" | label_format z="{{.x}}"/, %{"x" => "old"}, %{"x" => "new", "y" => "old", "z" => "new"}},
      {~s/y="é{{.x}}✓" | line_format "é{{.y}}✓" |= "ééold✓✓"/, %{"x" => "old"}, %{"x" => "old", "y" => "éold✓"}},
      {~s/x=x | logfmt/, %{"x" => "v"}, %{}}
    ]

    for {{assignments, input, expected}, index} <- Enum.with_index(cases), owner <- [:stream, :metadata, :parsed] do
      job = "format-#{index}-#{owner}"
      stream = %{"job" => job}
      line = "x=from_line"

      {labels, metadata, prefix} =
        case owner do
          :stream ->
            {Map.merge(stream, input), %{}, ""}

          :metadata ->
            {stream, input, ""}

          :parsed ->
            {stream, input, ~s/ | label_format / <> Enum.map_join(input, ",", fn {k, v} -> ~s(#{k}="#{v}") end)}
        end

      push(ctx, line, ctx.now + 20 * @second, labels, metadata)
      expression = ~s/count_over_time({job="#{job}"}#{prefix} | label_format #{assignments} [1m])/
      assert_metric(ctx, expression, 60, %{Map.merge(stream, expected) => [{60, "1"}]})
      assert_metric(ctx, expression, {40, 80, 20}, %{Map.merge(stream, expected) => [{40, "1"}, {60, "1"}]})
    end
  end

  # Complete label_replace block, functions.logqltest:24-132 at the pinned
  # Loki revision. Relative times, noise, labels and numeric oracles survive.
  @tag :label_replace_batch
  test "Loki label_replace copies overwrites and deletes labels over instant and range results", ctx do
    ctx = %{ctx | now: ctx.now - 180 * @second}

    streams =
      for {app, tier} <- [{"foo", "1"}, {"foobar", "2"}] do
        values =
          for i <- 0..12, {line, offset} <- [{"xbar", 0}, {"noise", 5}] do
            [to_string(ctx.now + (i * 10 + offset) * @second), line]
          end

        %{"stream" => %{"app" => app, "tier" => tier}, "values" => values}
      end

    push_streams(ctx, streams)
    inner = ~s/count_over_time({app=~"foo.*"} |~".+bar" [1m])/
    foo = %{"app" => "foo", "tier" => "1"}
    foobar = %{"app" => "foobar", "tier" => "2"}

    cases = [
      {~s/"new", "$1", "app", "(fo)o"/, Map.put(foo, "new", "fo"), foobar},
      {~s/"tier", "gold", "app", "foo"/, %{foo | "tier" => "gold"}, foobar},
      {~s/"tier", "", "app", "foo"/, Map.delete(foo, "tier"), foobar},
      {~s/"app", "$1", "app", "foo(.*)"/, Map.delete(foo, "app"), %{foobar | "app" => "bar"}},
      {~s/"app", "$1", "app", "f(.*)"/, %{foo | "app" => "oo"}, %{foobar | "app" => "oobar"}},
      {~s/"region", "eu", "missing", ".*"/, Map.put(foo, "region", "eu"), Map.put(foobar, "region", "eu")}
    ]

    for {args, left, right} <- cases do
      assert_metric(ctx, "label_replace(#{inner}, #{args})", 60, %{left => [{60, "6"}], right => [{60, "6"}]})
    end

    assert_metric(ctx, ~s/label_replace(#{inner}, "new", "$1", "app", "(fo)o")/, {60, 120, 60}, %{
      Map.put(foo, "new", "fo") => [{60, "6"}, {120, "6"}],
      foobar => [{60, "6"}, {120, "6"}]
    })

    # Source-derived control: rewriting labels must not sum sample values.
    collision = ~s/label_replace(label_replace(#{inner}, "tier", "1", "tier", ".*"), "app", "foo", "app", ".*")/
    params = [query: collision, time: to_string(ctx.now + 60 * @second)]
    response = request(ctx, "/query", params)
    sample = %{"metric" => foo, "value" => [(ctx.now + 60 * @second) / @second, "6"]}
    assert response["data"]["result"] == [sample, sample]
    assert request_form(ctx, "/query", params) == response

    before_reads = Agent.get(ctx.store, & &1.reads)
    invalid = ~s/label_replace(#{inner}, "new", "$1", "app", "(")/
    request(ctx, "/query", [query: invalid, time: to_string(ctx.now + 60 * @second)], 400)
    request_form(ctx, "/query", [query: invalid, time: to_string(ctx.now + 60 * @second)], 400)
    assert Agent.get(ctx.store, & &1.reads) == before_reads
    assert_parquet(ctx, 1)
  end

  # The remaining three complete fixtures in that block exercise final-label
  # ownership, not only the original stream labels.
  for {name, stream, line, metadata, stages, labels, sources} <- [
        {"metadata", %{"app" => "a", "env" => "prod"}, "msg", %{"region" => "eu", "env" => "canary"}, "",
         %{"app" => "a", "env" => "prod", "env_extracted" => "canary", "region" => "eu"},
         [{"region", "eu"}, {"env", "prod"}, {"env_extracted", "canary"}]},
        {"parsed", %{"app" => "a", "zone" => "s"}, "svc=api zone=p tid=p", %{"tid" => "m"}, " | logfmt",
         %{"app" => "a", "zone" => "s", "zone_extracted" => "p", "tid" => "m", "tid_extracted" => "p", "svc" => "api"},
         [{"svc", "api"}, {"zone", "s"}, {"zone_extracted", "p"}, {"tid", "m"}, {"tid_extracted", "p"}]},
        {"triple", %{"app" => "a", "k" => "s"}, "k=p", %{"k" => "m"}, " | logfmt",
         %{"app" => "a", "k" => "s", "k_extracted" => "p"}, [{"k", "s"}, {"k_extracted", "p"}]}
      ] do
    @tag :label_replace_batch
    test "Loki label_replace reads #{name} label ownership", ctx do
      ctx = %{ctx | now: ctx.now - 120 * @second}

      values =
        for t <- [20, 40, 60], do: [to_string(ctx.now + t * @second), unquote(line), unquote(Macro.escape(metadata))]

      push_streams(ctx, [
        %{"stream" => unquote(Macro.escape(stream)), "values" => values},
        %{"stream" => %{"app" => "noise"}, "values" => [[to_string(ctx.now + 30 * @second), "noise"]]}
      ])

      inner = ~s/count_over_time({app="a"}#{unquote(stages)} [1m])/

      for {source, value} <- unquote(Macro.escape(sources)) do
        query = ~s/label_replace(#{inner}, "out", "$1", "#{source}", "(.*)")/
        assert_metric(ctx, query, 60, %{Map.put(unquote(Macro.escape(labels)), "out", value) => [{60, "3"}]})
      end

      if unquote(name) == "triple" do
        query = ~s/label_replace(count_over_time({app="a"} [1m]), "out", "$1", "k_extracted", "(.*)")/
        assert_metric(ctx, query, 60, %{%{"app" => "a", "k" => "s", "k_extracted" => "m", "out" => "m"} => [{60, "3"}]})
      end

      assert_parquet(ctx, 1)
    end
  end

  @tag :label_replace_batch
  test "label replacement preserves Loki regex defaults and nested request restrictions", ctx do
    labels = %{"job" => "replace-control", "source" => "a\nb", "dst" => "unchanged"}
    push(ctx, "message", ctx.now, Map.take(labels, ["job"]), Map.delete(labels, "job"))
    inner = ~s/count_over_time({job="replace-control"}[1m])/

    for {pattern, expected} <- [{"(.*)", labels}, {"(?s:(.*))", %{labels | "dst" => "a\nb"}}] do
      query = ~s/label_replace(#{inner}, "dst", "$1", "source", "#{pattern}")/
      assert_metric(ctx, query, 0, %{expected => [{0, "1"}]})
    end

    captured = ~s/label_replace(#{inner}, "dst", "$$:$1:${word}:$1x:${1}x:$missing:${01}", "job", "(?P<word>.*)")/
    expected = %{labels | "dst" => "$:replace-control:replace-control::replace-controlx::"}
    assert_metric(ctx, captured, 0, %{expected => [{0, "1"}]})

    nested = ~s/label_replace(label_replace(#{inner}, "a", "x", "missing", ".*"), "b", "$1", "a", "(.*)")/
    assert_metric(ctx, nested, 0, %{Map.merge(labels, %{"a" => "x", "b" => "x"}) => [{0, "1"}]})

    cases = [
      {ctx, "/query", ~s/label_replace(#{inner}, "dst", "$1", "job", "(")/},
      {ctx, "/query", ~s/label_replace(#{inner}, "dst", "$1", "job", "x)|(?:y")/},
      {query_limits(ctx, ~s({"maxQueryInterval":"30s"})), "/query", ~s/label_replace(#{inner}, "a", "x", "job", ".*")/},
      {query_limits(ctx, ~s({"requiredLabels":["tenant"]})), "/query",
       ~s/label_replace(#{inner}, "tenant", "yes", "job", ".*")/},
      {query_limits(ctx, ~s({"minimumLabelsNumber":2})), "/query", ~s/label_replace(#{inner}, "a", "x", "job", ".*")/},
      {ctx, "/query_range", ~s/label_replace(approx_topk(1, #{inner}), "a", "x", "job", ".*")/}
    ]

    before_reads = Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests})

    for {context, path, query} <- cases do
      params = [query: query, time: to_string(ctx.now), start: to_string(ctx.now), end: to_string(ctx.now), step: 1]
      assert request(context, path, params, 400) == request_form(context, path, params, 400)
      assert Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == before_reads
    end
  end

  # Complete regexp/pattern/unpack engine blocks, parsers.logqltest:304-446.
  for {name, stage, line, labels} <- [
        {"regexp", ~S/regexp `(?P<method>\w+) (?P<path>\S+) (?P<status>\d+)`/, "GET /home 200",
         %{"app" => "a", "method" => "GET", "path" => "/home", "status" => "200"}},
        {"pattern", "pattern `<method> <path> <status>`", "GET /home 200",
         %{"app" => "a", "method" => "GET", "path" => "/home", "status" => "200"}},
        {"unpack", "unpack", ~s/{"lvl":"info","cluster":"eu","num":5,"_entry":"real message"}/,
         %{"app" => "a", "lvl" => "info", "cluster" => "eu"}}
      ] do
    @tag :remaining_parsers_batch
    test "Loki #{name} engine windows preserve captures and sparse results", ctx do
      ctx = %{ctx | now: ctx.now - 240 * @second}
      line = unquote(line)
      noise = if unquote(name) == "unpack", do: ~s/{"a":"b","_entry":"x"}/, else: line

      push_streams(
        ctx,
        for {app, text} <- [{"a", line}, {"noise", noise}] do
          %{
            "stream" => %{"app" => app},
            "values" => for(t <- [20, 40, 60, 80], do: [to_string(ctx.now + t * @second), text])
          }
        end
      )

      query = ~s/count_over_time({app="a"} | #{unquote(stage)} [1m])/
      labels = unquote(Macro.escape(labels))
      assert_metric(ctx, query, 60, %{labels => [{60, "3"}]})
      assert_metric(ctx, query, {40, 80, 20}, %{labels => [{40, "2"}, {60, "3"}, {80, "3"}]})
      assert_metric(ctx, query, {60, 180, 120}, %{labels => [{60, "3"}]})

      if unquote(name) == "pattern" do
        assert_metric(ctx, ~s/count_over_time({app="a"} | pattern `<method> <_> <status>` [1m])/, 60, %{
          Map.delete(labels, "path") => [{60, "3"}]
        })
      end

      assert_parquet(ctx, 1)
    end
  end

  for {name, stream, line, stage, labels, invalid} <- [
        {"regexp", %{"app" => "a", "method" => "stream"}, "PUT /x", ~S/regexp `(?P<method>\w+) (?P<path>\S+)`/,
         %{"app" => "a", "method" => "stream", "method_extracted" => "PUT", "path" => "/x"},
         ["regexp `nocapture`", "regexp `(?P<x>.)(?P<x>.)`", "regexp `(`"]},
        {"pattern", %{"app" => "a", "method" => "stream"}, "POST", "pattern `<method> <path>`",
         %{"app" => "a", "method" => "stream", "method_extracted" => "POST"}, ["pattern `no captures here`"]},
        {"unpack", %{"app" => "a", "lvl" => "stream"}, ~s/{"lvl":"packed","_entry":"code=42"}/, "unpack | logfmt",
         %{"app" => "a", "lvl" => "stream", "lvl_extracted" => "packed", "code" => "42"}, []}
      ] do
    @tag :remaining_parsers_batch
    test "Loki #{name} engine edge cases retain nonmatches and partial captures", ctx do
      ctx = %{ctx | now: ctx.now - 120 * @second}
      noise = if unquote(name) == "unpack", do: ~s/{"_entry":"x"}/, else: "y"

      push_streams(ctx, [
        %{
          "stream" => unquote(Macro.escape(stream)),
          "values" => for(t <- [20, 40, 60], do: [to_string(ctx.now + t * @second), unquote(line)])
        },
        %{
          "stream" => %{"app" => "noise"},
          "values" => for(t <- [20, 40, 60], do: [to_string(ctx.now + t * @second), noise])
        }
      ])

      query = ~s/count_over_time({app="a"} | #{unquote(stage)} [1m])/
      labels = unquote(Macro.escape(labels))
      assert_metric(ctx, query, 60, %{labels => [{60, "3"}]})
      assert_metric(ctx, query, {40, 60, 20}, %{labels => [{40, "2"}, {60, "3"}]})

      if unquote(name) == "regexp" do
        assert_metric(ctx, ~S/count_over_time({app="a"} | regexp `(?P<num>\d+)` [1m])/, 60, %{
          unquote(Macro.escape(stream)) => [{60, "3"}]
        })
      end

      if unquote(name) == "unpack" do
        assert_metric(ctx, ~s/count_over_time({app="a"} | unpack [1m])/, 60, %{
          Map.delete(labels, "code") => [{60, "3"}]
        })
      end

      before_reads = Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests})

      for stage <- unquote(invalid) do
        params = [query: ~s/count_over_time({app="a"} | #{stage} [1m])/, time: to_string(ctx.now + 60 * @second)]
        assert request(ctx, "/query", params, 400) == request_form(ctx, "/query", params, 400)
        assert Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == before_reads
      end

      assert_parquet(ctx, 1)
    end
  end

  for {name, stage, line, noise} <- [
        {"regexp", ~S/regexp `(?P<sl>\S+) (?P<md>\S+) (?P<tri>\S+)`/, "p p p", "y"},
        {"pattern", "pattern `<sl> <md> <tri>`", "p p p", "y"},
        {"unpack", "unpack", ~s/{"sl":"p","md":"p","tri":"p","_entry":"x"}/, ~s/{"_entry":"x"}/}
      ] do
    @tag :remaining_parsers_batch
    test "Loki #{name} engine retains all three label owners", ctx do
      ctx = %{ctx | now: ctx.now - 120 * @second}
      metadata = %{"md" => "m", "sm" => "m", "tri" => "m"}
      stream = %{"app" => "a", "sl" => "s", "sm" => "s", "tri" => "s"}

      push_streams(ctx, [
        %{
          "stream" => stream,
          "values" => for(t <- [20, 40, 60], do: [to_string(ctx.now + t * @second), unquote(line), metadata])
        },
        %{
          "stream" => %{"app" => "noise"},
          "values" => for(t <- [20, 40, 60], do: [to_string(ctx.now + t * @second), unquote(noise)])
        }
      ])

      labels = %{
        "app" => "a",
        "sl" => "s",
        "sl_extracted" => "p",
        "md" => "m",
        "md_extracted" => "p",
        "sm" => "s",
        "sm_extracted" => "m",
        "tri" => "s",
        "tri_extracted" => "p"
      }

      query = ~s/count_over_time({app="a"} | #{unquote(stage)} [1m])/
      assert_metric(ctx, query, 60, %{labels => [{60, "3"}]})
      assert_metric(ctx, query, {40, 60, 20}, %{labels => [{40, "2"}, {60, "3"}]})
      assert_parquet(ctx, 1)
    end
  end

  @tag :remaining_parsers_batch
  test "Loki unpack engine errors reject metric results unless selected away", ctx do
    ctx = %{ctx | now: ctx.now - 120 * @second}

    push_streams(
      ctx,
      for {app, line} <- [{"a", "not json"}, {"noise", ~s/{"_entry":"x"}/}] do
        %{"stream" => %{"app" => app}, "values" => for(t <- [20, 40, 60], do: [to_string(ctx.now + t * @second), line])}
      end
    )

    params = [query: ~s/count_over_time({app="a"} | unpack [1m])/, time: to_string(ctx.now + 60 * @second)]
    assert request(ctx, "/query", params, 400) == request_form(ctx, "/query", params, 400)
    assert_metric(ctx, ~s/count_over_time({app="a"} | unpack | __error__="" [1m])/, 60, %{})
    assert_parquet(ctx, 1)
  end

  # Complete regexp constructor table and pattern Test_Error admission table.
  @tag :remaining_parsers_batch
  test "Loki parser constructor tables reject invalid captures before storage", ctx do
    cases = [
      {"regexp", "w.*", true},
      {"regexp", "f(.*) (foo|bar|buzz)", true},
      {"regexp", "blah (.*) (?P<foo>)", false},
      {"regexp", "blah (.*) (?P<foo>foo)(?P<bar>barr)", false},
      {"regexp", "blah (.*) (?P<foo$>foo)(?P<bar>barr)", true},
      {"regexp", "blah (.*) (?P<foo>foo)(?P<foo>barr)", true},
      # Local metadata controls, separate from the original constructor rows.
      {"regexp", ~S/\Q(?P<fake>x)\E/, true},
      {"regexp", "[(?P<fake>x)]", true},
      {"regexp", "x(?)*", true},
      {"regexp", "(?P<field>x){0}", false},
      {"pattern", "<f>", false},
      {"pattern", "<f> <a>", false},
      {"pattern", "", true},
      {"pattern", "<_>", true},
      {"pattern", "foo <_> bar <_>", true},
      {"pattern", "foo bar buzz", true},
      {"pattern", "<f><f>", true},
      {"pattern", "<f> f<d><b>", true},
      {"pattern", "<f> f<f>", true},
      {"pattern", "f<f><_>", true},
      {"pattern", "<f>f<f><_>", true}
    ]

    for {stage, pattern, rejects?} <- cases do
      before_reads = Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests})
      params = [query: ~s/{job="constructor"} | #{stage} `#{pattern}`/, time: to_string(ctx.now)]
      status = if rejects?, do: 400, else: 200
      assert request(ctx, "/query", params, status) == request_form(ctx, "/query", params, status)
      if rejects?, do: assert(Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == before_reads)
    end
  end

  # Nine unhinted Test_unpackParser_Parse rows. The one hinted duplicate is
  # omitted: HTTP cannot supply that internal parser hint. A selector-only job
  # label isolates otherwise identical/empty upstream label sets.
  @tag :remaining_parsers_batch
  test "Loki unpack unit oracles preserve line replacement labels and object requirements", ctx do
    cluster = %{"cluster" => "us-central1"}
    packed = ~s/{"bar":1,"app":"foo","namespace":"prod","_entry":"some message","pod":{"uid":"1"}}/
    invalid = ~s/"app":"foo","namespace":"prod","_entry":"some message","pod":{"uid":"1"}/
    error = %{"__error__" => "JSONParserErr", "__error_details__" => "expecting json object(6), but it is not"}

    quoted =
      ~S|I0303 17:49:45.976518    1526 kubelet_getters.go:178] "Pod status updated" pod="openshift-etcd/etcd-ip-10-0-150-50.us-east-2.compute.internal" status=Running|

    original =
      ~S|{"_entry":"I0303 17:49:45.976518    1526 kubelet_getters.go:178] \"Pod status updated\" pod=\"openshift-etcd/etcd-ip-10-0-150-50.us-east-2.compute.internal\" status=Running"}|

    cases = [
      {packed, cluster, %{}, Map.merge(cluster, %{"app" => "foo", "namespace" => "prod"}), "some message"},
      {invalid, %{}, %{}, error, invalid},
      {"", cluster, %{}, cluster, ""},
      {~s/["foo","bar"]/, cluster, %{}, Map.merge(cluster, error), ~s/["foo","bar"]/},
      {packed, Map.put(cluster, "app", "bar"), %{},
       Map.merge(cluster, %{"app" => "bar", "app_extracted" => "foo", "namespace" => "prod"}), "some message"},
      {~s/{"bar":1,"app":"foo","namespace":"prod","pod":{"uid":"1"}}/, Map.put(cluster, "app", "bar"), %{},
       Map.put(cluster, "app", "bar"), nil},
      {original, Map.put(cluster, "app", "bar"), %{}, Map.put(cluster, "app", "bar"), quoted},
      {~s/{"foo.bar":"10ms","test-dash":"foo","_entry":"some message"}/, %{"foo" => "bar"}, %{},
       %{"foo" => "bar", "foo_bar" => "10ms", "test_dash" => "foo"}, "some message"},
      {~s/{"app":"foo","namespace":"prod","_entry":"some message"}/, %{}, %{"app" => "foo_sm"},
       %{"app" => "foo_sm", "app_extracted" => "foo", "namespace" => "prod"}, "some message"},
      # Separate source-derived controls, not original table rows.
      {~s/{"a":"x","_entry":42}/, %{}, %{}, %{}, nil},
      {~s/{"a":"x","a":"last","_entry":"first","_entry":"last"}/, %{}, %{}, %{"a" => "last"}, "last"},
      {~s/{"n":1e999999,"flag":true,"arr":["x"],"obj":{"a":"x"},"nil":null,"_entry":"ok"}/, %{}, %{}, %{}, "ok"}
    ]

    for {{line, stream, metadata, labels, output}, i} <- Enum.with_index(cases) do
      job = "unpack-unit-#{i}"
      push(ctx, line, ctx.now, Map.put(stream, "job", job), metadata)
      result = query(ctx, ~s/{job="#{job}"} | unpack/)
      assert_streams(result, [{Map.put(labels, "job", job), [output || line]}])
    end

    assert_parquet(ctx, length(cases))
  end

  # Complete Test_parseDuration table from Loki's lexer tests. Constructor
  # outputs become canonical runtime ns values, not the literals under test.
  @tag :quantity_literal_batch
  test "Loki duration token table survives HTTP filtering and metric evaluation", ctx do
    cases = [
      {"1ns", 1},
      {"1s", 1_000_000_000},
      {"1us", 1_000},
      {"1m", 60_000_000_000},
      {"1h", 3_600_000_000_000},
      {"1µs", 1_000},
      {"1y", 31_536_000_000_000_000},
      {"1w", 604_800_000_000_000},
      {"1d", 86_400_000_000_000},
      {"1h15m30.918273645s", 4_530_918_273_645},
      {"-1s", -1_000_000_000}
    ]

    for {{literal, ns}, index} <- Enum.with_index(cases) do
      job = "duration-token-#{index}"
      labels = %{"job" => job}
      push(ctx, "sample", ctx.now, labels, %{"foo" => "#{ns}ns"})
      expression = ~s/{job="#{job}"} | foo = #{literal}/
      assert_streams(query(ctx, expression), [{Map.put(labels, "foo", "#{ns}ns"), ["sample"]}])
      assert_metric(ctx, "count_over_time(#{expression}[1m])", 0, %{Map.put(labels, "foo", "#{ns}ns") => [{0, "1"}]})
    end

    assert_parquet(ctx, 11)
    assert_parquet_read(ctx)
  end

  # All 13 baseCases and nine TestParseBadDuration inputs from the pinned
  # prometheus/common model tests. Negative-helper cases are a different API.
  @tag :quantity_literal_batch
  test "Prometheus duration tables govern Loki bracketed ranges", ctx do
    cases = [
      {"0", 0},
      {"0w", 0},
      {"0s", 0},
      {"324ms", 324_000_000},
      {"3s", 3_000_000_000},
      {"5m", 300_000_000_000},
      {"1h", 3_600_000_000_000},
      {"4d", 345_600_000_000_000},
      {"4d1h", 349_200_000_000_000},
      {"14d", 1_209_600_000_000_000},
      {"3w", 1_814_400_000_000_000},
      {"3w2d1h", 1_990_800_000_000_000},
      {"10y", 315_360_000_000_000_000}
    ]

    for {{literal, ns}, index} <- Enum.with_index(cases) do
      job = "range-token-#{index}"
      expression = ~s/count_over_time({job="#{job}"}[#{literal}])/
      assert {:ok, %RangeAgg{range_ns: ^ns}} = Parser.parse(expression)

      if ns == 0 do
        # Lexer accepts zero; Pulse deliberately rejects zero metric windows.
        assert request(ctx, "/query", [query: expression, time: to_string(ctx.now)], 400)["error"] ==
                 "evaluation_failed"
      else
        push(ctx, "excluded boundary", ctx.now - ns, %{"job" => job})
        push(ctx, "included boundary", ctx.now - ns + 1, %{"job" => job})
        assert_metric(ctx, expression, 0, %{%{"job" => job} => [{0, "1"}]})
      end
    end

    for literal <- ["1", "1y1m1d", "1.5d", "d", "294y", "200y10400w", "107675d", "2584200h", ""] do
      params = [query: ~s/count_over_time({job="unused"}[#{literal}])/, time: to_string(ctx.now)]
      assert request(ctx, "/query", params, 400)["error"] == "parse_error"
      assert request_form(ctx, "/query", params, 400)["error"] == "parse_error"
    end

    assert_parquet(ctx, 20)
    assert_parquet_read(ctx)
  end

  @tag :quantity_literal_batch
  test "Loki byte token examples retain binary and decimal thresholds", ctx do
    # Complete standalone BYTES inputs plus the quantity examples in TestLex,
    # and parser_test.go's fractional-byte constructor expectation.
    cases = [
      {"123KB", 123_000},
      {"123PB", 123_000_000_000_000_000},
      {"123PiB", 138_485_688_541_642_752},
      {"0B", 0},
      {"1B", 1},
      {"250kB", 250_000},
      {"200MiB", 209_715_200},
      {"2.5KiB", 2_560}
    ]

    for {{literal, bytes}, index} <- Enum.with_index(cases) do
      labels = %{"job" => "byte-token-#{index}", "foo" => "#{bytes}B"}
      push(ctx, "sample", ctx.now, labels)
      expression = ~s/{job="byte-token-#{index}"} | foo = #{literal}/
      assert_streams(query(ctx, expression), [{labels, ["sample"]}])
      assert_metric(ctx, "count_over_time(#{expression}[1m])", 0, %{labels => [{0, "1"}]})
    end

    assert_parquet(ctx, 8)
    assert_parquet_read(ctx)
  end

  # Pulse controls distinguish correct token conversion from self-consistent
  # conversion on both sides, and keep producer/threshold/range profiles apart.
  @tag :quantity_literal_batch
  test "quantity thresholds retain rounding, signed and unsigned boundaries", ctx do
    cases = [
      {"duration", "0.3333333333333333333h", "1200000000000ns", "1199999999999ns"},
      {"duration", "-9223372036854775808ns", "-9223372036854775808ns", "-9223372036854775807ns"},
      {"duration", ".5s", "500000000ns", "499999999ns"},
      {"duration", "1.s", "1000000000ns", "999999999ns"},
      {"duration", "1m1h", "3660000000000ns", "3659999999999ns"},
      {"duration", "0.6ns0.6ns", "0ns", "1ns"},
      {"duration", "-0", "0ns", "1ns"},
      {"bytes", "9007199254740993.0B", "9007199254740992B", "9007199254740993B"},
      {"bytes", "18446744073709551615B", "18446744073709551615B", "18446744073709551614B"},
      {"bytes", "0.9999999999999999999B", "1B", "0B"},
      {"bytes", ".5KiB", "512B", "511B"},
      {"bytes", "1.B", "1B", "0B"}
    ]

    suffixes = [
      {"k", 1_000},
      {"K", 1_000},
      {"M", 1_000_000},
      {"G", 1_000_000_000},
      {"T", 1_000_000_000_000},
      {"P", 1_000_000_000_000_000},
      {"ki", 1_024},
      {"Ki", 1_024},
      {"Mi", 1_048_576},
      {"Gi", 1_073_741_824},
      {"Ti", 1_099_511_627_776},
      {"Pi", 1_125_899_906_842_624},
      {"kiB", 1_024}
    ]

    cases =
      cases ++ Enum.map(suffixes, fn {suffix, bytes} -> {"bytes", "1" <> suffix, "#{bytes}B", "#{bytes - 1}B"} end)

    for {{_kind, literal, equal, unequal}, index} <- Enum.with_index(cases) do
      job = "quantity-boundary-#{index}"
      push(ctx, "equal", ctx.now, %{"job" => job}, %{"foo" => equal})
      push(ctx, "unequal", ctx.now + 1, %{"job" => job}, %{"foo" => unequal})
      expression = ~s/{job="#{job}"} | foo == #{literal}/
      expected = [{%{"job" => job, "foo" => equal}, ["equal"]}]
      assert_streams(query(ctx, expression), expected)
      assert_streams(request_form(ctx, "/query_range", [query: expression] ++ range(ctx)), expected)
      assert_metric(ctx, "count_over_time(#{expression}[1m])", 1, %{%{"job" => job, "foo" => equal} => [{1, "1"}]})
    end

    query = ~s/count_over_time({job="quantity-boundary-0"} | foo=0.3333333333333333333h[1m])/

    assert_metric(ctx, query, {1, 2, 1}, %{
      %{"job" => "quantity-boundary-0", "foo" => "1200000000000ns"} => [{1, "1"}, {2, "1"}]
    })

    for {side, time} <- [{"past", -1}, {"future", 1}] do
      push(ctx, "sample", ctx.now + time * @second, %{"job" => "quantity-offset", "side" => side})
    end

    for {offset, side} <- [{"1.s", "past"}, {"-1.s", "future"}] do
      expression = ~s/count_over_time({job="quantity-offset"}[1s] offset #{offset})/
      assert_metric(ctx, expression, 0, %{%{"job" => "quantity-offset", "side" => side} => [{0, "1"}]})
    end

    Runtime.put_env(:pulse, Evaluator, max_work: 0)
    response = request(ctx, "/query", [query: query, time: to_string(ctx.now + @second)], 422)
    assert response["error"] == "query_limit"
    refute Map.has_key?(response, "data")
  end

  @tag :quantity_literal_batch
  test "invalid quantity profiles reject before provider reads", ctx do
    push(ctx, "sample", ctx.now, %{"job" => "quantity-rejections", "foo" => "1s"})
    reads = Agent.get(ctx.store, & &1.reads)

    thresholds = [
      "+1s",
      "- 1s",
      "1μs",
      "1.5d",
      "1.5w",
      "1.5y",
      "-1d",
      "1d1w",
      "1w1w",
      "1s 1m",
      "1e3s",
      "1_000ms",
      "9223372036854775808ns",
      "-9223372036854775809ns",
      "1s-1ms",
      "1mb",
      "1KBjunk",
      "1EB",
      "1EiB",
      "1e3B",
      "1,000B",
      "1 KB",
      "+1B",
      "-1B",
      "18446744073709551616B",
      "18446744073709551615.0B",
      "1..2B"
    ]

    queries = Enum.map(thresholds, &~s/{job="quantity-rejections"} | foo > #{&1}/)
    ranges = ["1.5h", "1ns", "1us", "1µs", "1s1m", "1m1m", "-1s", "+1s", " 1m", "1m ", "# comment\n1m"]
    queries = queries ++ Enum.map(ranges, &~s/count_over_time({job="quantity-rejections"}[#{&1}])/)

    for expression <- queries do
      params = [query: expression, time: to_string(ctx.now)]
      assert request(ctx, "/query", params, 400)["error"] == "parse_error"
      assert request_form(ctx, "/query", params, 400)["error"] == "parse_error"
    end

    assert Agent.get(ctx.store, & &1.reads) == reads
  end

  # Runtime producer values, unlike query literals, follow the converters
  # selected by Loki's label filters and sample extractors. These dependency
  # tables are pinned alongside the Loki extraction cases in the fixture README.
  @tag :quantity_value_batch
  test "Go duration parsing cases survive label filtering and duration unwrap", ctx do
    cases = [
      {"0", 0},
      {"5s", 5_000_000_000},
      {"30s", 30_000_000_000},
      {"1478s", 1_478_000_000_000},
      {"-5s", -5_000_000_000},
      {"+5s", 5_000_000_000},
      {"-0", 0},
      {"+0", 0},
      {"5.0s", 5_000_000_000},
      {"5.6s", 5_600_000_000},
      {"5.s", 5_000_000_000},
      {".5s", 500_000_000},
      {"1.0s", 1_000_000_000},
      {"1.00s", 1_000_000_000},
      {"1.004s", 1_004_000_000},
      {"1.0040s", 1_004_000_000},
      {"100.00100s", 100_001_000_000},
      {"10ns", 10},
      {"11us", 11_000},
      {"12µs", 12_000},
      {"12μs", 12_000},
      {"13ms", 13_000_000},
      {"14s", 14_000_000_000},
      {"15m", 900_000_000_000},
      {"16h", 57_600_000_000_000},
      {"3h30m", 12_600_000_000_000},
      {"10.5s4m", 250_500_000_000},
      {"-2m3.4s", -123_400_000_000},
      {"1h2m3s4ms5us6ns", 3_723_004_005_006},
      {"39h9m14.425s", 140_954_425_000_000},
      {"52763797000ns", 52_763_797_000},
      {"0.3333333333333333333h", 1_200_000_000_000},
      {"9007199254740993ns", 9_007_199_254_740_993},
      {"9223372036854775807ns", 9_223_372_036_854_775_807},
      {"9223372036854775.807us", 9_223_372_036_854_775_807},
      {"9223372036s854ms775us807ns", 9_223_372_036_854_775_807},
      {"-9223372036854775808ns", -9_223_372_036_854_775_808},
      {"-9223372036854775.808us", -9_223_372_036_854_775_808},
      {"-9223372036s854ms775us808ns", -9_223_372_036_854_775_808},
      {"-9223372036854775808ns", -9_223_372_036_854_775_808},
      {"-2562047h47m16.854775808s", -9_223_372_036_854_775_808},
      {"0.100000000000000000000h", 360_000_000_000},
      {"0.830103483285477580700h", 2_988_372_539_827}
    ]

    streams =
      for {{value, _ns}, index} <- Enum.with_index(cases),
          do: %{
            "stream" => %{"job" => "duration-#{index}", "foo" => value},
            "values" => [[to_string(ctx.now), "sample"]]
          }

    push_streams(ctx, streams)

    for {{value, ns}, index} <- Enum.with_index(cases) do
      labels = %{"job" => "duration-#{index}", "foo" => value}
      selector = ~s/{job="duration-#{index}"}/
      op = if ns < 0, do: "<0ns", else: ">=0ns"
      assert_streams(query(ctx, selector <> " | foo" <> op <> ~s/ | __error__=""/), [{labels, ["sample"]}])

      # A mismatching threshold proves that a conversion failure was not
      # silently accepted as an error-labeled line. The canonical boundary
      # avoids converting both the producer and threshold through one parser.
      if ns >= 0 do
        assert_streams(query(ctx, selector <> " | foo=" <> to_string(ns) <> "ns"), [{labels, ["sample"]}])
        assert_streams(query(ctx, selector <> " | foo!=" <> to_string(ns) <> "ns"), [])
      end

      for conversion <- ["duration", "duration_seconds"] do
        response = instant(ctx, "sum_over_time(#{selector} | unwrap #{conversion}(foo) [1m])")
        # time.Duration.Seconds splits whole seconds and the remainder before
        # float64 conversion; large durations cannot divide rounded ns directly.
        expected = div(ns, @second) + rem(ns, @second) / @second
        assert [{labels, actual}] = Map.to_list(values(response))
        assert labels == %{"job" => "duration-#{index}"}
        assert {expected, ""} == Float.parse(actual)
      end
    end

    assert_parquet(ctx, 1)
    assert_parquet_read(ctx)
  end

  @tag :quantity_value_batch
  test "go-humanize byte tables survive label filtering and bytes unwrap", ctx do
    cases = [
      {"42", 42},
      {"42MB", 42_000_000},
      {"42MiB", 44_040_192},
      {"42mb", 42_000_000},
      {"42mib", 44_040_192},
      {"42MIB", 44_040_192},
      {"42 MB", 42_000_000},
      {"42 MiB", 44_040_192},
      {"42 mb", 42_000_000},
      {"42 mib", 44_040_192},
      {"42 MIB", 44_040_192},
      {"42.5MB", 42_500_000},
      {"42.5MiB", 44_564_480},
      {"42.5 MB", 42_500_000},
      {"42.5 MiB", 44_564_480},
      {"42M", 42_000_000},
      {"42Mi", 44_040_192},
      {"42m", 42_000_000},
      {"42mi", 44_040_192},
      {"42MI", 44_040_192},
      {"42 M", 42_000_000},
      {"42 Mi", 44_040_192},
      {"42 m", 42_000_000},
      {"42 mi", 44_040_192},
      {"42 MI", 44_040_192},
      {"42.5M", 42_500_000},
      {"42.5Mi", 44_564_480},
      {"42.5 M", 42_500_000},
      {"42.5 Mi", 44_564_480},
      {"1,005.03 MB", 1_005_030_000},
      {"12.5 EB", 12_500_000_000_000_000_000},
      {"12.5 E", 12_500_000_000_000_000_000},
      {"12.5 EiB", 14_411_518_807_585_587_200},
      {"9007199254740993", 9_007_199_254_740_993},
      {"9007199254740993B", 9_007_199_254_740_993},
      {"18446744073709551615", 18_446_744_073_709_551_615},
      {"18446744073709551615 B", 18_446_744_073_709_551_615}
    ]

    streams =
      for {{value, _bytes}, index} <- Enum.with_index(cases),
          do: %{
            "stream" => %{"job" => "byte-value-#{index}", "foo" => value},
            "values" => [[to_string(ctx.now), "sample"]]
          }

    push_streams(ctx, streams)

    for {{value, bytes}, index} <- Enum.with_index(cases) do
      labels = %{"job" => "byte-value-#{index}", "foo" => value}
      selector = ~s/{job="byte-value-#{index}"}/
      assert_streams(query(ctx, selector <> ~s/ | foo>0B | __error__=""/), [{labels, ["sample"]}])

      if bytes <= 9_223_372_036_854_775_807 do
        assert_streams(query(ctx, selector <> " | foo=" <> to_string(bytes) <> "B"), [{labels, ["sample"]}])
        assert_streams(query(ctx, selector <> " | foo!=" <> to_string(bytes) <> "B"), [])
      end

      result = values(instant(ctx, "sum_over_time(#{selector} | unwrap bytes(foo) [1m])"))
      assert [{labels, actual}] = Map.to_list(result)
      assert labels == %{"job" => "byte-value-#{index}"}
      assert {bytes / 1, ""} == Float.parse(actual)
    end

    assert_parquet(ctx, 1)
    assert_parquet_read(ctx)
  end

  # UTF-8 rows from Go's parseDurationErrorTests and all TestByteErrors.
  # Three invalid-UTF-8 Go strings cannot be sent as JSON and are not claimed
  # as HTTP cases. Diagnostics are independently produced by the original
  # Go duration/go-humanize converters, never the Pulse evaluator.
  @tag :quantity_value_batch
  @tag :duration_diagnostics_batch
  @tag :byte_diagnostics_batch
  test "duration and byte error tables retain filter errors and reject invalid unwrap samples", ctx do
    duration_errors = Map.new(quantity_errors("duration"), fn [input, details] -> {input, details} end)
    byte_errors = Map.new(quantity_errors("byte"), fn [input, details] -> {input, details} end)

    cases = [
      {"duration", "ns",
       [
         "",
         "3",
         "-",
         "s",
         ".",
         "-.",
         ".s",
         "+.s",
         "1d",
         "�",
         "� hello � world",
         "9223372036854775810ns",
         "9223372036854775808ns",
         "-9223372036854775809ns",
         "9223372036854776us",
         "3000000h",
         "9223372036854775.808us",
         "9223372036854ms775us808ns"
       ]},
      {"bytes", "B", ["84 JB", "", "16 EiB", "18446744073709551616 EB", "184467440737095516150 EB"]}
    ]

    for {conversion, unit, inputs} <- cases,
        {input, index} <- Enum.with_index(inputs) do
      job = "invalid-#{conversion}-#{index}"
      push(ctx, "sample", ctx.now, %{"job" => job}, %{"foo" => input})
      selector = ~s/{job="#{job}"}/
      filter = selector <> " | foo>0" <> unit

      labels = %{
        "job" => job,
        "foo" => input,
        "__error__" => "LabelFilterErr",
        "__error_details__" => Map.fetch!(if(conversion == "duration", do: duration_errors, else: byte_errors), input)
      }

      assert_streams(query(ctx, filter), [{labels, ["sample"]}])
      assert_streams(query(ctx, filter <> ~s/ | __error__=""/), [])

      assert request(ctx, "/query", [query: "count_over_time(#{filter} [1m])", time: to_string(ctx.now + @second)], 400)[
               "message"
             ] =~ "pipeline_error"

      metric = "sum_over_time(#{selector} | unwrap #{conversion}(foo) [1m])"
      params = [query: metric, time: to_string(ctx.now + @second)]

      if input == "" do
        assert values(request(ctx, "/query", params)) == %{}
      else
        assert request(ctx, "/query", params, 400)["message"] =~ "sample_extraction_error"
      end

      assert values(instant(ctx, "sum_over_time(#{selector} | unwrap #{conversion}(foo) | __error__=\"\" [1m])")) == %{}
    end

    assert_parquet(ctx, 23)
    assert_parquet_read(ctx)
  end

  # Exact invalid-duration extractor input, grouping and diagnostic from
  # metrics_extraction_test.go:239-251. Explicit error selection makes its
  # kept zero-valued sample observable through the metric HTTP endpoint.
  @tag :duration_diagnostics_batch
  test "Loki invalid duration extraction retains its exact diagnostic", ctx do
    push(ctx, "foo=not_a_number", ctx.now, %{"job" => "duration-extraction", "bar" => "foo"})

    labels = %{
      "bar" => "foo",
      "__error__" => "SampleExtractionErr",
      "__error_details__" => ~s/time: invalid duration "not_a_number"/
    }

    for conversion <- ["duration", "duration_seconds"] do
      expression =
        ~s/avg_over_time({job="duration-extraction"} | logfmt | unwrap #{conversion}(foo) | __error__!="" [1m]) by (bar,buzz)/

      assert_metric(ctx, expression, 1, %{labels => [{1, "0"}]})
    end

    assert_parquet(ctx, 1)
  end

  # Pulse controls generated by the real pinned Go time.ParseDuration, not
  # the evaluator: escaping, failure precedence and selection by exact text.
  @tag :duration_diagnostics_batch
  test "duration diagnostics preserve escaping and error selection across HTTP transports", ctx do
    cases = Enum.drop(quantity_errors("duration"), 20)
    assert length(cases) == 14

    streams =
      for {[input, _details], index} <- Enum.with_index(cases) do
        %{
          "stream" => %{"job" => "duration-diagnostic-#{index}"},
          "values" => [[to_string(ctx.now), "sample", %{"foo" => input}]]
        }
      end

    push_streams(ctx, streams)

    for {[input, details], index} <- Enum.with_index(cases) do
      job = "duration-diagnostic-#{index}"
      selector = ~s/{job="#{job}"}/
      filter = selector <> " | foo>0ns"
      error_filter = " | __error_details__=" <> Pulse.JSON.encode!(details)

      labels = %{"job" => job, "foo" => input, "__error__" => "LabelFilterErr", "__error_details__" => details}
      expected = [{labels, ["sample"]}]
      assert_streams(query(ctx, filter <> error_filter), [])
      selected = filter <> rendered_error_details_filter(details)
      assert_streams(query(ctx, selected), expected)
      assert_streams(request_form(ctx, "/query_range", [query: selected] ++ range(ctx)), expected)
      assert_streams(query(ctx, filter <> ~s/ | __error__=""/), [])

      labels = %{"job" => job, "__error__" => "SampleExtractionErr", "__error_details__" => details}
      expression = ~s/sum_over_time(#{selector} | unwrap duration(foo) | __error__!=""#{error_filter} [1m])/
      assert_metric(ctx, expression, {1, 2, 1}, %{})
      expression = ~s/sum_over_time(#{selector} | unwrap duration(foo) | __error__!="" [1m])/
      assert_metric(ctx, expression, {1, 2, 1}, %{labels => [{1, "0"}, {2, "0"}]})
    end

    # The first duration-filter error survives a later failing byte filter.
    selector = ~s/{job="duration-diagnostic-0"}/
    details = ~s/time: missing unit in duration "1s2"/
    expression = selector <> " | foo>0ns and foo>0B" <> rendered_error_details_filter(details)

    assert_streams(query(ctx, expression), [
      {%{
         "job" => "duration-diagnostic-0",
         "foo" => "1s2",
         "__error__" => "LabelFilterErr",
         "__error_details__" => details
       }, ["sample"]}
    ])

    Runtime.put_env(:pulse, Evaluator, max_work: 0)
    expression = "sum_over_time(#{selector} | unwrap duration(foo) | __error__!=\"\" [1m])"
    response = request(ctx, "/query", [query: expression, time: to_string(ctx.now + @second)], 422)
    assert response["error"] == "query_limit"
    refute Map.has_key?(response, "data")
    assert_parquet(ctx, 1)
  end

  # Local controls from the real pinned go-humanize dependency, including its
  # rune-count/byte-slice prefix behavior and Go simple Unicode lowercasing.
  @tag :byte_diagnostics_batch
  test "byte diagnostics preserve error precedence and exact detail selection across HTTP transports", ctx do
    cases = Enum.drop(quantity_errors("byte"), 6)
    assert length(cases) == 28

    streams =
      for {[input, _details], index} <- Enum.with_index(cases) do
        %{
          "stream" => %{"job" => "byte-diagnostic-#{index}"},
          "values" => [[to_string(ctx.now), "sample", %{"foo" => input}]]
        }
      end

    push_streams(ctx, streams)

    for {[input, details], index} <- Enum.with_index(cases) do
      job = "byte-diagnostic-#{index}"
      selector = ~s/{job="#{job}"}/
      error_filter = " | __error_details__=" <> Pulse.JSON.encode!(details)
      filter = selector <> " | foo>0B" <> rendered_error_details_filter(details)
      labels = %{"job" => job, "foo" => input, "__error__" => "LabelFilterErr", "__error_details__" => details}
      expected = [{labels, ["sample"]}]
      assert_streams(query(ctx, filter), expected)
      assert_streams(request_form(ctx, "/query_range", [query: filter] ++ range(ctx)), expected)
      assert_streams(query(ctx, filter <> ~s/ | __error__=""/), [])

      labels = %{"job" => job, "__error__" => "SampleExtractionErr", "__error_details__" => details}
      expression = ~s/sum_over_time(#{selector} | unwrap bytes(foo) | __error__!=""#{error_filter} [1m])/
      assert_metric(ctx, expression, {1, 2, 1}, %{})
      expression = ~s/sum_over_time(#{selector} | unwrap bytes(foo) | __error__!="" [1m])/
      assert_metric(ctx, expression, {1, 2, 1}, %{labels => [{1, "0"}, {2, "0"}]})
    end

    for {input, bytes} <- [{"1KİB", 1024}, {"2Mİ", 2_097_152}] do
      push(ctx, "sample", ctx.now, %{"job" => input}, %{"foo" => input})
      selector = ~s/{job="#{input}"}/

      assert_streams(query(ctx, selector <> " | foo=" <> to_string(bytes) <> "B"), [
        {%{"job" => input, "foo" => input}, ["sample"]}
      ])

      assert_metric(ctx, "sum_over_time(#{selector} | unwrap bytes(foo) [1m])", 1, %{
        %{"job" => input} => [{1, to_string(bytes)}]
      })
    end

    selector = ~s/{job="byte-diagnostic-0"}/
    details = ~s/strconv.ParseFloat: parsing "": invalid syntax/
    error_filter = rendered_error_details_filter(details)
    expression = selector <> " | foo>0B and foo>0ns" <> error_filter

    assert_streams(query(ctx, expression), [
      {%{
         "job" => "byte-diagnostic-0",
         "foo" => "+5MB",
         "__error__" => "LabelFilterErr",
         "__error_details__" => details
       }, ["sample"]}
    ])

    expression =
      ~s/sum_over_time(#{selector} | label_format __error_details__="ordinary" | unwrap bytes(foo) | __error_details__="ordinary" [1m])/

    response = request(ctx, "/query", [query: expression, time: to_string(ctx.now + @second)], 400)
    assert response["message"] =~ "sample_extraction_error"

    Runtime.put_env(:pulse, Evaluator, max_work: 0)
    expression = "sum_over_time(#{selector} | unwrap bytes(foo) | __error__!=\"\" [1m])"
    response = request(ctx, "/query", [query: expression, time: to_string(ctx.now + @second)], 422)
    assert response["error"] == "query_limit"
    refute Map.has_key?(response, "data")
    assert_parquet(ctx, 3)
  end

  # Loki's own extraction table retains grouping and source ownership, not
  # just the converter inputs. Constructor grouping maps directly to LogQL.
  @tag :quantity_value_batch
  test "Loki extraction table preserves stream, metadata and parsed quantity owners", ctx do
    for {{conversion, input, labels, metadata, line, expected}, index} <-
          Enum.with_index([
            {"duration", "500ms", %{"foo" => "500ms", "bar" => "foo", "buzz" => "blip", "namespace" => "dev"}, %{}, "",
             "0.5"},
            {"duration", "500ms", %{"bar" => "foo", "namespace" => "dev"}, %{"foo" => "500ms", "buzz" => "blip"}, "",
             "0.5"},
            {"bytes", "13 MiB", %{"foo" => "13 MiB", "bar" => "foo", "buzz" => "blip", "namespace" => "dev"}, %{}, "",
             "13631488"},
            {"bytes", "13MiB", %{"foo" => "13MiB", "bar" => "foo", "buzz" => "blip", "namespace" => "dev"}, %{}, "",
             "13631488"},
            {"bytes", "13 MiB", %{"bar" => "foo", "namespace" => "dev"}, %{"foo" => "13 MiB", "buzz" => "blip"}, "",
             "13631488"},
            {"duration", "123.4ms", %{"bar" => "foo"}, %{}, "foo=123.4ms", "0.1234"}
          ]) do
      job = "extract-#{index}"
      push(ctx, line, ctx.now, Map.put(labels, "job", job), metadata)
      parser = if line == "", do: "", else: " | logfmt"
      groups = if input == "123.4ms", do: "bar", else: "bar,buzz"
      query = ~s/avg_over_time({job="#{job}"}#{parser} | unwrap #{conversion}(foo) [1m]) by (#{groups})/
      expected_labels = if input == "123.4ms", do: %{"bar" => "foo"}, else: %{"bar" => "foo", "buzz" => "blip"}
      assert values(instant(ctx, query)) == %{expected_labels => expected}
    end

    assert_parquet(ctx, 6)
    assert_parquet_read(ctx)
  end

  # Pulse control, not an additional upstream scenario.
  @tag :quantity_value_batch
  test "runtime quantities retain range, form and fail-whole budget contracts", ctx do
    for {time, input} <- [{1, "0.9999999999999999999B"}, {61, "42 kb"}] do
      push(ctx, "sample", ctx.now + time * @second, %{"job" => "runtime-bytes"}, %{"foo" => input})
    end

    query = ~s/sum_over_time({job="runtime-bytes"} | unwrap bytes(foo) [1m])/
    assert_metric(ctx, query, {60, 120, 60}, %{%{"job" => "runtime-bytes"} => [{60, "1"}, {120, "42000"}]})
    params = [query: query, time: to_string(ctx.now + 120 * @second)]

    for limit <- [[max_log_samples: 0], [max_work: 0], [max_result_points: 0]] do
      Runtime.put_env(:pulse, Evaluator, limit)
      response = request_form(ctx, "/query", params, 422)
      assert response["error"] == "query_limit"
      refute Map.has_key?(response, "data")
    end
  end

  # Complete TestBinary_Filter and TestBytes_Filter tables in the pinned
  # label_filter_test.go, retaining the original conversion diagnostics.
  # Constructor constants become canonical ns/B literals so unit conversion
  # cannot agree with itself.
  @tag :label_conversion_batch
  @tag :byte_diagnostics_batch
  @tag :number_diagnostics_batch
  test "Loki typed and compound label-filter tables retain conversion failures", ctx do
    cases = [
      {"foo=5 and bar=1000000000ns", %{"foo" => "5", "bar" => "1s"}, true, nil},
      {"foo=5 and bar=42000B", %{"foo" => "5", "bar" => "42kB"}, true, nil},
      {"foo=5 and bar=1000000000ns", %{"foo" => "6", "bar" => "1s"}, false, nil},
      {"foo=5 and bar=1000000000ns", %{"foo" => "5", "bar" => "2s"}, false, nil},
      {~s/foo="5" and bar=1000000000ns/, %{"foo" => "5", "bar" => "1s"}, true, nil},
      {~s/foo="5" and bar=1000000000ns/, %{"foo" => "6", "bar" => "1s"}, false, nil},
      {~s/(duration>1000000000ns or status!=200) and method!="POST"/,
       %{"duration" => "2s", "status" => "200", "method" => "GET"}, true, nil},
      {~s/(duration>1000000000ns or status!=200) and method!="POST"/,
       %{"duration" => "2s", "status" => "200", "method" => "POST"}, false, nil},
      {~s/(duration>1000000000ns or status!=200) and method!="POST"/,
       %{"duration" => "2s", "status" => "500", "method" => "POST"}, false, nil},
      {~s/(duration>3000000000ns or status!=200) and method!="POST"/,
       %{"duration" => "2s", "status" => "200", "method" => "POST"}, false, nil},
      {"duration>3000000000ns", %{"duration" => "2weeeeee"}, true,
       ~s/time: unknown unit "weeeeee" in duration "2weeeeee"/},
      {"bytes>100B", %{"bytes" => "2qb"}, true, "unhandled size name: qb"},
      {"number>100", %{"number" => "not_a_number"}, true,
       ~s/strconv.ParseFloat: parsing "not_a_number": invalid syntax/}
    ]

    for {{filter, labels, keep?, details}, index} <- Enum.with_index(cases) do
      labels = Map.put(labels, "job", "filter-#{index}")
      push(ctx, "sample log line", ctx.now, labels)
      expression = ~s/{job="filter-#{index}"} | / <> filter

      expected =
        if keep? do
          labels =
            if details,
              do: Map.merge(labels, %{"__error__" => "LabelFilterErr", "__error_details__" => details}),
              else: labels

          [{labels, ["sample log line"]}]
        else
          []
        end

      assert_streams(query(ctx, expression), expected)
      assert_streams(request_form(ctx, "/query_range", [{"query", expression} | range(ctx)]), expected)
    end

    assert_parquet(ctx, 13)
    assert_parquet_read(ctx)
  end

  # All float64 error rows from Go's atoftests, Loki's not_a_number input,
  # and separately documented local quoting/failure-precedence controls.
  @tag :number_diagnostics_batch
  test "numeric filter diagnostics preserve exact Go details across HTTP transports", ctx do
    cases = quantity_errors("number")
    assert length(cases) == 48

    streams =
      for {[input, _details], index} <- Enum.with_index(cases) do
        %{
          "stream" => %{"job" => "number-diagnostic-#{index}"},
          "values" => [[to_string(ctx.now), "sample", %{"foo" => input}]]
        }
      end

    push_streams(ctx, streams)

    for {[input, details], index} <- Enum.with_index(cases) do
      job = "number-diagnostic-#{index}"
      selector = ~s/{job="#{job}"}/
      error_filter = rendered_error_details_filter(details)
      filter = selector <> " | foo>0" <> error_filter
      labels = %{"job" => job, "foo" => input, "__error__" => "LabelFilterErr", "__error_details__" => details}
      expected = [{labels, ["sample"]}]
      assert_streams(query(ctx, filter), expected)
      assert_streams(request_form(ctx, "/query_range", [query: filter] ++ range(ctx)), expected)
      assert_streams(query(ctx, filter <> ~s/ | __error__=""/), [])
    end

    selector = ~s/{job="number-diagnostic-10"}/
    details = ~s/strconv.ParseFloat: parsing "1e10000": value out of range/
    error_filter = rendered_error_details_filter(details)
    expression = selector <> " | foo>0 and foo>0ns" <> error_filter

    assert_streams(query(ctx, expression), [
      {%{
         "job" => "number-diagnostic-10",
         "foo" => "1e10000",
         "__error__" => "LabelFilterErr",
         "__error_details__" => details
       }, ["sample"]}
    ])

    Runtime.put_env(:pulse, Evaluator, max_work: 0)
    expression = "count_over_time(#{expression} | __error__!=\"\" [1m])"
    response = request(ctx, "/query", [query: expression, time: to_string(ctx.now + @second)], 422)
    assert response["error"] == "query_limit"
    refute Map.has_key?(response, "data")
    assert_parquet(ctx, 1)
    assert_parquet_read(ctx)
  end

  @tag :number_diagnostics_batch
  test "plain unwrap diagnostics distinguish syntax and range without changing error preservation", ctx do
    cases = quantity_errors("number")

    streams =
      for {[input, _details], index} <- Enum.with_index(cases) do
        %{
          "stream" => %{"job" => "number-unwrap-#{index}"},
          "values" => [[to_string(ctx.now), "sample", %{"foo" => input}]]
        }
      end

    push_streams(ctx, streams)

    for {[input, details], index} <- Enum.with_index(cases) do
      selector = ~s/{job="number-unwrap-#{index}"}/
      unwrap = selector <> " | unwrap foo"
      expression = "sum_over_time(#{unwrap} [1m])"

      if input == "" do
        assert values(instant(ctx, expression)) == %{}
      else
        params = [query: expression, time: to_string(ctx.now + @second)]
        assert request(ctx, "/query", params, 400)["message"] =~ "sample_extraction_error"
        assert values(instant(ctx, "sum_over_time(#{unwrap} | __error__=\"\" [1m])")) == %{}

        labels = %{
          "job" => "number-unwrap-#{index}",
          "__error__" => "SampleExtractionErr",
          "__error_details__" => details
        }

        error_filter = " | __error_details__=" <> Pulse.JSON.encode!(details)
        expression = "sum_over_time(#{unwrap} | __error__!=\"\"#{error_filter} [1m])"
        assert_metric(ctx, expression, {1, 2, 1}, %{})
        expression = "sum_over_time(#{unwrap} | __error__!=\"\" [1m])"
        assert_metric(ctx, expression, {1, 2, 1}, %{labels => [{1, "0"}, {2, "0"}]})
      end
    end

    assert_parquet(ctx, 1)
    assert_parquet_read(ctx)
  end

  # Exact inputs, source owners, grouping and details from Loki's
  # metrics_extraction_test.go:201-227. Explicit __error__ selection exposes
  # the extractor's kept zero-valued samples through the metric endpoint.
  @tag :number_diagnostics_batch
  test "Loki failed numeric extraction preserves stream and structured metadata owners", ctx do
    cases = [
      {"number-stream", %{"foo" => "not_a_number", "bar" => "foo"}, %{}},
      {"number-metadata", %{"bar" => "foo"}, %{"foo" => "not_a_number"}}
    ]

    labels = %{
      "bar" => "foo",
      "__error__" => "SampleExtractionErr",
      "__error_details__" => ~s/strconv.ParseFloat: parsing "not_a_number": invalid syntax/
    }

    for {job, stream, metadata} <- cases do
      push(ctx, "", ctx.now, Map.put(stream, "job", job), metadata)
      expression = ~s/avg_over_time({job="#{job}"} | unwrap foo | __error__!="" [1m]) by (bar,buzz)/
      assert_metric(ctx, expression, 1, %{labels => [{1, "0"}]})
    end

    assert_parquet(ctx, 2)
  end

  @tag :logfmt_expression_batch
  test "Loki explicit logfmt tables preserve original fields and grammar admission", ctx do
    fixture = "test/fixtures/logs/loki-upstream/logfmt-expressions.json" |> File.read!() |> Pulse.JSON.decode!()
    assert length(fixture["expression_cases"]) == 9
    assert length(fixture["grammar_cases"]) == 5

    streams =
      for {row, index} <- Enum.with_index(fixture["expression_cases"]) do
        %{
          "stream" => Map.put(row["base_labels"], "fixture", to_string(index)),
          "values" => [[to_string(ctx.now), row["line"]]]
        }
      end

    push_streams(ctx, streams)

    for {row, index} <- Enum.with_index(fixture["expression_cases"]) do
      fields = Enum.map_join(row["fields"], ", ", fn [name, source] -> name <> "=" <> Pulse.JSON.encode!(source) end)
      params = [query: ~s/{fixture="#{index}"} | logfmt / <> fields] ++ range(ctx)

      for response <- [request(ctx, "/query_range", params), request_form(ctx, "/query_range", params)] do
        actual =
          Map.new(flattened_entries(response), fn {{timestamp, line, labels}, count} ->
            # Loki's unit builder has no ingest-time severity promotion.
            # Assert Pulse's extra label separately; preserve the source oracle.
            labels =
              if Map.has_key?(row["base_labels"], "level") do
                assert labels["detected_level"] == row["base_labels"]["level"]
                Map.delete(labels, "detected_level")
              else
                labels
              end

            {{timestamp, line, Map.delete(labels, "fixture")}, count}
          end)

        assert actual == %{{to_string(ctx.now), row["line"], row["want"]} => 1},
               "#{row["name"]}: #{inspect(actual)}"
      end
    end

    # Grammar tables have no log-line fixture. Both accepted source names
    # exist in this separate control; rejected rows must not reach storage.
    push(ctx, "app=one id8=two", ctx.now, %{"job" => "logfmt-grammar"})
    failure = fixture["constructor_failure"]
    rows = fixture["grammar_cases"] ++ [Map.put(failure, "outcome", "reject")]

    for row <- rows do
      destination = Map.get(row, "destination", "value")
      expression = ~s/{job="logfmt-grammar"} | logfmt #{destination}=/ <> Pulse.JSON.encode!(row["expression"])
      params = [query: expression] ++ range(ctx)
      before = Agent.get(ctx.store, & &1.requests)
      status = if row["outcome"] == "accept", do: 200, else: 400

      for response <- [request(ctx, "/query_range", params, status), request_form(ctx, "/query_range", params, status)] do
        if status == 200 do
          value = if row["expression"] == "app", do: "one", else: "two"
          assert_streams(response, [{%{"job" => "logfmt-grammar", "value" => value}, ["app=one id8=two"]}])
        else
          assert response["status"] == "error"
        end
      end

      if status == 400, do: assert(Agent.get(ctx.store, & &1.requests) == before)
    end

    assert_parquet(ctx, 2)
    assert_parquet_read(ctx)
  end

  # Source-derived controls for the pinned NewLogfmtExpressionParser.Process,
  # not additional rows from its public test table. Expected labels were also
  # checked by executing that parser with its real, unhinted LabelsBuilder.
  @tag :logfmt_destination_batch
  test "explicit logfmt destinations follow line order and discard replacement-rune values", ctx do
    cases = [
      {[{"dst", "source"}], "dst=own", %{"dst" => "own"}},
      {[{"dst", "source"}], "source=first dst=last", %{"dst" => "last"}},
      {[{"dst", "source"}], "dst=first source=last", %{"dst" => "last"}},
      {[{"dst", "source"}], "source=first dst=middle source=last", %{"dst" => "last"}},
      {[{"dst", "a_b"}], "a.b=first dst=last", %{"dst" => "last"}},
      {[{"dst", "a"}, {"dst", "b"}], "a=ignored b=selected dst=last", %{"dst" => "last"}},
      {[{"dst", "a"}, {"dst", "b"}], "a=ignored", %{"dst" => ""}},
      {[{"dst", "a"}, {"dst", "b"}], "dst=kept a=ignored", %{"dst" => "kept"}},
      {[{"p", "a"}, {"a", "b"}], "a=one b=two", %{"p" => "one", "a" => "two"}},
      {[{"p", "a"}, {"a", "b"}], "b=two a=one", %{"p" => "one", "a" => "two"}},
      {[{"dst", "source"}], "source=first source=last", %{"dst" => "last"}},
      {[{"dst", "source"}], "source=old source=", %{"dst" => ""}},
      {[{"dst", "source"}], "source=old source", %{"dst" => ""}},
      {[{"dst", "source"}], "source=before�after", %{"dst" => ""}},
      {[{"dst", "source"}], ~S/source="before\uFFFDafter"/, %{"dst" => ""}},
      {[{"dst", "source"}], ~S/source="before\uD800after"/, %{"dst" => ""}},
      {[{"dst", "source"}], ~S/source="\uD83D\uDE00"/, %{"dst" => "😀"}},
      {[{"dst", "source"}], "source=before�after dst=valid", %{"dst" => "valid"}},
      {[{"dst", "source"}], "source=valid dst=before�after", %{"dst" => ""}}
    ]

    streams =
      for {{_fields, line, _want}, index} <- Enum.with_index(cases) do
        %{"stream" => %{"fixture" => to_string(index)}, "values" => [[to_string(ctx.now), line]]}
      end

    push_streams(ctx, streams)

    for {{fields, line, want}, index} <- Enum.with_index(cases), strict <- ["", "--strict "] do
      fields = Enum.map_join(fields, ", ", fn {name, source} -> name <> "=" <> Pulse.JSON.encode!(source) end)
      expression = ~s/{fixture="#{index}"} | logfmt / <> strict <> fields
      params = [query: expression] ++ range(ctx)
      expected = [{Map.put(want, "fixture", to_string(index)), [line]}]

      for response <- [request(ctx, "/query_range", params), request_form(ctx, "/query_range", params)] do
        assert_streams(response, expected)
      end
    end

    assert_parquet(ctx, 1)
    assert_parquet_read(ctx)
  end

  @tag :logfmt_destination_batch
  test "explicit logfmt ordering preserves strict errors and metric admission", ctx do
    lines = ["source=2 dst=10", ~S/source=3 broken="\q" dst=20/, "source=4 dst=before�after"]
    labels = %{"job" => "logfmt-order-metric"}
    push_streams(ctx, [%{"stream" => labels, "values" => Enum.map(lines, &[to_string(ctx.now), &1])}])

    for {flags, sum} <- [{"", "30"}, {"--strict ", "10"}] do
      expression =
        ~s/sum(sum_over_time({job="logfmt-order-metric"} | logfmt #{flags}dst="source" | unwrap dst | __error__="" [1m]))/

      assert_metric(ctx, expression, 0, %{%{} => [{0, sum}]})
    end

    # A later duplicate destination must not hide an invalid earlier source.
    for fields <- [~s/dst="bad field", dst="source"/, ~s/dst="source", dst="bad field"/] do
      expression = ~s/{job="logfmt-order-metric"} |= "never matches" | logfmt / <> fields
      params = [query: expression] ++ range(ctx)
      before = Agent.get(ctx.store, & &1.requests)
      assert request(ctx, "/query_range", params, 400)["status"] == "error"
      assert request_form(ctx, "/query_range", params, 400)["status"] == "error"
      assert Agent.get(ctx.store, & &1.requests) == before
    end

    assert_parquet(ctx, 1)
    assert_parquet_read(ctx)
  end

  @tag :logfmt_expression_batch
  test "explicit logfmt sources use normalized keys and reject invalid expressions before storage", ctx do
    labels = %{"job" => "logfmt-expression", "missing" => "stream"}
    line = "a.b=one a_b=two 9x=three field=bad fieldwithÜFT8👌=four"
    push(ctx, line, ctx.now, labels)

    expression = ~s/{job="logfmt-expression"} | logfmt dotted="a_b", digit="_9x", unicode="fieldwith_FT8_", missing/
    expected = [{Map.merge(labels, %{"dotted" => "two", "digit" => "three", "unicode" => "four"}), [line]}]

    for response <- [query(ctx, expression), request_form(ctx, "/query_range", [query: expression] ++ range(ctx))] do
      assert_streams(response, expected)
    end

    # The field expression itself can quote its source; this is not a JSON
    # path, and the source is the normalized key rather than the raw line key.
    quoted = ~s/{job="logfmt-expression"} | logfmt value=`"_9x"`/
    assert_streams(query(ctx, quoted), [{Map.put(labels, "value", "three"), [line]}])

    # Inner quotes are field-lexer syntax, not another Go/JSON unquote layer.
    # Empty quoted source is valid, unlike an empty field expression.
    for {source, value} <- [
          {"\"_9x", "three"},
          {"\"_9x]", "three"},
          {"_9x\0ignored", "three"},
          {"\t_9x\n", "three"},
          {~s/""/, ""},
          {~s/_9x "extra"/, ""},
          {~s/"_9x" "extra" "more"/, ""},
          {~s/"_9x\\n"/, ""}
        ] do
      raw = ~s/{job="logfmt-expression"} | logfmt value=/ <> Pulse.JSON.encode!(source)
      assert_streams(query(ctx, raw), [{Map.put(labels, "value", value), [line]}])
    end

    for source <- ["field with space", "fieldwithÜFT8👌", "a.b", "9x", "", "field\r"] do
      raw = ~s/{job="logfmt-expression"} |= "never matches" | logfmt value=/ <> Pulse.JSON.encode!(source)

      for {path, params} <- [
            {"/query_range", [query: raw] ++ range(ctx)},
            {"/query", [query: "count_over_time(#{raw} [1m])", time: to_string(ctx.now)]}
          ] do
        before = Agent.get(ctx.store, & &1.requests)
        assert request(ctx, path, params, 400)["status"] == "error"
        assert request_form(ctx, path, params, 400)["status"] == "error"
        assert Agent.get(ctx.store, & &1.requests) == before
      end
    end

    for limit <- [[max_work: 0], [max_log_samples: 0], [max_result_points: 0]] do
      Runtime.put_env(:pulse, Evaluator, limit)
      params = [query: "count_over_time(#{expression} [1m])", time: to_string(ctx.now)]
      response = request_form(ctx, "/query", params, 422)
      assert response["error"] == "query_limit"
      refute Map.has_key?(response, "data")
    end

    assert_parquet(ctx, 1)
    assert_parquet_read(ctx)
  end

  @tag :logfmt_batch
  test "logfmt strict parsing, recovery and empty-value policies survive storage", ctx do
    labels = %{"job" => "logfmt-controls"}

    lines = [
      ~s/good=1 bad="unterminated/,
      ~S/good=2 broken="\q" tail=3/,
      ~S/n=1 n=2 empty= bare escaped="a\nb"/,
      "x=bu=zz after=4",
      ~S/face="\uD83D\uDE00" lone="\uD800" apostrophe="it\'s"/
    ]

    push_streams(ctx, [%{"stream" => labels, "values" => Enum.map(lines, &[to_string(ctx.now), &1])}])

    response = query(ctx, ~s/{job="logfmt-controls"} | logfmt/)
    entries = flattened_entries(response)

    assert entries ==
             Enum.frequencies([
               {to_string(ctx.now), Enum.at(lines, 0), Map.put(labels, "good", "1")},
               {to_string(ctx.now), Enum.at(lines, 1), Map.merge(labels, %{"good" => "2", "tail" => "3"})},
               {to_string(ctx.now), Enum.at(lines, 2), Map.merge(labels, %{"n" => "1", "escaped" => "a\nb"})},
               {to_string(ctx.now), Enum.at(lines, 3), Map.put(labels, "after", "4")},
               {to_string(ctx.now), Enum.at(lines, 4),
                Map.merge(labels, %{"face" => "😀", "lone" => " ", "apostrophe" => "it's"})}
             ])

    params = [query: ~s/{job="logfmt-controls"} | logfmt --strict/] ++ range(ctx)
    response = request_form(ctx, "/query_range", params)
    errors = Enum.filter(response["data"]["result"], &(&1["stream"]["__error__"] == "LogfmtParserErr"))
    assert length(errors) == 3

    details =
      Map.new(
        for stream <- errors, [_timestamp, line] <- stream["values"], do: {line, stream["stream"]["__error_details__"]}
      )

    assert details == %{
             Enum.at(lines, 0) => "logfmt syntax error at pos 25 : unterminated quoted value",
             Enum.at(lines, 1) => "logfmt syntax error at pos 19 : invalid quoted value",
             Enum.at(lines, 3) => "logfmt syntax error at pos 5 : unexpected '='"
           }

    assert_metric(ctx, ~s/sum(count_over_time({job="logfmt-controls"} | logfmt --strict | __error__="" [1m]))/, 0, %{
      %{} => [{0, "2"}]
    })

    assert_metric(ctx, ~s/sum(count_over_time({job="logfmt-controls"} | logfmt [1m]))/, 0, %{%{} => [{0, "5"}]})

    for limit <- [[max_work: 0], [max_log_samples: 0], [max_result_points: 0]] do
      Runtime.put_env(:pulse, Evaluator, limit)

      params = [
        query: ~s/count_over_time({job="logfmt-controls"} | logfmt --keep-empty [1m])/,
        time: to_string(ctx.now)
      ]

      assert request_form(ctx, "/query", params, 422)["error"] == "query_limit"
    end

    assert_parquet(ctx, 1)
  end

  @tag :logfmt_batch
  test "Loki logfmt parser tables preserve strict errors and empty-value labels", ctx do
    fixture = "test/fixtures/logs/loki-upstream/logfmt.json" |> File.read!() |> Pulse.JSON.decode!()
    cases = fixture["parse_cases"] ++ fixture["keep_empty_cases"]
    assert length(cases) == 23

    streams =
      for {row, index} <- Enum.with_index(cases) do
        %{
          "stream" => Map.put(row["base_labels"], "fixture", to_string(index)),
          "values" => [[to_string(ctx.now), row["line"] || ""]]
        }
      end

    push_streams(ctx, streams)

    for {row, index} <- Enum.with_index(cases), strict? <- [false, true] do
      flags = if row["keep_empty"], do: " --keep-empty", else: ""
      flags = if strict?, do: flags <> " --strict", else: flags
      expression = ~s/{fixture="#{index}"} | logfmt#{flags}/
      params = [{"query", expression} | range(ctx)]
      expected = if strict?, do: row["effective_strict_want"], else: row["want"]

      for response <- [request(ctx, "/query_range", params), request_form(ctx, "/query_range", params)] do
        actual =
          Map.new(flattened_entries(response), fn {{timestamp, line, labels}, count} ->
            {{timestamp, line, Map.delete(labels, "fixture")}, count}
          end)

        assert actual == %{{to_string(ctx.now), row["line"] || "", expected} => 1},
               "#{row["name"]}, strict=#{strict?}: #{inspect(actual)}"
      end
    end

    assert_parquet(ctx, 1)
    assert_parquet_read(ctx)
  end

  @tag :logfmt_batch
  test "Loki logfmt engine fixtures retain every instant, range and rejected result", ctx do
    fixture = "test/fixtures/logs/loki-upstream/logfmt.json" |> File.read!() |> Pulse.JSON.decode!()
    assert length(fixture["fixtures"]) == 4
    assert fixture["counts"]["engine_evaluations"] == 14
    base = div(ctx.now, @second) * @second - 2_000 * @second

    for {input, index} <- Enum.with_index(fixture["fixtures"]) do
      ctx = %{ctx | now: base + index * 300 * @second}

      streams =
        for load <- input["loads"] do
          values =
            for repeat <- 0..(load["count"] - 1) do
              stamp = ctx.now + (load["start"] + repeat * load["every"]) * @second
              [to_string(stamp), load["line"], load["metadata"]]
            end

          %{"stream" => load["labels"], "values" => values}
        end

      push_streams(ctx, streams)

      for row <- input["cases"] do
        if row["outcome"] == "reject" do
          params = [query: row["query"], time: to_string(ctx.now + row["start"] * @second)]

          for response <- [request(ctx, "/query", params, 400), request_form(ctx, "/query", params, 400)] do
            assert response["error"] == "evaluation_failed"
            assert response["message"] =~ "pipeline_error"
            refute Map.has_key?(response, "data")
          end

          raw = row["query"] |> String.replace_prefix("count_over_time(", "") |> String.replace_suffix(" [1m])", "")

          params = [
            query: raw,
            start: to_string(ctx.now + 1),
            end: to_string(ctx.now + 60 * @second)
          ]

          for response <- [request(ctx, "/query_range", params), request_form(ctx, "/query_range", params)] do
            assert response["data"]["result"] != []
            assert Enum.all?(response["data"]["result"], &(&1["stream"]["__error__"] == row["reject"]))
          end
        else
          time = if row["instant"], do: row["start"], else: {row["start"], row["end"], row["step"]}
          times = if row["instant"], do: [row["start"]], else: Enum.to_list(row["start"]..row["end"]//row["step"])

          expected =
            Map.new(row["expected"], fn series ->
              {series["labels"], for({t, v} <- Enum.zip(times, series["values"]), v != "_", do: {t, v})}
            end)

          assert_metric(ctx, row["query"], time, expected)
        end
      end
    end

    assert_parquet(ctx, 4)
    assert_parquet_read(ctx)
  end

  @tag :logfmt_ownership_batch
  test "Loki structured-metadata conflict tables retain their original flat-label oracles", ctx do
    fixture = "test/fixtures/logs/loki-upstream/logfmt-ownership.json" |> File.read!() |> Pulse.JSON.decode!()
    assert length(fixture["table_cases"]) == 2

    for {row, index} <- Enum.with_index(fixture["table_cases"]) do
      labels = Map.put(row["base_labels"], "fixture", to_string(index))
      push(ctx, row["line"], ctx.now, labels, row["structured_metadata"])

      fields =
        Enum.map_join(row["fields"] || [], ", ", fn [destination, source] ->
          destination <> "=" <> Pulse.JSON.encode!(source)
        end)

      for strict? <- row["strict_values"] do
        flags = if strict?, do: " --strict", else: ""
        expression = ~s/{fixture="#{index}"} | logfmt#{flags} #{fields}/
        params = [{"query", expression} | range(ctx)]
        expected = if strict?, do: row["effective_strict_want"], else: row["want"]

        for response <- [request(ctx, "/query_range", params), request_form(ctx, "/query_range", params)] do
          actual =
            Map.new(flattened_entries(response), fn {{timestamp, line, labels}, count} ->
              {{timestamp, line, Map.delete(labels, "fixture")}, count}
            end)

          assert actual == %{{to_string(ctx.now), row["line"], expected} => 1}, row["name"]
        end
      end
    end

    assert_parquet(ctx, 2)
    assert_parquet_read(ctx)
  end

  @tag :logfmt_ownership_batch
  test "Loki ownership engine fixtures preserve metrics and categorized drop/re-add results", ctx do
    fixture = "test/fixtures/logs/loki-upstream/logfmt-ownership.json" |> File.read!() |> Pulse.JSON.decode!()
    assert fixture["counts"]["engine_evaluations"] == 10
    base = div(ctx.now, @second) * @second - 2_000 * @second

    for {input, index} <- Enum.with_index(fixture["fixtures"]) do
      ctx = %{ctx | now: base + index * 300 * @second}

      streams =
        for load <- input["loads"] do
          values =
            for repeat <- 0..(load["count"] - 1) do
              stamp = ctx.now + (load["start"] + repeat * load["every"]) * @second
              [to_string(stamp), load["line"], load["metadata"]]
            end

          %{"stream" => load["labels"], "values" => values}
        end

      push_streams(ctx, streams)

      for row <- input["cases"] do
        if row["mode"] == "select" do
          params = [
            query: row["query"],
            start: to_string(ctx.now + row["start"] * @second),
            end: to_string(ctx.now + row["end"] * @second),
            direction: row["direction"]
          ]

          expected =
            for entry <- row["expected_entries"] do
              categories =
                %{"structuredMetadata" => entry["metadata"], "parsed" => entry["parsed"]}
                |> Map.reject(fn {_name, labels} -> labels == %{} end)

              %{
                "stream" => entry["labels"],
                "values" => [[to_string(ctx.now + entry["timestamp"] * @second), entry["line"], categories]]
              }
            end

          for response <- [
                request(categorize(ctx), "/query_range", params),
                request_form(categorize(ctx), "/query_range", params)
              ] do
            assert response["data"]["result"] == expected, row["query"]
          end
        else
          time = if row["mode"] == "instant", do: row["start"], else: {row["start"], row["end"], row["step"]}

          times =
            if row["mode"] == "instant", do: [row["start"]], else: Enum.to_list(row["start"]..row["end"]//row["step"])

          expected =
            Map.new(row["expected"], fn series ->
              {series["labels"], for({t, v} <- Enum.zip(times, series["values"]), do: {t, v})}
            end)

          assert_metric(ctx, row["query"], time, expected)
        end
      end
    end

    assert_parquet(ctx, 3)
    assert_parquet_read(ctx)
  end

  @tag :logfmt_ownership_batch
  test "repeated parsers keep extraction history across line rewrites and drops", ctx do
    cases = [
      {"logfmt", "k=first", "k=second", "k=second", "first"},
      {~s/regexp "k=(?P<k>.+)"/, "k=first", "k=second", "k=second", "first"},
      {~s/pattern "k=<k>"/, "k=first", "k=second", "k=second", "first"},
      {"json", ~s/{"k":"first"}/, ~s/{"k":"second"}/, ~s/{"k":"second"}/, "first"},
      {"unpack", ~s/{"k":"first","_entry":"old"}/, ~s/{"k":"second","_entry":"new"}/, "new", "first"},
      {~s/json k="k"/, ~s/{"k":"first"}/, ~s/{"k":"second"}/, ~s/{"k":"second"}/, "second"}
    ]

    for {{stage, line, next, final, value}, index} <- Enum.with_index(cases) do
      job = "repeated-#{index}"
      push(ctx, line, ctx.now, %{"job" => job, "k" => "stream"}, %{"k" => "metadata"})

      for drop? <- [false, true] do
        drop = if drop?, do: " | drop k_extracted", else: ""
        expression = ~s/{job="#{job}"} | #{stage}#{drop} | line_format / <> Pulse.JSON.encode!(next) <> " | " <> stage
        parsed = if drop? and value == "first", do: %{}, else: %{"k_extracted" => value}
        categories = if parsed == %{}, do: %{}, else: %{"parsed" => parsed}
        params = [{"query", expression} | range(ctx)]

        for response <- [
              request(categorize(ctx), "/query_range", params),
              request_form(categorize(ctx), "/query_range", params)
            ] do
          assert response["data"]["result"] == [
                   %{
                     "stream" => %{"job" => job, "k" => "stream"},
                     "values" => [[to_string(ctx.now), final, categories]]
                   }
                 ],
                 expression
        end
      end
    end

    assert_parquet(ctx, 6)
    assert_parquet_read(ctx)
  end

  @tag :logfmt_ownership_batch
  test "explicit logfmt halts on extracted suffixes and selects one shared-source alias", ctx do
    push(ctx, "k=first n=3", ctx.now, %{"job" => "halt", "k" => "stream"})

    expression =
      ~s/{job="halt"} | logfmt | line_format `k=second n=7 broken="` | logfmt --strict k, n/

    # The colliding, already extracted k suffix stops parsing before n=7 or
    # the malformed quote. Unprotected explicit destinations still default empty.
    for response <- [query(ctx, expression), query(categorize(ctx), expression)] do
      assert flattened_entries(response) == %{
               {to_string(ctx.now), ~s/k=second n=7 broken="/,
                %{"job" => "halt", "k" => "stream", "k_extracted" => "first", "n" => ""}} => 1
             }
    end

    push(ctx, "v=1 v=2", ctx.now, %{"job" => "alias"})

    for fields <- [~s/a="v", b="v"/, ~s/b="v", a="v"/] do
      # Loki's map iteration chooses one alias nondeterministically. Pulse
      # chooses the lexically first destination, one of those valid outcomes.
      params = [{"query", ~s/{job="alias"} | logfmt #{fields}/} | range(ctx)]

      for response <- [request(ctx, "/query_range", params), request_form(ctx, "/query_range", params)] do
        assert flattened_entries(response) == %{
                 {to_string(ctx.now), "v=1 v=2", %{"job" => "alias", "a" => "2", "b" => ""}} => 1
               }
      end
    end

    assert_parquet(ctx, 2)
  end

  @tag :json_parser_batch
  test "JSON extraction preserves source order, nested scalars and numeric spelling", ctx do
    line =
      ~s/{"obj":{"x":1,"y":{"z":2}},"obj_x":9,"a.b":1e+03,"zero":-0,"large":9223372036854775809,"text":"v1e+03","dup":"first","dup":"second","nil":null,"arr":[1,2],"ok":true}/

    push(ctx, line, ctx.now, %{"job" => "json-order"})
    expression = ~s/{job="json-order"} | json/

    expected = %{
      "job" => "json-order",
      "obj_x" => "1",
      "obj_y_z" => "2",
      "a_b" => "1e+03",
      "zero" => "-0",
      "large" => "9223372036854775809",
      "text" => "v1e+03",
      "dup" => "first",
      "ok" => "true"
    }

    params = [{"query", expression} | range(ctx)]

    for response <- [request(ctx, "/query_range", params), request_form(ctx, "/query_range", params)] do
      assert flattened_entries(response) == %{{to_string(ctx.now), line, expected} => 1}
    end

    assert_metric(ctx, ~s/sum_over_time(#{expression} | unwrap a_b [1m])/, 0, %{
      Map.delete(expected, "a_b") => [{0, "1000"}]
    })

    push(ctx, ~s/{"n":null}/, ctx.now, %{"job" => "json-missing"}, %{"n" => "metadata", "missing" => "retained"})
    params = [{"query", ~s/{job="json-missing"} | json n, missing="absent"/} | range(ctx)]

    for response <- [request(ctx, "/query_range", params), request_form(ctx, "/query_range", params)] do
      assert flattened_entries(response) == %{
               {to_string(ctx.now), ~s/{"n":null}/,
                %{"job" => "json-missing", "n" => "metadata", "n_extracted" => "", "missing" => "retained"}} => 1
             }
    end

    assert_parquet_read(ctx)
  end

  @tag :json_parser_batch
  test "Loki JSON parser table preserves exact flattened labels and errors", ctx do
    fixture = "test/fixtures/logs/loki-upstream/json-parser.json" |> File.read!() |> Pulse.JSON.decode!()
    assert length(fixture["parse_cases"]) == 16

    streams =
      for {row, index} <- Enum.with_index(fixture["parse_cases"]) do
        %{
          "stream" => Map.put(row["base_labels"], "fixture", to_string(index)),
          "values" => [[to_string(ctx.now), row["line"], row["structured_metadata"]]]
        }
      end

    push_streams(ctx, streams)

    # The hinted error row has the same public output without hints. Its
    # upstream hint object and JSON-path bookkeeping are provenance, not APIs.
    for {row, index} <- Enum.with_index(fixture["parse_cases"]) do
      params = [{"query", ~s/{fixture="#{index}"} | json/} | range(ctx)]

      for response <- [request(ctx, "/query_range", params), request_form(ctx, "/query_range", params)] do
        actual =
          Map.new(flattened_entries(response), fn {{timestamp, line, labels}, count} ->
            {{timestamp, line, Map.delete(labels, "fixture")}, count}
          end)

        assert actual == %{{to_string(ctx.now), row["line"], row["want"]} => 1}, row["name"]
      end
    end

    assert_parquet(ctx, 1)
    assert_parquet_read(ctx)
  end

  @tag :json_parser_batch
  test "Loki JSON engine fixtures preserve all metric, error and categorized results", ctx do
    fixture = "test/fixtures/logs/loki-upstream/json-parser.json" |> File.read!() |> Pulse.JSON.decode!()
    assert fixture["counts"]["engine_evaluations"] == 42
    base = div(ctx.now, @second) * @second - 3_000 * @second

    for {input, index} <- Enum.with_index(fixture["fixtures"]) do
      ctx = %{ctx | now: base + index * 300 * @second}
      promoted_level = Enum.find_value(input["loads"], & &1["labels"]["level"])

      streams =
        for load <- input["loads"] do
          values =
            for repeat <- 0..(load["count"] - 1) do
              stamp = ctx.now + (load["start"] + repeat * load["every"]) * @second
              [to_string(stamp), load["line"], load["metadata"]]
            end

          %{"stream" => load["labels"], "values" => values}
        end

      push_streams(ctx, streams)

      for row <- input["cases"] do
        cond do
          row["outcome"] == "reject" ->
            params = [query: row["query"], time: to_string(ctx.now + row["start"] * @second)]

            for response <- [request(ctx, "/query", params, 400), request_form(ctx, "/query", params, 400)] do
              assert response["error"] == "evaluation_failed"
              assert response["message"] =~ "pipeline_error"
              refute Map.has_key?(response, "data")
            end

          row["mode"] == "select" ->
            params = [
              query: row["query"],
              start: to_string(ctx.now + row["start"] * @second),
              end: to_string(ctx.now + row["end"] * @second),
              direction: row["direction"]
            ]

            expected =
              for entry <- row["expected_entries"] do
                %{
                  "stream" => entry["labels"],
                  "values" => [
                    [to_string(ctx.now + entry["timestamp"] * @second), entry["line"], %{"parsed" => entry["parsed"]}]
                  ]
                }
              end

            for response <- [
                  request(categorize(ctx), "/query_range", params),
                  request_form(categorize(ctx), "/query_range", params)
                ] do
              assert response["data"]["result"] == expected
            end

          true ->
            time = if row["mode"] == "instant", do: row["start"], else: {row["start"], row["end"], row["step"]}

            times =
              if row["mode"] == "instant", do: [row["start"]], else: Enum.to_list(row["start"]..row["end"]//row["step"])

            expected =
              Map.new(row["expected"], fn series ->
                # HTTP ingest promotes a source stream level to detected_level;
                # the upstream engine loads bypass that receiver behavior.
                labels =
                  if promoted_level && Map.has_key?(series["labels"], "level"),
                    do: Map.put(series["labels"], "detected_level", promoted_level),
                    else: series["labels"]

                {labels, for({t, v} <- Enum.zip(times, series["values"]), v != "_", do: {t, v})}
              end)

            assert_metric(ctx, row["query"], time, expected)
        end
      end
    end

    assert_parquet(ctx, 7)
    assert_parquet_read(ctx)
  end

  @tag :json_expression_batch
  test "Loki explicit JSON table preserves raw values, paths, errors and metadata", ctx do
    fixture = "test/fixtures/logs/loki-upstream/json-expressions.json" |> File.read!() |> Pulse.JSON.decode!()
    assert length(fixture["expression_cases"]) == 29

    streams =
      for {row, index} <- Enum.with_index(fixture["expression_cases"]) do
        %{
          "stream" => Map.put(row["base_labels"], "fixture", to_string(index)),
          "values" => [[to_string(ctx.now), row["line"], row["structured_metadata"]]]
        }
      end

    push_streams(ctx, streams)

    for {row, index} <- Enum.with_index(fixture["expression_cases"]) do
      fields = Enum.map_join(row["fields"], ", ", fn [name, path] -> name <> "=" <> Pulse.JSON.encode!(path) end)
      params = [{"query", ~s/{fixture="#{index}"} | json #{fields}/} | range(ctx)]

      for response <- [request(ctx, "/query_range", params), request_form(ctx, "/query_range", params)] do
        actual =
          Map.new(flattened_entries(response), fn {{timestamp, line, labels}, count} ->
            {{timestamp, line, Map.delete(labels, "fixture")}, count}
          end)

        assert actual == %{{to_string(ctx.now), row["line"], row["want"]} => 1}, row["name"]
      end
    end

    assert_parquet_read(ctx)
  end

  @tag :json_expression_batch
  test "Loki JSON path grammar selects original typed paths and rejects invalid paths before reads", ctx do
    fixture = "test/fixtures/logs/loki-upstream/json-expressions.json" |> File.read!() |> Pulse.JSON.decode!()
    assert length(fixture["grammar_cases"]) == 18

    for {row, index} <- Enum.with_index(fixture["grammar_cases"]), row["outcome"] == "path" do
      # Build input from the upstream path oracle, never the parsed Pulse path.
      nested =
        Enum.reduce(Enum.reverse(row["want"]), "selected", fn
          index, value when is_integer(index) -> List.duplicate("distractor", index) ++ [value, "other"]
          key, value -> %{key => value, "unrelated" => "other"}
        end)

      labels = %{"fixture" => "grammar-#{index}"}
      line = Pulse.JSON.encode!(nested)
      push(ctx, line, ctx.now, labels)
      expression = ~s/{fixture="grammar-#{index}"} | json result=/ <> Pulse.JSON.encode!(row["expression"])
      params = [{"query", expression} | range(ctx)]

      for response <- [request(ctx, "/query_range", params), request_form(ctx, "/query_range", params)] do
        assert flattened_entries(response) == %{{to_string(ctx.now), line, Map.put(labels, "result", "selected")} => 1}
      end
    end

    invalid =
      fixture["constructor_failure_cases"] ++ Enum.filter(fixture["grammar_cases"], &(&1["outcome"] == "reject"))

    before_reads = Agent.get(ctx.store, & &1.reads)

    for row <- invalid do
      expression = ~s/{fixture=~".+"} | json result=/ <> Pulse.JSON.encode!(row["expression"])
      params = [{"query", expression} | range(ctx)]

      for response <- [request(ctx, "/query_range", params, 400), request_form(ctx, "/query_range", params, 400)] do
        assert response["error"] == "evaluation_failed"
        assert response["message"] =~ "invalid_json_expression"
        refute Map.has_key?(response, "data")
      end
    end

    assert Agent.get(ctx.store, & &1.reads) == before_reads
  end

  @tag :json_expression_batch
  test "Loki explicit JSON engine fixture retains array indices, missing paths and sparse windows", ctx do
    fixture = "test/fixtures/logs/loki-upstream/json-expressions.json" |> File.read!() |> Pulse.JSON.decode!()
    [input] = fixture["fixtures"]
    ctx = %{ctx | now: div(ctx.now, @second) * @second - 300 * @second}

    streams =
      for load <- input["loads"] do
        values =
          for repeat <- 0..(load["count"] - 1) do
            stamp = ctx.now + (load["start"] + repeat * load["every"]) * @second
            [to_string(stamp), load["line"], load["metadata"]]
          end

        %{"stream" => load["labels"], "values" => values}
      end

    push_streams(ctx, streams)

    for row <- input["cases"] do
      if row["outcome"] == "reject" do
        before_reads = Agent.get(ctx.store, & &1.reads)
        params = [query: row["query"], time: to_string(ctx.now + row["start"] * @second)]

        for response <- [request(ctx, "/query", params, 400), request_form(ctx, "/query", params, 400)] do
          assert response["error"] == "evaluation_failed"
          assert response["message"] =~ "invalid_json_expression"
        end

        assert Agent.get(ctx.store, & &1.reads) == before_reads
      else
        time = if row["mode"] == "instant", do: row["start"], else: {row["start"], row["end"], row["step"]}

        times =
          if row["mode"] == "instant", do: [row["start"]], else: Enum.to_list(row["start"]..row["end"]//row["step"])

        expected =
          Map.new(row["expected"], fn series ->
            {series["labels"], for({t, v} <- Enum.zip(times, series["values"]), v != "_", do: {t, v})}
          end)

        assert_metric(ctx, row["query"], time, expected)
      end
    end

    assert_parquet(ctx, 1)
    assert_parquet_read(ctx)
  end

  @tag :json_expression_batch
  test "explicit JSON resolves duplicate paths and destinations in source order", ctx do
    cases = [
      {~s/{"k":{"x":1},"k":{"y":2}}/, ~s/result="k.y"/, %{"result" => "2"}},
      {~s/{"k":{"y":1},"k":{"y":2}}/, ~s/result="k.y"/, %{"result" => "1"}},
      {~s/{"a":1,"b":2}/, ~s/result="b", result="a"/, %{"result" => "2"}},
      {~s/{"b":2,"a":1}/, ~s/result="b", result="a"/, %{"result" => "1"}},
      {~s/{"k":1e+03}/, ~s/first="k", second="k"/, %{"first" => "1e+03", "second" => "1e+03"}},
      {~s/{"k":[-0,2]}/, ~s/first="k[0]", second="k[1]", absent="k[2]"/,
       %{"first" => "-0", "second" => "2", "absent" => ""}},
      {~S/{"obj":{"v":"a\nb"},"arr":["a\nb"]}/, ~s/object="obj", array="arr"/,
       %{"object" => ~S/{"v":"a\nb"}/, "array" => "[\"a\nb\"]"}},
      {~s/{"�":"value"}/, ~s/result=`["�"]`/, %{"result" => "value"}}
    ]

    for {{line, fields, want}, index} <- Enum.with_index(cases) do
      labels = %{"fixture" => "path-order-#{index}"}
      push(ctx, line, ctx.now, labels)
      params = [{"query", ~s/{fixture="path-order-#{index}"} | json / <> fields} | range(ctx)]

      for response <- [request(ctx, "/query_range", params), request_form(ctx, "/query_range", params)] do
        assert flattened_entries(response) == %{{to_string(ctx.now), line, Map.merge(labels, want)} => 1}
      end
    end

    before_reads = Agent.get(ctx.store, & &1.requests)

    for source <- ["", "k[-1]", "k[1.5]", "k[9223372036854775808]", "[\"k\"]."] do
      params = [{"query", ~s/{fixture=~"path-order-.+"} | json value=/ <> Pulse.JSON.encode!(source)} | range(ctx)]

      for response <- [request(ctx, "/query_range", params, 400), request_form(ctx, "/query_range", params, 400)] do
        assert response["message"] =~ "invalid_json_expression"
      end
    end

    assert Agent.get(ctx.store, & &1.requests) == before_reads
    assert_parquet_read(ctx)
  end

  # Complete logical-operator, precedence, short-circuit, first-error and mixed
  # metadata sections from the pinned label_filters.logqltest engine script.
  @tag :label_boolean_batch
  test "Loki label-filter logical fixtures preserve every instant and range result", ctx do
    fixtures = "test/fixtures/logs/loki-upstream/label-boolean.json" |> File.read!() |> Pulse.JSON.decode!()
    assert length(fixtures["fixtures"]) == 5
    cases = Enum.flat_map(fixtures["fixtures"], & &1["cases"])
    assert length(cases) == 36
    assert Enum.count(cases, &Map.has_key?(&1, "reject")) == 9
    base = div(ctx.now, @second) * @second - 2_000 * @second

    for {fixture, i} <- Enum.with_index(fixtures["fixtures"]) do
      ctx = %{ctx | now: base + i * 300 * @second}

      streams =
        for load <- fixture["loads"] do
          values =
            for repeat <- 0..(load["count"] - 1) do
              stamp = ctx.now + (load["start"] + repeat * load["every"]) * @second
              [to_string(stamp), load["line"], load["metadata"]]
            end

          %{"stream" => load["labels"], "values" => values}
        end

      push_streams(ctx, streams)

      for row <- fixture["cases"] do
        if row["reject"] do
          params = [query: row["query"], time: to_string(ctx.now + row["start"] * @second)]

          for response <- [request(ctx, "/query", params, 400), request_form(ctx, "/query", params, 400)] do
            assert response["error"] == "evaluation_failed"
            assert response["message"] =~ "pipeline_error"
            refute Map.has_key?(response, "data")
          end

          # Pulse's metric failure envelope is generic. Read the original
          # failing labels separately to check upstream's error type/details.
          raw = row["query"] |> String.replace_prefix("count_over_time(", "") |> String.replace_suffix(" [1m])", "")

          params = [
            query: raw <> ~s/ | __error__!=""/,
            start: to_string(ctx.now + 1),
            end: to_string(ctx.now + 60 * @second)
          ]

          expected = String.replace(row["reject"], ~r/\\+"/, ~s/"/)

          for response <- [request(ctx, "/query_range", params), request_form(ctx, "/query_range", params)] do
            assert response["data"]["result"] != []

            for stream <- response["data"]["result"] do
              assert stream["stream"]["__error__"] == "LabelFilterErr"

              if expected != "LabelFilterErr" do
                assert stream["stream"]["__error_details__"] =~ expected
              end
            end
          end
        else
          time = if row["instant"], do: row["start"], else: {row["start"], row["end"], row["step"]}
          times = if row["instant"], do: [row["start"]], else: Enum.to_list(row["start"]..row["end"]//row["step"])

          expected =
            Map.new(row["expected"], fn series ->
              {series["labels"], for({t, v} <- Enum.zip(times, series["values"]), v != "_", do: {t, v})}
            end)

          assert_metric(ctx, row["query"], time, expected)
        end
      end
    end

    assert_parquet(ctx, 5)
  end

  # Local truth tables distinguish Loki's right-attaching comma/implicit AND
  # from explicit AND precedence. Every combination has a separate identity.
  @tag :label_boolean_batch
  test "label-filter conjunctions preserve grouping, errors and admission", ctx do
    labels = %{"job" => "label-boolean"}
    inputs = for x <- ["0", "1"], y <- ["0", "1"], z <- ["0", "1"], do: %{"x" => x, "y" => y, "z" => z}

    push_streams(ctx, [
      %{"stream" => labels, "values" => Enum.map(inputs, &[to_string(ctx.now), &1["x"] <> &1["y"] <> &1["z"], &1])}
    ])

    for {filter, predicate} <- [
          {~s/x="1" y="1" or z="1"/, fn x, y, z -> x and (y or z) end},
          {~s/x="1", y="1" or z="1"/, fn x, y, z -> x and (y or z) end},
          {~s/x="1" and y="1" or z="1"/, fn x, y, z -> (x and y) or z end},
          {~s/x="1" AND y="1" OR z="1"/, fn x, y, z -> (x and y) or z end},
          {~s/x="1" or y="1", z="1"/, fn x, y, z -> x or (y and z) end},
          {~s/(x="1" or y="1"), z="1"/, fn x, y, z -> (x or y) and z end},
          {~s/x="1" (y="1" or z="1")/, fn x, y, z -> x and (y or z) end},
          {~s/x="1"y="1"/, fn x, y, _ -> x and y end},
          {~s/x="1" or y="1" | z="1"/, fn x, y, z -> (x or y) and z end}
        ] do
      expected =
        for input <- inputs, predicate.(input["x"] == "1", input["y"] == "1", input["z"] == "1") do
          {to_string(ctx.now), input["x"] <> input["y"] <> input["z"], Map.merge(labels, input)}
        end

      expression = ~s/{job="label-boolean"} | / <> filter

      for response <- [query(ctx, expression), request_form(ctx, "/query_range", [query: expression] ++ range(ctx))] do
        assert flattened_entries(response) == Enum.frequencies(expected)
      end
    end

    error_labels = %{"job" => "label-boolean-error", "x" => "0", "n" => "oops"}
    push(ctx, "bad", ctx.now, error_labels)

    for separator <- ["and", ",", " "] do
      expression = ~s/{job="label-boolean-error"} | (x="never" #{separator} n>1s) or __error__!=""/

      expected =
        Map.merge(error_labels, %{
          "__error__" => "LabelFilterErr",
          "__error_details__" => ~s/time: invalid duration "oops"/
        })

      assert_streams(query(ctx, expression), [{expected, ["bad"]}])
    end

    for filter <- [
          ~s/x="1",/,
          ~s/x="1",,y="1"/,
          ~s/x="1" and or y="1"/,
          ~s/x="1", y=~"["/,
          ~s/x="1" y=ip("invalid")/,
          ~s/x="1"/ <> String.duplicate(~s/ y="1"/, 300)
        ] do
      before = Agent.get(ctx.store, & &1.requests)
      params = [query: ~s/{job="label-boolean"} | / <> filter] ++ range(ctx)
      assert request(ctx, "/query_range", params, 400)["status"] == "error"
      assert request_form(ctx, "/query_range", params, 400)["status"] == "error"
      assert Agent.get(ctx.store, & &1.requests) == before
    end

    for limit <- [[max_work: 0], [max_log_samples: 0], [max_result_points: 0]] do
      Runtime.put_env(:pulse, Evaluator, limit)
      params = [query: ~s/count_over_time({job="label-boolean"} | x="1", y="1" [1m])/, time: to_string(ctx.now)]
      response = request_form(ctx, "/query", params, 422)
      assert response["error"] == "query_limit"
      refute Map.has_key?(response, "data")
    end
  end

  # Complete OR selection of Test_FilterMatcher: original queries and all
  # original keep/drop decisions. Time slices isolate rows without query edits.
  @tag :line_or_batch
  test "Loki line-filter OR tables preserve all original line decisions", ctx do
    ctx = %{ctx | now: div(ctx.now, @second) * @second - 600 * @second}
    cases = Enum.filter(line_or_cases(), &(&1["kind"] == "table"))
    assert length(cases) == 27
    assert Enum.sum(Enum.map(cases, &length(&1["checks"]))) == 121

    values =
      for {row, i} <- Enum.with_index(cases),
          check <- row["checks"],
          do: [to_string(ctx.now + i * 2 * @second), check["line"]]

    push_streams(ctx, [%{"stream" => %{"app" => "foo"}, "values" => values}])

    for {row, i} <- Enum.with_index(cases) do
      stamp = to_string(ctx.now + i * 2 * @second)
      params = [query: row["query"], start: stamp, end: to_string(ctx.now + i * 2 * @second + 1)]
      lines = for check <- row["checks"], check["match"], do: check["line"]

      # Upstream asserts individual keep/drop decisions, not equal-time order.
      expected = Enum.frequencies(for line <- lines, do: {stamp, line, %{"app" => "foo"}})

      for response <- [request(ctx, "/query_range", params), request_form(ctx, "/query_range", params)] do
        assert response["data"]["resultType"] == "streams"
        assert flattened_entries(response) == expected
      end

      counts = if lines == [], do: %{}, else: %{%{"app" => "foo"} => [{i * 2, to_string(length(lines))}]}
      assert_metric(ctx, "count_over_time(#{row["query"]} [1s])", i * 2, counts)
    end

    assert_parquet(ctx, 1)
  end

  @tag :line_or_batch
  test "Loki line-filter OR engine fixtures preserve instant and sparse range outputs", ctx do
    ctx = %{ctx | now: div(ctx.now, @second) * @second - 600 * @second}
    cases = Enum.filter(line_or_cases(), &(&1["kind"] == "engine"))
    assert length(cases) == 29
    assert Enum.count(cases, &Map.has_key?(&1, "reject")) == 3

    streams =
      for row <- Enum.uniq_by(cases, & &1["fixture"]), load <- row["loads"] do
        values =
          for i <- 0..(load["count"] - 1),
              do: [to_string(ctx.now + (load["start"] + i * load["every"]) * @second), load["line"]]

        %{"stream" => %{"app" => load["app"]}, "values" => values}
      end

    push_streams(ctx, streams)

    for row <- cases do
      if row["reject"] do
        before = Agent.get(ctx.store, & &1.requests)
        params = [query: row["query"], time: to_string(ctx.now + row["start"] * @second)]
        assert request(ctx, "/query", params, 400)["status"] == "error"
        assert request_form(ctx, "/query", params, 400)["status"] == "error"
        assert Agent.get(ctx.store, & &1.requests) == before
      else
        time = if row["instant"], do: row["start"], else: {row["start"], row["end"], row["step"]}
        times = if row["instant"], do: [row["start"]], else: Enum.to_list(row["start"]..row["end"]//row["step"])

        expected =
          Map.new(row["expected"], fn series ->
            points = for {time, value} <- Enum.zip(times, series["values"]), value != "_", do: {time, value}
            {series["labels"], points}
          end)

        assert_metric(ctx, row["query"], time, expected)
      end
    end

    assert_parquet(ctx, 1)
  end

  # Local controls distinguish negation of a union from a union of negations,
  # require all branches to validate, and retain existing admission budgets.
  @tag :line_or_batch
  test "line-filter OR preserves stage boundaries, validation and query ceilings", ctx do
    labels = %{"job" => "line-or-controls"}
    lines = ["alpha", "beta", "alpha beta", "none", ""]
    push_streams(ctx, [%{"stream" => labels, "values" => Enum.map(lines, &[to_string(ctx.now), &1])}])

    for {stage, expected} <- [
          {~s/|= "alpha" or "beta"/, ["alpha", "beta", "alpha beta"]},
          {~s/!= "alpha" or "beta"/, ["none", ""]},
          {~s/|= "" or "never"/, lines},
          {~s/!= "" or "never"/, []},
          {~s/|= "alpha" OR "beta"/, ["alpha", "beta", "alpha beta"]},
          {~s/|= "alpha" or "beta" |= "beta" or "gamma"/, ["beta", "alpha beta"]},
          {~s/|= "none" | line_format "alpha" |= "beta" or "alpha"/, ["alpha"]}
        ] do
      response = query(ctx, ~s/{job="line-or-controls"} / <> stage)
      assert response["data"]["resultType"] == "streams"

      assert flattened_entries(response) ==
               Enum.frequencies(for line <- expected, do: {to_string(ctx.now), line, labels})
    end

    for stage <- [
          ~s/|= "" or ip("invalid")/,
          ~s/|~ "" or "["/,
          ~s/|> "<_>" or "<named>"/,
          ~s/!~ "valid" or ip("::1")/,
          ~s/|= "alpha" or/,
          ~s/|= "alpha" orange "beta"/,
          ~s/|= "alpha"/ <> String.duplicate(~s/ or "never"/, 300)
        ] do
      before = Agent.get(ctx.store, & &1.requests)
      params = [query: ~s/{job="line-or-controls"} / <> stage] ++ range(ctx)
      assert request(ctx, "/query_range", params, 400)["status"] == "error"
      assert request_form(ctx, "/query_range", params, 400)["status"] == "error"
      assert Agent.get(ctx.store, & &1.requests) == before
    end

    for limit <- [[max_work: 0], [max_log_samples: 0], [max_result_points: 0]] do
      Runtime.put_env(:pulse, Evaluator, limit)

      params = [
        query: ~s'count_over_time({job="line-or-controls"} |= "alpha" or "beta" [1m])',
        time: to_string(ctx.now)
      ]

      response = request_form(ctx, "/query", params, 422)
      assert response["error"] == "query_limit"
      refute Map.has_key?(response, "data")
    end
  end

  # Complete Test_IPFilter table. The same original values additionally test
  # negative complements and label predicates, not additional upstream rows.
  @tag :ip_filters_batch
  test "Loki IP tables select exact lines and label values through storage", ctx do
    cases = Enum.filter(ip_filter_cases(), &(&1["suite"] == "Test_IPFilter" and not &1["reject"]))
    assert length(cases) == 7
    assert Enum.sum(Enum.map(cases, &length(&1["input"]))) == 43

    streams =
      for {row, i} <- Enum.with_index(cases), {line, j} <- Enum.with_index(row["input"]) do
        %{
          "stream" => %{"job" => "ip-table-#{i}", "row" => to_string(j)},
          "values" => [[to_string(ctx.now), line, %{"addr" => line}]]
        }
      end

    push_streams(ctx, streams)

    for {row, i} <- Enum.with_index(cases), negative? <- [false, true], label? <- [false, true] do
      pattern = Pulse.JSON.encode!(row["pattern"])
      op = if negative?, do: "!=", else: "="
      stage = if label?, do: "| addr#{op}ip(#{pattern})", else: "#{if negative?, do: "!=", else: "|="} ip(#{pattern})"
      expression = ~s/{job="ip-table-#{i}"} / <> stage

      expected =
        for {line, j} <- Enum.with_index(row["input"]), j in row["expected"] != negative? do
          {%{"job" => "ip-table-#{i}", "row" => to_string(j), "addr" => line}, [line]}
        end

      assert_streams(query(ctx, expression), expected)
      assert_streams(request_form(ctx, "/query_range", [query: expression] ++ range(ctx)), expected)
      counts = Map.new(expected, fn {labels, _} -> {labels, [{1, "1"}]} end)
      assert_metric(ctx, "count_over_time(#{expression} [1m])", 1, counts)
    end

    assert_parquet(ctx, 1)
    assert_parquet_read(ctx)
  end

  @tag :ip_filters_batch
  test "Loki IP operator tables preserve success and reject invalid forms before storage", ctx do
    cases = Enum.reject(ip_filter_cases(), &(&1["suite"] == "Test_IPFilter" and not &1["reject"]))
    assert length(cases) == 8

    for {row, i} <- Enum.with_index(cases) do
      pattern = Pulse.JSON.encode!(row["pattern"])
      label? = row["suite"] == "Test_IPLabelFilterTy"
      op = row["operator"] || "|="
      stage = if label?, do: "| addr#{op}ip(#{pattern})", else: "#{op} ip(#{pattern})"
      labels = %{"job" => "ip-operator-#{i}"}
      expression = ~s/{job="ip-operator-#{i}"} / <> stage

      if row["reject"] do
        before = Agent.get(ctx.store, & &1.requests)
        params = [query: expression] ++ range(ctx)
        assert request(ctx, "/query_range", params, 400)["status"] == "error"
        assert request_form(ctx, "/query_range", params, 400)["status"] == "error"
        assert Agent.get(ctx.store, & &1.requests) == before
      else
        [line] = row["input"]
        metadata = if label?, do: %{"addr" => line}, else: %{}
        push(ctx, line, ctx.now, labels, metadata)
        expected = if row["match"], do: [{Map.merge(labels, metadata), [line]}], else: []
        assert_streams(query(ctx, expression), expected)
        assert_streams(request_form(ctx, "/query_range", [query: expression] ++ range(ctx)), expected)
      end
    end

    assert_parquet(ctx, 4)
  end

  # Local controls: boundaries, stage ordering, error/absence policy and bounds.
  @tag :ip_filters_batch
  test "IP filters preserve pipeline ordering and fail whole on shared budgets", ctx do
    labels = %{"job" => "ip-controls"}

    for {line, addr} <- [
          {"192.0.2.0", "192.0.2.0"},
          {"192.0.2.1", "192.0.2.1"},
          {"192.0.2.2", "192.0.2.2"},
          {"192.0.2.3", "192.0.2.3"},
          {"::ffff:192.0.2.1", "::ffff:192.0.2.1"},
          {"missing", nil},
          {"empty", ""}
        ] do
      push(ctx, line, ctx.now, labels, if(addr, do: %{"addr" => addr}, else: %{}))
    end

    expected =
      for addr <- ["192.0.2.1", "192.0.2.2"], do: {Map.put(labels, "addr", addr), [addr]}

    for stage <- [
          ~s/|= ip("192.0.2.1-192.0.2.2")/,
          ~s/| addr=ip("192.0.2.1-192.0.2.2")/,
          ~s/|= Ip ( "192.0.2.1-192.0.2.2" )/,
          ~s/| addr = iP (\n "192.0.2.1-192.0.2.2" \t)/
        ] do
      assert_streams(query(ctx, ~s/{job="ip-controls"} / <> stage), expected)
    end

    assert_streams(query(ctx, ~s/{job="ip-controls"} | addr=ip("192.0.2.1") or addr=ip("192.0.2.2")/), expected)

    assert_streams(query(ctx, ~s/{job="ip-controls"} |= ip("192.0.2.1")/), [
      {Map.put(labels, "addr", "192.0.2.1"), ["192.0.2.1"]}
    ])

    # Missing labels fail either operator; present empty values match negation.
    expression = ~s[{job="ip-controls"} | addr!=ip("0.0.0.0/0")]

    assert_streams(query(ctx, expression), [
      {Map.put(labels, "addr", "::ffff:192.0.2.1"), ["::ffff:192.0.2.1"]},
      {Map.put(labels, "addr", ""), ["empty"]}
    ])

    # Filtering must read the current formatted line, never the stored body.
    expression = ~s/{job="ip-controls"} |= "missing" | line_format "::1" |= ip("::1")/
    assert_streams(query(ctx, expression), [{labels, ["::1"]}])
    assert_metric(ctx, "count_over_time(#{expression} [1m])", {1, 2, 1}, %{labels => [{1, "1"}, {2, "1"}]})

    push(ctx, "selected", ctx.now, %{"job" => "ip-unwrap"}, %{"value" => "7", "addr" => "::1"})
    push(ctx, "excluded", ctx.now, %{"job" => "ip-unwrap"}, %{"value" => "100", "addr" => "::2"})

    assert_metric(ctx, ~s/sum_over_time({job="ip-unwrap"} | unwrap value | addr=ip("::1") [1m])/, 1, %{
      %{"job" => "ip-unwrap", "addr" => "::1"} => [{1, "7"}]
    })

    # Keep Loki's candidate boundaries, distinct mapped family, and zone/range
    # parsing order. A failed CIDR parse must still try an inclusive IP range.
    lines = [
      "[::1]:80",
      "::1:80",
      "::",
      "::ffff:192.0.2.1",
      "192.00.2.1",
      "192.0.2.1.2",
      "fe80::1",
      "fe80::2",
      "fe80::3",
      "192.0.2.1,::1",
      "192.0.2.1::1",
      "2001:db8::1"
    ]

    push_streams(ctx, [
      %{"stream" => %{"job" => "ip-scanner"}, "values" => Enum.map(lines, &[to_string(ctx.now), &1, %{"addr" => &1}])}
    ])

    for {pattern, indices} <- [
          {"::1", [0, 9]},
          {"::/0", [0, 1, 3, 6, 7, 8, 9, 11]},
          {"0.0.0.0/0", [9, 10]},
          {"::ffff:192.0.2.1", [3]},
          {"fe80::1%eth0", []},
          {"fe80::1%eth0/64", []},
          {"fe80::1-fe80::2%eth0/64", [6, 7]}
        ],
        stage <- ["|= ip(#{Pulse.JSON.encode!(pattern)})", "| addr=ip(#{Pulse.JSON.encode!(pattern)})"] do
      expected =
        for index <- indices, line = Enum.at(lines, index), do: {%{"job" => "ip-scanner", "addr" => line}, [line]}

      assert_streams(query(ctx, ~s/{job="ip-scanner"} / <> stage), expected)
    end

    push(ctx, "not-number", ctx.now, %{"job" => "ip-errors"}, %{"value" => "not-number"})
    expression = ~s/{job="ip-errors"} | value>0 | absent=ip("::1")/

    error_labels = %{
      "job" => "ip-errors",
      "value" => "not-number",
      "__error__" => "LabelFilterErr",
      "__error_details__" => ~s/strconv.ParseFloat: parsing "not-number": invalid syntax/
    }

    assert_streams(query(ctx, expression), [{error_labels, ["not-number"]}])
    assert_streams(query(ctx, expression <> ~s/ | __error__=""/), [])

    assert request(ctx, "/query", [query: "count_over_time(#{expression} [1m])", time: to_string(ctx.now)], 400)[
             "status"
           ] == "error"

    for stage <- [
          ~s/|~ ip("::1")/,
          ~s/!~ ip("::1")/,
          ~s/| addr==ip("::1")/,
          ~s/| addr>ip("::1")/,
          ~s/| addr=~ip("::1")/
        ] do
      before = Agent.get(ctx.store, & &1.requests)

      assert request(ctx, "/query_range", [query: ~s/{job="ip-controls"} / <> stage] ++ range(ctx), 400)["status"] ==
               "error"

      assert Agent.get(ctx.store, & &1.requests) == before
    end

    for pattern <- ["192.00.2.1", "192.0.2.1/033", "::1/129", "::2-::1"] do
      before = Agent.get(ctx.store, & &1.requests)
      expression = ~s/{job="ip-controls"} |= ip(#{Pulse.JSON.encode!(pattern)})/
      assert request(ctx, "/query_range", [query: expression] ++ range(ctx), 400)["status"] == "error"
      assert Agent.get(ctx.store, & &1.requests) == before
    end

    for limit <- [[max_work: 0], [max_log_samples: 0], [max_result_points: 0]] do
      Runtime.put_env(:pulse, Evaluator, limit)
      params = [query: ~s'count_over_time({job="ip-controls"} |= ip("0.0.0.0/0") [1m])', time: to_string(ctx.now)]
      response = request_form(ctx, "/query", params, 422)
      assert response["error"] == "query_limit"
      refute Map.has_key?(response, "data")
    end
  end

  # Three original TestLex rows: raw/escaped regex and an escaped quote.
  # Token expectations become observable selection through HTTP/Parquet/S3.
  @tag :string_literals_batch
  test "Loki lexer regex and quote cases select the same stored lines", ctx do
    push(ctx, "word42", ctx.now, %{"foo" => "bar"})
    push(ctx, "quoted", ctx.now, %{"foo" => "ba\"r"})

    for expression <- [~S/{foo="bar"} |~ `\w+`/, ~S/{foo="bar"} |~ "\\w+"/] do
      expected = [{%{"foo" => "bar"}, ["word42"]}]
      assert_streams(query(ctx, expression), expected)
      assert_streams(request_form(ctx, "/query_range", [query: expression] ++ range(ctx)), expected)
    end

    assert_streams(query(ctx, ~S/{ foo = "ba\"r" }/), [{%{"foo" => "ba\"r"}, ["quoted"]}])
    assert_parquet(ctx, 2)
    assert_parquet_read(ctx)
  end

  # Go table inputs plus local controls, evaluated by the pinned Loki scanner
  # and decoder. Invalid decoded byte strings must not alias UTF-8 text.
  @tag :string_literals_batch
  test "string literals preserve exact filter bytes through logs and metrics", ctx do
    cases = Enum.reject(string_literal_cases(), fn {_literal, value} -> is_nil(value) end)
    assert length(cases) == 46

    streams =
      for {{_literal, value}, index} <- Enum.with_index(cases) do
        probe = if String.valid?(value), do: value, else: "ÿ"

        %{
          "stream" => %{"job" => "literal-#{index}"},
          "values" => [[to_string(ctx.now), "head:" <> probe <> ":tail", %{"foo" => probe}]]
        }
      end

    push_streams(ctx, streams)

    for {{literal, value}, index} <- Enum.with_index(cases) do
      selector = ~s/{job="literal-#{index}"}/
      filter = selector <> " | foo=" <> literal
      labels = %{"job" => "literal-#{index}", "foo" => value}
      expected = if String.valid?(value), do: [{labels, ["head:" <> value <> ":tail"]}], else: []
      assert_streams(query(ctx, filter), expected)
      assert_streams(request_form(ctx, "/query_range", [query: filter] ++ range(ctx)), expected)
      assert_streams(query(ctx, selector <> " |= " <> literal), expected)

      samples = if String.valid?(value), do: %{labels => [{1, "1"}]}, else: %{}
      assert_metric(ctx, "count_over_time(#{filter} [1m])", 1, samples)
    end

    assert_parquet(ctx, 1)
    assert_parquet_read(ctx)
  end

  @tag :string_literals_batch
  test "invalid string literals reject before provider access on both HTTP transports", ctx do
    before = Agent.get(ctx.store, & &1.requests)

    cases =
      for {literal, nil} <- string_literal_cases(), String.valid?(literal), do: literal

    assert length(cases) == 56

    for literal <- cases do
      expression = ~s/{job="literal"} | foo=/ <> literal
      params = [query: expression] ++ range(ctx)
      assert request(ctx, "/query_range", params, 400)["status"] == "error"
      assert request_form(ctx, "/query_range", params, 400)["status"] == "error"
    end

    assert Agent.get(ctx.store, & &1.requests) == before
  end

  @tag :label_conversion_batch
  test "Loki byte label-filter table preserves decimal and binary unit comparisons", ctx do
    cases = [
      {42, "42B"},
      {42 * 1000, "42kB"},
      {42 * 1000 * 1000, "42MB"},
      {42 * 1000 * 1000 * 1000, "42GB"},
      {42 * 1000 * 1000 * 1000 * 1000, "42TB"},
      {42 * 1000 * 1000 * 1000 * 1000 * 1000, "42PB"},
      {42 * 1024, "42KiB"},
      {42 * 1024 * 1024, "42MiB"},
      {42 * 1024 * 1024 * 1024, "42GiB"},
      {42 * 1024 * 1024 * 1024 * 1024, "42TiB"},
      {42 * 1024 * 1024 * 1024 * 1024 * 1024, "42PiB"}
    ]

    for {{bytes, value}, index} <- Enum.with_index(cases) do
      labels = %{"job" => "byte-filter-#{index}", "bar" => value}
      push(ctx, "sample log line", ctx.now, labels)
      expression = ~s/{job="byte-filter-#{index}"} | bar=#{bytes}B/
      assert_streams(query(ctx, expression), [{labels, ["sample log line"]}])
    end

    assert_parquet(ctx, 11)
    assert_parquet_read(ctx)
  end

  @tag :label_conversion_batch
  test "Loki error-label filter table preserves negative matcher and absence semantics", ctx do
    cases = [
      {~s/__error__!="JSONParserErr"/, "JSONParserErr", false},
      {~s/__error__!~".+"/, "foo", false},
      {~s/__error__!~".+"/, "", true},
      {~s/__error__!="JSONParserErr"/, "", true}
    ]

    for {{filter, error, keep?}, index} <- Enum.with_index(cases) do
      labels = %{"job" => "error-filter-#{index}", "status" => "200", "method" => "POST"}
      labels = if error == "", do: labels, else: Map.put(labels, "__error__", error)
      # Upstream label_filter_test.go:277 uses SetErr, not a base label.
      # Incoming metadata errors exercise that authoritative owner publicly.
      push(ctx, "sample log line", ctx.now, Map.delete(labels, "__error__"), Map.take(labels, ["__error__"]))
      expression = ~s/{job="error-filter-#{index}"} | / <> filter
      expected = if keep?, do: [{labels, ["sample log line"]}], else: []
      assert_streams(query(ctx, expression), expected)
      assert_streams(request_form(ctx, "/query_range", [query: expression] ++ range(ctx)), expected)
    end

    assert_parquet(ctx, 4)
    assert_parquet_read(ctx)
  end

  # Pulse HTTP/S3 control: error labels are parser output, not stream labels,
  # and cannot disappear during metric fast paths, grouping or transport.
  @tag :label_conversion_batch
  test "typed filter failures retain category provenance and fail unfiltered metric queries", ctx do
    push(ctx, "sample", ctx.now, %{"job" => "conversion"}, %{"n" => "oops"})
    objects = Agent.get(ctx.store, & &1.objects)
    expression = ~s/{job="conversion"} | n>0/
    response = query(categorize(ctx), expression)

    assert response["data"]["result"] == [
             %{
               "stream" => %{"job" => "conversion"},
               "values" => [
                 [
                   to_string(ctx.now),
                   "sample",
                   %{
                     "structuredMetadata" => %{"n" => "oops"},
                     "parsed" => %{
                       "__error__" => "LabelFilterErr",
                       "__error_details__" => ~s/strconv.ParseFloat: parsing "oops": invalid syntax/
                     }
                   }
                 ]
               ]
             }
           ]

    metric = "count_over_time(#{expression} [1m])"
    params = [query: metric, time: to_string(ctx.now + @second)]
    assert request(ctx, "/query", params, 400)["message"] =~ "pipeline_error"
    assert request_form(ctx, "/query", params, 400)["message"] =~ "pipeline_error"
    assert values(instant(ctx, ~s/count_over_time(#{expression} | __error__="" [1m])/)) == %{}

    assert values(instant(ctx, ~s/count_over_time(#{expression} | __error__!="" [1m])/)) == %{
             %{
               "job" => "conversion",
               "n" => "oops",
               "__error__" => "LabelFilterErr",
               "__error_details__" => ~s/strconv.ParseFloat: parsing "oops": invalid syntax/
             } => "1"
           }

    assert Agent.get(ctx.store, & &1.objects) == objects
    assert_parquet_read(ctx)
  end

  # Complete range_aggregations.logqltest:1558-1619: all thirteen original
  # inputs and twelve evaluations. Only the relative epoch translates.
  @tag :dispersion_unwrap_batch
  test "complete Loki dispersion block retains values and missing-unwrap diagnostics", ctx do
    fixture = File.read!("test/fixtures/logs/loki-upstream/range-aggregations-dispersion.logqltest")

    assert Base.encode16(:crypto.hash(:sha256, fixture), case: :lower) ==
             "330973461407db6b7ef06fc9ded0a6cd333efd28cd0ee5ffefc92252172d7691"

    ctx = %{ctx | now: (div(ctx.now, @second) - 400) * @second}
    streams = push_dispersion_fixture(ctx)

    for {operation, varied, late} <- [
          {"stdvar_over_time", "4", "100"},
          {"stddev_over_time", "2", "10"}
        ] do
      query = operation <> ~s/({app="a"} | logfmt | unwrap v [1m])/

      for {time, selected_times, late_points} <- [
            {60, [60], []},
            {{40, 60, 20}, [40, 60], []},
            {{60, 130, 70}, [60], [{130, late}]}
          ] do
        expected =
          Map.new(
            for {name, value} <- [{"single", "0"}, {"constant", "0"}, {"vary", varied}, {"nan", "NaN"}] do
              {%{"app" => "a", "c" => name}, for(at <- selected_times, do: {at, value})}
            end
          )

        expected = Map.put(expected, %{"app" => "a", "c" => "late"}, late_points)
        assert_metric(ctx, query, time, expected)
      end

      offset = operation <> ~s/({app="a"} | logfmt | unwrap v [20s] offset 20s)/

      for time <- [110, {110, 150, 20}] do
        assert_metric(ctx, offset, time, %{%{"app" => "a", "c" => "late"} => [{110, late}]})
      end
    end

    # The instant rows are original; range placements are authored controls.
    # Collect both complete rejection oracles before asserting substrings.
    responses =
      for {query, expected} <- [
            {~s/stdvar_over_time({app="a"}[1m])/, "invalid aggregation stdvar_over_time without unwrap"},
            {~s/stddev_over_time({app="a"}[1m])/, "invalid aggregation stddev_over_time without unwrap"}
          ],
          {path, bounds} <- [
            {"/query", [time: to_string(ctx.now + 60 * @second)]},
            {"/query_range",
             [start: to_string(ctx.now + 40 * @second), end: to_string(ctx.now + 60 * @second), step: "20"]}
          ],
          method <- [&request/4, &request_form/4] do
        before = Agent.get(ctx.store, & &1.requests)
        response = method.(ctx, path, [query: query] ++ bounds, 400)
        assert Agent.get(ctx.store, & &1.requests) == before
        {expected, response}
      end

    # Authored raw-byte control retains every original input, including noise.
    for method <- [&request/4, &request_form/4] do
      response =
        method.(
          ctx,
          "/query_range",
          [
            query: ~s/{app=~"a|noise"}/,
            start: to_string(ctx.now),
            end: to_string(ctx.now + 131 * @second),
            direction: "forward",
            limit: "50"
          ],
          200
        )

      assert Map.new(response["data"]["result"], &{&1["stream"], &1["values"]}) ==
               Map.new(streams, &{&1["stream"], &1["values"]})
    end

    assert_parquet(ctx, 1)
    assert_parquet_read(ctx)

    for {expected, response} <- responses do
      assert response["error"] == "evaluation_failed"
      assert response["message"] =~ expected
    end
  end

  @tag :dispersion_unwrap_batch
  test "missing-unwrap diagnostics preserve admission, fail-whole budgets and neighboring contracts", ctx do
    ctx = %{ctx | now: (div(ctx.now, @second) - 400) * @second}
    push_dispersion_fixture(ctx)

    endpoints = [
      {"/query", [time: to_string(ctx.now + 60 * @second)]},
      {"/query_range", [start: to_string(ctx.now + 40 * @second), end: to_string(ctx.now + 60 * @second), step: "20"]}
    ]

    # Authored controls below are not additional upstream source rows.
    for {path, bounds} <- endpoints, method <- [&request/4, &request_form/4] do
      before = Agent.get(ctx.store, & &1.requests)

      response =
        method.(%{ctx | token: "wrong-token"}, path, [query: ~s/stdvar_over_time({app="a"}[1m])/] ++ bounds, 401)

      assert response["error"] == "invalid_token"
      assert Agent.get(ctx.store, & &1.requests) == before
    end

    for {module, config, status, error} <- [
          {Pulse.QueryRunner, [max_per_tenant: 0], 429, "query_overloaded"},
          {Pulse.QueryRunner, [max_scan_rows: 1], 422, "query_limit"},
          {Evaluator, [max_work: 1], 422, "query_limit"}
        ] do
      original = Runtime.get_env(:pulse, module, [])
      Runtime.put_env(:pulse, module, Keyword.merge(original, config))

      for {path, bounds} <- endpoints, method <- [&request/4, &request_form/4] do
        before = Agent.get(ctx.store, & &1.requests)

        response =
          method.(ctx, path, [query: ~s/stdvar_over_time({app="a"} | logfmt | unwrap v [1m])/] ++ bounds, status)

        assert response["error"] == error
        refute Map.has_key?(response, "data")
        if status == 429, do: assert(Agent.get(ctx.store, & &1.requests) == before)
      end

      Runtime.put_env(:pulse, module, original)
    end

    for {query, expected} <- [
          {~s/sum(stdvar_over_time({app="a"}[1m]))/, "invalid aggregation stdvar_over_time without unwrap"},
          {~s/vector(1) + stddev_over_time({app="a"}[1m])/, "invalid aggregation stddev_over_time without unwrap"},
          {~s/sum_over_time({app="a"}[1m])/, "invalid aggregation sum_over_time without unwrap"},
          {~s/rate_counter({app="a"}[1m])/, "invalid aggregation rate_counter without unwrap"},
          {~s/quantile_over_time({app="a"}[1m])/, ":invalid_range_parameter"},
          {~s/count_over_time({app="a"}[1m]) by (app)/, ":unsupported_range_grouping"},
          {~s/bytes_over_time({app="a"} | unwrap v [1m])/, ":invalid_range_aggregation"}
        ],
        {path, bounds} <- endpoints,
        method <- [&request/4, &request_form/4] do
      before = Agent.get(ctx.store, & &1.requests)
      response = method.(ctx, path, [query: query] ++ bounds, 400)
      assert response["error"] == "evaluation_failed"
      assert response["message"] =~ expected
      assert Agent.get(ctx.store, & &1.requests) == before
    end

    # Unknown operations must retain the generic atom, with or without unwrap.
    for query <- [~s/sum_over_time({app="a"}[1m])/, ~s/sum_over_time({app="a"} | unwrap v [1m])/] do
      assert {:ok, %RangeAgg{} = ast} = Parser.parse(query)
      assert {:error, :invalid_range_aggregation} = QueryValidation.validate(%{ast | op: :unknown_range_operation})
    end

    # Supported log observations remain accepted without unwrap.
    labels = %{"app" => "a", "c" => "single"}
    assert_metric(ctx, ~s/count_over_time({app="a",c="single"}[1m])/, 60, %{labels => [{60, "1"}]})
    assert_metric(ctx, ~s/bytes_over_time({app="a",c="single"}[1m])/, 60, %{labels => [{60, "3"}]})
    assert_parquet(ctx, 1)
    assert_parquet_read(ctx)
  end

  # Complete vector_aggregations.logqltest:898-939: eight original schedules,
  # all 378 entries and nine evaluations. Only the relative epoch translates.
  @tag :topk_parameter_batch
  test "complete Loki topk block retains ranking results and parameter diagnostics", ctx do
    ctx = %{ctx | now: (div(ctx.now, @second) - 400) * @second}
    streams = push_topk_parameter_fixture(ctx)
    inner = ~s/count_over_time({app=~"foo|bar"} |~".+bar" [1m])/
    foo_a = %{"app" => "foo", "pod" => "a"}
    foo_b = %{"app" => "foo", "pod" => "b"}
    bar_a = %{"app" => "bar", "pod" => "a"}
    bar_b = %{"app" => "bar", "pod" => "b"}

    cases = [
      {"topk(2, #{inner})", 60, %{bar_b => ["30"], bar_a => ["15"]}},
      {"topk(2, #{inner})", {20, 60, 20}, %{bar_b => ["10", "20", "30"], bar_a => ["5", "10", "15"]}},
      {"topk(1, #{inner})", 60, %{bar_b => ["30"]}},
      {"topk(1, #{inner}) by (app)", 60, %{foo_b => ["12"], bar_b => ["30"]}},
      {"topk(1, #{inner}) without (app)", 60, %{bar_a => ["15"], bar_b => ["30"]}},
      {"topk(1, #{inner}) without (app, pod)", 60, %{bar_b => ["30"]}},
      {"topk(1, #{inner}) without ()", 60, %{foo_a => ["6"], foo_b => ["12"], bar_a => ["15"], bar_b => ["30"]}}
    ]

    for {query, times, expected} <- cases do
      assert_metric(
        ctx,
        query,
        times,
        Map.new(expected, fn {labels, values} ->
          times = if is_tuple(times), do: [20, 40, 60], else: [times]
          {labels, Enum.zip(times, values)}
        end)
      )
    end

    # Collect both original instant failures and authored range placements
    # before asserting substrings, so the red replay retains the whole block.
    responses =
      for {query, expected} <- [
            {"topk(1.5, #{inner})", "invalid parameter"},
            {"topk(#{inner})", "parameter required"}
          ],
          {path, bounds} <- [
            {"/query", [time: to_string(ctx.now + 60 * @second)]},
            {"/query_range",
             [start: to_string(ctx.now + 20 * @second), end: to_string(ctx.now + 60 * @second), step: "20"]}
          ],
          method <- [&request/4, &request_form/4] do
        before = Agent.get(ctx.store, & &1.requests)
        response = method.(ctx, path, [query: query] ++ bounds, 400)
        assert Agent.get(ctx.store, & &1.requests) == before
        {query, expected, response}
      end

    # Authored raw-byte control keeps every original schedule, including noise.
    for method <- [&request/4, &request_form/4] do
      response =
        method.(
          ctx,
          "/query_range",
          [
            query: ~s/{app=~"foo|bar"}/,
            start: to_string(ctx.now),
            end: to_string(ctx.now + 186 * @second),
            direction: "forward",
            limit: "500"
          ],
          200
        )

      assert Map.new(response["data"]["result"], &{&1["stream"], &1["values"]}) ==
               Map.new(streams, &{&1["stream"], &1["values"]})
    end

    assert_parquet(ctx, 1)
    assert_parquet_read(ctx)

    for {query, expected, response} <- responses do
      assert response["error"] == "evaluation_failed"
      assert response["message"] =~ expected, query <> ": " <> inspect(response)
    end
  end

  @tag :topk_parameter_batch
  test "topk diagnostics preserve bounded admission and neighboring error contracts", ctx do
    ctx = %{ctx | now: (div(ctx.now, @second) - 400) * @second}
    push_topk_parameter_fixture(ctx)
    inner = ~s/count_over_time({app=~"foo|bar"} |~".+bar" [1m])/

    endpoints = [
      {"/query", [time: to_string(ctx.now + 60 * @second)]},
      {"/query_range", [start: to_string(ctx.now + 20 * @second), end: to_string(ctx.now + 60 * @second), step: "20"]}
    ]

    for {path, bounds} <- endpoints, method <- [&request/4, &request_form/4] do
      before = Agent.get(ctx.store, & &1.requests)
      response = method.(%{ctx | token: "wrong-token"}, path, [query: "topk(#{inner})"] ++ bounds, 401)
      assert response["error"] == "invalid_token"
      assert Agent.get(ctx.store, & &1.requests) == before
    end

    for {module, config, status, error} <- [
          {Pulse.QueryRunner, [max_per_tenant: 0], 429, "query_overloaded"},
          {Pulse.QueryRunner, [max_scan_rows: 1], 422, "query_limit"},
          {Evaluator, [max_work: 1], 422, "query_limit"}
        ] do
      original = Runtime.get_env(:pulse, module, [])
      Runtime.put_env(:pulse, module, Keyword.merge(original, config))

      for {path, bounds} <- endpoints, method <- [&request/4, &request_form/4] do
        before = Agent.get(ctx.store, & &1.requests)
        response = method.(ctx, path, [query: "topk(2, #{inner})"] ++ bounds, status)
        assert response["error"] == error
        refute Map.has_key?(response, "data")
        if status == 429, do: assert(Agent.get(ctx.store, & &1.requests) == before)
      end

      Runtime.put_env(:pulse, module, original)
    end

    # Authored controls, not more upstream rows: retain zero-rank behavior,
    # recursive validation and unrelated range/grouping reasons.
    assert_metric(ctx, "topk(0, #{inner})", 60, %{})
    assert_metric(ctx, "bottomk(0, #{inner})", 60, %{})

    for {query, expected} <- [
          {"sum(topk(#{inner}))", "parameter required"},
          {"vector(1) + topk(1.5, #{inner})", "invalid parameter"},
          {"count_over_time({app=\"foo\"}[1m]) by (app)", ":unsupported_range_grouping"},
          {"approx_topk(1, #{inner}) by (app)", ":unsupported_vector_grouping"}
        ],
        method <- [&request/4, &request_form/4] do
      before = Agent.get(ctx.store, & &1.requests)
      response = method.(ctx, "/query", [query: query, time: to_string(ctx.now + 60 * @second)], 400)
      assert response["message"] =~ expected
      assert response["error"] == "evaluation_failed"
      assert Agent.get(ctx.store, & &1.requests) == before
    end
  end

  # Complete binary_operations.logqltest:750-789. The three original loads
  # match the later group-right block exactly; retain all 57 entries once.
  @tag :binary_missing_group_batch
  test "complete Loki group-left block retains explicit-group diagnostic and original values", ctx do
    ctx = %{ctx | now: (div(ctx.now, @second) - 400) * @second}
    push_binary_matching_fixture(ctx)
    left = ~s/sum by (app,machine) (count_over_time({app="foo"}[1m]))/
    right = ~s/sum by (app) (count_over_time({app="foo"}[1m]))/
    expected_error = "multiple matches for labels: many-to-one matching must be explicit (group_left/group_right)"

    cases = [
      {"> bool ignoring (machine)", {:error, expected_error}},
      {"> bool on () group_left", %{"fuzz" => "0", "buzz" => "0"}},
      {"> bool on () group_left ()", %{"fuzz" => "0", "buzz" => "0"}},
      {"> bool ignoring (machine) group_left", %{"fuzz" => "0", "buzz" => "0"}},
      {"< on () group_left", %{"fuzz" => "6", "buzz" => "4"}}
    ]

    # Collect the complete block before asserting the error substring, so the
    # public red replay also executes every unchanged successful oracle.
    responses =
      for {operator, expected} <- cases,
          {path, bounds} <- [
            {"/query", [time: to_string(ctx.now + 60 * @second)]},
            {"/query_range",
             [start: to_string(ctx.now + 60 * @second), end: to_string(ctx.now + 180 * @second), step: "30"]}
          ],
          method <- [&request/4, &request_form/4] do
        query = left <> " " <> operator <> " " <> right
        status = if is_tuple(expected), do: 400, else: 200
        {path, query, expected, method.(ctx, path, [query: query] ++ bounds, status)}
      end

    assert length(responses) == 20
    assert_parquet(ctx, 1)
    assert_parquet_read(ctx)

    for {path, query, expected, response} <- responses, is_map(expected) do
      assert length(response["data"]["result"]) == 2

      actual =
        Map.new(response["data"]["result"], fn series ->
          {series["metric"], series[if(path == "/query", do: "value", else: "values")]}
        end)

      expected =
        Map.new(expected, fn {machine, value} ->
          points = for time <- [60, 90, 120, 150, 180], do: [div(ctx.now, @second) + time, value]
          {%{"app" => "foo", "machine" => machine}, if(path == "/query", do: hd(points), else: points)}
        end)

      assert actual == expected, query
    end

    # Authored raw-byte control over the unchanged source loads, including noise.
    for method <- [&request/4, &request_form/4] do
      response =
        method.(
          ctx,
          "/query_range",
          [
            query: ~s/{app=~"foo|noise"}/,
            start: to_string(ctx.now),
            end: to_string(ctx.now + 271 * @second),
            direction: "forward",
            limit: "100"
          ],
          200
        )

      expected =
        Map.new(
          [
            {%{"app" => "foo", "machine" => "fuzz"}, "x", 10},
            {%{"app" => "foo", "machine" => "buzz"}, "x", 15},
            {%{"app" => "noise"}, "noise", 10}
          ],
          fn {labels, line, seconds} ->
            {labels, for(index <- 0..18, do: [to_string(ctx.now + index * seconds * @second), line])}
          end
        )

      assert Map.new(response["data"]["result"], &{&1["stream"], &1["values"]}) == expected
    end

    for {_path, query, {:error, message}, response} <- responses do
      assert response["error"] == "evaluation_failed"
      assert response["message"] =~ message, query <> ": " <> inspect(response)
    end
  end

  # Complete binary_operations.logqltest:888-929: all three original loads,
  # including noise, and all ten original evaluations. Only the epoch shifts.
  @tag :binary_matching_diagnostics_batch
  test "complete Loki group-right block retains matching diagnostics and original values", ctx do
    ctx = %{ctx | now: (div(ctx.now, @second) - 400) * @second}
    push_binary_matching_fixture(ctx)
    left = ~s/sum by (app) (count_over_time({app="foo"}[1m]))/
    right = ~s/sum by (app,machine) (count_over_time({app="foo"}[1m]))/
    expected_error = "found duplicate series on the right hand-side"

    cases = [
      {">= bool ignoring (machine)", {:error, expected_error}},
      {">= bool on () group_right", "1"},
      {">= bool on () group_right ()", "1"},
      {">= bool ignoring (machine) group_right", "1"},
      {"> on () group_right", "10"}
    ]

    # Collect every evaluation before checking diagnostics, so a red run still
    # executes the complete source block and both HTTP transports.
    responses =
      for {operator, expected} <- cases,
          {path, bounds} <- [
            {"/query", [time: to_string(ctx.now + 60 * @second)]},
            {"/query_range",
             [start: to_string(ctx.now + 60 * @second), end: to_string(ctx.now + 180 * @second), step: "30"]}
          ],
          method <- [&request/4, &request_form/4] do
        query = left <> " " <> operator <> " " <> right
        status = if is_tuple(expected), do: 400, else: 200
        {path, query, expected, method.(ctx, path, [query: query] ++ bounds, status)}
      end

    assert length(responses) == 20
    assert_parquet(ctx, 1)
    assert_parquet_read(ctx)

    for {path, query, expected, response} <- responses do
      case expected do
        {:error, message} ->
          assert response["error"] == "evaluation_failed"
          assert response["message"] =~ message, query <> ": " <> inspect(response)

        value ->
          labels = for machine <- ["fuzz", "buzz"], do: %{"app" => "foo", "machine" => machine}
          assert length(response["data"]["result"]) == 2

          if path == "/query" do
            assert values(response) == Map.new(labels, &{&1, value}), query

            assert Enum.all?(response["data"]["result"], fn series ->
                     hd(series["value"]) == div(ctx.now, @second) + 60
                   end)
          else
            assert response["data"]["resultType"] == "matrix"
            points = for time <- [60, 90, 120, 150, 180], do: [div(ctx.now, @second) + time, value]
            actual = Map.new(response["data"]["result"], &{&1["metric"], &1["values"]})
            assert actual == Map.new(labels, &{&1, points}), query
          end
      end
    end
  end

  @tag :binary_matching_diagnostics_batch
  @tag :binary_missing_group_batch
  test "authored matching controls retain side context without relabeling unrelated failures", ctx do
    ctx = %{ctx | now: (div(ctx.now, @second) - 400) * @second}
    push_binary_matching_fixture(ctx)
    many = ~s/sum by (app,machine) (count_over_time({app="foo"}[1m]))/
    one = ~s/sum by (app) (count_over_time({app="foo"}[1m]))/
    suffix = ";many-to-many matching not allowed: matching labels must be unique on one side"

    # Authored queries over the unchanged source loads, not extra upstream rows.
    cases = [
      {many <> " >= bool on (app) group_right " <> one, "found duplicate series on the left hand-side" <> suffix},
      {one <> " >= bool on (app) group_left " <> many, "found duplicate series on the right hand-side" <> suffix},
      {many <> " >= bool on (app) " <> one,
       "multiple matches for labels: many-to-one matching must be explicit (group_left/group_right)"},
      {many <> " > bool on (app) group_left (machine) " <> one, ":multiple_matches_for_labels"}
    ]

    for {query, expected} <- cases,
        {path, bounds} <- [
          {"/query", [time: to_string(ctx.now + 60 * @second)]},
          {"/query_range",
           [start: to_string(ctx.now + 60 * @second), end: to_string(ctx.now + 180 * @second), step: "30"]}
        ],
        method <- [&request/4, &request_form/4] do
      response = method.(ctx, path, [query: query] ++ bounds, 400)
      assert response == %{"status" => "error", "error" => "evaluation_failed", "message" => expected}, query
    end

    assert_parquet(ctx, 1)
    assert_parquet_read(ctx)
  end

  @tag :binary_matching_diagnostics_batch
  @tag :binary_missing_group_batch
  test "matching diagnostics cannot bypass authentication or existing admission, scan and work budgets", ctx do
    ctx = %{ctx | now: (div(ctx.now, @second) - 400) * @second}
    push_binary_matching_fixture(ctx)
    many = ~s/sum by (app,machine) (count_over_time({app="foo"}[1m]))/
    one = ~s/sum by (app) (count_over_time({app="foo"}[1m]))/

    endpoints = [
      {"/query", [time: to_string(ctx.now + 60 * @second)]},
      {"/query_range", [start: to_string(ctx.now + 60 * @second), end: to_string(ctx.now + 180 * @second), step: "30"]}
    ]

    for query <- [one <> " >= bool ignoring (machine) " <> many, many <> " > bool ignoring (machine) " <> one] do
      for {path, bounds} <- endpoints, method <- [&request/4, &request_form/4] do
        before = Agent.get(ctx.store, & &1.requests)
        unauthorized = method.(%{ctx | token: "wrong-token"}, path, [query: query] ++ bounds, 401)
        assert unauthorized["error"] == "invalid_token"
        assert Agent.get(ctx.store, & &1.requests) == before
      end

      for {module, config, status, error} <- [
            {Pulse.QueryRunner, [max_per_tenant: 0], 429, "query_overloaded"},
            {Pulse.QueryRunner, [max_scan_rows: 1], 422, "query_limit"},
            {Evaluator, [max_work: 1], 422, "query_limit"}
          ] do
        original = Runtime.get_env(:pulse, module, [])
        Runtime.put_env(:pulse, module, Keyword.merge(original, config))

        for {path, bounds} <- endpoints, method <- [&request/4, &request_form/4] do
          before = Agent.get(ctx.store, & &1.requests)
          response = method.(ctx, path, [query: query] ++ bounds, status)
          assert response["error"] == error
          refute Map.has_key?(response, "data")
          if status == 429, do: assert(Agent.get(ctx.store, & &1.requests) == before)
        end

        Runtime.put_env(:pulse, module, original)
      end
    end
  end

  # Complete scalar sections of binary_operations.logqltest:1-87. Expected
  # values are source literals, not answers regenerated from Pulse.
  @tag :loki_scalars_batch
  test "LogQL engine scalar arithmetic, comparisons, precedence and literal grammar", ctx do
    cases = [
      {"2", "2"},
      {"1+1", "2"},
      {"7 - 2", "5"},
      {"7 * 2", "14"},
      {"2 ^ 3", "8"},
      {"10 / 5 / 2", "1"},
      {"10 / (5 / 2)", "4"},
      {"10 % 3", "1"},
      {"1+1--1", "3"},
      {"0x1p3", "8"},
      {"0X1p3", "8"},
      {"0x1P3", "8"},
      {"0x1.8p3", "12"},
      {"10 / 0", "NaN"},
      {"-10 / 0", "NaN"},
      {"10 % 0", "NaN"},
      {"7 == 7", "1"},
      {"7 != 2", "1"},
      {"7 > 2", "1"},
      {"2 > 7", "0"},
      {"7 >= 7", "1"},
      {"2 < 7", "1"},
      {"2 <= 2", "1"},
      {"7 == bool 7", "1"},
      {"2 == bool 1", "0"},
      {"2^3^2", "512"},
      {"2 % 2^3", "2"},
      {"-2^2", "4"}
    ]

    for {query, value} <- cases do
      params = [query: query, time: "60000000000"]
      expected = %{"resultType" => "scalar", "result" => [60, value], "stats" => %{}}
      assert request(ctx, "/query", params)["data"] == expected, query
      assert request_form(ctx, "/query", params)["data"] == expected, query

      # Additional Pulse range replay of every selected scalar expression.
      params = [query: query, start: "60000000000", end: "120000000000", step: "30s"]

      expected = %{
        "resultType" => "matrix",
        "result" => [%{"metric" => %{}, "values" => [[60, value], [90, value], [120, value]]}],
        "stats" => %{}
      }

      assert request(ctx, "/query_range", params)["data"] == expected, query
      assert request_form(ctx, "/query_range", params)["data"] == expected, query
    end

    assert Agent.get(ctx.store, & &1.requests) == []
  end

  @tag :loki_scalars_batch
  test "LogQL engine scalar invalid forms reject without storage", ctx do
    for query <- ["0b1010", "0o17", "0x1A", "1 and 2", ~s|-count_over_time({app="foo"}[1m])|] do
      response = request(ctx, "/query", [query: query, time: "60000000000"], 400)
      assert response["status"] == "error"
      assert response["error"] in ["parse_error", "evaluation_failed"]
      assert response["message"] != ""
      assert request_form(ctx, "/query", [query: query, time: "60000000000"], 400) == response
    end

    assert Agent.get(ctx.store, & &1.requests) == []
  end

  # functions.logqltest:8-23: vector literals stay vectors, not scalars.
  @tag :loki_scalars_batch
  test "LogQL engine vector literals preserve instant and range result types", ctx do
    for {query, value} <- [{"vector(2)", "2"}, {"vector(3.14)", "3.14"}] do
      expected = %{
        "resultType" => "vector",
        "result" => [%{"metric" => %{}, "value" => [60, value]}],
        "stats" => %{}
      }

      assert request(ctx, "/query", query: query, time: "60000000000")["data"] == expected
      assert request_form(ctx, "/query", query: query, time: "60000000000")["data"] == expected

      expected = %{
        "resultType" => "matrix",
        "result" => [%{"metric" => %{}, "values" => for(ts <- [60, 90, 120, 150, 180], do: [ts, value])}],
        "stats" => %{}
      }

      params = [query: query, start: "60000000000", end: "180000000000", step: "30s"]
      assert request(ctx, "/query_range", params)["data"] == expected
      assert request_form(ctx, "/query_range", params)["data"] == expected
    end

    response = request(ctx, "/query", [query: ~s|vector(count_over_time({app="a"}[1m]))|], 400)
    assert response["error"] == "parse_error"
    assert Agent.get(ctx.store, & &1.requests) == []
  end

  @tag :loki_scalars_batch
  test "Pulse LogQL scalar controls preserve zeros, vector division and admission", ctx do
    for {query, kind, value} <- [
          {"-0", "scalar", "-0"},
          {"+0", "scalar", "0"},
          {".5", "scalar", "0.5"},
          {"2.", "scalar", "2"},
          {"1_000", "scalar", "1000"},
          {"0x_1.8p+2", "scalar", "6"},
          {"1 / (2 > 7)", "scalar", "NaN"},
          {"2 / -0", "scalar", "NaN"},
          {"2 / vector(0)", "vector", "NaN"},
          {"vector(2) / 0", "vector", "NaN"},
          {"vector(2) / vector(0)", "vector", "NaN"},
          {"vector(0) / vector(2)", "vector", "0"}
        ] do
      params = [query: query, time: "60000000000"]
      result = if kind == "scalar", do: [60, value], else: [%{"metric" => %{}, "value" => [60, value]}]
      assert request(ctx, "/query", params)["data"] == %{"resultType" => kind, "result" => result, "stats" => %{}}
    end

    flags = Map.put(ctx, :extra_headers, [{"x-loki-response-encoding-flags", "categorize-labels,future"}])
    response = request(flags, "/query", query: "2", time: "60000000000")
    assert response["data"]["encodingFlags"] == ["categorize-labels", "future"]
    assert response["data"]["resultType"] == "scalar"
    assert response["data"]["result"] == [60, "2"]

    for query <- ["1e309", "0x1p1024", "1__0", "0x1p", String.duplicate("9", 400)] do
      assert request(ctx, "/query", [query: query], 400)["error"] == "parse_error"
    end

    assert Req.get!(url: ctx.url <> "/loki/api/v1/query", params: [query: "2"]).status == 401
    assert Agent.get(ctx.store, & &1.requests) == []
  end

  describe "TestMicroServicesIngestQueryWithSchemaChange public stored results" do
    setup ctx do
      push(ctx, "lineA", ctx.now - 72 * 60 * @minute, %{"job" => "fake"})
      push(ctx, "lineB", ctx.now - 48 * 60 * @minute, %{"job" => "fake"})
      :ok
    end

    test "query again to verify logs being served from storage", ctx do
      assert_parquet(ctx, 2)
      params = [{"query", ~s({job="fake"})} | range(ctx)]
      response = request(ctx, "/query_range", params)
      assert_streams(response, [{%{"job" => "fake"}, ["lineB", "lineA"]}])
      assert request_form(ctx, "/query_range", params) == response
      assert_parquet_read(ctx)
    end

    test "query both periods to verify logs being served from storage", ctx do
      push(ctx, "lineC", ctx.now, %{"job" => "fake"})
      push(ctx, "lineD", ctx.now, %{"job" => "fake"})
      assert_parquet(ctx, 4)

      params = [{"query", ~s({job="fake"})} | range(ctx)]
      response = request(ctx, "/query_range", params)
      assert response["data"]["resultType"] == "streams"
      assert lines(response) == ["lineA", "lineB", "lineC", "lineD"]
      assert request_form(ctx, "/query_range", params) == response
      assert_parquet_read(ctx)
    end
  end

  test "Pulse control: historical raw-log partitions retain exclusive upper boundaries", ctx do
    for {line, timestamp} <- [
          {"lineA", ctx.now - 72 * 60 * @minute},
          {"lineB", ctx.now - 48 * 60 * @minute},
          {"lineC", ctx.now},
          {"lineD", ctx.now}
        ] do
      push(ctx, line, timestamp, %{"job" => "fake"})
    end

    for {start, finish, expected} <- [
          {ctx.now - 72 * 60 * @minute, ctx.now - 48 * 60 * @minute, ["lineA"]},
          {ctx.now - 72 * 60 * @minute, ctx.now - 48 * 60 * @minute + 1, ["lineA", "lineB"]},
          {ctx.now - 72 * 60 * @minute + 1, ctx.now - 48 * 60 * @minute - 1, []},
          {ctx.now - 48 * 60 * @minute + 1, ctx.now, []},
          {ctx.now - 48 * 60 * @minute + 1, ctx.now + 1, ["lineC", "lineD"]}
        ],
        direction <- ["forward", "backward"] do
      params = [query: ~s({job="fake"}), start: to_string(start), end: to_string(finish), direction: direction]
      response = request(ctx, "/query_range", params)
      assert lines(response) == expected
      assert request_form(ctx, "/query_range", params) == response
    end

    assert_parquet_read(ctx)
  end

  describe "TestMicroServicesIngestQuery" do
    setup ctx do
      for {line, timestamp} <- [
            {"lineA", ctx.now - 45 * @minute},
            {"lineB", ctx.now - 45 * @minute},
            {"lineC", ctx.now},
            {"lineD", ctx.now}
          ] do
        push(ctx, line, timestamp, %{"job" => "fake"})
      end

      assert_parquet(ctx, 4)
      :ok
    end

    test "query", ctx do
      response = query(ctx, ~s({job="fake"}))
      assert response["data"]["resultType"] == "streams"
      assert lines(response) == ["lineA", "lineB", "lineC", "lineD"]
      assert_parquet_read(ctx)
    end

    test "label-names", ctx do
      assert request(ctx, "/labels")["data"] == ["job"]
      assert_parquet_read(ctx)
    end

    test "label-values", ctx do
      assert request(ctx, "/label/job/values")["data"] == ["fake"]
      assert_parquet_read(ctx)
    end

    test "series", ctx do
      assert request(ctx, "/series", [{"match[]", ~s({job="fake"})} | range(ctx)])["data"] == [%{"job" => "fake"}]
      assert_parquet_read(ctx)
    end

    test "series error", ctx do
      response = request(ctx, "/series", [{"match[]", ~s({job="fake"}|= "search")} | range(ctx)], 400)
      assert response["message"] =~ "only label matchers are supported"
      refute_parquet_read(ctx)
    end

    test "stats error", ctx do
      response = request(ctx, "/index/stats", [{"query", ~s({job="fake"}|= "search")}], 400)
      assert response["message"] =~ "only label matchers are supported"
      refute_parquet_read(ctx)
    end

    test "per-request-limits", ctx do
      limited = Map.put(ctx, :extra_headers, [{"x-loki-query-limits", ~s({"maxQueryLength":"1m"})}])
      response = request(limited, "/labels", [], 400)
      assert response["message"] =~ "the query time range exceeds the limit (query length"
      refute_parquet_read(ctx)
    end

    test "tail", ctx do
      # The pinned Tail client uses the connection's wall clock, not Client.Now,
      # with limit=100, start=now-1h and no delay_for parameter for zero delay.
      {:ok, socket} =
        tail(ctx, ~s({job="fake"}), [
          {"limit", "100"},
          {"start", to_string(System.system_time(:nanosecond) - 60 * @minute)}
        ])

      try do
        entries = tail_values(socket, 4)
        assert Enum.sort(Enum.map(entries, &Enum.at(&1, 1))) == ["lineA", "lineB", "lineC", "lineD"]
        assert_parquet_read(ctx)
      after
        WebSocketClient.close(socket)
      end
    end
  end

  describe "TestProbabilisticQuery" do
    setup ctx do
      for {line, timestamp, job} <- [
            {"lineA", ctx.now - 45 * @minute, "one"},
            {"lineB", ctx.now - 45 * @minute, "one"},
            {"lineC", ctx.now, "one"},
            {"lineD", ctx.now, "two"}
          ] do
        push(ctx, line, timestamp, %{"job" => job})
      end

      assert_parquet(ctx, 4)
      :ok
    end

    test "query", ctx do
      response = instant(ctx, ~s'approx_topk(1, count_over_time({job=~".+"}[1h]))')
      assert response["data"]["resultType"] == "vector"
      assert length(response["data"]["result"]) == 1
      assert values(response) == %{%{"job" => "one"} => "3"}
      assert_parquet_read(ctx)
    end

    # Pulse-authored controls, not additional upstream integration cases.
    test "bounded exact ranking preserves values, inner grouping, windows and form transport", ctx do
      inner = ~s'count_over_time({job=~".+"}[1h])'

      for k <- [2, 10, 9_223_372_036_854_775_807] do
        expression = "approx_topk(#{k}, #{inner})"
        response = instant(ctx, expression)
        assert length(response["data"]["result"]) == 2
        assert values(response) == %{%{"job" => "one"} => "3", %{"job" => "two"} => "1"}

        assert request_form(ctx, "/query", query: expression, time: to_string(ctx.now + @second)) == response
      end

      assert values(instant(ctx, "approx_topk(1, sum without(job) (#{inner}))")) == %{%{} => "4"}

      assert values(instant(ctx, ~s'approx_topk(2, count_over_time({job=~".+"}[1m]))')) ==
               %{%{"job" => "one"} => "1", %{"job" => "two"} => "1"}

      assert values(instant(ctx, ~s'approx_topk(1, count_over_time({job="absent"}[1h]))')) == %{}
      assert values(instant(ctx, "approx_topk(1, #{inner}) * 2")) == %{%{"job" => "one"} => "6"}
    end

    test "invalid ranks and outer grouping reject before storage; range mode rejects every nested placement", ctx do
      inner = ~s'count_over_time({job=~".+"}[1h])'
      requests = Agent.get(ctx.store, & &1.requests)

      for expression <- [
            "approx_topk(0, #{inner})",
            "approx_topk(-1, #{inner})",
            "approx_topk(1.5, #{inner})",
            "approx_topk(1.0, #{inner})",
            "approx_topk(1e0, #{inner})",
            "approx_topk(9223372036854775808, #{inner})",
            "approx_topk(#{inner})",
            "approx_topk(1, #{inner}) by ()",
            "approx_topk(1, #{inner}) without (job)",
            "approx_topk by(job) (1, #{inner})"
          ] do
        params = [query: expression, time: to_string(ctx.now + @second)]
        assert request(ctx, "/query", params, 400)["status"] == "error"
        assert request_form(ctx, "/query", params, 400)["status"] == "error"
      end

      for expression <- [
            "approx_topk(1, #{inner})",
            "sum(approx_topk(1, #{inner}))",
            "#{inner} + approx_topk(1, #{inner})",
            "approx_topk(1, #{inner}) + #{inner}"
          ] do
        params = [query: expression, start: to_string(ctx.now), end: to_string(ctx.now + @second), step: "1"]

        for response <- [request(ctx, "/query_range", params, 400), request_form(ctx, "/query_range", params, 400)] do
          assert response["status"] == "error"
          assert response["message"] == ":instant_query_required"
        end
      end

      assert Agent.get(ctx.store, & &1.requests) == requests
    end

    test "small output ranks do not bypass scan or intermediate result budgets", ctx do
      expression = ~s'approx_topk(1, count_over_time({job=~".+"}[1h]))'
      params = [query: expression, time: to_string(ctx.now + @second)]
      objects = Agent.get(ctx.store, & &1.objects)
      Runtime.put_env(:pulse, Pulse.QueryRunner, max_scan_rows: 1)
      assert request(ctx, "/query", params, 422)["error"] == "query_limit"

      Runtime.put_env(:pulse, Pulse.QueryRunner, [])
      Runtime.put_env(:pulse, Evaluator, max_result_points: 1)
      assert request_form(ctx, "/query", params, 422)["error"] == "query_limit"
      assert Agent.get(ctx.store, & &1.objects) == objects
    end
  end

  describe "TestApproxCountDistinctQuery" do
    setup ctx do
      for {mac, minutes, device} <- [
            {"shared", 20, "a"},
            {"only-a", 10, "a"},
            {"shared", 15, "b"},
            {"only-b", 5, "b"}
          ] do
        push(ctx, ~s(mac="#{mac}"), ctx.now - minutes * @minute, %{
          "job" => "devices",
          "version" => "1",
          "device" => device
        })
      end

      assert_parquet(ctx, 4)
      :ok
    end

    test "query", ctx do
      response = instant(ctx, ~s'approx_count_distinct(mac, {job="devices"} | logfmt [1h]) by (version)')
      assert length(response["data"]["result"]) == 1
      assert values(response) == %{%{"version" => "1"} => "3"}
      assert_parquet_read(ctx)
    end

    test "query-ungrouped", ctx do
      response = instant(ctx, ~s'approx_count_distinct(mac, {job="devices"} | logfmt [1h]) by ()')
      assert length(response["data"]["result"]) == 1
      assert values(response) == %{%{} => "3"}
      assert_parquet_read(ctx)
    end

    # Pulse-authored controls, not additional upstream integration cases.
    test "distinct strings skip missing/empty fields and remove only the counted label", ctx do
      for line <- [~s(mac="01"), ~s(mac="1"), ~s(mac="1.0"), ~s(mac="01"), ~s(mac=""), ""] do
        push(ctx, line, ctx.now, %{"job" => "devices", "version" => "2", "device" => "c"})
      end

      expression = ~s'approx_count_distinct(mac, {job="devices"} | logfmt [1h])'
      response = instant(ctx, expression)
      assert length(response["data"]["result"]) == 3

      assert values(response) == %{
               %{"job" => "devices", "version" => "1", "device" => "a"} => "2",
               %{"job" => "devices", "version" => "1", "device" => "b"} => "2",
               %{"job" => "devices", "version" => "2", "device" => "c"} => "3"
             }

      assert request_form(ctx, "/query", query: expression, time: to_string(ctx.now + @second)) == response

      assert values(instant(ctx, expression <> " by (version)")) ==
               %{%{"version" => "1"} => "3", %{"version" => "2"} => "3"}

      assert values(instant(ctx, "(#{expression} by ()) * 2")) == %{%{} => "12"}

      assert values(instant(ctx, ~s'approx_count_distinct(device, {job="devices"}[1h])')) ==
               %{%{"job" => "devices", "version" => "1"} => "2", %{"job" => "devices", "version" => "2"} => "1"}

      assert values(instant(ctx, ~s'approx_count_distinct(missing, {job="devices"}[1h]) by ()')) == %{}
    end

    test "range windows deduplicate independently with open lower bounds, inclusive ends and offsets", ctx do
      expression = ~s'approx_count_distinct(mac, {job="devices"} | logfmt [10m]) by ()'

      params = [
        query: expression,
        start: to_string(ctx.now - 20 * @minute),
        end: to_string(ctx.now),
        step: "300"
      ]

      response = request(ctx, "/query_range", params)
      assert response["data"]["resultType"] == "matrix"

      expected =
        for {minutes, value} <- [{20, "1"}, {15, "1"}, {10, "2"}, {5, "2"}, {0, "1"}],
            do: [(ctx.now - minutes * @minute) / @second, value]

      assert response["data"]["result"] == [%{"metric" => %{}, "values" => expected}]
      assert request_form(ctx, "/query_range", params) == response

      offset_expression = ~s'approx_count_distinct(mac, {job="devices"} | logfmt [10m] offset 5m) by ()'
      offset = request(ctx, "/query_range", Keyword.put(params, :query, offset_expression))

      expected =
        for {minutes, value} <- [{15, "1"}, {10, "1"}, {5, "2"}, {0, "2"}],
            do: [(ctx.now - minutes * @minute) / @second, value]

      assert offset["data"]["result"] == [%{"metric" => %{}, "values" => expected}]

      # The only-a value first appears at the inclusive upper bound; the
      # overlapping shared values still count once across both streams.
      for {time, count} <- [{ctx.now - 10 * @minute - 1, "1"}, {ctx.now - 10 * @minute, "2"}] do
        response = request(ctx, "/query", query: expression, time: to_string(time))
        assert values(response) == %{%{} => count}
      end

      assert values(request(ctx, "/query", query: expression, time: to_string(ctx.now - 20 * @minute - 1))) == %{}
    end

    test "invalid distinct arguments, grouping and unwrap reject before provider requests", ctx do
      requests = Agent.get(ctx.store, & &1.requests)

      for expression <- [
            ~s'approx_count_distinct({job="devices"}[1h])',
            ~s'approx_count_distinct(1, {job="devices"}[1h])',
            ~s'approx_count_distinct("mac", {job="devices"}[1h])',
            ~s'approx_count_distinct(mac, {job="devices"}[0s])',
            ~s'approx_count_distinct(mac, {job="devices"}[1h]) without (device)',
            ~s'approx_count_distinct(mac, {job="devices"}[1h]) by (version, mac)',
            ~s'approx_count_distinct(mac, {job="devices"} | unwrap mac [1h])',
            ~s'approx_count_distinct(mac, {job="devices"}[1h] @ 1)',
            ~s'count_over_time(mac, {job="devices"}[1h])',
            ~s'quantile_over_time(mac, {job="devices"} | unwrap n [1h])'
          ] do
        params = [query: expression, time: to_string(ctx.now)]
        assert request(ctx, "/query", params, 400)["status"] == "error"
        assert request_form(ctx, "/query", params, 400)["status"] == "error"
      end

      assert Agent.get(ctx.store, & &1.requests) == requests
    end

    test "one distinct result still charges duplicate observations and fails whole on exhausted budgets", ctx do
      expression = ~s'approx_count_distinct(mac, {job="devices"} | logfmt [1h]) by ()'
      params = [query: expression, time: to_string(ctx.now + @second)]
      objects = Agent.get(ctx.store, & &1.objects)
      Runtime.put_env(:pulse, Pulse.QueryRunner, max_scan_rows: 3)
      assert request(ctx, "/query", params, 422)["error"] == "query_limit"
      Runtime.put_env(:pulse, Pulse.QueryRunner, [])

      for limit <- [[max_log_samples: 3], [max_materialized_samples: 3], [max_result_points: 0], [max_work: 5]] do
        Runtime.put_env(:pulse, Evaluator, limit)
        response = request_form(ctx, "/query", params, 422)
        assert response["error"] == "query_limit"
        refute Map.has_key?(response, "data")
      end

      Runtime.put_env(:pulse, Evaluator, max_log_samples: 4, max_materialized_samples: 4, max_result_points: 1)
      assert values(instant(ctx, expression)) == %{%{} => "3"}
      assert Agent.get(ctx.store, & &1.objects) == objects
    end
  end

  # These are executable upstream LogQL fixtures, not additional microservice
  # integration tests. Preserve every selected query and its complete result.
  @tag :compensated_sum_upstream
  test "vector_aggregations.logqltest sum_over_time retains cancellation residuals", ctx do
    ctx = %{ctx | now: div(ctx.now, @second) * @second - 180 * @second}

    # Original app=k load rows and all four evaluations from the pinned
    # vector_aggregations.logqltest:246-251,268-277. Other apps cannot match.
    for {c, count, finish} <- [{"ten", 10, 16}, {"seven", 7, 13}] do
      labels = %{"app" => "k", "c" => c}
      push(ctx, "v=10000000000000000", ctx.now + 5 * @second, labels)

      for index <- 0..(count - 1) do
        push(ctx, "v=1", ctx.now + (6 + index) * @second, labels)
      end

      push(ctx, "v=-10000000000000000", ctx.now + finish * @second, labels)
    end

    assert_parquet(ctx, 21)

    assert_metric(ctx, ~s'sum by (c) (sum_over_time({app="k"} | logfmt | unwrap v [1m]))', 60, %{
      %{"c" => "ten"} => [{60, "10"}],
      %{"c" => "seven"} => [{60, "7"}]
    })

    assert_metric(ctx, ~s'sum(sum_over_time({app="k"} | logfmt | unwrap v [1m]))', 60, %{
      %{} => [{60, "17"}]
    })

    assert_metric(ctx, ~s'sum by (c) (sum_over_time({app="k"} | logfmt | unwrap v [1m]))', {20, 60, 20}, %{
      %{"c" => "ten"} => [{20, "10"}, {40, "10"}, {60, "10"}],
      %{"c" => "seven"} => [{20, "7"}, {40, "7"}, {60, "7"}]
    })

    assert_metric(ctx, ~s'sum(sum_over_time({app="k"} | logfmt | unwrap v [20s]))', {20, 60, 40}, %{
      %{} => [{20, "17"}]
    })
  end

  @tag :vector_sum_precision_upstream
  test "upstream vector sum retains all 10000 small contributions", ctx do
    ctx = %{ctx | now: div(ctx.now, @second) * @second - 180 * @second}

    # TestVectorAggEvaluator_Precision/sum(), evaluator_test.go:1064-1073:
    # preserve every original value and the literal large+10000 oracle.
    # Unit-to-HTTP adaptation: unique stream labels keep the 10001 samples
    # distinct through max_over_time; sort_desc restores the unit input order.
    streams =
      for index <- 0..10_000 do
        value = if index == 0, do: "10000000000000000", else: "1"

        %{
          "stream" => %{"app" => "vector-sum-precision", "series" => Integer.to_string(index)},
          "values" => [[to_string(ctx.now + 30 * @second), "v=" <> value]]
        }
      end

    assert length(streams) == 10_001
    streams |> Enum.chunk_every(1000) |> Enum.each(&push_streams(ctx, &1))
    assert_parquet(ctx, 11)

    inner = ~s'max_over_time({app="vector-sum-precision"} | logfmt | unwrap v [1m])'
    expected = %{%{} => [{60, "10000000000010000"}]}

    assert_metric(ctx, "sum(sort_desc(#{inner}))", 60, expected)
    assert_metric(ctx, "sum(#{inner})", 60, expected)
    # The second window (60s,120s] is empty, not a zero-valued sample.
    assert_metric(ctx, "sum(#{inner})", {60, 120, 60}, expected)
  end

  @tag :raw_log_exclusive_end_upstream
  test "original log-selection upper boundary is exclusive before ordering and top-k", ctx do
    ctx = %{ctx | now: div(ctx.now, @second) * @second - 180 * @second}

    # Complete active log_selection.logqltest:28-36; only the epoch changes.
    push_streams(ctx, [
      %{
        "stream" => %{"app" => "foo"},
        "values" => [
          [to_string(ctx.now + 10 * @second), "in range"],
          [to_string(ctx.now + 20 * @second), "at boundary"]
        ]
      }
    ])

    assert_parquet(ctx, 1)

    # First row is the unchanged original oracle. The remaining rows are
    # authored direction/top-k/adjacent-nanosecond/start-inclusive controls.
    for {start, finish, direction, limit, values} <- [
          {0, 20 * @second, "forward", "100", [{10 * @second, "in range"}]},
          {0, 20 * @second, "backward", "100", [{10 * @second, "in range"}]},
          {0, 20 * @second, "forward", "1", [{10 * @second, "in range"}]},
          {0, 20 * @second, "backward", "1", [{10 * @second, "in range"}]},
          {0, 20 * @second - 1, "forward", "100", [{10 * @second, "in range"}]},
          {0, 20 * @second + 1, "forward", "100", [{10 * @second, "in range"}, {20 * @second, "at boundary"}]},
          {20 * @second, 20 * @second + 1, "forward", "100", [{20 * @second, "at boundary"}]},
          {20 * @second - 1, 20 * @second, "backward", "1", []}
        ] do
      params = [
        query: ~s/{app="foo"}/,
        start: to_string(ctx.now + start),
        end: to_string(ctx.now + finish),
        direction: direction,
        limit: limit
      ]

      expected =
        if values == [],
          do: [],
          else: [
            %{
              "stream" => %{"app" => "foo"},
              "values" => Enum.map(values, fn {time, line} -> [to_string(ctx.now + time), line] end)
            }
          ]

      for method <- [&request/4, &request_form/4] do
        assert method.(ctx, "/query_range", params, 200)["data"]["result"] == expected
      end
    end

    # These APIs retain their existing inclusive endpoint contracts.
    for method <- [&request/4, &request_form/4] do
      response =
        method.(
          ctx,
          "/query",
          [
            query: ~s/{app="foo"}/,
            start: to_string(ctx.now),
            time: to_string(ctx.now + 20 * @second),
            direction: "forward"
          ],
          200
        )

      assert [%{"values" => [[_, "in range"], [_, "at boundary"]]}] = response["data"]["result"]

      assert method.(
               ctx,
               "/labels",
               [start: to_string(ctx.now + 20 * @second), end: to_string(ctx.now + 20 * @second)],
               200
             )["data"] == ["app"]

      fields =
        method.(
          ctx,
          "/detected_fields",
          [
            query: ~s/{app="foo"} | line_format "value=present"/,
            start: to_string(ctx.now + 20 * @second),
            end: to_string(ctx.now + 20 * @second)
          ],
          200
        )

      assert [%{"label" => "value", "cardinality" => 1}] = fields["fields"]
    end

    assert_metric(ctx, ~s/count_over_time({app="foo"}[1m])/, 20, %{%{"app" => "foo"} => [{20, "2"}]})
    assert_metric(ctx, ~s/count_over_time({app="foo"}[1m])/, {20, 20, 1}, %{%{"app" => "foo"} => [{20, "2"}]})
    assert_parquet_read(ctx)

    # Equal bounds are empty even when a row exists at that exact timestamp.
    before = Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests})

    for method <- [&request/4, &request_form/4] do
      assert method.(
               ctx,
               "/query_range",
               [
                 query: ~s/{app="foo"}/,
                 start: to_string(ctx.now + 20 * @second),
                 end: to_string(ctx.now + 20 * @second)
               ],
               200
             )["data"]["result"] == []
    end

    assert Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == before
  end

  @tag :raw_log_exclusive_end_upstream
  test "empty raw-log ranges avoid providers without bypassing admission or validation", ctx do
    before = Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests})

    for time <- [ctx.now, -9_223_372_036_854_775_808, 9_223_372_036_854_775_807],
        method <- [&request/4, &request_form/4] do
      params = [query: ~s/{app="foo"}/, start: to_string(time), end: to_string(time)]

      assert method.(ctx, "/query_range", params, 200)["data"] == %{
               "resultType" => "streams",
               "result" => [],
               "stats" => %{}
             }

      method.(ctx, "/query_range", Keyword.put(params, :query, ~s/{app="foo"} |~ "("/), 400)
      method.(query_limits(ctx, ~s({"requiredLabels":["missing"]})), "/query_range", params, 400)
    end

    # 1ms + 1ns must reject against the ORIGINAL interval, not its normalized
    # inclusive storage bound (whose numerical difference would be 1ms).
    for method <- [&request/4, &request_form/4] do
      method.(
        query_limits(ctx, ~s({"maxQueryLength":"1ms"})),
        "/query_range",
        [query: ~s/{app="foo"}/, start: to_string(ctx.now), end: to_string(ctx.now + 1_000_001)],
        400
      )

      method.(
        %{ctx | token: "wrong-token"},
        "/query_range",
        [query: ~s/{app="foo"}/, start: to_string(ctx.now), end: to_string(ctx.now)],
        401
      )
    end

    assert Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == before
  end

  @tag :raw_log_exclusive_end_upstream
  test "empty raw-log validation uses bounded logql admission and query accounting", ctx do
    Runtime.put_env(:pulse, Pulse.QueryRunner, class_limits: %{logql: 1})
    slots = QuerySlots
    key = {:class, :logql, 0}
    assert {:ok, _} = Runtime.Registry.register(slots, key, nil)
    before = Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests})
    params = [query: ~s/{app="foo"}/, start: to_string(ctx.now), end: to_string(ctx.now)]
    invalid = Keyword.put(params, :query, ~s/{app="foo"} |~ "("/)
    limited = query_limits(ctx, ~s({"maxQueryTime":"200ms"}))

    # The slot belongs to this test's private runtime. Even static validation
    # must acquire the same logql class as nonempty reads, not run on the caller.
    for method <- [&request/4, &request_form/4], query <- [params, invalid] do
      assert method.(limited, "/query_range", query, 429)["error"] == "query_overloaded"
    end

    Runtime.Registry.unregister(slots, key)

    for method <- [&request/4, &request_form/4] do
      assert method.(limited, "/query_range", params, 200)["data"]["result"] == []
      method.(limited, "/query_range", invalid, 400)
    end

    metrics = Pulse.SelfMetrics.render()
    assert metrics =~ ~s(pulse_operations_total{layer="query",operation="logql_log",outcome="error"} 6\n)
    assert metrics =~ ~s(pulse_operations_total{layer="query",operation="logql_log",outcome="success"} 2\n)
    assert Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == before
  end

  @tag :absence_json_hints_upstream
  test "upstream absence skips unneeded JSON but explicit error consumers still parse", ctx do
    ctx = %{ctx | now: div(ctx.now, @second) * @second - 180 * @second}

    # Complete active range_aggregations.logqltest:1727-1745: two original
    # inputs, five literal oracles. Only the source epoch is translated.
    push_streams(ctx, [
      %{"stream" => %{"app" => "a"}, "values" => [[to_string(ctx.now + 40 * @second), "{"]]},
      %{"stream" => %{"app" => "noise"}, "values" => [[to_string(ctx.now + 40 * @second), ~s({"ok":1})]]}
    ])

    assert_parquet(ctx, 1)
    assert_metric(ctx, ~s/absent_over_time({app="a"} | json [1m])/, 60, %{})
    assert_metric(ctx, ~s/absent_over_time({app="a"} | json | __error__!="" [1m])/, 60, %{})

    assert_metric(ctx, ~s/absent_over_time({app="a"} | json | __error__!="" [1m])/, {60, 120, 60}, %{
      %{"app" => "a"} => [{120, "1"}]
    })

    assert_metric(ctx, ~s/absent_over_time({app="a"} | json | __error__="" [1m])/, 60, %{
      %{"app" => "a"} => [{60, "1"}]
    })

    assert_metric(ctx, ~s/absent_over_time({app="a"} | json | __error__="" [1m])/, {60, 120, 60}, %{
      %{"app" => "a"} => [{60, "1"}, {120, "1"}]
    })
  end

  @tag :absence_json_hints_upstream
  test "authored absence JSON hints preserve consumers, prior errors and validation", ctx do
    ctx = %{ctx | now: div(ctx.now, @second) * @second - 180 * @second}

    push_streams(ctx, [
      %{"stream" => %{"app" => "bad"}, "values" => [[to_string(ctx.now + 40 * @second), "{"]]},
      %{"stream" => %{"app" => "good"}, "values" => [[to_string(ctx.now + 40 * @second), ~s({"v":5})]]},
      %{"stream" => %{"app" => "explicit"}, "values" => [[to_string(ctx.now + 40 * @second), "not-json"]]},
      %{
        "stream" => %{"app" => "prior"},
        "values" => [[to_string(ctx.now + 40 * @second), "{", %{"__error__" => "prior", "v" => "5"}]]
      }
    ])

    assert_parquet(ctx, 1)

    # Multiple plain parsers and line-only stages need no extracted labels.
    # A post-parser line filter must not move into native head pushdown.
    for pipeline <- [~s/| json | json/, ~s/|= "{" | json | json != "absent"/, ~s/| json |= "absent"/] do
      expected =
        if String.ends_with?(pipeline, ~s/|= "absent"/),
          do: %{%{"app" => "bad"} => [{60, "1"}, {120, "1"}]},
          else: %{%{"app" => "bad"} => [{120, "1"}]}

      assert_metric(ctx, ~s/absent_over_time({app="bad"} #{pipeline} [1m])/, {60, 120, 60}, expected)
    end

    # Real label consumers must still see parsed fields and errors. An absent
    # target differs from a usable unwrap target after malformed JSON.
    for pipeline <- [
          ~s/| json | v="5"/,
          ~s/| json | line_format "{{.v}}" |= "5"/,
          ~s/| json | label_format out="{{.v}}" | out="5"/,
          ~s/| json | unwrap v/
        ] do
      assert_metric(ctx, ~s/absent_over_time({app="good"} #{pipeline} [1m])/, 60, %{})
    end

    for pipeline <- [~s/| json | v="missing"/, ~s/| json | line_format "{{.missing}}" |= "5"/] do
      assert_metric(ctx, ~s/absent_over_time({app="good"} #{pipeline} [1m])/, {60, 120, 60}, %{
        %{"app" => "good"} => [{60, "1"}, {120, "1"}]
      })
    end

    assert_metric(ctx, ~s/absent_over_time({app="bad"} | json | unwrap v [1m])/, 60, %{
      %{"app" => "bad"} => [{60, "1"}]
    })

    # An ordinary details filter sees no ordinary label. To consume the real
    # error details, capture the rendered template snapshot explicitly.
    assert_metric(ctx, ~s/absent_over_time({app="bad"} | json | __error_details__!="" [1m])/, 60, %{
      %{"app" => "bad"} => [{60, "1"}]
    })

    for {app, pipeline} <- [
          {"prior", "| json | json"},
          {"prior", "| json | unwrap v"},
          {"bad", ~s/| json | label_format diagnostic_details="{{.__error_details__}}" | diagnostic_details!=""/},
          {"bad", ~s/| json | line_format "{{.v}}"/},
          {"bad", "| json | logfmt"},
          {"bad", "| logfmt | json"},
          {"explicit", ~s/| json v="v"/}
        ],
        method <- [&request/4, &request_form/4],
        {path, times} <- [
          {"/query", [time: to_string(ctx.now + 60 * @second)]},
          {"/query_range",
           [start: to_string(ctx.now + 60 * @second), end: to_string(ctx.now + 120 * @second), step: "60"]}
        ] do
      response = method.(ctx, path, [query: ~s/absent_over_time({app="#{app}"} #{pipeline} [1m])/] ++ times, 400)
      assert response["message"] == ":pipeline_error"
    end

    before = Agent.get(ctx.store, & &1.reads)

    for method <- [&request/4, &request_form/4] do
      method.(
        ctx,
        "/query",
        [query: ~s/absent_over_time({app="bad"} | json |~ "(" [1m])/, time: to_string(ctx.now + 60 * @second)],
        400
      )
    end

    assert Agent.get(ctx.store, & &1.reads) == before

    # Both evaluators consume the same published Parquet, but assertions are
    # literal. Inspect streamed work after a post-JSON filter drops the row:
    # omission must not move that filter into provider/native head pushdown.
    for {pipeline, expected} <- [
          {"| json | json", []},
          {~s/| json |= "absent"/, [{%{"app" => "bad"}, {ctx.now + 60 * @second, 1.0}}]}
        ],
        module <- [MetricEval, MetricEvalReference] do
      {:ok, ast} = Parser.parse(~s/absent_over_time({app="bad"} #{pipeline} [1m])/)

      {result, budget} =
        Task.async(
          Runtime.capture(fn ->
            result = module.evaluate(ast, ctx.tenant, %{end_ts_ns: ctx.now + 60 * @second})
            {result, Process.get(:promql_budget)}
          end)
        )
        |> Task.await()

      assert result == {:ok, {:vector, expected}}
      assert budget.work >= 2
    end
  end

  @tag :unwrap_missing_errors_upstream
  test "upstream quantiles discard malformed JSON lines without an unwrap target", ctx do
    ctx = %{ctx | now: div(ctx.now, @second) * @second - 180 * @second}

    # Complete original setup and four evaluations: pinned
    # range_aggregations.logqltest:409-440, including the nonmatching noise.
    streams =
      for {time, app, pod, line} <- [
            {10, "a", "p1", ~s({"v":4})},
            {20, "a", "p1", ~s({"v":6})},
            {30, "a", "p1", ~s({"v":8})},
            {40, "a", "p1", "{"},
            {20, "noise", "p2", ~s({"v":1})}
          ] do
        %{"stream" => %{"app" => app, "pod" => pod}, "values" => [[to_string(ctx.now + time * @second), line]]}
      end

    push_streams(ctx, streams)
    assert_parquet(ctx, 1)

    query = ~s'quantile_over_time(0.5, {app="a"} | json | unwrap v [1m]) by (pod)'
    assert_metric(ctx, query, 60, %{%{"pod" => "p1"} => [{60, "6"}]})
    assert_metric(ctx, query, {20, 60, 40}, %{%{"pod" => "p1"} => [{20, "5"}, {60, "6"}]})

    assert_metric(ctx, ~s'quantile_over_time(0.5, {app="a"} | json | __error__="" | unwrap v [1m]) by (pod)', 60, %{
      %{"pod" => "p1"} => [{60, "6"}]
    })

    assert_metric(ctx, ~s'quantile_over_time(0.5, {app="a"} | json | __error__!="" | unwrap v [1m]) by (pod)', 60, %{})
  end

  @tag :unwrap_missing_errors_upstream
  test "missing and empty unwrap targets discard prior errors on native and fallback scans", ctx do
    ctx = %{ctx | now: div(ctx.now, @second) * @second - 180 * @second}

    # Authored controls: the same inputs run natively without stages and fall
    # back to Elixir with JSON. Only the usable, error-free value is retained.
    streams =
      for {kind, metadata} <- [
            {"missing", %{"__error__" => "prior"}},
            {"empty", %{"__error__" => "prior", "v" => ""}},
            {"good", %{"v" => "5"}}
          ] do
        %{
          "stream" => %{"job" => "unwrap-skip-errors", "case" => kind},
          "values" => [[to_string(ctx.now + 30 * @second), "{}", metadata]]
        }
      end

    push_streams(ctx, streams)
    assert_parquet(ctx, 1)

    for stage <- ["", " | json"] do
      query = ~s'sum(sum_over_time({job="unwrap-skip-errors"}#{stage} | unwrap v [1m]))'
      assert_metric(ctx, query, 60, %{%{} => [{60, "5"}]})
      assert_metric(ctx, query, {60, 120, 60}, %{%{} => [{60, "5"}]})
    end

    # Replay the actual published Parquet directly too: a successful native
    # response proves no fallback, and a one-sample cap proves skipped rows
    # do not spend the retained-sample budget. All three still count as work.
    [{_key, {_etag, bytes}}] =
      ctx.store |> Agent.get(& &1.objects) |> Enum.filter(fn {key, _} -> String.ends_with?(key, ".parquet") end)

    assert {:ok, scan} = NIF.log_metric_scan_new([], {:unwrap, "v"}, "v", nil, 1)

    assert {:ok, {3, 1}} =
             NIF.log_metric_scan_add(scan, bytes, ctx.now, ctx.now + 60 * @second, nil, [], [])

    assert {:ok, [_]} = NIF.log_metric_scan_finish(scan)
  end

  @tag :unwrap_missing_errors_upstream
  test "present unwrap targets and count or bytes observations retain prior errors", ctx do
    ctx = %{ctx | now: div(ctx.now, @second) * @second - 180 * @second}

    for {kind, metadata} <- [
          {"missing", %{"__error__" => "prior"}},
          {"empty", %{"__error__" => "prior", "v" => ""}},
          {"present", %{"__error__" => "prior", "v" => "7"}}
        ] do
      push(ctx, "{}", ctx.now + 30 * @second, %{"job" => "unwrap-keep-errors", "case" => kind}, metadata)
    end

    assert_parquet(ctx, 3)

    # Authored negative controls; neither native eligibility nor JSON fallback
    # may hide an error on a line that actually supplies an observation.
    for stage <- ["", " | json"],
        {op, kind, unwrap} <- [
          {"sum_over_time", "present", " | unwrap v"},
          {"count_over_time", "missing", ""},
          {"count_over_time", "empty", ""},
          {"bytes_over_time", "missing", ""},
          {"bytes_over_time", "empty", ""}
        ],
        {path, extra} <- [{"/query", []}, {"/query_range", [start: to_string(ctx.now + 60 * @second), step: "60"]}],
        method <- [&request/4, &request_form/4] do
      query = ~s'#{op}({job="unwrap-keep-errors",case="#{kind}"}#{stage}#{unwrap} [1m])'
      params = [query: query, time: to_string(ctx.now + 60 * @second), end: to_string(ctx.now + 60 * @second)] ++ extra

      assert method.(ctx, path, params, 400) == %{
               "status" => "error",
               "error" => "evaluation_failed",
               "message" => ":pipeline_error"
             }
    end

    assert_parquet_read(ctx)
  end

  @tag :quantile_sign_upstream
  test "range_aggregations.logqltest rejects signed quantile tokens before storage", ctx do
    ctx = %{ctx | now: div(ctx.now, @second) * @second - 180 * @second}

    # Complete original load at range_aggregations.logqltest:228-234 and
    # rejection at 273-274. Only relative times receive an epoch translation.
    for {time, line} <- [{10, "v=1"}, {20, "v=2"}, {30, "v=3"}, {40, "v=4"}, {50, "v=5"}, {110, "v=6"}, {25, "noise"}] do
      push(ctx, line, ctx.now + time * @second, %{"app" => "a"})
    end

    assert_parquet(ctx, 7)
    before = Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests})

    # -0.1 is the original oracle; the remaining signs are authored controls.
    for token <- ["-0.1", "-0", "+0", "-1e-1", "+1e-1"],
        path <- ["/query", "/query_range"],
        method <- [&request/4, &request_form/4] do
      query = ~s'quantile_over_time(#{token}, {app="a"} | logfmt | unwrap v [1m])'

      params = [
        query: query,
        time: to_string(ctx.now + 60 * @second),
        start: to_string(ctx.now + 60 * @second),
        end: to_string(ctx.now + 60 * @second),
        step: "1s"
      ]

      response = method.(ctx, path, params, 400)
      assert response["status"] == "error"
      assert response["error"] == "parse_error"
      refute Map.has_key?(response, "data")
      assert Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == before
    end

    # Original median/+Inf oracles at 243-244,270-271; exponent spellings
    # are authored controls, not additional upstream evaluations.
    for {token, expected} <- [
          {"0.5", "3"},
          {"1.5", "+Inf"},
          {"5e-1", "3"},
          {"5e+0", "+Inf"},
          {"0x1p-1", "3"},
          {"0x1p+1", "+Inf"},
          {"0", "1"}
        ] do
      query = ~s'quantile_over_time(#{token}, {app="a"} | logfmt | unwrap v [1m])'
      assert_metric(ctx, query, 60, %{%{"app" => "a"} => [{60, expected}]})
      assert_metric(ctx, query, {60, 60, 1}, %{%{"app" => "a"} => [{60, expected}]})
    end

    before = Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests})

    for {query, expected} <- [{"-2e-1", "-0.2"}, {"+2e+1", "20"}, {"-0x1p-1", "-0.5"}, {"+0x1p+1", "2"}],
        method <- [&request/4, &request_form/4] do
      params = [query: query, time: to_string(ctx.now + 60 * @second)]
      response = method.(ctx, "/query", params, 200)
      assert response["data"]["resultType"] == "scalar"
      assert response["data"]["result"] == [(ctx.now + 60 * @second) / @second, expected]
    end

    assert Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == before
  end

  describe "range_aggregations.logqltest missing unwrap fields" do
    setup ctx do
      %{now: div(ctx.now, @second) * @second - 180 * @second}
    end

    @tag :unwrap_upstream
    @tag :range_placement_batch
    test "first and last retain boundary values across noise, gaps and offsets", ctx do
      for {time, line} <- [{10, "v=10"}, {20, "v=20"}, {30, "v=30"}, {90, "v=40"}, {100, "v=NaN"}, {15, "noise"}] do
        push(ctx, line, ctx.now + time * @second, %{"app" => "a"})
      end

      assert_parquet(ctx, 6)

      for {op, window, offset, time, expected} <- [
            {"first", "1m", "", 60, [{60, "10"}]},
            {"last", "1m", "", 60, [{60, "30"}]},
            {"first", "20s", "", 40, [{40, "30"}]},
            {"last", "20s", "", 40, [{40, "30"}]},
            {"first", "20s", "", {20, 40, 10}, [{20, "10"}, {30, "20"}, {40, "30"}]},
            {"last", "20s", "", {20, 40, 10}, [{20, "20"}, {30, "30"}, {40, "30"}]},
            {"first", "10s", "", {10, 30, 20}, [{10, "10"}, {30, "30"}]},
            {"last", "10s", "", {10, 30, 20}, [{10, "10"}, {30, "30"}]},
            {"first", "20s", " offset 30s", 60, [{60, "20"}]},
            {"last", "20s", " offset 30s", 60, [{60, "30"}]},
            {"first", "20s", " offset 30s", {60, 120, 30}, [{60, "20"}, {120, "40"}]},
            {"last", "20s", " offset 30s", {60, 120, 30}, [{60, "30"}, {120, "40"}]},
            {"first", "20s", "", {30, 90, 30}, [{30, "20"}, {90, "40"}]},
            {"last", "20s", "", {30, 90, 30}, [{30, "30"}, {90, "40"}]},
            {"first", "30s", "", 110, [{110, "40"}]},
            {"last", "30s", "", 110, [{110, "NaN"}]},
            {"first", "30s", "", 125, [{125, "NaN"}]}
          ] do
        # Keep the upstream inputs/outputs and vary only equivalent placements
        # admitted by syntax.y's logRangeExpr productions.
        for body <- [
              ~s'{app="a"} | logfmt | unwrap v [#{window}]#{offset}',
              ~s'({app="a"} | logfmt | unwrap v) [#{window}]#{offset}',
              ~s'{app="a"} [#{window}]#{offset} | logfmt | unwrap v',
              ~s'({app="a"} [#{window}]#{offset} | logfmt | unwrap v)',
              ~s'(({app="a"} | logfmt | unwrap v) [#{window}]#{offset})',
              ~s'(({app="a"} [#{window}]#{offset} | logfmt | unwrap v))'
            ] do
          expression = "#{op}_over_time(#{body})"
          assert_metric(ctx, expression, time, %{%{"app" => "a"} => expected})
        end
      end
    end

    @tag :range_placement_batch
    test "range placement preserves post-unwrap filters and rejects split pipelines before storage", ctx do
      push(ctx, "old", ctx.now + 10 * @second, %{"app" => "a"}, %{"v" => "2"})
      push(ctx, "keep", ctx.now + 20 * @second, %{"app" => "a"}, %{"v" => "7"})

      for body <- [
            ~s'({app="a"})[1m] | unwrap v | v>3',
            ~s'({app="a"}[1m] | unwrap v | v>3)',
            ~s'({app="a"} | unwrap v | v>3)[1m]',
            ~s'{app="a"}[1m] |= "keep" | unwrap v | v>3'
          ] do
        assert_metric(ctx, "sum_over_time(#{body})", 60, %{%{"app" => "a"} => [{60, "7"}]})
      end

      assert_metric(ctx, ~s'quantile_over_time(0.75, (({app="a"}[1m] | unwrap v))) by (app)', 60, %{
        %{"app" => "a"} => [{60, "5.75"}]
      })

      assert_metric(ctx, ~s'approx_count_distinct(v, ({app="a"}[1m])) by (app)', 60, %{
        %{"app" => "a"} => [{60, "2"}]
      })

      deepest = String.duplicate("(", 63) <> ~s'{app="a"}[1m] | unwrap v | v>3' <> String.duplicate(")", 63)
      assert_metric(ctx, "sum_over_time(#{deepest})", 60, %{%{"app" => "a"} => [{60, "7"}]})

      before = Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests})

      for body <- [
            ~s'{app="a"} | logfmt [1m] | unwrap v',
            ~s'({app="a"} | logfmt)[1m] | unwrap v',
            ~s'({app="a"})[1m] | logfmt | unwrap v',
            ~s'{app="a"}[1m] | unwrap v | logfmt',
            ~s'({app="a"}[1m]) offset 1m',
            String.duplicate("(", 65) <> ~s'{app="a"}[1m] | unwrap v' <> String.duplicate(")", 65)
          ],
          method <- [&request/4, &request_form/4] do
        params = [query: "sum_over_time(#{body})", time: to_string(ctx.now + 60 * @second)]
        assert method.(ctx, "/query", params, 400)["status"] == "error"
      end

      assert Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == before
    end

    for parser <- [:logfmt, :json, :metadata] do
      @parser parser
      @tag :unwrap_upstream
      @tag :error_filter_batch
      test "#{parser} grouped averages omit streams with no extracted values", ctx do
        for repeat <- 0..1,
            {pod, time, line, value} <- [
              {"1", 10, "msg", "2"},
              {"1", 20, "msg", "4"},
              {"1", 25, "noise", nil},
              {"2", 15, "msg", "6"},
              {"2", 35, "msg", "12"},
              {"3", 15, "junk", nil},
              {"3", 35, "moar", nil}
            ] do
          {body, labels, metadata} =
            case @parser do
              :logfmt ->
                {if(value, do: "v=#{value}", else: line), %{"app" => "a", "pod" => pod}, %{}}

              :json ->
                fields = if value, do: %{"v" => String.to_integer(value)}, else: %{line => 1}
                {Pulse.JSON.encode!(fields), %{"app" => "a", "pod" => pod}, %{}}

              :metadata ->
                fields = if value, do: %{"pod" => pod, "v" => value}, else: %{"pod" => pod}
                {line, %{"app" => "a"}, fields}
            end

          push(ctx, body, ctx.now + (time + repeat * 60) * @second, labels, metadata)
        end

        assert_parquet(ctx, 14)
        pipeline = if @parser == :metadata, do: "", else: "| #{@parser} "
        base = ~s'avg_over_time({app="a"} #{pipeline}| unwrap v [1m])'
        dropped = ~s'avg_over_time({app="a"} #{pipeline}| drop pod | unwrap v [1m])'

        for {expression, expected} <- [
              {base <> " by (pod)", [{%{"pod" => "1"}, "3"}, {%{"pod" => "2"}, "9"}]},
              {base <> " by (app)", [{%{"app" => "a"}, "6"}]},
              {"sum(#{base} by (pod))", [{%{}, "12"}]},
              {base <> " by (pod, app)", [{%{"app" => "a", "pod" => "1"}, "3"}, {%{"app" => "a", "pod" => "2"}, "9"}]},
              {base <> " by ()", [{%{}, "6"}]},
              {base <> " without (pod)", [{%{"app" => "a"}, "6"}]},
              {dropped, [{%{"app" => "a"}, "6"}]},
              {dropped <> " by (pod)", [{%{}, "6"}]},
              {base <> " by (pod) > 5", [{%{"pod" => "2"}, "9"}]},
              {~s'avg_over_time({app="a"} #{pipeline}| unwrap v | pod="1" [1m]) by (app)', [{%{"app" => "a"}, "3"}]},
              {~s'avg_over_time({app="a"} #{pipeline}| unwrap v | pod!="1" [1m]) by (pod)', [{%{"pod" => "2"}, "9"}]},
              {~s'avg_over_time({app="a"} #{pipeline}| unwrap v | v > 3 [1m]) by (pod)',
               [{%{"pod" => "1"}, "4"}, {%{"pod" => "2"}, "9"}]}
            ] do
          assert_metric(ctx, expression, 60, Map.new(expected, fn {labels, value} -> {labels, [{60, value}]} end))

          assert_metric(
            ctx,
            expression,
            {60, 180, 60},
            Map.new(expected, fn {labels, value} -> {labels, [{60, value}, {120, value}]} end)
          )
        end
      end
    end
  end

  describe "range_aggregations.logqltest post-unwrap filters" do
    setup ctx do
      %{now: div(ctx.now, @second) * @second - 180 * @second}
    end

    @tag :error_filter_batch
    test "failed conversions remain zero-valued observations only when explicitly requested", ctx do
      push(ctx, "v=oops", ctx.now + 40 * @second, %{"app" => "a"})
      push(ctx, "v=5", ctx.now + 50 * @second, %{"app" => "a"})
      push(ctx, "v=1", ctx.now + 40 * @second, %{"app" => "noise"})
      assert_parquet(ctx, 3)
      base = ~s'{app="a"} | logfmt | unwrap v'

      error_labels = %{
        "app" => "a",
        "__error__" => "SampleExtractionErr",
        "__error_details__" => ~s(strconv.ParseFloat: parsing "oops": invalid syntax)
      }

      for filter <- [~s(__error__!=""), ~s(__error__="")] do
        assert_metric(ctx, ~s'absent_over_time(#{base} | #{filter} [1m])', 60, %{})
      end

      assert_metric(ctx, ~s'min_over_time(#{base} | __error__=~".*" [1m])', 60, %{
        %{"app" => "a"} => [{60, "5"}],
        error_labels => [{60, "0"}]
      })

      for {op, filter, expected} <- [
            {"min", ~s(__error__=~".*"), "0"},
            {"max", ~s(__error__=~".*"), "5"},
            {"min", ~s(__error__=""), "5"},
            {"max", ~s(__error__=""), "5"}
          ] do
        assert_metric(ctx, ~s'#{op}(#{op}_over_time(#{base} | #{filter} [1m]))', 60, %{%{} => [{60, expected}]})
      end

      request(ctx, "/query", [query: ~s'absent_over_time(#{base} [1m])', time: to_string(ctx.now + 60 * @second)], 400)
    end

    @tag :error_filter_batch
    test "rate filters conversion failures from structured metadata", ctx do
      push(ctx, "msg", ctx.now + 20 * @second, %{"app" => "err"}, %{"v" => "oops"})
      push(ctx, "msg", ctx.now + 40 * @second, %{"app" => "err"}, %{"v" => "6"})
      assert_parquet(ctx, 2)

      assert_metric(ctx, ~s'rate({app="err"} | unwrap v | __error__="" [1m])', 60, %{%{"app" => "err"} => [{60, "0.1"}]})

      labels = %{
        "app" => "err",
        "__error__" => "SampleExtractionErr",
        "__error_details__" => ~s(strconv.ParseFloat: parsing "oops": invalid syntax)
      }

      assert_metric(ctx, ~s'rate({app="err"} | unwrap v | __error__!="" [1m])', 60, %{labels => [{60, "0"}]})

      request(
        ctx,
        "/query",
        [query: ~s'rate({app="err"} | unwrap v [1m])', time: to_string(ctx.now + 60 * @second)],
        400
      )
    end

    @tag :error_filter_batch
    test "invalid post-unwrap stages and converting reserved-error filters reject before storage", ctx do
      for stage <- ["json", "unwrap other", ~s(line_format "x"), "__error__ > 0", "__error_details__ > 1s"] do
        request(
          ctx,
          "/query",
          [query: ~s'sum_over_time({app="a"} | unwrap v | #{stage} [1m])', time: to_string(ctx.now)],
          400
        )
      end

      refute_parquet_read(ctx)
    end
  end

  describe "range_aggregations.logqltest rate_counter" do
    setup ctx do
      %{now: div(ctx.now, @second) * @second - 600 * @second}
    end

    @tag :rate_counter_upstream
    test "non-overlapping and overlapping windows, offsets, single and absent observations", ctx do
      counter_fixture(
        ctx,
        [
          {90, 100},
          {120, 130},
          {150, 160},
          {180, 250},
          {210, 280},
          {240, 340},
          {330, 400},
          {360, 430},
          {390, 460},
          {420, 550},
          {450, 580},
          {480, 640}
        ],
        15,
        18
      )

      query = ~s'rate_counter({app="a"} | logfmt | unwrap c [1m])'
      assert_counter(ctx, query, 480, [{480, "2"}])

      assert_counter(ctx, query, {60, 540, 60}, [
        {120, "1"},
        {180, "3"},
        {240, "2"},
        {360, "1"},
        {420, "3"},
        {480, "2"}
      ])

      assert_counter(ctx, query, {60, 180, 60}, [{120, "1"}, {180, "3"}])
      assert_counter(ctx, query, {240, 360, 60}, [{240, "2"}, {360, "1"}])
      assert_counter(ctx, query, {420, 540, 60}, [{420, "3"}, {480, "2"}])

      overlapping = ~s'rate_counter({app="a"} | logfmt | unwrap c [3m])'
      assert_counter(ctx, overlapping, 360, [{360, "1"}])
      assert_counter(ctx, overlapping, {240, 360, 60}, [{240, "1.6"}, {300, "1.5"}, {360, "1"}])

      offset = ~s'rate_counter({app="a"} | logfmt | unwrap c [1m] offset 60s)'
      assert_counter(ctx, offset, 180, [{180, "1"}])

      assert_counter(ctx, offset, {60, 540, 60}, [
        {180, "1"},
        {240, "3"},
        {300, "2"},
        {420, "1"},
        {480, "3"},
        {540, "2"}
      ])

      single = ~s'rate_counter({app="a"} | logfmt | unwrap c [10s])'
      assert_counter(ctx, single, 90, [{90, "0"}])
      assert_counter(ctx, single, 300, [])
    end

    @tag :rate_counter_upstream
    test "decreases count as counter resets", ctx do
      counter_fixture(ctx, [{30, 30}, {60, 60}, {90, 90}, {120, 30}, {150, 60}], 15, 6)
      assert_counter(ctx, ~s'rate_counter({app="a"} | logfmt | unwrap c [2m])', 150, [{150, "1"}])
      assert_counter(ctx, ~s'rate_counter({app="a"} | logfmt | unwrap c [1m])', 120, [{120, "1"}])
    end

    @tag :rate_counter_upstream
    test "back-extrapolation stops at the counter zero point", ctx do
      counter_fixture(ctx, [{75, 30}, {105, 90}, {135, 150}], 60, 4)
      query = ~s'rate_counter({app="a"} | logfmt | unwrap c [1m])'
      assert_counter(ctx, query, 105, [{105, "1.5"}])
      assert_counter(ctx, query, 135, [{135, "2"}])
    end

    @tag :rate_counter_upstream
    test "distant edges cap at half an average sample interval", ctx do
      counter_fixture(ctx, [{150, 600}, {180, 660}], 15, 8)
      query = ~s'rate_counter({app="a"} | logfmt | unwrap c [90s])'
      assert_counter(ctx, query, 180, [{180, "1"}])
      assert_counter(ctx, query, {180, 210, 30}, [{180, "1"}, {210, "2"}])
      assert_counter(ctx, ~s'rate_counter({app="a"} | logfmt | unwrap c [150s])', 240, [{240, "0.8"}])
    end

    @tag :rate_counter_upstream
    test "the spacing cap applies before the zero-point cap", ctx do
      counter_fixture(ctx, [{180, 40}, {210, 100}], 150, 1)
      assert_counter(ctx, ~s'rate_counter({app="a"} | logfmt | unwrap c [90s])', 210, [{210, "1"}])
    end

    @tag :rate_counter_upstream
    test "structured metadata counters", ctx do
      push(ctx, "msg", ctx.now + 180 * @second, %{"app" => "a"}, %{"c" => "40"})
      push(ctx, "msg", ctx.now + 210 * @second, %{"app" => "a"}, %{"c" => "100"})
      push(ctx, "msg", ctx.now + 150 * @second, %{"app" => "a"})
      assert_parquet(ctx, 3)
      query = ~s'rate_counter({app="a"} | unwrap c [90s])'
      assert_counter(ctx, query, 210, [{210, "1"}])
      assert_counter(ctx, query, {180, 210, 30}, [{180, "0"}, {210, "1"}])
    end

    @tag :rate_counter_upstream
    test "unwrap is required and range grouping is forbidden", ctx do
      for query <- [
            ~s'rate_counter({app="a"}[1m])',
            ~s'rate_counter({app="a"} | logfmt | unwrap c [1m]) by (app)'
          ] do
        assert request(ctx, "/query", [query: query, time: to_string(ctx.now + 480 * @second)], 400)["status"] ==
                 "error"
      end

      assert Agent.get(ctx.store, & &1.requests) == []
    end

    # Pulse controls, not additional upstream fixtures.
    @tag :rate_counter_control
    test "missing counters skip but malformed counters fail only windows that read them", ctx do
      for {time, line} <- [{5, "c=10"}, {8, "noise"}, {9, ~s(c="")}, {15, "c=bad"}, {25, "c=30"}] do
        push(ctx, line, ctx.now + time * @second, %{"app" => "a"})
      end

      for time <- [15, 30] do
        query = ~s'rate_counter({app="a"} | logfmt | unwrap c [1m])'
        params = [query: query, time: to_string(ctx.now + time * @second)]
        assert request(ctx, "/query", params, 400)["message"] =~ "sample_extraction_error"
        assert request_form(ctx, "/query", params, 400)["message"] =~ "sample_extraction_error"
      end

      assert_counter(ctx, ~s'rate_counter({app="a"} | logfmt | unwrap c [10s])', {10, 30, 20}, [{10, "0"}, {30, "0"}])

      push(ctx, "noise", ctx.now + 31 * @second, %{"app" => "a"}, %{"__error__" => "bad"})
      assert_counter(ctx, ~s'rate_counter({app="a"} | unwrap c [1ms])', 31, [])
    end

    @tag :rate_counter_control
    test "counter observations and missing fields remain subject to fail-whole query budgets", ctx do
      counter_fixture(ctx, [{180, 40}, {210, 100}], 150, 1)
      query = ~s'rate_counter({app="a"} | logfmt | unwrap c [90s])'
      params = [query: query, time: to_string(ctx.now + 210 * @second)]
      objects = Agent.get(ctx.store, & &1.objects)
      Runtime.put_env(:pulse, Pulse.QueryRunner, max_scan_rows: 2)
      assert request(ctx, "/query", params, 422)["error"] == "query_limit"
      Runtime.put_env(:pulse, Pulse.QueryRunner, [])

      for limit <- [[max_log_samples: 1], [max_work: 2], [max_result_points: 0]] do
        Runtime.put_env(:pulse, Evaluator, limit)
        response = request_form(ctx, "/query", params, 422)
        assert response["error"] == "query_limit"
        refute Map.has_key?(response, "data")
      end

      Runtime.put_env(:pulse, Evaluator, max_log_samples: 2, max_result_points: 1)
      assert_counter(ctx, query, 210, [{210, "1"}])
      assert Agent.get(ctx.store, & &1.objects) == objects
    end
  end

  describe "TestPerRequestLimits" do
    test "limited range and label requests reject, then the same tenant reads without the policy", ctx do
      limited = query_limits(ctx, ~s({"maxQueryLength": "1m"}))
      push(limited, "lineA", ctx.now - 45 * @minute, %{"job" => "fake"})
      assert_parquet(ctx, 1)

      response = request(limited, "/query_range", [{"query", ~s({job="fake"})} | range(ctx)], 400)
      assert response["message"] =~ "the query time range exceeds the limit (query length"

      response = request(limited, "/labels", [], 400)
      assert response["message"] =~ "the query time range exceeds the limit (query length"
      refute_parquet_read(ctx)

      # Recreate the client without InjectHeadersOption, as upstream does.
      assert lines(query(ctx, ~s({job="fake"}))) == ["lineA"]
      assert_parquet_read(ctx)
    end
  end

  # Pulse-authored regression control, not another upstream case. The upstream
  # tail case reads only pre-existing entries; this discriminates a history-only
  # implementation, ignored start bounds, and unauthenticated/unfiltered sockets.
  describe "tail HTTP/S3 controls" do
    test "authenticated bounded history hands off to durable matching live writes", ctx do
      push(ctx, "level=error msg=history", ctx.now - @second, %{"job" => "fake"})
      expression = ~s({job="fake"} | logfmt | level="error" | line_format "{{.msg}}")
      params = [{"start", to_string(ctx.now)}, {"limit", "100"}]

      for unauthorized <- [%{ctx | token: "wrong-token"}, %{ctx | tenant: ctx.tenant <> "-other"}] do
        assert {:error, {401, _}} = tail(unauthorized, expression, params)
      end

      refute_parquet_read(ctx)
      {:ok, socket} = tail(ctx, expression, params)
      [tailer] = Tail.tailers(ctx.tenant)
      monitor = Process.monitor(tailer)

      try do
        assert WebSocketClient.next_json(socket, 10_000)["streams"] == []
        push(ctx, "level=info msg=skip", ctx.now + @second, %{"job" => "fake"})
        push(ctx, "level=error msg=other", ctx.now + 2 * @second, %{"job" => "other"})
        push(ctx, "level=error msg=live", ctx.now + 3 * @second, %{"job" => "fake"})
        assert_parquet(ctx, 4)

        assert tail_values(socket, 1) == [[to_string(ctx.now + 3 * @second), "live"]]
        assert lines(query(%{ctx | now: ctx.now + 4 * @second}, expression)) == ["history", "live"]
        assert_parquet_read(ctx)
      after
        WebSocketClient.close(socket)
        assert_receive {:DOWN, ^monitor, :process, ^tailer, _}, 5_000
      end
    end
  end

  describe "TestLabelAccessTestCases/disabled" do
    setup ctx do
      for {line, offset, labels} <- [
            {"line1", 0, %{"env" => "dev", "classification" => "confidential"}},
            {"line2", 1, %{}},
            {"line3", 2, %{"classification" => "secret", "env" => "dev"}},
            {"line4", 3, %{"classification" => "secret", "env" => "prod"}}
          ] do
        push(ctx, line, ctx.now + offset * @second, Map.put(labels, "job", "varlog"))
      end

      assert_parquet(ctx, 4)

      # The upstream disabled case sends this header, but does not enable LBAC.
      policy = ctx.tenant <> ":" <> URI.encode_www_form(~s({env="dev"}))
      %{now: ctx.now + 4 * @second, extra_headers: [{"x-prom-label-policy", policy}]}
    end

    test "logs-query", ctx do
      assert lines(query(ctx, ~s({job="varlog"} |= "line"))) == ["line1", "line2", "line3", "line4"]
      assert_parquet_read(ctx)
    end

    test "label-values-query", ctx do
      labels = request(ctx, "/labels")["data"]
      actual = Map.new(labels, fn label -> {label, request(ctx, "/label/#{label}/values")["data"]} end)

      assert actual == %{
               "classification" => ["confidential", "secret"],
               "env" => ["dev", "prod"],
               "job" => ["varlog"]
             }

      assert_parquet_read(ctx)
    end

    test "series-query", ctx do
      actual = request(ctx, "/series", [{"match[]", "{}"} | range(ctx)])["data"]
      assert Enum.sort(actual) == Enum.sort(access_streams())
      assert_parquet_read(ctx)
    end

    test "metrics-query", ctx do
      response = instant(ctx, ~s'count_over_time({job="varlog"} |= "line" [2h])')
      assert response["data"]["resultType"] == "vector"
      assert Enum.sort(Enum.map(response["data"]["result"], & &1["metric"])) == Enum.sort(access_streams())
      assert_parquet_read(ctx)
    end

    test "metrics-range-query", ctx do
      # Retain the seven-day client window and upstream maximum of four, but
      # request minute resolution: a ~40-minute default grid can miss all four
      # writes in the last four seconds. See the fixture README.
      response =
        request(ctx, "/query_range", [
          {"query", ~s'count_over_time({job="varlog"} |= "line" [2h])'},
          {"step", "60"}
          | range(ctx)
        ])

      assert response["data"]["resultType"] == "matrix"

      per_step =
        for series <- response["data"]["result"], [timestamp, count] <- series["values"], reduce: %{} do
          totals ->
            {value, ""} = Float.parse(count)
            Map.update(totals, timestamp, value, &(&1 + value))
        end

      assert Enum.max(Map.values(per_step)) == 4.0
      assert_parquet_read(ctx)
    end
  end

  describe "TestCategorizedLabels" do
    setup ctx do
      push(ctx, "lineA", ctx.now - @second, %{"job" => "fake"})
      push(ctx, "lineB", ctx.now - 2 * @second, %{"job" => "fake"}, %{"traceID" => "123", "user" => "a"})
      push(ctx, "lineC msg=foo", ctx.now - 3 * @second, %{"job" => "fake"}, %{"traceID" => "456", "user" => "b"})

      push(ctx, "lineD msg=foo text=bar", ctx.now - 4 * @second, %{"job" => "fake"}, %{
        "traceID" => "789",
        "user" => "c"
      })

      assert_parquet(ctx, 4)
      :ok
    end

    test "no header - no parser", ctx do
      response = query(ctx, ~s({job="fake"}))

      assert_streams(response, [
        {%{"job" => "fake"}, ["lineA"]},
        {%{"job" => "fake", "traceID" => "123", "user" => "a"}, ["lineB"]},
        {%{"job" => "fake", "traceID" => "456", "user" => "b"}, ["lineC msg=foo"]},
        {%{"job" => "fake", "traceID" => "789", "user" => "c"}, ["lineD msg=foo text=bar"]}
      ])

      assert_parquet_read(ctx)
    end

    test "no header - with parser", ctx do
      response = query(ctx, ~s({job="fake"} | logfmt))

      assert_streams(response, [
        {%{"job" => "fake"}, ["lineA"]},
        {%{"job" => "fake", "traceID" => "123", "user" => "a"}, ["lineB"]},
        {%{"job" => "fake", "traceID" => "456", "user" => "b", "msg" => "foo"}, ["lineC msg=foo"]},
        {%{"job" => "fake", "traceID" => "789", "user" => "c", "msg" => "foo", "text" => "bar"},
         ["lineD msg=foo text=bar"]}
      ])

      assert_parquet_read(ctx)
    end

    test "with header - no parser", ctx do
      ctx = Map.put(ctx, :extra_headers, [{"x-loki-response-encoding-flags", "categorize-labels"}])
      response = query(ctx, ~s({job="fake"}))

      assert response["data"]["encodingFlags"] == ["categorize-labels"]
      assert response["data"]["resultType"] == "streams"

      assert response["data"]["result"] == [
               %{
                 "stream" => %{"job" => "fake"},
                 "values" => [
                   [to_string(ctx.now - @second), "lineA", %{}],
                   [
                     to_string(ctx.now - 2 * @second),
                     "lineB",
                     %{"structuredMetadata" => %{"traceID" => "123", "user" => "a"}}
                   ],
                   [
                     to_string(ctx.now - 3 * @second),
                     "lineC msg=foo",
                     %{"structuredMetadata" => %{"traceID" => "456", "user" => "b"}}
                   ],
                   [
                     to_string(ctx.now - 4 * @second),
                     "lineD msg=foo text=bar",
                     %{"structuredMetadata" => %{"traceID" => "789", "user" => "c"}}
                   ]
                 ]
               }
             ]

      assert_parquet_read(ctx)
    end

    test "with header - with parser", ctx do
      ctx = Map.put(ctx, :extra_headers, [{"x-loki-response-encoding-flags", "categorize-labels"}])
      response = query(ctx, ~s({job="fake"} | logfmt))

      assert response["data"]["encodingFlags"] == ["categorize-labels"]
      assert response["data"]["resultType"] == "streams"

      assert response["data"]["result"] == [
               %{
                 "stream" => %{"job" => "fake"},
                 "values" => [
                   [to_string(ctx.now - @second), "lineA", %{}],
                   [
                     to_string(ctx.now - 2 * @second),
                     "lineB",
                     %{"structuredMetadata" => %{"traceID" => "123", "user" => "a"}}
                   ],
                   [
                     to_string(ctx.now - 3 * @second),
                     "lineC msg=foo",
                     %{
                       "structuredMetadata" => %{"traceID" => "456", "user" => "b"},
                       "parsed" => %{"msg" => "foo"}
                     }
                   ],
                   [
                     to_string(ctx.now - 4 * @second),
                     "lineD msg=foo text=bar",
                     %{
                       "structuredMetadata" => %{"traceID" => "789", "user" => "c"},
                       "parsed" => %{"msg" => "foo", "text" => "bar"}
                     }
                   ]
                 ]
               }
             ]

      assert_parquet_read(ctx)
    end
  end

  # Complete pinned TestEngine_checkIntervalLimit table. Downstream wrappers
  # are Loki execution topology, not separate public queries in Pulse.
  @tag :query_policy_batch
  test "Loki range-interval admission table survives HTTP query policies", ctx do
    cases = [
      {~s'rate({app="foo"} [1m])', false},
      {~s'rate({app="foo"} [10m])', false},
      {~s'max(rate({app="foo"} [5m])) - max(rate({app="bar"} [10m]))', false},
      {~s'rate({app="foo"} [5m]) - rate({app="bar"} [15m])', true},
      {~s'rate({app="foo"} [1h])', true},
      {~s'sum(rate({app="foo"} [1h]))', true},
      {~s'sum_over_time({app="foo"} |= "foo" | json | unwrap bar [1h])', true}
    ]

    limited = query_limits(ctx, ~s({"maxQueryInterval":"10m"}))

    for {query, rejects?} <- cases, path <- ["/query", "/query_range"] do
      params = [{"query", query}, {"time", to_string(ctx.now)} | range(ctx)]
      before = Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests})
      status = if rejects?, do: 400, else: 200
      response = request(limited, path, params, status)
      assert request_form(limited, path, params, status) == response

      if rejects? do
        assert response["error"] == "query_limit"
        assert response["message"] =~ "[interval] value exceeds limit"
        assert Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == before
      else
        assert response["status"] == "success"
      end
    end
  end

  # Complete TestEngine_MaxRangeInterval admission table and request geometry.
  # The upstream localQuerier's 100,000 synthetic logs are not a value oracle
  # here: these assertions concern only the original rejection decisions.
  @tag :query_policy_batch
  test "Loki nested range-interval engine table survives HTTP", ctx do
    cases = [
      {~s'topk(1,rate(({app=~"foo|bar"})[2d]))', true},
      {~s'topk(1,rate(({app=~"foo|bar"})[1d]))', false},
      {~s'topk(1,rate({app=~"foo|bar"}[12h]) / (rate({app="baz"}[23h]) + rate({app="fiz"}[25h])))', true}
    ]

    limited = query_limits(ctx, ~s({"maxQueryInterval":"1d"}))

    for {query, rejects?} <- cases do
      params = [
        {"query", query},
        {"start", "0"},
        {"end", "100000"},
        {"step", "60"},
        {"direction", "forward"},
        {"limit", "1000"}
      ]

      before = Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests})
      status = if rejects?, do: 400, else: 200
      response = request(limited, "/query_range", params, status)
      assert request_form(limited, "/query_range", params, status) == response

      if rejects? do
        assert response["message"] =~ "[interval] value exceeds limit"
        assert Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == before
      else
        assert response["status"] == "success"
      end
    end
  end

  @tag :error_classification_batch
  test "query-length errors preserve the original 800h versus 721h quantities", ctx do
    hour = 60 * @minute
    limited = query_limits(ctx, ~s({"maxQueryLength":"721h"}))
    push(ctx, "retained", ctx.now - @second, %{"job" => "fake"})

    for path <- ["/query", "/query_range"], method <- [&request/4, &request_form/4] do
      params = [
        {"query", ~s({job="fake"})},
        {"start", to_string(ctx.now - 800 * hour)},
        {"end", to_string(ctx.now)}
      ]

      before = Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests})
      response = method.(limited, path, params, @wrapped_limit_rows["max_query_length"]["status"])
      assert response["error"] == "query_limit"
      assert response["message"] =~ "query length: #{800 * hour}ns, limit: #{721 * hour}ns"
      refute Map.has_key?(response, "data")
      assert Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == before

      boundary = List.keystore(params, "start", 0, {"start", to_string(ctx.now - 721 * hour)})
      assert lines(method.(limited, path, boundary, 200)) == ["retained"]

      over = List.keystore(params, "start", 0, {"start", to_string(ctx.now - 721 * hour - 1)})
      before = Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests})
      assert method.(limited, path, over, 400)["error"] == "query_limit"
      assert Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == before
    end

    assert_parquet_read(ctx)
  end

  # TestTripperware_EntriesLimit's exact query, limit and six-hour window.
  @tag :query_policy_batch
  @tag :error_classification_batch
  test "Loki entries-limit middleware rejects before storage", ctx do
    limited = query_limits(ctx, ~s({"maxEntriesLimitPerQuery":5000}))
    push(ctx, "retained", ctx.now - @second, %{"app" => "foo"})

    params = [
      {"query", ~s({app="foo"})},
      {"start", to_string(ctx.now - 360 * @minute)},
      {"end", to_string(ctx.now)},
      {"direction", "forward"},
      {"limit", "10000"}
    ]

    for path <- ["/query", "/query_range"], method <- [&request/4, &request_form/4] do
      before = Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests})
      response = method.(limited, path, params, @wrapped_limit_rows["max_entries"]["status"])
      assert response["error"] == "query_limit"
      assert response["message"] == @wrapped_limit_rows["max_entries"]["body"]

      assert Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == before

      boundary = List.keystore(params, "limit", 0, {"limit", "5000"})
      assert lines(method.(limited, path, boundary, 200)) == ["retained"]

      over = List.keystore(params, "limit", 0, {"limit", "5001"})
      before = Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests})
      assert method.(limited, path, over, 400)["error"] == "query_limit"
      assert Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == before
    end

    assert_parquet_read(ctx)
  end

  @tag :error_classification_batch
  test "provider messages matching Loki limit templates are not treated as client rejections", ctx do
    Runtime.put_env(:pulse, Storage, adapter: BlockingMetricStorage)

    for {_name, original} <- @wrapped_limit_rows do
      Runtime.put_env(:pulse, BlockingMetricStorage, {:error, original["body"]})

      for path <- ["/query_range", "/labels"], method <- [&request/4, &request_form/4] do
        params = [{"query", ~s({job="fake"})} | range(ctx)]

        assert method.(ctx, path, params, 503) == %{
                 "status" => "error",
                 "error" => "storage_unavailable",
                 "message" => "Storage is unavailable."
               }
      end
    end
  end

  # Complete TestTripperware_RequiredLabels admission table. Upstream supplies
  # prebuilt responses rather than a log fixture; only admission is its oracle.
  @tag :query_policy_batch
  @tag :selector_policy_batch
  test "Loki required-label middleware table checks each selector independently", ctx do
    missing = "stream selector is missing required matchers [app], labels present in the query were [pod]"

    cases = [
      {~s'avg(count_over_time({app=~"foo|bar"} |~".+bar" [1m]))', nil},
      {~s'count_over_time({app="foo"}[1m]) / count_over_time({app="bar"}[1m] offset 1m)', nil},
      {~s'count_over_time({app="foo"}[1m]) / count_over_time({pod="bar"}[1m] offset 1m)', missing},
      {~s'avg(count_over_time({pod=~"foo|bar"} |~".+bar" [1m]))', missing},
      {~s({app="foo", pod="bar"}), nil},
      {~s({pod="bar"} |= "foo" |~ ".+bar"), missing}
    ]

    limited = query_limits(ctx, ~s({"requiredLabels":["app"]}))

    for {query, error} <- cases do
      params = [
        {"query", query},
        {"start", to_string(ctx.now - 360 * @minute)},
        {"end", to_string(ctx.now)},
        {"direction", "forward"},
        {"limit", "1000"}
      ]

      before = Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests})
      status = if error, do: 400, else: 200
      response = request(limited, "/query_range", params, status)
      assert request_form(limited, "/query_range", params, status) == response

      if error do
        assert response["error"] == "query_limit"
        assert response["message"] == error
        assert Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == before
      else
        assert response["status"] == "success"
      end
    end
  end

  # Complete TestTripperware_RequiredNumberLabels table: disabled, below,
  # exact and above, independently for log and metric queries.
  @tag :query_policy_batch
  @tag :selector_policy_batch
  test "Loki minimum-matcher middleware table survives HTTP policies", ctx do
    cases = [
      {~s({foo="foo"}), 0, false},
      {~s({foo="foo"}), 2, true},
      {~s({foo="foo", bar="bar"}), 2, false},
      {~s({foo="foo", bar="bar", baz="baz"}), 2, false},
      {~s'count_over_time({foo="foo"} [1m])', 0, false},
      {~s'count_over_time({foo="foo"} [1m])', 2, true},
      {~s'count_over_time({foo="foo", bar="bar"} [1m])', 2, false},
      {~s'count_over_time({foo="foo", bar="bar", baz="baz"} [1m])', 2, false}
    ]

    for {query, minimum, rejects?} <- cases do
      limited = query_limits(ctx, Pulse.JSON.encode!(%{"minimumLabelsNumber" => minimum}))

      params = [
        {"query", query},
        {"start", to_string(ctx.now - 360 * @minute)},
        {"end", to_string(ctx.now)},
        {"direction", "forward"},
        {"limit", "1000"}
      ]

      before = Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests})
      status = if rejects?, do: 400, else: 200
      response = request(limited, "/query_range", params, status)
      assert request_form(limited, "/query_range", params, status) == response

      if rejects? do
        assert response["message"] ==
                 "stream selector has less label matchers than required: (present: [foo], number_present: 1, required_number_label_matchers: 2)"

        assert Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == before
      else
        assert response["status"] == "success"
      end
    end
  end

  # Pulse-specific controls, not additional upstream ports.
  @tag :query_policy_batch
  @tag :selector_policy_batch
  test "selector and entry policies apply to query and field APIs without counting pipeline labels", ctx do
    push(ctx, "foo=bar", ctx.now, %{"job" => "fake"})
    policy = ~s({"requiredLabels":["job","job"],"minimumLabelsNumber":2,"maxEntriesLimitPerQuery":1})
    limited = query_limits(ctx, policy)
    bounds = [{"start", to_string(ctx.now - @minute)}, {"end", to_string(ctx.now)}, {"time", to_string(ctx.now)}]

    for {path, extras} <- [
          {"/query", [{"limit", "1"}]},
          {"/query_range", [{"limit", "1"}]},
          {"/detected_fields", [{"line_limit", "1"}]},
          {"/detected_field/foo/values", [{"line_limit", "1"}]},
          {"/patterns", []}
        ] do
      bad = [{"query", ~s({job="fake"} | logfmt | foo="bar")} | extras ++ bounds]
      before = Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests})
      response = request(limited, path, bad, 400)
      assert response["message"] =~ "number_present: 1"
      assert request_form(limited, path, bad, 400) == response
      assert Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == before

      # Loki counts matchers, including repeated label names, not distinct keys.
      good = List.keyreplace(bad, "query", 0, {"query", ~s({job="fake",job!="other"})})
      assert request(limited, path, good) == request(ctx, path, good)
    end

    absent = query_limits(ctx, ~s({"requiredLabels":["private"],"minimumLabelsNumber":9}))
    params = [{"query", ~s({job="fake"})} | bounds]
    assert request(absent, "/query", params, 400)["message"] =~ "missing required matchers [private]"
    assert lines(request(ctx, "/query", params)) == ["foo=bar"]

    for path <- ["/detected_fields", "/detected_field/foo/values"] do
      before = Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests})

      assert request(limited, path, [{"query", ~s({job="fake",job!="other"})}, {"line_limit", "2"} | bounds], 400)[
               "message"
             ] =~ "(2 > 1)"

      assert Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == before
    end

    empty_policy = query_limits(ctx, ~s({"requiredLabels":[],"minimumLabelsNumber":0}))
    assert request(empty_policy, "/query", params) == request(ctx, "/query", params)
    scalar = [{"query", "vector(2)"} | bounds]
    assert request(absent, "/query", scalar) == request(ctx, "/query", scalar)
  end

  @tag :query_policy_batch
  test "interval and entry policies compose without truncation or leaking into other queries", ctx do
    push(ctx, "older", ctx.now - @second, %{"job" => "fake"})
    push(ctx, "newer", ctx.now, %{"job" => "fake"})
    limited = query_limits(ctx, ~s({"maxQueryLength":"1m","maxQueryInterval":"1m","maxEntriesLimitPerQuery":1}))

    for path <- ["/query", "/query_range"], direction <- ["forward", "backward"] do
      # This authored policy control needs both rows inside a one-minute
      # window. Translate the range window by 1ns rather than claiming that
      # its exclusive end includes the newest row; instant bounds stay intact.
      shift = if path == "/query_range", do: 1, else: 0

      params = [
        {"query", ~s({job="fake"})},
        {"time", to_string(ctx.now)},
        {"direction", direction},
        {"limit", "1"},
        {"start", to_string(ctx.now - @minute + shift)},
        {"end", to_string(ctx.now + shift)}
      ]

      response = request(limited, path, params)
      assert lines(response) == [if(direction == "forward", do: "older", else: "newer")]
      assert request_form(limited, path, params) == response
      before = Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests})
      over = List.keyreplace(params, "limit", 0, {"limit", "2"})
      assert request(limited, path, over, 400)["error"] == "query_limit"
      assert request(limited, path, List.keydelete(params, "limit", 0), 400)["error"] == "query_limit"
      assert Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == before
      assert length(lines(request(ctx, path, over))) == 2
    end

    for query <- [~s'count_over_time({job="fake"}[1m])', ~s'count_over_time({job="fake"}[1m] offset 1h)', "vector(2)"] do
      params = [{"query", query}, {"time", to_string(ctx.now)}, {"limit", "100000"}]
      assert request(limited, "/query", params) == request(ctx, "/query", params)
    end

    metric = [{"query", ~s'count_over_time({job="fake"}[60001ms])'}, {"time", to_string(ctx.now)}]
    assert request(limited, "/query", metric, 400)["message"] =~ "[interval] value exceeds limit"
    assert values(request(ctx, "/query", metric)) == %{%{"job" => "fake"} => "2"}

    parenthesized = [{"query", ~s'count_over_time(({job="fake"} |= "newer")[1m])'}, {"time", to_string(ctx.now)}]
    assert values(request(limited, "/query", parenthesized)) == %{%{"job" => "fake"} => "1"}

    for policy <- [
          ~s({"maxQueryInterval":"0","maxEntriesLimitPerQuery":0}),
          ~s({"maxQueryInterval":"1y","maxEntriesLimitPerQuery":9223372036854775807})
        ] do
      ordinary = [{"query", ~s({job="fake"})} | range(ctx)]
      assert request(query_limits(ctx, policy), "/query_range", ordinary) == request(ctx, "/query_range", ordinary)
    end
  end

  @tag :query_policy_batch
  test "new query-policy fields reject malformed and duplicate values before storage", ctx do
    for policy <- [
          ~s({"maxQueryInterval":null}),
          ~s({"maxQueryInterval":"1.5m"}),
          ~s({"maxQueryInterval":"10m","maxQueryInterval":"0"}),
          ~s({"maxQueryTime":null}),
          ~s({"maxQueryTime":"1.5s"}),
          ~S({"maxQueryTime":"1s","maxQuery\u0054ime":"0"}),
          ~s({"maxEntriesLimitPerQuery":null}),
          ~s({"maxEntriesLimitPerQuery":"1"}),
          ~s({"maxEntriesLimitPerQuery":1.0}),
          ~s({"maxEntriesLimitPerQuery":-1}),
          ~s({"maxEntriesLimitPerQuery":9223372036854775808}),
          ~S({"maxEntriesLimitPerQuery":1,"maxEntriesLimitPer\u0051uery":0}),
          ~s({"requiredLabels":null}),
          ~s({"requiredLabels":"job"}),
          ~s({"requiredLabels":[1]}),
          ~s({"requiredLabels":["job"],"requiredLabels":[]}),
          ~s({"minimumLabelsNumber":null}),
          ~s({"minimumLabelsNumber":-1}),
          ~s({"minimumLabelsNumber":1.0}),
          ~s({"minimumLabelsNumber":9223372036854775808})
        ] do
      limited = query_limits(ctx, policy)
      params = [{"query", ~s({job="fake"})} | range(ctx)]
      assert request(limited, "/query_range", params, 400)["error"] == "invalid_parameter"
      assert request_form(limited, "/query_range", params, 400)["error"] == "invalid_parameter"
    end

    assert Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == {[], 0, []}
  end

  @tag :query_deadline_batch
  test "request deadlines bound every finite read and release query admission", ctx do
    push(ctx, "foo=bar", ctx.now, %{"job" => "fake"})
    Runtime.put_env(:pulse, Pulse.QueryRunner, timeout_ms: 3000)
    Runtime.put_env(:pulse, Storage, adapter: BlockingMetricStorage)
    Runtime.put_env(:pulse, BlockingMetricStorage, self())
    limited = query_limits(ctx, ~s({"maxQueryTime":"200ms"}))

    for {path, extra} <- finite_reads(), method <- [&request/4, &request_form/4] do
      params =
        extra ++
          [{"time", to_string(ctx.now)}, {"start", to_string(ctx.now - @minute)}, {"end", to_string(ctx.now)}]

      started = System.monotonic_time(:millisecond)
      assert method.(limited, path, params, 504)["error"] == "query_timeout"
      assert System.monotonic_time(:millisecond) - started < 2000
      assert_receive {:blocked_metric_query, worker, tenant}, 1000
      assert tenant == ctx.tenant
      ref = Process.monitor(worker)
      assert_receive {:DOWN, ^ref, :process, ^worker, _reason}, 1000
    end

    Runtime.put_env(:pulse, Storage, adapter: S3)
    params = [{"query", ~s({job="fake"})} | range(ctx)]
    assert lines(request(ctx, "/query_range", params)) == ["foo=bar"]

    assert request(query_limits(ctx, ~s({"maxQueryTime":"0"})), "/query_range", params) ==
             request(ctx, "/query_range", params)

    assert_parquet_read(ctx)
  end

  @tag :query_deadline_batch
  test "a timed out native S3 read does not poison subsequent requests", ctx do
    push(ctx, "foo=bar", ctx.now, %{"job" => "fake"})
    owner = self()
    Agent.update(ctx.store, &%{&1 | barriers: %{{"GET", :segment} => owner}})
    limited = query_limits(ctx, ~s({"maxQueryTime":"200ms"}))
    params = [{"query", ~s({job="fake"})} | range(ctx)]

    assert request(limited, "/query_range", params, 504)["error"] == "query_timeout"
    assert_receive {:storage_barrier, provider, "GET", key}, 1000
    assert String.ends_with?(key, ".parquet")
    Agent.update(ctx.store, &%{&1 | barriers: %{}})
    send(provider, {:release_storage, key})

    assert lines(request(ctx, "/query_range", params)) == ["foo=bar"]
    assert lines(request(query_limits(ctx, ~s({"maxQueryTime":"1m"})), "/query_range", params)) == ["foo=bar"]
    assert_parquet_read(ctx)
  end

  @tag :query_deadline_batch
  test "zero and higher client timeouts never disable or raise the server deadline", ctx do
    Runtime.put_env(:pulse, Pulse.QueryRunner, timeout_ms: 200)
    Runtime.put_env(:pulse, Storage, adapter: BlockingMetricStorage)
    Runtime.put_env(:pulse, BlockingMetricStorage, self())
    params = [{"query", ~s({job="fake"})} | range(ctx)]

    # Loki TestLimiter_Defaults / RejectHighLimits / AcceptLowerLimits:
    # preserve the minimum-positive rule, scaling seconds to milliseconds.
    for policy <- [nil, "{}", ~s({"maxQueryTime":"0s"}), ~s({"maxQueryTime":"1s"})] do
      caller = if policy, do: query_limits(ctx, policy), else: ctx
      started = System.monotonic_time(:millisecond)
      assert request(caller, "/query_range", params, 504)["error"] == "query_timeout"
      assert System.monotonic_time(:millisecond) - started < 800
      assert_receive {:blocked_metric_query, worker, _tenant}, 1000
      ref = Process.monitor(worker)
      assert_receive {:DOWN, ^ref, :process, ^worker, _reason}, 1000
    end
  end

  describe "per-request query length controls" do
    setup ctx do
      push(ctx, "foo=bar", ctx.now, %{"job" => "fake"})
      :ok
    end

    test "exact minute passes and one extra nanosecond rejects every finite read before storage", ctx do
      limited = query_limits(ctx, ~s({"maxQueryLength":"1m"}))

      for {path, extras} <- finite_reads() do
        bounds = [{"start", to_string(ctx.now - @minute)}, {"end", to_string(ctx.now)}]
        params = extras ++ bounds ++ [{"time", to_string(ctx.now)}]
        too_long = List.keyreplace(params, "start", 0, {"start", to_string(ctx.now - @minute - 1)})
        before = Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests})

        for response <- [request(limited, path, too_long, 400), request_form(limited, path, too_long, 400)] do
          assert response["error"] == "query_limit"
          assert response["message"] =~ "query length: 60000000001ns, limit: 60000000000ns"
          refute Map.has_key?(response, "data")
        end

        assert Agent.get(ctx.store, &{&1.reads, &1.lists, &1.requests}) == before
        ordinary = request(ctx, path, params)
        assert request(limited, path, params) == ordinary
        assert request_form(limited, path, params) == ordinary
      end

      assert_parquet_read(ctx)
    end

    test "default windows cannot evade the ceiling", ctx do
      limited = query_limits(ctx, ~s({"maxQueryLength":"1m"}))

      for {path, extras} <- finite_reads(), path != "/query" do
        assert request(limited, path, extras, 400)["error"] == "query_limit"
        assert request_form(limited, path, extras, 400)["error"] == "query_limit"
      end

      refute_parquet_read(ctx)
    end

    test "malformed, negative, overflowing, duplicate and unsupported policies fail closed", ctx do
      invalid = [
        "",
        "{broken}",
        "[]",
        "null",
        ~s({"maxQueryLength":null}),
        ~s({"maxQueryLength":60}),
        ~s({"maxQueryLength":"-1m"}),
        ~s({"maxQueryLength":"+1m"}),
        ~s({"maxQueryLength":"1.5m"}),
        ~s({"maxQueryLength":"1ns"}),
        ~s({"maxQueryLength":"1us"}),
        ~s({"maxQueryLength":"60"}),
        ~s({"maxQueryLength":"1s1m"}),
        ~s({"maxQueryLength":"1m1m"}),
        ~s({"maxQueryLength":"9223372036855ms"}),
        ~s({"maxQueryLength":"292y24w3d23h47m16s855ms"}),
        ~s({"maxQueryLength":"#{String.duplicate("1", 129)}s"}),
        ~s({"maxQueryLength":"1m","maxQueryLength":"0"}),
        ~S({"maxQueryLength":"1m","maxQuery\u004cength":"0"}),
        ~s({"MaxQueryLength":"1m"}),
        ~s({"maxQueryLength":"1m","maxQueryLookback":"1s"}),
        ~s({"futureLimit":1}),
        ~s({"maxQueryLength":"1m"} trailing),
        String.duplicate(" ", 1025)
      ]

      for policy <- invalid do
        limited = query_limits(ctx, policy)

        for response <- [request(limited, "/labels", [], 400), request_form(limited, "/labels", [], 400)] do
          assert response["error"] == "invalid_parameter"
          assert response["message"] =~ "X-Loki-Query-Limits"
        end
      end

      for policies <- [[~s({"maxQueryLength":"1m"}), ~s({"maxQueryLength":"0"})], ["{}", "{}"]] do
        limited = Map.put(ctx, :extra_headers, Enum.map(policies, &{"x-loki-query-limits", &1}))
        assert request(limited, "/labels", [], 400)["error"] == "invalid_parameter"
      end

      refute_parquet_read(ctx)
    end

    test "absent and zero policies preserve results and ordered model durations are accepted", ctx do
      params = [{"start", to_string(ctx.now - @minute)}, {"end", to_string(ctx.now)}]
      ordinary = request(ctx, "/labels", params)
      assert ordinary["data"] == ["job"]
      objects = Agent.get(ctx.store, & &1.objects)

      for policy <- [
            "{}",
            ~s({"maxQueryLength":"0"}),
            ~s({"maxQueryLength":"0ms"}),
            ~s({"maxQueryLength":"0y0w0d0h0m0s0ms"}),
            ~s({"maxQueryLength":"60000ms"}),
            ~s({"maxQueryLength":"1m0s"}),
            ~s({"maxQueryLength":"0h1m"}),
            ~s({"maxQueryLength":"1h30m45s"}),
            ~s({"maxQueryLength":"292y24w3d23h47m16s854ms"}),
            ~S( {"maxQuery\u004cength":"1m"} )
          ] do
        limited = query_limits(ctx, policy)
        assert request(limited, "/labels", params) == ordinary
        assert request_form(limited, "/labels", params) == ordinary
      end

      # Zero means no additional restriction, not a zero-length server budget.
      for policy <- ["{}", ~s({"maxQueryLength":"0"})] do
        assert request(query_limits(ctx, policy), "/labels")["data"] == ["job"]
      end

      assert Agent.get(ctx.store, & &1.objects) == objects
    end

    test "instant metrics have a zero evaluation window but unbounded log reads require a start", ctx do
      limited = query_limits(ctx, ~s({"maxQueryLength":"1m"}))
      params = [{"query", ~s({job="fake"})}, {"time", to_string(ctx.now)}]

      for response <- [request(limited, "/query", params, 400), request_form(limited, "/query", params, 400)] do
        assert response["message"] =~ "requires a finite start"
      end

      assert request(limited, "/tail", params, 400)["message"] =~ "not supported for live tail"
      refute_parquet_read(ctx)

      metrics = [{"query", ~s'count_over_time({job="fake"}[1h])'}, {"time", to_string(ctx.now + @second)}]
      assert values(request(limited, "/query", metrics)) == %{%{"job" => "fake"} => "1"}
      assert request_form(limited, "/query", metrics) == request(ctx, "/query", metrics)

      explicit = [{"start", to_string(ctx.now - @minute)}, {"end", to_string(ctx.now - 1)} | params]
      assert lines(request(limited, "/query", explicit)) == ["foo=bar"]
      too_long = List.keyreplace(explicit, "time", 0, {"time", to_string(ctx.now + 1)})
      assert request(limited, "/query", too_long, 400)["error"] == "query_limit"
    end

    test "policies are request-local and authentication keeps tenants isolated", ctx do
      other = %{ctx | tenant: ctx.tenant <> "-other", token: "other-token"}

      tokens =
        Map.new([ctx, other], fn context ->
          {context.tenant, "sha256$" <> Base.encode16(:crypto.hash(:sha256, context.token), case: :lower)}
        end)

      Runtime.put_env(:pulse, Auth, module: SharedSecret, tokens: tokens)
      push(other, "other", ctx.now, %{"private" => "other"})
      assert request(query_limits(ctx, ~s({"maxQueryLength":"1m"})), "/labels", [], 400)["error"] == "query_limit"
      assert request(ctx, "/labels")["data"] == ["job"]
      assert request(other, "/labels")["data"] == ["private"]
      assert request(query_limits(other, ~s({"maxQueryLength":"1m"})), "/labels", [], 400)["error"] == "query_limit"
      unauthorized = query_limits(%{other | token: ctx.token}, "{broken}")
      assert request(unauthorized, "/labels", [], 401)["error"] == "invalid_token"
      assert request(ctx, "/labels")["data"] == ["job"]
    end

    test "a client policy never raises server scan budgets", ctx do
      push(ctx, "foo=baz", ctx.now - @second, %{"job" => "fake"})
      Runtime.put_env(:pulse, Pulse.QueryRunner, max_scan_rows: 1)
      params = [{"query", ~s({job="fake"})} | range(ctx)]
      ordinary = request(ctx, "/query_range", params, 422)
      assert ordinary["error"] == "query_limit"

      for policy <- [~s({"maxQueryLength":"0"}), ~s({"maxQueryLength":"1y"})] do
        limited = query_limits(ctx, policy)
        assert request(limited, "/query_range", params, 422) == ordinary
        assert request_form(limited, "/query_range", params, 422) == ordinary
      end
    end
  end

  describe "categorized response encoding controls" do
    test "collisions, repeated parsing and label mutations retain explicit provenance", ctx do
      line = "job=same pod=body token=same keep=kept gone=drop"

      push(
        ctx,
        line,
        ctx.now,
        %{
          "job" => "same",
          "pod" => "stream",
          "pod_extracted" => "old",
          "rename" => "same"
        },
        %{"token" => "same", "untouched" => "u", "gone" => "drop"}
      )

      objects = Agent.get(ctx.store, & &1.objects)

      expression =
        ~s({job="same"} | logfmt | drop pod | logfmt | drop gone) <>
          ~s( | label_format renamed=rename, token="{{.token}}", overwrite="{{.job}}") <>
          ~s( | keep job, pod_extracted, token, untouched, renamed, overwrite, keep)

      ordinary = query(ctx, expression)
      categorized = query(categorize(ctx), expression)

      assert categorized["data"]["result"] == [
               %{
                 "stream" => %{"job" => "same"},
                 "values" => [
                   [
                     to_string(ctx.now),
                     line,
                     %{
                       "structuredMetadata" => %{"untouched" => "u"},
                       "parsed" => %{
                         "pod_extracted" => "body",
                         "token" => "same",
                         "renamed" => "same",
                         "overwrite" => "same",
                         "keep" => "kept"
                       }
                     }
                   ]
                 ]
               }
             ]

      assert flattened_entries(categorized) == flattened_entries(ordinary)
      assert Agent.get(ctx.store, & &1.objects) == objects
      assert_parquet_read(ctx)
    end

    test "repeated lines and exact duplicates preserve global selection and multiplicity", ctx do
      values =
        for {offset, id} <- [{4, "old"}, {2, "a"}, {2, "b"}, {2, "a"}],
            do: [to_string(ctx.now - offset * @second), "value=1", %{"id" => id}]

      body = %{"streams" => [%{"stream" => %{"job" => "fake", "pod" => "one"}, "values" => values}]}
      assert Req.post!(ctx.url <> "/loki/api/v1/push", headers: headers(ctx), json: body).status == 204
      push(ctx, "value=1", ctx.now - @second, %{"job" => "fake", "pod" => "two"}, %{"id" => "new"})

      all = query(categorize(ctx), ~s({job="fake"} | logfmt))
      entries = flattened_entries(all)
      assert Enum.sum(Map.values(entries)) == 5

      assert entries[
               {to_string(ctx.now - 2 * @second), "value=1",
                %{"job" => "fake", "pod" => "one", "id" => "a", "value" => "1"}}
             ] == 2

      assert entries == flattened_entries(query(ctx, ~s({job="fake"} | logfmt)))

      for direction <- ["forward", "backward"], limit <- [1, 3] do
        params = [
          {"query", ~s({job="fake"} |= "value=" | logfmt | id != "old" | line_format "{{.value}}")},
          {"direction", direction},
          {"limit", to_string(limit)}
          | range(ctx)
        ]

        ordinary = request(ctx, "/query_range", params)
        categorized = request(categorize(ctx), "/query_range", params)
        assert flattened_entries(categorized) == flattened_entries(ordinary)
        assert Enum.sum(Map.values(flattened_entries(categorized))) == limit
        assert Enum.uniq(lines(categorized)) == ["1"]
      end

      assert_parquet_read(ctx)
    end

    test "exact flags negotiate GET and form POST on instant and range endpoints", ctx do
      push(ctx, "x=one", ctx.now, %{"job" => "fake"}, %{"token" => "id"})

      for path <- ["/query", "/query_range"] do
        params = [{"query", ~s({job="fake"} | logfmt)}, {"time", to_string(ctx.now + @second)} | range(ctx)]
        ordinary = request(ctx, path, params)

        for {header, flags, enabled?} <- [
              {"future", ["future"], false},
              {"future,categorize-labels,categorize-labels", ["future", "categorize-labels"], true},
              {"CATEGORIZE-LABELS", ["CATEGORIZE-LABELS"], false},
              {",future,", ["", "future"], false},
              {"", [], false}
            ] do
          flagged = Map.put(ctx, :extra_headers, [{"x-loki-response-encoding-flags", header}])
          response = request(flagged, path, params)
          assert request_form(flagged, path, params) == response
          assert Map.get(response["data"], "encodingFlags", []) == flags
          assert flattened_entries(response) == flattened_entries(ordinary)

          if enabled? do
            assert [%{"stream" => %{"job" => "fake"}, "values" => [[_, "x=one", categories]]}] =
                     response["data"]["result"]

            assert categories == %{"structuredMetadata" => %{"token" => "id"}, "parsed" => %{"x" => "one"}}
          else
            assert response["data"]["result"] == ordinary["data"]["result"]
          end
        end
      end
    end

    test "encoding flags do not change metric samples", ctx do
      push(ctx, "x=one", ctx.now, %{"job" => "fake"}, %{"token" => "id"})
      expression = ~s'count_over_time({job="fake"}[1m])'

      for {path, params} <- [
            {"/query", [{"query", expression}, {"time", to_string(ctx.now + @second)}]},
            {"/query_range",
             [
               {"query", expression},
               {"step", "1"},
               {"start", to_string(ctx.now)},
               {"end", to_string(ctx.now + @second)}
             ]}
          ] do
        ordinary = request(ctx, path, params)
        flagged = request(categorize(ctx), path, params)
        assert flagged["data"]["encodingFlags"] == ["categorize-labels"]
        assert Map.delete(flagged["data"], "encodingFlags") == ordinary["data"]
      end
    end

    test "scan budget failures remain whole errors in both encodings", ctx do
      push(ctx, "x=one", ctx.now, %{"job" => "fake"})
      push(ctx, "x=two", ctx.now - @second, %{"job" => "fake"})
      Runtime.put_env(:pulse, Pulse.QueryRunner, max_scan_rows: 1)
      params = [{"query", ~s({job="fake"} | logfmt)} | range(ctx)]
      ordinary = request(ctx, "/query_range", params, 422)
      categorized = request(categorize(ctx), "/query_range", params, 422)
      assert ordinary == categorized
      assert ordinary["status"] == "error"
      refute Map.has_key?(ordinary, "data")
    end
  end

  @tag :detected_logfmt_duplicates
  test "detected logfmt fields reuse the complete frozen first-duplicate oracle", ctx do
    fixture = "test/fixtures/logs/loki-upstream/logfmt.json" |> File.read!() |> Pulse.JSON.decode!()
    row = Enum.find(fixture["parse_cases"], &(&1["name"] == "duplicate from line property"))
    selection = hd(hd(fixture["provenance"]["sources"])["selections"])

    raw =
      selection["raw"]
      |> String.split("\n")
      |> Enum.slice(row["source_start"] - selection["source_start"], row["source_end"] - row["source_start"] + 1)
      |> Enum.map_join("", &(&1 <> "\n"))

    assert Base.encode16(:crypto.hash(:sha256, raw), case: :lower) ==
             "907c9c52ee3423bf82f5b9c32259e25d5bf66952d702a5c465e8a9f6d564c289"

    assert fixture["counts"]["parse_rows"] == 19
    assert row["base_labels"] == %{"foo" => "bar"}
    assert row["structured_metadata"] == %{}
    assert row["want"] == %{"foo" => "bar", "foobar" => "foo bar"}
    assert row["effective_strict_want"] == row["want"]

    # This parser unit row has no HTTP request or timestamp. Preserve its
    # complete line/labels/oracles and add only a past time and positive bounds.
    line = row["line"]
    push_streams(ctx, [%{"stream" => row["base_labels"], "values" => [[to_string(ctx.now), line]]}])
    assert_parquet(ctx, 1)
    params = [query: ~s/{foo="bar"}/, start: to_string(ctx.now - 1), end: to_string(ctx.now + 1)]

    observations =
      for method <- [&request/4, &request_form/4] do
        raw = method.(ctx, "/query_range", params, 200)
        assert [%{"stream" => %{"foo" => "bar"}, "values" => [[_, ^line]]}] = raw["data"]["result"]

        for suffix <- [" | logfmt", " | logfmt --strict"] do
          parsed = method.(ctx, "/query_range", Keyword.update!(params, :query, &(&1 <> suffix)), 200)
          assert [%{"stream" => labels, "values" => [[_, ^line]]}] = parsed["data"]["result"]
          assert labels == row["want"]
        end

        for suffix <- ["", " | logfmt"] do
          params = Keyword.update!(params, :query, &(&1 <> suffix))
          values = method.(ctx, "/detected_field/foobar/values", params, 200)
          fields = method.(ctx, "/detected_fields", params, 200)
          {values["values"], fields["fields"]}
        end
      end

    assert_parquet_read(ctx)
    expected = {["foo bar"], [%{"label" => "foobar", "type" => "string", "cardinality" => 1, "parsers" => ["logfmt"]}]}
    assert observations == List.duplicate(List.duplicate(expected, 2), 2)
  end

  @tag :detected_logfmt_duplicates
  test "authored detected logfmt ownership preserves normalized destinations metadata and safety", ctx do
    # Authored controls, not new source rows. Empty values never claim a
    # destination; retained values claim it after sanitization and one suffix.
    rows = [
      {~s/foobar="foo bar"/, %{}, "foobar", "foo bar"},
      {~s/foobar= foobar="foo bar" foobar=10ms/, %{}, "foobar", "foo bar"},
      {"a.b=first a_b=second", %{}, "a_b", "first"},
      {~s/foobar="foo bar" foobar=10ms/, %{"foobar" => "stream"}, "foobar_extracted", "foo bar"},
      {"foobar_extracted=first foobar=second", %{"foobar" => "stream"}, "foobar_extracted", "first"}
    ]

    push_streams(
      ctx,
      for {{line, labels, _name, _value}, index} <- Enum.with_index(rows) do
        %{
          "stream" => Map.put(labels, "case", "c#{index}"),
          "values" => [[to_string(ctx.now), line, %{"tag" => "�"}]]
        }
      end
    )

    assert_parquet(ctx, 1)

    observations =
      for {{line, labels, name, expected}, index} <- Enum.with_index(rows), method <- [&request/4, &request_form/4] do
        params = [query: ~s/{case="c#{index}"}/, start: to_string(ctx.now - 1), end: to_string(ctx.now + 1)]
        values = method.(ctx, "/detected_field/#{name}/values", params, 200)
        fields = method.(ctx, "/detected_fields", params, 200)["fields"]
        assert method.(ctx, "/detected_field/tag/values", params, 200)["values"] == ["�"]
        raw = method.(ctx, "/query_range", params, 200)
        assert [%{"stream" => stream, "values" => [[_, ^line]]}] = raw["data"]["result"]
        assert stream == labels |> Map.put("case", "c#{index}") |> Map.put("tag", "�")
        {values["values"], Enum.find(fields, &(&1["label"] == name)), expected}
      end

    assert_parquet_read(ctx)
    params = [query: ~s/{case="c1"}/, start: to_string(ctx.now - 1), end: to_string(ctx.now + 1)]
    before = Agent.get(ctx.store, & &1.requests)

    denied =
      Req.get!(ctx.url <> "/loki/api/v1/detected_field/foobar/values",
        headers: [{"x-scope-orgid", ctx.tenant}],
        params: params,
        retry: false
      )

    assert denied.status == 401

    for method <- [&request/4, &request_form/4] do
      assert method.(%{ctx | token: "wrong-token"}, "/detected_field/foobar/values", params, 401)["error"] ==
               "invalid_token"

      assert method.(ctx, "/detected_field/foobar/values", Keyword.put(params, :end, to_string(ctx.now - 2)), 400)[
               "error"
             ] ==
               "invalid_parameter"
    end

    assert Agent.get(ctx.store, & &1.requests) == before

    for {limits, status, error} <- [
          {[max_per_tenant: 0], 429, "query_overloaded"},
          {[max_scan_rows: 0], 422, "query_limit"}
        ] do
      Runtime.put_env(:pulse, Pulse.QueryRunner, limits)

      for method <- [&request/4, &request_form/4] do
        response = method.(ctx, "/detected_field/foobar/values", params, status)
        assert response["error"] == error
        refute Map.has_key?(response, "values")
      end

      if status == 429, do: assert(Agent.get(ctx.store, & &1.requests) == before)
      Runtime.put_env(:pulse, Pulse.QueryRunner, [])
    end

    for {values, field, expected} <- observations do
      assert values == [expected]
      assert field["type"] == "string"
      assert field["cardinality"] == 1
      assert field["parsers"] == ["logfmt"]
    end
  end

  @tag :detected_json_replacement
  test "detected JSON values replay the complete frozen replacement-rune parser case", ctx do
    fixture = "test/fixtures/logs/loki-upstream/json-parser.json" |> File.read!() |> Pulse.JSON.decode!()
    row = Enum.find(fixture["parse_cases"], &(&1["name"] == "utf8 error rune"))
    assert fixture["counts"]["table_rows"] == 16

    assert Base.encode16(:crypto.hash(:sha256, row["raw"]), case: :lower) ==
             "96a487acc7f5b19984a56930f414bd3ffb1eeac186754d0dcd5a7e5aae0d2d7f"

    assert row["base_labels"] == %{}
    assert row["structured_metadata"] == %{}
    assert row["want"]["foo"] == " "

    # Reuse the existing complete source row, not another imported row. Only
    # timestamp and positive HTTP bounds adapt its empty-label unit setup.
    line = row["line"]
    push_streams(ctx, [%{"stream" => row["base_labels"], "values" => [[to_string(ctx.now), line]]}])
    assert_parquet(ctx, 1)
    params = [query: "{}", start: to_string(ctx.now - 1), end: to_string(ctx.now + 1)]

    responses =
      for method <- [&request/4, &request_form/4] do
        values =
          Map.new(row["want"], fn {key, _} ->
            {key, method.(ctx, "/detected_field/#{key}/values", params, 200)["values"]}
          end)

        fields = method.(ctx, "/detected_fields", params, 200)["fields"]
        assert Map.new(fields, &{&1["label"], &1["jsonPath"]}) == row["want_json_path"]
        raw = method.(ctx, "/query_range", params, 200)
        assert [%{"stream" => %{}, "values" => [[_, ^line]]}] = raw["data"]["result"]

        # The ordinary JSON pipeline already implements this exact oracle;
        # detection must agree without changing the persisted/raw line.
        parsed = method.(ctx, "/query_range", Keyword.put(params, :query, "{} | json"), 200)
        assert [%{"stream" => labels, "values" => [[_, ^line]]}] = parsed["data"]["result"]
        assert labels == row["want"]
        values
      end

    assert_parquet_read(ctx)
    expected = Map.new(row["want"], fn {key, value} -> {key, [value]} end)
    assert responses == [expected, expected]
  end

  @tag :detected_json_replacement
  test "authored detected JSON cleanup preserves key metadata raw and safety boundaries", ctx do
    # These are authored controls, not additional source rows. Cleanup applies
    # to decoded JSON string values, never key/path bytes or metadata values.
    rows = [
      {~s/{"foo":"a��b"}/, %{}, %{"foo" => ["a  b"]}},
      {~S/{"foo":"\ufffd"}/, %{}, %{"foo" => [" "]}},
      {~s/{"foo":"é🙂"}/, %{}, %{"foo" => ["é🙂"]}},
      {~S/{"foo":"\\ufffd"}/, %{}, %{"foo" => [~S/\ufffd/]}},
      {~s/{"�foo":"ok","foo":"clean"}/, %{"tag" => "�"}, %{"_foo" => ["ok"], "foo" => ["clean"], "tag" => ["�"]}},
      {~s/{"foo":"�",}/, %{}, %{"foo" => [" "]}}
    ]

    push_streams(ctx, [
      %{
        "stream" => %{},
        "values" =>
          for {{line, metadata, _}, index} <- Enum.with_index(rows) do
            [to_string(ctx.now - index * 100), line, metadata]
          end
      }
    ])

    assert_parquet(ctx, 1)

    observations =
      for {{line, _metadata, expected}, index} <- Enum.with_index(rows), method <- [&request/4, &request_form/4] do
        at = ctx.now - index * 100
        params = [query: "{}", start: to_string(at - 1), end: to_string(at + 1)]

        values =
          Map.new(expected, fn {key, _} ->
            {key, method.(ctx, "/detected_field/#{key}/values", params, 200)["values"]}
          end)

        fields = method.(ctx, "/detected_fields", params, 200)["fields"]
        paths = Map.new(fields, &{&1["label"], &1["jsonPath"]})

        assert paths ==
                 if(index == 4,
                   do: %{"_foo" => ["�foo"], "foo" => ["foo"], "tag" => nil},
                   else: %{"foo" => ["foo"]}
                 )

        raw = method.(ctx, "/query_range", params, 200)
        assert [%{"values" => [[_, ^line]]}] = raw["data"]["result"]
        {values, expected}
      end

    assert_parquet_read(ctx)
    params = [query: "{}", start: to_string(ctx.now - 1), end: to_string(ctx.now + 1)]
    before = Agent.get(ctx.store, & &1.requests)

    denied =
      Req.get!(ctx.url <> "/loki/api/v1/detected_field/foo/values",
        headers: [{"x-scope-orgid", ctx.tenant}],
        params: params,
        retry: false
      )

    assert denied.status == 401

    for method <- [&request/4, &request_form/4] do
      assert method.(%{ctx | token: "wrong-token"}, "/detected_field/foo/values", params, 401)["error"] ==
               "invalid_token"

      assert method.(
               ctx,
               "/detected_field/foo/values",
               Keyword.put(params, :end, to_string(ctx.now - 2)),
               400
             )["error"] == "invalid_parameter"
    end

    assert Agent.get(ctx.store, & &1.requests) == before

    for {limits, status, error} <- [
          {[max_per_tenant: 0], 429, "query_overloaded"},
          {[max_scan_rows: 0], 422, "query_limit"}
        ] do
      Runtime.put_env(:pulse, Pulse.QueryRunner, limits)

      for method <- [&request/4, &request_form/4] do
        response = method.(ctx, "/detected_field/foo/values", params, status)
        assert response["error"] == error
        refute Map.has_key?(response, "values")
      end

      if status == 429, do: assert(Agent.get(ctx.store, & &1.requests) == before)
      Runtime.put_env(:pulse, Pulse.QueryRunner, [])
    end

    for {values, expected} <- observations, do: assert(values == expected)
  end

  @tag :detected_numeric_booleans
  test "complete detected-label source subtest retains numeric boolean suggestions", ctx do
    source = File.read!("test/fixtures/logs/loki-upstream/detected-label-numeric-booleans.go.txt")

    assert Base.encode16(:crypto.hash(:sha256, source), case: :lower) ==
             "0240f47cc9e9678602ff7701aa5b69866222c6570af45c4626124f5335aefff0"

    original =
      Map.new(Regex.scan(~r/"([^"]+)":\s*\{Values: \[\]string\{([^}]+)\}\}/, source), fn [_, label, values] ->
        {label, Enum.map(Regex.scan(~r/"([^"]*)"/, values), fn [_, value] -> value end)}
      end)

    assert map_size(original) == 5
    assert Enum.sum(Enum.map(original, fn {_, values} -> length(values) end)) == 9
    assert source =~ "assert.Len(t, detectedLabels, 3)"

    [_, oracle] = Regex.run(~r/assert.ElementsMatch\(t, \[\]string\{([^}]+)\}, foundLabels\)/, source)
    expected = Enum.sort(Enum.map(Regex.scan(~r/"([^"]+)"/, oracle), fn [_, label] -> label end))
    assert expected == ["boolean-bools", "boolean-bools-uppercase", "boolean-ints"]

    # Original input is an ingester mock's five name/value collections, not
    # log lines. Give every original value its own singleton-label stream;
    # carrier text and a positive window replace the mock's equal bounds.
    streams =
      for {label, values} <- original, value <- values do
        %{"stream" => %{label => value}, "values" => [[to_string(ctx.now), "authored mock-to-HTTP carrier"]]}
      end

    push_streams(ctx, streams)
    assert_parquet(ctx, 1)
    params = [start: to_string(ctx.now - @second), end: to_string(ctx.now + @second)]

    responses =
      for method <- [&request/4, &request_form/4] do
        response = method.(ctx, "/detected_labels", params, 200)
        series = method.(ctx, "/series", params, 200)
        assert MapSet.new(series["data"]) == MapSet.new(Enum.map(streams, & &1["stream"]))
        response["detectedLabels"]
      end

    assert_parquet_read(ctx)

    # Execute both transports before asserting the unchanged source oracle.
    for labels <- responses do
      assert length(labels) == 3
      assert Enum.sort(Enum.map(labels, & &1["label"])) == expected
      # Authored exact-cardinality control, not an upstream sketch oracle.
      assert Enum.all?(labels, &(&1["cardinality"] == 2))
    end
  end

  @tag :detected_numeric_booleans
  test "authored detected-label boundaries keep only literal numeric booleans", ctx do
    authored = %{
      "zero-only" => ["0"],
      "one-only" => ["1"],
      "zero-one" => ["0", "1"],
      "zero-one-two" => ["0", "1", "2"],
      "signed-zero" => ["-0", "+0"],
      "decimal-bools" => ["0.0", "1.0"],
      "mixed" => ["0", "unknown"],
      "pod" => ["2", "3"],
      "numeric" => ["6", "7"],
      "uuid" => ["751e8ee6-b377-4b2e-b7b5-5508fbe980ef"]
    }

    push_streams(
      ctx,
      for {label, values} <- authored, value <- values do
        %{"stream" => %{label => value}, "values" => [[to_string(ctx.now), "authored boundary carrier"]]}
      end
    )

    assert_parquet(ctx, 1)
    params = [start: to_string(ctx.now - @second), end: to_string(ctx.now + @second)]

    responses =
      for method <- [&request/4, &request_form/4] do
        method.(ctx, "/detected_labels", params, 200)
      end

    for response <- responses do
      assert response == %{
               "detectedLabels" => [
                 %{"label" => "mixed", "cardinality" => 2},
                 %{"label" => "one-only", "cardinality" => 1},
                 %{"label" => "pod", "cardinality" => 2},
                 %{"label" => "zero-one", "cardinality" => 2},
                 %{"label" => "zero-only", "cardinality" => 1}
               ]
             }
    end

    # The label-suggestion exception must not change field typing: numeric
    # booleans remain integers, while ordinary Boolean strings remain Boolean.
    for method <- [&request/4, &request_form/4], value <- ["0", "1"] do
      response =
        method.(ctx, "/detected_fields", Keyword.put(params, :query, ~s/{pod="2"} | line_format "v=#{value}"/), 200)

      assert [%{"label" => "v", "type" => "int"}] =
               Enum.map(response["fields"], &Map.take(&1, ["label", "type"]))
    end

    assert FieldType.detect("1") == "int"
    assert FieldType.detect("true") == "boolean"
    assert_parquet_read(ctx)
  end

  @tag :detected_numeric_booleans
  test "numeric boolean suggestions preserve auth bounds admission and fail-whole scans", ctx do
    push_streams(
      ctx,
      for value <- ["0", "1"] do
        %{"stream" => %{"boolean" => value}, "values" => [[to_string(ctx.now), "authored policy carrier"]]}
      end
    )

    assert_parquet(ctx, 1)
    params = [start: to_string(ctx.now - @second), end: to_string(ctx.now + @second)]

    # Establish actual native Parquet reads before tightening admission. A
    # footer/manifest row bound can reject without downloading the payload.
    for method <- [&request/4, &request_form/4] do
      assert is_list(method.(ctx, "/detected_labels", params, 200)["detectedLabels"])

      assert method.(
               ctx,
               "/detected_labels",
               [start: to_string(ctx.now - 3 * @second), end: to_string(ctx.now - 2 * @second)],
               200
             ) == %{"detectedLabels" => []}
    end

    assert_parquet_read(ctx)
    before = Agent.get(ctx.store, & &1.requests)

    denied =
      Req.get!(ctx.url <> "/loki/api/v1/detected_labels",
        params: params,
        headers: [{"x-scope-orgid", ctx.tenant}],
        retry: false
      )

    assert denied.status == 401
    assert denied.body["error"] == "missing_token"

    for method <- [&request/4, &request_form/4] do
      assert method.(%{ctx | token: "wrong-token"}, "/detected_labels", params, 401)["error"] == "invalid_token"

      assert method.(
               ctx,
               "/detected_labels",
               [start: to_string(ctx.now + @second), end: to_string(ctx.now - @second)],
               400
             )["error"] == "invalid_parameter"
    end

    assert Agent.get(ctx.store, & &1.requests) == before

    for {limits, status, error} <- [
          {[max_scan_rows: 1], 422, "query_limit"},
          {[max_per_tenant: 0], 429, "query_overloaded"}
        ] do
      Runtime.put_env(:pulse, Pulse.QueryRunner, limits)

      for method <- [&request/4, &request_form/4] do
        before = Agent.get(ctx.store, & &1.requests)
        response = method.(ctx, "/detected_labels", params, status)
        assert response["error"] == error
        refute Map.has_key?(response, "detectedLabels")
        if status == 429, do: assert(Agent.get(ctx.store, & &1.requests) == before)
      end

      Runtime.put_env(:pulse, Pulse.QueryRunner, [])
    end

    assert_parquet_read(ctx)
  end

  @tag :detected_object_comma
  test "complete nested JSON detection source pairs retain original difficult-key paths", ctx do
    source = File.read!("test/fixtures/logs/loki-upstream/nested-json-field-detection.go.txt")

    assert Base.encode16(:crypto.hash(:sha256, source), case: :lower) ==
             "d90a731058af10163cdebda0c882ebafc7acb4f7c66c99ab75c50e34d6bfcbed"

    [valid_a, valid_b, difficult_a, difficult_b] =
      for [_, line] <- Regex.scan(~r/Line: `([^`]+)`/s, source), do: line

    common = %{
      "user_id" => ["user", "id"],
      "user_name" => ["user", "name"],
      "user_settings_theme" => ["user", "settings", "theme"],
      "user_settings_notifications" => ["user", "settings", "notifications"]
    }

    valid_paths =
      Map.merge(common, %{
        "app_version" => ["app", "version"],
        "app_metrics_cpu" => ["app", "metrics", "cpu"],
        "app_metrics_memory" => ["app", "metrics", "memory"]
      })

    difficult_paths =
      Map.merge(common, %{
        "app_id" => ["app-id"],
        "app_name" => ["app_name"],
        "app_terrible_key_name" => ["app", "terrible/key/name"],
        "other_bad_key_name" => ["other.bad.key.name"],
        "key_with_spaces" => ["key with spaces"],
        "nested_key_with_spaces_nest" => ["nested key with spaces", "nest"]
      })

    labels = %{"cluster" => "test-cluster", "job" => "json-test"}

    # Separately authored repairs remove only these known terminal commas from
    # the two fixtures. These are controls, never replacements for source loads.
    repaired_a =
      difficult_a
      |> String.replace("\"notifications\":true,", "\"notifications\":true")
      |> String.replace(~s("terrible/key/name": "four",), ~s("terrible/key/name": "four"))
      |> String.replace(~s("nest": "thermostat",), ~s("nest": "thermostat"))

    repaired_b =
      difficult_b
      |> String.replace("},\n        }", "}\n        }")
      |> String.replace(~s("terrible/key/name": "four",), ~s("terrible/key/name": "four"))
      |> String.replace(~s("nest": "protect",), ~s("nest": "protect"))

    assert {:ok, _} = Pulse.JSON.decode(repaired_a)
    assert {:ok, _} = Pulse.JSON.decode(repaired_b)

    pairs = [
      {ctx.now - @second, [valid_a, valid_b], valid_paths},
      {ctx.now, [difficult_a, difficult_b], difficult_paths},
      {ctx.now + 1, [repaired_a, repaired_b], difficult_paths}
    ]

    # HTTP adaptation: translate each original now to a separate instant,
    # retaining both same-timestamp entries, exact line bytes and empty metadata.
    push_streams(ctx, [
      %{
        "stream" => labels,
        "values" => for({time, lines, _paths} <- pairs, line <- lines, do: [to_string(time), line, %{}])
      }
    ])

    assert_parquet(ctx, 1)

    # Execute both transports for both complete original setups before checking
    # their oracles, so a red assertion cannot hide the other response.
    observations =
      for {time, lines, paths} <- pairs, method <- [&request/4, &request_form/4] do
        params = [
          query: ~s/{cluster="test-cluster", job="json-test"}/,
          start: to_string(time),
          end: to_string(time),
          line_limit: "100",
          limit: "20"
        ]

        raw = method.(ctx, "/query_range", Keyword.replace!(params, :end, to_string(time + 1)), 200)
        assert Enum.sort(lines(raw)) == Enum.sort(lines)
        {paths, method.(ctx, "/detected_fields", params, 200)}
      end

    for {paths, response} <- observations do
      assert Map.new(response["fields"] || [], &{&1["label"], &1["jsonPath"]}) == paths,
             inspect(response)

      if paths == valid_paths do
        # The preceding original subtest also asserts these seven types.
        assert Map.new(response["fields"], &{&1["label"], &1["type"]}) == %{
                 "user_id" => "int",
                 "user_name" => "string",
                 "user_settings_theme" => "string",
                 "user_settings_notifications" => "boolean",
                 "app_version" => "float",
                 "app_metrics_cpu" => "float",
                 "app_metrics_memory" => "bytes"
               }
      end
    end

    assert_parquet_read(ctx)
  end

  @tag :detected_object_comma
  test "authored object-comma controls preserve strings and reject unrelated malformed JSON", ctx do
    # These are authored producers/results, not more upstream table rows.
    string = "commas,} and braces {,} and quote \" and backslash \\"
    escaped = Pulse.JSON.encode!(string)
    escaped_key = Pulse.JSON.encode!("key,}\"\\end")

    cases = [
      {~s/{"text":#{escaped},"nested":{"leaf":true,},}/, %{"text" => ["text"], "nested_leaf" => ["nested", "leaf"]}},
      {~s/{"a":1,"b":false,"c":null,"d":[],"e":{}, \r\n\t}/, %{"a" => ["a"], "b" => ["b"]}},
      {~s/{"a":[{"b":2,}],"sentinel":1,}/, %{"sentinel" => ["sentinel"]}},
      {~s/{"a":{"b":2,},"c":3,}/, %{"a_b" => ["a", "b"], "c" => ["c"]}},
      # Repaired strict counterpart remains an independent control.
      {~s/{"text":#{escaped},"nested":{"leaf":true}}/, %{"text" => ["text"], "nested_leaf" => ["nested", "leaf"]}},
      {~s/{#{escaped_key}:{"leaf":1,},}/, %{"key____end_leaf" => ["key,}\"\\end", "leaf"]}},
      {~s/{,}/, :invalid},
      # Sentinel fields distinguish rejection from accidentally accepting an
      # otherwise invisible empty object or skipped array/null value.
      {~s/{,"sentinel":1}/, :invalid},
      {~s/{"a":1,,}/, :invalid},
      {~s/{"a":1, ,}/, :invalid},
      {~s/{"a":,}/, :invalid},
      {~s/{"sentinel":1,"a":,}/, :invalid},
      {~s/{"sentinel":1,"a":[1,],}/, :invalid},
      {~s/{"sentinel":1,"a":[,],}/, :invalid},
      {~s/{"a":1,/, :invalid},
      {~s/{"a":true false,}/, :invalid},
      {~s/{"a":1} garbage,}/, :invalid},
      {~s/{"a":"unterminated,}/, :invalid},
      {~s/{"a":{"b":,},}/, :invalid},
      {~s/{"a":1,} {"b":2,}/, :invalid},
      {"plain=logfmt", :logfmt}
    ]

    push_streams(ctx, [
      %{
        "stream" => %{"job" => "comma-controls"},
        "values" => for({{line, _expected}, i} <- Enum.with_index(cases), do: [to_string(ctx.now - i), line])
      }
    ])

    assert_parquet(ctx, 1)

    for {{line, expected}, i} <- Enum.with_index(cases), method <- [&request/4, &request_form/4] do
      params = [query: ~s/{job="comma-controls"}/, start: to_string(ctx.now - i), end: to_string(ctx.now - i)]
      response = method.(ctx, "/detected_fields", params, 200)
      fields = response["fields"] || []

      case expected do
        :invalid ->
          refute Enum.any?(fields, &("json" in (&1["parsers"] || []))), inspect({line, response})

        :logfmt ->
          assert fields == [%{"label" => "plain", "type" => "string", "cardinality" => 1, "parsers" => ["logfmt"]}]

        paths ->
          assert Map.new(fields, &{&1["label"], &1["jsonPath"]}) == paths, inspect({line, response})
          assert Enum.all?(fields, &(&1["parsers"] == ["json"]))
      end

      if i in [0, 4] do
        assert method.(ctx, "/detected_field/text/values", params, 200)["values"] == [string]
      end
    end

    assert_parquet_read(ctx)
  end

  @tag :detected_object_comma
  test "detector fallback retains newest-line selection authentication and fail-whole budgets", ctx do
    push_streams(ctx, [
      %{
        "stream" => %{"job" => "comma-policy"},
        "values" => [
          [to_string(ctx.now - 1), ~s/{"old":1,}/],
          [to_string(ctx.now), "new=ok"]
        ]
      }
    ])

    assert_parquet(ctx, 1)
    params = [query: ~s/{job="comma-policy"}/, start: to_string(ctx.now - 1), end: to_string(ctx.now), line_limit: "1"]

    for method <- [&request/4, &request_form/4] do
      assert Enum.map(method.(ctx, "/detected_fields", params, 200)["fields"], & &1["label"]) == ["new"]

      # The detector's fallback must not broaden ordinary | json execution.
      raw =
        method.(
          ctx,
          "/query_range",
          [query: ~s/{job="comma-policy"} | json/, start: to_string(ctx.now - 1), end: to_string(ctx.now)],
          200
        )

      assert [%{"stream" => %{"__error__" => "JSONParserErr"}, "values" => [[_, ~s/{"old":1,}/]]}] =
               raw["data"]["result"]
    end

    before = Agent.get(ctx.store, & &1.requests)

    denied =
      Req.get!(ctx.url <> "/loki/api/v1/detected_fields",
        params: params,
        headers: [{"x-scope-orgid", ctx.tenant}],
        retry: false
      )

    assert denied.status == 401
    assert Agent.get(ctx.store, & &1.requests) == before

    # Raw detector sampling has provider scan bounds and worker admission, not
    # the metric evaluator's request-local max_work budget. Test those existing
    # boundaries rather than inventing a new detector byte/work policy.
    for {limits, status, error} <- [
          {[max_scan_rows: 1], 422, "query_limit"},
          {[max_per_tenant: 0], 429, "query_overloaded"}
        ] do
      Runtime.put_env(:pulse, Pulse.QueryRunner, limits)

      for method <- [&request/4, &request_form/4] do
        before = Agent.get(ctx.store, & &1.requests)
        response = method.(ctx, "/detected_fields", Keyword.put(params, :line_limit, "100"), status)
        assert response["error"] == error
        refute Map.has_key?(response, "fields")
        if status == 429, do: assert(Agent.get(ctx.store, & &1.requests) == before)
      end

      Runtime.put_env(:pulse, Pulse.QueryRunner, [])
    end

    assert_parquet_read(ctx)
  end

  describe "Test_ExploreLogsApis/detected_fields public results" do
    setup ctx do
      for {line, timestamp} <- [
            {"foo=bar color=red", ctx.now - 45 * @minute},
            {"foo=bar color=blue", ctx.now - 45 * @minute},
            {"foo=bar color=red", ctx.now - 5 * @second},
            {"foo=bar color=purple", ctx.now - 5 * @second},
            {"foo=bar color=green", ctx.now},
            {"foo=bar color=red", ctx.now}
          ] do
        push(ctx, line, timestamp, %{"job" => "fake"})
      end

      assert_parquet(ctx, 6)
      :ok
    end

    test "log query returns all six input lines", ctx do
      response = query(ctx, ~s({job="fake"}))
      assert response["data"]["resultType"] == "streams"

      assert lines(response) ==
               Enum.sort([
                 "foo=bar color=red",
                 "foo=bar color=blue",
                 "foo=bar color=red",
                 "foo=bar color=purple",
                 "foo=bar color=green",
                 "foo=bar color=red"
               ])

      assert_parquet_read(ctx)
    end

    test "non-split queries detect three recent color values", ctx do
      response =
        request(ctx, "/detected_fields", [
          {"query", ~s({job="fake"})},
          {"start", to_string(ctx.now - @minute)},
          {"end", to_string(ctx.now + @minute)}
        ])

      # The upstream response struct decodes only these three field members.
      assert Enum.sort(Enum.map(response["fields"], &Map.take(&1, ["label", "type", "cardinality"]))) ==
               Enum.sort([
                 %{"label" => "foo", "type" => "string", "cardinality" => 1},
                 %{"label" => "color", "type" => "string", "cardinality" => 3}
               ])

      assert_parquet_read(ctx)
    end

    @tag :detected_limit_fallback
    test "empty limit falls back to field_limit without hiding invalid limits", ctx do
      bounds = [
        {"query", ~s({job="fake"})},
        {"start", to_string(ctx.now - @minute)},
        {"end", to_string(ctx.now + @minute)}
      ]

      # Authored controls for pinned pkg/loghttp/params.go detectedFieldsLimit.
      for {limits, expected} <- [
            {[], 1000},
            {[{"field_limit", "1"}], 1},
            {[{"limit", ""}, {"field_limit", "1"}], 1},
            {[{"limit", ""}, {"field_limit", ""}], 1000},
            {[{"limit", "2"}, {"field_limit", "0"}], 2},
            {[{"limit", "1"}, {"field_limit", "5001"}], 1}
          ],
          method <- [&request/4, &request_form/4] do
        fields = method.(ctx, "/detected_fields", bounds ++ limits, 200)
        assert fields["limit"] == expected
        assert length(fields["fields"]) == min(expected, 2)

        values = method.(ctx, "/detected_field/color/values", bounds ++ limits, 200)
        assert values["limit"] == expected
        assert length(values["values"]) == min(expected, 3)
        assert Enum.all?(values["values"], &(&1 in ["green", "purple", "red"]))
      end

      for limits <- [
            [{"limit", ""}, {"field_limit", "0"}],
            [{"limit", ""}, {"field_limit", "-1"}],
            [{"limit", ""}, {"field_limit", "invalid"}],
            [{"limit", ""}, {"field_limit", "5001"}],
            [{"limit", "0"}, {"field_limit", "1"}],
            [{"limit", "invalid"}, {"field_limit", "1"}]
          ],
          path <- ["/detected_fields", "/detected_field/color/values"],
          method <- [&request/4, &request_form/4] do
        before = Agent.get(ctx.store, & &1.requests)
        response = method.(ctx, path, bounds ++ limits, 400)
        assert response["error"] == "invalid_parameter"
        assert Agent.get(ctx.store, & &1.requests) == before
      end

      assert_parquet_read(ctx)
    end

    @tag :detected_step_admission
    test "detected fields validate millisecond steps and the original interval ceiling", ctx do
      bounds = [
        {"query", ~s({job="fake"})},
        {"start", to_string(ctx.now - div(@second, 2))},
        {"end", to_string(ctx.now + div(@second, 2))}
      ]

      # Pinned ParseDetectedFieldsQuery validates step.Milliseconds() and
      # integer (end-start)/step before dispatch; it does not ignore step.
      for step <- ["0", "-1", "invalid", "NaN", "Inf", "0.000999999", "999999ns", String.duplicate("1", 129)],
          path <- ["/detected_fields", "/detected_field/color/values"],
          method <- [&request/4, &request_form/4] do
        before = Agent.get(ctx.store, & &1.requests)
        response = method.(ctx, path, [{"step", step} | bounds], 400)
        assert response["error"] == "invalid_parameter"
        assert Agent.get(ctx.store, & &1.requests) == before
      end

      for step <- [nil, "", "0.001", "1ms", "0.001000999", "1s"],
          method <- [&request/4, &request_form/4] do
        params = if is_nil(step), do: bounds, else: [{"step", step} | bounds]
        fields = method.(ctx, "/detected_fields", params, 200)
        assert Map.new(fields["fields"], &{&1["label"], &1["cardinality"]}) == %{"foo" => 1, "color" => 2}
        values = method.(ctx, "/detected_field/color/values", params, 200)
        assert values["values"] == ["green", "red"]
      end

      for {step, width, status} <- [
            {"1ms", 11 * @second, 200},
            {"1ms", 11_001_000_000 - 1, 200},
            {"1ms", 11_001_000_000, 400},
            {"0.0015", 16_500_000_000, 200},
            {"0.0015", 16_501_500_000, 400}
          ],
          path <- ["/detected_fields", "/detected_field/color/values"],
          method <- [&request/4, &request_form/4] do
        params = [
          {"query", ~s({job="fake"})},
          {"start", to_string(ctx.now - width)},
          {"end", to_string(ctx.now)},
          {"step", step}
        ]

        before = Agent.get(ctx.store, & &1.requests)
        response = method.(ctx, path, params, status)

        if status == 400 do
          assert response["error"] == "invalid_parameter"
          assert Agent.get(ctx.store, & &1.requests) == before
        else
          if path == "/detected_fields" do
            assert Map.new(response["fields"], &{&1["label"], &1["cardinality"]}) == %{"foo" => 1, "color" => 3}
          else
            assert response["values"] == ["green", "purple", "red"]
          end
        end
      end

      assert_parquet_read(ctx)
    end

    test "split queries detect four retained color values", ctx do
      response =
        request(ctx, "/detected_fields", [
          {"query", ~s({job="fake"})},
          {"start", to_string(ctx.now - 24 * 60 * @minute)},
          {"end", to_string(ctx.now + @minute)}
        ])

      assert Enum.sort(Enum.map(response["fields"], &Map.take(&1, ["label", "type", "cardinality"]))) ==
               Enum.sort([
                 %{"label" => "foo", "type" => "string", "cardinality" => 1},
                 %{"label" => "color", "type" => "string", "cardinality" => 4}
               ])

      assert_parquet_read(ctx)
    end

    # Pulse-authored regression control, not another upstream case.
    test "Pulse control: inclusive bounds and newest sampling work across all six segments", ctx do
      for {start, finish, line_limit} <- [
            {ctx.now - 45 * @minute, ctx.now - 45 * @minute, "100"},
            {ctx.now, ctx.now, "100"},
            {ctx.now - 24 * 60 * @minute, ctx.now + @minute, "2"}
          ] do
        params = [
          {"query", ~s({job="fake"})},
          {"start", to_string(start)},
          {"end", to_string(finish)},
          {"line_limit", line_limit}
        ]

        response = request(ctx, "/detected_fields", params)
        assert request_form(ctx, "/detected_fields", params) == response
        assert Map.new(response["fields"], &{&1["label"], &1["cardinality"]}) == %{"foo" => 1, "color" => 2}
      end

      empty_window = [
        {"query", ~s({job="fake"})},
        {"start", to_string(ctx.now - 45 * @minute + 1)},
        {"end", to_string(ctx.now - 5 * @second - 1)}
      ]

      assert request(ctx, "/detected_fields", empty_window) == %{}
      assert request_form(ctx, "/detected_fields", empty_window) == %{}
      assert_parquet_read(ctx)
    end
  end

  describe "TestSampleQueryStreamOrderingEquivalence public result" do
    test "grouping by every fixture label returns counts a=3, b=2, c=1", ctx do
      for {app, lines} <- [{"a", ["a1", "a2", "a3"]}, {"b", ["b1", "b2"]}, {"c", ["c1"]}],
          {line, index} <- Enum.with_index(lines) do
        push(ctx, line, ctx.now - (30 - index) * @minute, %{"job" => "varlog", "cluster" => "prod", "app" => app})
      end

      assert_parquet(ctx, 6)
      response = instant(ctx, ~s'sum by (cluster, job, app) (count_over_time({cluster="prod"}[1h]))')
      assert length(response["data"]["result"]) == 3

      assert values(response) == %{
               %{"job" => "varlog", "cluster" => "prod", "app" => "a"} => "3",
               %{"job" => "varlog", "cluster" => "prod", "app" => "b"} => "2",
               %{"job" => "varlog", "cluster" => "prod", "app" => "c"} => "1"
             }

      assert_parquet_read(ctx)
    end
  end

  describe "TestSampleQueryStreamDataObjEquivalence public results" do
    setup ctx do
      for {line, minutes, app} <- [
            {"msg=a1 n=10", 6, "a"},
            {"msg=a2 n=20", 5, "a"},
            {"msg=a3 n=30", 4, "a"},
            {"msg=b1 n=1", 3, "b"},
            {"msg=b2 n=2", 2, "b"}
          ] do
        push(ctx, line, ctx.now - minutes * @minute, %{"job" => "dataobjit", "app" => app})
      end

      assert_parquet(ctx, 5)
      :ok
    end

    test "count_over_time complete expected result", ctx do
      response = instant(ctx, ~s'sum by (job, app) (count_over_time({job="dataobjit"}[1h]))')

      assert values(response) == %{
               %{"job" => "dataobjit", "app" => "a"} => "3",
               %{"job" => "dataobjit", "app" => "b"} => "2"
             }

      assert_parquet_read(ctx)
    end

    test "sum_over_time expected sums", ctx do
      response = instant(ctx, ~s'sum by (job, app) (sum_over_time({job="dataobjit"} | logfmt | unwrap n [1h]))')

      assert values(response) == %{
               %{"job" => "dataobjit", "app" => "a"} => "60",
               %{"job" => "dataobjit", "app" => "b"} => "3"
             }

      assert_parquet_read(ctx)
    end

    test "line-filter matching stream", ctx do
      response = instant(ctx, ~s'sum by (job, app) (count_over_time({job="dataobjit"} |= "a" [1h]))')
      assert values(response) == %{%{"job" => "dataobjit", "app" => "a"} => "3"}
      assert_parquet_read(ctx)
    end
  end

  defp headers(ctx) do
    [{"authorization", "Bearer " <> ctx.token}, {"x-scope-orgid", ctx.tenant}] ++ Map.get(ctx, :extra_headers, [])
  end

  defp push(ctx, line, timestamp, labels, metadata \\ %{}) do
    push_streams(ctx, [%{"stream" => labels, "values" => [[to_string(timestamp), line, metadata]]}])
  end

  defp replay_sample_extractors(ctx, rows) do
    rows =
      Enum.map(Enum.with_index(rows, 1), fn {row, index} ->
        {row, %{ctx | now: ctx.now - index * 120 * @second}}
      end)

    push_streams(
      ctx,
      for {row, at} <- rows do
        %{"stream" => row.base, "values" => [[to_string(at.now), row.line, row.metadata]]}
      end
    )

    assert_parquet(ctx, 1)

    for {row, at} <- rows,
        path <- ["/query", "/query_range"],
        method <- [&request/4, &request_form/4] do
      timestamp = to_string(at.now)
      params = [query: row.query, time: timestamp, start: timestamp, end: timestamp, step: "1"]
      response = method.(at, path, params, 200)
      series = response["data"]["result"]

      if row.expected_ok do
        assert [%{"metric" => labels} = sample] = series, row.id
        assert is_nil(row.expected_labels) or labels == row.expected_labels, row.id
        points = Map.get(sample, "values", [sample["value"]])
        assert [[time, text]] = points, row.id
        assert time == at.now / @second, row.id
        assert {value, ""} = Float.parse(text), row.id
        assert is_nil(row.expected_value) or value == row.expected_value, row.id
        assert not row.distinct? or value == 1.0, row.id
      else
        assert series == [], row.id
      end

      if row.unpreserved_query do
        failed = method.(at, path, Keyword.put(params, :query, row.unpreserved_query), 400)
        assert failed["error"] == "evaluation_failed"
        refute Map.has_key?(failed, "data")
      end
    end

    assert_parquet_read(ctx)
  end

  defp push_builder_rows(ctx, rows, spacing \\ @second) do
    rows = Enum.map(Enum.with_index(rows, 1), fn {row, index} -> {row, %{ctx | now: ctx.now - index * spacing}} end)

    push_streams(
      ctx,
      for {row, at} <- rows do
        %{"stream" => row.base, "values" => [[to_string(at.now), "label-builder", row.metadata]]}
      end
    )

    assert_parquet(ctx, 1)
    rows
  end

  defp push_dispersion_fixture(ctx) do
    streams =
      for {name, observations} <- [
            {"single", [{30, "v=5"}]},
            {"constant", [{20, "v=4"}, {30, "v=4"}, {40, "v=4"}]},
            {"vary", [{20, "v=2"}, {40, "v=6"}]},
            {"nan", [{20, "v=5"}, {40, "v=NaN"}]},
            {"late", [{80, "v=10"}, {90, "v=30"}]}
          ] do
        %{
          "stream" => %{"app" => "a", "c" => name},
          "values" => for({time, line} <- observations, do: [to_string(ctx.now + time * @second), line])
        }
      end

    noise = %{
      "stream" => %{"app" => "noise"},
      "values" => for(time <- [20, 30, 40], do: [to_string(ctx.now + time * @second), "noise"])
    }

    streams = streams ++ [noise]
    assert Enum.sum(Enum.map(streams, &length(&1["values"]))) == 13
    push_streams(ctx, streams)
    streams
  end

  defp push_topk_parameter_fixture(ctx) do
    streams =
      for {app, pod, line, start, step, count} <- [
            {"foo", "a", "xbar", 10, 10, 18},
            {"foo", "a", "noise", 15, 10, 18},
            {"foo", "b", "xbar", 5, 5, 36},
            {"foo", "b", "noise", 7, 5, 36},
            {"bar", "a", "xbar", 4, 4, 45},
            {"bar", "a", "noise", 2, 4, 45},
            {"bar", "b", "xbar", 2, 2, 90},
            {"bar", "b", "noise", 1, 2, 90}
          ] do
        %{
          "stream" => %{"app" => app, "pod" => pod},
          "values" => for(index <- 0..(count - 1), do: [to_string(ctx.now + (start + index * step) * @second), line])
        }
      end

    assert Enum.sum(Enum.map(streams, &length(&1["values"]))) == 378

    streams =
      streams
      |> Enum.group_by(& &1["stream"])
      |> Enum.map(fn {labels, schedules} ->
        values = schedules |> Enum.flat_map(& &1["values"]) |> Enum.sort_by(fn [time, _] -> String.to_integer(time) end)
        %{"stream" => labels, "values" => values}
      end)

    push_streams(ctx, streams)
    streams
  end

  defp push_binary_matching_fixture(ctx) do
    streams =
      for {labels, line, seconds} <- [
            {%{"app" => "foo", "machine" => "fuzz"}, "x", 10},
            {%{"app" => "foo", "machine" => "buzz"}, "x", 15},
            {%{"app" => "noise"}, "noise", 10}
          ] do
        %{
          "stream" => labels,
          "values" => for(index <- 0..18, do: [to_string(ctx.now + index * seconds * @second), line])
        }
      end

    assert Enum.sum(Enum.map(streams, &length(&1["values"]))) == 57
    push_streams(ctx, streams)
  end

  defp push_streams(ctx, streams) do
    response = Req.post!(ctx.url <> "/loki/api/v1/push", headers: headers(ctx), json: %{"streams" => streams})
    assert response.status == 204, inspect(response.body)
  end

  defp push_protobuf(ctx, labels, timestamp, line, status \\ 204) do
    request = %PushProto.PushRequest{
      streams: [
        %PushProto.Stream{
          labels: labels,
          entries: [
            %PushProto.Entry{
              timestamp: %PushProto.Timestamp{seconds: div(timestamp, @second), nanos: rem(timestamp, @second)},
              line: line
            }
          ]
        }
      ]
    }

    {bytes, _} = PushProto.PushRequest.encode!(request)
    {:ok, compressed} = :snappyer.compress(IO.iodata_to_binary(bytes))

    response =
      Req.post!(ctx.url <> "/loki/api/v1/push",
        headers: [{"content-type", "application/x-protobuf"} | headers(ctx)],
        body: compressed,
        decode_body: false,
        retry: false
      )

    assert response.status == status, response.body
    response
  end

  # Authored diagnostic-selection queries must capture the rendered details:
  # direct __error_details__ predicates read the independent ordinary label.
  defp rendered_error_details_filter(details) do
    ~s/ | label_format diagnostic_details="{{.__error_details__}}" | diagnostic_details=/ <>
      Pulse.JSON.encode!(details) <> " | drop diagnostic_details"
  end

  defp quantity_errors(kind) do
    "test/fixtures/logs/loki-upstream/#{kind}-errors.jsonl"
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&Pulse.JSON.decode!/1)
  end

  defp string_literal_cases do
    "test/fixtures/logs/loki-upstream/string-literals.jsonl"
    |> File.stream!()
    |> Enum.map(fn line ->
      row = Pulse.JSON.decode!(line)
      value = if row["value_base64"], do: Base.decode64!(row["value_base64"])
      {Base.decode64!(row["literal_base64"]), value}
    end)
  end

  defp ip_filter_cases do
    "test/fixtures/logs/loki-upstream/ip-filters.jsonl"
    |> File.stream!()
    |> Enum.map(&Pulse.JSON.decode!/1)
  end

  defp line_or_cases do
    "test/fixtures/logs/loki-upstream/line-or.jsonl"
    |> File.stream!()
    |> Enum.map(&Pulse.JSON.decode!/1)
  end

  defp http_parameter_params(%{"input" => %{"input" => values}}) do
    Enum.flat_map(values, fn {key, entries} -> Enum.map(entries, &{key, &1}) end)
  end

  defp http_parameter_params(%{"input" => input}) do
    target = input["path"] || input["reqPath"] || input["r"]["fields"]["URL"]
    target |> URI.parse() |> Map.fetch!(:query) |> URI.query_decoder() |> Enum.to_list()
  end

  defp request(ctx, path, params \\ [], status \\ 200) do
    # One assertion covers one attempt, including deliberate HTTP 504s.
    response =
      Req.get!(ctx.url <> "/loki/api/v1" <> path,
        headers: headers(ctx),
        params: params,
        decode_body: false,
        retry: false
      )

    assert response.status == status, response.body
    Pulse.JSON.decode!(response.body)
  end

  defp request_form(ctx, path, params, status \\ 200) do
    response =
      Req.post!(ctx.url <> "/loki/api/v1" <> path,
        headers: headers(ctx),
        form: params,
        decode_body: false,
        retry: false
      )

    assert response.status == status, response.body
    Pulse.JSON.decode!(response.body)
  end

  defp counter_fixture(ctx, samples, noise_start, noise_count) do
    for {time, value} <- samples do
      push(ctx, "c=#{value}", ctx.now + time * @second, %{"app" => "a"})
    end

    for index <- 0..(noise_count - 1) do
      push(ctx, "noise", ctx.now + (noise_start + index * 30) * @second, %{"app" => "a"})
    end

    assert_parquet(ctx, length(samples) + noise_count)
  end

  defp assert_counter(ctx, query, time, expected) do
    assert_metric(ctx, query, time, %{%{"app" => "a"} => expected})
  end

  defp assert_metric(ctx, query, time, expected) do
    {path, params, kind, sample_key} =
      case time do
        {start, finish, step} ->
          {"/query_range",
           [start: to_string(ctx.now + start * @second), end: to_string(ctx.now + finish * @second), step: step],
           "matrix", "values"}

        time ->
          {"/query", [time: to_string(ctx.now + time * @second)], "vector", "value"}
      end

    params = [query: query] ++ params
    response = request(ctx, path, params)
    assert response["data"]["resultType"] == kind

    series =
      for {labels, expected_points} <- expected, expected_points != [] do
        points = for {time, value} <- expected_points, do: [(ctx.now + time * @second) / @second, value]
        samples = if kind == "vector", do: List.first(points), else: points
        %{"metric" => labels, sample_key => samples}
      end

    assert Enum.sort(response["data"]["result"]) == Enum.sort(series)
    assert request_form(ctx, path, params) == response
    assert_parquet_read(ctx)
  end

  defp query_limits(ctx, policy), do: Map.put(ctx, :extra_headers, [{"x-loki-query-limits", policy}])

  defp tail(ctx, expression, params) do
    path = "/loki/api/v1/tail?" <> URI.encode_query([{"query", expression} | params])
    WebSocketClient.connect(URI.parse(ctx.url).port, path, headers(ctx))
  end

  # Receive frames, not timers or storage polls. Like upstream's collector,
  # retain every entry, including duplicates, until the expected count arrives.
  defp tail_values(socket, count, entries \\ []) do
    response = WebSocketClient.next_json(socket, 10_000)
    entries = entries ++ Enum.flat_map(response["streams"], & &1["values"])
    assert length(entries) <= count

    if length(entries) == count,
      do: entries,
      else: tail_values(socket, count, entries)
  end

  defp finite_reads do
    for {path, params} <- [
          {"/query", []},
          {"/query_range", []},
          {"/query_range", [{"query", ~s'count_over_time({job="fake"}[1s])'}, {"step", "1"}]},
          {"/labels", []},
          {"/label/job/values", []},
          {"/series", [{"match[]", ~s({job="fake"})}]},
          {"/index/stats", []},
          {"/index/volume", []},
          {"/index/volume", [{"aggregateBy", "labels"}]},
          {"/index/volume_range", [{"step", "1s"}]},
          {"/index/volume_range", [{"aggregateBy", "labels"}, {"step", "1s"}]},
          {"/detected_labels", []},
          {"/detected_fields", []},
          {"/detected_field/foo/values", []},
          {"/patterns", []}
        ] do
      params = if List.keymember?(params, "query", 0), do: params, else: [{"query", ~s({job="fake"})} | params]
      {path, params}
    end
  end

  defp categorize(ctx), do: Map.put(ctx, :extra_headers, [{"x-loki-response-encoding-flags", "categorize-labels"}])

  defp flattened_entries(response) do
    for stream <- response["data"]["result"], value <- stream["values"] do
      [timestamp, line | rest] = value
      categories = List.first(rest) || %{}

      labels =
        stream["stream"]
        |> Map.merge(Map.get(categories, "structuredMetadata", %{}))
        |> Map.merge(Map.get(categories, "parsed", %{}))

      {timestamp, line, labels}
    end
    |> Enum.frequencies()
  end

  defp range(ctx), do: [{"start", to_string(ctx.now - @week)}, {"end", to_string(ctx.now + @second)}]
  defp query(ctx, query), do: request(ctx, "/query_range", [{"query", query} | range(ctx)])
  defp instant(ctx, query), do: request(ctx, "/query", query: query, time: to_string(ctx.now + @second))

  defp lines(response) do
    response["data"]["result"]
    |> Enum.flat_map(fn stream -> Enum.map(stream["values"], &Enum.at(&1, 1)) end)
    |> Enum.sort()
  end

  defp assert_streams(response, expected) do
    assert response["data"]["resultType"] == "streams"

    actual =
      Enum.map(response["data"]["result"], fn stream ->
        {stream["stream"], Enum.map(stream["values"], &Enum.at(&1, 1))}
      end)

    assert Enum.sort(actual) == Enum.sort(expected)
    assert Map.get(response["data"], "encodingFlags", []) == []
  end

  defp values(response) do
    assert response["data"]["resultType"] == "vector"
    Map.new(response["data"]["result"], fn series -> {series["metric"], Enum.at(series["value"], 1)} end)
  end

  defp access_streams do
    [
      %{"classification" => "confidential", "env" => "dev", "job" => "varlog"},
      %{"classification" => "secret", "env" => "prod", "job" => "varlog"},
      %{"classification" => "secret", "env" => "dev", "job" => "varlog"},
      %{"job" => "varlog"}
    ]
  end

  defp assert_parquet(ctx, count) do
    objects = Agent.get(ctx.store, & &1.objects)
    segments = Enum.filter(objects, fn {key, _} -> String.ends_with?(key, ".parquet") end)
    assert length(segments) == count

    for {_key, {_etag, bytes}} <- segments do
      assert binary_part(bytes, 0, 4) == "PAR1"
      assert binary_part(bytes, byte_size(bytes) - 4, 4) == "PAR1"
    end
  end

  defp assert_parquet_read(ctx),
    do: assert(Agent.get(ctx.store, &Enum.any?(&1.reads, fn key -> String.ends_with?(key, ".parquet") end)))

  defp refute_parquet_read(ctx),
    do: refute(Agent.get(ctx.store, &Enum.any?(&1.reads, fn key -> String.ends_with?(key, ".parquet") end)))
end
