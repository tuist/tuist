defmodule TuistWeb.DocsMarkdownController do
  @moduledoc false
  use TuistWeb, :controller

  alias Tuist.Docs
  alias Tuist.Docs.Paths
  alias TuistWeb.Utilities.MarkdownResponse

  def show(conn, %{"locale" => locale} = params) do
    path_segments = Map.get(params, "path", [])

    case Docs.get_page(locale, path_segments) do
      %{markdown: markdown, slug: slug} when is_binary(markdown) and markdown != "" ->
        # The Markdown twin duplicates an HTML page. Point search engines at that page,
        # using the served page's slug so untranslated locale fallbacks name the English page.
        canonical_url = Tuist.Environment.app_url(path: Paths.public_path_from_slug(slug))

        conn
        |> put_resp_header("link", ~s(<#{canonical_url}>; rel="canonical"))
        |> MarkdownResponse.prepare(markdown)
        |> send_resp(:ok, markdown)

      _ ->
        send_resp(conn, :not_found, "Page not found")
    end
  end
end
