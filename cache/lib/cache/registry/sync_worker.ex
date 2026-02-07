defmodule Cache.Registry.SyncWorker do
  @moduledoc """
  Periodically syncs Swift package registry metadata and enqueues missing releases.
  """

  use Oban.Worker, queue: :registry_sync

  alias Cache.Config
  alias Cache.Registry.GitHub
  alias Cache.Registry.KeyNormalizer
  alias Cache.Registry.Lock
  alias Cache.Registry.Metadata
  alias Cache.Registry.ReleaseWorker
  alias Cache.Registry.SwiftPackageIndex
  alias Cache.Registry.SyncCursor

  require Logger

  @default_limit 350
  @default_sync_interval_seconds 21_600
  @sync_lock_ttl_seconds 3_000
  @package_lock_ttl_seconds 900

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    if Config.registry_enabled?() do
      case Lock.try_acquire(:sync, @sync_lock_ttl_seconds) do
        {:ok, :acquired} ->
          try do
            sync_packages(args, Config.registry_github_token())
          after
            Lock.release(:sync)
          end

        {:error, :already_locked} ->
          Logger.debug("Registry sync skipped: another node is the leader")
          :ok
      end
    else
      Logger.debug("Registry sync skipped: registry is not configured")
      :ok
    end
  end

  defp sync_packages(args, token) do
    limit = Map.get(args, "limit", registry_sync_limit())
    allowlist = registry_sync_allowlist()

    case SwiftPackageIndex.list_packages(token) do
      {:ok, packages} ->
        packages = apply_allowlist(packages, allowlist)

        case packages do
          [] ->
            :ok

          _ ->
            {batch, next_cursor} = take_batch(packages, limit)
            Enum.each(batch, &sync_package(&1, token))
            _ = SyncCursor.put(next_cursor)
            :ok
        end

        :ok

      {:error, reason} ->
        Logger.error("Failed to fetch SPI package list: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp sync_package(%{scope: scope, name: name, repository_full_handle: full_handle}, token) do
    lock_key = {:package, scope, name}

    case Lock.try_acquire(lock_key, @package_lock_ttl_seconds) do
      {:ok, :acquired} ->
        try do
          do_sync_package(scope, name, full_handle, token)
        after
          Lock.release(lock_key)
        end

      {:error, :already_locked} ->
        :ok
    end
  end

  defp do_sync_package(scope, name, full_handle, token) do
    {metadata, should_sync?} =
      case Metadata.get_package(scope, name) do
        {:ok, metadata} -> {metadata, not recently_synced?(metadata)}
        {:error, :not_found} -> {empty_metadata(scope, name, full_handle), true}
      end

    if should_sync? do
      case GitHub.list_tags(full_handle, token) do
        {:ok, tags} ->
          missing_versions = missing_versions(tags, metadata)
          updated_metadata = update_metadata(metadata, scope, name, full_handle)
          :ok = Metadata.put_package(scope, name, updated_metadata)
          enqueue_release_workers(scope, name, full_handle, missing_versions)
          :ok

        {:error, reason} ->
          Logger.warning("Failed to fetch tags for #{scope}/#{name}: #{inspect(reason)}")
          :ok
      end
    else
      :ok
    end
  end

  defp missing_versions(tags, metadata) do
    releases = Map.get(metadata, "releases", %{})

    tags
    |> Enum.filter(&valid_semver?/1)
    |> Enum.reject(&String.contains?(&1, "-dev"))
    |> Enum.uniq_by(&KeyNormalizer.normalize_version/1)
    |> Enum.filter(fn tag ->
      normalized = KeyNormalizer.normalize_version(tag)
      not Map.has_key?(releases, normalized)
    end)
  end

  defp enqueue_release_workers(scope, name, full_handle, versions) do
    Enum.each(versions, fn tag ->
      %{scope: scope, name: name, repository_full_handle: full_handle, tag: tag}
      |> ReleaseWorker.new()
      |> Oban.insert()
    end)
  end

  defp update_metadata(metadata, scope, name, full_handle) do
    metadata
    |> Map.put_new("scope", scope)
    |> Map.put_new("name", name)
    |> Map.put("repository_full_handle", full_handle)
    |> Map.put_new("releases", Map.get(metadata, "releases", %{}))
    |> Map.put("updated_at", DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601())
  end

  defp empty_metadata(scope, name, full_handle) do
    %{
      "scope" => scope,
      "name" => name,
      "repository_full_handle" => full_handle,
      "releases" => %{},
      "updated_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  defp valid_semver?(version) do
    Regex.match?(
      ~r/^v?\d+\.\d+(\.\d+)?(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$/,
      version
    )
  end

  defp recently_synced?(%{"updated_at" => updated_at}) when is_binary(updated_at) do
    case DateTime.from_iso8601(updated_at) do
      {:ok, datetime, _offset} ->
        DateTime.diff(DateTime.utc_now(), datetime) < registry_sync_min_interval_seconds()

      _ ->
        false
    end
  end

  defp recently_synced?(_), do: false

  defp apply_allowlist(packages, nil), do: packages
  defp apply_allowlist(packages, []), do: packages

  defp apply_allowlist(packages, allowlist) when is_list(allowlist) do
    Enum.filter(packages, fn package ->
      Enum.any?(allowlist, fn pattern ->
        matches_pattern?(package.repository_full_handle, pattern)
      end)
    end)
  end

  defp take_batch(packages, limit) do
    total = length(packages)
    safe_limit = max(min(limit, total), 0)
    cursor = SyncCursor.get()
    cursor = if total == 0, do: 0, else: rem(max(cursor, 0), total)

    {prefix, suffix} = Enum.split(packages, cursor)
    rotated = suffix ++ prefix
    batch = Enum.take(rotated, safe_limit)
    next_cursor = if total == 0, do: 0, else: rem(cursor + safe_limit, total)

    {batch, next_cursor}
  end

  defp matches_pattern?(handle, pattern) do
    handle = String.downcase(handle)
    pattern = String.downcase(pattern)

    if String.ends_with?(pattern, "*") do
      prefix = String.trim_trailing(pattern, "*")
      String.starts_with?(handle, prefix)
    else
      handle == pattern
    end
  end

  defp registry_sync_allowlist do
    Application.get_env(:cache, :registry_sync_allowlist)
  end

  defp registry_sync_limit do
    Application.get_env(:cache, :registry_sync_limit, @default_limit)
  end

  defp registry_sync_min_interval_seconds do
    Application.get_env(:cache, :registry_sync_min_interval_seconds, @default_sync_interval_seconds)
  end
end
