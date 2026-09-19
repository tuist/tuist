defmodule Atlas.Engineering.Postmortems.EmbeddingWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [fields: [:worker, :queue, :args], period: :infinity, states: :incomplete]

  alias Atlas.Engineering.Postmortems

  @embedding_unavailable_snooze_seconds 3_600

  def enqueue(postmortem_id, content_hash) do
    %{"postmortem_id" => postmortem_id, "content_hash" => content_hash}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"postmortem_id" => id, "content_hash" => content_hash}}) do
    case Postmortems.index_postmortem(id, content_hash) do
      {:ok, _embedding} ->
        :ok

      {:error, :not_found} ->
        :ok

      {:error, :embedding_not_configured} ->
        {:snooze, @embedding_unavailable_snooze_seconds}

      {:error, reason} ->
        # Atlas has no shared Errors.hard_failure_reason/terminal_attempt helpers
        # like Hive's Agents.Errors, so treat any other failure as retryable.
        :ok = Postmortems.mark_embedding_failed(id, content_hash, inspect(reason))
        {:error, inspect(reason)}
    end
  end
end
