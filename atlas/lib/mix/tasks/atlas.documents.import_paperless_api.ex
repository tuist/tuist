defmodule Mix.Tasks.Atlas.Documents.ImportPaperlessApi do
  @shortdoc "Imports documents from a Paperless-ngx instance over its REST API"

  @moduledoc """
  Imports documents from a Paperless-ngx instance through its REST API.

      mix atlas.documents.import_paperless_api --limit 1

  Reads `PAPERLESS_URL` and `PAPERLESS_TOKEN` from the environment (or the
  `:atlas, :paperless` config). Each document is downloaded and handed to the
  normal document pipeline (upload to object storage, then the processing job).

  In production, prefer running it inside the cluster against the release:

      bin/atlas eval 'Atlas.Documents.Paperless.import(limit: 1)'
  """

  use Mix.Task

  alias Atlas.Documents.Paperless

  @requirements ["app.start"]

  @impl true
  def run(args) do
    {opts, _rest, _invalid} = OptionParser.parse(args, strict: [limit: :integer])
    import_opts = if limit = opts[:limit], do: [limit: limit], else: []

    case Paperless.import(import_opts) do
      {:ok, summary} -> Mix.shell().info("Paperless import done: #{inspect(summary)}")
      {:error, reason} -> Mix.raise("Paperless import failed: #{inspect(reason)}")
    end
  end
end
