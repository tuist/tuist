defmodule Pulse.LogQL.LogScanPruningTest do
  # Many small log segments behind the real native S3/Parquet/paged-manifest
  # path, as Alloy pushes produce them. Asserts how many segment objects a
  # query reads (never timings) and that pruning never changes results,
  # against the in-memory adapter as reference.
  use Pulse.Test.Case, async: true

  alias Pulse.LogQL.Evaluator
  alias Pulse.LogQL.Parser
  alias Pulse.QueryLimit
  alias Pulse.Record.Log
  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Storage.Memory
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.ManifestOwner
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Test.CompactionStore
  alias Pulse.Test.MCPMessages

  # More than the 512-entry inline tail, so most segments live in leaf pages.
  @segments 600
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

    # Optional segment GET latency, with in-flight and peak counts: 1 delay
    # in ms (0 is none), 2 in flight, 3 peak.
    gate = :atomics.new(3, [])
    hook = fn method, key, _body -> if method == "GET", do: delay_segment_get(gate, key) end

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
      # Count every segment GET the query itself makes.
      query_prefetch: 1
    }

    Runtime.put_env(:pulse, S3, config)

    Runtime.put_env(:pulse, Storage, adapter: S3)
    start_supervised!(ManifestSupervision)
    tenant = "log-pruning-#{System.unique_integer([:positive])}"

    # Segment i holds two lines one nanosecond apart at second i. Every third
    # segment is the kura pod's; the rest are tuist server pushes.
    batches =
      for i <- 1..@segments do
        {namespace, container, pod} =
          if rem(i, 3) == 0, do: {"kura", "kura", "kura-#{rem(i, 2)}"}, else: {"tuist", "server", "server-0"}

        batch =
          for n <- 0..1 do
            line =
              if rem(i, 50) == 0 and n == 1,
                do: ~s({"msg":"literal_alloc: Cannot allocate","i":#{i}}),
                else: ~s({"msg":"ok","i":#{i},"n":#{n}})

            %Log{
              timestamp_ns: i * @second + n,
              body: line,
              resource: %{
                "cluster" => "tuist-canary",
                "namespace" => namespace,
                "container" => container,
                "pod" => pod
              }
            }
          end

        batch
      end

    batches
    |> Pulse.Runtime.Task.async_stream(&S3.append(:logs, tenant, &1), max_concurrency: 8, timeout: :infinity)
    |> Enum.each(&assert(&1 == {:ok, :ok}))

    # Most candidates are planned from immutable leaf pages, not the root tail.
    {:ok, entry} = ManifestOwner.ensure_loaded(tenant, "logs", config)
    assert entry.manifest.version == 4
    assert Enum.sum_by(entry.manifest.paging["refs"], & &1["n"]) > length(entry.manifest.segments)

    # Small enough that the unpruned window cannot be read in one query.
    budget(300)
    %{store: store, tenant: tenant, records: List.flatten(batches), config: config, gate: gate}
  end

  defp delay_segment_get(gate, key) do
    delay = :atomics.get(gate, 1)

    if delay > 0 and String.ends_with?(key, ".parquet") do
      peak(gate, :atomics.add_get(gate, 2, 1))
      Process.sleep(delay)
      :atomics.sub(gate, 2, 1)
    end
  end

  defp peak(gate, value) do
    current = :atomics.get(gate, 3)
    if value > current and :atomics.compare_exchange(gate, 3, current, value) != :ok, do: peak(gate, value)
  end

  defp page_reads(ctx) do
    ctx.store |> Agent.get(& &1.reads) |> Enum.count(&String.ends_with?(&1, "-leaf.json"))
  end

  defp budget(segments) do
    Runtime.put_env(:pulse, Pulse.QueryRunner, max_scan_segments: segments)
    Runtime.put_env(:pulse, Pulse.PromQL.Evaluator, max_scan_segments: segments)
  end

  defp range, do: %{start_ts_ns: 0, end_ts_ns: (@segments + 1) * @second}

  defp logs(ctx, query, opts) do
    {:ok, ast} = Parser.parse(query)
    Agent.update(ctx.store, &%{&1 | reads: []})
    result = Evaluator.evaluate_log(ast, ctx.tenant, Map.merge(range(), opts))
    {result, segment_reads(ctx)}
  end

  defp metric(ctx, query, opts \\ %{}) do
    {:ok, ast} = Parser.parse(query)
    Agent.update(ctx.store, &%{&1 | reads: []})
    result = Evaluator.evaluate_metric(ast, ctx.tenant, Map.merge(%{end_ts_ns: range().end_ts_ns}, opts))
    {result, segment_reads(ctx)}
  end

  defp segment_reads(ctx) do
    ctx.store
    |> Agent.get(& &1.reads)
    |> Enum.count(&(String.contains?(&1, "/signal=logs/") and String.ends_with?(&1, ".parquet")))
  end

  # The same query against the in-memory adapter holding the same records.
  defp reference(ctx, fun) do
    Runtime.put_env(:pulse, Storage, adapter: Memory)
    :ok = Memory.append(:logs, ctx.tenant, ctx.records)

    try do
      fun.()
    after
      Runtime.put_env(:pulse, Storage, adapter: S3)
    end
  end

  defp timestamps({:ok, streams}), do: streams |> Enum.flat_map(&elem(&1, 1)) |> Enum.map(&elem(&1, 0)) |> Enum.sort()

  test "a limited backward query reads only the newest segments it needs", ctx do
    query = ~s({cluster=~"tuist-canary", namespace="kura", container="kura", pod=~".*"} | json)
    {result, reads} = logs(ctx, query, %{limit: 5, direction: :backward})

    # Kura segments 600, 597 and 594 hold the five newest lines; segment 591
    # ends before the oldest kept line, so the scan stops without reading it.
    assert reads == 3
    assert timestamps(result) == [594 * @second + 1, 597 * @second, 597 * @second + 1, 600 * @second, 600 * @second + 1]
    {:ok, streams} = result
    assert Enum.all?(streams, fn {labels, _} -> labels["namespace"] == "kura" and is_binary(labels["msg"]) end)
  end

  test "a limited forward query reads only the oldest segments it needs", ctx do
    {result, reads} = logs(ctx, ~s({namespace="kura"}), %{limit: 3, direction: :forward})
    assert reads == 2
    assert timestamps(result) == [3 * @second, 3 * @second + 1, 6 * @second]
  end

  test "a limited query that every segment's labels match still stops early", ctx do
    # Lines of segments 599 and 598 match; segment 600 is read and has none.
    # Segment 597 ends before the oldest kept line, so it is never read.
    {result, reads} = logs(ctx, ~s({cluster="tuist-canary"} |= "\\"i\\":59"), %{limit: 3})
    assert reads == 3
    assert timestamps(result) == [598 * @second + 1, 599 * @second, 599 * @second + 1]
  end

  test "leaf summaries skip whole manifest pages no selected stream can be in", ctx do
    # Cold page cache: planning must read every leaf it cannot rule out.
    :ok = S3.MetadataCache.clear()
    {result, reads} = logs(ctx, ~s({namespace="missing"}), %{limit: 5})
    assert result == {:ok, []}
    assert {reads, page_reads(ctx)} == {0, 0}

    {result, reads} = metric(ctx, ~s<sum(count_over_time({namespace="missing"} [#{@segments + 1}s])) or vector(0)>)
    assert {:ok, {:vector, [{_, {_, +0.0}}]}} = result
    assert {reads, page_reads(ctx)} == {0, 0}

    # Every leaf holds kura segments, so each is read once.
    {_result, reads} = logs(ctx, ~s({namespace="kura"}), %{limit: 5})
    assert reads == 3
    assert page_reads(ctx) > 0
  end

  test "limited scans that cannot stop early read further ahead", ctx do
    budget(10_000)
    Runtime.put_env(:pulse, S3, %{ctx.config | query_prefetch: 4})
    :atomics.put(ctx.gate, 1, 5)

    # No line matches, so every segment is read; read-ahead grows past the
    # configured depth of 4 towards 32 while the scan keeps going.
    {result, reads} = logs(ctx, ~s({cluster="tuist-canary"} |= "no line has this"), %{limit: 10})
    assert result == {:ok, []}
    assert reads == @segments
    assert :atomics.get(ctx.gate, 3) > 8

    # A scan that stops after three segments reads at most the configured
    # depth past them.
    {result, reads} = logs(ctx, ~s({namespace="kura", container="kura"} | json), %{limit: 5})
    assert length(timestamps(result)) == 5
    assert reads in 3..7
  end

  test "stream-label selectors prune segments of metric queries", ctx do
    for selector <- [
          ~s({namespace="kura"}),
          ~s({namespace=~"ku.*|nothing", cluster="tuist-canary"}),
          ~s({namespace!="tuist"}),
          ~s({container!~"server|postgres"})
        ] do
      {result, reads} = metric(ctx, "sum(count_over_time(#{selector} [#{@segments + 1}s]))")
      assert reads == 200, selector
      assert {:ok, {:vector, [{_, {_, 400.0}}]}} = result
    end

    # 400 tuist segments: allow them all; no line-filter index skips any.
    budget(500)

    {result, reads} =
      metric(
        ctx,
        ~s<sum(count_over_time({namespace="tuist",container="server"} |= "literal_alloc: Cannot allocate" [#{@segments + 1}s])) or vector(0)>
      )

    assert reads == 400
    assert {:ok, {:vector, [{_, {_, 8.0}}]}} = result
  end

  test "an exceeded scan budget names the limit and its value", ctx do
    {result, reads} = metric(ctx, ~s<sum(count_over_time({namespace=~".+"} [#{@segments + 1}s]))>)
    assert result == {:error, :query_scan_limit}
    assert reads == 0

    assert %{limit: :max_scan_segments, maximum: 300, observed: observed, stage: :candidates} = QueryLimit.take()
    assert observed > 300

    # Enough budget for every candidate, but the limited scan must actually
    # read more than it may: the visited count is reported.
    budget(4)
    {result, reads} = logs(ctx, ~s({cluster="tuist-canary"} |= "literal_alloc"), %{limit: 100})
    assert result == {:error, :query_scan_limit}
    assert reads == 4
    detail = QueryLimit.take()
    assert detail == %{limit: :max_scan_segments, maximum: 4, observed: 5, stage: :visited}

    # MCP keeps the reason clients match on first and appends the detail.
    {:reply, response} =
      Pulse.MCP.dispatch(
        MCPMessages.request(1, "tools/call", %{
          "name" => "query_logql",
          "arguments" => %{
            "tenant" => ctx.tenant,
            "query" => ~s({cluster="tuist-canary"} |= "literal_alloc"),
            "start_ts_ns" => 0,
            "end_ts_ns" => range().end_ts_ns,
            "limit" => 100
          }
        })
      )

    assert response["result"]["isError"]

    assert [%{"text" => ":query_scan_limit: max_scan_segments=4 exceeded: the scan needed at least 5 segments; " <> _}] =
             response["result"]["content"]
  end

  test "pruning and early termination leave results unchanged", ctx do
    budget(10_000)

    log_queries = [
      {~s({namespace="kura"} | json), %{limit: 7, direction: :backward}},
      {~s({namespace="kura"} | json), %{limit: 7, direction: :forward}},
      {~s({namespace=~"tuist|kura", pod!~"server-.*"}), %{limit: 11}},
      {~s({container="server"} |= "literal_alloc"), %{limit: 1000}},
      {~s({container="server"} |= "literal_alloc"), %{limit: 3, direction: :forward}},
      {~s({namespace="missing"}), %{limit: 5}},
      {~s({cluster="tuist-canary"} |~ "\\"i\\":[12]\\\\d\\\\d,"), %{limit: 50}}
    ]

    metric_queries = [
      ~s<sum by (pod) (count_over_time({namespace=~"ku.*"} [#{@segments + 1}s]))>,
      ~s<sum(count_over_time({namespace="tuist"} |= "literal_alloc: Cannot allocate" [#{@segments + 1}s])) or vector(0)>,
      ~s<sum(count_over_time({namespace="missing"} [#{@segments + 1}s])) or vector(0)>
    ]

    actual =
      Enum.map(log_queries, fn {query, opts} -> query |> then(&logs(ctx, &1, opts)) |> elem(0) end) ++
        Enum.map(metric_queries, &(ctx |> metric(&1) |> elem(0)))

    expected =
      reference(ctx, fn ->
        Enum.map(log_queries, fn {query, opts} -> query |> then(&logs(ctx, &1, opts)) |> elem(0) end) ++
          Enum.map(metric_queries, &(ctx |> metric(&1) |> elem(0)))
      end)

    assert Enum.all?(actual, &match?({:ok, _}, &1))
    assert normalize(actual) == normalize(expected)
  end

  defp normalize(results) do
    Enum.map(results, fn
      {:ok, streams} when is_list(streams) -> {:ok, Enum.sort(streams)}
      {:ok, {kind, series}} when is_list(series) -> {:ok, {kind, Enum.sort(series)}}
      other -> other
    end)
  end
end
