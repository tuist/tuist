defmodule Tuist.MCP.Components.Tools.PulseToolsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.AccountToken
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Environment
  alias Tuist.MCP.Components.Tools.GetPulseAnalytics
  alias Tuist.MCP.Components.Tools.GetPulseTrace
  alias Tuist.MCP.Components.Tools.ListPulseLabels
  alias Tuist.MCP.Components.Tools.QueryPulse
  alias Tuist.MCP.Components.Tools.QueryPulseMetrics
  alias Tuist.MCP.Components.Tools.SearchPulseLogs
  alias Tuist.MCP.Components.Tools.SearchPulseTraces
  alias Tuist.Pulse
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture(creator: user)
    account = organization.account
    stub(Environment, :pulse_config, fn -> [account_id: account.id] end)
    stub(Tuist.FeatureFlags, :pulse_enabled?, fn _ -> true end)

    %{
      user: user,
      organization: organization,
      account: account,
      conn: %Plug.Conn{assigns: %{current_user: user}},
      args: %{"account_handle" => account.name, "signal" => "logs"}
    }
  end

  defp result do
    %{
      rows: [
        %{"timestamp" => "123", "service" => "server", "level" => "error", "message" => "timeout", "trace_id" => "abc"}
      ],
      series: [],
      warnings: [],
      meta: %{
        "page" => 2,
        "page_size" => 1,
        "total_count" => 3,
        "total_pages" => 3,
        "end_at" => "2026-10-01T12:00:00Z",
        "has_next_page" => true,
        "has_previous_page" => true
      }
    }
  end

  test "passes table arguments unchanged and validates nonempty structured content", ctx do
    params = %{
      "page" => 2,
      "page_size" => 1,
      "sort_by" => "service",
      "sort_order" => "asc",
      "search" => "time",
      "service" => "server",
      "end_at" => "2026-10-01T12:00:00Z"
    }

    expect(Pulse, :query, fn user, account, "logs", ^params ->
      assert user.id == ctx.user.id
      assert account.id == ctx.account.id
      {:ok, result()}
    end)

    assert %{"structuredContent" => %{"rows" => [%{"message" => "timeout"}], "meta" => %{"page" => 2}}} =
             QueryPulse.call(ctx.conn, Map.merge(ctx.args, params))
  end

  test "rejects invalid inputs and analytics table parameters before reads", ctx do
    reject(&Pulse.query/4)
    reject(&Pulse.analytics/4)

    for params <- [
          %{"page" => 0},
          %{"page_size" => 101},
          %{"page" => "2"},
          %{"sort_order" => "other"},
          %{"tenant" => "other"}
        ] do
      assert %{"isError" => true} = QueryPulse.call(ctx.conn, Map.merge(ctx.args, params))
    end

    assert %{"isError" => true} = GetPulseAnalytics.call(ctx.conn, Map.put(ctx.args, "query", "up"))
  end

  test "analytics forwards only supplied range and preserves null measurements", ctx do
    expect(Pulse, :analytics, fn _, _, "logs", %{"range" => "6h"} ->
      {:ok,
       %{
         widgets: [%{id: "entries", unit: :count, value: 0, previous_value: nil, points: [[123, nil], [124, 0]]}],
         warnings: []
       }}
    end)

    assert %{"structuredContent" => %{"widgets" => [%{"previous_value" => nil, "value" => 0}]}} =
             GetPulseAnalytics.call(ctx.conn, Map.put(ctx.args, "range", "6h"))
  end

  test "membership is persisted, rechecked after removal and independent of public visibility", ctx do
    {:ok, _account} = Accounts.update_account(ctx.account, %{visibility: :public})
    member = AccountsFixtures.user_fixture()
    :ok = Accounts.add_user_to_organization(member, ctx.organization, role: :viewer)
    conn = %Plug.Conn{assigns: %{current_user: member}}
    stub(Pulse, :query, fn _, _, _, _ -> {:ok, result()} end)
    assert %{"structuredContent" => _} = QueryPulse.call(conn, ctx.args)
    Accounts.remove_user_from_organization(member, ctx.organization)
    assert %{"isError" => true} = QueryPulse.call(conn, ctx.args)
    outsider = AccountsFixtures.user_fixture()
    assert %{"isError" => true} = QueryPulse.call(%Plug.Conn{assigns: %{current_user: outsider}}, ctx.args)
  end

  test "WebMCP account scope and configured organization remain mandatory", ctx do
    reject(&Pulse.query/4)
    conn = %{ctx.conn | assigns: Map.put(ctx.conn.assigns, :mcp_account_scope, %{id: ctx.account.id + 1})}
    assert %{"isError" => true} = QueryPulse.call(conn, ctx.args)
    stub(Environment, :pulse_config, fn -> [account_id: ctx.account.id + 1] end)
    assert %{"isError" => true} = QueryPulse.call(ctx.conn, ctx.args)
  end

  test "associated users cannot upgrade under-scoped or userless account credentials", ctx do
    reject(&Pulse.query/4)

    for scopes <- [[], ["project:builds:read"], ["account:read"]] do
      subject = %AuthenticatedAccount{account: ctx.account, scopes: scopes}
      conn = %{ctx.conn | assigns: Map.put(ctx.conn.assigns, :current_subject, subject)}
      assert %{"isError" => true} = QueryPulse.call(conn, ctx.args)
    end

    subject = %AuthenticatedAccount{account: ctx.account, scopes: [AccountToken.mcp_scope()]}
    assert %{"isError" => true} = QueryPulse.call(%Plug.Conn{assigns: %{current_subject: subject}}, ctx.args)
  end

  test "user-associated MCP credentials retain the framework's account read policy", ctx do
    subject = %AuthenticatedAccount{account: ctx.user.account, scopes: [AccountToken.mcp_scope()], issued_by: ctx.user}
    conn = %{ctx.conn | assigns: Map.put(ctx.conn.assigns, :current_subject, subject)}
    expect(Pulse, :query, fn _, _, _, _ -> {:ok, result()} end)
    assert %{"structuredContent" => _} = QueryPulse.call(conn, ctx.args)
  end

  test "domain errors become safe tool errors", ctx do
    for reason <- [
          :invalid_params,
          :invalid_query,
          :query_result_limit,
          :forbidden,
          :not_configured,
          :rate_limited,
          :upstream_error,
          :malformed_response,
          :timeout
        ] do
      stub(Pulse, :query, fn _, _, _, _ -> {:error, reason} end)
      assert %{"isError" => true, "content" => [%{"text" => text}]} = QueryPulse.call(ctx.conn, ctx.args)
      refute text =~ "secret"
    end
  end

  describe "exploration tools" do
    @now ~U[2026-11-06 12:00:00Z]
    @finish 1_793_966_400
    @trace_columns [
      ["timestamp", "timestamp(9)"],
      ["timestamp_end", "timestamp(9)"],
      ["duration_nano", "bigint"],
      ["trace_id", "string"],
      ["span_id", "string"],
      ["parent_span_id", "string"],
      ["service_name", "string"],
      ["span_name", "string"],
      ["span_kind", "string"],
      ["span_status_code", "string"],
      ["span_status_message", "string"],
      ["scope_name", "string"],
      ["span_events", "json"],
      ["span_links", "json"],
      ["span_attributes.http.route", "string"],
      ["span_attributes.http.response.status_code", "bigint"],
      ["resource_attributes.k8s.pod.name", "string"]
    ]
    # Instrumented apps choose attribute names, which become columns.
    @unsafe_column ~s|span_attributes.x" OR 1=1 --|
    # The logs table written by the Loki pipeline; OTLP log writes add span_id and scope_name.
    @loki_log_columns [
      ["timestamp", "timestamp(9)"],
      ["body", "string"],
      ["severity_text", "string"],
      ["trace_id", "string"],
      ["resource_attributes", "json"],
      ["log_attributes", "json"]
    ]
    @otlp_log_columns @loki_log_columns ++ [["span_id", "string"], ["scope_name", "string"]]

    setup ctx do
      config = [account_id: ctx.account.id, base_url: "https://pulse.internal", tenant: "public", token: "secret"]
      stub(Environment, :pulse_config, fn -> config end)
      stub(DateTime, :utc_now, fn -> @now end)
      %{args: %{"account_handle" => ctx.account.name}}
    end

    defp calls do
      [
        {QueryPulseMetrics, %{"query" => "up"}},
        {ListPulseLabels, %{"signal" => "logs"}},
        {SearchPulseLogs, %{}},
        {SearchPulseTraces, %{}},
        {GetPulseTrace, %{"trace_id" => "abc"}}
      ]
    end

    defp sql_response(columns, rows) do
      columns = Enum.map(columns, &%{"name" => &1})

      {:ok,
       %Req.Response{
         status: 200,
         body: %{"output" => [%{"records" => %{"schema" => %{"column_schemas" => columns}, "rows" => rows}}]}
       }}
    end

    # Answers the schema lookups and hands every other statement to `fun`.
    defp stub_sql(fun, log_columns \\ @otlp_log_columns) do
      stub(Req, :request, fn request ->
        assert request.url.path == "/v1/sql"
        sql = request.options.params[:sql]

        cond do
          sql =~ "information_schema.columns" and sql =~ "table_name = 'opentelemetry_traces'" ->
            assert sql =~ "table_schema = database()"
            sql_response(~w(column_name data_type), @trace_columns ++ [[@unsafe_column, "string"]])

          sql =~ "information_schema.columns" and sql =~ "table_name = 'opentelemetry_logs'" ->
            assert sql =~ "table_schema = database()"
            sql_response(~w(column_name data_type), log_columns)

          true ->
            fun.(sql)
        end
      end)
    end

    defp bounds(seconds),
      do: "timestamp > to_timestamp_seconds(#{@finish - seconds}) AND timestamp <= to_timestamp_seconds(#{@finish})"

    test "every tool requires the configured account, its flag and current membership before any read", ctx do
      reject(&Req.request/1)
      outsider = %Plug.Conn{assigns: %{current_user: AccountsFixtures.user_fixture()}}

      for {tool, args} <- calls() do
        args = Map.merge(ctx.args, args)
        assert %{"isError" => true} = tool.call(outsider, args)
      end

      stub(Tuist.FeatureFlags, :pulse_enabled?, fn _ -> false end)

      for {tool, args} <- calls() do
        assert %{"isError" => true} = tool.call(ctx.conn, Map.merge(ctx.args, args))
      end

      # A member of another organization cannot read the configured account's telemetry through its own handle.
      other = AccountsFixtures.organization_fixture(creator: ctx.user).account
      stub(Tuist.FeatureFlags, :pulse_enabled?, fn _ -> true end)

      for {tool, args} <- calls() do
        assert %{"isError" => true} = tool.call(ctx.conn, Map.put(args, "account_handle", other.name))
      end
    end

    test "range metrics default to at most 361 points and return labelled series", ctx do
      expect(Req, :request, fn request ->
        assert request.url.path == "/v1/prometheus/api/v1/query_range"
        assert request.options.params == [query: "sum by (job) (up)", start: @finish - 86_400, end: @finish, step: 240]

        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "status" => "success",
             "data" => %{
               "resultType" => "matrix",
               "result" => [%{"metric" => %{"job" => "tuist"}, "values" => [[@finish - 240, "1"], [@finish, "NaN"]]}]
             }
           }
         }}
      end)

      assert %{"structuredContent" => content} =
               QueryPulseMetrics.call(
                 ctx.conn,
                 Map.merge(ctx.args, %{"query" => "sum by (job) (up)", "type" => "range", "range" => "24h"})
               )

      assert content["step"] == 240
      assert content["start_at"] == "2026-11-05T12:00:00Z"

      assert content["series"] == [
               %{
                 "name" => "{job=tuist}",
                 "labels" => %{"job" => "tuist"},
                 "points" => [[@finish - 240, 1.0], [@finish, "NaN"]]
               }
             ]
    end

    test "metric steps finer than 361 points and instant steps are rejected before reads", ctx do
      reject(&Req.request/1)

      for args <- [
            %{"type" => "range", "range" => "24h", "step" => 239},
            %{"type" => "range", "range" => "1h", "step" => 3601},
            %{"type" => "instant", "step" => 60},
            %{"query" => " "}
          ] do
        assert %{"isError" => true} =
                 QueryPulseMetrics.call(ctx.conn, Map.merge(ctx.args, Map.merge(%{"query" => "up"}, args)))
      end
    end

    test "instant metrics evaluate at an explicit end_at and explain rejected windows", ctx do
      expect(Req, :request, fn request ->
        assert request.url.path == "/v1/prometheus/api/v1/query"
        assert request.options.params == [query: "up", time: @finish - 7200]

        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "status" => "success",
             "data" => %{
               "resultType" => "vector",
               "result" => [%{"metric" => %{"__name__" => "up"}, "value" => [@finish - 7200, "3"]}]
             }
           }
         }}
      end)

      assert %{"structuredContent" => content} =
               QueryPulseMetrics.call(
                 ctx.conn,
                 Map.merge(ctx.args, %{"query" => "up", "end_at" => "2026-11-06T11:00:00+01:00"})
               )

      assert content["type"] == "instant"
      assert content["start_at"] == "2026-11-06T10:00:00Z"
      assert content["end_at"] == "2026-11-06T10:00:00Z"

      assert content["series"] == [
               %{"name" => "up", "labels" => %{"__name__" => "up"}, "points" => [[@finish - 7200, 3.0]]}
             ]

      reject(&Req.request/1)

      assert %{"isError" => true, "content" => [%{"text" => text}]} =
               QueryPulseMetrics.call(ctx.conn, Map.merge(ctx.args, %{"query" => "up", "range" => "1h"}))

      assert text =~ "apply only to type range"

      for end_at <- ["yesterday", "1970-01-01T00:30:00Z", "2262-04-12T00:00:00Z"] do
        assert %{"isError" => true} =
                 QueryPulseMetrics.call(ctx.conn, Map.merge(ctx.args, %{"query" => "up", "end_at" => end_at}))
      end
    end

    test "metric label names use the labels endpoint over the window", ctx do
      expect(Req, :request, fn request ->
        assert request.url.path == "/v1/prometheus/api/v1/labels"
        assert request.options.params == [start: @finish - 900, end: @finish]
        {:ok, %Req.Response{status: 200, body: %{"status" => "success", "data" => ["job", "__name__", "namespace"]}}}
      end)

      assert %{"structuredContent" => %{"label" => nil, "values" => values, "truncated" => false}} =
               ListPulseLabels.call(ctx.conn, Map.merge(ctx.args, %{"signal" => "metrics", "range" => "15m"}))

      assert Enum.map(values, & &1["value"]) == ~w(__name__ job namespace)
    end

    test "metric label values need a selector and a Prometheus label name", ctx do
      reject(&Req.request/1)

      assert %{"isError" => true, "content" => [%{"text" => text}]} =
               ListPulseLabels.call(ctx.conn, Map.merge(ctx.args, %{"signal" => "metrics", "label" => "job"}))

      assert text =~ "requires match"

      for label <- ["../query", "job/values", "a b"] do
        assert %{"isError" => true} =
                 ListPulseLabels.call(
                   ctx.conn,
                   Map.merge(ctx.args, %{"signal" => "metrics", "label" => label, "match" => "up"})
                 )
      end
    end

    test "metric label values are filtered, sorted and limited", ctx do
      expect(Req, :request, fn request ->
        assert request.url.path == "/v1/prometheus/api/v1/label/job/values"
        assert request.options.params == [{"match[]", "up"}, start: @finish - 3600, end: @finish]

        {:ok,
         %Req.Response{status: 200, body: %{"status" => "success", "data" => ["tuist", "kura", "kubelet", "tuist-cnpg"]}}}
      end)

      assert %{"structuredContent" => content} =
               ListPulseLabels.call(
                 ctx.conn,
                 Map.merge(ctx.args, %{
                   "signal" => "metrics",
                   "label" => "job",
                   "match" => "up",
                   "search" => "TUIST",
                   "limit" => 1
                 })
               )

      assert content["values"] == [%{"value" => "tuist", "count" => nil}]
      assert content["truncated"]
    end

    test "log label names merge fixed columns with resource and log attribute keys", ctx do
      stub_sql(fn sql ->
        cond do
          sql =~ "json_to_string(resource_attributes)" ->
            sql_response(["attributes"], [
              [~s|{"namespace":"tuist","service.name":"tuist","bad key":"x","q\\"x":"y"}|],
              [nil]
            ])

          sql =~ "json_to_string(log_attributes)" ->
            sql_response(["attributes"], [[~s|{"pod":"server-0"}|]])
        end
      end)

      assert %{"structuredContent" => %{"values" => values, "truncated" => false}} =
               ListPulseLabels.call(ctx.conn, Map.put(ctx.args, "signal", "logs"))

      assert Enum.map(values, & &1["value"]) ==
               ~w(namespace pod scope_name service.name severity_text span_id trace_id)
    end

    test "log label values count entries and address attributes through escaped literals", ctx do
      stub_sql(fn sql ->
        path = ~s|'["namespace"]'|

        assert sql ==
                 "SELECT coalesce(json_get_string(resource_attributes, #{path}), json_get_string(log_attributes, #{path})) AS value, " <>
                   "count(*) AS count FROM opentelemetry_logs WHERE #{bounds(3600)} " <>
                   "AND severity_text = 'it''s' GROUP BY value ORDER BY count DESC, value ASC LIMIT 3"

        sql_response(~w(value count), [["tuist", 9], ["kura", 4], [nil, 1]])
      end)

      assert %{"structuredContent" => %{"values" => values, "truncated" => true}} =
               ListPulseLabels.call(
                 ctx.conn,
                 Map.merge(ctx.args, %{
                   "signal" => "logs",
                   "label" => "namespace",
                   "limit" => 2,
                   "filters" => [%{"label" => "severity_text", "value" => "it's"}]
                 })
               )

      assert values == [%{"value" => "tuist", "count" => 9}, %{"value" => "kura", "count" => 4}]
    end

    test "log search pushes every filter into SQL and merges attributes with resource precedence", ctx do
      stub_sql(fn sql ->
        pod = ~s|'["pod"]'|

        assert sql ==
                 "SELECT arrow_cast(timestamp, 'Int64') AS timestamp, body, severity_text, scope_name, trace_id, span_id, " <>
                   "json_to_string(resource_attributes) AS resource_attributes, json_to_string(log_attributes) AS log_attributes " <>
                   "FROM opentelemetry_logs WHERE #{bounds(900)}" <>
                   " AND (coalesce(json_get_string(resource_attributes, #{pod}), json_get_string(log_attributes, #{pod})) IS NULL" <>
                   " OR strpos(lower(coalesce(json_get_string(resource_attributes, #{pod}), json_get_string(log_attributes, #{pod}))), lower('x'' OR 1=1 --')) = 0)" <>
                   " AND strpos(lower(body), lower('time''out')) > 0 ORDER BY timestamp ASC LIMIT 2"

        sql_response(
          ~w(timestamp severity_text body trace_id span_id scope_name resource_attributes log_attributes),
          [
            [
              1_793_966_000_000_000_001,
              "ERROR",
              "timeout",
              nil,
              nil,
              nil,
              ~s|{"pod":"resource","port":8080}|,
              ~s|{"pod":"log","stream":"stderr"}|
            ],
            [1_793_966_000_000_000_002, "ERROR", "timeout", nil, nil, nil, nil, nil]
          ]
        )
      end)

      assert %{"structuredContent" => %{"rows" => [row], "truncated" => true}} =
               SearchPulseLogs.call(
                 ctx.conn,
                 Map.merge(ctx.args, %{
                   "range" => "15m",
                   "text" => "time'out",
                   "order" => "oldest",
                   "limit" => 1,
                   "filters" => [%{"label" => "pod", "op" => "not_contains", "value" => "x' OR 1=1 --"}]
                 })
               )

      assert row["timestamp"] == "1793966000000000001"
      assert row["attributes"] == %{"pod" => "resource", "port" => "8080", "stream" => "stderr"}
    end

    test "logs written only by the Loki pipeline lack span_id and scope_name", ctx do
      stub_sql(
        fn sql ->
          cond do
            sql =~ "json_to_string(resource_attributes) AS attributes" ->
              sql_response(["attributes"], [[~s|{"namespace":"tuist"}|]])

            sql =~ "json_to_string(log_attributes) AS attributes" ->
              sql_response(["attributes"], [])

            true ->
              path = ~s|'["span_id"]'|

              assert sql ==
                       "SELECT arrow_cast(timestamp, 'Int64') AS timestamp, body, severity_text, trace_id, " <>
                         "json_to_string(resource_attributes) AS resource_attributes, json_to_string(log_attributes) AS log_attributes " <>
                         "FROM opentelemetry_logs WHERE #{bounds(3600)}" <>
                         " AND coalesce(json_get_string(resource_attributes, #{path}), json_get_string(log_attributes, #{path})) = 'a1'" <>
                         " ORDER BY timestamp DESC LIMIT 51"

              sql_response(
                ~w(timestamp body severity_text trace_id resource_attributes log_attributes),
                [[1_793_966_000_000_000_001, "timeout", "ERROR", "t1", ~s|{"namespace":"tuist"}|, nil]]
              )
          end
        end,
        @loki_log_columns
      )

      assert %{"structuredContent" => %{"rows" => [row]}} =
               SearchPulseLogs.call(
                 ctx.conn,
                 Map.put(ctx.args, "filters", [%{"label" => "span_id", "value" => "a1"}])
               )

      assert %{"span_id" => nil, "scope_name" => nil, "severity_text" => "ERROR", "trace_id" => "t1"} = row

      assert %{"structuredContent" => %{"values" => values}} =
               ListPulseLabels.call(ctx.conn, Map.put(ctx.args, "signal", "logs"))

      assert Enum.map(values, & &1["value"]) == ~w(namespace severity_text trace_id)
    end

    test "labels that could escape a JSON path or identifier are rejected before reads", ctx do
      reject(&Req.request/1)

      for label <- [~s|pod"]|, "pod'", "service_name\" OR 1=1 --", " pod"] do
        filters = [%{"label" => label, "value" => "x"}]
        assert %{"isError" => true} = SearchPulseLogs.call(ctx.conn, Map.put(ctx.args, "filters", filters))
        assert %{"isError" => true} = SearchPulseTraces.call(ctx.conn, Map.put(ctx.args, "filters", filters))
      end

      assert %{"isError" => true} = GetPulseTrace.call(ctx.conn, Map.put(ctx.args, "trace_id", "abc' OR '1'='1"))
    end

    test "trace labels must be existing scalar trace columns", ctx do
      stub_sql(fn _sql -> flunk("no data query for an unknown label") end)

      for label <- ["span_attributes.missing", "span_events", "timestamp"] do
        assert %{"isError" => true, "content" => [%{"text" => text}]} =
                 SearchPulseTraces.call(ctx.conn, Map.put(ctx.args, "filters", [%{"label" => label, "value" => "x"}]))

        assert text =~ "Unknown Pulse trace label"
      end
    end

    test "span search casts non-string columns and bounds duration, roots and order", ctx do
      stub_sql(fn sql ->
        assert sql =~ "FROM opentelemetry_traces WHERE #{bounds(3600)}"
        assert sql =~ ~s| AND "service_name" = 'tuist-server'|
        assert sql =~ ~s| AND CAST("span_attributes.http.response.status_code" AS STRING) = '500'|

        assert sql =~
                 " AND duration_nano >= 1500000 AND duration_nano <= 2500000" <>
                   " AND (parent_span_id IS NULL OR parent_span_id = '') " <>
                   "ORDER BY duration_nano DESC, timestamp DESC, span_id ASC LIMIT 51"

        sql_response(
          ~w(timestamp trace_id span_id parent_span_id service_name span_name span_kind span_status_code span_status_message scope_name duration_ms),
          [
            [
              1_793_966_000_000_000_001,
              "abc",
              "s1",
              nil,
              "tuist-server",
              "GET /",
              "SPAN_KIND_SERVER",
              "STATUS_CODE_ERROR",
              "",
              nil,
              12.5
            ]
          ]
        )
      end)

      assert %{"structuredContent" => %{"rows" => [row], "truncated" => false}} =
               SearchPulseTraces.call(
                 ctx.conn,
                 Map.merge(ctx.args, %{
                   "filters" => [
                     %{"label" => "service_name", "value" => "tuist-server"},
                     %{"label" => "span_attributes.http.response.status_code", "value" => "500"}
                   ],
                   "min_duration_ms" => 1.5,
                   "max_duration_ms" => 2.5,
                   "root_only" => true,
                   "order" => "slowest"
                 })
               )

      assert row["timestamp"] == "1793966000000000001"
      assert row["duration_ms"] == 12.5
    end

    test "trace label names list scalar columns with safe names and take no filters", ctx do
      stub_sql(fn _sql -> flunk("label names come from the schema alone") end)

      assert %{"structuredContent" => %{"values" => values}} =
               ListPulseLabels.call(ctx.conn, Map.merge(ctx.args, %{"signal" => "traces", "limit" => 1000}))

      names = Enum.map(values, & &1["value"])
      assert "span_attributes.http.response.status_code" in names
      assert "service_name" in names
      refute @unsafe_column in names
      refute Enum.any?(~w(timestamp timestamp_end span_events span_links), &(&1 in names))

      assert %{"isError" => true} =
               ListPulseLabels.call(
                 ctx.conn,
                 Map.merge(ctx.args, %{
                   "signal" => "traces",
                   "filters" => [%{"label" => "service_name", "value" => "kura"}]
                 })
               )
    end

    test "trace label values count casted column values within filters", ctx do
      stub_sql(fn sql ->
        status = ~s|CAST("span_attributes.http.response.status_code" AS STRING)|

        assert sql ==
                 "SELECT #{status} AS value, count(*) AS count FROM opentelemetry_traces WHERE #{bounds(21_600)}" <>
                   ~s| AND ("service_name" IS NULL OR "service_name" <> 'kura')| <>
                   " AND strpos(lower(#{status}), lower('5')) > 0 GROUP BY value ORDER BY count DESC, value ASC LIMIT 101"

        sql_response(~w(value count), [["500", 7], ["503", 2]])
      end)

      assert %{"structuredContent" => %{"label" => label, "values" => values, "truncated" => false}} =
               ListPulseLabels.call(
                 ctx.conn,
                 Map.merge(ctx.args, %{
                   "signal" => "traces",
                   "label" => "span_attributes.http.response.status_code",
                   "range" => "6h",
                   "search" => "5",
                   "filters" => [%{"label" => "service_name", "op" => "neq", "value" => "kura"}]
                 })
               )

      assert label == "span_attributes.http.response.status_code"
      assert values == [%{"value" => "500", "count" => 7}, %{"value" => "503", "count" => 2}]
    end

    test "a trace with more than 1000 spans returns the first 1000 and says it is truncated", ctx do
      stub_sql(fn _sql ->
        sql_response(
          ~w(timestamp trace_id span_id),
          Enum.map(1..1001, &[1_793_966_000_000_000_000 + &1, "abc", "s#{&1}"])
        )
      end)

      assert %{"structuredContent" => %{"spans" => spans, "truncated" => true}} =
               GetPulseTrace.call(ctx.conn, Map.put(ctx.args, "trace_id", "abc"))

      assert length(spans) == 1000
      assert List.last(spans)["span_id"] == "s1000"
    end

    test "a trace loads its spans over 24 hours by default with non-empty attributes", ctx do
      stub_sql(fn sql ->
        assert sql =~ ~s|SELECT arrow_cast("timestamp", 'Int64') AS "timestamp", |
        assert sql =~ ~s|json_to_string("span_events") AS "span_events"|
        assert sql =~ "WHERE #{bounds(86_400)} AND trace_id = 'abc' ORDER BY timestamp ASC, span_id ASC LIMIT 1001"
        refute sql =~ "OR 1=1"

        sql_response(
          Enum.map(@trace_columns, &hd/1),
          [
            [
              1_793_966_000_000_000_001,
              1_793_966_000_002_000_001,
              2_000_000,
              "abc",
              "s1",
              nil,
              "tuist-server",
              "GET /",
              "SPAN_KIND_SERVER",
              "STATUS_CODE_UNSET",
              "",
              "opentelemetry_bandit",
              ~s|[{"name":"exception"}]|,
              "[]",
              "",
              200,
              "server-0"
            ],
            [
              1_793_966_000_000_000_002,
              nil,
              nil,
              "abc",
              "s2",
              "s1",
              "tuist-server",
              "SELECT",
              nil,
              nil,
              nil,
              nil,
              nil,
              nil,
              nil,
              nil,
              "server-0"
            ],
            [
              1_793_966_000_000_000_003,
              nil,
              nil,
              "abc",
              "s3",
              "s1",
              "kura",
              "GET",
              nil,
              nil,
              nil,
              nil,
              nil,
              nil,
              nil,
              nil,
              "kura-0"
            ]
          ]
        )
      end)

      assert %{"structuredContent" => %{"trace_id" => "abc", "spans" => [span | _] = spans, "resources" => resources}} =
               GetPulseTrace.call(ctx.conn, Map.put(ctx.args, "trace_id", "ABC"))

      assert span["duration_ms"] == 2.0
      assert span["timestamp_end"] == "1793966000002000001"
      assert span["events"] == [%{"name" => "exception"}]
      assert span["attributes"] == %{"span_attributes.http.response.status_code" => 200}

      assert resources == [
               %{"resource_attributes.k8s.pod.name" => "server-0"},
               %{"resource_attributes.k8s.pod.name" => "kura-0"}
             ]

      assert Enum.map(spans, & &1["resource"]) == [0, 0, 1]
    end
  end
end
