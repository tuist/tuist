defmodule Pulse.MetricsTest do
  use PulseWeb.ConnCase, async: true

  alias Plug.Parsers.ParseError
  alias Plug.Parsers.RequestTooLargeError
  alias Pulse.MCP.Tools
  alias Pulse.Metrics
  alias Pulse.ObjectStore
  alias Pulse.Record.Log
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.ManifestRegistry
  alias Pulse.Test.CompactionStore
  alias Pulse.Test.FailingStorage

  defp value(name, labels) do
    case :ets.lookup(Pulse.Runtime.table(Metrics), {name, labels}) do
      [{_, value}] -> value
      [] -> 0
    end
  end

  defp labels(kind, operation, outcome, purpose \\ "none") do
    [{"kind", kind}, {"operation", operation}, {"purpose", purpose}, {"outcome", outcome}]
  end

  defp requests(kind, operation, outcome) do
    value("pulse_operations_total", labels(kind, operation, outcome))
  end

  defp records(signal, outcome) do
    value("pulse_ingest_records_total", [{"signal", signal}, {"outcome", outcome}])
  end

  defp canonical_requests(layer, operation, outcome) do
    labels = ~s(layer="#{layer}",operation="#{operation}",outcome="#{outcome}")
    [{_, count}] = :ets.lookup(Pulse.Runtime.table(Pulse.SelfMetrics), {"pulse_operations_total", labels})
    count
  end

  defp otlp(records) do
    %{"resourceLogs" => [%{"scopeLogs" => [%{"logRecords" => records}]}]}
  end

  test "scrapes use Prometheus text, ignore JSON Accept, and do not observe themselves", %{conn: conn} do
    before = :ets.tab2list(Pulse.Runtime.table(Metrics)) |> Enum.sort()
    conn = conn |> put_req_header("accept", "text/plain") |> get("/metrics")
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["text/plain; version=0.0.4; charset=utf-8"]
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert conn.resp_body =~ "# TYPE pulse_operations_total counter\n"
    assert conn.resp_body =~ "# TYPE pulse_detailed_operations_total counter\n"
    assert conn.resp_body =~ "# TYPE pulse_operation_duration_seconds summary\n"
    assert conn.resp_body =~ "# TYPE pulse_detailed_operation_duration_seconds histogram\n"
    assert conn.resp_body =~ "pulse_manifest_pending_segments 0\n"
    assert conn.resp_body =~ "pulse_query_occupied_slots 0\n"
    assert conn.resp_body =~ "pulse_ingest_buffers 0\n"
    assert conn.resp_body =~ "pulse_ingest_buffer_reserved_calls 0\n"
    assert conn.resp_body =~ "pulse_ingest_buffer_input_bytes 0\n"
    assert conn.resp_body =~ "pulse_ingest_buffer_rows 0\n"
    assert :ets.tab2list(Pulse.Runtime.table(Metrics)) |> Enum.sort() == before
  end

  test "trace tools and capability-scoped alert attempts retain bounded detailed operation labels" do
    for tool <- [
          "get_trace",
          "search_traces",
          "search_trace_metadata",
          "discover_trace_tags",
          "discover_trace_tag_values"
        ] do
      before = requests("query", tool, "error")
      assert {:error, _} = Tools.call(tool, %{})
      assert requests("query", tool, "error") == before + 1
    end

    before = requests("query", "alert_tool", "error")
    assert {:error, _} = Tools.call("list_alert_rules", %{})
    assert requests("query", "alert_tool", "error") == before + 1
  end

  test "each metric family keeps its headers and samples in one group" do
    Metrics.measure(:query, "query_logs", fn -> :ok end)
    Metrics.measure(:object, "get", fn -> {:ok, "body"} end, fn _ -> %{read: 4} end, "segment")
    Metrics.measure(:compaction, "compact", fn -> {:ok, %{merged: 2}} end, fn _ -> %{segments: 2} end)
    assert :ok = Metrics.append(:logs, "metrics-grouping", [%Log{}], 1, [])

    Metrics.render()
    |> String.split("\n", trim: true)
    |> Enum.reduce(nil, fn line, family ->
      case String.split(line, " ", parts: 4) do
        ["#", "HELP", name, _] ->
          name

        ["#", "TYPE", name, _] ->
          assert name == family
          family

        _ ->
          [name | _] = String.split(line, ["{", " "], parts: 2)
          assert name in [family, family <> "_bucket", family <> "_count", family <> "_sum"]
          family
      end
    end)
  end

  test "merged exposition has unique families and sample identities" do
    conn = build_conn() |> get("/metrics")
    lines = String.split(conn.resp_body, "\n", trim: true)
    types = Enum.filter(lines, &String.starts_with?(&1, "# TYPE "))
    assert Enum.uniq(types) == types
    families = Enum.map(types, fn line -> Enum.at(String.split(line, " "), 2) end)
    assert Enum.uniq(families) == families
    samples = lines |> Enum.reject(&String.starts_with?(&1, "#")) |> Enum.map(&hd(String.split(&1, " ")))
    assert Enum.uniq(samples) == samples
  end

  test "router-equivalent paths count requests and pre-router parser errors" do
    for path <- ["/v1/logs/", "/v1//logs", "/v1/%6cogs/"] do
      before = requests("ingest", "otlp", "ok")
      canonical_before = canonical_requests("ingest", "otlp", "success")
      assert (build_conn() |> put_req_header("content-type", "application/json") |> post(path, otlp([]))).status == 200
      assert requests("ingest", "otlp", "ok") == before + 1
      assert canonical_requests("ingest", "otlp", "success") == canonical_before + 1
      rejected = requests("ingest", "otlp", "rejected")
      canonical_rejected = canonical_requests("ingest", "otlp", "error")

      assert_raise ParseError, fn ->
        build_conn() |> put_req_header("content-type", "application/json") |> post(path, "{")
      end

      assert requests("ingest", "otlp", "rejected") == rejected + 1
      assert canonical_requests("ingest", "otlp", "error") == canonical_rejected + 1
    end

    before = requests("query", "http_promql", "rejected")
    assert (build_conn() |> get("/api//v1/query/", %{"query" => "bad("})).status == 400
    assert requests("query", "http_promql", "rejected") == before + 1
  end

  test "encoded separators and nonexistent label routes do not become query or ingest attempts" do
    before = :ets.tab2list(Pulse.Runtime.table(Metrics)) |> Enum.sort()
    canonical_before = canonical_requests("query", "http", "error")
    assert (build_conn() |> get("/loki/api/v1/label/a/b/c/d")).status == 404
    assert (build_conn() |> get("/loki/api/v1/label/a%2Fb/c/values")).status == 404

    assert (build_conn() |> put_req_header("content-type", "application/json") |> post("/v1%2Flogs", otlp([]))).status ==
             404

    assert :ets.tab2list(Pulse.Runtime.table(Metrics)) |> Enum.sort() == before
    assert canonical_requests("query", "http", "error") == canonical_before
    before_labels = requests("query", "http_labels", "ok")
    assert (build_conn() |> get("/loki/api/v1/label/service_name/values/")).status == 200
    assert requests("query", "http_labels", "ok") == before_labels + 1
  end

  test "successful and partially rejected ingest records are counted after append", %{conn: conn} do
    accepted = records("logs", "accepted")
    rejected = records("logs", "rejected")
    requests = requests("ingest", "otlp", "ok")

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(
        "/v1/logs",
        otlp([
          %{"timeUnixNano" => "1700000000000000000", "body" => %{"stringValue" => "hello"}},
          "malformed"
        ])
      )

    assert conn.status == 200
    assert records("logs", "accepted") == accepted + 1
    assert records("logs", "rejected") == rejected + 1
    assert requests("ingest", "otlp", "ok") == requests + 1
  end

  test "pre-decoding rejections count requests, not invented record counts", %{conn: conn} do
    accepted = records("metrics", "accepted")
    rejected = records("metrics", "rejected")
    requests = requests("ingest", "remote_write", "rejected")
    assert (conn |> put_req_header("content-type", "text/plain") |> post("/api/v1/write", "not protobuf")).status == 415
    assert requests("ingest", "remote_write", "rejected") == requests + 1
    assert records("metrics", "accepted") == accepted
    assert records("metrics", "rejected") == rejected
  end

  test "parser failures before the controller are counted exactly once", %{conn: conn} do
    before = requests("ingest", "otlp", "rejected")

    assert_raise ParseError, fn ->
      conn |> put_req_header("content-type", "application/json") |> post("/v1/logs", "{")
    end

    assert requests("ingest", "otlp", "rejected") == before + 1
  end

  test "gzip expansion rejections before decoding are counted", %{conn: conn} do
    Pulse.Runtime.put_env(:pulse, PulseWeb.CompressedBodyReader, max_decompressed_bytes: 16)

    before = requests("ingest", "otlp", "rejected")

    assert_raise RequestTooLargeError, fn ->
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("content-encoding", "gzip")
      |> post("/v1/logs", :zlib.gzip(String.duplicate(" ", 100)))
    end

    assert requests("ingest", "otlp", "rejected") == before + 1
  end

  test "both Loki wire formats and remote write count durably accepted records" do
    alias Pulse.Loki.PushProto

    accepted_logs = records("logs", "accepted")
    accepted_metrics = records("metrics", "accepted")
    loki_requests = requests("ingest", "loki", "ok")
    metric_requests = requests("ingest", "remote_write", "ok")

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post("/loki/api/v1/push", %{
        "streams" => [%{"stream" => %{"service_name" => "api"}, "values" => [["1700000000000000000", "line"]]}]
      })

    assert conn.status == 204

    request = %PushProto.PushRequest{
      streams: [
        %PushProto.Stream{
          labels: "{service_name=\"api\"}",
          entries: [%PushProto.Entry{timestamp: %PushProto.Timestamp{seconds: 1_700_000_000}, line: "line"}]
        }
      ]
    }

    {:ok, loki_body} = request |> PushProto.encode() |> IO.iodata_to_binary() |> :snappyer.compress()

    assert (build_conn()
            |> put_req_header("content-type", "application/x-protobuf")
            |> post("/loki/api/v1/push", loki_body)).status == 204

    # Independent, literal remote-write protobuf: one `up=1` sample at 1ms.
    {:ok, metric_body} =
      :snappyer.compress(<<10, 29, 10, 14, 10, 8, "__name__", 18, 2, "up", 18, 11, 9, 1.0::little-float-64, 16, 1>>)

    assert (build_conn()
            |> put_req_header("content-type", "application/x-protobuf")
            |> put_req_header("content-encoding", "snappy")
            |> post("/api/v1/write", metric_body)).status == 204

    assert records("logs", "accepted") == accepted_logs + 2
    assert records("metrics", "accepted") == accepted_metrics + 1
    assert requests("ingest", "loki", "ok") == loki_requests + 2
    assert requests("ingest", "remote_write", "ok") == metric_requests + 1
  end

  test "whole decoded batches are rejected when storage fails" do
    Pulse.Runtime.put_env(:pulse, Pulse.Storage, adapter: S3)

    accepted = records("logs", "accepted")
    rejected = records("logs", "rejected")
    assert {:error, {:invalid_tenant, _}} = Metrics.append(:logs, "bad/name", [%Log{}], 2, [])
    assert records("logs", "accepted") == accepted
    assert records("logs", "rejected") == rejected + 3
  end

  test "Loki and remote write storage failures count requests and decoded records" do
    use_failing_storage(:error)
    log_count = records("logs", "rejected")
    metric_count = records("metrics", "rejected")
    loki_requests = requests("ingest", "loki", "error")
    metric_requests = requests("ingest", "remote_write", "error")

    assert (build_conn()
            |> put_req_header("content-type", "application/json")
            |> post("/loki/api/v1/push", %{
              "streams" => [%{"stream" => %{"job" => "api"}, "values" => [["1700000000000000000", "line"]]}]
            })).status == 500

    {:ok, body} =
      :snappyer.compress(<<10, 29, 10, 14, 10, 8, "__name__", 18, 2, "up", 18, 11, 9, 1.0::little-float-64, 16, 1>>)

    assert (build_conn()
            |> put_req_header("content-type", "application/x-protobuf")
            |> put_req_header("content-encoding", "snappy")
            |> post("/api/v1/write", body)).status == 503

    assert records("logs", "rejected") == log_count + 1
    assert records("metrics", "rejected") == metric_count + 1
    assert requests("ingest", "loki", "error") == loki_requests + 1
    assert requests("ingest", "remote_write", "error") == metric_requests + 1
  end

  test "controller exceptions are counted once, including their decoded rejected records" do
    use_failing_storage(:raise)
    count = records("logs", "rejected")
    errors = requests("ingest", "otlp", "error") + requests("ingest", "otlp", "exception")

    assert_raise RuntimeError, "storage crashed", fn ->
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post("/v1/logs", otlp([%{"body" => %{"stringValue" => "line"}}]))
    end

    assert records("logs", "rejected") == count + 1
    assert requests("ingest", "otlp", "error") + requests("ingest", "otlp", "exception") == errors + 1
  end

  defp use_failing_storage(mode) do
    Pulse.Runtime.put_env(:pulse, Pulse.Storage, adapter: FailingStorage)
    Pulse.Runtime.put_env(:pulse, FailingStorage, mode)
  end

  test "HTTP failures and MCP tool errors have separate bounded operation labels", %{conn: conn} do
    before_http = requests("query", "http_promql", "rejected")
    assert (conn |> get("/api/v1/query", %{"query" => "unsupported()"})).status == 400
    assert requests("query", "http_promql", "rejected") == before_http + 1
    before_tool = requests("query", "query_logs", "error")
    assert {:error, _} = Tools.call("query_logs", %{})
    assert requests("query", "query_logs", "error") == before_tool + 1
    assert {:error, _} = Tools.call("untrusted-name-secret", %{})
    refute Metrics.render() =~ "untrusted-name-secret"
  end

  test "duration histogram has every cumulative bucket, count and seconds sum" do
    metadata = %{kind: :compaction, operation: "compact", purpose: "none", outcome: "ok"}
    labels = labels("compaction", "compact", "ok")
    small = labels ++ [{"le", "0.005"}]
    large = labels ++ [{"le", "1.0"}]
    infinity = labels ++ [{"le", "+Inf"}]
    before_small = value("pulse_operation_duration_seconds_bucket", small)
    before_large = value("pulse_operation_duration_seconds_bucket", large)
    before_infinity = value("pulse_operation_duration_seconds_bucket", infinity)
    before_sum = value("pulse_operation_duration_seconds_sum", labels)
    duration = System.convert_time_unit(750_000, :microsecond, :native)
    :telemetry.execute([:pulse, :operation, :stop], %{duration: duration, segments: 3}, metadata)
    assert value("pulse_operation_duration_seconds_bucket", small) == before_small
    assert value("pulse_operation_duration_seconds_bucket", large) == before_large + 1
    assert value("pulse_operation_duration_seconds_bucket", infinity) == before_infinity + 1
    assert value("pulse_operation_duration_seconds_sum", labels) == before_sum + 750_000

    bounds =
      Metrics.render()
      |> String.split("\n")
      |> Enum.filter(
        &String.starts_with?(
          &1,
          ~s(pulse_detailed_operation_duration_seconds_bucket{kind="compaction",operation="compact",purpose="none",outcome="ok",)
        )
      )
      |> Enum.map(fn line ->
        [_, bound] = Regex.run(~r/le="([^"]+)"/, line)
        bound
      end)

    assert bounds == ["0.005", "0.01", "0.05", "0.1", "0.5", "1.0", "5.0", "10.0", "+Inf"]

    assert Metrics.render() =~
             ~s(pulse_detailed_operation_duration_seconds_bucket{kind="compaction",operation="compact",purpose="none",outcome="ok",le="0.005"})
  end

  test "ingest stages are timed by signal, with ordered buckets and a fixed vocabulary" do
    decode = [{"signal", "logs"}, {"stage", "decode"}]
    before = value("pulse_ingest_stage_duration_seconds_count", decode)

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post("/loki/api/v1/push", %{
        "streams" => [%{"stream" => %{"service_name" => "api"}, "values" => [["1700000000000000000", "line"]]}]
      })

    assert conn.status == 204
    assert value("pulse_ingest_stage_duration_seconds_count", decode) == before + 1

    size = :ets.info(Pulse.Runtime.table(Metrics), :size)
    started = System.monotonic_time()
    Metrics.stage(:logs, :user_stage, started)
    Metrics.stage(:profiles, :decode, started)
    assert :ets.info(Pulse.Runtime.table(Metrics), :size) == size

    rendered = Metrics.render()

    bounds =
      ~r/^pulse_ingest_stage_duration_seconds_bucket\{signal="logs",stage="decode",le="([^"]+)"\}/m
      |> Regex.scan(rendered, capture: :all_but_first)
      |> List.flatten()

    assert bounds == ~w(0.001 0.005 0.01 0.025 0.05 0.1 0.25 0.5 1.0 2.5 5.0 +Inf)
    assert rendered =~ ~r/^pulse_ingest_stage_duration_seconds_sum\{signal="logs",stage="decode"\} \d/m
    assert rendered =~ ~r/^pulse_manifest_bytes\{signal="logs"\} \d+$/m
    assert rendered =~ ~r/^pulse_manifest_segments\{signal="traces"\} \d+$/m
  end

  test "measurement preserves successes, errors, throws and exceptions" do
    assert {:ok, :body} = Metrics.measure(:object, "get", fn -> {:ok, :body} end)
    assert {:error, :not_found} = Metrics.measure(:object, "get", fn -> {:error, :not_found} end)
    assert catch_throw(Metrics.measure(:object, "get", fn -> throw(:original) end)) == :original

    assert_raise ArgumentError, "original", fn ->
      Metrics.measure(:object, "get", fn -> raise ArgumentError, "original" end)
    end

    assert_raise ArgumentError, fn -> ObjectStore.get(%{}, "tenants/secret/v4/signal=logs/file.parquet") end
    refute Metrics.render() =~ "tenants/secret"
  end

  test "untrusted labels cannot create new time series" do
    size = :ets.info(Pulse.Runtime.table(Metrics), :size)

    for n <- 1..100 do
      :telemetry.execute([:pulse, :operation, :stop], %{duration: 1}, %{
        kind: :query,
        operation: "user-#{n}",
        purpose: "none",
        outcome: "ok"
      })
    end

    assert :ets.info(Pulse.Runtime.table(Metrics), :size) == size
  end

  test "concurrent increments do not lose updates or enqueue reporting messages" do
    labels = labels("object", "list_prefixes", "ok", "other")
    before = value("pulse_operations_total", labels)

    runtime = Pulse.Runtime.current()

    1..100
    |> Task.async_stream(
      fn _ ->
        Pulse.Runtime.with(runtime, fn ->
          Metrics.measure(:object, "list_prefixes", fn -> {:ok, []} end, fn _ -> %{} end, "other")
        end)
      end,
      max_concurrency: 8
    )
    |> Stream.run()

    assert value("pulse_operations_total", labels) == before + 100
    assert {:message_queue_len, 0} = Process.info(Pulse.Runtime.whereis(Metrics), :message_queue_len)
  end

  test "queue gauges use registry metadata and survive owner exit" do
    start_supervised!({Registry, keys: :unique, name: ManifestRegistry})
    registry = Pulse.Runtime.name(ManifestRegistry)
    parent = self()

    pid =
      start_supervised!(
        {Task,
         fn ->
           {:ok, _} = Registry.register(registry, {"secret-tenant", "logs"}, %{pending: 4, waiters: 2})
           send(self(), :queued)
           send(self(), :queued)
           send(self(), :queued)
           send(parent, :registered)

           receive do
             :finish -> Registry.unregister(registry, {"secret-tenant", "logs"})
           end
         end}
      )

    ref = Process.monitor(pid)
    assert_receive :registered
    rendered = Metrics.render()
    assert rendered =~ "pulse_manifest_pending_segments 4\n"
    assert rendered =~ "pulse_manifest_waiting_requests 2\n"
    refute rendered =~ "secret-tenant"
    send(pid, :finish)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    assert Registry.lookup(registry, {"secret-tenant", "logs"}) == []
    assert Metrics.render() =~ "pulse_manifest_pending_segments 0\n"
  end

  test "memory breakdown partitions BEAM memory and attributes labelled process heaps" do
    parent = self()

    pid =
      start_supervised!(
        {Task,
         fn ->
           Process.set_label({:pulse, :query})
           heap = Enum.to_list(1..1_000_000)
           send(parent, :built)

           receive do
             :finish -> length(heap)
           end
         end}
      )

    assert_receive :built, 5_000
    kinds = Map.new(Pulse.MemoryStats.kinds())
    beam = ~w(processes binary ets code atom system_other) |> Enum.map(&Map.fetch!(kinds, &1)) |> Enum.sum()
    assert beam == kinds["total"]
    assert kinds["beam_allocated"] >= kinds["beam_allocator_free"]
    assert is_integer(kinds["native_codec"]) and is_integer(kinds["native_object_store"])
    # A million-element list takes 16 MiB of heap on a 64-bit VM.
    assert Map.new(Pulse.MemoryStats.processes())["query"] >= 16_000_000

    rendered = Metrics.render()
    assert rendered =~ ~s(pulse_memory_bytes{kind="beam_allocated"} )
    assert rendered =~ ~s(pulse_memory_process_bytes{group="manifest_owner"} )
    assert rendered =~ ~r/pulse_memory_ets_bytes\{table="[^"]*Pulse\.Metrics"\} \d+/
    send(pid, :finish)
  end

  test "object counters distinguish successful bodies, conflicts, conditional reads, and missing objects" do
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

    key = "tenants/private/v4/signal=logs/manifest.json"
    write_labels = [{"operation", "put_if_none_match"}, {"purpose", "manifest"}, {"direction", "write"}]
    read_labels = [{"operation", "get_if_none_match"}, {"purpose", "manifest"}, {"direction", "read"}]
    writes = value("pulse_object_bytes_total", write_labels)
    reads = value("pulse_object_bytes_total", read_labels)
    conflicts = value("pulse_operations_total", labels("object", "put_if_none_match", "conflict", "manifest"))
    unchanged = value("pulse_operations_total", labels("object", "get_if_none_match", "not_modified", "manifest"))
    missing = value("pulse_operations_total", labels("object", "get_if_none_match", "not_found", "manifest"))
    class = fn class, purpose -> value("pulse_object_requests_total", [{"class", class}, {"purpose", purpose}]) end
    billed = for c <- ["A", "B", "free"], p <- ["manifest", "other"], into: %{}, do: {{c, p}, class.(c, p)}

    assert {:ok, etag} = ObjectStore.put_if_none_match(config, key, "body")
    assert {:error, :already_exists} = ObjectStore.put_if_none_match(config, key, "body")
    assert :not_modified = ObjectStore.get_if_none_match(config, key, etag)
    assert {:ok, _, "body"} = ObjectStore.get_if_none_match(config, key, nil)
    assert {:error, :not_found} = ObjectStore.get_if_none_match(config, "tenants/private/missing/manifest.json", nil)
    assert value("pulse_object_bytes_total", write_labels) == writes + 4
    assert value("pulse_object_bytes_total", read_labels) == reads + 4

    assert value("pulse_operations_total", labels("object", "put_if_none_match", "conflict", "manifest")) ==
             conflicts + 1

    assert value("pulse_operations_total", labels("object", "get_if_none_match", "not_modified", "manifest")) ==
             unchanged + 1

    assert value("pulse_operations_total", labels("object", "get_if_none_match", "not_found", "manifest")) ==
             missing + 1

    assert {:ok, _} = ObjectStore.list(config, "tenants/private/")
    assert {:ok, _} = ObjectStore.list_prefixes(config, "tenants/")
    assert {:ok, "body"} = ObjectStore.get(config, key)
    assert :ok = ObjectStore.delete(config, key)

    # Billing classes: the created PUT and both listings are Class A; the full
    # read, the 404 and the plain GET are Class B; the 412 conflict, the 304
    # and the DELETE are free.
    assert class.("A", "manifest") == billed[{"A", "manifest"}] + 1
    assert class.("A", "other") == billed[{"A", "other"}] + 2
    assert class.("B", "manifest") == billed[{"B", "manifest"}] + 3
    assert class.("free", "manifest") == billed[{"free", "manifest"}] + 3
    assert Metrics.render() =~ ~s(pulse_object_requests_total{class="free",purpose="manifest"})

    byte_labels =
      :ets.tab2list(Pulse.Runtime.table(Metrics))
      |> Enum.flat_map(fn
        {{"pulse_object_bytes_total", labels}, _} -> [Map.new(labels)]
        _ -> []
      end)

    refute Enum.any?(byte_labels, &(&1["operation"] in ["list", "list_prefixes", "delete"]))
    refute Enum.any?(byte_labels, &(&1["operation"] in ["get", "get_if_none_match"] and &1["direction"] == "write"))

    refute Enum.any?(
             byte_labels,
             &(&1["operation"] in ["put", "put_if_match", "put_if_none_match"] and &1["direction"] == "read")
           )

    refute Metrics.render() =~ "tenants/private"
  end

  test "metrics restart resets counters without duplicating handlers, and unavailable reporting does not fail work" do
    # Restart only this test's own Metrics instance, never the application's.
    :ok = stop_supervised!(Metrics)
    assert Pulse.Runtime.whereis(Metrics) == nil

    assert :ok = Metrics.measure(:query, "query_logs", fn -> :ok end)
    start_supervised!(Metrics)
    assert requests("query", "query_logs", "ok") == 0
    assert :ok = Metrics.measure(:query, "query_logs", fn -> :ok end)
    assert requests("query", "query_logs", "ok") == 1
  end

  test "monitoring remains independent of unavailable storage" do
    Pulse.Runtime.put_env(:pulse, Pulse.Storage, adapter: S3)

    assert (build_conn() |> get("/metrics")).status == 200
  end
end
