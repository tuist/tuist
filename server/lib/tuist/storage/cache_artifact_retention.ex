defmodule Tuist.Storage.CacheArtifactRetention do
  @moduledoc false

  alias Tuist.Environment
  alias Tuist.Runners.GitLab.Cache, as: GitLabCache
  alias Tuist.Storage.BucketArtifactRetention

  @artifact_types [:xcode_cache, :cas, :xcode_module, :gradle, :gitlab_cache]

  def artifact_types, do: @artifact_types

  def delete_expired(artifact_type, opts \\ []) when artifact_type in @artifact_types do
    artifact_type
    |> retention_target()
    |> Map.put(:retention_days, Keyword.get(opts, :retention_days))
    |> BucketArtifactRetention.delete_expired(opts)
  end

  defp retention_target(:xcode_cache) do
    storage_provider = Environment.object_storage_provider()

    %{
      bucket_name: bucket_name(:xcode_cache, storage_provider),
      object_matches?: object_path_segment_matches?("xcode"),
      skip_custom_storage_accounts?: true,
      retention_artifact_type: :xcode_cache_artifact,
      storage_provider: storage_provider
    }
  end

  defp retention_target(:cas) do
    storage_provider = Environment.object_storage_provider()

    %{
      bucket_name: bucket_name(:cas, storage_provider),
      object_matches?: object_path_segment_matches?("cas"),
      skip_custom_storage_accounts?: true,
      retention_artifact_type: :xcode_cache_artifact,
      storage_provider: storage_provider
    }
  end

  defp retention_target(:xcode_module) do
    storage_provider = Environment.object_storage_provider()

    %{
      bucket_name: bucket_name(:xcode_module, storage_provider),
      object_matches?: object_path_segment_matches?("module"),
      skip_custom_storage_accounts?: true,
      retention_artifact_type: :cache_artifact,
      storage_provider: storage_provider
    }
  end

  defp retention_target(:gradle) do
    storage_provider = Environment.object_storage_provider()

    %{
      bucket_name: bucket_name(:gradle, storage_provider),
      object_matches?: object_path_segment_matches?("gradle"),
      skip_custom_storage_accounts?: true,
      retention_artifact_type: :cache_artifact,
      storage_provider: storage_provider
    }
  end

  # GitLab cache archives share the main bucket with previews and builds, so
  # listing is scoped to their prefix. Archives stay here after an account
  # configures its own storage, and a renamed account leaves its old prefix
  # behind; both must still expire.
  defp retention_target(:gitlab_cache) do
    storage_provider = Environment.object_storage_provider()

    %{
      bucket_name: bucket_name(:gitlab_cache, storage_provider),
      prefix: GitLabCache.prefix() <> "/",
      object_matches?: &gitlab_cache_object?/1,
      account_handle: &gitlab_cache_account_handle/1,
      orphaned_account_plan: :air,
      retention_artifact_type: :cache_artifact,
      storage_provider: storage_provider
    }
  end

  defp bucket_name(_artifact_type, :azure_blob), do: Environment.azure_blob_container_name()
  defp bucket_name(:gitlab_cache, :s3), do: Environment.s3_bucket_name()
  defp bucket_name(:xcode_cache, :s3), do: Environment.cache_xcode_s3_bucket_name()
  defp bucket_name(_artifact_type, :s3), do: Environment.cache_s3_bucket_name()

  defp gitlab_cache_object?(object), do: not is_nil(gitlab_cache_account_handle(object))

  defp gitlab_cache_account_handle(%{key: key}) do
    prefix = GitLabCache.prefix()

    case String.split(key, "/", parts: 6) do
      [^prefix, account_handle, _project_id, namespace, _cache_key] when namespace in ["protected", "unprotected"] ->
        account_handle

      _ ->
        nil
    end
  end

  defp object_path_segment_matches?(expected_path_segment) do
    fn object ->
      case String.split(object.key, "/", parts: 4) do
        [_account_handle, _project_handle, path_segment, _rest] -> path_segment == expected_path_segment
        _ -> false
      end
    end
  end
end
