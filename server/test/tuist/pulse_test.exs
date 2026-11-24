defmodule Tuist.PulseTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.Pulse
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @log_columns ~w(timestamp service level message trace_id)
  @span_columns ~w(timestamp service name duration_ms trace_id)

  setup do
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture(creator: user)
    config = [account_id: organization.account.id, base_url: "https://pulse.internal/", token: "secret"]
    stub(Environment, :pulse_config, fn -> config end)
    stub(Tuist.FeatureFlags, :pulse_enabled?, fn _ -> true end)
    # Tests read different upstream responses for one window; the reuse of a
    # computed window has its own test.
    stub(KeyValueStore, :get_or_update, fn _key, _opts, func -> func.() end)
    %{user: user, account: organization.account, organization: organization, config: config}
  end

  test "logs use readonly SQL rows in the configured database", ctx do
    expect(Req, :request, 3, fn request ->
      assert request.url.path == "/v1/sql"
      assert request.options[:auth] == {:basic, "dashboard:secret"}
      assert request.headers["x-pulse-db-name"] == ["public"]

      response(
        sql_body(@log_columns, [
          [1_794_329_254_406_000_001, "worker", "WARN", "can't cache", "abc"],
          [1_794_329_254_406_000_002, "server", "ERROR", "can't connect", "def"]
        ])
      )
    end)

    assert Pulse.default_query("metrics") == "up"
    assert Pulse.default_query("logs") == "*"
    assert Pulse.default_query("traces") == "*"
    assert Pulse.default_query("errors") == "*"

    assert {:ok, %{rows: [%{"message" => "can't connect", "timestamp" => "1794329254406000002"}], meta: meta}} =
             Pulse.query(ctx.user, ctx.account, "logs", %{"query" => "can't", "service" => "server"})

    assert meta["total_count"] == 1
  end

  test "metrics use the Prometheus API and spans retain measured milliseconds", ctx do
    expect(Req, :request, fn request ->
      assert request.url.path == "/v1/prometheus/api/v1/query"
      response(scalar_body([1_794_329_254, "17"]))
    end)

    assert {:ok, %{rows: [%{"value" => 17.0}]}} = Pulse.query(ctx.user, ctx.account, "metrics", %{})

    stub(Req, :request, fn _ ->
      response(sql_body(@span_columns, [[1_794_329_254_406_000_001, "worker", "cache.get", 17.25, "abc"]]))
    end)

    assert {:ok, %{rows: [%{"name" => "cache.get", "duration_ms" => 17.25, "trace_id" => "abc"}]}} =
             Pulse.query(ctx.user, ctx.account, "traces", %{})
  end

  test "availability requires the configured account and its feature flag", %{account: account} do
    reject(Accounts, :get_account_by_id, 2)
    reject(Req, :request, 1)
    assert Pulse.available?(account)
    assert Pulse.available?(%{account | name: "renamed"})
    refute Pulse.available?(%{account | id: account.id + 1})
    refute Pulse.available?(nil)

    for id <- [nil, 0, -1, "1"] do
      stub(Environment, :pulse_config, fn -> [account_id: id] end)
      refute Pulse.available?(%{id: id})
    end
  end

  test "own telemetry follows the configured account's enrollment", %{config: config} do
    assert Pulse.own_telemetry?()

    stub(Tuist.FeatureFlags, :pulse_enabled?, fn _ -> false end)
    refute Pulse.own_telemetry?()

    # An account that no longer exists, or none configured, takes nothing.
    stub(Tuist.FeatureFlags, :pulse_enabled?, fn _ -> true end)
    stub(Environment, :pulse_config, fn -> Keyword.put(config, :account_id, config[:account_id] + 1_000_000) end)
    refute Pulse.own_telemetry?()

    for id <- [nil, 0, "1"] do
      stub(Environment, :pulse_config, fn -> [account_id: id] end)
      refute Pulse.own_telemetry?()
    end
  end

  test "disabling the flag denies every read even for the configured organization's member", ctx do
    stub(Tuist.FeatureFlags, :pulse_enabled?, fn _ -> false end)
    reject(Req, :request, 1)

    refute Pulse.available?(ctx.account)
    refute Pulse.authorized?(ctx.user, ctx.account)
    assert {:error, :forbidden} = Pulse.query(ctx.user, ctx.account, "logs", %{})
    assert {:error, :forbidden} = Pulse.analytics(ctx.user, ctx.account, "logs", %{})
  end

  test "denies outsiders, anonymous visitors, public dashboard readers and other organizations before HTTP", ctx do
    outsider = AccountsFixtures.user_fixture()
    other = AccountsFixtures.organization_fixture(creator: ctx.user)
    ProjectsFixtures.project_fixture(account: ctx.account, visibility: :public)
    reject(Req, :request, 1)

    for {user, account} <- [{outsider, ctx.account}, {nil, ctx.account}, {ctx.user, other.account}] do
      refute Pulse.authorized?(user, account)
      assert {:error, :forbidden} = Pulse.query(user, account, "metrics", %{})
    end
  end

  test "personal accounts remain forbidden even when configured", %{user: user, config: config} do
    stub(Environment, :pulse_config, fn -> Keyword.put(config, :account_id, user.account.id) end)
    reject(Req, :request, 1)
    assert Pulse.available?(user.account)
    refute Pulse.authorized?(user, user.account)
    assert {:error, :forbidden} = Pulse.query(user, user.account, "metrics", %{})
  end

  test "members including viewers are authorized and queries recheck removed membership", ctx do
    for role <- [:admin, :user, :viewer] do
      member = AccountsFixtures.user_fixture()
      :ok = Accounts.add_user_to_organization(member, ctx.organization, role: role)
      assert Pulse.authorized?(member, ctx.account)
    end

    member = AccountsFixtures.user_fixture()
    :ok = Accounts.add_user_to_organization(member, ctx.organization)
    assert Pulse.authorized?(member, ctx.account)
    Accounts.remove_user_from_organization(member, ctx.organization)
    reject(Req, :request, 1)
    refute Pulse.authorized?(member, ctx.account)
    assert {:error, :forbidden} = Pulse.query(member, ctx.account, "metrics", %{})
  end

  test "rejects invalid parameters and endpoint, tenant and token overrides", ctx do
    reject(Req, :request, 1)

    for params <- [
          nil,
          %{query: "up"},
          %{"query" => " "},
          %{"query" => nil},
          %{"query" => <<255>>},
          %{"query" => String.duplicate("x", 4097)},
          %{"range" => "7d"},
          %{"base_url" => "https://attacker.test"},
          %{"tenant" => "other"},
          %{"token" => "other"}
        ] do
      assert {:error, :invalid_params} = Pulse.query(ctx.user, ctx.account, "metrics", params)
    end

    assert {:error, :invalid_params} = Pulse.query(ctx.user, ctx.account, "unknown", %{})
    assert Pulse.default_query("unknown") == nil
  end

  for {signal, path} <- [
        {"metrics", "/v1/prometheus/api/v1/query"},
        {"logs", "/v1/sql"},
        {"traces", "/v1/sql"}
      ] do
    test "#{signal} uses the canonical endpoint, units and bounded read-only options", ctx do
      signal = unquote(signal)
      now = ~U[2026-11-06 12:00:00Z]
      stub(DateTime, :utc_now, fn -> now end)
      finish = DateTime.to_unix(now)
      order = "ORDER BY timestamp DESC, trace_id ASC LIMIT 100"
      test = self()

      # Without 100 matches, the table widens from the newest minute to the
      # newest 15 minutes and then the whole hour.
      windows =
        for seconds <- [60, 900, 3600] do
          "timestamp > to_timestamp_seconds(#{finish - seconds}) AND timestamp <= to_timestamp_seconds(#{finish})"
        end

      expect(Req, :request, if(signal == "metrics", do: 1, else: 3), fn request ->
        assert request.method == :get
        assert request.url.host == "pulse.internal"
        assert request.url.path == unquote(path)
        assert Req.Request.get_header(request, "x-pulse-db-name") == ["public"]
        assert Req.Request.get_header(request, "accept") == ["application/json"]
        assert request.options.auth == {:basic, "dashboard:secret"}
        assert request.options.redirect == false
        assert request.options.retry == false
        assert request.options.receive_timeout == 30_000
        assert request.options.connect_options == [timeout: 10_000]
        params = request.options.params

        case signal do
          "metrics" ->
            assert params == [query: "up", time: finish]
            response(metric_body([]))

          _ ->
            assert [sql: sql] = params
            send(test, {:sql, sql})
            response(sql_body(if(signal == "logs", do: @log_columns, else: @span_columns), []))
        end
      end)

      assert {:ok, %{rows: [], series: [], warnings: []}} = Pulse.query(ctx.user, ctx.account, signal, %{})

      select =
        case signal do
          "metrics" ->
            nil

          "logs" ->
            "SELECT arrow_cast(timestamp, 'Int64') AS timestamp, " <>
              ~s|json_get_string(resource_attributes, '["service.name"]') AS service, | <>
              "severity_text AS level, body AS message, trace_id FROM opentelemetry_logs"

          "traces" ->
            "SELECT arrow_cast(timestamp, 'Int64') AS timestamp, service_name AS service, span_name AS name, " <>
              "duration_nano / 1000000.0 AS duration_ms, trace_id FROM opentelemetry_traces"
        end

      if select, do: assert(flush_sql() == Enum.map(windows, &"#{select} WHERE #{&1} #{order}"))
    end
  end

  test "the table stops widening at the first window holding 100 matches", ctx do
    stub(DateTime, :utc_now, fn -> ~U[2026-11-06 12:00:00Z] end)
    finish = DateTime.to_unix(~U[2026-11-06 12:00:00Z])
    rows = fn count -> Enum.map(1..count, &[finish * 1_000_000_000 - &1, "server", "span", 1, "trace"]) end

    expect(Req, :request, 2, fn request ->
      sql = request.options.params[:sql]

      cond do
        sql =~ "timestamp > to_timestamp_seconds(#{finish - 60}) AND" -> response(sql_body(@span_columns, rows.(40)))
        sql =~ "timestamp > to_timestamp_seconds(#{finish - 900}) AND" -> response(sql_body(@span_columns, rows.(100)))
      end
    end)

    assert {:ok, %{rows: [newest | _], meta: %{"total_count" => 100}}} =
             Pulse.query(ctx.user, ctx.account, "traces", %{"range" => "24h"})

    assert newest["timestamp"] == Integer.to_string(finish * 1_000_000_000 - 1)
  end

  test "log and span text search is a literal, case-insensitive SQL string", ctx do
    for {signal, column} <- [{"logs", "body"}, {"traces", "span_name"}] do
      expect(Req, :request, 3, fn request ->
        assert request.options.params[:sql] =~ " AND strpos(lower(#{column}), lower('it''s %_')) > 0 ORDER BY"
        response(sql_body(if(signal == "logs", do: @log_columns, else: @span_columns), []))
      end)

      assert {:ok, %{rows: []}} = Pulse.query(ctx.user, ctx.account, signal, %{"query" => "it's %_"})
    end
  end

  test "metric tables query an instant snapshot at the pinned end for every range", ctx do
    finish = ~U[2026-11-06 12:00:00Z]

    for range <- ~w(15m 1h 6h 24h) do
      expect(Req, :request, fn request ->
        params = request.options.params
        assert request.url.path == "/v1/prometheus/api/v1/query"
        assert params[:query] == "sum(up)"
        assert params[:time] == DateTime.to_unix(finish)
        refute Keyword.has_key?(params, :start)
        refute Keyword.has_key?(params, :step)
        response(vector_body([%{"metric" => %{"__name__" => "up"}, "value" => [DateTime.to_unix(finish), "17"]}]))
      end)

      assert {:ok, %{rows: [%{"value" => 17.0}], series: [%{"points" => [[timestamp, 17.0]]}]}} =
               Pulse.query(ctx.user, ctx.account, "metrics", %{
                 "range" => range,
                 "query" => "sum(up)",
                 "end_at" => DateTime.to_iso8601(finish)
               })

      assert timestamp == DateTime.to_unix(finish)
    end
  end

  test "instant scalar metric results project as one empty-label series", ctx do
    for {value, expected} <- [{"-2.5", -2.5}, {"0", 0.0}, {"NaN", "NaN"}, {"+Inf", "+Inf"}] do
      stub(Req, :request, fn _ -> response(scalar_body([1_793_966_400.0, value])) end)

      assert {:ok, %{rows: [row], series: [series], warnings: []}} =
               Pulse.query(ctx.user, ctx.account, "metrics", %{"query" => "scalar(sum(up))"})

      assert row == %{"name" => "", "labels" => %{}, "value" => expected}
      assert series == %{"name" => "", "labels" => %{}, "points" => [[1_793_966_400.0, expected]]}
    end
  end

  test "metric projection keeps seconds, converts numeric values and preserves nonfinite strings", ctx do
    body =
      metric_body([
        %{
          "metric" => %{"__name__" => "up", "job" => "server"},
          "values" => [[2.5, "NaN"], [1, "1.5"], [3, "+Inf"], [4, "-Inf"]]
        }
      ])

    stub(Req, :request, fn _ -> response(Map.put(body, "warnings", ["partial result"])) end)

    assert {:ok, %{rows: [row], series: [series], warnings: ["partial result"]}} =
             Pulse.query(ctx.user, ctx.account, "metrics", %{})

    assert row == %{"name" => "up{job=server}", "labels" => %{"__name__" => "up", "job" => "server"}, "value" => "-Inf"}
    assert series["points"] == [[1, 1.5], [2.5, "NaN"], [3, "+Inf"], [4, "-Inf"]]
  end

  test "metric results paginate beyond 100 without silently truncating points", ctx do
    entry = %{"metric" => %{}, "values" => Enum.map(1..500, &[&1, "1"])}
    stub(Req, :request, fn _ -> response(metric_body(List.duplicate(entry, 101))) end)
    assert {:error, :malformed_response} = Pulse.query(ctx.user, ctx.account, "metrics", %{})
    entries = Enum.map(1..101, &%{"metric" => %{"__name__" => "metric_#{&1}"}, "values" => [[1, "1"]]})
    stub(Req, :request, fn _ -> response(metric_body(entries)) end)

    assert {:ok, %{rows: rows, series: series, meta: meta}} =
             Pulse.query(ctx.user, ctx.account, "metrics", %{"page" => 6})

    assert length(rows) == 1
    assert length(series) == 1
    assert meta["total_count"] == 101
    assert meta["total_pages"] == 6
  end

  test "logs and traces project SQL rows with exact nanosecond strings", ctx do
    stub(Req, :request, fn _ ->
      response(
        sql_body(@log_columns, [
          [1_793_966_400_000_000_001, nil, nil, "plain", nil],
          [1_793_966_400_000_000_002, "server", "ERROR", "boom", "trace"]
        ])
      )
    end)

    assert {:ok, %{rows: [newer, older], series: []}} = Pulse.query(ctx.user, ctx.account, "logs", %{})

    assert newer == %{
             "timestamp" => "1793966400000000002",
             "service" => "server",
             "level" => "ERROR",
             "message" => "boom",
             "trace_id" => "trace"
           }

    assert older == %{
             "timestamp" => "1793966400000000001",
             "service" => nil,
             "level" => nil,
             "message" => "plain",
             "trace_id" => nil
           }

    stub(Req, :request, fn _ ->
      response(sql_body(@span_columns, [[1_793_966_400_000_000_001, "server", "GET /", nil, "abc"]]))
    end)

    assert {:ok, %{rows: [row], series: []}} = Pulse.query(ctx.user, ctx.account, "traces", %{})

    assert row == %{
             "trace_id" => "abc",
             "timestamp" => "1793966400000000001",
             "service" => "server",
             "name" => "GET /",
             "duration_ms" => nil
           }
  end

  test "logs and traces reject upstream responses exceeding the requested bound", ctx do
    rows = Enum.map(1..101, &[&1, "server", "INFO", "line", "trace"])
    stub(Req, :request, fn _ -> response(sql_body(@log_columns, rows)) end)
    assert {:error, :query_result_limit} = Pulse.query(ctx.user, ctx.account, "logs", %{})

    rows = Enum.map(1..101, &[&1, "server", "span", 1, "trace"])
    stub(Req, :request, fn _ -> response(sql_body(@span_columns, rows)) end)
    assert {:error, :query_result_limit} = Pulse.query(ctx.user, ctx.account, "traces", %{})
  end

  defp flush_sql(statements \\ []) do
    receive do
      {:sql, sql} -> flush_sql([sql | statements])
    after
      0 -> Enum.reverse(statements)
    end
  end

  @issue_columns ~w(service fingerprint events accounts first_seen last_seen title culprit level platform latest_event_id environment environments)
  @event_columns ~w(timestamp event_id title level environment release server_name trace_id account_handle sdk)
  @fingerprint String.duplicate("a1", 32)

  test "errors list issues by service and fingerprint, filtered and sorted before paging", ctx do
    expect(Req, :request, 6, fn request ->
      sql = request.options.params[:sql]
      assert sql =~ " FROM errors WHERE timestamp > to_timestamp_seconds("

      if sql =~ "GROUP BY service, fingerprint, bucket",
        do: issue_buckets(sql),
        else: issue_rows(sql)
    end)

    assert {:ok, %{rows: rows, meta: meta}} =
             Pulse.query(ctx.user, ctx.account, "errors", %{
               "query" => "can't",
               "service" => "server",
               "sort_by" => "events"
             })

    assert Enum.map(rows, & &1["fingerprint"]) == [@fingerprint, String.duplicate("c3", 32)]

    assert %{
             "first_seen" => "1794329254000000001",
             "last_seen" => "1794329255000000002",
             "accounts" => 1,
             "environment" => "production",
             "environments" => 2
           } = hd(rows)

    assert meta["total_count"] == 2

    # The worker's events under the same fingerprint stay out of the server issue's trend.
    series = hd(rows)["occurrence_series"]
    assert length(series) == 60
    assert series |> Enum.at(3) |> List.last() == 2
    assert series |> Enum.map(&List.last/1) |> Enum.sum() == 3
    assert rows |> List.last() |> Map.fetch!("occurrence_series") |> Enum.all?(&(List.last(&1) == 0))

    assert {:ok, %{rows: rows}} = Pulse.query(ctx.user, ctx.account, "errors", %{"query" => "can't"})
    assert Enum.map(rows, & &1["latest_event_id"]) == ~w(bb aa cc)

    # Search matches an issue's fields, not its trend's bucket labels.
    label = series |> Enum.at(30) |> hd() |> to_string()
    assert {:ok, %{rows: []}} = Pulse.query(ctx.user, ctx.account, "errors", %{"query" => "can't", "search" => label})
  end

  test "an error environment filter selects events before they are grouped into issues", ctx do
    expect(Req, :request, 2, fn request ->
      sql = request.options.params[:sql]

      assert sql =~ "AND environment = 'production' GROUP BY service, fingerprint ORDER BY" or
               sql =~
                 "AND strpos(lower(coalesce(environment, '')), lower('stag')) = 0 GROUP BY service, fingerprint ORDER BY"

      response(sql_body(@issue_columns, []))
    end)

    assert {:ok, %{rows: []}} = Pulse.query(ctx.user, ctx.account, "errors", %{"environment" => "production"})

    assert {:ok, %{rows: []}} =
             Pulse.query(ctx.user, ctx.account, "errors", %{
               "environment" => "stag",
               "environment_op" => "not_contains"
             })

    assert {:error, :invalid_params} = Pulse.query(ctx.user, ctx.account, "logs", %{"environment" => "production"})
  end

  defp issue_buckets(sql) do
    assert sql =~ " AND strpos(lower(title), lower('can''t')) > 0 AND fingerprint IN ("
    assert sql =~ "'#{String.duplicate("b2", 32)}'"

    response(
      sql_body(~w(service fingerprint bucket events), [
        ["server", @fingerprint, 3, 2],
        ["server", @fingerprint, 70, 1],
        ["worker", @fingerprint, 3, 5],
        ["worker", String.duplicate("b2", 32), 0, 9]
      ])
    )
  end

  defp issue_rows(sql) do
    assert sql =~ " FROM errors WHERE timestamp > to_timestamp_seconds("
    assert sql =~ " AND strpos(lower(title), lower('can''t')) > 0 GROUP BY service, fingerprint ORDER BY last_seen DESC"
    assert sql =~ "count(DISTINCT nullif(account_handle, '')) AS accounts"
    assert sql =~ "last_value(environment ORDER BY timestamp) AS environment, "
    assert sql =~ "count(DISTINCT nullif(environment, '')) AS environments"
    assert String.ends_with?(sql, " LIMIT 100")

    response(
      sql_body(@issue_columns, [
        [
          "server",
          @fingerprint,
          3,
          1,
          ns(1_794_329_254) + 1,
          ns(1_794_329_255) + 2,
          "RuntimeError: can't",
          "f/1",
          "error",
          "elixir",
          "aa",
          "production",
          2
        ],
        [
          "worker",
          String.duplicate("b2", 32),
          9,
          0,
          ns(1_794_329_250),
          ns(1_794_329_256),
          "KeyError: can't",
          nil,
          "warning",
          nil,
          "bb",
          "staging",
          1
        ],
        [
          "server",
          String.duplicate("c3", 32),
          1,
          0,
          ns(1_794_329_251),
          ns(1_794_329_251),
          "Exit: can't",
          nil,
          "fatal",
          nil,
          "cc",
          nil,
          0
        ]
      ])
    )
  end

  test "an error issue returns its summary, 60 occurrence buckets and the latest scrubbed event", ctx do
    finish = DateTime.to_unix(~U[2026-11-06 12:00:00Z])
    start = finish - 3600
    parent = self()
    event = ["ee", "RuntimeError: boom", "error", "production", "1.0", "pod", "0af7", "tuist", "sentry-elixir/11.0"]

    stub(Req, :request, fn request ->
      sql = request.options.params[:sql]
      send(parent, :sql)

      assert sql =~
               " FROM errors WHERE timestamp > to_timestamp_seconds(#{start}) AND timestamp <= to_timestamp_seconds(#{finish})"

      assert sql =~ " AND service = 'server''s' AND fingerprint = '#{@fingerprint}'"
      assert sql =~ " AND environment = 'prod''uction'"

      cond do
        sql =~ "GROUP BY service, fingerprint" ->
          response(
            sql_body(@issue_columns, [
              [
                "server's",
                @fingerprint,
                4,
                1,
                ns(start) + 5,
                ns(finish),
                "RuntimeError: boom",
                "f/1",
                "error",
                "elixir",
                "ee",
                "production",
                1
              ]
            ])
          )

        sql =~ "GROUP BY bucket" ->
          assert sql =~ "(arrow_cast(timestamp, 'Int64') - #{ns(start)}) / 60000000000 AS bucket"
          # An event at the window's inclusive end falls into the last bucket.
          response(sql_body(~w(bucket events), [[0, 2], [30, 1], [60, 1]]))

        sql =~ ", event FROM errors" ->
          payload = %{
            "exception" => [%{"type" => "RuntimeError", "frames" => []}],
            "tags" => %{"a" => "b"},
            "user" => %{"id" => "1"}
          }

          response(sql_body(@event_columns ++ ["event"], [[ns(finish) | event] ++ [payload]]))

        true ->
          assert String.ends_with?(sql, "ORDER BY timestamp DESC, event_id ASC LIMIT 2 OFFSET 2")

          response(
            sql_body(@event_columns, [
              [ns(finish) | event],
              [ns(start) + 5, "dd", nil, "error", nil, nil, nil, nil, nil, nil]
            ])
          )
      end
    end)

    assert {:ok, detail} =
             Pulse.error_issue(ctx.user, ctx.account, @fingerprint, %{
               "service" => "server's",
               "environment" => "prod'uction",
               "end_at" => "2026-11-06T12:00:00Z",
               "page" => "2",
               "page_size" => "2"
             })

    assert detail.issue["events"] == 4

    assert detail.meta == %{
             "page" => 2,
             "page_size" => 2,
             "total_count" => 4,
             "total_pages" => 2,
             "end_at" => "2026-11-06T12:00:00Z",
             "has_next_page" => false,
             "has_previous_page" => true
           }

    assert detail.issue["first_seen"] == Integer.to_string(ns(start) + 5)
    assert length(detail.occurrence_series) == 60
    assert hd(detail.occurrence_series) == [start, 2]
    assert Enum.at(detail.occurrence_series, 30) == [start + 1800, 1]
    assert List.last(detail.occurrence_series) == [finish - 60, 1]
    assert detail.occurrence_series |> Enum.map(&List.last/1) |> Enum.sum() == 4
    assert detail.latest_event["event_id"] == "ee"
    assert detail.latest_event["timestamp"] == Integer.to_string(ns(finish))
    assert detail.latest_event["exception"] == [%{"type" => "RuntimeError", "frames" => []}]
    assert detail.latest_event["tags"] == %{"a" => "b"}
    refute Map.has_key?(detail.latest_event, "user")
    assert Enum.map(detail.events, & &1["event_id"]) == ~w(ee dd)

    for _ <- 1..4, do: assert_received(:sql)
    refute_received :sql
  end

  test "error issues report a missing issue and validate before HTTP", ctx do
    expect(Req, :request, fn _ -> response(sql_body(@issue_columns, [])) end)
    assert {:error, :not_found} = Pulse.error_issue(ctx.user, ctx.account, @fingerprint, %{"service" => "server"})

    reject(Req, :request, 1)

    for {fingerprint, params} <- [
          {String.upcase(@fingerprint), %{"service" => "server"}},
          {"a1", %{"service" => "server"}},
          {@fingerprint, %{}},
          {@fingerprint, %{"service" => ""}},
          {@fingerprint, %{"service" => 1}},
          {@fingerprint, %{"service" => "server", "query" => "x"}},
          {@fingerprint, %{"service" => "server", "range" => "7d"}},
          {@fingerprint, %{"service" => "server", "page" => "0"}},
          {@fingerprint, nil}
        ] do
      assert {:error, :invalid_params} = Pulse.error_issue(ctx.user, ctx.account, fingerprint, params)
    end

    outsider = AccountsFixtures.user_fixture()
    assert {:error, :forbidden} = Pulse.error_issue(outsider, ctx.account, @fingerprint, %{"service" => "server"})
    assert {:error, :forbidden} = Pulse.error_issue(nil, ctx.account, "bad", %{})
  end

  test "an error event is read by its issue and ID within the window", ctx do
    event_id = String.duplicate("e5", 16)

    expect(Req, :request, fn request ->
      sql = request.options.params[:sql]
      assert sql =~ " AND service = 'server' AND fingerprint = '#{@fingerprint}' AND event_id = '#{event_id}'"

      response(
        sql_body(@event_columns ++ ["event"], [
          [ns(1_794_329_254), event_id, "KeyError", "error", "production", nil, "pod", nil, nil, "sentry-elixir/11.0"] ++
            [%{"contexts" => %{"trace.span_id" => "b7ad"}, "request" => %{"url" => "/x"}, "user" => %{}}]
        ])
      )
    end)

    assert {:ok, %{event: event}} =
             Pulse.error_event(ctx.user, ctx.account, @fingerprint, event_id, %{"service" => "server"})

    assert event["title"] == "KeyError"
    assert event["sdk"] == "sentry-elixir/11.0"
    assert event["contexts"] == %{"trace.span_id" => "b7ad"}
    refute Map.has_key?(event, "user")

    expect(Req, :request, fn _ -> response(sql_body(@event_columns ++ ["event"], [])) end)

    assert {:error, :not_found} =
             Pulse.error_event(ctx.user, ctx.account, @fingerprint, event_id, %{"service" => "server"})

    reject(Req, :request, 1)

    for {id, params} <- [
          {String.upcase(event_id), %{"service" => "server"}},
          {event_id, %{"service" => "server", "page" => "2"}},
          {event_id, %{}}
        ] do
      assert {:error, :invalid_params} = Pulse.error_event(ctx.user, ctx.account, @fingerprint, id, params)
    end

    assert {:error, :forbidden} = Pulse.error_event(nil, ctx.account, @fingerprint, event_id, %{"service" => "server"})
  end

  test "malformed upstream results return fixed errors", ctx do
    for {signal, body} <- [
          {"metrics", "not json"},
          {"metrics", %{}},
          {"metrics", metric_body([%{"metric" => %{}, "values" => [[1, "bad"]]}])},
          {"metrics", scalar_body([1, "bad"])},
          {"metrics", scalar_body(["1", "2"])},
          {"metrics", scalar_body([1, 2])},
          {"metrics", scalar_body([])},
          {"metrics", metric_body([%{"metric" => %{"label" => 1}, "values" => []}])},
          {"metrics", Map.put(metric_body([]), "warnings", [1])},
          {"logs", %{}},
          {"logs", %{"output" => []}},
          {"logs", sql_body(@log_columns, [["bad", "server", "INFO", "line", "trace"]])},
          {"logs", sql_body(@log_columns, [[-1, "server", "INFO", "line", "trace"]])},
          {"logs", sql_body(@log_columns, [[1, "server", "INFO", 1, "trace"]])},
          {"logs", sql_body(@log_columns, [[1, "server"]])},
          {"traces", sql_body(@span_columns, [[1, "server", "span", "bad", "trace"]])}
        ] do
      stub(Req, :request, fn _ -> response(body) end)
      assert {:error, :malformed_response} = Pulse.query(ctx.user, ctx.account, signal, %{})
    end
  end

  test "HTTP and transport failures never return upstream details", ctx do
    for {status, reason} <- [
          {400, :invalid_query},
          {422, :invalid_query},
          {429, :rate_limited},
          {408, :timeout},
          {504, :timeout},
          {302, :upstream_error},
          {401, :upstream_error},
          {500, :upstream_error}
        ] do
      stub(Req, :request, fn _ -> {:ok, %Req.Response{status: status, body: "secret diagnostic"}} end)
      assert {:error, ^reason} = Pulse.query(ctx.user, ctx.account, "metrics", %{})
    end

    stub(Req, :request, fn _ -> {:error, %Req.TransportError{reason: :timeout}} end)
    assert {:error, :timeout} = Pulse.query(ctx.user, ctx.account, "metrics", %{})
    stub(Req, :request, fn _ -> {:error, %Req.TransportError{reason: :econnrefused}} end)
    assert {:error, :unavailable} = Pulse.query(ctx.user, ctx.account, "metrics", %{})
  end

  test "invalid server credentials fail before HTTP", ctx do
    reject(Req, :request, 1)

    for {key, value} <- [
          base_url: nil,
          base_url: "file:///tmp/pulse",
          base_url: "https://user:pass@pulse.internal",
          base_url: "https://pulse.internal?query=up",
          token: "",
          token: "bad\rtoken"
        ] do
      stub(Environment, :pulse_config, fn -> Keyword.put(ctx.config, key, value) end)
      assert {:error, :not_configured} = Pulse.query(ctx.user, ctx.account, "metrics", %{})
    end
  end

  describe "analytics" do
    test "rechecks organization authorization before any HTTP", ctx do
      outsider = AccountsFixtures.user_fixture()
      other = AccountsFixtures.organization_fixture(creator: ctx.user)
      reject(Req, :request, 1)

      for {user, account} <- [{nil, ctx.account}, {outsider, ctx.account}, {ctx.user, other.account}] do
        assert {:error, :forbidden} = Pulse.analytics(user, account, "metrics", %{})
      end

      :ok = Accounts.add_user_to_organization(outsider, ctx.organization, role: :viewer)
      assert Pulse.authorized?(outsider, ctx.account)
      Accounts.remove_user_from_organization(outsider, ctx.organization)
      assert {:error, :forbidden} = Pulse.analytics(outsider, ctx.account, "metrics", %{})

      stub(Environment, :pulse_config, fn -> Keyword.put(ctx.config, :account_id, ctx.user.account.id) end)
      assert {:error, :forbidden} = Pulse.analytics(ctx.user, ctx.user.account, "metrics", %{})
    end

    test "accepts only string range, never caller queries or upstream configuration", ctx do
      reject(Req, :request, 1)

      for params <- [
            nil,
            %{range: "1h"},
            %{"range" => nil},
            %{"range" => :hour},
            %{"range" => "7d"},
            %{"widgets" => []},
            %{"widgets" => "reporting"},
            %{"widgets" => ["fatal"]},
            %{"query" => "up"},
            %{"base_url" => "https://evil.test"},
            %{"tenant" => "other"},
            %{"token" => "other"},
            %{"token_file" => "/tmp/secret"}
          ] do
        assert {:error, :invalid_params} = Pulse.analytics(ctx.user, ctx.account, "metrics", params)
      end

      assert {:error, :invalid_params} = Pulse.analytics(ctx.user, ctx.account, "unknown", %{})
      stub(Environment, :pulse_config, fn -> Keyword.put(ctx.config, :token, "bad\ntoken") end)
      assert {:error, :not_configured} = Pulse.analytics(ctx.user, ctx.account, "metrics", %{})
    end

    test "one count_values range query yields every gauge from a bounded snapshot, with missing distinct from zero",
         ctx do
      now = ~U[2026-11-06 12:00:07Z]
      stub(DateTime, :utc_now, fn -> now end)
      parent = self()

      for {range, seconds, step} <- [{"15m", 900, 3}, {"1h", 3600, 10}, {"6h", 21_600, 60}, {"24h", 86_400, 240}] do
        finish = DateTime.to_unix(now) - rem(DateTime.to_unix(now), step)
        start = finish - seconds

        stub(Req, :request, fn request ->
          send(parent, {:analytics_request, request})
          params = request.options.params
          assert params[:query] == ~s|count_values("value", up)|
          assert request.url.path == "/v1/prometheus/api/v1/query_range"
          assert {params[:start], params[:end], params[:step]} == {start, finish, step}

          # At the start 3 targets report 1 and one reports 0; afterwards 2
          # report 1 and none report 0. Pulse sends float timestamps and
          # formats whole sample values as floats.
          response(
            counts_body(%{
              "1" => Enum.map(start..finish//step, &[&1 / 1, if(&1 == start, do: "3.0", else: "2.0")]),
              "0" => [[start, "1.0"]]
            })
          )
        end)

        assert {:ok, %{widgets: [reporting, healthy, unhealthy], warnings: []}} =
                 Pulse.analytics(ctx.user, ctx.account, "metrics", %{"range" => range})

        assert Enum.map([reporting, healthy, unhealthy], & &1.id) == ~w(reporting healthy unhealthy)
        assert Enum.all?([reporting, healthy, unhealthy], &(&1.unit == :count))
        assert {reporting.value, healthy.value, unhealthy.value} == {2, 2, 0}
        assert {reporting.previous_value, healthy.previous_value, unhealthy.previous_value} == {4, 3, 1}
        assert Enum.take(unhealthy.points, 2) == [[start, 1], [start + step, 0]]
        assert length(reporting.points) <= 361

        assert_receive {:analytics_request, request}
        assert request.method == :get
        assert request.url.host == "pulse.internal"
        assert request.options.auth == {:basic, "dashboard:secret"}
        assert Req.Request.get_header(request, "x-pulse-db-name") == ["public"]
        assert request.options.redirect == false
        assert request.options.retry == false
        assert request.options.receive_timeout == 30_000
        assert request.options.connect_options == [timeout: 10_000]
        refute_receive {:analytics_request, _}
      end

      stub(Req, :request, fn _request -> response(metric_body([])) end)

      assert {:ok, %{widgets: widgets}} = Pulse.analytics(ctx.user, ctx.account, "metrics", %{})
      assert Enum.all?(widgets, &(&1.value == nil and &1.previous_value == nil and &1.points == []))
    end

    test "other up values count only as reporting, steps without targets are missing and warnings deduplicate",
         ctx do
      stub(DateTime, :utc_now, fn -> ~U[2026-11-06 12:00:00Z] end)
      finish = DateTime.to_unix(~U[2026-11-06 12:00:00Z])
      start = finish - 3600

      stub(Req, :request, fn _request ->
        body =
          counts_body(%{
            "1" => [[start, "2"], [finish - 10, "2"]],
            "NaN" => [[finish - 10, "1"]],
            "0" => [[start, "1"]]
          })

        response(Map.put(body, "warnings", ["upstream notice", "upstream notice"]))
      end)

      assert {:ok, %{widgets: [reporting, healthy, unhealthy], warnings: ["upstream notice"]}} =
               Pulse.analytics(ctx.user, ctx.account, "metrics", %{})

      assert reporting.points == [[start, 3], [finish - 10, 3]]
      assert healthy.points == [[start, 2], [finish - 10, 2]]
      assert unhealthy.points == [[start, 1], [finish - 10, 0]]
      assert Enum.map([reporting, healthy, unhealthy], &{&1.value, &1.previous_value}) == [{nil, 3}, {nil, 2}, {nil, 1}]

      # The previous gauge is missing independently of the current one.
      stub(Req, :request, fn _request -> response(counts_body(%{"1" => [[finish - 10, "2"], [finish, "2"]]})) end)

      assert {:ok, %{widgets: widgets}} = Pulse.analytics(ctx.user, ctx.account, "metrics", %{})
      assert Enum.map(widgets, &{&1.value, &1.previous_value}) == [{2, nil}, {2, nil}, {0, nil}]
    end

    for signal <- ~w(logs traces errors) do
      test "#{signal} aggregates through SQL with aligned buckets and full-window totals", ctx do
        signal = unquote(signal)
        now = ~U[2026-11-06 12:03:59Z]
        stub(DateTime, :utc_now, fn -> now end)
        parent = self()
        table = %{"logs" => "opentelemetry_logs", "traces" => "opentelemetry_traces", "errors" => "errors"}[signal]

        ids =
          %{
            "logs" => ~w(entries errors warnings),
            "traces" => ~w(spans errors duration_p95),
            "errors" => ~w(events fatal services)
          }[signal]

        # Each widget gets its own values, and Pulse returns the columns in
        # reverse order, so a widget reading another's column fails.
        weights = ids |> Enum.with_index(1) |> Map.new()
        columns = Enum.reverse(ids)

        steps =
          if signal in ~w(logs errors),
            do: [{"15m", 900, 60}, {"1h", 3600, 60}, {"6h", 21_600, 60}, {"24h", 86_400, 240}],
            else: [{"15m", 900, 3}, {"1h", 3600, 10}, {"6h", 21_600, 60}, {"24h", 86_400, 240}]

        for {range, seconds, step} <- steps do
          finish = DateTime.to_unix(now) - rem(DateTime.to_unix(now), step)

          stub(Req, :request, fn request ->
            assert request.url.path == "/v1/sql"
            assert request.options.auth == {:basic, "dashboard:secret"}
            sql = request.options.params[:sql]
            assert sql =~ " FROM #{table} WHERE "

            [start, stop] =
              ~r/timestamp > to_timestamp_seconds\((\d+)\) AND timestamp <= to_timestamp_seconds\((\d+)\)/
              |> Regex.run(sql, capture: :all_but_first)
              |> Enum.map(&String.to_integer/1)

            if sql =~ "GROUP BY bucket" do
              # Counts read one bucketed scan of both periods; other widgets
              # bucket only the current one.
              assert {start, stop} == {finish - if(signal == "logs", do: 2 * seconds, else: seconds), finish}

              assert String.starts_with?(
                       sql,
                       "SELECT ((arrow_cast(timestamp, 'Int64') - 1) / #{step * 1_000_000_000} + 1) * #{step} AS bucket, "
                     )

              assert String.ends_with?(sql, " GROUP BY bucket ORDER BY bucket")
              send(parent, {:sql, :range})

              rows =
                Enum.map((start + step)..stop//step, fn time ->
                  [time | Enum.map(columns, &(if(time > finish - seconds, do: 7, else: 5) * weights[&1]))]
                end)

              response(sql_body(["bucket" | columns], rows))
            else
              assert stop - start == seconds
              assert stop in [finish, finish - seconds]
              send(parent, {:sql, stop})
              value = if(stop == finish, do: 12_345, else: 23_456)
              response(sql_body(columns, [Enum.map(columns, &(value * weights[&1]))]))
            end
          end)

          assert {:ok, %{widgets: widgets, warnings: []}} =
                   Pulse.analytics(ctx.user, ctx.account, signal, %{"range" => range})

          assert Enum.map(widgets, & &1.id) == ids

          for widget <- widgets do
            factor = weights[widget.id] * if(widget.id == "duration_p95", do: 1000, else: 1)

            if signal == "logs" do
              # Totals are the sums of each period's buckets.
              assert widget.value == 7 * factor * div(seconds, step)
              assert widget.previous_value == 5 * factor * div(seconds, step)
            else
              assert widget.value == 12_345 * factor
              assert widget.previous_value == 23_456 * factor
            end

            assert widget.points == Enum.map((finish - seconds + step)..finish//step, &[&1, 7 * factor])
            assert length(widget.points) <= 360
          end

          # One statement per period computes every widget, and counts share one.
          expected = if signal == "logs", do: [:range], else: [:range, finish, finish - seconds]

          received =
            for _ <- expected do
              assert_receive {:sql, period}
              period
            end

          assert Enum.sort(received) == Enum.sort(expected)
          refute_receive {:sql, _}
        end
      end
    end

    test "a node shares one computation of a window across refreshes, never caching failures", ctx do
      stub(KeyValueStore, :get_or_update, fn key, opts, func ->
        Mimic.call_original(KeyValueStore, :get_or_update, [key, opts, func])
      end)

      test = self()

      # A failure is returned without being kept, so the next load retries.
      stub(DateTime, :utc_now, fn -> ~U[2026-11-06 12:00:05Z] end)
      stub(Req, :request, fn _request -> {:ok, %Req.Response{status: 503}} end)
      assert {:error, :upstream_error} = Pulse.analytics(ctx.user, ctx.account, "logs", %{})

      stub(Req, :request, fn _request ->
        send(test, :sql)
        response(sql_body(~w(bucket entries errors warnings), []))
      end)

      # The hour of logs has 60-second steps.
      assert {:ok, first} = Pulse.analytics(ctx.user, ctx.account, "logs", %{})
      assert_received :sql
      stub(DateTime, :utc_now, fn -> ~U[2026-11-06 12:00:59Z] end)
      assert {:ok, ^first} = Pulse.analytics(ctx.user, ctx.account, "logs", %{})
      refute_received :sql

      # Other widgets and ranges are separate windows.
      assert {:ok, _} = Pulse.analytics(ctx.user, ctx.account, "logs", %{"widgets" => ["errors"]})
      assert_received :sql
      assert {:ok, _} = Pulse.analytics(ctx.user, ctx.account, "logs", %{"range" => "15m"})
      assert_received :sql

      stub(DateTime, :utc_now, fn -> ~U[2026-11-06 12:01:00Z] end)
      assert {:ok, second} = Pulse.analytics(ctx.user, ctx.account, "logs", %{})
      assert_received :sql
      assert hd(hd(second.widgets).points) != hd(hd(first.widgets).points)
    end

    test "trace span and error counts come from one scan of both periods", ctx do
      now = ~U[2026-11-06 12:03:59Z]
      stub(DateTime, :utc_now, fn -> now end)
      test = self()

      for {range, seconds, step} <- [{"15m", 900, 3}, {"1h", 3600, 10}] do
        finish = DateTime.to_unix(now) - rem(DateTime.to_unix(now), step)

        stub(Req, :request, fn request ->
          sql = request.options.params[:sql]
          send(test, {:sql, sql})
          refute sql =~ "approx_percentile_cont"

          # Pulse omits empty buckets; every present one counts 3 spans and 1
          # error now, 2 spans and no errors in the previous period.
          rows =
            for time <- (finish - 2 * seconds + step)..finish//(2 * step) do
              if time > finish - seconds, do: [time, 3, 1], else: [time, 2, 0]
            end

          response(sql_body(~w(bucket spans errors), rows))
        end)

        assert {:ok, %{widgets: [spans, errors]}} =
                 Pulse.analytics(ctx.user, ctx.account, "traces", %{"range" => range, "widgets" => ~w(spans errors)})

        assert [sql] = flush_sql()

        assert sql =~
                 "/ #{step * 1_000_000_000} + 1) * #{step} AS bucket, " <>
                   ~s{count(*) AS "spans", count(*) FILTER (WHERE span_status_code = 'STATUS_CODE_ERROR') AS "errors" } <>
                   "FROM opentelemetry_traces WHERE timestamp > to_timestamp_seconds(#{finish - 2 * seconds}) " <>
                   "AND timestamp <= to_timestamp_seconds(#{finish}) GROUP BY bucket"

        # Every other bucket is present, so each period has half its buckets.
        present = div(seconds, step * 2)
        assert {spans.value, spans.previous_value} == {3 * present, 2 * present}
        assert {errors.value, errors.previous_value} == {present, 0}
        assert length(spans.points) == div(seconds, step)
        # The newest bucket is one Pulse omitted: a zero count, not a gap.
        assert Enum.take(spans.points, -2) == [[finish - step, 3], [finish, 0]]
      end

      # A count is never null, so a null bucket is malformed, not a crash.
      finish = DateTime.to_unix(now) - rem(DateTime.to_unix(now), 3)
      stub(Req, :request, fn _request -> response(sql_body(~w(bucket spans errors), [[finish, nil, 0]])) end)

      assert {:error, :malformed_response} =
               Pulse.analytics(ctx.user, ctx.account, "traces", %{"range" => "15m", "widgets" => ~w(spans errors)})
    end

    test "log, trace and error widgets share one statement per period with fixed filters and expressions", ctx do
      parent = self()

      for {signal, table, ids, fragments} <- [
            {"logs", "opentelemetry_logs", ~w(entries errors warnings),
             [
               ~s|count(*) AS "entries"|,
               ~s|count(*) FILTER (WHERE upper(severity_text) IN ('ERROR', 'FATAL')) AS "errors"|,
               ~s|count(*) FILTER (WHERE upper(severity_text) IN ('WARN', 'WARNING')) AS "warnings"|
             ]},
            {"traces", "opentelemetry_traces", ~w(spans errors duration_p95),
             [
               ~s|count(*) AS "spans"|,
               ~s|count(*) FILTER (WHERE span_status_code = 'STATUS_CODE_ERROR') AS "errors"|,
               ~s|approx_percentile_cont(duration_nano, 0.95) / 1000000000.0 AS "duration_p95"|
             ]},
            {"errors", "errors", ~w(events fatal services),
             [
               ~s|count(DISTINCT event_id) AS "events"|,
               ~s|count(DISTINCT event_id) FILTER (WHERE "level" = 'fatal') AS "fatal"|,
               ~s|count(DISTINCT nullif(service, '')) AS "services"|
             ]}
          ] do
        stub(Req, :request, fn request ->
          sql = request.options.params[:sql]
          send(parent, {:sql, sql})

          if sql =~ "GROUP BY bucket",
            do: response(sql_body(["bucket" | ids], [])),
            else: response(sql_body(ids, [[1, 1, 1]]))
        end)

        assert {:ok, %{widgets: widgets}} = Pulse.analytics(ctx.user, ctx.account, signal, %{})

        # With no rows in any bucket, counts are zero and durations are gaps.
        for widget <- widgets do
          empty = if widget.id == "duration_p95", do: nil, else: 0
          assert length(widget.points) == if(signal in ~w(logs errors), do: 60, else: 360)
          assert Enum.all?(widget.points, &match?([_, ^empty], &1))
        end

        statements =
          for _ <- 1..if(signal == "logs", do: 1, else: 3) do
            assert_receive {:sql, sql}
            sql
          end

        refute_receive {:sql, _}

        # The filters apply to their own widget only: the window bound is the
        # whole WHERE clause.
        assert Enum.all?(
                 statements,
                 &(&1 =~
                     ~r/ FROM #{table} WHERE timestamp > to_timestamp_seconds\(\d+\) AND timestamp <= to_timestamp_seconds\(\d+\)( GROUP BY bucket ORDER BY bucket)?$/)
               )

        for fragment <- fragments do
          assert Enum.all?(statements, &String.contains?(&1, fragment))
        end
      end
    end

    test "span duration seconds become milliseconds and periods without spans are gaps", ctx do
      stub(DateTime, :utc_now, fn -> ~U[2026-11-06 12:00:00Z] end)
      finish = DateTime.to_unix(~U[2026-11-06 12:00:00Z])

      ids = ~w(spans errors duration_p95)
      test = self()

      stub(Req, :request, fn request ->
        sql = request.options.params[:sql]
        send(test, {:sql, sql})
        current = sql =~ "to_timestamp_seconds(#{finish})"

        cond do
          sql =~ "GROUP BY bucket" ->
            response(
              sql_body(["bucket" | ids], [[finish - 20, 0, 0, 0.0], [finish - 10, 4, 0, 0.1], [finish, 6, 1, 0.9]])
            )

          current ->
            response(sql_body(ids, [[500, 1, 0.45]]))

          true ->
            response(sql_body(ids, [[250, 0, 0.25]]))
        end
      end)

      assert {:ok, %{widgets: [spans, errors, duration]}} = Pulse.analytics(ctx.user, ctx.account, "traces", %{})
      assert {spans.id, spans.value, spans.previous_value} == {"spans", 500, 250}
      assert {errors.id, errors.value, errors.previous_value} == {"errors", 1, 0}
      assert Enum.take(errors.points, -3) == [[finish - 20, 0], [finish - 10, 0], [finish, 1]]

      assert {duration.id, duration.unit, duration.value, duration.previous_value} ==
               {"duration_p95", :milliseconds, 450.0, 250.0}

      assert Enum.take(duration.points, 1) == [[finish - 3600 + 10, nil]]
      assert Enum.take(duration.points, -3) == [[finish - 20, nil], [finish - 10, 100.0], [finish, 900.0]]
      assert Enum.take(spans.points, -3) == [[finish - 20, 0], [finish - 10, 4], [finish, 6]]
      # Buckets Pulse omits are zero counts, not gaps.
      assert hd(spans.points) == [finish - 3600 + 10, 0]
      assert hd(errors.points) == [finish - 3600 + 10, 0]

      # Loaded on its own, the p95 still takes its gaps from the span counts,
      # and its statements never compute the error count.
      flush_sql()

      assert {:ok, %{widgets: [^duration]}} =
               Pulse.analytics(ctx.user, ctx.account, "traces", %{"widgets" => ["duration_p95"]})

      statements = flush_sql()
      assert length(statements) == 3
      assert Enum.all?(statements, &(&1 =~ ~s|count(*) AS "spans"| and &1 =~ ~s|AS "duration_p95"|))
      refute Enum.any?(statements, &(&1 =~ "STATUS_CODE_ERROR"))

      for {current_count, previous_count, expected, previous_expected} <- [
            {0, 2, nil, 125.0},
            {2, 0, 125.0, nil},
            {nil, 2, nil, 125.0},
            {2, nil, 125.0, nil}
          ] do
        stub(Req, :request, fn request ->
          sql = request.options.params[:sql]
          current = sql =~ "to_timestamp_seconds(#{finish})"

          if sql =~ "GROUP BY bucket",
            do: response(sql_body(["bucket" | ids], [])),
            else: response(sql_body(ids, [[if(current, do: current_count, else: previous_count), 0, 0.125]]))
        end)

        assert {:ok, %{widgets: [spans, _, duration]}} = Pulse.analytics(ctx.user, ctx.account, "traces", %{})
        assert spans.value == current_count
        assert spans.previous_value == previous_count
        assert duration.value == expected
        assert duration.previous_value == previous_expected
      end
    end

    test "aggregate failures reject the snapshot without leaking upstream details", ctx do
      stub(DateTime, :utc_now, fn -> ~U[2026-11-06 12:00:00Z] end)
      finish = DateTime.to_unix(~U[2026-11-06 12:00:00Z])

      for {result, reason} <- [
            {response(%{}), :malformed_response},
            {response(vector_body([%{"value" => [finish, "bad"]}])), :malformed_response},
            {response(Map.put(vector_body([]), "warnings", [1])), :malformed_response},
            {{:ok, %Req.Response{status: 429, body: "private"}}, :rate_limited},
            {{:error, %Req.TransportError{reason: :timeout}}, :timeout}
          ] do
        stub(Req, :request, fn _request -> result end)

        assert {:error, ^reason} = Pulse.analytics(ctx.user, ctx.account, "metrics", %{})
      end
    end

    test "rejects malformed, oversized, duplicate, extra-series and out-of-window aggregates without truncation", ctx do
      finish = DateTime.to_unix(~U[2026-11-06 12:00:00Z])
      stub(DateTime, :utc_now, fn -> ~U[2026-11-06 12:00:00Z] end)

      for body <- [
            "bad",
            %{},
            counts_body(%{"1" => [[finish, "bad"]]}),
            counts_body(%{"1" => [[finish, "1.5"]]}),
            counts_body(%{"1" => [[finish, "1.0x"]]}),
            counts_body(%{"1" => [[finish, "-1"]]}),
            counts_body(%{"1" => [[finish, "+Inf"]]}),
            counts_body(%{"1" => List.duplicate([finish, "1"], 362)}),
            counts_body(%{"1" => [[finish, "1"], [finish, "2"]]}),
            counts_body(%{"1" => [[finish + 1, "1"]]}),
            counts_body(%{"1" => [[finish - 0.5, "1"]]}),
            # Off the 10-second step grid, so unions of series could exceed 361 points.
            counts_body(%{"1" => [[finish, "1"]], "0" => [[finish - 5, "1"]]}),
            # count_values has one series per value; repeats or a flood are malformed.
            metric_body([
              %{"metric" => %{"value" => "1"}, "values" => [[finish, "2"]]},
              %{"metric" => %{"value" => "1"}, "values" => [[finish, "3"]]}
            ]),
            counts_body(%{"1" => [[finish, "1.0"]], "1.0" => [[finish, "1.0"]]}),
            counts_body(Map.new(0..100, &{"#{&1}", [[finish, "1"]]})),
            metric_body([%{"metric" => %{}, "values" => []}]),
            metric_body(["x"]),
            metric_body([[finish, "1"]]),
            metric_body([%{"metric" => "x", "values" => []}]),
            metric_body([%{"metric" => [1], "values" => []}]),
            Map.put(metric_body([]), "warnings", [1])
          ] do
        stub(Req, :request, fn _request -> response(body) end)

        assert {:error, :malformed_response} = Pulse.analytics(ctx.user, ctx.account, "metrics", %{})
      end

      ids = ~w(spans errors duration_p95)
      buckets = ["bucket" | ids]

      for {range_body, instant_body} <- [
            {sql_body(buckets, [[finish + 10, 1, 1, 1]]), sql_body(ids, [[1, 1, 1]])},
            {sql_body(buckets, [[finish - 3600, 1, 1, 1]]), sql_body(ids, [[1, 1, 1]])},
            {sql_body(buckets, [["bad", 1, 1, 1]]), sql_body(ids, [[1, 1, 1]])},
            {sql_body(buckets, [[finish, "1", 1, 1]]), sql_body(ids, [[1, 1, 1]])},
            {sql_body(buckets, []), sql_body(ids, [])},
            {sql_body(buckets, []), sql_body(ids, [[1, 1, 1], [2, 2, 2]])},
            {sql_body(buckets, []), sql_body(~w(spans errors), [[1, 1]])},
            {sql_body(buckets, []), %{}}
          ] do
        stub(Req, :request, fn request ->
          response(if request.options.params[:sql] =~ "GROUP BY bucket", do: range_body, else: instant_body)
        end)

        assert {:error, :malformed_response} = Pulse.analytics(ctx.user, ctx.account, "traces", %{})
      end
    end

    test "uses one metric request, preserving safe failure reasons", ctx do
      parent = self()

      stub(Req, :request, fn _request ->
        send(parent, {:blocked_request, self()})

        receive do
          :release -> {:ok, %Req.Response{status: 429, body: "private upstream details"}}
        end
      end)

      task = Task.async(fn -> Pulse.analytics(ctx.user, ctx.account, "metrics", %{}) end)

      assert_receive {:blocked_request, pid}, 1000
      refute_receive {:blocked_request, _}
      send(pid, :release)

      assert Task.await(task) == {:error, :rate_limited}
      refute_receive {:blocked_request, _}

      for {result, reason} <- [
            {{:ok, %Req.Response{status: 501}}, :upstream_error},
            {{:ok, %Req.Response{status: 422}}, :invalid_query},
            {{:error, %Req.TransportError{reason: :timeout}}, :timeout},
            {{:error, %Req.TransportError{reason: :econnrefused}}, :unavailable}
          ] do
        stub(Req, :request, fn _ -> result end)
        assert {:error, ^reason} = Pulse.analytics(ctx.user, ctx.account, "traces", %{})
      end
    end
  end

  describe "table contracts" do
    test "validates pagination, sort and signal-specific filters before HTTP", ctx do
      reject(Req, :request, 1)

      for params <- [
            %{"page" => 0},
            %{"page" => "1.5"},
            %{"page_size" => 101},
            %{"page_size" => 0},
            %{"sort_by" => "duration_ms"},
            %{"sort_order" => "DESC"},
            %{"end_at" => "no"},
            %{"end_at" => nil},
            %{"end_at" => :now},
            %{"end_at" => 1_793_966_400},
            %{"end_at" => "2500-01-01T00:00:00Z"},
            %{"service_op" => "regex"},
            %{"project" => "1"},
            %{"service" => nil}
          ] do
        assert {:error, :invalid_params} = Pulse.query(ctx.user, ctx.account, "logs", params)
      end

      assert {:error, :invalid_params} = Pulse.query(ctx.user, ctx.account, "traces", %{"level" => "error"})
    end

    test "pinned logs sort numerically in both directions and filter before paging", ctx do
      stub(Req, :request, fn request ->
        assert request.options.params[:sql] =~ "AND timestamp <= to_timestamp_seconds(1793966400) ORDER BY"

        response(
          sql_body(@log_columns, [
            [11, "worker", "info", "needle", nil],
            [10, "api-server", "error", "needle", nil],
            [9, "api-server", "error", "needle", nil]
          ])
        )
      end)

      params = %{
        "end_at" => "2026-11-06T12:00:00Z",
        "service" => "API",
        "service_op" => "contains",
        "level" => "info",
        "level_op" => "not_contains",
        "search" => "needle",
        "page_size" => "1",
        "sort_order" => "asc"
      }

      assert {:ok, %{rows: [%{"timestamp" => "9"}], meta: meta}} = Pulse.query(ctx.user, ctx.account, "logs", params)

      assert meta == %{
               "page" => 1,
               "page_size" => 1,
               "total_count" => 2,
               "total_pages" => 2,
               "end_at" => "2026-11-06T12:00:00Z",
               "has_next_page" => true,
               "has_previous_page" => false
             }

      assert {:ok, %{rows: [%{"timestamp" => "10"}]}} =
               Pulse.query(ctx.user, ctx.account, "logs", Map.put(params, "page", 2))

      assert {:ok, %{rows: [%{"timestamp" => "10"}]}} =
               Pulse.query(ctx.user, ctx.account, "logs", Map.put(params, "sort_order", "desc"))

      assert {:ok, %{rows: [], meta: %{"total_count" => 2}}} =
               Pulse.query(ctx.user, ctx.account, "logs", Map.put(params, "page", 100))
    end

    test "numeric metric and trace sorting keeps missing measurements last", ctx do
      metrics =
        Enum.map([{"b", "10"}, {"a", "2"}, {"c", "NaN"}], fn {name, value} ->
          %{"metric" => %{"__name__" => name}, "values" => [[1, value]]}
        end)

      stub(Req, :request, fn _ -> response(metric_body(metrics)) end)

      for {order, names} <- [{"asc", ~w(a b c)}, {"desc", ~w(b a c)}] do
        assert {:ok, %{rows: rows}} =
                 Pulse.query(ctx.user, ctx.account, "metrics", %{"sort_by" => "value", "sort_order" => order})

        assert Enum.map(rows, & &1["name"]) == names
      end

      spans = Enum.map([{1, 10}, {2, 2}, {3, nil}], fn {id, duration} -> [id, nil, nil, duration, "#{id}"] end)
      stub(Req, :request, fn _ -> response(sql_body(@span_columns, spans)) end)

      assert {:ok, %{rows: rows}} =
               Pulse.query(ctx.user, ctx.account, "traces", %{"sort_by" => "duration_ms", "sort_order" => "asc"})

      assert Enum.map(rows, & &1["trace_id"]) == ~w(2 1 3)
    end

    test "equal log timestamps preserve every tied row across stable pages", ctx do
      stub(Req, :request, fn _ ->
        response(sql_body(@log_columns, [[10, nil, nil, "a", nil], [10, nil, nil, "b", nil], [10, nil, nil, "c", nil]]))
      end)

      for order <- ~w(asc desc) do
        messages =
          for page <- 1..3 do
            assert {:ok, %{rows: [row], meta: %{"total_count" => 3}}} =
                     Pulse.query(ctx.user, ctx.account, "logs", %{
                       "page_size" => 1,
                       "page" => page,
                       "sort_order" => order,
                       "end_at" => "2026-11-06T12:00:00Z"
                     })

            row["message"]
          end

        assert Enum.sort(messages) == ~w(a b c)
      end
    end

    test "full log and trace searches stay bounded without generated warnings", ctx do
      for count <- [99, 100], signal <- ~w(logs traces) do
        stub(Req, :request, fn request ->
          assert String.ends_with?(request.options.params[:sql], " LIMIT 100")

          if signal == "logs",
            do: response(sql_body(@log_columns, Enum.map(1..count, &[&1, nil, nil, "line", nil]))),
            else: response(sql_body(@span_columns, Enum.map(1..count, &[&1, nil, "span", nil, "#{&1}"])))
        end)

        assert {:ok, %{rows: rows, meta: meta, warnings: []}} =
                 Pulse.query(ctx.user, ctx.account, signal, %{"page" => 2, "page_size" => 20, "sort_order" => "asc"})

        assert length(rows) == 20
        assert hd(rows)["timestamp"] == "21"
        assert meta["total_count"] == count
        assert meta["total_pages"] == 5

        assert {:ok, %{rows: [], warnings: [], meta: %{"total_count" => 0}}} =
                 Pulse.query(ctx.user, ctx.account, signal, %{"service" => "absent"})
      end
    end

    test "responses beyond the requested ceiling still fail whole", ctx do
      stub(Req, :request, fn _ ->
        response(sql_body(@log_columns, Enum.map(1..5000, &[&1, nil, nil, "line", nil])))
      end)

      assert {:error, :query_result_limit} = Pulse.query(ctx.user, ctx.account, "logs", %{"service" => "absent"})

      stub(Req, :request, fn _ ->
        response(sql_body(@span_columns, Enum.map(1..1000, &[&1, nil, nil, nil, "#{&1}"])))
      end)

      assert {:error, :query_result_limit} = Pulse.query(ctx.user, ctx.account, "traces", %{"sort_by" => "duration_ms"})
      entry = %{"metric" => %{}, "values" => []}
      stub(Req, :request, fn _ -> response(metric_body(List.duplicate(entry, 5001))) end)
      assert {:error, :query_result_limit} = Pulse.query(ctx.user, ctx.account, "metrics", %{})
    end

    test "HTTP streaming bounds bytes before decoding and accepts bounded JSON", ctx do
      stub(Req, :request, fn request ->
        assert request.options.compressed == false

        assert {:cont, {_, response}} =
                 request.into.(
                   {:data, JSON.encode!(metric_body([]))},
                   {request, %Req.Response{status: 200, body: ""}}
                 )

        {:ok, response}
      end)

      assert {:ok, %{rows: []}} = Pulse.query(ctx.user, ctx.account, "metrics", %{})

      stub(Req, :request, fn request ->
        assert {:halt, {_, response}} =
                 request.into.({:data, String.duplicate("x", 8_388_609)}, {request, %Req.Response{status: 200, body: ""}})

        {:ok, response}
      end)

      assert {:error, :query_result_limit} = Pulse.query(ctx.user, ctx.account, "metrics", %{})
    end
  end

  defp response(body), do: {:ok, %Req.Response{status: 200, body: body}}
  defp ns(seconds), do: seconds * 1_000_000_000
  defp vector_body(entries), do: %{"status" => "success", "data" => %{"resultType" => "vector", "result" => entries}}
  defp scalar_body(value), do: %{"status" => "success", "data" => %{"resultType" => "scalar", "result" => value}}

  defp counts_body(counts) do
    metric_body(
      Enum.map(counts, fn {value, values} ->
        %{"metric" => %{"__name__" => "up", "value" => value}, "values" => values}
      end)
    )
  end

  defp metric_body(entries), do: %{"status" => "success", "data" => %{"resultType" => "matrix", "result" => entries}}

  defp sql_body(columns, rows) do
    columns = Enum.map(columns, &%{"name" => &1})
    %{"output" => [%{"records" => %{"schema" => %{"column_schemas" => columns}, "rows" => rows}}]}
  end
end
