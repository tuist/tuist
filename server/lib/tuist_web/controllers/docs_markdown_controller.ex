defmodule TuistWeb.DocsMarkdownController do
  @moduledoc false
  use TuistWeb, :controller

  alias TuistWeb.DocsMarkdown
  alias TuistWeb.Utilities.MarkdownResponse

  def show(conn, %{"locale" => locale} = params) do
    path_segments = Map.get(params, "path", [])

    case DocsMarkdown.get(locale, path_segments) do
      :error ->
        send_resp(conn, :not_found, "Page not found")

      {:ok, markdown} ->
        conn
        |> MarkdownResponse.prepare(markdown)
        |> send_resp(:ok, markdown)
    end
  end
end
