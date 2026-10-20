defmodule Mix.Tasks.Atlas.Documents.ImportPaperless do
  @shortdoc "Imports a local Paperless export directory into Atlas documents"

  @moduledoc """
  Imports documents from a local Paperless export directory.

      mix atlas.documents.import_paperless /path/to/paperless/export

  The task scans recursively for PDF, text, and Markdown files, uploads them to
  the configured S3 bucket, and enqueues the normal document processor.
  """

  use Mix.Task

  alias Atlas.Documents

  @requirements ["app.start"]
  @extensions ~w(.pdf .txt .md)

  @impl true
  def run([directory]) do
    directory = Path.expand(directory)

    if !File.dir?(directory) do
      Mix.raise("expected #{directory} to be a directory")
    end

    files =
      directory
      |> Path.join("**/*")
      |> Path.wildcard()
      |> Enum.filter(&regular_document?/1)

    Mix.shell().info("Importing #{length(files)} documents")

    Enum.each(files, fn path ->
      attrs = %{
        "original_filename" => Path.basename(path),
        "content_type" => content_type(path),
        "source" => "paperless"
      }

      case Documents.create_from_path(path, attrs) do
        {:ok, document} ->
          Mix.shell().info("imported #{document.original_filename}")

        {:error, reason} ->
          Mix.shell().error("failed #{path}: #{inspect(reason)}")
      end
    end)
  end

  def run(_args), do: Mix.raise("usage: mix atlas.documents.import_paperless /path/to/paperless/export")

  defp regular_document?(path) do
    File.regular?(path) and (Path.extname(path) |> String.downcase()) in @extensions
  end

  defp content_type(path) do
    Path.extname(path)
    |> String.downcase()
    |> case do
      ".pdf" -> "application/pdf"
      ".md" -> "text/markdown"
      _ -> "text/plain"
    end
  end
end
