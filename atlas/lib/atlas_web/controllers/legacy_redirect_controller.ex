defmodule AtlasWeb.LegacyRedirectController do
  # 2026-09 sidebar reshuffle moved the internal dashboard under grouped
  # prefixes (Commercial / Outbound / Operations / Library / Admin). These
  # redirects keep the old bare URLs working so bookmarks and muscle memory
  # do not 404. External URLs (OAuth callbacks, webhooks, download links) are
  # intentionally NOT redirected because their old paths are still live.

  use AtlasWeb, :controller

  def sales_index(conn, _params), do: moved(conn, "/commercial/sales")
  def sales(conn, %{"rest" => rest}), do: moved(conn, "/commercial/sales/" <> Enum.join(rest, "/"), conn.query_string)

  def finance_index(conn, _params), do: moved(conn, "/commercial/finance")
  def finance(conn, %{"rest" => rest}), do: moved(conn, "/commercial/finance/" <> Enum.join(rest, "/"), conn.query_string)

  def gtm(conn, %{"rest" => rest}), do: moved(conn, "/commercial/gtm/" <> Enum.join(rest, "/"), conn.query_string)

  def support_index(conn, _params), do: moved(conn, "/commercial/support")

  def email_index(conn, _params), do: moved(conn, "/outbound/email")
  def email_audience(conn, %{"id" => id}), do: moved(conn, "/outbound/email/audiences/#{id}")

  def postal_index(conn, _params), do: moved(conn, "/outbound/postal")

  def hardware_index(conn, _params), do: moved(conn, "/operations/hardware")
  def hardware(conn, %{"rest" => rest}), do: moved(conn, "/operations/hardware/" <> Enum.join(rest, "/"), conn.query_string)

  def documents_index(conn, _params), do: moved(conn, "/library/documents")
  def documents_show(conn, %{"id" => id}), do: moved(conn, "/library/documents/#{id}")

  def notes_index(conn, _params), do: moved(conn, "/library/notes")
  def notes_new(conn, _params), do: moved(conn, "/library/notes/new")
  def notes_show(conn, %{"id" => id}), do: moved(conn, "/library/notes/#{id}")

  def mcps_index(conn, _params), do: moved(conn, "/admin/mcps")

  def sessions_index(conn, _params), do: moved(conn, "/admin/sessions")
  def sessions_show(conn, %{"id" => id}), do: moved(conn, "/admin/sessions/#{id}")

  def memory_index(conn, _params), do: moved(conn, "/admin/memory")
  def memory_show(conn, %{"id" => id}), do: moved(conn, "/admin/memory/#{id}")

  defp moved(conn, path, "" = _query), do: moved(conn, path)
  defp moved(conn, path, nil), do: moved(conn, path)
  defp moved(conn, path, query), do: moved(conn, path <> "?" <> query)

  defp moved(conn, path) do
    conn
    |> put_status(:moved_permanently)
    |> redirect(to: path)
  end
end
