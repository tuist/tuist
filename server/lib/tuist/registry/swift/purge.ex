defmodule Tuist.Registry.Swift.Purge do
  @moduledoc """
  Operator entry point for removing Swift package artifacts and metadata
  from the registry. Run these functions from the server runtime, usually
  by connecting to a swift-registry-sync pod and opening an Elixir console.

  Bypasses the read-time sanitize step in `Tuist.Registry.Swift.Metadata`
  so that an operator can still remove a previously-skipped version
  whose stored identifier wouldn't pass `valid_storage_version?` (which
  the sanitize gate would otherwise hide on read).

  Removal covers both `releases` and `skipped_releases`, so enqueuing
  `Tuist.Registry.Swift.ReleaseWorker` after a purge re-mirrors the
  version cleanly (the SyncWorker's known-versions set no longer thinks
  the tag is already handled).
  """

  alias Tuist.Registry.S3
  alias TuistCommon.Registry.Swift.KeyNormalizer

  require Logger

  def purge_package(scope, name) when is_binary(scope) and is_binary(name) do
    {scope, name} = KeyNormalizer.normalize_scope_name(scope, name)
    artifact_prefix = "registry/swift/#{scope}/#{name}/"
    metadata_prefix = "registry/metadata/#{scope}/#{name}/"

    Logger.info("Purging package #{scope}/#{name}")

    with {:ok, artifacts} <- S3.delete_all_with_prefix(artifact_prefix),
         {:ok, metadata} <- S3.delete_all_with_prefix(metadata_prefix) do
      {:ok, %{scope: scope, name: name, artifacts_deleted: artifacts, metadata_deleted: metadata}}
    end
  end

  def purge_version(scope, name, version) when is_binary(scope) and is_binary(name) and is_binary(version) do
    {scope, name} = KeyNormalizer.normalize_scope_name(scope, name)
    normalized = KeyNormalizer.normalize_version(version)
    artifact_prefix = "registry/swift/#{scope}/#{name}/#{normalized}/"
    metadata_key = "registry/metadata/#{scope}/#{name}/index.json"

    Logger.info("Purging #{scope}/#{name}@#{normalized} (input: #{version})")

    with {:ok, artifacts} <- S3.delete_all_with_prefix(artifact_prefix),
         {:ok, metadata_status} <- remove_version_from_metadata(metadata_key, normalized) do
      {:ok,
       %{
         scope: scope,
         name: name,
         version: normalized,
         artifacts_deleted: artifacts,
         metadata: metadata_status
       }}
    end
  end

  defp remove_version_from_metadata(key, version) do
    case S3.get_object(key) do
      {:ok, body} ->
        case JSON.decode(body) do
          {:ok, metadata} -> apply_version_removal(key, metadata, version)
          {:error, reason} -> {:error, {:invalid_metadata_json, reason}}
        end

      {:error, :not_found} ->
        {:ok, :metadata_absent}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp apply_version_removal(key, metadata, version) do
    {updated, removed_from} = drop_version(metadata, version)

    if removed_from == [] do
      {:ok, :not_present}
    else
      updated_at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      body = updated |> Map.put("updated_at", updated_at) |> JSON.encode!()

      case S3.upload_content(key, body, content_type: "application/json") do
        :ok -> {:ok, %{removed_from: removed_from}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp drop_version(metadata, version) do
    Enum.reduce(["releases", "skipped_releases"], {metadata, []}, fn map_key, {acc, removed} ->
      case Map.fetch(acc, map_key) do
        {:ok, versions} when is_map(versions) ->
          if Map.has_key?(versions, version) do
            {Map.put(acc, map_key, Map.delete(versions, version)), [map_key | removed]}
          else
            {acc, removed}
          end

        _ ->
          {acc, removed}
      end
    end)
  end
end
