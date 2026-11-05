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
          [{"limit", "1"}],
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

    assert %{"status" => "error", "errorType" => "execution"} =
             conn |> get("/api/v1/label/host/values") |> json_response(422)

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
