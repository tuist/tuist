defmodule Pulse.Storage.S3.Retention do
  @moduledoc """
  Object-backed retention, policy migration, bucket teardown and bounded sweeps.
  A root CAS is the sole publication fence; all work is restartable from it.
  """
  alias Pulse.ObjectStore
  alias Pulse.Runtime.Task
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.CASBackoff
  alias Pulse.Storage.S3.JournalManifest
  alias Pulse.Storage.S3.LogCompactor
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.ManifestBackup
  alias Pulse.Storage.S3.ManifestCache
  alias Pulse.Storage.S3.ManifestOwner
  alias Pulse.Storage.S3.MetricsCompactor
  alias Pulse.Storage.S3.PagedManifest, as: Pages
  alias Pulse.Storage.S3.RetentionAdmission
  alias Pulse.Storage.S3.RetentionCatchup
  alias Pulse.Storage.S3.RetentionTasks
  alias Pulse.Storage.S3.TraceCompactor

  @day_ns 86_400_000_000_000
  @legacy_limit 16_777_216

  def signals, do: ["logs", "metrics", "traces"]
  def days(config, "logs"), do: Map.get(config, :logs_retention_days, 0)
  def days(config, "metrics"), do: Map.get(config, :metrics_retention_days, 0)
  def days(config, "traces"), do: Map.get(config, :traces_retention_days, 0)
  def days(_config, _signal), do: 0

  def configured?(config),
    do: Enum.any?(signals(), &(days(config, &1) > 0)) or Map.get(config, :retention_enabled, false)

  @doc "Whether this node enforces retention for `signal` (and therefore gates legacy roots)."
  def enforcing?(config, signal),
    do: Map.get(config, :retention_mode, "observe") == "enforce" and days(config, signal) > 0

  @doc """
  Whether enforcing retention converts `signal`'s prefixes to the bucketed
  format-3 manifest. By default (`:retention_manifest_format` `"paged"`)
  retention keeps format 4, so manifest backups and hour finalization keep
  working; `"bucketed"` and flat manifests use format 3. Prefixes already in
  format 3 stay there either way.
  """
  def bucketed?(config, signal),
    do:
      enforcing?(config, signal) and
        (Map.get(config, :retention_manifest_format, "paged") == "bucketed" or
           Map.get(config, :manifest_format, "paged") == "flat")

  @doc "The retention floor a root enforces, in event-time nanoseconds, or nil."
  def retention_floor(%Manifest{version: 3} = root), do: Pages.floor(root)
  def retention_floor(root), do: JournalManifest.retention_floor(root)

  @doc false
  def fetch_root(tenant, signal, config, etag, known_version \\ nil) do
    key = Manifest.manifest_key(tenant, signal)

    cond do
      known_version == 3 ->
        ObjectStore.get_bounded(config, key, etag, Pages.root_limit())

      known_version == 4 ->
        ObjectStore.get_bounded(config, key, etag, JournalManifest.root_limit())

      # Conversion, policy inspection and maintenance decode a whole legacy root
      # into one process, so they keep an explicit legacy budget.
      config[:retention_conversion] == true or config[:retention_bounded_read] == true ->
        ObjectStore.get_bounded(config, key, etag, Map.get(config, :retention_legacy_max_bytes, @legacy_limit))

      # Ordinary legacy reads stay unbounded, as before retention existed, in
      # every mode: enforcement must not make a large legacy tenant unreadable.
      known_version in [1, 2] ->
        ObjectStore.get_if_none_match(config, key, etag)

      # Unknown format: a valid format-3 root always fits the root cap, so only
      # an oversized legacy root pays for a second, unbounded read.
      true ->
        case ObjectStore.get_bounded(config, key, etag, Pages.root_limit()) do
          {:error, :response_too_large} -> ObjectStore.get_if_none_match(config, key, etag)
          other -> other
        end
    end
  end

  def load(tenant, signal, config) do
    with :ok <- S3.validate_tenant(tenant),
         :ok <- validate_signal(signal),
         {:ok, etag, body} <- fetch_root(tenant, signal, config, nil),
         {:ok, root} <- Manifest.decode(body),
         {:ok, :ok} <- Pages.validate_context(root, tenant, signal) do
      if root.version == 3 and byte_size(body) > Pages.root_limit(),
        do: {:error, :retention_capacity},
        else: {:ok, root, etag}
    else
      {:error, :not_found} ->
        case Pages.managed?(config, tenant, signal) do
          {:ok, true} -> {:error, :managed_manifest_missing}
          {:ok, false} -> {:error, :not_found}
          error -> error
        end

      error ->
        error
    end
  end

  @doc "Explicit, heap- and body-bounded conversion for a quiesced legacy prefix."
  def convert_offline(tenant, signal, config, opts) do
    maximum = Keyword.get(opts, :max_legacy_bytes)
    heap = Keyword.get(opts, :heap_words, 64_000_000)
    timeout = Keyword.get(opts, :timeout_ms, 600_000)

    cond do
      not valid_migration_budget?(maximum, heap, timeout) ->
        {:error, :invalid_migration_budget}

      days(config, signal) == 0 ->
        {:error, :finite_retention_required}

      Pulse.Runtime.whereis(RetentionTasks) == nil ->
        {:error, :retention_worker_disabled}

      Task.Supervisor.children(RetentionTasks) != [] ->
        {:error, :retention_busy}

      true ->
        config =
          config
          |> Map.put(:retention_legacy_max_bytes, maximum)
          |> Map.put(:retention_timeout_ms, timeout)
          |> Map.put(:retention_migration_timeout_ms, timeout)
          |> Map.put(:retention_mode, "enforce")

        RetentionTasks
        |> Task.Supervisor.async_nolink(fn ->
          Process.set_label({:pulse, :maintenance})
          Process.flag(:max_heap_size, %{size: heap, kill: true, error_logger: false, include_shared_binaries: true})
          advance(tenant, signal, config)
        end)
        |> await_migration(timeout)
    end
  rescue
    RuntimeError -> {:error, :retention_busy}
  end

  defp valid_migration_budget?(maximum, heap, timeout) do
    is_integer(maximum) and maximum in 1..268_435_456 and is_integer(heap) and heap in 1_000_000..128_000_000 and
      is_integer(timeout) and timeout in 1000..600_000
  end

  # A timed-out conversion is not killed; it may still complete.
  defp await_migration(task, timeout) do
    case Task.yield(task, timeout) do
      {:ok, result} ->
        result

      {:exit, reason} ->
        {:error, {:migration_exit, reason}}

      nil ->
        Process.demonitor(task.ref, [:flush])
        {:error, :migration_timeout}
    end
  end

  def effective_grace(config, signal) do
    options =
      case signal do
        "metrics" ->
          Map.new(Map.get(config, :compaction_options, []))

        "traces" ->
          Map.new(Map.get(config, :trace_compaction_options, []))

        "logs" ->
          if(Map.get(config, :log_compaction_enabled, false),
            do: Map.new(Map.get(config, :log_compaction_options, [])),
            else: %{grace_ms: 0}
          )

        _ ->
          %{grace_ms: 0}
      end

    max(Map.get(config, :retention_delete_grace_ms, 3_600_000), Map.get(options, :grace_ms, 3_600_000))
  end

  def window_ns(days, config, signal),
    do:
      days * @day_ns +
        (effective_grace(config, signal) + Map.get(config, :retention_future_skew_ms, 600_000)) * 1_000_000

  def validate_capacity(root, config, new_days, signal) do
    duration = new_days || root.paging["days"]
    width = root.paging["width"]

    if div(window_ns(duration, config, signal) + width - 1, width) + 4 <= 512,
      do: :ok,
      else: {:error, :retention_capacity}
  end

  defp capacity!(root, config, new_days, signal) do
    case validate_capacity(root, config, new_days, signal) do
      :ok -> :ok
      {:error, reason} -> Pages.fail(reason)
    end
  end

  def inspect_policy(tenant, signal, config, opts \\ []) do
    config = Map.put(config, :retention_bounded_read, true)
    now = Keyword.get(opts, :now_ns, System.system_time(:nanosecond))

    with {:ok, root, _} <- load(tenant, signal, config) do
      duration = days(config, signal)

      floor =
        if duration > 0,
          do: max(retention_floor(root) || 0, max(0, now - duration * @day_ns)),
          else: retention_floor(root)

      stats = metadata_stats(root)

      {:ok,
       Map.merge(stats, %{
         format: root.version,
         desired_days: duration,
         floor_ns: retention_floor(root),
         proposed_floor_ns: floor,
         inline_segments: length(root.segments),
         catchup: if(root.paging, do: root.paging["catchup"])
       })}
    end
  end

  def advance(tenant, signal, config, opts \\ []),
    do: Pulse.Metrics.measure(:retention, "advance", fn -> do_advance(tenant, signal, config, opts) end)

  defp do_advance(tenant, signal, config, opts) do
    if Map.get(config, :retention_mode, "observe") != "enforce" or days(config, signal) == 0 do
      inspect_policy(tenant, signal, config, opts)
    else
      now_ns = Keyword.get(opts, :now_ns, System.system_time(:nanosecond))
      now_ms = Keyword.get(opts, :now_ms, div(now_ns, 1_000_000))
      config = Map.put(config, :retention_conversion, true)

      if bucketed?(config, signal),
        do: advance_bucketed(tenant, signal, config, now_ns, now_ms),
        else: advance_paged(tenant, signal, config, now_ns, now_ms)
    end
  end

  defp advance_bucketed(tenant, signal, config, now_ns, now_ms),
    do: transact(tenant, signal, config, &advance_step(&1, now_ns, now_ms, tenant, signal, config))

  # ---- format-4 retention ----------------------------------------------------

  @hour_ns 3_600_000_000_000

  # The floor moves in whole hours, so an idle prefix's root is rewritten at
  # most hourly. Expiry pages are planned outside the manifest owner, which
  # only commits the plan (see JournalManifest.expire_plan/7), so ingest
  # publications never wait on page I/O. A flat root is converted first.
  defp advance_paged(tenant, signal, config, now_ns, now_ms) do
    floor = div(max(0, now_ns - days(config, signal) * @day_ns), @hour_ns) * @hour_ns
    deadline = now_ms + effective_grace(config, signal)
    leaves = Map.get(config, :retention_expiry_leaves, 32)

    case load(tenant, signal, config) do
      # Format 3 stays format 3.
      {:ok, %Manifest{version: 3}, _etag} ->
        advance_bucketed(tenant, signal, config, now_ns, now_ms)

      {:ok, root, _etag} ->
        with {:ok, changes} <- plan_expiry(root, floor, deadline, leaves, tenant, signal, config) do
          commit = &commit_expiry(&1, floor, deadline, changes, tenant, signal, config)
          ManifestOwner.transact(tenant, signal, config, commit)
        end

      error ->
        error
    end
  end

  defp plan_expiry(%Manifest{version: 4} = root, floor, deadline, leaves, tenant, signal, config),
    do: Pages.with_budget(config, fn -> expire_plan!(root, floor, deadline, leaves, tenant, signal, config) end)

  defp plan_expiry(_root, _floor, _deadline, _leaves, _tenant, _signal, _config), do: {:ok, []}

  defp expire_plan!(root, floor, deadline, leaves, tenant, signal, config) do
    case JournalManifest.expire_plan(root, floor, deadline, leaves, tenant, signal, config) do
      {:ok, changes} -> changes
      {:error, reason} -> Pages.fail(reason)
    end
  end

  defp commit_expiry(%Manifest{version: 4} = current, floor, deadline, changes, tenant, signal, config) do
    with {:ok, {updated, retired}} <-
           JournalManifest.apply_expiry(current, floor, deadline, changes, tenant, signal, config) do
      result = %{format: 4, floor_ns: JournalManifest.retention_floor(updated), retired: retired}
      write_expiry(updated, current, result, tenant, signal, config)
    end
  end

  defp commit_expiry(%Manifest{version: version} = flat, floor, deadline, _changes, tenant, signal, config)
       when version in [1, 2] do
    with {:ok, root} <- JournalManifest.convert(flat, tenant, signal, config),
         do: commit_expiry(root, floor, deadline, [], tenant, signal, config)
  end

  # Another node converted the prefix to format 3 meanwhile; it owns retention.
  defp commit_expiry(_root, _floor, _deadline, _changes, _tenant, _signal, _config), do: {:done, %{format: 3}}

  defp write_expiry(current, current, result, _tenant, _signal, _config), do: {:done, result}

  defp write_expiry(updated, _current, result, tenant, signal, config) do
    with {:ok, {sealed, payload, _}} <- JournalManifest.seal(updated, tenant, signal, config),
         do: {:write, sealed, payload, result}
  end

  defp advance_step(root, now_ns, now_ms, tenant, signal, config) do
    initial =
      config
      |> Map.put(:retention_initial_floor, max(0, now_ns - days(config, signal) * @day_ns))
      |> Map.put(:retention_initial_now_ms, now_ms)

    root = activate(root, tenant, signal, initial)
    if root.paging["days"] != days(config, signal), do: Pages.fail(:retention_policy_mismatch)
    capacity!(root, config, nil, signal)

    floor = max(root.paging["floor"], max(0, now_ns - days(config, signal) * @day_ns))
    root = %{root | paging: %{root.paging | "floor" => floor}}
    root = Enum.reduce(root.paging["buckets"], root, &expire_bucket(&2, &1, floor, now_ms, tenant, signal, config))
    root = age_floor(root, now_ms, config)
    {root, %{floor_ns: floor, buckets: length(root.paging["buckets"])}}
  end

  # A live bucket wholly below the floor spills its tail and starts teardown
  # after the grace period, in the same root write that moves the floor.
  defp expire_bucket(root, bucket, floor, now_ms, tenant, signal, config) do
    if bucket["state"] == "live" and bucket["start"] + root.paging["width"] <= floor do
      root = Pages.spill_bucket(root, bucket, tenant, signal, Map.put(config, :retention_expiry_spill, true))
      bucket = Pages.bucket!(root, bucket["start"])

      Pages.put_bucket(root, %{
        bucket
        | "state" => "data",
          "deadline" => max(now_ms + grace(config), Map.get(bucket, "retire_after", 0)),
          "cursor" => 0
      })
    else
      root
    end
  end

  def apply_policy(tenant, signal, config, expected_days, new_days) when new_days in 1..3650 do
    transact(tenant, signal, config, fn root ->
      if root.version != 3 or root.paging["days"] != expected_days, do: Pages.fail(:retention_policy_mismatch)
      capacity!(root, config, new_days, signal)

      {%{root | paging: %{root.paging | "days" => new_days}}, :ok}
    end)
  end

  def cleanup(tenant, signal, config, opts \\ []),
    do: Pulse.Metrics.measure(:retention, "cleanup", fn -> do_cleanup(tenant, signal, config, opts) end)

  defp do_cleanup(tenant, signal, config, opts) do
    if Map.get(config, :retention_mode, "observe") == "paused" do
      {:ok, 0}
    else
      now = Keyword.get(opts, :now_ms, System.system_time(:millisecond))

      transact(tenant, signal, config, &cleanup_step(&1, now, tenant, signal, config))
    end
  end

  defp cleanup_step(%Manifest{version: 3} = root, now, tenant, signal, config) do
    candidates = Enum.filter(root.paging["buckets"], &(&1["state"] != "live" and &1["deadline"] <= now))
    bucket = next_bucket(candidates, root.paging["cleanup_bucket"])
    {root, count} = if bucket, do: clean_bucket(root, bucket, tenant, signal, config), else: {root, 0}
    root = %{root | paging: Map.put(root.paging, "cleanup_bucket", if(bucket, do: bucket["start"]))}
    {age_floor(root, now, config), count}
  end

  defp cleanup_step(root, _now, _tenant, _signal, _config), do: {root, 0}

  # Round-robin: the first bucket after the cursor, wrapping to the first.
  defp next_bucket(buckets, cursor),
    do: Enum.find(buckets, &(cursor == nil or &1["start"] > cursor)) || List.first(buckets)

  def cleanup_retired(tenant, signal, config, opts \\ []),
    do: Pulse.Metrics.measure(:retention, "cleanup_retired", fn -> do_cleanup_retired(tenant, signal, config, opts) end)

  defp do_cleanup_retired(tenant, signal, config, opts) do
    if Map.get(config, :retention_mode, "observe") == "paused" do
      {:ok, 0}
    else
      now = Keyword.get(opts, :now_ms, System.system_time(:millisecond))

      with {:ok, loaded, _} <- load(tenant, signal, config),
           do: cleanup_retired_root(loaded, now, tenant, signal, config, opts)
    end
  end

  defp cleanup_retired_root(%Manifest{version: 3}, now, tenant, signal, config, _opts),
    do: transact(tenant, signal, config, &retired_step(&1, now, tenant, signal, config))

  defp cleanup_retired_root(root, _now, tenant, signal, config, opts) do
    case backup_hold(root, tenant, signal, config, opts) do
      {:ok, opts} -> compactor_cleanup(tenant, signal, config, opts)
      error -> error
    end
  end

  defp compactor_cleanup(tenant, "logs", config, opts), do: LogCompactor.cleanup(tenant, config, opts)
  defp compactor_cleanup(tenant, "metrics", config, opts), do: MetricsCompactor.cleanup(tenant, config, opts)
  defp compactor_cleanup(tenant, "traces", config, opts), do: TraceCompactor.cleanup(tenant, config, opts)
  defp compactor_cleanup(_tenant, _signal, _config, _opts), do: {:ok, 0}

  # With manifest backups on, deletions of a retention-managed format-4
  # prefix wait for a backup that records each retirement, as compaction
  # cleanup does, so the newest backup always restores. The retention worker
  # takes those backups itself: signals without compaction have no other
  # backup writer. Flat prefixes without retention keep their old behavior.
  defp backup_hold(%Manifest{version: 4}, tenant, signal, config, opts) do
    if days(config, signal) > 0 and Map.get(config, :manifest_backup_enabled, true) do
      with {:ok, taken} <- ManifestBackup.ensure_recent(tenant, signal, config) do
        hold = ManifestBackup.hold_ms(taken, hold_grace(config, signal), config)
        {:ok, Keyword.update(opts, :now_ms, hold, &min(&1, hold))}
      end
    else
      {:ok, opts}
    end
  end

  defp backup_hold(_root, _tenant, _signal, _config, opts), do: {:ok, opts}

  # Every retirement of the prefix used at least this grace: compaction uses
  # its own, expiry `effective_grace/2`, which is never smaller.
  defp hold_grace(config, signal) do
    key = %{"metrics" => :compaction_options, "logs" => :log_compaction_options, "traces" => :trace_compaction_options}
    compaction = config |> Map.get(key[signal], []) |> Map.new() |> Map.get(:grace_ms, 3_600_000)
    min(compaction, effective_grace(config, signal))
  end

  defp retired_step(root, now, tenant, signal, config) do
    buckets = Enum.filter(root.paging["buckets"], &(&1["state"] == "live"))

    case next_bucket(buckets, root.paging["retired_bucket"]) do
      nil -> {root, 0}
      bucket -> retire_bucket(root, bucket, now, tenant, signal, config)
    end
  end

  # Visits one retired page per pass, rotating through the bucket's index.
  defp retire_bucket(root, bucket, now, tenant, signal, config) do
    idx = Pages.index(bucket, tenant, signal, config)
    position = rem(Map.get(bucket, "retired_cursor", 0), max(1, length(idx["retired"])))
    ref = Enum.at(idx["retired"], position)
    {root, count} = retire_page(root, bucket, ref, now, tenant, signal, config)
    bucket = Pages.bucket!(root, bucket["start"]) |> Map.put("retired_cursor", position + 1)
    root = Pages.put_bucket(root, bucket)
    {%{root | paging: Map.put(root.paging, "retired_bucket", bucket["start"])}, count}
  end

  defp retire_page(root, _bucket, nil, _now, _tenant, _signal, _config), do: {root, 0}

  defp retire_page(root, bucket, ref, now, tenant, signal, config) do
    entries = Pages.page(ref, bucket, tenant, signal, config, 65_536)
    {updated, count} = Enum.map_reduce(entries, 0, &retire_entry(&1, &2, root, now, tenant, signal, config))

    root =
      if count > 0,
        do: Pages.rewrite(root, bucket, "retired", ref, fn _ -> updated end, tenant, signal, config),
        else: root

    {root, count}
  end

  # A due retired source is deleted only after proving it is in scope and no
  # longer referenced by the live root.
  defp retire_entry(%{"ret" => %{"x" => false, "d" => due} = ret} = entry, count, root, now, tenant, signal, config)
       when due <= now do
    validate_scope!(entry["k"], tenant, signal)
    source = segment!(entry["k"])
    if Pages.active?(root, source, tenant, signal, config), do: Pages.fail(:invalid_manifest_page)

    if try_delete(config, entry["k"]),
      do: {%{entry | "ret" => %{ret | "x" => true}}, count + 1},
      else: {entry, count}
  end

  defp retire_entry(entry, count, _root, _now, _tenant, _signal, _config), do: {entry, count}

  defp segment!(key) do
    case ManifestOwner.segment_from_key(key) do
      {:ok, source} -> source
      _ -> Pages.fail(:invalid_segment_key)
    end
  end

  @doc "Start bounded orphan catch-up from an explicit event time to the reclaimed watermark."
  def start_catchup(tenant, signal, config, from_ns) when is_integer(from_ns) and from_ns >= 0 do
    transact(tenant, signal, config, fn root ->
      if root.version != 3 or root.paging["catchup"] != nil or from_ns >= root.paging["reclaimed"],
        do: Pages.fail(:invalid_catchup)

      job = RetentionCatchup.new(from_ns, root.paging["reclaimed"], root.paging["width"])
      {%{root | paging: Map.put(root.paging, "catchup", job)}, :ok}
    end)
  end

  def start_catchup(_, _, _, _), do: {:error, :invalid_catchup}

  def sweep(tenant, signal, config, opts \\ []),
    do: Pulse.Metrics.measure(:retention, "sweep", fn -> do_sweep(tenant, signal, config, opts) end)

  defp do_sweep(tenant, signal, config, opts) do
    if Map.get(config, :retention_mode, "observe") == "paused" do
      {:ok, 0}
    else
      transact(tenant, signal, config, &sweep_step(&1, opts, tenant, signal, config))
    end
  end

  defp sweep_step(%Manifest{version: 3, paging: %{"catchup" => job}} = root, _opts, tenant, signal, config)
       when job != nil, do: RetentionCatchup.step(root, tenant, signal, config)

  defp sweep_step(%Manifest{version: 3, paging: %{"reclaimed" => reclaimed}} = root, opts, tenant, signal, config)
       when reclaimed != 0, do: sweep_window(root, opts, tenant, signal, config)

  defp sweep_step(root, _opts, _tenant, _signal, _config), do: {root, 0}

  defp sweep_window(root, opts, tenant, signal, config) do
    watermark = root.paging["reclaimed"]
    horizon = Map.get(config, :retention_sweep_horizon_days, root.paging["days"] * 2 + 2) * @day_ns
    lower = Keyword.get(opts, :from_ns, max(0, watermark - horizon))
    {p, count} = sweep_data(root.paging, lower, watermark, tenant, signal, config)
    # Also visit dead metadata slots within the horizon, including orphan generations.
    start = metadata_sweep_start(root.paging, lower, watermark)
    {p, page_count} = sweep_pages(p, start, watermark, tenant, signal, config)
    {p, legacy_count} = sweep_legacy_pages(p, watermark, tenant, signal, config)
    {%{root | paging: p}, count + page_count + legacy_count}
  end

  # One UTC date at a time, never a recursive lifetime-sized LIST.
  defp sweep_data(paging, lower, watermark, tenant, signal, config) do
    current_day = div(lower, @day_ns)
    last_day = div(watermark, @day_ns)
    saved = paging["sweep_day"]
    day = if is_integer(saved) and saved in current_day..last_day, do: saved, else: current_day
    date = DateTime.from_unix!(div(day * @day_ns, 1_000_000_000)) |> DateTime.to_date() |> Date.to_iso8601()
    prefix = Pages.scope(tenant, signal) <> "date=#{date}/"
    after_key = if paging["sweep_prefix"] == prefix, do: paging["sweep_after"]
    {:ok, keys, next} = list!(config, prefix, after_key)
    count = keys |> Enum.filter(&segment_below?(&1, watermark)) |> Enum.count(&try_delete(config, &1))

    next_day =
      cond do
        next -> day
        day >= last_day -> current_day
        true -> day + 1
      end

    p =
      paging
      |> Map.put("sweep_day", next_day)
      |> Map.put("sweep_after", next)
      |> Map.put("sweep_prefix", prefix)

    {p, count}
  end

  defp segment_below?(key, bound) do
    case ManifestOwner.segment_from_key(key) do
      {:ok, s} -> s.max_ts < bound
      :skip -> false
    end
  end

  defp metadata_sweep_start(paging, lower, watermark) do
    first = Pages.bucket_start(paging, lower)
    start = paging["metadata_sweep_start"] || first
    if start + paging["width"] <= watermark and start >= first, do: start, else: first
  end

  defp prepare_transaction(original, config, fun),
    do: Pages.with_budget(transaction_budget(original, config), fn -> fun.(original) end)

  def transact(tenant, signal, config, fun, attempts \\ 5)
  def transact(_tenant, _signal, _config, _fun, 0), do: {:error, :cas_retries_exhausted}

  def transact(tenant, signal, config, fun, attempts) do
    with {:ok, original, etag} <- load(tenant, signal, config),
         {:ok, {updated, result}} <- prepare_transaction(original, config, fun) do
      if updated == original do
        {:ok, result}
      else
        transaction = %{
          tenant: tenant,
          signal: signal,
          config: config,
          fun: fun,
          attempts: attempts,
          etag: etag,
          cache_base: ManifestCache.publication_base(tenant, signal)
        }

        commit(stamp_nonce(updated), result, etag, transaction)
      end
    end
  end

  # Conversion of a legacy root runs under the longer migration deadline.
  defp transaction_budget(%Manifest{version: 3}, config), do: config

  defp transaction_budget(_legacy, config) do
    if config[:retention_conversion],
      do: Map.put(config, :retention_timeout_ms, Map.get(config, :retention_migration_timeout_ms, 600_000)),
      else: config
  end

  defp stamp_nonce(%Manifest{paging: nil} = root), do: root
  defp stamp_nonce(root), do: %{root | paging: Map.put(root.paging, "nonce", Pages.nonce())}

  defp commit(updated, result, etag, %{tenant: tenant, signal: signal, config: config} = transaction) do
    with {:ok, updated} <- Pages.with_budget(config, fn -> bound(updated, config) end) do
      body = updated |> Manifest.encode() |> IO.iodata_to_binary()

      case ObjectStore.put_if_match(config, Manifest.manifest_key(tenant, signal), body, etag) do
        {:ok, new_etag} ->
          ManifestCache.publish(tenant, signal, updated, new_etag, etag, transaction.cache_base)
          {:ok, result}

        {:error, reason} ->
          tenant |> load(signal, config) |> resolve_commit(reason, updated, result, transaction)
      end
    end
  end

  defp bound(%Manifest{paging: nil} = root, _config), do: root

  defp bound(%Manifest{version: 4} = root, _config) do
    case JournalManifest.bounded(root) do
      {:ok, root} -> root
      {:error, reason} -> Pages.fail(reason)
    end
  end

  defp bound(root, config), do: Pages.bounded(root, config)

  # After an ambiguous write, our own nonce in the current root proves commit.
  defp resolve_commit({:ok, current, current_etag}, reason, updated, result, transaction) do
    cond do
      current.paging != nil and updated.paging != nil and current.paging["nonce"] == updated.paging["nonce"] ->
        ManifestCache.publish(
          transaction.tenant,
          transaction.signal,
          current,
          current_etag,
          transaction.etag,
          transaction.cache_base
        )

        {:ok, result}

      reason == :precondition_failed ->
        %{tenant: tenant, signal: signal, config: config, fun: fun, attempts: attempts} = transaction
        CASBackoff.wait(attempts)
        transact(tenant, signal, config, fun, attempts - 1)

      true ->
        {:error, reason}
    end
  end

  defp resolve_commit(_load, reason, _updated, _result, _transaction), do: {:error, reason}

  defp activate(%Manifest{version: 3} = root, _tenant, _signal, _config), do: root

  # A paged (format-4) root is read whole into one flat manifest first, within
  # the same legacy budget a flat root of that size would need.
  defp activate(%Manifest{version: 4} = root, tenant, signal, config) do
    if config[:retention_empty_conversion_only] == true and not Manifest.empty?(root),
      do: Pages.fail(:retention_migration_required)

    limit = Map.get(config, :retention_legacy_max_bytes, @legacy_limit)

    case JournalManifest.materialize(root, tenant, signal, config, limit) do
      {:ok, flat} -> activate(flat, tenant, signal, config)
      {:error, reason} -> Pages.fail(reason)
    end
  end

  defp activate(root, tenant, signal, config) do
    if config[:retention_empty_conversion_only] == true and not Manifest.empty?(root),
      do: Pages.fail(:retention_migration_required)

    if config[:retention_migration_notify], do: send(config.retention_migration_notify, {:retention_migration, self()})
    config = Map.put(config, :retention_seed, marker_seed(config, Pages.marker(tenant, signal)))

    case Pages.migrate(root, tenant, signal, days(config, signal), config) do
      {:ok, root} -> root
      {:error, reason} -> Pages.fail(reason)
    end
  end

  # Creates the marker with a fresh seed, or reuses the seed of an existing
  # marker so a retried conversion rewrites the same pages.
  defp marker_seed(config, marker) do
    seed = Pages.nonce()

    case ObjectStore.put_if_none_match(config, marker, Pulse.JSON.encode!(%{"seed" => seed})) do
      {:ok, _} -> seed
      {:error, reason} when reason in [:already_exists, :precondition_failed] -> existing_seed(config, marker)
      {:error, reason} -> Pages.fail(reason)
    end
  end

  defp existing_seed(config, marker) do
    case ObjectStore.get_bounded(config, marker, nil, 1024) do
      {:ok, _, ""} -> :crypto.hash(:sha256, marker) |> Base.encode16(case: :lower) |> binary_part(0, 32)
      {:ok, _, body} -> decode_seed(body)
      {:error, reason} -> Pages.fail(reason)
    end
  end

  defp decode_seed(body) do
    case Pulse.JSON.decode(body) do
      {:ok, %{"seed" => seed}} when is_binary(seed) ->
        if Regex.match?(~r/\A[0-9a-f]{32}\z/, seed), do: seed, else: Pages.fail(:invalid_managed_marker)

      _ ->
        Pages.fail(:invalid_managed_marker)
    end
  end

  # Data stage: delete every segment the bucket's pages reference, one page
  # per pass, then retry failed pages before moving on to its metadata.
  defp clean_bucket(root, %{"state" => "data"} = bucket, tenant, signal, config) do
    idx = Pages.index(bucket, tenant, signal, config)
    refs = Enum.map(idx["active"], &{&1, "active"}) ++ Enum.map(idx["retired"], &{&1, "retired"})
    failures = Map.get(bucket, "failed", [])
    position = if bucket["cursor"] < length(refs), do: bucket["cursor"], else: List.first(failures)

    case if(position != nil, do: Enum.at(refs, position)) do
      nil -> {Pages.put_bucket(root, %{bucket | "state" => "pages", "cursor" => 0}), 0}
      {ref, _kind} -> clean_page(root, bucket, ref, position, failures, tenant, signal, config)
    end
  end

  # The floor fences the whole bucket, including abandoned CAS generations.
  defp clean_bucket(root, bucket, tenant, signal, config) do
    prefix = Pages.scope(tenant, signal) <> "index/#{bucket["start"]}/"
    {:ok, keys, next} = list!(config, prefix, nil)
    successful = Enum.count(keys, &try_delete(config, &1))

    root =
      if next == nil and successful == length(keys),
        do: Pages.remove_bucket(root, bucket["start"]),
        else: Pages.put_bucket(root, %{bucket | "list_after" => nil})

    {root, successful}
  end

  defp clean_page(root, bucket, ref, position, failures, tenant, signal, config) do
    entries = Pages.page(ref, bucket, tenant, signal, config, 65_536)

    successes =
      Enum.count(entries, fn e ->
        validate_delete!(e["k"], tenant, signal, root.paging["floor"])
        try_delete(config, e["k"])
      end)

    failures = List.delete(failures, position)
    failures = if successes == length(entries), do: failures, else: failures ++ [position]
    bucket = bucket |> Map.put("failed", failures) |> Map.put("cursor", max(bucket["cursor"], position + 1))
    {Pages.put_bucket(root, bucket), successes}
  end

  defp sweep_pages(p, start, watermark, tenant, signal, config) do
    if start + p["width"] > watermark do
      {p, 0}
    else
      prefix = Pages.scope(tenant, signal) <> "index/#{start}/"
      after_key = if p["metadata_sweep_start"] == start, do: p["metadata_sweep_after"]
      {:ok, keys, next} = list!(config, prefix, after_key)
      count = Enum.count(keys, &try_delete(config, &1))
      next_start = if next, do: start, else: start + p["width"]
      {p |> Map.put("metadata_sweep_start", next_start) |> Map.put("metadata_sweep_after", next), count}
    end
  end

  defp sweep_legacy_pages(p, watermark, tenant, signal, config) do
    finish = Map.get(p, "legacy_gc_end", 0)

    if finish > 0 and finish <= watermark do
      start = Map.get(p, "legacy_sweep_start", 0)
      {:ok, keys, next} = list!(config, Pages.scope(tenant, signal) <> "index/#{start}/", p["legacy_sweep_after"])
      count = Enum.count(keys, &try_delete(config, &1))

      following =
        cond do
          next -> start
          start + p["width"] >= finish -> 0
          true -> start + p["width"]
        end

      {p |> Map.put("legacy_sweep_start", following) |> Map.put("legacy_sweep_after", next), count}
    else
      {p, 0}
    end
  end

  defp age_floor(root, now, config) do
    p = root.paging
    aged = if p["pending_after"] <= now, do: max(p["aged_floor"], p["pending_floor"]), else: p["aged_floor"]

    p =
      if p["pending_after"] <= now,
        do: %{p | "aged_floor" => aged, "pending_floor" => p["floor"], "pending_after" => now + grace(config)},
        else: p

    oldest = p["buckets"] |> Enum.map(& &1["start"]) |> Enum.min(fn -> aged end)
    watermark = max(p["reclaimed"], min(aged, oldest))
    %{root | paging: %{p | "reclaimed" => watermark}}
  end

  defp validate_scope!(key, tenant, signal) do
    if not is_binary(key) or not String.starts_with?(key, Pages.scope(tenant, signal)) or String.contains?(key, "/../"),
      do: Pages.fail(:invalid_segment_key)
  end

  defp validate_delete!(key, tenant, signal, floor) do
    validate_scope!(key, tenant, signal)

    case ManifestOwner.segment_from_key(key) do
      {:ok, s} when s.max_ts < floor -> :ok
      _ -> Pages.fail(:invalid_segment_key)
    end
  end

  defp grace(config), do: Map.get(config, :retention_delete_grace_ms, 3_600_000)

  defp list!(config, prefix, after_key) do
    case ObjectStore.list_page(config, prefix, after_key, Map.get(config, :retention_delete_limit, 512)) do
      {:ok, keys, cursor} -> {:ok, keys, cursor}
      {:error, reason} -> Pages.fail(reason)
    end
  end

  defp try_delete(config, key) do
    deadline =
      case Process.get(:pulse_metadata_budget) do
        %{deadline: deadline} -> deadline
        _ -> System.monotonic_time(:millisecond) + 30_000
      end

    if System.monotonic_time(:millisecond) >= deadline do
      false
    else
      case RetentionAdmission.delete(config, key) do
        :ok -> true
        {:error, :not_found} -> true
        {:error, _} -> false
      end
    end
  end

  defp validate_signal(signal) when signal in ["logs", "metrics", "traces"], do: :ok
  defp validate_signal(_), do: {:error, :unsupported_signal}

  def metadata_stats(%{version: 3} = root) do
    buckets = root.paging["buckets"]
    maximum = fn key -> Enum.map(buckets, &Map.get(&1, key, 0)) |> Enum.max(fn -> 0 end) end
    bytes = IO.iodata_length(Manifest.encode(root))

    %{
      root_bytes: bytes,
      buckets: length(buckets),
      pending_buckets: Enum.count(buckets, &(&1["state"] != "live")),
      max_leaf_refs: maximum.("leaf_count"),
      max_bucket_mutations: maximum.("mutations"),
      max_bucket_written_bytes: maximum.("written"),
      reclaimed_through_ns: root.paging["reclaimed"],
      capacity_ratio:
        Enum.max([
          bytes / Pages.root_limit(),
          length(buckets) / 2048,
          maximum.("leaf_count") / 1024,
          maximum.("mutations") / 10_000,
          maximum.("written") / 268_435_456
        ])
    }
  end

  def metadata_stats(root),
    do: %{
      root_bytes: IO.iodata_length(Manifest.encode(root)),
      buckets: 0,
      pending_buckets: 0,
      max_leaf_refs: 0,
      max_bucket_mutations: 0,
      max_bucket_written_bytes: 0,
      reclaimed_through_ns: 0,
      capacity_ratio: 0.0
    }
end
