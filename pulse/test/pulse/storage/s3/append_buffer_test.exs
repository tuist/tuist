defmodule Pulse.Storage.S3.AppendBufferTest do
  use Pulse.Test.Case, async: true

  alias Pulse.OTLP.Traces
  alias Pulse.Record.Log
  alias Pulse.Record.MetricSample
  alias Pulse.Runtime
  alias Pulse.Runtime.Registry
  alias Pulse.Runtime.Task
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.AppendBuffer
  alias Pulse.Storage.S3.AppendRegistry
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.Manifest.Segment
  alias Pulse.Storage.S3.ManifestCache
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Test.CompactionStore
  alias Pulse.Test.OTLPTraceFixture

  setup context do
    signal = Map.get(context, :signal, :logs)

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

    # Cached native clients leave keep-alive sockets open. All publications
    # are awaited below; do not spend 15s draining each idle socket at teardown.
    server =
      start_supervised!(
        {Bandit,
         plug: {CompactionStore, agent: agent},
         ip: {127, 0, 0, 1},
         port: 0,
         thousand_island_options: [shutdown_timeout: 100]}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

    config = %{
      bucket: "pulse",
      endpoint: "http://127.0.0.1:#{port}",
      region: "us-east-1",
      # Native clients cache connection pools by full config. Unique test
      # credentials prevent reusing a stale pool if the OS recycles a port.
      access_key_id: "test-#{System.unique_integer([:positive])}",
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0,
      ingest_flush_interval_ms: Map.get(context, :flush_interval_ms, 1000)
    }

    Runtime.put_env(:pulse, S3, config)

    start_supervised!(ManifestSupervision)
    tasks = start_supervised!(Task.Supervisor)
    tenant = "buffer-#{System.unique_integer([:positive])}"
    key = {:crypto.hash(:sha256, :erlang.term_to_binary(config, [:deterministic])), tenant, signal}
    buffer = start_supervised!({AppendBuffer, key: key, signal: signal, tenant: tenant, config: config})
    :erlang.trace(buffer, true, [:receive])
    [{^buffer, admission}] = Registry.lookup(AppendRegistry, key)
    %{agent: agent, config: config, tasks: tasks, tenant: tenant, signal: signal, buffer: buffer, admission: admission}
  end

  defp enqueue(ctx, batches) do
    # Control the flush explicitly, without sleeps or a scheduler-timing race.
    token = make_ref()
    :sys.replace_state(ctx.buffer, fn state -> %{state | timer: {token, token}} end)

    tasks =
      Enum.map(batches, fn records ->
        Task.Supervisor.async_nolink(ctx.tasks, fn -> S3.append(ctx.signal, ctx.tenant, records) end)
      end)

    buffer = ctx.buffer
    for _ <- batches, do: assert_receive({:trace, ^buffer, :receive, {:"$gen_call", _, {:append, _, _, _, _}}}, 30_000)
    state = :sys.get_state(buffer)
    assert length(state.pending) == length(batches)
    {_ref, token} = state.timer
    send(buffer, {:flush, token})
    tasks
  end

  defp segment_puts(agent),
    do:
      Agent.get(
        agent,
        &Enum.count(&1.requests, fn {method, key} -> method == "PUT" and String.ends_with?(key, ".parquet") end)
      )

  test "concurrent unkeyed appends share a segment and ACK only after complete publication", ctx do
    # Include identical rows: buffering must not introduce deduplication.
    record = %Log{timestamp_ns: 1, service: "api", body: "same"}
    manifest_key = Manifest.manifest_key(ctx.tenant, "logs")
    owner = self()
    Agent.update(ctx.agent, &%{&1 | barriers: %{{"PUT", manifest_key} => owner}})
    tasks = enqueue(ctx, [[record], [record]])
    assert_receive {:storage_barrier, writer, "PUT", ^manifest_key}, 30_000
    assert Enum.all?(tasks, &(Task.yield(&1, 0) == nil))
    assert ManifestCache.get(ctx.tenant, "logs") == nil
    assert [{:pending, 2, bytes, 2}] = :ets.lookup(ctx.admission, :pending)
    assert bytes > 0
    # Scraping reads reservation tables, even while the owner is blocked in I/O.
    assert AppendBuffer.stats() == {1, 2, bytes, 2}
    report = Pulse.Metrics.render()
    assert report =~ "pulse_ingest_buffer_reserved_calls 2\n"
    assert report =~ "pulse_ingest_buffer_input_bytes #{bytes}\n"
    assert report =~ "pulse_ingest_buffer_rows 2\n"
    Agent.update(ctx.agent, &%{&1 | barriers: %{}})
    send(writer, {:release_storage, manifest_key})
    assert Enum.all?(tasks, &(Task.await(&1, 10_000) == :ok))
    _ = :sys.get_state(ctx.buffer)
    assert :ets.lookup(ctx.admission, :pending) == [{:pending, 0, 0, 0}]
    assert AppendBuffer.stats() == {1, 0, 0, 0}
    assert segment_puts(ctx.agent) == 1
    assert {:ok, [^record, ^record]} = S3.query(:logs, ctx.tenant, [])
  end

  test "queued normalized slices do not retain their full request arena", ctx do
    arena = String.duplicate("x", 1024 * 1024)
    slice = binary_part(arena, 1, 100)
    entry = %Log{timestamp_ns: 1, service: "api", body: slice}
    assert :binary.referenced_byte_size(slice) > 100
    caller = Task.Supervisor.async_nolink(ctx.tasks, fn -> S3.append(:logs, ctx.tenant, [entry]) end)
    buffer = ctx.buffer
    assert_receive {:trace, ^buffer, :receive, {:"$gen_call", _, {:append, _, _, _, _}}}, 30_000
    state = :sys.get_state(ctx.buffer)
    [{_from, [stored], _bytes, _rows, _opts, _enqueued}] = state.pending
    assert :binary.referenced_byte_size(stored.body) == 100
    {_timer, token} = state.timer
    send(ctx.buffer, {:flush, token})
    assert :ok = Task.await(caller, 30_000)
  end

  for status <- [304, 200] do
    test "delayed #{status} query refresh cannot overwrite an actual acknowledged owner publication", ctx do
      key = Manifest.manifest_key(ctx.tenant, "logs")
      old = Manifest.new()
      assert {:ok, etag} = Pulse.ObjectStore.put(ctx.config, key, IO.iodata_to_binary(Manifest.encode(old)))
      cached_etag = if unquote(status) == 304, do: etag, else: "\"older-cache\""
      ManifestCache.put(ctx.tenant, "logs", old, cached_etag)
      owner = self()
      Agent.update(ctx.agent, &%{&1 | barriers: %{{"GET", key} => owner}})

      reader =
        Task.Supervisor.async_nolink(ctx.tasks, fn ->
          S3.ManifestOwner.ensure_loaded(ctx.tenant, "logs", ctx.config, require_fresh_manifest: true)
        end)

      assert_receive {:storage_barrier, worker, "GET", ^key}, 30_000
      Agent.update(ctx.agent, &%{&1 | barriers: %{}})
      record = %Log{timestamp_ns: 1, service: "api", body: "acknowledged during refresh"}
      assert :ok = S3.append_unbuffered(:logs, ctx.tenant, [record], [], ctx.config)
      published = ManifestCache.get(ctx.tenant, "logs")
      assert published.etag != etag
      send(worker, {:release_storage, key})
      assert {:ok, _} = Task.await(reader, 30_000)
      assert ManifestCache.get(ctx.tenant, "logs").etag == published.etag
      assert {:ok, [^record]} = S3.query(:logs, ctx.tenant, [])
    end
  end

  test "a delayed maintenance publication cannot hide a later acknowledged append", ctx do
    key = Manifest.manifest_key(ctx.tenant, "logs")
    old = Manifest.new()
    assert {:ok, etag} = Pulse.ObjectStore.put(ctx.config, key, IO.iodata_to_binary(Manifest.encode(old)))
    ManifestCache.put(ctx.tenant, "logs", old, etag)
    owner = self()
    Agent.update(ctx.agent, &%{&1 | barriers: %{{"PUT", key} => owner}})

    maintenance =
      Task.Supervisor.async_nolink(ctx.tasks, fn ->
        S3.Retention.transact(ctx.tenant, "logs", ctx.config, &{%{&1 | version: 2}, :updated})
      end)

    # The CAS is committed but its response has not reached maintenance yet.
    assert_receive {:storage_barrier, writer, "PUT", ^key}, 30_000
    Agent.update(ctx.agent, &%{&1 | barriers: %{}})
    config = Map.put(ctx.config, :refresh_stale_ms, 60_000)
    Runtime.put_env(:pulse, S3, config)
    record = %Log{timestamp_ns: 1, service: "api", body: "newer than maintenance response"}
    assert :ok = S3.append_unbuffered(:logs, ctx.tenant, [record], [], config)
    assert length(ManifestCache.get(ctx.tenant, "logs").manifest.segments) == 1
    send(writer, {:release_storage, key})
    assert {:ok, :updated} = Task.await(maintenance, 30_000)
    assert ManifestCache.get(ctx.tenant, "logs") == nil
    assert {:ok, [^record]} = S3.query(:logs, ctx.tenant, [])
  end

  test "a fetched invalid authority fails closed even with a warm flat cache", ctx do
    key = Manifest.manifest_key(ctx.tenant, "logs")
    old = Manifest.new()

    for required? <- [false, true], body <- [~s({"v":99,"s":[]}), ~s({"v":2,"s":[]}), "{"] do
      config = if required?, do: Map.put(ctx.config, :refresh_stale_ms, 60_000), else: ctx.config
      assert {:ok, etag} = Pulse.ObjectStore.put(config, key, IO.iodata_to_binary(Manifest.encode(old)))
      ManifestCache.put(ctx.tenant, "logs", old, etag)
      assert {:ok, _} = Pulse.ObjectStore.put(config, key, body)
      assert {:error, _} = S3.ManifestOwner.ensure_loaded(ctx.tenant, "logs", config, require_fresh_manifest: required?)
      assert ManifestCache.get(ctx.tenant, "logs") == nil
      assert {:error, _} = S3.ManifestOwner.ensure_loaded(ctx.tenant, "logs", config)
    end
  end

  test "legacy transport refresh failures retain the documented stale fallback", ctx do
    key = Manifest.manifest_key(ctx.tenant, "logs")
    old = Manifest.new()
    assert {:ok, etag} = Pulse.ObjectStore.put(ctx.config, key, IO.iodata_to_binary(Manifest.encode(old)))
    ManifestCache.put(ctx.tenant, "logs", old, etag)
    Agent.update(ctx.agent, &%{&1 | faults: %{{"GET", key} => {400, :before, 1}}})
    assert {:ok, %{manifest: ^old}} = S3.ManifestOwner.ensure_loaded(ctx.tenant, "logs", ctx.config)
    config = Map.put(ctx.config, :refresh_stale_ms, 60_000)
    Agent.update(ctx.agent, &%{&1 | faults: %{{"GET", key} => {400, :before, 1}}})

    assert {:error, :manifest_freshness_unavailable} =
             S3.ManifestOwner.ensure_loaded(ctx.tenant, "logs", config, require_fresh_manifest: true)

    assert %{manifest: ^old} = ManifestCache.get(ctx.tenant, "logs")
    assert {:ok, %{manifest: ^old}} = S3.ManifestOwner.ensure_loaded(ctx.tenant, "logs", config)
  end

  test "fresh error queries share required authority without falling back to a warm cache", ctx do
    config = Map.put(ctx.config, :refresh_stale_ms, 60_000)
    Runtime.put_env(:pulse, S3, config)
    key = Manifest.manifest_key(ctx.tenant, "logs")
    manifest = Manifest.new()
    assert {:ok, tag} = Pulse.ObjectStore.put(config, key, IO.iodata_to_binary(Manifest.encode(manifest)))
    ManifestCache.put(ctx.tenant, "logs", manifest, tag)
    assert {:ok, []} = S3.query(:logs, ctx.tenant, [])
    Agent.update(ctx.agent, &%{&1 | faults: %{{"GET", key} => {400, :before, 1}}})
    assert {:error, :manifest_freshness_unavailable} = S3.query(:logs, ctx.tenant, fresh: true)
    assert %{etag: ^tag} = ManifestCache.get(ctx.tenant, "logs")
    assert {:ok, []} = S3.query(:logs, ctx.tenant, [])
    lists = Agent.get(ctx.agent, & &1.lists)
    Agent.update(ctx.agent, &%{&1 | objects: Map.delete(&1.objects, key)})
    assert {:error, :not_found} = S3.query(:logs, ctx.tenant, fresh: true)
    assert ManifestCache.get(ctx.tenant, "logs") == nil
    assert Agent.get(ctx.agent, & &1.lists) == lists
  end

  test "missing authority preserves optional freshness and distinction semantics for every signal", ctx do
    cases = [
      {[], :signal_authority_missing},
      {[fresh: false], :signal_authority_missing},
      {[fresh: true], :not_found},
      {[distinguish_missing_authority: false], :signal_authority_missing},
      {[distinguish_missing_authority: true], :signal_authority_missing},
      {[fresh: false, distinguish_missing_authority: false], :signal_authority_missing},
      {[fresh: false, distinguish_missing_authority: true], :signal_authority_missing},
      {[fresh: true, distinguish_missing_authority: false], :not_found},
      {[fresh: true, distinguish_missing_authority: true], :signal_authority_missing}
    ]

    lists = Agent.get(ctx.agent, & &1.lists)

    for signal <- [:logs, :metrics, :traces], {opts, reason} <- cases do
      assert {:error, ^reason} = S3.query(signal, ctx.tenant, [require_fresh_manifest: true] ++ opts)
      assert ManifestCache.get(ctx.tenant, Atom.to_string(signal)) == nil
    end

    assert Agent.get(ctx.agent, & &1.lists) == lists
  end

  test "a failed legacy CAS response succeeds only when fresh read-back proves every key visible", ctx do
    key = Manifest.manifest_key(ctx.tenant, "logs")
    Agent.update(ctx.agent, &%{&1 | faults: %{{"PUT", key} => {400, :after, 1}}})
    record = %Log{timestamp_ns: 1, service: "api", body: "lost ACK"}
    tasks = enqueue(ctx, [[record], [record]])
    assert Enum.all?(tasks, &(Task.await(&1, 30_000) == :ok))
    assert segment_puts(ctx.agent) == 1
    assert {:ok, [^record, ^record]} = S3.query(:logs, ctx.tenant, [])
  end

  for managed? <- [false, true] do
    @tag matrix_managed: managed?
    test "authority response matrix with managed=#{managed?}", ctx do
      managed? = ctx.matrix_managed
      config = Map.put(ctx.config, :refresh_stale_ms, 60_000)

      config =
        if managed?,
          do:
            Map.merge(config, %{
              retention_mode: "enforce",
              retention_manifest_format: "bucketed",
              logs_retention_days: 1
            }),
          else: config

      key = Manifest.manifest_key(ctx.tenant, "logs")
      assert {:ok, _} = Pulse.ObjectStore.put(config, key, IO.iodata_to_binary(Manifest.encode(Manifest.new())))

      if managed?,
        do: assert({:ok, _} = S3.Retention.advance(ctx.tenant, "logs", config, now_ns: System.system_time(:nanosecond)))

      ManifestCache.drop(ctx.tenant, "logs")
      assert {:ok, initial} = S3.ManifestOwner.ensure_loaded(ctx.tenant, "logs", config, require_fresh_manifest: true)
      root_reads = fn -> Agent.get(ctx.agent, &Enum.count(&1.requests, fn request -> request == {"GET", key} end)) end
      count = root_reads.()
      assert {:ok, %{etag: tag}} = S3.ManifestOwner.ensure_loaded(ctx.tenant, "logs", config)
      assert tag == initial.etag
      assert root_reads.() == count
      Agent.update(ctx.agent, &%{&1 | faults: %{{"GET", key} => {400, :before, 1}}})

      assert {:error, :manifest_freshness_unavailable} =
               S3.ManifestOwner.ensure_loaded(ctx.tenant, "logs", config, require_fresh_manifest: true)

      assert %{etag: tag} = ManifestCache.get(ctx.tenant, "logs")
      assert tag == initial.etag
      count = root_reads.()
      assert {:ok, %{etag: ^tag}} = S3.ManifestOwner.ensure_loaded(ctx.tenant, "logs", config)
      assert root_reads.() == count
      # The conditional GET revalidates the unchanged warm root (304 in the stub).
      assert {:ok, validated} = S3.ManifestOwner.ensure_loaded(ctx.tenant, "logs", config, require_fresh_manifest: true)
      assert validated.manifest == initial.manifest
      assert validated.etag == initial.etag
      assert root_reads.() > count
      bytes = IO.iodata_to_binary(Manifest.encode(initial.manifest))
      assert {:ok, changed_tag} = Pulse.ObjectStore.put(config, key, bytes)
      assert changed_tag != initial.etag
      assert {:ok, replaced} = S3.ManifestOwner.ensure_loaded(ctx.tenant, "logs", config, require_fresh_manifest: true)
      assert replaced.etag == changed_tag
      assert %{etag: ^changed_tag} = ManifestCache.get(ctx.tenant, "logs")
      assert {:ok, _} = Pulse.ObjectStore.put(config, key, "not-json")
      assert {:error, _} = S3.ManifestOwner.ensure_loaded(ctx.tenant, "logs", config, require_fresh_manifest: true)
      assert ManifestCache.get(ctx.tenant, "logs") == nil
      assert {:error, _} = S3.ManifestOwner.ensure_loaded(ctx.tenant, "logs", config)
      # A cold 304 cannot prove a root when no cached body exists.
      Agent.update(ctx.agent, &%{&1 | faults: %{{"GET", key} => {304, :before, 1}}})

      assert {:error, :manifest_freshness_unavailable} =
               S3.ManifestOwner.ensure_loaded(ctx.tenant, "logs", config, require_fresh_manifest: true)

      assert ManifestCache.get(ctx.tenant, "logs") == nil
      assert {:ok, _} = Pulse.ObjectStore.put(config, key, bytes)
      assert {:ok, _} = S3.ManifestOwner.ensure_loaded(ctx.tenant, "logs", config, require_fresh_manifest: true)
      lists = Agent.get(ctx.agent, & &1.lists)
      Agent.update(ctx.agent, &%{&1 | objects: Map.delete(&1.objects, key)})

      assert {:error, :signal_authority_missing} =
               S3.ManifestOwner.ensure_loaded(ctx.tenant, "logs", config, require_fresh_manifest: true)

      assert ManifestCache.get(ctx.tenant, "logs") == nil
      if managed?, do: assert({:error, _} = S3.ManifestOwner.ensure_loaded(ctx.tenant, "logs", config))
      assert Agent.get(ctx.agent, & &1.lists) == lists
    end
  end

  test "required-fresh missing managed authority invalidates an unexpired ordinary cache", ctx do
    config =
      Map.merge(ctx.config, %{
        retention_mode: "enforce",
        retention_manifest_format: "bucketed",
        logs_retention_days: 1,
        refresh_stale_ms: 60_000
      })

    key = Manifest.manifest_key(ctx.tenant, "logs")
    assert {:ok, _} = Pulse.ObjectStore.put(config, key, IO.iodata_to_binary(Manifest.encode(Manifest.new())))
    assert {:ok, _} = S3.Retention.advance(ctx.tenant, "logs", config, now_ns: System.system_time(:nanosecond))
    assert {:ok, _} = S3.ManifestOwner.ensure_loaded(ctx.tenant, "logs", config)
    assert %{manifest: _} = ManifestCache.get(ctx.tenant, "logs")
    lists = Agent.get(ctx.agent, & &1.lists)
    Agent.update(ctx.agent, &%{&1 | objects: Map.delete(&1.objects, key)})

    assert {:error, :signal_authority_missing} =
             S3.ManifestOwner.ensure_loaded(ctx.tenant, "logs", config, require_fresh_manifest: true)

    assert ManifestCache.get(ctx.tenant, "logs") == nil
    assert {:error, _} = S3.ManifestOwner.ensure_loaded(ctx.tenant, "logs", config)
    assert Agent.get(ctx.agent, & &1.lists) == lists
  end

  test "a rejected-only flush cannot populate a cold cache from stale private owner state", ctx do
    config =
      Map.merge(ctx.config, %{retention_mode: "enforce", retention_manifest_format: "bucketed", logs_retention_days: 1})

    key = Manifest.manifest_key(ctx.tenant, "logs")
    now = System.system_time(:nanosecond)
    assert {:ok, _} = Pulse.ObjectStore.put(config, key, IO.iodata_to_binary(Manifest.encode(Manifest.new())))
    assert {:ok, _} = S3.Retention.advance(ctx.tenant, "logs", config, now_ns: now)
    assert {:ok, old, old_etag} = S3.Retention.load(ctx.tenant, "logs", config)
    assert {:ok, owner} = S3.ManifestOwner.ensure_started(ctx.tenant, "logs", config)
    :sys.replace_state(owner, &%{&1 | manifest: old, etag: old_etag, loaded?: true})
    assert {:ok, _} = S3.Retention.advance(ctx.tenant, "logs", config, now_ns: now + 1)
    ManifestCache.drop(ctx.tenant, "logs")
    before = Agent.get(ctx.agent, & &1.requests)
    expired = %Segment{key: "never-uploaded", min_ts: 0, max_ts: 0}
    assert {:error, :retention_expired} = S3.ManifestOwner.register_segments(ctx.tenant, "logs", [expired], config)
    assert ManifestCache.get(ctx.tenant, "logs") == nil
    assert Agent.get(ctx.agent, & &1.requests) == before
    assert {:ok, fresh} = S3.ManifestOwner.ensure_loaded(ctx.tenant, "logs", config)
    assert fresh.etag != old_etag
    assert fresh.manifest.paging["floor"] > old.paging["floor"]
  end

  for expired? <- [false, true] do
    test "managed lost-ACK conflict proves publication after another nonce, expired=#{expired?}", ctx do
      day = 86_400_000_000_000
      now = System.system_time(:nanosecond)

      config =
        Map.merge(ctx.config, %{
          retention_mode: "enforce",
          retention_manifest_format: "bucketed",
          logs_retention_days: 1
        })

      key = Manifest.manifest_key(ctx.tenant, "logs")
      assert {:ok, _} = Pulse.ObjectStore.put(config, key, IO.iodata_to_binary(Manifest.encode(Manifest.new())))
      assert {:ok, _} = S3.Retention.advance(ctx.tenant, "logs", config, now_ns: now)
      owner = self()

      Agent.update(ctx.agent, fn state ->
        %{state | faults: %{{"PUT", key} => {412, :after, 1}}, barriers: %{{"PUT", key} => owner}}
      end)

      record = %Log{timestamp_ns: now, service: "api", body: "committed before conflict response"}

      append =
        Task.Supervisor.async_nolink(ctx.tasks, fn -> S3.append_unbuffered(:logs, ctx.tenant, [record], [], config) end)

      assert_receive {:storage_barrier, writer, "PUT", ^key}, 30_000
      Agent.update(ctx.agent, &%{&1 | barriers: %{}})
      advanced_now = if unquote(expired?), do: now + day + 1, else: now + 1
      assert {:ok, _} = S3.Retention.advance(ctx.tenant, "logs", config, now_ns: advanced_now)
      before = Agent.get(ctx.agent, &Enum.count(&1.requests, fn request -> request == {"PUT", key} end))
      send(writer, {:release_storage, key})
      assert :ok = Task.await(append, 30_000)
      assert Agent.get(ctx.agent, &Enum.count(&1.requests, fn request -> request == {"PUT", key} end)) == before
    end
  end

  for signal <- [:logs, :metrics] do
    @tag signal: signal
    test "#{signal}: a floor advance after combined PUT never permanently rejects fresh siblings", ctx do
      config =
        Map.merge(ctx.config, %{
          retention_enabled: true,
          retention_mode: "enforce",
          retention_manifest_format: "bucketed",
          logs_retention_days: 1,
          metrics_retention_days: 1
        })

      # Keep the caller's buffer identity, while its flush uses the managed
      # policy. Even observe-mode callers must honor the committed root floor.
      :sys.replace_state(ctx.buffer, &%{&1 | config: config})
      now = System.system_time(:nanosecond)
      day = 86_400_000_000_000

      assert {:ok, _} =
               Pulse.ObjectStore.put(
                 config,
                 Manifest.manifest_key(ctx.tenant, Atom.to_string(ctx.signal)),
                 IO.iodata_to_binary(Manifest.encode(Manifest.new()))
               )

      assert {:ok, _} = S3.Retention.advance(ctx.tenant, Atom.to_string(ctx.signal), config, now_ns: now)
      old_ts = now - day + 1_000_000_000

      record = fn ts ->
        case ctx.signal do
          :logs -> %Log{timestamp_ns: ts, service: "api", body: "moving floor"}
          :metrics -> %MetricSample{timestamp_ns: ts, value: 1.0, labels: %{"__name__" => "moving_floor"}}
        end
      end

      key = Manifest.manifest_key(ctx.tenant, Atom.to_string(ctx.signal))
      assert {:ok, root, _} = S3.Retention.load(ctx.tenant, Atom.to_string(ctx.signal), config)

      paging =
        Map.merge(root.paging, %{
          "floor" => root.paging["floor"] + 2_000_000_000,
          "nonce" => Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
        })

      advanced = IO.iodata_to_binary(Manifest.encode(%{root | paging: paging}))
      # Inject another writer's valid floor commit immediately before our
      # conditional PUT, not after it has already become durable.
      Agent.update(ctx.agent, fn state ->
        %{
          state
          | hook: fn state ->
              version = state.version + 1
              %{state | version: version, objects: Map.put(state.objects, key, {"\"#{version}\"", advanced})}
            end
        }
      end)

      tasks = enqueue(ctx, [[record.(old_ts)], [record.(now)]])
      assert Enum.all?(tasks, &(Task.await(&1, 30_000) == {:error, :retention_floor_advanced}))
      assert segment_puts(ctx.agent) == 1
      assert :ets.lookup(ctx.admission, :pending) == [{:pending, 0, 0, 0}]
      assert {:ok, []} = S3.query(ctx.signal, ctx.tenant, [])
      assert {:error, :retention_expired} = S3.append(ctx.signal, ctx.tenant, [record.(old_ts)])
      assert :ok = S3.append(ctx.signal, ctx.tenant, [record.(now)])
      assert {:ok, [stored]} = S3.query(ctx.signal, ctx.tenant, [])
      assert stored.timestamp_ns == now
    end
  end

  test "keyed retries bypass buffers and keep original idempotent fingerprints", ctx do
    record = %Log{timestamp_ns: 1, service: "api"}
    for _ <- 1..2, do: assert(:ok = S3.append(:logs, ctx.tenant, [record], idempotency_key: "retry"))
    assert :sys.get_state(ctx.buffer).pending == []
    assert :ets.lookup(ctx.admission, :pending) == [{:pending, 0, 0, 0}]
    assert {:ok, [^record]} = S3.query(:logs, ctx.tenant, [])
  end

  # Object stores bill every PUT, so a tenant's ingest cost must follow the
  # flush interval, not the push rate: unkeyed pushes share segments and
  # every append, keyed ones included, shares root writes spaced at least one
  # interval apart. Every push is still acknowledged only once it is visible.
  @tag flush_interval_ms: 300
  test "segment and root writes follow the flush interval, not the number of pushes", ctx do
    root = Manifest.manifest_key(ctx.tenant, "logs")
    started = System.monotonic_time(:millisecond)

    tasks =
      for i <- 1..30 do
        Process.sleep(25)
        opts = if rem(i, 5) == 0, do: [idempotency_key: "keyed-#{i}"], else: []
        record = %Log{timestamp_ns: i, service: "api", body: "push #{i}"}
        Task.Supervisor.async_nolink(ctx.tasks, fn -> S3.append(:logs, ctx.tenant, [record], opts) end)
      end

    assert Enum.map(tasks, &Task.await(&1, 30_000)) == List.duplicate(:ok, 30)
    elapsed = System.monotonic_time(:millisecond) - started
    requests = Agent.get(ctx.agent, & &1.requests)
    root_puts = Enum.count(requests, &(&1 == {"PUT", root}))

    # Publications start at least 300 ms apart; without spacing each keyed push
    # and each flush would publish on its own (about nine here).
    assert root_puts <= div(elapsed, 300) + 1, "#{root_puts} root writes in #{elapsed} ms"
    # 24 unkeyed pushes over 750 ms fill about three windows; 6 keyed pushes upload alone.
    assert segment_puts(ctx.agent) <= div(elapsed, 300) + 1 + 6
    assert {:ok, records} = S3.query(:logs, ctx.tenant, [])
    assert records |> Enum.map(& &1.timestamp_ns) |> Enum.sort() == Enum.to_list(1..30)
  end

  test "byte, row and caller reservations cannot grow a full mailbox; overflow publishes directly", ctx do
    for counters <- [{:pending, 128, 0, 0}, {:pending, 0, 10 * 1024 * 1024, 0}, {:pending, 0, 0, 100_000}] do
      :ets.insert(ctx.admission, counters)
      assert :ok = S3.append(:logs, ctx.tenant, [%Log{timestamp_ns: 1, service: "direct"}])
      assert :ets.lookup(ctx.admission, :pending) == [counters]
      assert :sys.get_state(ctx.buffer).pending == []
    end

    assert segment_puts(ctx.agent) == 3
    assert {:ok, records} = S3.query(:logs, ctx.tenant, [])
    assert length(records) == 3
  end

  test "oversized terms bypass the buffer without truncating their contents", ctx do
    body = String.duplicate("x", 11 * 1024 * 1024)
    record = %Log{timestamp_ns: 1, service: "large", body: body}
    assert :ok = S3.append(:logs, ctx.tenant, [record])
    assert :sys.get_state(ctx.buffer).pending == []
    assert :ets.lookup(ctx.admission, :pending) == [{:pending, 0, 0, 0}]
    assert {:ok, [^record]} = S3.query(:logs, ctx.tenant, service: "large")
  end

  @tag flush_interval_ms: 20
  test "while a slow manifest write is in flight, requests beyond the window share the next segment", ctx do
    key = Manifest.manifest_key(ctx.tenant, "logs")
    owner = self()
    buffer = ctx.buffer
    hold = fn -> Agent.update(ctx.agent, &%{&1 | barriers: %{{"PUT", key} => owner}}) end

    release = fn writer ->
      Agent.update(ctx.agent, &%{&1 | barriers: %{}})
      send(writer, {:release_storage, key})
    end

    append = fn ts ->
      Task.Supervisor.async_nolink(ctx.tasks, fn -> S3.append(:logs, ctx.tenant, [%Log{timestamp_ns: ts}]) end)
    end

    arrived = fn ts ->
      assert_receive {:trace, ^buffer, :receive, {:"$gen_call", _, {:append, [%Log{timestamp_ns: ^ts}], _, _, _}}},
                     30_000
    end

    # A first publication that takes 1.2 s teaches the owner its commit time.
    # The adaptive window is that estimate minus the buffer's measured upload
    # time and the time already spent in the next commit, both of which grow
    # under scheduler load, so the estimate must dwarf them.
    hold.()
    first = append.(1)
    assert_receive {:storage_barrier, writer, "PUT", ^key}, 30_000
    Process.sleep(1200)
    release.(writer)
    assert Task.await(first, 10_000) == :ok

    hold.()
    second = append.(2)
    assert_receive {:storage_barrier, writer, "PUT", ^key}, 30_000

    # Requests 60 ms apart, three windows, would each flush alone; behind the
    # in-flight write they keep collecting for the next one instead.
    third = append.(3)
    arrived.(3)
    # The batch waits for the next publication: far longer than three windows.
    assert {timer, _token} = :sys.get_state(buffer).timer
    assert Process.read_timer(timer) > 300
    Process.sleep(60)
    fourth = append.(4)
    arrived.(4)
    assert length(:sys.get_state(buffer).pending) == 2

    release.(writer)
    assert Enum.map([second, third, fourth], &Task.await(&1, 10_000)) == [:ok, :ok, :ok]
    assert segment_puts(ctx.agent) == 3
    assert {:ok, records} = S3.query(:logs, ctx.tenant, [])
    assert records |> Enum.map(& &1.timestamp_ns) |> Enum.sort() == [1, 2, 3, 4]
  end

  test "flushes pipeline: a later batch uploads while an earlier one waits on its manifest CAS", ctx do
    start_supervised!(Pulse.IngestAdmission)
    first = %Log{timestamp_ns: 1, service: "first"}
    second = %Log{timestamp_ns: 2, service: "second"}
    manifest_key = Manifest.manifest_key(ctx.tenant, "logs")
    owner = self()
    Agent.update(ctx.agent, &%{&1 | barriers: %{{"PUT", manifest_key} => owner}})

    # Each waiting caller hands its admission slot to the pending budget.
    admitted = fn records ->
      fn ->
        :ok = Pulse.IngestAdmission.acquire(:logs)
        S3.append(:logs, ctx.tenant, records)
      end
    end

    [early] = enqueue_with(ctx, [admitted.([first])])
    assert_receive {:storage_barrier, writer, "PUT", ^manifest_key}, 30_000
    assert Pulse.IngestAdmission.in_flight(:logs) == 0
    assert Pulse.IngestAdmission.pending_bytes() > 0

    [late] = enqueue_with(ctx, [admitted.([second])])
    buffer = ctx.buffer
    refute_received {:trace, ^buffer, :receive, {:flushed, _}}
    # The second segment is uploaded before the first publication finishes.
    wait_for_segment_puts(ctx.agent, 2)
    assert Task.yield(early, 0) == nil

    Agent.update(ctx.agent, &%{&1 | barriers: %{}})
    send(writer, {:release_storage, manifest_key})
    assert Task.await(early, 10_000) == :ok
    assert Task.await(late, 10_000) == :ok
    assert {:ok, records} = S3.query(:logs, ctx.tenant, [])
    assert Enum.sort_by(records, & &1.timestamp_ns) == [first, second]
  end

  defp enqueue_with(ctx, funs) do
    token = make_ref()
    :sys.replace_state(ctx.buffer, fn state -> %{state | timer: {token, token}} end)
    tasks = Enum.map(funs, &Task.Supervisor.async_nolink(ctx.tasks, &1))
    buffer = ctx.buffer
    for _ <- funs, do: assert_receive({:trace, ^buffer, :receive, {:"$gen_call", _, {:append, _, _, _, _}}}, 30_000)
    send(buffer, {:flush, token})
    tasks
  end

  defp wait_for_segment_puts(agent, count) do
    # Uploads are observed through the fake store, not timed.
    if !(segment_puts(agent) >= count) do
      :erlang.yield()
      wait_for_segment_puts(agent, count)
    end
  end

  test "a caller timeout cannot release queued input reservations before publication", ctx do
    record = %Log{timestamp_ns: 1, service: "timed-out"}
    records = [record]
    bytes = :erlang.external_size(records)
    :ets.insert(ctx.admission, {:pending, 1, bytes, 1})
    token = make_ref()
    :sys.replace_state(ctx.buffer, fn state -> %{state | timer: {token, token}} end)

    caller =
      Task.Supervisor.async_nolink(ctx.tasks, fn ->
        try do
          GenServer.call(ctx.buffer, {:append, records, bytes, 1, []}, 0)
        catch
          :exit, {:timeout, _} -> :timed_out
        end
      end)

    assert Task.await(caller) == :timed_out
    assert length(:sys.get_state(ctx.buffer).pending) == 1
    assert :ets.lookup(ctx.admission, :pending) == [{:pending, 1, bytes, 1}]
    key = Manifest.manifest_key(ctx.tenant, "logs")
    owner = self()
    Agent.update(ctx.agent, &%{&1 | barriers: %{{"PUT", key} => owner}})
    send(ctx.buffer, {:flush, token})
    # This verifies reservation lifetime, not encode/provider scheduling latency.
    assert_receive {:storage_barrier, writer, "PUT", ^key}, 30_000
    assert :ets.lookup(ctx.admission, :pending) == [{:pending, 1, bytes, 1}]
    Agent.update(ctx.agent, &%{&1 | barriers: %{}})
    send(writer, {:release_storage, key})
    # Flushes publish in their own process and report back when done.
    buffer = ctx.buffer
    assert_receive {:trace, ^buffer, :receive, {:flushed, _}}, 30_000
    assert :ets.lookup(ctx.admission, :pending) == [{:pending, 0, 0, 0}]
    assert %{etag: etag} = ManifestCache.get(ctx.tenant, "logs")
    assert is_binary(etag)
    assert {:ok, [^record]} = S3.query(:logs, ctx.tenant, [])
  end

  test "invalid encoding does not poison a valid request sharing its flush", ctx do
    valid = %Log{timestamp_ns: 1, service: "api", body: "valid"}
    invalid = %{valid | body: make_ref()}
    [good, bad] = enqueue(ctx, [[valid], [invalid]])
    assert Task.await(good, 10_000) == :ok
    assert {:error, {:encode_failed, _}} = Task.await(bad, 10_000)
    assert segment_puts(ctx.agent) == 1
    assert {:ok, [^valid]} = S3.query(:logs, ctx.tenant, [])
    assert :ets.lookup(ctx.admission, :pending) == [{:pending, 0, 0, 0}]
  end

  defp heterogeneous_batches(signal, producers) do
    for producer <- 1..producers do
      for row <- 1..Enum.at([1, 17, 131, 509], rem(producer - 1, 4)) do
        id = producer * 1000 + row

        producer_record(signal, producer, id)
      end
    end
  end

  defp producer_record(:logs, producer, id) do
    %Log{
      timestamp_ns: id,
      service: "worker-#{rem(producer, 3)}",
      body: "request-#{id}",
      resource: %{"instance" => "host-#{producer}"}
    }
  end

  defp producer_record(:metrics, producer, id) do
    %MetricSample{
      timestamp_ns: id,
      value: id / 13,
      labels: %{"__name__" => "work", "job" => "worker-#{rem(producer, 3)}", "instance" => "host-#{producer}"}
    }
  end

  defp producer_label(:logs, record), do: record.service
  defp producer_label(:metrics, record), do: record.labels["job"]

  defp normalized(signal, records) do
    assert {:ok, blob, _, _} = S3.encode_segment(signal, records)
    assert {:ok, decoded} = S3.decode_segment(signal, blob, nil, nil, [])
    Enum.sort(decoded)
  end

  for signal <- [:logs, :metrics], producers <- [8, 32] do
    @tag signal: signal
    test "#{signal}: #{producers} heterogeneous producers preserve every row", ctx do
      batches = heterogeneous_batches(ctx.signal, unquote(producers))
      tasks = enqueue(ctx, batches)
      assert Enum.all?(tasks, &(Task.await(&1, 30_000) == :ok))
      assert segment_puts(ctx.agent) == 1
      assert {:ok, actual} = S3.query(ctx.signal, ctx.tenant, [])
      expected = normalized(ctx.signal, List.flatten(batches))
      assert Enum.sort(actual) == expected
      label = if ctx.signal == :logs, do: "service", else: "job"
      assert {:ok, selected} = S3.query(ctx.signal, ctx.tenant, matchers: [{label, :eq, "worker-1"}])
      matching = Enum.filter(expected, &(producer_label(ctx.signal, &1) == "worker-1"))
      assert Enum.sort(selected) == matching
      _ = :sys.get_state(ctx.buffer)
      assert :ets.lookup(ctx.admission, :pending) == [{:pending, 0, 0, 0}]
    end

    @tag signal: signal, flush_interval_ms: 0
    test "#{signal}: disabled coalescing publishes one segment per each of #{producers} producers", ctx do
      # As in the original holdout, publish a keyed bootstrap before the
      # burst so this checks direct appends, not first-write reconstruction.
      bootstrap = producer_record(ctx.signal, 99, 99_000)
      assert :ok = S3.append(ctx.signal, ctx.tenant, [bootstrap], idempotency_key: "bootstrap")
      puts_before = segment_puts(ctx.agent)
      batches = heterogeneous_batches(ctx.signal, unquote(producers))

      tasks =
        Enum.map(batches, fn records ->
          Task.Supervisor.async_nolink(ctx.tasks, fn -> S3.append(ctx.signal, ctx.tenant, records) end)
        end)

      assert Enum.all?(tasks, &(Task.await(&1, 30_000) == :ok))
      assert segment_puts(ctx.agent) - puts_before == unquote(producers)
      assert {:ok, actual} = S3.query(ctx.signal, ctx.tenant, [])
      assert Enum.sort(actual) == normalized(ctx.signal, [bootstrap | List.flatten(batches)])
      assert :sys.get_state(ctx.buffer).pending == []
      assert :ets.lookup(ctx.admission, :pending) == [{:pending, 0, 0, 0}]
    end

    @tag signal: signal
    test "#{signal}: one invalid request cannot poison #{producers - 1} valid producers", ctx do
      [first | rest] = heterogeneous_batches(ctx.signal, unquote(producers))
      [record | tail] = first
      field = if ctx.signal == :logs, do: :body, else: :value
      invalid = Map.put(record, field, make_ref())
      [bad | good] = enqueue(ctx, [[invalid | tail] | rest])
      assert {:error, {:encode_failed, _}} = Task.await(bad, 30_000)
      assert Enum.all?(good, &(Task.await(&1, 30_000) == :ok))
      assert segment_puts(ctx.agent) == unquote(producers) - 1
      assert {:ok, actual} = S3.query(ctx.signal, ctx.tenant, [])
      assert Enum.sort(actual) == normalized(ctx.signal, List.flatten(rest))
      _ = :sys.get_state(ctx.buffer)
      assert :ets.lookup(ctx.admission, :pending) == [{:pending, 0, 0, 0}]
    end

    @tag signal: signal
    test "#{signal}: publication failure does not retry #{producers} producers separately", ctx do
      key = Manifest.manifest_key(ctx.tenant, Atom.to_string(ctx.signal))
      Agent.update(ctx.agent, &%{&1 | faults: %{{"PUT", key} => {400, :before, 1}}})
      tasks = enqueue(ctx, heterogeneous_batches(ctx.signal, unquote(producers)))
      for task <- tasks, do: assert({:error, _} = Task.await(task, 30_000))
      assert segment_puts(ctx.agent) == 1
      refute Agent.get(ctx.agent, &Map.has_key?(&1.objects, key))
      _ = :sys.get_state(ctx.buffer)
      assert :ets.lookup(ctx.admission, :pending) == [{:pending, 0, 0, 0}]
    end
  end

  test "trace payload overflow splits a coalesced flush instead of rejecting valid callers", ctx do
    key = {:crypto.hash(:sha256, :erlang.term_to_binary(ctx.config, [:deterministic])), ctx.tenant, :traces}

    buffer =
      start_supervised!({AppendBuffer, key: key, signal: :traces, tenant: ctx.tenant, config: ctx.config},
        id: :trace_buffer
      )

    :erlang.trace(buffer, true, [:receive])
    [{^buffer, admission}] = Registry.lookup(AppendRegistry, key)
    ctx = Map.merge(ctx, %{buffer: buffer, admission: admission, signal: :traces})
    {:ok, [base], 0} = Traces.decode(OTLPTraceFixture.payload())
    record = %{base | name: :binary.copy(<<0>>, 2 * 1024 * 1024)}
    tasks = enqueue(ctx, [[record], [record]])
    for task <- tasks, do: assert(:ok = Task.await(task, 30_000))
    assert segment_puts(ctx.agent) == 2
    assert :ets.lookup(ctx.admission, :pending) == [{:pending, 0, 0, 0}]
    assert {:ok, [^record]} = S3.query(:traces, ctx.tenant, limit: 1)
  end

  test "storage errors fan out without retrying individual inputs after an ambiguous publication", ctx do
    key = Manifest.manifest_key(ctx.tenant, "logs")
    Agent.update(ctx.agent, &%{&1 | faults: %{{"PUT", key} => {400, :before, 1}}})
    tasks = enqueue(ctx, [[%Log{timestamp_ns: 1}], [%Log{timestamp_ns: 2}]])
    for task <- tasks, do: assert({:error, _} = Task.await(task, 10_000))
    assert segment_puts(ctx.agent) == 1
    assert ManifestCache.get(ctx.tenant, "logs") == nil
    assert :ets.lookup(ctx.admission, :pending) == [{:pending, 0, 0, 0}]
  end
end
