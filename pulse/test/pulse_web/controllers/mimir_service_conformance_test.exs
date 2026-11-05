# SPDX-License-Identifier: AGPL-3.0-only
# Adapted from grafana/mimir integration tests at dd039cdd4ba466adb5d28280bf1b8a374a98432e.
# querier_test.go, query_frontend_test.go and api_endpoints_test.go also carry:
# Provenance-includes-license: Apache-2.0
# Provenance-includes-copyright: The Cortex Authors.
# Histogram generator geometry also adapted from vendored Prometheus tsdbutil:
# Copyright The Prometheus Authors, licensed under Apache-2.0.
# Source selections, adaptations and licenses: test/fixtures/promql/mimir/services/README.md.
defmodule PulseWeb.MimirServiceConformanceTest do
  use PulseWeb.ConnCase, async: true

  import Bitwise

  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Test.CompactionStore

  # Replace upstream time.Now().Round(time.Second) with a fixed queryStart.
  @start 1_700_000_000
  @tenant "user-1"

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

    server = start_supervised!({Bandit, plug: {CompactionStore, agent: store}, ip: {127, 0, 0, 1}, port: 0})
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    Runtime.put_env(:pulse, Storage, adapter: S3)

    Runtime.put_env(:pulse, S3, %{
      bucket: "pulse",
      endpoint: "http://127.0.0.1:#{port}",
      region: "us-east-1",
      access_key_id: "mimir-#{System.unique_integer([:positive])}",
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0
    })

    start_supervised!(ManifestSupervision)
    %{store: store}
  end

  @tag :regex_hex_batch
  test "Pulse controls: braced hex repetition matches Go through remote write and Parquet", %{store: store} do
    inputs = ["a", "aa", "aaa", "aab", "aabb", "éé", "Éé", "Ā"]
    samples = inputs |> Enum.with_index(1) |> Map.new()

    bytes =
      Enum.map_join(inputs, fn input ->
        field(1, series([{"__name__", "regex_hex"}, {"x", input}], [{@start, samples[input]}]))
      end)

    assert post_write(bytes).status == 204

    controls =
      "test/fixtures/regex/go-controls.json"
      |> File.read!()
      |> Pulse.JSON.decode!()
      |> Enum.filter(
        &(&1["value"] in inputs and String.contains?(&1["pattern"], "\\x{") and String.ends_with?(&1["pattern"], "$"))
      )
      |> Enum.group_by(& &1["pattern"])

    for {pattern, rows} <- controls, {operator, matches?} <- [{"=~", true}, {"!~", false}] do
      query = "regex_hex{x" <> operator <> Pulse.JSON.encode!(pattern) <> "}"

      expected =
        for row <- rows, row["match"] == matches? do
          input = row["value"]
          %{"metric" => %{"__name__" => "regex_hex", "x" => input}, "value" => [@start, to_string(samples[input])]}
        end

      assert %{"resultType" => "vector", "result" => actual} = data("/api/v1/query", query: query, time: @start)
      assert Enum.sort(actual) == Enum.sort(expected), query

      response =
        conn()
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post("/api/v1/query", URI.encode_query(query: query, time: @start))

      assert %{"data" => %{"result" => actual}} = json_response(response, 200)
      assert Enum.sort(actual) == Enum.sort(expected), query
    end

    # Independently checked with Go 1.25.10 regexp.Compile; these are not lazy
    # forms. Only the first question mark after a repetition is its lazy suffix.
    for pattern <- ["a???", "a{2}??", ~S"\x{61}{2}??", ~S"\x{61}???", ~S"\x{61}+??", ~S"\x{61}*??"] do
      params = [query: "regex_hex{x=~" <> Pulse.JSON.encode!(pattern) <> "}", time: @start]
      assert %{"errorType" => "bad_data"} = conn() |> get("/api/v1/query", params) |> json_response(400)

      response =
        conn()
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post("/api/v1/query", URI.encode_query(params))

      assert %{"errorType" => "bad_data"} = json_response(response, 400)
    end

    assert_parquet(store)
  end

  @tag :regex_literals_batch
  test "Go quoted and octal regex literals match whole labels through Parquet", %{store: store} do
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

    samples = inputs |> Enum.with_index(1) |> Map.new()

    bytes =
      Enum.map_join(inputs, fn input ->
        exemplar = field(1, field(1, "trace_id") <> field(2, "literal")) <> double(2, 123) <> uint(3, @start * 1000)

        field(
          1,
          series([{"__name__", "regex_literals"}, {"x", input}], [{@start, samples[input]}]) <> field(3, exemplar)
        )
      end)

    assert post_write(bytes).status == 204

    controls =
      "test/fixtures/regex/go-controls.json"
      |> File.read!()
      |> Pulse.JSON.decode!()
      |> Enum.filter(&(Map.has_key?(&1, "label_match") and &1["value"] in inputs))
      |> Enum.group_by(& &1["pattern"])

    assert map_size(controls) == 30

    for {pattern, rows} <- controls, {operator, matches?} <- [{"=~", true}, {"!~", false}] do
      query = "regex_literals{x" <> operator <> Pulse.JSON.encode!(pattern) <> "}"

      expected =
        for row <- rows, row["label_match"] == matches? do
          input = row["value"]
          %{"metric" => %{"__name__" => "regex_literals", "x" => input}, "value" => [@start, to_string(samples[input])]}
        end

      assert %{"resultType" => "vector", "result" => actual} = data("/api/v1/query", query: query, time: @start)
      assert Enum.sort(actual) == Enum.sort(expected), query

      response =
        conn()
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post("/api/v1/query", URI.encode_query(query: query, time: @start))

      assert %{"data" => %{"result" => actual}} = json_response(response, 200)
      assert Enum.sort(actual) == Enum.sort(expected), query
    end

    assert %{"result" => [%{"metric" => %{"__name__" => "regex_literals", "x" => "a.b", "out" => "hit"}}]} =
             data("/api/v1/query",
               query: ~S'label_replace(regex_literals{x="a.b"}, "out", "hit", "x", "\\Qa.b")',
               time: @start
             )

    selector = ~S'regex_literals{x=~"\\Qa.b"}'
    labels = %{"__name__" => "regex_literals", "x" => "a.b"}
    assert discovery("/api/v1/series", [start: @start, end: @start + 1], [selector]) == [labels]
    assert discovery("/api/v1/label/x/values", [start: @start, end: @start + 1], [selector]) == ["a.b"]

    assert data("/api/v1/query_exemplars", query: selector, start: @start, end: @start + 1) == [
             %{
               "seriesLabels" => labels,
               "exemplars" => [%{"labels" => %{"trace_id" => "literal"}, "value" => "123", "timestamp" => @start}]
             }
           ]

    assert_parquet(store)
  end

  # Replays the Go regex corpus; under CI concurrency its native calls queue
  # behind other tests and can exceed ExUnit's 60 s default.
  @tag :regex_admission_batch
  @tag timeout: 300_000
  test "Go repetition classes and raw headers agree through remote write and Parquet", %{store: store} do
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

    samples = inputs |> Enum.with_index(1) |> Map.new()

    bytes =
      Enum.map_join(inputs, fn input ->
        field(1, series([{"__name__", "regex_admission"}, {"x", input}], [{@start, samples[input]}]))
      end)

    assert post_write(bytes).status == 204

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

    for row <- cases, {operator, matches?} <- [{"=~", true}, {"!~", false}] do
      query = "regex_admission{x" <> operator <> Pulse.JSON.encode!(row["pattern"]) <> "}"
      params = [query: query, time: @start]
      before_reads = Agent.get(store, &{&1.reads, &1.lists, &1.requests})
      status = if row["valid"], do: 200, else: 400
      result = conn() |> get("/api/v1/query", params) |> json_response(status)

      form =
        conn()
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post("/api/v1/query", URI.encode_query(params))
        |> json_response(status)

      assert form == result

      if row["valid"] do
        expected =
          for value <- row["values"],
              input = String.duplicate(value["text"], value["repeat"]),
              input in inputs and value["label_match"] == matches?,
              do: %{
                "metric" => %{"__name__" => "regex_admission", "x" => input},
                "value" => [@start, to_string(samples[input])]
              }

        assert Enum.sort(result["data"]["result"]) == Enum.sort(expected), query
      else
        assert Agent.get(store, &{&1.reads, &1.lists, &1.requests}) == before_reads
      end
    end

    assert_parquet(store)
  end

  @tag :regex_properties_batch
  test "Unicode properties and scalar complements match upstream through remote write and Parquet", %{store: store} do
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

    samples = inputs |> Enum.with_index(1) |> Map.new()

    bytes =
      Enum.map_join(inputs, fn input ->
        field(1, series([{"__name__", "regex_properties"}, {"x", input}], [{@start, samples[input]}]))
      end)

    assert post_write(bytes).status == 204

    for path <- ["unicode-property-controls.json", "scalar-complement-controls.json"],
        row <- ("test/fixtures/regex/" <> path) |> File.read!() |> Pulse.JSON.decode!() |> Map.fetch!("cases"),
        Map.get(row, "http", true),
        {operator, matches?} <- [{"=~", true}, {"!~", false}] do
      query = "regex_properties{x" <> operator <> Pulse.JSON.encode!(row["pattern"]) <> "}"
      params = [query: query, time: @start]
      before_reads = Agent.get(store, &{&1.reads, &1.lists, &1.requests})
      status = if row["valid"], do: 200, else: 400
      response = conn() |> get("/api/v1/query", params) |> json_response(status)

      assert conn()
             |> put_req_header("content-type", "application/x-www-form-urlencoded")
             |> post("/api/v1/query", URI.encode_query(params))
             |> json_response(status) == response

      if row["valid"] do
        expected =
          for value <- row["values"], value["text"] in inputs, value["label_match"] == matches? do
            %{
              "metric" => %{"__name__" => "regex_properties", "x" => value["text"]},
              "value" => [@start, to_string(samples[value["text"]])]
            }
          end

        assert Enum.sort(response["data"]["result"]) == Enum.sort(expected), query
      else
        assert Agent.get(store, &{&1.reads, &1.lists, &1.requests}) == before_reads
      end
    end

    assert_parquet(store)
  end

  @tag :regex_selector_names_batch
  test "label_replace expands numeric and repeated aliases like Go through Parquet", %{store: store} do
    inputs = ["x", "y", "xy", "hi", "bye", "aba", "xx"]
    samples = inputs |> Enum.with_index(1) |> Map.new()

    bytes =
      Enum.map_join(inputs, fn input ->
        field(1, series([{"__name__", "regex_names"}, {"x", input}, {"out", "existing"}], [{@start, samples[input]}]))
      end)

    assert post_write(bytes).status == 204
    fixture = "test/fixtures/regex/selector-name-controls.json" |> File.read!() |> Pulse.JSON.decode!()

    for row <- fixture["cases"], row["valid"] do
      query =
        ~s(label_replace(regex_names, "out", #{Pulse.JSON.encode!(fixture["replacement"])}, "x", ) <>
          Pulse.JSON.encode!(row["pattern"]) <> ")"

      expected =
        for value <- row["values"], value["text"] in inputs do
          %{
            "metric" => %{"__name__" => "regex_names", "x" => value["text"], "out" => value["expanded"] || "existing"},
            "value" => [@start, to_string(samples[value["text"]])]
          }
        end

      params = [query: query, time: @start]
      response = conn() |> get("/api/v1/query", params) |> json_response(200)
      assert Enum.sort(response["data"]["result"]) == Enum.sort(expected), query

      assert conn()
             |> put_req_header("content-type", "application/x-www-form-urlencoded")
             |> post("/api/v1/query", URI.encode_query(params))
             |> json_response(200) == response
    end

    assert_parquet(store)
  end

  # integration/api_endpoints_test.go: TestFormatQueryAPIEndpoint.
  test "TestFormatQueryAPIEndpoint", %{store: store} do
    assert data("/api/v1/format_query", query: "count(up)by(foo)") == "count by (foo) (up)"
    assert Agent.get(store, & &1.requests) == []
  end

  # integration/query_frontend_test.go: testQueryFrontend, user-0's scalar and
  # range-vector results. Freeze the source generator's random float to 0.5.
  @tag :result_types_batch
  test "testQueryFrontend / scalar and range-vector results", %{store: store} do
    bytes = field(1, series([{"__name__", "series_1"}], [{@start, 0.5}]))
    assert post_write(bytes, :v1, [{"x-scope-orgid", "user-0"}]).status == 204

    assert data("/api/v1/query", [query: "scalar(series_1)", time: @start], "user-0") ==
             %{"resultType" => "scalar", "result" => [@start, "0.5"]}

    assert data("/api/v1/query", [query: "series_1[5m]", time: @start], "user-0") ==
             %{
               "resultType" => "matrix",
               "result" => [%{"metric" => %{"__name__" => "series_1"}, "values" => [[@start, "0.5"]]}]
             }

    assert_parquet(store)
  end

  @tag :result_types_batch
  @tag :range_result_diagnostics
  test "Pulse rejects range and string results in range requests before storage", %{store: store} do
    for query <- [
          ~s("text"),
          "series_1[5m]",
          "(series_1[5m])",
          "series_1[5m:]",
          "series_1[5m] @ 1700000000",
          "(sum(rate(series_1[1m])))[5m:10s]"
        ],
        finish <- [@start, @start + 60],
        method <- [:get, :post] do
      params = [query: query, start: @start, end: finish, step: "1m"]

      response =
        if method == :get,
          do: get(conn(), "/api/v1/query_range", params),
          else:
            conn()
            |> put_req_header("content-type", "application/x-www-form-urlencoded")
            |> post("/api/v1/query_range", URI.encode_query(params))

      expected =
        if query == ~s("text"),
          do: "Invalid or unsupported query parameters.",
          else:
            "invalid parameter \"query\": query expression produces a range vector, but expression for range queries must produce an instant vector or scalar"

      assert %{"status" => "error", "errorType" => "bad_data", "error" => expected} ==
               json_response(response, 400)
    end

    assert Agent.get(store, & &1.requests) == []
  end

  # integration/distributor_test.go: testDistributorWithCachingUnmarshalData.
  # These are the exact first four table entries, including RW2 symbol order.
  @distributor [
    {"simple counter", "foobarC_total", 1, "counter", "some helpC", "someunitC",
     ["", "__name__", "foobarC_total", "some helpC", "someunitC"], [{[{"__name__", "foobarC_total"}], 100}], 3, 4},
    {"simple gauge", "foobarG", 2, "gauge", "some helpG", "someunitG",
     ["", "__name__", "foobarG", "some helpG", "someunitG"], [{[{"__name__", "foobarG"}], 100}], 3, 4},
    {"simple histogram", "foobarH", 3, "histogram", "some helpH", "someunitH",
     ["", "__name__", "foobarH_bucket", "le", "0.1", "some helpH", "someunitH", "+Inf", "foobarH_count", "foobarH_sum"],
     [
       {[{"__name__", "foobarH_bucket"}, {"le", "0.1"}], 100},
       {[{"__name__", "foobarH_bucket"}, {"le", "+Inf"}], 200},
       {[{"__name__", "foobarH_count"}], 200},
       {[{"__name__", "foobarH_sum"}], 1000}
     ], 5, 6},
    {"simple summary", "foobarS", 5, "summary", "some helpS", "someunitS",
     ["", "__name__", "foobarS", "quantile", "0.5", "some helpS", "someunitS", "foobarS_count", "foobarS_sum"],
     [
       {[{"__name__", "foobarS"}, {"quantile", "0.5"}], 100},
       {[{"__name__", "foobarS_count"}], 200},
       {[{"__name__", "foobarS_sum"}], 1000}
     ], 5, 6}
  ]

  for {name, family, type, type_name, help, unit, symbols, rows, help_ref, unit_ref} <- @distributor,
      version <- [:v1, :v2] do
    @tag rw_version: version
    test "TestDistributor / #{name} / #{version}", %{store: store, rw_version: version} do
      rows = unquote(Macro.escape(rows))

      bytes =
        case version do
          :v1 ->
            series = Enum.map_join(rows, fn {labels, value} -> field(1, series(labels, [{@start, value}])) end)

            metadata =
              uint(1, unquote(type)) <> field(2, unquote(family)) <> field(4, unquote(help)) <> field(5, unquote(unit))

            series <> field(3, metadata)

          :v2 ->
            symbols = unquote(symbols)
            refs = symbols |> Enum.with_index() |> Map.new()
            metadata = uint(1, unquote(type)) <> uint(3, unquote(help_ref)) <> uint(4, unquote(unit_ref))

            Enum.map_join(symbols, &field(4, &1)) <>
              Enum.map_join(rows, fn {labels, value} ->
                label_refs = Enum.map_join(labels, fn {key, value} -> varint(refs[key]) <> varint(refs[value]) end)
                field(5, field(1, label_refs) <> field(2, sample(@start, value)) <> field(5, metadata))
              end)
        end

      response = post_write(bytes, version)
      assert response.status == 204

      for {header, count} <- [{"samples", length(rows)}, {"histograms", 0}, {"exemplars", 0}] do
        assert get_resp_header(response, "x-prometheus-remote-write-#{header}-written") ==
                 if(version == :v2, do: [to_string(count)], else: [])
      end

      for {query, selected} <- Enum.group_by(rows, fn {labels, _} -> labels |> Map.new() |> Map.fetch!("__name__") end) do
        expected =
          Enum.map(selected, fn {labels, value} ->
            %{"metric" => Map.new(labels), "values" => [[@start, to_string(value)]]}
          end)

        result = data("/api/v1/query_range", query: query, start: @start, end: @start + 3600, step: "5m")
        assert result["resultType"] == "matrix"
        assert Enum.sort(result["result"]) == Enum.sort(expected)
      end

      assert data("/api/v1/metadata", metric: unquote(family)) == %{
               unquote(family) => [%{"type" => unquote(type_name), "help" => unquote(help), "unit" => unquote(unit)}]
             }

      # Controls beyond upstream: tenant isolation and actual durable artifacts.
      assert data("/api/v1/metadata", [metric: unquote(family)], "other") == %{}
      assert_parquet(store)
      assert Agent.get(store, &Map.has_key?(&1.objects, "tenants/#{@tenant}/v4/metadata/metrics.json"))
    end
  end

  # integration/distributor_test.go: exact label-normalization table inputs,
  # including the repeated empty string at symbol index 4 in the first case.
  for {name, metric, labels, symbols, refs, expected_labels} <- [
        {"drop empty labels", "series_with_empty_label", [{"__name__", "series_with_empty_label"}, {"empty", ""}],
         ["", "__name__", "series_with_empty_label", "empty", ""], [1, 2, 3, 4],
         %{"__name__" => "series_with_empty_label"}},
        {"wrong labels order", "series_with_wrong_labels_order",
         [{"__name__", "series_with_wrong_labels_order"}, {"zzz", "1"}, {"aaa", "2"}],
         ["", "__name__", "series_with_wrong_labels_order", "zzz", "1", "aaa", "2"], [1, 2, 3, 4, 5, 6],
         %{"__name__" => "series_with_wrong_labels_order", "aaa" => "2", "zzz" => "1"}}
      ],
      version <- [:v1, :v2] do
    @tag rw_version: version
    test "TestDistributor / #{name} / #{version}", %{store: store, rw_version: version} do
      bytes =
        case version do
          :v1 ->
            field(1, series(unquote(Macro.escape(labels)), [{@start, 100}]))

          :v2 ->
            Enum.map_join(unquote(symbols), &field(4, &1)) <>
              field(5, field(1, Enum.map_join(unquote(refs), &varint/1)) <> field(2, sample(@start, 100)))
        end

      response = post_write(bytes, version)
      assert response.status == 204
      assert_written(response, version, 1, 0, 0)

      assert data("/api/v1/query_range", query: unquote(metric), start: @start, end: @start + 3600, step: "5m") == %{
               "resultType" => "matrix",
               "result" => [%{"metric" => unquote(Macro.escape(expected_labels)), "values" => [[@start, "100"]]}]
             }

      assert_parquet(store)
    end
  end

  # TestDistributor_NameValidation: only the UTF8Validation scheme, which is
  # already Pulse's receiver contract. The legacy-validation policy is not ported.
  # Unlike the earlier distributor table, the single sample is at queryEnd.
  for {name, metric, labels, symbols, refs, query, metadata?} <- [
        {"legacy metric name", "legacy_metricC", [{"__name__", "legacy_metricC"}, {"label_name", "test"}],
         ["", "__name__", "legacy_metricC", "label_name", "test"], [1, 2, 3, 4], "legacy_metricC", false},
        {"utf8 metric name", "utf_metric😀C", [{"__name__", "utf_metric😀C"}],
         ["", "__name__", "utf_metric😀C", "some helpC", "someunitC"], [1, 2], ~s({"utf_metric😀C"}), true},
        {"utf8 label name", "legacy_metricC_total_2", [{"__name__", "legacy_metricC_total_2"}, {"utf8_label😀", "test"}],
         ["", "__name__", "legacy_metricC_total_2", "utf8_label😀", "test"], [1, 2, 3, 4], "legacy_metricC_total_2",
         false}
      ],
      version <- [:v1, :v2] do
    @tag rw_version: version
    test "TestDistributor_NameValidation / utf8 / #{name} / #{version}", %{store: store, rw_version: version} do
      metric = unquote(metric)
      labels = unquote(Macro.escape(labels))
      query_end = @start + 3600

      bytes =
        case version do
          :v1 ->
            metadata =
              if unquote(metadata?),
                do: field(3, uint(1, 1) <> field(2, metric) <> field(4, "some helpC") <> field(5, "someunitC")),
                else: ""

            field(1, series(labels, [{query_end, 100}])) <> metadata

          :v2 ->
            metadata = if unquote(metadata?), do: field(5, uint(1, 1) <> uint(3, 3) <> uint(4, 4)), else: ""

            Enum.map_join(unquote(symbols), &field(4, &1)) <>
              field(
                5,
                field(1, Enum.map_join(unquote(refs), &varint/1)) <> field(2, sample(query_end, 100)) <> metadata
              )
        end

      response = post_write(bytes, version)
      assert response.status == 204
      assert_written(response, version, 1, 0, 0)

      assert data("/api/v1/query_range", query: unquote(query), start: @start, end: query_end, step: "5m") == %{
               "resultType" => "matrix",
               "result" => [%{"metric" => Map.new(labels), "values" => [[query_end, "100"]]}]
             }

      # Metadata is an upstream input; the public read is an extra Pulse control.
      expected_metadata =
        if unquote(metadata?),
          do: %{metric => [%{"type" => "counter", "help" => "some helpC", "unit" => "someunitC"}]},
          else: %{}

      assert data("/api/v1/metadata", metric: metric) == expected_metadata
      assert_parquet(store)
    end
  end

  for version <- [:v1, :v2] do
    @tag rw_version: version
    test "Pulse UTF8 selector controls / #{version}", %{store: store, rw_version: version} do
      labels = [{"__name__", "utf_metric😀C"}, {"label\"😀", "test"}]
      assert post_write(label_request(version, [%{labels: labels, samples: [{@start, 100}]}]), version).status == 204

      for query <- [
            ~S({"utf_metric\U0001f600C","label\"😀"="test"}),
            ~S({ "label\"😀" =~ "te.*", "utf_metric😀C", }),
            ~S({"utf_metric😀C","label\"😀"!="other"}),
            ~S({"utf_metric😀C","label\"😀"!~"other.*"}),
            ~S({"__name__"="utf_metric😀C","label\"😀"="test"})
          ] do
        assert data("/api/v1/query", query: query, time: @start) == %{
                 "resultType" => "vector",
                 "result" => [%{"metric" => Map.new(labels), "value" => [@start, "100"]}]
               }
      end

      assert data("/api/v1/query", query: ~S({"utf_metric😀C","label\"😀"="other"}), time: @start) == %{
               "resultType" => "vector",
               "result" => []
             }

      for query <- [
            ~S({"utf_metric😀C","other"}),
            ~S(legacy_metricC{"utf_metric😀C"}),
            ~S({"","label😀"="test"}),
            ~S({""="test"}),
            ~S({"utf_metric😀C","label😀"=}),
            ~S({"utf_metric😀C","label\q"="test"}),
            ~S({"utf_metric😀C"),
            "utf_metric😀C"
          ] do
        response = conn() |> get("/api/v1/query", %{query: query, time: @start})
        assert %{"status" => "error", "errorType" => "bad_data"} = json_response(response, 400)
      end

      assert_parquet(store)
    end
  end

  test "TestDistributor / invalid rw2 symbols / v2", %{store: store} do
    bytes =
      Enum.map_join(["__name__", "invalid_series_bad_symbols", "some helpC", "someunitC"], &field(4, &1)) <>
        field(
          5,
          field(1, <<0, 1>>) <> field(2, sample(@start, 100)) <> field(5, uint(1, 1) <> uint(3, 2) <> uint(4, 3))
        )

    response = post_write(bytes, :v2)
    assert response.status == 400
    assert_written(response, :v2, 0, 0, 0)
    assert data("/api/v1/metadata", metric: "invalid_series_bad_symbols") == %{}
    assert Agent.get(store, & &1.objects) == %{}
  end

  for version <- [:v1, :v2] do
    @tag rw_version: version
    test "Pulse label controls: normalized same-label merging and keyed retry / #{version}",
         %{rw_version: version} do
      labels = [{"__name__", "normalized"}, {"job", "api"}]

      bytes =
        label_request(version, [
          %{labels: [{"empty", ""} | Enum.reverse(labels)], histograms: [generated_histogram(@start, 1, :integer)]},
          %{labels: labels, samples: [{@start, 100}, {@start + 600, 110}]}
        ])

      for _attempt <- 1..2 do
        response = post_write(bytes, version, [{"idempotency-key", "normalized-labels"}])
        assert response.status == 204
        assert_written(response, version, 2, 0, 0)
      end

      assert {:ok, stored} = Storage.query(:metrics, @tenant)
      assert length(stored) == 2
      assert Enum.all?(stored, &(&1.labels == Map.new(labels) and is_nil(&1.histogram)))
      assert stored |> Enum.map(& &1.series_id) |> Enum.uniq() |> length() == 1

      assert data("/api/v1/query_range", query: "normalized", start: @start, end: @start + 3600, step: "10m") == %{
               "resultType" => "matrix",
               "result" => [%{"metric" => Map.new(labels), "values" => [[@start, "100"], [@start + 600, "110"]]}]
             }

      assert discovery("/api/v1/labels", [start: @start, end: @start + 600], ["normalized"]) == ["__name__", "job"]
    end
  end

  # These are Pulse receiver-contract controls, not upstream table entries.
  # Invalid series must not poison the valid sibling, and all their points
  # count as rejected even if the invalid label precedes the sample fields.
  for {name, bad_labels} <- [
        {"duplicate differing values", [{"job", "a"}, {"job", "b"}]},
        {"duplicate identical values", [{"job", "a"}, {"job", "a"}]},
        {"duplicate before empty-value removal", [{"job", "a"}, {"job", ""}]},
        {"duplicate empty values", [{"job", ""}, {"job", ""}]},
        {"duplicate metric names", [{"__name__", "other"}]},
        {"empty label name", [{"", "value"}]},
        {"empty label name and value", [{"", ""}]}
      ],
      version <- [:v1, :v2] do
    @tag rw_version: version
    test "Pulse label controls: partial write / #{name} / #{version}", %{store: store, rw_version: version} do
      bytes =
        label_request(version, [
          %{
            labels: [{"__name__", "invalid"} | unquote(Macro.escape(bad_labels))],
            samples: [{@start, 1}, {@start + 1, 2}]
          },
          %{labels: [{"__name__", "valid"}], samples: [{@start, 100}]}
        ])

      response = post_write(bytes, version)

      case version do
        :v1 -> assert response.status == 204
        :v2 -> assert json_response(response, 400) == %{"error" => "rejected_records", "rejected" => 2}
      end

      assert get_resp_header(response, "x-pulse-rejected-records") == ["2"]
      assert_written(response, version, 1, 0, 0)
      assert {:ok, [%{labels: %{"__name__" => "valid"}, value: 100.0}]} = Storage.query(:metrics, @tenant)

      assert data("/api/v1/query", query: "valid", time: @start) == %{
               "resultType" => "vector",
               "result" => [%{"metric" => %{"__name__" => "valid"}, "value" => [@start, "100"]}]
             }

      assert discovery("/api/v1/series", [start: @start, end: @start + 1], [~s({__name__=~".+"})]) == [
               %{"__name__" => "valid"}
             ]

      assert_parquet(store)
    end
  end

  # The next two distributor table entries. NHCB is RW2-only upstream.
  for {name, metric, suffix, schema, version, buckets} <- [
        {"simple native histogram", "foobarNH", "NH", -1, :v1, [[0, "0.25", "1", "150"], [0, "1", "4", "50"]]},
        {"simple native histogram", "foobarNH", "NH", -1, :v2, [[0, "0.25", "1", "150"], [0, "1", "4", "50"]]},
        {"simple nhcb histogram", "foobarNHCB", "NHCB", -53, :v2, [[3, "-Inf", "0.1", "150"], [0, "0.1", "+Inf", "50"]]}
      ] do
    @tag rw_version: version
    test "TestDistributor / #{name} / #{version}", %{store: store, rw_version: version} do
      metric = unquote(metric)
      help = "some help" <> unquote(suffix)
      unit = "someunit" <> unquote(suffix)

      histogram =
        uint(1, 200) <>
          double(3, 1000) <>
          uint(4, zigzag(unquote(schema))) <>
          field(11, uint(2, 2)) <> field(12, varint(300) <> varint(199)) <> uint(15, @start * 1000)

      histogram = if unquote(schema) == -53, do: histogram <> double(16, 0.1), else: histogram

      bytes =
        case version do
          :v1 ->
            field(1, series([{"__name__", metric}], []) <> field(4, histogram)) <>
              field(3, uint(1, 3) <> field(2, metric) <> field(4, help) <> field(5, unit))

          :v2 ->
            Enum.map_join(["", "__name__", metric, help, unit], &field(4, &1)) <>
              field(5, field(1, <<1, 2>>) <> field(3, histogram) <> field(5, uint(1, 3) <> uint(3, 3) <> uint(4, 4)))
        end

      response = post_write(bytes, version)
      assert response.status == 204
      assert_written(response, version, 0, 1, 0)

      assert data("/api/v1/query_range", query: metric, start: @start, end: @start + 3600, step: "5m") == %{
               "resultType" => "matrix",
               "result" => [
                 %{
                   "metric" => %{"__name__" => metric},
                   "histograms" => [[@start, %{"count" => "200", "sum" => "1000", "buckets" => unquote(buckets)}]]
                 }
               ]
             }

      assert data("/api/v1/metadata", metric: metric) == %{
               metric => [%{"type" => "histogram", "help" => help, "unit" => unit}]
             }

      assert_parquet(store)
    end
  end

  # "series with exemplars" retains the exact labels, value and timestamp.
  # Mimir's enable/disable/age overrides are separate unported scenarios.
  for version <- [:v1, :v2] do
    @tag rw_version: version
    test "TestDistributor / series with exemplars / #{version}", %{store: store, rw_version: version} do
      metric = "foobar_with_exemplars"

      bytes =
        case version do
          :v1 ->
            exemplar = field(1, field(1, "test") <> field(2, "test")) <> double(2, 123) <> uint(3, @start * 1000)
            field(1, series([{"__name__", metric}], [{@start, 100}]) <> field(3, exemplar))

          :v2 ->
            exemplar = field(1, <<3, 3>>) <> double(2, 123) <> uint(3, @start * 1000)

            Enum.map_join(["", "__name__", metric, "test"], &field(4, &1)) <>
              field(5, field(1, <<1, 2>>) <> field(2, sample(@start, 100)) <> field(4, exemplar))
        end

      response = post_write(bytes, version)
      assert response.status == 204
      assert_written(response, version, 1, 0, 1)

      assert data("/api/v1/query_exemplars", query: metric, start: @start, end: @start + 3600) == [
               %{
                 "seriesLabels" => %{"__name__" => metric},
                 "exemplars" => [%{"labels" => %{"test" => "test"}, "value" => "123", "timestamp" => @start}]
               }
             ]

      assert_parquet(store)
    end
  end

  for version <- [:v1, :v2] do
    @tag rw_version: version
    test "Pulse collision controls: split entries, exemplars and exact keyed retries / #{version}",
         %{store: store, rw_version: version} do
      # Reversed wire order still appends floats first after merging labels.
      bytes = fn value ->
        case version do
          :v1 ->
            label = series([{"__name__", "foobar"}], [])
            exemplar = field(1, field(1, "test") <> field(2, "test")) <> double(2, 123) <> uint(3, @start * 1000)

            field(1, label <> field(4, generated_histogram(@start, 1, :integer)) <> field(3, exemplar)) <>
              field(
                1,
                label <> field(2, sample(@start, value)) <> field(4, generated_histogram(@start + 600, 2, :float))
              )

          :v2 ->
            label = field(1, <<1, 2>>)
            exemplar = field(1, <<3, 3>>) <> double(2, 123) <> uint(3, @start * 1000)

            Enum.map_join(["", "__name__", "foobar", "test"], &field(4, &1)) <>
              field(5, label <> field(3, generated_histogram(@start, 1, :integer)) <> field(4, exemplar)) <>
              field(
                5,
                label <> field(2, sample(@start, value)) <> field(3, generated_histogram(@start + 600, 2, :float))
              )
        end
      end

      for _attempt <- 1..2 do
        response = post_write(bytes.(100), version, [{"idempotency-key", "collision"}])
        assert response.status == 204
        assert_written(response, version, 1, 1, 1)
      end

      assert {:ok, stored} = Storage.query(:metrics, @tenant)
      assert length(stored) == 2
      assert [%{value: 100.0, histogram: nil, exemplars: [%{value: 123.0}]}] = Enum.filter(stored, & &1.value)
      assert [%{histogram: %{count: 30.0}}] = Enum.filter(stored, & &1.histogram)

      # Simulate provider corruption at the SAME deterministic object key.
      # Different caller content would correctly derive a different key.
      corrupted =
        Agent.get_and_update(store, fn state ->
          {key, {etag, <<_first, rest::binary>>}} =
            Enum.find(state.objects, fn {key, _} -> String.ends_with?(key, ".parquet") end)

          objects = Map.put(state.objects, key, {etag, <<0, rest::binary>>})
          {objects, %{state | objects: objects}}
        end)

      response = post_write(bytes.(100), version, [{"idempotency-key", "collision"}])
      assert json_response(response, 409) == %{"error" => "keyed_content_mismatch"}
      assert Agent.get(store, & &1.objects) == corrupted
    end
  end

  # integration/ingester_test.go: TestIngesterQuerying, float-only selections.
  for {name, metric, offset} <- [
        {"float series", "foobar", 0},
        {"float series where sample timestamps don't align with query step", "foobar", -2},
        {"query that returns no results", "not_foobar", -2}
      ] do
    test "TestIngesterQuerying / #{name}", %{store: store} do
      metric = unquote(metric)
      offset = unquote(offset)

      points =
        if metric == "not_foobar",
          do: [{@start - 2, 100}],
          else: Enum.map(0..5, &{@start + &1 * 600 + offset, 100 + &1 * 10})

      assert post_write(field(1, series([{"__name__", metric}], points))).status == 204

      for {query, labels, expected_values} <- [
            {"foobar", %{"__name__" => "foobar"}, Enum.map(0..5, &[@start + &1 * 600, to_string(100 + &1 * 10)])},
            {"timestamp(foobar)", %{}, Enum.map(0..5, &[@start + &1 * 600, to_string(@start + &1 * 600 + offset)])}
          ] do
        expected = if metric == "not_foobar", do: [], else: [%{"metric" => labels, "values" => expected_values}]

        assert data("/api/v1/query_range", query: query, start: @start, end: @start + 3600, step: "10m") ==
                 %{"resultType" => "matrix", "result" => expected}
      end

      assert_parquet(store)
    end
  end

  # Remaining TestIngesterQuerying entries. Geometry and expected JSON are from
  # pkg/util/test/histogram.go and its vendored tsdbutil helpers, not Pulse.
  for {name, floats, histograms, expected_indices} <- [
        {"integer histogram series", [], Enum.map(0..5, &{&1, &1 + 1, :integer}), Enum.to_list(0..5)},
        {"float histogram series", [], Enum.map(0..5, &{&1, &1 + 1, :float}), Enum.to_list(0..5)},
        {"series switching from float to integer histogram to float histogram", [{0, 100}, {1, 110}],
         [{2, 3, :integer}, {3, 4, :integer}, {4, 5, :float}, {5, 6, :float}], [2, 3, 4, 5]},
        {"series including float and native histograms at same timestamp", [{0, 100}, {1, 110}, {2, 120}],
         [{2, 3, :integer}, {3, 4, :integer}, {4, 5, :integer}, {5, 6, :integer}], [3, 4, 5]}
      ] do
    test "TestIngesterQuerying / #{name}", %{store: store} do
      floats = unquote(Macro.escape(floats))
      histograms = unquote(Macro.escape(histograms))

      input =
        series([{"__name__", "foobar"}], Enum.map(floats, fn {step, value} -> {@start + step * 600, value} end)) <>
          Enum.map_join(histograms, fn {step, index, type} ->
            field(4, generated_histogram(@start + step * 600, index, type))
          end)

      assert post_write(field(1, input)).status == 204

      expected = %{
        "metric" => %{"__name__" => "foobar"},
        "histograms" => Enum.map(unquote(expected_indices), &[@start + &1 * 600, generated_sample_histogram(&1 + 1)])
      }

      expected = add_float_values(expected, floats)

      assert data("/api/v1/query_range", query: "foobar", start: @start, end: @start + 3600, step: "10m") ==
               %{"resultType" => "matrix", "result" => [expected]}

      assert data("/api/v1/query_range", query: "timestamp(foobar)", start: @start, end: @start + 3600, step: "10m") ==
               %{
                 "resultType" => "matrix",
                 "result" => [
                   %{"metric" => %{}, "values" => Enum.map(0..5, &[@start + &1 * 600, to_string(@start + &1 * 600)])}
                 ]
               }

      assert_parquet(store)
    end
  end

  # integration/query_frontend_test.go: TestQueryFrontendWithExplicitLookbackDelta.
  # generateFloatSeries chooses rand.Float64(); freeze it to 0.5, not a new expectation.
  for {name, elapsed, lookback, present?} <- [
        {"default includes sample", 180, nil, true},
        {"default excludes sample", 360, nil, false},
        {"explicit includes sample", 360, "10m", true},
        {"explicit excludes sample", 360, "1m", false}
      ] do
    test "TestQueryFrontendWithExplicitLookbackDelta / #{name}" do
      assert post_write(field(1, series([{"__name__", "test_metric"}], [{@start, 0.5}]))).status == 204
      time = @start + unquote(elapsed)
      extra = if unquote(lookback), do: [lookback_delta: unquote(lookback)], else: []

      vector =
        if unquote(present?), do: [%{"metric" => %{"__name__" => "test_metric"}, "value" => [time, "0.5"]}], else: []

      matrix =
        if unquote(present?), do: [%{"metric" => %{"__name__" => "test_metric"}, "values" => [[time, "0.5"]]}], else: []

      assert data("/api/v1/query", [query: "test_metric", time: time] ++ extra) ==
               %{"resultType" => "vector", "result" => vector}

      assert data(
               "/api/v1/query_range",
               [query: "test_metric", start: time - 6000, end: time + 6000, step: "100m"] ++ extra
             ) ==
               %{"resultType" => "matrix", "result" => matrix}
    end
  end

  test "TestQueryFrontendErrorMessageParity / execution error", %{store: store} do
    seed_frontend_error_series()

    query =
      ~s'sum by (group_1) (metric{unique=~"0|1|2|3"})' <>
        ~s' * on(group_1) group_right(unique) (sum by (group_1,unique) (metric{unique=~"0|1|2|3"}))'

    response =
      conn()
      |> get(
        "/api/v1/query_range?" <>
          URI.encode_query(query: query, start: @start - 60, end: @start, step: "60")
      )

    assert json_response(response, 422) == %{
             "status" => "error",
             "errorType" => "execution",
             "error" => "multiple matches for labels: grouping labels must ensure unique matches"
           }

    assert_parquet(store)
  end

  test "Pulse grouping controls: step-local uniqueness, directions and error ownership", %{store: store} do
    seed_frontend_error_series()
    one = ~s'sum by (group_1) (metric{unique=~"0|1|2|3"})'
    many = ~s'sum by (group_1,unique) (metric{unique=~"0|1|2|3"})'
    single = ~s'sum by (group_1,unique) (metric{unique=~"0|1"})'

    for query <- [
          one <> " * on(group_1) group_right " <> many,
          many <> " * on(group_1) group_left " <> one,
          one <> " * on(group_1) group_right(unique) " <> single,
          single <> " * on(group_1) group_left(unique) " <> one
        ] do
      labels =
        if String.contains?(query, "(unique)"),
          do: [%{"group_1" => "0"}, %{"group_1" => "1"}],
          else: for(i <- [0, 2, 1, 3], do: %{"group_1" => to_string(rem(i, 2)), "unique" => to_string(i)})

      expected = Enum.map(labels, &%{"metric" => &1, "values" => [[@start, "0.5"], [@start + 60, "0.5"]]})

      params = [query: query, start: @start - 60, end: @start + 60, step: "60"]
      assert data("/api/v1/query_range", params) == %{"resultType" => "matrix", "result" => expected}
    end

    for query <- [
          one <> " * on(group_1) group_right(unique) " <> many,
          many <> " * on(group_1) group_left(unique) " <> one,
          one <> " < bool on(group_1) group_right(unique) " <> many,
          many <> " > bool on(group_1) group_left(unique) " <> one
        ],
        {path, params} <- [
          {"/api/v1/query", [query: query, time: @start]},
          {"/api/v1/query_range", [query: query, start: @start - 60, end: @start + 60, step: "60"]}
        ] do
      for response <- [
            get(conn(), path, params),
            conn()
            |> put_req_header("content-type", "application/x-www-form-urlencoded")
            |> post(path, URI.encode_query(params))
          ] do
        assert json_response(response, 422) == %{
                 "status" => "error",
                 "errorType" => "execution",
                 "error" => "multiple matches for labels: grouping labels must ensure unique matches"
               }
      end

      assert data("/api/v1/query", query: query, time: @start - 1) == %{"resultType" => "vector", "result" => []}
      assert data("/api/v1/query", query: query, time: @start + 300) == %{"resultType" => "vector", "result" => []}
    end

    # Filtered-out pairs never enter the uniqueness set, whereas bool false
    # pairs above retain zero-valued output and must still reject collisions.
    for query <- [
          one <> " < on(group_1) group_right(unique) " <> many,
          many <> " > on(group_1) group_left(unique) " <> one,
          one <> ~s' * on(group_1) group_right(unique) metric{group_1="missing"}'
        ] do
      assert data("/api/v1/query", query: query, time: @start) == %{"resultType" => "vector", "result" => []}
    end

    # Ordinary duplicate outputs and an ambiguous one-side index are different
    # execution errors, not grouped output collisions.
    for query <- [
          many <> " * on(group_1) group_right " <> one,
          ~s'label_replace(metric{unique=~"0|2"}, "unique", "", "unique", ".*")'
        ] do
      assert conn() |> get("/api/v1/query", query: query, time: @start) |> json_response(422) == %{
               "status" => "error",
               "errorType" => "execution",
               "error" => "Vector matching produced ambiguous or duplicate series."
             }
    end

    assert_parquet(store)
  end

  # TestQueryFrontendErrorMessageParity: its eight portable invalid range
  # requests. Six diagnostics retain the complete upstream envelope;
  # unknown-function/aggregation diagnostics remain adapted. QueryRangeRaw sends
  # numeric seconds (including -60), not duration strings. The last row's omitted
  # resolution is valid inside range functions, but a top-level range result rejects.
  for {name, query, first, last, step} <- [
        {"maximum resolution error", "unknown", @start - 86_400, @start, "1"},
        {"negative step", "unknown", @start - 3600, @start, "-60"},
        {"unknown function", "unknown(up)", @start - 3600, @start, "60"},
        {"range vector instead of instant vector",
         ~s|sum by(grpc_method)(grpc_server_handled_total{job="cortex-dedicated-06/etcd"}[1m])|, @start - 3600, @start,
         "60"},
        {"start after end", "unknown", @start, @start - 3600, "60"},
        {"wrong duration specified in step", "unknown", @start - 3600, @start, "123notafloat"},
        {"wrong timestamp in start", "unknown", "depths-of-time", @start, "30"},
        {"range query with range vector", "(sum(rate(up[1m])))[5m:]", @start - 3600, @start, "60"}
      ] do
    expected_error =
      Map.get(
        %{
          "maximum resolution error" =>
            "exceeded maximum resolution of 11,000 points per timeseries. Try decreasing the query resolution (?step=XX)",
          "negative step" =>
            "invalid parameter \"step\": zero or negative query resolution step widths are not accepted. Try a positive integer",
          "start after end" => "invalid parameter \"end\": end timestamp must not be before start time",
          "wrong duration specified in step" =>
            ~s(invalid parameter "step": cannot parse "123notafloat" to a valid duration),
          "wrong timestamp in start" =>
            ~s(invalid parameter "start": cannot parse "depths-of-time" to a valid timestamp),
          "range query with range vector" =>
            "invalid parameter \"query\": query expression produces a range vector, but expression for range queries must produce an instant vector or scalar"
        },
        name,
        "Invalid or unsupported query parameters."
      )

    @tag range_result_diagnostics: name == "range query with range vector"
    test "TestQueryFrontendErrorMessageParity / #{name} / Pulse diagnostics", %{store: store} do
      params = [query: unquote(query), start: unquote(first), end: unquote(last), step: unquote(step)]
      assert Agent.get(store, & &1.requests) == []

      response = conn() |> get("/api/v1/query_range?" <> URI.encode_query(params))

      assert json_response(response, 400) == %{
               "status" => "error",
               "errorType" => "bad_data",
               "error" => unquote(expected_error)
             }

      assert Agent.get(store, & &1.requests) == []
    end
  end

  # integration/querier_test.go: TestHashCollisionHandling, RW1 as sent by Push.
  # These labels collide in upstream fingerprints/fast fingerprints, not in
  # Pulse's StableHash/xxhash64. This replays the public result, not a Pulse collision.
  test "TestHashCollisionHandling", %{store: store} do
    bytes =
      field(1, series([{"A", "K6sjsNNczPl"}, {"__name__", "fingerprint_collision"}], [{@start, 0}])) <>
        field(1, series([{"A", "cswpLMIZpwt"}, {"__name__", "fingerprint_collision"}], [{@start, 1}]))

    assert post_write(bytes, :v1, [{"x-scope-orgid", "user-0"}]).status == 204

    assert data("/api/v1/query", [query: "fingerprint_collision", time: @start], "user-0") == %{
             "resultType" => "vector",
             "result" => [
               %{
                 "metric" => %{"A" => "K6sjsNNczPl", "__name__" => "fingerprint_collision"},
                 "value" => [@start, "0"]
               },
               %{
                 "metric" => %{"A" => "cswpLMIZpwt", "__name__" => "fingerprint_collision"},
                 "value" => [@start, "1"]
               }
             ]
           }

    assert_parquet(store)
  end

  # integration/querier_test.go: testMetadataQueriesWithBlocksStorage, called by
  # TestQuerierWithBlocksStorageRunningInSingleBinaryMode. All four time windows.
  for {name, first, last, included, value_selectors} <- [
        {"query metadata entirely inside the head range", 4, 5, [3], [{[], [3]}, {[3], [3]}, {[1], []}]},
        {"query metadata entirely inside the ingester range but outside the head range", 2, 2.5, [2],
         [{[], [2]}, {[2], [2]}, {[3], []}]},
        {"query metadata partially inside the ingester range", -1, 5, [1, 2, 3],
         [{[], [1, 2, 3]}, {[1], [1]}, {[2], [2]}, {[1, 2], [1, 2]}]},
        {"query metadata entirely outside the ingester range should not return the head data", -2, 0, [1],
         [{[], [1]}, {[1], [1]}, {[3], []}]}
      ] do
    test "testMetadataQueriesWithBlocksStorage / #{name}", %{store: store} do
      # A fixed 60s blockRangePeriod; Pulse has one durable segment path, not TSDB tiers.
      for {index, offset} <- [{1, 0}, {2, 120}, {3, 240}] do
        labels = [{"__name__", "series_#{index}"}, {"series_#{index}", "series_#{index}"}]

        input =
          if index == 2,
            do: series(labels, []) <> field(4, generated_histogram(@start + offset, 1, :integer)),
            else: series(labels, [{@start + offset, 0.5}])

        assert post_write(field(1, input)).status == 204
      end

      bounds = [start: @start + unquote(first) * 60, end: @start + unquote(last) * 60]
      included = unquote(included)

      for index <- 1..3 do
        expected =
          if index in included,
            do: [%{"__name__" => "series_#{index}", "series_#{index}" => "series_#{index}"}],
            else: []

        assert discovery("/api/v1/series", bounds, ["series_#{index}"]) == expected
      end

      for {selectors, expected} <- unquote(Macro.escape(value_selectors)) do
        assert discovery("/api/v1/label/__name__/values", bounds, Enum.map(selectors, &"series_#{&1}")) ==
                 Enum.map(expected, &"series_#{&1}")
      end

      assert discovery("/api/v1/labels", bounds, []) == ["__name__" | Enum.map(included, &"series_#{&1}")]
      assert_parquet(store)
    end
  end

  test "Pulse lookback controls: nested timestamp, offsets, range windows, boundaries and POST" do
    assert post_write(field(1, series([{"__name__", "test_metric"}], [{@start, 0.5}]))).status == 204

    for lookback <- ["10m", "600", "6e2"] do
      assert data("/api/v1/query", query: "abs(timestamp(test_metric))", time: @start + 360, lookback_delta: lookback) ==
               %{
                 "resultType" => "vector",
                 "result" => [%{"metric" => %{}, "value" => [@start + 360, to_string(@start)]}]
               }
    end

    assert data("/api/v1/query", query: "test_metric offset 1m", time: @start + 360, lookback_delta: "6m") ==
             %{
               "resultType" => "vector",
               "result" => [%{"metric" => %{"__name__" => "test_metric"}, "value" => [@start + 360, "0.5"]}]
             }

    # Left-open lookback boundary, independently of the range-vector window.
    assert data("/api/v1/query", query: "test_metric", time: @start + 600, lookback_delta: "10m") ==
             %{"resultType" => "vector", "result" => []}

    assert data("/api/v1/query", query: "count_over_time(test_metric[10m])", time: @start + 360, lookback_delta: "1m") ==
             %{"resultType" => "vector", "result" => [%{"metric" => %{}, "value" => [@start + 360, "1"]}]}

    for {lookback, expected} <- [{"10m", [%{"metric" => %{}, "value" => [@start + 360, "0.5"]}]}, {"1m", []}] do
      assert data("/api/v1/query",
               query: "sum_over_time((test_metric)[1m:1m])",
               time: @start + 360,
               lookback_delta: lookback
             ) ==
               %{"resultType" => "vector", "result" => expected}
    end

    response =
      conn()
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> post("/api/v1/query", URI.encode_query(query: "test_metric", time: @start + 360, lookback_delta: "10m"))

    assert %{"data" => %{"result" => [%{"value" => [_, "0.5"]}]}} = json_response(response, 200)

    # An override never leaks into a subsequent request's default.
    assert data("/api/v1/query", query: "test_metric", time: @start + 360) == %{
             "resultType" => "vector",
             "result" => []
           }

    for value <- ["", "bad", "0", "0s", "-1", "-1m", "1e300", "99999999999999999y"] do
      response = conn() |> get("/api/v1/query", %{query: "test_metric", time: @start, lookback_delta: value})
      assert %{"status" => "error", "errorType" => "bad_data"} = json_response(response, 400)
    end
  end

  defp discovery(path, bounds, selectors) do
    params =
      Enum.map(bounds, fn {key, value} -> {to_string(key), to_string(value)} end) ++
        Enum.map(selectors, &{"match[]", &1})

    # Form POST is an additional Pulse transport control, not an upstream case.
    expected = data(path, params)

    response =
      conn()
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> post(path, URI.encode_query(params))

    assert json_response(response, 200) == %{"status" => "success", "data" => expected}
    expected
  end

  defp conn(tenant \\ @tenant), do: build_conn() |> put_req_header("x-scope-orgid", tenant)

  defp data(path, params, tenant \\ @tenant) do
    response = conn(tenant) |> get(path <> "?" <> URI.encode_query(params)) |> json_response(200)
    assert response["status"] == "success"
    Map.fetch!(response, "data")
  end

  # integration/query_frontend_test.go:672-689. Freeze GenerateSeries' random
  # float to 0.5 and clock to @start; keep all 50 distinct RW1 pushes.
  defp seed_frontend_error_series do
    for i <- 0..49 do
      labels = [{"__name__", "metric"}, {"unique", to_string(i)}, {"group_1", to_string(rem(i, 2))}]
      assert post_write(field(1, series(labels, [{@start, 0.5}]))).status == 204
    end
  end

  defp post_write(bytes, version \\ :v1, headers \\ []) do
    {:ok, compressed} = :snappyer.compress(bytes)

    type =
      if version == :v2,
        do: "application/x-protobuf;proto=io.prometheus.write.v2.Request",
        else: "application/x-protobuf"

    conn()
    |> put_req_header("content-type", type)
    |> put_req_header("content-encoding", "snappy")
    |> put_req_header("x-prometheus-remote-write-version", if(version == :v2, do: "2.0.0", else: "0.1.0"))
    |> then(fn conn -> Enum.reduce(headers, conn, fn {key, value}, conn -> put_req_header(conn, key, value) end) end)
    |> post("/api/v1/write", compressed)
  end

  defp assert_parquet(store) do
    assert Agent.get(store, fn state ->
             Enum.any?(state.objects, fn {key, {_etag, body}} ->
               String.ends_with?(key, ".parquet") and String.starts_with?(body, "PAR1")
             end)
           end)
  end

  defp assert_written(response, version, samples, histograms, exemplars) do
    for {header, count} <- [{"samples", samples}, {"histograms", histograms}, {"exemplars", exemplars}] do
      assert get_resp_header(response, "x-prometheus-remote-write-#{header}-written") ==
               if(version == :v2, do: [to_string(count)], else: [])
    end
  end

  # Independent test-only protobuf encoding, no Mimir implementation code.
  defp label_request(:v1, rows) do
    Enum.map_join(rows, fn row ->
      points = Map.get(row, :samples, [])
      histograms = Map.get(row, :histograms, [])
      field(1, series(row.labels, points) <> Enum.map_join(histograms, &field(4, &1)))
    end)
  end

  defp label_request(:v2, rows) do
    symbols =
      ["" | Enum.flat_map(rows, fn row -> Enum.flat_map(row.labels, fn {key, value} -> [key, value] end) end)]
      |> Enum.uniq()

    refs = symbols |> Enum.with_index() |> Map.new()

    entries =
      Enum.map_join(rows, fn row ->
        points = Map.get(row, :samples, [])
        histograms = Map.get(row, :histograms, [])
        labels = Enum.map_join(row.labels, fn {key, value} -> varint(refs[key]) <> varint(refs[value]) end)

        field(5, field(1, labels) <> sample_fields(points) <> Enum.map_join(histograms, &field(3, &1)))
      end)

    Enum.map_join(symbols, &field(4, &1)) <> entries
  end

  defp series(labels, points) do
    Enum.map_join(labels, fn {key, value} -> field(1, field(1, key) <> field(2, value)) end) <>
      sample_fields(points)
  end

  defp sample_fields(points), do: Enum.map_join(points, fn {time, value} -> field(2, sample(time, value)) end)

  defp add_float_values(expected, []), do: expected

  defp add_float_values(expected, floats),
    do: Map.put(expected, "values", Enum.map(floats, fn {step, value} -> [@start + step * 600, to_string(value)] end))

  # GenerateTestHistogram / GenerateTestFloatHistogram: schema 1, identical
  # positive/negative spans, delta integer versus absolute floating counts.
  defp generated_histogram(time, index, type) do
    base = double(3, 18.4 * (index + 1)) <> uint(4, 2) <> double(5, 0.001) <> uint(15, time * 1000)
    spans = field(8, uint(2, 2)) <> field(8, uint(1, 2) <> uint(2, 2))
    spans = spans <> field(11, uint(2, 2)) <> field(11, uint(1, 2) <> uint(2, 2))

    case type do
      :integer ->
        buckets = Enum.map_join([index + 1, 1, -1, 0], &varint(zigzag(&1)))
        base <> uint(1, 12 + index * 9) <> uint(6, 2 + index) <> spans <> field(9, buckets) <> field(12, buckets)

      :float ->
        buckets = Enum.map_join([index + 1, index + 2, index + 1, index + 1], &<<&1 * 1.0::little-float-64>>)
        base <> double(2, 12 + index * 9) <> double(7, 2 + index) <> spans <> field(10, buckets) <> field(13, buckets)
    end
  end

  # GenerateTestSampleHistogram's explicit decoded geometry. Sums are frozen
  # Go FloatString spellings of 18.4 * float64(i+1), never formatter output
  # from the implementation under test.
  defp generated_sample_histogram(index) do
    sums = ["36.8", "55.199999999999996", "73.6", "92", "110.39999999999999", "128.79999999999998"]
    count = to_string(index + 1)
    larger = to_string(index + 2)

    %{
      "count" => to_string(12 + index * 9),
      "sum" => Enum.at(sums, index - 1),
      "buckets" => [
        [1, "-4", "-2.82842712474619", count],
        [1, "-2.82842712474619", "-2", count],
        [1, "-1.414213562373095", "-1", larger],
        [1, "-1", "-0.7071067811865475", count],
        [3, "-0.001", "0.001", larger],
        [0, "0.7071067811865475", "1", count],
        [0, "1", "1.414213562373095", larger],
        [0, "2", "2.82842712474619", count],
        [0, "2.82842712474619", "4", count]
      ]
    }
  end

  defp zigzag(value) when value < 0, do: -value * 2 - 1
  defp zigzag(value), do: value * 2
  defp double(number, value), do: varint(number <<< 3 ||| 1) <> <<value * 1.0::little-float-64>>
  defp sample(time, value), do: <<9, value * 1.0::little-float-64>> <> uint(2, trunc(time * 1000))
  defp field(number, bytes), do: varint(number <<< 3 ||| 2) <> varint(byte_size(bytes)) <> bytes
  defp uint(number, value), do: varint(number <<< 3) <> varint(value)
  defp varint(value) when value < 128, do: <<value>>
  defp varint(value), do: <<(value &&& 127) ||| 128>> <> varint(value >>> 7)
end
