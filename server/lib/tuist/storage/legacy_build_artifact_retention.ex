defmodule Tuist.Storage.LegacyBuildArtifactRetention do
  @moduledoc false

  alias Tuist.Environment
  alias Tuist.Storage.BucketArtifactRetention

  @orphaned_account_plan :air
  @uuid_pattern ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

  def delete_expired(opts \\ []) do
    BucketArtifactRetention.delete_expired(
      %{
        bucket_name: Environment.s3_bucket_name(),
        object_matches?: &legacy_build_artifact?/1,
        orphaned_account_plan: @orphaned_account_plan,
        retention_artifact_type: :build_archive
      },
      opts
    )
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
