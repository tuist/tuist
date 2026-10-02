defmodule Tuist.Storage.RunArtifactRetention do
  @moduledoc false

  alias Tuist.Environment
  alias Tuist.Storage.BucketArtifactRetention

  @orphaned_account_plan :air

  def delete_expired(opts \\ []) do
    storage_provider = Environment.object_storage_provider()

    BucketArtifactRetention.delete_expired(
      %{
        bucket_name: bucket_name(storage_provider),
        object_matches?: &run_artifact?/1,
        orphaned_account_plan: @orphaned_account_plan,
        retention_days: Keyword.get(opts, :retention_days),
        retention_artifact_type: :run_session,
        storage_provider: storage_provider
      },
      opts
    )
  end

  defp bucket_name(:azure_blob), do: Environment.azure_blob_container_name()
  defp bucket_name(:s3), do: Environment.s3_bucket_name()

  # Runs are keyed by a command event, test run, or legacy integer id
  # depending on the uploader, so the key shape is all they share.
  defp run_artifact?(object) do
    match?([_account_handle, _project_handle, "runs", _run_id, _object_name], String.split(object.key, "/", parts: 5))
  end
end
