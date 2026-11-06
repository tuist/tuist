# Result-limit cases adapted from Prometheus v3.5.0 web/api/v1/api_test.go.
# Copyright 2016 The Prometheus Authors, Apache-2.0.
# Source/case mapping: test/fixtures/grafana/README.md.
defmodule PulseWeb.PrometheusQueryControllerTest do
  use PulseWeb.ConnCase, async: true

  alias Pulse.Auth
  alias Pulse.Auth.SharedSecret
  alias Pulse.PromQL.Evaluator
  alias Pulse.Record.MetricSample
  alias Pulse.Storage
  alias Pulse.Storage.Memory
  alias Pulse.Test.BlockingMetricStorage

  setup do
    Memory.reset()

    :ok =
      Storage.append(:metrics, "acme", [
        %MetricSample{timestamp_ns: 10_000_000_000, value: 10.0, labels: %{"__name__" => "requests_total"}},
        %MetricSample{timestamp_ns: 20_000_000_000, value: 20.0, labels: %{"__name__" => "requests_total"}}
      ])

    :ok
  end

  test "instant and range queries return Prometheus envelopes", %{conn: conn} do
    conn = put_req_header(conn, "x-scope-orgid", "acme")

    assert %{"data" => %{"resultType" => "vector", "result" => [%{"value" => [20.0, "20"]}]}} =
             conn |> get("/api/v1/query", %{query: "requests_total", time: "20"}) |> json_response(200)

    assert %{"data" => %{"resultType" => "matrix", "result" => [%{"values" => [[10.0, "10"], [20.0, "20"]]}]}} =
             conn
             |> get("/api/v1/query_range", %{query: "requests_total", start: "10", end: "20", step: "10s"})
             |> json_response(200)

    assert %{"status" => "success"} =
             conn
             |> post("/api/v1/query", %{query: "requests_total", time: "1970-01-01T00:00:20Z"})
             |> json_response(200)
  end

  test "math domain results remain successful instant and range values", %{conn: conn} do
    conn = put_req_header(conn, "x-scope-orgid", "acme")

    assert %{"data" => %{"resultType" => "vector", "result" => [%{"metric" => %{}, "value" => [20.0, "-Inf"]}]}} =
             conn |> post("/api/v1/query", %{query: "ln(requests_total - 20)", time: "20"}) |> json_response(200)

    assert %{
             "data" => %{
               "resultType" => "matrix",
               "result" => [%{"metric" => %{}, "values" => [[10.0, "NaN"], [20.0, "-Inf"]]}]
             }
           } =
             conn
             |> get("/api/v1/query_range", %{query: "ln(requests_total - 20)", start: "10", end: "20", step: "10s"})
             |> json_response(200)
  end

  test "invalid syntax and parameters return structured errors", %{conn: conn} do
    for params <- [%{}, %{query: "unsupported(x)"}, %{query: "x", time: "bad"}, %{query: "x", time: "1e300"}] do
      assert %{"status" => "error", "errorType" => "bad_data"} =
               conn |> get("/api/v1/query", params) |> json_response(400)
    end

    for step <- ["0", "-1", "garbage", "1e300"] do
      assert %{"status" => "error"} =
               conn
               |> get("/api/v1/query_range", %{query: "x", start: "0", end: "20", step: step})
               |> json_response(400)
    end
  end

  test "decimal boundaries, default tenants, and unsupported overrides", %{conn: conn} do
    :ok =
      Storage.append(:metrics, "default", [
        %MetricSample{timestamp_ns: 375_000_000, value: 1.0, labels: %{"__name__" => "boundary"}}
      ])

    for time <- ["0.375", "375e-3", "1970-01-01T00:00:00.375Z"] do
      assert %{"data" => %{"result" => [%{"value" => [0.375, "1"]}]}} =
               conn
               |> put_req_header("x-scope-orgid", "")
               |> get("/api/v1/query", %{query: "boundary", time: time})
               |> json_response(200)
    end

    assert %{"errorType" => "bad_data"} =
             conn |> get("/api/v1/query", %{query: "boundary", time: "9999-01-01T00:00:00Z"}) |> json_response(400)
  end

  test "upstream result limits count series, preserve samples and warn only on truncation", %{conn: conn} do
    # Prometheus v3.5.0 web/api/v1/api_test.go TestEndpoints, limit rows.
    query =
      ~s/label_replace(vector(42), "foo", "bar", "", "") or label_replace(vector(3.1415), "dings", "bums", "", "")/

    for method <- [:get, :post], limit <- ["", "0", "1", "2", "3"] do
      params = %{query: query, start: "0", end: "2", step: "1", limit: limit}
      response = range_request(conn, method, params) |> json_response(200)

      expected = [
        %{"metric" => %{"dings" => "bums"}, "values" => [[0, "3.1415"], [1, "3.1415"], [2, "3.1415"]]},
        %{"metric" => %{"foo" => "bar"}, "values" => [[0, "42"], [1, "42"], [2, "42"]]}
      ]

      assert response["data"] == %{
               "resultType" => "matrix",
               "result" => if(limit == "1", do: Enum.take(expected, 1), else: expected)
             }

      assert Map.get(response, "warnings", []) == if(limit == "1", do: ["results truncated due to limit"], else: [])
    end

    for limit <- ["0", "1", "2"] do
      response =
        conn |> get("/api/v1/query", %{query: "sort_desc(#{query})", time: "123.4", limit: limit}) |> json_response(200)

      expected = [
        %{"metric" => %{"foo" => "bar"}, "value" => [123.4, "42"]},
        %{"metric" => %{"dings" => "bums"}, "value" => [123.4, "3.1415"]}
      ]

      assert response["data"] == %{
               "resultType" => "vector",
               "result" => if(limit == "1", do: Enum.take(expected, 1), else: expected)
             }

      assert Map.get(response, "warnings", []) == if(limit == "1", do: ["results truncated due to limit"], else: [])
    end

    for {query, type, result} <- [{"2", "scalar", [123.4, "2"]}, {~s("hello"), "string", [123.4, "hello"]}] do
      response = conn |> get("/api/v1/query", %{query: query, time: "123.4", limit: "1"}) |> json_response(200)
      assert response["data"] == %{"resultType" => type, "result" => result}
      refute Map.has_key?(response, "warnings")
    end

    for limit <- ["-1", "1.5", "bad", "9223372036854775808", ["1"], %{"nested" => "1"}] do
      assert %{"errorType" => "bad_data"} =
               conn |> post("/api/v1/query", %{query: "2", limit: limit}) |> json_response(400)
    end
  end

  test "range parameter diagnostics are field-aware with GET and form POST", %{conn: conn} do
    nonpositive =
      "invalid parameter \"step\": zero or negative query resolution step widths are not accepted. Try a positive integer"

    cases =
      Enum.map(["0", "-0", "-60", "-1e-9", "0s", "0m0s", "1e-20"], &{%{step: &1}, nonpositive}) ++
        [
          {%{start: "21", end: "20", step: "bad"},
           "invalid parameter \"end\": end timestamp must not be before start time"},
          {%{start: "bad", end: "bad", step: "bad"},
           ~s(invalid parameter "start": cannot parse "bad" to a valid timestamp)},
          {%{end: "bad", step: "bad"}, ~s(invalid parameter "end": cannot parse "bad" to a valid timestamp)},
          {%{step: "bad"}, ~s(invalid parameter "step": cannot parse "bad" to a valid duration)},
          {%{step: "1e300"}, ~s(invalid parameter "step": cannot parse "1e300" to a valid duration)},
          {%{step: "-1s"}, ~s(invalid parameter "step": cannot parse "-1s" to a valid duration)},
          {%{step: ""}, ~s(invalid parameter "step": cannot parse "" to a valid duration)},
          {%{step: "NaN"}, ~s(invalid parameter "step": cannot parse "NaN" to a valid duration)},
          {%{step: "+Inf"}, ~s(invalid parameter "step": cannot parse "+Inf" to a valid duration)},
          {%{start: "1e300"}, ~s(invalid parameter "start": cannot parse "1e300" to a valid timestamp)},
          {%{end: ""}, ~s(invalid parameter "end": cannot parse "" to a valid timestamp)},
          {%{start: "0", end: "11000", step: "1"},
           "exceeded maximum resolution of 11,000 points per timeseries. Try decreasing the query resolution (?step=XX)"},
          {%{start: "0", end: "11001", step: "1"},
           "exceeded maximum resolution of 11,000 points per timeseries. Try decreasing the query resolution (?step=XX)"},
          {%{start: "a\"\n\\雪\u0000"}, ~S(invalid parameter "start": cannot parse "a\"\n\\雪\x00" to a valid timestamp)}
        ]

    for method <- [:get, :post], {overrides, message} <- cases do
      params = Map.merge(%{query: "unknown", start: "0", end: "20", step: "1"}, overrides)

      assert range_request(conn, method, params) |> json_response(400) == %{
               "status" => "error",
               "errorType" => "bad_data",
               "error" => message
             }
    end
  end

  test "range admission preserves exact timestamps, duration grammar and the inclusive point ceiling", %{conn: conn} do
    for method <- [:get, :post],
        {first, last, step, count} <- [
          {"0", "10999", "1", 11_000},
          {"0", "10999.999999999", "1", 11_000},
          {"20", "20", "1e-9", 1},
          {"0.000000001", "0.000000002", "1e-9", 2},
          {"1970-01-01T00:00:00Z", "1970-01-01T00:01:00+00:00", "1m", 2},
          {"0", "0.000000002", "0.000000001", 3},
          {"0", "60", "0m1s", 61}
        ] do
      response = range_request(conn, method, %{query: "1", start: first, end: last, step: step})
      assert %{"status" => "success", "data" => %{"result" => [%{"values" => values}]}} = json_response(response, 200)
      assert length(values) == count
    end
  end

  test "malformed range fields have bounded reflection and denial wins over diagnostics", %{conn: conn} do
    for method <- [:get, :post], field <- [:start, :end, :step] do
      params = %{query: "unknown", start: "0", end: "20", step: "1"}
      oversized = Map.put(params, field, String.duplicate("\u0000", 4096))
      response = range_request(conn, method, oversized)
      assert %{"status" => "error", "errorType" => "bad_data"} = json_response(response, 400)
      assert byte_size(response.resp_body) < 2048

      missing = range_request(conn, method, Map.delete(params, field))

      assert json_response(missing, 400) == %{
               "status" => "error",
               "errorType" => "bad_data",
               "error" =>
                 "invalid parameter \"#{field}\": cannot parse \"\" to a valid #{if field == :step, do: "duration", else: "timestamp"}"
             }

      for value <- [[], %{"nested" => "bad"}] do
        assert %{"status" => "error", "errorType" => "bad_data"} =
                 conn |> post("/api/v1/query_range", Map.put(params, field, value)) |> json_response(400)
      end
    end

    for method <- [:get, :post],
        overrides <- [%{query: "unknown(up)"}, %{timeout: "bad"}, %{lookback_delta: "0"}, %{unsupported: "1"}] do
      assert range_request(conn, method, Map.merge(%{query: "unknown", start: "0", end: "20", step: "1"}, overrides))
             |> json_response(400) == %{
               "status" => "error",
               "errorType" => "bad_data",
               "error" => "Invalid or unsupported query parameters."
             }
    end

    Pulse.Runtime.put_env(:pulse, Auth, module: SharedSecret, tokens: %{})

    for method <- [:get, :post],
        params <- [
          %{query: "unknown", start: "bad", end: "20", step: "bad"},
          %{query: "unknown", start: "0", end: "86400", step: "1"},
          %{query: "unknown", start: "0", end: "20", step: "-60"},
          %{query: "up[1m]", start: "0", end: "20", step: "1"}
        ] do
      assert range_request(conn, method, params) |> json_response(401) == %{
               "status" => "error",
               "errorType" => "unauthorized",
               "error" => "unauthorized"
             }
    end
  end

  defp range_request(conn, :get, params), do: get(conn, "/api/v1/query_range?" <> URI.encode_query(params))

  defp range_request(conn, :post, params) do
    conn
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> post("/api/v1/query_range", URI.encode_query(params))
  end

  test "Grafana query statistics selectors preserve truthful ordinary GET and POST results", %{conn: conn} do
    conn = put_req_header(conn, "x-scope-orgid", "acme")

    for {route, params, expected} <- [
          {"/api/v1/query", %{query: "requests_total", time: "20"},
           %{
             "resultType" => "vector",
             "result" => [%{"metric" => %{"__name__" => "requests_total"}, "value" => [20, "20"]}]
           }},
          {"/api/v1/query_range", %{query: "requests_total", start: "10", end: "20", step: "10s"},
           %{
             "resultType" => "matrix",
             "result" => [%{"metric" => %{"__name__" => "requests_total"}, "values" => [[10, "10"], [20, "20"]]}]
           }}
        ],
        method <- [:get, :post] do
      response =
        case method do
          :get ->
            conn |> get(route <> "?" <> URI.encode_query(Map.put(params, :stats, "all"))) |> json_response(200)

          :post ->
            conn
            |> put_req_header("content-type", "application/x-www-form-urlencoded")
            |> post(route <> "?stats=all", URI.encode_query(params))
            |> json_response(200)
        end

      assert response == %{"status" => "success", "data" => expected}
    end

    for stats <- [["all"], %{"nested" => "all"}] do
      assert conn |> post("/api/v1/query", %{query: "requests_total", time: "20", stats: stats}) |> json_response(400)
    end
  end

  test "client timeouts are accepted and invalid durations rejected", %{conn: conn} do
    for timeout <- ["30s", "1s", "0.1"] do
      assert %{"status" => "success"} =
               conn |> get("/api/v1/query", %{query: "m", timeout: timeout}) |> json_response(200)
    end

    for timeout <- ["bad", "0s", "-1s"] do
      assert %{"errorType" => "bad_data"} =
               conn |> get("/api/v1/query", %{query: "m", timeout: timeout}) |> json_response(400)
    end
  end

  test "scan limits and timeouts are execution errors rather than storage failures", %{conn: conn} do
    adapter = BlockingMetricStorage
    Pulse.Runtime.put_env(:pulse, Storage, adapter: adapter)

    for reason <- [:query_scan_limit, :query_timeout], limit <- ["0", "1"] do
      Pulse.Runtime.put_env(:pulse, adapter, {:error, reason})

      assert %{"errorType" => "execution"} =
               conn |> get("/api/v1/query", %{query: "m", limit: limit}) |> json_response(422)
    end

    Pulse.Runtime.put_env(:pulse, adapter, self())

    assert %{"errorType" => "execution"} =
             conn |> get("/api/v1/query", %{query: "m", timeout: "5ms"}) |> json_response(422)
  end

  test "sample budgets return an execution error", %{conn: conn} do
    Pulse.Runtime.put_env(:pulse, Evaluator, max_samples: 1)

    assert %{"errorType" => "execution"} =
             conn
             |> put_req_header("x-scope-orgid", "acme")
             |> get("/api/v1/query", %{query: "requests_total", time: "20"})
             |> json_response(422)
  end

  test "a valid token for another tenant cannot read acme", %{conn: conn} do
    token = fn value -> "sha256$" <> Base.encode16(:crypto.hash(:sha256, value), case: :lower) end

    Pulse.Runtime.put_env(:pulse, Auth,
      module: SharedSecret,
      tokens: %{"acme" => token.("acme-key"), "beta" => token.("beta-key")}
    )

    conn = conn |> put_req_header("x-scope-orgid", "acme") |> put_req_header("authorization", "Bearer beta-key")

    for path <- ["/api/v1/query", "/api/v1/query_range"] do
      assert %{"errorType" => "unauthorized"} = conn |> get(path, %{query: "requests_total"}) |> json_response(401)
    end
  end

  test "reads require tenant authorization", %{conn: conn} do
    Pulse.Runtime.put_env(:pulse, Auth, module: SharedSecret, tokens: %{})

    assert %{"errorType" => "unauthorized"} =
             conn |> get("/api/v1/query", %{query: "requests_total"}) |> json_response(401)

    assert %{"errorType" => "unauthorized"} =
             conn |> get("/api/v1/query_range", %{query: "requests_total"}) |> json_response(401)
  end
end
