defmodule Pulse.Storage.S3.MetricCatalogTest do
  @moduledoc """
  Hourly series catalogs answer label and series discovery exactly as the
  samples they cover, while reading series-sized objects: 100 series sampled
  in 60 flushes over two settled hours, plus one flush straddling them.
  """
  use Pulse.Test.Case, async: true

  alias Pulse.ObjectStore
  alias Pulse.Record.MetricSample
  alias Pulse.Runtime
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.JournalManifest
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.Manifest.Segment
  alias Pulse.Storage.S3.ManifestOwner
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Storage.S3.MetricCatalog
  alias Pulse.Storage.S3.MetricTiers
  alias Pulse.Storage.S3.Retention
  alias Pulse.Test.CompactionStore

  @minute 60_000_000_000
  @hour 60 * @minute

  @queries [
    {"names", "", []},
    {"names", "", [[{"__name__", :re, ".+"}]]},
    {"names", "", [[{"job", :eq, "job-3"}]]},
    {"values", "__name__", []},
    {"values", "job", [[{"job", :re, "job-[0-2]"}]]},
    {"values", "instance", [[{"__name__", :eq, "m_1"}]]},
    {"series", "", [[{"__name__", :eq, "m_2"}, {"job", :neq, "job-1"}], [{"__name__", :eq, "early"}]]},
    # Asymmetric: a metric under one job only, and a series without `job`.
    {"values", "__name__", [[{"job", :eq, "lonely"}]]},
    {"names", "", [[{"__name__", :eq, "lonely"}]]},
    {"series", "", [[{"__name__", :re, "unjobbed|m_1"}, {"job", :eq, ""}]]},
    {"values", "instance", [[{"__name__", :re, ".+"}, {"job", :eq, ""}]]}
  ]

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
      access_key_id: "catalog-#{System.unique_integer([:positive])}",
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0
    }

    Runtime.put_env(:pulse, S3, config)
    start_supervised!(ManifestSupervision)
    tenant = "catalog-#{System.unique_integer([:positive])}"
    manifest = IO.iodata_to_binary(Manifest.encode(Manifest.new()))
    {:ok, _} = ObjectStore.put(config, Manifest.manifest_key(tenant, "metrics"), manifest)

    h0 = div(System.os_time(:nanosecond), @hour) * @hour - 3 * @hour

    for n <- 0..59 do
      ts = h0 + n * 2 * @minute + @minute
      :ok = S3.append(:metrics, tenant, flush(ts, n))
    end

    # Only at the start of the first hour.
    lonely = %{sample(h0 + 1, "lonely", 0) | labels: %{"__name__" => "lonely", "job" => "lonely"}}
    unjobbed = %{sample(h0 + 1, "unjobbed", 0) | labels: %{"__name__" => "unjobbed", "instance" => "solo"}}
    :ok = S3.append(:metrics, tenant, [sample(h0 + 1, "early", 0), lonely, unjobbed])
    # One segment holding rows of both hours.
    :ok = S3.append(:metrics, tenant, [sample(h0 + @hour - 1, "edge", 0), sample(h0 + @hour, "edge", 1)])
    reads(agent)
    %{agent: agent, config: config, tenant: tenant, h0: h0}
  end

  defp sample(ts, name, target) do
    %MetricSample{
      timestamp_ns: ts,
      value: 1.0,
      labels: %{"__name__" => name, "instance" => "10.0.0.#{target}:9090", "job" => "job-#{rem(target, 5)}"}
    }
  end

  defp flush(ts, n), do: for(i <- 0..99, do: %{sample(ts, "m_#{rem(i, 10)}", div(i, 10)) | value: n * 1.0})

  defp reads(agent), do: agent |> read_keys() |> length()

  defp read_keys(agent) do
    Agent.get_and_update(agent, fn state ->
      {Enum.filter(state.reads, &String.ends_with?(&1, ".parquet")), %{state | reads: []}}
    end)
  end

  defp read_tiers(agent), do: agent |> read_keys() |> MapSet.new(&Segment.key_tier/1)

  defp discover(ctx, window, opts \\ []) do
    {start_ts, end_ts} = window

    for {mode, key, selectors} <- @queries do
      S3.metric_discovery_json(ctx.tenant, mode, key, selectors, [start_ts: start_ts, end_ts: end_ts] ++ opts)
    end
  end

  defp build_all(ctx, opts) do
    case MetricCatalog.build(ctx.tenant, ctx.config, opts) do
      {:ok, %{hours: 0}} -> :ok
      {:ok, _} -> build_all(ctx, opts)
    end
  end

  defp manifest(ctx) do
    {:ok, root, _} = Retention.load(ctx.tenant, "metrics", ctx.config)
    root.segments
  end

  defp catalogs(ctx), do: Enum.filter(manifest(ctx), &(Segment.metric_tier(&1) == :catalog))

  # Retire `keys` without replacements, as finalization retires an hour.
  defp retire(ctx, keys) do
    deadline = System.system_time(:millisecond) + 3_600_000

    {:ok, :ok} =
      ManifestOwner.transact(ctx.tenant, "metrics", ctx.config, fn
        %{version: 4} = root ->
          {:ok, updated} = JournalManifest.replace_all(root, keys, [], deadline, ctx.tenant, "metrics", ctx.config)
          {:ok, {sealed, payload, _}} = JournalManifest.seal(updated, ctx.tenant, "metrics", ctx.config)
          {:write, sealed, payload, :ok}

        root ->
          {:ok, updated} = Manifest.replace_all(root, keys, [], deadline)
          {:write, updated, updated |> Manifest.encode() |> IO.iodata_to_binary(), :ok}
      end)

    :ok
  end

  test "catalogs answer discovery like the samples they cover, reading series instead", ctx do
    hours = {ctx.h0, ctx.h0 + 2 * @hour - 1}
    expected = discover(ctx, hours)
    assert Enum.all?(expected, &match?({:ok, _}, &1))
    raw_reads = reads(ctx.agent)
    # 6,005 sample rows over 63 segments in each broad query; postings prune
    # the asymmetric ones.
    limited = discover(ctx, hours, max_scan_rows: 1_000)
    assert limited |> Enum.take(7) |> Enum.all?(&(&1 == {:error, :query_scan_limit}))
    reads(ctx.agent)

    # Small passes write several deltas per hour; the third catalog of an
    # hour merges them.
    :ok = build_all(ctx, max_rows: 1_500, merge_at: 3)
    assert catalogs(ctx) |> Enum.frequencies_by(& &1.min_ts) |> Map.values() |> Enum.all?(&(&1 <= 2))
    reads(ctx.agent)

    assert discover(ctx, hours) == expected
    catalog_reads = reads(ctx.agent)
    assert catalog_reads == length(@queries) * length(catalogs(ctx))
    assert catalog_reads < raw_reads
    # Each hour lists 102 series: names and values read a few rows.
    assert discover(ctx, hours, max_scan_rows: 1_000) == expected

    # A settled hour's catalogs merge into one.
    :ok = build_all(ctx, settle_ms: 0)
    assert catalogs(ctx) |> Enum.map(& &1.min_ts) |> Enum.sort() == [ctx.h0, ctx.h0 + @hour]
    reads(ctx.agent)
    assert discover(ctx, hours) == expected
    assert reads(ctx.agent) == 2 * length(@queries)

    # A segment written later is read until a catalog covers it.
    :ok = S3.append(:metrics, ctx.tenant, [sample(ctx.h0 + @hour + 5 * @minute, "late", 7)])
    late = discover(ctx, hours)
    assert {:ok, names} = Enum.at(late, 3)
    assert "late" in Pulse.JSON.decode!(names)
    assert read_tiers(ctx.agent) == MapSet.new([:catalog, :raw])

    # Grouped and finalized outputs of covered sources stay covered.
    :ok = build_all(ctx, [])
    opts = [consolidate_settle_ms: 0, consolidate_min_rows: 1, consolidate_max_rows: 60_000]

    assert {:ok, %{hour: _}} =
             MetricTiers.consolidate(ctx.tenant, ctx.config, Keyword.put(opts, :consolidate_max_sources, 10))

    assert {:ok, %{finals: finals}} = MetricTiers.finalize_hour(ctx.tenant, ctx.h0, ctx.config, [])
    assert finals > 0
    outputs = Enum.filter(manifest(ctx), &(Segment.metric_tier(&1) in [:grouped, :final]))
    assert outputs != [] and Enum.all?(outputs, &is_binary(&1.catalog))
    reads(ctx.agent)

    assert discover(ctx, hours) == late
    # Only catalogs and the edge rows finalization moved out of the hour.
    assert read_tiers(ctx.agent) == MapSet.new([:catalog, :raw])
  end

  test "outputs stamped by catalogs that a rollback retired are read again", ctx do
    hours = {ctx.h0, ctx.h0 + 2 * @hour - 1}
    :ok = build_all(ctx, settle_ms: 0)
    opts = [consolidate_settle_ms: 0, consolidate_min_rows: 1, consolidate_max_rows: 60_000]
    assert {:ok, %{hour: hour}} = MetricTiers.consolidate(ctx.tenant, ctx.config, opts)
    stamped = Enum.filter(manifest(ctx), &(Segment.metric_tier(&1) == :grouped))
    assert stamped != [] and Enum.all?(stamped, &(is_binary(&1.catalog) and &1.min_ts >= hour))

    # Releases that predate catalogs read `-rollup-` keys as rollups and
    # retire them with the hour's other sources when they finalize it.
    lost = catalogs(ctx)
    assert Enum.all?(lost, &String.contains?(&1.key, "-rollup-catalog-"))
    :ok = retire(ctx, Enum.map(lost, & &1.key))
    :ok = S3.append(:metrics, ctx.tenant, [sample(hour + 1, "late", 7)])
    expected = discover(ctx, hours)

    # A catalog of a fresh lineage covering only the oldest segments, the
    # straddling and the new one, does not cover the stamped outputs.
    assert {:ok, %{hours: 1, sources: 2}} =
             MetricCatalog.build(ctx.tenant, ctx.config, max_sources: 2, min_hour: hour, max_hour: hour)

    assert [fresh] = catalogs(ctx)
    refute MetricCatalog.lineage(fresh.key) in Enum.map(lost, &MetricCatalog.lineage(&1.key))
    reads(ctx.agent)

    assert discover(ctx, hours) == expected
    assert MapSet.subset?(MapSet.new([:catalog, :grouped]), read_tiers(ctx.agent))
  end

  test "an hour with a catalog is discovered whole, others by sample time", ctx do
    end_of_first = {ctx.h0 + 50 * @minute, ctx.h0 + @hour - 2}
    early = ~s|{"__name__":"early","instance":"10.0.0.0:9090","job":"job-0"}|

    assert {:ok, "[]"} =
             S3.metric_discovery_json(ctx.tenant, "series", "", [[{"__name__", :eq, "early"}]],
               start_ts: elem(end_of_first, 0),
               end_ts: elem(end_of_first, 1)
             )

    :ok = build_all(ctx, settle_ms: 0)

    assert {:ok, "[" <> ^early <> "]"} =
             S3.metric_discovery_json(ctx.tenant, "series", "", [[{"__name__", :eq, "early"}]],
               start_ts: elem(end_of_first, 0),
               end_ts: elem(end_of_first, 1)
             )
  end
end
