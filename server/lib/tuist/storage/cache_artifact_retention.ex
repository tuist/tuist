defmodule Tuist.Storage.CacheArtifactRetention do
  @moduledoc false

  alias Tuist.Environment
  alias Tuist.Storage.BucketArtifactRetention

  @artifact_types [:xcode_cache, :cas, :xcode_module, :gradle]

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

  defp bucket_name(_artifact_type, :azure_blob), do: Environment.azure_blob_container_name()
  defp bucket_name(:xcode_cache, :s3), do: Environment.cache_xcode_s3_bucket_name()
  defp bucket_name(_artifact_type, :s3), do: Environment.cache_s3_bucket_name()

  defp object_path_segment_matches?(expected_path_segment) do
    fn object ->
      case String.split(object.key, "/", parts: 4) do
        [_account_handle, _project_handle, path_segment, _rest] -> path_segment == expected_path_segment
        _ -> false
      end
    end
  end
end
