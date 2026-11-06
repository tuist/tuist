defmodule Pulse.Storage.S3.ObjectCacheTest do
  # Segment GETs a dashboard refresh makes through the real native S3/Parquet
  # path, with and without the node-local object cache. Asserts request counts
  # (never timings) and that cached reads return the same results.
  use Pulse.Test.Case, async: true

  alias Pulse.LogQL.Evaluator
  alias Pulse.LogQL.Parser
  alias Pulse.Record.Log
  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Storage.S3.ObjectCache
  alias Pulse.Test.CompactionStore

  @segments 24
  @second 1_000_000_000

  setup do
    store =
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

    # Segment GETs wait `delay` ms, so concurrent readers overlap.
    delay = :atomics.new(1, [])

    hook = fn method, key, _body ->
      if method == "GET" and String.ends_with?(key, ".parquet"), do: Process.sleep(:atomics.get(delay, 1))
    end

    server =
      start_supervised!(
        {Bandit, plug: {CompactionStore, agent: store, before_request: hook}, ip: {127, 0, 0, 1}, port: 0}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

    config = %{
      bucket: "pulse",
      endpoint: "http://127.0.0.1:#{port}",
      region: "us-east-1",
      access_key_id: "test-#{System.unique_integer([:positive])}",
      secret_access_key: "test",
      allow_http: true,
      query_prefetch: 4
    }

    Runtime.put_env(:pulse, S3, config)
    Runtime.put_env(:pulse, Storage, adapter: S3)
    %{store: store, delay: delay, config: config, tenant: "object-cache-#{System.unique_integer([:positive])}"}
  end

  defp start(cache) do
    Runtime.put_env(:pulse, ObjectCache, cache)
    start_supervised!(ManifestSupervision)
  end

  defp append(ctx) do
    for i <- 1..@segments do
      records =
        for n <- 0..1,
            do: %Log{
              timestamp_ns: i * @second + n,
              body: ~s({"level":"#{if rem(i, 3) == 0, do: "error", else: "info"}","i":#{i}}),
              resource: %{"namespace" => "tuist", "pod" => "server-#{rem(i, 2)}"}
            }

      assert :ok = S3.append(:logs, ctx.tenant, records)
    end
  end

  defp query(ctx) do
    {:ok, ast} = Parser.parse(~s|sum by (pod) (count_over_time({namespace="tuist"} \|= "error" [1m]))|)
    Agent.update(ctx.store, &%{&1 | reads: []})

    result =
      Evaluator.evaluate_metric(ast, ctx.tenant, %{
        start_ts_ns: 60 * @second,
        end_ts_ns: 60 * @second,
        step_ns: 60 * @second
      })

    {result, segment_reads(ctx)}
  end

  defp segment_reads(ctx), do: ctx.store |> Agent.get(& &1.reads) |> Enum.count(&String.ends_with?(&1, ".parquet"))

  defp sync, do: :sys.get_state(Runtime.whereis(ObjectCache))

  test "without a cache every refresh reads every segment again", ctx do
    start(memory_bytes: 0)
    append(ctx)
    {first, reads} = query(ctx)
    assert reads == @segments
    assert {^first, @segments} = query(ctx)
  end

  test "segments this node uploaded and segments read once are served without a GET", ctx do
    start(memory_bytes: 64 * 1_048_576)
    append(ctx)
    sync()

    # Write-through: the uploading node never reads its own segments back.
    {cached, reads} = query(ctx)
    assert reads == 0

    # A cold cache reads each segment once, then serves every refresh.
    ObjectCache.clear_memory()
    sync()
    assert {^cached, @segments} = query(ctx)
    sync()
    assert {^cached, 0} = query(ctx)
    assert %{memory: {@segments, bytes}, memory_hits: hits} = ObjectCache.stats()
    assert bytes > 0 and hits >= 2 * @segments

    # Cached reads answer exactly what the store answers.
    Runtime.put_env(:pulse, ObjectCache, memory_bytes: 0)
    stop_supervised!(ManifestSupervision)
    start_supervised!(ManifestSupervision)
    assert {^cached, @segments} = query(ctx)
  end

  test "concurrent cold refreshes share one GET per segment", ctx do
    start(memory_bytes: 64 * 1_048_576)
    append(ctx)
    ObjectCache.clear_memory()
    sync()
    :atomics.put(ctx.delay, 1, 50)
    Agent.update(ctx.store, &%{&1 | reads: []})

    results =
      1..2
      |> Enum.map(fn _ -> Pulse.Runtime.Task.async(fn -> query_result(ctx) end) end)
      |> Enum.map(&Pulse.Runtime.Task.await(&1, 30_000))

    assert [first | _] = results
    assert Enum.all?(results, &(&1 == first))
    assert segment_reads(ctx) == @segments
  end

  test "the memory tier stays within its byte bound", ctx do
    start(memory_bytes: 64 * 1_048_576)
    append(ctx)
    sync()
    %{memory: {@segments, total}} = ObjectCache.stats()

    # Room for about a third of the segments evicts the least recently used.
    bound = div(total, 3)
    Runtime.put_env(:pulse, ObjectCache, memory_bytes: bound)
    stop_supervised!(ManifestSupervision)
    start_supervised!(ManifestSupervision)
    assert {_, @segments} = query(ctx)
    sync()
    assert %{memory: {entries, bytes}} = ObjectCache.stats()
    assert bytes <= bound and entries in div(@segments, 4)..div(@segments, 3)
  end

  @tag :tmp_dir
  test "the disk tier serves segments after a restart", %{tmp_dir: dir} = ctx do
    cache = [memory_bytes: 0, disk_dir: dir, disk_bytes: 64 * 1_048_576]
    start(cache)
    append(ctx)
    sync()
    assert %{disk: {@segments, _}} = ObjectCache.stats()
    {cached, 0} = query(ctx)

    # A partial write from a crash is discarded, never served.
    File.write!(Path.join(dir, "partial.tmp"), "x")
    stop_supervised!(ManifestSupervision)
    start_supervised!(ManifestSupervision)
    assert %{disk: {@segments, _}} = ObjectCache.stats()
    refute File.exists?(Path.join(dir, "partial.tmp"))
    assert {^cached, 0} = query(ctx)
    assert %{disk_hits: hits} = ObjectCache.stats()
    assert hits >= @segments
  end

  defp query_result(ctx) do
    {:ok, ast} = Parser.parse(~s|sum by (pod) (count_over_time({namespace="tuist"} \|= "error" [1m]))|)

    Evaluator.evaluate_metric(ast, ctx.tenant, %{
      start_ts_ns: 60 * @second,
      end_ts_ns: 60 * @second,
      step_ns: 60 * @second
    })
  end
end
