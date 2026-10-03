defmodule TuistWeb.Marketing.Preferences do
  @moduledoc """
  Mirrors the marketing site's client-side preference cookies into the Plug
  session, so LiveViews can read them in `mount/3` — a LiveView socket carries
  the session, never the cookies.

  Today the only one is the blog index's grid/list view, written by the
  `BlogViewPreference` JS hook whenever the view changes. Reading it on the
  server (rather than from JS after load) is what lets the first paint already
  be in the visitor's preferred view.
  """

  import Plug.Conn

  @preferences %{"tuist_blog_view" => {"blog_view", ~w(grid list)}}

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_cookies(conn)

    Enum.reduce(@preferences, conn, fn {cookie, {session_key, allowed_values}}, conn ->
      sync(conn, cookie, session_key, allowed_values)
    end)
  end

  # Only writes when the two disagree, to leave the session cookie untouched on
  # the vast majority of requests.
  defp sync(conn, cookie, session_key, allowed_values) do
    value = if conn.cookies[cookie] in allowed_values, do: conn.cookies[cookie]

    cond do
      get_session(conn, session_key) == value -> conn
      is_nil(value) -> delete_session(conn, session_key)
      true -> put_session(conn, session_key, value)
    end
  end
end
