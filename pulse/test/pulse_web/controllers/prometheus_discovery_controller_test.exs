# Escaped-name cases adapted from Prometheus common v0.73.1 model/metric_test.go.
# Copyright 2013 The Prometheus Authors, Apache-2.0.
# Source/case mapping: test/fixtures/grafana/README.md.
defmodule PulseWeb.PrometheusDiscoveryControllerTest do
  use PulseWeb.ConnCase, async: true

  import Phoenix.VerifiedRoutes, only: []

  alias Pulse.Auth
  alias Pulse.Auth.Open
  alias Pulse.Auth.SharedSecret
  alias Pulse.MCP.Tools
  alias Pulse.Record.MetricSample
  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Test.BlockingMetricStorage

  setup do
    rows = [
      %MetricSample{
        timestamp_ns: 10_000_000_001,
        value: :stale,
        labels: %{"__name__" => "requests", "host" => "a", "env" => "prod"}
      },
      %MetricSample{
        timestamp_ns: 20_000_000_000,
        value: :nan,
        labels: %{"__name__" => "requests", "host" => "b", "env" => "dev"}
      },
      %MetricSample{
        timestamp_ns: 30_000_000_000,
        value: :infinity,
        labels: %{"__name__" => "latency", "host" => "b", "empty" => "", "unicode" => "µ\"\\\n"}
      }
    ]

    :ok = Storage.append(:metrics, "acme", rows ++ rows)

    :ok =
      Storage.append(:metrics, "other", [%MetricSample{timestamp_ns: 1, value: 1.0, labels: %{"secret" => "never"}}])

    %{conn: build_conn() |> put_req_header("x-scope-orgid", "acme"), rows: rows}
  end

  defp path(base, params), do: base <> "?" <> URI.encode_query(params)
  defp data(conn, path), do: conn |> get(path) |> json_response(200) |> Map.fetch!("data")

  test "names and values are complete sorted dictionaries, not instant vectors", %{conn: conn} do
    assert data(conn, "/api/v1/labels") == ["__name__", "env", "host", "unicode"]
    assert data(conn, "/api/v1/label/__name__/values") == ["latency", "requests"]
    assert data(conn, "/api/v1/label/host/values") == ["a", "b"]
    assert data(conn, "/api/v1/label/absent/values") == []
    assert data(conn, "/api/v1/label/empty/values") == []
    assert data(conn, "/api/v1/label/unicode/values") == ["µ\"\\\n"]
  end

  test "explicit result limits warn only when a complete dictionary is truncated", %{conn: conn} do
    for {route, selectors, expected} <- [
          {"/api/v1/labels", [], ["__name__", "env", "host", "unicode"]},
          {"/api/v1/label/host/values", [], ["a", "b"]},
          {"/api/v1/series", [{"match[]", "requests"}],
           [
             %{"__name__" => "requests", "env" => "dev", "host" => "b"},
             %{"__name__" => "requests", "env" => "prod", "host" => "a"}
           ]}
        ],
        method <- [:get, :post],
        limit <- ["", "0", "1", Integer.to_string(length(expected))] do
      params = URI.encode_query(selectors ++ [{"limit", limit}])

      response =
        case method do
          :get ->
            conn |> get(route <> "?" <> params) |> json_response(200)

          :post ->
            conn
            |> put_req_header("content-type", "application/x-www-form-urlencoded")
            |> post(route, params)
            |> json_response(200)
        end

      assert response["data"] == if(limit == "1", do: Enum.take(expected, 1), else: expected)
      assert Map.get(response, "warnings", []) == if(limit == "1", do: ["results truncated due to limit"], else: [])
    end

    for params <- [
          [{"limit", "-1"}],
          [{"limit", "1.5"}],
          [{"limit", "9223372036854775808"}],
          [{"limit", "1"}, {"limit", "2"}]
        ] do
      assert conn |> get(path("/api/v1/labels", params)) |> json_response(400)
    end
  end

  test "Grafana escaped label paths use upstream whole-name decoding", %{conn: conn} do
    # Grafana's utf8_support.test.ts and Prometheus common v0.73.1
    # TestValueUnescapeErrors table; see Grafana fixture provenance.
    cases = [
      {"no:escaping_required", "no:escaping_required"},
      {"U__mysystem_2e_prod_2e_west_2e_cpu_2e_load", "mysystem.prod.west.cpu.load"},
      {"U__mysystem_2e_prod_2e_west_2e_cpu_2e_load__total", "mysystem.prod.west.cpu.load_total"},
      {"U__http_2e_status:sum", "http.status:sum"},
      {"U__my_20_lovely__http_2e_status:sum", "my lovely_http.status:sum"},
      {"U___82b1__706b_", "花火"},
      {"U__label_20_with_20__1f631_", "label with 😱"},
      {"U__no:unescapingrequired", "no:unescapingrequired"},
      {"U__capitals_2E_ok", "capitals.ok"},
      {"U__underscores__doubled__", "underscores_doubled_"},
      {"U__underscores_doubled_", "U__underscores_doubled_"},
      {"U__underscores__doubled_", "U__underscores__doubled_"},
      {"U__my__hack_2e_attempt_872348732fabdabbab_", "U__my__hack_2e_attempt_872348732fabdabbab_"},
      {"U__my__hack_2e", "U__my__hack_2e"},
      {"U__bad__utf_2eg_", "U__bad__utf_2eg_"},
      {"U__bad__utf_D900_", "U__bad__utf_D900_"},
      # Local decoded-length, single-pass and pinned six-digit-policy controls.
      {"U__" <> String.duplicate("_00061_", 256), String.duplicate("a", 256)},
      {"U__U____http__2e__status:sum", "U__http_2e_status:sum"},
      {"U___10ffff_", "U___10ffff_"}
    ]

    labels = Map.new(Enum.with_index(cases), fn {{_, decoded}, i} -> {decoded, "value#{i}"} end)
    :ok = Storage.append(:metrics, "escaped", [%MetricSample{timestamp_ns: 10_000_000_000, value: 1.0, labels: labels}])
    conn = put_req_header(conn, "x-scope-orgid", "escaped")

    for {{encoded, _decoded}, i} <- Enum.with_index(cases), method <- [:get, :post] do
      route = "/api/v1/label/#{encoded}/values"
      params = URI.encode_query(start: "10", end: "10", limit: "40000")

      response =
        case method do
          :get ->
            conn |> get(route <> "?" <> params) |> json_response(200)

          :post ->
            conn
            |> put_req_header("content-type", "application/x-www-form-urlencoded")
            |> post(route, params)
            |> json_response(200)
        end

      assert response == %{"status" => "success", "data" => ["value#{i}"]}
    end

    oversized = "U__" <> String.duplicate("_00061_", 257)
    assert conn |> get("/api/v1/label/#{oversized}/values?limit=40000") |> json_response(400)
  end

  test "repeated selectors union branches and AND within a branch, deduplicating series", %{conn: conn, rows: rows} do
    selectors = [{"match[]", ~s(requests{env="prod"})}, {"match[]", ~s(latency{host=~"b"})}]
    result = data(conn, path("/api/v1/series", selectors))

    assert MapSet.new(result) ==
             MapSet.new(Enum.map([hd(rows), List.last(rows)], &Map.reject(&1.labels, fn {_, v} -> v == "" end)))

    assert data(conn, path("/api/v1/label/host/values", selectors)) == ["a", "b"]
    assert data(conn, path("/api/v1/label/host/values", [{"match[]", ~s(requests{host=~"a|b",env!="dev"})}])) == ["a"]
    assert data(conn, path("/api/v1/labels", [{"match[]", "missing"}])) == []
    assert data(conn, path("/api/v1/series", [{"match[]", "missing"}])) == []
    assert data(conn, path("/api/v1/label/host/values", [{"match[]", ~s({__name__=~"lat.*",env=""})}])) == ["b"]
    assert data(conn, path("/api/v1/label/host/values", [{"match[]", ~s(requests{host=~"a."})}])) == []
  end

  test "form POST merges selectors from query and body without dropping branches", %{conn: conn} do
    conn = put_req_header(conn, "content-type", "application/x-www-form-urlencoded")
    url = path("/api/v1/series", [{"match[]", ~s(requests{env="prod"})}])
    body = URI.encode_query([{"match[]", "latency"}])
    assert %{"data" => series} = conn |> post(url, body) |> json_response(200)
    assert Enum.sort(Enum.map(series, & &1["__name__"])) == ["latency", "requests"]

    for route <- ["/api/v1/labels", "/api/v1/label/host/values"] do
      assert %{"status" => "success"} =
               conn |> post(route, URI.encode_query([{"match[]", "requests"}])) |> json_response(200)
    end
  end

  test "time bounds are exact inclusive sample timestamps including RFC3339 nanoseconds", %{conn: conn} do
    for instant <- ["10.000000001", "10000000001e-9", "1970-01-01T00:00:10.000000001Z"] do
      assert data(conn, path("/api/v1/label/host/values", [{"start", instant}, {"end", instant}])) == ["a"]
    end

    assert data(conn, path("/api/v1/labels", [{"start", "10.000000002"}, {"end", "19.999999999"}])) == []
    assert data(conn, path("/api/v1/label/host/values", [{"end", "10.000000001"}])) == ["a"]
    assert data(conn, path("/api/v1/label/host/values", [{"start", "30"}])) == ["b"]
  end

  test "unsupported or malformed parameters never become unfiltered discovery", %{conn: conn} do
    for pairs <- [
          [{"match[]", ~s(requests{host=~"#{String.duplicate("a", 1025)}"})}],
          [{"match[]", ~s(requests{#{String.duplicate("a", 257)}="a"})}],
          [{"match[]", ~s(requests{host=~"[z-a]"})}],
          [{"match[]", "sum(requests)"}],
          [{"match[]", "requests[5m]"}],
          [{"match[]", ~s({host=~".*"})}],
          [{"match[]", "{"}],
          [{"match[]", ""}],
          [{"query", "requests"}],
          [{"start", "NaN"}],
          [{"start", "20"}, {"end", "10"}],
          [{"end", "1e300"}],
          [{"start", "10"}, {"start", "20"}],
          [{"timeout", "0s"}],
          [{"match", "requests"}],
          [{"start", "1970-01-01T00:00:10.0000000001Z"}]
        ] do
      assert %{"errorType" => "bad_data"} = conn |> get(path("/api/v1/labels", pairs)) |> json_response(400)
    end

    assert %{"errorType" => "bad_data"} = conn |> get("/api/v1/series") |> json_response(400)
    assert %{"errorType" => "bad_data"} = conn |> post("/api/v1/labels", %{match: ["requests"]}) |> json_response(415)
    # URI.decode tolerates malformed escapes on the pinned Elixir, as the
    # router does. The early gate must not introduce a global path crash.
    for path <- ["/anything/%zz", "/api/v1/label/%/values", "/api/v1/label/%2/values"] do
      request = Plug.Test.conn(:get, path)
      assert PulseWeb.PrometheusDiscoveryRequestGate.call(request, []) == request
    end

    form_conn = put_req_header(conn, "content-type", "application/x-www-form-urlencoded")
    assert form_conn |> post("/api/v1/labels", "start=10&start=20") |> json_response(400)

    for route <- ["/api/v1/labels/", "/api/v1/%6cabels", "/%61pi/v1/labels"] do
      assert form_conn |> post(route, "start=10&start=20") |> json_response(400)
      assert form_conn |> post(route, "match%5B%5D=" <> String.duplicate("x", 33_000)) |> json_response(413)
    end

    assert form_conn |> post("/api/v1/labels", "match%5B%5D=" <> String.duplicate("x", 33_000)) |> json_response(413)

    assert form_conn
           |> put_req_header("content-encoding", "gzip")
           |> post("/api/v1/labels", :zlib.gzip("match%5B%5D=requests"))
           |> json_response(415)

    body = "match%5B%5D=requests&start=20"

    assert %{"errorType" => "bad_data"} =
             conn
             |> put_req_header("content-type", "application/x-www-form-urlencoded")
             |> post("/api/v1/labels?start=10", body)
             |> json_response(400)
  end

  test "tenant auth precedes selector validation; explicit empty or duplicate tenant headers reject", %{conn: conn} do
    digest = "sha256$" <> Base.encode16(:crypto.hash(:sha256, "secret"), case: :lower)
    Runtime.put_env(:pulse, Auth, module: SharedSecret, tokens: %{"other" => digest})
    bad = conn |> put_req_header("authorization", "Bearer secret")

    for route <- ["/api/v1/labels", "/api/v1/label/host/values", "/api/v1/series"] do
      assert %{"errorType" => "unauthorized"} = bad |> get(route <> "?match%5B%5D=bad(") |> json_response(401)
    end

    Runtime.put_env(:pulse, Auth, module: Open)
    assert conn |> put_req_header("x-scope-orgid", "") |> get("/api/v1/labels") |> json_response(400)
    assert conn |> put_req_header("x-scope-orgid", "../other") |> get("/api/v1/labels") |> json_response(400)
    duplicate = %{conn | req_headers: [{"x-scope-orgid", "acme"}, {"x-scope-orgid", "other"}]}
    assert duplicate |> get("/api/v1/labels") |> json_response(400)
    default = build_conn()
    assert data(default, "/api/v1/labels") == []
  end

  test "MCP exposes the same complete dictionaries and rejects unsupported modes and truncation", %{rows: rows} do
    assert {:ok, [%{"text" => text}]} =
             Tools.call("discover_metrics", %{"tenant" => "acme", "mode" => "series", "selectors" => ["requests"]})

    assert MapSet.new(Pulse.JSON.decode!(text)["data"]) == MapSet.new(Enum.map(Enum.take(rows, 2), & &1.labels))

    for arguments <- [
          %{"mode" => "values"},
          %{"mode" => "series"},
          %{"mode" => "names", "limit" => 1},
          %{"mode" => "names", "selectors" => ["sum(requests)"]}
        ] do
      assert {:error, _} = Tools.call("discover_metrics", Map.put(arguments, "tenant", "acme"))
    end
  end

  test "dictionary overflow rejects the whole response and never returns 5000 sampled values", %{conn: conn} do
    rows =
      for n <- 1..5001,
          do: %MetricSample{timestamp_ns: 1, value: 1.0, labels: %{"__name__" => "wide", "host" => "h#{n}"}}

    :ok = Storage.append(:metrics, "wide", rows)
    conn = put_req_header(conn, "x-scope-orgid", "wide")

    for suffix <- ["", "?limit=1"] do
      assert %{"status" => "error", "errorType" => "execution"} =
               conn |> get("/api/v1/label/host/values" <> suffix) |> json_response(422)
    end

    assert data(conn, path("/api/v1/label/host/values", [{"match[]", ~s(wide{host="h1"})}])) == ["h1"]
  end

  test "storage failures, admission, crashes and deadlines do not become empty dictionaries", %{conn: conn} do
    Runtime.put_env(:pulse, Storage, adapter: BlockingMetricStorage)

    for {reason, status} <- [
          {:query_scan_limit, 422},
          {:query_overloaded, 429},
          {:query_execution_failed, 500},
          {:not_found, 503}
        ] do
      Runtime.put_env(:pulse, BlockingMetricStorage, {:error, reason})
      assert %{"status" => "error"} = conn |> get("/api/v1/labels") |> json_response(status)
    end

    Runtime.put_env(:pulse, BlockingMetricStorage, self())
    assert %{"errorType" => "timeout"} = conn |> get("/api/v1/labels?timeout=5ms") |> json_response(504)
  end
end
