defmodule Pulse.Storage.S3.TraceRetentionTest do
  use Pulse.Test.Case, async: true

  alias Pulse.ObjectStore
  alias Pulse.OTLP.Traces
  alias Pulse.Runtime
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.AppendBuffer
  alias Pulse.Storage.S3.CompactionWorker
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.Manifest.Segment
  alias Pulse.Storage.S3.ManifestOwner
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Storage.S3.PagedManifest
  alias Pulse.Storage.S3.Retention
  alias Pulse.Storage.S3.RetentionWorker
  alias Pulse.Storage.S3.TraceCompactor
  alias Pulse.Storage.S3.TraceSummary
  alias Pulse.Test.CompactionStore
  alias Pulse.Test.OTLPTraceFixture, as: Fixture

  @day 86_400_000_000_000

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
      access_key_id: "trace-retention-#{System.unique_integer([:positive])}",
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0,
      traces_retention_days: 1,
      retention_mode: "observe",
      retention_manifest_format: "bucketed",
      retention_delete_grace_ms: 5,
      retention_interval_ms: 1,
      retention_tail_entries: 2
    }

    Runtime.put_env(:pulse, S3, config)
    Runtime.put_env(:pulse, Pulse.Storage, adapter: S3)
    start_supervised!(ManifestSupervision)
    {:ok, [span], 0} = Traces.decode(Fixture.payload([Fixture.span(System.system_time(:nanosecond))]))

    %{
      agent: agent,
      config: config,
      tenant: "trace-retain-#{System.unique_integer([:positive])}",
      span: span,
      now: span.timestamp_ns
    }
  end

  defp root(ctx) do
    assert {:ok, root, _} = Retention.load(ctx.tenant, "traces", ctx.config)
    root
  end

  defp enforce(ctx, now \\ nil) do
    assert {:ok, _} = ManifestOwner.ensure_loaded(ctx.tenant, "traces", ctx.config)
    now = now || ctx.now
    config = Map.put(ctx.config, :retention_mode, "enforce")
    Runtime.put_env(:pulse, S3, config)
    assert {:ok, _} = Retention.advance(ctx.tenant, "traces", config, now_ns: now, now_ms: div(now, 1_000_000))
    %{ctx | config: config}
  end

  defp clean(ctx, now_ms) do
    for _ <- 1..16, do: assert(match?({:ok, _}, Retention.cleanup(ctx.tenant, "traces", ctx.config, now_ms: now_ms)))
  end

  defp request(ctx, payload, type, keyed? \\ false) do
    body = if type == "application/json", do: Pulse.JSON.encode!(payload), else: Fixture.protobuf(payload)

    conn =
      Plug.Test.conn(:post, "/v1/traces", body)
      |> Plug.Conn.put_req_header("content-type", type)
      |> Plug.Conn.put_req_header("x-scope-orgid", ctx.tenant)

    conn = if keyed?, do: Plug.Conn.put_req_header(conn, "idempotency-key", "whole-batch"), else: conn
    PulseWeb.Endpoint.call(conn, PulseWeb.Endpoint.init([]))
  end

  test "trace policy is independent and only trace retention starts maintenance", ctx do
    assert Retention.days(%{metrics_retention_days: 90}, "traces") == 0
    assert Retention.enforcing?(%{retention_mode: "enforce", metrics_retention_days: 1}, "traces") == false
    assert Retention.configured?(%{traces_retention_days: 1})
    assert RetentionWorker.children(%{traces_retention_days: 1}) != []
    assert CompactionWorker.children(%{traces_retention_days: 1}) == []
    config = Map.merge(ctx.config, %{traces_retention_days: 0, metrics_retention_days: 1, retention_mode: "enforce"})
    Runtime.put_env(:pulse, S3, config)
    old = %{ctx.span | timestamp_ns: 1, end_timestamp_ns: 2}
    assert :ok = S3.append(:traces, ctx.tenant, [old])
    # Not retention-managed: the default paged format, not format 3.
    assert root(ctx).version == 4
  end

  test "first enforcement creates the shared paged root and rejects expired and future batches", ctx do
    config = Map.put(ctx.config, :retention_mode, "enforce")
    Runtime.put_env(:pulse, S3, config)
    assert {:error, :retention_expired} = S3.append(:traces, ctx.tenant, [%{ctx.span | timestamp_ns: 1}])

    assert {:error, :timestamp_too_new} =
             S3.append(:traces, ctx.tenant, [
               %{ctx.span | timestamp_ns: ctx.now + @day, end_timestamp_ns: ctx.now + @day + 1}
             ])

    assert root(ctx).version == 3
    assert {:ok, _, _} = ObjectStore.get_bounded(config, PagedManifest.marker(ctx.tenant, "traces"), nil, 1024)
    refute Agent.get(ctx.agent, &Enum.any?(Map.keys(&1.objects), fn k -> String.ends_with?(k, ".parquet") end))
  end

  test "mixed-age segments hide expired rows in records, native search and exact assembly", ctx do
    floor = ctx.now - @day
    old = %{ctx.span | timestamp_ns: floor - 1, span_id: String.duplicate("a", 16), parent_span_id: nil}
    boundary = %{ctx.span | timestamp_ns: floor, span_id: String.duplicate("b", 16), parent_span_id: old.span_id}

    fresh = %{
      ctx.span
      | timestamp_ns: floor + 100,
        span_id: String.duplicate("c", 16),
        parent_span_id: boundary.span_id
    }

    assert :ok = S3.append(:traces, ctx.tenant, [old, boundary, fresh])
    ctx = enforce(ctx)
    assert {:ok, [^fresh, ^boundary]} = S3.query(:traces, ctx.tenant, [])
    assert {:ok, json} = S3.query_traces_json(ctx.tenant, [], ["span_id"])
    assert Enum.map(Pulse.JSON.decode!(json), & &1["span_id"]) == [fresh.span_id, boundary.span_id]
    assert {:ok, json} = S3.get_trace_json(ctx.tenant, ctx.span.trace_id, [])
    assembled = Pulse.JSON.decode!(json)
    assert assembled["coverage"] == "all_stored_spans_at_or_above_floor"
    assert assembled["retention_floor_ns"] == floor
    assert assembled["span_count"] == 2
    assert assembled["missing_parent_span_ids"] == [old.span_id]
    assert {:ok, []} = S3.query(:traces, ctx.tenant, end_ts: floor - 1)
  end

  test "paged metadata preserves Bloom pruning and incremental limited-query scan budgets", ctx do
    ctx = enforce(ctx)

    for n <- 1..5 do
      assert :ok = S3.append(:traces, ctx.tenant, [%{ctx.span | timestamp_ns: ctx.now + n}], idempotency_key: "p#{n}")
    end

    assert {:ok, [latest]} = S3.query(:traces, ctx.tenant, limit: 1, max_scan_segments: 1)
    assert latest.timestamp_ns == ctx.now + 5
    assert {:error, :query_scan_limit} = S3.get_trace_json(ctx.tenant, ctx.span.trace_id, max_scan_segments: 1)
    assert {:ok, json} = S3.get_trace_json(ctx.tenant, String.duplicate("f", 32), max_scan_segments: 1)
    assert Pulse.JSON.decode!(json)["span_count"] == 0
  end

  test "exact-ID lookup prunes 140 leaves before charging their metadata budgets", ctx do
    ctx = enforce(ctx)
    assert :ok = S3.append(:traces, ctx.tenant, [ctx.span])

    assert {:ok, :ok} =
             Retention.transact(ctx.tenant, "traces", ctx.config, fn root ->
               [bucket] = root.paging["buckets"]

               refs =
                 for n <- 1..140 do
                   id = Base.encode16(<<n::128>>, case: :lower)
                   record = %{ctx.span | trace_id: id, timestamp_ns: ctx.now + n}
                   key = S3.object_key(ctx.tenant, "traces", record.timestamp_ns, record.timestamp_ns, "#{n}", nil)

                   segment = %{
                     Segment.build(key, record.timestamp_ns, record.timestamp_ns, 1, 100)
                     | trace_summary: TraceSummary.build([record])
                   }

                   # Independent time bounds; these keys need never be downloaded by an
                   # exact-ID lookup. Missing data would be a hard error if wrongly read.
                   PagedManifest.put_page(
                     bucket,
                     "active",
                     [Segment.to_wire(segment)],
                     ctx.tenant,
                     "traces",
                     ctx.config
                   )
                 end

               bucket = %{bucket | "max" => ctx.now + 140}
               root = PagedManifest.put_bucket(root, bucket)
               idx = %{"active" => refs, "retired" => []}
               {PagedManifest.write_index(root, bucket, idx, ctx.tenant, "traces", ctx.config), :ok}
             end)

    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)
    Agent.update(ctx.agent, &%{&1 | requests: []})
    assert {:ok, json} = S3.get_trace_json(ctx.tenant, ctx.span.trace_id, max_scan_segments: 1)
    assert Pulse.JSON.decode!(json)["span_count"] == 1

    reads =
      Agent.get(
        ctx.agent,
        &Enum.filter(&1.requests, fn {method, key} ->
          method == "GET" and String.contains?(key, "/index/")
        end)
      )

    assert length(reads) == 1
  end

  test "exact-ID metadata fanout scales within a hard ceiling and honors explicit byte limits", ctx do
    ctx = %{ctx | config: Map.put(ctx.config, :traces_retention_days, 14)} |> enforce()
    assert :ok = S3.append(:traces, ctx.tenant, [ctx.span])
    ids = for n <- 1..512, do: Base.encode16(<<n::128>>, case: :lower)
    summary = TraceSummary.from_values(["api"], ids)
    q = TraceSummary.page_summary([%{"t" => TraceSummary.to_wire(summary)}])
    refute TraceSummary.page_matches?(q, trace_id: ctx.span.trace_id)

    assert {:ok, :ok} =
             Retention.transact(ctx.tenant, "traces", ctx.config, fn root ->
               hour = 3_600_000_000_000

               Enum.reduce(1..140, root, fn n, root ->
                 start = PagedManifest.bucket_start(root.paging, ctx.now - n * hour)

                 bucket = %{
                   "start" => start,
                   "id" => PagedManifest.nonce(),
                   "state" => "live",
                   "cursor" => 0,
                   "min" => start,
                   "max" => start,
                   "mutations" => 0,
                   "written" => 0,
                   "index" => nil
                 }

                 # Synthetic irrelevant leaves: if fetched, their absent objects fail
                 # loudly. Real, checksummed index bodies exceed 8 MiB in aggregate.
                 # Stay comfortably below the scaled default: key lengths
                 # vary across full-suite runtime/tenant names.
                 refs =
                   for _ <- 1..32,
                       do: %{
                         "k" =>
                           PagedManifest.bucket_prefix(ctx.tenant, "traces", bucket) <>
                             "#{PagedManifest.nonce()}-active-#{String.duplicate("a", 64)}.json",
                         "b" => 1000,
                         "sha" => String.duplicate("a", 64),
                         "min" => start,
                         "max" => start,
                         "min_max" => start,
                         "q" => q
                       }

                 PagedManifest.write_index(
                   PagedManifest.put_bucket(root, bucket),
                   bucket,
                   %{"active" => refs, "retired" => []},
                   ctx.tenant,
                   "traces",
                   ctx.config
                 )
               end)
               |> then(&{&1, :ok})
             end)

    bytes =
      Agent.get(ctx.agent, fn state ->
        state.objects
        |> Enum.filter(fn {key, _} -> String.contains?(key, "/index/") end)
        |> Enum.reduce(0, fn {_, {_etag, body}}, sum -> sum + byte_size(body) end)
      end)

    assert bytes > 8 * 1024 * 1024
    assert {:ok, root, _} = Retention.load(ctx.tenant, "traces", ctx.config)
    opts = [trace_id: ctx.span.trace_id, limit: 5001]
    fixed = Map.put(ctx.config, :retention_metadata_scan_bytes, 8 * 1024 * 1024)
    assert {:error, :metadata_scan_limit} = PagedManifest.query(root, ctx.tenant, "traces", opts, fixed)
    assert {:ok, [_]} = PagedManifest.query(root, ctx.tenant, "traces", opts, ctx.config)
    # Non-ID searches do not inherit the larger default.
    assert {:error, :metadata_scan_limit} =
             PagedManifest.query(root, ctx.tenant, "traces", [service: "missing"], ctx.config)

    assert {:ok, json} = S3.get_trace_json(ctx.tenant, ctx.span.trace_id, max_scan_segments: 1)
    assert Pulse.JSON.decode!(json)["span_count"] == 1
  end

  test "paged native merges and retired keyed retries preserve duplicate spans", ctx do
    ctx = enforce(ctx)
    assert :ok = S3.append(:traces, ctx.tenant, [ctx.span], idempotency_key: "retry")
    assert :ok = S3.append(:traces, ctx.tenant, [ctx.span])
    assert {:ok, %{merged: 2}} = TraceCompactor.compact(ctx.tenant, ctx.config, grace_ms: 0)
    assert {:ok, 2} = TraceCompactor.cleanup(ctx.tenant, ctx.config)
    assert :ok = S3.append(:traces, ctx.tenant, [ctx.span], idempotency_key: "retry")
    assert {:ok, [_, _]} = S3.query(:traces, ctx.tenant, [])
    assert root(ctx).version == 3
    assert root(ctx).retired == %{}
  end

  test "legacy near-full indexes cannot poison another bucket or wedge expiry", ctx do
    ctx = %{ctx | config: Map.put(ctx.config, :retention_future_skew_ms, 7_200_000)} |> enforce()
    assert :ok = S3.append(:traces, ctx.tenant, [ctx.span])

    assert {:ok, :ok} =
             Retention.transact(ctx.tenant, "traces", ctx.config, fn root ->
               [bucket] = root.paging["buckets"]
               ids = for n <- 1..512, do: Base.encode16(<<n::128>>, case: :lower)
               q = TraceSummary.page_summary([%{"t" => TraceSummary.to_wire(TraceSummary.from_values(["api"], ids))}])

               ref = %{
                 "k" =>
                   PagedManifest.bucket_prefix(ctx.tenant, "traces", bucket) <>
                     "#{PagedManifest.nonce()}-active-#{String.duplicate("a", 64)}.json",
                 "b" => 1000,
                 "sha" => String.duplicate("a", 64),
                 "min" => ctx.now,
                 "max" => ctx.now,
                 "min_max" => ctx.now,
                 "q" => q
               }

               size = byte_size(Pulse.JSON.encode!(ref)) + 1
               count = div(522_200 - 32, size)

               refs =
                 for _ <- 1..count,
                     do:
                       Map.put(
                         ref,
                         "k",
                         String.replace(
                           ref["k"],
                           Path.basename(ref["k"]),
                           "#{PagedManifest.nonce()}-active-#{String.duplicate("a", 64)}.json"
                         )
                       )

               index = %{"active" => refs, "retired" => [], "extension" => ""}
               # Valid extension fields pin the old index exactly 40 bytes below
               # its former live ceiling, independent of tenant/key length.
               padding = 522_200 - byte_size(Pulse.JSON.encode!(index))
               body = Pulse.JSON.encode!(%{index | "extension" => String.duplicate("x", padding)})
               assert byte_size(body) == 522_200
               sha = :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)

               key =
                 PagedManifest.bucket_prefix(ctx.tenant, "traces", bucket) <>
                   "#{binary_part(sha, 0, 32)}-index-#{sha}.json"

               assert {:ok, _} = ObjectStore.put_if_none_match(ctx.config, key, body)
               # Reproduce a valid older root: a large index and one acknowledged inline
               # segment. New writes no longer create this state, but upgrades must drain it.
               bucket =
                 bucket
                 |> Map.put("index", %{"k" => key, "b" => byte_size(body), "sha" => sha})
                 |> Map.put("leaf_count", count)

               {PagedManifest.put_bucket(root, bucket), :ok}
             end)

    next = PagedManifest.bucket_start(root(ctx).paging, ctx.now) + root(ctx).paging["width"] + 1

    for n <- 0..1 do
      fresh = %{ctx.span | timestamp_ns: next + n, end_timestamp_ns: next + n + 1}
      assert :ok = S3.append(:traces, ctx.tenant, [fresh])
    end

    assert length(root(ctx).segments) == 1
    now = ctx.now + @day + 4 * 3_600_000_000_000
    ctx = enforce(ctx, now)
    assert PagedManifest.floor(root(ctx)) == now - @day
    assert Enum.all?(root(ctx).paging["buckets"], &(&1["state"] == "data"))
    assert {:ok, []} = S3.query(:traces, ctx.tenant, [])
  end

  test "leaf-count admission reserves the entire bounded flush before upload", ctx do
    ctx = enforce(ctx)
    assert :ok = S3.append(:traces, ctx.tenant, [ctx.span])

    assert {:ok, :ok} =
             Retention.transact(ctx.tenant, "traces", ctx.config, fn root ->
               [bucket] = root.paging["buckets"]

               refs =
                 for _ <- 1..1020,
                     do: %{
                       "k" =>
                         PagedManifest.bucket_prefix(ctx.tenant, "traces", bucket) <>
                           "#{PagedManifest.nonce()}-active-#{String.duplicate("a", 64)}.json",
                       "b" => 1000,
                       "sha" => String.duplicate("a", 64),
                       "min" => ctx.now,
                       "max" => ctx.now,
                       "min_max" => ctx.now
                     }

               {PagedManifest.write_index(
                  root,
                  bucket,
                  %{"active" => refs, "retired" => []},
                  ctx.tenant,
                  "traces",
                  ctx.config
                ), :ok}
             end)

    before = Agent.get(ctx.agent, &Map.keys(&1.objects))
    assert {:error, :retention_capacity} = S3.append(:traces, ctx.tenant, [ctx.span])
    assert Agent.get(ctx.agent, &Map.keys(&1.objects)) == before
  end

  test "definitive pre-CAS compaction failures reclaim uploads and rotate the cursor", ctx do
    ctx = enforce(ctx)
    for _ <- 1..2, do: assert(:ok = S3.append(:traces, ctx.tenant, [ctx.span]))
    config = Map.put(ctx.config, :retention_bucket_mutations, 0)
    for _ <- 1..2, do: assert({:error, :retention_capacity} = TraceCompactor.compact(ctx.tenant, config))
    [bucket] = root(ctx).paging["buckets"]
    assert root(ctx).paging["compaction_bucket"] == bucket["start"]
    refute Agent.get(ctx.agent, &Enum.any?(Map.keys(&1.objects), fn key -> String.contains?(key, "-compact-") end))
    assert {:ok, [_, _]} = S3.query(:traces, ctx.tenant, [])
  end

  test "trace compaction grace does not change log or metric window capacity", ctx do
    config = Map.put(ctx.config, :trace_compaction_options, grace_ms: 5 * 86_400_000)
    assert Retention.effective_grace(config, "metrics") == 3_600_000
    assert Retention.effective_grace(config, "logs") == 5
    # Log compaction, when enabled, applies its own retirement grace.
    assert Retention.effective_grace(Map.put(config, :log_compaction_enabled, true), "logs") == 3_600_000
    assert Retention.effective_grace(config, "traces") == 5 * 86_400_000
    assert Retention.window_ns(21, config, "metrics") == Retention.window_ns(21, ctx.config, "metrics")
    assert Retention.window_ns(21, config, "traces") > Retention.window_ns(21, ctx.config, "traces")
  end

  test "native compaction above the hash cap preserves canonical leaf pruning", ctx do
    ctx = enforce(ctx)

    records =
      for n <- 1..320 do
        %{
          ctx.span
          | trace_id: Base.encode16(<<n::128>>, case: :lower),
            timestamp_ns: ctx.now + n,
            end_timestamp_ns: ctx.now + n + 1
        }
      end

    for batch <- Enum.chunk_every(records, 160), do: assert(:ok = S3.append(:traces, ctx.tenant, batch))
    assert {:ok, %{merged: 2}} = TraceCompactor.compact(ctx.tenant, ctx.config, grace_ms: 0)
    [merged] = root(ctx).segments
    assert merged.row_count == 320
    assert merged.trace_summary.lookup_hashes == nil
    assert byte_size(merged.trace_summary.lookup_bits) == 2048
    # Spill a leaf containing both the wide replacement and small hash sets.
    for _ <- 1..2, do: assert(:ok = S3.append(:traces, ctx.tenant, [ctx.span]))
    root = root(ctx)
    [bucket] = root.paging["buckets"]

    assert {:ok, index} =
             PagedManifest.with_budget(ctx.config, fn ->
               PagedManifest.index(bucket, ctx.tenant, "traces", ctx.config)
             end)

    [ref] = index["active"]
    assert byte_size(Base.decode64!(ref["q"]["b"])) == 2048
    for record <- records, do: assert(TraceSummary.page_matches?(ref["q"], trace_id: record.trace_id))

    for record <- Enum.take_every(records, 79) do
      assert {:ok, json} = S3.get_trace_json(ctx.tenant, record.trace_id, max_scan_segments: 1)
      assert Pulse.JSON.decode!(json)["span_count"] == 1
    end

    assert {:ok, json} = S3.query_traces_json(ctx.tenant, [], ["trace_id"])
    assert length(Pulse.JSON.decode!(json)) == 322
  end

  test "bucket teardown and restart fence both keyed and stale random registration retries", ctx do
    assert :ok = S3.append(:traces, ctx.tenant, [ctx.span], idempotency_key: "old-keyed")
    assert :ok = S3.append(:traces, ctx.tenant, [ctx.span])
    sources = root(ctx).segments
    ctx = enforce(ctx, ctx.now + 3 * @day)
    clean(ctx, div(ctx.now + 3 * @day, 1_000_000) + 10)
    assert {:ok, []} = S3.query(:traces, ctx.tenant, [])
    for source <- sources, do: assert({:error, :not_found} = ObjectStore.get(ctx.config, source.key))
    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)
    assert {:error, :retention_expired} = S3.append(:traces, ctx.tenant, [ctx.span], idempotency_key: "old-keyed")
    assert {:error, :retention_expired} = ManifestOwner.register_segments(ctx.tenant, "traces", sources, ctx.config)
    assert {:ok, []} = S3.query(:traces, ctx.tenant, [])
  end

  test "missing managed authority never reconstructs physically expired history", ctx do
    assert :ok = S3.append(:traces, ctx.tenant, [ctx.span])
    ctx = enforce(ctx, ctx.now + 3 * @day)
    clean(ctx, div(ctx.now + 3 * @day, 1_000_000) + 10)
    assert :ok = ObjectStore.delete(ctx.config, Manifest.manifest_key(ctx.tenant, "traces"))
    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)
    assert {:error, :managed_manifest_missing} = S3.query(:traces, ctx.tenant, [])
    assert {:error, :managed_manifest_missing} = S3.append(:traces, ctx.tenant, [ctx.span])
  end

  test "disabled policy and paused maintenance never rewind the committed trace floor", ctx do
    assert :ok = S3.append(:traces, ctx.tenant, [ctx.span])
    ctx = enforce(ctx, ctx.now + 3 * @day)
    paused = Map.merge(ctx.config, %{retention_mode: "paused", traces_retention_days: 0})
    Runtime.put_env(:pulse, S3, paused)
    assert {:ok, []} = S3.query(:traces, ctx.tenant, [])
    assert {:error, :retention_expired} = S3.append(:traces, ctx.tenant, [ctx.span])
    assert {:ok, 0} = Retention.cleanup(ctx.tenant, "traces", paused)
    assert root(ctx).paging["floor"] == ctx.now + 2 * @day
  end

  test "unkeyed OTLP semantic rejections use the committed floor in both formats", ctx do
    ctx = enforce(ctx)
    payload = Fixture.payload([Fixture.span(1), Fixture.span(ctx.now)])

    for type <- ["application/json", "application/x-protobuf"] do
      conn = request(ctx, payload, type)
      assert conn.status == 200
      assert Plug.Conn.get_resp_header(conn, "content-type") == [type]

      if type == "application/json",
        do: assert(Pulse.JSON.decode!(conn.resp_body)["partialSuccess"]["rejectedSpans"] == "1"),
        else: assert(<<10, _, 8, 1, _::binary>> = conn.resp_body)

      assert request(ctx, payload, type, true).status == 400
    end

    assert {:ok, rows} = S3.query(:traces, ctx.tenant, [])
    assert length(rows) == 2
  end

  test "an advanced floor fences buffered publication without an old cutoff bypass", ctx do
    ctx = enforce(ctx)
    config = Map.put(ctx.config, :ingest_flush_interval_ms, 1000)
    old = %{ctx.span | timestamp_ns: ctx.now - @day + 1}
    fresh = ctx.span
    assert :ok = S3.check_retention(:traces, ctx.tenant, [old], config)
    ctx = enforce(ctx, ctx.now + 2)
    admission = :ets.new(:queued_trace_retention, [:set, :public])
    :ets.insert(admission, {:pending, 2, 20, 2})
    old_ref = make_ref()
    fresh_ref = make_ref()
    token = make_ref()

    state = %{
      signal: :traces,
      tenant: ctx.tenant,
      config: config,
      admission: admission,
      pending: [
        {{self(), fresh_ref}, [fresh], 10, 1, [], System.monotonic_time()},
        {{self(), old_ref}, [old], 10, 1, [trace_retention_cutoff_ns: 0], System.monotonic_time()}
      ],
      pending_bytes: 20,
      pending_rows: 2,
      flushing: 0,
      uploading: 0,
      upload_ms: nil,
      upload_deviation_ms: 0,
      registered_at: nil,
      timer: {nil, token}
    }

    assert {:noreply, %{pending: [], flushing: 1}, _} = AppendBuffer.handle_info({:flush, token}, state)
    # The flush publishes in a linked process that reports back to its buffer.
    assert_receive {:flushed, _uploaded?}, 30_000
    assert_receive {^old_ref, {:error, :retention_expired}}
    assert_receive {^fresh_ref, :ok}
    assert {:ok, [^fresh]} = S3.query(:traces, ctx.tenant, [])
    assert :ets.lookup(admission, :pending) == [{:pending, 0, 0, 0}]
  end

  test "unpaged trace archive-v3 data is rejected rather than confused with a paged root" do
    bytes = Pulse.JSON.encode!(%{"v" => 3, "s" => [], "retired" => %{}})
    assert {:error, :invalid_manifest} = Manifest.decode(bytes)
  end
end
