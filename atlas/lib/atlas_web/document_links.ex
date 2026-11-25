defmodule AtlasWeb.DocumentLinks do
  @moduledoc """
  Helpers for document file links.
  """

  use AtlasWeb, :verified_routes

  alias Atlas.Documents.Document
  alias Atlas.Users.User
  alias AtlasWeb.Endpoint

  @signed_salt "document-signed-download"
  @signed_max_age 900

  def download_path(%Document{} = document) do
    ~p"/documents/#{document.id}/download/#{download_filename(document)}"
  end

  def download_url(%Document{} = document) do
    url(~p"/documents/#{document.id}/download/#{download_filename(document)}")
  end

  @doc """
  A link that serves the file without an Atlas session for `signed_max_age/0`
  seconds, for agents whose HTTP client cannot sign in. It is bound to `user`,
  and `AtlasWeb.DocumentSignedDownloadController` checks that user's document
  access again when the link is opened.
  """
  def signed_download_url(%Document{} = document, %User{id: user_id}) do
    token = Phoenix.Token.sign(Endpoint, @signed_salt, %{"document_id" => document.id, "user_id" => user_id})
    url(~p"/documents/#{document.id}/file/#{download_filename(document)}?#{%{token: token}}")
  end

  def signed_download_expires_at do
    DateTime.utc_now() |> DateTime.add(@signed_max_age, :second) |> DateTime.truncate(:second)
  end

  def signed_max_age, do: @signed_max_age

  def verify_signed_download(token) when is_binary(token),
    do: Phoenix.Token.verify(Endpoint, @signed_salt, token, max_age: @signed_max_age)

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
