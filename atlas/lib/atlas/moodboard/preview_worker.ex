defmodule Atlas.Moodboard.PreviewWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :moodboard,
    max_attempts: 2,
    unique: [keys: [:resource_id, :revision], states: :incomplete]

  alias Atlas.Moodboard
  alias Atlas.Moodboard.Preview
  alias Atlas.Moodboard.Resource
  alias Atlas.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"resource_id" => id, "revision" => revision}} = job) do
    case Repo.get(Resource, id) do
      %Resource{preview_revision: ^revision, preview_status: "pending", url: url} when is_binary(url) ->
        result = Preview.fetch(url)

        persist_result(job, id, revision, result)

      _ ->
        :ok
    end
  end

  defp persist_result(job, id, revision, result) do
    case Moodboard.apply_preview(id, revision, result) do
      {:ok, :ok} -> :ok
      {:error, _reason} -> persistence_failed(job, id, revision)
    end
  rescue
    _error in [Postgrex.Error, DBConnection.ConnectionError] ->
      persistence_failed(job, id, revision)
  end

  defp persistence_failed(job, id, revision) do
    if job.attempt >= job.max_attempts, do: mark_unavailable(id, revision), else: {:error, :preview_persistence_failed}
  end

  defp mark_unavailable(id, revision) do
    case Moodboard.apply_preview(id, revision, {:error, :persistence_failed}) do
      {:ok, :ok} -> :ok
      _ -> {:error, :preview_persistence_failed}
    end
  rescue
    _error in [Postgrex.Error, DBConnection.ConnectionError] -> {:error, :preview_persistence_failed}
  end
end
