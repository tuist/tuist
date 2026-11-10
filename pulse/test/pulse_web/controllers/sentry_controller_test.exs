defmodule PulseWeb.SentryControllerTest do
  use PulseWeb.ConnCase, async: true

  alias Pulse.Auth.SharedSecret
  alias Pulse.MCP.Tools
  alias Pulse.PromQL.QuerySlots
  alias Pulse.PromQL.TaskSupervisor
  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.ManifestCache
  alias Pulse.Storage.S3.ManifestOwner
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Storage.S3.Retention
  alias Pulse.Test.CompactionStore
  alias Pulse.Test.FailingStorage
  alias Pulse.Test.MCPMessages

  @id "0123456789abcdef0123456789abcdef"
  @other_id "abcdef0123456789abcdef0123456789"
  @key "test-public-key"

  setup context do
    project = %{
      "tenant" => "acme",
      "service" => "api",
      "public_key_hashes" => [Base.encode16(:crypto.hash(:sha256, @key), case: :lower)]
    }

    Runtime.put_env(:pulse, Pulse.Sentry, projects: %{"42" => project, "43" => project})
    if context[:s3], do: s3_setup(), else: :ok
  end

  defp event(overrides \\ %{}) do
    Map.merge(
      %{
        "event_id" => @id,
        "timestamp" => "2026-01-01T00:00:00Z",
        "environment" => "production",
        "release" => "app@1.0",
        "exception" => %{
          "values" => [
            %{
              "type" => "RuntimeError",
              "value" => "customer 123 failed",
              "stacktrace" => %{"frames" => [%{"filename" => "app.py", "function" => "run", "in_app" => true}]}
            }
          ]
        },
        "contexts" => %{"trace" => %{"trace_id" => String.duplicate("a", 32), "span_id" => String.duplicate("b", 16)}}
      },
      overrides
    )
  end

  defp envelope(event, headers \\ %{}) do
    payload = Pulse.JSON.encode!(event)

    Pulse.JSON.encode!(headers) <>
      "\n" <> Pulse.JSON.encode!(%{type: "event", length: byte_size(payload)}) <> "\n" <> payload <> "\n"
  end

  defp send_envelope(body, path \\ "/api/42/envelope/") do
    build_conn()
    |> put_req_header("content-type", "application/x-sentry-envelope")
    |> put_req_header("x-sentry-auth", "Sentry sentry_version=7, sentry_key=#{@key}, sentry_client=test/1")
    |> post(path, body)
  end

  defp query(name, extra \\ %{}) do
    args = Map.merge(%{"tenant" => "acme", "start_ts_ns" => 0, "end_ts_ns" => 1_800_000_000_000_000_000}, extra)
    message = MCPMessages.request(1, "tools/call", %{"name" => name, "arguments" => args})

    response =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json, text/event-stream")
      |> put_req_header("authorization", "Bearer read-token")
      |> put_req_header("mcp-protocol-version", MCPMessages.version())
      |> put_req_header("mcp-method", "tools/call")
      |> put_req_header("mcp-name", name)
      |> post("/mcp", Pulse.JSON.encode!(message))
      |> json_response(200)

    assert %{"result" => %{"content" => [%{"text" => text}]}} = response
    refute response["result"]["isError"]
    Pulse.JSON.decode!(text)
  end

  defp s3_setup do
    # Exercise the actual native codec and object-store client against an owned
    # conditional-write HTTP store, without requiring shared cloud credentials.
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

    server =
      start_supervised!(
        {Bandit,
         plug: {CompactionStore, agent: agent},
         ip: {127, 0, 0, 1},
         port: 0,
         thousand_island_options: [shutdown_timeout: 100]}
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(server)

    config = %{
      bucket: "pulse",
      endpoint: "http://127.0.0.1:#{port}",
      region: "us-east-1",
      access_key_id: "sentry-#{System.unique_integer([:positive])}",
      secret_access_key: "test",
      allow_http: true
    }

    Runtime.put_env(:pulse, Storage, adapter: S3)
    Runtime.put_env(:pulse, S3, config)
    start_supervised!(ManifestSupervision)
    %{agent: agent, config: config}
  end

  @tag :s3
  test "SDK event survives real Parquet/S3 publication and cold manifest reload", %{agent: agent, config: config} do
    Runtime.put_env(:pulse, Pulse.Auth,
      module: SharedSecret,
      tokens: %{"acme" => "sha256$" <> Base.encode16(:crypto.hash(:sha256, "read-token"), case: :lower)}
    )

    payload =
      event(%{
        "user" => %{"email" => "private@example.com"},
        "request" => %{"url" => "https://example.com/?private=value"},
        "extra" => %{
          "token" => "secret-value",
          "headers" => [["x-private", "secret-header"]],
          "credentials" => [["password", "secret-password"]]
        }
      })

    assert %{"id" => @id} = payload |> envelope() |> send_envelope() |> json_response(200)
    {:ok, owner} = ManifestOwner.ensure_started("acme", "logs", config)
    :ok = GenServer.stop(owner)
    ManifestCache.drop("acme", "logs")

    assert %{"matched_events" => 1, "results" => [result]} = query("query_errors", %{"project" => "42"})
    assert result["event_id"] == @id
    assert result["event"]["exception"] == payload["exception"]
    assert result["event"]["user"] == "[Filtered]"
    assert result["event"]["request"] == "[Filtered]"
    assert result["event"]["extra"]["token"] == "[Filtered]"
    assert result["event"]["extra"]["headers"] == "[Filtered]"
    assert result["event"]["extra"]["credentials"] == [["password", "[Filtered]"]]
    assert result["trace_id"] == String.duplicate("a", 32)
    assert result["service"] == "api"
    assert %{"results" => [%{"count" => 1}]} = query("list_error_issues")
    assert %{"results" => []} = query("query_errors", %{"environment" => "staging"})
    assert %{"results" => []} = query("query_errors", %{"issue_id" => "not-this-issue"})
    assert %{"results" => []} = query("query_errors", %{"release" => "app@2.0"})
    assert {:ok, []} = Storage.query(:logs, "another")
    objects = Agent.get(agent, &Map.keys(&1.objects))
    assert Enum.any?(objects, &String.ends_with?(&1, ".parquet"))
    assert Enum.any?(objects, &String.ends_with?(&1, "/manifest.json"))
  end

  @tag :s3
  test "independent stateless ingest instances publish concurrently and a cold instance reads every acknowledgment" do
    original = Runtime.current()
    first = %{original | instance: __MODULE__.FirstInstance}
    second = %{original | instance: __MODULE__.SecondInstance}

    for {runtime, id} <- [{first, :first_manifest}, {second, :second_manifest}] do
      Runtime.with(runtime, fn ->
        start_supervised!(ManifestSupervision, id: id)
        start_supervised!(Pulse.Metrics, id: {id, :metrics})
        start_supervised!(Pulse.SelfMetrics, id: {id, :self_metrics})
        start_supervised!({Task.Supervisor, name: TaskSupervisor}, id: {id, :queries})
        start_supervised!({Registry, keys: :unique, name: QuerySlots}, id: {id, :slots})
      end)
    end

    supervisor = start_supervised!({Task.Supervisor, []}, id: :ingest_clients)

    uploads =
      for n <- 1..20 do
        Task.Supervisor.async_nolink(
          supervisor,
          Runtime.capture(fn ->
            runtime = if rem(n, 2) == 0, do: first, else: second
            id = n |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(32, "0")

            Runtime.with(runtime, fn ->
              assert %{"id" => ^id} = event(%{"event_id" => id}) |> envelope() |> send_envelope() |> json_response(200)
            end)
          end)
        )
      end

    Enum.each(uploads, &Task.await(&1, 15_000))
    first_page = Runtime.with(first, fn -> query("query_errors", %{"limit" => 7}) end)
    assert length(first_page["results"]) == 7
    assert is_binary(first_page["next_cursor"])
    # Stop both ingest owners/caches; the original read instance has no local
    # manifest state and cannot recover accepted data from either mailbox.
    stop_supervised!(:first_manifest)
    stop_supervised!(:second_manifest)
    assert ManifestCache.get("acme", "logs") == nil

    assert %{"results" => remaining, "next_cursor" => nil} =
             query("query_errors", %{"cursor" => first_page["next_cursor"]})

    assert length(remaining) == 13
    assert %{"matched_events" => 20, "results" => [%{"count" => 20}]} = query("list_error_issues")
    assert %{"results" => events} = query("query_errors")
    assert length(Enum.uniq_by(events, & &1["event_id"])) == 20
    assert first_page["results"] ++ remaining == events
  end

  @tag :s3
  test "S3 enforces the occurrence ceiling across segments before deduplication or result limiting" do
    records =
      for id <- 1..5000 do
        assert {:ok, record} =
                 Pulse.Errors.record(
                   event(%{"event_id" => String.pad_leading(Integer.to_string(id, 16), 32, "0")}),
                   %{},
                   "42",
                   %{"service" => "api"}
                 )

        record
      end

    assert :ok = Storage.append(:logs, "acme", Enum.take(records, 4999))
    assert :ok = Storage.append(:logs, "acme", Enum.drop(records, 4999))
    assert %{"matched_events" => 5000, "results" => [%{"count" => 5000}]} = query("list_error_issues", %{"limit" => 1})
    assert :ok = Storage.append(:logs, "acme", [hd(records)])

    for name <- ["query_errors", "list_error_issues"] do
      assert {:error, :query_sample_limit} =
               Tools.call(name, %{
                 "tenant" => "acme",
                 "start_ts_ns" => 0,
                 "end_ts_ns" => 1_800_000_000_000_000_000,
                 "limit" => 1
               })
    end
  end

  @tag :s3
  test "same-service unrelated logs and projects prune before candidate scan budgets", %{agent: agent, config: config} do
    assert {:ok, record} = Pulse.Errors.record(event(), %{}, "42", %{"service" => "api"})
    ordinary = %{record | resource: %{}, body: "ordinary log"}
    other_project = %{record | resource: Map.put(record.resource, "error_project", "43")}
    assert :ok = Storage.append(:logs, "acme", List.duplicate(ordinary, 100))
    assert :ok = Storage.append(:logs, "acme", List.duplicate(other_project, 100))
    assert :ok = Storage.append(:logs, "acme", [record])
    Runtime.put_env(:pulse, Pulse.QueryRunner, max_scan_rows: 1, max_scan_segments: 1)

    assert %{"matched_events" => 1} = query("query_errors", %{"project" => "42", "service" => "api"})
    opts = [service: "api", matchers: [{"error_source", :eq, "sentry"}, {"error_project", :eq, "42"}]]
    assert {:ok, %{segments: [segment], floor_ns: 0, etag: etag}} = S3.log_snapshot("acme", opts)
    assert is_binary(etag)
    assert segment.row_count == 1
    assert {:error, :query_scan_limit} = S3.log_snapshot("acme", Keyword.put(opts, :max_scan_rows, 0))

    # Old segments have no error summary and must still be scanned, not hidden.
    assert {:ok, root, _} = Retention.load("acme", "logs", config)
    root = %{root | segments: Enum.map(root.segments, &%{&1 | log_labels: nil})}

    assert {:ok, _} =
             Pulse.ObjectStore.put(
               config,
               Manifest.manifest_key("acme", "logs"),
               IO.iodata_to_binary(Manifest.encode(root))
             )

    args = %{"tenant" => "acme", "project" => "42", "start_ts_ns" => 0, "end_ts_ns" => 1_800_000_000_000_000_000}
    assert {:error, :query_scan_limit} = Tools.call("query_errors", args)
    assert Agent.get(agent, & &1.lists) == 1
  end

  @tag :s3
  test "S3 expanded-byte allowance is cumulative across small compressed objects", %{config: config, agent: agent} do
    for {id, timestamp} <- [{@id, 10}, {@other_id, 20}] do
      assert {:ok, record} =
               Pulse.Errors.record(
                 event(%{"event_id" => id, "timestamp" => timestamp, "message" => String.duplicate("x", 700_000)}),
                 %{},
                 "42",
                 %{"service" => "api"}
               )

      assert :ok = Storage.append(:logs, "acme", [record])
    end

    assert {:ok, %{segments: segments}} = S3.log_snapshot("acme", [])
    assert length(segments) == 2
    assert Enum.sum(Enum.map(segments, & &1.byte_size)) < 20_000

    for segment <- segments do
      assert {:ok, payload} = Pulse.ObjectStore.get(config, segment.key)
      assert {:ok, [_], charged} = S3.decode_log_segment_bounded(payload, nil, nil, max_decoded_bytes: 1_048_576)
      assert charged >= 700_000
      assert charged < 800_000
    end

    assert {:ok, [_, _]} = Storage.query(:logs, "acme", max_decoded_bytes: 2_097_152)
    assert {:error, :query_decoded_limit} = Storage.query(:logs, "acme", max_decoded_bytes: 1_048_576)

    # Cleanup removes the older object while a query is in flight. A fresh
    # retry must not reset the allowance already spent decoding the newer one.
    older = Enum.min_by(segments, & &1.min_ts)
    assert :ok = Pulse.ObjectStore.delete(config, older.key)
    owner = self()
    Agent.update(agent, &%{&1 | barriers: %{{"GET", older.key} => owner}})

    task =
      Pulse.Runtime.Task.Supervisor.async_nolink(TaskSupervisor, fn ->
        Storage.query(:logs, "acme", fresh: true, max_decoded_bytes: 1_048_576)
      end)

    key = older.key
    assert_receive {:storage_barrier, request, "GET", ^key}, 5000
    assert {:ok, root, _} = Retention.load("acme", "logs", config)
    root = %{root | segments: Enum.reject(root.segments, &(&1.key == key))}

    assert {:ok, _} =
             Pulse.ObjectStore.put(
               config,
               Manifest.manifest_key("acme", "logs"),
               IO.iodata_to_binary(Manifest.encode(root))
             )

    send(request, {:release_storage, key})
    assert {:error, :query_decoded_limit} = Task.await(task)
    assert {:ok, [_]} = Storage.query(:logs, "acme", fresh: true, max_decoded_bytes: 1_048_576)
  end

  @tag :s3
  test "small response pages cannot bypass the whole-window expanded-byte ceiling" do
    records =
      for id <- 1..40 do
        assert {:ok, record} =
                 Pulse.Errors.record(
                   event(%{
                     "event_id" => String.pad_leading(Integer.to_string(id, 16), 32, "0"),
                     "message" => String.duplicate("x", 900_000)
                   }),
                   %{},
                   "42",
                   %{"service" => "api"}
                 )

        record
      end

    for batch <- Enum.chunk_every(records, 10), do: assert(:ok = Storage.append(:logs, "acme", batch))
    assert {:ok, %{segments: segments}} = S3.log_snapshot("acme", [])
    assert Enum.sum(Enum.map(segments, & &1.byte_size)) < 100_000

    for name <- ["query_errors", "list_error_issues"] do
      assert {:error, :query_decoded_limit} =
               Tools.call(name, %{
                 "tenant" => "acme",
                 "start_ts_ns" => 0,
                 "end_ts_ns" => 1_800_000_000_000_000_000,
                 "limit" => 1
               })
    end
  end

  @tag :s3
  test "fresh diagnostic reads and source snapshots never use stale roots or reconstruct missing manifests", %{
    agent: agent,
    config: config
  } do
    assert %{"id" => @id} = event() |> envelope() |> send_envelope() |> json_response(200)
    assert %{"matched_events" => 1} = query("query_errors")
    key = Manifest.manifest_key("acme", "logs")
    lists = Agent.get(agent, & &1.lists)
    Agent.update(agent, &%{&1 | faults: %{{"GET", key} => {403, :before, 100}}})
    args = %{"tenant" => "acme", "start_ts_ns" => 0, "end_ts_ns" => 1_800_000_000_000_000_000}
    assert {:error, _} = Tools.call("query_errors", args)
    assert {:error, _} = S3.log_snapshot("acme", [])
    Agent.update(agent, &%{&1 | faults: %{}})
    assert :ok = Pulse.ObjectStore.delete(config, key)
    assert {:error, :not_found} = Tools.call("query_errors", args)
    assert {:error, :not_found} = S3.log_snapshot("acme", [])
    assert Agent.get(agent, & &1.lists) == lists
  end

  @tag :s3
  test "paged source snapshots expose the fresh retained floor and invalidate pages when retained results change", %{
    config: config
  } do
    now = System.system_time(:nanosecond)

    for {id, timestamp} <- [{@id, now - 10_000_000_000}, {@other_id, now - 5_000_000_000}] do
      assert {:ok, record} = Pulse.Errors.record(event(%{"event_id" => id}), %{}, "42", %{"service" => "api"})
      assert :ok = Storage.append(:logs, "acme", [%{record | timestamp_ns: timestamp}])
    end

    args = %{"tenant" => "acme", "start_ts_ns" => 0, "end_ts_ns" => now, "limit" => 1}
    assert {:ok, [%{"text" => json}]} = Tools.call("query_errors", args)
    cursor = Pulse.JSON.decode!(json)["next_cursor"]

    config =
      Map.merge(config, %{
        logs_retention_days: 1,
        retention_enabled: true,
        retention_mode: "enforce",
        retention_manifest_format: "bucketed",
        retention_tail_entries: 1
      })

    Runtime.put_env(:pulse, S3, config)
    assert {:ok, _} = Retention.advance("acme", "logs", config, now_ns: now)
    assert {:ok, root, _} = Retention.load("acme", "logs", config)
    assert root.version == 3
    floor = now - 86_400_000_000_000

    assert {:ok, %{segments: [_, _], floor_ns: ^floor}} =
             S3.log_snapshot("acme", matchers: [{"error_project", :eq, "42"}])

    assert {:ok, _} = Tools.call("query_errors", Map.put(args, "cursor", cursor))

    future = now + 86_400_000_000_000 - 7_000_000_000
    floor = now - 7_000_000_000
    assert {:ok, _} = Retention.advance("acme", "logs", config, now_ns: future)
    assert {:ok, %{segments: [_], floor_ns: ^floor}} = S3.log_snapshot("acme", [])
    assert {:error, :error_query_reset_required} = Tools.call("query_errors", Map.put(args, "cursor", cursor))
    assert {:ok, [%{"text" => json}]} = Tools.call("query_errors", args)
    assert %{"matched_events" => 1, "results" => [%{"event_id" => @other_id}]} = Pulse.JSON.decode!(json)
  end

  test "raw byte framing accepts multiline UTF-8 JSON and skips binary attachments" do
    payload = ~s({\n"event_id":"#{@id}",\n"message":"échec"\n})

    body =
      ~s({}\n{"type":"attachment","length":4}\n) <>
        <<255, 10, 0, 13>> <>
        ~s(\n{"type":"event","length":#{byte_size(payload)}}\n) <> payload

    response = send_envelope(body)
    assert %{"id" => @id, "discarded_items" => %{"attachment" => 1}} = json_response(response, 200)
    assert get_resp_header(response, "x-pulse-discarded-items") == ["1"]
    assert %{"results" => [%{"event" => %{"message" => "échec"}}]} = query("query_errors")
  end

  test "browser and SDK authentication forms agree and cannot override tenant attribution" do
    headers = %{"dsn" => "https://#{@key}@errors.example.com/42", "event_id" => @other_id}
    body = envelope(event(), headers)

    for type <- ["text/plain", "application/x-www-form-urlencoded", "multipart/form-data", "application/json"] do
      response =
        build_conn()
        |> put_req_header("content-type", type)
        |> put_req_header("x-scope-orgid", "victim")
        |> post("/api/42/envelope/?sentry_key=#{@key}", body)

      assert %{"id" => @other_id} = json_response(response, 200)
      assert get_resp_header(response, "access-control-allow-origin") == ["*"]
    end

    assert {:ok, []} = Storage.query(:logs, "victim")
    assert %{"results" => [%{"event_id" => @other_id}]} = query("query_errors")
    assert :post |> Plug.Test.conn("/api/42/envelope/", body) |> PulseWeb.Endpoint.call([]) |> json_response(200)

    assert :post
           |> Plug.Test.conn("/api/42/envelope/?sentry_key=wrong", body)
           |> PulseWeb.Endpoint.call([])
           |> json_response(403)

    assert body |> send_envelope("/api/43/envelope/") |> json_response(403)
    assert envelope(event()) |> send_envelope("/api/999/envelope/") |> json_response(403)

    assert :post
           |> Plug.Test.conn("/api/42/envelope/", envelope(event()))
           |> PulseWeb.Endpoint.call([])
           |> json_response(403)

    response = build_conn() |> put_req_header("origin", "https://app.example.com") |> options("/api/42/envelope/")
    assert response.status == 204
    assert get_resp_header(response, "access-control-allow-origin") == ["*"]
  end

  @tag :sentry_preflight
  test "browser preflight advertises POST only and permits supported gzip request headers" do
    # getsentry/relay a68f1dbec05258cfa27b01059e1c1816d10c7257,
    # tests/integration/test_store.py::test_options_response (lines 67–83).
    # The two store rows preserve the original requested method/header inputs.
    # Gzip and envelope rows extend the same shared CORS contract locally.
    for {path, method, requested} <- [
          {"/api/42/store/", "GET", "X-Sentry-Auth"},
          {"/api/42/store/", "POST", "X-Sentry-Auth"},
          {"/api/42/store/", "POST", "Content-Type, Content-Encoding, X-Sentry-Auth"},
          {"/api/42/envelope/", "POST", "Content-Type, Content-Encoding, X-Sentry-Auth"},
          {"/api/store/", "POST", "Authorization"},
          {"/api/42/envelope/", "POST", "Content-Type, Authorization"}
        ] do
      response =
        build_conn()
        |> put_req_header("origin", "https://app.example.com")
        |> put_req_header("access-control-request-method", method)
        |> put_req_header("access-control-request-headers", requested)
        |> options(path)

      assert response.status == 204
      assert get_resp_header(response, "access-control-allow-methods") == ["POST"]
      assert get_resp_header(response, "access-control-allow-origin") == ["*"]
      assert get_resp_header(response, "access-control-allow-credentials") == []

      allowed = response |> get_resp_header("access-control-allow-headers") |> Enum.join(",")
      allowed = allowed |> String.downcase() |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

      for name <- String.split(requested, ",") do
        assert String.downcase(String.trim(name)) in allowed
      end

      refute "x-arbitrary-header" in allowed
    end

    assert {:ok, []} = Storage.query(:logs, "acme")
  end

  @tag :sentry_corp
  test "Sentry ingestion responses permit cross-origin resources without relaxing query origins" do
    # Complete upstream scenario: getsentry/relay a68f1dbec05258cfa27b01059e1c1816d10c7257,
    # tests/integration/test_basic.py::test_corp_response_header (lines 274–291).
    # The source asserts only the header on an empty store POST, not its status.
    response =
      :post
      |> Plug.Test.conn("/api/42/store/?sentry_key=#{@key}", "")
      |> PulseWeb.Endpoint.call([])

    assert get_resp_header(response, "cross-origin-resource-policy") == ["cross-origin"]
    assert json_response(response, 400) == %{"error" => "invalid_event"}

    # Local controls cover early body rejection, authentication and preflight
    # on both ingestion routes. None of these requests may publish an event.
    for endpoint <- ["store", "envelope"],
        {method, body, encoding, key, status} <- [
          {:options, "", "identity", @key, 204},
          {:post, "{}", "br", @key, 415},
          {:post, "{}", "identity", "wrong", 403},
          {:post, String.duplicate("a", 4 * 1024 * 1024 + 1), "identity", @key, 413}
        ] do
      response =
        method
        |> Plug.Test.conn("/api/42/#{endpoint}/?sentry_key=#{key}", body)
        |> put_req_header("content-encoding", encoding)
        |> PulseWeb.Endpoint.call([])

      assert response.status == status
      assert get_resp_header(response, "cross-origin-resource-policy") == ["cross-origin"]
      assert get_resp_header(response, "access-control-allow-credentials") == []
    end

    assert {:ok, []} = Storage.query(:logs, "acme")

    response =
      build_conn()
      |> put_req_header("origin", "https://app.example.com")
      |> put_req_header("content-type", "application/json")
      |> post("/mcp", "{}")

    assert response.status == 403
    assert get_resp_header(response, "cross-origin-resource-policy") == []
    assert get_resp_header(response, "access-control-allow-origin") == []
  end

  @tag :s3
  @tag :sentry_empty_auth
  test "an empty auth header permits envelope DSN authentication but grants no authority", %{
    agent: agent,
    config: config
  } do
    # Complete upstream scenario: getsentry/relay a68f1dbec05258cfa27b01059e1c1816d10c7257,
    # tests/integration/test_envelope.py::test_envelope_without_header (lines 73–87).
    # Relay normalizes message into logentry; Pulse retains the original scrubbed message.
    payload = %{"message" => "Hello, World!"}
    headers = %{"dsn" => "https://#{@key}@errors.example.com/42"}

    for {auth, envelope_headers, path} <- [
          {"", %{}, "/api/42/envelope/"},
          {"", %{"dsn" => "https://wrong@errors.example.com/42"}, "/api/42/envelope/"},
          {"", %{"dsn" => "https://#{@key}@errors.example.com/43"}, "/api/42/envelope/"},
          {"", headers, "/api/42/envelope/?sentry_key=wrong"},
          {"malformed", headers, "/api/42/envelope/"},
          {"Sentry sentry_key=wrong", headers, "/api/42/envelope/"}
        ] do
      before = Agent.get(agent, & &1.requests)

      assert build_conn()
             |> put_req_header("content-type", "application/x-sentry-envelope")
             |> put_req_header("x-sentry-auth", auth)
             |> post(path, envelope(payload, envelope_headers))
             |> json_response(403) == %{"error" => "invalid_sentry_key"}

      assert Agent.get(agent, & &1.requests) == before
    end

    response =
      build_conn()
      |> put_req_header("content-type", "application/x-sentry-envelope")
      |> put_req_header("x-sentry-auth", "")
      |> post("/api/42/envelope/", envelope(payload, headers))
      |> json_response(200)

    assert %{"id" => id, "discarded_items" => %{}} = response
    assert Regex.match?(~r/\A[0-9a-f]{32}\z/, id)

    {:ok, owner} = ManifestOwner.ensure_started("acme", "logs", config)
    :ok = GenServer.stop(owner)
    ManifestCache.drop("acme", "logs")

    assert %{"matched_events" => 1, "results" => [result]} = query("query_errors", %{"project" => "42"})
    assert result["event_id"] == id
    assert result["event"]["message"] == "Hello, World!"
    assert result["service"] == "api"
    assert {:ok, []} = Storage.query(:logs, "another")
    assert Agent.get(agent, &Enum.any?(Map.keys(&1.objects), fn key -> String.ends_with?(key, ".parquet") end))
  end

  @tag :s3
  @tag :sentry_preflight
  test "browser gzip envelopes and legacy JSON store requests publish before success", %{agent: agent, config: config} do
    for {path, type, encoding, body} <- [
          {"/api/42/envelope/", "application/x-sentry-envelope", "gzip", :zlib.gzip(envelope(event()))},
          {"/api/42/store/", "application/json", "gzip", :zlib.gzip(Pulse.JSON.encode!(event()))},
          {"/api/42/store/", "application/json", "identity", Pulse.JSON.encode!(event())}
        ] do
      conn =
        build_conn()
        |> put_req_header("origin", "https://app.example.com")
        |> put_req_header("content-type", type)
        |> put_req_header("content-encoding", encoding)

      before = Agent.get(agent, & &1.requests)
      assert conn |> post(path <> "?sentry_key=wrong", body) |> json_response(403)
      assert Agent.get(agent, & &1.requests) == before

      response = post(conn, path <> "?sentry_key=#{@key}", body)
      assert %{"id" => @id} = json_response(response, 200)
      assert get_resp_header(response, "access-control-allow-origin") == ["*"]
      assert get_resp_header(response, "cross-origin-resource-policy") == ["cross-origin"]
      assert get_resp_header(response, "access-control-allow-credentials") == []
    end

    {:ok, owner} = ManifestOwner.ensure_started("acme", "logs", config)
    :ok = GenServer.stop(owner)
    ManifestCache.drop("acme", "logs")
    assert %{"matched_events" => 1, "results" => [%{"event_id" => @id, "event" => stored}]} = query("query_errors")
    assert stored == event()
    assert Agent.get(agent, &Enum.count(Map.keys(&1.objects), fn key -> String.ends_with?(key, ".parquet") end)) == 3
  end

  @tag :s3
  @tag :sentry_store_envelope
  test "store dispatches the exact envelope media type through bounded envelope ingestion", %{
    agent: agent,
    config: config
  } do
    # Independently authored HTTP consumers of Relay a68f1dbec05258cfa27b01059e1c1816d10c7257,
    # endpoints/store.rs:106-121 and extractors/content_type.rs:24-37. Store
    # requires request credentials before selecting the raw media-type branch.
    project = Runtime.get_env(:pulse, Pulse.Sentry)[:projects]["42"]
    Runtime.put_env(:pulse, Pulse.Sentry, projects: %{"42" => project})
    payload = %{"message" => "envelope on store", "timestamp" => "2026-01-01T00:00:00Z", "event_id" => @id}

    ids =
      for {path, index} <- Enum.with_index(["/api/42/store/", "/api/store/"], 1),
          encoding <- ["identity", "gzip"] do
        id = String.duplicate(Integer.to_string(index + if(encoding == "gzip", do: 2, else: 0)), 32)
        headers = if index == 1, do: %{"dsn" => "https://#{@key}@errors.example.com/42"}, else: %{}

        body =
          envelope(payload, Map.put(headers, "event_id", id)) <>
            ~s({"type":"attachment","length":4}\n) <> <<255, 10, 0, 13>>

        conn =
          build_conn()
          |> put_req_header("content-type", "application/x-sentry-envelope")
          |> put_req_header("content-encoding", encoding)
          |> put_req_header("x-sentry-auth", "Sentry sentry_version=7, sentry_key=#{@key}")

        wire = if encoding == "gzip", do: :zlib.gzip(body), else: body

        assert conn |> post("/api/42/envelope/", wire) |> json_response(200) ==
                 %{"id" => id, "discarded_items" => %{"attachment" => 1}}

        response = post(conn, path, wire)
        assert json_response(response, 200) == %{"id" => id, "discarded_items" => %{"attachment" => 1}}
        assert get_resp_header(response, "x-pulse-discarded-items") == ["1"]
        assert get_resp_header(response, "cross-origin-resource-policy") == ["cross-origin"]
        id
      end

    {:ok, owner} = ManifestOwner.ensure_started("acme", "logs", config)
    :ok = GenServer.stop(owner)
    ManifestCache.drop("acme", "logs")
    assert %{"matched_events" => 4, "results" => records} = query("query_errors")
    assert Enum.sort(Enum.map(records, & &1["event_id"])) == Enum.sort(ids)

    for record <- records do
      assert record["event"] == Map.put(payload, "event_id", record["event_id"])
      assert record["project"] == "42"
    end

    assert Agent.get(agent, & &1.reads) != []
    assert Agent.get(agent, &Enum.count(Map.keys(&1.objects), fn key -> String.ends_with?(key, ".parquet") end)) == 8
  end

  @tag :s3
  @tag :sentry_store_envelope
  test "store envelope dispatch retains credential, exact media type, framing and size boundaries", %{agent: agent} do
    payload = %{"message" => "store envelope control", "timestamp" => "2026-01-01T00:00:00Z"}
    valid = envelope(payload)
    dsn = "https://#{@key}@errors.example.com/42"

    cases = [
      {"/api/42/store/", "", "application/x-sentry-envelope", envelope(payload, %{"dsn" => dsn}), 403},
      {"/api/42/store/?sentry_key=wrong", "", "application/x-sentry-envelope", valid, 403},
      {"/api/42/store/?sentry_key=#{@key}", "", "application/x-sentry-envelope",
       envelope(payload, %{"dsn" => "https://wrong@errors.example.com/42"}), 403},
      {"/api/42/store/?sentry_key=#{@key}", "", "application/x-sentry-envelope",
       envelope(payload, %{"dsn" => "https://#{@key}@errors.example.com/43"}), 403},
      {"/api/store/?sentry_key=#{@key}", "", "application/x-sentry-envelope", valid, 403},
      {"/api/42/store/?sentry_key=#{@key}", "", "application/x-sentry-envelope; charset=utf-8", valid, 400},
      {"/api/42/store/?sentry_key=#{@key}", "", "Application/X-Sentry-Envelope", valid, 400},
      {"/api/42/store/?sentry_key=#{@key}", "", "text/plain", valid, 400},
      {"/api/42/store/?sentry_key=#{@key}", "", "application/x-sentry-envelope", Pulse.JSON.encode!(payload), 200},
      {"/api/42/store/?sentry_key=#{@key}", "", "application/x-sentry-envelope", "not an envelope", 400},
      {"/api/42/store/?sentry_key=#{@key}", "", "application/x-sentry-envelope", valid <> ~s({"type":"event"}\n{}\n),
       400},
      {"/api/42/store/?sentry_key=#{@key}", "", "application/x-sentry-envelope",
       ~s({}\n{"type":"event","length":99}\n{}), 400},
      {"/api/42/store/?sentry_key=#{@key}", "", "application/x-sentry-envelope",
       envelope(Map.put(payload, "message", String.duplicate("a", 1_048_576))), 413}
    ]

    before = Agent.get(agent, & &1.requests)

    for {path, auth, type, body, status} <- cases do
      response =
        build_conn()
        |> put_req_header("content-type", type)
        |> put_req_header("x-sentry-auth", auth)
        |> post(path, body)

      assert json_response(response, status)
      assert Agent.get(agent, & &1.requests) == before
    end

    query = URI.encode_query(%{"sentry_key" => @key, "sentry_data" => valid})

    assert build_conn()
           |> put_req_header("content-type", "application/x-sentry-envelope")
           |> get("/api/42/store/?" <> query)
           |> json_response(400)

    project = Runtime.get_env(:pulse, Pulse.Sentry)[:projects]["42"]
    Runtime.put_env(:pulse, Pulse.Sentry, projects: %{"42" => project})

    assert build_conn()
           |> put_req_header("content-type", "application/x-sentry-envelope")
           |> post("/api/store/?sentry_key=#{@key}", envelope(payload, %{"dsn" => dsn}))
           |> json_response(403)

    # A header-only JSON object is an empty envelope, not a legacy JSON event.
    assert %{"id" => nil, "discarded_items" => %{}} =
             build_conn()
             |> put_req_header("content-type", "application/x-sentry-envelope")
             |> post("/api/42/store/?sentry_key=#{@key}", "{}\n")
             |> json_response(200)

    assert %{"id" => nil, "discarded_items" => %{"transaction" => 1}} =
             build_conn()
             |> put_req_header("content-type", "application/x-sentry-envelope")
             |> post("/api/42/store/?sentry_key=#{@key}", ~s({}\n{"type":"transaction"}\n{}\n))
             |> json_response(200)

    assert Agent.get(agent, & &1.requests) == before
    assert Agent.get(agent, & &1.objects) == %{}
  end

  @tag :s3
  @tag :sentry_authorization_header
  test "Sentry authorization header locations and scheme case preserve durable project ownership", %{
    agent: agent,
    config: config
  } do
    # Independently authored consumers of Relay a68f1dbec05258cfa27b01059e1c1816d10c7257,
    # extractors/request_meta.rs:663-687: case-insensitive Sentry scheme in
    # either header. Agreement of multiple credentials is Pulse's stricter policy.
    projects = Runtime.get_env(:pulse, Pulse.Sentry)[:projects] |> Map.take(["42"])
    Runtime.put_env(:pulse, Pulse.Sentry, projects: projects)

    Runtime.put_env(:pulse, Pulse.Auth,
      module: SharedSecret,
      tokens: %{"acme" => "sha256$" <> Base.encode16(:crypto.hash(:sha256, "read-token"), case: :lower)}
    )

    expected =
      for {header, scheme} <- [{"authorization", "Sentry"}, {"authorization", "sEnTrY"}, {"x-sentry-auth", "sEnTrY"}],
          {method, path} <- [
            {:post, "/api/42/store/"},
            {:post, "/api/store/"},
            {:post, "/api/42/envelope/"},
            {:get, "/api/42/store/"},
            {:get, "/api/store/"}
          ] do
        id = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
        payload = event(%{"event_id" => id})
        json = Pulse.JSON.encode!(payload)
        path = if method == :get, do: path <> "?" <> URI.encode_query(%{"sentry_data" => json}), else: path
        body = if String.contains?(path, "/envelope/"), do: envelope(payload), else: json

        response =
          method
          |> Plug.Test.conn(path, body)
          |> put_req_header(header, "#{scheme} sentry_version=7, sentry_key=#{@key}")
          |> put_req_header("x-scope-orgid", "spoofed")
          |> PulseWeb.Endpoint.call([])

        if method == :get do
          assert response.status == 200
          assert get_resp_header(response, "content-type") == ["image/gif"]
        else
          assert %{"id" => ^id} = json_response(response, 200)
        end

        {id, payload}
      end

    # Matching credentials retain Pulse's existing agreement policy, rather
    # than Relay's rejection of multiple authentication methods.
    payload = event()

    assert %{"id" => @id} =
             :post
             |> Plug.Test.conn(
               "/api/42/envelope/?sentry_key=#{@key}",
               envelope(payload, %{"dsn" => "https://#{@key}@example.com/42"})
             )
             |> put_req_header("authorization", "Sentry sentry_key=#{@key}")
             |> put_req_header("x-sentry-auth", "Sentry sentry_key=#{@key}")
             |> PulseWeb.Endpoint.call([])
             |> json_response(200)

    expected = [{@id, payload} | expected]
    {:ok, owner} = ManifestOwner.ensure_started("acme", "logs", config)
    :ok = GenServer.stop(owner)
    ManifestCache.drop("acme", "logs")
    assert %{"matched_events" => 16, "results" => results} = query("query_errors")
    records = Map.new(results, &{&1["event_id"], &1})

    for {id, payload} <- expected do
      assert %{"project" => "42", "service" => "api", "event" => ^payload} = Map.fetch!(records, id)
    end

    before = Agent.get(agent, & &1.requests)

    for headers <- [
          [{"authorization", "Sentry sentry_key=wrong"}],
          [{"authorization", "Sentry sentry_version=7"}],
          [{"authorization", "Sentry sentry_key=#{@key}, sentry_key=wrong"}],
          [{"authorization", "Sentry sentry_key=wrong"}, {"x-sentry-auth", "Sentry sentry_key=#{@key}"}],
          [{"authorization", "Sentry sentry_key=#{@key}"}, {"x-sentry-auth", "Sentry sentry_key=wrong"}],
          [{"authorization", "Bearer read-token"}]
        ] do
      conn = Plug.Test.conn(:post, "/api/42/store/", Pulse.JSON.encode!(event()))
      conn = Enum.reduce(headers, conn, fn {name, value}, conn -> put_req_header(conn, name, value) end)
      assert conn |> PulseWeb.Endpoint.call([]) |> json_response(403) == %{"error" => "invalid_sentry_key"}
    end

    assert :post
           |> Plug.Test.conn("/api/42/store/?sentry_key=wrong", Pulse.JSON.encode!(event()))
           |> put_req_header("authorization", "Sentry sentry_key=#{@key}")
           |> PulseWeb.Endpoint.call([])
           |> json_response(403) == %{"error" => "invalid_sentry_key"}

    duplicate = Plug.Test.conn(:post, "/api/42/store/", Pulse.JSON.encode!(event()))

    duplicate = %{
      duplicate
      | req_headers: [{"authorization", "Sentry sentry_key=#{@key}"}, {"authorization", "Sentry sentry_key=wrong"}]
    }

    assert duplicate |> PulseWeb.Endpoint.call([]) |> json_response(403) == %{"error" => "invalid_sentry_key"}

    assert :get
           |> Plug.Test.conn("/api/v1/query?query=vector(1)")
           |> put_req_header("authorization", "Sentry sentry_key=#{@key}")
           |> put_req_header("x-scope-orgid", "acme")
           |> PulseWeb.Endpoint.call([])
           |> json_response(401)

    assert Agent.get(agent, & &1.requests) == before
  end

  @tag :s3
  @tag :sentry_projectless_store
  test "project-less store resolves a unique credential and never trusts supplied project or tenant fields", %{
    agent: agent,
    config: config
  } do
    # Complete getsentry/relay a68f1dbec05258cfa27b01059e1c1816d10c7257 scenario,
    # tests/integration/test_store.py::test_legacy_store (lines 53–64): two
    # project-less POSTs with send_event's default payload and Raven auth header.
    # The other project, rotation and rejection cases are separate local controls.
    project = Runtime.get_env(:pulse, Pulse.Sentry)[:projects]["42"]
    rotated = Base.encode16(:crypto.hash(:sha256, "rotated-key"), case: :lower)
    other_digest = Base.encode16(:crypto.hash(:sha256, "other-key"), case: :lower)
    project = Map.update!(project, "public_key_hashes", &[rotated | &1])
    other = %{"tenant" => "another", "service" => "worker", "public_key_hashes" => [other_digest]}
    projects = %{"42" => project, "43" => other}
    Runtime.put_env(:pulse, Pulse.Sentry, projects: projects)
    payload = %{"message" => "Hello, World!"}

    ids =
      for _ <- 1..2 do
        response =
          build_conn()
          |> put_req_header("content-type", "application/octet-stream")
          |> put_req_header(
            "x-sentry-auth",
            "Sentry sentry_version=5, sentry_timestamp=1535376240291, sentry_client=raven-node/2.6.3, sentry_key=#{@key}"
          )
          |> post("/api/store/", Pulse.JSON.encode!(payload))
          |> json_response(200)

        assert %{"id" => id, "discarded_items" => %{}} = response
        id
      end

    for {key, id} <- [{"rotated-key", @id}, {"other-key", @other_id}] do
      body = Pulse.JSON.encode!(%{"message" => "local control", "event_id" => id, "project" => "999"})

      assert build_conn()
             |> put_req_header("content-type", "text/plain")
             |> put_req_header("x-sentry-auth", "")
             |> put_req_header("x-scope-orgid", "victim")
             |> post("/api/store/?sentry_key=#{key}&project_id=999", body)
             |> json_response(200) == %{"id" => id, "discarded_items" => %{}}
    end

    for {path, auth, body, status} <- [
          {"/api/store/", "", Pulse.JSON.encode!(payload), 403},
          {"/api/store/?sentry_key=wrong", "", "bad JSON", 403},
          {"/api/store/?sentry_key=#{@key}", "malformed", Pulse.JSON.encode!(payload), 403},
          {"/api/store/?sentry_key=#{@key}", "Sentry sentry_key=other-key", Pulse.JSON.encode!(payload), 403},
          {"/api/43/store/?sentry_key=#{@key}&project_id=42", "", Pulse.JSON.encode!(payload), 403},
          {"/api/store/?sentry_key=#{@key}", "", "bad JSON", 400},
          {"/api/store/?sentry_key=#{@key}", "", "{}" <> String.duplicate(" ", 1_048_575), 413},
          {"/api/store/?sentry_key=#{@key}", "", String.duplicate("a", 4 * 1024 * 1024 + 1), 413}
        ] do
      before = Agent.get(agent, & &1.requests)

      assert build_conn()
             |> put_req_header("content-type", "application/octet-stream")
             |> put_req_header("x-sentry-auth", auth)
             |> post(path, body)
             |> json_response(status)

      assert Agent.get(agent, & &1.requests) == before
    end

    ambiguous = Map.put(projects, "43", Map.put(other, "public_key_hashes", project["public_key_hashes"]))

    for configured <- [ambiguous, %{}], path <- ["/api/store/", "/api/store/?project_id=42"] do
      Runtime.put_env(:pulse, Pulse.Sentry, projects: configured)
      before = Agent.get(agent, & &1.requests)

      assert build_conn()
             |> put_req_header("content-type", "application/octet-stream")
             |> put_req_header("x-sentry-auth", "Sentry sentry_key=#{@key}")
             |> post(path, Pulse.JSON.encode!(%{"message" => "local control", "project" => "42"}))
             |> json_response(403) == %{"error" => "invalid_sentry_key"}

      assert Agent.get(agent, & &1.requests) == before
    end

    for tenant <- ["acme", "another"] do
      {:ok, owner} = ManifestOwner.ensure_started(tenant, "logs", config)
      :ok = GenServer.stop(owner)
      ManifestCache.drop(tenant, "logs")
    end

    assert %{"matched_events" => 3, "results" => results} = query("query_errors")
    assert results |> Enum.map(& &1["event_id"]) |> Enum.sort() == Enum.sort([@id | ids])
    assert Enum.all?(results, &(&1["project"] == "42" and &1["service"] == "api"))

    assert Enum.filter(results, &(&1["event_id"] in ids)) |> Enum.map(& &1["event"]["message"]) ==
             ["Hello, World!", "Hello, World!"]

    assert %{"matched_events" => 1, "results" => [result]} = query("query_errors", %{"tenant" => "another"})
    assert result["event_id"] == @other_id
    assert result["project"] == "43"
    assert result["service"] == "worker"
    assert result["event"]["project"] == "999"
    assert {:ok, []} = Storage.query(:logs, "victim")
    assert Agent.get(agent, &Enum.count(Map.keys(&1.objects), fn key -> String.ends_with?(key, ".parquet") end)) == 4
  end

  @tag :s3
  @tag :sentry_pixel_store
  test "pixel store publishes query events before returning a non-cacheable GIF within existing limits", %{
    agent: agent,
    config: config
  } do
    # Complete getsentry/relay a68f1dbec05258cfa27b01059e1c1816d10c7257 table,
    # tests/integration/test_basic.py::test_store_pixel_gif (lines 115–141).
    # Upstream parametrizes trailing_slash but does not use it: retain all four
    # executions of the actual /api/42/store/ URL, not invented alternate URLs.
    for _trailing_slash <- [true, false],
        input <- [
          ~s({"message": "im in ur query params"}),
          "eF6rVspNLS5OTE9VslJQysxVyMxTKC1SKCxNLapUKEgsSswtVqoFAOKyDI4="
        ] do
      query = URI.encode_query(%{"sentry_data" => input, "sentry_key" => @key})
      conn = get(build_conn(), "/api/42/store/?" <> query)
      assert <<"GIF89a", 1::little-16, 1::little-16, _::binary>> = response(conn, 200)
      assert get_resp_header(conn, "content-type") == ["image/gif"]
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end

    # A key shared by two configured projects must remain ambiguous on GET too.
    before = Agent.get(agent, & &1.requests)
    query = URI.encode_query(%{"sentry_data" => ~s({"project":"42"}), "sentry_key" => @key, "project_id" => "42"})
    assert build_conn() |> get("/api/store/?" <> query) |> json_response(403)
    assert Agent.get(agent, & &1.requests) == before
    projects = Runtime.get_env(:pulse, Pulse.Sentry)[:projects] |> Map.take(["42"])
    Runtime.put_env(:pulse, Pulse.Sentry, projects: projects)

    boundary = Pulse.JSON.encode!(%{"event_id" => @other_id, "message" => "boundary"})
    boundary = boundary <> String.duplicate(" ", 1_048_576 - byte_size(boundary))

    for {path, data} <- [
          {"/api/store/", Pulse.JSON.encode!(%{"event_id" => @id, "message" => "local control", "project" => "999"})},
          {"/api/42/store/", Base.encode64(:zlib.compress(boundary))}
        ] do
      query = URI.encode_query(%{"sentry_key" => @key, "sentry_data" => data, "project_id" => "999"})
      conn = build_conn() |> put_req_header("x-scope-orgid", "victim") |> get(path <> "?" <> query)
      assert <<"GIF89a", 1::little-16, 1::little-16, _::binary>> = response(conn, 200)
    end

    for {path, query, status} <- [
          {"/api/42/store/", URI.encode_query(%{"sentry_data" => "{}"}), 403},
          {"/api/42/store/", URI.encode_query(%{"sentry_key" => @key}), 400},
          {"/api/42/store/", "sentry_key=#{@key}&sentry_data[]=bad", 400},
          {"/api/42/store/", URI.encode_query(%{"sentry_key" => @key, "sentry_data" => "bad"}), 400},
          {"/api/999/store/", URI.encode_query(%{"sentry_key" => @key, "sentry_data" => "{}"}), 403},
          {"/api/42/envelope/", URI.encode_query(%{"sentry_key" => @key, "sentry_data" => "{}"}), 404}
        ] do
      before = Agent.get(agent, & &1.requests)
      assert build_conn() |> get(path <> "?" <> query) |> json_response(status)
      assert Agent.get(agent, & &1.requests) == before
    end

    for key <- [@key, "wrong"] do
      query = URI.encode_query(%{"sentry_key" => key, "sentry_data" => Base.encode64(:zlib.compress(boundary <> " "))})
      before = Agent.get(agent, & &1.requests)
      assert build_conn() |> get("/api/42/store/?" <> query) |> json_response(if(key == @key, do: 413, else: 403))
      assert Agent.get(agent, & &1.requests) == before
    end

    prefix = "sentry_key=wrong&sentry_data=%7B%7D&padding="
    query = prefix <> String.duplicate("a", 1_000_000 - byte_size(prefix))
    before = Agent.get(agent, & &1.requests)
    assert build_conn() |> get("/api/42/store/?" <> query) |> json_response(403)

    assert_error_sent(414, fn -> get(build_conn(), "/api/42/store/?" <> query <> "a") end)
    assert Agent.get(agent, & &1.requests) == before

    before = Agent.get(agent, & &1.requests)
    query = URI.encode_query(%{"sentry_key" => @key, "sentry_data" => "{}"})
    assert build_conn() |> head("/api/42/store/?" <> query) |> response(405)
    assert Agent.get(agent, & &1.requests) == before

    {:ok, owner} = ManifestOwner.ensure_started("acme", "logs", config)
    :ok = GenServer.stop(owner)
    ManifestCache.drop("acme", "logs")
    assert %{"matched_events" => 6, "results" => results} = query("query_errors")
    assert Enum.count(results, &(&1["event"]["message"] == "im in ur query params")) == 4
    assert Enum.find(results, &(&1["event_id"] == @id))["event"]["project"] == "999"
    assert Enum.find(results, &(&1["event_id"] == @other_id))["event"]["message"] == "boundary"
    assert Enum.all?(results, &(&1["project"] == "42" and &1["service"] == "api"))
    assert {:ok, []} = Storage.query(:logs, "victim")
    assert Agent.get(agent, &Enum.count(Map.keys(&1.objects), fn key -> String.ends_with?(key, ".parquet") end)) == 6
  end

  @tag :s3
  @tag :sentry_origins
  test "configured origins admit the complete Relay browser table without granting credential authority", %{
    agent: agent,
    config: config
  } do
    # Relay a68f1dbec05258cfa27b01059e1c1816d10c7257,
    # test_basic.py::test_store_allowed_origins_passes, all six original rows.
    project = Runtime.get_env(:pulse, Pulse.Sentry)[:projects]["42"]

    for {domains, allowed?} <- [
          {["*"], true},
          {["http://valid.com"], true},
          {["http://*"], true},
          {["valid.com"], true},
          {[], false},
          {["invalid.com"], false}
        ] do
      projects = %{"42" => Map.put(project, "allowed_domains", domains)}
      Runtime.put_env(:pulse, Pulse.Sentry, projects: projects)
      before = Agent.get(agent, & &1.requests)

      conn =
        build_conn()
        |> put_req_header("origin", "http://valid.com")
        |> put_req_header("content-type", "application/json")
        |> post("/api/42/store/?sentry_key=#{@key}", ~s({"message":"hi"}))

      # Relay asserts capture/noncapture, not an HTTP rejection code. Pulse's
      # explicit 403 is a local policy rather than an invented upstream oracle.
      assert json_response(conn, if(allowed?, do: 200, else: 403))
      if !allowed?, do: assert(Agent.get(agent, & &1.requests) == before)
    end

    projects = %{"42" => Map.put(project, "allowed_domains", ["https://*.example.com:8443"])}
    assert Pulse.Sentry.validate_projects!(projects) == projects
    Runtime.put_env(:pulse, Pulse.Sentry, projects: projects)

    for origin <- ["https://example.com:8443", "https://sub.example.com:8443"] do
      assert build_conn()
             |> put_req_header("origin", origin)
             |> put_req_header("content-type", "application/json")
             |> post("/api/42/store/?sentry_key=#{@key}", ~s({"message":"local control"}))
             |> json_response(200)
    end

    for origin <- [
          "https://notexample.com:8443",
          "https://example.com.evil:8443",
          "http://example.com:8443",
          "https://example.com",
          "https://user@example.com:8443",
          "https://example.com:8443/path",
          "https://example.com:8443 https://other.com",
          "https://" <> String.duplicate("a", 2049),
          "null"
        ] do
      before = Agent.get(agent, & &1.requests)

      assert build_conn()
             |> put_req_header("origin", origin)
             |> put_req_header("content-type", "application/x-sentry-envelope")
             |> post("/api/42/envelope/?sentry_key=#{@key}", envelope(event()))
             |> json_response(403)

      data = URI.encode_query(%{"sentry_key" => @key, "sentry_data" => "{}"})
      assert build_conn() |> put_req_header("origin", origin) |> get("/api/store/?" <> data) |> json_response(403)
      assert Agent.get(agent, & &1.requests) == before
    end

    for {pattern, origin} <- [
          {"https://[::1]:8443", "https://[::1]:8443"},
          {"*://EXAMPLE.NET:*/ignored", "https://example.net:443"}
        ] do
      Runtime.put_env(:pulse, Pulse.Sentry, projects: %{"42" => Map.put(project, "allowed_domains", [pattern])})

      assert build_conn()
             |> put_req_header("origin", origin)
             |> put_req_header("content-type", "application/json")
             |> post("/api/42/store/?sentry_key=#{@key}", ~s({"message":"component control"}))
             |> json_response(200)
    end

    # A permitted origin cannot choose between projects that share the same key.
    Runtime.put_env(:pulse, Pulse.Sentry,
      projects: %{"42" => Map.put(project, "allowed_domains", ["http://valid.com"]), "43" => project}
    )

    before = Agent.get(agent, & &1.requests)

    assert build_conn()
           |> put_req_header("origin", "http://valid.com")
           |> put_req_header("content-type", "application/json")
           |> post("/api/store/?sentry_key=#{@key}", ~s({"message":"ambiguous"}))
           |> json_response(403)

    assert Agent.get(agent, & &1.requests) == before

    Runtime.put_env(:pulse, Pulse.Sentry, projects: %{"42" => Map.put(project, "allowed_domains", [])})

    assert build_conn()
           |> put_req_header("content-type", "application/json")
           |> post("/api/42/store/?sentry_key=#{@key}", ~s({"message":"non-browser"}))
           |> json_response(200)

    before = Agent.get(agent, & &1.requests)

    assert build_conn()
           |> put_req_header("content-type", "application/x-sentry-envelope")
           |> post("/api/42/envelope/?sentry_key=wrong", envelope(event()))
           |> json_response(403)

    assert Agent.get(agent, & &1.requests) == before

    {:ok, owner} = ManifestOwner.ensure_started("acme", "logs", config)
    :ok = GenServer.stop(owner)
    ManifestCache.drop("acme", "logs")
    assert %{"matched_events" => 9, "results" => results} = query("query_errors")
    assert Enum.count(results, &(&1["event"]["message"] == "hi")) == 4
    assert Enum.all?(results, &(&1["project"] == "42" and &1["service"] == "api"))
  end

  @tag :s3
  @tag :sentry_legacy_store
  test "legacy base64 store events retain the upstream Node payload within the event budget", %{
    agent: agent,
    config: config
  } do
    # Complete getsentry/relay a68f1dbec05258cfa27b01059e1c1816d10c7257 scenario,
    # tests/integration/test_store.py::test_store_node_base64 (lines 86–110),
    # including send_event's octet-stream/auth headers and original encoded bytes.
    fixture = File.read!("test/fixtures/sentry/relay-store-node-base64.txt") |> String.trim_trailing("\n")
    original_id = "6954759d0d1945229f6e4175e513882a"
    boundary_id = String.duplicate("c", 32)
    json = Pulse.JSON.encode!(event(%{"message" => "base64 JSON"}))
    boundary = Pulse.JSON.encode!(event(%{"event_id" => boundary_id, "message" => "legacy boundary"}))
    boundary = boundary <> String.duplicate(" ", 1_048_576 - byte_size(boundary))

    for {body, encoding, id} <- [
          {fixture, nil, original_id},
          {Base.encode64(json), "identity", @id},
          {:zlib.gzip(fixture), "gzip", original_id},
          {" \r\n" <> Pulse.JSON.encode!(event(%{"event_id" => @other_id})), "identity", @other_id},
          {Base.encode64(boundary), "identity", boundary_id},
          {Base.encode64(:zlib.compress(boundary)), "identity", boundary_id}
        ] do
      response =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header(
          "x-sentry-auth",
          "Sentry sentry_version=5, sentry_timestamp=1535376240291, sentry_client=raven-node/2.6.3, sentry_key=#{@key}"
        )
        |> then(&if(encoding, do: put_req_header(&1, "content-encoding", encoding), else: &1))
        |> post("/api/42/store/", body)

      assert %{"id" => ^id} = json_response(response, 200)
    end

    compressed = Base.decode64!(fixture)
    truncated = binary_part(compressed, 0, byte_size(compressed) - 1)

    for {body, key, status} <- [
          {fixture, "wrong", 403},
          {"not base64!", "wrong", 403},
          {"not base64!", @key, 400},
          {Base.encode64("[]"), @key, 400},
          {Base.encode64("not zlib"), @key, 400},
          {Base.encode64(truncated), @key, 400},
          {Base.encode64(compressed <> "junk"), @key, 400},
          {Base.encode64(compressed <> compressed), @key, 400},
          {Base.encode64(:zlib.zip(json)), @key, 400},
          {Base.encode64(:zlib.gzip(json)), @key, 400},
          {Base.encode64(fixture), @key, 400},
          {compressed, @key, 400},
          {Base.encode64(boundary <> " "), @key, 413},
          {Base.encode64(:zlib.compress(boundary <> " ")), @key, 413},
          {Base.encode64(:zlib.compress(String.duplicate("a", 16 * 1024 * 1024 + 1))), @key, 413},
          {String.duplicate("a", 4 * 1024 * 1024 + 1), @key, 413}
        ] do
      before = Agent.get(agent, & &1.requests)

      assert build_conn()
             |> put_req_header("content-type", "application/octet-stream")
             |> post("/api/42/store/?sentry_key=#{key}", body)
             |> json_response(status)

      assert Agent.get(agent, & &1.requests) == before
    end

    before = Agent.get(agent, & &1.requests)
    assert fixture |> send_envelope() |> json_response(400)
    assert Agent.get(agent, & &1.requests) == before

    {:ok, owner} = ManifestOwner.ensure_started("acme", "logs", config)
    :ok = GenServer.stop(owner)
    ManifestCache.drop("acme", "logs")
    assert %{"matched_events" => 4, "results" => results} = query("query_errors")
    original = Enum.find(results, &(&1["event_id"] == original_id))
    assert original["event"]["message"] == "Error: yo mark"
    assert original["event"]["timestamp"] == "2018-08-27T13:24:00"
    assert original["timestamp_ns"] == 1_535_376_240_000_000_000
    assert original["project"] == "42"
    assert original["event"]["project"] == "11"
    assert is_list(original["event"]["exception"])
    assert Enum.find(results, &(&1["event_id"] == @id))["event"] == event(%{"message" => "base64 JSON"})
    assert Enum.find(results, &(&1["event_id"] == @other_id))["event"] == event(%{"event_id" => @other_id})

    assert Enum.find(results, &(&1["event_id"] == boundary_id))["event"] ==
             event(%{"event_id" => boundary_id, "message" => "legacy boundary"})

    assert Enum.all?(results, &(&1["service"] == "api"))
    assert {:ok, []} = Storage.query(:logs, "another")
    assert Agent.get(agent, &Enum.count(Map.keys(&1.objects), fn key -> String.ends_with?(key, ".parquet") end)) == 6
  end

  @tag :s3
  @tag :sentry_empty_encoding
  @tag :sentry_deflate
  test "Sentry compression forms preserve authentication, decoding and size limits", %{
    agent: agent,
    config: config
  } do
    # getsentry/relay a68f1dbec05258cfa27b01059e1c1816d10c7257,
    # tests/integration/test_basic.py::test_compression (lines 253–271).
    # All four source rows retain the original bytes and omitted content type;
    # envelope rows and rejection cases are separate local controls.
    payload = ~s({"message": "hello world"})
    deflated = :zlib.compress(payload)
    prefix_size = byte_size(deflated) - 1
    <<prefix::binary-size(^prefix_size), checksum>> = deflated

    ids =
      for {path, encoding, body} <- [
            {"/api/42/store/", "gzip", :zlib.gzip(payload)},
            {"/api/42/store/", "deflate", deflated},
            {"/api/42/store/", "identity", payload},
            {"/api/42/store/", "", payload},
            {"/api/42/envelope/", "", envelope(%{"message" => "hello world"})},
            {"/api/42/envelope/", "deflate", :zlib.compress(envelope(%{"message" => "hello world"}))}
          ] do
        response =
          :post
          |> Plug.Test.conn(path <> "?sentry_key=#{@key}", body)
          |> put_req_header("content-encoding", encoding)
          |> PulseWeb.Endpoint.call([])
          |> json_response(200)

        assert %{"id" => id} = response
        id
      end

    for {encoding, body, key, status} <- [
          {"br", payload, @key, 415},
          {"gzip, identity", payload, @key, 415},
          {"deflate, gzip", deflated, @key, 415},
          {"deflate", "", @key, 400},
          {"deflate", prefix, @key, 400},
          {"deflate", prefix <> <<Bitwise.bxor(checksum, 1)>>, @key, 400},
          {"deflate", :zlib.zip(payload), @key, 400},
          {"deflate", :zlib.gzip(payload), @key, 400},
          {"deflate", deflated <> "junk", @key, 400},
          {"deflate", deflated <> deflated, @key, 400},
          {"deflate", :zlib.compress("not-json"), @key, 400},
          {"deflate", deflated, "wrong", 403},
          {"deflate", :zlib.compress(Pulse.JSON.encode!(%{"message" => String.duplicate("a", 1_048_576)})), @key, 413},
          {"deflate", :zlib.compress(String.duplicate("a", 16 * 1024 * 1024 + 1)), @key, 413},
          {"deflate", String.duplicate("a", 4 * 1024 * 1024 + 1), @key, 413},
          {"", :zlib.gzip(payload), @key, 400},
          {"", "not-json", @key, 400},
          {"", payload, "wrong", 403},
          {"", Pulse.JSON.encode!(%{"message" => String.duplicate("a", 1_048_576)}), @key, 413},
          {"", String.duplicate("a", 4 * 1024 * 1024 + 1), @key, 413}
        ] do
      before = Agent.get(agent, & &1.requests)

      assert :post
             |> Plug.Test.conn("/api/42/store/?sentry_key=#{key}", body)
             |> put_req_header("content-encoding", encoding)
             |> PulseWeb.Endpoint.call([])
             |> json_response(status)

      assert Agent.get(agent, & &1.requests) == before
    end

    # The expanded-body ceiling is inclusive even when the only item is
    # discarded; its separate per-event limit must not shrink this allowance.
    header = ~s({}\n{"type":"attachment"}\n)
    body = header <> String.duplicate("a", 16 * 1024 * 1024 - byte_size(header))
    before = Agent.get(agent, & &1.requests)

    assert :post
           |> Plug.Test.conn("/api/42/envelope/?sentry_key=#{@key}", :zlib.compress(body))
           |> put_req_header("content-encoding", "deflate")
           |> PulseWeb.Endpoint.call([])
           |> json_response(200) == %{"id" => nil, "discarded_items" => %{"attachment" => 1}}

    assert Agent.get(agent, & &1.requests) == before

    {:ok, owner} = ManifestOwner.ensure_started("acme", "logs", config)
    :ok = GenServer.stop(owner)
    ManifestCache.drop("acme", "logs")
    assert %{"matched_events" => 6, "results" => results} = query("query_errors")
    assert results |> Enum.map(& &1["event_id"]) |> Enum.sort() == Enum.sort(ids)
    assert Enum.all?(results, &(&1["event"]["message"] == "hello world" and &1["service"] == "api"))
    assert Agent.get(agent, &Enum.count(Map.keys(&1.objects), fn key -> String.ends_with?(key, ".parquet") end)) == 6
  end

  @tag :s3
  @tag :sentry_logentry_string
  test "Relay string logentry oracle supplies titles and grouping while retaining raw input", %{config: config} do
    # Relay a68f1dbec05258cfa27b01059e1c1816d10c7257,
    # logentry.rs:178-191, complete test_logentry_from_message:
    # JSON "hi" decodes to {"formatted":"hi"}. These become public event
    # fields; Pulse titles/group IDs are explicitly authored consumers.
    cases = [
      {%{"logentry" => Pulse.JSON.decode!(~s("hi"))}, "hi"},
      {%{"logentry" => %{"formatted" => "hi"}}, "hi"},
      {%{"logentry" => "bye", "message" => "must not override logentry"}, "bye"},
      {%{"logentry" => "hi", "exception" => %{"type" => "Inner", "value" => "selected exception"}},
       "Inner: selected exception"}
    ]

    expected =
      for {fields, title} <- cases, route <- ["store", "envelope"] do
        event = Map.put(fields, "timestamp", "2026-01-01T00:00:00Z")
        body = if route == "store", do: Pulse.JSON.encode!(event), else: envelope(event)

        %{"id" => id} =
          :post
          |> Plug.Test.conn("/api/42/#{route}/?sentry_key=#{@key}", body)
          |> PulseWeb.Endpoint.call([])
          |> json_response(200)

        {id, {fields, title}}
      end

    {:ok, owner} = ManifestOwner.ensure_started("acme", "logs", config)
    :ok = GenServer.stop(owner)
    ManifestCache.drop("acme", "logs")

    assert %{"matched_events" => 8, "results" => issues} = query("list_error_issues")
    assert Map.new(issues, &{&1["title"], &1["count"]}) == %{"hi" => 4, "bye" => 2, "Inner: selected exception" => 2}
    assert length(issues) == 3
    issue_ids = Map.new(issues, &{&1["title"], &1["issue_id"]})
    assert %{"matched_events" => 8, "results" => results} = query("query_errors")
    records = Map.new(results, &{&1["event_id"], &1})
    assert map_size(records) == length(expected)

    for {id, {fields, title}} <- expected do
      record = Map.fetch!(records, id)
      assert Map.take(record["event"], Map.keys(fields)) == fields
      assert record["issue_id"] == Map.fetch!(issue_ids, title)
    end
  end

  @tag :s3
  @tag :sentry_stacktrace_alias
  test "legacy exception stacktraces retain canonical frame-based groups through cold reads", %{
    config: config,
    agent: agent
  } do
    # Independently authored consumers of Relay's exception.rs:50-54 alias at
    # a68f1dbec05258cfa27b01059e1c1816d10c7257. Group IDs are Pulse policy,
    # not upstream Sentry grouping oracles; no Rust fixture is copied.
    expected =
      for function <- ["authorize", "refund"],
          field <- ["stacktrace", "sentry.interfaces.Stacktrace"],
          route <- ["store", "envelope"] do
        exception = %{
          "type" => "PaymentFailure",
          "value" => "declined",
          field => %{"frames" => [%{"module" => "payments.gateway", "function" => function, "in_app" => true}]}
        }

        payload = %{"timestamp" => "2026-01-01T00:00:00Z", "exception" => %{"values" => [exception]}}
        body = if route == "store", do: Pulse.JSON.encode!(payload), else: envelope(payload)

        %{"id" => id} =
          :post
          |> Plug.Test.conn("/api/42/#{route}/?sentry_key=#{@key}", body)
          |> PulseWeb.Endpoint.call([])
          |> json_response(200)

        {id, exception, function}
      end

    {:ok, owner} = ManifestOwner.ensure_started("acme", "logs", config)
    :ok = GenServer.stop(owner)
    ManifestCache.drop("acme", "logs")
    assert %{"matched_events" => 8, "results" => results} = query("query_errors")
    records = Map.new(results, &{&1["event_id"], &1})
    assert {:ok, stored} = Storage.query(:logs, "acme", fresh: true)
    assert length(stored) == 8

    for {id, exception, _} <- expected do
      assert Map.fetch!(records, id)["event"]["exception"] == %{"values" => [exception]}
    end

    for record <- stored do
      assert record.body == Map.fetch!(records, record.resource["error_event_id"])["event"]
    end

    before_requests = Agent.get(agent, & &1.requests)

    for route <- ["store", "envelope"] do
      body = if route == "store", do: "{}", else: envelope(%{})

      assert :post
             |> Plug.Test.conn("/api/42/#{route}/?sentry_key=invalid", body)
             |> PulseWeb.Endpoint.call([])
             |> json_response(403)
    end

    assert Agent.get(agent, & &1.requests) == before_requests

    groups =
      Enum.group_by(expected, &elem(&1, 2), fn {id, _, _} -> Map.fetch!(records, id)["issue_id"] end)

    assert Enum.all?(groups, fn {_, ids} -> length(Enum.uniq(ids)) == 1 end)
    assert groups |> Map.values() |> List.flatten() |> Enum.uniq() |> length() == 2
    assert %{"results" => issues} = query("list_error_issues")
    assert Enum.sort(Enum.map(issues, & &1["count"])) == [4, 4]
  end

  @tag :s3
  @tag :sentry_stacktrace_alias
  test "exception stacktrace aliases preserve canonical presence exact names and custom fingerprints" do
    stack = %{"frames" => [%{"function" => "selected", "filename" => "payment.ex"}]}
    other = %{"frames" => [%{"function" => "ignored", "filename" => "other.ex"}]}

    pairs = [
      {%{"stacktrace" => nil, "sentry.interfaces.Stacktrace" => stack}, %{"stacktrace" => nil}, nil},
      {%{"stacktrace" => false, "sentry.interfaces.Stacktrace" => stack}, %{"stacktrace" => false}, nil},
      {%{"stacktrace" => %{"frames" => []}, "sentry.interfaces.Stacktrace" => stack},
       %{"stacktrace" => %{"frames" => []}}, nil},
      {%{"stacktrace" => stack, "sentry.interfaces.Stacktrace" => other}, %{"stacktrace" => stack}, nil},
      {%{"sentry.interfaces.stacktrace" => stack, "sentry.interfaces.StacktraceExtra" => stack}, %{}, nil},
      {%{"sentry.interfaces.Stacktrace" => other}, %{"stacktrace" => stack}, ["stacktrace-control"]}
    ]

    expected =
      for {{left, right, fingerprint}, pair} <- Enum.with_index(pairs),
          fields <- [left, right],
          route <- ["store", "envelope"] do
        exception = Map.merge(%{"type" => "BoundaryFailure", "value" => "same message"}, fields)

        payload = %{
          "timestamp" => "2026-01-01T00:00:00Z",
          "exception" => [exception],
          "fingerprint" => fingerprint
        }

        body = if route == "store", do: Pulse.JSON.encode!(payload), else: envelope(payload)

        %{"id" => id} =
          :post
          |> Plug.Test.conn("/api/42/#{route}/?sentry_key=#{@key}", body)
          |> PulseWeb.Endpoint.call([])
          |> json_response(200)

        {id, pair, exception, fingerprint}
      end

    assert %{"matched_events" => 24, "results" => results} = query("query_errors")
    records = Map.new(results, &{&1["event_id"], &1})

    for {id, _, exception, fingerprint} <- expected do
      record = Map.fetch!(records, id)
      assert record["event"]["exception"] == [exception]
      assert record["event"]["fingerprint"] == fingerprint
    end

    groups = Enum.group_by(expected, &elem(&1, 1), fn {id, _, _, _} -> Map.fetch!(records, id)["issue_id"] end)
    assert Enum.all?(groups, fn {_, ids} -> length(Enum.uniq(ids)) == 1 end)
  end

  @tag :s3
  @tag :sentry_event_uuid
  test "all pinned UUID valid inputs retain canonical event identities through cold reads", %{config: config} do
    # Relay EventId delegates to uuid 1.28.0 through FromStr at Relay pin
    # a68f1dbec05258cfa27b01059e1c1816d10c7257. Preserve all seventeen literal
    # parse_str calls in uuid/src/parser.rs::test_parse_valid, including repeats.
    inputs = [
      {"67e55044-10b1-426f-9247-bb680e5fe0c8", "67e5504410b1426f9247bb680e5fe0c8"},
      {"67e5504410b1426f9247bb680e5fe0c8", "67e5504410b1426f9247bb680e5fe0c8"},
      {"urn:uuid:67e55044-10b1-426f-9247-bb680e5fe0c8", "67e5504410b1426f9247bb680e5fe0c8"},
      {"{67e55044-10b1-426f-9247-bb680e5fe0c8}", "67e5504410b1426f9247bb680e5fe0c8"},
      {"00000000000000000000000000000000", "00000000000000000000000000000000"},
      {"67e55044-10b1-426f-9247-bb680e5fe0c8", "67e5504410b1426f9247bb680e5fe0c8"},
      {"F9168C5E-CEB2-4faa-B6BF-329BF39FA1E4", "f9168c5eceb24faab6bf329bf39fa1e4"},
      {"67e5504410b1426f9247bb680e5fe0c8", "67e5504410b1426f9247bb680e5fe0c8"},
      {"01020304-1112-2122-3132-414243444546", "01020304111221223132414243444546"},
      {"urn:uuid:67e55044-10b1-426f-9247-bb680e5fe0c8", "67e5504410b1426f9247bb680e5fe0c8"},
      {"URN:UUID:67e55044-10b1-426f-9247-bb680e5fe0c8", "67e5504410b1426f9247bb680e5fe0c8"},
      {"Urn:Uuid:67e55044-10b1-426f-9247-bb680e5fe0c8", "67e5504410b1426f9247bb680e5fe0c8"},
      {"{6d93bade-bd9f-4e13-8914-9474e1e3567b}", "6d93badebd9f4e1389149474e1e3567b"},
      {"URN:UUID:67e55044-10b1-426f-9247-bb680e5fe0c8", "67e5504410b1426f9247bb680e5fe0c8"},
      {"urn:UUID:67e55044-10b1-426f-9247-bb680e5fe0c8", "67e5504410b1426f9247bb680e5fe0c8"},
      {"00000000000000000000000000000000", "00000000000000000000000000000000"},
      {"00000000-0000-0000-0000-000000000000", "00000000000000000000000000000000"}
    ]

    for {input, canonical} <- inputs, route <- ["store", "envelope"] do
      payload = event(%{"event_id" => input})
      body = if route == "store", do: Pulse.JSON.encode!(payload), else: envelope(payload)

      assert %{"id" => ^canonical, "discarded_items" => %{}} =
               :post
               |> Plug.Test.conn("/api/42/#{route}/?sentry_key=#{@key}", body)
               |> PulseWeb.Endpoint.call([])
               |> json_response(200)
    end

    {:ok, owner} = ManifestOwner.ensure_started("acme", "logs", config)
    :ok = GenServer.stop(owner)
    ManifestCache.drop("acme", "logs")

    assert {:ok, stored} = Storage.query(:logs, "acme", fresh: true)
    assert length(stored) == 34

    expected = inputs |> Enum.flat_map(fn {_, id} -> [id, id] end) |> Enum.frequencies()
    assert Enum.frequencies_by(stored, & &1.resource["error_event_id"]) == expected

    for record <- stored do
      assert record.body == event(%{"event_id" => record.resource["error_event_id"]})
    end

    # MCP intentionally deduplicates repeated project/event identities.
    assert %{"matched_events" => 5, "results" => results} = query("query_errors")
    assert Enum.sort(Enum.map(results, & &1["event_id"])) == Enum.sort(Map.keys(expected))
  end

  @tag :s3
  @tag :sentry_event_uuid
  test "event UUID wrappers keep strict grammar and envelope-header precedence", %{agent: agent} do
    dashed = "67e55044-10b1-426f-9247-bb680e5fe0c8"
    canonical = "67e5504410b1426f9247bb680e5fe0c8"

    # Authored grammar boundaries, not additional upstream acceptance rows.
    for input <- [
          "{" <> canonical <> "}",
          "urn:uuid:" <> canonical,
          "urn:uuid:{" <> dashed <> "}",
          "{{" <> dashed <> "}}",
          "urn:uuid:urn:uuid:" <> dashed,
          "{67e550441-0b1-426f-9247-bb680e5fe0c8}",
          "urn:uuid:g7e55044-10b1-426f-9247-bb680e5fe0c8",
          "uuid:urn:" <> dashed,
          " " <> dashed,
          "{" <> dashed <> "}\n"
        ],
        route <- ["store", "envelope"] do
      payload = event(%{"event_id" => input})
      body = if route == "store", do: Pulse.JSON.encode!(payload), else: envelope(payload)
      before = Agent.get(agent, & &1.requests)

      assert %{"error" => "invalid_event_id"} =
               :post
               |> Plug.Test.conn("/api/42/#{route}/?sentry_key=#{@key}", body)
               |> PulseWeb.Endpoint.call([])
               |> json_response(400)

      assert Agent.get(agent, & &1.requests) == before
    end

    before = Agent.get(agent, & &1.requests)

    for route <- ["store", "envelope"] do
      payload = event(%{"event_id" => "urn:uuid:" <> dashed})
      body = if route == "store", do: Pulse.JSON.encode!(payload), else: envelope(payload)

      assert :post
             |> Plug.Test.conn("/api/42/#{route}/?sentry_key=wrong", body)
             |> PulseWeb.Endpoint.call([])
             |> json_response(403)

      assert Agent.get(agent, & &1.requests) == before
    end

    assert %{"error" => "invalid_event_id"} =
             event() |> envelope(%{"event_id" => "invalid"}) |> send_envelope() |> json_response(400)

    assert Agent.get(agent, & &1.requests) == before

    trace = %{"trace_id" => "urn:uuid:" <> dashed, "span_id" => dashed}

    assert %{"id" => ^canonical} =
             event(%{"event_id" => "invalid", "contexts" => %{"trace" => trace}})
             |> envelope(%{"event_id" => "Urn:Uuid:" <> dashed})
             |> send_envelope()
             |> json_response(200)

    assert {:ok, [record]} = Storage.query(:logs, "acme", fresh: true)
    assert record.body["event_id"] == canonical
    assert record.resource["error_event_id"] == canonical
    assert record.body["contexts"] == %{"trace" => trace}
    assert record.trace_id == nil
    assert record.span_id == nil
  end

  @tag :s3
  @tag :sentry_trace_uuid
  test "trace correlation normalizes canonical UUID and hex IDs through cold reads", %{config: config} do
    # Independently authored interoperability cases. Relay's active formatting
    # contract is protocol/contexts/trace.rs:562-615 at
    # a68f1dbec05258cfa27b01059e1c1816d10c7257; no FSL Rust test is copied.
    # This does not establish all TraceId spellings or nil-ID repair semantics.
    expected =
      for {trace, projected} <- [
            {"A1039B7C-2468-4ACE-9F01-23456789ABCD", "a1039b7c24684ace9f0123456789abcd"},
            {"b2048c6d-1357-4bdf-8e02-abcdef012345", "b2048c6d13574bdf8e02abcdef012345"},
            {"C3059D7E24684ACE9F03123456789ABC", "c3059d7e24684ace9f03123456789abc"},
            {"d406ae8f13574bdf8e04abcdef012345", "d406ae8f13574bdf8e04abcdef012345"}
          ],
          route <- ["store", "envelope"] do
        context = %{"trace_id" => trace, "type" => "trace"}

        payload = %{
          "timestamp" => "2026-01-01T00:00:00Z",
          "message" => "trace formatting",
          "contexts" => %{"trace" => context}
        }

        body = if route == "store", do: Pulse.JSON.encode!(payload), else: envelope(payload)

        %{"id" => id} =
          :post
          |> Plug.Test.conn("/api/42/#{route}/?sentry_key=#{@key}", body)
          |> PulseWeb.Endpoint.call([])
          |> json_response(200)

        {id, context, projected}
      end

    {:ok, owner} = ManifestOwner.ensure_started("acme", "logs", config)
    :ok = GenServer.stop(owner)
    ManifestCache.drop("acme", "logs")

    assert %{"matched_events" => 8, "results" => results} = query("query_errors")
    records = Map.new(results, &{&1["event_id"], &1})

    for {id, context, projected} <- expected do
      record = Map.fetch!(records, id)
      assert record["trace_id"] == projected
      assert record["span_id"] == nil
      assert record["event"]["contexts"] == %{"trace" => context}
    end

    assert {:ok, stored} = Storage.query(:logs, "acme", fresh: true)
    assert length(stored) == 8

    for record <- stored do
      assert record.trace_id == Map.fetch!(records, record.resource["error_event_id"])["trace_id"]
      assert record.body == Map.fetch!(records, record.resource["error_event_id"])["event"]
    end

    assert %{"results" => [%{"title" => "trace formatting", "count" => 8}]} = query("list_error_issues")
  end

  @tag :s3
  @tag :sentry_trace_uuid
  test "trace UUID projection keeps strict hyphen positions span grammar and source fields", %{agent: agent} do
    # Authored boundaries, not extra upstream TraceId acceptance rows.
    canonical = "b1e2a9dc9b8e4cd0af0e80e6b83b56e6"
    uuid = "b1e2a9dc-9b8e-4cd0-af0e-80e6b83b56e6"

    expected =
      for {trace, span, trace_id, span_id} <- [
            {String.upcase(uuid), "FA90FDEAD5F74052", canonical, "fa90fdead5f74052"},
            {"b1e2a9dc9-b8e4-cd0a-f0e8-0e6b83b56e6", "FA90FDEAD5F74052", nil, "fa90fdead5f74052"},
            {"g1e2a9dc-9b8e-4cd0-af0e-80e6b83b56e6", "fa90fdead5f74052", nil, "fa90fdead5f74052"},
            {"{" <> canonical <> "}", uuid, nil, nil},
            {nil, nil, nil, nil},
            {42, ["span"], nil, nil},
            {String.upcase(canonical), "", canonical, nil},
            {uuid, "ga90fdead5f74052", canonical, nil}
          ],
          route <- ["store", "envelope"] do
        context = %{"trace_id" => trace, "span_id" => span}

        payload = %{
          "timestamp" => "2026-01-01T00:00:00Z",
          "message" => "correlation controls",
          "fingerprint" => ["trace-projection"],
          "contexts" => %{"trace" => context}
        }

        body = if route == "store", do: Pulse.JSON.encode!(payload), else: envelope(payload)

        %{"id" => id} =
          :post
          |> Plug.Test.conn("/api/42/#{route}/?sentry_key=#{@key}", body)
          |> PulseWeb.Endpoint.call([])
          |> json_response(200)

        {id, context, trace_id, span_id}
      end

    assert %{"matched_events" => 16, "results" => results} = query("query_errors")
    records = Map.new(results, &{&1["event_id"], &1})

    for {id, context, trace_id, span_id} <- expected do
      record = Map.fetch!(records, id)
      assert {record["trace_id"], record["span_id"]} == {trace_id, span_id}
      assert record["event"]["contexts"] == %{"trace" => context}
      assert record["event"]["fingerprint"] == ["trace-projection"]
    end

    assert %{"results" => [%{"title" => "correlation controls", "count" => 16}]} = query("list_error_issues")
    before_requests = Agent.get(agent, & &1.requests)

    for route <- ["store", "envelope"] do
      payload = %{"contexts" => %{"trace" => %{"trace_id" => uuid}}}
      body = if route == "store", do: Pulse.JSON.encode!(payload), else: envelope(payload)

      assert :post
             |> Plug.Test.conn("/api/42/#{route}/?sentry_key=invalid", body)
             |> PulseWeb.Endpoint.call([])
             |> json_response(403)
    end

    assert Agent.get(agent, & &1.requests) == before_requests
  end

  for {name, canonical, legacy, cases} <- [
        {"message", "logentry", "sentry.interfaces.Message",
         [
           {"hi", "hi"},
           {%{"message" => "hello, %s!"}, "hello, %s!"},
           {%{"message" => "hello, world!"}, "hello, world!"},
           {%{"message" => "hello, world!", "formatted" => "hello, world!"}, "hello, world!"}
         ]},
        {"exception", "exception", "sentry.interfaces.Exception",
         [
           {%{"type" => "mytype", "value" => "myvalue", "module" => "mymodule", "thread_id" => 42, "other" => "value"},
            "mytype: myvalue"}
         ]}
      ] do
    @tag :s3
    @tag :sentry_legacy_titles
    test "Relay legacy #{name} interface retains canonical titles and groups", %{config: config, agent: agent} do
      # Relay a68f1dbec05258cfa27b01059e1c1816d10c7257:
      # protocol/logentry.rs:178-191, normalization/logentry.rs:156-190 and
      # protocol/exception.rs:89-117 retain the complete selected input values.
      # protocol/event.rs:218,364 declares the legacy aliases. HTTP routes,
      # title/group equivalence and persistence are authored Pulse consumers,
      # not original Relay grouping oracles or full normalization parity.
      expected =
        for {value, title} <- unquote(Macro.escape(cases)),
            field <- [unquote(canonical), unquote(legacy)],
            route <- ["store", "envelope"] do
          fields = %{field => value}
          payload = Map.put(fields, "timestamp", "2026-01-01T00:00:00Z")
          body = if route == "store", do: Pulse.JSON.encode!(payload), else: envelope(payload)

          %{"id" => id} =
            :post
            |> Plug.Test.conn("/api/42/#{route}/?sentry_key=#{@key}", body)
            |> PulseWeb.Endpoint.call([])
            |> json_response(200)

          {id, fields, title}
        end

      {:ok, owner} = ManifestOwner.ensure_started("acme", "logs", config)
      :ok = GenServer.stop(owner)
      ManifestCache.drop("acme", "logs")

      assert %{"matched_events" => count, "results" => issues} = query("list_error_issues")
      assert count == length(expected)
      assert Map.new(issues, &{&1["title"], &1["count"]}) == Enum.frequencies_by(expected, &elem(&1, 2))
      assert length(issues) == length(Enum.uniq_by(expected, &elem(&1, 2)))
      issue_ids = Map.new(issues, &{&1["title"], &1["issue_id"]})
      assert %{"results" => results} = query("query_errors")
      records = Map.new(results, &{&1["event_id"], &1})

      for {id, fields, title} <- expected do
        record = Map.fetch!(records, id)
        assert Map.take(record["event"], Map.keys(fields)) == fields
        assert record["issue_id"] == Map.fetch!(issue_ids, title)
      end

      assert {:ok, stored} = Storage.query(:logs, "acme", fresh: true)
      assert length(stored) == length(expected)

      for record <- stored do
        assert record.body == Map.fetch!(records, record.resource["error_event_id"])["event"]
      end

      assert Agent.get(agent, & &1.reads) != []
    end
  end

  @tag :s3
  @tag :sentry_legacy_titles
  test "legacy title aliases preserve canonical presence privacy and custom fingerprints", %{agent: agent} do
    # Authored boundary controls; canonical field presence wins over aliases
    # even for null/invalid values, as in relay-protocol-derive/src/lib.rs:407-420.
    inner = %{"type" => "Inner", "value" => "selected", "stacktrace" => %{"frames" => [%{"function" => "run"}]}}

    cases = [
      {%{"logentry" => "canonical", "sentry.interfaces.Message" => "alias"}, "canonical"},
      {%{"logentry" => nil, "sentry.interfaces.Message" => "alias"}, "fallback"},
      {%{"logentry" => false, "sentry.interfaces.Message" => "alias"}, "fallback"},
      {%{"sentry.interfaces.Message" => %{"formatted" => ""}}, ""},
      {%{"sentry.interfaces.Message" => %{"formatted" => nil, "message" => "alias"}}, "alias"},
      {%{"sentry.interfaces.message" => "not-an-alias"}, "fallback"},
      {%{"sentry.interfaces.Exception" => [%{"value" => "outer"}, inner]}, "Inner: selected"},
      {%{"sentry.interfaces.Exception" => %{"values" => [%{"value" => "outer"}, inner]}}, "Inner: selected"},
      {%{"sentry.interfaces.Exception" => %{"value" => %{"token" => "secret-value"}}}, ~s({"token":"[Filtered]"})},
      {%{"exception" => nil, "sentry.interfaces.Exception" => inner}, "fallback"},
      {%{"exception" => false, "sentry.interfaces.Exception" => inner}, "fallback"},
      {%{"exception" => inner, "sentry.interfaces.Exception" => %{"value" => "alias"}}, "Inner: selected"},
      {%{"sentry.interfaces.ExceptionExtra" => inner}, "fallback"},
      {%{"sentry.interfaces.Message" => String.duplicate("é", 600)}, String.duplicate("é", 500)}
    ]

    ids =
      for {fields, title} <- cases, route <- ["store", "envelope"] do
        payload =
          Map.merge(
            %{"timestamp" => "2026-01-01T00:00:00Z", "message" => "fallback", "fingerprint" => ["alias-control"]},
            fields
          )

        body = if route == "store", do: Pulse.JSON.encode!(payload), else: envelope(payload)

        %{"id" => id} =
          :post
          |> Plug.Test.conn("/api/42/#{route}/?sentry_key=#{@key}", body)
          |> PulseWeb.Endpoint.call([])
          |> json_response(200)

        assert %{"results" => [issue]} = query("list_error_issues", %{"event_id" => id})
        assert issue["title"] == title
        assert %{"results" => [record]} = query("query_errors", %{"event_id" => id})
        assert record["event"]["fingerprint"] == ["alias-control"]
        refute Pulse.JSON.encode!(record["event"]) =~ "secret-value"
        issue["issue_id"]
      end

    assert length(Enum.uniq(ids)) == 1
    before_requests = Agent.get(agent, & &1.requests)

    for route <- ["store", "envelope"] do
      payload = %{"sentry.interfaces.Exception" => inner}
      body = if route == "store", do: Pulse.JSON.encode!(payload), else: envelope(payload)

      assert :post
             |> Plug.Test.conn("/api/42/#{route}/?sentry_key=invalid", body)
             |> PulseWeb.Endpoint.call([])
             |> json_response(403)
    end

    assert Agent.get(agent, & &1.requests) == before_requests
  end

  @tag :s3
  @tag :sentry_legacy_privacy
  test "Relay legacy user and HTTP interfaces receive canonical privacy filtering", %{config: config, agent: agent} do
    # Complete roundtrip input values from pinned Relay
    # a68f1dbec05258cfa27b01059e1c1816d10c7257, protocol/user.rs:143-186
    # and protocol/request.rs:634-723; JSON whitespace is adapted.
    # protocol/event.rs:345-351 identifies the equivalent legacy field names.
    # Filtering, routes and cold S3/MCP expectations are Pulse policy controls,
    # not upstream Relay privacy oracles or full normalization parity.
    user =
      Pulse.JSON.decode!(~s({
        "id":"e4e24881-8238-4539-a32b-d3c3ecd40568","email":"mail@example.org",
        "ip_address":"{{auto}}","username":"john_doe","name":"John Doe",
        "segment":"vip","data":{"data":"value"},"other":"value"
      }))

    request =
      Pulse.JSON.decode!(~s({
        "url":"https://google.com/search","method":"GET","data":{"some":1},
        "query_string":[["q","foo"]],"fragment":"home","cookies":[["GOOGLE","1"]],
        "headers":[["Referer","https://google.com/"]],"body_size":1024,
        "env":{"REMOTE_ADDR":"213.47.147.207"},"inferred_content_type":"application/json",
        "api_target":"graphql","other":"value"
      }))

    expected =
      for {fields, value} <- [
            {["user", "sentry.interfaces.User"], user},
            {["request", "sentry.interfaces.Http"], request}
          ],
          field <- fields,
          route <- ["store", "envelope"] do
        payload = %{
          "timestamp" => "2026-01-01T00:00:00Z",
          "message" => "legacy privacy",
          field => value
        }

        body = if route == "store", do: Pulse.JSON.encode!(payload), else: envelope(payload)

        %{"id" => id} =
          :post
          |> Plug.Test.conn("/api/42/#{route}/?sentry_key=#{@key}", body)
          |> PulseWeb.Endpoint.call([])
          |> json_response(200)

        {id, field}
      end

    {:ok, owner} = ManifestOwner.ensure_started("acme", "logs", config)
    :ok = GenServer.stop(owner)
    ManifestCache.drop("acme", "logs")

    assert %{"matched_events" => 8, "results" => results} = query("query_errors")
    records = Map.new(results, &{&1["event_id"], &1["event"]})

    for {id, field} <- expected do
      assert Map.fetch!(records, id)[field] == "[Filtered]"
    end

    # This storage read proves the policy is applied before persistence, not
    # merely hidden by a query response serializer.
    assert {:ok, stored} = Storage.query(:logs, "acme", fresh: true)
    assert length(stored) == 8

    for record <- stored do
      assert record.body == Map.fetch!(records, record.resource["error_event_id"])
    end

    assert %{"results" => [%{"title" => "legacy privacy", "count" => 8}]} = query("list_error_issues")
    assert Agent.get(agent, & &1.reads) != []
  end

  @tag :s3
  @tag :sentry_legacy_privacy
  test "legacy interface privacy stays recursive exact-name and before title rendering", %{agent: agent} do
    fields = %{
      "user" => %{"email" => "canonical-private"},
      "sentry.interfaces.User" => %{"email" => "legacy-private"},
      "request" => "canonical-request-private",
      "sentry.interfaces.Http" => ["legacy-request-private"],
      "extra" => %{
        "nested" => [
          %{"SENTRY.INTERFACES.USER" => nil, "safe" => "retained"},
          %{"sentry.interfaces.http" => 123}
        ],
        "sentry.interfaces.UserExtra" => %{"email" => "not-an-interface"},
        "token" => "credential-private"
      },
      "exception" => %{"value" => %{"sentry.interfaces.User" => %{"email" => "title-private"}}},
      "fingerprint" => ["privacy-control"]
    }

    for route <- ["store", "envelope"] do
      payload = Map.put(fields, "timestamp", "2026-01-01T00:00:00Z")
      body = if route == "store", do: Pulse.JSON.encode!(payload), else: envelope(payload)

      %{"id" => id} =
        :post
        |> Plug.Test.conn("/api/42/#{route}/?sentry_key=#{@key}", body)
        |> PulseWeb.Endpoint.call([])
        |> json_response(200)

      assert %{"results" => [record]} = query("query_errors", %{"event_id" => id})
      retained = record["event"]

      assert Map.take(retained, ~w(user request sentry.interfaces.User sentry.interfaces.Http)) ==
               Map.new(~w(user request sentry.interfaces.User sentry.interfaces.Http), &{&1, "[Filtered]"})

      assert retained["extra"] == %{
               "nested" => [
                 %{"SENTRY.INTERFACES.USER" => "[Filtered]", "safe" => "retained"},
                 %{"sentry.interfaces.http" => "[Filtered]"}
               ],
               "sentry.interfaces.UserExtra" => %{"email" => "not-an-interface"},
               "token" => "[Filtered]"
             }

      assert retained["fingerprint"] == ["privacy-control"]
      assert %{"results" => [issue]} = query("list_error_issues", %{"event_id" => id})
      assert issue["title"] == ~s({"sentry.interfaces.User":"[Filtered]"})
      refute Pulse.JSON.encode!(retained) =~ "-private"
    end

    assert %{"results" => [%{"count" => 2}]} = query("list_error_issues")
    before = Agent.get(agent, & &1.requests)

    for route <- ["store", "envelope"] do
      body = if route == "store", do: Pulse.JSON.encode!(fields), else: envelope(fields)

      assert :post
             |> Plug.Test.conn("/api/42/#{route}/?sentry_key=invalid", body)
             |> PulseWeb.Endpoint.call([])
             |> json_response(403)
    end

    assert Agent.get(agent, & &1.requests) == before
  end

  @tag :s3
  @tag :sentry_message_object
  test "Relay message-only logentries retain titles through the legacy message field", %{config: config, agent: agent} do
    # Relay a68f1dbec05258cfa27b01059e1c1816d10c7257:
    # relay-event-normalization/src/logentry.rs:156-190, complete
    # test_format_no_params, test_only_message and test_message_formatted_equal,
    # preserve these strings as formatted.
    # event-schema/src/protocol/event.rs:218 aliases message to logentry.
    # HTTP fields/routes, titles and Pulse grouping are authored consumers of
    # those normalization oracles, not original Relay ingestion/grouping tests.
    cases = [
      {%{"message" => "hello, %s!"}, "hello, %s!"},
      {%{"message" => "hello, world!"}, "hello, world!"},
      {%{"message" => "hello, world!", "formatted" => "hello, world!"}, "hello, world!"}
    ]

    expected =
      for {entry, title} <- cases, field <- ["message", "logentry"], route <- ["store", "envelope"] do
        fields = %{field => entry}
        payload = Map.put(fields, "timestamp", "2026-01-01T00:00:00Z")
        body = if route == "store", do: Pulse.JSON.encode!(payload), else: envelope(payload)

        %{"id" => id} =
          :post
          |> Plug.Test.conn("/api/42/#{route}/?sentry_key=#{@key}", body)
          |> PulseWeb.Endpoint.call([])
          |> json_response(200)

        {id, fields, title}
      end

    {:ok, owner} = ManifestOwner.ensure_started("acme", "logs", config)
    :ok = GenServer.stop(owner)
    ManifestCache.drop("acme", "logs")

    assert %{"matched_events" => 12, "results" => issues} = query("list_error_issues")
    assert Map.new(issues, &{&1["title"], &1["count"]}) == %{"hello, %s!" => 4, "hello, world!" => 8}
    assert length(issues) == 2
    issue_ids = Map.new(issues, &{&1["title"], &1["issue_id"]})
    assert %{"matched_events" => 12, "results" => results} = query("query_errors")
    records = Map.new(results, &{&1["event_id"], &1})

    for {id, fields, title} <- expected do
      record = Map.fetch!(records, id)
      assert Map.take(record["event"], Map.keys(fields)) == fields
      assert record["issue_id"] == Map.fetch!(issue_ids, title)
    end

    assert Agent.get(agent, & &1.reads) != []
  end

  @tag :s3
  @tag :sentry_message_json
  test "nonobject logentries use JSON display text without rewriting retained values", %{config: config, agent: agent} do
    # Independently authored inputs for Relay a68f1dbec05258cfa27b01059e1c1816d10c7257,
    # protocol/logentry.rs:119-134 and protocol/types.rs JsonLenientString.
    # These exercise the declared conversion, not copied upstream test rows.
    cases = [{true, "true"}, {47, "47"}, {-2.5, "-2.5"}, {[], "[]"}, {["é", nil, true], ~s(["é",null,true])}]

    expected =
      for {value, title} <- cases,
          value <- [value, title],
          field <- ["message", "logentry", "sentry.interfaces.Message"],
          route <- ["store", "envelope"] do
        fields = %{field => value}
        payload = Map.put(fields, "timestamp", "2026-01-01T00:00:00Z")
        body = if route == "store", do: Pulse.JSON.encode!(payload), else: envelope(payload)

        %{"id" => id} =
          :post
          |> Plug.Test.conn("/api/42/#{route}/?sentry_key=#{@key}", body)
          |> PulseWeb.Endpoint.call([])
          |> json_response(200)

        {id, fields, title}
      end

    {:ok, owner} = ManifestOwner.ensure_started("acme", "logs", config)
    :ok = GenServer.stop(owner)
    ManifestCache.drop("acme", "logs")

    assert %{"matched_events" => 60, "results" => issues} = query("list_error_issues")
    assert Map.new(issues, &{&1["title"], &1["count"]}) == Map.new(cases, fn {_, title} -> {title, 12} end)
    issues = Map.new(issues, &{&1["issue_id"], &1})
    assert %{"matched_events" => 60, "results" => results} = query("query_errors")
    records = Map.new(results, &{&1["event_id"], &1})

    for {id, fields, title} <- expected do
      record = Map.fetch!(records, id)
      assert Map.fetch!(issues, record["issue_id"])["title"] == title
      assert Map.take(record["event"], Map.keys(fields)) == fields
    end

    assert Agent.get(agent, & &1.reads) != []
  end

  @tag :s3
  @tag :sentry_message_json
  test "JSON message projection preserves fallback, privacy, bounds and literal fingerprints", %{agent: agent} do
    cases = [
      {%{"logentry" => false, "message" => "fallback"}, "fallback"},
      {%{"logentry" => nil, "sentry.interfaces.Message" => true}, "Error"},
      {%{"logentry" => "", "message" => true}, ""},
      {%{"logentry" => %{"formatted" => false, "message" => 42}, "message" => "fallback"}, "fallback"},
      {%{"logentry" => true, "exception" => %{"type" => "Typed", "value" => "selected"}}, "Typed: selected"},
      {%{"message" => [%{"password" => "private", "safe" => true}]}, ~s([{"password":"[Filtered]","safe":true}])},
      {%{"message" => [String.duplicate("é", 600)]}, "[\"" <> String.duplicate("é", 498)}
    ]

    for {fields, title} <- cases do
      payload =
        fields
        |> Map.put("timestamp", "2026-01-01T00:00:00Z")
        |> Map.put("fingerprint", ["literal-json-message"])

      %{"id" => id} = payload |> envelope() |> send_envelope() |> json_response(200)
      assert %{"results" => [issue]} = query("list_error_issues", %{"event_id" => id})
      assert issue["title"] == title
      assert %{"results" => [record]} = query("query_errors", %{"event_id" => id})
      assert record["event"]["fingerprint"] == ["literal-json-message"]
      refute Pulse.JSON.encode!(record["event"]) =~ "private"
    end

    assert %{"results" => [%{"count" => 7}]} = query("list_error_issues")
    before = Agent.get(agent, & &1.requests)

    for route <- ["store", "envelope"] do
      fields = %{"message" => [true]}
      body = if route == "store", do: Pulse.JSON.encode!(fields), else: envelope(fields)

      assert :post
             |> Plug.Test.conn("/api/42/#{route}/?sentry_key=invalid", body)
             |> PulseWeb.Endpoint.call([])
             |> json_response(403)
    end

    assert Agent.get(agent, & &1.requests) == before
  end

  @tag :s3
  @tag :sentry_message_object
  test "legacy message objects preserve priority, scrubbing and title bounds", %{agent: agent} do
    cases = [
      {%{"message" => %{"message" => "template", "formatted" => "rendered"}}, "rendered"},
      {%{"message" => %{"message" => "template", "formatted" => ""}}, ""},
      {%{"message" => %{"message" => "template", "formatted" => nil}}, "template"},
      {%{"message" => %{"message" => "legacy"}, "logentry" => %{"message" => "explicit"}}, "explicit"},
      {%{"message" => %{"message" => "legacy"}, "exception" => %{"type" => "Typed", "value" => "exception"}},
       "Typed: exception"},
      {%{"message" => %{"message" => "safe", "password" => "do-not-keep"}}, "safe"},
      {%{"message" => %{"message" => 123}}, "Error"},
      {%{"message" => %{"message" => String.duplicate("é", 600)}}, String.duplicate("é", 500)}
    ]

    for {{fields, title}, index} <- Enum.with_index(cases) do
      payload =
        fields
        |> Map.put("timestamp", "2026-01-01T00:00:00Z")
        |> Map.put("fingerprint", ["message-object-control-#{index}"])

      %{"id" => id} = payload |> envelope() |> send_envelope() |> json_response(200)
      assert %{"results" => [issue]} = query("list_error_issues", %{"event_id" => id})
      assert issue["title"] == title
      assert %{"results" => [record]} = query("query_errors", %{"event_id" => id})

      retained = Map.replace(fields["message"], "password", "[Filtered]")
      assert record["event"]["message"] == retained
    end

    before = Agent.get(agent, & &1.requests)

    for route <- ["store", "envelope"] do
      payload = %{"message" => %{"message" => "unauthorized"}}
      body = if route == "store", do: Pulse.JSON.encode!(payload), else: envelope(payload)

      assert :post
             |> Plug.Test.conn("/api/42/#{route}/?sentry_key=invalid", body)
             |> PulseWeb.Endpoint.call([])
             |> json_response(403)
    end

    assert Agent.get(agent, & &1.requests) == before
  end

  @tag :s3
  @tag :sentry_exception_json
  test "Relay object exception values supply titles without rewriting scrubbed events", %{config: config, agent: agent} do
    # Complete test_coerces_object_value_to_string, exception.rs:145-156,
    # Relay a68f1dbec05258cfa27b01059e1c1816d10c7257:
    # {"value":{"unauthorized":true}} becomes {"value":"{\"unauthorized\":true}"}.
    # Wrapped events, string counterparts and HTTP/MCP results are authored
    # consumers; the remaining values exercise the source JsonLenientString rule.
    cases = [
      {%{"unauthorized" => true}, ~s({"unauthorized":true})},
      {%{"z" => [nil, 3, true, %{"b" => 2, "a" => "é"}], "a" => false},
       ~s({"a":false,"z":[null,3,true,{"a":"é","b":2}]})},
      {[1, false, nil, "é"], ~s([1,false,null,"é"])},
      {true, "true"},
      {false, "false"},
      {42, "42"},
      {[], "[]"},
      {%{}, "{}"}
    ]

    expected =
      for {original, rendered} <- cases, value <- [original, rendered], route <- ["store", "envelope"] do
        fields = %{"exception" => %{"values" => [%{"value" => value}]}}
        payload = Map.put(fields, "timestamp", "2026-01-01T00:00:00Z")
        body = if route == "store", do: Pulse.JSON.encode!(payload), else: envelope(payload)

        response =
          :post
          |> Plug.Test.conn("/api/42/#{route}/?sentry_key=#{@key}", body)
          |> PulseWeb.Endpoint.call([])

        %{"id" => id} = json_response(response, 200)
        {id, fields, rendered}
      end

    {:ok, owner} = ManifestOwner.ensure_started("acme", "logs", config)
    :ok = GenServer.stop(owner)
    ManifestCache.drop("acme", "logs")

    assert %{"matched_events" => 32, "results" => issues} = query("list_error_issues")
    assert Map.new(issues, &{&1["title"], &1["count"]}) == Map.new(cases, fn {_, title} -> {title, 4} end)
    issue_ids = Map.new(issues, &{&1["title"], &1["issue_id"]})
    assert %{"matched_events" => 32, "results" => results} = query("query_errors")
    records = Map.new(results, &{&1["event_id"], &1})

    for {id, fields, title} <- expected do
      record = Map.fetch!(records, id)
      assert record["event"]["exception"] == fields["exception"]
      assert record["issue_id"] == Map.fetch!(issue_ids, title)
    end

    assert Agent.get(agent, & &1.reads) != []
  end

  @tag :s3
  @tag :sentry_exception_json
  test "JSON exception titles preserve scrubbing, fallback, truncation and authentication", %{agent: agent} do
    cases = [
      {%{"value" => %{"password" => "do-not-keep", "safe" => true}},
       %{"value" => %{"password" => "[Filtered]", "safe" => true}}, ~s({"password":"[Filtered]","safe":true})},
      {%{"type" => "Fallback", "value" => nil}, %{"type" => "Fallback", "value" => nil}, "Fallback: fallback"},
      {%{"type" => "Empty", "value" => ""}, %{"type" => "Empty", "value" => ""}, "Empty: "},
      {%{"type" => "Typed", "value" => false}, %{"type" => "Typed", "value" => false}, "Typed: false"},
      {%{"value" => [String.duplicate("é", 600)]}, %{"value" => [String.duplicate("é", 600)]},
       "[\"" <> String.duplicate("é", 498)}
    ]

    for {{exception, retained, title}, index} <- Enum.with_index(cases) do
      payload = %{
        "timestamp" => "2026-01-01T00:00:00Z",
        "exception" => exception,
        "message" => "fallback",
        "fingerprint" => ["json-control-#{index}"]
      }

      %{"id" => id} = payload |> envelope() |> send_envelope() |> json_response(200)
      assert %{"results" => [record]} = query("query_errors", %{"event_id" => id})
      assert record["event"]["exception"] == retained
      assert %{"results" => [issue]} = query("list_error_issues", %{"event_id" => id})
      assert issue["title"] == title
      refute issue["title"] =~ "do-not-keep"
    end

    before = Agent.get(agent, & &1.requests)

    for route <- ["store", "envelope"] do
      payload = %{"exception" => %{"value" => %{"unauthorized" => true}}}
      body = if route == "store", do: Pulse.JSON.encode!(payload), else: envelope(payload)

      assert :post
             |> Plug.Test.conn("/api/42/#{route}/?sentry_key=invalid", body)
             |> PulseWeb.Endpoint.call([])
             |> json_response(403)
    end

    assert Agent.get(agent, & &1.requests) == before
  end

  @tag :s3
  @tag :sentry_release_scalars
  test "Relay numeric release oracle remains searchable without rewriting raw events", %{config: config, agent: agent} do
    # Complete test_lenient_release, event.rs:1037-1049, Relay
    # a68f1dbec05258cfa27b01059e1c1816d10c7257: {"release":42}
    # decodes as {"release":"42"}. HTTP/MCP consumers and remaining
    # scalar/boundary cases below are authored adaptations and controls.
    cases = [
      {42, "42"},
      {"42", "42"},
      {-22, "-22"},
      {true, "True"},
      {false, "False"},
      {3.5, "3"},
      {-0.9, "-0"},
      {-9_223_372_036_854_775_808, "-9223372036854775808"},
      {18_446_744_073_709_551_615, "18446744073709551615"},
      {String.duplicate("r", 257), String.duplicate("r", 257)},
      {nil, ""},
      {[], ""},
      {%{}, ""},
      {9_007_199_254_740_992.0, ""}
    ]

    expected =
      for {release, normalized} <- cases, route <- ["store", "envelope"] do
        payload = %{"timestamp" => "2026-01-01T00:00:00Z", "message" => "release oracle", "release" => release}
        body = if route == "store", do: Pulse.JSON.encode!(payload), else: envelope(payload)

        response =
          :post
          |> Plug.Test.conn("/api/42/#{route}/?sentry_key=#{@key}", body)
          |> PulseWeb.Endpoint.call([])

        assert response.status == 200, inspect({route, release, response.resp_body})
        %{"id" => id} = json_response(response, 200)
        {id, release, normalized}
      end

    {:ok, owner} = ManifestOwner.ensure_started("acme", "logs", config)
    :ok = GenServer.stop(owner)
    ManifestCache.drop("acme", "logs")
    assert %{"matched_events" => 28, "results" => results} = query("query_errors")
    records = Map.new(results, &{&1["event_id"], &1})

    for {id, original, _normalized} <- expected do
      assert Map.fetch!(records, id)["event"]["release"] === original
    end

    assert query("query_errors", %{"release" => "42"})["matched_events"] == 4

    for {release, rows} <- Enum.group_by(expected, &elem(&1, 2)) do
      ids = rows |> Enum.map(&elem(&1, 0)) |> Enum.sort()
      assert %{"matched_events" => count, "results" => matches} = query("query_errors", %{"release" => release})
      assert count == length(ids)
      assert Enum.sort(Enum.map(matches, & &1["event_id"])) == ids
      assert %{"matched_events" => ^count, "results" => [issue]} = query("list_error_issues", %{"release" => release})
      assert issue["count"] == count
    end

    assert Agent.get(agent, & &1.reads) != []
    before = Agent.get(agent, & &1.requests)

    for route <- ["store", "envelope"] do
      payload = %{"release" => 42}
      body = if route == "store", do: Pulse.JSON.encode!(payload), else: envelope(payload)

      :post
      |> Plug.Test.conn("/api/42/#{route}/?sentry_key=invalid", body)
      |> PulseWeb.Endpoint.call([])
      |> json_response(403)
    end

    assert Agent.get(agent, & &1.requests) == before
  end

  @tag :s3
  @tag :sentry_fingerprint_scalars
  test "Relay fingerprint scalar oracles group like strings without rewriting raw events", %{
    config: config,
    agent: agent
  } do
    # Complete successful fingerprint.rs decoder cases at pinned Relay
    # a68f1dbec05258cfa27b01059e1c1816d10c7257:125-162,198-215.
    # HTTP events and Pulse issue identities are authored consumers, not
    # Relay ingestion or Sentry grouping oracles.
    cases = [
      {~s(["fingerprint"]), ["fingerprint"]},
      {"[true, false]", ["True", "False"]},
      {"[-22]", ["-22"]},
      {"[3.0]", ["3"]},
      {"[3.5]", ["3"]},
      {~s(["a", null, "d"]), ["a", "d"]},
      {"[]", []},
      # Authored signed-zero/negative truncation and integer-width controls.
      {"[-0.0, -0.9, -3.9]", ["-0", "-0", "-3"]},
      {"[-9223372036854775808, 18446744073709551615]", ["-9223372036854775808", "18446744073709551615"]},
      {"[9007199254740991.0, -9007199254740991.0]", ["9007199254740991", "-9007199254740991"]}
    ]

    expected =
      for {source, normalized} <- cases,
          route <- ["store", "envelope"],
          fingerprint <- [Pulse.JSON.decode!(source), normalized] do
        payload = %{
          "timestamp" => "2026-01-01T00:00:00Z",
          "message" => "fingerprint oracle",
          "fingerprint" => fingerprint
        }

        body = if route == "store", do: Pulse.JSON.encode!(payload), else: envelope(payload)

        %{"id" => id} =
          :post
          |> Plug.Test.conn("/api/42/#{route}/?sentry_key=#{@key}", body)
          |> PulseWeb.Endpoint.call([])
          |> json_response(200)

        {id, fingerprint, normalized}
      end

    {:ok, owner} = ManifestOwner.ensure_started("acme", "logs", config)
    :ok = GenServer.stop(owner)
    ManifestCache.drop("acme", "logs")
    assert %{"matched_events" => 40, "results" => results} = query("query_errors")
    records = Map.new(results, &{&1["event_id"], &1})
    assert map_size(records) == 40

    grouped =
      Enum.group_by(expected, &elem(&1, 2), fn {id, fingerprint, _} ->
        record = Map.fetch!(records, id)
        assert record["event"]["fingerprint"] === fingerprint
        record["issue_id"]
      end)

    for {_normalized, ids} <- grouped, do: assert(length(Enum.uniq(ids)) == 1)
    assert grouped |> Map.values() |> Enum.map(&hd/1) |> Enum.uniq() |> length() == map_size(grouped)

    before = Agent.get(agent, & &1.requests)

    # Deliberately keep whole-event rejection for bad components instead of
    # Relay's soft-error stripping. Supplied count/byte limits still apply.
    for fingerprint <- [
          [-1.0e100],
          [1.797_693_134_862_315_7e308],
          [9_007_199_254_740_992.0],
          [-9_007_199_254_740_992.0],
          [-9_223_372_036_854_775_809],
          [18_446_744_073_709_551_616],
          [%{}],
          [[]],
          "not an array",
          [String.duplicate("x", 257)],
          List.duplicate(nil, 33)
        ],
        route <- ["store", "envelope"] do
      payload = %{"timestamp" => "2026-01-01T00:00:00Z", "fingerprint" => fingerprint}
      body = if route == "store", do: Pulse.JSON.encode!(payload), else: envelope(payload)

      assert %{"error" => "invalid_fingerprint"} =
               :post
               |> Plug.Test.conn("/api/42/#{route}/?sentry_key=#{@key}", body)
               |> PulseWeb.Endpoint.call([])
               |> json_response(400)
    end

    assert Agent.get(agent, & &1.requests) == before
  end

  @tag :s3
  @tag :sentry_exception_shapes
  test "Relay exception container oracles share titles and grouping without rewriting events", %{config: config} do
    # Relay a68f1dbec05258cfa27b01059e1c1816d10c7257,
    # types.rs:1078-1119, complete test_values_deserialization. Its three
    # equivalent decoded exceptions are adapted into public HTTP events;
    # titles and Pulse issue identity are authored consumer expectations.
    source_inputs = [
      ~s({"values": [{"type": "Test", "value": "aha!"}]}),
      ~s([{"type": "Test", "value": "aha!"}]),
      ~s({"type": "Test", "value": "aha!"})
    ]

    chain = [
      %{"type" => "Outer", "value" => "not the selected exception"},
      %{
        "type" => "Inner",
        "value" => "selected exception",
        "stacktrace" => %{"frames" => [%{"filename" => "inner.ex", "function" => "run", "in_app" => true}]}
      }
    ]

    inputs =
      Enum.map(source_inputs, &{Pulse.JSON.decode!(&1), "Test: aha!"}) ++
        [{%{"values" => chain}, "Inner: selected exception"}, {chain, "Inner: selected exception"}]

    expected =
      for {exception, title} <- inputs, route <- ["store", "envelope"] do
        event = %{"exception" => exception, "timestamp" => "2026-01-01T00:00:00Z"}
        body = if route == "store", do: Pulse.JSON.encode!(event), else: envelope(event)

        %{"id" => id} =
          :post
          |> Plug.Test.conn("/api/42/#{route}/?sentry_key=#{@key}", body)
          |> PulseWeb.Endpoint.call([])
          |> json_response(200)

        {id, {exception, title}}
      end

    {:ok, owner} = ManifestOwner.ensure_started("acme", "logs", config)
    :ok = GenServer.stop(owner)
    ManifestCache.drop("acme", "logs")

    assert %{"matched_events" => 10, "results" => issues} = query("list_error_issues")
    assert Map.new(issues, &{&1["title"], &1["count"]}) == %{"Test: aha!" => 6, "Inner: selected exception" => 4}
    assert length(issues) == 2
    issue_ids = Map.new(issues, &{&1["title"], &1["issue_id"]})
    assert %{"matched_events" => 10, "results" => results} = query("query_errors")
    records = Map.new(results, &{&1["event_id"], &1})
    assert map_size(records) == length(expected)

    for {id, {exception, title}} <- expected do
      record = Map.fetch!(records, id)
      assert record["event"]["exception"] == exception
      assert record["issue_id"] == Map.fetch!(issue_ids, title)
    end
  end

  @tag :s3
  @tag :sentry_environment_tag
  test "legacy environment tags remain filterable after durable publication", %{agent: agent, config: config} do
    # Independent HTTP adaptations of Relay a68f1dbec05258cfa27b01059e1c1816d10c7257,
    # normalize/mod.rs:797-842: both complete tag-promotion inputs and the
    # empty-without-tag control. Retained events are not Relay-normalized JSON.
    cases = [
      {%{"tags" => [["environment", "despacito"]]}, "despacito"},
      {%{"environment" => "", "tags" => [["environment", "despacito"]]}, "despacito"},
      {%{"environment" => ""}, ""},
      {%{"environment" => "production", "tags" => [["environment", "staging"]]}, "production"},
      {%{"tags" => %{"environment" => "despacito"}}, "despacito"},
      {%{"tags" => [["environment", "first"], ["environment", "second"]]}, "first"},
      {%{"tags" => [["environment", ""], ["environment", "second"]]}, ""},
      {%{"tags" => [["environment", nil], ["environment", "second"]]}, ""},
      {%{"tags" => %{"environment" => "  trimmed  "}}, "trimmed"},
      {%{"tags" => %{"environment" => 42}}, "42"},
      {%{"tags" => %{"environment" => false}}, "False"},
      {%{"tags" => %{"environment" => %{}}}, ""}
    ]

    expected =
      for {fields, environment} <- cases, route <- ["store", "envelope"] do
        payload = Map.merge(%{"message" => "legacy environment", "timestamp" => "2026-01-01T00:00:00Z"}, fields)
        body = if route == "store", do: Pulse.JSON.encode!(payload), else: envelope(payload)

        %{"id" => id} =
          :post
          |> Plug.Test.conn("/api/42/#{route}/?sentry_key=#{@key}", body)
          |> PulseWeb.Endpoint.call([])
          |> json_response(200)

        {id, {payload, environment}}
      end

    {:ok, owner} = ManifestOwner.ensure_started("acme", "logs", config)
    :ok = GenServer.stop(owner)
    ManifestCache.drop("acme", "logs")
    assert %{"matched_events" => 24, "results" => results} = query("query_errors")
    assert %{"matched_events" => 6} = query("query_errors", %{"environment" => "despacito"})
    records = Map.new(results, &{&1["event_id"], &1})
    assert {:ok, logs} = Storage.query(:logs, "acme", start_ts: 0, end_ts: 1_800_000_000_000_000_000)
    environments = Map.new(logs, &{&1.resource["error_event_id"], &1.resource["environment"]})

    for {id, {payload, environment}} <- expected do
      record = Map.fetch!(records, id)
      assert Map.fetch!(environments, id) == environment
      assert Map.delete(record["event"], "event_id") == payload
    end

    assert %{"matched_events" => 2} = query("query_errors", %{"environment" => "production"})
    assert %{"matched_events" => 2} = query("query_errors", %{"environment" => "first"})
    assert %{"matched_events" => 0} = query("query_errors", %{"environment" => "second"})
    assert %{"matched_events" => 0} = query("query_errors", %{"environment" => "staging"})

    before = Agent.get(agent, & &1.requests)

    assert :post
           |> Plug.Test.conn(
             "/api/42/store/?sentry_key=wrong",
             Pulse.JSON.encode!(%{"tags" => %{"environment" => "despacito"}})
           )
           |> PulseWeb.Endpoint.call([])
           |> json_response(403) == %{"error" => "invalid_sentry_key"}

    assert Agent.get(agent, & &1.requests) == before
  end

  @tag :s3
  @tag :sentry_float_timestamp
  test "Relay float timestamp oracles round to microseconds before durable publication", %{agent: agent, config: config} do
    # Relay a68f1dbec05258cfa27b01059e1c1816d10c7257,
    # types.rs:1038-1063, complete test_timestamp_to_datetime.
    # Five nonnegative scalar oracles become HTTP events. Its four negative
    # inputs retain Pulse's deliberate pre-epoch rejection, not Relay parity.
    cases = [
      {0.0, 0},
      {1000.0, 1_000_000_000_000},
      {1.234567, 1_234_567_000},
      {2.99999951, 3_000_000_000},
      {2.99999945, 2_999_999_000},
      # Authored modern-epoch control: round the fractional seconds, not the
      # whole timestamp multiplied into a precision-losing float nanosecond.
      {1_735_689_600.1234567, 1_735_689_600_123_457_000}
    ]

    expected =
      for {input, timestamp} <- cases, route <- ["store", "envelope"] do
        event = %{"message" => "Relay float timestamp oracle", "timestamp" => input}
        body = if route == "store", do: Pulse.JSON.encode!(event), else: envelope(event)

        %{"id" => id} =
          :post
          |> Plug.Test.conn("/api/42/#{route}/?sentry_key=#{@key}", body)
          |> PulseWeb.Endpoint.call([])
          |> json_response(200)

        {id, {input, timestamp}}
      end

    {:ok, owner} = ManifestOwner.ensure_started("acme", "logs", config)
    :ok = GenServer.stop(owner)
    ManifestCache.drop("acme", "logs")
    %{"results" => results} = query("query_errors")
    records = Map.new(results, &{&1["event_id"], &1})
    assert map_size(records) == length(expected)

    for {id, {input, timestamp}} <- expected do
      record = Map.fetch!(records, id)
      assert record["timestamp_ns"] == timestamp
      assert record["event"]["timestamp"] === input
    end

    before = Agent.get(agent, & &1.requests)

    for input <- [-1000.0, -0.000001, -3.00000049, -3.00000051], route <- ["store", "envelope"] do
      event = %{"message" => "pre-epoch control", "timestamp" => input}
      body = if route == "store", do: Pulse.JSON.encode!(event), else: envelope(event)

      assert :post
             |> Plug.Test.conn("/api/42/#{route}/?sentry_key=#{@key}", body)
             |> PulseWeb.Endpoint.call([])
             |> json_response(400) == %{"error" => "invalid_timestamp"}
    end

    assert Agent.get(agent, & &1.requests) == before
  end

  @tag :s3
  @tag :sentry_level
  test "Relay level oracles project canonical severity without rewriting retained events", %{config: config} do
    # Relay a68f1dbec05258cfa27b01059e1c1816d10c7257,
    # relay-event-schema/src/protocol/types.rs:1153-1169, complete test_level.
    # These are scalar decoder oracles, adapted into HTTP error events rather
    # than claimed as original Relay ingestion/normalization integration cases.
    cases = [
      {"log", "info", 9},
      {30, "warning", 13},
      {"critical", "fatal", 21},
      # Additional controls cover the other Python codes and unchanged policies.
      {10, "debug", 5},
      {20, "info", 9},
      {40, "error", 17},
      {50, "fatal", 21},
      {"warning", "warning", 13},
      {"custom", "custom", 17},
      {30.0, "error", 17},
      {nil, "error", 17}
    ]

    expected =
      for {input, level, number} <- cases, route <- ["store", "envelope"] do
        event = %{"message" => "Relay level oracle", "level" => input}
        body = if route == "store", do: Pulse.JSON.encode!(event), else: envelope(event)

        %{"id" => id} =
          :post
          |> Plug.Test.conn("/api/42/#{route}/?sentry_key=#{@key}", body)
          |> PulseWeb.Endpoint.call([])
          |> json_response(200)

        {id, {input, level, number}}
      end

    {:ok, owner} = ManifestOwner.ensure_started("acme", "logs", config)
    :ok = GenServer.stop(owner)
    ManifestCache.drop("acme", "logs")
    records = Map.new(query("query_logs"), &{&1["body"]["event_id"], &1})
    assert map_size(records) == length(expected)

    for {id, {input, level, number}} <- expected do
      record = Map.fetch!(records, id)
      assert record["severity_text"] == level
      assert record["severity_number"] == number
      assert record["body"]["level"] === input
      assert record["service"] == "api"
    end
  end

  @tag :s3
  @tag :sentry_zstd
  test "Relay zstd encoding cases use bounded decoding before durable error publication", %{
    agent: agent,
    config: config
  } do
    # Relay a68f1dbec05258cfa27b01059e1c1816d10c7257,
    # test_store.py::test_store_content_encodings_chained, the zstd row.
    # Replay its receiving hop and original message, not Relay forwarding.
    payload = ~s({"message":"Hello, World!"})
    compressed = payload |> :zstd.compress(%{checksumFlag: true}) |> IO.iodata_to_binary()

    ids =
      for {path, body} <- [
            {"/api/42/store/", compressed},
            {"/api/42/envelope/",
             envelope(%{"message" => "Hello, World!"}) |> :zstd.compress() |> IO.iodata_to_binary()}
          ] do
        response =
          :post
          |> Plug.Test.conn(path <> "?sentry_key=#{@key}", body)
          |> put_req_header("content-encoding", "zstd")
          |> PulseWeb.Endpoint.call([])
          |> json_response(200)

        response["id"]
      end

    prefix = binary_part(compressed, 0, byte_size(compressed) - 1)
    checksum = :binary.last(compressed)
    over_event = Pulse.JSON.encode!(%{"message" => String.duplicate("a", 1_048_576)})

    for {body, key, status} <- [
          # Original test_store_content_encodings zstd row requires 400 for an empty body.
          {"", @key, 400},
          {prefix, @key, 400},
          {prefix <> <<Bitwise.bxor(checksum, 1)>>, @key, 400},
          {compressed <> "junk", @key, 400},
          {compressed <> compressed, @key, 400},
          {:zstd.compress("not JSON") |> IO.iodata_to_binary(), @key, 400},
          {compressed, "wrong", 403},
          {:zstd.compress(over_event) |> IO.iodata_to_binary(), @key, 413},
          {:zstd.compress(String.duplicate("a", 16 * 1024 * 1024 + 1)) |> IO.iodata_to_binary(), @key, 413},
          {:zstd.compress(String.duplicate("a", 16 * 1024 * 1024 + 1), %{contentSizeFlag: false})
           |> IO.iodata_to_binary(), @key, 413},
          {String.duplicate("a", 4 * 1024 * 1024 + 1), @key, 413}
        ] do
      before = Agent.get(agent, & &1.requests)

      assert :post
             |> Plug.Test.conn("/api/42/store/?sentry_key=#{key}", body)
             |> put_req_header("content-encoding", "zstd")
             |> PulseWeb.Endpoint.call([])
             |> json_response(status)

      assert Agent.get(agent, & &1.requests) == before
    end

    # Exact output limits remain inclusive on both the event and whole-body paths.
    event = payload <> String.duplicate(" ", 1_048_576 - byte_size(payload))
    header = ~s({}\n{"type":"attachment"}\n)
    discarded = header <> String.duplicate("a", 16 * 1024 * 1024 - byte_size(header))

    for {path, body} <- [{"store", event}, {"envelope", discarded}] do
      assert :post
             |> Plug.Test.conn("/api/42/#{path}/?sentry_key=#{@key}", :zstd.compress(body) |> IO.iodata_to_binary())
             |> put_req_header("content-encoding", "zstd")
             |> PulseWeb.Endpoint.call([])
             |> json_response(200)
    end

    {:ok, owner} = ManifestOwner.ensure_started("acme", "logs", config)
    :ok = GenServer.stop(owner)
    ManifestCache.drop("acme", "logs")
    assert %{"matched_events" => 3, "results" => results} = query("query_errors")
    assert Enum.all?(ids, fn id -> Enum.any?(results, &(&1["event_id"] == id)) end)
    assert Enum.all?(results, &(&1["event"]["message"] == "Hello, World!" and &1["service"] == "api"))
  end

  test "malformed, truncated and duplicate event envelopes append nothing" do
    valid = envelope(event())

    for body <- [
          "bad",
          ~s({}\n{"type":"event","length":99999}\n{}),
          valid <> "{}\n",
          valid <> ~s({"type":"event"}\n{}\n),
          ~s({}\n{"type":"event","length":-1}\n{})
        ] do
      assert body |> send_envelope() |> json_response(400)
    end

    for overrides <- [
          %{"event_id" => "bad"},
          %{"timestamp" => "bad"},
          %{"timestamp" => -1},
          %{"timestamp" => "2500-01-01T00:00:00Z"},
          %{"fingerprint" => [%{}]}
        ] do
      assert event(overrides) |> envelope() |> send_envelope() |> json_response(400)
    end

    assert {:ok, []} = Storage.query(:logs, "acme")
  end

  test "unsupported-only envelopes report discarded data rather than inventing events" do
    assert %{"id" => nil, "discarded_items" => %{"transaction" => 1}} =
             ~s({}\n{"type":"transaction"}\n{}\n) |> send_envelope() |> json_response(200)

    assert {:ok, []} = Storage.query(:logs, "acme")
  end

  test "request, expansion, event, item and structure budgets reject without publication" do
    for body <- [
          String.duplicate("a", 4 * 1024 * 1024 + 1),
          "{}\n" <> String.duplicate(~s({"type":"session"}\n{}\n), 101),
          envelope(event(%{"message" => String.duplicate("a", 1_048_576)})),
          envelope(event(%{"extra" => Enum.to_list(1..1100)}))
        ] do
      assert body |> send_envelope() |> json_response(413)
    end

    response =
      build_conn()
      |> put_req_header("content-type", "application/x-sentry-envelope")
      |> put_req_header("content-encoding", "gzip")
      |> post("/api/42/envelope/?sentry_key=#{@key}", :zlib.gzip(String.duplicate("a", 17 * 1024 * 1024)))

    assert json_response(response, 413)
    assert {:ok, []} = Storage.query(:logs, "acme")
  end

  @tag :sentry_pixel_store
  test "publication failures return retryable, non-sensitive errors rather than success" do
    Runtime.put_env(:pulse, Storage, adapter: FailingStorage)
    Runtime.put_env(:pulse, FailingStorage, {:error, "secret-provider-url"})
    response = envelope(event()) |> send_envelope()
    assert json_response(response, 503) == %{"error" => "storage_unavailable"}
    assert get_resp_header(response, "retry-after") == ["5"]
    assert get_resp_header(response, "cross-origin-resource-policy") == ["cross-origin"]

    response =
      build_conn()
      |> put_req_header("content-type", "application/x-sentry-envelope")
      |> post("/api/42/store/?sentry_key=#{@key}", envelope(event()))

    assert json_response(response, 503) == %{"error" => "storage_unavailable"}
    assert get_resp_header(response, "retry-after") == ["5"]

    query = URI.encode_query(%{"sentry_key" => @key, "sentry_data" => Pulse.JSON.encode!(event())})
    response = get(build_conn(), "/api/42/store/?" <> query)
    assert json_response(response, 503) == %{"error" => "storage_unavailable"}
    assert get_resp_header(response, "retry-after") == ["5"]
    assert get_resp_header(response, "cache-control") == ["no-store"]
  end
end
