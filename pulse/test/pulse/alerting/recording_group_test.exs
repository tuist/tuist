defmodule Pulse.Alerting.RecordingGroupTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Alerting
  alias Pulse.Alerting.{Evaluator, Recording, Repository, Rule, RuleFiles}
  alias Pulse.PromQL.Evaluator, as: PromQL
  alias Pulse.Record.MetricSample
  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Test.CompactionStore

  @fixture "test/fixtures/alerting/kura_recording.json"
  # A minute boundary, so recording ticks align like Prometheus's group ticks.
  @t0 1_793_836_800_000_000_000
  @minute 60_000_000_000

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
      tenant: "kura",
      id: "operator",
      type: "human",
      capabilities: ~w(alert:read alert:rules:write alert:preview alert:evaluate alert:record)
    }

    %{agent: agent, actor: actor, opts: [store_config: config]}
  end

  defp request(rule, op, revision \\ nil),
    do: %{"rule" => rule, "operation_id" => op, "reason" => "Record kura topology", "expected_revision" => revision}

  defp tick(ctx, id, ns) do
    result = Evaluator.evaluate(ctx.actor, id, ctx.opts ++ [timestamp_ns: ns])
    assert {:ok, _} = Recording.drain("kura", id, ctx.opts)
    result
  end

  defp class_a(ctx),
    do:
      Agent.get(ctx.agent, fn state -> Enum.count(state.requests, fn {method, _} -> method in ["PUT", "POST"] end) end)

  # promtool's expanding notation: `a+bxN` is N+1 values, `_xN` N gaps.
  defp expand(values) do
    values
    |> String.split(" ")
    |> Enum.flat_map(fn
      "stale" ->
        [:stale]

      "_x" <> n ->
        List.duplicate(nil, String.to_integer(n))

      term ->
        [_, start, sign, step, n] = Regex.run(~r/\A(-?\d+)([+-])(\d+)x(\d+)\z/, term)
        step = if sign == "-", do: -String.to_integer(step), else: String.to_integer(step)
        for i <- 0..String.to_integer(n), do: (String.to_integer(start) + i * step) * 1.0
    end)
  end

  defp ingest(fixture) do
    interval = fixture["scrape_interval_s"] * 1_000_000_000

    fixture["series"]
    |> Enum.flat_map(fn %{"labels" => labels, "values" => values} ->
      for {value, i} <- Enum.with_index(expand(values)),
          value != nil,
          do: %MetricSample{labels: labels, timestamp_ns: @t0 + i * interval, value: value}
    end)
    # One segment per metric name, as separate scrape jobs would produce, so
    # each selector reads only the segments its name can match.
    |> Enum.group_by(& &1.labels["__name__"])
    |> Enum.each(fn {_name, records} -> assert :ok = Storage.append(:metrics, "kura", records) end)
  end

  defp value(text) do
    case text do
      "NaN" -> :nan
      "+Inf" -> :inf
      "-Inf" -> :neg_inf
      _ -> text |> Float.parse() |> elem(0)
    end
  end

  test "the kura recording group matches Prometheus 3.5.0 rule-group evaluation at production volume", ctx do
    fixture = @fixture |> File.read!() |> Pulse.JSON.decode!()
    ingest(fixture)
    assert {:ok, _} = Alerting.create(ctx.actor, "kura-recording", request(fixture["group"], "create"), ctx.opts)

    # Prometheus evaluates the group from the first tick; so does Pulse.
    for minute <- 0..15 do
      assert {:ok, %{"health" => "ok"}} = tick(ctx, "kura-recording", @t0 + minute * @minute)
    end

    assert {:ok, state} = Alerting.state(ctx.actor, "kura-recording", ctx.opts)
    assert state["recording_pending"] == 0

    assert Enum.map(state["recording_rules"], &{&1["record"], &1["series"]}) == [
             {"kura:pod_region", 372},
             {"kura:node_pool", 69},
             {"kura:pool_region", 11},
             {"kura:node_region", 27}
           ]

    labels = fixture["labels"]

    mismatches =
      for evaluation <- fixture["evaluations"],
          ts = @t0 + evaluation["time_s"] * 1_000_000_000,
          {:ok, %{"data" => %{"result" => result}}} = PromQL.query(evaluation["expr"], "kura", %{end_ts_ns: ts}),
          actual = Map.new(result, &{&1["metric"], value(List.last(&1["value"]))}),
          expected = Map.new(evaluation["result"], fn [id, text] -> {Enum.at(labels, id), value(text)} end),
          actual != expected do
        {evaluation["expr"], evaluation["time_s"], Map.drop(expected, Map.keys(actual)) |> Enum.take(3),
         Map.drop(actual, Map.keys(expected)) |> Enum.take(3),
         for({k, v} <- expected, Map.has_key?(actual, k), actual[k] != v, do: {k, v, actual[k]}) |> Enum.take(3)}
      end

    assert mismatches == []
    # Every recorded tick is a distinct sample; chained rules never lag.
    assert fixture["evaluations"] |> Enum.filter(&String.starts_with?(&1["expr"], "kura:")) |> length() == 60
  end

  @tag timeout: 60_000
  test "the Kura regional latency alert fits the production heap with a packed metric object" do
    # The saved alert, but synthetic samples: two different regional
    # histograms, an idle region, and a pod without a topology recording.
    # A single large object exposed whole-object term expansion before any
    # rate or join could run; splitting these same rows into small objects
    # masked that failure. Keep the production budgets, not a larger heap.
    Runtime.put_env(:pulse, Pulse.QueryRunner,
      max_heap_words: div(160 * 1_048_576, 8),
      timeout_ms: 15_000
    )

    Runtime.put_env(:pulse, PromQL, max_samples: 300_000, max_scan_bytes: 268_435_456)

    fixture = @fixture |> File.read!() |> Pulse.JSON.decode!()
    alert = Enum.find(fixture["alerts"], &Enum.any?(&1["rules"], fn rule -> rule["uid"] == "ffx2xchowcwlce" end))
    finish = @t0 + 5 * @minute

    samples =
      Enum.flat_map(1..64, fn pod ->
        region = if pod == 64, do: "idle", else: if(rem(pod, 2) == 0, do: "eu", else: "us")
        scale = if region == "us", do: 2, else: 1
        traffic = if region == "idle", do: 0.001, else: 1.0

        counters =
          for route <- 1..4, replica <- 1..4, bucket <- 1..17, tick <- 0..10 do
            labels = %{
              "cluster" => "tuist-production",
              "pod" => "kura-#{pod}",
              "route" => "route-#{route}",
              "instance" => "instance-#{replica}"
            }

            labels =
              if bucket == 17 do
                Map.put(labels, "__name__", "kura_public_request_latency_seconds_count")
              else
                labels
                |> Map.put("__name__", "kura_public_request_latency_seconds_bucket")
                |> Map.put("le", if(bucket == 16, do: "+Inf", else: "#{bucket * scale}"))
              end

            %MetricSample{
              labels: labels,
              timestamp_ns: finish - (10 - tick) * div(@minute, 2),
              value: tick * min(bucket, 16) * traffic
            }
          end

        topology =
          if pod == 63 do
            []
          else
            [
              %MetricSample{
                labels: %{
                  "__name__" => "kura:pod_region",
                  "cluster" => "tuist-production",
                  "pod" => "kura-#{pod}",
                  "region" => region
                },
                timestamp_ns: finish,
                value: 1.0
              }
            ]
          end

        counters ++ topology
      end)

    assert :ok = Storage.append(:metrics, "kura", samples)
    assert {:ok, %{"data" => %{"result" => result}}} = PromQL.query(alert["expr"], "kura", %{end_ts_ns: finish})

    # p95 lies in +Inf (15.2 of 16 equal increments): Prometheus returns
    # the last finite bound, 15 in eu and 30 in us. The idle region's
    # request rate is below one and the unrecorded pod cannot join.
    assert Map.new(result, &{&1["metric"], value(List.last(&1["value"]))}) == %{
             %{"cluster" => "tuist-production", "region" => "eu"} => 15.0,
             %{"cluster" => "tuist-production", "region" => "us"} => 30.0
           }

    # The selected-sample limit remains shared across chunks and selectors.
    # Left-open rate windows select ten scrapes per counter series; the
    # shared topology selector is loaded once, not once per join branch.
    selected = 64 * 4 * 4 * 17 * 10 + 63
    Runtime.put_env(:pulse, PromQL, max_samples: selected)
    assert {:ok, %{"data" => %{"result" => ^result}}} = PromQL.query(alert["expr"], "kura", %{end_ts_ns: finish})
    Runtime.put_env(:pulse, PromQL, max_samples: selected - 1)
    assert {:error, :query_sample_limit} = PromQL.query(alert["expr"], "kura", %{end_ts_ns: finish})
  end

  test "one group tick costs one head commit, one segment, one manifest CAS and one acknowledgement", ctx do
    fixture = @fixture |> File.read!() |> Pulse.JSON.decode!()
    ingest(fixture)
    assert {:ok, _} = Alerting.create(ctx.actor, "kura-recording", request(fixture["group"], "create"), ctx.opts)
    assert {:ok, _} = tick(ctx, "kura-recording", @t0 + 5 * @minute)

    before = class_a(ctx)

    assert {:ok, %{"recording_pending" => 1}} =
             Evaluator.evaluate(ctx.actor, "kura-recording", ctx.opts ++ [timestamp_ns: @t0 + 6 * @minute])

    assert class_a(ctx) - before == 1
    assert {:ok, 1} = Recording.drain("kura", "kura-recording", ctx.opts)
    assert class_a(ctx) - before == 4

    # The 479 samples rode inline in the head: no intent object exists.
    keys = Agent.get(ctx.agent, &Map.keys(&1.objects))
    refute Enum.any?(keys, &String.contains?(&1, "/recordings/"))
  end

  defp simple(rules, extra \\ %{}) do
    Map.merge(
      %{
        "kind" => "promql_recording_group",
        "name" => "chain",
        "enabled" => true,
        "cadence_ms" => 60_000,
        "rules" => rules
      },
      extra
    )
  end

  test "a pending historical recording intent reuses its already-published metric object", ctx do
    group = simple([%{"record" => "recorded", "expr" => "vector(2)"}])
    assert {:ok, _} = Alerting.create(ctx.actor, "historical", request(group, "create"), ctx.opts)

    assert {:ok, %{"recording_pending" => 1}} =
             Evaluator.evaluate(ctx.actor, "historical", ctx.opts ++ [timestamp_ns: @t0])

    assert {:ok, %{"recording_queue" => [ref]}, _} = Repository.load("kura", "historical", ctx.opts)
    rows = [%MetricSample{labels: %{"__name__" => "recorded"}, timestamp_ns: @t0, value: 2.0}]
    # The historical publisher committed the append, but crashed before ack.
    assert :ok = S3.append(:metrics, "kura", rows, idempotency_key: "pulso-recording-v1-" <> ref["digest"])
    before = Agent.get(ctx.agent, &Map.keys(&1.objects)) |> Enum.filter(&String.ends_with?(&1, ".parquet"))
    assert [_] = before
    assert {:ok, 1} = Recording.drain("kura", "historical", ctx.opts)
    assert {:ok, 0} = Recording.drain("kura", "historical", ctx.opts)
    after_keys = Agent.get(ctx.agent, &Map.keys(&1.objects)) |> Enum.filter(&String.ends_with?(&1, ".parquet"))
    assert after_keys == before
    assert {:ok, [sample]} = S3.query(:metrics, "kura", [])
    assert sample.labels == %{"__name__" => "recorded"}
    assert sample.value == 2.0
    assert {:ok, %{"recording_pending" => 0}} = Alerting.state(ctx.actor, "historical", ctx.opts)
  end

  defp samples(name, values) do
    for {value, minute} <- Enum.with_index(values),
        do: %MetricSample{
          labels: %{"__name__" => name, "job" => "a"},
          timestamp_ns: @t0 + minute * @minute,
          value: value
        }
  end

  defp at(query, minute) do
    {:ok, %{"data" => %{"result" => result}}} = PromQL.query(query, "kura", %{end_ts_ns: @t0 + minute * @minute})
    Enum.map(result, &{&1["metric"], List.last(&1["value"])})
  end

  test "later rules read earlier results of the same tick; a failed rule keeps its series without stale markers",
       ctx do
    assert :ok = Storage.append(:metrics, "kura", samples("source", [1.0, 2.0, 3.0]))
    # `dup` has two series with the same `job`, so `on (job)` matching fails at minute 1.
    assert :ok =
             Storage.append(:metrics, "kura", [
               %MetricSample{labels: %{"__name__" => "dup", "job" => "a", "i" => "1"}, timestamp_ns: @t0, value: 1.0},
               %MetricSample{
                 labels: %{"__name__" => "dup", "job" => "a", "i" => "1"},
                 timestamp_ns: @t0 + @minute,
                 value: 1.0
               },
               %MetricSample{
                 labels: %{"__name__" => "dup", "job" => "a", "i" => "2"},
                 timestamp_ns: @t0 + @minute,
                 value: 1.0
               },
               %MetricSample{
                 labels: %{"__name__" => "dup", "job" => "a", "i" => "1"},
                 timestamp_ns: @t0 + 2 * @minute,
                 value: 1.0
               },
               %MetricSample{
                 labels: %{"__name__" => "dup", "job" => "a", "i" => "2"},
                 timestamp_ns: @t0 + 2 * @minute,
                 value: :stale
               }
             ])

    group =
      simple([
        %{"record" => "job:first", "expr" => "sum by (job) (source)"},
        %{"record" => "job:fragile", "expr" => "job:first * on (job) group_left() dup"},
        %{"record" => "job:last", "expr" => "job:first * 10 + on (job) job:fragile"}
      ])

    assert {:ok, _} = Alerting.create(ctx.actor, "chain", request(group, "create"), ctx.opts)

    # Preview chains the same way and writes nothing.
    assert {:ok, %{"health" => "ok", "rules" => [_, _, %{"record" => "job:last", "samples" => [%{"value" => "11"}]}]}} =
             Evaluator.preview(ctx.actor, "chain", ctx.opts ++ [timestamp_ns: @t0])

    assert at("job:first", 0) == []
    assert {:ok, %{"health" => "ok"}} = tick(ctx, "chain", @t0)
    assert {:ok, %{"health" => "error"}} = tick(ctx, "chain", @t0 + @minute)
    assert {:ok, state} = Alerting.state(ctx.actor, "chain", ctx.opts)

    assert [%{"health" => "ok"}, %{"health" => "error", "error" => "many_to_many_matching"}, %{"health" => "ok"}] =
             state["recording_rules"]

    assert {:ok, %{"health" => "ok"}} = tick(ctx, "chain", @t0 + 2 * @minute)

    # Same-tick: job:first is 1, 2, 3 at minutes 0, 1, 2, and job:last uses
    # that tick's job:first. At minute 1 job:fragile failed, so job:last read
    # its minute-0 sample from storage, as Prometheus does.
    assert at("job:first", 1) == [{%{"__name__" => "job:first", "job" => "a"}, "2"}]
    assert at("job:last", 0) == [{%{"__name__" => "job:last", "job" => "a"}, "11"}]
    assert at("job:last", 1) == [{%{"__name__" => "job:last", "job" => "a"}, "21"}]
    assert at("job:last", 2) == [{%{"__name__" => "job:last", "job" => "a"}, "33"}]
    # The failed tick wrote neither a sample nor a stale marker.
    assert at("timestamp(job:fragile)", 1) == [{%{"job" => "a"}, Integer.to_string(div(@t0, 1_000_000_000))}]
  end

  test "groups validate Prometheus rule fields, unique names and expressions", _ctx do
    rule = simple([%{"record" => "a:b", "expr" => "sum(x)"}])
    assert {:ok, %{"rules" => [%{"labels" => %{}}]}} = Rule.validate(rule)
    assert Rule.classification(rule) == ["alert:record"]

    for bad <- [
          [],
          [%{"record" => "a:b", "expr" => "sum(x)"}, %{"record" => "a:b", "expr" => "sum(y)"}],
          [%{"record" => "bad name", "expr" => "sum(x)"}],
          [%{"record" => "a:b", "expr" => "sum("}],
          [%{"record" => "a:b", "expr" => "sum(x)", "labels" => %{"__name__" => "x"}}],
          [%{"record" => "a:b", "expr" => "sum(x)", "for" => "5m"}],
          List.duplicate(%{"record" => "a:b", "expr" => "x"}, 65)
        ] do
      assert {:error, :invalid_rule} = Rule.validate(simple(bad))
    end

    assert {:error, :invalid_rule} = Rule.validate(Map.put(rule, "query", "x"))
  end

  test "group results are bounded per group: 4096 series fit, 4097 fail whole without publishing", ctx do
    rows =
      for i <- 1..4097,
          do: %MetricSample{labels: %{"__name__" => "wide", "i" => Integer.to_string(i)}, timestamp_ns: @t0, value: 1.0}

    assert :ok = Storage.append(:metrics, "kura", rows)

    group =
      simple([
        %{"record" => "wide:copy", "expr" => "wide{i!=\"4097\"}"},
        %{"record" => "wide:one", "expr" => "wide{i=\"4097\"}"}
      ])

    assert {:ok, _} = Alerting.create(ctx.actor, "wide", request(group, "create"), ctx.opts)
    assert {:ok, %{"health" => "error"}} = tick(ctx, "wide", @t0)
    assert {:ok, head, _} = Repository.load("kura", "wide", ctx.opts)
    assert head["recording_series"] == []

    assert {:ok, %{"revision" => revision}} = Alerting.get(ctx.actor, "wide", ctx.opts)
    fits = put_in(group, ["rules"], [hd(group["rules"])])
    assert {:ok, _} = Alerting.update(ctx.actor, "wide", request(fits, "fits", revision), ctx.opts)
    assert {:ok, %{"health" => "ok"}} = tick(ctx, "wide", @t0 + @minute)
    assert length(at("wide:copy", 1)) == 4096
  end

  test "a Prometheus rule file converts to the same disabled group, keeping file order", _ctx do
    fixture = @fixture |> File.read!() |> Pulse.JSON.decode!()

    rules =
      Enum.map_join(fixture["group"]["rules"], "", fn rule ->
        "      - record: #{rule["record"]}\n        expr: |\n" <>
          (rule["expr"] |> String.split("\n") |> Enum.map_join("", &"          #{&1}\n"))
      end)

    yaml = """
    groups:
      - name: Kura Recording
        interval: 1m
        rules:
    #{rules}      - alert: KuraDown
            expr: up{job="kura"} == 0
            for: 5m
      - name: Alerts only
        rules:
          - alert: Other
            expr: vector(1)
    """

    assert {:ok, %{"rules" => [%{"id" => "kura-recording", "rule" => rule}], "skipped" => skipped}} =
             RuleFiles.preview(yaml)

    assert skipped == [
             %{"group" => "Kura Recording", "rule" => "KuraDown", "reason" => "alerting_rule_not_converted"},
             %{"group" => "Alerts only", "rule" => "Other", "reason" => "alerting_rule_not_converted"}
           ]

    # YAML block scalars keep a trailing newline; the queries are otherwise identical.
    assert Enum.map(rule["rules"], &String.trim_trailing(&1["expr"])) ==
             Enum.map(fixture["group"]["rules"], & &1["expr"])

    assert Map.delete(rule, "rules") == fixture["group"] |> Map.delete("rules") |> Map.put("enabled", false)
    assert {:ok, _} = Rule.validate(rule)

    assert {:ok, %{"rules" => [%{"rule" => %{"cadence_ms" => 90_000, "rules" => [%{"labels" => labels}]}}]}} =
             RuleFiles.preview(
               ~s|groups: [{name: g, interval: 1m30s, labels: {team: a, tier: 1}, rules: [{record: "a:b", expr: "sum(x)", labels: {tier: 2}}]}]|
             )

    assert labels == %{"team" => "a", "tier" => "2"}

    assert {:ok, %{"rules" => [], "skipped" => [%{"reason" => "query_offset_unsupported"}]}} =
             RuleFiles.preview(
               ~s|{"groups": [{"name": "g", "query_offset": "1m", "rules": [{"record": "a:b", "expr": "x"}]}]}|
             )

    for bad <- ["groups: [", "not: groups", String.duplicate("a", 262_145), "a: &a [*a, *a]\nb: *a"] do
      assert {:error, :invalid_import} = RuleFiles.preview(bad)
    end
  end

  test "a Grafana export converts recordings in dependency order and skips what it cannot record", _ctx do
    fixture = @fixture |> File.read!() |> Pulse.JSON.decode!()
    [pod, node_pool, pool, node] = fixture["group"]["rules"]

    grafana = fn %{"record" => record, "expr" => expr} ->
      %{
        "uid" => String.replace(record, ":", "-"),
        "title" => record,
        "record" => %{"metric" => record, "from" => "A", "targetDatasourceUid" => "grafanacloud-prom"},
        "data" => [
          %{
            "refId" => "A",
            "datasourceUid" => "grafanacloud-prom",
            "relativeTimeRange" => %{"from" => 600},
            "model" => %{"expr" => expr, "instant" => true, "range" => false, "refId" => "A"}
          }
        ]
      }
    end

    alert = %{
      "uid" => "alert",
      "title" => "An alert",
      "condition" => "C",
      "data" => [%{"refId" => "A", "datasourceUid" => "grafanacloud-prom", "model" => %{"expr" => "up"}}]
    }

    # Grafana lists the group's rules in any order (node_region first here).
    export = %{
      "apiVersion" => 1,
      "groups" => [
        %{
          "orgId" => 1,
          "name" => "Kura Recording",
          "folder" => "Kura",
          "interval" => "1m",
          "rules" => [grafana.(node), grafana.(pool), alert, grafana.(node_pool), grafana.(pod)]
        }
      ]
    }

    assert {:ok, %{"rules" => [%{"rule" => rule}], "skipped" => [%{"rule" => "An alert"}]}} =
             RuleFiles.preview(Pulse.JSON.encode!(export))

    assert Enum.map(rule["rules"], & &1["record"]) ==
             ~w(kura:node_pool kura:pod_region kura:pool_region kura:node_region)

    assert Map.new(rule["rules"], &{&1["record"], &1["expr"]}) ==
             Map.new(fixture["group"]["rules"], &{&1["record"], &1["expr"]})
  end
end
