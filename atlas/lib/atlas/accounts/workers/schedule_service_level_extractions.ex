defmodule Atlas.Accounts.Workers.ScheduleServiceLevelExtractions do
  @moduledoc """
  Enqueues service level extraction jobs for ready account documents that have not been checked.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Atlas.Accounts
  alias Atlas.Accounts.Workers.ExtractDocumentServiceLevels

  @impl true
  def perform(%Oban.Job{}) do
    Accounts.list_service_level_candidate_document_ids()
    |> Enum.reduce_while({:ok, 0}, fn document_id, {:ok, count} ->
      document_id
      |> extraction_job()
      |> Oban.insert()
      |> case do
        {:ok, _job} -> {:cont, {:ok, count + 1}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp extraction_job(document_id) do
    ExtractDocumentServiceLevels.new_unique(document_id)
  end
end
