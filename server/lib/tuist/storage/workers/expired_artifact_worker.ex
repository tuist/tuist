defmodule Tuist.Storage.Workers.ExpiredArtifactWorker do
  @moduledoc """
  Shared helpers for the per-account expired-artifact deletion workers.

  Each worker deletes one keyset-paginated batch and, when the batch was full,
  updates and reschedules the same job with the returned cursor. The cursor lives
  in the job args (`after_inserted_at`/`after_id`) so a single scheduled run walks
  the whole backlog instead of re-deleting the oldest batch every day.
  """

  alias Tuist.Storage.Workers.ArtifactRetentionWorker

  def cursor_from_args(args, retention_days) do
    [
      after_inserted_at: Map.get(args, "after_inserted_at"),
      after_id: Map.get(args, "after_id"),
      retention_days: retention_days
    ]
  end

  def continue(result, job, account_id, batch_size, retention_days \\ nil, self_hosted \\ false)

  def continue({:ok, nil}, _job, _account_id, _batch_size, _retention_days, _self_hosted), do: :ok

  def continue({:ok, cursor}, job, account_id, batch_size, retention_days, self_hosted) when is_map(cursor) do
    args =
      %{"account_id" => account_id, "batch_size" => batch_size}
      |> Map.merge(cursor)
      |> ArtifactRetentionWorker.put_retention_days(retention_days)
      |> ArtifactRetentionWorker.put_self_hosted(self_hosted)

    ArtifactRetentionWorker.reschedule_with_args(job, args)
  end

  def continue({:error, _reason} = error, _job, _account_id, _batch_size, _retention_days, _self_hosted), do: error
end
