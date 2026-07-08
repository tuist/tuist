defmodule Tuist.Storage.LegacyBuildArtifactRetention do
  @moduledoc false

  alias Tuist.Environment
  alias Tuist.Storage.BucketArtifactRetention

  @orphaned_account_plan :air
  @uuid_pattern ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

  def delete_expired(opts \\ []) do
    storage_provider = Environment.object_storage_provider()

    BucketArtifactRetention.delete_expired(
      %{
        bucket_name: bucket_name(storage_provider),
        object_matches?: &legacy_build_artifact?/1,
        orphaned_account_plan: @orphaned_account_plan,
        retention_artifact_type: :build_archive,
        storage_provider: storage_provider
      },
      opts
    )
  end

  defp bucket_name(storage_provider) do
    case storage_provider do
      :azure_blob -> Environment.azure_blob_container_name()
      :s3 -> Environment.s3_bucket_name()
    end
  end

  defp legacy_build_artifact?(object) do
    case String.split(object.key, "/", parts: 6) do
      [_account_handle, _project_handle, "builds", build_identifier, "build.zip"] ->
        not Regex.match?(@uuid_pattern, build_identifier)

      [_account_handle, _project_handle, "builds", _build_identifier, _object_name] ->
        true

      [_account_handle, _project_handle, "builds", _build_identifier, _object_name, _rest] ->
        true

      _ ->
        false
    end
  end
end
