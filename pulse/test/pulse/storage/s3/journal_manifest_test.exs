defmodule Pulse.Storage.S3.JournalManifestTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Record.Log
  alias Pulse.Runtime
  alias Pulse.Runtime.Task
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.JournalManifest
  alias Pulse.Storage.S3.LogCompactor
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.Manifest.Segment
  alias Pulse.Storage.S3.ManifestOwner
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Storage.S3.MetadataCache
  alias Pulse.Storage.S3.MetricTiers
  alias Pulse.Storage.S3.Retention
  alias Pulse.Test.CompactionStore

  @moduletag timeout: 180_000
  @services ~w(api web worker kura)

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
    {:ok, {_, port}} = ThousandIsland.listener_info(server)

    config = %{
      bucket: "pulse",
      endpoint: "http://127.0.0.1:#{port}",
      region: "us-east-1",
      access_key_id: "journal-#{System.unique_integer([:positive])}",
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0
    }

    Runtime.put_env(:pulse, S3, config)
    start_supervised!(ManifestSupervision)
    %{agent: agent, config: config, tenant: "journal-#{System.unique_integer([:positive])}"}
  end

  # A flat history shaped like a node that never enabled retention: one
  # segment per second, a few services each.
  defp history(tenant, count) do
    for i <- 1..count do
      min = i * 1_000_000
      key = S3.object_key(tenant, "logs", min, min + 500, Integer.to_string(i, 16), nil)
      services = @services |> Enum.drop(rem(i, 4)) |> Enum.take(1 + rem(i, 3)) |> Enum.sort()
      %{Segment.build(key, min, min + 500, 1 + rem(i, 7), 1000 + i) | log_services: services}
    end
  end

  defp put_root(ctx, %Manifest{} = manifest) do
    body = manifest |> Manifest.encode() |> IO.iodata_to_binary()
    key = Manifest.manifest_key(ctx.tenant, "logs")
    Agent.update(ctx.agent, &put_in(&1.objects[key], {"\"seed\"", body}))
  end

  defp root(ctx) do
    {_, body} = Agent.get(ctx.agent, &Map.fetch!(&1.objects, Manifest.manifest_key(ctx.tenant, "logs")))
    {:ok, root} = Manifest.decode(body)
    {body, root}
  end

  defp object?(ctx, key), do: Agent.get(ctx.agent, &Map.has_key?(&1.objects, key))

  defp expected(segments, start, finish, service) do
    matching =
      Enum.filter(segments, fn s ->
        Segment.intersects?(s, start, finish) and (service == nil or service in s.log_services)
      end)

    %{segments: length(matching), entries: Enum.sum_by(matching, & &1.row_count)}
  end

  defp stats(ctx, start, finish, service) do
    opts = [start_ts: start, end_ts: finish] ++ if(service, do: [service: service], else: [])
    {:ok, stats} = S3.log_index_stats(ctx.tenant, opts)
    Map.take(stats, [:segments, :entries])
  end

  test "a flat history converts on its next append and stays exactly queryable from a bounded root", ctx do
    history = history(ctx.tenant, 9000)
    put_root(ctx, %Manifest{version: 1, segments: history})
    {flat_body, _} = root(ctx)

    assert :ok = S3.append(:logs, ctx.tenant, [%Log{timestamp_ns: 10_000_000_000, service: "api", body: "new"}])

    {body, converted} = root(ctx)
    assert converted.version == 4
    assert JournalManifest.referenced(converted) == 9001
    assert byte_size(body) < div(byte_size(flat_body), 50)
    # 9000 entries span more than 16 leaves, so part of history moved into an index page.
    assert Enum.any?(converted.paging["refs"], &(&1["h"] == 1))

    {:ok, [new]} = S3.query(:logs, ctx.tenant, start_ts: 9_999_999_999)
    all = converted.segments ++ history

    # Page references carry their subtree's stored bytes, through index pages too.
    assert {spans, 0} = JournalManifest.referenced_bytes(converted)
    assert Enum.sum_by(spans, &elem(&1, 2)) == Enum.sum_by(all, & &1.byte_size)

    for {start, finish, service} <- [
          {0, 99_999_999_999, nil},
          {2_000_000_000, 2_500_000_000, nil},
          {3_000_000_000, 5_000_000_000, "kura"},
          {4_499_999_800, 4_500_000_200, nil},
          {8_000_000_000, 10_000_000_000, "api"}
        ] do
      assert stats(ctx, start, finish, service) == expected(all, start, finish, service)
    end

    assert new.body == "new"
  end

  test "replacement replans after unrelated maintenance changes the same journal page", ctx do
    [first, second | _] = history = history(ctx.tenant, 600)
    put_root(ctx, %Manifest{version: 1, segments: history})
    assert :ok = S3.append(:logs, ctx.tenant, [%Log{timestamp_ns: 10_000_000_000, service: "api", body: "new"}])
    before = stats(ctx, 0, 20_000_000_000, nil)
    replacement = %{first | key: String.replace(first.key, "-rand-", "-compact-")}
    other = %{second | key: String.replace(second.key, "-rand-", "-compact-")}
    parent = self()
    Agent.update(ctx.agent, &%{&1 | barriers: %{{"PUT", :page} => parent}})
    tasks = start_supervised!(Task.Supervisor)

    pending =
      Task.Supervisor.async_nolink(tasks, fn ->
        MetricTiers.publish(ctx.tenant, ctx.config, [first.key], [replacement], 60_000, "logs")
      end)

    assert_receive {:storage_barrier, storage, "PUT", page}, 30_000
    Agent.update(ctx.agent, &%{&1 | barriers: %{}})
    assert :ok = MetricTiers.publish(ctx.tenant, ctx.config, [second.key], [other], 60_000, "logs")
    send(storage, {:release_storage, page})
    assert :ok = Task.await(pending, 60_000)

    {_, current} = root(ctx)

    for source <- [first, second] do
      assert {:ok, {:retired, _}} = JournalManifest.lookup(current, source, ctx.tenant, "logs", ctx.config)
    end

    for output <- [replacement, other] do
      assert {:ok, :active} = JournalManifest.lookup(current, output, ctx.tenant, "logs", ctx.config)
    end

    assert stats(ctx, 0, 20_000_000_000, nil) == before
  end

  test "a narrow window reads only the pages on its path, not the rest of history", ctx do
    put_root(ctx, %Manifest{version: 1, segments: history(ctx.tenant, 9000)})
    assert :ok = S3.append(:logs, ctx.tenant, [%Log{timestamp_ns: 10_000_000_000, service: "api", body: "new"}])
    {_, root} = root(ctx)

    journal_gets = fn ->
      Agent.get(ctx.agent, fn s -> Enum.count(s.requests, fn {m, k} -> m == "GET" and k =~ "/journal/" end) end)
    end

    for {start, finish} <- [{4_499_999_800, 4_500_000_200}, {8_999_000_000, 9_000_000_600}] do
      MetadataCache.clear()
      Agent.update(ctx.agent, &%{&1 | requests: []})
      assert stats(ctx, start, finish, nil) == expected(history(ctx.tenant, 9000), start, finish, nil)
      # One index page and one leaf at most, of more than 16 leaves in all.
      assert journal_gets.() <= 2
    end

    assert Enum.sum_by(root.paging["refs"], & &1["l"]) > 16
  end

  test "limited plans order nested subtrees and inline candidates in both directions, including ties", ctx do
    segments =
      for i <- 1..20_000 do
        min = div(i, 700) * 10_000 + rem(i, 3)
        max = min + 100 + rem(i, 5)
        key = S3.object_key(ctx.tenant, "logs", min, max, Integer.to_string(i, 16), nil)
        %{Segment.build(key, min, max, 1, 100) | log_services: [if(rem(i, 3) == 0, do: "api", else: "web")]}
      end

    assert {:ok, root} =
             JournalManifest.convert(%Manifest{version: 2, segments: segments}, ctx.tenant, "logs", ctx.config)

    inline = Enum.at(segments, 2)
    inline = %{inline | key: String.replace_suffix(inline.key, ".parquet", "-inline.parquet")}
    # An inline entry competes with index and leaf bounds at a tied time.
    root = %{root | segments: [inline]}
    all = [inline | segments]

    for order <- [:backward, :forward], n <- [1, 17, 700] do
      rank = if order == :backward, do: &{-&1.max_ts, &1.key}, else: &{&1.min_ts, &1.key}
      expected = all |> Enum.filter(&("api" in &1.log_services)) |> Enum.sort_by(rank) |> Enum.take(n)
      opts = [service: "api", log_window: {order, n}, max_scan_segments: n]
      assert {:ok, actual} = JournalManifest.query(root, ctx.tenant, "logs", opts, ctx.config)
      assert actual == expected
    end
  end

  test "appends spill into pages, keyed retries stay idempotent and every root stays bounded", ctx do
    keyed =
      for i <- 1..1500 do
        min = 1_000_000_000 + i * 1_000_000
        key = S3.object_key(ctx.tenant, "logs", min, min + 10, "c#{i}", "retry-#{i}")
        %{Segment.build(key, min, min + 10, 2, 900) | log_services: ["api"]}
      end

    sizes =
      for batch <- Enum.chunk_every(keyed, 100) do
        assert :ok = ManifestOwner.register_segments(ctx.tenant, "logs", batch, ctx.config)
        {body, _} = root(ctx)
        byte_size(body)
      end

    {_, root} = root(ctx)
    assert JournalManifest.referenced(root) == 1500
    assert root.paging["refs"] != []
    assert Enum.max(sizes) < 200_000

    # The first batch now lives only in leaf pages; retrying it changes nothing.
    first = Enum.take(keyed, 100)
    assert Enum.all?(first, fn s -> not Enum.any?(root.segments, &(&1.key == s.key)) end)
    assert :ok = ManifestOwner.register_segments(ctx.tenant, "logs", first, ctx.config)
    {_, retried} = root(ctx)
    assert JournalManifest.referenced(retried) == 1500
    assert stats(ctx, 0, nil, nil) == %{segments: 1500, entries: 3000}
  end

  test "a missing page fails queries closed instead of returning part of the history", ctx do
    put_root(ctx, %Manifest{version: 1, segments: history(ctx.tenant, 2000)})
    assert :ok = S3.append(:logs, ctx.tenant, [%Log{timestamp_ns: 10_000_000_000, service: "api", body: "new"}])
    {_, root} = root(ctx)
    leaf = hd(root.paging["refs"])["k"]
    Agent.update(ctx.agent, &%{&1 | objects: Map.delete(&1.objects, leaf)})
    MetadataCache.clear()

    assert {:error, _} = S3.log_index_stats(ctx.tenant, start_ts: 0)
  end

  test "compaction retires paged sources; cleanup deletes them and superseded pages", ctx do
    config = Map.put(ctx.config, :manifest_page_grace_ms, 0)
    Runtime.put_env(:pulse, S3, config)
    record = fn i -> %Log{timestamp_ns: i, service: "api", body: "line #{i}"} end

    for i <- 1..600, do: assert(:ok = S3.append(:logs, ctx.tenant, [record.(i)], idempotency_key: "line-#{i}"))

    {_, spilled} = root(ctx)
    assert spilled.paging["refs"] != []
    assert {:ok, before} = S3.query(:logs, ctx.tenant, [])
    assert length(before) == 600
    sources = Agent.get(ctx.agent, &for({key, _} <- &1.objects, String.ends_with?(key, ".parquet"), do: key))
    tail = MapSet.new(spilled.segments, & &1.key)
    {:ok, %{min_ts: paged}} = sources |> Enum.find(&(not MapSet.member?(tail, &1))) |> ManifestOwner.segment_from_key()

    merged = compact_all(ctx.tenant, config, 0)
    assert merged >= 600

    {_, compacted} = root(ctx)
    superseded = Enum.map(compacted.paging["g"], &hd/1)
    assert superseded != []
    assert {:ok, ^before} = S3.query(:logs, ctx.tenant, [])

    deleted = cleanup_all(ctx.tenant, config, 0)
    assert deleted >= 600
    refute Enum.any?(sources, &object?(ctx, &1))
    refute Enum.any?(superseded, &object?(ctx, &1))

    {_, cleaned} = root(ctx)
    assert cleaned.paging["g"] == [] and cleaned.paging["gr"] == []
    refute JournalManifest.cleanup_pending?(%{cleaned | retired: %{}})

    # Fresh caches still find every referenced page.
    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)
    assert {:ok, ^before} = S3.query(:logs, ctx.tenant, [])

    # A keyed retry of a source that lived in a page re-uploads it; it stays
    # retired and the next cleanup deletes the copy again.
    assert :ok = S3.append(:logs, ctx.tenant, [record.(paged)], idempotency_key: "line-#{paged}")
    assert {:ok, ^before} = S3.query(:logs, ctx.tenant, [])
    assert cleanup_all(ctx.tenant, config, 0) == 1
    refute Enum.any?(sources, &object?(ctx, &1))
  end

  defp compact_all(tenant, config, total) do
    case LogCompactor.compact(tenant, config, grace_ms: 0) do
      {:ok, %{merged: 0}} -> total
      {:ok, %{merged: merged}} -> compact_all(tenant, config, total + merged)
    end
  end

  defp cleanup_all(tenant, config, total) do
    {:ok, deleted} = LogCompactor.cleanup(tenant, config)
    {:ok, root, _} = Retention.load(tenant, "logs", config)

    if deleted == 0 and root.paging["g"] == [] and root.paging["gr"] == [],
      do: total,
      else: cleanup_all(tenant, config, total + deleted)
  end

  test "retention enforcement reads a paged history whole into its own format", ctx do
    now = System.os_time(:nanosecond)

    history =
      for i <- 1..900 do
        min = now - i * 1_000_000_000
        key = S3.object_key(ctx.tenant, "logs", min, min + 500, "h#{i}", nil)
        Segment.build(key, min, min + 500, 3, 1000)
      end

    put_root(ctx, %Manifest{version: 1, segments: history})
    assert :ok = S3.append(:logs, ctx.tenant, [%Log{timestamp_ns: now, service: "api", body: "new"}])
    {_, paged} = root(ctx)
    assert paged.version == 4 and paged.paging["refs"] != []

    config =
      Map.merge(ctx.config, %{logs_retention_days: 30, retention_mode: "enforce", retention_manifest_format: "bucketed"})

    assert {:ok, %{floor_ns: _}} = Retention.advance(ctx.tenant, "logs", config)
    {_, managed} = root(ctx)
    assert managed.version == 3
    assert stats(ctx, 0, nil, nil) == %{segments: 901, entries: 2701}
  end
end
