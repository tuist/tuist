defmodule Tuist.PulseTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.Pulse
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture(creator: user)
    config = [account_id: organization.account.id, base_url: "https://pulse.internal/", tenant: "tuist", token: "secret"]
    stub(Environment, :pulse_config, fn -> config end)
    stub(Tuist.FeatureFlags, :pulse_enabled?, fn _ -> true end)
    %{user: user, account: organization.account, organization: organization, config: config}
  end

  test "Greptime uses readonly SQL rows and denies issue reads without HTTP", ctx do
    config = Keyword.merge(ctx.config, backend: :greptime, tenant: "public")
    stub(Environment, :pulse_config, fn -> config end)

    columns = Enum.map(~w(timestamp service level message trace_id), &%{"name" => &1})

    body = %{
      "output" => [
        %{
          "records" => %{
            "schema" => %{"column_schemas" => columns},
            "rows" => [
              [1_794_329_254_406_000_001, "worker", "WARN", "can't cache", "abc"],
              [1_794_329_254_406_000_002, "server", "ERROR", "can't connect", "def"]
            ]
          }
        }
      ]
    }

    expect(Req, :request, fn request ->
      assert request.url.path == "/v1/sql"
      assert request.options[:auth] == {:basic, "dashboard:secret"}
      assert request.headers["x-greptime-db-name"] == ["public"]
      response(body)
    end)

    assert Pulse.default_query("logs") == "*"
    assert Pulse.default_query("traces") == "*"

    assert {:ok, %{rows: [%{"message" => "can't connect", "timestamp" => "1794329254406000002"}], meta: meta}} =
             Pulse.query(ctx.user, ctx.account, "logs", %{"query" => "can't", "service" => "server"})

    assert meta["total_count"] == 1

    reject(Req, :request, 1)
    assert {:error, :forbidden} = Pulse.query(ctx.user, ctx.account, "errors", %{})
    assert {:error, :forbidden} = Pulse.analytics(ctx.user, ctx.account, "errors", %{})
    assert {:error, :forbidden} = Pulse.error_issue(ctx.user, ctx.account, "issue", %{})
    assert {:error, :forbidden} = Pulse.error_event(ctx.user, ctx.account, "issue", "event", %{})
  end

  test "Greptime metrics use its Prometheus API and spans retain measured milliseconds", ctx do
    stub(Environment, :pulse_config, fn -> Keyword.merge(ctx.config, backend: :greptime, tenant: "public") end)

    expect(Req, :request, fn request ->
      assert request.url.path == "/v1/prometheus/api/v1/query"
      response(scalar_body([1_794_329_254, "17"]))
    end)

    assert {:ok, %{rows: [%{"value" => 17.0}]}} = Pulse.query(ctx.user, ctx.account, "metrics", %{})

    columns = Enum.map(~w(timestamp service name duration_ms trace_id), &%{"name" => &1})

    stub(Req, :request, fn _ ->
      response(%{
        "output" => [
          %{
            "records" => %{
              "schema" => %{"column_schemas" => columns},
              "rows" => [[1_794_329_254_406_000_001, "worker", "cache.get", 17.25, "abc"]]
            }
          }
        ]
      })
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
    assert {:error, :forbidden} = Pulse.error_issue(ctx.user, ctx.account, "issue", %{})
    assert {:error, :forbidden} = Pulse.error_event(ctx.user, ctx.account, "issue", "event", %{})
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
        {"metrics", "/api/v1/query"},
        {"logs", "/loki/api/v1/query_range"},
        {"traces", "/api/search"}
      ] do
    test "#{signal} uses the canonical endpoint, units and bounded read-only options", ctx do
      signal = unquote(signal)
      now = ~U[2026-11-06 12:00:00Z]
      stub(DateTime, :utc_now, fn -> now end)
      finish = DateTime.to_unix(now)

      expect(Req, :request, fn request ->
        assert request.method == :get
        assert request.url.host == "pulse.internal"
        assert request.url.path == unquote(path)
        assert Req.Request.get_header(request, "x-scope-orgid") == ["tuist"]
        assert request.options.auth == {:bearer, "secret"}
        assert request.options.redirect == false
        assert request.options.retry == false
        assert request.options.receive_timeout == 30_000
        assert request.options.connect_options == [timeout: 10_000]
        params = request.options.params

        if signal == "logs" do
          assert params[:start] == Integer.to_string((finish - 3600) * 1_000_000_000)
          assert params[:end] == Integer.to_string(finish * 1_000_000_000)
          assert params[:limit] == 100
          assert params[:direction] == "backward"
        end

        if signal == "traces" do
          assert params[:start] == finish - 3600
          assert params[:end] == finish
        end

        case signal do
          "metrics" ->
            assert params[:query] == "up"
            assert params[:time] == finish
            refute Keyword.has_key?(params, :step)

          "traces" ->
            assert params[:q] == "{}"
            assert params[:limit] == 100

          "logs" ->
            assert params[:query] == ~s({service_name=~".+"})
        end

        response(empty_body(signal))
      end)

      assert {:ok, %{rows: [], series: [], warnings: []}} = Pulse.query(ctx.user, ctx.account, signal, %{})
    end
  end

  test "metric tables query an instant snapshot at the pinned end for every range", ctx do
    finish = ~U[2026-11-06 12:00:00Z]

    for range <- ~w(15m 1h 6h 24h) do
      expect(Req, :request, fn request ->
        params = request.options.params
        assert request.url.path == "/api/v1/query"
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

  test "logs project safe fields and preserve exact nanosecond ordering", ctx do
    event = %{
      "exception" => %{"values" => [%{"type" => "RuntimeError", "value" => "boom"}]},
      "contexts" => %{"trace" => %{"trace_id" => "trace"}},
      "request" => %{"password" => "private"}
    }

    values = [
      ["1793966400000000001", JSON.encode!(event)],
      ["1793966400000000002", "plain", %{"trace_id" => "metadata-trace", "private" => "secret"}]
    ]

    body =
      stream_body([
        %{"stream" => %{"service_name" => "server", "severity_text" => "error", "secret" => "hidden"}, "values" => values}
      ])

    stub(Req, :request, fn _ -> response(body) end)

    for signal <- ~w(logs) do
      assert {:ok, %{rows: [newer, older], series: []}} = Pulse.query(ctx.user, ctx.account, signal, %{})

      assert newer == %{
               "timestamp" => "1793966400000000002",
               "service" => "server",
               "level" => "error",
               "message" => "plain",
               "trace_id" => "metadata-trace"
             }

      assert older["timestamp"] == "1793966400000000001"
      assert older["message"] == "RuntimeError: boom"
      assert older["trace_id"] == "trace"
      refute inspect(older) =~ "private"
      refute inspect(newer) =~ "secret"
    end
  end

  test "structured logs without a display message do not expose arbitrary payloads", ctx do
    values = [["1", ~s({"secret":"hidden"})], ["2", ~s(["hidden"])], ["3", String.duplicate("x", 5000)]]
    stub(Req, :request, fn _ -> response(stream_body([%{"stream" => %{}, "values" => values}])) end)
    assert {:ok, %{rows: [long, structured, object]}} = Pulse.query(ctx.user, ctx.account, "logs", %{})
    assert String.length(long["message"]) == 4096
    assert structured["message"] == "Structured log"
    assert object["message"] == "Structured log"
  end

  test "traces retain nanoseconds and milliseconds without raw span metadata", ctx do
    trace = %{
      "traceID" => "abc",
      "startTimeUnixNano" => "1793966400000000001",
      "rootServiceName" => "server",
      "rootTraceName" => "GET /",
      "durationMs" => 1.25,
      "spanSet" => %{"secret" => "hidden"}
    }

    stub(Req, :request, fn _ -> response(%{"traces" => [trace]}) end)
    assert {:ok, %{rows: [row], series: []}} = Pulse.query(ctx.user, ctx.account, "traces", %{})

    assert row == %{
             "trace_id" => "abc",
             "timestamp" => "1793966400000000001",
             "service" => "server",
             "name" => "GET /",
             "duration_ms" => 1.25
           }
  end

  test "logs and traces reject upstream responses exceeding the requested bound", ctx do
    values = Enum.map(1..101, &[Integer.to_string(&1), "line"])
    stub(Req, :request, fn _ -> response(stream_body([%{"stream" => %{}, "values" => values}])) end)
    assert {:error, :query_result_limit} = Pulse.query(ctx.user, ctx.account, "logs", %{})

    traces = Enum.map(1..101, &%{"traceID" => "trace", "startTimeUnixNano" => &1})
    stub(Req, :request, fn _ -> response(%{"traces" => traces}) end)
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
          {"metrics", Map.put(empty_body("metrics"), "warnings", [1])},
          {"logs", stream_body([%{"stream" => %{}, "values" => [["bad", "line"]]}])},
          {"traces", %{"traces" => [%{"traceID" => "trace", "startTimeUnixNano" => "1", "durationMs" => "bad"}]}}
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
        assert request.options.auth == {:bearer, token}
        response(empty_body("metrics"))
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

          assert request.url.path == "/api/v1/query_range"
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
          assert request.options.auth == {:bearer, "secret"}
          assert Req.Request.get_header(request, "x-scope-orgid") == ["tuist"]
          assert request.options.redirect == false
          assert request.options.retry == false
          assert request.options.receive_timeout == 30_000
          assert request.options.connect_options == [timeout: 10_000]
        end

        refute_receive {:analytics_request, _}
      end

      stub(Req, :request, fn request ->
        response(if request.url.path == "/api/v1/query", do: vector_body([]), else: metric_body([]))
      end)

      assert {:ok, %{widgets: widgets}} = Pulse.analytics(ctx.user, ctx.account, "metrics", %{})
      assert Enum.all?(widgets, &(&1.value == nil and &1.previous_value == nil and &1.points == []))
    end

    test "preserves measured zero, maps nonfinite observations to nil and deduplicates warnings", ctx do
      stub(DateTime, :utc_now, fn -> ~U[2026-11-06 12:00:00Z] end)
      finish = DateTime.to_unix(~U[2026-11-06 12:00:00Z])

      stub(Req, :request, fn request ->
        body =
          if request.url.path == "/api/v1/query" do
            value = if request.options.params[:time] == finish, do: "NaN", else: "0"
            vector_body([%{"value" => [request.options.params[:time], value]}])
          else
            metric_body([%{"values" => [[finish - 3600, "0"], [finish - 10, "0"], [finish, "+Inf"]]}])
          end

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

    test "current and previous missing, nonfinite and measured zero values stay independent", ctx do
      stub(DateTime, :utc_now, fn -> ~U[2026-11-06 12:00:00Z] end)
      finish = DateTime.to_unix(~U[2026-11-06 12:00:00Z])

      for signal <- ~w(metrics logs errors),
          {current, previous} <- [{nil, "0"}, {"0", nil}, {"0", "NaN"}, {"1", "+Inf"}, {"-Inf", "2"}] do
        stub(Req, :request, fn request ->
          params = request.options.params

          cond do
            signal == "metrics" ->
              points =
                Enum.reject([[finish - 3600, previous], [finish - 10, "7"], [finish, current]], &is_nil(List.last(&1)))

              response(metric_body([%{"values" => points}]))

            String.ends_with?(request.url.path, "query_range") ->
              response(metric_body([]))

            true ->
              time = String.to_integer(params[:time]) / 1_000_000_000
              value = if time == finish, do: current, else: previous
              entries = if is_nil(value), do: [], else: [%{"value" => [time, value]}]
              response(vector_body(entries))
          end
        end)

        assert {:ok, %{widgets: widgets}} = Pulse.analytics(ctx.user, ctx.account, signal, %{})
        expected_current = if current in ["0", "1"], do: String.to_integer(current)
        expected_previous = if previous in ["0", "2"], do: String.to_integer(previous)
        assert Enum.all?(widgets, &(&1.value == expected_current and &1.previous_value == expected_previous))
      end
    end

    test "event comparison windows keep the selected duration and aligned boundaries for every range", ctx do
      now = ~U[2026-11-06 12:00:07Z]
      stub(DateTime, :utc_now, fn -> now end)
      parent = self()

      for signal <- ~w(logs errors traces),
          {range, seconds, step} <- [{"15m", 900, 3}, {"1h", 3600, 10}, {"6h", 21_600, 60}, {"24h", 86_400, 240}] do
        step = if signal == "traces", do: step, else: max(60, step)
        finish = DateTime.to_unix(now) - rem(DateTime.to_unix(now), step)

        stub(Req, :request, fn request ->
          params = request.options.params
          instant = String.ends_with?(request.url.path, "/query")

          if signal == "traces" do
            assert params[:end] in [finish, finish - seconds]
            assert params[:start] == params[:end] - seconds
            if !instant, do: assert(params[:step] == "#{step}s")
            if instant, do: send(parent, {:comparison_end, params[:end]})
            response(%{"series" => []})
          else
            duration = if instant, do: seconds, else: step
            assert params[:query] =~ "[#{duration}s]"

            if instant do
              time = div(String.to_integer(params[:time]), 1_000_000_000)
              assert time in [finish, finish - seconds]
              send(parent, {:comparison_end, time})
            else
              assert params[:start] == Integer.to_string((finish - seconds + step) * 1_000_000_000)
              assert params[:end] == Integer.to_string(finish * 1_000_000_000)
            end

            response(if instant, do: vector_body([]), else: metric_body([]))
          end
        end)

        assert {:ok, _} = Pulse.analytics(ctx.user, ctx.account, signal, %{"range" => range})

        ends =
          for _ <- 1..6,
              do:
                (
                  assert_receive {:comparison_end, time}
                  time
                )

        assert Enum.sort(ends) == List.duplicate(finish - seconds, 3) ++ List.duplicate(finish, 3)
        refute_receive {:comparison_end, _}
      end
    end

    @tag :tmp_dir
    test "analytics reads projected credentials afresh for each complete snapshot", %{tmp_dir: tmp_dir} = ctx do
      path = Path.join(tmp_dir, "analytics-token")
      stub(Environment, :pulse_config, fn -> Keyword.put(ctx.config, :token_file, path) end)

      for token <- ["initial", "rotated"] do
        File.write!(path, token <> "\n")

        stub(Req, :request, fn request ->
          assert request.options.auth == {:bearer, token}
          response(if request.url.path == "/api/v1/query", do: vector_body([]), else: metric_body([]))
        end)

        assert {:ok, _} = Pulse.analytics(ctx.user, ctx.account, "metrics", %{})
      end

      File.rm!(path)
      reject(Req, :request, 1)
      assert {:error, :not_configured} = Pulse.analytics(ctx.user, ctx.account, "metrics", %{})
    end

    for signal <- ~w(logs errors) do
      test "#{signal} uses minute-aligned bins and independent full-window totals for every range", ctx do
        signal = unquote(signal)
        now = ~U[2026-11-06 12:03:59Z]
        stub(DateTime, :utc_now, fn -> now end)
        parent = self()

        for {range, seconds, step} <- [{"15m", 900, 60}, {"1h", 3600, 60}, {"6h", 21_600, 60}, {"24h", 86_400, 240}] do
          finish = DateTime.to_unix(now) - rem(DateTime.to_unix(now), step)

          selectors =
            if signal == "logs" do
              [
                ~s({service_name=~".+"}),
                ~s'{service_name=~".+",level=~"(?i)(error|fatal)"}',
                ~s'{service_name=~".+",level=~"(?i)(warning|warn)"}'
              ]
            else
              [
                ~s({error_source="sentry"}),
                ~s'{error_source="sentry",level=~"(?i)fatal"}',
                ~s({error_source="sentry",service_name=~".+"})
              ]
            end

          stub(Req, :request, fn request ->
            params = request.options.params
            instant = request.url.path == "/loki/api/v1/query"
            duration = if instant, do: seconds, else: step

            expected =
              Enum.with_index(selectors, fn selector, index ->
                counts = "count_over_time(#{selector}[#{duration}s])"

                if signal == "errors" and index == 2,
                  do: "count(sum by (service_name) (#{counts}))",
                  else: "sum(#{counts})"
              end)

            assert params[:query] in expected
            send(parent, {:log_query, params[:query]})
            refute Keyword.has_key?(params, :limit)

            if instant do
              assert params[:time] in Enum.map([finish, finish - seconds], &Integer.to_string(&1 * 1_000_000_000))
              value = if params[:time] == Integer.to_string(finish * 1_000_000_000), do: "12345", else: "23456"
              response(vector_body([%{"value" => [finish, value]}]))
            else
              assert request.url.path == "/loki/api/v1/query_range"
              assert params[:start] == Integer.to_string((finish - seconds + step) * 1_000_000_000)
              assert params[:end] == Integer.to_string(finish * 1_000_000_000)
              assert params[:step] == step
              assert rem(step, 60) == 0
              assert rem(finish, 60) == 0
              points = Enum.map((finish - seconds + step)..finish//step, &[&1, "7"])
              assert length(points) <= 360
              response(metric_body([%{"values" => points}]))
            end
          end)

          assert {:ok, %{widgets: widgets}} = Pulse.analytics(ctx.user, ctx.account, signal, %{"range" => range})

          assert Enum.map(widgets, & &1.id) ==
                   if(signal == "logs", do: ~w(entries errors warnings), else: ~w(events fatal services))

          assert Enum.all?(
                   widgets,
                   &(&1.value == 12_345 and &1.previous_value == 23_456 and
                       &1.points == Enum.map((finish - seconds + step)..finish//step, fn time -> [time, 7.0] end) and
                       &1.unit == :count)
                 )

          for _ <- 1..9, do: assert_receive({:log_query, _})
          refute_receive {:log_query, _}
        end
      end
    end

    test "minute bins preserve boundary totals and count repeated services once per full window", ctx do
      now = ~U[2026-11-06 12:00:59Z]
      stub(DateTime, :utc_now, fn -> now end)
      finish = DateTime.to_unix(now) - 59
      start = finish - 900

      events = [
        {start - 900, "outside"},
        {start, "previous"},
        {start + 1, "api"},
        {finish, "api"},
        {finish + 1, "outside"}
      ]

      stub(Req, :request, fn request ->
        params = request.options.params
        instant = request.url.path == "/loki/api/v1/query"
        duration = if instant, do: 900, else: 60
        assert params[:query] =~ "[#{duration}s]"
        services? = String.starts_with?(params[:query], "count(sum by (service_name)")

        count = fn time ->
          matching = Enum.filter(events, fn {timestamp, _} -> timestamp > time - duration and timestamp <= time end)
          if services?, do: matching |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> length(), else: length(matching)
        end

        if instant do
          time = div(String.to_integer(params[:time]), 1_000_000_000)
          assert time in [start, finish]
          response(vector_body([%{"value" => [time, Integer.to_string(count.(time))]}]))
        else
          assert params[:start] == Integer.to_string((start + 60) * 1_000_000_000)
          assert params[:end] == Integer.to_string(finish * 1_000_000_000)
          assert params[:step] == 60
          points = Enum.map((start + 60)..finish//60, &[&1, Integer.to_string(count.(&1))])
          response(metric_body([%{"values" => points}]))
        end
      end)

      for signal <- ~w(logs errors) do
        assert {:ok, %{widgets: widgets}} = Pulse.analytics(ctx.user, ctx.account, signal, %{"range" => "15m"})

        for widget <- widgets do
          assert widget.value == if(widget.id == "services", do: 1, else: 2)
          assert widget.previous_value == 1
          assert Enum.sum(Enum.map(widget.points, &List.last/1)) == 2
          assert hd(widget.points) == [start + 60, 1.0]
          assert List.last(widget.points) == [finish, 1.0]
        end
      end
    end

    test "Tempo full-window p95 is independent of bucket quantiles, seconds become milliseconds and empty buckets are gaps",
         ctx do
      stub(DateTime, :utc_now, fn -> ~U[2026-11-06 12:00:00Z] end)
      finish = DateTime.to_unix(~U[2026-11-06 12:00:00Z])
      parent = self()

      stub(Req, :request, fn request ->
        send(parent, {:trace_request, request})
        params = request.options.params
        assert params[:end] in [finish, finish - 3600]
        assert params[:start] == params[:end] - 3600

        assert params[:q] in [
                 "{} | count_over_time()",
                 "{status=error} | count_over_time()",
                 "{} | quantile_over_time(duration,0.95)"
               ]

        duration = String.contains?(params[:q], "quantile")

        if request.url.path == "/api/metrics/query" do
          refute Keyword.has_key?(params, :step)

          value =
            case {duration, params[:end] == finish} do
              {true, true} -> 0.45
              {true, false} -> 0.25
              {false, true} -> 500
              {false, false} -> 250
            end

          response(%{"series" => [%{"labels" => [], "value" => value}]})
        else
          assert request.url.path == "/api/metrics/query_range"
          assert params[:end] == finish
          assert params[:step] == "10s"

          samples =
            Enum.map(
              [
                {finish - 3600, 999},
                {finish - 20, 0},
                {finish - 10, if(duration, do: 0.1, else: 4)},
                {finish, if(duration, do: 0.9, else: 6)}
              ],
              fn {time, value} ->
                %{"timestampMs" => Integer.to_string(time * 1000), "value" => value}
              end
            )

          response(%{"series" => [%{"labels" => [], "samples" => samples}]})
        end
      end)

      assert {:ok, %{widgets: [spans, errors, duration]}} = Pulse.analytics(ctx.user, ctx.account, "traces", %{})
      assert spans.id == "spans"
      assert spans.value == 500
      assert spans.previous_value == 250
      assert errors.id == "errors"

      assert duration == %{
               id: "duration_p95",
               value: 450.0,
               previous_value: 250.0,
               unit: :milliseconds,
               points: [[finish - 20, nil], [finish - 10, 100.0], [finish, 900.0]]
             }

      for _ <- 1..9, do: assert_receive({:trace_request, _})
      refute_receive {:trace_request, _}

      stub(Req, :request, fn request ->
        response(
          if request.url.path == "/api/metrics/query", do: %{"series" => [%{"value" => 0}]}, else: %{"series" => []}
        )
      end)

      assert {:ok,
              %{
                widgets: [
                  %{value: 0, previous_value: 0},
                  %{value: 0, previous_value: 0},
                  %{value: nil, previous_value: nil}
                ]
              }} =
               Pulse.analytics(ctx.user, ctx.account, "traces", %{})
    end

    test "Tempo duration availability is determined independently by each period's span count", ctx do
      stub(DateTime, :utc_now, fn -> ~U[2026-11-06 12:00:00Z] end)
      finish = DateTime.to_unix(~U[2026-11-06 12:00:00Z])

      for {current_count, previous_count, current_duration, previous_duration, expected, previous_expected} <- [
            {0, 2, 0, 0.125, nil, 125.0},
            {2, 0, 0.125, 0, 125.0, nil},
            {nil, 2, 0, 0, nil, 0.0},
            {2, nil, 0, 0, 0.0, nil},
            {2, 2, "NaN", 0.125, nil, 125.0},
            {2, 2, 0.125, "+Inf", 125.0, nil}
          ] do
        stub(Req, :request, fn request ->
          params = request.options.params

          if request.url.path == "/api/metrics/query_range" do
            response(%{"series" => []})
          else
            current = params[:end] == finish
            duration = String.contains?(params[:q], "quantile")

            value =
              case {current, duration} do
                {true, true} -> current_duration
                {false, true} -> previous_duration
                {true, false} -> current_count
                {false, false} -> previous_count
              end

            response(%{"series" => if(is_nil(value), do: [], else: [%{"value" => value}])})
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
        stub(Req, :request, fn request ->
          response(if request.url.path == "/api/v1/query", do: vector_body([]), else: body)
        end)

        assert {:error, :malformed_response} = Pulse.analytics(ctx.user, ctx.account, "metrics", %{})
      end

      for body <- [
            %{"series" => [%{"samples" => [%{"timestampMs" => "bad", "value" => 1}]}]},
            %{"series" => [%{"samples" => List.duplicate(%{"timestampMs" => "1", "value" => 1}, 362)}]},
            %{"series" => [%{"samples" => []}, %{"samples" => []}]}
          ] do
        stub(Req, :request, fn request ->
          response(if request.url.path == "/api/metrics/query", do: %{"series" => []}, else: body)
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
        assert request.options.params[:end] == "1793966400000000000"

        response(
          stream_body([
            %{
              "stream" => %{"service_name" => "api-server", "level" => "error"},
              "values" => [["9", "needle"], ["10", "needle"]]
            },
            %{"stream" => %{"service_name" => "worker", "level" => "info"}, "values" => [["11", "needle"]]}
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

      traces =
        Enum.map([{1, 10}, {2, 2}, {3, nil}], fn {id, duration} ->
          %{"traceID" => "#{id}", "startTimeUnixNano" => id, "durationMs" => duration}
        end)

      stub(Req, :request, fn _ -> response(%{"traces" => traces}) end)

      assert {:ok, %{rows: rows}} =
               Pulse.query(ctx.user, ctx.account, "traces", %{"sort_by" => "duration_ms", "sort_order" => "asc"})

      assert Enum.map(rows, & &1["trace_id"]) == ~w(2 1 3)
    end

    test "equal log timestamps preserve every tied row across stable pages", ctx do
      stub(Req, :request, fn request ->
        direction = request.options.params[:direction]
        assert direction == "backward"
        values = [["10", "a"], ["10", "b"], ["10", "c"]]
        values = if direction == "forward", do: Enum.reverse(values), else: values
        response(stream_body([%{"stream" => %{}, "values" => values}]))
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

    test "full log and trace searches stay bounded without generated warnings and preserve upstream warnings", ctx do
      for count <- [99, 100], signal <- ~w(logs traces), warnings <- [[], ["upstream notice"]] do
        stub(Req, :request, fn request ->
          assert request.options.params[:limit] == 100

          body =
            if signal == "logs" do
              stream_body([%{"stream" => %{}, "values" => Enum.map(1..count, &["#{&1}", "line"])}])
            else
              %{"traces" => Enum.map(1..count, &%{"traceID" => "#{&1}", "startTimeUnixNano" => &1})}
            end

          response(Map.put(body, "warnings", warnings))
        end)

        assert {:ok, %{rows: rows, meta: meta, warnings: ^warnings}} =
                 Pulse.query(ctx.user, ctx.account, signal, %{"page" => 2, "page_size" => 20, "sort_order" => "asc"})

        assert length(rows) == 20
        assert hd(rows)["timestamp"] == "21"
        assert meta["total_count"] == count
        assert meta["total_pages"] == 5

        assert {:ok, %{rows: [], warnings: ^warnings, meta: %{"total_count" => 0}}} =
                 Pulse.query(ctx.user, ctx.account, signal, %{"service" => "absent"})
      end
    end

    test "responses beyond the requested ceiling still fail whole", ctx do
      stub(Req, :request, fn _ ->
        response(stream_body([%{"stream" => %{}, "values" => Enum.map(1..5000, &["#{&1}", "line"])}]))
      end)

      assert {:error, :query_result_limit} = Pulse.query(ctx.user, ctx.account, "logs", %{"service" => "absent"})

      stub(Req, :request, fn _ ->
        response(%{"traces" => Enum.map(1..1000, &%{"traceID" => "#{&1}", "startTimeUnixNano" => &1})})
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
                   {:data, JSON.encode!(empty_body("metrics"))},
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

  describe "native error issues and event details" do
    test "native issues collect byte pages in one snapshot before literal search and sorting", ctx do
      first = issue_row(1, 2, "first")
      second = issue_row(2, 10, "literal .* title")

      expect(Req, :request, fn request ->
        assert request.method == :post
        assert request.url.path == "/mcp"
        assert request.options.auth == {:bearer, "secret"}
        assert Req.Request.get_header(request, "mcp-protocol-version") == ["2026-07-28"]
        assert Req.Request.get_header(request, "mcp-method") == ["tools/call"]
        assert Req.Request.get_header(request, "mcp-name") == ["query_errors"]

        assert request.options.json["params"]["_meta"] == %{
                 "io.modelcontextprotocol/protocolVersion" => "2026-07-28",
                 "io.modelcontextprotocol/clientCapabilities" => %{},
                 "io.modelcontextprotocol/clientInfo" => %{"name" => "Tuist", "version" => Environment.version()}
               }

        args = request.options.json["params"]["arguments"]
        assert args["tenant"] == "tuist"
        assert args["limit"] == 5000
        assert args["end_ts_ns"] == 1_793_966_400_000_000_000
        assert args["start_ts_ns"] == 1_793_962_800_000_000_000
        assert args["environment"] == "production"
        response(error_page([first], 2, "next"))
      end)

      expect(Req, :request, fn request ->
        assert request.options.json["params"]["arguments"]["cursor"] == "next"
        response(error_page([second], 2))
      end)

      assert {:ok, %{rows: [row], meta: meta}} =
               Pulse.query(ctx.user, ctx.account, "errors", %{
                 "end_at" => "2026-11-06T12:00:00Z",
                 "environment" => "production",
                 "query" => ".*",
                 "sort_by" => "count"
               })

      assert row["title"] == "literal .* title"
      assert row["latest_event_id"] == second["event_id"]
      assert row["count"] == 1
      assert meta["total_count"] == 1

      stub(Req, :request, fn request ->
        if request.options.json["params"]["arguments"]["cursor"],
          do: response(error_page([second], 2)),
          else: response(error_page([first], 2, "next"))
      end)

      assert {:ok, %{rows: [row], meta: %{"total_count" => 2}}} =
               Pulse.query(ctx.user, ctx.account, "errors", %{
                 "sort_by" => "count",
                 "sort_order" => "desc",
                 "page_size" => 1,
                 "page" => 2
               })

      assert row["latest_event_id"] == first["event_id"]
    end

    test "native tool errors discard diagnostics and excessive byte pages fail with fixed bounds", ctx do
      for {diagnostic, reason} <- [
            {":query_result_limit: secret", :query_result_limit},
            {":query_scan_limit: secret", :query_result_limit},
            {":query_execution_limit: secret", :query_result_limit},
            {":query_sample_limit: secret", :query_result_limit},
            {":query_decoded_limit: secret", :query_result_limit},
            {":query_resource_limit: secret", :query_result_limit},
            {":query_timeout: secret", :timeout},
            {":query_overloaded: secret", :rate_limited},
            {":unrecognized_error: secret", :upstream_error},
            {":error_query_reset_required", :query_reset_required}
          ] do
        stub(Req, :request, fn _ ->
          response(%{"result" => %{"isError" => true, "content" => [%{"type" => "text", "text" => diagnostic}]}})
        end)

        assert {:error, ^reason} = Pulse.query(ctx.user, ctx.account, "errors", %{})
      end

      expect(Req, :request, 32, fn request ->
        number = String.to_integer(request.options.json["params"]["arguments"]["cursor"] || "0") + 1
        response(error_page([issue_row(number, 1, "issue")], 33, "#{number}"))
      end)

      assert {:error, :query_result_limit} = Pulse.query(ctx.user, ctx.account, "errors", %{})
    end

    test "changed snapshots, missing continuations and native errors never return partial issues", ctx do
      for final <- [
            error_page([issue_row(2, 1, "b")], 2, nil, "changed"),
            error_page([], 2),
            %{"result" => %{"isError" => true, "content" => [%{"type" => "text", "text" => "secret diagnostic"}]}}
          ] do
        expect(Req, :request, fn _ -> response(error_page([issue_row(1, 1, "a")], 2, "next")) end)
        expect(Req, :request, fn _ -> response(final) end)
        assert {:error, reason} = Pulse.query(ctx.user, ctx.account, "errors", %{})
        assert reason in [:malformed_response, :upstream_error]
      end
    end

    test "native occurrence ceiling is accepted exactly and never yields a partial larger cohort", ctx do
      records =
        Enum.map(1..5000, fn id ->
          id |> event_row(id) |> Map.put("event", %{"message" => "bounded"})
        end)

      stub(Req, :request, fn _ -> response(error_page(records, 5000)) end)
      assert {:ok, %{rows: [row]}} = Pulse.query(ctx.user, ctx.account, "errors", %{})
      assert row["count"] == 5000
      assert row["latest_event_id"] == hex(5000, 32)
      assert Enum.sum(Enum.map(row["occurrence_series"], &List.last/1)) == 5000

      stub(Req, :request, fn _ -> response(error_page(records, 5001, "more")) end)
      assert {:error, :malformed_response} = Pulse.query(ctx.user, ctx.account, "errors", %{})
    end

    test "text operators filter occurrences before grouping and counting", ctx do
      records = [
        event_row(1, 10, "api", "production"),
        event_row(2, 9, "api", "preview"),
        event_row(3, 8, "worker", "production")
      ]

      expect(Req, :request, fn request ->
        assert request.options.json["params"]["name"] == "query_errors"
        refute Map.has_key?(request.options.json["params"]["arguments"], "environment")
        response(error_page(records, 3))
      end)

      assert {:ok, %{rows: [row]}} =
               Pulse.query(ctx.user, ctx.account, "errors", %{
                 "environment" => "PROD",
                 "environment_op" => "contains",
                 "service" => "work",
                 "service_op" => "not_contains"
               })

      assert row["count"] == 1
      assert row["latest_event_id"] == hex(1, 32)
    end

    test "issue pages are newest first, exact, bounded and never contain raw payloads", ctx do
      records = [event_row(1, 9), event_row(2, 10)]

      stub(Req, :request, fn request ->
        assert request.options.json["params"]["arguments"]["issue_id"] == issue_id()
        response(error_page(records, 2))
      end)

      assert {:ok, %{issue: issue, events: [event], meta: meta, warnings: []}} =
               Pulse.error_issue(ctx.user, ctx.account, issue_id(), %{"page_size" => 1, "page" => 2})

      assert issue["count"] == 2
      assert issue["last_seen_ns"] == 10
      assert event["event_id"] == hex(1, 32)
      assert event["timestamp"] == "9"
      assert event["exception"]["type"] == "RuntimeError"
      assert length(event["exception"]["frames"]) == 100
      refute inspect(event) =~ "private"
      refute inspect(event) =~ "locals"
      assert event["contexts"] == %{"secret" => "[REDACTED]"}
      assert meta["total_count"] == 2
      assert {:ok, %{events: []}} = Pulse.error_issue(ctx.user, ctx.account, issue_id(), %{"page" => 50})
    end

    test "issue overview covers the full selected period before numbered pagination", ctx do
      finish = DateTime.to_unix(~U[2026-11-06 12:00:00Z])

      for {range, seconds} <- [{"15m", 900}, {"1h", 3600}, {"6h", 21_600}, {"24h", 86_400}] do
        start = finish - seconds
        width = div(seconds, 60)

        records = [
          event_row(1, start * 1_000_000_000),
          event_row(2, (start + width) * 1_000_000_000 - 1),
          event_row(3, (start + width) * 1_000_000_000),
          event_row(4, (start + 17 * width + 2) * 1_000_000_000),
          event_row(5, finish * 1_000_000_000),
          event_row(6, (finish - 1) * 1_000_000_000, "api", "preview")
        ]

        # Each detail request follows the existing native continuation only;
        # neither the histogram nor the latest preview makes another request.
        expect(Req, :request, 8, fn request ->
          args = request.options.json["params"]["arguments"]
          assert args["start_ts_ns"] == start * 1_000_000_000
          assert args["end_ts_ns"] == finish * 1_000_000_000
          refute Map.has_key?(args, "environment")

          if args["cursor"],
            do: response(error_page(Enum.drop(records, 2), 6)),
            else: response(error_page(Enum.take(records, 2), 6, "next"))
        end)

        params = %{
          "range" => range,
          "end_at" => "2026-11-06T12:00:00Z",
          "environment" => "PROD",
          "environment_op" => "contains",
          "page_size" => 1
        }

        assert {:ok, first} = Pulse.error_issue(ctx.user, ctx.account, issue_id(), params)
        assert {:ok, second} = Pulse.error_issue(ctx.user, ctx.account, issue_id(), Map.put(params, "page", 2))
        assert {:ok, empty} = Pulse.error_issue(ctx.user, ctx.account, issue_id(), Map.put(params, "page", 50))
        assert {:ok, %{rows: [listed]}} = Pulse.query(ctx.user, ctx.account, "errors", params)
        assert listed == first.issue

        assert [first.latest_event] == first.events
        assert first.latest_event["event_id"] == hex(5, 32)
        assert first.latest_event == second.latest_event
        assert first.latest_event == empty.latest_event
        assert length(first.latest_event["exception"]["frames"]) == 100
        refute inspect(first.latest_event) =~ "private"
        refute inspect(first.latest_event) =~ "locals"
        assert Enum.map(second.events, & &1["event_id"]) == [hex(4, 32)]
        assert empty.events == []

        expected =
          Enum.map(0..59, fn bucket ->
            [start + bucket * width, Map.get(%{0 => 2, 1 => 1, 17 => 1, 59 => 1}, bucket, 0)]
          end)

        assert first.occurrence_series == expected
        assert second.occurrence_series == expected
        assert empty.occurrence_series == expected
        assert listed["occurrence_series"] == expected

        for result <- [first, second, empty] do
          total = Enum.sum(Enum.map(result.occurrence_series, fn [_, count] -> count end))
          assert total == 5
          assert total == result.issue["count"]
          assert total == result.meta["total_count"]
          assert result.issue["latest_event_id"] == result.latest_event["event_id"]
        end
      end
    end

    test "issue rows use latest filtered metadata and whole-cohort counts before sorting and paging", ctx do
      finish = 1_793_966_400
      start = finish - 3600
      older = event_row(1, start * 1_000_000_000)
      newer = event_row(2, finish * 1_000_000_000, "worker")
      newer = put_in(newer, ["event", "platform"], "elixir")
      newer = put_in(newer, ["event", "level"], "fatal")

      newer =
        put_in(newer, ["event", "exception", "values"], [
          %{
            "type" => "LatestError",
            "value" => "latest title",
            "stacktrace" => %{
              "frames" =>
                [%{"module" => "Recorded", "function" => "run", "in_app" => true}] ++
                  List.duplicate(%{"module" => "Dependency", "function" => "last"}, 101)
            }
          }
        ])

      excluded = event_row(3, finish * 1_000_000_000, "preview", "preview")
      other = 4 |> event_row((finish - 10) * 1_000_000_000) |> Map.put("project", "2")
      records = [newer, excluded, older, other]

      expect(Req, :request, 8, fn request ->
        assert request.options.json["params"]["name"] == "query_errors"
        args = request.options.json["params"]["arguments"]
        refute Map.has_key?(args, "issue_id")
        refute Map.has_key?(args, "environment")

        if args["cursor"],
          do: response(error_page(Enum.drop(records, 2), 4)),
          else: response(error_page(Enum.take(records, 2), 4, "next"))
      end)

      params = %{
        "end_at" => "2026-11-06T12:00:00Z",
        "page_size" => 1,
        "sort_by" => "count",
        "environment" => "PROD",
        "environment_op" => "contains"
      }

      assert {:ok, %{rows: [row], meta: %{"total_count" => 2}}} = Pulse.query(ctx.user, ctx.account, "errors", params)
      assert row["count"] == 2
      assert row["service"] == "worker"
      assert row["title"] == "LatestError: latest title"
      assert row["platform"] == "elixir"
      assert row["level"] == "fatal"
      assert row["culprit"] == "Recorded.run"
      assert row["latest_event_id"] == hex(2, 32)
      assert row["first_seen_ns"] == start * 1_000_000_000
      assert row["last_seen_ns"] == finish * 1_000_000_000
      assert row["occurrence_series"] == Enum.map(0..59, &[start + &1 * 60, if(&1 in [0, 59], do: 1, else: 0)])

      assert {:ok, %{rows: [second]}} = Pulse.query(ctx.user, ctx.account, "errors", Map.put(params, "page", 2))
      assert second["project"] == "2"
      assert second["count"] == 1
      assert Enum.sum(Enum.map(second["occurrence_series"], &List.last/1)) == 1

      assert {:ok, %{rows: [^row, ^second]}} =
               Pulse.query(ctx.user, ctx.account, "errors", Map.put(params, "page_size", 100))

      assert {:ok, %{rows: [^second]}} =
               Pulse.query(ctx.user, ctx.account, "errors", Map.put(params, "sort_order", "asc"))
    end

    test "recorded detail sections preserve typed JSON, redact sensitive data and remain untrusted text", ctx do
      malicious = ~s|<script>alert("payload")</script>|
      record = event_row(1, 10)

      record =
        update_in(
          record["event"],
          &Map.merge(&1, %{
            "platform" => "javascript",
            "culprit" => "invented root culprit",
            "tags" => [
              ["region", "eu"],
              ["attempt", 3],
              ["enabled", true],
              ["empty", nil],
              ["API-Key", "private-key"],
              ["bad"],
              2
            ],
            "contexts" => %{"runtime" => %{"name" => "BEAM", "version" => 29, "Authorization" => "private-auth"}},
            "extra" => %{
              "html" => malicious,
              "nested" => [%{"password" => "private-password", "vars" => %{"value" => "private-local"}}],
              "command" => "--token private-token",
              "url" => "https://admin:private-pass@example.com",
              "ratio" => 1.5
            },
            "modules" => %{"package" => "1.2.3", "access_token" => "private-access"}
          })
        )

      stub(Req, :request, fn _ -> response(error_page([record], 1)) end)
      assert {:ok, %{event: event}} = Pulse.error_event(ctx.user, ctx.account, issue_id(), hex(1, 32), %{})
      assert event["platform"] == "javascript"
      assert event["culprit"] == "app.ex.run"

      assert event["tags"] == %{
               "region" => "eu",
               "attempt" => 3,
               "enabled" => true,
               "empty" => nil,
               "API-Key" => "[REDACTED]"
             }

      assert event["contexts"]["runtime"]["version"] == 29
      assert event["contexts"]["runtime"]["Authorization"] == "[REDACTED]"
      assert event["extra"]["html"] == malicious
      assert event["extra"]["ratio"] == 1.5
      assert event["extra"]["nested"] == [%{"password" => "[REDACTED]", "vars" => "[REDACTED]"}]
      assert event["modules"] == %{"package" => "1.2.3", "access_token" => "[REDACTED]"}
      assert Phoenix.HTML.safe_to_string(Phoenix.HTML.html_escape(event["extra"]["html"])) =~ "&lt;script&gt;"
      refute Map.has_key?(event, "request")
      refute Map.has_key?(event, "user")
      refute JSON.encode!(event) =~ "private"
      refute JSON.encode!(event) =~ "invented"
    end

    test "metadata bounds deep, wide, multibyte and serialization-expanding input with visible markers", ctx do
      deep = Enum.reduce(1..100, "private-deep", fn _, value -> %{"child" => value} end)
      many = Map.new(1..100, &{"field#{&1}", &1})
      oversized = Map.new(1..50, &{"field#{&1}", String.duplicate("\"", 1024)})
      record = event_row(1, 10)

      for {section, value} <- [
            {"tags", many},
            {"tags", Enum.map(1..100, &["tag#{&1}", &1])},
            {"contexts", %{"deep" => deep}},
            {"extra", %{"list" => Enum.to_list(1..100)}},
            {"extra", %{"text" => String.duplicate("😀", 1000)}},
            {"extra", %{"combining" => "x" <> String.duplicate("\u0301", 10_000)}},
            {"modules", oversized},
            {"extra", %{String.duplicate("key", 100) => "private-key"}},
            {"extra", %{"nodes" => List.duplicate(Enum.to_list(1..50), 50)}}
          ] do
        record = put_in(record, ["event", section], value)
        stub(Req, :request, fn _ -> response(error_page([record], 1)) end)
        assert {:ok, %{event: event}} = Pulse.error_event(ctx.user, ctx.account, issue_id(), hex(1, 32), %{})
        encoded = JSON.encode!(event[section])
        assert byte_size(encoded) <= 4096
        assert encoded =~ "[TRUNCATED]"
        refute encoded =~ "private"
        assert String.valid?(encoded)
        assert JSON.decode!(encoded) == event[section]
      end
    end

    test "sparse and malformed metadata never manufactures platform, culprit or recorded sections", ctx do
      for payload <- [%{}, %{"platform" => 12, "tags" => "bad", "contexts" => [], "extra" => true, "modules" => nil}] do
        record = Map.put(event_row(1, 10), "event", payload)
        stub(Req, :request, fn _ -> response(error_page([record], 1)) end)
        assert {:ok, %{event: event}} = Pulse.error_event(ctx.user, ctx.account, issue_id(), hex(1, 32), %{})
        assert is_nil(event["platform"])
        assert is_nil(event["culprit"])
        assert Map.take(event, ~w(tags contexts extra modules)) == Map.new(~w(tags contexts extra modules), &{&1, %{}})
      end
    end

    test "metadata accepts exact entry, depth, key, text and serialized byte bounds", ctx do
      sections = %{
        "tags" => Map.new(1..50, &{"key#{&1}", &1}),
        "contexts" => %{"child" => Enum.reduce(1..4, false, fn _, value -> %{"child" => value} end)},
        "extra" => %{String.duplicate("k", 128) => String.duplicate("x", 1024)},
        "modules" => %{
          "a" => String.duplicate("x", 1024),
          "b" => String.duplicate("x", 1024),
          "c" => String.duplicate("x", 1024),
          "d" => ""
        }
      }

      size = byte_size(JSON.encode!(sections["modules"]))
      sections = put_in(sections, ["modules", "d"], String.duplicate("x", 4096 - size))
      assert byte_size(JSON.encode!(sections["modules"])) == 4096
      record = update_in(event_row(1, 10)["event"], &Map.merge(&1, sections))
      stub(Req, :request, fn _ -> response(error_page([record], 1)) end)
      assert {:ok, %{event: event}} = Pulse.error_event(ctx.user, ctx.account, issue_id(), hex(1, 32), %{})
      assert Map.take(event, Map.keys(sections)) == sections

      record = update_in(record, ["event", "modules", "d"], &(&1 <> "x"))
      stub(Req, :request, fn _ -> response(error_page([record], 1)) end)
      assert {:ok, %{event: event}} = Pulse.error_event(ctx.user, ctx.account, issue_id(), hex(1, 32), %{})
      assert event["modules"] == %{"[TRUNCATED]" => "[TRUNCATED]"}
    end

    test "shared HTTP and MCP issue schemas require the overview fields" do
      schema = Pulse.Schemas.response(:issue)
      assert :latest_event in schema.required
      assert :occurrence_series in schema.required
      assert schema.properties.latest_event == Pulse.Schemas.event()

      json = Pulse.Schemas.json_schema(schema)
      assert "latest_event" in json["required"]
      assert "occurrence_series" in json["required"]
      assert json["properties"]["occurrence_series"]["type"] == "array"
      assert json["properties"]["issue"]["properties"]["occurrence_series"]["type"] == "array"
      assert json["properties"]["occurrence_series"]["minItems"] == 60
      assert json["properties"]["occurrence_series"]["maxItems"] == 60
      assert json["properties"]["occurrence_series"]["items"]["minItems"] == 2
      assert json["properties"]["occurrence_series"]["items"]["items"]["type"] == "integer"

      for field <- ~w(tags contexts extra modules) do
        metadata = json["properties"]["latest_event"]["properties"][field]
        assert metadata["type"] == "object"
        assert metadata["additionalProperties"] == %{}
        assert metadata["description"] =~ "4096"
      end

      refute "platform" in json["properties"]["issue"]["required"]
    end

    test "event detail validates identities, returns safe fields and distinguishes not found", ctx do
      expect(Req, :request, fn request ->
        args = request.options.json["params"]["arguments"]
        assert args["event_id"] == hex(1, 32)
        assert args["issue_id"] == issue_id()
        response(error_page([event_row(1, 10)], 1))
      end)

      assert {:ok, %{event: event}} = Pulse.error_event(ctx.user, ctx.account, issue_id(), hex(1, 32), %{})
      assert event["environment"] == "production"
      assert event["release"] == "v1"
      assert event["title"] == "RuntimeError: boom"
      stub(Req, :request, fn _ -> response(error_page([], 0)) end)
      assert {:error, :not_found} = Pulse.error_event(ctx.user, ctx.account, issue_id(), hex(1, 32), %{})
      assert {:error, :not_found} = Pulse.error_issue(ctx.user, ctx.account, issue_id(), %{})
      assert {:error, :invalid_params} = Pulse.error_event(ctx.user, ctx.account, "bad", hex(1, 32), %{})
      assert {:error, :invalid_params} = Pulse.error_event(ctx.user, ctx.account, issue_id(), "bad", %{})
      assert {:error, :invalid_params} = Pulse.error_issue(ctx.user, ctx.account, issue_id(), %{"tenant" => "other"})
    end

    test "error details recheck current membership before HTTP", ctx do
      outsider = AccountsFixtures.user_fixture()
      :ok = Accounts.add_user_to_organization(outsider, ctx.organization)
      Accounts.remove_user_from_organization(outsider, ctx.organization)
      reject(Req, :request, 1)

      for user <- [nil, outsider] do
        assert {:error, :forbidden} = Pulse.error_issue(user, ctx.account, issue_id(), %{})
        assert {:error, :forbidden} = Pulse.error_event(user, ctx.account, issue_id(), hex(1, 32), %{})
      end
    end

    @tag :tmp_dir
    test "cursor requests reread rotated token files", %{tmp_dir: tmp_dir} = ctx do
      path = Path.join(tmp_dir, "token")
      File.write!(path, "first")
      stub(Environment, :pulse_config, fn -> Keyword.put(ctx.config, :token_file, path) end)

      expect(Req, :request, fn request ->
        assert request.options.auth == {:bearer, "first"}
        File.write!(path, "rotated")
        response(error_page([issue_row(1, 1, "a")], 2, "next"))
      end)

      expect(Req, :request, fn request ->
        assert request.options.auth == {:bearer, "rotated"}
        response(error_page([issue_row(2, 1, "b")], 2))
      end)

      assert {:ok, %{rows: rows}} = Pulse.query(ctx.user, ctx.account, "errors", %{})
      assert length(rows) == 2
    end
  end

  defp hex(id, size), do: id |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(size, "0")
  defp issue_id, do: "v1_" <> hex(1, 64)

  defp issue_row(id, timestamp, title) do
    id
    |> event_row(timestamp)
    |> Map.put("issue_id", "v1_" <> hex(id, 64))
    |> Map.put("event", %{"message" => title, "environment" => "production"})
  end

  defp event_row(id, timestamp, service \\ "api", environment \\ "production") do
    %{
      "issue_id" => issue_id(),
      "project" => "1",
      "service" => service,
      "event_id" => hex(id, 32),
      "timestamp_ns" => timestamp,
      "event" => %{
        "level" => "error",
        "environment" => environment,
        "release" => "v1",
        "request" => %{"authorization" => "private"},
        "user" => %{"email" => "private"},
        "contexts" => %{"secret" => "private"},
        "exception" => %{
          "values" => [
            %{
              "type" => "RuntimeError",
              "value" => "boom",
              "stacktrace" => %{
                "frames" =>
                  List.duplicate(
                    %{"filename" => "app.ex", "function" => "run", "lineno" => 12, "vars" => %{"locals" => "private"}},
                    101
                  )
              }
            }
          ]
        }
      }
    }
  end

  defp error_page(rows, count, cursor \\ nil, snapshot \\ "snapshot") do
    %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "result" => %{
        "isError" => false,
        "content" => [
          %{
            "type" => "text",
            "text" =>
              JSON.encode!(%{
                "results" => rows,
                "matched_results" => count,
                "matched_events" => count,
                "snapshot_id" => snapshot,
                "next_cursor" => cursor
              })
          }
        ]
      }
    }
  end

  defp response(body), do: {:ok, %Req.Response{status: 200, body: body}}
  defp vector_body(entries), do: %{"status" => "success", "data" => %{"resultType" => "vector", "result" => entries}}

  defp scalar_body(value), do: %{"status" => "success", "data" => %{"resultType" => "scalar", "result" => value}}
  defp empty_body("metrics"), do: metric_body([])
  defp empty_body("traces"), do: %{"traces" => []}
  defp empty_body(_signal), do: stream_body([])
  defp metric_body(entries), do: %{"status" => "success", "data" => %{"resultType" => "matrix", "result" => entries}}
  defp stream_body(entries), do: %{"status" => "success", "data" => %{"resultType" => "streams", "result" => entries}}
end
