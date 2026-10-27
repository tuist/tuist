defmodule AtlasWeb.DocumentLinks do
  @moduledoc """
  Helpers for document file links.
  """

  use AtlasWeb, :verified_routes

  alias Atlas.Documents.Document

  def download_path(%Document{} = document) do
    ~p"/documents/#{document.id}/download/#{download_filename(document)}"
  end

  def download_url(%Document{} = document) do
    url(~p"/documents/#{document.id}/download/#{download_filename(document)}")
  end

  def download_filename(%Document{} = document) do
    slug =
      (document.title || document.original_filename || "document")
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    slug = if slug == "", do: "document", else: slug
    slug <> extension(document)
  end

  defp extension(%Document{} = document) do
    document.original_filename
    |> to_string()
    |> Path.extname()
    |> String.downcase()
    |> case do
      "" -> content_type_extension(document.content_type)
      ext -> ext
    end
  end

  defp content_type_extension("application/pdf"), do: ".pdf"
  defp content_type_extension("text/plain"), do: ".txt"
  defp content_type_extension(_content_type), do: ""
end
