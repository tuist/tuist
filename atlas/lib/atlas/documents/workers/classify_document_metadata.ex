defmodule Atlas.Documents.Workers.ClassifyDocumentMetadata do
  @moduledoc """
  Refreshes classifier-derived metadata for one processed document.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    tags: ["documents", "classification"]

  alias Atlas.Documents
  alias Atlas.LLMs.Errors, as: LLMErrors

  def new_unique(document_id) when is_binary(document_id) do
    new(
      %{document_id: document_id},
      unique: [
        period: {23, :hour},
        fields: [:worker, :args],
        keys: [:document_id],
        states: [:available, :scheduled, :executing, :retryable]
      ]
    )
  end

  @impl true
  def perform(%Oban.Job{args: %{"document_id" => document_id}}) do
    case Documents.classify_document_metadata(document_id) do
      {:ok, _document} -> :ok
      {:error, :document_not_found} -> {:cancel, :document_not_found}
      {:error, :document_not_ready} -> {:cancel, :document_not_ready}
      {:error, :document_has_no_pages} -> {:cancel, :document_has_no_pages}
      {:error, :llm_not_configured} -> {:cancel, :llm_not_configured}
      {:error, reason} -> LLMErrors.oban_error(reason)
    end
  end
end
