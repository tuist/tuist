defmodule Tuist.Registry.Swift.SyncWorker do
  @moduledoc """
  Cron-driven worker. Fetches the SwiftPackageIndex catalog every 10
  minutes (cron entry is registered on the `:web` pod's leader; this
  worker runs the resulting jobs in `TUIST_MODE=swift_registry_sync`).
  Rotates through the catalog in fixed-size batches via a cursor in S3,
  and enqueues `ReleaseWorker` jobs for tags missing from each
  package's metadata.
  """

  use Oban.Worker, queue: :swift_registry_sync

  alias Tuist.Registry
  alias Tuist.Registry.Swift.Lock
  alias Tuist.Registry.Swift.Metadata
  alias Tuist.Registry.Swift.ReleaseWorker
  alias Tuist.Registry.Swift.SwiftPackageIndex
  alias Tuist.Registry.Swift.SyncCursor
  alias TuistCommon.Registry.Swift.KeyNormalizer

  require Logger

  @github_opts [finch: Tuist.Finch, retry: false]

  @sync_lock_ttl_seconds 3_000
  @package_lock_ttl_seconds 900

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    cond do
      not Registry.swift_registry_sync_enabled?() ->
        Logger.debug("Registry sync skipped: registry sync is disabled")
        :ok

      not Registry.swift_registry_enabled?() ->
        Logger.debug("Registry sync skipped: registry is not configured")
        :ok

      true ->
        case Lock.try_acquire(:sync, @sync_lock_ttl_seconds) do
          {:ok, :acquired} ->
            try do
              sync_packages(args, Registry.swift_registry_github_token())
            after
              Lock.release(:sync)
            end

          {:error, :already_locked} ->
            Logger.debug("Registry sync skipped: another node is the leader")
            :ok
        end
    end
  end

  defp sync_packages(args, token) do
    limit = Map.get(args, "limit", Registry.swift_registry_sync_limit())
    allowlist = Registry.swift_registry_sync_allowlist()

    case SwiftPackageIndex.list_packages(token) do
      {:ok, packages} ->
        packages = apply_allowlist(packages, allowlist)

        case packages do
          [] ->
            :ok

          _ ->
            {batch, next_cursor} = take_batch(packages, limit)
            Enum.each(batch, &sync_package(&1, token))
            SyncCursor.put(next_cursor)
            :ok
        end

      {:error, reason} ->
        if transient_fetch_error?(reason) do
          # A transport/protocol blip talking to GitHub (connection closed
          # mid-flight, timeout, DNS hiccup). This is a cron worker that
          # fires every 10 minutes, so the next tick retries for free.
          # Retrying the Oban job instead just replays the same failure up
          # to max_attempts and pages Sentry each time for something
          # un-actionable. Discard quietly; the warning keeps it in logs.
          Logger.warning("Skipping SPI package list fetch after transient error: #{inspect(reason)}")
          {:discard, reason}
        else
          # HTTP-status failures (403 rate/abuse limit, 5xx, an auth or
          # scope problem) can be persistent and are worth surfacing, so
          # they stay a hard error that retries and reports.
          Logger.error("Failed to fetch SPI package list: #{inspect(reason)}")
          {:error, reason}
        end
    end
  end

  # Transport and protocol errors arrive as Req exception structs; a real
  # HTTP response maps to a `{:http_error, status}` tuple upstream and is
  # deliberately excluded here so 403s and 5xx keep surfacing.
  defp transient_fetch_error?(%Req.TransportError{}), do: true
  defp transient_fetch_error?(%Req.HTTPError{}), do: true
  defp transient_fetch_error?(_reason), do: false

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
    metadata =
      case Metadata.get_package(scope, name) do
        {:ok, metadata} -> metadata
        {:error, :not_found} -> empty_metadata(scope, name, full_handle)
      end

    case TuistCommon.GitHub.list_tags(full_handle, token, @github_opts) do
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
  end

  defp missing_versions(tags, metadata) do
    releases = Map.get(metadata, "releases", %{})
    skipped_releases = Map.get(metadata, "skipped_releases", %{})
    known_versions = Map.keys(releases) ++ Map.keys(skipped_releases)

    tags
    |> Enum.filter(&KeyNormalizer.valid_source_tag?/1)
    |> Enum.reject(&String.ends_with?(&1, "-dev"))
    |> Enum.uniq_by(&KeyNormalizer.normalize_version/1)
    |> Enum.filter(fn tag ->
      normalized = KeyNormalizer.normalize_version(tag)
      KeyNormalizer.valid_storage_version?(normalized) and normalized not in known_versions
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
    |> Map.put_new("releases", %{})
    |> Map.put(
      "updated_at",
      DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    )
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
end
