defmodule PulseWeb.MetricsControllerTest do
  use PulseWeb.ConnCase, async: true

  alias Plug.Parsers.ParseError
  alias Pulse.MCP.Tools
  alias Pulse.ObjectStore
  alias Pulse.PromQL.Evaluator
  alias Pulse.Record.Log
  alias Pulse.Record.MetricSample
  alias Pulse.Runtime.Task
  alias Pulse.SelfMetrics
  alias Pulse.Storage
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.CompactionSupervision
  alias Pulse.Storage.S3.CompactionTasks
  alias Pulse.Storage.S3.CompactionWorker
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.ManifestCache
  alias Pulse.Storage.S3.ManifestRegistry
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Storage.S3.MetricsCompactor
  alias Pulse.Test.CompactionStore
  alias Pulse.Test.SelfMetricsStorage
  alias Pulse.Test.SelfMetricsTasks

  defp value(name, labels \\ "") do
    key = if labels == "", do: name, else: "#{name}{#{labels}}"
    line = Enum.find(String.split(SelfMetrics.render(), "\n"), &String.starts_with?(&1, key <> " "))
    [_, number] = String.split(line, " ")
    {number, ""} = Float.parse(number)
    number
  end

  defp operations(layer, operation, outcome) do
    value("pulse_operations_total", ~s(layer="#{layer}",operation="#{operation}",outcome="#{outcome}"))
  end

  defp records(outcome), do: value("pulse_ingest_records_total", ~s(signal="logs",outcome="#{outcome}"))

  defp configure_storage(adapter), do: Pulse.Runtime.put_env(:pulse, Storage, adapter: adapter)

  defp payload do
    %{
      "resourceLogs" => [
        %{
          "scopeLogs" => [
            %{
              "logRecords" => [
                %{"timeUnixNano" => "1700000000000000000", "body" => %{"stringValue" => "ok"}},
                "not-a-map"
              ]
            }
          ]
        }
      ]
    }
  end

  test "scrape is Prometheus text, uncacheable, and independent of signal storage", %{conn: conn} do
    configure_storage(SelfMetricsStorage)
    conn = conn |> put_req_header("accept", "text/plain") |> get("/metrics")
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["text/plain; version=0.0.4; charset=utf-8"]
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert conn.resp_body =~ "# TYPE pulse_operations_total counter\n"
    assert conn.resp_body =~ "# TYPE pulse_operation_duration_seconds summary\n"
    assert conn.resp_body =~ "pulse_manifest_queue_depth 0\n"
    refute conn.resp_body =~ "tenant="
    refute conn.resp_body =~ "key="
  end

  test "partial-success ingestion counts only published records as accepted", %{conn: conn} do
    accepted = records(:accepted)
    rejected = records(:rejected)
    success = operations(:ingest, :otlp, :success)
    conn = conn |> put_req_header("content-type", "application/json") |> post("/v1/logs", payload())
    assert conn.status == 200
    assert records(:accepted) == accepted + 1
    assert records(:rejected) == rejected + 1
    assert operations(:ingest, :otlp, :success) == success + 1
  end

  test "publication failure is not an accepted record", %{conn: conn} do
    configure_storage(SelfMetricsStorage)
    accepted = records(:accepted)
    failed = records(:failed)
    rejected = records(:rejected)
    errors = operations(:ingest, :otlp, :error)
    conn = conn |> put_req_header("content-type", "application/json") |> post("/v1/logs", payload())
    # OTLP/HTTP clients only retry 429/502/503/504, so storage failures are retryable 503s.
    assert %{"code" => 14} = json_response(conn, 503)
    assert records(:accepted) == accepted
    assert records(:failed) == failed + 1
    assert records(:rejected) == rejected + 1
    assert operations(:ingest, :otlp, :error) == errors + 1
  end

  test "early request rejection does not invent record counts", %{conn: conn} do
    errors = operations(:ingest, :remote_write, :error)
    accepted = records(:accepted)
    conn = conn |> put_req_header("content-type", "application/json") |> post("/api/v1/write", %{})
    assert conn.status == 415
    assert operations(:ingest, :remote_write, :error) == errors + 1
    assert records(:accepted) == accepted
  end

  test "parser rejection is monitored before controller dispatch", %{conn: conn} do
    errors = operations(:ingest, :otlp, :error)

    assert_raise ParseError, fn ->
      conn |> put_req_header("content-type", "application/json") |> post("/v1/logs", "{")
    end

    assert operations(:ingest, :otlp, :error) == errors + 1
  end

  test "query failures are measured at separate storage, evaluator, MCP, and HTTP layers", %{conn: conn} do
    configure_storage(SelfMetricsStorage)
    storage = operations(:query, :storage_logs, :error)
    promql = operations(:query, :promql, :error)
    mcp = operations(:query, :mcp, :error)
    http = operations(:query, :http, :error)
    assert {:error, :unavailable} = Storage.query(:logs, "private-tenant")
    assert {:error, _} = Evaluator.query("unsupported(", "private-tenant")
    assert {:error, _} = Tools.call("query_logs", %{"tenant" => "private-tenant"})
    conn = get(conn, "/api/v1/query?query=unsupported(")
    assert conn.status == 400
    assert operations(:query, :storage_logs, :error) == storage + 2
    assert operations(:query, :promql, :error) == promql + 2
    assert operations(:query, :mcp, :error) == mcp + 1
    assert operations(:query, :http, :error) == http + 1
    refute SelfMetrics.render() =~ "private-tenant"
  end

  test "concurrent observations are exact and unsupported dimensions cannot grow cardinality" do
    count = operations(:object, :get, :success)

    1..200
    |> Task.async_stream(fn _ -> SelfMetrics.track(:object, :get, fn -> {:ok, "body"} end) end, [])
    |> Enum.each(fn result -> assert {:ok, {:ok, "body"}} = result end)

    assert operations(:object, :get, :success) == count + 200
    size = :ets.info(Pulse.Runtime.table(SelfMetrics), :size)
    for n <- 1..100, do: SelfMetrics.operation(:query, "untrusted-#{n}", :error, 1)
    assert :ets.info(Pulse.Runtime.table(SelfMetrics), :size) == size
  end

  test "exceptions, throws and exits retain their original behavior and are counted" do
    count = operations(:object, :put, :exception)
    assert_raise RuntimeError, "original", fn -> SelfMetrics.track(:object, :put, fn -> raise "original" end) end
    assert catch_throw(SelfMetrics.track(:object, :put, fn -> throw(:original) end)) == :original
    assert catch_exit(SelfMetrics.track(:object, :put, fn -> exit(:original) end)) == :original
    assert operations(:object, :put, :exception) == count + 3
  end

  test "queue depth includes pending waiters without calling owners and vanishes on unregister" do
    start_supervised!({Registry, keys: :unique, name: ManifestRegistry})
    registry = Pulse.Runtime.name(ManifestRegistry)
    {:ok, _} = Registry.register(registry, {"private-tenant", "metrics"}, 4)
    {:message_queue_len, messages} = Process.info(self(), :message_queue_len)
    assert value("pulse_manifest_queue_depth") == 4 + messages
    Registry.update_value(registry, {"private-tenant", "metrics"}, fn _ -> 0 end)
    assert value("pulse_manifest_queue_depth") == messages
    Registry.unregister(registry, {"private-tenant", "metrics"})
    assert value("pulse_manifest_queue_depth") == 0
  end

  defp object_store do
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

    {config, agent}
  end

  defp configure_s3(config), do: Pulse.Runtime.put_env(:pulse, S3, config)

  test "real native object operations count successful bytes, errors, and conditional hits" do
    {config, _agent} = object_store()
    write = value("pulse_object_payload_bytes_total", ~s(direction="write"))
    read = value("pulse_object_payload_bytes_total", ~s(direction="read"))
    puts = operations(:object, :put_if_none_match, :error)
    hits = operations(:object, :get_if_none_match, :success)
    {:ok, etag} = ObjectStore.put_if_none_match(config, "example", "abc")
    assert {:error, :already_exists} = ObjectStore.put_if_none_match(config, "example", "ignored")
    assert {:ok, "abc"} = ObjectStore.get(config, "example")
    assert :not_modified = ObjectStore.get_if_none_match(config, "example", etag)
    assert {:ok, ^etag, "abc"} = ObjectStore.get_if_none_match(config, "example", nil)
    assert {:error, :not_found} = ObjectStore.get(config, "missing")
    assert value("pulse_object_payload_bytes_total", ~s(direction="write")) == write + 3
    assert value("pulse_object_payload_bytes_total", ~s(direction="read")) == read + 6
    assert operations(:object, :put_if_none_match, :error) == puts + 1
    assert operations(:object, :get_if_none_match, :success) == hits + 2
  end

  test "compaction and cleanup expose outcomes and successful progress" do
    {config, _agent} = object_store()
    start_supervised!(ManifestSupervision)
    tenant = "self-metrics-compaction"

    {:ok, _} =
      ObjectStore.put(
        config,
        Manifest.manifest_key(tenant, "metrics"),
        IO.iodata_to_binary(Manifest.encode(Manifest.new()))
      )

    configure_s3(config)

    sample = %MetricSample{timestamp_ns: 1_700_000_000_000_000_000, value: 1.0, labels: %{"__name__" => "up"}}
    assert :ok = S3.append(:metrics, tenant, [sample], [])
    assert :ok = S3.append(:metrics, tenant, [%{sample | timestamp_ns: sample.timestamp_ns + 1}], [])
    merged = value("pulse_compaction_segments_total")
    deleted = value("pulse_compaction_deleted_objects_total")
    success = operations(:compaction, :compact, :success)
    assert {:ok, %{merged: 2}} = MetricsCompactor.compact(tenant, config, grace_ms: 0)
    assert {:ok, 2} = MetricsCompactor.cleanup(tenant, config)
    assert {:ok, %{merged: 0}} = MetricsCompactor.compact(tenant, config)
    assert value("pulse_compaction_segments_total") == merged + 2
    assert value("pulse_compaction_deleted_objects_total") == deleted + 2
    assert operations(:compaction, :compact, :success) == success + 2
    assert value("pulse_manifest_queue_depth") == 0
  end

  test "scrape observes publication backlog without waiting for a stalled native call", %{conn: conn} do
    {config, agent} = object_store()
    configure_s3(config)
    start_supervised!(ManifestSupervision)
    supervisor = start_supervised!({Task.Supervisor, name: SelfMetricsTasks})
    key = Manifest.manifest_key("self-metrics-queue", "logs")
    {:ok, _} = ObjectStore.put(config, key, IO.iodata_to_binary(Manifest.encode(Manifest.new())))
    caller = self()
    Agent.update(agent, &%{&1 | barriers: %{{"PUT", key} => caller}})

    record = %Log{timestamp_ns: 1_700_000_000_000_000_000, body: "example"}

    task =
      Task.Supervisor.async_nolink(supervisor, fn -> S3.append(:logs, "self-metrics-queue", [record], []) end)

    assert_receive {:storage_barrier, server, "PUT", ^key}, 30_000
    before_scrape = Agent.get(agent, &length(&1.requests))
    assert value("pulse_manifest_queue_depth") >= 1
    conn = get(conn, "/metrics")
    assert conn.status == 200
    assert Agent.get(agent, &length(&1.requests)) == before_scrape
    send(server, {:release_storage, key})
    assert Task.await(task, 5_000) == :ok
    assert value("pulse_manifest_queue_depth") == 0
  end

  test "background compaction deadline failures are visible even while native work remains in flight" do
    {config, agent} = object_store()
    configure_s3(config)
    start_supervised!(ManifestSupervision)
    tenant = "self-metrics-worker"

    {:ok, _} =
      ObjectStore.put(
        config,
        Manifest.manifest_key(tenant, "metrics"),
        IO.iodata_to_binary(Manifest.encode(Manifest.new()))
      )

    sample = %MetricSample{timestamp_ns: 1_700_000_000_000_000_000, value: 1.0, labels: %{"__name__" => "up"}}
    assert :ok = S3.append(:metrics, tenant, [sample], [])
    assert :ok = S3.append(:metrics, tenant, [%{sample | timestamp_ns: sample.timestamp_ns + 1}], [])
    entry = ManifestCache.get(tenant, "metrics")
    source = hd(entry.manifest.segments).key
    caller = self()
    Agent.update(agent, &%{&1 | barriers: %{{"GET", source} => caller}})
    worker_config = Map.merge(config, %{compaction_interval_ms: 3_600_000, compaction_timeout_ms: 100})
    start_supervised!({CompactionSupervision, worker_config})
    errors = operations(:compaction, :worker_merge, :error)
    send(Pulse.Runtime.whereis(CompactionWorker), :compact)
    assert_receive {:storage_barrier, server, "GET", ^source}, 30_000
    _ = :sys.get_state(Pulse.Runtime.whereis(CompactionWorker))
    assert operations(:compaction, :worker_merge, :error) == errors + 1
    [task] = Task.Supervisor.children(CompactionTasks)
    ref = Process.monitor(task)
    Agent.update(agent, &%{&1 | barriers: %{}})
    send(server, {:release_storage, source})
    assert_receive {:DOWN, ^ref, :process, ^task, :normal}, 5_000
  end

  test "latency sums are exported in seconds" do
    labels = ~s(layer="object",operation="list",outcome="success")
    sum = value("pulse_operation_duration_seconds_sum", labels)
    count = value("pulse_operation_duration_seconds_count", labels)
    SelfMetrics.operation(:object, :list, :success, System.convert_time_unit(1, :second, :native))
    assert_in_delta value("pulse_operation_duration_seconds_sum", labels), sum + 1, 0.000001
    assert value("pulse_operation_duration_seconds_count", labels) == count + 1
  end

  test "Loki partial ingestion is instrumented", %{conn: conn} do
    accepted = records(:accepted)
    rejected = records(:rejected)
    count = operations(:ingest, :loki, :success)

    payload = %{
      "streams" => [
        %{
          "stream" => %{"service_name" => "test"},
          "values" => [["1700000000000000000", "example"], ["invalid", "discard"]]
        }
      ]
    }

    conn = conn |> put_req_header("content-type", "application/json") |> post("/loki/api/v1/push", payload)
    assert conn.status == 204
    assert records(:accepted) == accepted + 1
    assert records(:rejected) == rejected + 1
    assert operations(:ingest, :loki, :success) == count + 1
  end

  test "remote-write samples are instrumented through the native decoder", %{conn: conn} do
    accepted_labels = ~s(signal="metrics",outcome="accepted")
    rejected_labels = ~s(signal="metrics",outcome="rejected")
    accepted = value("pulse_ingest_records_total", accepted_labels)
    rejected = value("pulse_ingest_records_total", rejected_labels)
    count = operations(:ingest, :remote_write, :success)
    label = <<10, 8, "__name__", 18, 2, "up">>
    sample = <<9, 1.0::little-float-64, 16, 1>>
    series = <<10, byte_size(label), label::binary, 18, byte_size(sample), sample::binary>>
    invalid_series = <<18, byte_size(sample), sample::binary>>
    request = <<10, byte_size(series), series::binary, 10, byte_size(invalid_series), invalid_series::binary>>
    {:ok, compressed} = :snappyer.compress(request)

    conn =
      conn
      |> put_req_header("content-type", "application/x-protobuf")
      |> put_req_header("content-encoding", "snappy")
      |> post("/api/v1/write", compressed)

    assert conn.status == 204
    assert value("pulse_ingest_records_total", accepted_labels) == accepted + 1
    assert value("pulse_ingest_records_total", rejected_labels) == rejected + 1
    assert operations(:ingest, :remote_write, :success) == count + 1
  end
end
