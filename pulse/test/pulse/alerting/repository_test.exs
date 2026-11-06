defmodule Pulse.Alerting.RepositoryTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Alerting
  alias Pulse.Alerting.{Canonical, Evaluator, Importer, Repository}
  alias Pulse.Record.MetricSample
  alias Pulse.Runtime.Task
  alias Pulse.Test.CompactionStore

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
      tenant: "alerts",
      id: "pedro",
      type: "human",
      capabilities: ~w(alert:read alert:rules:write alert:audit:read alert:preview alert:evaluate alert:import)
    }

    opts = [store_config: config, cursor_secret: "a-stable-test-cursor-secret"]
    %{actor: actor, opts: opts, agent: agent}
  end

  defp rule(extra \\ %{}),
    do:
      Map.merge(
        %{
          "name" => "Backup failed",
          "query" => "max(backup_failed)",
          "threshold" => %{"op" => "gt", "value" => 0},
          "enabled" => true,
          "cadence_ms" => 1000
        },
        extra
      )

  defp request(rule, op, revision \\ nil),
    do: %{"rule" => rule, "operation_id" => op, "reason" => "Review backup failures", "expected_revision" => revision}

  defp query(value),
    do: fn _, _, _ ->
      {:ok,
       %{"data" => %{"resultType" => "vector", "result" => [%{"metric" => %{}, "value" => [0, to_string(value)]}]}}}
    end

  test "publishes configuration and its verified audit together and exact retries reuse the revision", ctx do
    params = request(rule(), "create")
    assert {:ok, first} = Alerting.create(ctx.actor, "backup", params, ctx.opts)
    assert first["actor"] == %{"id" => "pedro", "type" => "human"}
    assert {:ok, ^first} = Alerting.create(ctx.actor, "backup", params, ctx.opts)
    assert {:ok, current} = Alerting.get(ctx.actor, "backup", ctx.opts)
    assert current["revision"] == first["revision"]
    assert {:ok, page} = Alerting.changes(ctx.actor, "backup", %{}, ctx.opts)
    assert length(page["changes"]) == 1
    assert page["next_cursor"] == nil

    assert {:error, :operation_reused} =
             Alerting.create(ctx.actor, "backup", request(rule(%{"name" => "Other"}), "create"), ctx.opts)
  end

  test "exact mutation retries use committed target bindings after configuration changes", ctx do
    target = %{"tenant" => "alerts", "id" => "slack", "type" => "slack_webhook", "secret_env" => "PULSE_ALERTING_OLD"}
    Pulse.Runtime.put_env(:pulse, Alerting, notification_targets: [target])
    params = request(rule(%{"notification_targets" => ["slack"]}), "target-retry")
    assert {:ok, first} = Alerting.create(ctx.actor, "backup", params, ctx.opts)
    [binding] = first["notification_targets"]
    assert binding["secret_env"] == "PULSE_ALERTING_OLD"

    for targets <- [[%{target | "secret_env" => "PULSE_ALERTING_NEW"}], []] do
      Pulse.Runtime.put_env(:pulse, Alerting, notification_targets: targets)
      assert {:ok, ^first} = Alerting.create(ctx.actor, "backup", params, ctx.opts)
      changed = put_in(params, ["rule", "name"], "Different caller request")
      assert {:error, :operation_reused} = Alerting.create(ctx.actor, "backup", changed, ctx.opts)
    end

    # A genuinely new operation still has to bind current operator targets.
    assert {:error, :invalid_target} =
             Alerting.create(ctx.actor, "other", %{params | "operation_id" => "new-target-operation"}, ctx.opts)
  end

  test "ancestry recovery verifies the existing digest format against original bindings", ctx do
    target = %{"tenant" => "alerts", "id" => "slack", "type" => "slack_webhook", "secret_env" => "PULSE_ALERTING_OLD"}
    Pulse.Runtime.put_env(:pulse, Alerting, notification_targets: [target])
    params = request(rule(%{"notification_targets" => ["slack"]}), "original-target")
    assert {:ok, first} = Alerting.create(ctx.actor, "backup", params, ctx.opts)
    assert {:ok, _} = Alerting.update(ctx.actor, "backup", request(rule(), "later", first["revision"]), ctx.opts)
    Pulse.Runtime.put_env(:pulse, Alerting, notification_targets: [])

    # Model bounded receipt eviction without manufacturing a new revision or
    # changing the immutable original digest/bindings.
    assert {:ok, head, _} = Repository.load("alerts", "backup", ctx.opts)
    key = "tenants/alerts/alerting/v1/rules/backup/head.json"

    assert {:ok, _} =
             Pulse.ObjectStore.put(ctx.opts[:store_config], key, Canonical.encode(%{head | "operations" => []}))

    assert {:ok, ^first} = Alerting.create(ctx.actor, "backup", params, ctx.opts)
    changed = put_in(params, ["rule", "name"], "Changed")
    assert {:error, :operation_reused} = Alerting.create(ctx.actor, "backup", changed, ctx.opts)
  end

  test "actual native commit-then-500/412 is read back as success", ctx do
    key = "tenants/alerts/alerting/v1/rules/backup/head.json"
    Agent.update(ctx.agent, &%{&1 | faults: %{{"PUT", key} => {500, :after, 1}}})
    assert {:ok, created} = Alerting.create(ctx.actor, "backup", request(rule(), "lost-response"), ctx.opts)
    assert {:ok, page} = Alerting.changes(ctx.actor, "backup", %{}, ctx.opts)
    assert [change] = page["changes"]
    assert change["revision"] == created["revision"]
  end

  test "stale edits cannot overwrite newer configuration and no orphan is audit history", ctx do
    assert {:ok, first} = Alerting.create(ctx.actor, "backup", request(rule(), "create"), ctx.opts)

    assert {:ok, second} =
             Alerting.update(
               ctx.actor,
               "backup",
               request(rule(%{"name" => "New"}), "edit", first["revision"]),
               ctx.opts
             )

    assert {:error, :conflict} =
             Alerting.update(
               ctx.actor,
               "backup",
               request(rule(%{"name" => "Old"}), "stale", first["revision"]),
               ctx.opts
             )

    assert {:ok, page} = Alerting.changes(ctx.actor, "backup", %{}, ctx.opts)
    assert Enum.map(page["changes"], & &1["revision"]) == [second["revision"], first["revision"]]
  end

  test "frozen-tip pagination continues even when another edit moves the head", ctx do
    assert {:ok, first} = Alerting.create(ctx.actor, "backup", request(rule(), "create"), ctx.opts)
    assert {:ok, second} = Alerting.update(ctx.actor, "backup", request(rule(), "edit", first["revision"]), ctx.opts)
    assert {:ok, page} = Alerting.changes(ctx.actor, "backup", %{"limit" => 1}, ctx.opts)
    assert {:ok, _third} = Alerting.update(ctx.actor, "backup", request(rule(), "edit2", second["revision"]), ctx.opts)

    assert {:ok, continuation} =
             Alerting.changes(ctx.actor, "backup", %{"cursor" => page["next_cursor"], "limit" => 1}, ctx.opts)

    assert Enum.map(continuation["changes"], & &1["revision"]) == [first["revision"]]
    other = %{ctx.actor | id: "other"}
    assert {:error, :reset_required} = Alerting.changes(other, "backup", %{"cursor" => page["next_cursor"]}, ctx.opts)
  end

  test "deleted generations keep audit ancestry and recreation gets a fresh nonce", ctx do
    assert {:ok, first} = Alerting.create(ctx.actor, "backup", request(rule(), "create"), ctx.opts)
    params = Map.delete(request(rule(), "delete", first["revision"]), "rule")
    assert {:ok, deleted} = Alerting.delete(ctx.actor, "backup", params, ctx.opts)
    assert {:error, :not_found} = Alerting.get(ctx.actor, "backup", ctx.opts)

    assert {:ok, recreated} =
             Alerting.create(ctx.actor, "backup", request(rule(), "recreate", deleted["revision"]), ctx.opts)

    refute recreated["generation"] == first["generation"]
    assert {:ok, historical} = Alerting.historical(ctx.actor, "backup", first["revision"], ctx.opts)
    assert historical["rule"]["name"] == "Backup failed"
    assert {:ok, page} = Alerting.changes(ctx.actor, "backup", %{}, ctx.opts)
    assert length(page["changes"]) == 3
  end

  test "restore creates a disabled revision rather than replaying state or rewriting history", ctx do
    assert {:ok, first} = Alerting.create(ctx.actor, "backup", request(rule(), "create"), ctx.opts)

    assert {:ok, second} =
             Alerting.update(
               ctx.actor,
               "backup",
               request(rule(%{"name" => "New"}), "edit", first["revision"]),
               ctx.opts
             )

    params = %{
      "revision" => first["revision"],
      "expected_revision" => second["revision"],
      "operation_id" => "restore",
      "reason" => "Undo title change"
    }

    assert {:ok, restored} = Alerting.restore(ctx.actor, "backup", params, ctx.opts)
    assert restored["rule"]["name"] == "Backup failed"
    assert restored["rule"]["enabled"] == false
    refute restored["revision"] == first["revision"]
  end

  test "normal evaluations are fenced and pending/firing/hold state survives evaluator restart", ctx do
    assert {:ok, _} =
             Alerting.create(
               ctx.actor,
               "backup",
               request(rule(%{"for_ms" => 1000, "keep_firing_ms" => 1000}), "create"),
               ctx.opts
             )

    assert {:ok, first} =
             Evaluator.evaluate(ctx.actor, "backup", ctx.opts ++ [timestamp_ns: 1_000_000_000, query: query(1)])

    assert [%{"status" => "pending"}] = Map.values(first["instances"])

    assert {:ok, second} =
             Evaluator.evaluate(ctx.actor, "backup", ctx.opts ++ [timestamp_ns: 2_000_000_000, query: query(1)])

    assert [%{"status" => "firing"}] = Map.values(second["instances"])

    assert {:ok, third} =
             Evaluator.evaluate(ctx.actor, "backup", ctx.opts ++ [timestamp_ns: 3_000_000_000, query: query(0)])

    assert [%{"status" => "recovering"}] = Map.values(third["instances"])

    assert {:ok, fourth} =
             Evaluator.evaluate(ctx.actor, "backup", ctx.opts ++ [timestamp_ns: 4_000_000_000, query: query(0)])

    assert fourth["instances"] == %{}

    assert {:error, :not_due} =
             Evaluator.evaluate(ctx.actor, "backup", ctx.opts ++ [timestamp_ns: 3_000_000_000, query: query(1)])

    assert {:ok, events} = Alerting.events(ctx.actor, "backup", %{}, ctx.opts)
    assert Enum.map(events["events"], & &1["type"]) == ["pending", "health_changed", "firing", "recovering", "resolved"]
  end

  test "source failure and local admission skip are not healthy empty results", ctx do
    assert {:ok, _} = Alerting.create(ctx.actor, "backup", request(rule(), "create"), ctx.opts)

    assert {:ok, firing} =
             Evaluator.evaluate(ctx.actor, "backup", ctx.opts ++ [timestamp_ns: 1_000_000_000, query: query(1)])

    error = fn _, _, _ -> {:error, :backend_unavailable} end

    assert {:ok, degraded} =
             Evaluator.evaluate(ctx.actor, "backup", ctx.opts ++ [timestamp_ns: 2_000_000_000, query: error])

    assert degraded["instances"] == firing["instances"]
    assert degraded["health"] == "error"
    busy = fn _, _, _ -> {:error, :query_overloaded} end

    assert {:error, :evaluation_skipped} =
             Evaluator.evaluate(ctx.actor, "backup", ctx.opts ++ [timestamp_ns: 3_000_000_000, query: busy])

    assert {:ok, state} = Alerting.state(ctx.actor, "backup", ctx.opts)
    assert state["completed_at_ns"] == "2000000000"
  end

  test "scheduled budget memo avoids repeated work without publishing a completed tick", ctx do
    assert {:ok, created} = Alerting.create(ctx.actor, "backup", request(rule(), "create"), ctx.opts)
    cache = :ets.new(:budget_skips, [:set, :public])
    owner = self()

    failed = fn _, _, _ ->
      send(owner, :ran_query)
      {:error, :query_work_limit}
    end

    opts = ctx.opts ++ [budget_skip_cache: cache, timestamp_ns: 2_000_000_000, query: failed]

    for _ <- 1..2, do: assert({:error, :evaluation_skipped} = Evaluator.evaluate(ctx.actor, "backup", opts))
    assert_received :ran_query
    refute_received :ran_query
    assert {:ok, state} = Alerting.state(ctx.actor, "backup", ctx.opts)
    assert state["completed_at_ns"] == "-1"

    assert {:error, :evaluation_skipped} =
             Evaluator.evaluate(ctx.actor, "backup", Keyword.put(opts, :timestamp_ns, 3_000_000_000))

    assert_received :ran_query

    assert {:ok, _} =
             Alerting.update(
               ctx.actor,
               "backup",
               request(rule(%{"name" => "Edited"}), "edit", created["revision"]),
               ctx.opts
             )

    assert {:error, :evaluation_skipped} = Evaluator.evaluate(ctx.actor, "backup", opts)
    assert_received :ran_query

    transient = fn _, _, _ ->
      send(owner, :transient_query)
      {:error, :query_overloaded}
    end

    opts = opts |> Keyword.put(:timestamp_ns, 4_000_000_000) |> Keyword.put(:query, transient)
    for _ <- 1..2, do: assert({:error, :evaluation_skipped} = Evaluator.evaluate(ctx.actor, "backup", opts))
    assert_received :transient_query
    assert_received :transient_query
  end

  test "sealed pages provide forward replay, and candidate integrity is checked", ctx do
    assert {:ok, _} = Alerting.create(ctx.actor, "backup", request(rule(), "create"), ctx.opts)

    for n <- 1..70 do
      assert {:ok, _} =
               Evaluator.evaluate(
                 ctx.actor,
                 "backup",
                 ctx.opts ++ [timestamp_ns: n * 1_000_000_000, query: query(rem(n, 2))]
               )
    end

    assert {:ok, head, _} = Repository.load("alerts", "backup", ctx.opts)
    assert length(head["pages"]) == 1
    assert {:ok, page1} = Alerting.events(ctx.actor, "backup", %{"limit" => 10}, ctx.opts)

    assert {:ok, page2} =
             Alerting.events(ctx.actor, "backup", %{"limit" => 10, "cursor" => page1["next_cursor"]}, ctx.opts)

    assert hd(page2["events"])["sequence"] == "11"
    ref = head["revision"]

    Agent.update(ctx.agent, fn state ->
      {etag, _bytes} = state.objects[ref["key"]]
      %{state | objects: Map.put(state.objects, ref["key"], {etag, Canonical.encode(%{"id" => "backup"})})}
    end)

    assert {:error, :integrity_error} = Alerting.get(ctx.actor, "backup", ctx.opts)
  end

  test "in-flight old evaluation cannot publish after a disable edit", ctx do
    assert {:ok, created} = Alerting.create(ctx.actor, "backup", request(rule(), "create"), ctx.opts)
    owner = self()

    query = fn _, _, _ ->
      send(owner, {:query_started, self()})

      receive do
        :release -> query(1).("", "", %{})
      end
    end

    supervisor = start_supervised!({Task.Supervisor, []})

    task =
      Task.Supervisor.async_nolink(supervisor, fn ->
        Evaluator.evaluate(ctx.actor, "backup", ctx.opts ++ [timestamp_ns: 1_000_000_000, query: query])
      end)

    # The evaluation reads its rule head from storage before querying; allow for a
    # loaded async suite without changing the ordering under test.
    assert_receive {:query_started, pid}, 5_000

    assert {:ok, _} =
             Alerting.update(
               ctx.actor,
               "backup",
               request(rule(%{"enabled" => false}), "disable", created["revision"]),
               ctx.opts
             )

    send(pid, :release)
    assert {:error, :ambiguous_head_write} = Task.await(task)
    assert {:ok, state} = Alerting.state(ctx.actor, "backup", ctx.opts)
    assert state["state"] == "disabled"
    assert state["instances"] == %{}
    assert {:ok, events} = Alerting.events(ctx.actor, "backup", %{}, ctx.opts)
    assert events["events"] == []
  end

  test "removing an imported source does not declassify old audit content", ctx do
    original =
      File.read!("plans/alerting/grafana-rule-inventory.json") |> Pulse.JSON.decode!() |> Map.fetch!("rules") |> hd()

    imported = %{"kind" => "grafana", "original" => original, "enabled" => false}
    id = original["uid"]
    assert {:ok, created} = Alerting.create(ctx.actor, id, request(imported, "import"), ctx.opts)
    assert {:ok, _} = Alerting.update(ctx.actor, id, request(rule(), "native", created["revision"]), ctx.opts)
    reader = %{ctx.actor | capabilities: ctx.actor.capabilities -- ["alert:import"]}
    assert {:ok, _} = Alerting.get(reader, id, ctx.opts)
    assert {:error, :forbidden} = Alerting.changes(reader, id, %{}, ctx.opts)
    assert {:error, :forbidden} = Alerting.historical(reader, id, created["revision"], ctx.opts)
    assert {:ok, page} = Alerting.changes(ctx.actor, id, %{}, ctx.opts)
    [_, change] = page["changes"]

    assert {:ok, snapshot} =
             Alerting.historical(
               ctx.actor,
               id,
               %{"revision" => change["revision"], "revision_cursor" => change["revision_cursor"]},
               ctx.opts
             )

    assert snapshot["rule"]["original"] == original
  end

  test "authorized disabled Grafana preview reads native sources without any rule-state publication", ctx do
    uid = "bound-preview"

    original = %{
      "uid" => uid,
      "condition" => "B",
      "data" => [
        %{
          "refId" => "A",
          "datasourceUid" => "native",
          "model" => %{"instant" => true, "expr" => "sum(preview_metric)"}
        },
        %{"refId" => "B", "datasourceUid" => "__expr__", "model" => %{"type" => "math", "expression" => "$A > 2"}}
      ]
    }

    assert {:ok, _} =
             Alerting.create(
               ctx.actor,
               uid,
               request(%{"kind" => "grafana", "original" => original}, "preview-import"),
               ctx.opts
             )

    Pulse.Runtime.put_env(:pulse, Pulse.Alerting,
      source_bindings: [%{"tenant" => ctx.actor.tenant, "uid" => "native", "type" => "native_promql"}]
    )

    assert :ok =
             Pulse.Storage.append(:metrics, ctx.actor.tenant, [
               %MetricSample{
                 series_id: 1,
                 timestamp_ns: System.system_time(:nanosecond),
                 value: 3.0,
                 labels: %{"__name__" => "preview_metric"}
               }
             ])

    before = Agent.get(ctx.agent, & &1.objects)
    assert {:ok, preview} = Evaluator.preview(ctx.actor, uid, ctx.opts)
    assert preview["result"] == %{"type" => "numbers", "frames" => [%{"labels" => %{}, "value" => "1.0"}]}
    assert preview["executable"] == false
    assert before == Agent.get(ctx.agent, & &1.objects)
    reader = %{ctx.actor | capabilities: ctx.actor.capabilities -- ["alert:import"]}
    assert {:error, :forbidden} = Evaluator.preview(reader, uid, ctx.opts)
    assert {:error, :rule_disabled} = Evaluator.evaluate(ctx.actor, uid, ctx.opts)
    assert {:ok, state} = Alerting.state(ctx.actor, uid, ctx.opts)
    assert state["state"] == "disabled"
    assert state["instances"] == %{}
  end

  test "rejects broken/cyclic Grafana dependency graphs without writing", ctx do
    original = %{
      "uid" => "broken",
      "condition" => "A",
      "data" => [
        %{"refId" => "A", "datasourceUid" => "__expr__", "model" => %{"type" => "threshold", "expression" => "B"}},
        %{"refId" => "B", "datasourceUid" => "__expr__", "model" => %{"type" => "threshold", "expression" => "A"}}
      ]
    }

    assert {:error, :invalid_rule} =
             Alerting.create(
               ctx.actor,
               "broken",
               request(%{"kind" => "grafana", "original" => original}, "cycle"),
               ctx.opts
             )

    assert {:error, :not_found} = Repository.load(ctx.actor.tenant, "broken", ctx.opts)
  end

  test "all 115 Grafana definitions round-trip disabled with explicit execution blockers", ctx do
    inventory = File.read!("plans/alerting/grafana-rule-inventory.json") |> Pulse.JSON.decode!()
    assert {:ok, reports} = Importer.preview(inventory["rules"])
    assert length(reports) == 115
    assert Enum.map(reports, & &1["rule"]["original"]) == inventory["rules"]
    assert Enum.count(reports, &(&1["kind"] == "recording")) == 4
    assert Enum.all?(reports, &(&1["executable"] == false and &1["rule"]["enabled"] == false))

    for report <- reports do
      assert {:ok, _} =
               Alerting.create(ctx.actor, report["id"], request(report["rule"], "import-" <> report["id"]), ctx.opts)

      assert {:ok, stored} = Alerting.get(ctx.actor, report["id"], ctx.opts)
      assert stored["rule"]["original"] == report["rule"]["original"]
      assert stored["state"] == "disabled"
    end
  end

  test "ordinary read and shared tenant identity cannot grant alert administration", ctx do
    reader = %{ctx.actor | capabilities: ["alert:read"]}
    assert {:error, :forbidden} = Alerting.create(reader, "backup", request(rule(), "create"), ctx.opts)
    assert {:error, :invalid_id} = Alerting.create(ctx.actor, "../other", request(rule(), "create"), ctx.opts)

    assert {:error, :invalid_arguments} =
             Alerting.create(ctx.actor, "backup", Map.put(request(rule(), "create"), "actor", "admin"), ctx.opts)
  end
end
