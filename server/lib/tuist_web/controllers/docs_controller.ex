defmodule TuistWeb.DocsController do
  use TuistWeb, :controller

  alias Tuist.Docs.Redirects
  alias TuistWeb.Errors.NotFoundError

  def legacy(conn, _params) do
    docs_path = strip_docs_prefix(conn.request_path)

    case Redirects.redirect_path(docs_path) do
      nil ->
        raise NotFoundError, dgettext("errors", "Page not found")

      destination ->
        permanent_redirect(conn, "/docs" <> destination)
    end
  end

  defp strip_docs_prefix("/docs" <> rest), do: rest
  defp strip_docs_prefix(path), do: path

  defp permanent_redirect(conn, destination) do
    destination =
      if conn.query_string == "" do
        destination
      else
        "#{destination}?#{conn.query_string}"
      end

    conn
    |> put_status(:moved_permanently)
    |> redirect(to: destination)
    |> halt()
  end
end
