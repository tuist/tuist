defmodule Atlas.Documents.Workers.ProcessDocument do
  @moduledoc false

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Atlas.Documents

  @impl true
  def perform(%Oban.Job{args: %{"document_id" => document_id}, attempt: attempt, max_attempts: max_attempts}) do
    # On the final attempt, let a failing classifier fall back to filename-only
    # metadata so the document still completes (text + embeddings) instead of
    # being retried forever and left stuck in "processing".
    opts = [classify_fallback?: attempt >= max_attempts]

    case Documents.process_document(document_id, opts) do
      {:ok, _document} -> :ok
      {:error, :document_not_found} -> {:cancel, :document_not_found}
      {:error, reason} -> {:error, reason}
    end
  end
end
