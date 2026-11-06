defmodule PulseWeb.CompatControllerTest do
  use PulseWeb.ConnCase, async: true

  alias Pulse.Auth
  alias Pulse.Auth.SharedSecret
  alias Pulse.PromQL.Parser
  alias Pulse.Record.Log
  alias Pulse.Storage

  describe "datasource build information" do
    test "Prometheus, Loki and Tempo report the API versions they follow", %{conn: conn} do
      assert %{"status" => "success", "data" => %{"version" => "3.5.0"}} =
               conn |> get("/api/v1/status/buildinfo") |> json_response(200)

      assert %{"version" => "3.5.0", "revision" => "pulse-" <> _} =
               build_conn() |> get("/loki/api/v1/status/buildinfo") |> json_response(200)

      assert %{"version" => "2.9.0"} = build_conn() |> get("/api/status/buildinfo") |> json_response(200)
      assert build_conn() |> get("/api/echo") |> text_response(200) == "echo"
    end
  end

  describe "Prometheus metadata endpoints" do
    test "metadata and exemplars are empty rather than invented", %{conn: conn} do
      assert %{"status" => "success", "data" => %{}} = conn |> get("/api/v1/metadata") |> json_response(200)

      assert %{"status" => "success", "data" => []} =
               build_conn() |> post("/api/v1/query_exemplars", %{"query" => "up"}) |> json_response(200)
    end

    test "format_query formats the supported grammar over GET and form POST", %{conn: conn} do
      assert %{"data" => "sum(rate(up[5m]))"} =
               conn |> get("/api/v1/format_query", %{"query" => "sum(rate(up[5m]))"}) |> json_response(200)

      for {input, expected} <- [
            {"SUM ( rate ( up [300s] OFFSET 60s ) ) BY (job,instance)",
             "sum by (job, instance) (rate(up[5m] offset 1m))"},
            {"topk( 2,sum(up)without(instance))by(job)", "topk by (job) (2, sum without (instance) (up))"},
            {"sum by()(up)", "sum by () (up)"},
            {"sum without()(up)", "sum without () (up)"},
            {"up/ON(job)GROUP_LEFT(region)other", "up / on (job) group_left (region) other"},
            {"up ATAN2 ON(job) GROUP_LEFT(region) other", "up atan2 on (job) group_left (region) other"},
            {~s|sort_by_label_desc(year(up),"zone")|, ~s|sort_by_label_desc(year(up), "zone")|},
            {"up offset -60 @ END()", "up @ end() offset -1m"},
            {"sum_over_time(up[600] offset -.25 @ start())", "sum_over_time(up[10m] @ start() offset -250ms)"},
            {"sum_over_time(up[60:10] @ 1790000000.000000001)", "sum_over_time(up[1m:10s] @ 1790000000.000000001)"},
            {"sum_over_time(up[130: ])", "sum_over_time(up[2m10s:])"},
            {"up @ 0X_10 offset 1_0", "up @ 16 offset 10s"},
            {"sum_over_time(up[(0x10+1_4):])", "sum_over_time(up[(0x10 + 1_4):])"},
            {~s|sum by ('zone😀',) (up)|, ~s|sum by ("zone😀") (up)|},
            {~s|up + on ('zone😀',) group_left (`owner name`,) other|,
             ~s|up + on ("zone😀") group_left ("owner name") other|},
            {"sum_over_time(up[STEP()+1ms])", "sum_over_time(up[(step() + 1ms)])"},
            {"up offset -(RANGE()+2m)", "up offset (-(range() + 2m))"},
            {"vector(1h30m+2.5)", "vector(5400 + 2.5)"},
            {"up @ -0.000000001 offset -1e-9", "up @ -0.000000001 offset -0.000000001"},
            {"min_of( end()-start(),max_of(step(),range()))", "min_of(end() - start(), max_of(step(), range()))"},
            {"up>BOOL IGNORING(instance)GROUP_RIGHT other", "up > bool ignoring (instance) group_right other"},
            {"up/ON(job)GROUP_LEFT()other", "up / on (job) group_left () other"},
            {"up and ON() other or third unless fourth", "up and on () other or third unless fourth"},
            {"round( (up+2)*3,.25)", "round((up + 2) * 3, 0.25)"},
            {"up-(other-third)", "up - (other - third)"},
            {"(up^2)^3", "(up ^ 2) ^ 3"},
            {"up^(2^3)", "up ^ 2 ^ 3"},
            {"-(up+2)^2", "-((up + 2) ^ 2)"},
            {"(-up)^2", "(-up) ^ 2"},
            {"rate((up + other)[3600s:60s] offset 120s)", "rate((up + other)[1h:1m] offset 2m)"},
            {"up # remove this comment\n + 2", "up + 2"},
            {~S|{"metric😀","label😀"!='a',"with space"=~`a\..*`,x!~"b"}|,
             ~S|{__name__="metric😀","label😀"!="a","with space"=~"a\\..*",x!~"b"}|},
            {~S|label_replace(up,'dst','$1','src',`(a\b)`) |, ~S|label_replace(up, "dst", "$1", "src", "(a\\b)")|},
            {"vector(0x10+010+1_000)", "vector(16 + 8 + 1000)"},
            {"vector(-0.0)", "vector(-0)"},
            {"vector(NaN+Inf)", "vector(NaN + Inf)"},
            {"up offset 1w1d1h1m1s1ms", "up offset 8d1h1m1s1ms"}
          ] do
        for method <- [:get, :post] do
          response = format_query(input, method)
          assert response == %{"status" => "success", "data" => expected}, input
          assert format_query(expected, method) == response
          assert {:ok, parsed} = Parser.parse(input)
          assert Parser.parse(expected) === {:ok, parsed}
        end
      end
    end

    test "format_query preserves number boundaries, strings and every binary precedence" do
      for literal <- ["5e-324", "2.2250738585072014e-308", "1e-7", "1e20", "1.7976931348623157e308"],
          sign <- ["", "-"] do
        query = "vector(#{sign}#{literal})"
        %{"data" => formatted} = format_query(query)
        assert {:ok, parsed} = Parser.parse(query)
        assert Parser.parse(formatted) === {:ok, parsed}
        assert format_query(formatted)["data"] == formatted
      end

      for name <- ["NaN", "nan", "Inf", "iNF", "or", "sum", ":colon", "1leading", "with space", "😀"],
          suffix <- ["", ~s(,job="api")],
          range <- ["", " offset 1m"] do
        query = "{" <> Pulse.JSON.encode!(name) <> suffix <> "}" <> range
        %{"data" => formatted} = format_query(query)
        assert {:ok, parsed} = Parser.parse(query)
        assert Parser.parse(formatted) === {:ok, parsed}, inspect({query, formatted})
      end

      for value <- ["quote\" slash\\ newline\n\t\r", <<0, 1, 7, 8, 12, 11, 27, 127>>, "😀 café #{<<0x2028::utf8>>}"] do
        query = "up{job=" <> Pulse.JSON.encode!(value) <> "}"
        %{"data" => formatted} = format_query(query)
        assert {:ok, parsed} = Parser.parse(query)
        assert Parser.parse(formatted) === {:ok, parsed}
      end

      operators = ["+", "-", "*", "/", "%", "atan2", "^", "==", "!=", ">", "<", ">=", "<=", "and", "unless", "or"]

      for outer <- operators,
          inner <- operators,
          query <- ["(a #{inner} b) #{outer} c", "a #{outer} (b #{inner} c)"] do
        %{"data" => formatted} = format_query(query)
        assert {:ok, parsed} = Parser.parse(query)
        assert Parser.parse(formatted) === {:ok, parsed}, inspect({query, formatted})
        assert format_query(formatted)["data"] == formatted
      end
    end

    test "format_query rejects invalid and oversized queries instead of returning executable-looking text" do
      assert %{"errorType" => "bad_data"} =
               build_conn() |> get("/api/v1/format_query", %{"query" => "sum(("}) |> json_response(400)

      for method <- [:get, :post],
          query <- ["", "unknown(up)", "up @ time()", "sum by(job,job)(up)", String.duplicate(" ", 16_385) <> "up"] do
        assert %{"status" => "error", "errorType" => "bad_data"} = format_query(query, method, 400)
      end

      assert build_conn() |> get("/api/v1/format_query") |> json_response(400)

      for method <- [:get, :post] do
        assert format_query("up" <> String.duplicate(" ", 16_382), method)["data"] == "up"

        expanded = ~s(up{job=`#{String.duplicate(<<1>>, 3000)}`})
        assert {:ok, _} = Parser.parse(expanded)
        assert format_query(expanded, method, 400)["error"] == ":query_expression_limit"

        numeric = Enum.map_join(1..60, " + ", fn _ -> "vector(1e-308)" end)
        assert {:ok, _} = Parser.parse(numeric)
        assert format_query(numeric, method, 400)["error"] == ":query_expression_limit"
      end
    end

    test "format_query authenticates before parsing" do
      token = "formatter-secret"
      digest = "sha256$" <> Base.encode16(:crypto.hash(:sha256, token), case: :lower)
      Pulse.Runtime.put_env(:pulse, Auth, module: SharedSecret, tokens: %{"acme" => digest})

      assert %{"errorType" => "unauthorized"} = format_query("sum((", :get, 401)

      assert build_conn()
             |> put_req_header("authorization", "Basic " <> Base.encode64("acme:" <> token))
             |> get("/api/v1/format_query", %{"query" => "count(up)by(foo)"})
             |> json_response(200) == %{"status" => "success", "data" => "count by (foo) (up)"}
    end

    test "metadata requires the tenant's credentials", %{conn: conn} do
      token = "secret"
      digest = "sha256$" <> Base.encode16(:crypto.hash(:sha256, token), case: :lower)
      Pulse.Runtime.put_env(:pulse, Auth, module: SharedSecret, tokens: %{"acme" => digest})

      assert conn |> get("/api/v1/metadata") |> json_response(401)

      basic = "Basic " <> Base.encode64("acme:" <> token)

      assert %{"status" => "success"} =
               build_conn() |> put_req_header("authorization", basic) |> get("/api/v1/metadata") |> json_response(200)
    end
  end

  describe "Loki index endpoints" do
    setup do
      tenant = "index-#{System.unique_integer([:positive])}"

      :ok =
        Storage.append(:logs, tenant, [
          %Log{timestamp_ns: 10, service: "api", body: "12345", resource: %{"namespace" => "prod", "pod" => "a"}},
          %Log{timestamp_ns: 20, service: "api", body: "123", resource: %{"namespace" => "prod", "pod" => "b"}},
          %Log{timestamp_ns: 30, service: "web", body: "1", resource: %{"namespace" => "staging", "pod" => "c"}}
        ])

      {:ok, tenant: tenant}
    end

    test "index/stats estimates matching volume", %{conn: conn, tenant: tenant} do
      stats =
        conn
        |> put_req_header("x-scope-orgid", tenant)
        |> get("/loki/api/v1/index/stats", %{"query" => ~s({service_name="api"}), "start" => "0", "end" => "100"})
        |> json_response(200)

      assert %{"entries" => 2, "bytes" => 8, "streams" => 0} = stats
    end

    test "index/volume returns bytes per selector-label group, largest first", %{conn: conn, tenant: tenant} do
      params = %{"query" => ~s({namespace=~".+"}), "start" => "0", "end" => "100"}

      result =
        conn
        |> put_req_header("x-scope-orgid", tenant)
        |> get("/loki/api/v1/index/volume", params)
        |> json_response(200)

      assert result["data"]["resultType"] == "vector"

      assert Enum.map(result["data"]["result"], &{&1["metric"], List.last(&1["value"])}) == [
               {%{"namespace" => "prod"}, "8"},
               {%{"namespace" => "staging"}, "1"}
             ]
    end

    test "index/volume honors targetLabels and limit", %{conn: conn, tenant: tenant} do
      params = %{
        "query" => ~s({namespace="prod"}),
        "targetLabels" => "pod",
        "limit" => "1",
        "start" => "0",
        "end" => "100"
      }

      result =
        conn
        |> put_req_header("x-scope-orgid", tenant)
        |> get("/loki/api/v1/index/volume", params)
        |> json_response(200)

      assert [%{"metric" => %{"pod" => "a"}, "value" => [_, "5"]}] = result["data"]["result"]
    end

    test "index/volume_range returns a matrix", %{conn: conn, tenant: tenant} do
      params = %{"query" => ~s({namespace="prod"}), "start" => "0", "end" => "100", "step" => "1s"}

      result =
        conn
        |> put_req_header("x-scope-orgid", tenant)
        |> get("/loki/api/v1/index/volume_range", params)
        |> json_response(200)

      assert result["data"]["resultType"] == "matrix"
      assert [%{"metric" => %{"namespace" => "prod"}}] = result["data"]["result"]
    end

    test "volume rejects unsupported aggregation and invalid labels", %{conn: conn, tenant: tenant} do
      for extra <- [%{"aggregateBy" => "invalid"}, %{"targetLabels" => "service.name"}, %{"limit" => "0"}] do
        params = Map.merge(%{"query" => ~s({namespace="prod"}), "start" => "0", "end" => "100"}, extra)

        assert conn
               |> put_req_header("x-scope-orgid", tenant)
               |> get("/loki/api/v1/index/volume", params)
               |> json_response(400)
      end
    end
  end

  describe "ingest path aliases" do
    test "/otlp/v1/logs is Loki's and Grafana Cloud's OTLP path", %{conn: conn} do
      tenant = "otlp-alias-#{System.unique_integer([:positive])}"

      payload = %{
        "resourceLogs" => [
          %{
            "resource" => %{"attributes" => [%{"key" => "service.name", "value" => %{"stringValue" => "api"}}]},
            "scopeLogs" => [
              %{"logRecords" => [%{"timeUnixNano" => "1700000000000000000", "body" => %{"stringValue" => "hi"}}]}
            ]
          }
        ]
      }

      assert conn
             |> put_req_header("content-type", "application/json")
             |> put_req_header("x-scope-orgid", tenant)
             |> post("/otlp/v1/logs", Pulse.JSON.encode!(payload))
             |> json_response(200)

      assert {:ok, [%Log{service: "api", body: "hi"}]} = Storage.query(:logs, tenant)
    end

    test "Grafana Cloud and Mimir remote-write paths reach the remote-write receiver", %{conn: conn} do
      canonical = conn |> put_req_header("content-type", "text/plain") |> post("/api/v1/write", "x")

      for path <- ["/api/prom/push", "/api/v1/push"] do
        aliased = build_conn() |> put_req_header("content-type", "text/plain") |> post(path, "x")
        assert aliased.status == canonical.status
        assert aliased.resp_body == canonical.resp_body
      end
    end
  end

  defp format_query(query, method \\ :get, status \\ 200) do
    response =
      case method do
        :get ->
          get(build_conn(), "/api/v1/format_query", %{"query" => query})

        :post ->
          build_conn()
          |> put_req_header("content-type", "application/x-www-form-urlencoded")
          |> post("/api/v1/format_query", URI.encode_query(%{"query" => query}))
      end

    json_response(response, status)
  end
end
