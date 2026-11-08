defmodule PulseWeb.LokiQueryControllerTest do
  use PulseWeb.ConnCase, async: true

  alias Pulse.Record.Log
  alias Pulse.Storage
  alias Pulse.Storage.Memory

  setup do
    Memory.reset()
    :ok
  end

  test "label discovery reads every stream, not a bounded record sample", %{conn: conn} do
    records =
      for ts <- 1..5_001, do: %Log{timestamp_ns: ts, service: "api", body: "line", resource: %{"service.name" => "api"}}

    :ok = Storage.append(:logs, "acme", records)

    response =
      conn
      |> put_req_header("x-scope-orgid", "acme")
      |> get("/loki/api/v1/labels", %{"start" => "0"})
      |> json_response(200)

    assert response["data"] == ["service.name", "service_name"]
  end

  test "label discovery rejects an incomplete result", %{conn: conn} do
    records = for ts <- 1..5_001, do: %Log{timestamp_ns: ts, body: "line", resource: %{"pod" => "pod-#{ts}"}}

    :ok = Storage.append(:logs, "acme", records)

    response =
      conn
      |> put_req_header("x-scope-orgid", "acme")
      |> get("/loki/api/v1/label/pod/values", %{"start" => "0"})
      |> json_response(422)

    assert response["error"] == "query_limit"
  end

  test "a regular expression unsupported by the native decoder is a client error", %{conn: conn} do
    response =
      conn
      |> get("/loki/api/v1/query_range", %{"query" => ~s[{service="api"} |~ "foo(?=bar)"]})
      |> json_response(400)

    assert response["error"] == "evaluation_failed"
    assert response["message"] =~ "invalid_regex"
  end

  test "overflowing quantity literals return client errors for log and metric routes", %{conn: conn} do
    for expression <- [
          ~s/{app="a"} | latency > 9223372036854775808ns/,
          ~s/count_over_time({app="a"} | latency > 9223372036854775807ns1ns [1m])/,
          ~s/{app="a"} | size > 18446744073709551616B/
        ],
        path <- ["/loki/api/v1/query", "/loki/api/v1/query_range"] do
      response = conn |> get(path, %{"query" => expression}) |> json_response(400)
      assert is_binary(response["error"])
      refute Map.has_key?(response, "data")
    end
  end

  test "excessive metric ranges return a client error without allocating a timeline", %{conn: conn} do
    for {start, finish} <- [{"0", "11000000000"}, {"20", "10"}] do
      response =
        conn
        |> get("/loki/api/v1/query_range", %{
          "query" => ~s|rate({service="api"}[5m])|,
          "start" => start,
          "end" => finish,
          "step" => "1ms"
        })
        |> json_response(400)

      if start == "20" do
        assert response["error"] == "invalid_parameter"
      else
        assert response["error"] == "evaluation_failed"
        assert response["message"] =~ "invalid_range_or_too_many_steps"
      end
    end
  end

  test "instant time is honored for native metrics, including RFC3339", %{conn: conn} do
    assert :ok = Storage.append(:logs, "acme", [%Log{timestamp_ns: 9_000_000_000, service: "api", body: "a"}])

    for time <- ["10000000000", "1970-01-01T00:00:10Z"] do
      response =
        conn
        |> put_req_header("x-scope-orgid", "acme")
        |> get("/loki/api/v1/query", %{"query" => ~s'count_over_time({service="api"}[5s])', "time" => time})
        |> json_response(200)

      assert [%{"value" => [10.0, "1"]}] = response["data"]["result"]
    end
  end

  test "short integer timestamps are Unix seconds and long integers are nanoseconds", %{conn: conn} do
    assert :ok =
             Storage.append(:logs, "acme", [%Log{timestamp_ns: 1_760_000_000_000_000_000, service: "api", body: "a"}])

    for time <- ["1760000000", "1760000000000000000"] do
      response =
        conn
        |> put_req_header("x-scope-orgid", "acme")
        |> get("/loki/api/v1/query", %{"query" => ~s'count_over_time({service="api"}[5s])', "time" => time})
        |> json_response(200)

      assert [%{"value" => [timestamp, "1"]}] = response["data"]["result"]
      assert timestamp == 1_760_000_000.0
    end
  end

  test "RFC3339 query bounds preserve the submicrosecond remainder", %{conn: conn} do
    assert :ok = Storage.append(:logs, "acme", [%Log{timestamp_ns: 10_000_000_005, service: "api", body: "a"}])

    response =
      conn
      |> put_req_header("x-scope-orgid", "acme")
      |> get("/loki/api/v1/query", %{
        "query" => ~s'count_over_time({service="api"}[5s])',
        "time" => "1970-01-01T00:00:10.000000009Z"
      })
      |> json_response(200)

    assert [%{"value" => [10.000000009, "1"]}] = response["data"]["result"]
  end

  test "malformed or overflowing supplied times fail, never turn into an unbounded scan", %{conn: conn} do
    for {name, value} <- [
          {"time", "invalid"},
          {"start", "invalid"},
          {"end", "9223372036854775808"},
          {"time", "9999-01-01T00:00:00Z"},
          {"time", "1970-01-01T00:00:10.000000009+0000"},
          {"time", String.duplicate("1", 129)}
        ] do
      response = conn |> get("/loki/api/v1/query", Map.put(%{"query" => "1"}, name, value)) |> json_response(400)
      assert response["error"] == "invalid_parameter"
    end
  end

  test "range defaults to the last hour and instant defaults to now", %{conn: conn} do
    now = System.system_time(:nanosecond)

    assert :ok =
             Storage.append(:logs, "acme", [
               %Log{timestamp_ns: now - 1_000_000_000, service: "api", body: "recent"},
               %Log{timestamp_ns: 10, service: "api", body: "old"}
             ])

    range =
      conn
      |> put_req_header("x-scope-orgid", "acme")
      |> get("/loki/api/v1/query_range", %{"query" => ~s'{service="api"}'})
      |> json_response(200)

    assert [%{"values" => [[_, "recent"]]}] = range["data"]["result"]

    instant =
      conn
      |> put_req_header("x-scope-orgid", "acme")
      |> get("/loki/api/v1/query", %{"query" => ~s'count_over_time({service="api"}[1m])'})
      |> json_response(200)

    assert [%{"value" => [_, "1"]}] = instant["data"]["result"]
  end

  describe "GET /loki/api/v1/query_range with a log query" do
    setup do
      :ok =
        Storage.append(:logs, "acme", [
          %Log{timestamp_ns: 10, service: "api", body: "connection timeout"},
          %Log{timestamp_ns: 20, service: "api", body: "connection ok"},
          %Log{timestamp_ns: 30, service: "db", body: "insert failed"}
        ])

      :ok
    end

    test "returns a Loki streams envelope", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-scope-orgid", "acme")
        |> get(~p"/loki/api/v1/query_range?query=#{"{service=\"api\"}"}&start=0&end=100")

      body = json_response(conn, 200)
      assert body["status"] == "success"
      assert body["data"]["resultType"] == "streams"
      streams = body["data"]["result"]
      lines = for %{"values" => vs} <- streams, [_ts, line] <- vs, do: line
      assert Enum.sort(lines) == ["connection ok", "connection timeout"]
    end

    test "applies line filters", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-scope-orgid", "acme")
        |> get(~p"/loki/api/v1/query_range?query=#{~s({service="api"} |= "timeout")}&start=0&end=100")

      body = json_response(conn, 200)
      streams = body["data"]["result"]
      lines = for %{"values" => vs} <- streams, [_ts, line] <- vs, do: line
      assert lines == ["connection timeout"]
    end

    test "rejects a missing query param", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-scope-orgid", "acme")
        |> get(~p"/loki/api/v1/query_range")

      body = json_response(conn, 400)
      assert body["status"] == "error"
      assert body["error"] == "missing_param"
    end

    test "rejects an unparseable query", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-scope-orgid", "acme")
        |> get(~p"/loki/api/v1/query_range?query=#{"not a query"}")

      body = json_response(conn, 400)
      assert body["error"] == "parse_error"
    end
  end

  describe "GET /loki/api/v1/query_range with a metric query" do
    test "returns a matrix envelope", %{conn: conn} do
      :ok =
        Storage.append(:logs, "acme", [
          %Log{timestamp_ns: 1_000_000_000, service: "api", body: "a"},
          %Log{timestamp_ns: 2_000_000_000, service: "api", body: "b"},
          %Log{timestamp_ns: 3_000_000_000, service: "api", body: "c"}
        ])

      query = "count_over_time({service=\"api\"}[1s])"

      conn =
        conn
        |> put_req_header("x-scope-orgid", "acme")
        |> get(~p"/loki/api/v1/query_range?query=#{query}&start=1&end=3&step=1")

      body = json_response(conn, 200)
      assert body["data"]["resultType"] == "matrix"
      assert [_series] = body["data"]["result"]
    end
  end

  describe "GET /loki/api/v1/labels" do
    test "returns unique label names for the tenant", %{conn: conn} do
      :ok =
        Storage.append(:logs, "acme", [
          %Log{
            timestamp_ns: 10,
            service: "api",
            body: "x",
            resource: %{"env" => "prod", "region" => "us"}
          }
        ])

      conn =
        conn
        |> put_req_header("x-scope-orgid", "acme")
        |> get(~p"/loki/api/v1/labels?start=0")

      body = json_response(conn, 200)
      assert body["status"] == "success"
      names = body["data"]
      assert "env" in names
      assert "region" in names
    end
  end

  describe "GET /loki/api/v1/label/:name/values" do
    test "returns unique values seen for the given label", %{conn: conn} do
      :ok =
        Storage.append(:logs, "acme", [
          %Log{timestamp_ns: 10, body: "x", resource: %{"env" => "prod"}},
          %Log{timestamp_ns: 20, body: "y", resource: %{"env" => "stg"}},
          %Log{timestamp_ns: 30, body: "z", resource: %{"env" => "prod"}}
        ])

      conn =
        conn
        |> put_req_header("x-scope-orgid", "acme")
        |> get(~p"/loki/api/v1/label/env/values?start=0")

      body = json_response(conn, 200)
      assert Enum.sort(body["data"]) == ["prod", "stg"]
    end
  end

  describe "input validation" do
    test "discovery and stats reject pipelines on GET and form POST", %{conn: conn} do
      for {path, key} <- [
            {"/loki/api/v1/labels", "query"},
            {"/loki/api/v1/label/job/values", "query"},
            {"/loki/api/v1/series", "match[]"},
            {"/loki/api/v1/index/stats", "query"}
          ],
          expression <- [~s({job="fake"} |= "search"), ~s({job="fake"} | logfmt)],
          method <- [:get, :post] do
        encoded = URI.encode_query([{key, expression}])

        response =
          case method do
            :get -> get(conn, path <> "?" <> encoded)
            :post -> conn |> put_req_header("content-type", "application/x-www-form-urlencoded") |> post(path, encoded)
          end
          |> json_response(400)

        assert response["message"] == "only label matchers are supported"
        refute Map.has_key?(response, "data")
      end
    end

    test "invalid regex returns 400 with a parse_error, not 500", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-scope-orgid", "acme")
        |> get(~p"/loki/api/v1/query_range?query=#{"{env=~\"(\"}"}")

      body = json_response(conn, 400)
      assert body["error"] in ["parse_error", "evaluation_failed"]
    end

    test "unparseable supplied limit rejects instead of silently using the default", %{conn: conn} do
      :ok = Storage.append(:logs, "acme", [%Log{timestamp_ns: 10, service: "api", body: "a"}])

      conn =
        conn
        |> put_req_header("x-scope-orgid", "acme")
        |> get(~p"/loki/api/v1/query_range?query=#{"{service=\"api\"}"}&limit=abc")

      body = json_response(conn, 400)
      assert body["error"] == "invalid_parameter"
    end

    test "RFC3339 timestamps parse instead of scanning the whole tenant", %{conn: conn} do
      :ok = Storage.append(:logs, "acme", [%Log{timestamp_ns: 10, service: "api", body: "a"}])

      conn =
        conn
        |> put_req_header("x-scope-orgid", "acme")
        |> get(~p"/loki/api/v1/labels?start=2024-01-01T00:00:00Z&end=2024-01-02T00:00:00Z")

      # No records fall in that window; the response is a well-formed
      # empty labels list, not a crash or a full-tenant scan.
      body = json_response(conn, 200)
      assert body["status"] == "success"
    end
  end

  describe "stream discovery" do
    setup do
      :ok =
        Storage.append(:logs, "streams", [
          %Log{timestamp_ns: 10, service: "api", body: "a", resource: %{"namespace" => "prod", "pod" => "api-1"}},
          %Log{timestamp_ns: 20, service: "api", body: "b", resource: %{"namespace" => "prod", "pod" => "api-1"}},
          %Log{timestamp_ns: 30, service: "gateway", body: "c", resource: %{"namespace" => "prod", "pod" => "api-gw"}},
          %Log{timestamp_ns: 40, body: "d", resource: %{"namespace" => "staging", "pod" => "web-1"}}
        ])

      :ok
    end

    defp discover(conn, path, params) do
      conn
      |> put_req_header("x-scope-orgid", "streams")
      |> get(path, Map.merge(%{"start" => "0", "end" => "100"}, params))
      |> json_response(200)
      |> Map.fetch!("data")
    end

    test "series returns each matching stream once", %{conn: conn} do
      assert discover(conn, "/loki/api/v1/series", %{"match" => [~s({namespace="prod"})]}) == [
               %{"namespace" => "prod", "pod" => "api-1", "service_name" => "api"},
               %{"namespace" => "prod", "pod" => "api-gw", "service_name" => "gateway"}
             ]
    end

    test "series unions repeated match[] selectors", %{conn: conn} do
      selectors = [~s({service_name="gateway"}), ~s({namespace="staging"})]

      assert discover(conn, "/loki/api/v1/series", %{"match" => selectors}) == [
               %{"namespace" => "prod", "pod" => "api-gw", "service_name" => "gateway"},
               %{"namespace" => "staging", "pod" => "web-1"}
             ]
    end

    test "series without a selector discovers all bounded streams", %{conn: conn} do
      assert discover(conn, "/loki/api/v1/series", %{}) == [
               %{"namespace" => "prod", "pod" => "api-1", "service_name" => "api"},
               %{"namespace" => "prod", "pod" => "api-gw", "service_name" => "gateway"},
               %{"namespace" => "staging", "pod" => "web-1"}
             ]
    end

    test "label values honor the query selector", %{conn: conn} do
      assert discover(conn, "/loki/api/v1/label/pod/values", %{"query" => ~s({namespace="prod"})}) == [
               "api-1",
               "api-gw"
             ]
    end

    test "regex matchers match whole label values, as in Loki", %{conn: conn} do
      assert discover(conn, "/loki/api/v1/label/pod/values", %{"query" => ~s({pod=~"api"})}) == []
      assert discover(conn, "/loki/api/v1/label/pod/values", %{"query" => ~s({pod=~"api-.*"})}) == ["api-1", "api-gw"]

      streams =
        conn
        |> put_req_header("x-scope-orgid", "streams")
        |> get("/loki/api/v1/query_range", %{"query" => ~s({pod=~"api"}), "start" => "0", "end" => "100"})
        |> json_response(200)

      assert streams["data"]["result"] == []
    end

    test "label filters and drop matchers are anchored too", %{conn: conn} do
      params = %{"query" => ~s({namespace="prod"} | pod=~"api"), "start" => "0", "end" => "100"}

      streams =
        conn
        |> put_req_header("x-scope-orgid", "streams")
        |> get("/loki/api/v1/query_range", params)
        |> json_response(200)

      assert streams["data"]["result"] == []
    end

    test "names accept a form-encoded POST like Grafana sends", %{conn: conn} do
      names =
        conn
        |> put_req_header("x-scope-orgid", "streams")
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post("/loki/api/v1/labels", "start=0&end=100&query=%7Bnamespace%3D%22staging%22%7D")
        |> json_response(200)

      assert names["data"] == ["namespace", "pod"]
    end

    test "an omitted range covers the last six hours", %{conn: conn} do
      now = System.system_time(:nanosecond)
      :ok = Storage.append(:logs, "recent", [%Log{timestamp_ns: now - 1_000, body: "x", resource: %{"fresh" => "yes"}}])

      names =
        conn
        |> put_req_header("x-scope-orgid", "recent")
        |> get("/loki/api/v1/labels")
        |> json_response(200)

      assert names["data"] == ["fresh"]
    end

    test "metric queries are not stream selectors", %{conn: conn} do
      assert conn
             |> put_req_header("x-scope-orgid", "streams")
             |> get("/loki/api/v1/series", %{"match" => ~s|count_over_time({namespace="prod"}[1m])|})
             |> json_response(400)
    end
  end

  describe "vector literals" do
    test "range default resolution follows the window and explicit steps win", %{conn: conn} do
      for {finish, step, expected_step} <- [
            {3600, nil, 14},
            {3600, "", 14},
            {100, nil, 1},
            {3600, "5", 5},
            {604_801, nil, 2419}
          ] do
        params = %{"query" => "vector(1)", "start" => "0", "end" => to_string(finish)}
        params = if step == nil, do: params, else: Map.put(params, "step", step)
        response = conn |> get("/loki/api/v1/query_range", params) |> json_response(200)
        assert response["data"]["resultType"] == "matrix"
        assert [%{"metric" => %{}, "values" => samples}] = response["data"]["result"]
        assert samples == for(timestamp <- 0..finish//expected_step, do: [timestamp, "1"])
      end
    end

    test "Grafana's Loki health check expression evaluates to 2", %{conn: conn} do
      result =
        conn
        |> get("/loki/api/v1/query", %{"query" => "vector(1)+vector(1)", "time" => "4000000000"})
        |> json_response(200)

      assert %{"resultType" => "vector", "result" => [%{"metric" => %{}, "value" => [4_000_000_000.0, "2"]}]} =
               result["data"]
    end

    test "vector(0) fills gaps for absent streams in range queries", %{conn: conn} do
      params = %{
        "query" => ~s|sum(count_over_time({app="none"}[1m])) or vector(0)|,
        "start" => "0",
        "end" => "120",
        "step" => "60"
      }

      result = conn |> get("/loki/api/v1/query_range", params) |> json_response(200)

      assert %{"resultType" => "matrix", "result" => [%{"metric" => %{}, "values" => values}]} = result["data"]
      assert Enum.all?(values, fn [_ts, value] -> value == "0" end)
    end
  end

  describe "limits" do
    setup do
      tenant = "limits-#{System.unique_integer([:positive])}"

      records =
        for {pod, times} <- [{"old", 1..5}, {"new", 6..10}], ts <- times do
          %Log{timestamp_ns: ts * 1_000_000_000, body: "#{pod} #{ts}", resource: %{"app" => "a", "pod" => pod}}
        end

      :ok = Storage.append(:logs, tenant, Enum.shuffle(records))
      {:ok, tenant: tenant}
    end

    defp lines(conn, tenant, direction) do
      conn
      |> put_req_header("x-scope-orgid", tenant)
      |> get("/loki/api/v1/query_range", %{
        "query" => ~s({app="a"}),
        "start" => "0",
        "end" => "100",
        "limit" => "3",
        "direction" => direction
      })
      |> json_response(200)
      |> get_in(["data", "result"])
      |> Enum.flat_map(fn stream -> Enum.map(stream["values"], &List.last/1) end)
    end

    test "backward returns the newest lines across every stream", %{conn: conn, tenant: tenant} do
      assert lines(conn, tenant, "backward") == ["new 10", "new 9", "new 8"]
    end

    test "forward returns the oldest lines across every stream", %{conn: conn, tenant: tenant} do
      assert lines(conn, tenant, "forward") == ["old 1", "old 2", "old 3"]
    end
  end
end
