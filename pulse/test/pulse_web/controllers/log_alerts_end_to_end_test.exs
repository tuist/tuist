defmodule PulseWeb.LogAlertsEndToEndTest do
  use PulseWeb.ConnCase, async: true

  alias Pulse.Alerting.{Canonical, Evaluator, Notifier, Repository}
  alias Pulse.Alerting.Tools
  alias Pulse.Alerting.Worker
  alias Pulse.PromQL.Evaluator, as: PromQL
  alias Pulse.Runtime
  alias Pulse.Runtime.Task
  alias Pulse.Storage
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.{Manifest, ManifestCache, ManifestSupervision}
  alias Pulse.Test.CompactionStore

  @tick 10_000_000_000
  @query ~s'sum by(service)(count_over_time({service="api"} |= "error" [10s]))'
  setup do
    agent =
      start_supervised!(
        {Agent,
         fn ->
           %{
             objects: %{},
             reads: [],
             version: 0,
             hook: nil,
             faults: %{},
             barriers: %{},
             lists: 0,
             deletes: [],
             requests: []
           }
         end}
      )

    server = start_supervised!({Bandit, plug: {CompactionStore, agent: agent}, ip: {127, 0, 0, 1}, port: 0})
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

    config = %{
      bucket: "pulse",
      endpoint: "http://127.0.0.1:#{port}",
      region: "us-east-1",
      access_key_id: "test",
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 60_000
    }

    actor = %{
      tenant: "log-alerts",
      id: "pedro",
      type: "human",
      token_hash: Canonical.digest("admin-token"),
      capabilities: ~w(alert:read alert:rules:write alert:audit:read alert:preview alert:evaluate)
    }

    target = %{
      "tenant" => actor.tenant,
      "id" => "slack",
      "type" => "slack_webhook",
      "secret_env" => "PULSE_ALERTING_TEST_LOG_WEBHOOK"
    }

    Runtime.put_env(:pulse, Storage, adapter: S3)
    Runtime.put_env(:pulse, S3, config)
    start_supervised!(ManifestSupervision)
    Runtime.put_env(:pulse, Pulse.Alerting, principals: [actor], store_config: config, notification_targets: [target])
    Runtime.put_env("PULSE_ALERTING_TEST_LOG_WEBHOOK", "https://notifications.invalid/test-token")
    %{agent: agent, actor: actor, config: config}
  end

  defp ingest(tenant, timestamp, body) do
    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-scope-orgid", tenant)
      |> post("/loki/api/v1/push", %{
        "streams" => [%{"stream" => %{"service" => "api"}, "values" => [[Integer.to_string(timestamp), body]]}]
      })

    assert conn.status == 204
  end

  defp create(extra \\ %{}) do
    rule =
      Map.merge(
        %{
          "kind" => "logql_threshold",
          "name" => "API errors",
          "query" => @query,
          "threshold" => %{"op" => "gt", "value" => 0},
          "enabled" => true,
          "cadence_ms" => 10_000,
          "no_data_policy" => "ok"
        },
        extra
      )

    create_rule(rule)
  end

  defp create_rule(rule) do
    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer admin-token")
      |> put_req_header("x-scope-orgid", "log-alerts")
      |> post("/api/v1/alerting/rules/api-errors", %{
        "rule" => rule,
        "operation_id" => "create",
        "reason" => "Alert on persisted API errors"
      })

    assert json_response(conn, 200)["rule"]["kind"] == rule["kind"]
  end

  defp ingest_metric(tenant, time, value, extra_attributes \\ []) do
    point = %{
      "timeUnixNano" => Integer.to_string(time),
      "asDouble" => value,
      "attributes" => [%{"key" => "service", "value" => %{"stringValue" => "api"}}] ++ extra_attributes
    }

    body = %{
      "resourceMetrics" => [
        %{"scopeMetrics" => [%{"metrics" => [%{"name" => "requests", "gauge" => %{"dataPoints" => [point]}}]}]}
      ]
    }

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-scope-orgid", tenant)
      |> post("/v1/metrics", body)

    assert json_response(conn, 200) == %{}
  end

  defp expression_rule(extra \\ %{}) do
    Map.merge(
      %{
        "kind" => "expression_threshold",
        "name" => "API errors",
        "sources" => [
          %{"ref" => "errors", "language" => "logql", "query" => @query},
          %{"ref" => "requests", "language" => "promql", "query" => "requests{service=\"api\"}"}
        ],
        "expression" => "$errors > 0 && $requests > 100",
        "threshold" => %{"op" => "gt", "value" => 0},
        "enabled" => true,
        "cadence_ms" => 10_000,
        "no_data_policy" => "ok"
      },
      extra
    )
  end

  defp evaluate(ctx, tick),
    do: Evaluator.evaluate(ctx.actor, "api-errors", timestamp_ns: tick, store_config: ctx.config)

  defp root_key(tenant, signal \\ "logs"), do: "tenants/#{tenant}/v4/signal=#{signal}/manifest.json"

  test "HTTP ingest to Parquet, HTTP query, durable lifecycle/restart, and Slack outbox", ctx do
    create(%{"for_ms" => 10_000, "keep_firing_ms" => 10_000, "notification_targets" => ["slack"]})
    ingest(ctx.actor.tenant, @tick, "error: backup failed")
    ingest("other-tenant", @tick, "error: unrelated")
    assert Agent.get(ctx.agent, fn state -> Enum.any?(Map.keys(state.objects), &String.ends_with?(&1, ".parquet")) end)

    query =
      build_conn()
      |> put_req_header("x-scope-orgid", ctx.actor.tenant)
      |> get("/loki/api/v1/query", %{"query" => @query, "time" => Integer.to_string(@tick)})
      |> json_response(200)

    assert [%{"value" => [_, "1"]}] = query["data"]["result"]
    assert {:ok, pending} = evaluate(ctx, @tick)
    assert [%{"status" => "pending"}] = Map.values(pending["instances"])
    assert 0 = Notifier.run_once(ctx.actor.tenant, "api-errors")
    ingest(ctx.actor.tenant, 2 * @tick, "error: still failing")
    callers = start_supervised!({Task.Supervisor, []})
    restarted = Task.Supervisor.async_nolink(callers, fn -> evaluate(ctx, 2 * @tick) end)
    assert {:ok, firing} = Task.await(restarted, 5000)
    assert [%{"status" => "firing", "pending_since_ns" => "10000000000"}] = Map.values(firing["instances"])
    owner = self()

    Req.Test.stub(:log_alert_slack, fn conn ->
      {:ok, bytes, conn} = Plug.Conn.read_body(conn)
      send(owner, {:slack, Pulse.JSON.decode!(bytes)})
      Plug.Conn.send_resp(conn, 200, "ok")
    end)

    assert 1 = Notifier.run_once(ctx.actor.tenant, "api-errors", http_options: [plug: {Req.Test, :log_alert_slack}])
    assert_receive {:slack, delivered}
    assert get_in(delivered, ["blocks", Access.at(0), "text", "text"]) =~ "FIRING: API errors"
    assert {:ok, recovering} = evaluate(ctx, 3 * @tick)
    assert recovering["health"] == "no_data"
    assert [%{"status" => "recovering", "hold_until_ns" => "40000000000"}] = Map.values(recovering["instances"])
    assert {:ok, resolved} = evaluate(ctx, 4 * @tick)
    assert resolved["instances"] == %{}
    assert 1 = Notifier.run_once(ctx.actor.tenant, "api-errors", http_options: [plug: {Req.Test, :log_alert_slack}])
    assert_receive {:slack, _}
    assert {:ok, events} = Pulse.Alerting.events(ctx.actor, "api-errors")

    assert Enum.map(events["events"], & &1["type"]) == [
             "pending",
             "health_changed",
             "firing",
             "recovering",
             "health_changed",
             "resolved"
           ]

    assert {:error, :not_due} = evaluate(ctx, 2 * @tick)
  end

  test "durable rule discovery automatically evaluates stored logs through the existing worker", ctx do
    create(%{"query" => ~s'sum(count_over_time({service="api"} |= "error" [2m]))'})
    time = div(System.system_time(:nanosecond), @tick) * @tick - 1
    ingest(ctx.actor.tenant, time, "error")
    assert {:ok, 1} = Worker.run_once([store_config: ctx.config], [node()])
    assert {:ok, state} = Pulse.Alerting.state(ctx.actor, "api-errors")
    assert [%{"status" => "firing"}] = Map.values(state["instances"])
    assert state["health"] == "ok"
    assert String.to_integer(state["completed_at_ns"]) >= time
    before = Agent.get(ctx.agent, & &1.objects)
    conn = build_conn() |> put_req_header("authorization", "Bearer admin-token")

    assert {:ok, [%{"text" => json}]} =
             Tools.call("preview_alert_rule", %{"tenant" => ctx.actor.tenant, "id" => "api-errors"}, %{conn: conn})

    assert Pulse.JSON.decode!(json)["health"] == "ok"
    assert Agent.get(ctx.agent, & &1.objects) == before
  end

  test "mixed persisted log and metric conditions drive durable pending, firing, holds and recovery", ctx do
    create_rule(expression_rule(%{"for_ms" => 10_000, "keep_firing_ms" => 10_000}))
    ingest_metric(ctx.actor.tenant, @tick, 200.0)
    ingest(ctx.actor.tenant, @tick, "error")
    before = Agent.get(ctx.agent, & &1.objects)
    assert {:ok, preview} = Evaluator.preview(ctx.actor, "api-errors", timestamp_ns: @tick, store_config: ctx.config)
    assert preview["health"] == "ok"
    assert Agent.get(ctx.agent, & &1.objects) == before
    assert {:ok, pending} = evaluate(ctx, @tick)
    assert [%{"status" => "pending"}] = Map.values(pending["instances"])
    ingest(ctx.actor.tenant, 2 * @tick, "error")
    assert {:ok, firing} = Task.async(fn -> evaluate(ctx, 2 * @tick) end) |> Task.await()
    assert [%{"status" => "firing"}] = Map.values(firing["instances"])
    ingest_metric(ctx.actor.tenant, 3 * @tick, 10.0)
    ingest(ctx.actor.tenant, 3 * @tick, "error")
    assert {:ok, held} = evaluate(ctx, 3 * @tick)
    assert [%{"status" => "recovering", "hold_until_ns" => time}] = Map.values(held["instances"])
    assert time == Integer.to_string(4 * @tick)
    ingest(ctx.actor.tenant, 4 * @tick, "error")
    assert {:ok, resolved} = evaluate(ctx, 4 * @tick)
    assert resolved["instances"] == %{}
    assert resolved["health"] == "ok"
    assert {:ok, events} = Pulse.Alerting.events(ctx.actor, "api-errors")

    assert Enum.map(events["events"], & &1["type"]) == [
             "pending",
             "health_changed",
             "firing",
             "recovering",
             "resolved"
           ]
  end

  test "explicit empty scalar zero resolves quiet logs, but never substitutes missing authority", ctx do
    definition = put_in(expression_rule(), ["sources", Access.at(0), "empty_value"], 0)
    create_rule(Map.put(definition, "no_data_policy", "keep_last"))
    ingest_metric(ctx.actor.tenant, @tick, 200.0)
    assert {:error, :evaluation_skipped} = evaluate(ctx, @tick)
    ingest(ctx.actor.tenant, @tick, "error")
    assert {:ok, firing} = evaluate(ctx, @tick)
    assert map_size(firing["instances"]) == 1
    assert {:ok, resolved} = evaluate(ctx, 2 * @tick)
    assert resolved["health"] == "ok"
    assert resolved["instances"] == %{}
  end

  test "fixed expression label limits publish error health instead of silently skipping forever", ctx do
    create_rule(expression_rule())
    ingest_metric(ctx.actor.tenant, @tick, 200.0)
    ingest(ctx.actor.tenant, @tick, "error")
    assert {:ok, firing} = evaluate(ctx, @tick)
    extra = for n <- 1..32, do: %{"key" => "label_#{n}", "value" => %{"stringValue" => "value"}}
    ingest_metric(ctx.actor.tenant, 2 * @tick, 200.0, extra)
    assert {:ok, degraded} = evaluate(ctx, 2 * @tick)
    assert degraded["health"] == "error"
    assert degraded["instances"] == firing["instances"]
    assert degraded["completed_at_ns"] == Integer.to_string(2 * @tick)
  end

  test "mixed conditions execute through durable worker discovery and read-only MCP preview", ctx do
    definition = expression_rule()

    sources =
      update_in(definition["sources"], [Access.at(0), "query"], fn _ ->
        ~s'sum by(service)(count_over_time({service="api"} |= "error" [5m]))'
      end)

    create_rule(Map.put(definition, "sources", sources))
    time = div(System.system_time(:nanosecond), @tick) * @tick - 1
    ingest_metric(ctx.actor.tenant, time, 200.0)
    ingest(ctx.actor.tenant, time, "error")
    assert {:ok, 1} = Worker.run_once([store_config: ctx.config], [node()])
    assert {:ok, state} = Pulse.Alerting.state(ctx.actor, "api-errors")
    assert [%{"status" => "firing"}] = Map.values(state["instances"])
    before = Agent.get(ctx.agent, & &1.objects)
    conn = build_conn() |> put_req_header("authorization", "Bearer admin-token")

    assert {:ok, [%{"text" => json}]} =
             Tools.call("preview_alert_rule", %{"tenant" => ctx.actor.tenant, "id" => "api-errors"}, %{conn: conn})

    assert Pulse.JSON.decode!(json)["health"] == "ok"
    assert Agent.get(ctx.agent, & &1.objects) == before
  end

  test "mixed evaluation skips unavailable authority without publishing a partial source", ctx do
    create_rule(expression_rule())
    ingest_metric(ctx.actor.tenant, @tick, 200.0)
    ingest(ctx.actor.tenant, @tick, "error")
    assert {:ok, firing} = evaluate(ctx, @tick)

    Agent.update(ctx.agent, fn state ->
      %{state | faults: Map.put(state.faults, {"GET", root_key(ctx.actor.tenant, "metrics")}, {403, :before, 100})}
    end)

    assert {:error, :evaluation_skipped} = evaluate(ctx, 2 * @tick)
    assert {:ok, head, _} = Repository.load(ctx.actor.tenant, "api-errors")
    assert head["instances"] == firing["instances"]
    assert head["completed_at_ns"] == Integer.to_string(@tick)
    assert Pulse.SelfMetrics.render() =~ ~s(pulse_alert_evaluation_skips_total{reason="freshness_unavailable"} 1)
  end

  test "required snapshots see a remote root change immediately despite a warm cache", ctx do
    create()
    ingest(ctx.actor.tenant, @tick, "error")
    assert {:ok, firing} = evaluate(ctx, @tick)
    assert map_size(firing["instances"]) == 1
    empty = Manifest.new() |> Manifest.encode() |> IO.iodata_to_binary()

    Agent.update(ctx.agent, fn state ->
      %{state | objects: Map.put(state.objects, root_key(ctx.actor.tenant), {"\"remote-v2\"", empty})}
    end)

    assert {:ok, [_]} = Storage.query(:logs, ctx.actor.tenant)
    assert {:ok, resolved} = evaluate(ctx, 2 * @tick)
    assert resolved["instances"] == %{}
    assert resolved["health"] == "no_data"
  end

  test "refresh failure skips evaluation and never converts stale data to an OK recovery", ctx do
    create()
    ingest(ctx.actor.tenant, @tick, "error")
    assert {:ok, firing} = evaluate(ctx, @tick)

    Agent.update(ctx.agent, fn state ->
      %{state | faults: Map.put(state.faults, {"GET", root_key(ctx.actor.tenant)}, {403, :before, 100})}
    end)

    assert {:ok, [_]} = Storage.query(:logs, ctx.actor.tenant)
    assert {:error, :evaluation_skipped} = evaluate(ctx, 2 * @tick)
    assert {:ok, head, _} = Repository.load(ctx.actor.tenant, "api-errors")
    assert head["instances"] == firing["instances"]
    assert head["completed_at_ns"] == Integer.to_string(@tick)
    assert head["health"] == "ok"
    assert Pulse.SelfMetrics.render() =~ ~s(pulse_alert_evaluation_skips_total{reason="freshness_unavailable"} 1)
  end

  test "invalid extraction preserves firing, and resource exhaustion skips rather than clearing it", ctx do
    create(%{"query" => ~s'sum(sum_over_time({service="api"} | logfmt | unwrap count [10s]))'})
    ingest(ctx.actor.tenant, @tick, "count=1")
    assert {:ok, firing} = evaluate(ctx, @tick)
    assert map_size(firing["instances"]) == 1
    ingest(ctx.actor.tenant, 2 * @tick, "count=invalid")
    assert {:ok, degraded} = evaluate(ctx, 2 * @tick)
    assert degraded["instances"] == firing["instances"]
    assert degraded["health"] == "error"
    Runtime.put_env(:pulse, PromQL, max_samples: 0)
    assert {:error, :evaluation_skipped} = evaluate(ctx, 3 * @tick)
    assert {:ok, head, _} = Repository.load(ctx.actor.tenant, "api-errors")
    assert head["completed_at_ns"] == Integer.to_string(2 * @tick)
    assert head["instances"] == firing["instances"]
    assert head["health"] == "error"
    assert Pulse.SelfMetrics.render() =~ ~s(pulse_alert_evaluation_skips_total{reason="budget"} 1)
  end

  test "native instance overflow publishes error health, never a truncated set of fires", ctx do
    create(%{"query" => ~s'count_over_time({service="api"}[10s])'})

    streams =
      for n <- 1..129,
          do: %{
            "stream" => %{"service" => "api", "instance" => Integer.to_string(n)},
            "values" => [[Integer.to_string(@tick), "error"]]
          }

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-scope-orgid", ctx.actor.tenant)
      |> post("/loki/api/v1/push", %{"streams" => streams})

    assert conn.status == 204
    assert {:ok, degraded} = evaluate(ctx, @tick)
    assert degraded["health"] == "error"
    assert {:ok, head, _} = Repository.load(ctx.actor.tenant, "api-errors")
    assert head["instances"] == %{}
    assert head["event_seq"] == 1
    assert head["completed_at_ns"] == Integer.to_string(@tick)
    assert {:ok, events} = Pulse.Alerting.events(ctx.actor, "api-errors")
    assert [%{"type" => "health_changed", "health" => "error"}] = events["events"]
  end

  test "a missing signal authority never triggers LIST reconstruction or no-data recovery", ctx do
    create()
    before = Agent.get(ctx.agent, &{&1.objects, &1.lists})
    ManifestCache.drop(ctx.actor.tenant, "logs")
    assert {:error, :evaluation_skipped} = evaluate(ctx, @tick)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer admin-token")
      |> put_req_header("x-scope-orgid", ctx.actor.tenant)
      |> post("/api/v1/alerting/rules/api-errors/evaluate", %{})

    assert json_response(conn, 503) == %{"error" => "evaluation_skipped"}
    assert get_resp_header(conn, "retry-after") == ["1"]
    assert Agent.get(ctx.agent, &{&1.objects, &1.lists}) == before
    assert {:ok, head, _} = Repository.load(ctx.actor.tenant, "api-errors")
    assert head["completed_at_ns"] == "-1"
    assert head["instances"] == %{}
    Runtime.put_env(:pulse, S3, ctx.config)

    assert Pulse.SelfMetrics.render() =~ ~s(pulse_alert_evaluation_skips_total{reason="authority_missing"} 2)
    refute Pulse.SelfMetrics.render() =~ ctx.actor.tenant

    assert {:error, :signal_authority_missing} =
             PromQL.query("up", ctx.actor.tenant, %{end_ts_ns: @tick, require_fresh_manifest: true})

    refute Agent.get(ctx.agent, fn state -> Map.has_key?(state.objects, root_key(ctx.actor.tenant, "metrics")) end)
  end
end
