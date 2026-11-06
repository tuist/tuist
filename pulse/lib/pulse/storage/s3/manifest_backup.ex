defmodule Pulse.Storage.S3.ManifestBackup do
  @moduledoc """
  Pulse-side manifest backups, for object stores without bucket versioning.

  Once compaction or hour finalization has run, a prefix's manifest is the
  only record of which objects are live. `backup/4` writes a copy of the
  current manifest to `tenants/<t>/v4/signal=<s>/backups/<unix_ms>.json` and
  keeps the newest `:keep` (48) copies. A flat root is copied whole. A
  format-4 root is copied as it is: its pages are immutable, so the copy costs
  one PUT whatever the history, and it needs no memory proportional to the
  history (materializing every page into one flat document read hundreds of
  pages and exceeded maintenance heap limits on large prefixes).

  Maintenance holds deletions back so the newest backup stays restorable:
  cleanup only deletes objects retired, and manifest pages superseded, before
  that backup was taken (`hold_ms/3`). An object retired or a page superseded
  later is still referenced by the backup and is kept until a newer backup
  records the change.

  `restore/4` rebuilds a lost manifest from the newest backup and adopts the
  ingested segments written after it (keys the backup does not know). Outputs
  of compaction and finalization written after the backup are not adopted;
  their sources were not deleted, so no acknowledged data is lost or
  duplicated. Prefixes with bucketed (format-3) retention are not backed up;
  format-4 prefixes with retention are, and the retention worker takes their
  backups (`ensure_recent/3`). A backup is a flat copy without the retention
  floor; a format-4 copy keeps the floor it had.
  """

  alias Pulse.ObjectStore
  alias Pulse.Storage.S3.JournalManifest
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.Manifest.Segment
  alias Pulse.Storage.S3.ManifestOwner
  alias Pulse.Storage.S3.MetadataCache
  alias Pulse.Storage.S3.Retention

  @width 20

  def prefix(tenant, signal), do: "tenants/#{tenant}/v4/signal=#{signal}/backups/"

  @doc """
  Back up the current manifest. Returns `{:ok, %{key, taken_ms, segments}}`,
  or `{:ok, :retention_managed}` for format-3 prefixes, which are not backed up.
  """
  def backup(tenant, signal, config, opts \\ []) do
    with {:ok, root, _etag} <- Retention.load(tenant, signal, config) do
      case flatten(root, tenant, signal, config) do
        {:ok, flat} -> write(tenant, signal, config, flat, Keyword.get(opts, :keep, 48))
        :retention_managed -> {:ok, :retention_managed}
      end
    end
  end

  defp flatten(%{version: 3}, _tenant, _signal, _config), do: :retention_managed

  defp flatten(%{version: 4} = root, _tenant, _signal, _config), do: {:ok, root}
  defp flatten(root, _tenant, _signal, _config), do: {:ok, %{root | version: max(root.version, 2)}}

  defp write(tenant, signal, config, flat, keep) do
    now = System.system_time(:millisecond)
    key = prefix(tenant, signal) <> pad(now) <> ".json"
    body = flat |> Manifest.encode() |> IO.iodata_to_binary()

    with {:ok, _etag} <- ObjectStore.put(config, key, body) do
      prune(tenant, signal, config, keep)
      {:ok, %{key: key, taken_ms: now, segments: JournalManifest.referenced(flat)}}
    end
  end

  defp prune(tenant, signal, config, keep) do
    with {:ok, keys} <- list(tenant, signal, config) do
      keys |> Enum.drop(-keep) |> Enum.each(&ObjectStore.delete(config, &1))
    end
  end

  # Backup keys, oldest first.
  defp list(tenant, signal, config) do
    with {:ok, keys} <- ObjectStore.list(config, prefix(tenant, signal)) do
      {:ok, keys |> Enum.filter(&match?({:ok, _}, taken(&1))) |> Enum.sort()}
    end
  end

  defp taken(key) do
    case Integer.parse(Path.basename(key, ".json")) do
      {ms, ""} -> {:ok, ms}
      _ -> :error
    end
  end

  @doc "When the newest backup was taken, or nil without one."
  def latest(tenant, signal, config) do
    with {:ok, keys} <- list(tenant, signal, config) do
      case List.last(keys) do
        nil -> {:ok, nil}
        key -> taken(key)
      end
    end
  end

  @doc """
  The newest backup's time (nil without one), first taking a backup when the
  newest is older than `:manifest_backup_interval_ms` (15 minutes). The time
  is cached node-locally until the next backup is due (and for at least a
  minute), so maintenance passes do not LIST the backups (a billed Class A
  request) each time; a stale value only holds deletions back longer. A
  failed backup keeps the previous time.
  """
  def ensure_recent(tenant, signal, config) do
    with {:ok, taken} <- cached_latest(tenant, signal, config) do
      if taken == nil or
           System.system_time(:millisecond) - taken >= Map.get(config, :manifest_backup_interval_ms, 900_000),
         do: {:ok, take(tenant, signal, config, taken)},
         else: {:ok, taken}
    end
  end

  defp take(tenant, signal, config, previous) do
    case backup(tenant, signal, config, keep: Map.get(config, :manifest_backup_keep, 48)) do
      {:ok, %{taken_ms: taken}} ->
        remember(tenant, signal, taken)
        taken

      _not_taken ->
        previous
    end
  end

  defp cache_ref(tenant, signal), do: %{"k" => "backup-cache:" <> prefix(tenant, signal), "b" => 1}

  defp cached_latest(tenant, signal, config) do
    now = System.monotonic_time(:millisecond)

    case MetadataCache.get(cache_ref(tenant, signal)) do
      {:ok, {checked, taken}} when now - checked < 60_000 ->
        {:ok, taken}

      {:ok, {_checked, taken}} when is_integer(taken) ->
        if System.system_time(:millisecond) - taken < Map.get(config, :manifest_backup_interval_ms, 900_000),
          do: {:ok, taken},
          else: refresh_latest(tenant, signal, config)

      _ ->
        refresh_latest(tenant, signal, config)
    end
  end

  defp refresh_latest(tenant, signal, config) do
    with {:ok, taken} <- latest(tenant, signal, config) do
      remember(tenant, signal, taken)
      {:ok, taken}
    end
  end

  defp remember(tenant, signal, taken),
    do: MetadataCache.put(cache_ref(tenant, signal), {System.monotonic_time(:millisecond), taken})

  @doc """
  The `now` cleanup may use so that it only deletes objects retired before
  the backup taken at `taken_ms` (strictly earlier, since a retirement in the
  same millisecond may follow it): retirement deadlines are retirement time
  plus `grace_ms`. Without a backup nothing is deleted.
  """
  def hold_ms(nil, _grace_ms), do: 0
  def hold_ms(taken_ms, grace_ms), do: min(System.system_time(:millisecond), taken_ms + grace_ms - 1)

  @doc """
  `hold_ms/2` for a cleanup that also deletes superseded manifest pages: their
  deadlines are supersession time plus `:manifest_page_grace_ms`, so the hold
  uses the smaller of the two graces. A format-4 backup references the pages
  that were current when it was taken.
  """
  def hold_ms(taken_ms, grace_ms, config),
    do: hold_ms(taken_ms, min(grace_ms, Map.get(config, :manifest_page_grace_ms, 3_600_000)))

  @doc """
  Rebuild a missing manifest from the newest backup. Refuses to overwrite an
  existing manifest unless `force: true`. Returns `{:ok, %{backup, segments, adopted}}`.
  """
  def restore(tenant, signal, config, opts \\ []) do
    with :ok <- check_missing(tenant, signal, config, opts),
         {:ok, keys} <- list(tenant, signal, config),
         {:ok, key} <- newest(keys),
         {:ok, body} <- ObjectStore.get(config, key),
         {:ok, manifest} <- Manifest.decode(body),
         {:ok, adopted} <- adoptable(tenant, signal, config, manifest),
         {:ok, restored, payload} <- restored(manifest, adopted, tenant, signal, config) do
      manifest_key = Manifest.manifest_key(tenant, signal)

      result =
        if Keyword.get(opts, :force, false),
          do: ObjectStore.put(config, manifest_key, payload),
          else: ObjectStore.put_if_none_match(config, manifest_key, payload)

      with {:ok, _etag} <- result,
           do: {:ok, %{backup: key, segments: JournalManifest.referenced(restored), adopted: length(adopted)}}
    end
  end

  defp restored(%{version: 4} = root, adopted, tenant, signal, config) do
    with {:ok, :ok} <- JournalManifest.validate_context(root, tenant, signal),
         {:ok, updated} <- JournalManifest.register(root, adopted, tenant, signal, config),
         {:ok, {sealed, payload, _}} <- JournalManifest.seal(updated, tenant, signal, config),
         do: {:ok, sealed, payload}
  end

  defp restored(manifest, adopted, _tenant, _signal, _config) do
    restored = Manifest.merge(%{manifest | version: max(manifest.version, 2)}, adopted)
    {:ok, restored, restored |> Manifest.encode() |> IO.iodata_to_binary()}
  end

  defp newest([]), do: {:error, :no_manifest_backup}
  defp newest(keys), do: {:ok, List.last(keys)}

  defp check_missing(tenant, signal, config, opts) do
    case Retention.load(tenant, signal, config) do
      {:ok, _root, _etag} -> if Keyword.get(opts, :force, false), do: :ok, else: {:error, :manifest_exists}
      {:error, reason} when reason in [:not_found, :managed_manifest_missing] -> :ok
      _error -> if Keyword.get(opts, :force, false), do: :ok, else: {:error, :manifest_exists}
    end
  end

  # Ingested segments the backup does not know: written after it was taken.
  defp adoptable(tenant, signal, config, manifest) do
    scope = "tenants/#{tenant}/v4/signal=#{signal}/"

    with {:ok, keys} <- ObjectStore.list(config, scope) do
      candidates =
        for key <- keys, ingested?(key, scope), {:ok, segment} <- [ManifestOwner.segment_from_key(key)], do: segment

      unknown(manifest, candidates, tenant, signal, config)
    end
  end

  defp unknown(%{version: 4} = root, candidates, tenant, signal, config),
    do: JournalManifest.absent(root, candidates, tenant, signal, config)

  defp unknown(manifest, candidates, _tenant, _signal, _config) do
    known = MapSet.new(Enum.map(manifest.segments, & &1.key) ++ Map.keys(manifest.retired))
    {:ok, Enum.reject(candidates, &MapSet.member?(known, &1.key))}
  end

  defp ingested?(key, scope) do
    base = Path.basename(key)

    String.starts_with?(key, scope <> "date=") and String.ends_with?(base, ".parquet") and
      Segment.key_tier(key) == :raw and
      (String.contains?(base, "-rand-") or String.contains?(base, "-idem-"))
  end

  defp pad(ms), do: ms |> Integer.to_string() |> String.pad_leading(@width, "0")
end
