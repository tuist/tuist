defmodule Tuist.Storage.Workers.ExpiredArtifactWorker do
  @moduledoc """
  Shared helpers for the per-account expired-artifact deletion workers.

  Each worker deletes one keyset-paginated batch and, when the batch was full,
  self-enqueues the next page for the same account with the returned cursor. The
  cursor lives in the job args (`after_inserted_at`/`after_id`) so a single
  scheduled run walks the whole backlog instead of re-deleting the oldest batch
  every day. Because the cursor is part of the uniqueness key, the follow-up job
  isn't deduplicated against the currently-executing one.
  """

  def cursor_from_args(args) do
    [after_inserted_at: Map.get(args, "after_inserted_at"), after_id: Map.get(args, "after_id")]
  end

  def continue({:ok, nil}, _worker, _account_id, _batch_size), do: :ok

  def continue({:ok, cursor}, worker, account_id, batch_size) when is_map(cursor) do
    %{"account_id" => account_id, "batch_size" => batch_size}
    |> Map.merge(cursor)
    |> worker.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} -> :ok
      error -> error
    end
  end

  def continue({:error, _reason} = error, _worker, _account_id, _batch_size), do: error
end
