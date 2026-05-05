defmodule Tuist.Registry.SyncWorker do
  @moduledoc """
  Periodically syncs Swift package registry metadata and enqueues missing releases.

  Runs on the registry-population pod (`TUIST_MODE=registry_population`) which is
  deployed as a single replica, so no distributed leader election is required.
  """

  use Oban.Worker, queue: :registry_sync

  alias Tuist.Environment
  alias Tuist.Registry.KeyNormalizer
  alias Tuist.Registry.Metadata
  alias Tuist.Registry.ReleaseWorker
  alias Tuist.Registry.SwiftPackageIndex
  alias Tuist.Registry.SyncCursor

  require Logger

  @github_opts [finch: Tuist.Finch, retry: false]

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    if Environment.registry_population_enabled?() do
      sync_packages(args, Environment.registry_github_token())
    else
      Logger.debug("Registry sync skipped: missing bucket or GitHub token")
      :ok
    end
  end

  defp sync_packages(args, token) do
    limit = Map.get(args, "limit", Environment.registry_sync_limit())
    allowlist = Environment.registry_sync_allowlist()

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
        Logger.error("Failed to fetch SPI package list: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp sync_package(%{scope: scope, name: name, repository_full_handle: full_handle}, token) do
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
    |> Enum.reject(&String.contains?(&1, "-dev"))
    |> Enum.uniq_by(&KeyNormalizer.normalize_version/1)
    |> Enum.filter(fn tag ->
      normalized = KeyNormalizer.normalize_version(tag)
      normalized not in known_versions
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
