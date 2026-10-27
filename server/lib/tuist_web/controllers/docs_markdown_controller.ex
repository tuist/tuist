defmodule TuistWeb.DocsMarkdownController do
  @moduledoc false
  use TuistWeb, :controller

  alias Tuist.Docs
  alias TuistWeb.Utilities.MarkdownResponse

  def show(conn, %{"locale" => locale} = params) do
    path_segments = Map.get(params, "path", [])

    case Docs.get_page(locale, path_segments) do
      %{markdown: markdown} when is_binary(markdown) and markdown != "" ->
        conn
        |> MarkdownResponse.prepare(markdown)
        |> send_resp(:ok, markdown)

      _ ->
        send_resp(conn, :not_found, "Page not found")
    end
  end
end
