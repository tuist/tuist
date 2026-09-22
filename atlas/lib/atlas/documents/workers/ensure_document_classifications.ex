defmodule Atlas.Documents.Workers.EnsureDocumentClassifications do
  @moduledoc """
  Enqueues metadata classification jobs for processed documents missing
  classifier-derived metadata.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    tags: ["documents", "classification"]

  alias Atlas.Documents
  alias Atlas.Documents.Workers.ClassifyDocumentMetadata

  @default_limit 10

  @impl true
  def perform(%Oban.Job{args: args}) do
    limit = Map.get(args, "limit", @default_limit)

    Documents.list_document_classification_candidate_ids(limit: limit, include_failed?: false)
    |> Enum.reduce_while({:ok, 0}, fn document_id, {:ok, count} ->
      document_id
      |> ClassifyDocumentMetadata.new_unique()
      |> Oban.insert()
      |> case do
        {:ok, _job} -> {:cont, {:ok, count + 1}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end
end
