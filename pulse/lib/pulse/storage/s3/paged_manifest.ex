defmodule Pulse.Storage.S3.PagedManifest do
  @moduledoc """
  Format-3 manifests: one CAS root, an inline tail and immutable bucket pages.
  All pages precede root publication. Superseded pages belong to the bucket
  that produced them and are reclaimed with it, never a lifetime garbage map.
  """
  import Kernel, except: [floor: 1]

  alias Pulse.ObjectStore
  alias Pulse.Storage.S3.JournalManifest
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.Manifest.Retirement
  alias Pulse.Storage.S3.Manifest.Segment
  alias Pulse.Storage.S3.ManifestOwner
  alias Pulse.Storage.S3.MetadataCache
  alias Pulse.Storage.S3.Retention
  alias Pulse.Storage.S3.RetentionCatchup
  alias Pulse.Storage.S3.TraceSummary

  @root_bytes 524_288
  @leaf_bytes 65_536
  @index_bytes 524_288
  # Reserve two worst-case refs for expiry (the tail is at most one leaf),
  # Owner batches add at most 64 KiB of wire entries; together with the
  # committed tail they need at most four refs (byte/count chunk boundaries).
  # Never assume tiny metric refs.
  @reference_bytes 4096
  @expiry_reserve 2 * @reference_bytes
  @day_ns 86_400_000_000_000

  def nonce, do: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  def floor(%Manifest{paging: nil}), do: nil
  def floor(%Manifest{paging: p}), do: p["floor"]
  def root_limit, do: @root_bytes
  def scope(tenant, signal), do: "tenants/#{tenant}/v4/signal=#{signal}/"
  def marker(tenant, signal), do: scope(tenant, signal) <> ".managed"
  def bucket_prefix(tenant, signal, bucket), do: scope(tenant, signal) <> "index/#{bucket["start"]}/#{bucket["id"]}/"
  def bucket_start(p, timestamp), do: div(timestamp, p["width"]) * p["width"]

  def validate(%{"floor" => f, "days" => d, "width" => w, "buckets" => buckets, "nonce" => n} = p) do
    # Each predicate checks types before any arithmetic that depends on them.
    valid =
      valid_header?(f, d, w, buckets) and hex32?(n) and hex32?(p["seed"]) and valid_floors?(p, f) and
        Enum.all?(buckets, &valid_bucket?(&1, w, f)) and length(Enum.uniq_by(buckets, & &1["start"])) == length(buckets) and
        valid_reclaimed?(p, buckets, w) and valid_cursors?(p, w)

    if valid, do: :ok, else: {:error, :invalid_manifest}
  end

  def validate(_), do: {:error, :invalid_manifest}

  defp optional?(map, key, predicate), do: map[key] == nil or predicate.(map[key])

  defp valid_header?(f, d, w, buckets) do
    non_negative?(f) and is_integer(d) and d in 1..3650 and is_integer(w) and w > 0 and is_list(buckets) and
      length(buckets) <= 2048
  end

  defp hex32?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)
  defp non_negative?(value), do: is_integer(value) and value >= 0
  defp within?(value, maximum), do: non_negative?(value) and value <= maximum

  defp valid_floors?(p, f),
    do: within?(p["aged_floor"], f) and within?(p["pending_floor"], f) and non_negative?(p["pending_after"])

  defp valid_bucket?(b, w, f) do
    is_map(b) and valid_bucket_identity?(b, w) and valid_bucket_progress?(b) and valid_bucket_options?(b) and
      valid_bucket_span?(b, w) and valid_bucket_teardown?(b, f)
  end

  defp valid_bucket_identity?(b, w),
    do:
      non_negative?(b["start"]) and rem(b["start"], w) == 0 and hex32?(b["id"]) and
        b["state"] in ["live", "data", "pages"]

  defp valid_bucket_progress?(b) do
    within?(b["cursor"], 1024) and non_negative?(b["min"]) and is_integer(b["max"]) and b["min"] <= b["max"] and
      non_negative?(b["mutations"]) and non_negative?(b["written"])
  end

  defp valid_bucket_options?(b) do
    (b["index"] == nil or is_map(b["index"])) and optional?(b, "failed", &valid_failures?/1) and
      Enum.all?(["retired_cursor", "retire_after", "leaf_count"], &optional?(b, &1, fn v -> non_negative?(v) end)) and
      optional?(b, "legacy_gc", &is_boolean/1)
  end

  defp valid_failures?(list),
    do: is_list(list) and length(list) <= 1024 and Enum.all?(list, &(is_integer(&1) and &1 in 0..1023))

  # Only legacy closed-GC buckets may span more than their own width.
  defp valid_bucket_span?(b, w), do: b["legacy_gc"] == true or (b["max"] >= b["start"] and b["max"] < b["start"] + w)

  # A bucket leaves "live" only once wholly below the floor, with a deadline.
  defp valid_bucket_teardown?(%{"state" => "live"}, _f), do: true
  defp valid_bucket_teardown?(b, f), do: b["max"] < f and non_negative?(b["deadline"])

  defp valid_reclaimed?(p, buckets, w) do
    within?(p["reclaimed"], p["aged_floor"]) and Enum.all?(buckets, &(&1["start"] + w > p["reclaimed"]))
  end

  defp valid_cursors?(p, w) do
    Enum.all?(
      ["cleanup_bucket", "retired_bucket", "compaction_bucket", "sweep_day", "metadata_sweep_start"] ++
        ["legacy_sweep_start", "legacy_gc_end"],
      &optional?(p, &1, fn v -> non_negative?(v) end)
    ) and optional?(p, "catchup", &RetentionCatchup.valid?(&1, p["reclaimed"], w)) and
      Enum.all?(
        ["sweep_after", "sweep_prefix", "metadata_sweep_after", "legacy_sweep_after"],
        &optional?(p, &1, fn v -> is_binary(v) and byte_size(v) <= 1024 end)
      )
  end

  def managed?(config, tenant, signal) do
    case ObjectStore.get_bounded(config, marker(tenant, signal), nil, 1024) do
      {:ok, _, _} -> {:ok, true}
      {:error, :not_found} -> {:ok, false}
      {:error, _} = error -> error
    end
  end

  def check_create(config, tenant, signal) do
    case managed?(config, tenant, signal) do
      {:ok, false} -> :ok
      {:ok, true} -> {:error, :managed_manifest_missing}
      error -> error
    end
  end

  def migrate(manifest, tenant, signal, days, config) do
    with_budget(config, fn ->
      hour = 3_600_000_000_000
      window = Retention.window_ns(days, config, signal)
      required_hours = div(window + 508 * hour - 1, 508 * hour)
      width = Map.get(config, :retention_bucket_width_ns, max(1, required_hours) * hour)
      if div(days * @day_ns, width) + 4 > 2048, do: fail(:retention_capacity)
      initial_floor = Map.get(config, :retention_initial_floor, 0)

      p = %{
        "seed" => Map.get(config, :retention_seed, nonce()),
        "floor" => initial_floor,
        "days" => days,
        "width" => width,
        "buckets" => [],
        "nonce" => nonce(),
        "reclaimed" => 0,
        "aged_floor" => 0,
        "pending_floor" => 0,
        "pending_after" => 0,
        "sweep_after" => nil,
        "sweep_prefix" => nil
      }

      Enum.each(manifest.segments, &validate_segment!(&1, tenant, signal))

      Enum.each(manifest.retired, fn {key, _} -> key |> key_segment!() |> validate_segment!(tenant, signal) end)

      root = %{manifest | version: 3, segments: [], retired: %{}, cleanup_cursor: nil, paging: p}
      closed? = fn timestamp -> bucket_start(p, timestamp) + width <= initial_floor end
      {expired, retained} = Enum.split_with(manifest.segments, &closed?.(&1.max_ts))

      {old_retired, current_retired} =
        Enum.split_with(manifest.retired, fn {key, _} -> closed?.(key_segment!(key).max_ts) end)

      old_entries =
        Enum.map(expired, &Map.take(Segment.to_wire(&1), ["k", "mn", "mx"])) ++
          Enum.map(old_retired, fn {key, _} ->
            {:ok, s} = ManifestOwner.segment_from_key(key)
            Map.take(Segment.to_wire(s), ["k", "mn", "mx"])
          end)

      old_chunks = old_entries |> chunk() |> Enum.chunk_every(1024) |> Enum.map(&List.flatten/1)

      {retained, current_retired, old_chunks} =
        if initial_floor >= width * (length(old_chunks) + 1),
          do: {retained, current_retired, old_chunks},
          else: {manifest.segments, Enum.to_list(manifest.retired), []}

      root =
        Enum.reduce(retained, root, fn s, r ->
          validate_segment!(s, tenant, signal)
          add_inline(r, s)
        end)

      root = spill(root, tenant, signal, config)

      deadline =
        max(
          Map.get(config, :retention_initial_now_ms, System.system_time(:millisecond)) +
            Map.get(config, :retention_delete_grace_ms, 3_600_000),
          old_retired |> Enum.map(fn {_, r} -> r.delete_after end) |> Enum.max(fn -> 0 end)
        )

      root = %{root | paging: Map.put(root.paging, "legacy_gc_end", length(old_chunks) * width)}

      root =
        Enum.with_index(old_chunks)
        |> Enum.reduce(root, fn {entries, i}, r ->
          bucket = %{
            "start" => i * width,
            "id" => digest(p["seed"] <> ":gc:#{i}") |> binary_part(0, 32),
            "index" => nil,
            "min" => Enum.min(Enum.map(entries, & &1["mn"])),
            "max" => Enum.max(Enum.map(entries, & &1["mx"])),
            "state" => "data",
            "deadline" => deadline,
            "cursor" => 0,
            "list_after" => nil,
            "mutations" => 0,
            "written" => 0,
            "legacy_gc" => true
          }

          r = put_bucket(r, bucket)
          append_leaf(r, bucket, "active", entries, tenant, signal, config)
        end)

      grouped = Enum.group_by(current_retired, fn {key, _} -> bucket_start(p, key_segment!(key).max_ts) end)

      root = Enum.reduce(grouped, root, &add_retired_group(&1, &2, p, tenant, signal, config))
      bounded(root, config)
    end)
  end

  defp key_segment!(key) do
    case ManifestOwner.segment_from_key(key) do
      {:ok, s} -> s
      _ -> fail(:invalid_segment_key)
    end
  end

  # Retirement identities derive from the marker seed, so a restarted
  # conversion rewrites identical pages.
  defp add_retired_group({_start, entries}, root, p, tenant, signal, config) do
    {root, rows} = Enum.reduce(entries, {root, []}, &add_retired_row(&1, &2, p["seed"]))
    {:ok, s} = hd(entries) |> elem(0) |> ManifestOwner.segment_from_key()
    append_leaf(root, bucket!(root, bucket_start(p, s.max_ts)), "retired", rows, tenant, signal, config)
  end

  defp add_retired_row({key, retirement}, {root, rows}, seed) do
    {:ok, s} = ManifestOwner.segment_from_key(key)
    {root, _} = ensure_bucket(root, s)
    ret = Retirement.to_wire(retirement) |> Map.put("id", digest(seed <> key) |> binary_part(0, 32))
    {root, [%{"k" => key, "mn" => s.min_ts, "mx" => s.max_ts, "ret" => ret} | rows]}
  end

  def eligible(root, segment, now_ns, config) do
    cond do
      not is_integer(segment.min_ts) or segment.min_ts < floor(root) ->
        {:error, :retention_expired}

      segment.max_ts > now_ns + Map.get(config, :retention_future_skew_ms, 600_000) * 1_000_000 ->
        {:error, :timestamp_too_new}

      true ->
        :ok
    end
  end

  def check_capacity(root, segment, config) do
    with_budget(config, fn ->
      start = bucket_start(root.paging, segment.max_ts)
      root.paging["buckets"] |> Enum.find(&(&1["start"] == start)) |> bucket_capacity!(root, config)
      :ok
    end)
  end

  # A new bucket needs a descriptor and root room for one more leaf reference.
  defp bucket_capacity!(nil, root, config) do
    base_bytes = IO.iodata_length(Manifest.encode(%{root | segments: []}))

    if length(root.paging["buckets"]) >= Map.get(config, :retention_max_buckets, 2048) or
         base_bytes > @root_bytes - @leaf_bytes - 1024,
       do: fail(:retention_capacity)
  end

  defp bucket_capacity!(bucket, _root, config) do
    if Map.get(bucket, "leaf_count", 0) >= 1020 or
         (bucket["index"] && bucket["index"]["b"] > @index_bytes - @expiry_reserve - 4 * @reference_bytes),
       do: fail(:retention_capacity)

    ensure_mutable!(bucket, config)
  end

  def register(root, segments, tenant, signal, config) do
    with_budget(config, fn ->
      starts =
        Map.get(
          config,
          :retention_affected_buckets,
          Enum.map(segments, &bucket_start(root.paging, &1.max_ts)) |> Enum.uniq()
        )

      if length(starts) > 4, do: fail(:retention_capacity)
      now = System.system_time(:nanosecond)
      root = Enum.reduce(segments, root, &register_segment(&2, &1, now, tenant, signal, config))
      tail_bytes = root.segments |> Enum.map(&Segment.to_wire/1) |> Pulse.JSON.encode_to_iodata!() |> IO.iodata_length()
      root = %{root | paging: %{root.paging | "nonce" => nonce()}}

      if length(root.segments) >= Map.get(config, :retention_tail_entries, 256) or tail_bytes >= @leaf_bytes do
        bounded(spill(root, tenant, signal, config, starts), config)
      else
        bounded(root, config)
      end
    end)
  end

  # Every attempt re-fences against the latest root; a retried segment is
  # refreshed or revived in place rather than registered twice.
  defp register_segment(root, s, now, tenant, signal, config) do
    validate_segment!(s, tenant, signal)

    case eligible(root, s, now, config) do
      :ok -> :ok
      {:error, reason} -> fail(reason)
    end

    case lookup(root, s, tenant, signal, config) do
      :active ->
        refresh_active(root, s, tenant, signal, config)

      {:retired, ref, entry, bucket} ->
        revive_retired(root, s, ref, entry, bucket, tenant, signal, config)

      :absent ->
        start = bucket_start(root.paging, s.max_ts)
        bucket_capacity!(Enum.find(root.paging["buckets"], &(&1["start"] == start)), root, config)
        add_inline(root, s)
    end
  end

  defp revive_retired(root, s, ref, entry, bucket, tenant, signal, config) do
    ret = Map.update!(entry["ret"], "g", &(&1 + 1)) |> Map.put("x", false)
    update = fn entries -> Enum.map(entries, &if(&1["k"] == s.key, do: %{&1 | "ret" => ret}, else: &1)) end
    rewrite(root, bucket, "retired", ref, update, tenant, signal, config)
  end

  defp refresh_active(root, segment, tenant, signal, config) do
    wire = Segment.to_wire(segment)

    if Enum.any?(root.segments, &(&1.key == segment.key)) do
      %{root | segments: Enum.map(root.segments, fn s -> if s.key == segment.key, do: segment, else: s end)}
    else
      bucket = bucket!(root, bucket_start(root.paging, segment.max_ts))

      ref =
        Enum.find(index(bucket, tenant, signal, config)["active"], fn ref ->
          segment.max_ts >= (ref["min_max"] || ref["min"]) and segment.max_ts <= ref["max"] and
            Enum.any?(page(ref, bucket, tenant, signal, config, @leaf_bytes), &(&1["k"] == segment.key and &1 != wire))
        end)

      if ref, do: replace_entry(root, bucket, ref, segment.key, wire, tenant, signal, config), else: root
    end
  end

  defp replace_entry(root, bucket, ref, key, wire, tenant, signal, config) do
    update = fn entries -> Enum.map(entries, &if(&1["k"] == key, do: wire, else: &1)) end
    rewrite(root, bucket, "active", ref, update, tenant, signal, config)
  end

  def candidates(root, tenant, signal, config) do
    with_budget(config, fn ->
      cursor = root.paging["compaction_bucket"]
      buckets = Enum.filter(root.paging["buckets"], &(&1["state"] == "live"))
      bucket = Enum.find(buckets, &(cursor == nil or &1["start"] > cursor)) || List.first(buckets)

      if bucket do
        refs = index(bucket, tenant, signal, config)["active"] |> Enum.take(4)
        paged = Enum.flat_map(refs, &page_segments(&1, bucket, tenant, signal, config))

        inline = Enum.filter(root.segments, &(bucket_start(root.paging, &1.max_ts) == bucket["start"]))

        %{
          root
          | segments: Enum.filter(inline ++ paged, &(&1.min_ts >= floor(root))),
            paging: Map.put(root.paging, "compaction_candidate", bucket["start"])
        }
      else
        %{root | segments: []}
      end
    end)
  end

  def query(root, tenant, signal, opts, config) do
    # Sparse ranges need bounded index fanout. Exact trace lookup additionally
    # reserves 64 KiB per live overlapping bucket for pruning indexes, capped at
    # 32 MiB total. Explicit caller configuration is never raised. Maintenance
    # and all other searches keep the original 8 MiB default.
    config =
      Map.put(
        config,
        :retention_metadata_pages,
        max(Map.get(config, :retention_metadata_pages, 128), 128 + 2 * length(root.paging["buckets"]))
      )

    config = Map.put_new(config, :retention_metadata_scan_bytes, query_metadata_bytes(root, signal, opts))

    with_budget(config, fn ->
      Enum.each(root.segments, &validate_segment!(&1, tenant, signal))
      start_ts = max(floor(root), Keyword.get(opts, :start_ts) || floor(root))
      end_ts = Keyword.get(opts, :end_ts)

      if end_ts != nil and end_ts < start_ts do
        []
      else
        scan = %{
          start_ts: start_ts,
          end_ts: end_ts,
          # Limited trace scans charge objects actually visited. Metadata remains
          # independently page/byte bounded; do not reject older candidates that
          # a strict native timestamp boundary can safely skip.
          maximum: query_maximum(signal, opts),
          opts: opts,
          match: fn s -> Segment.intersects?(s, start_ts, end_ts) and matches?(s, signal, opts) end
        }

        scan_live(root, scan, tenant, signal, config)
      end
    end)
  end

  defp limited_trace_scan?("traces", opts),
    do:
      is_nil(opts[:trace_search]) and is_nil(opts[:tempo_search]) and is_nil(opts[:tempo_discovery]) and
        is_integer(opts[:limit]) and opts[:limit] in 1..5000

  defp limited_trace_scan?(_signal, _opts), do: false

  defp query_maximum(signal, opts) do
    cond do
      signal == "traces" and opts[:tempo_search] != nil ->
        TraceSummary.plan_catalog_limit()

      limited_trace_scan?(signal, opts) ->
        nil

      # Limited log queries plan their window in the storage adapter and
      # charge only the segments they visit.
      signal == "logs" and opts[:log_window] != nil ->
        nil

      true ->
        opts[:max_scan_segments] || 1024
    end
  end

  defp query_metadata_bytes(root, "traces", opts) do
    if is_binary(opts[:trace_id]) and byte_size(opts[:trace_id]) == 32 do
      start = max(floor(root), opts[:start_ts] || floor(root))
      live = Enum.count(root.paging["buckets"], &(&1["state"] == "live" and intersects?(&1, start, opts[:end_ts])))
      min(32 * 1024 * 1024, 8 * 1024 * 1024 + live * 64 * 1024)
    else
      8 * 1024 * 1024
    end
  end

  defp query_metadata_bytes(_root, _signal, _opts), do: 8 * 1024 * 1024

  # Reads one index per overlapping live bucket and only overlapping leaves;
  # exceeding the segment budget fails rather than truncating.
  defp scan_live(root, scan, tenant, signal, config) do
    result =
      root.paging["buckets"]
      |> Enum.filter(&(&1["state"] == "live" and intersects?(&1, scan.start_ts, scan.end_ts)))
      |> Enum.reduce(Enum.filter(root.segments, scan.match), &scan_bucket(&1, &2, scan, tenant, signal, config))

    if scan.maximum != nil and length(result) > scan.maximum, do: too_many(scan.maximum, length(result))
    Enum.sort_by(result, & &1.max_ts, :desc)
  end

  defp scan_bucket(bucket, rows, scan, tenant, signal, config) do
    index(bucket, tenant, signal, config)["active"]
    |> Enum.filter(&(intersects?(&1, scan.start_ts, scan.end_ts) and leaf_matches?(&1, signal, scan.opts)))
    |> Enum.reduce(rows, fn ref, rows ->
      found = ref |> page_segments(bucket, tenant, signal, config) |> Enum.filter(scan.match)

      if scan.maximum != nil and length(rows) + length(found) > scan.maximum,
        do: too_many(scan.maximum, length(rows) + length(found))

      found ++ rows
    end)
  end

  defp too_many(maximum, count) do
    Pulse.QueryLimit.exceeded(:max_scan_segments, maximum, count, :candidates)
    fail(:query_scan_limit)
  end

  defp page_segments(ref, bucket, tenant, signal, config),
    do: ref |> page(bucket, tenant, signal, config, @leaf_bytes) |> Enum.map(&segment!/1)

  def lookup(root, segment, tenant, signal, config, opts \\ []) do
    allow_closed = Keyword.get(opts, :allow_closed, false)

    if Enum.any?(root.segments, &(&1.key == segment.key)) do
      :active
    else
      root
      |> lookup_bucket(segment, allow_closed)
      |> lookup_in_bucket(segment, allow_closed, tenant, signal, config)
    end
  end

  # Closed legacy GC buckets are only consulted when explicitly allowed.
  defp lookup_bucket(root, segment, allow_closed) do
    Enum.find(root.paging["buckets"], &(&1["start"] == bucket_start(root.paging, segment.max_ts))) ||
      if(allow_closed,
        do:
          Enum.find(
            root.paging["buckets"],
            &(&1["legacy_gc"] == true and segment.max_ts >= &1["min"] and segment.max_ts <= &1["max"])
          )
      )
  end

  defp lookup_in_bucket(nil, _segment, _allow_closed, _tenant, _signal, _config), do: :absent

  defp lookup_in_bucket(bucket, segment, allow_closed, tenant, signal, config) do
    if bucket["state"] != "live" and not allow_closed, do: fail(:retention_expired)
    idx = index(bucket, tenant, signal, config)

    Enum.find_value(["retired", "active"], :absent, fn kind ->
      Enum.find_value(idx[kind], &find_entry(&1, kind, bucket, segment, tenant, signal, config))
    end)
  end

  defp find_entry(ref, kind, bucket, segment, tenant, signal, config) do
    if ref_covers?(ref, segment.max_ts) do
      case Enum.find(page(ref, bucket, tenant, signal, config, @leaf_bytes), &(&1["k"] == segment.key)) do
        nil -> nil
        _entry when kind == "active" -> :active
        entry -> {:retired, ref, entry, bucket}
      end
    end
  end

  defp ref_covers?(ref, timestamp), do: timestamp >= (ref["min_max"] || ref["min"]) and timestamp <= ref["max"]

  def active?(root, segment, tenant, signal, config) do
    Enum.any?(root.segments, &(&1.key == segment.key)) or
      root.paging["buckets"]
      |> Enum.find(&(&1["start"] == bucket_start(root.paging, segment.max_ts)))
      |> paged_active?(segment, tenant, signal, config)
  end

  defp paged_active?(nil, _segment, _tenant, _signal, _config), do: false

  defp paged_active?(bucket, segment, tenant, signal, config) do
    Enum.any?(index(bucket, tenant, signal, config)["active"], fn ref ->
      ref_covers?(ref, segment.max_ts) and
        Enum.any?(page(ref, bucket, tenant, signal, config, @leaf_bytes), &(&1["k"] == segment.key))
    end)
  end

  def replace(root, sources, replacement, deadline, tenant, signal, config) do
    with_budget(config, fn ->
      validate_segment!(replacement, tenant, signal)
      starts = Enum.map([replacement | sources], &bucket_start(root.paging, &1.max_ts)) |> Enum.uniq()
      if length(starts) != 1 or Enum.any?(sources, &(&1.min_ts < floor(root))), do: fail(:compaction_conflict)
      if Enum.any?(sources, &(lookup(root, &1, tenant, signal, config) != :active)), do: fail(:compaction_conflict)
      {root, bucket} = ensure_bucket(root, replacement)
      root = spill_bucket(root, bucket, tenant, signal, config)
      bucket = bucket!(root, bucket["start"])
      keys = MapSet.new(sources, & &1.key)
      idx = index(bucket, tenant, signal, config)

      {active, new_bytes} =
        Enum.map_reduce(idx["active"], 0, &drop_sources(&1, &2, sources, keys, bucket, tenant, signal, config))

      entries =
        Enum.map(sources, fn s ->
          %{
            "k" => s.key,
            "mn" => s.min_ts,
            "mx" => s.max_ts,
            "ret" => Retirement.new(deadline) |> Retirement.to_wire() |> Map.put("id", nonce())
          }
        end)

      retired_refs = entries |> chunk() |> Enum.map(&put_page(bucket, "retired", &1, tenant, signal, config))
      idx = idx |> Map.put("active", Enum.reject(active, &is_nil/1)) |> Map.update!("retired", &(&1 ++ retired_refs))

      root =
        write_index(root, bucket, idx, tenant, signal, config, new_bytes + Enum.sum(Enum.map(retired_refs, & &1["b"])))

      root = add_inline(root, replacement)
      root = %{root | paging: Map.put(root.paging, "compaction_bucket", bucket["start"])}

      case register(root, [], tenant, signal, Map.put(config, :retention_affected_buckets, starts)) do
        {:ok, prepared} -> bounded(prepared, config)
        {:error, reason} -> fail(reason)
      end
    end)
  end

  # Rewrites a leaf without the compacted sources; an emptied leaf is dropped.
  defp drop_sources(ref, bytes, sources, keys, bucket, tenant, signal, config) do
    if Enum.any?(sources, &ref_covers?(ref, &1.max_ts)) do
      before = page(ref, bucket, tenant, signal, config, @leaf_bytes)
      remaining = Enum.reject(before, &MapSet.member?(keys, &1["k"]))

      cond do
        remaining == before ->
          {ref, bytes}

        remaining == [] ->
          {nil, bytes}

        true ->
          replacement_ref = put_page(bucket, "active", remaining, tenant, signal, config)
          {replacement_ref, bytes + replacement_ref["b"]}
      end
    else
      {ref, bytes}
    end
  end

  def spill(root, tenant, signal, config, affected \\ nil) do
    groups = Enum.group_by(root.segments, &bucket_start(root.paging, &1.max_ts))

    starts =
      if affected == nil do
        Map.keys(groups)
      else
        extras =
          groups
          |> Enum.reject(fn {start, _} -> start in affected end)
          |> Enum.sort_by(
            fn {_, rows} -> IO.iodata_length(Pulse.JSON.encode_to_iodata!(Enum.map(rows, &Segment.to_wire/1))) end,
            :desc
          )
          |> Enum.take(max(0, 4 - length(affected)))
          |> Enum.map(&elem(&1, 0))

        affected ++ extras
      end

    Enum.reduce(starts, root, fn start, r ->
      if affected == nil or start in affected do
        spill_bucket(r, bucket!(r, start), tenant, signal, config)
      else
        spill_extra(r, start, tenant, signal, config)
      end
    end)
  end

  defp spill_extra(root, start, tenant, signal, config) do
    spill_bucket(root, bucket!(root, start), tenant, signal, config)
  catch
    {:paged_manifest, :retention_capacity} -> spill_extra_without_summary(root, start, tenant, signal, config)
  end

  defp spill_extra_without_summary(root, start, tenant, signal, config) do
    spill_bucket(root, bucket!(root, start), tenant, signal, Map.put(config, :retention_omit_summaries, true))
  catch
    {:paged_manifest, :retention_capacity} -> root
  end

  def spill_bucket(root, bucket, tenant, signal, config) do
    {entries, rest} = Enum.split_with(root.segments, &(bucket_start(root.paging, &1.max_ts) == bucket["start"]))

    if entries == [] do
      root
    else
      root = %{root | segments: rest}
      append_leaf(root, bucket, "active", Enum.map(entries, &Segment.to_wire/1), tenant, signal, config)
    end
  end

  def index(%{"index" => nil}, _tenant, _signal, _config), do: %{"active" => [], "retired" => []}

  def index(bucket, tenant, signal, config) do
    idx = page(bucket["index"], bucket, tenant, signal, config, @index_bytes)
    if not valid_index_shape?(idx), do: fail(:invalid_manifest_page)

    Enum.each(["active", "retired"], fn kind ->
      Enum.each(idx[kind], &validate_index_ref!(&1, kind, bucket, tenant, signal))
    end)

    idx
  end

  defp valid_index_shape?(idx) do
    is_map(idx) and is_list(idx["active"]) and is_list(idx["retired"]) and
      length(idx["active"]) + length(idx["retired"]) <= 1024
  end

  defp validate_index_ref!(ref, kind, bucket, tenant, signal) do
    reference!(ref, bucket, tenant, signal, @leaf_bytes)

    if not (valid_index_ref_kind?(ref, kind) and valid_index_ref_range?(ref, bucket) and
              valid_index_ref_deadline?(ref, kind)),
       do: fail(:invalid_manifest_page)
  end

  defp valid_index_ref_kind?(ref, kind),
    do: is_map(ref) and is_binary(ref["k"]) and String.contains?(Path.basename(ref["k"]), "-#{kind}-")

  # A reference's range must lie within its bucket's recorded range.
  defp valid_index_ref_range?(ref, bucket) do
    is_integer(ref["min"]) and is_integer(ref["max"]) and ref["min"] <= ref["max"] and ref["min"] >= bucket["min"] and
      ref["max"] <= bucket["max"] and
      optional?(ref, "min_max", fn v -> is_integer(v) and v >= ref["min"] and v <= ref["max"] end)
  end

  defp valid_index_ref_deadline?(ref, "retired"), do: non_negative?(ref["max_deadline"])
  defp valid_index_ref_deadline?(_ref, _kind), do: true

  def page(ref, bucket, tenant, signal, config, limit) do
    name = reference!(ref, bucket, tenant, signal, limit)
    cached = Process.get(:pulse_metadata_budget, %{}) |> Map.get(:cache, %{}) |> Map.get(ref["k"])

    if cached do
      {previous_ref, data} = cached
      if previous_ref != ref, do: fail(:invalid_manifest_page)
      data
    else
      charge(config, ref["b"])

      case MetadataCache.get(ref) do
        {:ok, data} -> remember(ref, data)
        :miss -> fetch_page(ref, name, tenant, signal, config, limit)
      end
    end
  end

  # Only a page whose exact bytes match its reference is decoded, validated
  # and cached.
  defp fetch_page(ref, name, tenant, signal, config, limit) do
    case ObjectStore.get_bounded(config, ref["k"], nil, limit) do
      {:ok, _, body} ->
        data = decode_page!(body, ref, name, tenant, signal, limit)
        MetadataCache.put(ref, data)
        remember(ref, data)

      {:error, :not_found} ->
        fail(:manifest_page_missing)

      {:error, reason} ->
        fail(reason)
    end
  end

  defp decode_page!(body, ref, name, tenant, signal, limit) do
    if byte_size(body) != ref["b"] or digest(body) != ref["sha"], do: fail(:invalid_manifest_page)

    case Pulse.JSON.decode(body) do
      {:ok, data} ->
        data = Pulse.JSON.detach(data)
        if limit == @leaf_bytes, do: validate_leaf!(data, name, tenant, signal)
        data

      _ ->
        fail(:invalid_manifest_page)
    end
  end

  defp validate_leaf!(data, name, tenant, signal) do
    if not is_list(data) or length(data) > 256, do: fail(:invalid_manifest_page)
    Enum.each(data, &validate_leaf_entry!(&1, name, tenant, signal))
  end

  defp validate_leaf_entry!(entry, name, tenant, signal) do
    s = segment!(entry)
    validate_segment!(s, tenant, signal)
    if String.contains?(name, "-retired-") != is_map(entry["ret"]), do: fail(:invalid_manifest_page)
    if entry["ret"], do: validate_retirement!(entry["ret"])
  end

  defp validate_retirement!(ret) do
    case Retirement.from_wire(ret) do
      {:ok, _} -> :ok
      _ -> fail(:invalid_manifest_page)
    end

    if not hex32?(ret["id"]), do: fail(:invalid_manifest_page)
  end

  def validate_context(%Manifest{version: 3} = root, tenant, signal) do
    with_budget(%{}, fn ->
      Enum.each(root.segments, &validate_segment!(&1, tenant, signal))
      Enum.each(root.paging["buckets"], &validate_index_reference!(&1, tenant, signal))
      :ok
    end)
  end

  def validate_context(%Manifest{version: 4} = root, tenant, signal),
    do: JournalManifest.validate_context(root, tenant, signal)

  def validate_context(_root, _tenant, _signal), do: {:ok, :ok}

  defp validate_index_reference!(%{"index" => index} = bucket, tenant, signal) when index not in [nil, false],
    do: reference!(index, bucket, tenant, signal, @index_bytes)

  defp validate_index_reference!(_bucket, _tenant, _signal), do: :ok

  defp reference!(ref, bucket, tenant, signal, limit) do
    if not valid_page_ref?(ref, limit), do: fail(:invalid_manifest_page)
    name = Path.basename(ref["k"])
    if not valid_page_name?(ref, name, bucket_prefix(tenant, signal, bucket), limit), do: fail(:invalid_manifest_page)
    name
  end

  defp valid_page_ref?(ref, limit) do
    is_map(ref) and is_binary(ref["k"]) and is_integer(ref["b"]) and ref["b"] > 0 and ref["b"] <= limit and
      is_binary(ref["sha"]) and Regex.match?(~r/\A[0-9a-f]{64}\z/, ref["sha"])
  end

  # Pages are content-addressed under their own bucket's prefix.
  defp valid_page_name?(ref, name, prefix, limit) do
    ref["k"] == prefix <> name and
      Regex.match?(~r/\A[0-9a-f]{32}-(active|retired|index)-[0-9a-f]{64}\.json\z/, name) and
      String.ends_with?(name, "-#{ref["sha"]}.json") and
      (limit != @index_bytes or String.contains?(name, "-index-"))
  end

  defp remember(ref, data) do
    budget = Process.get(:pulse_metadata_budget)
    Process.put(:pulse_metadata_budget, %{budget | cache: Map.put(budget.cache, ref["k"], {ref, data})})
    data
  end

  def put_page(bucket, kind, data, tenant, signal, config) do
    check_deadline!()
    body = Pulse.JSON.encode!(data)
    if byte_size(body) > page_limit(bucket, kind, config), do: fail(:retention_capacity)
    if is_list(data) and length(data) > 256, do: fail(:retention_capacity)
    sha = digest(body)
    key = bucket_prefix(tenant, signal, bucket) <> binary_part(sha, 0, 32) <> "-#{kind}-#{sha}.json"

    summary = pruning_summary(signal, kind, data, config)

    case ObjectStore.put_if_none_match(config, key, body) do
      {:ok, _} ->
        page_written(key, body, sha, kind, data, summary)

      {:error, reason} when reason in [:already_exists, :precondition_failed] ->
        page_written(key, body, sha, kind, data, summary)

      {:error, reason} ->
        fail(reason)
    end
  end

  defp pruning_summary("traces", "active", data, config) do
    if config[:retention_expiry_spill] != true and config[:retention_omit_summaries] != true,
      do: TraceSummary.page_summary(data)
  end

  defp pruning_summary(_signal, _kind, _data, _config), do: nil

  # Expiry never needs pruning summaries: the bucket becomes invisible in the
  # same root transition. This also lets old large-summary roots drain safely.
  # Live indexes reserve space derived from the enforced reference bound.
  defp page_limit(bucket, "index", config) do
    if bucket["state"] == "live" and config[:retention_expiry_spill] != true,
      do: @index_bytes - @expiry_reserve,
      else: @index_bytes
  end

  defp page_limit(_bucket, _kind, _config), do: @leaf_bytes

  defp page_written(key, body, sha, kind, data, summary) do
    ref = page_ref(%{"k" => key, "b" => byte_size(body), "sha" => sha}, kind, data)
    ref = if summary, do: Map.put(ref, "q", summary), else: ref
    ref = bounded_reference(ref)
    MetadataCache.put(ref, data)

    case Process.get(:pulse_metadata_budget) do
      nil -> :ok
      budget -> Process.put(:pulse_metadata_budget, %{budget | cache: Map.put(budget.cache, key, {ref, data})})
    end

    ref
  end

  defp bounded_reference(ref) do
    ref = if ref_bytes(ref) > @reference_bytes, do: Map.delete(ref, "q"), else: ref
    if ref_bytes(ref) > @reference_bytes, do: fail(:retention_capacity)
    ref
  end

  defp ref_bytes(ref), do: IO.iodata_length(Pulse.JSON.encode_to_iodata!(ref))

  defp page_ref(ref, kind, data) do
    ref =
      if is_list(data) and data != [] do
        Map.merge(ref, %{
          "min" => Enum.min(Enum.map(data, & &1["mn"])),
          "max" => Enum.max(Enum.map(data, & &1["mx"])),
          "min_max" => Enum.min(Enum.map(data, & &1["mx"]))
        })
      else
        ref
      end

    if kind == "retired", do: Map.put(ref, "max_deadline", Enum.max(Enum.map(data, & &1["ret"]["d"]))), else: ref
  end

  def append_leaf(root, bucket, kind, entries, tenant, signal, config) do
    ensure_mutable!(bucket, config)
    idx = index(bucket, tenant, signal, config)
    maximum = if config[:retention_expiry_spill] == true or bucket["state"] != "live", do: 1024, else: 1023
    if length(idx["active"]) + length(idx["retired"]) + length(chunk(entries)) > maximum, do: fail(:retention_capacity)
    refs = chunk(entries) |> Enum.map(&put_page(bucket, kind, &1, tenant, signal, config))

    write_index(
      root,
      bucket,
      Map.update!(idx, kind, &(&1 ++ refs)),
      tenant,
      signal,
      config,
      Enum.sum(Enum.map(refs, & &1["b"]))
    )
  end

  def rewrite(root, bucket, kind, ref, fun, tenant, signal, config) do
    ensure_mutable!(bucket, config)
    idx = index(bucket, tenant, signal, config)
    entries = page(ref, bucket, tenant, signal, config, @leaf_bytes) |> fun.()
    refs = if entries == [], do: [], else: [put_page(bucket, kind, entries, tenant, signal, config)]
    updated = Enum.flat_map(idx[kind], fn r -> if r["k"] == ref["k"], do: refs, else: [r] end)
    write_index(root, bucket, Map.put(idx, kind, updated), tenant, signal, config, Enum.sum(Enum.map(refs, & &1["b"])))
  end

  def write_index(root, bucket, idx, tenant, signal, config, new_bytes \\ 0) do
    leaf_limit = if config[:retention_expiry_spill] == true, do: 1024, else: 1023
    if length(idx["active"]) + length(idx["retired"]) > leaf_limit, do: fail(:retention_capacity)
    mutations = bucket["mutations"] + 1
    written = bucket["written"] + IO.iodata_length(Pulse.JSON.encode_to_iodata!(idx)) + new_bytes

    if config[:retention_expiry_spill] != true and
         (mutations > Map.get(config, :retention_bucket_mutations, 10_000) or
            written > Map.get(config, :retention_bucket_metadata_bytes, 268_435_456)),
       do: fail(:retention_capacity)

    ref = put_page(bucket, "index", idx, tenant, signal, config)

    retirement_after =
      idx["retired"] |> Enum.map(& &1["max_deadline"]) |> Enum.filter(&is_integer/1) |> Enum.max(fn -> 0 end)

    bucket = bucket |> Map.put("retire_after", max(Map.get(bucket, "retire_after", 0), retirement_after))
    bucket = Map.put(bucket, "leaf_count", length(idx["active"]) + length(idx["retired"]))
    put_bucket(root, %{bucket | "index" => ref, "mutations" => mutations, "written" => written})
  end

  def add_inline(root, segment) do
    {root, _bucket} = ensure_bucket(root, segment)
    %{root | segments: [segment | root.segments]}
  end

  def ensure_bucket(root, segment) do
    start = bucket_start(root.paging, segment.max_ts)
    bucket = Enum.find(root.paging["buckets"], &(&1["start"] == start))
    id = if root.paging["seed"], do: digest(root.paging["seed"] <> ":#{start}") |> binary_part(0, 32), else: nonce()

    bucket =
      bucket ||
        %{
          "start" => start,
          "id" => id,
          "index" => nil,
          "min" => segment.min_ts,
          "max" => segment.max_ts,
          "state" => "live",
          "deadline" => nil,
          "cursor" => 0,
          "list_after" => nil,
          "mutations" => 0,
          "written" => 0
        }

    if bucket["state"] != "live", do: fail(:retention_expired)
    bucket = %{bucket | "min" => min(bucket["min"], segment.min_ts), "max" => max(bucket["max"], segment.max_ts)}
    {put_bucket(root, bucket), bucket}
  end

  def bucket!(root, start), do: Enum.find(root.paging["buckets"], &(&1["start"] == start)) || fail(:invalid_manifest)

  def put_bucket(root, bucket) do
    buckets = [bucket | Enum.reject(root.paging["buckets"], &(&1["start"] == bucket["start"]))]
    %{root | paging: %{root.paging | "buckets" => Enum.sort_by(buckets, & &1["start"]), "nonce" => nonce()}}
  end

  def remove_bucket(root, start),
    do: %{
      root
      | paging: %{
          root.paging
          | "buckets" => Enum.reject(root.paging["buckets"], &(&1["start"] == start)),
            "nonce" => nonce()
        }
    }

  def bounded(root, config) do
    check_deadline!()

    tail_bytes = IO.iodata_length(Pulse.JSON.encode_to_iodata!(Enum.map(root.segments, &Segment.to_wire/1)))

    if length(root.segments) > 256 or tail_bytes > @leaf_bytes or
         length(root.paging["buckets"]) > Map.get(config, :retention_max_buckets, 2048) or
         IO.iodata_length(Manifest.encode(root)) > @root_bytes,
       do: fail(:retention_capacity)

    root
  end

  def with_budget(config, fun) do
    owner = Process.get(:pulse_metadata_budget) == nil

    if owner,
      do:
        Process.put(:pulse_metadata_budget, %{
          pages: 0,
          bytes: 0,
          cache: %{},
          deadline: System.monotonic_time(:millisecond) + Map.get(config, :retention_timeout_ms, 30_000)
        })

    try do
      {:ok, fun.()}
    catch
      {:paged_manifest, reason} -> {:error, reason}
    after
      if owner, do: Process.delete(:pulse_metadata_budget)
    end
  end

  defp ensure_mutable!(bucket, config) do
    if config[:retention_expiry_spill] != true and bucket["state"] == "live" and
         (bucket["mutations"] + 2 > Map.get(config, :retention_bucket_mutations, 10_000) or
            bucket["written"] + 2 * (@index_bytes + @leaf_bytes) >
              Map.get(config, :retention_bucket_metadata_bytes, 268_435_456)),
       do: fail(:retention_capacity)
  end

  defp check_deadline! do
    case Process.get(:pulse_metadata_budget) do
      %{deadline: deadline} -> if System.monotonic_time(:millisecond) >= deadline, do: fail(:metadata_scan_limit)
      _ -> :ok
    end
  end

  def fail(reason), do: throw({:paged_manifest, reason})

  defp charge(config, bytes) do
    budget =
      Process.get(:pulse_metadata_budget, %{
        pages: 0,
        bytes: 0,
        cache: %{},
        deadline: System.monotonic_time(:millisecond) + 30_000
      })

    budget = %{budget | pages: budget.pages + 1, bytes: budget.bytes + bytes}

    if budget.pages > Map.get(config, :retention_metadata_pages, 128) or
         budget.bytes > Map.get(config, :retention_metadata_scan_bytes, 8_388_608) or
         System.monotonic_time(:millisecond) >= budget.deadline,
       do: fail(:metadata_scan_limit)

    Process.put(:pulse_metadata_budget, budget)
  end

  defp chunk(entries) do
    {pages, _, _} =
      entries
      |> Enum.sort_by(&{&1["mx"], &1["k"]})
      |> Enum.reduce({[[]], 2, 0}, fn e, {[head | tail], bytes, count} ->
        size = IO.iodata_length(Pulse.JSON.encode_to_iodata!(e))
        if size > @leaf_bytes - 2, do: fail(:retention_capacity)
        added = size + if(count == 0, do: 0, else: 1)

        if count >= 256 or bytes + added > @leaf_bytes do
          {[[e], head | tail], size + 2, 1}
        else
          {[[e | head] | tail], bytes + added, count + 1}
        end
      end)

    pages |> Enum.reject(&(&1 == [])) |> Enum.reverse() |> Enum.map(&Enum.reverse/1)
  end

  defp matches?(s, "metrics", opts), do: Segment.matches_metrics?(s, opts[:metrics_filter] || opts[:matchers] || [])
  defp matches?(s, "logs", opts), do: Segment.matches_log_service?(s, opts)
  defp matches?(s, "traces", opts), do: TraceSummary.matches?(s.trace_summary, opts)
  defp leaf_matches?(ref, "traces", opts), do: TraceSummary.page_matches?(ref["q"], opts)
  defp leaf_matches?(_ref, _signal, _opts), do: true

  defp intersects?(ref, start, finish),
    do: (start == nil or ref["max"] >= start) and (finish == nil or ref["min"] <= finish)

  defp digest(body), do: :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)

  defp valid_bounds?(s), do: non_negative?(s.min_ts) and is_integer(s.max_ts) and s.max_ts >= s.min_ts

  defp valid_key_scope?(key, tenant, signal) do
    is_binary(key) and byte_size(key) <= 1024 and String.starts_with?(key, scope(tenant, signal)) and
      not String.contains?(key, "/../")
  end

  defp segment!(wire) do
    case Segment.from_wire(wire) do
      {:ok, s} -> s
      _ -> fail(:invalid_manifest_page)
    end
  end

  # Bounds, scope and the key-encoded bounds must all agree before a segment
  # can be referenced or deleted.
  defp validate_segment!(s, tenant, signal) do
    if not (valid_bounds?(s) and valid_key_scope?(s.key, tenant, signal)), do: fail(:invalid_segment_key)

    case ManifestOwner.segment_from_key(s.key) do
      {:ok, parsed} when parsed.min_ts == s.min_ts and parsed.max_ts == s.max_ts -> :ok
      _ -> fail(:invalid_segment_key)
    end
  end
end
