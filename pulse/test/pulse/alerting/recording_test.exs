defmodule Pulse.Alerting.RecordingTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Alerting
  alias Pulse.Alerting.{Canonical, Evaluator, Recording, Repository, Resources, Rule}
  alias Pulse.Alerting.Cursor
  alias Pulse.Alerting.Tools
  alias Pulse.PromQL.Evaluator, as: PromQL
  alias Pulse.Record.MetricSample
  alias Pulse.Runtime
  alias Pulse.Runtime.Task
  alias Pulse.Storage
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.ManifestSupervision
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
      allow_http: true,
      manifest_flush_interval_ms: 1
    }

    Runtime.put_env(:pulse, S3, config)
    Runtime.put_env(:pulse, Storage, adapter: S3)
    start_supervised!(ManifestSupervision)

    actor = %{
      tenant: "alerts",
      id: "pedro",
      type: "human",
      capabilities: ~w(alert:read alert:rules:write alert:audit:read alert:preview alert:evaluate alert:record)
    }

    %{agent: agent, config: config, actor: actor, opts: [store_config: config]}
  end

  defp rule(extra \\ %{}),
    do:
      Map.merge(
        %{
          "kind" => "promql_recording",
          "name" => "backup_failed:sum",
          "query" => "sum(backup_failed)",
          "enabled" => true,
          "cadence_ms" => 1000,
          "labels" => %{}
        },
        extra
      )

  defp request(rule, op, revision \\ nil),
    do: %{"rule" => rule, "operation_id" => op, "reason" => "Record backup totals", "expected_revision" => revision}

  defp sample(value, labels \\ %{}), do: %{"metric" => labels, "value" => [0, to_string(value)]}
  defp query(samples), do: fn _, _, _ -> {:ok, %{"data" => %{"resultType" => "vector", "result" => samples}}} end

  defp tick(ctx, ns, samples \\ [sample(1)]),
    do: Evaluator.evaluate(ctx.actor, "record", ctx.opts ++ [timestamp_ns: ns, query: query(samples)])

  defp create(ctx, definition \\ rule()),
    do: Alerting.create(ctx.actor, "record", request(definition, "create"), ctx.opts)

  defp parquet_keys(ctx),
    do: Agent.get(ctx.agent, fn state -> Enum.filter(Map.keys(state.objects), &String.ends_with?(&1, ".parquet")) end)

  test "recording validation is closed, bounded and disabled by default" do
    assert {:ok, validated} = Rule.validate(Map.take(rule(), ~w(kind name query)))
    refute validated["enabled"]
    assert validated["cadence_ms"] == 60_000

    for change <- [
          %{"name" => "invalid name"},
          %{"labels" => %{"__name__" => "spoof"}},
          %{"labels" => %{"bad-label" => "value"}},
          %{"notification_targets" => ["slack"]},
          %{"threshold" => %{"op" => "gt", "value" => 0}},
          %{"query" => "sum("}
        ] do
      assert {:error, :invalid_rule} = Rule.validate(rule(change))
    end
  end

  test "final labels define identity; invalid, duplicate or oversized results fail as a whole" do
    definition = rule(%{"labels" => %{"job" => "recorded"}})

    assert {:error, :duplicate_recording_label_sets} =
             Recording.result(definition, [sample(1, %{"job" => "a"}), sample(2, %{"job" => "b"})], 1)

    assert {:error, :invalid_recording_result} = Recording.result(rule(), [sample("not-a-float")], 1)
    assert {:error, :invalid_recording_result} = Recording.result(rule(), List.duplicate(sample(1), 129), 1)
    labels = Map.new(1..30, &{"label_#{&1}", String.duplicate("x", 512)})
    rich = Enum.map(1..5, &sample(1, Map.put(labels, "id", to_string(&1))))
    assert {:error, :invalid_recording_result} = Recording.result(rule(), rich, 1)

    assert {:ok, result} =
             Recording.result(
               rule(),
               [sample("NaN", %{"id" => "a"}), sample("+Inf", %{"id" => "b"}), sample("-Inf", %{"id" => "c"})],
               1
             )

    assert Enum.map(result["samples"], & &1["value"]) == ["NaN", "+Inf", "-Inf"]
  end

  test "permanent keyed conflicts retain the FIFO intent and expose a precise recording error", ctx do
    assert {:ok, _} = create(ctx)
    assert {:ok, _} = tick(ctx, 1_000_000_000)
    assert {:ok, _} = tick(ctx, 2_000_000_000)
    assert {:ok, head, _} = Repository.load("alerts", "record", ctx.opts)
    assert [first, _second] = queue = head["recording_queue"]

    conflict = fn _, _, opts ->
      assert opts[:idempotency_key] == "pulse-recording-v1-" <> first["digest"]
      {:error, :keyed_content_mismatch}
    end

    for _ <- 1..2 do
      assert {:error, :keyed_content_mismatch} =
               Recording.publish_one("alerts", "record", ctx.opts ++ [recording_append: conflict])

      assert {:ok, blocked, _} = Repository.load("alerts", "record", ctx.opts)
      assert blocked["recording_queue"] == queue
      assert blocked["recording_error"] == %{"digest" => first["digest"], "reason" => "keyed_content_mismatch"}
    end

    assert parquet_keys(ctx) == []
  end

  test "commit precedes visibility; a lost append response and restart replay identical keyed bytes", ctx do
    assert {:ok, _} = create(ctx)
    assert {:ok, result} = tick(ctx, 1_000_000_000, [sample(2.5, %{"job" => "backup"})])
    assert result["recording_pending"] == 1
    assert parquet_keys(ctx) == []
    assert {:ok, head, _} = Repository.load("alerts", "record", ctx.opts)
    [ref] = head["recording_queue"]
    assert {:ok, object} = Repository.revision("alerts", "record", ref, ctx.opts)
    assert object["timestamp_ns"] == "1000000000"
    assert object["revision"] == head["revision"]

    lost = fn tenant, records, opts ->
      assert :ok = Storage.append(:metrics, tenant, records, opts)
      {:error, :storage_unavailable}
    end

    assert {:error, :storage_unavailable} =
             Recording.publish_one("alerts", "record", ctx.opts ++ [recording_append: lost])

    assert length(parquet_keys(ctx)) == 1
    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)
    assert {:ok, :published} = Recording.publish_one("alerts", "record", ctx.opts)
    assert length(parquet_keys(ctx)) == 1

    assert {:ok,
            [
              %MetricSample{
                value: 2.5,
                timestamp_ns: 1_000_000_000,
                labels: %{"__name__" => "backup_failed:sum", "job" => "backup"}
              }
            ]} = S3.query(:metrics, "alerts", [])

    assert {:ok, []} = S3.query(:metrics, "other-tenant", [])
    assert {:ok, state} = Alerting.state(ctx.actor, "record", ctx.opts)
    assert state["recording_pending"] == 0
    assert state["recording_last"]["status"] == "published"
    assert {:ok, :idle} = Recording.publish_one("alerts", "record", ctx.opts)
  end

  test "independent native recording queries can consume previously published producer results", ctx do
    rows =
      Enum.map([4.0, 5.0], fn value ->
        %MetricSample{
          timestamp_ns: 1_000_000_000,
          value: value,
          labels: %{"__name__" => "backup_failed", "job" => to_string(value)}
        }
      end)

    assert :ok = Storage.append(:metrics, "alerts", rows)
    assert {:ok, _} = create(ctx)
    assert {:ok, _} = Evaluator.evaluate(ctx.actor, "record", ctx.opts ++ [timestamp_ns: 1_000_000_000])
    assert {:ok, :published} = Recording.publish_one("alerts", "record", ctx.opts)

    assert {:ok, _} =
             Alerting.create(
               ctx.actor,
               "consumer",
               request(rule(%{"name" => "backup_failed:double", "query" => "backup_failed:sum * 2"}), "consumer"),
               ctx.opts
             )

    assert {:ok, _} = Evaluator.evaluate(ctx.actor, "consumer", ctx.opts ++ [timestamp_ns: 1_000_000_000])
    assert {:ok, :published} = Recording.publish_one("alerts", "consumer", ctx.opts)
    assert {:ok, rows} = S3.query(:metrics, "alerts", [])
    assert Enum.find(rows, &(&1.labels["__name__"] == "backup_failed:double")).value == 18.0
  end

  test "all four inventory recording expressions publish through the real producer chain", ctx do
    definitions =
      File.read!("plans/alerting/grafana-rule-inventory.json")
      |> Pulse.JSON.decode!()
      |> Map.fetch!("rules")
      |> Enum.filter(&is_map(&1["record"]))

    assert length(definitions) == 4
    cluster = "tuist-production"

    inputs = [
      %{"__name__" => "kura_node_geo_info", "cluster" => cluster, "pod" => "pod-1", "region" => "eu"},
      %{
        "__name__" => "kube_node_labels",
        "cluster" => cluster,
        "node" => "node-1",
        "label_node_cluster_x_k8s_io_pool" => "pool-1"
      },
      %{
        "__name__" => "kube_pod_info",
        "cluster" => cluster,
        "node" => "node-1",
        "pod" => "pod-1",
        "namespace" => "kura"
      }
    ]

    ns = 60_000_000_000

    assert :ok =
             Storage.append(
               :metrics,
               "alerts",
               Enum.map(inputs, &%MetricSample{labels: &1, timestamp_ns: ns, value: 1.0})
             )

    expected = [
      {"kura:pod_region", %{"cluster" => cluster, "pod" => "pod-1", "region" => "eu"}},
      {"kura:node_pool", %{"cluster" => cluster, "node" => "node-1", "pool" => "pool-1"}},
      {"kura:pool_region", %{"cluster" => cluster, "pool" => "pool-1", "region" => "eu"}},
      {"kura:node_region", %{"cluster" => cluster, "node" => "node-1", "region" => "eu"}}
    ]

    for {name, labels} <- expected do
      original = Enum.find(definitions, &(&1["record"]["metric"] == name))
      [source] = original["data"]
      assert source["refId"] == original["record"]["from"]
      assert source["source_type"] == "prometheus"

      definition =
        rule(%{
          "name" => name,
          "query" => source["model"]["expr"],
          "cadence_ms" => original["evaluation_interval_seconds"] * 1000
        })

      assert {:ok, _} = Alerting.create(ctx.actor, original["uid"], request(definition, original["uid"]), ctx.opts)
      assert {:ok, %{"health" => "ok"}} = Evaluator.evaluate(ctx.actor, original["uid"], ctx.opts ++ [timestamp_ns: ns])
      assert {:ok, :published} = Recording.publish_one("alerts", original["uid"], ctx.opts)

      assert {:ok, %{"data" => %{"result" => [%{"metric" => actual, "value" => [60.0, "1"]}]}}} =
               PromQL.query(name, "alerts", %{end_ts_ns: ns})

      assert actual == Map.put(labels, "__name__", name)
    end
  end

  test "an in-flight disabled candidate never becomes visible or enters the committed outbox", ctx do
    # The query is held open across a rule update; a long cadence keeps that
    # wait from counting as an evaluation overrun on a loaded machine.
    slow = %{"cadence_ms" => 600_000}
    assert {:ok, created} = create(ctx, rule(slow))
    owner = self()

    blocked = fn _, _, _ ->
      send(owner, {:query_started, self()})

      receive do
        :release -> query([sample(3)]).("", "", %{})
      end
    end

    supervisor = start_supervised!(Task.Supervisor)

    task =
      Task.Supervisor.async_nolink(supervisor, fn ->
        Evaluator.evaluate(ctx.actor, "record", ctx.opts ++ [timestamp_ns: 1_000_000_000, query: blocked])
      end)

    assert_receive {:query_started, pid}, 5_000

    assert {:ok, _} =
             Alerting.update(
               ctx.actor,
               "record",
               request(rule(Map.put(slow, "enabled", false)), "disable", created["revision"]),
               ctx.opts
             )

    send(pid, :release)
    assert {:error, :ambiguous_head_write} = Task.await(task)
    assert {:ok, :idle} = Recording.publish_one("alerts", "record", ctx.opts)
    assert parquet_keys(ctx) == []
    assert {:ok, state} = Alerting.state(ctx.actor, "record", ctx.opts)
    assert state["recording_pending"] == 0
    assert state["state"] == "disabled"
  end

  test "concurrent evaluators cannot publish different candidates for the same completed tick", ctx do
    assert {:ok, _} = create(ctx)
    owner = self()
    supervisor = start_supervised!(Supervisor.child_spec(Task.Supervisor, shutdown: 5_000))

    tasks =
      Enum.map([1, 2], fn value ->
        blocked = fn _, _, _ ->
          send(owner, {:query_started, self()})

          receive do
            :release -> query([sample(value)]).("", "", %{})
          end
        end

        Task.Supervisor.async_nolink(supervisor, fn ->
          Evaluator.evaluate(ctx.actor, "record", ctx.opts ++ [timestamp_ns: 1_000_000_000, query: blocked])
        end)
      end)

    results =
      try do
        assert_receive {:query_started, a}, 5_000
        assert_receive {:query_started, b}, 5_000
        send(a, :release)
        send(b, :release)
        Enum.map(tasks, &Task.await(&1, 10_000))
      after
        Enum.each(tasks, &Task.Supervisor.terminate_child(supervisor, &1.pid))
      end

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert {:ok, head, _} = Repository.load("alerts", "record", ctx.opts)
    assert [ref] = head["recording_queue"]
    assert {:ok, object} = Repository.revision("alerts", "record", ref, ctx.opts)
    assert {:ok, :published} = Recording.publish_one("alerts", "record", ctx.opts)
    assert {:ok, [row]} = S3.query(:metrics, "alerts", [])
    assert to_string(trunc(row.value)) == hd(object["samples"])["value"]
  end

  test "delete and recreation preserve pending old-generation publication without rewriting labels", ctx do
    assert {:ok, first} = create(ctx)
    assert {:ok, _} = tick(ctx, 1_000_000_000)
    assert {:ok, _} = tick(ctx, 2_000_000_000)

    assert {:ok, deleted} =
             Alerting.delete(
               ctx.actor,
               "record",
               Map.delete(request(rule(), "delete", first["revision"]), "rule"),
               ctx.opts
             )

    assert {:ok, :published} = Recording.publish_one("alerts", "record", ctx.opts)

    assert {:ok, recreated} =
             Alerting.create(
               ctx.actor,
               "record",
               request(rule(%{"name" => "backup_failed:new"}), "recreate", deleted["revision"]),
               ctx.opts
             )

    refute recreated["generation"] == first["generation"]
    new_timestamp = System.system_time(:nanosecond) + 1_000_000_000
    assert {:ok, _} = tick(ctx, new_timestamp)
    assert {:ok, :published} = Recording.publish_one("alerts", "record", ctx.opts)
    assert {:ok, :published} = Recording.publish_one("alerts", "record", ctx.opts)
    assert {:ok, :published} = Recording.publish_one("alerts", "record", ctx.opts)
    assert {:ok, rows} = S3.query(:metrics, "alerts", [])

    assert Enum.sort(Enum.map(Enum.reject(rows, &(&1.value == :stale)), &{&1.timestamp_ns, &1.labels["__name__"]})) == [
             {1_000_000_000, "backup_failed:sum"},
             {2_000_000_000, "backup_failed:sum"},
             {new_timestamp, "backup_failed:new"}
           ]

    assert Enum.count(rows, &(&1.value == :stale)) == 1
  end

  test "stale acknowledgements never consume the next committed result", ctx do
    assert {:ok, _} = create(ctx)
    assert {:ok, _} = tick(ctx, 1_000_000_000)
    assert {:ok, _} = tick(ctx, 2_000_000_000)
    assert {:ok, head, _} = Repository.load("alerts", "record", ctx.opts)
    [first, second] = head["recording_queue"]
    assert {:ok, :published} = Recording.publish_one("alerts", "record", ctx.opts)
    assert :ok = Repository.ack_recording("alerts", "record", first, ctx.opts)
    assert {:ok, head, _} = Repository.load("alerts", "record", ctx.opts)
    assert head["recording_queue"] == [second]
  end

  test "an ambiguous committed head write is read back before any metric publication", ctx do
    assert {:ok, _} = create(ctx)
    key = "tenants/alerts/alerting/v1/rules/record/head.json"
    Agent.update(ctx.agent, &%{&1 | faults: %{{"PUT", key} => {500, :after, 1}}})
    assert {:ok, _} = tick(ctx, 1_000_000_000)
    assert parquet_keys(ctx) == []
    assert {:ok, :published} = Recording.publish_one("alerts", "record", ctx.opts)
    assert length(parquet_keys(ctx)) == 1
  end

  test "bounded backlog defers before querying rather than dropping committed outputs", ctx do
    assert {:ok, _} = create(ctx)
    for n <- 1..63, do: assert({:ok, _} = tick(ctx, n * 1_000_000_000))
    forbidden_query = fn _, _, _ -> flunk("a full publication queue must defer before querying") end

    assert {:error, :recording_backlog} =
             Evaluator.evaluate(ctx.actor, "record", ctx.opts ++ [timestamp_ns: 65_000_000_000, query: forbidden_query])

    assert {:ok, state} = Alerting.state(ctx.actor, "record", ctx.opts)
    assert state["recording_pending"] == 63
    assert {:ok, :published} = Recording.publish_one("alerts", "record", ctx.opts)
    assert {:ok, result} = tick(ctx, 65_000_000_000)
    assert result["recording_pending"] == 63
    assert {:ok, current} = Alerting.get(ctx.actor, "record", ctx.opts)

    assert {:ok, _} =
             Alerting.update(
               ctx.actor,
               "record",
               request(rule(%{"enabled" => false}), "disable-full", current["revision"]),
               ctx.opts
             )

    assert {:ok, state} = Alerting.state(ctx.actor, "record", ctx.opts)
    assert state["recording_pending"] == 64
    assert state["state"] == "disabled"
  end

  test "only authoritative metrics expiry retires an intent, with a committed diagnostic event", ctx do
    Runtime.put_env(
      :pulse,
      S3,
      Map.merge(ctx.config, %{
        retention_mode: "enforce",
        retention_manifest_format: "bucketed",
        metrics_retention_days: 1
      })
    )

    assert {:ok, _} = create(ctx)
    assert {:ok, _} = tick(ctx, 1_000_000_000)
    assert {:ok, :expired} = Recording.publish_one("alerts", "record", ctx.opts)
    assert parquet_keys(ctx) == []
    assert {:ok, state} = Alerting.state(ctx.actor, "record", ctx.opts)
    assert state["recording_pending"] == 0
    assert state["recording_last"]["status"] == "expired"
    assert {:ok, events} = Alerting.events(ctx.actor, "record", %{}, ctx.opts)
    assert [%{"type" => "recording_expired"}] = Enum.filter(events["events"], &(&1["type"] == "recording_expired"))
    assert {:ok, _} = tick(ctx, System.system_time(:nanosecond))
    assert {:ok, :published} = Recording.publish_one("alerts", "record", ctx.opts)
  end

  test "recording expiry history and retained state stay classified after conversion, including legacy events", ctx do
    Runtime.put_env(
      :pulse,
      S3,
      Map.merge(ctx.config, %{
        retention_mode: "enforce",
        retention_manifest_format: "bucketed",
        metrics_retention_days: 1
      })
    )

    assert {:ok, created} = create(ctx)
    assert {:ok, _} = tick(ctx, 1_000_000_000)
    assert {:ok, :expired} = Recording.publish_one("alerts", "record", ctx.opts)
    reader = %{ctx.actor | capabilities: ctx.actor.capabilities -- ["alert:record"]}
    assert {:ok, all} = Alerting.events(ctx.actor, "record", %{}, ctx.opts)
    assert [expiry] = Enum.filter(all["events"], &(&1["type"] == "recording_expired"))
    assert "alert:record" in expiry["classification"]
    assert {:ok, denied} = Alerting.events(reader, "record", %{}, ctx.opts)
    refute Enum.any?(denied["events"], &(&1["type"] == "recording_expired"))

    # Commit genuine legacy immutable event bodies through the acknowledgement
    # seam. Head tail entries are references, not event bodies.
    for {timestamp, classification} <- [{2_000_000_000, []}, {3_000_000_000, ["alert:preview"]}] do
      assert {:ok, _} = tick(ctx, timestamp)
      assert {:ok, head, _} = Repository.load("alerts", "record", ctx.opts)
      [ref] = head["recording_queue"]
      assert {:ok, object} = Repository.revision("alerts", "record", ref, ctx.opts)

      event = %{
        "type" => "recording_expired",
        "recording" => ref,
        "revision" => object["revision"],
        "classification" => classification,
        "timestamp_ns" => to_string(timestamp),
        "actor" => %{"id" => "legacy-publisher", "type" => "service"}
      }

      progress = %{"status" => "expired", "timestamp_ns" => to_string(timestamp), "digest" => ref["digest"]}

      assert :ok =
               Repository.ack_recording(
                 "alerts",
                 "record",
                 ref,
                 ctx.opts ++ [recording_event: event, recording_progress: progress]
               )
    end

    assert {:ok, raw} = Repository.events("alerts", "record", 0, 100, ctx.opts)
    assert Enum.any?(raw, &(&1["type"] == "recording_expired" and &1["classification"] == []))
    assert Enum.any?(raw, &(&1["type"] == "recording_expired" and &1["classification"] == ["alert:preview"]))

    threshold = %{
      "kind" => "promql_threshold",
      "name" => "Threshold",
      "query" => "vector(1)",
      "threshold" => %{"op" => "gt", "value" => 0}
    }

    assert {:ok, _} = Alerting.update(ctx.actor, "record", request(threshold, "convert", created["revision"]), ctx.opts)
    assert {:ok, _} = Alerting.get(reader, "record", ctx.opts)
    assert {:ok, filtered} = Alerting.events(reader, "record", %{}, ctx.opts)
    refute Enum.any?(filtered["events"], &(&1["type"] == "recording_expired"))
    assert {:ok, authorized} = Alerting.events(ctx.actor, "record", %{}, ctx.opts)
    assert 3 == Enum.count(authorized["events"], &(&1["type"] == "recording_expired"))
    record_only = %{ctx.actor | capabilities: ctx.actor.capabilities -- ["alert:preview"]}
    assert {:ok, restricted} = Alerting.events(record_only, "record", %{}, ctx.opts)
    assert 2 == Enum.count(restricted["events"], &(&1["type"] == "recording_expired"))
    assert {:error, :forbidden} = Alerting.state(reader, "record", ctx.opts)
    config = Pulse.Runtime.get_env(:pulse, Alerting)
    principal = Map.put(reader, :token_hash, Canonical.digest("no-record-test-token"))
    privileged = Map.put(ctx.actor, :token_hash, Canonical.digest("record-test-token"))
    Pulse.Runtime.put_env(:pulse, Alerting, Keyword.update!(config, :principals, &[principal, privileged | &1]))
    conn = Plug.Test.conn(:post, "/mcp") |> Plug.Conn.put_req_header("authorization", "Bearer no-record-test-token")
    assert {:error, :forbidden} = Resources.read(conn, Resources.uri("alerts", "record", "state"), ctx.opts)
    assert {:error, :forbidden} = Resources.fingerprint(conn, Resources.uri("alerts", "record", "state"), ctx.opts)

    privileged_conn =
      Plug.Test.conn(:post, "/mcp") |> Plug.Conn.put_req_header("authorization", "Bearer record-test-token")

    assert {:ok, _} = Resources.read(privileged_conn, Resources.uri("alerts", "record", "state"), ctx.opts)
    assert {:ok, _} = Resources.fingerprint(privileged_conn, Resources.uri("alerts", "record", "state"), ctx.opts)
    assert {:ok, _} = Alerting.state(ctx.actor, "record", ctx.opts)
    assert {:ok, _} = Recording.drain("alerts", "record", ctx.opts)
    assert {:ok, drained} = Alerting.state(ctx.actor, "record", ctx.opts)
    assert drained["recording_pending"] == 0
    assert {:error, :forbidden} = Alerting.state(reader, "record", ctx.opts)
    assert {:error, :forbidden} = Resources.read(conn, Resources.uri("alerts", "record", "state"), ctx.opts)
    assert {:error, :forbidden} = Resources.fingerprint(conn, Resources.uri("alerts", "record", "state"), ctx.opts)
  end

  test "event replay preserves authorized threshold history across recording conversion and hidden pages", ctx do
    Runtime.put_env(
      :pulse,
      S3,
      Map.merge(ctx.config, %{
        retention_mode: "enforce",
        retention_manifest_format: "bucketed",
        metrics_retention_days: 1
      })
    )

    threshold = %{
      "kind" => "promql_threshold",
      "name" => "Threshold",
      "query" => "vector(1)",
      "enabled" => true,
      "cadence_ms" => 1000,
      "threshold" => %{"op" => "gt", "value" => 0}
    }

    assert {:ok, original} = create(ctx, threshold)
    assert {:ok, _} = tick(ctx, 1_000_000_000)
    assert {:ok, before_conversion} = Alerting.events(ctx.actor, "record", %{}, ctx.opts)
    assert Enum.any?(before_conversion["events"], &(&1["type"] == "firing"))

    assert {:ok, recording} =
             Alerting.update(ctx.actor, "record", request(rule(), "record", original["revision"]), ctx.opts)

    assert {:ok, _} = tick(ctx, 2_000_000_000)
    assert {:ok, :expired} = Recording.publish_one("alerts", "record", ctx.opts)
    reader = %{ctx.actor | capabilities: ctx.actor.capabilities -- ["alert:record"]}
    assert {:error, :forbidden} = Alerting.get(reader, "record", ctx.opts)
    assert {:error, :forbidden} = Alerting.state(reader, "record", ctx.opts)
    assert {:ok, historical} = Alerting.historical(reader, "record", original["revision"], ctx.opts)
    assert historical["rule"]["kind"] == "promql_threshold"
    assert {:error, :forbidden} = Alerting.changes(reader, "record", %{}, ctx.opts)
    assert {:ok, raw} = Repository.events("alerts", "record", 0, 100, ctx.opts)
    assert Enum.any?(raw, &(&1["type"] == "recording_expired"))
    # Derive the expected partition from committed revision provenance, not
    # whichever classification production happened to stamp on the events.
    expected = Enum.filter(raw, &(get_in(&1, ["revision", "digest"]) == original["revision"]))
    protected = Enum.filter(raw, &(get_in(&1, ["revision", "digest"]) == recording["revision"]))
    assert length(expected) + length(protected) == length(raw)
    assert Enum.all?(expected, &(&1["classification"] == []))
    assert Enum.all?(protected, &(&1["classification"] == ["alert:record"]))
    assert Enum.any?(protected, &(&1["type"] == "health_changed" and &1["timestamp_ns"] == "2000000000"))
    assert Enum.any?(protected, &(&1["type"] == "recording_expired"))
    assert Enum.all?(before_conversion["events"], &(&1 in expected))
    objects = Agent.get(ctx.agent, & &1.objects)

    {cursor, replayed} =
      Enum.reduce(raw, {nil, []}, fn event, {cursor, acc} ->
        assert {:ok, page} = Alerting.events(reader, "record", %{"cursor" => cursor, "limit" => 1}, ctx.opts)
        after_seq = String.to_integer(event["sequence"])
        assert {:ok, %{"after" => ^after_seq}} = Cursor.open(page["next_cursor"], reader, "events:record", ctx.opts)
        assert page["events"] == if(event in expected, do: [event], else: [])
        {page["next_cursor"], acc ++ page["events"]}
      end)

    assert replayed == expected
    assert {:ok, %{"events" => []}} = Alerting.events(reader, "record", %{"cursor" => cursor}, ctx.opts)
    principal = Map.put(reader, :token_hash, Canonical.digest("history-matrix-token"))
    config = Runtime.get_env(:pulse, Alerting)
    Runtime.put_env(:pulse, Alerting, Keyword.put(config, :principals, [principal]))

    conn =
      Plug.Test.conn(:get, "/events")
      |> Plug.Conn.put_req_header("authorization", "Bearer history-matrix-token")
      |> Plug.Conn.put_req_header("x-scope-orgid", "alerts")

    assert {:error, :forbidden} = Resources.read(conn, Resources.uri("alerts", "record", "events"), ctx.opts)

    assert {:ok, [%{"text" => text}]} =
             Tools.call("read_alert_events", %{"tenant" => "alerts", "id" => "record", "limit" => 100}, %{conn: conn})

    assert Pulse.JSON.decode!(text)["events"] == expected
    http = PulseWeb.AlertingController.events(conn, %{"id" => "record", "limit" => "100"})
    assert http.status == 200
    assert Pulse.JSON.decode!(http.resp_body)["events"] == expected
    assert Agent.get(ctx.agent, & &1.objects) == objects
  end

  test "threshold evaluation does not disclose retained recording counts without record authority", ctx do
    assert {:ok, created} = create(ctx)
    assert {:ok, _} = tick(ctx, 1_000_000_000)

    threshold = %{
      "kind" => "promql_threshold",
      "name" => "Threshold",
      "query" => "vector(1)",
      "enabled" => true,
      "cadence_ms" => 1000,
      "threshold" => %{"op" => "gt", "value" => 0}
    }

    assert {:ok, _} = Alerting.update(ctx.actor, "record", request(threshold, "convert", created["revision"]), ctx.opts)
    reader = %{ctx.actor | capabilities: ctx.actor.capabilities -- ["alert:record"]}
    now = System.system_time(:nanosecond)

    assert {:ok, response} =
             Evaluator.evaluate(reader, "record", ctx.opts ++ [timestamp_ns: now, query: query([sample(1)])])

    refute Map.has_key?(response, "recording_pending")

    assert {:ok, privileged} =
             Evaluator.evaluate(
               ctx.actor,
               "record",
               ctx.opts ++ [timestamp_ns: now + 1_000_000_000, query: query([sample(1)])]
             )

    assert privileged["recording_pending"] > 0
  end

  test "source failures, empty results, invalid output and resource deferrals never enqueue samples", ctx do
    assert {:ok, _} = create(ctx)
    assert {:ok, %{"health" => "no_data", "recording_pending" => 0}} = tick(ctx, 1_000_000_000, [])
    assert {:ok, %{"health" => "error", "recording_pending" => 0}} = tick(ctx, 2_000_000_000, [sample("invalid")])
    error = fn _, _, _ -> {:error, :query_timeout} end

    assert {:error, :evaluation_skipped} =
             Evaluator.evaluate(ctx.actor, "record", ctx.opts ++ [timestamp_ns: 3_000_000_000, query: error])

    assert parquet_keys(ctx) == []
    assert {:ok, state} = Alerting.state(ctx.actor, "record", ctx.opts)
    assert state["completed_at_ns"] == "2000000000"
  end

  test "preview is read-only even for disabled recording definitions and nonfinite results", ctx do
    assert {:ok, _} = create(ctx, rule(%{"enabled" => false}))
    before = Agent.get(ctx.agent, & &1.objects)
    assert {:ok, result} = Evaluator.preview(ctx.actor, "record", ctx.opts ++ [query: query([sample("NaN")])])
    assert result["health"] == "ok"
    assert [%{"value" => "NaN"}] = result["samples"]
    assert before == Agent.get(ctx.agent, & &1.objects)
    unprivileged = %{ctx.actor | capabilities: ctx.actor.capabilities -- ["alert:preview"]}
    assert {:error, :forbidden} = Evaluator.preview(unprivileged, "record", ctx.opts)
  end

  test "disappeared and wholly absent series publish stale markers instead of surviving lookback", ctx do
    assert {:ok, _} = create(ctx)
    assert {:ok, _} = tick(ctx, 1_000_000_000, [sample(1, %{"id" => "a"}), sample(2, %{"id" => "b"})])
    assert {:ok, :published} = Recording.publish_one("alerts", "record", ctx.opts)
    assert {:ok, _} = tick(ctx, 2_000_000_000, [sample(3, %{"id" => "b"}), sample("NaN", %{"id" => "c"})])
    assert {:ok, :published} = Recording.publish_one("alerts", "record", ctx.opts)
    assert {:ok, rows} = S3.query(:metrics, "alerts", [])
    assert Enum.any?(rows, &(&1.labels["id"] == "a" and &1.timestamp_ns == 2_000_000_000 and &1.value == :stale))
    assert Enum.any?(rows, &(&1.labels["id"] == "c" and &1.value == :nan))

    assert {:ok, %{"data" => %{"result" => live}}} =
             PromQL.query("backup_failed:sum", "alerts", %{end_ts_ns: 2_000_000_000})

    assert Enum.sort(Enum.map(live, & &1["metric"]["id"])) == ["b", "c"]
    assert {:ok, %{"health" => "no_data"}} = tick(ctx, 3_000_000_000, [])
    assert {:ok, :published} = Recording.publish_one("alerts", "record", ctx.opts)

    assert {:ok, %{"data" => %{"result" => []}}} =
             PromQL.query("backup_failed:sum", "alerts", %{end_ts_ns: 3_000_000_000})
  end

  test "configuration retirement preserves past answers and fences older cadence ticks after re-enable", ctx do
    base = div(System.system_time(:nanosecond), 1_000_000_000) * 1_000_000_000 - 5_000_000_000
    assert {:ok, created} = create(ctx)
    assert {:ok, _} = tick(ctx, base)
    assert {:ok, :published} = Recording.publish_one("alerts", "record", ctx.opts)

    assert {:ok, disabled} =
             Alerting.update(
               ctx.actor,
               "record",
               request(rule(%{"enabled" => false}), "disable", created["revision"]),
               ctx.opts
             )

    assert {:ok, :published} = Recording.publish_one("alerts", "record", ctx.opts)
    assert {:ok, head, _} = Repository.load("alerts", "record", ctx.opts)
    fence = String.to_integer(head["recording_fence_ns"])
    assert fence > base
    assert {:ok, %{"data" => %{"result" => [_]}}} = PromQL.query("backup_failed:sum", "alerts", %{end_ts_ns: base})
    assert {:ok, %{"data" => %{"result" => []}}} = PromQL.query("backup_failed:sum", "alerts", %{end_ts_ns: fence})
    assert {:ok, _} = Alerting.update(ctx.actor, "record", request(rule(), "enable", disabled["revision"]), ctx.opts)
    assert {:error, :not_due} = tick(ctx, div(fence, 1_000_000_000) * 1_000_000_000)
    assert {:ok, _} = tick(ctx, fence + 1_000_000_000)
    assert {:ok, :published} = Recording.publish_one("alerts", "record", ctx.opts)
  end

  test "bounded drain makes catch-up progress and worker-mode ticks cannot refill residual backlog", ctx do
    assert {:ok, _} = create(ctx)
    for n <- 1..10, do: assert({:ok, _} = tick(ctx, n * 1_000_000_000))
    # The count bound, not the wall-clock one, must stop this drain.
    assert {:ok, 8} = Recording.drain("alerts", "record", ctx.opts ++ [drain_ms: 60_000])
    assert {:ok, state} = Alerting.state(ctx.actor, "record", ctx.opts)
    assert state["recording_pending"] == 2
    forbidden = fn _, _, _ -> flunk("worker mode must finish catch-up before a new recording query") end

    assert {:error, :recording_backlog} =
             Evaluator.evaluate(
               ctx.actor,
               "record",
               ctx.opts ++ [timestamp_ns: 11_000_000_000, query: forbidden, require_recording_drained: true]
             )

    unavailable = fn _, _, _ -> {:error, :storage_unavailable} end

    assert {:error, :storage_unavailable} =
             Recording.publish_one("alerts", "record", ctx.opts ++ [recording_append: unavailable])

    assert {:ok, state} = Alerting.state(ctx.actor, "record", ctx.opts)
    assert state["recording_error"]["reason"] == "storage_unavailable"
    assert {:ok, 2} = Recording.drain("alerts", "record", ctx.opts)
    assert {:ok, state} = Alerting.state(ctx.actor, "record", ctx.opts)
    refute Map.has_key?(state, "recording_error")
    assert {:ok, _} = tick(ctx, 11_000_000_000)
  end

  test "state resource fingerprints include recording acknowledgements and blocked publication", ctx do
    principal = Map.put(ctx.actor, :token_hash, Canonical.digest("recording-test-token"))
    Runtime.put_env(:pulse, Alerting, principals: [principal])
    conn = Plug.Test.conn(:post, "/mcp") |> Plug.Conn.put_req_header("authorization", "Bearer recording-test-token")
    uri = Resources.uri("alerts", "record", "state")
    assert {:ok, _} = create(ctx)
    assert {:ok, _} = tick(ctx, 1_000_000_000)
    assert {:ok, pending} = Resources.fingerprint(conn, uri, ctx.opts)
    unavailable = fn _, _, _ -> {:error, :storage_unavailable} end

    assert {:error, :storage_unavailable} =
             Recording.publish_one("alerts", "record", ctx.opts ++ [recording_append: unavailable])

    assert {:ok, blocked} = Resources.fingerprint(conn, uri, ctx.opts)
    refute blocked == pending
    assert {:ok, :published} = Recording.publish_one("alerts", "record", ctx.opts)
    assert {:ok, published} = Resources.fingerprint(conn, uri, ctx.opts)
    refute published in [pending, blocked]
  end

  test "complete replacement of two individually valid rich sets fits the joint transition budget" do
    old = Enum.map(1..100, &sample(1, %{"id" => "old-#{&1}", "padding" => String.duplicate("x", 190)}))
    fresh = Enum.map(1..100, &sample(1, %{"id" => "new-#{&1}", "padding" => String.duplicate("x", 190)}))
    assert {:ok, previous} = Recording.transition(rule(), old, 1, [])
    assert {:ok, replaced} = Recording.transition(rule(), fresh, 2, previous["next_series"])
    assert length(replaced["samples"]) == 200
    assert Enum.count(replaced["samples"], &(&1["stale"] == true)) == 100
    assert length(replaced["next_series"]) == 100
    assert byte_size(Canonical.encode(Map.delete(replaced, "next_series"))) <= 63_488
  end

  test "rule administration alone cannot create a metric-writing recording rule", ctx do
    actor = %{ctx.actor | capabilities: ctx.actor.capabilities -- ["alert:record"]}

    params = %{
      "operation_id" => "recording-denied",
      "reason" => "capability test",
      "rule" => rule(%{"query" => "vector(0)"})
    }

    assert {:error, :forbidden} = Alerting.create(actor, "unprivileged-recording", params, ctx.opts)
    assert {:error, :not_found} = Repository.load("alerts", "unprivileged-recording", ctx.opts)
  end

  test "a clock behind the completed tick cannot place retirement at the last real sample", ctx do
    ns = System.system_time(:nanosecond) + 1_000_000_000
    assert {:ok, created} = create(ctx)
    assert {:ok, _} = tick(ctx, ns)
    assert {:ok, :published} = Recording.publish_one("alerts", "record", ctx.opts)

    assert {:ok, _} =
             Alerting.update(
               ctx.actor,
               "record",
               request(rule(%{"enabled" => false}), "disable-skew", created["revision"]),
               Keyword.put(ctx.opts, :clock_ns, fn -> ns - 1_000_000_000 end)
             )

    assert {:ok, head, _} = Repository.load("alerts", "record", ctx.opts)
    assert String.to_integer(head["recording_fence_ns"]) == ns + 1
    assert {:ok, :published} = Recording.publish_one("alerts", "record", ctx.opts)
    assert {:ok, %{"data" => %{"result" => [_]}}} = PromQL.query("backup_failed:sum", "alerts", %{end_ts_ns: ns})
    assert {:ok, %{"data" => %{"result" => []}}} = PromQL.query("backup_failed:sum", "alerts", %{end_ts_ns: ns + 1})
  end

  test "empty static label overrides remove source labels" do
    assert {:ok, result} = Recording.result(rule(%{"labels" => %{"job" => ""}}), [sample(1, %{"job" => "source"})], 1)
    assert hd(result["samples"])["labels"] == %{"__name__" => "backup_failed:sum"}
  end

  test "oversized committed objects are rejected during bounded GET and remain pending", ctx do
    assert {:ok, _} = create(ctx)
    assert {:ok, _} = tick(ctx, 1_000_000_000)
    assert {:ok, head, _} = Repository.load("alerts", "record", ctx.opts)
    [ref] = head["recording_queue"]

    Agent.update(ctx.agent, fn state ->
      {etag, _body} = Map.fetch!(state.objects, ref["key"])
      %{state | objects: Map.put(state.objects, ref["key"], {etag, String.duplicate("x", 131_072)})}
    end)

    assert {:error, :integrity_error} = Recording.publish_one("alerts", "record", ctx.opts)
    assert {:ok, state} = Alerting.state(ctx.actor, "record", ctx.opts)
    assert state["recording_pending"] == 1
    assert parquet_keys(ctx) == []
  end

  test "rule heads also enforce their ceiling before body allocation", ctx do
    assert {:ok, _} = create(ctx)
    key = "tenants/alerts/alerting/v1/rules/record/head.json"

    Agent.update(ctx.agent, fn state ->
      {etag, _body} = Map.fetch!(state.objects, key)
      %{state | objects: Map.put(state.objects, key, {etag, String.duplicate("x", 1_048_577)})}
    end)

    assert {:error, :response_too_large} = Repository.load("alerts", "record", ctx.opts)
    assert parquet_keys(ctx) == []
  end

  test "corrupt committed results fail checksum verification and stay pending", ctx do
    assert {:ok, _} = create(ctx)
    assert {:ok, _} = tick(ctx, 1_000_000_000)
    assert {:ok, head, _} = Repository.load("alerts", "record", ctx.opts)
    [ref] = head["recording_queue"]

    Agent.update(ctx.agent, fn state ->
      {etag, body} = Map.fetch!(state.objects, ref["key"])
      corrupt = body |> Pulse.JSON.decode!() |> Map.put("samples", []) |> Canonical.encode()
      %{state | objects: Map.put(state.objects, ref["key"], {etag, corrupt})}
    end)

    assert {:error, :integrity_error} = Recording.publish_one("alerts", "record", ctx.opts)
    assert {:ok, state} = Alerting.state(ctx.actor, "record", ctx.opts)
    assert state["recording_pending"] == 1
    assert parquet_keys(ctx) == []
  end
end
