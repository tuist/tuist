defmodule Symptoms.EndToEndTest do
  @moduledoc """
  The evaluator end to end against a fake Pulse and a fake Prometheus (Req
  stubbed with Mimic, rows shaped like the Flow tables, the errors table and
  the span edges): a quiet period, a Postgres failure on one route that opens
  one shared-cause root, the log API serving it, and resolution.
  """
  use Symptoms.DataCase
  use Mimic

  import Phoenix.ConnTest
  import Plug.Conn

  alias Symptoms.Baselines
  alias Symptoms.Pipeline
  alias Symptoms.Sources
  alias Symptoms.Store
  alias Symptoms.Store.StreamWindow
  alias Symptoms.Store.Symptom

  @endpoint SymptomsWeb.Endpoint
  @moduletag :tmp_dir

  # Monday 10:10 UTC (11:10 Berlin, day prices).
  @t0 ~U[2026-11-16 10:10:00.000000Z]
  @server "tuist-server"
  @route %{environment: "production", service: @server, kind: "span_server", key: "GET /api/projects/:id"}
  @client %{environment: "production", service: @server, kind: "span_client", key: "tuist.repo.query:projects"}
  @cache %{environment: "production", service: @server, kind: "span_server", key: "GET /api/cache"}
  @sources [
    Sources.PulseTraces,
    Sources.PulseLogs,
    Sources.PulseSpanEdges,
    Sources.PromMetrics,
    Sources.Probes,
    Sources.Presence
  ]
  @definitions [
    %{
      key: "postgres.connections",
      phenomenon: :saturation,
      role: :resource,
      split: nil,
      units: "connections",
      promql: "sum(cnpg_backends_total)"
    }
  ]

  # The contract in README "Symptom log", plus `board`.
  @contract_keys ~w(schema_version seq symptom_id symptom_key scope revision state merged_into tier transition entity phenomenon
                    title phenomena score p_degraded impact budget_price decision root suspected_change evidence
                    board brief_ref outcome opened_at updated_at resolved_at)

  setup %{tmp_dir: dir} do
    previous =
      for key <- [Sources.Pulse, Sources.Prometheus, :source_opts, :api_auth],
          do: {key, Application.get_env(:symptoms, key)}

    token_path = Path.join(dir, "reviewer-token")
    File.write!(token_path, "reviewer-token")

    Application.put_env(:symptoms, :api_auth,
      base_url: "https://kube.test",
      server_namespace: "tuist",
      server_service_account: "server",
      token_path: token_path,
      ca_file: Path.join(dir, "ca.crt")
    )

    stub(Req, :post, fn _url, opts ->
      assert opts[:json].spec.token == "test-projected-token"

      {:ok,
       %Req.Response{
         status: 201,
         body: %{
           "status" => %{
             "authenticated" => true,
             "user" => %{"username" => "system:serviceaccount:tuist:server"},
             "audiences" => ["tuist-symptoms-api"]
           }
         }
       }}
    end)

    Application.put_env(:symptoms, Sources.Pulse, base_url: "http://pulse.test", token: "read")
    Application.put_env(:symptoms, Sources.Prometheus, base_url: "http://mimir.test/api/prom")
    Application.put_env(:symptoms, :source_opts, [{Sources.PromMetrics, definitions: @definitions}])

    on_exit(fn ->
      for {key, value} <- previous do
        if value, do: Application.put_env(:symptoms, key, value), else: Application.delete_env(:symptoms, key)
      end
    end)

    Mimic.stub(Req, :request, fn request ->
      body =
        if String.ends_with?(request.url.path, "/v1/sql"),
          do: pulse(request.options.params[:sql], request.options[:auth]),
          else: prometheus(request.url.path, request.options.params[:query])

      case body do
        {:error, status} -> {:ok, %Req.Response{status: status, body: ""}}
        body -> {:ok, %Req.Response{status: 200, body: body}}
      end
    end)

    seed_history([@route, @client, @cache])
    :ok
  end

  test "quiet, a Postgres failure on one route opens one shared-cause root, the log serves it, and it resolves" do
    # Baselines from 28 days of the fake Flow tables (README "Inputs").
    assert :ok = Baselines.refresh(Sources.PulseTraces, @t0)

    # Quiet: 10:10–10:15. The window ending 10:15 builds the 09:00 span edges.
    for minute <- 0..5 do
      assert %{opened: []} = run(minute, failing: false)
      if minute == 0, do: assert(:ok = Baselines.refresh(Sources.PromMetrics, window_end(0)))
    end

    assert Repo.all(Symptom) == []
    # route → postgres and client span → postgres (aliases merged), cache → kura.
    postgres = Store.entity_id(%{environment: "production", service: "postgres", kind: "resource", key: "postgres"})
    callers = for {caller, ^postgres} <- Store.edges(), do: caller
    assert Enum.sort(callers) == Enum.sort([Store.entity_id(@route), Store.entity_id(@client)])
    assert length(Store.edges()) == 3
    assert metric_records?()

    # Every Pulse request is a read as the evaluator's read-only user; it
    # never writes to Pulse.
    {:messages, messages} = Process.info(self(), :messages)
    pulse_requests = for {:pulse_auth, sql, auth} <- messages, do: {sql, auth}
    assert pulse_requests != []
    assert Enum.all?(pulse_requests, fn {sql, auth} -> sql =~ ~r/^\s*SELECT/ and auth == {:basic, "symptoms:read"} end)

    # Failure: the route and its Postgres client span return 120 errors in 600
    # (baseline p = 0.0025). Each window is above all 180 quiet windows:
    # p = 1/181, e = 0.5·√181, 1.906 nats; the 4th window crosses h = 6.
    for minute <- 6..8, do: assert(%{opened: []} = run(minute, failing: true))
    assert %{opened: opened} = run(9, failing: true)
    assert length(opened) == 2

    symptoms = Repo.all(Symptom)
    root_ids = symptoms |> Enum.map(& &1.document["root"]["root_symptom_id"]) |> Enum.uniq()
    assert [root_id] = root_ids
    root = Repo.get!(Symptom, root_id)
    assert root.root_key =~ ~r/^60:shared:entity:\d+$/

    # The errors table sees the failure on the 5-minute pipeline.
    run_five(1, now: DateTime.shift(window_end(9), minute: 2))
    assert Repo.exists?(from(w in StreamWindow, where: w.source == "error.novelty" and w.window_seconds == 300))

    # The log API serves the root's revisions in the README contract.
    %{"revisions" => revisions, "next" => next} =
      build_conn()
      |> put_req_header("authorization", "Bearer test-projected-token")
      |> get("/api/v1/symptoms/log?after=0")
      |> json_response(200)

    assert next == List.last(revisions)["seq"]
    [opened_doc | _] = root_revisions = Enum.filter(revisions, &(&1["symptom_id"] == root_id))

    for doc <- revisions, do: assert(Enum.sort(Map.keys(doc)) == Enum.sort(@contract_keys))

    assert %{
             "schema_version" => "1.0",
             "revision" => 1,
             "state" => "open",
             "transition" => "opened",
             "scope" => %{"kind" => "tuist_ops"},
             "merged_into" => nil,
             "entity" => %{"environment" => "production", "service" => @server},
             "root" => %{"root_symptom_id" => ^root_id, "member_symptom_ids" => [_member], "shared_cause" => true},
             "impact" => %{"unit" => "failed_requests_per_min", "rate" => 120.0},
             "resolved_at" => nil
           } = opened_doc

    assert [%{"phenomenon" => "request_errors", "sources" => ["trace.error_betabinomial"]}] = opened_doc["phenomena"]
    assert opened_doc["tier"] in ~w(audit board page)
    assert opened_doc["decision"]["tier"] == opened_doc["tier"]
    assert is_boolean(opened_doc["decision"]["would_page"])
    assert byte_size(Jason.encode!(opened_doc)) <= Symptoms.Log.max_bytes()

    # The attribute contrast is recorded on the next revision: one pod holds
    # 570 of 600 error spans but half the spans (lift 1.9).
    [contrast_doc] = Enum.filter(root_revisions, &get_in(&1, ["evidence", "attribute_contrast"]))
    assert contrast_doc["transition"] == "annotated"
    contrast = Map.new(contrast_doc["evidence"]["attribute_contrast"], &{&1["attribute"], &1["values"]})
    assert [%{"value" => "tuist-server-7d9f8b6c5d-x2x4z", "lift" => 1.9} | _] = contrast["pod"]
    refute Map.has_key?(contrast, "region")

    # Recovery: the 5th consecutive quiet window resolves every symptom of the root.
    for minute <- 10..13, do: assert(%{resolved: []} = run(minute, failing: false))
    assert %{resolved: resolved} = run(14, failing: false)
    assert Enum.sort(resolved) == Enum.sort(Enum.map(symptoms, & &1.id))

    resolved_doc = Symptoms.Log.latest(root_id)
    assert %{"state" => "resolved", "transition" => "resolved"} = resolved_doc
    assert resolved_doc["resolved_at"] == DateTime.to_iso8601(window_end(14))
    # The contrast stays on later revisions.
    assert resolved_doc["evidence"]["attribute_contrast"]
  end

  test "standalone saturation pages at high confidence without inventing request impact" do
    entity = Sources.PromMetrics.entity(hd(@definitions), @definitions, [])
    ids = Store.resolve_entities([entity], DateTime.shift(@t0, day: -30))
    id = ids[Store.entity_tuple(entity)]

    # 180 quiet residuals below one: a value above all of them has
    # e = 0.5 * sqrt(181), so four windows cross h = 6;
    # a fifth exceeds the prior's 0.9 paging floor (score > 6 + ln 9).
    history =
      for week <- 1..3, minute <- 0..59 do
        %{
          entity_id: id,
          source: "metric.robust_residual",
          phenomenon: "saturation",
          window_seconds: 60,
          window_start: DateTime.shift(%{@t0 | minute: 0}, week: -week, minute: minute),
          statistic: minute / 60,
          p: 0.5,
          e: 1.0,
          open_symptom: false,
          examples: [],
          inserted_at: @t0
        }
      end

    Store.insert_windows(history)
    Pipeline.run_window(60, window_start(0), sources: [Sources.PromMetrics])
    assert :ok = Baselines.refresh(Sources.PromMetrics, window_end(0))
    Process.put(:metric_value, "100000")

    for minute <- 1..5 do
      Pipeline.run_window(60, window_start(minute), sources: [Sources.PromMetrics])
    end

    [symptom] = Repo.all(Symptom)
    assert symptom.state == "open"
    assert symptom.document["tier"] == "page"
    assert symptom.document["impact"] == nil
    assert symptom.document["decision"]["expected_cost"] == nil

    # Real quiet metric reads, not absent observations, permit recovery.
    Process.put(:metric_value, "40")

    for minute <- 6..10 do
      Pipeline.run_window(60, window_start(minute), sources: [Sources.PromMetrics])
    end

    assert Repo.get!(Symptom, symptom.id).state == "resolved"
  end

  ## Driving the pipeline

  defp window_start(minute), do: DateTime.shift(@t0, minute: minute)
  defp window_end(minute), do: window_start(minute + 1)

  defp run(minute, failing: failing) do
    Process.put(:failing, failing)
    Process.put(:latest, DateTime.to_unix(window_end(minute)))
    Pipeline.run_window(60, window_start(minute), sources: @sources)
  end

  defp run_five(index, now: now) do
    start = DateTime.shift(~U[2026-11-16 10:10:00.000000Z], minute: 5 * index)
    Process.put(:latest, DateTime.to_unix(now))
    Pipeline.run_window(300, start, sources: [Sources.PulseErrors], now: now)
  end

  defp metric_records? do
    Repo.exists?(from(w in StreamWindow, where: w.source == "metric.robust_residual" and w.window_start > ^@t0))
  end

  # 180 quiet windows per entity at this hour of week in the 3 previous weeks,
  # residuals rem(37 i, 100) / 50 − 1, spread over [−1, 0.98].
  defp seed_history(entities) do
    hour = %{@t0 | minute: 0}
    ids = Store.resolve_entities(entities, DateTime.shift(@t0, day: -30))

    rows =
      for entity <- entities, week <- 1..3, minute <- 0..59 do
        i = (week - 1) * 60 + minute

        %{
          entity_id: ids[Store.entity_tuple(entity)],
          source: "trace.error_betabinomial",
          phenomenon: "request_errors",
          window_seconds: 60,
          window_start: DateTime.shift(hour, week: -week, minute: minute),
          statistic: rem(37 * i, 100) / 50 - 1,
          p: 0.5,
          e: 1.0,
          open_symptom: false,
          examples: [],
          inserted_at: @t0
        }
      end

    Store.insert_windows(rows)
  end

  ## Fake Pulse

  defp pulse(sql, auth) do
    send(self(), {:pulse_auth, sql, auth})
    sql |> pulse_rows(Process.get(:failing, false)) |> sql_reply()
  end

  # Most specific patterns first: several queries name the same table.
  defp pulse_rows(sql, failing) do
    {_pattern, reply} =
      Enum.find(
        [
          {"AS latest FROM", fn -> [%{"latest" => Process.get(:latest)}] end},
          {"AS minutes", fn -> Enum.map([@route, @client, @cache], &error_baseline/1) end},
          {"latency_bucket", &latency_rows/0},
          {"first_seen", fn -> [version_row()] end},
          {"JOIN opentelemetry_traces AS parent", &span_edges/0},
          {"SELECT DISTINCT service_name, span_name, span_kind", &span_kinds/0},
          {"span_attributes.db.system", &db_clients/0},
          {"AS items", fn -> [%{"service" => @server, "items" => if(sql =~ "trace", do: 2_400, else: 5_000)}] end},
          {"AS k JOIN", fn -> [] end},
          {"symptoms_log_counts_1m", fn -> [] end},
          {"symptoms_log_totals_1m", fn -> [%{"service" => @server, "line_count" => 5_000}] end},
          {"symptoms_trace_counts_1m", fn -> trace_counts(failing) end},
          {"date_bin", fn -> [] end},
          {"FROM errors", fn -> if Process.get(:latest) > DateTime.to_unix(window_end(9)), do: issues(), else: [] end},
          {"AS value", fn -> attribute(sql) end},
          {"AS spans", fn -> [%{"spans" => 6_000, "errors" => 600}] end}
        ],
        fn {pattern, _reply} -> sql =~ pattern end
      )

    reply.()
  end

  defp trace_counts(failing) do
    errors = if failing, do: 120, else: 1

    [
      count_row(@route, 600, errors),
      count_row(@client, 600, errors),
      count_row(@cache, 1_200, 2)
    ]
  end

  defp count_row(entity, spans, errors) do
    %{
      "service_name" => entity.service,
      "span_kind" => "SPAN_KIND_" <> String.upcase(String.replace_prefix(entity.kind, "span_", "")),
      "span_name" => entity.key,
      "service_version" => "1.0.0",
      "span_count" => spans,
      "error_count" => errors
    }
  end

  defp latency_rows do
    for entity <- [@route, @client, @cache], {bucket, count} <- [{10, 90}, {20, 8}, {30, 2}] do
      entity
      |> count_row(count, 0)
      |> Map.put("latency_bucket", bucket)
    end
  end

  # 1000 baseline minutes of n spans: half with x, half with 2x errors.
  defp error_baseline(entity) do
    {n, x} = if entity == @cache, do: {1_200, 2}, else: {600, 1}

    %{
      "service_name" => entity.service,
      "span_kind" => count_row(entity, 0, 0)["span_kind"],
      "span_name" => entity.key,
      "errors" => 1_500 * x,
      "total" => 1_000 * n,
      "pairs" => 1_000 * n * (n - 1),
      "errors_sq" => 500 * x * x + 500 * 4 * x * x,
      "errors_total" => 1_500 * x * n,
      "total_sq" => 1_000 * n * n
    }
  end

  defp version_row do
    %{
      "service_name" => @server,
      "service_version" => "1.0.0",
      "first_seen" => DateTime.to_unix(@t0) - 86_000,
      "last_seen" => Process.get(:latest) - 60
    }
  end

  defp span_edges do
    [
      edge(@route.key, @server, @client.key, 1_000),
      edge(@cache.key, "kura", "GET /cas", 2_000)
    ]
  end

  defp edge(caller, callee_service, callee, count) do
    %{
      "caller_service" => @server,
      "caller_span_name" => caller,
      "callee_service" => callee_service,
      "callee_span_name" => callee,
      "edge_count" => count
    }
  end

  defp span_kinds do
    [
      %{"service_name" => @server, "span_name" => @route.key, "span_kind" => "SPAN_KIND_SERVER"},
      %{"service_name" => @server, "span_name" => @cache.key, "span_kind" => "SPAN_KIND_SERVER"},
      %{"service_name" => @server, "span_name" => @client.key, "span_kind" => "SPAN_KIND_CLIENT"},
      %{"service_name" => "kura", "span_name" => "GET /cas", "span_kind" => "SPAN_KIND_SERVER"}
    ]
  end

  defp db_clients do
    [
      %{
        "service_name" => @server,
        "span_name" => @client.key,
        "address" => "tuist-tuist-pg-pooler-rw",
        "span_count" => 1_000,
        "duration_seconds" => 5.0,
        "queue_seconds" => 0.5
      }
    ]
  end

  defp issues do
    [
      %{
        "service" => @server,
        "fingerprint" => "7f3a9c0e",
        "events" => 40,
        "accounts" => 12,
        "latest_event_id" => "8d1c2f4a",
        "latest_trace_id" => "4bf92f3577b34da6a3ce929d0e0e4736"
      }
    ]
  end

  # Top values per attribute on the affected spans; Pulse has no region column.
  defp attribute(sql) do
    cond do
      sql =~ "k8s.pod.name" ->
        [
          %{"value" => "tuist-server-7d9f8b6c5d-x2x4z", "spans" => 3_000, "errors" => 570},
          %{"value" => "tuist-server-7d9f8b6c5d-q8w7e", "spans" => 3_000, "errors" => 30}
        ]

      sql =~ "host.name" ->
        [
          %{"value" => "node-a", "spans" => 3_000, "errors" => 570},
          %{"value" => "node-b", "spans" => 3_000, "errors" => 30}
        ]

      sql =~ "service.version" ->
        [%{"value" => "1.0.0", "spans" => 6_000, "errors" => 600}]

      sql =~ "cloud.region" ->
        {:error, 400}
    end
  end

  defp sql_reply({:error, _} = error), do: error

  defp sql_reply(rows) do
    names = rows |> Enum.flat_map(&Map.keys/1) |> Enum.uniq() |> Enum.sort()

    %{
      "output" => [
        %{
          "records" => %{
            "schema" => %{"column_schemas" => Enum.map(names, &%{"name" => &1})},
            "rows" => Enum.map(rows, fn row -> Enum.map(names, &Map.get(row, &1)) end)
          }
        }
      ]
    }
  end

  ## Fake Prometheus

  defp prometheus(path, "probe_success" <> _) do
    true = String.ends_with?(path, "/api/v1/query")
    at = Process.get(:latest)
    values = for t <- [at - 120, at - 60], do: [t, "1"]
    matrix([%{"job" => "api-check", "probe" => "Frankfurt", "instance" => "https://tuist.dev/api"}], values)
  end

  defp prometheus(path, _query) do
    if String.ends_with?(path, "/query_range") do
      # Hour-of-week history: the same hour in the 3 previous weeks, 35–45.
      values =
        for week <- 1..3, minute <- 0..55//5 do
          [DateTime.to_unix(DateTime.shift(%{@t0 | minute: minute}, week: -week)), to_string(35 + rem(minute, 11))]
        end

      matrix([%{}], values)
    else
      %{
        "status" => "success",
        "data" => %{
          "resultType" => "vector",
          "result" => [%{"metric" => %{}, "value" => [0, Process.get(:metric_value, "40")]}]
        }
      }
    end
  end

  defp matrix(metrics, values) do
    %{
      "status" => "success",
      "data" => %{"resultType" => "matrix", "result" => Enum.map(metrics, &%{"metric" => &1, "values" => values})}
    }
  end
end
