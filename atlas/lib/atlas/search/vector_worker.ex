defmodule Atlas.Search.VectorWorker do
  @moduledoc "Commit-bound, best-effort search-vector maintenance for transactional domain operations."
  use Oban.Worker, queue: :default, max_attempts: 5

  alias Atlas.Search

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"operation" => "upsert", "record_id" => id}}), do: Search.sync_record_vector(id)

  def perform(%Oban.Job{args: %{"operation" => "delete", "record_id" => id}}) do
    case Search.delete_record_vector(id) do
      {:error, _} -> {:error, :vector_delete_failed}
      _ -> :ok
    end
  end
end
