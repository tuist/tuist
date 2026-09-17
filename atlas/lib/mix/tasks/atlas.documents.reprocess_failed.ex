defmodule Mix.Tasks.Atlas.Documents.ReprocessFailed do
  @shortdoc "Re-enqueues ProcessDocument for documents currently in `failed`"

  @moduledoc """
  One-shot backfill: enqueues a `ProcessDocument` job for every document
  whose status is `failed`, so a processing-pipeline fix can pick them up.

      mix atlas.documents.reprocess_failed
  """

  use Mix.Task

  alias Atlas.Documents

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    %{enqueued: count} = Documents.reenqueue_failed_documents()

    Mix.shell().info("Re-enqueued ProcessDocument for #{count} failed document(s)")
  end
end
