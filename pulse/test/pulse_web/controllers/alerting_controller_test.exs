defmodule PulseWeb.AlertingControllerTest do
  use PulseWeb.ConnCase, async: true

  alias Pulse.Alerting.Canonical
  alias Pulse.Alerting.Evaluator
  alias Pulse.Alerting.Notifier
  alias Pulse.Alerting.Repository
  alias Pulse.Alerting.Resources
  alias Pulse.Alerting.Worker
  alias Pulse.MCP.Tools
  alias Pulse.Record.Log
  alias Pulse.Record.MetricSample
  alias Pulse.Runtime.Task
  alias Pulse.Test.BlockingMetricStorage
  alias Pulse.Test.CompactionStore
  alias Pulse.Test.MCPMessages
  alias Pulse.Test.RuntimePlug

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
      allow_http: true
    }

    actor = %{
      tenant: "transport-alerts",
      id: "pedro",
      type: "human",
      token_hash: Canonical.digest("admin-token"),
      capabilities: ~w(alert:read alert:rules:write alert:audit:read alert:preview alert:evaluate alert:import)
    }

    Pulse.Runtime.put_env(:pulse, Pulse.Alerting, principals: [actor], store_config: config)

    %{config: config, actor: actor, agent: agent}
  end

  defp rule,
    do: %{
      "name" => "Backup failed",
      "query" => "max(backup_failed)",
      "threshold" => %{"op" => "gt", "value" => 0},
      "enabled" => true,
      "cadence_ms" => 1000
    }

  defp params(op, revision \\ nil),
    do: %{"rule" => rule(), "operation_id" => op, "reason" => "Watch backups", "expected_revision" => revision}

  defp request(method, path, body \\ %{}, token \\ "admin-token") do
    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("x-scope-orgid", "transport-alerts")
    |> put_req_header("content-type", "application/json")
    |> Phoenix.ConnTest.dispatch(@endpoint, method, path, Pulse.JSON.encode!(body))
  end

  test "HTTP config, history, preconditions and restore share the durable service" do
    created = request(:post, "/api/v1/alerting/rules/backup", params("create")) |> json_response(200)
    changed = request(:put, "/api/v1/alerting/rules/backup", params("edit", created["revision"])) |> json_response(200)
    assert request(:put, "/api/v1/alerting/rules/backup", params("stale", created["revision"])) |> json_response(409)
    history = request(:get, "/api/v1/alerting/rules/backup/changes") |> json_response(200)
    assert length(history["changes"]) == 2

    restored =
      request(:post, "/api/v1/alerting/rules/backup/restore", %{
        "revision" => created["revision"],
        "expected_revision" => changed["revision"],
        "operation_id" => "restore",
        "reason" => "Restore approved baseline"
      })
      |> json_response(200)

    assert restored["state"] == "disabled"
    assert restored["actor"]["id"] == "pedro"
  end

  test "rule-file previews convert Prometheus recording groups for principals with alert:record", ctx do
    yaml = """
    groups:
      - name: Kura Recording
        interval: 1m
        rules:
          - record: kura:pod_region
            expr: max by (cluster, pod, region) (kura_node_geo_info)
    """

    path = "/api/v1/alerting/import/rule-file/preview"
    assert request(:post, path, %{"content" => yaml}) |> json_response(403)

    recorder = %{
      ctx.actor
      | id: "recorder",
        token_hash: Canonical.digest("record-token"),
        capabilities: ctx.actor.capabilities ++ ["alert:record"]
    }

    Pulse.Runtime.put_env(:pulse, Pulse.Alerting, principals: [ctx.actor, recorder], store_config: ctx.config)
    assert request(:post, path, %{"content" => "groups: ["}, "record-token") |> json_response(400)
    body = request(:post, path, %{"content" => yaml}, "record-token") |> json_response(200)
    assert [%{"id" => "kura-recording", "rule" => rule}] = body["rules"]
    assert %{"kind" => "promql_recording_group", "enabled" => false, "cadence_ms" => 60_000} = rule

    created =
      request(
        :post,
        "/api/v1/alerting/rules/kura-recording",
        %{"rule" => rule, "operation_id" => "import", "reason" => "Move kura recordings"},
        "record-token"
      )
      |> json_response(200)

    assert created["rule"]["rules"] == [
             %{
               "record" => "kura:pod_region",
               "expr" => "max by (cluster, pod, region) (kura_node_geo_info)",
               "labels" => %{}
             }
           ]
  end

  test "unauthorized calls fail before malformed rule validation" do
    response = request(:post, "/api/v1/alerting/rules/backup", %{"rule" => "malformed"}, "wrong") |> json_response(401)
    assert response == %{"error" => "unauthorized"}
  end

  test "imported previews expose unsupported and budget failures distinctly in HTTP and MCP", ctx do
    configured =
      Pulse.Runtime.get_env(:pulse, Pulse.Alerting, [])
      |> Keyword.put(:source_bindings, [
        %{"tenant" => ctx.actor.tenant, "uid" => "native", "type" => "native_promql"},
        %{"tenant" => ctx.actor.tenant, "uid" => "native-logs", "type" => "native_logql"}
      ])

    Pulse.Runtime.put_env(:pulse, Pulse.Alerting, configured)
    conn = build_conn() |> put_req_header("authorization", "Bearer admin-token")

    for {id, uid, model, code, mcp_reason} <- [
          {"unbound", "missing", %{"instant" => true, "expr" => "vector(1)"}, "unsupported_graph_source",
           :unsupported_graph_source},
          {"bad-model", "native", "malformed", "unsupported_graph_source", :unsupported_graph_source},
          {"macro", "native", %{"instant" => true, "expr" => "rate(m[$__rate_interval])"}, "unsupported_source_query",
           :invalid_or_unsupported_query},
          {"log-macro", "native-logs", %{"queryType" => "instant", "expr" => "$__interval"}, "unsupported_source_query",
           :invalid_logql},
          {"log-stream", "native-logs", %{"queryType" => "instant", "expr" => ~s'{service="api"}'},
           "unsupported_source_query", :unsupported_source_query}
        ] do
      original = %{
        "uid" => id,
        "condition" => "A",
        "data" => [%{"refId" => "A", "datasourceUid" => uid, "model" => model}]
      }

      body = %{
        "operation_id" => id,
        "reason" => "Preview only",
        "rule" => %{"kind" => "grafana", "original" => original}
      }

      assert request(:post, "/api/v1/alerting/rules/#{id}", body) |> json_response(200)
      assert request(:post, "/api/v1/alerting/rules/#{id}/preview") |> json_response(422) == %{"error" => code}

      assert {:error, ^mcp_reason} =
               Tools.call("preview_alert_rule", %{"tenant" => ctx.actor.tenant, "id" => id}, %{conn: conn})
    end

    original = %{
      "uid" => "bounded",
      "condition" => "A",
      "data" => [
        %{"refId" => "A", "datasourceUid" => "native", "model" => %{"instant" => true, "expr" => "vector(1)+vector(2)"}}
      ]
    }

    assert request(:post, "/api/v1/alerting/rules/bounded", %{
             "operation_id" => "bounded",
             "reason" => "Preview",
             "rule" => %{"kind" => "grafana", "original" => original}
           })
           |> json_response(200)

    # Each operand of vector(1)+vector(2) holds one point; the result is one.
    Pulse.Runtime.put_env(:pulse, Pulse.PromQL.Evaluator, max_materialized_samples: 1)

    assert request(:post, "/api/v1/alerting/rules/bounded/preview") |> json_response(422) == %{
             "error" => "query_intermediate_limit"
           }

    Pulse.Runtime.put_env(:pulse, Pulse.PromQL.Evaluator, [])
    Pulse.Runtime.put_env(:pulse, Pulse.Storage, adapter: BlockingMetricStorage)
    # Scalar vector(1) has no storage reads; use the normal native threshold
    # route to exercise the same shared deadline classification.
    assert request(:post, "/api/v1/alerting/rules/timeout", params("timeout")) |> json_response(200)
    Pulse.Runtime.put_env(:pulse, BlockingMetricStorage, {:error, :query_timeout})

    assert request(:post, "/api/v1/alerting/rules/timeout/preview") |> json_response(504) == %{
             "error" => "query_timeout"
           }
  end

  test "mixed native source previews use HTTP/MCP authorization and never write state", ctx do
    configured =
      Pulse.Runtime.get_env(:pulse, Pulse.Alerting, [])
      |> Keyword.put(:source_bindings, [
        %{"tenant" => ctx.actor.tenant, "uid" => "logs", "type" => "native_logql"},
        %{"tenant" => ctx.actor.tenant, "uid" => "prom", "type" => "native_promql"}
      ])

    Pulse.Runtime.put_env(:pulse, Pulse.Alerting, configured)

    original = %{
      "uid" => "mixed",
      "condition" => "C",
      "data" => [
        %{
          "refId" => "A",
          "datasourceUid" => "logs",
          "model" => %{"queryType" => "instant", "expr" => ~s'sum(count_over_time({service="transport-api"}[1m]))'}
        },
        %{"refId" => "B", "datasourceUid" => "prom", "model" => %{"instant" => true, "expr" => "vector(1)"}},
        %{
          "refId" => "C",
          "datasourceUid" => "__expr__",
          "model" => %{"type" => "math", "expression" => "$A > 0 && $B > 0"}
        }
      ]
    }

    assert :ok =
             Pulse.Storage.append(:logs, ctx.actor.tenant, [
               %Log{timestamp_ns: System.system_time(:nanosecond), service: "transport-api", body: "hello"}
             ])

    assert request(:post, "/api/v1/alerting/rules/mixed", %{
             "operation_id" => "mixed",
             "reason" => "Preview",
             "rule" => %{"kind" => "grafana", "original" => original}
           })
           |> json_response(200)

    assert {:ok, before, _} = Repository.load(ctx.actor.tenant, "mixed")
    objects = Agent.get(ctx.agent, & &1.objects)
    http = request(:post, "/api/v1/alerting/rules/mixed/preview") |> json_response(200)
    assert http["result"]["frames"] == [%{"labels" => %{}, "value" => "1.0"}]
    assert http["executable"] == false
    conn = build_conn() |> put_req_header("authorization", "Bearer admin-token")

    assert {:ok, [%{"text" => text}]} =
             Tools.call("preview_alert_rule", %{"tenant" => ctx.actor.tenant, "id" => "mixed"}, %{conn: conn})

    assert Pulse.JSON.decode!(text)["result"] == http["result"]

    assert {:error, :unauthorized} =
             Tools.call("preview_alert_rule", %{"tenant" => "other", "id" => "mixed"}, %{conn: conn})

    assert request(:post, "/api/v1/alerting/rules/mixed/preview", %{}, "wrong") |> json_response(401)
    assert {:ok, after_preview, _} = Repository.load(ctx.actor.tenant, "mixed")
    assert before == after_preview
    assert objects == Agent.get(ctx.agent, & &1.objects)
    state = request(:get, "/api/v1/alerting/rules/mixed/state") |> json_response(200)
    assert state["state"] == "disabled"
    assert state["instances"] == %{}
    assert {:error, :rule_disabled} = Evaluator.evaluate(ctx.actor, "mixed")
  end

  test "native evaluation works on stored metrics, and preview makes no writes", ctx do
    now = System.system_time(:nanosecond)

    :ok =
      Pulse.Storage.append(:metrics, "transport-alerts", [
        %MetricSample{
          timestamp_ns: now - 2_000_000_000,
          value: 1.0,
          labels: %{"__name__" => "backup_failed"}
        }
      ])

    assert request(:post, "/api/v1/alerting/rules/backup", params("create")) |> json_response(200)
    preview = request(:post, "/api/v1/alerting/rules/backup/preview") |> json_response(200)
    assert [%{"status" => "firing"}] = Map.values(preview["instances"])
    before = request(:get, "/api/v1/alerting/rules/backup/state") |> json_response(200)
    assert before["completed_at_ns"] == "-1"
    assert before["instances"] == %{}
    assert {:ok, 1} = Worker.run_once([store_config: ctx.config], [node()])
    after_eval = request(:get, "/api/v1/alerting/rules/backup/state") |> json_response(200)
    assert [%{"status" => "firing"}] = Map.values(after_eval["instances"])
    events = request(:post, "/api/v1/alerting/rules/backup/events") |> json_response(200)
    assert Enum.any?(events["events"], &(&1["type"] == "firing"))
  end

  test "resources expose authorized replay frontiers without acknowledging transitions", ctx do
    assert {:ok, _} = Pulse.Alerting.create(ctx.actor, "backup", params("create"))

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer admin-token")
      |> put_req_header("x-scope-orgid", ctx.actor.tenant)

    assert {:ok, listing} = Resources.list(conn, %{})
    assert length(listing["resources"]) == 3
    uri = Resources.uri(ctx.actor.tenant, "backup", "events")
    assert {:ok, response} = Resources.read(conn, uri)
    checkpoint = response["contents"] |> hd() |> Map.fetch!("text") |> Pulse.JSON.decode!()
    assert checkpoint["latest_sequence"] == "0"
    assert checkpoint["replay_floor"] == "1"
    assert is_binary(checkpoint["checkpoint_cursor"])
    assert response["ttlMs"] == 0
    assert {:error, :unauthorized} = Resources.read(build_conn(), uri)
    assert {:error, :unauthorized} = Resources.read(conn, Resources.uri("other", "backup", "events"))
    refute Enum.any?(listing["resources"], &String.contains?(&1["uri"], checkpoint["checkpoint_cursor"]))
  end

  test "native notifications drain committed Slack outboxes on a successful pass", ctx do
    target = %{
      "tenant" => ctx.actor.tenant,
      "id" => "slack",
      "type" => "slack_webhook",
      "secret_env" => "PULSE_ALERTING_TEST_WEBHOOK"
    }

    Pulse.Runtime.put_env("PULSE_ALERTING_TEST_WEBHOOK", "https://notifications.invalid/private-webhook")

    Pulse.Runtime.put_env(:pulse, Pulse.Alerting,
      principals: [ctx.actor],
      store_config: ctx.config,
      notification_targets: [target]
    )

    input = params("notify") |> put_in(["rule", "notification_targets"], ["slack"])
    assert {:ok, _} = Pulse.Alerting.create(ctx.actor, "backup", input)

    query = fn _, _, _ ->
      {:ok,
       %{
         "data" => %{
           "resultType" => "vector",
           "result" => [%{"metric" => %{"service" => "<!channel>"}, "value" => [1, "1"]}]
         }
       }}
    end

    assert {:ok, _} = Evaluator.evaluate(ctx.actor, "backup", timestamp_ns: 1_000_000_000, query: query)
    owner = self()

    Req.Test.stub(:native_slack, fn conn ->
      {:ok, bytes, conn} = Plug.Conn.read_body(conn)
      body = Pulse.JSON.decode!(bytes)
      assert hd(body["blocks"])["text"]["type"] == "plain_text"
      assert body["text"] =~ "Pulse alert"
      send(owner, :slack_delivered)
      Plug.Conn.send_resp(conn, 200, "ok")
    end)

    assert 1 = Notifier.run_once(ctx.actor.tenant, "backup", http_options: [plug: {Req.Test, :native_slack}])
    assert_receive :slack_delivered
    assert 0 = Notifier.run_once(ctx.actor.tenant, "backup", http_options: [plug: {Req.Test, :native_slack}])
    refute_receive :slack_delivered
    assert {:ok, head, _} = Repository.load(ctx.actor.tenant, "backup")
    assert Enum.all?(head["outboxes"], fn {_key, box} -> box["queue"] == [] end)
    assert {:ok, events} = Pulse.Alerting.events(ctx.actor, "backup")
    assert Enum.any?(events["events"], &(&1["type"] == "firing"))
    refute Pulse.JSON.encode!(head) =~ "private-webhook"
  end

  test "failed notifications retain durable work and lease ownership across restarts", ctx do
    target = %{
      "tenant" => ctx.actor.tenant,
      "id" => "slack",
      "type" => "slack_webhook",
      "secret_env" => "PULSE_ALERTING_TEST_WEBHOOK"
    }

    Pulse.Runtime.put_env("PULSE_ALERTING_TEST_WEBHOOK", "https://notifications.invalid/private-webhook")

    Pulse.Runtime.put_env(:pulse, Pulse.Alerting,
      principals: [ctx.actor],
      store_config: ctx.config,
      notification_targets: [target]
    )

    input = params("notify") |> put_in(["rule", "notification_targets"], ["slack"])
    assert {:ok, _} = Pulse.Alerting.create(ctx.actor, "backup", input)

    query = fn _, _, _ ->
      {:ok, %{"data" => %{"resultType" => "vector", "result" => [%{"metric" => %{}, "value" => [1, "1"]}]}}}
    end

    assert {:ok, _} = Evaluator.evaluate(ctx.actor, "backup", timestamp_ns: 1_000_000_000, query: query)
    Req.Test.stub(:failed_slack, &Plug.Conn.send_resp(&1, 503, "unavailable"))
    assert 1 = Notifier.run_once(ctx.actor.tenant, "backup", http_options: [plug: {Req.Test, :failed_slack}])
    assert 0 = Notifier.run_once(ctx.actor.tenant, "backup", http_options: [plug: {Req.Test, :failed_slack}])
    assert {:ok, head, _} = Repository.load(ctx.actor.tenant, "backup")
    assert [{_, box}] = Map.to_list(head["outboxes"])
    assert length(box["queue"]) == 1
    assert is_map(box["claim"])
    Req.Test.stub(:recovered_slack, &Plug.Conn.send_resp(&1, 200, "ok"))
    after_expiry = String.to_integer(box["claim"]["expires_ns"]) + 1

    assert 1 =
             Notifier.run_once(ctx.actor.tenant, "backup",
               timestamp_ns: after_expiry,
               http_options: [plug: {Req.Test, :recovered_slack}]
             )

    assert {:ok, drained, _} = Repository.load(ctx.actor.tenant, "backup")
    assert drained["outboxes"] == %{}
  end

  test "real HTTP subscription acknowledges before hints and closes on credential revocation", ctx do
    assert {:ok, created} = Pulse.Alerting.create(ctx.actor, "backup", params("create"))

    # The server's connection process must observe credential revocation made by
    # this test, so share a test-owned runtime with it instead of a snapshot.
    runtime = Pulse.Runtime.share()

    http =
      start_supervised!(
        Supervisor.child_spec(
          {Bandit, plug: {RuntimePlug, runtime: runtime, plug: PulseWeb.Endpoint}, ip: {127, 0, 0, 1}, port: 0},
          id: :mcp_http
        )
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(http)
    uri = Resources.uri(ctx.actor.tenant, "backup", "changes")

    message =
      MCPMessages.request("watch", "subscriptions/listen", %{"notifications" => %{"resourceSubscriptions" => [uri]}})

    headers = [
      {"mcp-protocol-version", "2026-07-28"},
      {"mcp-method", "subscriptions/listen"},
      {"accept", "application/json, text/event-stream"},
      {"authorization", "Bearer admin-token"}
    ]

    owner = self()
    supervisor = start_supervised!({Task.Supervisor, []})

    task =
      Task.Supervisor.async_nolink(supervisor, fn ->
        Req.post("http://127.0.0.1:#{port}/mcp",
          json: message,
          headers: headers,
          retry: false,
          receive_timeout: 15_000,
          into: fn {:data, bytes}, {req, response} ->
            send(owner, {:sse_bytes, bytes})
            {:cont, {req, response}}
          end
        )
      end)

    {ack, buffer} = next_sse("")
    assert ack["method"] == "notifications/subscriptions/acknowledged"
    assert ack["params"]["notifications"] == %{"resourceSubscriptions" => [uri]}
    assert {:ok, _} = Pulse.Alerting.update(ctx.actor, "backup", params("edit", created["revision"]))
    {hint, buffer} = next_sse(buffer)
    assert hint["method"] == "notifications/resources/updated"
    assert hint["params"]["uri"] == uri
    assert hint["params"]["_meta"]["io.modelcontextprotocol/subscriptionId"] == "watch"
    Pulse.Runtime.put_env(:pulse, Pulse.Alerting, principals: [], store_config: ctx.config)
    {completion, _buffer} = next_sse(buffer)
    assert completion["id"] == "watch"
    assert completion["result"]["resultType"] == "complete"
    assert {:ok, %{status: 200}} = Task.await(task)
  end

  defp next_sse(buffer) do
    case String.split(buffer, "\n\n", parts: 2) do
      ["data: " <> json, rest] ->
        {Pulse.JSON.decode!(json), rest}

      [_comment, rest] ->
        next_sse(rest)

      [_partial] ->
        assert_receive {:sse_bytes, bytes}, 5000
        next_sse(buffer <> bytes)
    end
  end

  test "MCP writes use configured principals, never open/shared query auth" do
    args =
      Map.merge(params("mcp-create"), %{"tenant" => "transport-alerts", "id" => "backup"})
      |> Map.delete("expected_revision")

    assert {:error, :unauthorized} = Tools.call("create_alert_rule", args)
    conn = build_conn() |> put_req_header("authorization", "Bearer admin-token")
    assert {:ok, [%{"text" => text}]} = Tools.call("create_alert_rule", args, %{conn: conn})
    result = Pulse.JSON.decode!(text)
    assert result["actor"]["id"] == "pedro"

    assert {:ok, [%{"text" => history}]} =
             Tools.call("list_alert_rule_changes", %{"tenant" => "transport-alerts", "id" => "backup"}, %{conn: conn})

    assert length(Pulse.JSON.decode!(history)["changes"]) == 1
  end
end
