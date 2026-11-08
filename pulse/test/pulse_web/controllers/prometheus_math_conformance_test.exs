defmodule PulseWeb.PrometheusMathConformanceTest do
  use PulseWeb.ConnCase, async: true

  alias Pulse.Auth.SharedSecret
  alias Pulse.PromQL.Evaluator
  alias Pulse.Record.MetricSample
  alias Pulse.Record.NativeHistogram
  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Storage.Memory
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Test.CompactionStore

  @directory Path.expand("../../fixtures/promql/mimir", __DIR__)

  setup %{adapter: adapter} do
    Runtime.put_env(:pulse, Storage, adapter: adapter)

    store =
      if adapter == S3 do
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
        {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

        Runtime.put_env(:pulse, S3, %{
          bucket: "pulse",
          endpoint: "http://127.0.0.1:#{port}",
          region: "us-east-1",
          access_key_id: "test-#{System.unique_integer([:positive])}",
          secret_access_key: "test",
          allow_http: true,
          refresh_stale_ms: 0
        })

        start_supervised!(ManifestSupervision)
        store
      end

    {:ok, store: store}
  end

  for adapter <- [Memory, S3],
      {file, count} <- [
        {"upstream-math.test", 25},
        {"upstream-absence.test", 15},
        {"upstream-timestamp.test", 7},
        {"upstream-absence-over-time.test", 27},
        {"upstream-label-replace.test", 11},
        {"mimir-label-replace-regex-error.test", 2},
        {"upstream-staleness.test", 17},
        {"upstream-selectors.test", 31},
        {"upstream-collision.test", 2},
        {"mimir-staleness.test", 2},
        {"mimir-subqueries.test", 25},
        {"mimir-math.test", 7},
        {"collision.test", 4},
        {"upstream-clamp.test", 27},
        {"mimir-clamp.test", 9},
        {"upstream-presence.test", 19},
        {"mimir-presence.test", 3},
        {"upstream-last.test", 1},
        {"mimir-last.test", 3},
        {"upstream-first.test", 1},
        {"upstream-endpoint-timestamps.test", 9},
        {"mimir-endpoint-timestamps.test", 6},
        {"upstream-transitions.test", 20},
        {"mimir-transitions.test", 1},
        {"upstream-regression.test", 11},
        {"mimir-regression.test", 1},
        {"mimir-rate-name-annotations.test", 3},
        {"mimir-prefilter-cardinality.test", 2},
        {"mimir-nan-ranking.test", 2},
        {"upstream-mad.test", 7},
        {"mimir-mad.test", 8},
        {"upstream-extremum-timestamps.test", 2},
        {"mimir-extremum-timestamps.test", 8},
        {"upstream-label-join.test", 10},
        {"mimir-label-join.test", 12},
        {"upstream-range-quantile.test", 13},
        {"mimir-range-quantile.test", 2},
        {"upstream-smoothing.test", 4},
        {"mimir-smoothing.test", 6},
        {"upstream-angles.test", 9},
        {"mimir-angles.test", 3},
        {"upstream-inverse-trig.test", 3},
        {"mimir-inverse-trig.test", 5},
        {"upstream-trig.test", 3},
        {"mimir-trig.test", 3},
        {"upstream-hyperbolic.test", 3},
        {"mimir-hyperbolic.test", 3},
        {"upstream-inverse-hyperbolic.test", 3},
        {"mimir-inverse-hyperbolic.test", 4},
        {"upstream-calendar.test", 32},
        {"mimir-calendar.test", 34},
        {"upstream-label-sort.test", 11},
        {"mimir-label-sort.test", 8},
        {"upstream-atan2.test", 4},
        {"mimir-atan2.test", 32},
        {"upstream-sort-warnings.test", 5},
        {"mimir-sort-histograms.test", 7},
        {"upstream-query-context.test", 33},
        {"upstream-scalar.test", 3},
        {"upstream-scalar-extrema.test", 14},
        {"mimir-scalar-extrema.test", 4},
        {"upstream-ranking-histogram-annotations.test", 12},
        {"upstream-range-extrema.test", 8},
        {"upstream-range-dispersion.test", 9},
        {"upstream-aggregation-extrema.test", 8},
        {"upstream-dispersion.test", 36},
        {"upstream-value-count.test", 10},
        {"mimir-value-count.test", 4},
        {"upstream-aggregate-quantile.test", 11},
        {"mimir-aggregate-quantile.test", 27},
        {"upstream-time-anchors.test", 78},
        {"upstream-time-duration.test", 3},
        {"upstream-time-offset.test", 7},
        {"upstream-time-subquery.test", 7},
        {"upstream-limit.test", 37},
        {"mimir-limit.test", 93},
        {"upstream-duration-expressions.test", 59},
        {"upstream-default-subquery.test", 12},
        {"upstream-default-subquery-empty.test", 2},
        {"upstream-string-results.test", 5},
        {"upstream-range-results.test", 5},
        {"upstream-histogram-annotations.test", 4},
        {"upstream-histogram-nan.test", 8},
        {"upstream-histogram-nan-multi.test", 20},
        {"upstream-histogram-quantiles.test", 4},
        {"upstream-histogram-fractions.test", 3},
        {"upstream-histogram-extrapolation.test", 8},
        {"upstream-idelta.test", 10},
        {"upstream-irate.test", 11},
        {"upstream-delta.test", 4},
        {"upstream-float-delta-boundaries.test", 7},
        {"upstream-subquery-reset-hints.test", 2},
        {"upstream-custom-histogram-arithmetic.test", 17},
        {"upstream-histogram-range-aggregation.test", 20},
        {"upstream-histogram-group-aggregation.test", 3},
        {"upstream-histogram-counter-annotations.test", 7},
        {"upstream-histogram-precision.test", 32},
        {"upstream-histogram-scaling.test", 25},
        {"upstream-histogram-trimming.test", 124},
        {"upstream-histogram-properties.test", 22},
        {"upstream-histogram-bucket-retention.test", 15},
        {"upstream-histogram-fundamentals.test", 65},
        {"upstream-histogram-interpolation.test", 150},
        {"mimir-histogram-binary.test", 25},
        {"upstream-classic-histograms.test", 183},
        {"mimir-empty-load-labels.test", 2},
        {"mimir-histogram-quantiles.test", 5}
      ] do
    @tag adapter: adapter
    @tag subquery_reset_hints: file == "upstream-subquery-reset-hints.test"
    @tag subquery_reset_affected:
           file in ~w(upstream-histogram-counter-annotations.test upstream-histogram-extrapolation.test upstream-time-subquery.test mimir-subqueries.test)
    @tag empty_load_labels: file == "mimir-empty-load-labels.test"
    @tag empty_load_labels_affected:
           file in ~w(upstream-classic-histograms.test mimir-histogram-quantiles.test upstream-absence.test upstream-absence-over-time.test upstream-selectors.test)
    @tag time_modifiers: String.starts_with?(file, "upstream-time-")
    @tag sampling: String.ends_with?(file, "-limit.test")
    @tag scalar_batch: file == "upstream-scalar.test"
    @tag ranking_histogram_annotations: file == "upstream-ranking-histogram-annotations.test"
    @tag range_extrema: file == "upstream-range-extrema.test"
    @tag range_dispersion: file == "upstream-range-dispersion.test"
    @tag aggregation_extrema: file == "upstream-aggregation-extrema.test"
    @tag rate_name_annotations: file == "mimir-rate-name-annotations.test"
    @tag prefilter_cardinality: file == "mimir-prefilter-cardinality.test"
    @tag nan_ranking: file == "mimir-nan-ranking.test"
    @tag range_sort_histograms: file == "mimir-sort-histograms.test"
    @tag range_sort_affected: file in ~w(upstream-sort-warnings.test upstream-label-sort.test mimir-label-sort.test)
    @tag omitted_repetitions: file == "upstream-float-delta-boundaries.test"
    @tag omitted_repetitions_affected:
           file in ~w(upstream-delta.test upstream-idelta.test upstream-irate.test upstream-regression.test mimir-rate-name-annotations.test upstream-histogram-counter-annotations.test upstream-histogram-extrapolation.test)
    @tag label_replace_regex_error: file == "mimir-label-replace-regex-error.test"
    @tag label_replace_regex_affected: file in ~w(upstream-label-replace.test mimir-label-replace-regex-error.test)
    @tag prefilter_cardinality_affected: file in ~w(upstream-atan2.test mimir-atan2.test mimir-histogram-binary.test)
    @tag rate_name_affected:
           file in ~w(upstream-regression.test upstream-histogram-counter-annotations.test upstream-histogram-extrapolation.test upstream-histogram-range-aggregation.test upstream-custom-histogram-arithmetic.test upstream-irate.test)
    @tag duration_expressions: file == "upstream-duration-expressions.test"
    @tag grammar_batch: String.starts_with?(file, "upstream-default-subquery")
    @tag result_types_batch: String.ends_with?(file, "-results.test")
    @tag absence_timestamp_batch: file in ~w(upstream-math.test upstream-absence.test upstream-timestamp.test)
    @tag absence_replace_staleness_batch:
           file in ~w(upstream-absence-over-time.test upstream-label-replace.test upstream-staleness.test)
    @tag complete_selector_subquery_batch:
           file in ~w(upstream-selectors.test upstream-collision.test mimir-staleness.test mimir-subqueries.test collision.test)
    @tag histogram_annotations_batch: String.starts_with?(file, "upstream-histogram-")
    @tag histogram_quantiles_batch: String.ends_with?(file, "-histogram-quantiles.test")
    @tag histogram_fraction_batch: String.ends_with?(file, "-histogram-fractions.test")
    @tag histogram_nan_multi_batch: String.ends_with?(file, "-histogram-nan-multi.test")
    @tag histogram_extrapolation_batch: String.ends_with?(file, "-histogram-extrapolation.test")
    @tag idelta_batch: file == "upstream-idelta.test"
    @tag irate_batch: file == "upstream-irate.test"
    @tag delta_batch: file == "upstream-delta.test"
    @tag custom_arithmetic_batch: file == "upstream-custom-histogram-arithmetic.test"
    @tag histogram_aggregation_batch: String.ends_with?(file, "-aggregation.test")
    @tag histogram_counter_batch: file == "upstream-histogram-counter-annotations.test"
    @tag histogram_precision_batch: file == "upstream-histogram-precision.test"
    @tag histogram_scaling_batch: file == "upstream-histogram-scaling.test"
    @tag histogram_trimming_batch: file == "upstream-histogram-trimming.test"
    @tag histogram_interpolation_batch: file == "upstream-histogram-interpolation.test"
    @tag histogram_binary_batch: file == "mimir-histogram-binary.test"
    @tag classic_histograms_batch: file == "upstream-classic-histograms.test"
    @tag histogram_properties_batch:
           file in [
             "upstream-histogram-properties.test",
             "upstream-histogram-bucket-retention.test",
             "upstream-histogram-fundamentals.test"
           ]
    test "Mimir #{file} through HTTP and #{inspect(adapter)}" do
      blocks =
        @directory
        |> Path.join(unquote(file))
        |> File.read!()
        |> String.replace(~r/^[ \t]*#.*\n/m, "")
        |> String.trim()
        |> then(&Regex.split(~r/(?=^(?:load(?:_with_nhcb)?|clear|eval(?:_fail|_ordered)?)\b)/m, &1, trim: true))

      {_, count} =
        Enum.reduce(blocks, {"fixture-0", 0}, fn block, {tenant, count} ->
          [command | body] = block |> String.split("\n", trim: true) |> Enum.map(&String.trim/1)

          case String.split(command, " ", parts: 2) do
            ["clear"] ->
              {"fixture-#{count}", count}

            [load, interval] when load in ["load", "load_with_nhcb"] ->
              records = Enum.flat_map(body, &records(&1, nanoseconds(interval)))
              records = if load == "load_with_nhcb", do: records ++ classic_histograms(records), else: records
              assert :ok = Storage.append(:metrics, tenant, records)
              {tenant, count}

            [eval, _] when eval in ["eval", "eval_fail", "eval_ordered"] ->
              check(command, body, tenant)
              {tenant, count + 1}
          end
        end)

      assert count == unquote(count)
    end
  end

  for adapter <- [Memory, S3], path <- ["/api/v1/query", "/api/v1/query_range"] do
    @tag adapter: adapter, nan_ranking: true
    test "NaN ranking and sampling isolation through authenticated #{path} and #{inspect(adapter)}",
         %{store: store} do
      Runtime.put_env(:pulse, Pulse.Auth,
        module: SharedSecret,
        tokens: %{
          "nan-ranking" => "sha256$" <> Base.encode16(:crypto.hash(:sha256, "ranking-token"), case: :lower)
        }
      )

      source = [~s(ranking{id="one"} 1), ~s(ranking{id="two"} 2)]
      assert :ok = Storage.append(:metrics, "nan-ranking", Enum.flat_map(source, &records(&1, 1_000_000_000)))

      params =
        if unquote(path) == "/api/v1/query",
          do: %{time: "0"},
          else: %{start: "0", end: "0", step: "1s"}

      before_requests = if store, do: Agent.get(store, & &1.requests)

      denied =
        build_conn()
        |> put_req_header("x-scope-orgid", "nan-ranking")
        |> get(unquote(path), Map.put(params, :query, "topk(NaN, ranking)"))

      assert %{"status" => "error", "errorType" => "unauthorized", "error" => "unauthorized"} ==
               json_response(denied, 401)

      if store, do: assert(Agent.get(store, & &1.requests) == before_requests)

      for {query, op} <- [
            {"topk(0 / 0, ranking)", "topk"},
            {"bottomk(NaN, missing_ranking)", "bottomk"},
            {"bottomk(scalar(ranking), ranking)", "bottomk"}
          ] do
        conn =
          build_conn()
          |> put_req_header("x-scope-orgid", "nan-ranking")
          |> put_req_header("authorization", "Bearer ranking-token")
          |> get(unquote(path), Map.put(params, :query, query))

        assert %{
                 "status" => "error",
                 "errorType" => "execution",
                 "error" => "parameter value is NaN for " <> op
               } == json_response(conn, 422)
      end

      for query <- ["limitk(NaN, ranking)", "topk(Inf, ranking)"] do
        conn =
          build_conn()
          |> put_req_header("x-scope-orgid", "nan-ranking")
          |> put_req_header("authorization", "Bearer ranking-token")
          |> get(unquote(path), Map.put(params, :query, query))

        assert %{
                 "status" => "error",
                 "errorType" => "execution",
                 "error" => "Ranking requires a scalar other than NaN and below the signed int64 maximum."
               } == json_response(conn, 422)
      end

      query = "topk(1, ranking)"

      conn =
        build_conn()
        |> put_req_header("x-scope-orgid", "nan-ranking")
        |> put_req_header("authorization", "Bearer ranking-token")
        |> get(unquote(path), Map.put(params, :query, query))

      expected = [~s(ranking{id="two"} 2), "expect no_warn", "expect no_info"]
      assert_success(conn, expected, unquote(path), query, 0, 1)
    end
  end

  for adapter <- [Memory, S3] do
    @tag adapter: adapter, subquery_reset_hints: true
    test "subqueries clear only counter hints and preserve direct inputs through authenticated #{inspect(adapter)}", %{
      store: store
    } do
      Runtime.put_env(:pulse, Pulse.Auth,
        module: SharedSecret,
        tokens: %{"subquery-hints" => "sha256$" <> Base.encode16(:crypto.hash(:sha256, "hint-token"), case: :lower)}
      )

      source = [
        "yes {{count:10}} {{count:12 counter_reset_hint:reset}} {{count:14 counter_reset_hint:not_reset}}",
        "no {{count:10}} {{count:4 counter_reset_hint:not_reset}} {{count:6 counter_reset_hint:not_reset}}",
        "unknown {{count:10}} {{count:4}} {{count:6}}",
        "gauge {{count:10 counter_reset_hint:gauge}} {{count:4 counter_reset_hint:gauge}} {{count:6 counter_reset_hint:gauge}}",
        "floats 0 1 2"
      ]

      assert :ok = Storage.append(:metrics, "subquery-hints", Enum.flat_map(source, &records(&1, 1_000_000_000)))
      before_requests = if store, do: Agent.get(store, & &1.requests)

      for path <- ["/api/v1/query", "/api/v1/query_range"] do
        denied = build_conn() |> put_req_header("x-scope-orgid", "subquery-hints") |> get(path, query: "vector(1)")
        assert denied.status == 401
      end

      if store, do: assert(Agent.get(store, & &1.requests) == before_requests)

      for {query, expected} <- [
            {"vector(1)", ["{} 1", "expect no_warn"]},
            {"resets(yes[3s])", ["{} 1", "expect no_warn"]},
            {"resets(yes[3s:500ms])", ["{} 0", "expect no_warn"]},
            {"resets(no[3s])", ["{} 0", "expect no_warn"]},
            {"resets(no[3s:1s])", ["{} 1", "expect no_warn"]},
            {"resets(unknown[3s:500ms])", ["{} 1", "expect no_warn"]},
            {"histogram_count(rate(gauge[3s:1s]))",
             ["{} 3", ~s(expect warn msg: PromQL warning: this native histogram metric is not a counter: "gauge")]},
            {"sum_over_time(floats[3s:1s])", ["{} 3", "expect no_warn"]}
          ],
          {path, params} <- [
            {"/api/v1/query", %{time: "2"}},
            {"/api/v1/query_range", %{start: "2", end: "2", step: "1s"}}
          ] do
        conn =
          build_conn()
          |> put_req_header("x-scope-orgid", "subquery-hints")
          |> put_req_header("authorization", "Bearer hint-token")
          |> get(path, Map.put(params, :query, query))

        assert_success(conn, expected ++ ["expect no_info"], path, query, 2, 1)
      end
    end

    @tag adapter: adapter, subquery_reset_hints: true
    test "subquery counter hint normalization keeps query-local state and shared budgets through #{inspect(adapter)}" do
      source = "yes {{count:10}} {{count:12 counter_reset_hint:reset}} {{count:14}}"
      assert :ok = Storage.append(:metrics, "subquery-budget", records(source, 1_000_000_000))
      opts = %{end_ts_ns: 2_000_000_000}
      direct = {"direct", "resets(yes[3s])", opts}
      subquery = {"subquery", "resets(yes[3s:500ms])", opts}

      for batch <- [[direct, subquery], [subquery, direct]] do
        assert {:ok, results} = Evaluator.query_batch(batch, "subquery-budget", fn result, _ -> {:ok, result} end)
        assert [%{"value" => [2.0, "1"]}] = results["direct"]["data"]["result"]
        assert [%{"value" => [2.0, "0"]}] = results["subquery"]["data"]["result"]
      end

      # Five inner points and the one-point result they produce fit once, but
      # two sources share the cap: the first result stays held for the batch.
      Runtime.put_env(:pulse, Evaluator, max_materialized_samples: 6)
      assert {:ok, _} = Evaluator.query_batch([subquery], "subquery-budget", fn result, _ -> {:ok, result} end)

      assert {:error, :query_intermediate_limit} =
               Evaluator.query_batch([subquery, put_elem(subquery, 0, "second")], "subquery-budget", fn _, _ ->
                 flunk("partial over-budget subquery batch")
               end)

      Runtime.put_env(:pulse, Evaluator, max_work: 1)
      assert {:error, :query_work_limit} = Evaluator.query(elem(subquery, 1), "subquery-budget", opts)
    end
  end

  for adapter <- [Memory, S3], path <- ["/api/v1/query", "/api/v1/query_range"] do
    @tag adapter: adapter, empty_load_labels: true
    test "load labels normalize only empty values through authenticated #{path} and #{inspect(adapter)}", %{
      store: store
    } do
      Runtime.put_env(:pulse, Pulse.Auth,
        module: SharedSecret,
        tokens: %{
          "load-labels" => "sha256$" <> Base.encode16(:crypto.hash(:sha256, "load-token"), case: :lower)
        }
      )

      source = [
        ~s(producer_labels{empty="",kept="value","κλειδί"="雪"} 7),
        ~s(producer_empty{first="",second=""} 8)
      ]

      assert :ok = Storage.append(:metrics, "load-labels", Enum.flat_map(source, &records(&1, 1_000_000_000)))
      before_requests = if store, do: Agent.get(store, & &1.requests)

      denied =
        build_conn()
        |> put_req_header("x-scope-orgid", "load-labels")
        |> get(unquote(path), query: "producer_labels")

      assert denied.status == 401
      if store, do: assert(Agent.get(store, & &1.requests) == before_requests)

      for {query, expected} <- [
            {"vector(1)", ["{} 1"]},
            {"producer_labels", [~s(producer_labels{kept="value","κλειδί"="雪"} 7)]},
            {"producer_empty", ["producer_empty 8"]}
          ] do
        params =
          if unquote(path) == "/api/v1/query",
            do: %{query: query, time: "0"},
            else: %{query: query, start: "0", end: "0", step: "1s"}

        conn =
          build_conn()
          |> put_req_header("x-scope-orgid", "load-labels")
          |> put_req_header("authorization", "Bearer load-token")
          |> get(unquote(path), params)

        response = json_response(conn, 200)
        assert Map.get(response, "warnings", []) == []
        assert Map.get(response, "infos", []) == []
        assert_query_data(response["data"], expected, unquote(path), query, 0, 1)
      end
    end
  end

  for adapter <- [Memory, S3] do
    @tag adapter: adapter, omitted_repetitions: true
    test "omitted and value repetition boundaries through authenticated HTTP and #{inspect(adapter)}", %{
      store: store
    } do
      Runtime.put_env(:pulse, Pulse.Auth,
        module: SharedSecret,
        tokens: %{
          "repeat-boundaries" => "sha256$" <> Base.encode16(:crypto.hash(:sha256, "repeat-token"), case: :lower)
        }
      )

      source = [
        ~s(repeat_boundary{kind="omitted-zero"} _x0 7),
        ~s(repeat_boundary{kind="omitted-one"} _x1 7),
        ~s(repeat_boundary{kind="float-zero"} 7x0),
        ~s(repeat_boundary{kind="float-one"} 7x1),
        ~s(repeat_boundary{kind="histogram-zero"} {{count:2 sum:3}}x0),
        ~s(repeat_boundary{kind="histogram-one"} {{count:2 sum:3}}x1)
      ]

      assert :ok = Storage.append(:metrics, "repeat-boundaries", Enum.flat_map(source, &records(&1, 1_000_000_000)))
      before_requests = if store, do: Agent.get(store, & &1.requests)

      for path <- ["/api/v1/query", "/api/v1/query_range"] do
        denied = build_conn() |> put_req_header("x-scope-orgid", "repeat-boundaries") |> get(path, query: "vector(1)")
        assert denied.status == 401
      end

      if store, do: assert(Agent.get(store, & &1.requests) == before_requests)

      for {query, range_expected, instant_expected} <- [
            {"count_over_time(repeat_boundary[3s])",
             [
               ~s({kind="omitted-zero"} 1 1 1),
               ~s({kind="omitted-one"} _ 1 1),
               ~s({kind="float-zero"} 1 1 1),
               ~s({kind="float-one"} 1 2 2),
               ~s({kind="histogram-zero"} 1 1 1),
               ~s({kind="histogram-one"} 1 2 2)
             ],
             [
               ~s({kind="omitted-zero"} 1),
               ~s({kind="omitted-one"} 1),
               ~s({kind="float-zero"} 1),
               ~s({kind="float-one"} 2),
               ~s({kind="histogram-zero"} 1),
               ~s({kind="histogram-one"} 2)
             ]},
            {"sum_over_time(repeat_boundary[3s])",
             [
               ~s({kind="omitted-zero"} 7 7 7),
               ~s({kind="omitted-one"} _ 7 7),
               ~s({kind="float-zero"} 7 7 7),
               ~s({kind="float-one"} 7 14 14),
               ~s({kind="histogram-zero"} {{count:2 sum:3}}x2),
               ~s({kind="histogram-one"} {{count:2 sum:3}} {{count:4 sum:6}}x1)
             ],
             [
               ~s({kind="omitted-zero"} 7),
               ~s({kind="omitted-one"} 7),
               ~s({kind="float-zero"} 7),
               ~s({kind="float-one"} 14),
               ~s({kind="histogram-zero"} {{count:2 sum:3}}),
               ~s({kind="histogram-one"} {{count:4 sum:6}})
             ]}
          ],
          {path, params, expected, first} <- [
            {"/api/v1/query_range", %{start: "0", end: "2", step: "1s"}, range_expected, 0},
            {"/api/v1/query", %{time: "1"}, instant_expected, 1}
          ] do
        conn =
          build_conn()
          |> put_req_header("x-scope-orgid", "repeat-boundaries")
          |> put_req_header("authorization", "Bearer repeat-token")
          |> get(path, Map.put(params, :query, query))

        response = json_response(conn, 200)
        assert Map.get(response, "warnings", []) == []
        assert Map.get(response, "infos", []) == []
        assert_query_data(response["data"], expected, path, query, first, 1)
      end
    end
  end

  for adapter <- [Memory, S3] do
    @tag adapter: adapter, range_sort_histograms: true
    test "range sorting omits only value-sort histograms through authenticated HTTP and #{inspect(adapter)}", %{
      store: store
    } do
      Runtime.put_env(:pulse, Pulse.Auth,
        module: SharedSecret,
        tokens: %{"range-sort" => "sha256$" <> Base.encode16(:crypto.hash(:sha256, "sort-token"), case: :lower)}
      )

      source = [
        ~s(typed{kind="mixed"} 1 {{count:2 sum:3}} -0 NaN +Inf -Inf),
        ~s(typed{kind="hist"} {{count:2 sum:3}}x5),
        ~s(typed{kind="float"} 6 5 4 3 2 1)
      ]

      assert :ok = Storage.append(:metrics, "range-sort", Enum.flat_map(source, &records(&1, 1_000_000_000)))
      before_requests = if store, do: Agent.get(store, & &1.requests)

      for path <- ["/api/v1/query", "/api/v1/query_range"] do
        denied = build_conn() |> put_req_header("x-scope-orgid", "range-sort") |> get(path, query: "sort(typed)")
        assert denied.status == 401
      end

      if store, do: assert(Agent.get(store, & &1.requests) == before_requests)

      for {query, label_sort?} <- [
            {"sort(typed)", false},
            {"sort_desc(typed)", false},
            {~s|sort_by_label(typed, "kind")|, true},
            {~s|sort_by_label_desc(typed, "kind")|, true}
          ],
          {path, params, first, step, range?} <- [
            {"/api/v1/query_range", %{start: "0", end: "5", step: "1s"}, 0, 1, true},
            {"/api/v1/query_range", %{start: "1", end: "1", step: "1s"}, 1, 1, false},
            {"/api/v1/query", %{time: "1"}, 1, 1, false}
          ] do
        conn =
          build_conn()
          |> put_req_header("x-scope-orgid", "range-sort")
          |> put_req_header("authorization", "Bearer sort-token")
          |> get(path, Map.put(params, :query, query))

        response = json_response(conn, 200)

        expected =
          case {label_sort?, range?} do
            {true, true} ->
              source

            {false, true} ->
              [~s(typed{kind="mixed"} 1 _ -0 NaN +Inf -Inf), ~s(typed{kind="float"} 6 5 4 3 2 1)]

            {true, false} ->
              [
                ~s(typed{kind="mixed"} {{count:2 sum:3}}),
                ~s(typed{kind="hist"} {{count:2 sum:3}}),
                ~s(typed{kind="float"} 5)
              ]

            {false, false} ->
              [~s(typed{kind="float"} 5)]
          end

        assert_query_data(response["data"], expected, path, query, first, step)
        assert Map.get(response, "infos", []) == []

        warnings =
          if range?,
            do: ["PromQL warning: sort is ineffective for range queries since results are always ordered by labels"],
            else: []

        assert Map.get(response, "warnings", []) == warnings

        if range? do
          mixed = Enum.find(response["data"]["result"], &(&1["metric"]["kind"] == "mixed"))
          assert [2.0, "-0"] in mixed["values"]
        end
      end
    end

    @tag adapter: adapter, range_sort_histograms: true
    test "range sort batches isolate filtering and warnings and preserve budgets through #{inspect(adapter)}" do
      samples =
        Enum.flat_map(
          [~s(typed{kind="mixed"} 1 {{count:2 sum:3}} 2), ~s(typed{kind="hist"} {{count:2 sum:3}}x2)],
          &records(&1, 1_000_000_000)
        )

      assert :ok = Storage.append(:metrics, "sort-batch", samples)
      range = %{start_ts_ns: 0, end_ts_ns: 2_000_000_000, step_ns: 1_000_000_000}

      queries = [
        {"value", "sort(typed)", range},
        {"label", ~s|sort_by_label(typed, "kind")|, range},
        {"instant", "sort_desc(typed)", %{end_ts_ns: 1_000_000_000}},
        {"raw", "typed", range}
      ]

      for batch <- [queries, Enum.reverse(queries)] do
        assert {:ok, results} = Evaluator.query_batch(batch, "sort-batch", fn result, _ -> {:ok, result} end)

        assert [%{"metric" => %{"__name__" => "typed", "kind" => "mixed"}, "values" => [[+0.0, "1"], [2.0, "2"]]}] =
                 results["value"]["data"]["result"]

        assert results["label"]["data"] == results["raw"]["data"]
        assert length(results["label"]["data"]["result"]) == 2
        assert results["instant"]["data"]["result"] == []
        assert length(results["value"]["warnings"]) == 1
        assert results["label"]["warnings"] == results["value"]["warnings"]
        refute Map.has_key?(results["instant"], "warnings")
        refute Map.has_key?(results["raw"], "warnings")
      end

      for {limits, reason} <- [
            {[max_samples: 1], :query_sample_limit},
            {[max_work: 1], :query_work_limit},
            {[max_result_points: 1], :query_result_limit}
          ] do
        Runtime.put_env(:pulse, Evaluator, limits)
        assert {:error, ^reason} = Evaluator.query("sort(typed)", "sort-batch", range)

        assert {:error, ^reason} =
                 Evaluator.query_batch(queries, "sort-batch", fn _, _ -> flunk("partial over-budget sort batch") end)
      end

      # Even an empty projected result pays for every selected histogram.
      Runtime.put_env(:pulse, Evaluator, max_samples: 2)

      assert {:error, :query_sample_limit} =
               Evaluator.query(~s|sort(typed{kind="hist"})|, "sort-batch", range)
    end

    @tag adapter: adapter, label_replace_regex_error: true
    test "label_replace regex diagnostics preserve admission and bounded reflection through #{inspect(adapter)}", %{
      store: store
    } do
      Runtime.put_env(:pulse, Pulse.Auth,
        module: SharedSecret,
        tokens: %{
          "regex-errors" => "sha256$" <> Base.encode16(:crypto.hash(:sha256, "owned-regex-token"), case: :lower)
        }
      )

      before_requests = if store, do: Agent.get(store, & &1.requests)

      for {path, params} <- [
            {"/api/v1/query", %{time: "0"}},
            {"/api/v1/query_range", %{start: "0", end: "0", step: "1s"}}
          ] do
        query = ~s|label_replace(series, "export", "$1", "label", "[.*")|

        conn =
          build_conn() |> put_req_header("x-scope-orgid", "regex-errors") |> get(path, Map.put(params, :query, query))

        assert json_response(conn, 401) == %{
                 "status" => "error",
                 "errorType" => "unauthorized",
                 "error" => "unauthorized"
               }

        for {destination, regex, message} <- [
              {"export", "[.*", "invalid regular expression in label_replace(): [.*"},
              {"export", "(.*", "invalid regular expression in label_replace(): (.*"},
              {"export", "é[", "invalid regular expression in label_replace(): é["},
              {"export", String.duplicate("a", 1023) <> "[",
               "invalid regular expression in label_replace(): " <> String.duplicate("a", 1023) <> "["},
              {"", "[.*", "Invalid or unsupported query parameters."},
              {"", "(.*)", "Invalid or unsupported query parameters."},
              {"export", String.duplicate("a", 1024) <> "[", "Invalid or unsupported query parameters."},
              {"export", String.duplicate("é", 512) <> "[", "Invalid or unsupported query parameters."}
            ] do
          query = "label_replace(series, #{JSON.encode!(destination)}, \"$1\", \"label\", #{JSON.encode!(regex)})"

          conn =
            build_conn()
            |> put_req_header("x-scope-orgid", "regex-errors")
            |> put_req_header("authorization", "Bearer owned-regex-token")
            |> get(path, Map.put(params, :query, query))

          assert json_response(conn, 400) == %{"status" => "error", "errorType" => "bad_data", "error" => message}
        end
      end

      if store, do: assert(Agent.get(store, & &1.requests) == before_requests)
    end

    @tag adapter: adapter
    @tag :ranking_histogram_annotations
    test "Pulse ranking notices describe only executed histogram filters through #{inspect(adapter)}" do
      samples =
        Enum.flat_map(
          [
            ~s(ranking{kind="histogram"} {{schema:0 sum:4 count:4}}x2),
            ~s(ranking{kind="other_histogram"} {{schema:0 sum:2 count:2}}x2),
            ~s(ranking{kind="float"} 3 3),
            ~s(ranking_switch {{schema:0 sum:4 count:4}} 3)
          ],
          &records(&1, 60_000_000_000)
        )

      assert :ok = Storage.append(:metrics, "ranking-notices", samples)

      for op <- ~w(topk bottomk) do
        # Instant upstream ranking stops before filtering for nonpositive k.
        # Pulse also keeps this no-notice policy for range steps with zero k.
        for k <- ["0", "-1", "0.9"] do
          check("eval instant at 0 #{op}(#{k}, ranking)", ["expect no_info"], "ranking-notices")
          check("eval range from 0 to 1m step 1m #{op}(#{k}, ranking)", ["expect no_info"], "ranking-notices")
        end

        notice = "expect info msg: PromQL info: ignored histogram in #{op} aggregation"

        check(
          "eval range from 0 to 1m step 1m #{op}(1, ranking)",
          [notice, ~s(ranking{kind="float"} 3 3)],
          "ranking-notices"
        )

        check(
          "eval instant at 0 #{op}(1, ranking{kind=\"float\"})",
          ["expect no_info", ~s(ranking{kind="float"} 3)],
          "ranking-notices"
        )

        check("eval instant at 0 #{op}(1, ranking_missing)", ["expect no_info"], "ranking-notices")

        check(
          "eval range from 0 to 1m step 1m #{op}(time()/60, ranking_switch)",
          ["expect no_info", ~s(ranking_switch _ 3)],
          "ranking-notices"
        )
      end
    end
  end

  for adapter <- [Memory, S3] do
    @tag adapter: adapter
    @tag :prefilter_cardinality
    test "Pulse checks matched input cardinality before filtering through #{inspect(adapter)}" do
      # Authored adaptations of pinned ours/binary_operators.test:1706-1744.
      # The first setup is unchanged; the second retains the original disjoint
      # lifetimes. Instant adaptations also replay through the range endpoint.
      samples =
        Enum.flat_map(
          [
            ~s(left{pod="a"} 1 2 3 4),
            ~s(left{pod="b"} 5 6 7 8),
            ~s(right 2 2 7 7),
            ~s(left_side_a{env="test", pod="a"} 1 2 _ _),
            ~s(left_side_b{env="test", pod="a"} _ _ 7 8),
            ~s(right_side{env="test", pod="a"} 2 2 7 7)
          ],
          &records(&1, 360_000_000_000)
        )

      assert :ok = Storage.append(:metrics, "prefilter-cardinality", samples)

      # No survivor at 0/18m; only a survives at 6m and only b at 12m. Neither
      # the predicate nor source order may hide the two simultaneous inputs.
      for at <- ~w(0 6m 12m 18m),
          query <- [
            "left == ignoring(pod) right",
            "left == ignoring(pod) group_right right",
            "right == ignoring(pod) left"
          ] do
        check("eval_fail instant at #{at} " <> query, [], "prefilter-cardinality")
      end

      # A populated counterpart with a different signature must not turn
      # unmatched duplicate left signatures into a matching-cardinality error.
      check(
        ~s|eval range from 0 to 18m step 6m left == ignoring(pod) label_replace(right, "env", "absent", "", "")|,
        ["expect no_warn", "expect no_info"],
        "prefilter-cardinality"
      )

      check(
        "eval instant at 6m left == ignoring(pod) absent_right",
        [],
        "prefilter-cardinality"
      )

      # Valid one-to-one input and explicit many-to-one grouping still succeed.
      check(
        ~s|eval instant at 6m left{pod="a"} == ignoring(pod) right|,
        ["left 2"],
        "prefilter-cardinality"
      )

      check(
        ~s|eval instant at 12m left{pod="b"} == ignoring(pod) right|,
        ["left 7"],
        "prefilter-cardinality"
      )

      check(
        "eval range from 0 to 18m step 6m left == ignoring(pod) group_left right",
        [~s(left{pod="a"} _ 2 _ _), ~s(left{pod="b"} _ _ 7 _)],
        "prefilter-cardinality"
      )

      # Including a missing one-side label drops pod. Grouped uniqueness is
      # still about retained output labels, not unfiltered many-side inputs.
      check(
        "eval range from 0 to 18m step 6m left == ignoring(pod) group_left(pod) right",
        ["left _ 2 7 _"],
        "prefilter-cardinality"
      )

      check(
        "eval instant at 6m left != ignoring(pod) group_left(pod) right",
        ["left 6"],
        "prefilter-cardinality"
      )

      check(
        "eval_fail instant at 0 left != ignoring(pod) group_left(pod) right",
        ["expected_fail_message multiple matches for labels: grouping labels must ensure unique matches"],
        "prefilter-cardinality"
      )

      # Source-backed nonoverlap controls: never accumulate matching signatures
      # across evaluation steps, including steps whose comparison is false.
      for {query, expected} <- [
            {~s|{__name__=~"left_side.*"} == ignoring(env) right_side|,
             [~s(left_side_a{pod="a"} _ 2 _ _), ~s(left_side_b{pod="a"} _ _ 7 _)]},
            {~s|{__name__=~"left_side.*"} == bool ignoring(env) right_side|, [~s({pod="a"} 0 1 1 0)]},
            {~s|{__name__=~"left_side.*"} == on(pod) right_side|, [~s({pod="a"} _ 2 7 _)]}
          ] do
        check("eval range from 0 to 18m step 6m " <> query, expected, "prefilter-cardinality")
      end

      for {at, expected} <- [
            {"0", []},
            {"6m", [~s(left_side_a{pod="a"} 2)]},
            {"12m", [~s(left_side_b{pod="a"} 7)]},
            {"18m", []}
          ] do
        check(
          ~s|eval instant at #{at} {__name__=~"left_side.*"} == ignoring(env) right_side|,
          expected,
          "prefilter-cardinality"
        )
      end
    end
  end

  for adapter <- [Memory, S3] do
    @tag adapter: adapter
    @tag :rate_name_annotations
    test "Pulse counter-name infos follow produced float results through #{inspect(adapter)}" do
      # Pinned engine_test.go TestRateIncreaseAnnotations and rateSeriesValidator:
      # validate output floats, not input presence; suffixes and empty names skip.
      # These authored controls are separate from the three unchanged DSL cases.
      samples =
        Enum.flat_map(
          [
            ~s(unsuffixed{id="a"} 0 60 120),
            ~s(unsuffixed{id="b"} 0 60 120),
            ~s(other_bad{id="c"} 0 60 120),
            ~s(valid_total{id="suffix"} 0 60 120),
            ~s(valid_sum{id="suffix"} 0 60 120),
            ~s(valid_count{id="suffix"} 0 60 120),
            ~s(valid_bucket{id="suffix"} 0 60 120),
            ~s(short_bad _ 1),
            ~s(hist_bad {{count:0 sum:0}} {{count:1 sum:1}} {{count:2 sum:2}}),
            ~s(mixed_bad 0 {{count:1 sum:1}} 2),
            ~s(switch_bad 0 60 {{count:2 sum:2}}),
            ~s(nan_bad NaN NaN),
            ~s(infinite_bad 0 Inf),
            ~s(negative_bad 0 -Inf)
          ],
          &records(&1, 60_000_000_000)
        )

      assert :ok = Storage.append(:metrics, "counter-name-infos", samples)

      for op <- ~w(rate increase) do
        notice =
          ~s(PromQL info: metric might not be a counter, name does not end in _total/_sum/_count/_bucket: "unsuffixed")

        for suffix <- ~w(total sum count bucket) do
          check(
            "eval instant at 1m timestamp(#{op}(valid_#{suffix}[61s]))",
            ["expect no_info", "expect no_warn", ~s({id="suffix"} 60)],
            "counter-name-infos"
          )
        end

        # Arithmetic removes the name before the subquery reaches rate/increase.
        check(
          "eval instant at 1m timestamp(#{op}((valid_total + 0)[61s:1m]))",
          ["expect no_info", "expect no_warn", ~s({id="suffix"} 60)],
          "counter-name-infos"
        )

        for {selector, at} <- [{"unsuffixed", "0"}, {"short_bad", "1m"}, {"absent_bad", "1m"}] do
          check(
            "eval instant at #{at} #{op}(#{selector}[61s])",
            ["expect no_info", "expect no_warn"],
            "counter-name-infos"
          )
        end

        check(
          "eval instant at 1m timestamp(#{op}(hist_bad[61s]))",
          ["expect no_info", "expect no_warn", "{} 60"],
          "counter-name-infos"
        )

        check(
          "eval instant at 1m #{op}(mixed_bad[61s])",
          [
            "expect no_info",
            ~s(expect warn msg: PromQL warning: encountered a mix of histograms and floats for metric name "mixed_bad")
          ],
          "counter-name-infos"
        )

        check(
          "eval range from 0 to 2m step 1m timestamp(#{op}(unsuffixed[61s]))",
          ["expect info msg: " <> notice, "expect no_warn", ~s({id="a"} _ 60 120), ~s({id="b"} _ 60 120)],
          "counter-name-infos"
        )

        check(
          "eval range from 0 to 2m step 1m timestamp(#{op}(switch_bad[61s]))",
          [
            ~s(expect info msg: PromQL info: metric might not be a counter, name does not end in _total/_sum/_count/_bucket: "switch_bad"),
            ~s(expect warn msg: PromQL warning: encountered a mix of histograms and floats for metric name "switch_bad"),
            "{} _ 60 _"
          ],
          "counter-name-infos"
        )

        for {name, result} <- [{"nan_bad", "NaN"}, {"infinite_bad", "+Inf"}, {"negative_bad", "-Inf"}] do
          check(
            "eval instant at 1m #{op}(#{name}[61s])",
            [
              ~s(expect info msg: PromQL info: metric might not be a counter, name does not end in _total/_sum/_count/_bucket: "#{name}"),
              "expect no_warn",
              "{} " <> result
            ],
            "counter-name-infos"
          )
        end

        dirty = "timestamp(#{op}(unsuffixed[61s]))"
        clean = "timestamp(#{op}(valid_total[61s]))"
        other = "timestamp(#{op}(other_bad[61s]))"

        # Every HTTP request has a fresh annotation context, even on this worker.
        for _ <- 1..2 do
          check(
            "eval instant at 1m " <> dirty,
            ["expect info msg: " <> notice, ~s({id="a"} 60), ~s({id="b"} 60)],
            "counter-name-infos"
          )

          check(
            "eval instant at 1m " <> clean,
            ["expect no_info", ~s({id="suffix"} 60)],
            "counter-name-infos"
          )
        end

        batch = [
          {"dirty", dirty, %{end_ts_ns: 60_000_000_000}},
          {"clean", clean, %{end_ts_ns: 60_000_000_000}},
          {"other", other, %{end_ts_ns: 60_000_000_000}}
        ]

        for batch <- [batch, Enum.reverse(batch)] do
          assert {:ok, results} = Evaluator.query_batch(batch, "counter-name-infos", fn result, _ -> {:ok, result} end)
          assert results["dirty"]["infos"] == [notice]
          refute Map.has_key?(results["clean"], "infos")

          assert results["other"]["infos"] == [
                   ~s(PromQL info: metric might not be a counter, name does not end in _total/_sum/_count/_bucket: "other_bad")
                 ]
        end
      end
    end
  end

  for adapter <- [Memory, S3] do
    @tag adapter: adapter
    @tag :histogram_annotations_batch
    test "Pulse histogram collisions use valid buckets and complete input identities through #{inspect(adapter)}" do
      histogram = %NativeHistogram{
        schema: -53,
        custom_values: [6.0],
        count: 4.0,
        sum: 12.0,
        positive_spans: [{0, 1}],
        positive_buckets: [4.0]
      }

      buckets =
        Enum.flat_map(~w(mixed classic native_le), fn kind ->
          records(~s(collision{kind="#{kind}",le="2"} 4), 1) ++
            records(~s(collision{kind="#{kind}",le="+Inf"} 8), 1)
        end)

      native =
        for {kind, extra} <- [{"mixed", %{}}, {"native", %{}}, {"native_le", %{"le" => "99"}}] do
          %MetricSample{
            labels: Map.merge(%{"__name__" => "collision", "kind" => kind}, extra),
            timestamp_ns: 0,
            histogram: if(kind == "mixed", do: %{histogram | count: 5.0, sum: :nan}, else: histogram)
          }
        end

      # Invalid classic bounds must warn, but cannot suppress a native sample.
      invalid =
        for bound <- ["NaN", "", "1e999", "\"\n\u0000é\u200b"] do
          %MetricSample{
            labels: %{"__name__" => "collision", "kind" => "native", "le" => bound},
            timestamp_ns: 0,
            value: 9.0
          }
        end

      assert :ok = Storage.append(:metrics, "histogram-identities", buckets ++ native ++ invalid)

      checks = [
        ~s({kind="classic"} 2),
        ~s({kind="native"} 3),
        ~s({kind="native_le"} 2),
        ~s({kind="native_le",le="99"} 3),
        ~s(expect warn msg: PromQL warning: vector contains a mix of classic and native histograms for metric name "collision"),
        ~s(expect warn msg: PromQL warning: bucket label "le" is missing or has a malformed value of "NaN" for metric name "collision"),
        ~s(expect warn msg: PromQL warning: bucket label "le" is missing or has a malformed value of "" for metric name "collision"),
        ~s(expect warn msg: PromQL warning: bucket label "le" is missing or has a malformed value of "1e999" for metric name "collision"),
        ~S(expect warn msg: PromQL warning: bucket label "le" is missing or has a malformed value of "\"\n\x00é\u200b" for metric name "collision"),
        "expect no_info"
      ]

      fraction_checks =
        [
          ~s({kind="classic"} 0.5),
          ~s({kind="native"} 0.3333333333333333),
          ~s({kind="native_le"} 0.5),
          ~s({kind="native_le",le="99"} 0.3333333333333333)
        ] ++ Enum.drop(checks, 4)

      for {query, checks} <- [
            {"histogram_quantile(0.5, collision)", checks},
            {"histogram_fraction(0,2,collision)", fraction_checks}
          ],
          {path, time} <- [
            {"/api/v1/query", %{time: "0"}},
            {"/api/v1/query_range", %{start: "0", end: "0", step: "1s"}}
          ] do
        params = Map.put(time, :query, query)

        response =
          build_conn()
          |> put_req_header("x-scope-orgid", "histogram-identities")
          |> put_req_header("content-type", "application/x-www-form-urlencoded")
          |> post(path, URI.encode_query(params))
          |> json_response(200)

        expected = assert_annotations(response, checks, params.query)
        assert_samples(response["data"]["result"], expected, 0, 1, params.query)
      end

      # Different names do not collide until the result name is removed.
      different =
        records(~s(classic_name{le="2"} 4), 1) ++
          records(~s(classic_name{le="+Inf"} 8), 1) ++
          [%MetricSample{labels: %{"__name__" => "native_name"}, timestamp_ns: 0, histogram: histogram}]

      assert :ok = Storage.append(:metrics, "histogram-names", different)

      for query <- [
            ~s'histogram_quantile(0.5,{__name__=~"classic_name|native_name"})',
            ~s'histogram_fraction(0,2,{__name__=~"classic_name|native_name"})'
          ],
          do: check("eval_fail instant at 0 " <> query, [], "histogram-names")
    end

    @tag adapter: adapter
    @tag :histogram_annotations_batch
    test "Pulse histogram repair notices are step-local, deduplicated and source-isolated through #{inspect(adapter)}" do
      for {name, buckets} <- [
            {"tiny_down", [{"1", 100.0}, {"2", 100.0 - 1.0e-11}, {"+Inf", 200.0}]},
            {"tiny_up", [{"1", 100.0}, {"2", 100.0 + 1.0e-11}, {"+Inf", 200.0}]},
            {"subnormal_up", [{"1", 0.0}, {"2", 1.0e-321}, {"+Inf", 1.0e-321}]},
            {"subnormal_down", [{"1", 1.0e-321}, {"2", 0.0}, {"+Inf", 1.0e-321}]},
            {"subnormal_pair", [{"1", 1.0e-321}, {"2", 2.0e-321}, {"+Inf", 4.0e-321}]},
            {"subnormal_boundary", [{"1", 0.0}, {"2", 2.2253e-320}, {"+Inf", 2.2253e-320}]},
            {"huge_close", [{"1", 1.0e308}, {"2", 1.000_000_000_000_01e308}, {"+Inf", 1.2e308}]},
            {"huge_decrease", [{"1", 1.0e308}, {"2", 9.0e307}, {"+Inf", 1.2e308}]},
            {"decrease", [{"1", 5.0}, {"2", 4.0}, {"+Inf", 10.0}]},
            {"no_inf", [{"1", 5.0}, {"2", 4.0}]},
            {"same_bound", [{"1", 2.0}, {"1.0", 3.0}, {"+Inf", 10.0}]}
          ] do
        samples = Enum.flat_map(buckets, fn {bound, value} -> records(~s(#{name}{le="#{bound}"} #{value}), 1) end)
        assert :ok = Storage.append(:metrics, "histogram-repair", samples)
      end

      for {name, q, expected} <- [
            {"tiny_down", "0.5", "1"},
            {"tiny_up", "0.500000000000025", "2"},
            {"huge_close", "0.5", "0.6"},
            {"subnormal_up", "0.5", "NaN"},
            {"subnormal_down", "0.5", "0.5"},
            {"subnormal_pair", "0.5", "0.5"},
            {"subnormal_boundary", "0.5", "1.5"},
            {"no_inf", "0.5", "NaN"},
            {"same_bound", "0.5", "1"}
          ] do
        check(
          "eval instant at 0 histogram_quantile(#{q},#{name})",
          ["{} " <> expected, "expect no_info", "expect no_warn"],
          "histogram-repair"
        )
      end

      check(
        "eval instant at 0 histogram_quantile(0.5,huge_decrease)",
        [
          "{} 0.6",
          "expect info regex: ^PromQL info: input to histogram_quantile needed to be fixed for monotonicity ",
          "expect no_warn"
        ],
        "histogram-repair"
      )

      check(
        "eval range from 0 to 20s step 10s histogram_quantile(0.5,decrease)",
        [
          "{} 1 1 1",
          "expect info regex: ^PromQL info: input to histogram_quantile needed to be fixed for monotonicity ",
          "expect no_warn"
        ],
        "histogram-repair"
      )

      assert :ok =
               Storage.append(:metrics, "histogram-repair", [
                 %MetricSample{
                   labels: %{"__name__" => "decrease"},
                   timestamp_ns: 10_000_000_000,
                   histogram: %NativeHistogram{}
                 },
                 %MetricSample{labels: %{"__name__" => "decrease"}, timestamp_ns: 20_000_000_000, value: :stale}
               ])

      check(
        "eval range from 0 to 20s step 10s histogram_quantile(0.5,decrease)",
        [
          "{} 1 _ 1",
          "expect info regex: ^PromQL info: input to histogram_quantile needed to be fixed for monotonicity ",
          ~s(expect warn msg: PromQL warning: vector contains a mix of classic and native histograms for metric name "decrease")
        ],
        "histogram-repair"
      )

      queries = [
        {"repair", "histogram_quantile(0.5,decrease)", %{end_ts_ns: 0}},
        {"invalid", "histogram_quantile(2,decrease)", %{end_ts_ns: 0}},
        {"empty", "histogram_quantile(NaN,absent_metric)", %{end_ts_ns: 0}},
        {"clean", "histogram_quantile(0.5,tiny_down)", %{end_ts_ns: 0}}
      ]

      assert {:ok, results} = Evaluator.query_batch(queries, "histogram-repair", fn values, _ -> {:ok, values} end)

      # Mimir's streaming engine deliberately passes zero summary fields to
      # keep the original message, unlike its vendored Prometheus engine.
      assert results["repair"]["infos"] == [
               "PromQL info: input to histogram_quantile needed to be fixed for monotonicity " <>
                 "(see https://prometheus.io/docs/prometheus/latest/querying/functions/#histogram_quantile)"
             ]

      refute Map.has_key?(results["repair"], "warnings")
      assert results["invalid"]["warnings"] == ["PromQL warning: quantile value should be between 0 and 1, got 2"]
      refute Map.has_key?(results["invalid"], "infos")
      assert results["empty"]["warnings"] == ["PromQL warning: quantile value should be between 0 and 1, got NaN"]
      refute Map.has_key?(results["empty"], "infos")
      refute Map.has_key?(results["clean"], "warnings")
      refute Map.has_key?(results["clean"], "infos")
    end

    @tag adapter: adapter
    @tag :histogram_quantiles_batch
    test "Pulse plural quantiles preserve OpenMetrics labels and reject overwrites through #{inspect(adapter)}" do
      input =
        records(~s(classic{job="api",le="1"} 1), 1) ++
          records(~s(classic{job="api",le="10"} 3), 1) ++ records(~s(classic{job="api",le="+Inf"} 3), 1)

      assert :ok = Storage.append(:metrics, "plural-labels", input)

      for {q, text, value} <- [
            {"0", "0.0", "0"},
            {"-0", "0.0", "0"},
            {"1", "1.0", "10"},
            {"0.00001", "1e-05", "0.00003"},
            {"0.0001", "0.0001", "0.0003"}
          ] do
        check(
          ~s|eval instant at 0 histogram_quantiles(classic,"q",#{q})|,
          [~s({job="api",q="#{text}"} #{value}), "expect no_warn", "expect no_info"],
          "plural-labels"
        )
      end

      for {q, text, value} <- [
            {"2", "2.0", "+Inf"},
            {"NaN", "NaN", "NaN"},
            {"+Inf", "+Inf", "+Inf"},
            {"-Inf", "-Inf", "-Inf"}
          ] do
        warning_q = if q == "2", do: "2", else: text

        check(
          ~s|eval instant at 0 histogram_quantiles(classic,"q",#{q})|,
          [
            ~s({job="api",q="#{text}"} #{value}),
            "expect warn msg: PromQL warning: quantile value should be between 0 and 1, got " <> warning_q
          ],
          "plural-labels"
        )
      end

      for {destination, expected} <- [
            {"job", ~s({job="0.5"} 3.25)},
            {"__name__", ~s({job="api"} 3.25)},
            {"クォータ", ~s({job="api","クォータ"="0.5"} 3.25)}
          ] do
        query = ~s|histogram_quantiles(classic,"#{destination}",0.5)|
        check("eval instant at 0 " <> query, [expected], "plural-labels")

        response =
          build_conn()
          |> put_req_header("x-scope-orgid", "plural-labels")
          |> put_req_header("content-type", "application/x-www-form-urlencoded")
          |> post("/api/v1/query", URI.encode_query(%{query: query, time: "0"}))
          |> json_response(200)

        assert_samples(response["data"]["result"], [expected], 0, 1, query)
      end

      for qs <- ["0,-0", "NaN,NaN", "0.5,0.5"] do
        check(~s|eval_fail instant at 0 histogram_quantiles(classic,"q",#{qs})|, [], "plural-labels")
      end

      check(~s|eval_fail instant at 0 histogram_quantiles(classic,"__name__",0.25,0.5)|, [], "plural-labels")

      assert :ok =
               Storage.append(
                 :metrics,
                 "plural-labels",
                 records(~s(overwrite{q="a",le="1"} 1), 1) ++
                   records(~s(overwrite{q="a",le="+Inf"} 2), 1) ++
                   records(~s(overwrite{q="b",le="1"} 1), 1) ++ records(~s(overwrite{q="b",le="+Inf"} 2), 1)
               )

      check(~s|eval_fail instant at 0 histogram_quantiles(overwrite,"q",0.5)|, [], "plural-labels")

      check(
        ~s|eval instant at 0 histogram_quantiles(missing,"q",NaN)|,
        ["expect warn msg: PromQL warning: quantile value should be between 0 and 1, got NaN"],
        "plural-labels"
      )

      for query <- [
            ~s|histogram_quantiles(classic,"q")|,
            ~s|histogram_quantiles(classic,"q","0.5")|,
            ~s|histogram_quantiles(1,"q",0.5)|,
            ~s|histogram_quantiles(classic,1,0.5)|
          ] do
        conn = build_conn() |> get("/api/v1/query", query: query, time: "0")
        assert %{"status" => "error", "errorType" => "bad_data"} = json_response(conn, 400)
      end
    end

    @tag adapter: adapter
    @tag :histogram_quantiles_batch
    test "Pulse plural quantile fan-out and native bucket work share batch quotas through #{inspect(adapter)}" do
      narrow = %NativeHistogram{
        schema: -53,
        count: 1.0,
        sum: 2.0,
        custom_values: [4.0],
        positive_spans: [{0, 1}],
        positive_buckets: [1.0]
      }

      wide = %NativeHistogram{
        schema: -53,
        count: 512.0,
        sum: 131_328.0,
        custom_values: Enum.map(1..511, &(&1 / 1)),
        positive_spans: [{0, 512}],
        positive_buckets: List.duplicate(1.0, 512)
      }

      samples =
        for {name, h} <- [{"narrow", narrow}, {"wide", wide}],
            do: %MetricSample{labels: %{"__name__" => name}, timestamp_ns: 0, histogram: h}

      assert :ok = Storage.append(:metrics, "plural-cost", samples)
      check(~s|eval instant at 0 histogram_quantiles(wide,"q",0.5)|, [~s({q="0.5"} 256)], "plural-cost")

      Runtime.put_env(:pulse, Evaluator, max_work: 100)
      assert {:ok, _} = Evaluator.query(~s|histogram_quantiles(narrow,"q",0.5)|, "plural-cost", %{end_ts_ns: 0})

      assert {:error, :query_work_limit} =
               Evaluator.query(~s|histogram_quantiles(wide,"q",0.5)|, "plural-cost", %{end_ts_ns: 0})

      assert {:error, :query_work_limit} =
               Evaluator.query(
                 ~s|histogram_quantiles(narrow,"#{String.duplicate("x", 200)}",0.5)|,
                 "plural-cost",
                 %{end_ts_ns: 0}
               )

      expression = ~s|histogram_quantiles(narrow,"q",0.25,0.5,0.75)|
      Runtime.put_env(:pulse, Evaluator, max_materialized_samples: 2)
      assert {:error, :query_intermediate_limit} = Evaluator.query(expression, "plural-cost", %{end_ts_ns: 0})
      Runtime.put_env(:pulse, Evaluator, max_materialized_samples: 3)
      assert {:ok, %{"data" => %{"result" => results}}} = Evaluator.query(expression, "plural-cost", %{end_ts_ns: 0})

      assert results == [
               %{"metric" => %{"q" => "0.25"}, "value" => [0.0, "1"]},
               %{"metric" => %{"q" => "0.5"}, "value" => [0.0, "2"]},
               %{"metric" => %{"q" => "0.75"}, "value" => [0.0, "3"]}
             ]

      sources = for name <- ["one", "two"], do: {name, expression, %{end_ts_ns: 0}}

      for batch <- [sources, Enum.reverse(sources)] do
        assert {:error, :query_intermediate_limit} =
                 Evaluator.query_batch(batch, "plural-cost", fn _, _ -> flunk("partial quantiles") end)
      end
    end

    @tag adapter: adapter
    @tag :histogram_extrapolation_batch
    test "Pulse counter extrapolation uses original observation counts, not bucket or sum slopes through #{inspect(adapter)}" do
      for {kind, fields} <- [
            {"positive", "sum:0.75 count:1 buckets:[1]"},
            {"negative", "sum:-0.75 count:1 n_buckets:[1]"},
            {"zero", "count:1 z_bucket:1 z_bucket_w:1"},
            {"custom", "schema:-53 sum:0.75 count:1 custom_values:[1] buckets:[1]"}
          ] do
        first = value("{{#{fields}}}")

        last = %{
          first
          | count: 11.0,
            sum: first.sum * 11,
            zero_count: first.zero_count * 11,
            positive_buckets: Enum.map(first.positive_buckets, &(&1 * 11)),
            negative_buckets: Enum.map(first.negative_buckets, &(&1 * 11))
        }

        samples =
          for {time, h} <- [{10, first}, {20, last}],
              do: %MetricSample{
                labels: %{"__name__" => "observations", "kind" => kind},
                timestamp_ns: time * 1_000_000_000,
                histogram: h
              }

        assert :ok = Storage.append(:metrics, "counter-extrapolation", samples)

        # Count grows 1 -> 11 over 10s: extrapolate 1s left and 10s right.
        # Gauges still extrapolate 10s on each side; irate never extrapolates.
        for {op, expected} <- [{"increase", "21"}, {"rate", "0.7"}, {"delta", "30"}, {"irate", "1"}] do
          query = ~s|histogram_count(#{op}(observations{kind="#{kind}"}[30s]))|
          check("eval instant at 30s " <> query, [~s({kind="#{kind}"} #{expected})], "counter-extrapolation")
        end
      end

      # A reset at the second sample must retain the original first count
      # for the zero-point estimate, even though change discards that sample.
      assert :ok =
               Storage.append(
                 :metrics,
                 "counter-extrapolation",
                 records("reset _ {{sum:3 count:4 buckets:[4]}} {{sum:0.75 count:1 buckets:[1]}}", 10_000_000_000) ++
                   records("zero_start _ {{count:0}} {{sum:7.5 count:10 buckets:[10]}}", 10_000_000_000) ++
                   records("flat _ {{count:1 buckets:[1]}} {{count:1 buckets:[1]}}", 10_000_000_000)
               )

      for {name, expected} <- [{"reset", "3"}, {"zero_start", "20"}, {"flat", "0"}] do
        check(
          "eval instant at 30s histogram_count(increase(#{name}[30s]))",
          ["{} " <> expected, "expect no_info", "expect no_warn"],
          "counter-extrapolation"
        )
      end

      query = ~s|histogram_sum(increase(observations{kind="negative"}[30s]))|
      expected = [~s({kind="negative"} -15.75)]
      check("eval instant at 30s " <> query, expected, "counter-extrapolation")

      response =
        build_conn()
        |> put_req_header("x-scope-orgid", "counter-extrapolation")
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post("/api/v1/query", URI.encode_query(%{query: query, time: "30"}))
        |> json_response(200)

      assert_samples(response["data"]["result"], expected, 30, 1, query)
    end

    @tag adapter: adapter, histogram_precision_batch: true
    test "Pulse histogram compensation survives layout changes and field-specific overflow through #{inspect(adapter)}" do
      cases = [
        {"resolution",
         [
           "{{schema:1 offset:1 buckets:[1e16 1] counter_reset_hint:gauge}}",
           "{{schema:0 offset:1 buckets:[1] counter_reset_hint:gauge}}",
           "{{schema:0 offset:1 buckets:[-1e16] counter_reset_hint:gauge}}"
         ], "{{schema:0 offset:1 buckets:[2]}}"},
        {"custom",
         [
           "{{schema:-53 custom_values:[1 2] buckets:[1e16 1] counter_reset_hint:gauge}}",
           "{{schema:-53 custom_values:[2] buckets:[1] counter_reset_hint:gauge}}",
           "{{schema:-53 custom_values:[2] buckets:[-1e16] counter_reset_hint:gauge}}"
         ], "{{schema:-53 custom_values:[2] buckets:[2]}}"},
        {"zero",
         [
           "{{offset:1 buckets:[1e16] n_offset:1 n_buckets:[3] counter_reset_hint:gauge}}",
           "{{z_bucket_w:2 z_bucket:1 counter_reset_hint:gauge}}",
           "{{z_bucket_w:2 z_bucket:-1e16 counter_reset_hint:gauge}}"
         ], "{{z_bucket_w:2 z_bucket:4}}"}
      ]

      for {name, inputs, expected} <- cases do
        for {input, index} <- Enum.with_index(inputs) do
          # Separate publications exercise cross-object chronological folding.
          sample = hd(records("#{name} #{input}", 10_000_000_000))
          sample = %{sample | timestamp_ns: index * 10_000_000_000}
          assert :ok = Storage.append(:metrics, "precision", [sample])

          grouped = %{sample | labels: Map.put(sample.labels, "index", Integer.to_string(index))}
          assert :ok = Storage.append(:metrics, "precision-groups", [grouped])
        end

        for {tenant, query} <- [
              {"precision", "sum_over_time(#{name}[31s])"},
              {"precision-groups", "sum(#{name})"}
            ] do
          check("eval instant at 20s #{query}", ["{} #{expected}", "expect no_warn"], tenant)
        end
      end

      overflow = [
        {"buckets", "buckets:[1e308]", "{{count:1 sum:0 buckets:[1e308]}}"},
        {"zero_count", "z_bucket:1e308", "{{count:1 sum:0 z_bucket:1e308}}"}
      ]

      for {name, field, expected} <- overflow do
        inputs = "{{count:1 sum:1e308 #{field}}} {{count:1 sum:-1e308 #{field}}}"
        samples = records("#{name} #{inputs}", 10_000_000_000)
        assert :ok = Storage.append(:metrics, "overflow", samples)

        grouped =
          Enum.map(samples, fn sample ->
            %{sample | labels: Map.put(sample.labels, "index", Integer.to_string(sample.timestamp_ns))}
          end)

        assert :ok = Storage.append(:metrics, "overflow-groups", grouped)

        check("eval instant at 10s avg_over_time(#{name}[11s])", ["{} #{expected}"], "overflow")
        check("eval instant at 10s avg(#{name})", ["{} #{expected}"], "overflow-groups")
      end
    end

    @tag adapter: adapter, histogram_reset_tail_batch: true
    test "Pulse counter ranges detect missing populated tail buckets through #{inspect(adapter)}" do
      # These controls follow the pinned FloatHistogram.DetectReset iterator,
      # not the earlier 3.5.0 behavior frozen by Pulse's original unit test.
      cases = [
        {"empty", "buckets:[0 5]", "", 1},
        {"prefix", "buckets:[1 0 4]", "buckets:[6]", 1},
        {"negative", "n_buckets:[0 5]", "", 1},
        {"negative_prefix", "n_buckets:[1 0 4]", "n_buckets:[6]", 1},
        {"custom", "schema:-53 custom_values:[1 2] buckets:[0 0 5]", "schema:-53 custom_values:[1 2]", 1},
        {"only_zeros", "buckets:[5 0 0]", "buckets:[10]", 0},
        {"explicit_hint", "buckets:[0 5]", "counter_reset_hint:not_reset", 0}
      ]

      for {name, before, after_fields, resets} <- cases do
        inputs = "{{count:5 sum:10 #{before}}} {{count:10 sum:20 #{after_fields}}}"

        for sample <- records("#{name} #{inputs}", 10_000_000_000),
            do: assert(:ok = Storage.append(:metrics, "reset-tails", [sample]))

        check("eval instant at 10s resets(#{name}[11s])", ["{} #{resets}"], "reset-tails")

        for function <- ["irate", "rate"] do
          count = if resets == 1, do: 1, else: 0.5

          check(
            "eval instant at 10s histogram_count(#{function}(#{name}[11s]))",
            ["{} #{count}", "expect no_warn"],
            "reset-tails"
          )
        end

        increase = if resets == 1, do: 11, else: 5.5
        check("eval instant at 10s histogram_count(increase(#{name}[11s]))", ["{} #{increase}"], "reset-tails")
      end
    end

    @tag adapter: adapter, histogram_scaling_batch: true
    test "Pulse negative histogram scaling retains gauge identity through nested arithmetic on #{inspect(adapter)}" do
      samples = records("scaled {{count:5 sum:10 buckets:[5]}} {{count:10 sum:20 buckets:[10]}}", 10_000_000_000)

      for sample <- samples, do: assert(:ok = Storage.append(:metrics, "scaling-hints", [sample]))

      for expression <- [
            "-(-scaled)",
            "(scaled * -1) * -1",
            "-1 * (-1 * scaled)",
            "(scaled / -1) / -1",
            "(scaled * -1) / -1"
          ] do
        check(
          "eval instant at 10s histogram_count(delta((#{expression})[11s:10s]))",
          ["{} 5.5", "expect no_warn"],
          "scaling-hints"
        )

        check(
          "eval instant at 10s histogram_count(rate((#{expression})[11s:10s]))",
          ["{} 0.5", ~s(expect warn msg: PromQL warning: this native histogram metric is not a counter: "")],
          "scaling-hints"
        )
      end

      check(
        "eval instant at 10s histogram_count(delta((scaled * 1)[11s:10s]))",
        ["{} 5.5", ~s(expect warn msg: PromQL warning: this native histogram metric is not a gauge: "")],
        "scaling-hints"
      )
    end

    @tag adapter: adapter, histogram_scaling_work_batch: true
    test "Pulse histogram scaling and negation reserve traversal work before scalar wrappers through #{inspect(adapter)}" do
      dense = %NativeHistogram{
        count: 1.0,
        sum: 1.0,
        positive_spans: [{0, 64}],
        positive_buckets: [1.0 | List.duplicate(0.0, 63)],
        negative_spans: [{0, 32}],
        negative_buckets: List.duplicate(0.0, 32)
      }

      sparse = %NativeHistogram{
        schema: -53,
        count: 1.0,
        sum: 1.0,
        custom_values: Enum.map(1..128, &(&1 / 1)),
        positive_spans: [{0, 1}],
        positive_buckets: [1.0]
      }

      samples =
        for {name, histogram} <- [{"dense", dense}, {"sparse", sparse}], ts <- [0, 1_000_000_000] do
          %MetricSample{labels: %{"__name__" => name}, timestamp_ns: ts, histogram: histogram}
        end

      assert :ok = Storage.append(:metrics, "scaling-cost", samples ++ records("factor 2 2", 1_000_000_000))
      Runtime.put_env(:pulse, Evaluator, max_work: 64)

      # Unary plus and division by zero do not traverse the histogram's buckets.
      for {expression, expected} <- [{"+dense", "1"}, {"dense / 0", "+Inf"}, {"dense / -0", "-Inf"}] do
        check("eval instant at 0 histogram_count(#{expression})", ["{} #{expected}"], "scaling-cost")
      end

      # Scaling does not read unused custom bounds, unlike reconciliation.
      check("eval instant at 0 histogram_count(sparse * 2)", ["{} 2"], "scaling-cost")

      for {expression, expected} <- [
            {"dense * 2", "2"},
            {"2 * dense", "2"},
            {"dense * 0", "0"},
            {"dense / 2", "0.5"},
            {"-dense", "-1"},
            {"dense * factor", "2"},
            {"factor * dense", "2"},
            {"dense / factor", "0.5"}
          ] do
        query = "histogram_count(#{expression})"
        assert {:error, :query_work_limit} = Evaluator.query(query, "scaling-cost", %{end_ts_ns: 0})

        Runtime.put_env(:pulse, Evaluator, max_work: 128)
        check("eval instant at 0 #{query}", ["{} #{expected}", "expect no_info", "expect no_warn"], "scaling-cost")
        source = {"one", query, %{end_ts_ns: 0}}
        assert {:ok, _} = Evaluator.query_batch([source], "scaling-cost", fn result, _ -> {:ok, result} end)

        assert {:error, :query_work_limit} =
                 Evaluator.query_batch([source, put_elem(source, 0, "two")], "scaling-cost", fn _, _ ->
                   flunk("partial histogram scaling batch")
                 end)

        assert {:error, :query_work_limit} =
                 Evaluator.query(query, "scaling-cost", %{
                   start_ts_ns: 0,
                   end_ts_ns: 1_000_000_000,
                   step_ns: 1_000_000_000
                 })

        Runtime.put_env(:pulse, Evaluator, max_work: 64)
      end
    end

    @tag adapter: adapter, histogram_binary_batch: true
    test "Pulse binary histogram warnings preserve values and isolate successful and rejected pairs through #{inspect(adapter)}" do
      cases = [
        {"collision", :yes, :no},
        {"reversed_collision", :no, :yes},
        {"reset", :yes, :yes},
        {"no_reset", :no, :no},
        {"unknown", :yes, :unknown},
        {"gauge", :no, :gauge}
      ]

      for {tenant, left, right} <- cases do
        histogram = %NativeHistogram{count: 3.0, sum: 6.0, positive_spans: [{0, 1}], positive_buckets: [3.0]}
        other = %{histogram | count: 2.0, sum: 4.0, positive_buckets: [2.0]}

        assert :ok =
                 Storage.append(:metrics, tenant, [
                   %MetricSample{
                     labels: %{"__name__" => "lhs"},
                     timestamp_ns: 0,
                     histogram: %{histogram | counter_reset_hint: left}
                   },
                   %MetricSample{
                     labels: %{"__name__" => "rhs"},
                     timestamp_ns: 0,
                     histogram: %{other | counter_reset_hint: right}
                   }
                 ])

        for {op, operation, count} <- [{"+", "addition", 5}, {"-", "subtraction", 1}] do
          notices =
            if tenant in ["collision", "reversed_collision"],
              do: ["expect warn msg: PromQL warning: conflicting counter resets during histogram #{operation}"],
              else: ["expect no_warn"]

          check("eval instant at 0 histogram_count(lhs #{op} rhs)", ["{} #{count}", "expect no_info" | notices], tenant)
        end
      end

      for {query, index} <- Enum.with_index(["lhs + rhs", "rhs + lhs", "lhs - rhs", "rhs - lhs"]) do
        op = if String.contains?(query, "+"), do: "+", else: "-"
        tenant = "mixed-#{index}"

        exponential = %NativeHistogram{
          count: 1.0,
          sum: 1.0,
          counter_reset_hint: :yes,
          positive_spans: [{0, 1}],
          positive_buckets: [1.0]
        }

        custom = %{exponential | schema: -53, custom_values: [1.0], counter_reset_hint: :no}

        assert :ok =
                 Storage.append(:metrics, tenant, [
                   %MetricSample{labels: %{"__name__" => "lhs"}, timestamp_ns: 0, histogram: exponential},
                   %MetricSample{labels: %{"__name__" => "rhs"}, timestamp_ns: 0, histogram: custom}
                 ])

        warning = "PromQL warning: incompatible bucket layout encountered for binary operator #{op}"
        check("eval instant at 0 #{query}", ["expect warn msg: #{warning}", "expect no_info"], tenant)
        check("eval instant at 0 histogram_count(lhs)", ["{} 1", "expect no_warn", "expect no_info"], tenant)
        batch = [{"bad", query, %{end_ts_ns: 0}}, {"good", "histogram_count(lhs)", %{end_ts_ns: 0}}]

        for sources <- [batch, Enum.reverse(batch)] do
          assert {:ok, results} = Evaluator.query_batch(sources, tenant, fn result, _ -> {:ok, result} end)
          assert results["bad"]["warnings"] == [warning]
          assert results["bad"]["data"]["result"] == []
          assert Map.get(results["good"], "warnings", []) == []
          assert_samples(results["good"]["data"]["result"], ["{} 1"], 0, 1, "unmodified histogram source")
        end
      end
    end

    @tag adapter: adapter, histogram_trimming_batch: true
    test "Pulse trims preserve operand order, names, reset hints and request-local notices through #{inspect(adapter)}" do
      hist = "{{schema:-53 count:12 sum:42 custom_values:[1 3] buckets:[2 4 6]}}"
      assert :ok = Storage.append(:metrics, "trims", records("h #{hist}", 1) ++ records("cutoff 2", 1))

      for {query, left, right} <- [
            {"h </ h", "histogram", "histogram"},
            {"cutoff </ h", "float", "histogram"},
            {"2 >/ h", "float", "histogram"},
            {"cutoff </ 2", "float", "float"}
          ] do
        op = if String.contains?(query, ">/"), do: ">/", else: "</"

        info =
          ~s(PromQL info: incompatible sample types encountered for binary operator "#{op}": #{left} #{op} #{right})

        check("eval instant at 0 #{query}", ["expect no_warn", "expect info msg: " <> info], "trims")
      end

      expected = "h {{schema:-53 count:4 sum:4 custom_values:[1 3] buckets:[2 2]}}"
      check("eval instant at 0 h </ cutoff", [expected, "expect no_warn", "expect no_info"], "trims")
      check("eval instant at 0 h </ cutoff", [], "other-tenant")

      for query <- ["h </ bool 2", "1 >/ 2"] do
        response = build_conn() |> get("/api/v1/query", %{query: query, time: "0"}) |> json_response(400)
        assert response["errorType"] == "bad_data"
      end

      post_response =
        build_conn()
        |> put_req_header("x-scope-orgid", "trims")
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post("/api/v1/query", URI.encode_query(query: "h </ cutoff", time: "0"))
        |> json_response(200)

      assert_samples(post_response["data"]["result"], [expected], 0, 1, "trim form POST")

      for hint <- ["gauge", "not_reset"] do
        input =
          "hinted {{schema:-53 custom_values:[1] count:5 sum:10 buckets:[5] counter_reset_hint:#{hint}}} {{schema:-53 custom_values:[1] count:10 sum:20 buckets:[10] counter_reset_hint:#{hint}}}"

        assert :ok = Storage.append(:metrics, hint, records(input, 10_000_000_000))

        warnings =
          if hint == "gauge",
            do: ["expect no_warn"],
            else: [~s(expect warn msg: PromQL warning: this native histogram metric is not a gauge: "hinted")]

        check("eval instant at 10s histogram_count(delta((hinted </ 0.5)[11s:10s]))", ["{} 2.75" | warnings], hint)
      end

      batch = [
        {"bad", "cutoff </ 2", %{end_ts_ns: 0}},
        {"good", "h </ 2", %{end_ts_ns: 0}},
        {"original", "h", %{end_ts_ns: 0}}
      ]

      for queries <- [batch, Enum.reverse(batch)] do
        assert {:ok, results} = Evaluator.query_batch(queries, "trims", fn result, _ -> {:ok, result} end)
        assert length(results["bad"]["infos"]) == 1
        assert Map.get(results["good"], "infos", []) == []
        assert_samples(results["good"]["data"]["result"], [expected], 0, 1, "trim batch")
        assert_samples(results["original"]["data"]["result"], ["h " <> hist], 0, 1, "unmodified source")
      end
    end

    @tag adapter: adapter, histogram_trimming_batch: true
    test "Pulse trims charge bucket bounds to shared work and retain scan and result limits through #{inspect(adapter)}" do
      histogram = %NativeHistogram{
        schema: -53,
        custom_values: Enum.map(1..64, &(&1 / 1)),
        count: 1.0,
        sum: 1.0,
        positive_spans: [{0, 1}],
        positive_buckets: [1.0]
      }

      assert :ok =
               Storage.append(:metrics, "trim-cost", [
                 %MetricSample{labels: %{"__name__" => "costly"}, timestamp_ns: 0, histogram: histogram},
                 %MetricSample{labels: %{"__name__" => "costly"}, timestamp_ns: 1_000_000_000, histogram: histogram}
               ])

      Runtime.put_env(:pulse, Evaluator, max_work: 64)
      assert {:ok, _} = Evaluator.query("costly", "trim-cost", %{end_ts_ns: 0})

      for op <- ["</", ">/"] do
        assert {:error, :query_work_limit} = Evaluator.query("costly #{op} 0.5", "trim-cost", %{end_ts_ns: 0})
      end

      Runtime.put_env(:pulse, Evaluator, max_work: 100)
      source = {"one", "costly </ 0.5", %{end_ts_ns: 0}}
      assert {:ok, _} = Evaluator.query_batch([source], "trim-cost", fn result, _ -> {:ok, result} end)

      assert {:error, :query_work_limit} =
               Evaluator.query_batch([source, put_elem(source, 0, "two")], "trim-cost", fn _, _ ->
                 flunk("partial trim batch")
               end)

      for {opts, reason} <- [{[max_samples: 1], :query_sample_limit}, {[max_result_points: 1], :query_result_limit}] do
        Runtime.put_env(:pulse, Evaluator, opts)

        assert {:error, ^reason} =
                 Evaluator.query("costly </ 0.5", "trim-cost", %{
                   start_ts_ns: 0,
                   end_ts_ns: 1_000_000_000,
                   step_ns: 1_000_000_000
                 })
      end

      if unquote(adapter) == S3 do
        Runtime.put_env(:pulse, Evaluator, max_scan_rows: 1)
        assert {:error, :query_scan_limit} = Evaluator.query("costly </ 0.5", "trim-cost", %{end_ts_ns: 1_000_000_000})
      end
    end

    @tag adapter: adapter, histogram_properties_batch: true
    test "Pulse histogram dispersion charges sparse bounds and empty buckets to shared work through #{inspect(adapter)}" do
      histograms = [
        {"custom",
         %NativeHistogram{
           schema: -53,
           custom_values: Enum.map(1..64, &(&1 / 1)),
           count: 1.0,
           sum: 1.5,
           positive_spans: [{1, 1}],
           positive_buckets: [1.0]
         }},
        {"exponential",
         %NativeHistogram{
           count: 1.0,
           sum: 0.0,
           zero_count: 1.0,
           positive_spans: [{0, 64}],
           positive_buckets: List.duplicate(0.0, 64),
           negative_spans: [{0, 32}],
           negative_buckets: List.duplicate(0.0, 32)
         }}
      ]

      for {tenant, histogram} <- histograms do
        samples =
          for ts <- [0, 1_000_000_000],
              do: %MetricSample{labels: %{"__name__" => "costly"}, timestamp_ns: ts, histogram: histogram}

        assert :ok = Storage.append(:metrics, tenant, samples)

        Runtime.put_env(:pulse, Evaluator, max_work: 64)

        for function <- ["histogram_count", "histogram_sum", "histogram_avg"] do
          # Constant-time properties must not pay for unused bucket geometry.
          assert {:ok, _} = Evaluator.query("#{function}(costly)", tenant, %{end_ts_ns: 0})
        end

        for function <- ["histogram_stdvar", "histogram_stddev"] do
          query = "#{function}(costly)"
          assert {:error, :query_work_limit} = Evaluator.query(query, tenant, %{end_ts_ns: 0})

          Runtime.put_env(:pulse, Evaluator, max_work: 128)
          check("eval instant at 0 #{query}", ["{} 0", "expect no_warn", "expect no_info"], tenant)
          source = {"one", query, %{end_ts_ns: 0}}
          assert {:ok, _} = Evaluator.query_batch([source], tenant, fn result, _ -> {:ok, result} end)

          assert {:error, :query_work_limit} =
                   Evaluator.query_batch([source, put_elem(source, 0, "two")], tenant, fn _, _ ->
                     flunk("partial histogram dispersion batch")
                   end)

          assert {:error, :query_work_limit} =
                   Evaluator.query(query, tenant, %{
                     start_ts_ns: 0,
                     end_ts_ns: 1_000_000_000,
                     step_ns: 1_000_000_000
                   })

          Runtime.put_env(:pulse, Evaluator, max_work: 64)
        end
      end
    end

    @tag adapter: adapter, histogram_properties_batch: true
    test "Pulse histogram comparisons charge both layouts before discarding buckets through #{inspect(adapter)}" do
      histogram = %NativeHistogram{
        schema: -53,
        custom_values: Enum.map(1..64, &(&1 / 1)),
        count: 1.0,
        sum: 1.5,
        positive_spans: [{1, 1}],
        positive_buckets: [1.0]
      }

      samples =
        for ts <- [0, 1_000_000_000],
            do: %MetricSample{labels: %{"__name__" => "costly"}, timestamp_ns: ts, histogram: histogram}

      assert :ok = Storage.append(:metrics, "comparison-cost", samples)
      Runtime.put_env(:pulse, Evaluator, max_work: 100)
      check("eval instant at 0 histogram_count(costly)", ["{} 1"], "comparison-cost")

      for {query, expected} <- [
            {"histogram_count(costly == costly)", ["{} 1"]},
            {"histogram_sum(costly != costly)", []},
            {"costly == bool costly", ["{} 1"]},
            {"costly != bool costly", ["{} 0"]}
          ] do
        assert {:error, :query_work_limit} = Evaluator.query(query, "comparison-cost", %{end_ts_ns: 0})

        Runtime.put_env(:pulse, Evaluator, max_work: 192)
        check("eval instant at 0 #{query}", expected ++ ["expect no_info", "expect no_warn"], "comparison-cost")
        source = {"one", query, %{end_ts_ns: 0}}
        assert {:ok, _} = Evaluator.query_batch([source], "comparison-cost", fn result, _ -> {:ok, result} end)

        assert {:error, :query_work_limit} =
                 Evaluator.query_batch([source, put_elem(source, 0, "two")], "comparison-cost", fn _, _ ->
                   flunk("partial histogram comparison batch")
                 end)

        Runtime.put_env(:pulse, Evaluator, max_work: 100)
      end
    end

    @tag adapter: adapter, histogram_counter_batch: true
    test "Pulse counter ranges report executed reconciliation and preserve warning precedence through #{inspect(adapter)}" do
      first = "{{schema:-53 count:6 custom_values:[1 3] buckets:[1 2 3]}}"
      growth = "{{schema:-53 count:10 custom_values:[1 2 3] buckets:[2 1 3 4]}}"
      last = "{{schema:-53 count:14 custom_values:[1 3] buckets:[3 5 6]}}"
      reset = "{{schema:-53 count:3 custom_values:[1 2 3] buckets:[1 0 1 1]}}"
      late_reset = "{{schema:-53 count:4 custom_values:[1 3] buckets:[1 1 2]}}"
      small = "{{schema:-53 count:3 custom_values:[1 3] buckets:[1 1 1]}}"
      expanded = "{{schema:-53 count:5 custom_values:[1 2 3] buckets:[1 1 1 2]}}"
      exponential = "{{count:2 buckets:[2]}}"
      gauge = String.replace(first, "}}", " counter_reset_hint:gauge}}")
      gauge_growth = String.replace(growth, "}}", " counter_reset_hint:gauge}}")

      cases = [
        {"endpoints", "#{first} #{growth}", 0.4, 4.4, ["subtraction"], []},
        {"middle_only", "#{first} #{growth} #{last}", 0.4, 8.4, [], []},
        {"first_reset", "#{first} #{reset}", 0.3, 3.3, [], []},
        {"later_reset", "#{first} #{growth} #{late_reset}", 0.4, 8.4, ["addition"], []},
        {"both", "#{first} #{growth} #{small} #{expanded}", 0.3, 9.3, ["addition", "subtraction"], []},
        {"gauge_middle", "#{first} #{gauge_growth} #{last}", 0.4, 8.4, [], [:not_counter]},
        {"error_middle", "#{gauge} #{growth} #{exponential} #{last}", nil, nil, [], [:schema]},
        {"error_endpoint", "#{gauge} #{growth} #{exponential}", nil, nil, [], [:schema, :not_counter]},
        {"gauge_first_reset", "#{gauge} #{exponential}", 0.2, 2.2, [], [:not_counter]},
        {"mixed", "#{gauge} 1 #{last}", nil, nil, [], [:mixed]},
        {"single", gauge, nil, nil, [], []},
        {"stale", "#{first} stale #{growth}", 0.2, 4.2, ["subtraction"], []}
      ]

      for {name, input, rate, increase, reconciliations, warnings} <- cases do
        samples = records("#{name} #{input}", 10_000_000_000)

        for sample <- samples,
            do: assert(:ok = Storage.append(:metrics, "counter-notices", [sample]))

        finish = div(List.last(samples).timestamp_ns, 1_000_000_000)

        warnings =
          if warnings == [] do
            ["expect no_warn"]
          else
            Enum.map(warnings, fn type ->
              message =
                case type do
                  :not_counter ->
                    "this native histogram metric is not a counter:"

                  :schema ->
                    "vector contains a mix of histograms with exponential and custom buckets schemas for metric name"

                  :mixed ->
                    "encountered a mix of histograms and floats for metric name"
                end

              "expect warn msg: PromQL warning: #{message} #{Pulse.JSON.encode!(name)}"
            end)
          end

        infos =
          if reconciliations == [],
            do: ["expect no_info"],
            else:
              Enum.map(reconciliations, fn operation ->
                "expect info regex: PromQL info: mismatched custom buckets were reconciled during #{operation}"
              end)

        for {function, value} <- [{"rate", rate}, {"increase", increase}] do
          expected = if value, do: ["{} #{value}" | warnings ++ infos], else: warnings ++ infos

          check(
            "eval instant at #{finish}s histogram_count(#{function}(#{name}[#{finish + 1}s]))",
            expected,
            "counter-notices"
          )
        end
      end

      sources = [
        {"noisy", "histogram_count(rate(gauge_middle[21s]))", %{end_ts_ns: 20_000_000_000}},
        {"quiet", "histogram_count(rate(middle_only[21s]))", %{end_ts_ns: 20_000_000_000}}
      ]

      for batch <- [sources, Enum.reverse(sources)] do
        assert {:ok, results} = Evaluator.query_batch(batch, "counter-notices", fn result, _ -> {:ok, result} end)

        assert results["noisy"]["warnings"] == [
                 "PromQL warning: this native histogram metric is not a counter: \"gauge_middle\""
               ]

        assert Map.get(results["quiet"], "warnings", []) == []
        assert Map.get(results["quiet"], "infos", []) == []
      end

      assert :ok =
               Storage.append(
                 :metrics,
                 "counter-notices",
                 records(
                   "costly {{schema:-53 count:1 custom_values:[#{Enum.join(1..64, " ")}] buckets:[1]}}x1",
                   10_000_000_000
                 )
               )

      Runtime.put_env(:pulse, Evaluator, max_work: 80)
      assert {:ok, _} = Evaluator.query("costly", "counter-notices", %{end_ts_ns: 10_000_000_000})

      for function <- ["rate", "increase"] do
        assert {:error, :query_work_limit} =
                 Evaluator.query("#{function}(costly[11s])", "counter-notices", %{end_ts_ns: 10_000_000_000})
      end

      Runtime.put_env(:pulse, Evaluator, max_work: 240)
      source = {"one", "rate(costly[11s])", %{end_ts_ns: 10_000_000_000}}
      assert {:ok, _} = Evaluator.query_batch([source], "counter-notices", fn result, _ -> {:ok, result} end)

      assert {:error, :query_work_limit} =
               Evaluator.query_batch([source, put_elem(source, 0, "two")], "counter-notices", fn _, _ ->
                 flunk("partial histogram counter batch")
               end)
    end

    @tag adapter: adapter, histogram_aggregation_batch: true
    test "Pulse histogram range aggregation reports only visited inputs and spends shared work through #{inspect(adapter)}" do
      custom = "{{schema:-53 count:1 sum:2 custom_values:[5] buckets:[1]}}"
      other = "{{schema:-53 count:1 sum:2 custom_values:[5 10] buckets:[1]}}"
      reset = String.replace(custom, "}}", " counter_reset_hint:reset}}")
      gauge = String.replace(custom, "}}", " counter_reset_hint:gauge}}")
      no_reset = String.replace(custom, "}}", " counter_reset_hint:not_reset}}")
      exponential = "{{count:1 sum:2 buckets:[1]}}"
      reconciliation = "expect info msg: PromQL info: mismatched custom buckets were reconciled during aggregation"
      collision = "expect warn msg: PromQL warning: conflicting counter resets during histogram aggregation"

      cases = [
        {"coarsened", "#{custom} #{other} #{other}", [reconciliation, "expect no_warn"], true},
        {"same", "#{custom} #{custom} #{custom}", ["expect no_info", "expect no_warn"], true},
        {"gauge_between", "#{reset} #{gauge} #{no_reset}", [collision, "expect no_info"], true},
        {"unknown_between", "#{reset} #{custom} #{no_reset}", [collision, "expect no_info"], true},
        {"incompatible", "#{exponential} #{custom} #{reset} #{no_reset}", ["expect no_info"], false},
        {"reconciled_then_error",
         "#{reset} #{String.replace(other, "}}", " counter_reset_hint:not_reset}}")} #{exponential}",
         [collision, reconciliation], false},
        {"mixed_first", "1 #{reset} #{no_reset}", ["expect no_info"], false},
        {"mixed_middle", "#{reset} 1 #{no_reset}", ["expect no_info"], false},
        {"mixed_last", "#{reset} #{no_reset} 1", ["expect no_info"], false},
        {"with_stale", "#{custom} stale #{other}", [reconciliation, "expect no_warn"], true}
      ]

      for {name, input, _, _} <- cases do
        # Publish individual samples so S3 must combine separate objects.
        for sample <- records("#{name} #{input}", 10_000_000_000),
            do: assert(:ok = Storage.append(:metrics, "range-aggregation", [sample]))
      end

      for {name, _, notices, output?} <- cases,
          function <- ["sum_over_time", "avg_over_time"] do
        notices =
          cond do
            String.starts_with?(name, "mixed_") ->
              [
                "expect warn msg: PromQL warning: encountered a mix of histograms and floats for metric name #{Pulse.JSON.encode!(name)}"
                | notices
              ]

            name in ["incompatible", "reconciled_then_error"] ->
              [
                "expect warn msg: PromQL warning: vector contains a mix of histograms with exponential and custom buckets schemas for metric name #{Pulse.JSON.encode!(name)}"
                | notices
              ]

            true ->
              notices
          end

        count = if name == "with_stale", do: 2, else: 3
        count = if function == "avg_over_time", do: 1, else: count
        expected = if output?, do: ["{} #{count}" | notices], else: notices
        finish = if name == "incompatible", do: "30s", else: "20s"

        check(
          "eval instant at #{finish} histogram_count(#{function}(#{name}[31s]))",
          expected,
          "range-aggregation"
        )
      end

      queries = [
        {"noisy", "histogram_count(sum_over_time(gauge_between[31s]))", %{end_ts_ns: 20_000_000_000}},
        {"quiet", "histogram_count(sum_over_time(same[31s]))", %{end_ts_ns: 20_000_000_000}}
      ]

      for batch <- [queries, Enum.reverse(queries)] do
        assert {:ok, results} = Evaluator.query_batch(batch, "range-aggregation", fn result, _ -> {:ok, result} end)
        assert results["noisy"]["warnings"] == [String.replace_prefix(collision, "expect warn msg: ", "")]
        assert Map.get(results["quiet"], "warnings", []) == []
      end

      assert :ok =
               Storage.append(
                 :metrics,
                 "range-aggregation",
                 records(
                   "costly {{schema:-53 count:1 custom_values:[#{Enum.join(1..64, " ")}] buckets:[1]}}x1",
                   10_000_000_000
                 )
               )

      Runtime.put_env(:pulse, Evaluator, max_work: 80)
      assert {:ok, _} = Evaluator.query("costly", "range-aggregation", %{end_ts_ns: 10_000_000_000})

      for function <- ["sum_over_time", "avg_over_time"] do
        query = "#{function}(costly[11s])"

        assert {:error, :query_work_limit} =
                 Evaluator.query(query, "range-aggregation", %{end_ts_ns: 10_000_000_000})
      end

      Runtime.put_env(:pulse, Evaluator, max_work: 240)
      source = {"one", "sum_over_time(costly[11s])", %{end_ts_ns: 10_000_000_000}}
      assert {:ok, _} = Evaluator.query_batch([source], "range-aggregation", fn result, _ -> {:ok, result} end)

      assert {:error, :query_work_limit} =
               Evaluator.query_batch([source, put_elem(source, 0, "two")], "range-aggregation", fn _, _ ->
                 flunk("partial histogram aggregation batch")
               end)
    end

    @tag adapter: adapter, histogram_aggregation_batch: true
    test "Pulse vector aggregation retains diagnostic source names and isolates groups through #{inspect(adapter)}" do
      inputs = [
        "small{kind=\"coarsened\"} {{schema:-53 count:1 custom_values:[5] buckets:[1]}}",
        "wide{kind=\"coarsened\"} {{schema:-53 count:2 custom_values:[5 10] buckets:[1 1]}}",
        "reset{kind=\"collision\"} {{count:1 counter_reset_hint:reset buckets:[1]}}",
        "unknown{kind=\"collision\"} {{count:2 buckets:[2]}}",
        "not_reset{kind=\"collision\"} {{count:3 counter_reset_hint:not_reset buckets:[3]}}",
        "float{kind=\"mixed\"} 1",
        "hist{kind=\"mixed\"} {{count:4 buckets:[4]}}",
        "exponential{kind=\"incompatible\"} {{count:1 buckets:[1]}}",
        "custom{kind=\"incompatible\"} {{schema:-53 count:2 custom_values:[5] buckets:[2]}}"
      ]

      for input <- inputs,
          do: assert(:ok = Storage.append(:metrics, "group-aggregation", records(input, 1)))

      for {function, coarsened, collision} <- [{"sum", 3, 6}, {"avg", 1.5, 2}] do
        check(
          "eval instant at 0 histogram_count(#{function}({kind=\"coarsened\"}))",
          [
            "{} #{coarsened}",
            "expect no_warn",
            "expect info msg: PromQL info: mismatched custom buckets were reconciled during aggregation"
          ],
          "group-aggregation"
        )

        check(
          "eval instant at 0 histogram_count(#{function}({kind=\"collision\"}))",
          [
            "{} #{collision}",
            "expect no_info",
            "expect warn msg: PromQL warning: conflicting counter resets during histogram aggregation"
          ],
          "group-aggregation"
        )

        check(
          "eval instant at 0 #{function}({kind=\"mixed\"})",
          [
            "expect no_info",
            "expect warn msg: PromQL warning: encountered a mix of histograms and floats for aggregation"
          ],
          "group-aggregation"
        )

        check(
          "eval instant at 0 #{function}({kind=\"incompatible\"})",
          [
            "expect no_info",
            ~s|expect warn regex: PromQL warning: vector contains a mix of histograms with exponential and custom buckets schemas for metric name "(custom\|exponential)"|
          ],
          "group-aggregation"
        )
      end

      sources = [
        {"noisy", "sum({kind=\"coarsened\"})", %{end_ts_ns: 0}},
        {"quiet", "count({kind=\"coarsened\"})", %{end_ts_ns: 0}}
      ]

      for batch <- [sources, Enum.reverse(sources)] do
        assert {:ok, results} = Evaluator.query_batch(batch, "group-aggregation", fn result, _ -> {:ok, result} end)
        assert length(results["noisy"]["infos"]) == 1
        assert Map.get(results["quiet"], "infos", []) == []
        assert Map.get(results["quiet"], "warnings", []) == []
      end
    end

    @tag adapter: adapter, custom_arithmetic_batch: true
    test "Pulse custom arithmetic coarsens asymmetric layouts, preserves gauges and spends shared work through #{inspect(adapter)}" do
      left = "{{schema:-53 count:17 sum:10 custom_values:[-2 1 4] buckets:[2 3 5 7]}}"

      right =
        "{{schema:-53 count:112 sum:50 custom_values:[-1 1 3 4 9] buckets:[11 13 17 19 23 29] counter_reset_hint:gauge}}"

      for input <- ["left _ #{left}", "right _ #{right}", "rolling #{left} #{right}"],
          do: assert(:ok = Storage.append(:metrics, "custom-arithmetic", records(input, 10_000_000_000)))

      sum = "{} {{schema:-53 count:129 sum:60 custom_values:[1 4] buckets:[29 41 59] counter_reset_hint:gauge}}"
      mean = "{} {{schema:-53 count:64.5 sum:30 custom_values:[1 4] buckets:[14.5 20.5 29.5] counter_reset_hint:gauge}}"

      for query <- ["left + right", "right + left"] do
        check(
          "eval instant at 10s #{query}",
          [
            sum,
            "expect no_warn",
            "expect info msg: PromQL info: mismatched custom buckets were reconciled during addition"
          ],
          "custom-arithmetic"
        )
      end

      for {query, result} <- [
            {"sum({__name__=~\"left|right\"})", sum},
            {"avg({__name__=~\"left|right\"})", mean},
            {"sum_over_time(rolling[11s])", sum},
            {"avg_over_time(rolling[11s])", mean}
          ],
          do: check("eval instant at 10s #{query}", [result, "expect no_warn"], "custom-arithmetic")

      # Arithmetic subtraction is a gauge even when its left input is a counter.
      check(
        "eval instant at 12s histogram_count(idelta((left-right)[2s:1s]))",
        [
          "{} 0",
          "expect no_warn",
          "expect info msg: PromQL info: mismatched custom buckets were reconciled during subtraction"
        ],
        "custom-arithmetic"
      )

      queries = [
        {"addition", "left + right", %{end_ts_ns: 10_000_000_000}},
        {"quiet", "left", %{end_ts_ns: 10_000_000_000}}
      ]

      for batch <- [queries, Enum.reverse(queries)] do
        assert {:ok, results} = Evaluator.query_batch(batch, "custom-arithmetic", fn result, _ -> {:ok, result} end)

        assert results["addition"]["infos"] == [
                 "PromQL info: mismatched custom buckets were reconciled during addition"
               ]

        assert Map.get(results["quiet"], "infos", []) == []
      end

      for {name, offset} <- [{"costly_left", 0.0}, {"costly_right", 0.5}] do
        histogram = %NativeHistogram{
          schema: -53,
          count: 1.0,
          custom_values: Enum.map(1..64, &(&1 + offset)),
          positive_spans: [{0, 1}],
          positive_buckets: [1.0]
        }

        sample = %MetricSample{labels: %{"__name__" => name}, timestamp_ns: 10_000_000_000, histogram: histogram}
        assert :ok = Storage.append(:metrics, "custom-arithmetic", [sample])
      end

      Runtime.put_env(:pulse, Evaluator, max_work: 80)
      assert {:ok, _} = Evaluator.query("costly_left", "custom-arithmetic", %{end_ts_ns: 10_000_000_000})
      query = "costly_left + costly_right"
      assert {:error, :query_work_limit} = Evaluator.query(query, "custom-arithmetic", %{end_ts_ns: 10_000_000_000})

      Runtime.put_env(:pulse, Evaluator, max_work: 240)
      source = {"one", query, %{end_ts_ns: 10_000_000_000}}
      assert {:ok, _} = Evaluator.query_batch([source], "custom-arithmetic", fn result, _ -> {:ok, result} end)

      assert {:error, :query_work_limit} =
               Evaluator.query_batch([source, put_elem(source, 0, "two")], "custom-arithmetic", fn _, _ ->
                 flunk("partial histogram arithmetic batch")
               end)
    end

    @tag adapter: adapter, irate_batch: true
    test "Pulse custom reset detection preserves growth and notices only executed subtractions through #{inspect(adapter)}" do
      previous = %NativeHistogram{
        schema: -53,
        count: 20.0,
        custom_values: [1.0, 3.0],
        positive_spans: [{0, 3}],
        positive_buckets: [4.0, 6.0, 10.0]
      }

      cases = [
        {"same", [1.0, 3.0, 2.0, 4.0, 10.0], 20.0, :unknown, "0", "0"},
        {"decrease", [1.0, 2.0, 2.0, 5.0, 12.0], 22.0, :unknown, "1", "2.2"},
        {"infinity", [1.0, 4.0, 3.0, 7.0, 9.0], 24.0, :unknown, "1", "2.4"},
        {"missing", [1.0, 4.0, 3.0, 17.0], 25.0, :unknown, "1", "2.5"},
        {"forced_no", [1.0, 2.0, 2.0, 5.0, 12.0], 22.0, :no, "0", "0.2"},
        {"forced_yes", [1.0, 3.0, 2.0, 4.0, 10.0], 20.0, :yes, "1", "2"},
        {"gauge", [1.0, 3.0, 2.0, 4.0, 10.0], 20.0, :gauge, "0", "0"}
      ]

      # Distinct appends also exercise pairs crossing Parquet object boundaries.
      for second? <- [false, true] do
        samples =
          for {name, counts, count, hint, _, _} <- cases do
            current = %{
              previous
              | custom_values: [0.0, 1.0, 2.0, 3.0],
                positive_spans: [{0, length(counts)}],
                positive_buckets: counts,
                count: count,
                counter_reset_hint: hint
            }

            %MetricSample{
              labels: %{"__name__" => name},
              timestamp_ns: if(second?, do: 20_000_000_000, else: 10_000_000_000),
              histogram: if(second?, do: current, else: previous)
            }
          end

        assert :ok = Storage.append(:metrics, "custom-reset", samples)
      end

      for {name, _, _, _, resets, rate} <- cases do
        warning =
          if name == "gauge",
            do: ~s(expect warn msg: PromQL warning: this native histogram metric is not a counter: "gauge"),
            else: "expect no_warn"

        info =
          if resets == "0",
            do: "expect info msg: PromQL info: mismatched custom buckets were reconciled during subtraction",
            else: "expect no_info"

        check(
          "eval instant at 20s histogram_count(irate(#{name}[30s]))",
          ["{} " <> rate, warning, info],
          "custom-reset"
        )

        check(
          "eval instant at 20s resets(#{name}[30s])",
          ["{} " <> resets, "expect no_warn", "expect no_info"],
          "custom-reset"
        )
      end

      for op <- ["rate", "increase"],
          do: check("eval instant at 20s histogram_count(#{op}(same[30s]))", ["{} 0"], "custom-reset")

      queries = [
        {"warning", "irate(gauge[30s])", %{end_ts_ns: 20_000_000_000}},
        {"quiet", "irate(decrease[30s])", %{end_ts_ns: 20_000_000_000}}
      ]

      for batch <- [queries, Enum.reverse(queries)] do
        assert {:ok, results} = Evaluator.query_batch(batch, "custom-reset", fn result, _ -> {:ok, result} end)

        assert results["warning"]["warnings"] == [
                 ~s(PromQL warning: this native histogram metric is not a counter: "gauge")
               ]

        assert results["warning"]["infos"] == [
                 "PromQL info: mismatched custom buckets were reconciled during subtraction"
               ]

        assert Map.get(results["quiet"], "warnings", []) == []
        assert Map.get(results["quiet"], "infos", []) == []
      end
    end

    @tag adapter: adapter, delta_batch: true
    test "Pulse delta validates whole-window types but subtracts only endpoint histograms through #{inspect(adapter)}" do
      inputs = [
        "middle_counter {{count:3 sum:6 counter_reset_hint:gauge}} {{count:100}} {{count:1 sum:2 counter_reset_hint:gauge}}",
        "middle_schema {{count:3 sum:6 counter_reset_hint:gauge}} {{schema:-53 count:100}} {{count:1 sum:2 counter_reset_hint:gauge}}",
        "end_counter {{count:3 sum:6 counter_reset_hint:gauge}} {{count:100}} {{count:1 sum:2}}",
        "end_schema {{count:3 sum:6 counter_reset_hint:gauge}} {{count:100}} {{schema:-53 count:1 sum:2}}",
        "mixed {{count:3 sum:6 counter_reset_hint:gauge}} 100 {{count:1 sum:2 counter_reset_hint:gauge}}",
        "one _ _ {{count:1 sum:2}}",
        "custom {{schema:-53 count:10 sum:5 custom_values:[-1 1] buckets:[2 3 5] counter_reset_hint:gauge}} _ {{schema:-53 count:31 sum:50 custom_values:[0 2] buckets:[7 11 13] counter_reset_hint:gauge}}"
      ]

      assert :ok = Storage.append(:metrics, "window-delta", Enum.flat_map(inputs, &records(&1, 10_000_000_000)))

      gauge = "{} {{count:-3 sum:-6 counter_reset_hint:gauge}}"

      for {name, values, notices} <- [
            {"middle_counter", [gauge], ["expect no_warn", "expect no_info"]},
            {"middle_schema", [gauge], ["expect no_warn", "expect no_info"]},
            {"end_counter", [gauge],
             [
               ~s(expect warn msg: PromQL warning: this native histogram metric is not a gauge: "end_counter"),
               "expect no_info"
             ]},
            {"end_schema", [],
             [
               ~s(expect warn msg: PromQL warning: vector contains a mix of histograms with exponential and custom buckets schemas for metric name "end_schema"),
               "expect no_info"
             ]},
            {"mixed", [],
             [
               ~s(expect warn msg: PromQL warning: encountered a mix of histograms and floats for metric name "mixed"),
               "expect no_info"
             ]},
            {"one", [], ["expect no_warn", "expect no_info"]},
            {"custom", ["{} {{schema:-53 count:31.5 sum:67.5 buckets:[31.5] counter_reset_hint:gauge}}"],
             [
               "expect no_warn",
               "expect info msg: PromQL info: mismatched custom buckets were reconciled during subtraction"
             ]}
          ] do
        check("eval instant at 20s delta(#{name}[30s])", values ++ notices, "window-delta")
      end

      queries =
        for {name, metric} <- [{"warning", "end_counter"}, {"info", "custom"}, {"quiet", "middle_schema"}],
            do: {name, "delta(#{metric}[30s])", %{end_ts_ns: 20_000_000_000}}

      for batch <- [queries, Enum.reverse(queries)] do
        assert {:ok, results} = Evaluator.query_batch(batch, "window-delta", fn result, _ -> {:ok, result} end)

        assert results["warning"]["warnings"] == [
                 ~s(PromQL warning: this native histogram metric is not a gauge: "end_counter")
               ]

        assert results["info"]["infos"] == ["PromQL info: mismatched custom buckets were reconciled during subtraction"]
        assert Map.get(results["quiet"], "warnings", []) == []
        assert Map.get(results["quiet"], "infos", []) == []
      end
    end

    @tag adapter: adapter, idelta_batch: true
    test "Pulse idelta subtracts the last pair without reset correction or time scaling through #{inspect(adapter)}" do
      inputs = [
        "gauge _ {{count:5 sum:15 buckets:[2 3] counter_reset_hint:gauge}} {{count:2 sum:6 buckets:[1 1] counter_reset_hint:gauge}}",
        "history 7 {{count:5 sum:5}} {{count:3 sum:3 counter_reset_hint:gauge}} {{count:2 sum:2 counter_reset_hint:gauge}}",
        "disjoint _ {{schema:-53 count:10 sum:5 custom_values:[-1 1] buckets:[2 3 5] counter_reset_hint:gauge}} {{schema:-53 count:31 sum:50 custom_values:[0 2] buckets:[7 11 13] counter_reset_hint:gauge}}",
        "common _ {{schema:-53 count:17 custom_values:[-2 1 4] buckets:[2 3 5 7] counter_reset_hint:gauge}} {{schema:-53 count:112 custom_values:[-1 1 3 4 9] buckets:[11 13 17 19 23 29] counter_reset_hint:gauge}}"
      ]

      assert :ok = Storage.append(:metrics, "instant-delta", Enum.flat_map(inputs, &records(&1, 10_000_000_000)))

      for {name, at, window, histogram, notices} <- [
            {"gauge", "30s", "30s", "{{count:-3 sum:-9 buckets:[-1 -2] counter_reset_hint:gauge}}", ["expect no_info"]},
            {"history", "40s", "50s", "{{count:-1 sum:-1 counter_reset_hint:gauge}}", ["expect no_info"]},
            {"disjoint", "30s", "30s", "{{schema:-53 count:21 sum:45 buckets:[21] counter_reset_hint:gauge}}",
             ["expect info msg: PromQL info: mismatched custom buckets were reconciled during subtraction"]},
            {"common", "30s", "30s",
             "{{schema:-53 count:95 custom_values:[1 4] buckets:[19 31 45] counter_reset_hint:gauge}}",
             ["expect info msg: PromQL info: mismatched custom buckets were reconciled during subtraction"]}
          ] do
        check(
          "eval instant at #{at} idelta(#{name}[#{window}])",
          ["{} " <> histogram, "expect no_warn" | notices],
          "instant-delta"
        )
      end

      nanos =
        for {ts, number} <- [{1, 13.0}, {2, 8.0}, {3, 3.0}],
            do: %MetricSample{labels: %{"__name__" => "nano_delta"}, timestamp_ns: ts, value: number}

      assert :ok = Storage.append(:metrics, "instant-delta", nanos)

      for query <- ["idelta(nano_delta[2s])", "idelta(nano_delta[2s] @ 1)"],
          do: check("eval instant at 1s " <> query, ["{} -5", "expect no_warn", "expect no_info"], "instant-delta")

      check("eval instant at 30s idelta(vector(time())[3s:1s])", ["{} 1"], "instant-delta")
      check("eval instant at 30s idelta(gauge[10s])", [], "instant-delta")
      check("eval instant at 30s idelta(gauge[30s])", [], "other-tenant")

      response =
        build_conn()
        |> put_req_header("x-scope-orgid", "instant-delta")
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post("/api/v1/query", URI.encode_query(query: "histogram_count(idelta(gauge[30s]))", time: "30"))
        |> json_response(200)

      assert_samples(response["data"]["result"], ["{} -3"], 30, 1, "idelta form POST")
    end

    @tag adapter: adapter, idelta_batch: true, irate_batch: true, delta_batch: true
    test "Pulse idelta shares scan, bucket-work and result budgets and isolates notices through #{inspect(adapter)}" do
      histogram = %NativeHistogram{
        schema: -53,
        custom_values: Enum.map(1..64, &(&1 / 1)),
        count: 1.0,
        sum: 1.0,
        positive_spans: [{0, 1}],
        positive_buckets: [1.0],
        counter_reset_hint: :gauge
      }

      samples =
        for ts <- [10, 20],
            do: %MetricSample{labels: %{"__name__" => "costly"}, timestamp_ns: ts * 1_000_000_000, histogram: histogram}

      assert :ok =
               Storage.append(
                 :metrics,
                 "idelta-cost",
                 samples ++
                   records("plain 9 5 2", 10_000_000_000) ++
                   records("counter _ {{count:2}} {{count:3}}", 10_000_000_000)
               )

      queries = [
        {"warning", "idelta(counter[30s])", %{end_ts_ns: 20_000_000_000}},
        {"quiet", "idelta(plain[30s])", %{end_ts_ns: 20_000_000_000}}
      ]

      for batch <- [queries, Enum.reverse(queries)] do
        assert {:ok, results} = Evaluator.query_batch(batch, "idelta-cost", fn result, _ -> {:ok, result} end)

        assert results["warning"]["warnings"] == [
                 ~s(PromQL warning: this native histogram metric is not a gauge: "counter")
               ]

        assert Map.get(results["quiet"], "warnings", []) == []
        assert Map.get(results["quiet"], "infos", []) == []
      end

      Runtime.put_env(:pulse, Evaluator, max_work: 80)
      assert {:ok, _} = Evaluator.query("costly", "idelta-cost", %{end_ts_ns: 20_000_000_000})

      for op <- ["idelta", "irate", "delta"] do
        assert {:error, :query_work_limit} =
                 Evaluator.query("#{op}(costly[30s])", "idelta-cost", %{end_ts_ns: 20_000_000_000})
      end

      Runtime.put_env(:pulse, Evaluator, max_work: 240)
      source = {"one", "idelta(costly[30s])", %{end_ts_ns: 20_000_000_000}}
      assert {:ok, _} = Evaluator.query_batch([source], "idelta-cost", fn result, _ -> {:ok, result} end)

      assert {:error, :query_work_limit} =
               Evaluator.query_batch([source, put_elem(source, 0, "two")], "idelta-cost", fn _, _ ->
                 flunk("partial idelta batch")
               end)

      for {opts, reason} <- [{[max_samples: 1], :query_sample_limit}, {[max_result_points: 1], :query_result_limit}] do
        Runtime.put_env(:pulse, Evaluator, opts)

        assert {:error, ^reason} =
                 Evaluator.query("idelta(costly[30s])", "idelta-cost", %{
                   start_ts_ns: 20_000_000_000,
                   end_ts_ns: 21_000_000_000,
                   step_ns: 1_000_000_000
                 })
      end
    end

    @tag adapter: adapter
    @tag :histogram_fraction_batch
    test "Pulse classic fractions interpolate without quantile repairs through #{inspect(adapter)}" do
      for {name, buckets} <- [
            {"positive", [{"1", 2}, {"3", 6}, {"+Inf", 10}]},
            {"negative", [{"-2", 4}, {"-1", 6}, {"+Inf", 10}]},
            {"crossing", [{"-2", 2}, {"2", 6}, {"+Inf", 10}]},
            {"decreasing", [{"1", 8}, {"2", 4}, {"+Inf", 10}]},
            {"duplicate", [{"1", 2}, {"1.0", 3}, {"+Inf", 10}]},
            {"missing_inf", [{"1", 2}, {"3", 6}]},
            {"only_inf", [{"+Inf", 10}]},
            {"empty", [{"1", 0}, {"+Inf", 0}]}
          ] do
        samples = Enum.flat_map(buckets, fn {bound, count} -> records(~s(#{name}{le="#{bound}"} #{count}), 1) end)
        assert :ok = Storage.append(:metrics, "classic-fractions", samples)
      end

      for {name, lower, upper, expected} <- [
            {"positive", "0", "1", "0.2"},
            {"positive", "0", "2", "0.4"},
            {"positive", "1", "3", "0.4"},
            {"positive", "2", "4", "0.2"},
            {"positive", "4", "+Inf", "0.4"},
            {"positive", "-Inf", "+Inf", "1"},
            {"positive", "2", "2", "0"},
            {"positive", "3", "1", "0"},
            {"positive", "NaN", "1", "NaN"},
            {"positive", "0", "NaN", "NaN"},
            {"negative", "-3", "-1.5", "0.1"},
            {"negative", "-Inf", "-3", "0.4"},
            {"crossing", "-1", "1", "0.2"},
            {"decreasing", "1", "2", "-0.4"},
            {"duplicate", "0", "1", "0.5"},
            {"missing_inf", "0", "1", "NaN"},
            {"missing_inf", "1", "0", "NaN"},
            {"empty", "0", "1", "NaN"},
            {"empty", "1", "0", "NaN"},
            {"only_inf", "0", "10", "0"},
            {"only_inf", "0", "+Inf", "1"}
          ] do
        check(
          "eval instant at 0 histogram_fraction(#{lower},#{upper},#{name})",
          ["{} " <> expected, "expect no_info", "expect no_warn"],
          "classic-fractions"
        )
      end

      check(
        "eval range from 0 to 3s step 1s histogram_fraction(time(),3,positive)",
        ["{} 0.6 0.4 0.2 0", "expect no_info", "expect no_warn"],
        "classic-fractions"
      )

      check("eval instant at 0 histogram_fraction(0,1,missing)", [], "classic-fractions")

      queries = [
        {"fraction", "histogram_fraction(0,2,positive)", %{end_ts_ns: 0}},
        {"quantile", "histogram_quantile(0.5,decreasing)", %{end_ts_ns: 0}}
      ]

      assert {:ok, results} = Evaluator.query_batch(queries, "classic-fractions", fn values, _ -> {:ok, values} end)
      refute Map.has_key?(results["fraction"], "infos")
      assert [_] = results["quantile"]["infos"]

      Runtime.put_env(:pulse, Evaluator, max_work: 2)

      assert {:error, :query_work_limit} =
               Evaluator.query("histogram_fraction(0,2,positive)", "classic-fractions", %{end_ts_ns: 0})
    end

    @tag adapter: adapter
    @tag :result_types_batch
    test "Pulse top-level results retain source times, types and query clocks through #{inspect(adapter)}" do
      assert :ok = Storage.append(:metrics, "raw-result", records("raw 99 2 stale NaN +Inf -Inf -0 7", 1_000_000_000))

      for {query, time} <- [
            {"raw[3s]", "3"},
            {"raw[3s] offset 1s", "4"},
            {"raw[3s] offset -1s", "2"},
            {"raw[3s] @ 3", "90"},
            {"raw[3s] @ end()", "3"},
            {"(raw)[3s:1s]", "3"}
          ] do
        request(
          "/api/v1/query",
          %{query: query, time: time},
          ["expect range vector from 1s to 3s step 1s", "raw 2 _ NaN"],
          "raw-result",
          query,
          0,
          1
        )
      end

      request(
        "/api/v1/query",
        %{query: "raw[3s:]", time: "3"},
        ["expect range vector from 1s to 3s step 1s"],
        "raw-result",
        "empty minute grid",
        0,
        1
      )

      for method <- [:get, :post] do
        conn = build_conn() |> put_req_header("x-scope-orgid", "raw-result")
        params = %{query: "raw[7s]", time: "7"}
        response = if method == :get, do: get(conn, "/api/v1/query", params), else: post(conn, "/api/v1/query", params)

        assert %{
                 "data" => %{
                   "resultType" => "matrix",
                   "result" => [
                     %{
                       "metric" => %{"__name__" => "raw"},
                       "values" => [[1.0, "2"], [3.0, "NaN"], [4.0, "+Inf"], [5.0, "-Inf"], [6.0, "-0"], [7.0, "7"]]
                     }
                   ]
                 }
               } = json_response(response, 200)

        for {query, expected} <- [{~S|"quote\n\u03bb"|, "quote\nλ"}, {~S|'\x00'|, <<0>>}, {"` raw \\ `", " raw \\ "}] do
          params = %{query: query, time: "20.125000001"}

          response =
            if method == :get, do: get(conn, "/api/v1/query", params), else: post(conn, "/api/v1/query", params)

          assert %{"data" => %{"resultType" => "string", "result" => [20.125000001, ^expected]}} =
                   json_response(response, 200)
        end
      end

      for {query, time, window, expected} <- [
            {"raw[3s]", "3.999999999", "1s to 3s", "raw 2 _ NaN"},
            {"raw[3s]", "4", "2s to 4s", "raw _ NaN +Inf"},
            {"raw[3s]", "4.000000001", "2s to 4s", "raw _ NaN +Inf"},
            {"raw[3s] offset -1s", "3.000000001", "2s to 4s", "raw _ NaN +Inf"}
          ] do
        request(
          "/api/v1/query",
          %{query: query, time: time},
          ["expect range vector from #{window} step 1s", expected],
          "raw-result",
          query,
          0,
          1
        )
      end

      assert :ok = Storage.append(:metrics, "raw-result", records("mixed 3 {{count:2 sum:5}} stale", 1_000_000_000))

      request(
        "/api/v1/query",
        %{query: "mixed[3s]", time: "2"},
        ["expect range vector from 0s to 2s step 1s", "mixed 3 {{count:2 sum:5}}"],
        "raw-result",
        "mixed",
        0,
        1
      )

      request(
        "/api/v1/query",
        %{query: "raw[7s]", time: "7"},
        ["expect range vector from 1s to 7s step 1s"],
        "other-tenant",
        "isolation",
        0,
        1
      )
    end

    @tag adapter: adapter
    @tag :result_types_batch
    test "Pulse top-level result budgets fail whole through #{inspect(adapter)}" do
      assert :ok = Storage.append(:metrics, "raw-budget", records("raw 1+1x4", 1_000_000_000))

      for {query, limits} <- [
            {"raw[5s]", [max_samples: 4]},
            {"raw[5s]", [max_work: 4]},
            {"raw[5s]", [max_result_points: 4]},
            {"raw[5s:1s]", [max_materialized_samples: 4]},
            {~s("text"), [max_result_points: 0]}
          ] do
        Runtime.put_env(:pulse, Evaluator, limits)

        conn =
          build_conn()
          |> put_req_header("x-scope-orgid", "raw-budget")
          |> get("/api/v1/query", %{query: query, time: "4"})

        assert %{
                 "errorType" => "execution",
                 "error" => "query exceeded " <> _
               } = json_response(conn, 422)
      end

      Runtime.put_env(:pulse, Evaluator, max_samples: 5, max_result_points: 5)

      request(
        "/api/v1/query",
        %{query: "raw[5s]", time: "4"},
        ["expect range vector from 0s to 4s step 1s", "raw 1 2 3 4 5"],
        "raw-budget",
        "budget boundary",
        0,
        1
      )
    end

    @tag adapter: adapter
    @tag grammar_batch: true
    test "Pulse omitted resolutions retain independent minute grids through #{inspect(adapter)}" do
      # A moving value makes an outer-step or window-derived default observably wrong.
      assert :ok = Storage.append(:metrics, "default-grid", records("grid 0+1x100", 10_000_000_000))

      for {query, expected} <- [
            {"sum_over_time(grid[130:])", ["{} 30 42 42"]},
            {"sum_over_time(grid[130:60])", ["{} 30 42 42"]},
            {"sum_over_time(grid[130:] @ start())", ["{} 30 30 30"]},
            {"sum_over_time(grid[130:] @ end())", ["{} 42 42 42"]},
            {"sum_over_time(grid[130:] offset -10)", ["{} 54 42 42"]},
            {"sum_over_time(sum_over_time(grid[130:])[130:])", ["{} 54 90 90"]},
            {"sum_over_time(vector(step())[130:])", ["{} 50 50 50"]},
            {"sum_over_time(grid[(range()+80):])", ["{} 30 42 42"]}
          ] do
        check("eval range from 230s to 280s step 25s " <> query, expected, "default-grid")
      end

      check("eval instant at 230s sum_over_time(grid[130:])", ["{} 30"], "default-grid")
      check("eval instant at 230s count_over_time(grid[30:])", [], "default-grid")

      assert :ok =
               Storage.append(
                 :metrics,
                 "default-grid",
                 records("hist_grid {{count:2 sum:3}} {{count:5 sum:7}}", 60_000_000_000)
               )

      check("eval instant at 120s last_over_time(hist_grid[130:])", ["hist_grid {{count:5 sum:7}}"], "default-grid")
      request("/api/v1/query", %{query: "sum_over_time(grid[130:])", time: "230"}, [], "other", "empty", 230, 1)

      conn =
        build_conn()
        |> put_req_header("x-scope-orgid", "default-grid")
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post("/api/v1/query", URI.encode_query(query: "sum_over_time(grid[130:])", time: "230"))

      assert %{"data" => %{"result" => [%{"value" => [230.0, "30"]}]}} = json_response(conn, 200)

      for limits <- [[max_samples: 1], [max_work: 1], [max_result_points: 1]] do
        Runtime.put_env(:pulse, Evaluator, limits)

        assert %{"status" => "error", "errorType" => "execution"} =
                 build_conn()
                 |> put_req_header("x-scope-orgid", "default-grid")
                 |> get("/api/v1/query_range", query: "sum_over_time(grid[130:])", start: "230", end: "280", step: "25")
                 |> json_response(422)
      end

      Runtime.put_env(:pulse, Evaluator, [])
      assert {:error, :query_work_limit} = Evaluator.query("sum_over_time(grid[1y:])", "default-grid", %{end_ts_ns: 0})
    end

    @tag adapter: adapter
    @tag grammar_batch: true
    test "Pulse numeric time spellings preserve exact boundaries through #{inspect(adapter)}" do
      samples =
        for {ns, value} <- [{0, 2}, {10_000_000_000, 3}, {16_000_000_000, 5}, {16_000_000_001, 7}] do
          %MetricSample{labels: %{"__name__" => "numeric"}, timestamp_ns: ns, value: value * 1.0}
        end

      assert :ok = Storage.append(:metrics, "numeric-time", samples)

      for query <- ["numeric @ 0x10", "numeric @ 0X_10", "numeric @ 1_6", "numeric @ 0_20"] do
        check("eval instant at 30s " <> query, ["numeric 5"], "numeric-time")
      end

      for {query, expected} <- [
            {"timestamp(numeric @ 0x10)", ["{} 16"]},
            {"numeric @ 1_6.000_000_001", ["numeric 7"]},
            {"numeric offset 0x10", ["numeric 3"]},
            {"numeric offset (0x10 + 1_4)", ["numeric 2"]},
            {"sum_over_time(numeric[0x10] @ 0x10)", ["{} 8"]},
            {"sum_over_time(numeric[1_6.000_000_001] @ 1_6.000_000_001)", ["{} 15"]},
            {"sum_over_time(numeric[(0x10+1_4):0xA] @ 0x1e)", ["{} 17"]}
          ] do
        check("eval instant at 30s " <> query, expected, "numeric-time")
      end

      # Contemporary epoch nanoseconds must not pass through a float.
      assert :ok =
               Storage.append(:metrics, "numeric-time", [
                 %MetricSample{labels: %{"__name__" => "epoch"}, timestamp_ns: 1_790_000_000_000_000_001, value: 11.0},
                 %MetricSample{labels: %{"__name__" => "epoch"}, timestamp_ns: 1_790_000_000_000_000_002, value: 13.0}
               ])

      check("eval instant at 0 epoch @ 1_790_000_000.000_000_001", ["epoch 11"], "numeric-time")

      for query <- [
            "numeric @ 1__6",
            "numeric @ 0x_",
            "numeric @ 1_.0",
            "numeric @ 0x1p4",
            "numeric @ 0x10000000000000000",
            "numeric offset 0x1e13381",
            "sum_over_time(numeric[1_6:0x0])",
            "sum_over_time(numeric[0x10_])"
          ] do
        assert %{"errorType" => "bad_data"} =
                 build_conn() |> get("/api/v1/query", query: query, time: "30") |> json_response(400)
      end
    end

    @tag adapter: adapter
    @tag grammar_batch: true
    test "Pulse quoted grouping and matching preserve label identities through #{inspect(adapter)}" do
      samples =
        for {metric, labels, value} <- [
              {"left", %{"zone😀" => "a", "instance.id" => "1"}, 2},
              {"left", %{"zone😀" => "a", "instance.id" => "2"}, 5},
              {"left", %{"zone😀" => "b", "instance.id" => "3"}, 11},
              {"right", %{"zone😀" => "a", "owner name" => "alice"}, 3},
              {"right", %{"zone😀" => "b", "owner name" => "bob"}, 7}
            ] do
          %MetricSample{labels: Map.put(labels, "__name__", metric), timestamp_ns: 0, value: value * 1.0}
        end

      assert :ok = Storage.append(:metrics, "quoted-labels", samples)

      for {query, expected} <- [
            {~s|sum by ("zone😀") (left)|, [~s|{"zone😀"="a"} 7|, ~s|{"zone😀"="b"} 11|]},
            {~s|sum(left) without ('instance.id')|, [~s|{"zone😀"="a"} 7|, ~s|{"zone😀"="b"} 11|]},
            {~s|sum by ("zone😀") (left) + on ("zone😀",) sum by ("zone😀") (right)|,
             [~s|{"zone😀"="a"} 10|, ~s|{"zone😀"="b"} 18|]},
            {~s|sum without ("instance.id") (left) + ignoring (`owner name`,) right|,
             [~s|{"zone😀"="a"} 10|, ~s|{"zone😀"="b"} 18|]},
            {~s|left * on ("zone😀") group_left ("owner name",) right|,
             [
               ~s|{"zone😀"="a","instance.id"="1","owner name"="alice"} 6|,
               ~s|{"zone😀"="a","instance.id"="2","owner name"="alice"} 15|,
               ~s|{"zone😀"="b","instance.id"="3","owner name"="bob"} 77|
             ]},
            {~s|right / on ("zone😀") group_right ("owner name") left|,
             [
               ~s|{"zone😀"="a","instance.id"="1","owner name"="alice"} 1.5|,
               ~s|{"zone😀"="a","instance.id"="2","owner name"="alice"} 0.6|,
               ~s|{"zone😀"="b","instance.id"="3","owner name"="bob"} 0.6363636363636364|
             ]},
            {~s|sum by ("zone😀") (left) and on ("zone😀") right{"zone😀"="a"}|, [~s|{"zone😀"="a"} 7|]},
            {~s|label_replace(right, "owner.alias", "$1", "owner name", "(.*)")|,
             [
               ~s|right{"zone😀"="a","owner name"="alice","owner.alias"="alice"} 3|,
               ~s|right{"zone😀"="b","owner name"="bob","owner.alias"="bob"} 7|
             ]}
          ] do
        check("eval instant at 0 " <> query, expected, "quoted-labels")
      end

      for query <- [
            ~s|sum by ("") (left)|,
            ~s|sum by (job,"job") (left)|,
            ~s|left + on ("",) right|,
            ~s|left + on (job,"job") right|,
            ~s|left + on ("zone😀") group_left ("zone😀") right|
          ] do
        assert %{"errorType" => "bad_data"} =
                 build_conn() |> get("/api/v1/query", query: query, time: "0") |> json_response(400)
      end
    end
  end

  for adapter <- [Memory, S3] do
    @tag adapter: adapter
    @tag sampling: true
    test "Pulse sampling hashes select exact identities and preserve samples through #{inspect(adapter)}" do
      # Independent Go 1.25.10 / cespare xxhash v2.3.0 oracle using the pinned
      # stringlabels encoding, not Pulse's query hash or storage fingerprint.
      cases = [
        {0, 6_052_832_491_276_595_497},
        {1, 6_695_092_507_474_621_463},
        {7, 684_935_918_096_940_444},
        {8, 17_569_576_087_607_226_423},
        {15, 10_547_973_137_771_546_632},
        {16, 9_809_290_455_273_998_171},
        {31, 12_213_389_837_855_942_690},
        {32, 1_741_455_738_332_009_022},
        {254, 8_853_092_598_191_269_092},
        {255, 13_788_097_792_911_845_287},
        {256, 6_557_429_058_470_608_666},
        {1024, 18_210_241_903_618_378_418},
        {"unicode", 11_674_198_981_860_858_718},
        {"long_name", 1_668_686_600_217_069_987}
      ]

      samples =
        for {id, _} <- cases do
          labels = %{"__name__" => "sampling", "id" => to_string(id)}

          labels =
            case id do
              0 -> labels
              "unicode" -> Map.put(labels, "key", "é😀水")
              "long_name" -> Map.put(labels, String.duplicate("n", 255), "value")
              n -> Map.put(labels, "key", String.duplicate("x", n))
            end

          sample = %MetricSample{labels: labels, timestamp_ns: 0, value: 17.0}

          case id do
            0 ->
              %{
                sample
                | value: nil,
                  histogram: %NativeHistogram{
                    schema: 0,
                    count: 5.0,
                    sum: 7.0,
                    positive_spans: [{0, 2}],
                    positive_buckets: [2.0, 3.0]
                  }
              }

            1 ->
              %{sample | value: -0.0}

            7 ->
              %{sample | value: :nan}

            8 ->
              %{sample | value: :infinity}

            15 ->
              %{sample | value: :negative_infinity}

            _ ->
              sample
          end
        end

      assert :ok = Storage.append(:metrics, "sampling", samples)

      conn =
        build_conn()
        |> put_req_header("x-scope-orgid", "sampling")
        |> get("/api/v1/query", query: "sampling", time: "0")

      assert %{"data" => %{"result" => results}} = json_response(conn, 200)
      baseline = Map.new(results, &{&1["metric"]["id"], &1})
      assert map_size(baseline) == length(cases)
      assert baseline["1"]["value"] == [0.0, "-0"]
      assert baseline["7"]["value"] == [0.0, "NaN"]
      assert baseline["0"]["histogram"] != nil

      for {id, hash} <- cases do
        ratio = hash / 18_446_744_073_709_551_616
        <<bits::64>> = <<ratio::float-64>>
        <<above::float-64>> = <<bits + 1::64>>

        # Equality must exclude; the immediately adjacent representable ratio
        # must include, catching wrong hashes, >=, decimal rounding and uints.
        for {ratio, expected} <- [{ratio, []}, {above, [Map.fetch!(baseline, to_string(id))]}] do
          query = ~s|limit_ratio(#{ratio}, sampling{id="#{id}"})|

          conn =
            build_conn() |> put_req_header("x-scope-orgid", "sampling") |> get("/api/v1/query", query: query, time: "0")

          assert %{"data" => %{"result" => ^expected}} = response = json_response(conn, 200)
          assert Map.get(response, "warnings", []) == []
          assert Map.get(response, "infos", []) == []
        end
      end

      for {query, ids} <- [
            {"limitk(3.9, sampling)", ["7", "long_name", "32"]},
            {"limitk by(id)(1, sampling)", Map.keys(baseline)},
            {"limitk(1, sampling) without(key)", Map.keys(baseline)},
            {"limit_ratio(0.5, sampling)",
             for({id, hash} <- cases, hash < 9_223_372_036_854_775_808, do: to_string(id))},
            {"limit_ratio(-0.5, sampling)",
             for({id, hash} <- cases, hash >= 9_223_372_036_854_775_808, do: to_string(id))},
            {"limit_ratio(0.5, sampling) or limit_ratio(-0.5, sampling)", Map.keys(baseline)},
            {"limit_ratio(0.5, sampling) and limit_ratio(-0.5, sampling)", []}
          ] do
        conn =
          build_conn()
          |> put_req_header("x-scope-orgid", "sampling")
          |> put_req_header("content-type", "application/x-www-form-urlencoded")
          |> post("/api/v1/query", URI.encode_query(query: query, time: "0"))

        assert %{"data" => %{"result" => actual}} = json_response(conn, 200)
        assert Map.new(actual, &{&1["metric"]["id"], &1}) == Map.take(baseline, ids)
        request("/api/v1/query", %{query: query, time: "0"}, [], "other-tenant", query, 0, 1)
      end

      # Rewrite the id=1 float into the independently hashed id=0 labels. Its
      # original hash is above both thresholds, so reusing it loses the float.
      ratio = 6_052_832_491_276_595_497 / 18_446_744_073_709_551_616
      <<bits::64>> = <<ratio::float-64>>
      <<above::float-64>> = <<bits + 1::64>>
      rewritten = ~s|label_replace(label_join(sampling{id="1"}, "key", "", "missing"), "id", "0", "id", "1")|

      for {ratio, expected} <- [{ratio, []}, {above, [~s(sampling{id="0"} -0)]}],
          do: check("eval instant at 0 limit_ratio(#{ratio}, #{rewritten})", expected, "sampling")

      # Keeping all observations also admits the selector's intermediate points
      # at the exact output-point ceiling, independently of sample/work limits.
      for query <- ["limitk(100, sampling)", "limit_ratio(1, sampling)"] do
        source = {"one", query, %{end_ts_ns: 0}}

        assert {:ok, budget} =
                 Evaluator.query_batch([source], "sampling", fn _, _ -> {:ok, Process.get(:promql_budget)} end)

        for {setting, key, reason} <- [
              {:max_work, :work, :query_work_limit},
              {:max_samples, :samples, :query_sample_limit},
              {:max_result_points, :points, :query_result_limit}
            ] do
          Runtime.put_env(:pulse, Evaluator, [{setting, Map.fetch!(budget, key) - 1}])
          assert {:error, ^reason} = Evaluator.query_batch([source], "sampling", fn _, _ -> flunk("partial result") end)
          Runtime.put_env(:pulse, Evaluator, [{setting, Map.fetch!(budget, key)}])
          assert {:ok, _} = Evaluator.query_batch([source], "sampling", fn result, _ -> {:ok, result} end)

          assert {:error, ^reason} =
                   Evaluator.query_batch([source, {"two", query, %{end_ts_ns: 0}}], "sampling", fn _, _ ->
                     flunk("partial batch")
                   end)

          Runtime.put_env(:pulse, Evaluator, [])
        end
      end
    end

    @tag adapter: adapter
    @tag sampling: true
    test "Pulse sampling validates empty inputs and isolates range warnings through #{inspect(adapter)}" do
      for {op, parameter} <- [
            {"limitk", "NaN"},
            {"limitk", "Inf"},
            {"limitk", "-Inf"},
            {"limitk", "9223372036854775808"},
            {"limitk", "-9223372036854775808"},
            {"limit_ratio", "NaN"}
          ],
          input <- ["absent_metric", "vector(1)"] do
        query = "#{op}(#{parameter}, #{input})"
        assert {:error, :invalid_aggregation_parameter} = Evaluator.query(query, "empty-sampling", %{end_ts_ns: 0})

        for {path, params} <- [
              {"/api/v1/query", %{query: query, time: "0"}},
              {"/api/v1/query_range", %{query: query, start: "0", end: "1", step: "1s"}}
            ] do
          conn = build_conn() |> put_req_header("x-scope-orgid", "empty-sampling") |> get(path, params)

          assert %{
                   "status" => "error",
                   "errorType" => "execution",
                   "error" => "Ranking requires a scalar other than NaN and below the signed int64 maximum."
                 } = json_response(conn, 422)
        end
      end

      for query <- ["limitk(-1, absent_metric)", "limitk(-0.9, vector(1))", "limit_ratio(-0, vector(1))"],
          do: check("eval instant at 0 " <> query, ["expect no_info", "expect no_warn"], "empty-sampling")

      query = "limit_ratio(2 + 4 * (time() % 3 - 1), absent_metric)"

      assert {:ok, results} =
               Evaluator.query_batch(
                 [
                   {"range", query, %{start_ts_ns: 0, end_ts_ns: 5_000_000_000, step_ns: 1_000_000_000}},
                   {"instant", "limit_ratio(0.5, absent_metric)", %{end_ts_ns: 0}}
                 ],
                 "empty-sampling",
                 fn result, _ -> {:ok, result} end
               )

      assert results["range"]["data"]["result"] == []

      assert results["range"]["warnings"] == [
               "PromQL warning: ratio value should be between -1 and 1, got -2, capping to -1",
               "PromQL warning: ratio value should be between -1 and 1, got 2, capping to 1"
             ]

      refute Map.has_key?(results["instant"], "warnings")

      for {parameter, formatted, capped} <- [{"Inf", "+Inf", "1"}, {"-Inf", "-Inf", "-1"}] do
        check(
          "eval instant at 0 limit_ratio(#{parameter}, absent_metric)",
          [
            "expect warn msg: PromQL warning: ratio value should be between -1 and 1, got #{formatted}, capping to #{capped} (1:13)"
          ],
          "empty-sampling"
        )
      end
    end

    @tag adapter: adapter
    test "Pulse aggregation populations change only at selected nonstale steps through #{inspect(adapter)}" do
      samples =
        for {instance, values} <- [{"a", [1.0, :stale, :stale]}, {"b", [2.0, 4.0, :stale]}, {"c", [6.0, 8.0, 8.0]}],
            {value, index} <- Enum.with_index(values) do
          %MetricSample{
            labels: %{"__name__" => "spread", "job" => "api", "instance" => instance},
            timestamp_ns: index * 10_000_000_000,
            value: value
          }
        end

      # This histogram exists only between steps and must not produce notices.
      transient = [
        %MetricSample{
          labels: %{"__name__" => "spread", "job" => "api", "instance" => "hist"},
          timestamp_ns: 5_000_000_000,
          histogram: %NativeHistogram{count: 1.0, sum: 2.0}
        },
        %MetricSample{
          labels: %{"__name__" => "spread", "job" => "api", "instance" => "hist"},
          timestamp_ns: 9_000_000_000,
          value: :stale
        }
      ]

      assert :ok = Storage.append(:metrics, "aggregate-populations", samples ++ transient)

      for {query, expected} <- [
            {"stdvar by(job)(spread)", ~s({job="api"} 4.666666666666667 4 0)},
            {"stddev without(instance)(spread)", ~s({job="api"} 2.160246899469287 2 0)},
            {"quantile by(job)(0.25, spread)", ~s({job="api"} 1.5 5 8)},
            {"sum(count_values(\"value\", spread))", "{} 3 2 1"}
          ] do
        check(
          "eval range from 0 to 20s step 10s " <> query,
          [expected, "expect no_info", "expect no_warn"],
          "aggregate-populations"
        )
      end

      response =
        build_conn()
        |> put_req_header("x-scope-orgid", "aggregate-populations")
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post("/api/v1/query", URI.encode_query(query: "stddev(spread)", time: "10"))
        |> json_response(200)

      assert response["data"]["result"] == [%{"metric" => %{}, "value" => [10.0, "2"]}]
      refute Map.has_key?(response, "infos")
      request("/api/v1/query", %{query: "stddev(spread)", time: "10"}, [], "other-tenant", "stddev", 10, 1)

      queries = [
        {"hist", "stddev(spread)", %{end_ts_ns: 5_000_000_000}},
        {"bad_q", "quantile(2, absent_metric)", %{end_ts_ns: 0}},
        {"large_q", "quantile(1e6, absent_metric)", %{end_ts_ns: 0}},
        {"good_q", "quantile(0.25, spread)", %{end_ts_ns: 0}}
      ]

      assert {:ok, results} = Evaluator.query_batch(queries, "aggregate-populations", fn values, _ -> {:ok, values} end)
      assert results["hist"]["infos"] == ["PromQL info: ignored histogram in stddev aggregation"]
      assert results["bad_q"]["warnings"] == ["PromQL warning: quantile value should be between 0 and 1, got 2"]
      assert results["large_q"]["warnings"] == ["PromQL warning: quantile value should be between 0 and 1, got 1e+06"]
      refute Map.has_key?(results["good_q"], "infos")
      refute Map.has_key?(results["good_q"], "warnings")
    end

    @tag adapter: adapter
    test "Pulse value-count labels retain shortest floats and complete histogram text through #{inspect(adapter)}" do
      <<smallest::float-64>> = <<1::64>>
      expected = ["0.0000001", "1000000000000000000000", "0." <> String.duplicate("0", 323) <> "5", "-0", "0"]

      floats =
        for {value, index} <- Enum.with_index([1.0e-7, 1.0e21, smallest, -0.0, 0.0]),
            do: %MetricSample{
              labels: %{"__name__" => "formats", "instance" => "#{index}"},
              timestamp_ns: 0,
              value: value
            }

      histograms = [
        {%NativeHistogram{
           schema: -53,
           count: 4.0,
           sum: 2.0,
           custom_values: [-2.0, 0.0, 3.0],
           positive_spans: [{0, 4}],
           positive_buckets: [1.0, 2.0, 0.0, 1.0]
         }, "{count:4, sum:2, [-Inf,-2]:1, (-2,0]:2, (3,+Inf]:1}"},
        {%NativeHistogram{
           schema: 0,
           count: 2.0,
           sum: 1.0e7,
           zero_threshold: 0.75,
           zero_count: 1.0,
           positive_spans: [{0, 1}],
           positive_buckets: [1.0]
         }, "{count:2, sum:1e+07, [-0.75,0.75]:1, (0.5,1]:1}"}
      ]

      samples =
        for {{h, _}, index} <- Enum.with_index(histograms),
            do: %MetricSample{
              labels: %{"__name__" => "formats", "instance" => "hist#{index}"},
              timestamp_ns: 0,
              histogram: h
            }

      assert :ok = Storage.append(:metrics, "aggregate-formats", floats ++ samples)
      expected = expected ++ Enum.map(histograms, &elem(&1, 1))

      for query <- [~s|count_values("值😀", formats)|, ~s|count_values without(instance)("值😀", formats)|] do
        wanted = for text <- expected, do: "{\"值😀\"=" <> JSON.encode!(text) <> "} 1"
        check("eval instant at 0 " <> query, wanted ++ ["expect no_info", "expect no_warn"], "aggregate-formats")
      end

      # Match Mimir's group-then-set contract: the generated label survives
      # even if without names it. Prometheus's pinned engine differs here.
      wanted = for text <- expected, do: "{v=" <> JSON.encode!(text) <> "} 1"
      check(~s|eval instant at 0 count_values without(instance,v)("v",formats)|, wanted, "aggregate-formats")

      # Generated metric names are deliberate labels, not arithmetic name removal.
      wanted = for text <- Enum.take(expected, 2), do: "{__name__=" <> JSON.encode!(text) <> "} 1"
      check(~s[eval instant at 0 count_values("__name__", formats{instance=~"0|1"})], wanted, "aggregate-formats")
    end

    @tag adapter: adapter
    test "Pulse aggregations share scan, sort, generated-label and batch budgets through #{inspect(adapter)}" do
      samples =
        for index <- 1..8,
            do: %MetricSample{
              labels: %{"__name__" => "cost", "instance" => "#{index}"},
              timestamp_ns: 0,
              value: index * 1.0
            }

      assert :ok = Storage.append(:metrics, "aggregate-cost", samples)
      queries = ["stddev(cost)", "stdvar(cost)", "quantile(0.25,cost)", ~s|count_values("v",cost)|]

      # The selector holds eight points; most results are one. stddev and
      # stdvar fold each series in as it is selected and hold one state.
      for query <- queries,
          limits <- [[max_samples: 1], [max_work: 1], [max_materialized_samples: 7]],
          limits != [max_materialized_samples: 7] or String.starts_with?(query, ~w(quantile count_values)) do
        Runtime.put_env(:pulse, Evaluator, limits)

        conn =
          build_conn()
          |> put_req_header("x-scope-orgid", "aggregate-cost")
          |> get("/api/v1/query", query: query, time: "0")

        assert %{
                 "errorType" => "execution",
                 "error" => "query exceeded " <> _
               } = json_response(conn, 422)
      end

      Runtime.put_env(:pulse, Evaluator, max_materialized_samples: 1)
      assert {:ok, _} = Evaluator.query("stddev(cost)", "aggregate-cost", %{end_ts_ns: 0})

      Runtime.put_env(:pulse, Evaluator, max_work: 40)
      assert {:ok, _} = Evaluator.query("cost", "aggregate-cost", %{end_ts_ns: 0})
      assert {:error, :query_work_limit} = Evaluator.query("quantile(0.25,cost)", "aggregate-cost", %{end_ts_ns: 0})

      assert {:error, :query_work_limit} =
               Evaluator.query(~s|count_values("#{String.duplicate("v", 100)}",cost)|, "aggregate-cost", %{end_ts_ns: 0})

      Runtime.put_env(:pulse, Evaluator, max_samples: 8)
      batch = for {query, ref} <- Enum.with_index(queries), do: {"#{ref}", query, %{end_ts_ns: 0}}

      assert {:error, :query_sample_limit} =
               Evaluator.query_batch(batch, "aggregate-cost", fn _, _ -> flunk("partial aggregation batch") end)
    end

    @tag adapter: adapter
    test "Pulse scalar query context retains requested outer bounds through #{inspect(adapter)}" do
      for {query, expected} <- [
            {"start()", "10.125"},
            {"end()", "15.625"},
            {"step()", "2"},
            {"range()", "5.5"},
            {"min_of(time(), end() - step())", "10.125 12.125 13.625"},
            {"max_of(time(), start() + step())", "12.125 12.125 14.125"},
            {"avg_over_time(vector(start())[4s:1s] offset 3s)", "10.125"},
            {"avg_over_time(vector(end())[4s:1s])", "15.625"},
            {"avg_over_time(vector(step())[4s:1s])", "2"},
            {"avg_over_time(vector(range())[4s:1s])", "5.5"},
            {"avg_over_time(avg_over_time(vector(step())[2s:1s])[4s:2s])", "2"}
          ] do
        values = if String.contains?(expected, " "), do: expected, else: Enum.join(List.duplicate(expected, 3), " ")

        request(
          "/api/v1/query_range",
          %{query: query, start: "10.125", end: "15.625", step: "2s"},
          ["{} " <> values, "expect no_info", "expect no_warn"],
          "context",
          query,
          10.125,
          2
        )
      end

      # One evaluation step with different bounds still has a nonzero step.
      for {last, expected} <- [{"10", "0"}, {"11", "5"}] do
        request(
          "/api/v1/query_range",
          %{query: "step()", start: "10", end: last, step: "5s"},
          ["{} " <> expected],
          "context",
          "step()",
          10,
          5
        )
      end

      check("eval instant at 10s avg_over_time(vector(step())[4s:1s])", ["{} 0"], "context")
      check("eval instant at 10s end() - start() + range()", ["0"], "context")

      # Query context follows Pulse's existing nanosecond timestamp precision.
      conn =
        build_conn()
        |> get("/api/v1/query", query: "start() == bool time()", time: "-0.000000123")

      assert %{"data" => %{"resultType" => "scalar", "result" => [_, "1"]}} = json_response(conn, 200)

      # Go time.Duration saturates when the requested span exceeds int64 ns.
      request(
        "/api/v1/query_range",
        %{query: "range()", start: "-9223372036", end: "9223372036", step: "9223372036"},
        ["{} 9223372036.854776 9223372036.854776 9223372036.854776"],
        "context",
        "range() duration saturation",
        -9_223_372_036,
        9_223_372_036
      )
    end

    @tag adapter: adapter
    test "Pulse scalar extrema retain Go infinity, NaN and signed-zero rules through #{inspect(adapter)}" do
      # Expected rows/columns: -Inf, -3, -0, +0, 2, +Inf, NaN.
      inputs = ["-Inf", "-3", "-0", "0", "2", "Inf", "NaN"]

      minima = [
        ~w(-Inf -Inf -Inf -Inf -Inf -Inf -Inf),
        ~w(-Inf -3 -3 -3 -3 -3 NaN),
        ~w(-Inf -3 -0 -0 -0 -0 NaN),
        ~w(-Inf -3 -0 0 0 0 NaN),
        ~w(-Inf -3 -0 0 2 2 NaN),
        ~w(-Inf -3 -0 0 2 +Inf NaN),
        ~w(-Inf NaN NaN NaN NaN NaN NaN)
      ]

      maxima = [
        ~w(-Inf -3 -0 0 2 +Inf NaN),
        ~w(-3 -3 -0 0 2 +Inf NaN),
        ~w(-0 -0 -0 0 2 +Inf NaN),
        ~w(0 0 0 0 2 +Inf NaN),
        ~w(2 2 2 2 2 +Inf NaN),
        ~w(+Inf +Inf +Inf +Inf +Inf +Inf +Inf),
        ~w(NaN NaN NaN NaN NaN +Inf NaN)
      ]

      for {name, table} <- [{"min_of", minima}, {"max_of", maxima}],
          {left, row} <- Enum.zip(inputs, table),
          {right, expected} <- Enum.zip(inputs, row) do
        query = "#{name}(#{left}, #{right})"

        for {path, params} <- [
              {"/api/v1/query", %{time: "20"}},
              {"/api/v1/query_range", %{start: "20", end: "21", step: "1s"}}
            ] do
          conn = build_conn() |> get(path, Map.put(params, :query, query))
          assert %{"data" => data} = response = json_response(conn, 200)
          assert Map.get(response, "infos", []) == []
          assert Map.get(response, "warnings", []) == []

          if path == "/api/v1/query" do
            assert data == %{"resultType" => "scalar", "result" => [20.0, expected]}, query
          else
            assert data == %{
                     "resultType" => "matrix",
                     "result" => [%{"metric" => %{}, "values" => [[20.0, expected], [21.0, expected]]}]
                   },
                   query
          end
        end
      end
    end

    @tag adapter: adapter
    @tag :absence_replace_staleness_batch
    test "Pulse absence preserves multi-metric presence across types and expiry through #{inspect(adapter)}" do
      samples =
        records(~s(first{service="api"} 0 _ stale), 5_000_000_000)
        |> Enum.map(&%{&1 | timestamp_ns: &1.timestamp_ns + 10_000_000_000})

      histogram = value("{{count:0}}")

      samples =
        samples ++
          [
            %MetricSample{
              labels: %{"__name__" => "second", "service" => "api"},
              timestamp_ns: 15_000_000_000,
              histogram: histogram
            },
            %MetricSample{
              labels: %{"__name__" => "second", "service" => "api"},
              timestamp_ns: 25_000_000_000,
              histogram: %{histogram | sum: :stale}
            },
            %MetricSample{
              labels: %{"__name__" => "third", "service" => "api"},
              timestamp_ns: 30_000_000_000,
              value: :nan
            }
          ]

      assert :ok = Storage.append(:metrics, "absence-control", samples)
      query = ~s|absent_over_time({service="api"}[10s])|

      for method <- [:get, :post] do
        for {time, expected} <- [
              {"10", []},
              {"20", []},
              {"25", [~s({service="api"} 1)]},
              {"30", []},
              {"40", [~s({service="api"} 1)]}
            ] do
          params = %{query: query, time: time}
          conn = build_conn() |> put_req_header("x-scope-orgid", "absence-control")

          conn =
            if method == :get,
              do: get(conn, "/api/v1/query", params),
              else:
                conn
                |> put_req_header("content-type", "application/x-www-form-urlencoded")
                |> post("/api/v1/query", URI.encode_query(params))

          assert %{"status" => "success", "data" => %{"result" => result}} = json_response(conn, 200)
          assert_samples(result, expected, value(time), 1, query)
        end
      end

      request(
        "/api/v1/query_range",
        %{query: query, start: "10", end: "40", step: "5"},
        [~s({service="api"} _ _ _ 1 _ _ 1)],
        "absence-control",
        query,
        10,
        5
      )

      for limits <- [[max_samples: 1], [max_work: 1]] do
        Runtime.put_env(:pulse, Evaluator, limits)

        conn =
          build_conn()
          |> put_req_header("x-scope-orgid", "absence-control")
          |> get("/api/v1/query", query: query, time: "20")

        assert %{
                 "status" => "error",
                 "errorType" => "execution",
                 "error" => "query exceeded " <> _
               } =
                 json_response(conn, 422)
      end
    end

    @tag adapter: adapter
    test "Pulse range-presence controls through HTTP and #{inspect(adapter)}" do
      histogram = %NativeHistogram{
        schema: -53,
        custom_values: [2.0],
        positive_spans: [{0, 1}],
        positive_buckets: [1.0],
        count: 1.0,
        sum: 1.0
      }

      points = [
        {"boundary", 10, 0.0},
        {"nan", 20, :nan},
        {"positive_inf", 20, :infinity},
        {"negative_inf", 20, :negative_infinity},
        {"zero", 20, -0.0},
        {"stale", 20, :stale},
        {"stale_history", 19, 8.0},
        {"stale_history", 20, :stale},
        {"histogram", 20, histogram},
        {"histogram_stale", 20, %{histogram | sum: :stale}},
        {"mixed", 15, 2.0},
        {"mixed", 20, histogram},
        {"future", 21, 1.0}
      ]

      samples =
        for {kind, second, value} <- points do
          sample = %MetricSample{
            labels: %{"__name__" => "presence", "kind" => kind},
            timestamp_ns: second * 1_000_000_000
          }

          if is_struct(value, NativeHistogram), do: %{sample | histogram: value}, else: %{sample | value: value}
        end

      assert :ok = Storage.append(:metrics, "presence-control", samples)
      query = "present_over_time(presence[10s])"

      expected =
        for kind <- ~w(nan positive_inf negative_inf zero stale_history histogram mixed), do: ~s({kind="#{kind}"} 1)

      request("/api/v1/query", %{query: query, time: "20"}, expected, "presence-control", query, 20, 1)
      request("/api/v1/query", %{query: query, time: "20"}, [], "other-tenant", query, 20, 1)

      for {expression, time, expected} <- [
            {~s|present_over_time(presence{kind="boundary"}[10s])|, "19.999999999", [~s({kind="boundary"} 1)]},
            {~s|present_over_time(presence{kind="boundary"}[10s])|, "20", []},
            {~s|present_over_time(presence{kind="boundary"}[10s] offset 10s)|, "20", [~s({kind="boundary"} 1)]},
            {~s|present_over_time(presence{kind="histogram"}[10s:1s])|, "20", [~s({kind="histogram"} 1)]},
            {~s|present_over_time(presence{kind="histogram"}[10s:1s] offset 10s)|, "20", []},
            {~s|present_over_time(presence{kind="histogram"}[10s:1s] offset 10s)|, "30", [~s({kind="histogram"} 1)]},
            {"sum(present_over_time(presence[10s]))", "20", ["{} 7"]}
          ] do
        request(
          "/api/v1/query",
          %{query: expression, time: time},
          expected,
          "presence-control",
          expression,
          value(time),
          1
        )
      end

      conn =
        build_conn()
        |> put_req_header("x-scope-orgid", "presence-control")
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post("/api/v1/query", URI.encode_query(query: query, time: "20"))

      assert %{"status" => "success", "data" => %{"resultType" => "vector", "result" => result}} =
               json_response(conn, 200)

      assert_samples(result, expected, 20, 1, query)

      for limits <- [[max_samples: 1], [max_work: 1], [max_result_points: 1]] do
        Runtime.put_env(:pulse, Evaluator, limits)

        conn =
          build_conn()
          |> put_req_header("x-scope-orgid", "presence-control")
          |> get("/api/v1/query", query: query, time: "20")

        assert %{
                 "status" => "error",
                 "errorType" => "execution",
                 "error" => "query exceeded " <> _
               } = json_response(conn, 422)
      end
    end
  end

  for adapter <- [Memory, S3], function <- [:first_over_time, :last_over_time] do
    @tag adapter: adapter, function: function
    test "Pulse #{function} controls through HTTP and #{inspect(adapter)}", %{function: function} do
      first? = function == :first_over_time

      histogram = %NativeHistogram{
        schema: -53,
        custom_values: [2.0],
        positive_spans: [{0, 2}],
        positive_buckets: [1.0, 2.0],
        count: 3.0,
        sum: 5.0
      }

      points = [
        {"last_boundary", 10, 99.0},
        {"last_float", 17, :stale},
        {"last_float", 18, 9.0},
        {"last_float", 19, -2.0},
        {"last_float", 20, :stale},
        {"last_histogram", 18, 7.0},
        {"last_histogram", 19, histogram},
        {"last_mixed", 18, histogram},
        {"last_mixed", 19, 4.0},
        {"last_hist_stale", 17, %{histogram | sum: :stale}},
        {"last_hist_stale", 19, histogram},
        {"last_hist_stale", 20, %{histogram | sum: :stale}},
        {"last_stale", 20, :stale},
        {"last_future", 21, 8.0},
        {"last_nan", 20, :nan},
        {"last_inf", 20, :infinity},
        {"last_zero", 20, -0.0}
      ]

      samples =
        for {name, second, value} <- Enum.reverse(points) do
          sample = %MetricSample{labels: %{"__name__" => name}, timestamp_ns: second * 1_000_000_000}
          if is_struct(value, NativeHistogram), do: %{sample | histogram: value}, else: %{sample | value: value}
        end

      assert :ok = Storage.append(:metrics, "last-control", samples)
      query = ~s|#{function}({__name__=~"last_.*"}[10s])|

      floats =
        if first?,
          do: [{"last_float", "9"}, {"last_histogram", "7"}],
          else: [{"last_float", "-2"}, {"last_mixed", "4"}]

      expected =
        for {name, value} <-
              floats ++
                [
                  {"last_nan", "NaN"},
                  {"last_inf", "+Inf"},
                  {"last_zero", "-0"}
                ],
            do: %{"metric" => %{"__name__" => name}, "value" => [20, value]}

      histogram_names = if first?, do: ["last_mixed", "last_hist_stale"], else: ["last_histogram", "last_hist_stale"]

      expected =
        expected ++
          for name <- histogram_names do
            %{
              "metric" => %{"__name__" => name},
              "histogram" => [
                20,
                %{
                  "count" => "3",
                  "sum" => "5",
                  "buckets" => [[3, "-Inf", "2", "1"], [0, "2", "+Inf", "2"]]
                }
              ]
            }
          end

      for method <- [:get, :post] do
        conn = build_conn() |> put_req_header("x-scope-orgid", "last-control")
        params = %{query: query, time: "20"}

        conn =
          if method == :get,
            do: get(conn, "/api/v1/query", params),
            else:
              conn
              |> put_req_header("content-type", "application/x-www-form-urlencoded")
              |> post("/api/v1/query", URI.encode_query(params))

        assert %{"data" => %{"resultType" => "vector", "result" => actual}} = json_response(conn, 200)
        assert Enum.sort_by(actual, & &1["metric"]) == Enum.sort_by(expected, & &1["metric"])
      end

      for {expression, time, expected} <- [
            {"#{function}(last_boundary[10s])", "19.999999999", ["last_boundary 99"]},
            {"#{function}(last_boundary[10s])", "20", []},
            {"#{function}(last_boundary[10s] offset 10s)", "20", ["last_boundary 99"]},
            {"histogram_sum(#{function}(last_histogram[10s:1s] offset 10s))", "20", []},
            {"histogram_sum(#{function}(last_histogram[10s:1s] offset 10s))", "30", if(first?, do: [], else: ["{} 5"])},
            {"histogram_sum(#{function}(last_mixed[10s:1s] offset 10s))", "30", if(first?, do: ["{} 5"], else: [])}
          ] do
        request("/api/v1/query", %{query: expression, time: time}, expected, "last-control", expression, value(time), 1)
      end

      expression = "#{function}(last_float[10s])"
      expected = if first?, do: ["last_float 9 9 9 9 -2 _"], else: ["last_float -2 -2 -2 -2 -2 _"]

      request(
        "/api/v1/query_range",
        %{query: expression, start: "20", end: "30", step: "2s"},
        expected,
        "last-control",
        expression,
        20,
        2
      )

      request("/api/v1/query", %{query: query, time: "20"}, [], "other-tenant", query, 20, 1)

      for limits <- [[max_samples: 1], [max_work: 1], [max_result_points: 1]] do
        Runtime.put_env(:pulse, Evaluator, limits)

        conn =
          build_conn()
          |> put_req_header("x-scope-orgid", "last-control")
          |> get("/api/v1/query", query: query, time: "20")

        assert %{
                 "status" => "error",
                 "errorType" => "execution",
                 "error" => "query exceeded " <> _
               } = json_response(conn, 422)
      end
    end
  end

  for adapter <- [Memory, S3], function <- [:ts_of_first_over_time, :ts_of_last_over_time] do
    @tag adapter: adapter, function: function
    test "Pulse #{function} source timestamps through HTTP and #{inspect(adapter)}", %{function: function} do
      first? = function == :ts_of_first_over_time
      histogram = %NativeHistogram{schema: 1, count: 2.0, sum: 3.0}

      points = [
        {"zero_time", 0, 99.0},
        {"boundary", 10_000_000_000, 99.0},
        {"float", 17_000_000_000, :stale},
        {"float", 18_000_000_001, 9.0},
        {"float", 19_000_000_002, -2.0},
        {"float", 20_000_000_000, :stale},
        {"float_to_hist", 18_000_000_000, 7.0},
        {"float_to_hist", 19_000_000_000, histogram},
        {"hist_to_float", 18_000_000_000, histogram},
        {"hist_to_float", 19_000_000_000, 4.0},
        {"hist_stale", 17_000_000_000, %{histogram | sum: :stale}},
        {"hist_stale", 18_000_000_000, histogram},
        {"hist_stale", 20_000_000_000, %{histogram | sum: :stale}},
        {"stale", 20_000_000_000, :stale},
        {"future", 21_000_000_000, 8.0},
        {"nan", 19_000_000_000, :nan},
        {"inf", 19_000_000_000, :infinity},
        {"negative_inf", 19_000_000_000, :negative_infinity},
        {"zero", 19_000_000_000, -0.0}
      ]

      samples =
        for {kind, timestamp, value} <- Enum.reverse(points) do
          sample = %MetricSample{labels: %{"__name__" => "endpoint", "kind" => kind}, timestamp_ns: timestamp}
          if is_struct(value, NativeHistogram), do: %{sample | histogram: value}, else: %{sample | value: value}
        end

      assert :ok = Storage.append(:metrics, "endpoint-timestamps", samples)
      query = "#{function}(endpoint[21s])"

      endpoints =
        if first?,
          do: [{"float", "18.000000001"}, {"float_to_hist", "18"}, {"hist_to_float", "18"}],
          else: [{"float", "19.000000002"}, {"float_to_hist", "19"}, {"hist_to_float", "19"}]

      expected =
        for {kind, timestamp} <-
              endpoints ++
                [{"zero_time", "0"}, {"boundary", "10"}, {"hist_stale", "18"}] ++
                Enum.map(~w(nan inf negative_inf zero), &{&1, "19"}),
            do: %{"metric" => %{"kind" => kind}, "value" => [20, timestamp]}

      for method <- [:get, :post] do
        conn = build_conn() |> put_req_header("x-scope-orgid", "endpoint-timestamps")
        params = %{query: query, time: "20"}

        conn =
          if method == :get,
            do: get(conn, "/api/v1/query", params),
            else:
              conn
              |> put_req_header("content-type", "application/x-www-form-urlencoded")
              |> post("/api/v1/query", URI.encode_query(params))

        assert %{"data" => %{"resultType" => "vector", "result" => actual}} = json_response(conn, 200)
        assert Enum.sort_by(actual, & &1["metric"]) == Enum.sort_by(expected, & &1["metric"])
      end

      endpoint = if first?, do: "18.000000001", else: "19.000000002"
      grid_endpoint = if first?, do: "18", else: "20"

      for {expression, time, expected} <- [
            {~s|#{function}(endpoint{kind="boundary"}[10s])|, "19.999999999", [~s({kind="boundary"} 10)]},
            {~s|#{function}(endpoint{kind="boundary"}[10s])|, "20", []},
            {~s|#{function}(endpoint{kind="boundary"}[10s] offset 10s)|, "20", [~s({kind="boundary"} 10)]},
            {~s|#{function}(endpoint{kind="float"}[10s] offset 10s)|, "30", [~s({kind="float"} #{endpoint})]},
            {~s|#{function}(endpoint{kind="hist_to_float"}[10s:1s])|, "20",
             [~s({kind="hist_to_float"} #{grid_endpoint})]},
            {~s|#{function}(endpoint{kind="hist_to_float"}[10s:1s] offset 10s)|, "30",
             [~s({kind="hist_to_float"} #{grid_endpoint})]}
          ] do
        request(
          "/api/v1/query",
          %{query: expression, time: time},
          expected,
          "endpoint-timestamps",
          expression,
          value(time),
          1
        )
      end

      expression = ~s|#{function}(endpoint{kind="float"}[10s])|

      values =
        if first?,
          do: List.duplicate("18.000000001", 9) ++ ["19.000000002", "_"],
          else: List.duplicate("19.000000002", 10) ++ ["_"]

      request(
        "/api/v1/query_range",
        %{query: expression, start: "20", end: "30", step: "1s"},
        [~s({kind="float"} #{Enum.join(values, " ")})],
        "endpoint-timestamps",
        expression,
        20,
        1
      )

      request("/api/v1/query", %{query: query, time: "20"}, [], "other-tenant", query, 20, 1)

      for name <- ~w(endpoint_collision_a endpoint_collision_b) do
        sample = %MetricSample{labels: %{"__name__" => name}, timestamp_ns: 18_000_000_000, value: 1.0}
        assert :ok = Storage.append(:metrics, "endpoint-timestamps", [sample])
      end

      collision = ~s|#{function}({__name__=~"endpoint_collision_.*"}[10s])|

      request(
        "/api/v1/query",
        %{query: collision, time: "20"},
        ["expected_fail_message vector cannot contain metrics with the same labelset"],
        "endpoint-timestamps",
        "eval_fail #{collision}",
        20,
        1
      )

      for limits <- [[max_samples: 1], [max_work: 1], [max_result_points: 1]] do
        Runtime.put_env(:pulse, Evaluator, limits)

        conn =
          build_conn()
          |> put_req_header("x-scope-orgid", "endpoint-timestamps")
          |> get("/api/v1/query", query: query, time: "20")

        assert %{
                 "status" => "error",
                 "errorType" => "execution",
                 "error" => "query exceeded " <> _
               } = json_response(conn, 422)
      end
    end
  end

  for adapter <- [Memory, S3], function <- [:changes, :resets] do
    @tag adapter: adapter, function: function
    test "Pulse #{function} transitions through HTTP and #{inspect(adapter)}", %{function: function} do
      histogram = %NativeHistogram{
        schema: -53,
        custom_values: [2.0],
        positive_spans: [{0, 2}],
        positive_buckets: [1.0, 2.0],
        count: 3.0,
        sum: 5.0
      }

      sequences = [
        {"float", [8.0, 3.0, 3.0, 7.0, 2.0], 3, 2},
        {"nan", [:nan, :nan, 1.0, :nan, :nan], 2, 0},
        {"zero", [0.0, -0.0, 0.0], 0, 0},
        {"infinities", [:negative_infinity, 1.0, :infinity, :infinity, 2.0], 3, 1},
        {"mixed", [0.0, histogram, 1.0, %{histogram | sum: 7.0}, histogram, 2.0], 5, 4},
        {"mixed_nan", [:nan, histogram, :nan], 2, 2},
        {"sum_only", [histogram, %{histogram | sum: 9.0}, %{histogram | sum: -1.0}], 2, 0},
        {"hint_yes", [histogram, %{histogram | counter_reset_hint: :yes}], 0, 1},
        {"hint_no", [histogram, %{histogram | count: 1.0, positive_buckets: [1.0, 0.0], counter_reset_hint: :no}], 1,
         0},
        {"histogram_zero", [%{histogram | sum: 0.0}, %{histogram | sum: -0.0}], 1, 0},
        {"stale_bridge", [4.0, :stale, 1.0], 1, 1},
        {"hist_stale_bridge", [histogram, %{histogram | sum: :stale}, %{histogram | sum: 8.0}], 1, 0},
        {"single", [histogram], 0, 0},
        {"only_stale", [:stale, %{histogram | sum: :stale}], nil, nil}
      ]

      points =
        for {kind, values, _, _} <- sequences, {value, index} <- Enum.with_index(values), do: {kind, 12 + index, value}

      points = points ++ [{"boundary", 10, 8.0}, {"boundary", 11, 5.0}, {"boundary", 20, 7.0}]

      samples =
        for {kind, second, value} <- Enum.reverse(points) do
          sample = %MetricSample{
            labels: %{"__name__" => "transition", "kind" => kind},
            timestamp_ns: second * 1_000_000_000
          }

          if is_struct(value, NativeHistogram), do: %{sample | histogram: value}, else: %{sample | value: value}
        end

      assert :ok = Storage.append(:metrics, "transitions", samples)
      query = "#{function}(transition[10s])"

      expected =
        for {kind, _, changes, resets} <- sequences ++ [{"boundary", [], 1, 0}],
            not is_nil(changes),
            do: ~s({kind="#{kind}"} #{if function == :changes, do: changes, else: resets})

      request("/api/v1/query", %{query: query, time: "20"}, expected, "transitions", query, 20, 1)

      conn =
        build_conn()
        |> put_req_header("x-scope-orgid", "transitions")
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post("/api/v1/query", URI.encode_query(query: query, time: "20"))

      assert %{"data" => %{"resultType" => "vector", "result" => actual}} = json_response(conn, 200)
      assert_samples(actual, expected, 20, 1, query)

      for {expression, time, expected} <- [
            {~s|#{function}(transition{kind="boundary"}[10s])|, "19.999999999", [~s({kind="boundary"} 1)]},
            {~s|#{function}(transition{kind="boundary"}[10s])|, "21", [~s({kind="boundary"} 0)]},
            {~s|#{function}(transition{kind="boundary"}[10s])|, "30", []},
            {~s|#{function}(transition{kind="float"}[10s] offset 10s)|, "30",
             [~s({kind="float"} #{if function == :changes, do: 3, else: 2})]},
            {~s|#{function}(transition{kind="float"}[10s:2s])|, "20", [~s({kind="float"} 2)]},
            {~s|#{function}(transition{kind="float"}[10s:2s] offset 10s)|, "30", [~s({kind="float"} 2)]}
          ] do
        request("/api/v1/query", %{query: expression, time: time}, expected, "transitions", expression, value(time), 1)
      end

      request("/api/v1/query", %{query: query, time: "20"}, [], "other-tenant", query, 20, 1)

      for name <- ~w(transition_collision_a transition_collision_b) do
        sample = %MetricSample{labels: %{"__name__" => name}, timestamp_ns: 18_000_000_000, value: 1.0}
        assert :ok = Storage.append(:metrics, "transitions", [sample])
      end

      collision = ~s|#{function}({__name__=~"transition_collision_.*"}[10s])|

      request(
        "/api/v1/query",
        %{query: collision, time: "20"},
        ["expected_fail_message vector cannot contain metrics with the same labelset"],
        "transitions",
        "eval_fail #{collision}",
        20,
        1
      )

      for limits <- [[max_samples: 1], [max_work: 1], [max_result_points: 1]] do
        Runtime.put_env(:pulse, Evaluator, limits)

        conn =
          build_conn()
          |> put_req_header("x-scope-orgid", "transitions")
          |> get("/api/v1/query", query: query, time: "20")

        assert %{
                 "status" => "error",
                 "errorType" => "execution",
                 "error" => "query exceeded " <> _
               } = json_response(conn, 422)
      end
    end
  end

  for adapter <- [Memory, S3] do
    @tag adapter: adapter
    test "Pulse least-squares regression controls through HTTP and #{inspect(adapter)}" do
      histogram = %NativeHistogram{schema: 0, count: 2.0, sum: 100_000.0}

      points = [
        {"irregular", 12, 5.0},
        {"irregular", 14, 15.0},
        {"irregular", 19, 9.0},
        {"mixed", 12, 5.0},
        {"mixed", 13, histogram},
        {"mixed", 14, 15.0},
        {"mixed", 16, histogram},
        {"mixed", 18, histogram},
        {"mixed", 19, 9.0},
        {"huge_constant", 12, 1.0e308},
        {"huge_constant", 15, 1.0e308},
        {"huge_constant", 19, 1.0e308},
        {"zero", 12, 0.0},
        {"zero", 19, -0.0},
        {"stale_bridge", 12, 1.0},
        {"stale_bridge", 14, :stale},
        {"stale_bridge", 18, 7.0},
        {"stale_bridge", 20, %{histogram | sum: :stale}},
        {"two", 18, 9.0},
        {"two", 19, 7.0},
        {"hist_only", 14, histogram},
        {"hist_only", 18, histogram},
        {"one_float_hist", 18, 3.0},
        {"one_float_hist", 19, histogram},
        {"single", 19, 3.0},
        {"future", 21, 100.0},
        {"boundary", 10, -3.0},
        {"boundary", 11, 1.0},
        {"boundary", 20, 19.0}
      ]

      samples =
        for {kind, second, value} <- Enum.reverse(points) do
          sample = %MetricSample{
            labels: %{"__name__" => "regression", "kind" => kind},
            timestamp_ns: second * 1_000_000_000
          }

          if is_struct(value, NativeHistogram), do: %{sample | histogram: value}, else: %{sample | value: value}
        end

      assert :ok = Storage.append(:metrics, "regressions", samples)
      query = "deriv(regression[10s])"

      expected = [
        ~s({kind="irregular"} 0.23076923076923078),
        ~s({kind="mixed"} 0.23076923076923078),
        ~s({kind="huge_constant"} 0),
        ~s({kind="zero"} 0),
        ~s({kind="stale_bridge"} 1),
        ~s({kind="two"} -2),
        ~s({kind="boundary"} 2)
      ]

      request(
        "/api/v1/query",
        %{query: query, time: "20"},
        ["expect info", "expect no_warn" | expected],
        "regressions",
        query,
        20,
        1
      )

      conn =
        build_conn()
        |> put_req_header("x-scope-orgid", "regressions")
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post("/api/v1/query", URI.encode_query(query: query, time: "20"))

      response = json_response(conn, 200)
      assert [info] = response["infos"]
      assert info =~ "histogram"
      assert Map.get(response, "warnings", []) == []
      assert_samples(response["data"]["result"], expected, 20, 1, query)

      for {expression, time, expected} <- [
            {~s|deriv(regression{kind="boundary"}[10s])|, "19.999999999", ["expect no_info", ~s({kind="boundary"} 4)]},
            {~s|deriv(regression{kind="boundary"}[10s])|, "21", ["expect no_info"]},
            {~s|deriv(regression{kind="irregular"}[10s] offset 10s)|, "30",
             ["expect no_info", ~s({kind="irregular"} 0.23076923076923078)]},
            {~s|deriv(regression{kind="irregular"}[10s:2s])|, "20", ["expect no_info", ~s({kind="irregular"} 0.4)]},
            {~s|deriv(regression{kind="mixed"}[10s:2s])|, "20",
             ["expect info", ~s({kind="mixed"} 0.15384615384615385)]},
            {~s|deriv(regression{kind="hist_only"}[10s])|, "20", ["expect no_info", "expect no_warn"]},
            {~s|deriv(regression{kind="one_float_hist"}[10s])|, "20", ["expect info", "expect no_warn"]},
            {~s|deriv(regression{kind="single"}[10s])|, "20", ["expect no_info"]},
            {~s|deriv(regression{kind="stale_bridge"}[10s])|, "20", ["expect no_info", ~s({kind="stale_bridge"} 1)]},
            {~s|1 / deriv(regression{kind="zero"}[10s])|, "20", [~s({kind="zero"} Inf)]},
            {~s|sum(deriv(regression{kind="mixed"}[10s]))|, "20", ["expect info", "{} 0.23076923076923078"]},
            {~s|predict_linear(regression{kind="irregular"}[10s], 2)|, "20",
             ["expect no_info", ~s({kind="irregular"} 11.282051282051283)]},
            {~s|predict_linear(regression{kind="mixed"}[10s], 2)|, "20",
             ["expect info", ~s({kind="mixed"} 11.282051282051283)]},
            {~s|predict_linear(regression{kind="hist_only"}[10s], 2)|, "20", ["expect no_info", "expect no_warn"]},
            {~s|predict_linear(regression{kind="one_float_hist"}[10s], 2)|, "20", ["expect info", "expect no_warn"]}
          ] do
        request("/api/v1/query", %{query: expression, time: time}, expected, "regressions", expression, value(time), 1)
      end

      request("/api/v1/query", %{query: query, time: "20"}, ["expect no_info"], "other-tenant", query, 20, 1)

      expression = ~s|deriv(regression{kind="mixed"}[1s])|

      request(
        "/api/v1/query_range",
        %{query: expression, start: "12", end: "20", step: "8s"},
        ["expect no_info", "expect no_warn"],
        "regressions",
        expression,
        12,
        8
      )

      epoch_samples =
        for sample <- samples,
            sample.labels["kind"] == "irregular",
            do: %{
              sample
              | labels: %{"__name__" => "epoch_regression"},
                timestamp_ns: sample.timestamp_ns + 1_700_000_000_000_000_000
            }

      assert :ok = Storage.append(:metrics, "regressions", epoch_samples)

      request(
        "/api/v1/query",
        %{query: "deriv(epoch_regression[10s])", time: "1700000020"},
        ["{} 0.23076923076923078"],
        "regressions",
        "large epoch regression",
        1_700_000_020,
        1
      )

      batch = [
        {"mixed", ~s|deriv(regression{kind="mixed"}[10s])|, %{end_ts_ns: 20_000_000_000}},
        {"clean", ~s|deriv(regression{kind="irregular"}[10s])|, %{end_ts_ns: 20_000_000_000}},
        {"prediction", ~s|predict_linear(regression{kind="mixed"}[10s], 2)|, %{end_ts_ns: 20_000_000_000}}
      ]

      assert {:ok, results} = Evaluator.query_batch(batch, "regressions", fn results, _ -> {:ok, results} end)
      assert [_] = results["mixed"]["infos"]
      assert [_] = results["prediction"]["infos"]
      refute Map.has_key?(results["clean"], "infos")

      for name <- ~w(regression_collision_a regression_collision_b) do
        samples =
          for second <- [18, 19],
              do: %MetricSample{
                labels: %{"__name__" => name},
                timestamp_ns: second * 1_000_000_000,
                value: second * 1.0
              }

        assert :ok = Storage.append(:metrics, "regressions", samples)
      end

      collision = ~s|deriv({__name__=~"regression_collision_.*"}[10s])|

      request(
        "/api/v1/query",
        %{query: collision, time: "20"},
        ["expected_fail_message vector cannot contain metrics with the same labelset"],
        "regressions",
        "eval_fail #{collision}",
        20,
        1
      )

      for limits <- [[max_samples: 1], [max_work: 1], [max_result_points: 1]] do
        Runtime.put_env(:pulse, Evaluator, limits)

        conn =
          build_conn()
          |> put_req_header("x-scope-orgid", "regressions")
          |> get("/api/v1/query", query: query, time: "20")

        assert %{
                 "status" => "error",
                 "errorType" => "execution",
                 "error" => "query exceeded " <> _
               } = json_response(conn, 422)
      end
    end
  end

  for adapter <- [Memory, S3] do
    @tag adapter: adapter
    test "Pulse median absolute deviation controls through HTTP and #{inspect(adapter)}" do
      histogram = %NativeHistogram{schema: 0, count: 2.0, sum: 100_000.0}

      sequences = [
        {"odd", [0.0, 1.0, 2.0, 50.0, 100.0], "2"},
        {"even", [-20.0, 0.0, 1.0, 100.0], "10.5"},
        {"single", [-8.0], "0"},
        {"nan", [2.0, :nan, 9.0], "NaN"},
        {"finite_median", [1.0, 2.0, :infinity], "1"},
        {"infinite_deviation", [:negative_infinity, 0.0, :infinity], "Inf"},
        {"infinite_median", [0.0, :infinity, :infinity], "NaN"},
        {"single_infinity", [:negative_infinity], "NaN"},
        {"opposite_infinities", [:negative_infinity, :infinity], "NaN"},
        {"huge_constant", [1.0e308, 1.0e308], "0"},
        {"huge_even", [-1.0e308, 1.0e308], "1e308"},
        {"overflow_deviation", [-1.0e308, 1.0e308, 1.0e308], "0"},
        {"zero", [0.0, -0.0], "0"},
        {"stale_bridge", [1.0, :stale, 9.0, %{histogram | sum: :stale}], "4"},
        {"mixed", [1.0, histogram, 9.0], "4"},
        {"one_float_hist", [histogram, 6.0, histogram], "0"},
        {"mixed_nan", [2.0, :nan, histogram], "NaN"},
        {"hist_only", [histogram, histogram], nil},
        {"stale_only", [:stale, %{histogram | sum: :stale}], nil}
      ]

      points =
        for {kind, values, _} <- sequences, {value, index} <- Enum.with_index(values), do: {kind, 12 + index, value}

      points =
        points ++
          [{"boundary", 10, 100.0}, {"boundary", 11, 1.0}, {"boundary", 20, 9.0}] ++
          [{"grid", 12, 1.0}, {"grid", 14, 5.0}, {"grid", 19, 9.0}]

      samples =
        for {kind, second, value} <- Enum.reverse(points) do
          sample = %MetricSample{
            labels: %{"__name__" => "deviation", "kind" => kind},
            timestamp_ns: second * 1_000_000_000
          }

          if is_struct(value, NativeHistogram), do: %{sample | histogram: value}, else: %{sample | value: value}
        end

      assert :ok = Storage.append(:metrics, "deviations", samples)
      query = "mad_over_time(deviation[10s])"

      expected =
        for {kind, _, result} <- sequences ++ [{"boundary", [], "4"}, {"grid", [], "4"}],
            not is_nil(result),
            do: ~s({kind="#{kind}"} #{result})

      request("/api/v1/query", %{query: query, time: "20"}, ["expect info" | expected], "deviations", query, 20, 1)

      conn =
        build_conn()
        |> put_req_header("x-scope-orgid", "deviations")
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post("/api/v1/query", URI.encode_query(query: query, time: "20"))

      assert %{"data" => %{"resultType" => "vector", "result" => actual}, "infos" => [_]} = json_response(conn, 200)
      assert_samples(actual, expected, 20, 1, query)

      for {expression, time, expected} <- [
            {~s|mad_over_time(deviation{kind="boundary"}[10s])|, "19.999999999",
             ["expect no_info", ~s({kind="boundary"} 49.5)]},
            {~s|mad_over_time(deviation{kind="boundary"}[10s])|, "21", [~s({kind="boundary"} 0)]},
            {~s|mad_over_time(deviation{kind="boundary"}[10s])|, "30", []},
            {~s|mad_over_time(deviation{kind="boundary"}[10s] offset 10s)|, "30", [~s({kind="boundary"} 4)]},
            {~s|mad_over_time(deviation{kind="grid"}[10s:2s])|, "20", ["expect no_info", ~s({kind="grid"} 0)]},
            {~s|mad_over_time(deviation{kind="mixed"}[10s:1s])|, "20", ["expect info", ~s({kind="mixed"} 0)]},
            {~s|mad_over_time(deviation{kind="hist_only"}[10s])|, "20", ["expect no_info", "expect no_warn"]},
            {~s|mad_over_time(deviation{kind="stale_only"}[10s])|, "20", ["expect no_info", "expect no_warn"]},
            {~s|mad_over_time(deviation{kind="stale_bridge"}[10s])|, "20",
             ["expect no_info", ~s({kind="stale_bridge"} 4)]},
            {~s|mad_over_time(deviation{kind="one_float_hist"}[10s])|, "20",
             ["expect info", ~s({kind="one_float_hist"} 0)]},
            {~s|1 / mad_over_time(deviation{kind="zero"}[10s])|, "20", [~s({kind="zero"} Inf)]},
            {~s|sum(mad_over_time(deviation{kind="mixed"}[10s]))|, "20", ["expect info", "{} 4"]}
          ] do
        request("/api/v1/query", %{query: expression, time: time}, expected, "deviations", expression, value(time), 1)
      end

      expression = ~s|mad_over_time(deviation{kind="mixed"}[1s])|

      request(
        "/api/v1/query_range",
        %{query: expression, start: "12", end: "14", step: "2s"},
        ["expect no_info", "expect no_warn", ~s({kind="mixed"} 0 0)],
        "deviations",
        expression,
        12,
        2
      )

      request("/api/v1/query", %{query: query, time: "20"}, ["expect no_info"], "other-tenant", query, 20, 1)

      batch = [
        {"mixed", ~s|mad_over_time(deviation{kind="mixed"}[10s])|, %{end_ts_ns: 20_000_000_000}},
        {"clean", ~s|mad_over_time(deviation{kind="odd"}[10s])|, %{end_ts_ns: 20_000_000_000}}
      ]

      assert {:ok, results} = Evaluator.query_batch(batch, "deviations", fn results, _ -> {:ok, results} end)
      assert [_] = results["mixed"]["infos"]
      refute Map.has_key?(results["clean"], "infos")

      for name <- ~w(deviation_collision_a deviation_collision_b) do
        samples =
          for second <- [18, 19],
              do: %MetricSample{
                labels: %{"__name__" => name},
                timestamp_ns: second * 1_000_000_000,
                value: second * 1.0
              }

        assert :ok = Storage.append(:metrics, "deviations", samples)
      end

      collision = ~s|mad_over_time({__name__=~"deviation_collision_.*"}[10s])|

      request(
        "/api/v1/query",
        %{query: collision, time: "20"},
        ["expected_fail_message vector cannot contain metrics with the same labelset"],
        "deviations",
        "eval_fail #{collision}",
        20,
        1
      )

      for limits <- [[max_samples: 1], [max_work: 1], [max_result_points: 1]] do
        Runtime.put_env(:pulse, Evaluator, limits)

        conn =
          build_conn()
          |> put_req_header("x-scope-orgid", "deviations")
          |> get("/api/v1/query", query: query, time: "20")

        assert %{
                 "status" => "error",
                 "errorType" => "execution",
                 "error" => "query exceeded " <> _
               } = json_response(conn, 422)
      end

      expression = ~s|mad_over_time(deviation{kind="odd"}[10s])|

      # A linear-only charge would admit this window under 30 work units;
      # charging both median sorts must reject it, while a larger budget works.
      Runtime.put_env(:pulse, Evaluator, max_work: 30)

      conn =
        build_conn()
        |> put_req_header("x-scope-orgid", "deviations")
        |> get("/api/v1/query", query: expression, time: "20")

      assert %{
               "errorType" => "execution",
               "error" => "query exceeded " <> _
             } =
               json_response(conn, 422)

      Runtime.put_env(:pulse, Evaluator, max_work: 80)
      request("/api/v1/query", %{query: expression, time: "20"}, [~s({kind="odd"} 2)], "deviations", expression, 20, 1)

      Runtime.put_env(:pulse, Evaluator, max_work: 60)
      batch = for ref <- ~w(first second), do: {ref, expression, %{end_ts_ns: 20_000_000_000}}

      assert {:error, :query_work_limit} =
               Evaluator.query_batch(batch, "deviations", fn _, _ -> flunk("over-budget batch reached consumer") end)
    end
  end

  for adapter <- [Memory, S3], function <- [:ts_of_min_over_time, :ts_of_max_over_time] do
    @tag adapter: adapter, function: function
    test "Pulse #{function} source timestamp controls through HTTP and #{inspect(adapter)}", %{function: function} do
      min? = function == :ts_of_min_over_time
      histogram = %NativeHistogram{schema: 0, count: 2.0, sum: 100_000.0}

      sequences = [
        {"ties", [5.0, 1.0, 1.0, 9.0, 9.0, 1.0], 17, 16},
        {"nan_edges", [:nan, 4.0, :nan], 13, 13},
        {"all_nan", [:nan, :nan, :nan], 14, 14},
        {"zeros", [-0.0, 0.0, -0.0], 14, 14},
        {"infinities", [:infinity, :negative_infinity, :infinity, :negative_infinity], 15, 14},
        {"huge", [1.0e308, -1.0e308, 1.0e308], 13, 14},
        {"stale_bridge", [1.0, :stale, 8.0, %{histogram | sum: :stale}], 12, 14},
        {"mixed", [9.0, histogram, 1.0, 4.0, histogram, 1.0], 17, 12},
        {"one_float_hist", [histogram, 6.0, histogram], 13, 13},
        {"nan_hist", [histogram, :nan, histogram], 13, 13},
        {"single", [7.0], 12, 12},
        {"hist_only", [histogram, histogram], nil, nil},
        {"stale_only", [:stale, %{histogram | sum: :stale}], nil, nil}
      ]

      points =
        for {kind, values, _, _} <- sequences,
            {value, index} <- Enum.with_index(values),
            do: {kind, (12 + index) * 1_000_000_000, value}

      points =
        points ++
          [
            {"boundary", 10_000_000_000, -9.0},
            {"boundary", 11_000_000_000, 1.0},
            {"boundary", 20_000_000_000, 9.0},
            {"grid", 12_000_000_000, 5.0},
            {"grid", 14_000_000_000, 1.0},
            {"grid", 19_000_000_000, 7.0},
            {"fractional", 18_000_000_001, 2.0},
            {"fractional", 19_000_000_002, 9.0},
            {"epoch_zero", 0, :nan},
            {"future", 21_000_000_000, 0.0}
          ]

      samples =
        for {kind, timestamp, value} <- Enum.reverse(points) do
          sample = %MetricSample{labels: %{"__name__" => "extremum", "kind" => kind}, timestamp_ns: timestamp}
          if is_struct(value, NativeHistogram), do: %{sample | histogram: value}, else: %{sample | value: value}
        end

      assert :ok = Storage.append(:metrics, "extrema", samples)
      query = "#{function}(extremum[10s])"

      expected =
        for {kind, _, minimum, maximum} <-
              sequences ++
                [{"boundary", [], 11, 20}, {"grid", [], 14, 19}, {"fractional", [], "18.000000001", "19.000000002"}],
            not is_nil(minimum),
            do: ~s({kind="#{kind}"} #{if min?, do: minimum, else: maximum})

      request("/api/v1/query", %{query: query, time: "20"}, ["expect info" | expected], "extrema", query, 20, 1)

      conn =
        build_conn()
        |> put_req_header("x-scope-orgid", "extrema")
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post("/api/v1/query", URI.encode_query(query: query, time: "20"))

      assert %{"data" => %{"result" => actual}, "infos" => [_]} = json_response(conn, 200)
      assert_samples(actual, expected, 20, 1, query)

      # The upstream relative epsilon would allow sub-millisecond truncation.
      fractional = Enum.find(actual, &(&1["metric"]["kind"] == "fractional"))
      assert value(List.last(fractional["value"])) == if(min?, do: 18.000000001, else: 19.000000002)

      for {expression, time, expected} <- [
            {~s|#{function}(extremum{kind="boundary"}[10s])|, "19.999999999",
             [~s({kind="boundary"} #{if min?, do: 10, else: 11})]},
            {~s|#{function}(extremum{kind="boundary"}[10s])|, "21", [~s({kind="boundary"} 20)]},
            {~s|#{function}(extremum{kind="boundary"}[10s])|, "30", []},
            {~s|#{function}(extremum{kind="boundary"}[10s] offset 10s)|, "30",
             [~s({kind="boundary"} #{if min?, do: 11, else: 20})]},
            {~s|#{function}(extremum{kind="grid"}[10s:2s])|, "20",
             ["expect no_info", ~s({kind="grid"} #{if min?, do: 18, else: 20})]},
            {~s|#{function}(extremum{kind="mixed"}[10s:2s])|, "20",
             ["expect info", ~s({kind="mixed"} #{if min?, do: 20, else: 12})]},
            {~s|#{function}(extremum{kind="hist_only"}[10s])|, "20", ["expect no_info", "expect no_warn"]},
            {~s|#{function}(extremum{kind="stale_only"}[10s])|, "20", ["expect no_info", "expect no_warn"]},
            {~s|#{function}(extremum{kind="epoch_zero"}[10s])|, "0", ["expect no_info", ~s({kind="epoch_zero"} 0)]}
          ] do
        request("/api/v1/query", %{query: expression, time: time}, expected, "extrema", expression, value(time), 1)
      end

      expression = ~s|#{function}(extremum{kind="boundary"}[10s])|

      request(
        "/api/v1/query_range",
        %{query: expression, start: "20", end: "30", step: "5s"},
        ["expect no_info", ~s({kind="boundary"} #{if min?, do: 11, else: 20} 20 _)],
        "extrema",
        expression,
        20,
        5
      )

      expression = ~s|#{function}(extremum{kind="mixed"}[1s])|

      request(
        "/api/v1/query_range",
        %{query: expression, start: "12", end: "14", step: "2s"},
        ["expect no_info", ~s({kind="mixed"} 12 14)],
        "extrema",
        expression,
        12,
        2
      )

      for {name, owner, second} <- [{"extremum_context_a", "left", 12}, {"extremum_context_b", "right", 14}] do
        samples = [
          %MetricSample{
            labels: %{"__name__" => name, "owner" => owner},
            timestamp_ns: second * 1_000_000_000,
            value: 5.0
          },
          %MetricSample{
            labels: %{"__name__" => name, "owner" => owner},
            timestamp_ns: (second + 1) * 1_000_000_000,
            histogram: histogram
          }
        ]

        assert :ok = Storage.append(:metrics, "extrema", samples)
      end

      expression = ~s|#{function}({__name__=~"extremum_context_.*"}[10s])|

      conn =
        build_conn()
        |> put_req_header("x-scope-orgid", "extrema")
        |> get("/api/v1/query", query: expression, time: "20")

      response = json_response(conn, 200)
      assert_samples(response["data"]["result"], [~s({owner="left"} 12), ~s({owner="right"} 14)], 20, 1, expression)

      assert Enum.sort(response["infos"]) == [
               ~s(PromQL info: ignored histograms in a range containing both floats and histograms for metric name "extremum_context_a"),
               ~s(PromQL info: ignored histograms in a range containing both floats and histograms for metric name "extremum_context_b")
             ]

      expression = ~s|#{function}(sum by(owner)(extremum_context_a)[10s:1s])|

      conn =
        build_conn()
        |> put_req_header("x-scope-orgid", "extrema")
        |> get("/api/v1/query", query: expression, time: "20")

      response = json_response(conn, 200)
      assert_samples(response["data"]["result"], [~s({owner="left"} 12)], 20, 1, expression)

      assert [~s(PromQL info: ignored histograms in a range containing both floats and histograms for metric name "")] ==
               response["infos"]

      request("/api/v1/query", %{query: query, time: "20"}, ["expect no_info"], "other-tenant", query, 20, 1)

      for name <- ~w(extremum_collision_a extremum_collision_b) do
        sample = %MetricSample{labels: %{"__name__" => name}, timestamp_ns: 18_000_000_000, value: 1.0}
        assert :ok = Storage.append(:metrics, "extrema", [sample])
      end

      collision = ~s|#{function}({__name__=~"extremum_collision_.*"}[10s])|

      request(
        "/api/v1/query",
        %{query: collision, time: "20"},
        ["expected_fail_message vector cannot contain metrics with the same labelset"],
        "extrema",
        "eval_fail #{collision}",
        20,
        1
      )

      for limits <- [[max_samples: 1], [max_work: 1], [max_result_points: 1]] do
        Runtime.put_env(:pulse, Evaluator, limits)

        conn =
          build_conn() |> put_req_header("x-scope-orgid", "extrema") |> get("/api/v1/query", query: query, time: "20")

        assert %{
                 "errorType" => "execution",
                 "error" => "query exceeded " <> _
               } = json_response(conn, 422)
      end
    end
  end

  for adapter <- [Memory, S3] do
    @tag adapter: adapter
    test "Pulse label_join controls through HTTP and #{inspect(adapter)}" do
      labels = %{"__name__" => "joined", "src" => "α😀", "(src)" => "B", "dst" => "old"}

      histogram = %NativeHistogram{
        schema: 0,
        count: 3.0,
        sum: 1.5,
        positive_spans: [{0, 1}],
        positive_buckets: [3.0]
      }

      samples =
        for {kind, value} <- [{"float", -0.0}, {"nan", :nan}, {"histogram", histogram}, {"stale", :stale}] do
          sample = %MetricSample{labels: Map.put(labels, "kind", kind), timestamp_ns: 10_000_000_000}
          if is_struct(value, NativeHistogram), do: %{sample | histogram: value}, else: %{sample | value: value}
        end

      assert :ok = Storage.append(:metrics, "joins", samples)

      for {destination, separator, sources, joined} <- [
            {"合成😀", "|", ["src", "missing", "(src)", "src"], "α😀||B|α😀"},
            {"src", "/", ["src", "(src)", "src"], "α😀/B/α😀"},
            {"dst", "/", ["dst", "dst"], "old/old"},
            {"dst", "😀\n", ["__name__", "(src)"], "joined😀\nB"},
            {"__name__", "", [], ""}
          ] do
        arguments = Enum.map_join([destination, separator | sources], ", ", &JSON.encode!/1)
        query = "label_join(joined, #{arguments})"

        conn =
          build_conn() |> put_req_header("x-scope-orgid", "joins") |> get("/api/v1/query", query: query, time: "20")

        response = json_response(conn, 200)
        assert %{"data" => %{"result" => results}} = response
        assert length(results) == 3
        assert Map.get(response, "warnings", []) == []
        assert Map.get(response, "infos", []) == []

        for result <- results do
          kind = result["metric"]["kind"]
          expected = if joined == "", do: Map.delete(labels, destination), else: Map.put(labels, destination, joined)
          assert result["metric"] == Map.put(expected, "kind", kind)

          case kind do
            "float" ->
              assert result["value"] == [20.0, "-0"]

            "nan" ->
              assert result["value"] == [20.0, "NaN"]

            "histogram" ->
              assert result["histogram"] ==
                       [20.0, %{"count" => "3", "sum" => "1.5", "buckets" => [[0, "0.5", "1", "3"]]}]
          end
        end
      end

      query = ~s|label_join(joined, "dst", "/", "dst", "src")|

      conn =
        build_conn()
        |> put_req_header("x-scope-orgid", "joins")
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post("/api/v1/query", URI.encode_query(query: query, time: "20"))

      assert %{"data" => %{"result" => results}} = json_response(conn, 200)
      assert Enum.all?(results, &(&1["metric"]["dst"] == "old/α😀"))
      assert length(results) == 3
      request("/api/v1/query", %{query: query, time: "20"}, [], "other-tenant", query, 20, 1)

      for limits <- [[max_samples: 1], [max_work: 1], [max_result_points: 1]] do
        Runtime.put_env(:pulse, Evaluator, limits)

        conn =
          build_conn() |> put_req_header("x-scope-orgid", "joins") |> get("/api/v1/query", query: query, time: "20")

        assert %{
                 "errorType" => "execution",
                 "error" => "query exceeded " <> _
               } = json_response(conn, 422)
      end
    end

    @tag adapter: adapter
    test "Pulse label_join charges source lookups and joined bytes against shared work through #{inspect(adapter)}" do
      large = String.duplicate("x", 1024)

      sample = %MetricSample{
        labels: %{"__name__" => "join_cost", "src" => large},
        timestamp_ns: 10_000_000_000,
        value: 7.0
      }

      assert :ok = Storage.append(:metrics, "join-cost", [sample])
      single = ~s|label_join(join_cost, "dst", "", "src")|

      Runtime.put_env(:pulse, Evaluator, max_work: 1800)

      conn =
        build_conn() |> put_req_header("x-scope-orgid", "join-cost") |> get("/api/v1/query", query: single, time: "20")

      assert %{"data" => %{"result" => [%{"metric" => %{"dst" => ^large}, "value" => [20.0, "7"]}]}} =
               json_response(conn, 200)

      batch = for ref <- ["a", "b"], do: {ref, single, %{end_ts_ns: 20_000_000_000}}

      assert {:error, :query_work_limit} =
               Evaluator.query_batch(batch, "join-cost", fn _, _ -> flunk("over-budget join batch reached consumer") end)

      repeated_sources = Enum.map_join(1..200, ", ", fn _ -> ~s("missing") end)

      for {work, expression} <- [
            {1800, ~s|label_join(join_cost, "dst", "", "src", "src")|},
            {1800, "label_join(join_cost, \"dst\", #{JSON.encode!(large)}, \"missing\", \"missing\", \"missing\")"},
            {150, "label_join(join_cost, \"dst\", \"\", #{repeated_sources})"}
          ] do
        Runtime.put_env(:pulse, Evaluator, max_work: work)

        conn =
          build_conn()
          |> put_req_header("x-scope-orgid", "join-cost")
          |> get("/api/v1/query", query: expression, time: "20")

        assert %{
                 "errorType" => "execution",
                 "error" => "query exceeded " <> _
               } = json_response(conn, 422)
      end
    end
  end

  for adapter <- [Memory, S3] do
    @tag adapter: adapter
    test "Pulse quantile_over_time boundary and IEEE controls through HTTP and #{inspect(adapter)}" do
      histogram = %NativeHistogram{schema: 0, count: 1.0, sum: 1000.0}

      cases = [
        {"unordered", [10.0, 2.0, 6.0, 0.0], "0.75", "7"},
        {"nan_low", [9.0, :nan, 1.0], "0", "NaN"},
        {"nan_exact", [9.0, :nan, 1.0], "0.5", "1"},
        {"nan_high", [9.0, :nan, 1.0], "0.75", "5"},
        {"nan_max", [9.0, :nan, 1.0], "1", "9"},
        {"huge", [-1.0e308, 1.0e308], "0.25", "-5e+307"},
        {"single", [-0.0], "0.75", "-0"},
        {"mixed", [3.0, histogram, 11.0], "0.25", "5"},
        {"stale", [3.0, :stale, 11.0, %{histogram | sum: :stale}], "0.75", "9"},
        {"hist_only", [histogram], "NaN", nil},
        {"stale_only", [:stale], "2", nil}
      ]

      samples =
        for {kind, values, _, _} <- cases,
            {value, index} <- Enum.with_index(values) do
          sample = %MetricSample{
            labels: %{"__name__" => "quantile_input", "kind" => kind},
            timestamp_ns: (12 + index) * 1_000_000_000
          }

          if is_struct(value, NativeHistogram), do: %{sample | histogram: value}, else: %{sample | value: value}
        end

      boundary =
        for {time, value} <- [{10, -100.0}, {11, 1.0}, {20, 9.0}],
            do: %MetricSample{labels: %{"__name__" => "boundary"}, timestamp_ns: time * 1_000_000_000, value: value}

      assert :ok = Storage.append(:metrics, "quantiles", Enum.reverse(samples ++ boundary))

      for {kind, _, q, expected} <- cases do
        expression = ~s|quantile_over_time(#{q}, quantile_input{kind="#{kind}"}[10s])|

        conn =
          build_conn()
          |> put_req_header("x-scope-orgid", "quantiles")
          |> get("/api/v1/query", query: expression, time: "20")

        response = json_response(conn, 200)
        assert Map.get(response, "warnings", []) == []

        assert Map.get(response, "infos", []) ==
                 if(kind == "mixed",
                   do: [
                     ~s|PromQL info: ignored histograms in a range containing both floats and histograms for metric name "quantile_input"|
                   ],
                   else: []
                 )

        expected = if expected, do: [%{"metric" => %{"kind" => kind}, "value" => [20.0, expected]}], else: []
        assert response["data"]["result"] == expected
      end

      for {expression, time, expected} <- [
            {"quantile_over_time(0.75, boundary[10s])", "19.999999999", "{} -24.25"},
            {"quantile_over_time(0.75, boundary[10s])", "20", "{} 7"},
            {"quantile_over_time(0.75, boundary[10s])", "21", "{} 9"},
            {"quantile_over_time(0.75, boundary[10s] offset 10s)", "30", "{} 7"},
            {~s|quantile_over_time(0.5, quantile_input{kind="unordered"}[10s:2s])|, "20", ~s({kind="unordered"} 0)},
            {~s|quantile_over_time(time()/40, quantile_input{kind="unordered"}[10s] offset 10s)|, "30",
             ~s({kind="unordered"} 7)},
            {~s|quantile_over_time(time()/40, quantile_input{kind="unordered"}[10s:2s] offset 10s)|, "30",
             ~s({kind="unordered"} 6)}
          ] do
        request("/api/v1/query", %{query: expression, time: time}, [expected], "quantiles", expression, value(time), 1)
      end

      expression = "quantile_over_time(0.75, boundary[10s])"

      conn =
        build_conn()
        |> put_req_header("x-scope-orgid", "quantiles")
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post("/api/v1/query_range", URI.encode_query(query: expression, start: "20", end: "30", step: "5s"))

      assert %{"data" => %{"result" => [%{"metric" => %{}, "values" => [[20.0, "7"], [25.0, "9"]]}]}} =
               json_response(conn, 200)

      request("/api/v1/query", %{query: expression, time: "20"}, [], "other-tenant", expression, 20, 1)
    end

    @tag adapter: adapter
    test "Pulse quantile_over_time warnings, collisions and budgets through #{inspect(adapter)}" do
      samples =
        for name <- ["quantile_a", "quantile_b"],
            second <- 12..19,
            do: %MetricSample{labels: %{"__name__" => name}, timestamp_ns: second * 1_000_000_000, value: second * 1.0}

      assert :ok = Storage.append(:metrics, "quantile-cost", samples)
      valid = "quantile_over_time(0.25, quantile_a[10s])"

      for {q, expected} <- [{"NaN", "NaN"}, {"-Inf", "-Inf"}, {"Inf", "+Inf"}, {"2", "+Inf"}] do
        expression = "sum(quantile_over_time(#{q}, quantile_a[10s]) + quantile_over_time(#{q}, quantile_b[10s]))"
        diagnostic = if q == "Inf", do: "+Inf", else: q

        conn =
          build_conn()
          |> put_req_header("x-scope-orgid", "quantile-cost")
          |> get("/api/v1/query", query: expression, time: "20")

        response = json_response(conn, 200)
        assert response["warnings"] == ["PromQL warning: quantile value should be between 0 and 1, got #{diagnostic}"]
        assert response["data"]["result"] == [%{"metric" => %{}, "value" => [20.0, expected]}]
      end

      batch = [
        {"warn", "quantile_over_time(2, quantile_a[10s])", %{end_ts_ns: 20_000_000_000}},
        {"valid", valid, %{end_ts_ns: 20_000_000_000}},
        {"empty", "quantile_over_time(NaN, missing[10s])", %{end_ts_ns: 20_000_000_000}}
      ]

      assert {:ok, results} = Evaluator.query_batch(batch, "quantile-cost", fn results, _ -> {:ok, results} end)
      assert [_] = results["warn"]["warnings"]
      refute Map.has_key?(results["valid"], "warnings")
      refute Map.has_key?(results["empty"], "warnings")
      assert results["valid"]["data"]["result"] == [%{"metric" => %{}, "value" => [20.0, "13.75"]}]

      collision = ~s|quantile_over_time(0.5, {__name__=~"quantile_.*"}[10s])|

      request(
        "/api/v1/query",
        %{query: collision, time: "20"},
        ["expected_fail_message vector cannot contain metrics with the same labelset"],
        "quantile-cost",
        "eval_fail #{collision}",
        20,
        1
      )

      # Eight values fit a linear scan under 30 work units, but not a sort.
      for limits <- [[max_samples: 1], [max_work: 30], [max_result_points: 1]] do
        Runtime.put_env(:pulse, Evaluator, limits)

        conn =
          build_conn()
          |> put_req_header("x-scope-orgid", "quantile-cost")
          |> get("/api/v1/query_range", query: valid, start: "20", end: "21", step: "1s")

        assert %{
                 "errorType" => "execution",
                 "error" => "query exceeded " <> _
               } = json_response(conn, 422)
      end

      Runtime.put_env(:pulse, Evaluator, max_work: 80)
      request("/api/v1/query", %{query: valid, time: "20"}, ["{} 13.75"], "quantile-cost", valid, 20, 1)
      batch = for ref <- ["a", "b"], do: {ref, valid, %{end_ts_ns: 20_000_000_000}}

      assert {:error, :query_work_limit} =
               Evaluator.query_batch(batch, "quantile-cost", fn _, _ ->
                 flunk("over-budget quantile batch reached consumer")
               end)
    end
  end

  for adapter <- [Memory, S3] do
    @tag adapter: adapter
    test "Pulse smoothing recurrence, IEEE and window controls through #{inspect(adapter)}" do
      histogram = %NativeHistogram{schema: 0, count: 1.0, sum: 1000.0}

      cases = [
        {"asymmetric", [2.0, 8.0, 1.0, 7.0], "0.5", "0.25", "9.4375"},
        {"mixed", [2.0, histogram, 8.0, 1.0, 7.0], "0.5", "0.25", "9.4375"},
        {"one_mixed", [histogram, 2.0], "0.5", "0.25", nil},
        {"stale", [2.0, :stale, 8.0, 1.0, 7.0, %{histogram | sum: :stale}], "0.5", "0.25", "9.4375"},
        {"two", [2.0, 8.0], "0.5", "NaN", "8"},
        {"nan_sf", [2.0, 8.0], "NaN", "0.25", "NaN"},
        {"nan_tf", [2.0, 8.0, 1.0], "0.5", "NaN", "NaN"},
        {"missing_factor", [2.0, 8.0], "scalar(missing)", "0.25", "NaN"},
        {"huge", [-1.0e308, 1.0e308], "0.5", "0.25", "+Inf"},
        {"infinite_trend", [:infinity, 1.0], "0.5", "0.25", "NaN"},
        {"infinite_level", [1.0, :infinity], "0.5", "0.25", "+Inf"},
        {"nan", [1.0, :nan, 3.0], "0.5", "0.25", "NaN"},
        {"zero", [-0.0, -0.0], "0.5", "0.25", "0"},
        {"single", [2.0], "0.5", "0.25", nil},
        {"hist_only", [histogram], "0.5", "0.25", nil},
        {"stale_only", [:stale], "0", "Inf", nil}
      ]

      samples =
        for {kind, values, _, _, _} <- cases,
            {value, index} <- Enum.with_index(values) do
          sample = %MetricSample{
            labels: %{"__name__" => "smoothing", "kind" => kind},
            timestamp_ns: (12 + index) * 1_000_000_000
          }

          if is_struct(value, NativeHistogram), do: %{sample | histogram: value}, else: %{sample | value: value}
        end

      boundary =
        for {time, value} <- [{10, -100.0}, {12, 2.0}, {14, 8.0}, {16, 1.0}, {18, 7.0}],
            do: %MetricSample{labels: %{"__name__" => "boundary"}, timestamp_ns: time * 1_000_000_000, value: value}

      assert :ok = Storage.append(:metrics, "smoothing", Enum.reverse(samples ++ boundary))

      for {kind, _, sf, tf, expected} <- cases do
        expression = ~s|double_exponential_smoothing(smoothing{kind="#{kind}"}[10s], #{sf}, #{tf})|

        conn =
          build_conn()
          |> put_req_header("x-scope-orgid", "smoothing")
          |> get("/api/v1/query", query: expression, time: "20")

        response = json_response(conn, 200)
        assert Map.get(response, "warnings", []) == []

        assert Map.get(response, "infos", []) ==
                 if(kind in ["mixed", "one_mixed"],
                   do: [
                     ~s|PromQL info: ignored histograms in a range containing both floats and histograms for metric name "smoothing"|
                   ],
                   else: []
                 )

        expected = if expected, do: [%{"metric" => %{"kind" => kind}, "value" => [20.0, expected]}], else: []
        assert response["data"]["result"] == expected
      end

      for {range, sf, tf, time, expected} <- [
            {"boundary[10s]", "0.5", "0.25", "19.999999999", "76.1875"},
            {"boundary[10s]", "0.5", "0.25", "20", "9.4375"},
            {"boundary[10s]", "0.5", "0.25", "22", "0.5"},
            {"boundary[10s] offset 10s", "time()/40", "0.25", "30", "7.203125"},
            {"boundary[10s] offset 10s", "0.5", "time()/60", "30", "8.625"},
            {"boundary[8s:2s] offset 12s", "time()/40", "0.25", "30", "7.203125"}
          ] do
        expression = "holt_winters(#{range}, #{sf}, #{tf})"

        request(
          "/api/v1/query",
          %{query: expression, time: time},
          ["{} #{expected}"],
          "smoothing",
          expression,
          value(time),
          1
        )
      end

      expression = "double_exponential_smoothing(boundary[10s], 0.5, 0.25)"

      conn =
        build_conn()
        |> put_req_header("x-scope-orgid", "smoothing")
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post("/api/v1/query_range", URI.encode_query(query: expression, start: "20", end: "30", step: "2s"))

      assert %{
               "data" => %{"result" => [%{"metric" => %{}, "values" => [[20.0, "9.4375"], [22.0, "0.5"], [24.0, "7"]]}]}
             } =
               json_response(conn, 200)

      request("/api/v1/query", %{query: expression, time: "20"}, [], "other-tenant", expression, 20, 1)
    end

    @tag adapter: adapter
    test "Pulse smoothing validation, collisions and shared budgets through #{inspect(adapter)}" do
      assert :ok = Storage.append(:metrics, "smoothing-cost", records("smooth_a 2 8 1 7", 2_000_000_000))
      assert :ok = Storage.append(:metrics, "smoothing-cost", records("smooth_b 2 8 1 7", 2_000_000_000))
      assert :ok = Storage.append(:metrics, "smoothing-cost", records("hist {{schema:0 count:1 sum:2}}", 1_000_000_000))

      for {sf, tf, factor, parameter, value} <- [
            {"0", "0.25", "smoothing", "sf", "0.000000"},
            {"-0", "0.25", "smoothing", "sf", "-0.000000"},
            {"1", "0.25", "smoothing", "sf", "1.000000"},
            {"Inf", "0.25", "smoothing", "sf", "+Inf"},
            {"0.5", "-Inf", "trend", "tf", "-Inf"},
            {"NaN", "1.01", "trend", "tf", "1.010000"}
          ],
          range <- ["smooth_a[10s]", "hist[10s]"] do
        expression = "double_exponential_smoothing(#{range}, #{sf}, #{tf})"

        conn =
          build_conn()
          |> put_req_header("x-scope-orgid", "smoothing-cost")
          |> get("/api/v1/query", query: expression, time: "0")

        assert %{
                 "status" => "error",
                 "errorType" => "execution",
                 "error" => "invalid #{factor} factor. Expected: 0 < #{parameter} < 1, got: #{value}"
               } == json_response(conn, 422)
      end

      # Fixed-decimal float_to_binary has a bounded output buffer: even a
      # very large finite invalid factor must report an error, not crash HTTP.
      conn =
        build_conn()
        |> put_req_header("x-scope-orgid", "smoothing-cost")
        |> get("/api/v1/query", query: "holt_winters(smooth_a[10s], 1e308, 0.25)", time: "6")

      assert %{"errorType" => "execution", "error" => message} = json_response(conn, 422)
      assert String.starts_with?(message, "invalid smoothing factor. Expected: 0 < sf < 1, got: ")
      assert String.ends_with?(message, ".000000")

      expression = "double_exponential_smoothing(missing[10s], 0, Inf)"
      request("/api/v1/query", %{query: expression, time: "6"}, [], "smoothing-cost", expression, 6, 1)

      collision = ~s|double_exponential_smoothing({__name__=~"smooth_.*"}[10s], 0.5, 0.25)|
      request("/api/v1/query", %{query: collision, time: "6"}, [], "smoothing-cost", "eval_fail #{collision}", 6, 1)

      valid = "double_exponential_smoothing(smooth_a[10s], 0.5, 0.25)"

      for limits <- [[max_samples: 1], [max_work: 2], [max_result_points: 1]] do
        Runtime.put_env(:pulse, Evaluator, limits)

        conn =
          build_conn()
          |> put_req_header("x-scope-orgid", "smoothing-cost")
          |> get("/api/v1/query_range", query: valid, start: "6", end: "7", step: "1s")

        assert %{
                 "errorType" => "execution",
                 "error" => "query exceeded " <> _
               } = json_response(conn, 422)
      end

      Runtime.put_env(:pulse, Evaluator, max_work: 12)
      request("/api/v1/query", %{query: valid, time: "6"}, ["{} 9.4375"], "smoothing-cost", valid, 6, 1)
      batch = for ref <- ["a", "b"], do: {ref, valid, %{end_ts_ns: 6_000_000_000}}

      assert {:error, :query_work_limit} =
               Evaluator.query_batch(batch, "smoothing-cost", fn _, _ ->
                 flunk("over-budget smoothing batch reached consumer")
               end)
    end
  end

  for adapter <- [Memory, S3] do
    @tag adapter: adapter
    test "Pulse angular IEEE and histogram controls through HTTP and #{inspect(adapter)}" do
      histogram = %NativeHistogram{schema: 0, count: 1.0, sum: 90.0}

      # Finite expectations were independently checked with Go's constant
      # expressions. Compare bits: the upstream epsilon hides subnormal errors.
      cases = [
        {"negative_zero", -0.0, "-0", "-0"},
        {"subnormal", 5.0e-324, "0", "2.8161741812951053e-322"},
        {"negative_subnormal", -1.0e-323, "-0", "-5.6817549271743353e-322"},
        {"huge", 1.0e308, "1.7453292519943295e+306", "+Inf"},
        {"negative_huge", -1.0e308, "-1.7453292519943295e+306", "-Inf"},
        {"large_degrees", 1.0e306, "1.7453292519943295e+304", "5.7295779513082323e+307"},
        {"right_angle", 90.0, "1.5707963267948966", "5156.6201561774087"},
        {"nan", :nan, "NaN", "NaN"},
        {"infinity", :infinity, "+Inf", "+Inf"},
        {"negative_infinity", :negative_infinity, "-Inf", "-Inf"},
        {"histogram", histogram, nil, nil},
        {"stale_histogram", %{histogram | sum: :stale}, nil, nil},
        {"stale", :stale, nil, nil}
      ]

      samples =
        for {kind, value, _, _} <- cases do
          sample = %MetricSample{
            labels: %{"__name__" => "angles", "kind" => kind},
            timestamp_ns: 10_000_000_000
          }

          if is_struct(value, NativeHistogram), do: %{sample | histogram: value}, else: %{sample | value: value}
        end

      previous = %MetricSample{
        labels: %{"__name__" => "angles", "kind" => "stale"},
        timestamp_ns: 9_000_000_000,
        value: 90.0
      }

      assert :ok = Storage.append(:metrics, "angles", [previous | samples])

      for {name, position} <- [{"rad", 2}, {"deg", 3}],
          {path, params} <- [
            {"/api/v1/query", %{time: "20"}},
            {"/api/v1/query_range", %{start: "20", end: "21", step: "1s"}}
          ] do
        conn =
          build_conn()
          |> put_req_header("x-scope-orgid", "angles")
          |> get(path, Map.put(params, :query, "#{name}(angles)"))

        response = json_response(conn, 200)
        assert %{"data" => %{"result" => results}} = response

        expected =
          Map.new(cases, fn row -> {elem(row, 0), elem(row, position)} end) |> Map.reject(fn {_, v} -> is_nil(v) end)

        assert length(results) == map_size(expected)
        assert Map.get(response, "warnings", []) == []
        assert Map.get(response, "infos", []) == []

        for result <- results do
          assert %{"kind" => kind} = result["metric"]
          assert result["metric"] == %{"kind" => kind}
          expected = Map.fetch!(expected, kind)
          points = result["values"] || [result["value"]]
          assert Enum.map(points, &hd/1) == if(path == "/api/v1/query", do: [20.0], else: [20.0, 21.0])

          for [_, actual] <- points do
            if expected in ["NaN", "+Inf", "-Inf"],
              do: assert(actual == expected),
              else: assert(<<value(actual)::float-64>> == <<value(expected)::float-64>>, "#{name}: #{kind}")
          end
        end
      end
    end

    @tag adapter: adapter
    test "Pulse pi scalar and angular composition through HTTP and #{inspect(adapter)}" do
      samples =
        for {second, value} <- [{10, 90.0}, {11, 180.0}],
            do: %MetricSample{labels: %{"__name__" => "heading"}, timestamp_ns: second * 1_000_000_000, value: value}

      assert :ok = Storage.append(:metrics, "angles", samples)

      for {query, expected} <- [
            {"pi()", ["3.141592653589793"]},
            {"pi()/pi()", ["1"]},
            {"deg(vector(pi()/2))", ["{} 90"]},
            {"rad(vector(180))/pi()", ["{} 1"]},
            {"deg(rad(vector(-90)))", ["{} -90"]},
            {"rad(heading offset 10s)", ["{} 1.5707963267948966"]},
            {"sum_over_time(rad(heading)[2s:1s] offset 9s)", ["{} 4.71238898038469"]},
            {"deg(asin(vector(1)))", ["{} 90"]},
            {"acos(vector(0))/pi()", ["{} 0.5"]},
            {"atan(vector(Inf))/pi()", ["{} 0.5"]},
            {"asin(heading offset 10s / 180)", ["{} 0.5235987755982989"]},
            {"sum_over_time(atan(heading/180)[2s:1s] offset 9s)", ["{} 1.2490457723982544"]},
            {"sin(rad(heading offset 10s))", ["{} 1"]},
            {"cos(rad(heading))", ["{} -1"]},
            {"tan(rad(heading/4))", ["{} 1"]},
            {"sum_over_time(sin(rad(heading))[2s:1s] offset 9s)", ["{} 1"]},
            {"tanh(heading offset 10s / 180)", ["{} 0.46211715726000974"]},
            {"sinh(vector(0.5))/cosh(vector(0.5))", ["{} 0.46211715726000974"]},
            {"sum_over_time(tanh(heading/180)[2s:1s] offset 9s)", ["{} 1.2237113132157746"]},
            {"asinh(heading offset 10s / 180)", ["{} 0.48121182505960347"]},
            {"acosh(heading offset 10s / 180 + 1)", ["{} 0.96242365011920694"]},
            {"atanh(heading offset 10s / 360)", ["{} 0.25541281188299536"]},
            {"asinh(sinh(vector(-2.1)))", ["{} -2.1"]},
            {"sum_over_time(atanh(heading/360)[2s:1s] offset 9s)", ["{} 0.80471895621705014"]}
          ] do
        request("/api/v1/query", %{query: query, time: "20.125"}, expected, "angles", query, 20.125, 1)
      end

      request("/api/v1/query", %{query: "rad(heading)", time: "20"}, [], "other-tenant", "rad(heading)", 20, 1)

      for {query, expected} <- [
            {"sin(heading/180)", "{} 0.47942553860420301 0.8414709848078965"},
            {"cos(heading/180)", "{} 0.87758256189037276 0.5403023058681398"},
            {"tan(heading/180)", "{} 0.54630248984379048 1.5574077246549021"},
            {"sinh(heading/180)", "{} 0.52109530549374738 1.1752011936438014"},
            {"cosh(heading/180)", "{} 1.1276259652063807 1.5430806348152437"},
            {"tanh(heading/180)", "{} 0.46211715726000974 0.76159415595576485"},
            {"asinh(heading/180)", "{} 0.48121182505960347 0.88137358701954305"},
            {"acosh(heading/180 + 1)", "{} 0.96242365011920694 1.3169578969248166"},
            {"atanh(heading/360)", "{} 0.25541281188299536 0.54930614433405478"}
          ] do
        request(
          "/api/v1/query_range",
          %{query: query, start: "10", end: "11", step: "1s"},
          [expected],
          "angles",
          query,
          10,
          1
        )
      end

      request(
        "/api/v1/query_range",
        %{query: "pi()", start: "20.125", end: "21.125", step: "500ms"},
        ["{} 3.141592653589793x2"],
        "angles",
        "pi()",
        20.125,
        0.5
      )

      conn =
        build_conn()
        |> put_req_header("x-scope-orgid", "angles")
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post("/api/v1/query", URI.encode_query(query: "pi()", time: "20.125"))

      assert %{"data" => %{"resultType" => "scalar", "result" => [20.125, "3.141592653589793"]}} =
               json_response(conn, 200)
    end

    @tag adapter: adapter
    test "Pulse angular and scalar budgets through HTTP and #{inspect(adapter)}" do
      samples =
        for {kind, value} <- [{"a", 90.0}, {"b", 180.0}],
            do: %MetricSample{
              labels: %{"__name__" => "heading", "kind" => kind},
              timestamp_ns: 10_000_000_000,
              value: value
            }

      assert :ok = Storage.append(:metrics, "angles", samples)

      for {query, values} <- [
            {"rad(heading)", ["1.5707963267948966", "3.141592653589793"]},
            {"asin(heading/180)", ["0.5235987755982989", "1.5707963267948966"]},
            {"acos(heading/180)", ["1.0471975511965976", "0"]},
            {"atan(heading/180)", ["0.46364760900080609", "0.78539816339744828"]},
            {"sin(heading/180)", ["0.47942553860420301", "0.8414709848078965"]},
            {"cos(heading/180)", ["0.87758256189037276", "0.5403023058681398"]},
            {"tan(heading/180)", ["0.54630248984379048", "1.5574077246549021"]},
            {"sinh(heading/180)", ["0.52109530549374738", "1.1752011936438014"]},
            {"cosh(heading/180)", ["1.1276259652063807", "1.5430806348152437"]},
            {"tanh(heading/180)", ["0.46211715726000974", "0.76159415595576485"]},
            {"asinh(heading/180)", ["0.48121182505960347", "0.88137358701954305"]},
            {"acosh(heading/180 + 1)", ["0.96242365011920694", "1.3169578969248166"]},
            {"atanh(heading/360)", ["0.25541281188299536", "0.54930614433405478"]}
          ] do
        expected = Enum.zip_with(["a", "b"], values, fn kind, v -> ~s({kind="#{kind}"} #{v}) end)
        Runtime.put_env(:pulse, Evaluator, [])
        request("/api/v1/query", %{query: query, time: "20"}, expected, "angles", query, 20, 1)

        for limits <- [[max_samples: 1], [max_work: 1], [max_result_points: 1]] do
          Runtime.put_env(:pulse, Evaluator, limits)

          conn =
            build_conn() |> put_req_header("x-scope-orgid", "angles") |> get("/api/v1/query", query: query, time: "20")

          assert %{
                   "errorType" => "execution",
                   "error" => "query exceeded " <> _
                 } = json_response(conn, 422)
        end

        Runtime.put_env(:pulse, Evaluator, max_samples: 2)
        request("/api/v1/query", %{query: query, time: "20"}, expected, "angles", query, 20, 1)
        batch = for ref <- ["a", "b"], do: {ref, query, %{end_ts_ns: 20_000_000_000}}

        assert {:error, :query_sample_limit} =
                 Evaluator.query_batch(batch, "angles", fn _, _ ->
                   flunk("over-budget angular batch reached consumer")
                 end)
      end

      Runtime.put_env(:pulse, Evaluator, max_samples: 0, max_result_points: 1)
      request("/api/v1/query", %{query: "pi()", time: "20"}, ["3.141592653589793"], "angles", "pi()", 20, 1)
      batch = for ref <- ["a", "b"], do: {ref, "pi()", %{end_ts_ns: 20_000_000_000}}

      assert {:error, :query_result_limit} =
               Evaluator.query_batch(batch, "angles", fn _, _ -> flunk("over-budget scalar batch reached consumer") end)

      conn =
        build_conn()
        |> put_req_header("x-scope-orgid", "angles")
        |> get("/api/v1/query_range", query: "pi()", start: "20", end: "21", step: "1s")

      assert %{
               "errorType" => "execution",
               "error" => "query exceeded " <> _
             } = json_response(conn, 422)
    end
  end

  for adapter <- [Memory, S3] do
    @tag adapter: adapter
    test "Pulse inverse trigonometric domains and IEEE controls through HTTP and #{inspect(adapter)}" do
      histogram = %NativeHistogram{schema: 0, count: 1.0, sum: 0.5}

      # Independent Go 1.25.10 math results. Domain classifications and tiny
      # signed values are exact; other finite values allow one binary64 ULP.
      cases = [
        {"negative_outside", -1.0000000000000002, "NaN", "NaN", "-0.78539816339744839"},
        {"negative_endpoint", -1.0, "-1.5707963267948966", "3.1415926535897931", "-0.78539816339744828"},
        {"negative_inside", -0.9999999999999999, "-1.5707963118937354", "3.1415926386886319", "-0.78539816339744828"},
        {"negative_half", -0.5, "-0.52359877559829893", "2.0943951023931957", "-0.46364760900080609"},
        {"negative_zero", -0.0, "-0", "1.5707963267948966", "-0"},
        {"zero", 0.0, "0", "1.5707963267948966", "0"},
        {"subnormal", 5.0e-324, "4.9406564584124654e-324", "1.5707963267948966", "4.9406564584124654e-324"},
        {"negative_subnormal", -5.0e-324, "-4.9406564584124654e-324", "1.5707963267948966", "-4.9406564584124654e-324"},
        {"half", 0.5, "0.52359877559829893", "1.0471975511965976", "0.46364760900080609"},
        {"inside", 0.9999999999999999, "1.5707963118937354", "1.4901161193847656e-08", "0.78539816339744828"},
        {"endpoint", 1.0, "1.5707963267948966", "0", "0.78539816339744828"},
        {"outside", 1.0000000000000002, "NaN", "NaN", "0.78539816339744839"},
        {"huge", 1.0e308, "NaN", "NaN", "1.5707963267948966"},
        {"negative_huge", -1.0e308, "NaN", "NaN", "-1.5707963267948966"},
        {"nan", :nan, "NaN", "NaN", "NaN"},
        {"infinity", :infinity, "NaN", "NaN", "1.5707963267948966"},
        {"negative_infinity", :negative_infinity, "NaN", "NaN", "-1.5707963267948966"},
        {"histogram", histogram, nil, nil, nil},
        {"stale_histogram", %{histogram | sum: :stale}, nil, nil, nil},
        {"stale", :stale, nil, nil, nil}
      ]

      samples =
        for {kind, value, _, _, _} <- cases do
          sample = %MetricSample{
            labels: %{"__name__" => "inverse", "kind" => kind},
            timestamp_ns: 10_000_000_000
          }

          if is_struct(value, NativeHistogram), do: %{sample | histogram: value}, else: %{sample | value: value}
        end

      previous = %MetricSample{
        labels: %{"__name__" => "inverse", "kind" => "stale"},
        timestamp_ns: 9_000_000_000,
        value: 0.5
      }

      assert :ok = Storage.append(:metrics, "inverse", [previous | samples])

      for {name, position} <- [{"asin", 2}, {"acos", 3}, {"atan", 4}],
          {path, params} <- [
            {"/api/v1/query", %{time: "20"}},
            {"/api/v1/query_range", %{start: "20", end: "21", step: "1s"}}
          ] do
        conn =
          build_conn()
          |> put_req_header("x-scope-orgid", "inverse")
          |> get(path, Map.put(params, :query, "#{name}(inverse)"))

        response = json_response(conn, 200)
        assert %{"data" => %{"result" => results, "resultType" => type}} = response
        assert type == if(path == "/api/v1/query", do: "vector", else: "matrix")

        expected =
          Map.new(cases, fn row -> {elem(row, 0), elem(row, position)} end) |> Map.reject(fn {_, v} -> is_nil(v) end)

        assert length(results) == map_size(expected)
        assert MapSet.new(results, & &1["metric"]) == MapSet.new(Map.keys(expected), &%{"kind" => &1})
        assert Map.get(response, "warnings", []) == []
        assert Map.get(response, "infos", []) == []

        for result <- results do
          kind = result["metric"]["kind"]
          expected = Map.fetch!(expected, kind)
          points = result["values"] || [result["value"]]
          assert Enum.map(points, &hd/1) == if(path == "/api/v1/query", do: [20.0], else: [20.0, 21.0])

          for [_, actual] <- points do
            if expected == "NaN" do
              assert actual == "NaN"
            else
              <<actual_bits::64>> = <<value(actual)::float-64>>
              <<expected_bits::64>> = <<value(expected)::float-64>>
              tolerance = if abs(value(expected)) < 1.0e-300, do: 0, else: 1
              assert abs(actual_bits - expected_bits) <= tolerance, "#{name}: #{kind}"
            end
          end
        end
      end

      conn =
        build_conn()
        |> put_req_header("x-scope-orgid", "inverse")
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post("/api/v1/query", URI.encode_query(query: "acos(inverse)", time: "20"))

      assert %{"data" => %{"result" => results}} = json_response(conn, 200)
      assert Enum.any?(results, &(&1["metric"] == %{"kind" => "outside"} and &1["value"] == [20.0, "NaN"]))
      request("/api/v1/query", %{query: "acos(inverse)", time: "20"}, [], "other-tenant", "acos(inverse)", 20, 1)
    end
  end

  for adapter <- [Memory, S3] do
    @tag adapter: adapter
    test "Pulse circular trigonometric IEEE and reduction controls through HTTP and #{inspect(adapter)}" do
      histogram = %NativeHistogram{schema: 0, count: 1.0, sum: 0.5}

      # Independent Go 1.25.10 math expectations, not values from this evaluator.
      # Go and platform range reduction differ near poles and huge arguments;
      # require 1e-14 relative accuracy, with tiny values/zero signs exact.
      cases = [
        {"negative_zero", -0.0, "-0", "1", "-0"},
        {"zero", 0.0, "0", "1", "0"},
        {"subnormal", 5.0e-324, "4.9406564584124654e-324", "1", "4.9406564584124654e-324"},
        {"negative_subnormal", -5.0e-324, "-4.9406564584124654e-324", "1", "-4.9406564584124654e-324"},
        {"half", 0.5, "0.47942553860420301", "0.87758256189037276", "0.54630248984379048"},
        {"negative_half", -0.5, "-0.47942553860420301", "0.87758256189037276", "-0.54630248984379048"},
        {"quadrant", 2.1, "0.86320936664887371", "-0.50484610459985746", "-1.7098465429045075"},
        {"negative_quadrant", -2.1, "-0.86320936664887371", "-0.50484610459985746", "1.7098465429045075"},
        {"below_pole", 1.5707963267948963, "1", "2.8327694488239888e-16", "3530114321217158.5"},
        {"nearest_pole", 1.5707963267948966, "1", "6.1232339957367574e-17", "16331239353195392"},
        {"above_pole", 1.5707963267948968, "1", "-1.6081226496766373e-16", "-6218431163823735"},
        {"pi", 3.141592653589793, "1.2246467991473515e-16", "-1", "-1.2246467991473515e-16"},
        {"negative_pi", -3.141592653589793, "-1.2246467991473515e-16", "-1", "1.2246467991473515e-16"},
        {"large", 1.0e20, "-0.64525128526578079", "0.76397040444172837", "-0.84460246301988418"},
        {"negative_large", -1.0e20, "0.64525128526578079", "0.76397040444172837", "0.84460246301988418"},
        {"huge", 1.0e308, "0.45339649050164915", "-0.89130893768703334", "-0.50868612591075679"},
        {"negative_huge", -1.0e308, "-0.45339649050164915", "-0.89130893768703334", "0.50868612591075679"},
        {"maximum", 1.797_693_134_862_315_7e308, "0.0049619547891840837", "-0.99998768942655991",
         "-0.0049620158744449168"},
        {"nan", :nan, "NaN", "NaN", "NaN"},
        {"infinity", :infinity, "NaN", "NaN", "NaN"},
        {"negative_infinity", :negative_infinity, "NaN", "NaN", "NaN"},
        {"histogram", histogram, nil, nil, nil},
        {"stale_histogram", %{histogram | sum: :stale}, nil, nil, nil},
        {"stale", :stale, nil, nil, nil}
      ]

      samples =
        for {kind, value, _, _, _} <- cases do
          sample = %MetricSample{
            labels: %{"__name__" => "circular", "kind" => kind},
            timestamp_ns: 10_000_000_000
          }

          if is_struct(value, NativeHistogram), do: %{sample | histogram: value}, else: %{sample | value: value}
        end

      previous = %MetricSample{
        labels: %{"__name__" => "circular", "kind" => "stale"},
        timestamp_ns: 9_000_000_000,
        value: 0.5
      }

      assert :ok = Storage.append(:metrics, "circular", [previous | samples])

      for {name, position} <- [{"sin", 2}, {"cos", 3}, {"tan", 4}],
          {path, params} <- [
            {"/api/v1/query", %{time: "20"}},
            {"/api/v1/query_range", %{start: "20", end: "21", step: "1s"}}
          ] do
        conn =
          build_conn()
          |> put_req_header("x-scope-orgid", "circular")
          |> get(path, Map.put(params, :query, "#{name}(circular)"))

        response = json_response(conn, 200)
        assert %{"data" => %{"result" => results, "resultType" => type}} = response
        assert type == if(path == "/api/v1/query", do: "vector", else: "matrix")

        expected =
          Map.new(cases, fn row -> {elem(row, 0), elem(row, position)} end) |> Map.reject(fn {_, v} -> is_nil(v) end)

        assert length(results) == map_size(expected)
        assert MapSet.new(results, & &1["metric"]) == MapSet.new(Map.keys(expected), &%{"kind" => &1})
        assert Map.get(response, "warnings", []) == []
        assert Map.get(response, "infos", []) == []

        for result <- results do
          kind = result["metric"]["kind"]
          expected = Map.fetch!(expected, kind)
          points = result["values"] || [result["value"]]
          assert Enum.map(points, &hd/1) == if(path == "/api/v1/query", do: [20.0], else: [20.0, 21.0])

          for [_, actual] <- points do
            cond do
              expected == "NaN" ->
                assert actual == "NaN"

              abs(value(expected)) < 1.0e-300 ->
                assert <<value(actual)::float-64>> == <<value(expected)::float-64>>, "#{name}: #{kind}"

              true ->
                assert_in_delta value(actual), value(expected), abs(value(expected)) * 1.0e-14, "#{name}: #{kind}"
            end
          end
        end
      end

      conn =
        build_conn()
        |> put_req_header("x-scope-orgid", "circular")
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post("/api/v1/query", URI.encode_query(query: "tan(circular)", time: "20"))

      assert %{"data" => %{"result" => results}} = json_response(conn, 200)
      assert Enum.any?(results, &(&1["metric"] == %{"kind" => "infinity"} and &1["value"] == [20.0, "NaN"]))
      request("/api/v1/query", %{query: "tan(circular)", time: "20"}, [], "other-tenant", "tan(circular)", 20, 1)
    end
  end

  for adapter <- [Memory, S3] do
    @tag adapter: adapter
    test "Pulse hyperbolic IEEE and overflow controls through HTTP and #{inspect(adapter)}" do
      histogram = %NativeHistogram{schema: 0, count: 1.0, sum: 0.5}

      # Independent Go 1.25.10 math results. Classifications, tiny signed values
      # and saturation are exact; other selected finite values allow one ULP.
      cases = [
        {"negative_zero", -0.0, "-0", "1", "-0"},
        {"zero", 0.0, "0", "1", "0"},
        {"subnormal", 5.0e-324, "4.9406564584124654e-324", "1", "4.9406564584124654e-324"},
        {"negative_subnormal", -5.0e-324, "-4.9406564584124654e-324", "1", "-4.9406564584124654e-324"},
        {"half", 0.5, "0.52109530549374738", "1.1276259652063807", "0.46211715726000974"},
        {"negative_half", -0.5, "-0.52109530549374738", "1.1276259652063807", "-0.46211715726000974"},
        {"asymmetric", 2.1, "4.0218567421573344", "4.1443131704103155", "0.97045193661345386"},
        {"negative_asymmetric", -2.1, "-4.0218567421573344", "4.1443131704103155", "-0.97045193661345386"},
        {"ten", 10.0, "11013.232874703393", "11013.232920103324", "0.99999999587769273"},
        {"below_branch", 20.999999999999996, "659407867.24160504", "659407867.24160504", "1"},
        {"branch", 21.0, "659407867.24160731", "659407867.24160731", "1"},
        {"above_branch", 21.000000000000004, "659407867.24160969", "659407867.24160969", "1"},
        {"below_overflow", 709.7827128933839, "8.9884656743103441e307", "8.9884656743103441e307", "1"},
        {"overflow_edge", 709.782712893384, "8.988465674311366e307", "8.988465674311366e307", "1"},
        {"above_overflow", 709.7827128933841, "+Inf", "+Inf", "1"},
        {"negative_edge", -709.782712893384, "-8.988465674311366e307", "8.988465674311366e307", "-1"},
        {"negative_overflow", -709.7827128933841, "-Inf", "+Inf", "-1"},
        {"platform_still_finite", 710.0, "+Inf", "+Inf", "1"},
        {"negative_platform_still_finite", -710.0, "-Inf", "+Inf", "-1"},
        {"maximum", 1.797_693_134_862_315_7e308, "+Inf", "+Inf", "1"},
        {"negative_maximum", -1.797_693_134_862_315_7e308, "-Inf", "+Inf", "-1"},
        {"nan", :nan, "NaN", "NaN", "NaN"},
        {"infinity", :infinity, "+Inf", "+Inf", "1"},
        {"negative_infinity", :negative_infinity, "-Inf", "+Inf", "-1"},
        {"histogram", histogram, nil, nil, nil},
        {"stale_histogram", %{histogram | sum: :stale}, nil, nil, nil},
        {"stale", :stale, nil, nil, nil}
      ]

      samples =
        for {kind, value, _, _, _} <- cases do
          sample = %MetricSample{
            labels: %{"__name__" => "hyperbolic", "kind" => kind},
            timestamp_ns: 10_000_000_000
          }

          if is_struct(value, NativeHistogram), do: %{sample | histogram: value}, else: %{sample | value: value}
        end

      previous = %MetricSample{
        labels: %{"__name__" => "hyperbolic", "kind" => "stale"},
        timestamp_ns: 9_000_000_000,
        value: 0.5
      }

      assert :ok = Storage.append(:metrics, "hyperbolic", [previous | samples])

      for {name, position} <- [{"sinh", 2}, {"cosh", 3}, {"tanh", 4}],
          {path, params} <- [
            {"/api/v1/query", %{time: "20"}},
            {"/api/v1/query_range", %{start: "20", end: "21", step: "1s"}}
          ] do
        conn =
          build_conn()
          |> put_req_header("x-scope-orgid", "hyperbolic")
          |> get(path, Map.put(params, :query, "#{name}(hyperbolic)"))

        response = json_response(conn, 200)
        assert %{"data" => %{"result" => results, "resultType" => type}} = response
        assert type == if(path == "/api/v1/query", do: "vector", else: "matrix")

        expected =
          Map.new(cases, fn row -> {elem(row, 0), elem(row, position)} end) |> Map.reject(fn {_, v} -> is_nil(v) end)

        assert length(results) == map_size(expected)
        assert MapSet.new(results, & &1["metric"]) == MapSet.new(Map.keys(expected), &%{"kind" => &1})
        assert Map.get(response, "warnings", []) == []
        assert Map.get(response, "infos", []) == []

        for result <- results do
          kind = result["metric"]["kind"]
          expected = Map.fetch!(expected, kind)
          points = result["values"] || [result["value"]]
          assert Enum.map(points, &hd/1) == if(path == "/api/v1/query", do: [20.0], else: [20.0, 21.0])

          for [_, actual] <- points do
            if expected in ["NaN", "+Inf", "-Inf"] do
              assert actual == expected
            else
              <<actual_bits::64>> = <<value(actual)::float-64>>
              <<expected_bits::64>> = <<value(expected)::float-64>>
              exact? = abs(value(expected)) < 1.0e-300 or (name == "tanh" and abs(value(expected)) == 1)
              assert abs(actual_bits - expected_bits) <= if(exact?, do: 0, else: 1), "#{name}: #{kind}"
            end
          end
        end
      end

      conn =
        build_conn()
        |> put_req_header("x-scope-orgid", "hyperbolic")
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post("/api/v1/query", URI.encode_query(query: "sinh(hyperbolic)", time: "20"))

      assert %{"data" => %{"result" => results}} = json_response(conn, 200)

      assert Enum.any?(
               results,
               &(&1["metric"] == %{"kind" => "platform_still_finite"} and &1["value"] == [20.0, "+Inf"])
             )

      request("/api/v1/query", %{query: "sinh(hyperbolic)", time: "20"}, [], "other-tenant", "sinh(hyperbolic)", 20, 1)
    end
  end

  for adapter <- [Memory, S3] do
    @tag adapter: adapter
    test "Pulse inverse hyperbolic domains and IEEE controls through HTTP and #{inspect(adapter)}" do
      histogram = %NativeHistogram{schema: 0, count: 1.0, sum: 0.5}

      # Independent Go 1.25.10 math results. Compare domain classifications and
      # tiny signed values exactly; other selected finite values allow one ULP.
      cases = [
        {"negative_zero", -0.0, "-0", "NaN", "-0"},
        {"zero", 0.0, "0", "NaN", "0"},
        {"subnormal", 5.0e-324, "4.9406564584124654e-324", "NaN", "4.9406564584124654e-324"},
        {"negative_subnormal", -5.0e-324, "-4.9406564584124654e-324", "NaN", "-4.9406564584124654e-324"},
        {"half", 0.5, "0.48121182505960347", "NaN", "0.54930614433405478"},
        {"negative_half", -0.5, "-0.48121182505960347", "NaN", "-0.54930614433405478"},
        {"inside", 0.9999999999999999, "0.88137358701954294", "NaN", "18.714973875118524"},
        {"negative_inside", -0.9999999999999999, "-0.88137358701954294", "NaN", "-18.714973875118524"},
        {"endpoint", 1.0, "0.88137358701954305", "0", "+Inf"},
        {"negative_endpoint", -1.0, "-0.88137358701954305", "NaN", "-Inf"},
        {"outside", 1.0000000000000002, "0.88137358701954316", "2.1073424255447017e-08", "NaN"},
        {"negative_outside", -1.0000000000000002, "-0.88137358701954316", "NaN", "NaN"},
        {"asymmetric", 2.1, "1.4874828366412711", "1.3728591442425799", "NaN"},
        {"negative_asymmetric", -2.1, "-1.4874828366412711", "NaN", "NaN"},
        {"below_large", 268_435_455.99999997, "20.101268236238415", "20.101268236238415", "NaN"},
        {"large", 268_435_456.0, "20.101268236238415", "20.101268236238411", "NaN"},
        {"above_large", 268_435_456.00000006, "20.101268236238411", "20.101268236238411", "NaN"},
        {"huge", 1.0e308, "709.88935582272597", "709.88935582272597", "NaN"},
        {"negative_huge", -1.0e308, "-709.88935582272597", "NaN", "NaN"},
        {"maximum", 1.797_693_134_862_315_7e308, "710.47586007394386", "710.47586007394386", "NaN"},
        {"negative_maximum", -1.797_693_134_862_315_7e308, "-710.47586007394386", "NaN", "NaN"},
        {"nan", :nan, "NaN", "NaN", "NaN"},
        {"infinity", :infinity, "+Inf", "+Inf", "NaN"},
        {"negative_infinity", :negative_infinity, "-Inf", "NaN", "NaN"},
        {"histogram", histogram, nil, nil, nil},
        {"stale_histogram", %{histogram | sum: :stale}, nil, nil, nil},
        {"stale", :stale, nil, nil, nil}
      ]

      samples =
        for {kind, value, _, _, _} <- cases do
          sample = %MetricSample{
            labels: %{"__name__" => "inverse_hyperbolic", "kind" => kind},
            timestamp_ns: 10_000_000_000
          }

          if is_struct(value, NativeHistogram), do: %{sample | histogram: value}, else: %{sample | value: value}
        end

      previous = %MetricSample{
        labels: %{"__name__" => "inverse_hyperbolic", "kind" => "stale"},
        timestamp_ns: 9_000_000_000,
        value: 0.5
      }

      assert :ok = Storage.append(:metrics, "inverse-hyperbolic", [previous | samples])

      for {name, position} <- [{"asinh", 2}, {"acosh", 3}, {"atanh", 4}],
          {path, params} <- [
            {"/api/v1/query", %{time: "20"}},
            {"/api/v1/query_range", %{start: "20", end: "21", step: "1s"}}
          ] do
        conn =
          build_conn()
          |> put_req_header("x-scope-orgid", "inverse-hyperbolic")
          |> get(path, Map.put(params, :query, "#{name}(inverse_hyperbolic)"))

        response = json_response(conn, 200)
        assert %{"data" => %{"result" => results, "resultType" => type}} = response
        assert type == if(path == "/api/v1/query", do: "vector", else: "matrix")

        expected =
          Map.new(cases, fn row -> {elem(row, 0), elem(row, position)} end) |> Map.reject(fn {_, v} -> is_nil(v) end)

        assert length(results) == map_size(expected)
        assert MapSet.new(results, & &1["metric"]) == MapSet.new(Map.keys(expected), &%{"kind" => &1})
        assert Map.get(response, "warnings", []) == []
        assert Map.get(response, "infos", []) == []

        for result <- results do
          kind = result["metric"]["kind"]
          expected = Map.fetch!(expected, kind)
          points = result["values"] || [result["value"]]
          assert Enum.map(points, &hd/1) == if(path == "/api/v1/query", do: [20.0], else: [20.0, 21.0])

          for [_, actual] <- points do
            if expected in ["NaN", "+Inf", "-Inf"] do
              assert actual == expected
            else
              <<actual_bits::64>> = <<value(actual)::float-64>>
              <<expected_bits::64>> = <<value(expected)::float-64>>
              tolerance = if abs(value(expected)) < 1.0e-300, do: 0, else: 1
              assert abs(actual_bits - expected_bits) <= tolerance, "#{name}: #{kind}"
            end
          end
        end
      end

      conn =
        build_conn()
        |> put_req_header("x-scope-orgid", "inverse-hyperbolic")
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post("/api/v1/query", URI.encode_query(query: "atanh(inverse_hyperbolic)", time: "20"))

      assert %{"data" => %{"result" => results}} = json_response(conn, 200)
      assert Enum.any?(results, &(&1["metric"] == %{"kind" => "endpoint"} and &1["value"] == [20.0, "+Inf"]))

      query = "atanh(inverse_hyperbolic)"
      request("/api/v1/query", %{query: query, time: "20"}, [], "other-tenant", query, 20, 1)
    end
  end

  for adapter <- [Memory, S3] do
    @tag adapter: adapter
    test "Pulse UTC calendar boundaries and defaults through HTTP and #{inspect(adapter)}" do
      names = ~w(year month day_of_month day_of_week day_of_year days_in_month hour minute)
      # Independently checked against Go time.Unix(...).UTC(), not DateTime.
      cases = [
        {"epoch", 0.0, [1970, 1, 1, 4, 1, 31, 0, 0]},
        {"fraction", -0.9, [1970, 1, 1, 4, 1, 31, 0, 0]},
        {"before_epoch", -1.9, [1969, 12, 31, 3, 365, 31, 23, 59]},
        {"year_zero", -62_167_219_200.0, [0, 1, 1, 6, 1, 31, 0, 0]},
        {"century", -2_203_891_200.0, [1900, 3, 1, 4, 60, 31, 0, 0]},
        {"leap", 951_827_696.9, [2000, 2, 29, 2, 60, 29, 12, 34]},
        {"nan", :nan, [1970, 1, 1, 4, 1, 31, 0, 0]},
        {"infinity", :infinity, [292_277_026_596, 12, 4, 0, 339, 31, 15, 30]},
        {"negative_infinity", :negative_infinity, [292_277_026_596, 12, 4, 0, 339, 31, 15, 30]},
        {"overflow", 1.0e308, [292_277_026_596, 12, 4, 0, 339, 31, 15, 30]},
        {"underflow", -1.0e308, [292_277_026_596, 12, 4, 0, 339, 31, 15, 30]},
        {"below_int64", 9_223_372_036_854_774_784.0, [292_277_026_596, 12, 4, 0, 339, 31, 15, 13]}
      ]

      samples =
        for {kind, value, _} <- cases do
          %MetricSample{labels: %{"__name__" => "calendar", "kind" => kind}, timestamp_ns: 10_000_000_000, value: value}
        end

      histogram = %MetricSample{
        labels: %{"__name__" => "calendar", "kind" => "histogram"},
        timestamp_ns: 10_000_000_000,
        histogram: %NativeHistogram{schema: 0, count: 1.0, sum: 1.0}
      }

      stale = %MetricSample{
        labels: %{"__name__" => "calendar", "kind" => "stale"},
        timestamp_ns: 10_000_000_000,
        value: :stale
      }

      assert :ok = Storage.append(:metrics, "calendar", [histogram, stale | samples])

      for {name, index} <- Enum.with_index(names) do
        expected = for {kind, _, fields} <- cases, do: ~s({kind="#{kind}"} #{Enum.at(fields, index)})
        check("eval instant at 20s #{name}(calendar)", expected, "calendar")
        request("/api/v1/query", %{query: "#{name}(calendar)", time: "20"}, [], "other-tenant", name, 20, 1)
        default = Enum.at([2000, 2, 29, 2, 60, 29, 12, 34], index)

        request(
          "/api/v1/query",
          %{query: "#{name}()", time: "951827696.9"},
          ["{} #{default}"],
          "calendar",
          name,
          951_827_696.9,
          1
        )
      end

      request(
        "/api/v1/query_range",
        %{query: "day_of_month()", start: "951696000", end: "951868800", step: "1d"},
        ["{} 28 29 1"],
        "calendar",
        "day_of_month()",
        951_696_000,
        86_400
      )

      conn =
        build_conn()
        |> put_req_header("x-scope-orgid", "calendar")
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post("/api/v1/query", URI.encode_query(query: "minute()", time: "951827696.9"))

      assert %{"data" => %{"result" => [%{"metric" => %{}, "value" => [951_827_696.9, "34"]}]}} =
               json_response(conn, 200)
    end

    @tag adapter: adapter
    test "Pulse natural label sorting preserves samples and reverses ties through #{inspect(adapter)}" do
      histogram = %NativeHistogram{schema: 0, count: 1.0, sum: 3.0}

      rows = [
        {"node10", "b", :nan},
        {"node2", "z", -0.0},
        {"node2", "a", histogram},
        {"Node1", "a", :infinity},
        {"nœud2", "a", :negative_infinity},
        {"node٢", "a", 17.0}
      ]

      samples =
        for {key, tie, value} <- rows do
          sample = %MetricSample{
            labels: %{"__name__" => "label_order", "key" => key, "tie" => tie},
            timestamp_ns: 10_000_000_000
          }

          if is_struct(value, NativeHistogram), do: %{sample | histogram: value}, else: %{sample | value: value}
        end

      assert :ok = Storage.append(:metrics, "label-order", samples)
      expected = [{"Node1", "a"}, {"node2", "a"}, {"node2", "z"}, {"node10", "b"}, {"node٢", "a"}, {"nœud2", "a"}]

      for {name, order} <- [{"sort_by_label", expected}, {"sort_by_label_desc", Enum.reverse(expected)}] do
        conn =
          build_conn()
          |> put_req_header("x-scope-orgid", "label-order")
          |> get("/api/v1/query", query: ~s|#{name}(label_order, "key")|, time: "20")

        assert %{"data" => %{"result" => results}} = response = json_response(conn, 200)
        assert Enum.map(results, &{&1["metric"]["key"], &1["metric"]["tie"]}) == order
        assert Enum.all?(results, &(&1["metric"]["__name__"] == "label_order"))
        by_key = Map.new(results, &{{&1["metric"]["key"], &1["metric"]["tie"]}, &1})
        assert by_key[{"node2", "z"}]["value"] == [20.0, "-0"]
        assert by_key[{"node10", "b"}]["value"] == [20.0, "NaN"]
        assert by_key[{"Node1", "a"}]["value"] == [20.0, "+Inf"]
        assert by_key[{"nœud2", "a"}]["value"] == [20.0, "-Inf"]
        assert by_key[{"node٢", "a"}]["value"] == [20.0, "17"]
        assert by_key[{"node2", "a"}]["histogram"] == [20.0, %{"count" => "1", "sum" => "3"}]
        assert Map.get(response, "infos", []) == []
      end

      # Empty requested values fall through to the complete lexical label set,
      # including the name; label count and numeric-aware fallback are wrong.
      assert :ok =
               Storage.append(:metrics, "label-ties", [
                 %MetricSample{labels: %{"__name__" => "tie_z", "n" => "1"}, timestamp_ns: 0, value: 1.0},
                 %MetricSample{
                   labels: %{"__name__" => "tie_a", "n" => "2", "extra" => "x"},
                   timestamp_ns: 0,
                   value: 2.0
                 }
               ])

      for args <- ["", ~s|, "missing"|, ~s|, "missing", "missing"|] do
        check(
          ~s|eval_ordered instant at 0 sort_by_label({__name__=~"tie_.*"}#{args})|,
          [~s(tie_a{n="2",extra="x"} 2), ~s(tie_z{n="1"} 1)],
          "label-ties"
        )
      end

      # Both runs overflow int64: lexical fallback deliberately puts the larger
      # mathematical integer first. Arbitrary precision natural sorting differs.
      for {key, value} <- [{"100000000000000000000", 1.0}, {"99999999999999999999", 2.0}] do
        assert :ok =
                 Storage.append(:metrics, "overflow-sort", [
                   %MetricSample{labels: %{"__name__" => "overflow_sort", "key" => key}, timestamp_ns: 0, value: value}
                 ])
      end

      check(
        ~s|eval_ordered instant at 0 sort_by_label(overflow_sort, "key")|,
        [~s(overflow_sort{key="100000000000000000000"} 1), ~s(overflow_sort{key="99999999999999999999"} 2)],
        "overflow-sort"
      )

      batch = [
        {"range", ~s|sort_by_label(label_order, "key")|,
         %{start_ts_ns: 20_000_000_000, end_ts_ns: 21_000_000_000, step_ns: 1_000_000_000}},
        {"instant", ~s|sort_by_label_desc(label_order, "key")|, %{end_ts_ns: 20_000_000_000}}
      ]

      assert {:ok, results} = Evaluator.query_batch(batch, "label-order", fn result, _ -> {:ok, result} end)

      assert results["range"]["warnings"] == [
               "PromQL warning: sort is ineffective for range queries since results are always ordered by labels"
             ]

      refute Map.has_key?(results["instant"], "warnings")

      assert Enum.map(results["instant"]["data"]["result"], &{&1["metric"]["key"], &1["metric"]["tie"]}) ==
               Enum.reverse(expected)
    end

    @tag adapter: adapter
    test "Pulse atan2 IEEE quadrants and signed zero through HTTP and #{inspect(adapter)}" do
      axes = [
        {"p0", 0.0},
        {"n0", -0.0},
        {"pos", 2.0},
        {"neg", -3.0},
        {"pinf", :infinity},
        {"ninf", :negative_infinity},
        {"nan", :nan}
      ]

      expected = [
        ["0", "3.141592653589793", "0", "3.141592653589793", "0", "3.141592653589793", "NaN"],
        ["-0", "-3.141592653589793", "-0", "-3.141592653589793", "-0", "-3.141592653589793", "NaN"],
        [
          "1.5707963267948966",
          "1.5707963267948966",
          "0.7853981633974483",
          "2.5535900500422257",
          "0",
          "3.141592653589793",
          "NaN"
        ],
        [
          "-1.5707963267948966",
          "-1.5707963267948966",
          "-0.982793723247329",
          "-2.356194490192345",
          "-0",
          "-3.141592653589793",
          "NaN"
        ],
        [
          "1.5707963267948966",
          "1.5707963267948966",
          "1.5707963267948966",
          "1.5707963267948966",
          "0.7853981633974483",
          "2.356194490192345",
          "NaN"
        ],
        [
          "-1.5707963267948966",
          "-1.5707963267948966",
          "-1.5707963267948966",
          "-1.5707963267948966",
          "-0.7853981633974483",
          "-2.356194490192345",
          "NaN"
        ],
        List.duplicate("NaN", 7)
      ]

      samples =
        for {y, yv} <- axes, {x, xv} <- axes, {name, v} <- [{"ordinate", yv}, {"abscissa", xv}] do
          %MetricSample{labels: %{"__name__" => name, "y" => y, "x" => x}, timestamp_ns: 10_000_000_000, value: v}
        end

      assert :ok = Storage.append(:metrics, "atan2", samples)

      oracle =
        Map.new(
          for {{y, _}, i} <- Enum.with_index(axes),
              {{x, _}, j} <- Enum.with_index(axes),
              do: {{y, x}, expected |> Enum.at(i) |> Enum.at(j)}
        )

      for {path, params} <- [
            {"/api/v1/query", %{time: "20"}},
            {"/api/v1/query_range", %{start: "20", end: "21", step: "1s"}}
          ] do
        conn =
          build_conn()
          |> put_req_header("x-scope-orgid", "atan2")
          |> get(path, Map.put(params, :query, "ordinate atan2 abscissa"))

        assert %{"data" => %{"result" => results}} = response = json_response(conn, 200)
        assert length(results) == 49
        assert Map.get(response, "warnings", []) == []
        assert Map.get(response, "infos", []) == []

        for row <- results do
          assert Map.keys(row["metric"]) |> Enum.sort() == ["x", "y"]
          wanted = Map.fetch!(oracle, {row["metric"]["y"], row["metric"]["x"]})

          for [_, actual] <- row["values"] || [row["value"]] do
            if wanted in ["0", "-0", "NaN"],
              do: assert(actual == wanted),
              else: assert_in_delta(value(actual), value(wanted), 1.0e-15)
          end
        end
      end

      check("eval instant at 20s 1 + 2 atan2 3 * 4", ["3.35201041419027"], "atan2")
    end

    @tag adapter: adapter
    test "Pulse atan2 histogram omission, operand order and matching through #{inspect(adapter)}" do
      samples = [
        %MetricSample{labels: %{"__name__" => "a", "job" => "api", "kind" => "float"}, timestamp_ns: 0, value: 2.0},
        %MetricSample{
          labels: %{"__name__" => "a", "job" => "api", "kind" => "hist"},
          timestamp_ns: 0,
          histogram: %NativeHistogram{schema: 0, count: 1.0, sum: 2.0}
        },
        %MetricSample{labels: %{"__name__" => "b", "job" => "api", "zone" => "west"}, timestamp_ns: 0, value: -3.0}
      ]

      assert :ok = Storage.append(:metrics, "atan2-types", samples)

      for {query, wanted, info} <- [
            {"a atan2 2", ~s({job="api",kind="float"} 0.7853981633974483), "histogram atan2 float"},
            {"2 atan2 a", ~s({job="api",kind="float"} 0.7853981633974483), "float atan2 histogram"},
            {"a atan2 a", ~s({job="api",kind="float"} 0.7853981633974483), "histogram atan2 histogram"},
            {"a atan2 on(job) group_left(zone) b", ~s({job="api",kind="float",zone="west"} 2.5535900500422257),
             "histogram atan2 float"},
            {"b atan2 on(job) group_right(zone) a", ~s({job="api",kind="float",zone="west"} -0.982793723247329),
             "float atan2 histogram"}
          ] do
        conn =
          build_conn()
          |> put_req_header("x-scope-orgid", "atan2-types")
          |> get("/api/v1/query", query: query, time: "0")

        assert %{"data" => data, "infos" => infos} = response = json_response(conn, 200)
        assert_query_data(data, [wanted], "/api/v1/query", query, 0, 1)
        assert infos == [~s(PromQL info: incompatible sample types encountered for binary operator "atan2": #{info})]
        assert Map.get(response, "warnings", []) == []
      end

      check(
        ~s|eval instant at 0 a{kind="float"} atan2 on(job) group_left(__name__) b|,
        [~s(b{job="api",kind="float"} 2.5535900500422257), "expect no_info"],
        "atan2-types"
      )

      check(
        ~s|eval instant at 0 b atan2 on(job) group_right(__name__) a{kind="float"}|,
        [~s(b{job="api",kind="float"} -0.982793723247329), "expect no_info"],
        "atan2-types"
      )

      check(~s|eval instant at 0 a{kind="hist"} atan2 on(job) b{zone="missing"}|, ["expect no_info"], "atan2-types")
      request("/api/v1/query", %{query: "a atan2 2", time: "0"}, [], "other-tenant", "atan2", 0, 1)

      batch = [{"hist", "a atan2 2", %{end_ts_ns: 0}}, {"float", ~s|a{kind="float"} atan2 2|, %{end_ts_ns: 0}}]
      assert {:ok, results} = Evaluator.query_batch(batch, "atan2-types", fn result, _ -> {:ok, result} end)
      assert length(results["hist"]["infos"]) == 1
      refute Map.has_key?(results["float"], "infos")
    end

    @tag adapter: adapter
    test "Pulse calendar, label sort and atan2 share query budgets through #{inspect(adapter)}" do
      samples =
        for {key, v} <- [{"node10", 10.0}, {"node2", 2.0}] do
          %MetricSample{labels: %{"__name__" => "batch_cost", "key" => key}, timestamp_ns: 0, value: v}
        end

      assert :ok = Storage.append(:metrics, "batch-cost", samples)

      for query <- ["year(batch_cost)", ~s|sort_by_label(batch_cost, "key")|, "batch_cost atan2 3"],
          limits <- [[max_samples: 1], [max_work: 1], [max_result_points: 1]] do
        Runtime.put_env(:pulse, Evaluator, limits)

        conn =
          build_conn() |> put_req_header("x-scope-orgid", "batch-cost") |> get("/api/v1/query", query: query, time: "0")

        assert %{
                 "errorType" => "execution",
                 "error" => "query exceeded " <> _
               } = json_response(conn, 422)
      end

      # Selector alone fits; comparison bytes must also spend work, including
      # fallback labels when there are no requested names.
      for suffix <- ["", ~s(, "key")] do
        Runtime.put_env(:pulse, Evaluator, max_work: 20)
        assert {:ok, _} = Evaluator.query("batch_cost", "batch-cost", %{end_ts_ns: 0})

        assert {:error, :query_work_limit} =
                 Evaluator.query("sort_by_label(batch_cost#{suffix})", "batch-cost", %{end_ts_ns: 0})
      end

      Runtime.put_env(:pulse, Evaluator, max_samples: 2)
      batch = for ref <- ["a", "b"], do: {ref, "year(batch_cost)", %{end_ts_ns: 0}}

      assert {:error, :query_sample_limit} =
               Evaluator.query_batch(batch, "batch-cost", fn _, _ -> flunk("over-budget batch reached consumer") end)
    end
  end

  for adapter <- [Memory, S3] do
    @tag adapter: adapter, time_modifiers: true
    test "Pulse fixed windows preserve source timestamps, staleness and nanosecond edges through #{inspect(adapter)}" do
      samples =
        for {ns, value} <- [
              {1_000_000_000, 2.0},
              {1_000_000_001, 5.0},
              {1_000_000_002, 9.0},
              {1_000_000_003, :stale},
              {1_000_000_004, %NativeHistogram{schema: 0, count: 3.0, sum: 7.0}},
              {1_000_000_005, 11.0}
            ] do
          sample = %MetricSample{labels: %{"__name__" => "edge"}, timestamp_ns: ns}
          if is_struct(value, NativeHistogram), do: %{sample | histogram: value}, else: %{sample | value: value}
        end

      assert :ok = Storage.append(:metrics, "time-edges", samples)

      for {query, expected} <- [
            {"edge @ 1.000000002", ["edge 9"]},
            {"edge @ 1.000000003", []},
            {"edge @ 1.000000002 offset 0.000000001", ["edge 5"]},
            {"edge offset 0.000000001 @ 1.000000002", ["edge 5"]},
            {"histogram_count(edge @ 1.000000004)", ["{} 3"]},
            {"sum_over_time(edge[0.000000002] @ 1.000000002)", ["{} 14"]},
            {"sum_over_time(edge[0.000000001] @ 1.000000002)", ["{} 9"]},
            {"edge @ -1", []}
          ] do
        check(
          "eval range from 20s to 21s step 1s #{query}",
          Enum.map(expected, &(&1 <> " " <> List.last(String.split(&1)))),
          "time-edges"
        )
      end

      check("eval instant at 0 edge offset -1.000000001", ["edge 5"], "time-edges")
      check("eval instant at 0 edge @ 0 offset -1.000000001", ["edge 5"], "time-edges")
      check("eval instant at 0 edge @ -1 offset -2.000000001", ["edge 5"], "time-edges")
      check("eval range from 20s to 21s step 1s timestamp(abs(edge @ 1.000000002))", ["{} 20 21"], "time-edges")

      conn =
        build_conn()
        |> put_req_header("x-scope-orgid", "time-edges")
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post("/api/v1/query", URI.encode_query(query: "timestamp(edge @ 1.000000004)", time: "20"))

      assert %{"data" => %{"result" => [%{"metric" => %{}, "value" => [20.0, "1.000000004"]}]}} =
               json_response(conn, 200)

      request("/api/v1/query", %{query: "edge @ 1.000000002", time: "20"}, [], "other-tenant", "time isolation", 20, 1)

      assert {:ok, %{"data" => %{"result" => [%{"value" => [20.0, "9"]}]}}} =
               Evaluator.query("edge @ 1.000000002", "time-edges", %{end_ts_ns: 20_000_000_000, lookback_ns: 1})
    end

    @tag adapter: adapter, time_modifiers: true
    test "Pulse anchored parameters and nested start/end retain the outer clock through #{inspect(adapter)}" do
      samples =
        for {name, values} <- [{"linear", [1.0, 21.0, 41.0]}, {"smooth", [1.0, 3.0, 10.0]}],
            {value, i} <- Enum.with_index(values),
            do: %MetricSample{labels: %{"__name__" => name}, timestamp_ns: i * 10_000_000_000, value: value}

      base = 1_790_000_000_000_000_000

      clock =
        for {ns, value} <- [{1, 2.0}, {5, 11.0}, {6, 19.0}, {7, 23.0}],
            do: %MetricSample{labels: %{"__name__" => "clock"}, timestamp_ns: base + ns, value: value}

      assert :ok = Storage.append(:metrics, "time-context", samples ++ clock)

      # y = 2t + 1 is predicted from the frozen data at the current outer
      # time plus its varying horizon, not from the data-window endpoint.
      check(
        "eval range from 100s to 110s step 10s predict_linear(linear[21] @ 20, time()/10)",
        ["{} 221 243"],
        "time-context"
      )

      check(
        "eval range from 20s to 40s step 20s double_exponential_smoothing(smooth[21] @ 20, time()/100, 0.5)",
        ["{} 6 7"],
        "time-context"
      )

      check(
        "eval range from 20s to 40s step 20s quantile_over_time(time()/100, smooth[21] @ 20)",
        ["{} 1.8 2.6"],
        "time-context"
      )

      opts = %{start_ts_ns: base + 1, end_ts_ns: base + 6, step_ns: 4}

      for {query, labels, values} <- [
            {"clock @ start()", %{"__name__" => "clock"}, ["2", "2"]},
            {"clock @ end()", %{"__name__" => "clock"}, ["19", "19"]},
            {"clock @ end() offset -1e-9", %{"__name__" => "clock"}, ["23", "23"]},
            {"sum_over_time((clock @ end())[5e-9:1e-9] @ start())", %{}, ["95", "95"]}
          ] do
        assert {:ok, %{"data" => %{"result" => [row]}}} = Evaluator.query(query, "time-context", opts)
        assert row["metric"] == labels
        assert Enum.map(row["values"], &List.last/1) == values
      end
    end

    @tag adapter: adapter, time_modifiers: true
    test "Pulse time-modifier batches isolate anchors and retain shared budgets through #{inspect(adapter)}" do
      samples =
        for {ts, value} <- [{0, 2.0}, {10, 9.0}, {20, 19.0}],
            do: %MetricSample{labels: %{"__name__" => "clock"}, timestamp_ns: ts * 1_000_000_000, value: value}

      assert :ok = Storage.append(:metrics, "anchor-cost", samples)

      batch = [
        {"early", "clock @ end()", %{end_ts_ns: 0}},
        {"late", "clock @ start()", %{start_ts_ns: 10_000_000_000, end_ts_ns: 20_000_000_000, step_ns: 10_000_000_000}},
        {"instant", "clock @ start()", %{end_ts_ns: 20_000_000_000}}
      ]

      for queries <- [batch, Enum.reverse(batch)] do
        assert {:ok, results} = Evaluator.query_batch(queries, "anchor-cost", fn result, _ -> {:ok, result} end)
        assert [%{"value" => [+0.0, "2"]}] = results["early"]["data"]["result"]
        assert [%{"values" => [[10.0, "9"], [20.0, "9"]]}] = results["late"]["data"]["result"]
        assert [%{"value" => [20.0, "19"]}] = results["instant"]["data"]["result"]
      end

      for {limits, reason} <- [
            {[max_samples: 1], :query_sample_limit},
            {[max_work: 1], :query_work_limit},
            {[max_result_points: 1], :query_result_limit}
          ] do
        Runtime.put_env(:pulse, Evaluator, limits)

        assert {:error, ^reason} =
                 Evaluator.query("sum_over_time(clock[21] @ end())", "anchor-cost", %{
                   start_ts_ns: 20_000_000_000,
                   end_ts_ns: 21_000_000_000,
                   step_ns: 1_000_000_000
                 })
      end

      # Physical footer-row admission is specific to the native S3 adapter.
      if unquote(adapter) == S3 do
        Runtime.put_env(:pulse, Evaluator, max_scan_rows: 1)
        assert {:error, :query_scan_limit} = Evaluator.query("clock @ 20", "anchor-cost", %{end_ts_ns: 0})
      end

      Runtime.put_env(:pulse, Evaluator, max_samples: 2)
      source = {"a", "clock @ 10", %{end_ts_ns: 0}}
      assert {:ok, _} = Evaluator.query_batch([source], "anchor-cost", fn result, _ -> {:ok, result} end)

      assert {:error, :query_sample_limit} =
               Evaluator.query_batch([source, {"b", "clock @ 10", %{end_ts_ns: 0}}], "anchor-cost", fn _, _ ->
                 flunk("partial anchored batch")
               end)

      Runtime.put_env(:pulse, Evaluator, [])

      assert {:error, :query_work_limit} =
               Evaluator.query("sum_over_time(vector(1)[1:1e-9] @ 0)", "anchor-cost", %{end_ts_ns: 0})
    end

    @tag adapter: adapter, time_modifiers: true
    test "Pulse shifted timestamp bounds never wrap or clamp observations through #{inspect(adapter)}" do
      upper = %MetricSample{labels: %{"__name__" => "upper"}, timestamp_ns: 9_223_372_036_854_775_807, value: 7.0}
      lower = %MetricSample{labels: %{"__name__" => "lower"}, timestamp_ns: -9_223_372_036_854_775_808, value: 3.0}
      # Negative source-time storage is outside S3's existing object-key
      # contract. Memory can additionally distinguish clamping to int64_min.
      samples = if unquote(adapter) == Memory, do: [upper, lower], else: [upper]
      assert :ok = Storage.append(:metrics, "time-bounds", samples)

      for {query, expected} <- [
            {"upper @ 9223372036.854775807 offset -1e-9", ["upper 7"]},
            {"upper @ 9223372036.854775807 offset -301", []},
            {"lower @ -9223372036.854775808", if(unquote(adapter) == Memory, do: ["lower 3"], else: [])},
            {"lower @ -9223372036.854775808 offset 1e-9", []},
            {"sum_over_time(upper[1e-9] @ 9223372036.854775807 offset -1e-9)", []},
            {"sum_over_time(upper[2e-9] @ 9223372036.854775807 offset -1e-9)", ["{} 7"]}
          ],
          do: check("eval instant at 0 #{query}", expected, "time-bounds")

      assert {:error, :invalid_evaluation_time_or_step} =
               Evaluator.query("sum_over_time(vector(1)[1:1] @ 9223372036.854775807 offset -1)", "time-bounds", %{
                 end_ts_ns: 0
               })
    end

    @tag adapter: adapter, duration_expressions: true
    test "Pulse duration expressions retain outer clocks and nanosecond boundaries through #{inspect(adapter)}" do
      samples =
        for second <- 0..120,
            do: %MetricSample{labels: %{"__name__" => "clock"}, timestamp_ns: second * 1_000_000_000, value: second / 1}

      nanos =
        for {ns, value} <- [{1, 3.0}, {2, 7.0}, {3, 11.0}, {4, 19.0}],
            do: %MetricSample{labels: %{"__name__" => "nano"}, timestamp_ns: ns, value: value}

      histograms =
        for {second, sum} <- [{3, 7.0}, {6, 11.0}, {9, 19.0}],
            do: %MetricSample{
              labels: %{"__name__" => "hist"},
              timestamp_ns: second * 1_000_000_000,
              histogram: %NativeHistogram{schema: 0, count: 1.0, sum: sum}
            }

      assert :ok = Storage.append(:metrics, "duration", samples ++ nanos ++ histograms)

      for {query, values} <- [
            {"count_over_time(clock[range()])", "4 4"},
            {"count_over_time(clock[10s:step()])", "3 3"},
            {"sum_over_time(count_over_time(clock[step()+1ms])[range()+1s:1s])", "20 20"}
          ],
          do: check("eval range from 10s to 14s step 3s #{query}", ["{} " <> values], "duration")

      check("eval range from 10s to 14s step 3s clock offset range()", ["clock 6 9"], "duration")

      check(
        "eval range from 6s to 10s step 3s histogram_sum(last_over_time(hist[step()+1ms]))",
        ["{} 11 19"],
        "duration"
      )

      # Round the completed expression, not each numeric operand separately.
      for query <- ["sum_over_time(nano[0.6e-9+0.6e-9])", "sum_over_time(nano[1e-9/2])"] do
        request("/api/v1/query", %{query: query, time: "0.000000004"}, ["{} 19"], "duration", query, 4.0e-9, 1)
      end

      check("eval instant at 0 nano @ 3e-9 offset -(0.6e-9+0.6e-9)", ["nano 19"], "duration")
      check("eval instant at 10s sum_over_time(clock[min_of(2^1024,1s)])", ["{} 10"], "duration")
      check("eval instant at 0 1h30m+2.5", ["5402.5"], "duration")

      # Translation of Mimir TestInstantQueryDurationExpression at the pinned
      # revision: step() is zero for an instant query, not a range replay step.
      assert :ok = Storage.append(:metrics, "duration-ms", records("some_metric 0+1x300", 1_000_000))

      conn =
        build_conn()
        |> put_req_header("x-scope-orgid", "duration-ms")
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post("/api/v1/query", URI.encode_query(query: "count_over_time(some_metric[step()+1ms])", time: "0.005"))

      assert %{"data" => %{"result" => [%{"metric" => %{}, "value" => [0.005, "1"]}]}} = json_response(conn, 200)

      conn =
        build_conn()
        |> put_req_header("x-scope-orgid", "other-duration-tenant")
        |> get("/api/v1/query", query: "sum_over_time(clock[step()+1s])", time: "10")

      assert %{"data" => %{"result" => []}} = json_response(conn, 200)
    end

    @tag adapter: adapter, duration_expressions: true
    test "Pulse duration validation and budgets reject whole empty queries through #{inspect(adapter)}" do
      for duration <- ["1/0", "1%0", "min_of(1/0,1s)", "0^-1", "(-1)^0.5", "1y+1ms", "0", "-1", "step()", "range()"],
          query <- ["sum_over_time(missing[#{duration}+0])", "sum_over_time(missing[1:#{duration}+0])"] do
        assert {:error, :invalid_duration} = Evaluator.query(query, "duration-invalid", %{end_ts_ns: 10_000_000_000}),
               query
      end

      for duration <- ["1/0", "1%0", "(-1)^0.5", "1y*2", "-1y*2"] do
        query = "missing offset (#{duration})"
        assert {:error, :invalid_duration} = Evaluator.query(query, "duration-invalid", %{end_ts_ns: 0}), query
      end

      conn =
        build_conn()
        |> put_req_header("x-scope-orgid", "duration-invalid")
        |> get("/api/v1/query", query: "missing offset (1/0)", time: "0")

      assert %{"status" => "error", "errorType" => "bad_data"} = json_response(conn, 400)

      assert :ok = Storage.append(:metrics, "duration-cost", records("clock 0+1x20", 1_000_000_000))
      opts = %{start_ts_ns: 10_000_000_000, end_ts_ns: 14_000_000_000, step_ns: 3_000_000_000}

      for {limits, reason} <- [
            {[max_work: 1], :query_work_limit},
            {[max_samples: 1], :query_sample_limit},
            {[max_result_points: 1], :query_result_limit},
            {[max_materialized_samples: 1], :query_intermediate_limit}
          ] do
        Runtime.put_env(:pulse, Evaluator, limits)
        assert {:error, ^reason} = Evaluator.query("sum_over_time(clock[step()+1s:1s])", "duration-cost", opts)
      end

      Runtime.put_env(:pulse, Evaluator, [])

      assert {:error, :query_work_limit} =
               Evaluator.query("sum_over_time(vector(1)[1s:step()/10000000])", "duration-cost", opts)

      if unquote(adapter) == S3 do
        Runtime.put_env(:pulse, Evaluator, max_scan_rows: 1)
        assert {:error, :query_scan_limit} = Evaluator.query("clock offset (step()+1s)", "duration-cost", opts)
      end
    end

    @tag adapter: adapter, duration_expressions: true
    test "Pulse duration batches isolate outer clocks and share budgets through #{inspect(adapter)}" do
      assert :ok = Storage.append(:metrics, "duration-batch", records("clock 0+1x20", 1_000_000_000))
      range = %{start_ts_ns: 10_000_000_000, end_ts_ns: 14_000_000_000, step_ns: 3_000_000_000}

      batch = [
        {"range", "count_over_time(clock[step()+1ms])", range},
        {"instant", "count_over_time(clock[step()+1ms])", %{end_ts_ns: 10_000_000_000}},
        {"offset", "clock offset (range()+1s)", range}
      ]

      for queries <- [batch, Enum.reverse(batch)] do
        assert {:ok, results} = Evaluator.query_batch(queries, "duration-batch", fn result, _ -> {:ok, result} end)
        assert [%{"values" => [[10.0, "4"], [13.0, "4"]]}] = results["range"]["data"]["result"]
        assert [%{"value" => [10.0, "1"]}] = results["instant"]["data"]["result"]
        assert [%{"values" => [[10.0, "5"], [13.0, "8"]]}] = results["offset"]["data"]["result"]
      end

      Runtime.put_env(:pulse, Evaluator, max_result_points: 2)
      source = {"one", "count_over_time(clock[step()+1ms])", range}
      assert {:ok, _} = Evaluator.query_batch([source], "duration-batch", fn result, _ -> {:ok, result} end)

      assert {:error, :query_result_limit} =
               Evaluator.query_batch([source, {"two", elem(source, 1), range}], "duration-batch", fn _, _ ->
                 flunk("partial duration batch")
               end)
    end
  end

  # Only the syntax present in the selected upstream cases is supported.
  # Unknown commands, values and series forms fail rather than being skipped.
  defp series(line) do
    [_, metric, values] = Regex.run(~r/^([\w:]*(?:\{(?:[^{}"]|"(?:[^"\\]|\\.)*")*\})?)\s+(.+)$/, line)
    [_, name, attributes] = Regex.run(~r/^([\w:]*)(.*)$/, metric)

    labels =
      case attributes do
        "" ->
          []

        "{}" ->
          []

        _ ->
          matches = Regex.scan(~r/(?:\{|,\s*)(\w+|"(?:[^"\\]|\\.)*")=("(?:[^"\\]|\\.)*")(?=,|\})/, attributes)
          assert Enum.map_join(matches, &hd/1) <> "}" == attributes
          matches
      end
      |> Map.new(fn [_, key, quoted] ->
        key = if String.starts_with?(key, "\""), do: JSON.decode!(key), else: key
        {key, JSON.decode!(quoted)}
      end)

    labels = if name == "", do: labels, else: Map.put(labels, "__name__", name)

    {labels,
     Regex.scan(~r/\{\{[^}]*\}\}(?:\+\{\{[^}]*\}\})?(?:x\d+)?|\S+/, values)
     |> Enum.flat_map(fn [token] -> expand(token) end)}
  end

  defp expand("{{" <> _ = token) do
    case Regex.run(~r/^(\{\{[^}]*\}\})\+(\{\{[^}]*\}\})x(\d+)$/, token) do
      [_, first, increment, count] ->
        first = value(first)
        increment = value(increment)

        # Expand source inputs independently of Pulse's histogram arithmetic.
        # Like the upstream DSL producer, increments may use a finer schema or
        # disjoint sides/offsets, but cannot lower the preceding resolution.
        assert first.schema <= increment.schema
        assert first.custom_values == increment.custom_values
        assert first.zero_threshold == increment.zero_threshold
        assert first.counter_reset_hint == increment.counter_reset_hint

        {values, _} =
          Enum.map_reduce(0..String.to_integer(count), first, fn _, previous ->
            {positive_spans, positive_buckets} = ramp_buckets(previous, increment, :positive)
            {negative_spans, negative_buckets} = ramp_buckets(previous, increment, :negative)

            next = %{
              previous
              | count: previous.count + increment.count,
                sum: previous.sum + increment.sum,
                zero_count: previous.zero_count + increment.zero_count,
                positive_spans: positive_spans,
                positive_buckets: positive_buckets,
                negative_spans: negative_spans,
                negative_buckets: negative_buckets
            }

            {previous, next}
          end)

        values

      nil ->
        repeat(token)
    end
  end

  defp expand(token) do
    case Regex.run(~r/^(.+?)([+-][\d.]+)x(\d+)$/, token) do
      [_, first, increment, count] ->
        # Prometheus's producer adds each increment to the preceding value.
        # Multiplying by an index rounds decimal ramps differently at sf=1.
        {values, _} =
          Enum.map_reduce(0..String.to_integer(count), value(first), fn _, previous ->
            {previous, previous + value(increment)}
          end)

        values

      nil ->
        repeat(token)
    end
  end

  defp ramp_buckets(first, increment, side) do
    {spans_key, buckets_key} =
      if side == :positive, do: {:positive_spans, :positive_buckets}, else: {:negative_spans, :negative_buckets}

    buckets =
      Enum.reduce([first, increment], %{}, fn h, buckets ->
        {indices, _} =
          Enum.map_reduce(Map.fetch!(h, spans_key), -1, fn {offset, length}, previous ->
            start = previous + offset + 1
            {Enum.to_list(start..(start + length - 1)//1), start + length - 1}
          end)

        indices = List.flatten(indices)
        values = Map.fetch!(h, buckets_key)
        assert length(indices) == length(values)
        divisor = Integer.pow(2, h.schema - first.schema)

        Enum.reduce(Enum.zip(indices, values), buckets, fn {index, count}, buckets ->
          index = Integer.floor_div(index - 1, divisor) + 1
          Map.update(buckets, index, count, &(&1 + count))
        end)
      end)

    {chunks, _} =
      buckets
      |> Enum.sort()
      |> Enum.with_index()
      |> Enum.chunk_by(fn {{index, _}, ordinal} -> index - ordinal end)
      |> Enum.map_reduce(-1, fn chunk, previous ->
        {{first, _}, _} = hd(chunk)
        {{last, _}, _} = List.last(chunk)
        {{{first - previous - 1, length(chunk)}, Enum.map(chunk, fn {{_, count}, _} -> count end)}, last}
      end)

    {Enum.map(chunks, &elem(&1, 0)), Enum.flat_map(chunks, &elem(&1, 1))}
  end

  defp repeat(token) do
    case Regex.run(~r/^(.+)x(\d+)$/, token) do
      [_, "_", count] -> List.duplicate(:absent, String.to_integer(count))
      [_, sample, count] -> List.duplicate(value(sample), String.to_integer(count) + 1)
      nil -> [value(token)]
    end
  end

  defp value("_"), do: :absent
  defp value("stale"), do: :stale
  defp value(nan) when nan in ["NaN", "-NaN"], do: :nan
  defp value(infinity) when infinity in ["Inf", "+Inf", "inf", "+inf"], do: :infinity
  defp value("-Inf"), do: :negative_infinity

  defp value("{{" <> rest) do
    fields =
      rest
      |> String.trim_trailing("}}")
      |> String.split(~r/\s+(?![^\[]*\])/, trim: true)
      |> Map.new(&List.to_tuple(String.split(&1, ":")))

    assert Map.keys(fields) --
             [
               "schema",
               "sum",
               "count",
               "buckets",
               "n_buckets",
               "offset",
               "n_offset",
               "z_bucket_w",
               "z_bucket",
               "custom_values",
               "counter_reset_hint"
             ] == []

    buckets = histogram_array(fields, "buckets")
    negative = histogram_array(fields, "n_buckets")

    %NativeHistogram{
      schema: String.to_integer(Map.get(fields, "schema", "0")),
      sum: value(Map.get(fields, "sum", "0")),
      count: value(Map.get(fields, "count", "0")),
      zero_threshold: value(Map.get(fields, "z_bucket_w", "0")),
      zero_count: value(Map.get(fields, "z_bucket", "0")),
      counter_reset_hint:
        Map.fetch!(
          %{"unknown" => :unknown, "reset" => :yes, "not_reset" => :no, "gauge" => :gauge},
          Map.get(fields, "counter_reset_hint", "unknown")
        ),
      custom_values: histogram_array(fields, "custom_values"),
      positive_spans:
        if(buckets == [], do: [], else: [{String.to_integer(Map.get(fields, "offset", "0")), length(buckets)}]),
      positive_buckets: buckets,
      negative_spans:
        if(negative == [], do: [], else: [{String.to_integer(Map.get(fields, "n_offset", "0")), length(negative)}]),
      negative_buckets: negative
    }
  end

  defp value("." <> rest), do: value("0." <> rest)
  defp value("-." <> rest), do: value("-0." <> rest)
  defp value("+." <> rest), do: value("+0." <> rest)

  defp value(token) do
    {number, ""} = Float.parse(token)
    number
  end

  defp histogram_array(fields, key) do
    [_, values] = Regex.run(~r/^\[([^\]]*)\]$/, Map.get(fields, key, "[]"))
    values |> String.split() |> Enum.map(&value/1)
  end

  defp records(line, interval) do
    {labels, values} = series(line)
    # The pinned TSDB load path calls labels.WithoutEmpty before storing.
    # Keep expected output labels untouched in series/1.
    labels = Map.reject(labels, fn {_, value} -> value == "" end)

    for {value, index} <- Enum.with_index(values), value != :absent do
      sample = %MetricSample{labels: labels, timestamp_ns: index * interval}
      if is_struct(value, NativeHistogram), do: %{sample | histogram: value}, else: %{sample | value: value}
    end
  end

  # Upstream load_with_nhcb retains the classic samples and additionally loads
  # custom native histograms. Derive these inputs from cumulative source rows,
  # never from Pulse's production histogram conversion or arithmetic.
  defp classic_histograms(records) do
    records
    |> Enum.group_by(fn sample ->
      [_, name, _suffix] = Regex.run(~r/^(.*)_(bucket|sum|count)$/, sample.labels["__name__"])
      labels = sample.labels |> Map.delete("le") |> Map.put("__name__", name)
      {labels, sample.timestamp_ns}
    end)
    |> Enum.map(fn {{labels, timestamp}, samples} ->
      fields = Enum.reduce(samples, %{buckets: %{}}, &classic_histogram_field/2)

      buckets =
        Enum.sort(fields.buckets, fn {a, _}, {b, _} ->
          a != :infinity and (b == :infinity or a <= b)
        end)

      # The converter infers a missing count from the last cumulative bucket,
      # adding a missing +Inf boundary with that total. Duplicate boundaries
      # have identical counts in the selected source inputs.
      {last, cumulative} = List.last(buckets)
      count = Map.get(fields, :count, cumulative)
      assert count == cumulative
      buckets = if last == :infinity, do: buckets, else: buckets ++ [{:infinity, count}]

      {values, _} =
        Enum.map_reduce(buckets, 0.0, fn {_boundary, cumulative}, previous ->
          assert cumulative >= previous
          {cumulative - previous, cumulative}
        end)

      histogram = %NativeHistogram{
        schema: -53,
        count: count,
        sum: Map.get(fields, :sum, 0.0),
        custom_values: buckets |> Enum.drop(-1) |> Enum.map(&elem(&1, 0)),
        positive_spans: [{0, length(values)}],
        positive_buckets: values
      }

      %MetricSample{labels: labels, timestamp_ns: timestamp, histogram: histogram}
    end)
  end

  defp classic_histogram_field(sample, fields) do
    assert is_nil(sample.histogram)

    cond do
      String.ends_with?(sample.labels["__name__"], "_bucket") ->
        boundary = value(Map.fetch!(sample.labels, "le"))
        assert boundary != :nan

        buckets =
          Map.update(fields.buckets, boundary, sample.value, fn previous ->
            assert previous == sample.value
            previous
          end)

        %{fields | buckets: buckets}

      String.ends_with?(sample.labels["__name__"], "_count") ->
        Map.put(fields, :count, sample.value)

      String.ends_with?(sample.labels["__name__"], "_sum") ->
        Map.put(fields, :sum, sample.value)
    end
  end

  defp seconds(duration), do: nanoseconds(duration) / 1_000_000_000

  defp nanoseconds("0"), do: 0

  defp nanoseconds(duration) do
    parts = Regex.scan(~r/(\d+)(ms|s|m|h)/, duration)
    assert Enum.map_join(parts, &hd/1) == duration

    Enum.sum(
      for [_, count, unit] <- parts,
          do:
            String.to_integer(count) *
              Map.fetch!(
                %{"ms" => 1_000_000, "s" => 1_000_000_000, "m" => 60_000_000_000, "h" => 3_600_000_000_000},
                unit
              )
    )
  end

  defp check(command, expected, tenant) do
    [_, mode, query] =
      Regex.run(~r/^eval(?:_fail|_ordered)? (instant at \S+|range from \S+ to \S+ step \S+) (.+)$/, command)

    case String.split(mode) do
      ["instant", "at", time] ->
        time = seconds(time)
        request("/api/v1/query", %{query: query, time: "#{time}"}, expected, tenant, command, time, 1)

        # The upstream runner also checks instant cases as range queries.
        request(
          "/api/v1/query_range",
          %{query: query, start: "#{time}", end: "#{time}", step: "1s"},
          expected,
          tenant,
          command,
          time,
          1
        )

      ["range", "from", first, "to", last, "step", step] ->
        params = %{query: query, start: "#{seconds(first)}", end: "#{seconds(last)}", step: step}
        request("/api/v1/query_range", params, expected, tenant, command, seconds(first), seconds(step))
    end
  end

  defp request(path, params, expected, tenant, command, first, step) do
    conn = build_conn() |> put_req_header("x-scope-orgid", tenant) |> get(path, params)

    cond do
      path == "/api/v1/query_range" and
          Enum.any?(expected, &String.starts_with?(&1, ["expect string ", "expect range vector "])) ->
        assert_range_type_rejection(conn, expected)

      Enum.any?(expected, &String.starts_with?(&1, ["expect fail regex:", "expect fail msg:invalid label name"])) ->
        assert_parse_rejection(conn, expected)

      params.query in [
        ~s|label_replace(testmetric, "dst", "value-$1", "src", "(.*")|,
        ~S|label_replace(testmetric, "\xff", "", "src", "(.*)")|
      ] ->
        assert expected == ["expect fail"]

        message =
          Map.fetch!(
            %{
              ~s|label_replace(testmetric, "dst", "value-$1", "src", "(.*")| =>
                "invalid regular expression in label_replace(): (.*",
              ~S|label_replace(testmetric, "\xff", "", "src", "(.*)")| => "Invalid or unsupported query parameters."
            },
            params.query
          )

        assert %{
                 "status" => "error",
                 "errorType" => "bad_data",
                 "error" => message
               } == json_response(conn, 400)

      Enum.any?(expected, &String.starts_with?(&1, "expected_fail_message invalid ")) ->
        assert ["expected_fail_message " <> message] = expected

        {status, type} =
          Map.fetch!(
            %{
              "invalid smoothing factor. Expected: 0 < sf < 1, got: 0.000000" => {422, "execution"},
              "invalid trend factor. Expected: 0 < tf < 1, got: 0.000000" => {422, "execution"},
              "invalid regular expression in label_replace(): [.*" => {400, "bad_data"}
            },
            message
          )

        assert %{"status" => "error", "errorType" => type, "error" => message} == json_response(conn, status)

      String.starts_with?(command, "eval_fail") or
          expected in [
            ["expect fail"],
            ["expect fail msg:vector cannot contain metrics with the same labelset"],
            ["expected_fail_message multiple matches for labels: grouping labels must ensure unique matches"]
          ] ->
        matching_error = "Vector matching produced ambiguous or duplicate series."

        messages = %{
          [] => matching_error,
          ["expect fail"] => matching_error,
          ["expected_fail_message vector cannot contain metrics with the same labelset"] => matching_error,
          ["expect fail msg:vector cannot contain metrics with the same labelset"] => matching_error,
          ["expected_fail_regexp (P|p)arameter value is NaN( for topk)?"] => "parameter value is NaN for topk",
          [
            ~S"expected_fail_regexp (multiple matches for labels: many-to-one matching must be explicit|found duplicate series for the match group .* on the left (hand-)?side of the operation)"
          ] => matching_error,
          [
            ~S"expected_fail_regexp found duplicate series for the match group .* on the left (hand-)?side of the operation"
          ] => matching_error,
          ["expected_fail_message multiple matches for labels: grouping labels must ensure unique matches"] =>
            "multiple matches for labels: grouping labels must ensure unique matches"
        }

        assert Map.has_key?(messages, expected)

        # Pulse's HTTP diagnostic differs; assert its corresponding error exactly,
        # not just any 422 (which could conceal budgets or unrelated failures).
        assert %{
                 "status" => "error",
                 "errorType" => "execution",
                 "error" => Map.fetch!(messages, expected)
               } == json_response(conn, 422)

      true ->
        assert_success(conn, expected, path, command, first, step)
    end
  end

  defp assert_range_type_rejection(conn, expected) do
    message =
      if Enum.any?(expected, &String.starts_with?(&1, "expect range vector ")),
        do:
          "invalid parameter \"query\": query expression produces a range vector, but expression for range queries must produce an instant vector or scalar",
        else: "Invalid or unsupported query parameters."

    assert %{"status" => "error", "errorType" => "bad_data", "error" => message} == json_response(conn, 400)
  end

  defp assert_success(conn, expected, path, command, first, step) do
    assert conn.status == 200, "#{command}: #{conn.status} #{conn.resp_body}"
    assert %{"status" => "success", "data" => data} = response = json_response(conn, 200)
    ordered? = "expect ordered" in expected or String.starts_with?(command, "eval_ordered ")
    expected = List.delete(expected, "expect ordered")
    expected = assert_annotations(response, expected, command)

    if ordered? and path == "/api/v1/query" do
      assert Enum.map(data["result"], & &1["metric"]) == Enum.map(expected, &(series(&1) |> elem(0))), command
    end

    assert_query_data(data, expected, path, command, first, step)
  end

  defp assert_query_data(data, ["expect string " <> literal], "/api/v1/query", _command, first, _step) do
    expected = if String.starts_with?(literal, "`"), do: String.slice(literal, 1..-2//1), else: JSON.decode!(literal)
    assert data == %{"resultType" => "string", "result" => [first, expected]}
  end

  defp assert_query_data(data, ["expect range vector from " <> window | expected], "/api/v1/query", command, _, _) do
    [first, "to", last, "step", step] = String.split(window)
    assert data["resultType"] == "matrix"
    assert_samples(data["result"], expected, seconds(first), seconds(step), command)

    for sample <- data["result"],
        [timestamp, _] <- Map.get(sample, "values", []) ++ Map.get(sample, "histograms", []),
        do: assert(timestamp <= seconds(last), command)
  end

  defp assert_query_data(data, expected, path, command, first, step) do
    scalar? = match?([_], expected) and length(String.split(hd(expected))) == 1

    if scalar? and path == "/api/v1/query" do
      assert data["resultType"] == "scalar"
      assert [timestamp, actual] = data["result"]
      assert timestamp == first
      assert_value(actual, value(hd(expected)), command)
    else
      assert data["resultType"] == if(path == "/api/v1/query", do: "vector", else: "matrix")
      # A scalar instant case replayed as a one-step range has a matrix
      # envelope with empty labels, without changing its expected value.
      expected = if scalar?, do: ["{} " <> hd(expected)], else: expected
      assert_samples(data["result"], expected, first, step, command)
    end
  end

  defp assert_parse_rejection(conn, [expected]) do
    # These five upstream diagnostics map to Pulse's parse-time 400, not an
    # engine panic. Keep the original directives; reject any unknown mapping.
    supported =
      for owner <- ["source", "destination"],
          suffix <- ["", "�"],
          do: "expect fail regex:^invalid " <> owner <> ~S| label name in label_join\(\): | <> suffix <> "$"

    assert expected in [~S(expect fail msg:invalid label name "a\xc5z") | supported]

    assert %{
             "status" => "error",
             "errorType" => "bad_data",
             "error" => "Invalid or unsupported query parameters."
           } == json_response(conn, 400)
  end

  defp assert_annotations(response, expected, command) do
    {annotations, expected} =
      Enum.split_with(
        expected,
        &String.starts_with?(&1, ["expect info", "expect no_info", "expect warn", "expect no_warn"])
      )

    {patterns, annotations} = Enum.split_with(annotations, &String.starts_with?(&1, "expect info regex: "))
    assert_info_patterns(response, patterns, command)

    {messages, annotations} = Enum.split_with(annotations, &String.starts_with?(&1, "expect warn msg: "))

    if messages != [] do
      warnings =
        Enum.map(messages, &Regex.replace(~r/ \(\d+:\d+\)$/, String.replace_prefix(&1, "expect warn msg: ", ""), ""))

      assert Enum.sort(warnings) == Enum.sort(Map.get(response, "warnings", [])), command
    end

    for annotation <- annotations do
      case annotation do
        "expect info" ->
          assert Map.get(response, "infos", []) != [], command

        "expect info msg: " <> message ->
          assert [Regex.replace(~r/ \(\d+:\d+\)$/, message, "")] == Map.get(response, "infos", []), command

        "expect no_info" ->
          assert Map.get(response, "infos", []) == [], command

        "expect warn" ->
          assert Map.get(response, "warnings", []) != [], command

        "expect no_warn" ->
          assert Map.get(response, "warnings", []) == [], command

        "expect warn regex: " <> pattern ->
          # Only the source-location suffix is adapted, never the diagnostic.
          pattern = String.replace_suffix(pattern, ~S| \([0-9]+:[0-9]+\)|, "")
          assert [warning] = Map.get(response, "warnings", []), command
          assert Regex.match?(Regex.compile!("\\A(?:" <> pattern <> ")\\z"), warning), command
      end
    end

    expected
  end

  defp assert_info_patterns(_response, [], _command), do: :ok

  defp assert_info_patterns(response, expected, command) do
    patterns =
      Enum.map(expected, fn pattern ->
        pattern = String.replace_prefix(pattern, "expect info regex: ", "")
        # Like warning directives, omit only the upstream AST position.
        pattern = Regex.replace(~r/ \\\(\d+:\d+\\\)$/, pattern, "")
        Regex.compile!(pattern)
      end)

    infos = Map.get(response, "infos", [])

    for pattern <- patterns, do: assert(Enum.any?(infos, &Regex.match?(pattern, &1)), command)
    for info <- infos, do: assert(Enum.any?(patterns, &Regex.match?(&1, info)), command)
  end

  defp assert_samples(actual, expected, first, step, command) do
    expected =
      Map.new(expected, fn line ->
        {labels, values} = series(line)
        points = for {v, i} <- Enum.with_index(values), v != :absent, do: {first + i * step, v}
        {labels, points}
      end)

    assert length(actual) == map_size(expected), command
    assert MapSet.new(actual, & &1["metric"]) == MapSet.new(Map.keys(expected)), command

    for sample <- actual do
      points = Map.fetch!(expected, sample["metric"])
      floats = sample["values"] || if(sample["value"], do: [sample["value"]], else: [])
      histograms = sample["histograms"] || if(sample["histogram"], do: [sample["histogram"]], else: [])
      values = Enum.sort_by(floats ++ histograms, &hd/1)
      assert length(values) == length(points), command

      for {[timestamp, actual], {expected_timestamp, expected}} <- Enum.zip(values, points) do
        assert timestamp == expected_timestamp, command
        assert_value(actual, expected, command)
      end
    end
  end

  defp assert_value(actual, %NativeHistogram{} = expected, command) when is_map(actual) do
    assert Map.keys(actual) -- ["count", "sum", "buckets"] == [], command
    assert_number(value(Map.fetch!(actual, "count")), expected.count, command)
    assert_number(value(Map.fetch!(actual, "sum")), expected.sum, command)

    # Derive selected exponential/custom bounds independently, never through
    # Pulse's formatter. Reject layouts this fixture adapter cannot assert.
    assert expected.schema in [-53, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8], command
    assert length(expected.positive_spans) <= 1 and length(expected.negative_spans) <= 1, command

    # Upstream's AllBucketIterator emits only strictly positive zero counts,
    # even though negative/NaN count and sum fields remain in the HTTP result.
    zero =
      if expected.zero_count == :infinity or (is_number(expected.zero_count) and expected.zero_count > 0),
        do: [[3, -expected.zero_threshold, expected.zero_threshold, expected.zero_count]],
        else: []

    expected_buckets = Enum.reverse(expected_side(expected, :negative), zero ++ expected_side(expected, :positive))

    buckets = Map.get(actual, "buckets", [])
    assert length(buckets) == length(expected_buckets), command

    for {[rule, lower, upper, count], [expected_rule, lo, hi, n]} <- Enum.zip(buckets, expected_buckets) do
      assert rule == expected_rule, command
      assert_number(value(lower), lo, command)
      assert_number(value(upper), hi, command)
      assert_number(value(count), n, command)
    end
  end

  defp assert_value(actual, expected, command) when is_binary(actual) and not is_struct(expected),
    do: assert_number(value(actual), expected, command)

  defp expected_side(histogram, side) do
    {spans, buckets} =
      if side == :positive,
        do: {histogram.positive_spans, histogram.positive_buckets},
        else: {histogram.negative_spans, histogram.negative_buckets}

    offset = if spans == [], do: 0, else: elem(hd(spans), 0)

    for {count, index} <- Enum.with_index(buckets, offset), count != 0 do
      case {side, expected_bucket(histogram, index, count)} do
        {:positive, [rule, lower, upper, count]} when histogram.schema == -53 -> [rule, lower, upper, count]
        {:positive, [rule, lower, upper, count]} -> [rule, max(lower, histogram.zero_threshold), upper, count]
        {:negative, [_, lower, upper, count]} -> [1, -upper, min(-lower, -histogram.zero_threshold), count]
      end
    end
  end

  defp expected_bucket(%{schema: -53, custom_values: bounds}, index, count) do
    lower = if index == 0, do: :negative_infinity, else: Enum.at(bounds, index - 1)
    upper = Enum.at(bounds, index, :infinity)
    [if(index == 0, do: 3, else: 0), lower, upper, count]
  end

  defp expected_bucket(histogram, index, count) do
    scale = :math.pow(2.0, -histogram.schema)
    [0, :math.pow(2.0, (index - 1) * scale), :math.pow(2.0, index * scale), count]
  end

  defp assert_number(actual, expected, command) when is_number(actual) and is_number(expected) do
    # Upstream uses almost.Equal with relative epsilon 1e-6, treating signed
    # zeros as equal. The separate IEEE corpus checks zero signs exactly.
    assert actual == expected or abs(actual - expected) < 1.0e-6 * (abs(actual) + abs(expected)), command
  end

  defp assert_number(actual, expected, command), do: assert(actual == expected, command)
end
