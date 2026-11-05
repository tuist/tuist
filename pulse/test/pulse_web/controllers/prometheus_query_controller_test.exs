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
             conn |> get("/api/v1/query", %{"query" => "boundary", "limit" => "1"}) |> json_response(400)

    assert %{"errorType" => "bad_data"} =
             conn |> get("/api/v1/query", %{query: "boundary", time: "9999-01-01T00:00:00Z"}) |> json_response(400)
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

    for reason <- [:query_scan_limit, :query_timeout] do
      Pulse.Runtime.put_env(:pulse, adapter, {:error, reason})
      assert %{"errorType" => "execution"} = conn |> get("/api/v1/query", %{query: "m"}) |> json_response(422)
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
