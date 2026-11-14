defmodule Tuist.PulseTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.Pulse
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @log_columns ~w(timestamp service level message trace_id)
  @span_columns ~w(timestamp service name duration_ms trace_id)

  setup do
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture(creator: user)
    config = [account_id: organization.account.id, base_url: "https://pulse.internal/", tenant: "public", token: "secret"]
    stub(Environment, :pulse_config, fn -> config end)
    stub(Tuist.FeatureFlags, :pulse_enabled?, fn _ -> true end)
    %{user: user, account: organization.account, organization: organization, config: config}
  end

  test "logs use readonly SQL rows in the configured database and errors are not a signal", ctx do
    expect(Req, :request, fn request ->
      assert request.url.path == "/v1/sql"
      assert request.options[:auth] == {:basic, "dashboard:secret"}
      assert request.headers["x-pulse-db-name"] == ["public"]
      assert request.headers["x-greptime-db-name"] == ["public"]

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
    assert Pulse.default_query("errors") == nil

    assert {:ok, %{rows: [%{"message" => "can't connect", "timestamp" => "1794329254406000002"}], meta: meta}} =
             Pulse.query(ctx.user, ctx.account, "logs", %{"query" => "can't", "service" => "server"})

    assert meta["total_count"] == 1

    reject(Req, :request, 1)
    assert {:error, :invalid_params} = Pulse.query(ctx.user, ctx.account, "errors", %{})
    assert {:error, :invalid_params} = Pulse.analytics(ctx.user, ctx.account, "errors", %{})
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
      bounds = "timestamp > to_timestamp_seconds(#{finish - 3600}) AND timestamp <= to_timestamp_seconds(#{finish})"
      order = "ORDER BY timestamp DESC, trace_id ASC LIMIT 100"

      expect(Req, :request, fn request ->
        assert request.method == :get
        assert request.url.host == "pulse.internal"
        assert request.url.path == unquote(path)
        assert Req.Request.get_header(request, "x-pulse-db-name") == ["public"]
        assert Req.Request.get_header(request, "x-greptime-db-name") == ["public"]
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

          "logs" ->
            assert params == [
                     sql:
                       "SELECT arrow_cast(timestamp, 'Int64') AS timestamp, " <>
                         ~s|json_get_string(resource_attributes, '["service.name"]') AS service, | <>
                         "severity_text AS level, body AS message, trace_id FROM opentelemetry_logs WHERE #{bounds} #{order}"
                   ]

            response(sql_body(@log_columns, []))

          "traces" ->
            assert params == [
                     sql:
                       "SELECT arrow_cast(timestamp, 'Int64') AS timestamp, service_name AS service, span_name AS name, " <>
                         "duration_nano / 1000000.0 AS duration_ms, trace_id FROM opentelemetry_traces WHERE #{bounds} #{order}"
                   ]

            response(sql_body(@span_columns, []))
        end
      end)

      assert {:ok, %{rows: [], series: [], warnings: []}} = Pulse.query(ctx.user, ctx.account, signal, %{})
    end
  end

  test "log and span text search is a literal, case-insensitive SQL string", ctx do
    for {signal, column} <- [{"logs", "body"}, {"traces", "span_name"}] do
      expect(Req, :request, fn request ->
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
          tenant: "bad\ntenant",
          token: "",
          token: "bad\rtoken"
        ] do
      stub(Environment, :pulse_config, fn -> Keyword.put(ctx.config, key, value) end)
      assert {:error, :not_configured} = Pulse.query(ctx.user, ctx.account, "metrics", %{})
    end
  end

  @tag :tmp_dir
  test "projected token files rotate each request and never fall back to a static token", %{tmp_dir: tmp_dir} = ctx do
    path = Path.join(tmp_dir, "token")
    stub(Environment, :pulse_config, fn -> Keyword.put(ctx.config, :token_file, path) end)

    for token <- ["first", "rotated"] do
      File.write!(path, token <> "\n")

      expect(Req, :request, fn request ->
        assert request.options.auth == {:basic, "dashboard:" <> token}
        response(metric_body([]))
      end)

      assert {:ok, _} = Pulse.query(ctx.user, ctx.account, "metrics", %{})
    end

    File.rm!(path)
    reject(Req, :request, 1)
    assert {:error, :not_configured} = Pulse.query(ctx.user, ctx.account, "metrics", %{})
    File.write!(path, "\n")
    assert {:error, :not_configured} = Pulse.query(ctx.user, ctx.account, "metrics", %{})
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

    test "fixed end gauges and range queries share a bounded snapshot, with missing distinct from zero", ctx do
      now = ~U[2026-11-06 12:00:07Z]
      stub(DateTime, :utc_now, fn -> now end)
      parent = self()

      for {range, seconds, step} <- [{"15m", 900, 3}, {"1h", 3600, 10}, {"6h", 21_600, 60}, {"24h", 86_400, 240}] do
        finish = DateTime.to_unix(now) - rem(DateTime.to_unix(now), step)

        stub(Req, :request, fn request ->
          send(parent, {:analytics_request, request})
          params = request.options.params
          assert params[:query] in ["count(up)", "sum(up == bool 1)", "sum(up == bool 0)"]
          value = if params[:query] == "sum(up == bool 0)", do: "0", else: "2"

          assert request.url.path == "/v1/prometheus/api/v1/query_range"
          assert params[:start] == finish - seconds
          assert params[:end] == finish
          assert params[:step] == step
          points = Enum.map((finish - seconds)..finish//step, &[&1 / 1, if(&1 == finish - seconds, do: "3", else: value)])
          response(metric_body([%{"metric" => %{}, "values" => points}]))
        end)

        assert {:ok, %{widgets: [reporting, healthy, unhealthy], warnings: []}} =
                 Pulse.analytics(ctx.user, ctx.account, "metrics", %{"range" => range})

        assert Enum.map([reporting, healthy, unhealthy], & &1.id) == ~w(reporting healthy unhealthy)
        assert reporting.value == 2
        assert healthy.unit == :count
        assert unhealthy.value == 0
        assert Enum.all?([reporting, healthy, unhealthy], &(&1.previous_value == 3))
        assert length(reporting.points) <= 361

        for _ <- 1..3 do
          assert_receive {:analytics_request, request}
          assert request.method == :get
          assert request.url.host == "pulse.internal"
          assert request.options.auth == {:basic, "dashboard:secret"}
          assert Req.Request.get_header(request, "x-pulse-db-name") == ["public"]
          assert Req.Request.get_header(request, "x-greptime-db-name") == ["public"]
          assert request.options.redirect == false
          assert request.options.retry == false
          assert request.options.receive_timeout == 30_000
          assert request.options.connect_options == [timeout: 10_000]
        end

        refute_receive {:analytics_request, _}
      end

      stub(Req, :request, fn _request -> response(metric_body([])) end)

      assert {:ok, %{widgets: widgets}} = Pulse.analytics(ctx.user, ctx.account, "metrics", %{})
      assert Enum.all?(widgets, &(&1.value == nil and &1.previous_value == nil and &1.points == []))
    end

    test "preserves measured zero, maps nonfinite observations to nil and deduplicates warnings", ctx do
      stub(DateTime, :utc_now, fn -> ~U[2026-11-06 12:00:00Z] end)
      finish = DateTime.to_unix(~U[2026-11-06 12:00:00Z])

      stub(Req, :request, fn _request ->
        body = metric_body([%{"values" => [[finish - 3600, "0"], [finish - 10, "0"], [finish, "+Inf"]]}])
        response(Map.put(body, "warnings", ["upstream notice"]))
      end)

      assert {:ok, %{widgets: widgets, warnings: ["upstream notice"]}} =
               Pulse.analytics(ctx.user, ctx.account, "metrics", %{})

      assert Enum.all?(
               widgets,
               &(&1.value == nil and &1.previous_value == 0 and
                   &1.points == [[finish - 3600, 0.0], [finish - 10, 0.0], [finish, nil]])
             )
    end

    test "current and previous metric gauges stay independent when missing, nonfinite or zero", ctx do
      stub(DateTime, :utc_now, fn -> ~U[2026-11-06 12:00:00Z] end)
      finish = DateTime.to_unix(~U[2026-11-06 12:00:00Z])

      for {current, previous} <- [{nil, "0"}, {"0", nil}, {"0", "NaN"}, {"1", "+Inf"}, {"-Inf", "2"}] do
        stub(Req, :request, fn _request ->
          points =
            Enum.reject([[finish - 3600, previous], [finish - 10, "7"], [finish, current]], &is_nil(List.last(&1)))

          response(metric_body([%{"values" => points}]))
        end)

        assert {:ok, %{widgets: widgets}} = Pulse.analytics(ctx.user, ctx.account, "metrics", %{})
        expected_current = if current in ["0", "1"], do: String.to_integer(current)
        expected_previous = if previous in ["0", "2"], do: String.to_integer(previous)
        assert Enum.all?(widgets, &(&1.value == expected_current and &1.previous_value == expected_previous))
      end
    end

    for signal <- ~w(logs traces) do
      test "#{signal} aggregates through SQL with aligned buckets and independent full-window totals", ctx do
        signal = unquote(signal)
        now = ~U[2026-11-06 12:03:59Z]
        stub(DateTime, :utc_now, fn -> now end)
        parent = self()
        table = if signal == "logs", do: "opentelemetry_logs", else: "opentelemetry_traces"

        steps =
          if signal == "logs",
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

            assert stop - start == seconds

            if sql =~ "GROUP BY bucket" do
              assert {start, stop} == {finish - seconds, finish}

              assert String.starts_with?(
                       sql,
                       "SELECT ((arrow_cast(timestamp, 'Int64') - 1) / #{step * 1_000_000_000} + 1) * #{step} AS bucket, "
                     )

              assert String.ends_with?(sql, " GROUP BY bucket ORDER BY bucket")
              send(parent, {:sql, :range})
              response(sql_body(~w(bucket value), Enum.map((start + step)..stop//step, &[&1, 7])))
            else
              assert stop in [finish, finish - seconds]
              send(parent, {:sql, stop})
              response(sql_body(~w(value), [[if(stop == finish, do: 12_345, else: 23_456)]]))
            end
          end)

          assert {:ok, %{widgets: widgets, warnings: []}} =
                   Pulse.analytics(ctx.user, ctx.account, signal, %{"range" => range})

          assert Enum.map(widgets, & &1.id) ==
                   if(signal == "logs", do: ~w(entries errors warnings), else: ~w(spans errors duration_p95))

          for widget <- widgets do
            factor = if widget.id == "duration_p95", do: 1000, else: 1
            assert widget.value == 12_345 * factor
            assert widget.previous_value == 23_456 * factor
            assert widget.points == Enum.map((finish - seconds + step)..finish//step, &[&1, 7 * factor])
            assert length(widget.points) <= 360
          end

          received =
            for _ <- 1..9 do
              assert_receive {:sql, period}
              period
            end

          assert Enum.frequencies(received) == %{:range => 3, finish => 3, (finish - seconds) => 3}
          refute_receive {:sql, _}
        end
      end
    end

    test "log and trace widgets use fixed SQL filters and expressions", ctx do
      parent = self()

      stub(Req, :request, fn request ->
        sql = request.options.params[:sql]
        send(parent, {:sql, sql})

        if sql =~ "GROUP BY bucket",
          do: response(sql_body(~w(bucket value), [])),
          else: response(sql_body(~w(value), [[1]]))
      end)

      for {signal, table, fragments} <- [
            {"logs", "opentelemetry_logs",
             ["upper(severity_text) IN ('ERROR', 'FATAL')", "upper(severity_text) IN ('WARN', 'WARNING')"]},
            {"traces", "opentelemetry_traces",
             [
               "span_status_code = 'STATUS_CODE_ERROR'",
               "approx_percentile_cont(duration_nano, 0.95) / 1000000000.0 AS value"
             ]}
          ] do
        assert {:ok, _} = Pulse.analytics(ctx.user, ctx.account, signal, %{})

        statements =
          for _ <- 1..9 do
            assert_receive {:sql, sql}
            sql
          end

        refute_receive {:sql, _}
        assert Enum.all?(statements, &(&1 =~ " FROM #{table} WHERE timestamp > to_timestamp_seconds("))
        assert Enum.count(statements, &(&1 =~ "count(*) AS value")) == if(signal == "logs", do: 9, else: 6)

        for fragment <- fragments do
          assert Enum.count(statements, &(&1 =~ fragment)) == 3
        end
      end
    end

    test "span duration seconds become milliseconds and periods without spans are gaps", ctx do
      stub(DateTime, :utc_now, fn -> ~U[2026-11-06 12:00:00Z] end)
      finish = DateTime.to_unix(~U[2026-11-06 12:00:00Z])

      stub(Req, :request, fn request ->
        sql = request.options.params[:sql]
        duration = sql =~ "approx_percentile_cont"
        current = sql =~ "to_timestamp_seconds(#{finish})"

        cond do
          sql =~ "GROUP BY bucket" and duration ->
            response(sql_body(~w(bucket value), [[finish - 20, 0.0], [finish - 10, 0.1], [finish, 0.9]]))

          sql =~ "GROUP BY bucket" ->
            response(sql_body(~w(bucket value), [[finish - 10, 4], [finish, 6]]))

          duration ->
            response(sql_body(~w(value), [[if(current, do: 0.45, else: 0.25)]]))

          true ->
            response(sql_body(~w(value), [[if(current, do: 500, else: 250)]]))
        end
      end)

      assert {:ok, %{widgets: [spans, errors, duration]}} = Pulse.analytics(ctx.user, ctx.account, "traces", %{})
      assert {spans.id, spans.value, spans.previous_value} == {"spans", 500, 250}
      assert errors.id == "errors"

      assert {duration.id, duration.unit, duration.value, duration.previous_value} ==
               {"duration_p95", :milliseconds, 450.0, 250.0}

      assert Enum.take(duration.points, 1) == [[finish - 3600 + 10, nil]]
      assert Enum.take(duration.points, -3) == [[finish - 20, nil], [finish - 10, 100.0], [finish, 900.0]]
      assert Enum.take(spans.points, -3) == [[finish - 20, 0], [finish - 10, 4], [finish, 6]]

      for {current_count, previous_count, expected, previous_expected} <- [
            {0, 2, nil, 125.0},
            {2, 0, 125.0, nil},
            {nil, 2, nil, 125.0},
            {2, nil, 125.0, nil}
          ] do
        stub(Req, :request, fn request ->
          sql = request.options.params[:sql]
          current = sql =~ "to_timestamp_seconds(#{finish})"

          cond do
            sql =~ "GROUP BY bucket" -> response(sql_body(~w(bucket value), []))
            sql =~ "approx_percentile_cont" -> response(sql_body(~w(value), [[0.125]]))
            true -> response(sql_body(~w(value), [[if(current, do: current_count, else: previous_count)]]))
          end
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
            metric_body([%{"values" => [[finish, "bad"]]}]),
            metric_body([%{"values" => List.duplicate([finish, "1"], 362)}]),
            metric_body([%{"values" => [[finish, "1"], [finish, "2"]]}]),
            metric_body([%{"values" => [[finish + 1, "1"]]}]),
            metric_body([%{"values" => []}, %{"values" => []}]),
            Map.put(metric_body([]), "warnings", [1])
          ] do
        stub(Req, :request, fn _request -> response(body) end)

        assert {:error, :malformed_response} = Pulse.analytics(ctx.user, ctx.account, "metrics", %{})
      end

      for {range_body, instant_body} <- [
            {sql_body(~w(bucket value), [[finish + 10, 1]]), sql_body(~w(value), [[1]])},
            {sql_body(~w(bucket value), [[finish - 3600, 1]]), sql_body(~w(value), [[1]])},
            {sql_body(~w(bucket value), [["bad", 1]]), sql_body(~w(value), [[1]])},
            {sql_body(~w(bucket value), [[finish, "1"]]), sql_body(~w(value), [[1]])},
            {sql_body(~w(bucket value), []), sql_body(~w(value), [])},
            {sql_body(~w(bucket value), []), sql_body(~w(value), [[1], [2]])},
            {sql_body(~w(bucket value), []), %{}}
          ] do
        stub(Req, :request, fn request ->
          response(if request.options.params[:sql] =~ "GROUP BY bucket", do: range_body, else: instant_body)
        end)

        assert {:error, :malformed_response} = Pulse.analytics(ctx.user, ctx.account, "traces", %{})
      end
    end

    test "uses three metric requests with bounded workers, preserving safe failure reasons", ctx do
      parent = self()

      stub(Req, :request, fn _request ->
        send(parent, {:blocked_request, self()})

        receive do
          :release -> {:ok, %Req.Response{status: 429, body: "private upstream details"}}
        end
      end)

      task = Task.async(fn -> Pulse.analytics(ctx.user, ctx.account, "metrics", %{}) end)

      first =
        for _ <- 1..3 do
          assert_receive {:blocked_request, pid}, 1000
          pid
        end

      refute_receive {:blocked_request, _}
      Enum.each(first, &send(&1, :release))

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
  defp vector_body(entries), do: %{"status" => "success", "data" => %{"resultType" => "vector", "result" => entries}}
  defp scalar_body(value), do: %{"status" => "success", "data" => %{"resultType" => "scalar", "result" => value}}
  defp metric_body(entries), do: %{"status" => "success", "data" => %{"resultType" => "matrix", "result" => entries}}

  defp sql_body(columns, rows) do
    columns = Enum.map(columns, &%{"name" => &1})
    %{"output" => [%{"records" => %{"schema" => %{"column_schemas" => columns}, "rows" => rows}}]}
  end
end
