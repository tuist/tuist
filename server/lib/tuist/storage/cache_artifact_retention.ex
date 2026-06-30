defmodule Tuist.Storage.CacheArtifactRetention do
  @moduledoc false

  alias Tuist.Environment
  alias Tuist.Storage.BucketArtifactRetention

  @artifact_types [:xcode_cache, :cas, :xcode_module, :gradle]

  def artifact_types, do: @artifact_types

  def delete_expired(artifact_type, opts \\ []) when artifact_type in @artifact_types do
    artifact_type
    |> retention_target()
    |> BucketArtifactRetention.delete_expired(opts)
  end

  defp retention_target(:xcode_cache) do
    %{
      bucket_name: Environment.cache_xcode_s3_bucket_name(),
      object_matches?: object_path_segment_matches?("xcode"),
      skip_custom_storage_accounts?: true,
      retention_artifact_type: :xcode_cache_artifact
    }
  end

  defp retention_target(:cas) do
    %{
      bucket_name: Environment.cache_s3_bucket_name(),
      object_matches?: object_path_segment_matches?("cas"),
      skip_custom_storage_accounts?: true,
      retention_artifact_type: :xcode_cache_artifact
    }
  end

  defp retention_target(:xcode_module) do
    %{
      bucket_name: Environment.cache_s3_bucket_name(),
      object_matches?: object_path_segment_matches?("module"),
      skip_custom_storage_accounts?: true,
      retention_artifact_type: :cache_artifact
    }
  end

  defp retention_target(:gradle) do
    %{
      bucket_name: Environment.cache_s3_bucket_name(),
      object_matches?: object_path_segment_matches?("gradle"),
      skip_custom_storage_accounts?: true,
      retention_artifact_type: :cache_artifact
    }
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
