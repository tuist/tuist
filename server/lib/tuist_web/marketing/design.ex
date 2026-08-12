defmodule TuistWeb.Marketing.Design do
  @moduledoc """
  Decides whether a marketing page renders the redesigned version or the
  legacy one while the redesign rolls out page by page.

  The public rollout is driven by per-page FunWithFlags booleans (see
  `Tuist.FeatureFlags.new_marketing_page_enabled?/1`). On top of that, this
  plug supports a cookie override so the new design can be previewed (or the
  old one recovered) on any environment before a flag is flipped:

    * `?design=new` — preview the redesigned pages
    * `?design=old` — force the legacy pages
    * `?design=default` — clear the override and follow the flags

  The override is stored in a cookie so it sticks across navigation. Pages
  that have migrated call `new?/2` in their controller action to pick the
  template, and assign the result as `:new_design` so the root layout links
  bundle-new.css instead of bundle.css — the two designs restyle the same
  selectors, so their stylesheets are never loaded together.

  LiveView pages can't read cookies (they aren't part of the socket's
  session), so the plug mirrors the override into the Plug session and
  `new?/2` also accepts the session map handed to `mount/3`.
  """

  import Plug.Conn

  @cookie "tuist_marketing_design"
  @session_key "marketing_design"
  # Long enough to survive a preview/QA session, short enough that a stale
  # override on a visitor's browser eventually expires on its own.
  @cookie_max_age 60 * 60 * 24 * 30

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = conn |> fetch_query_params() |> fetch_cookies()

    conn =
      case conn.query_params["design"] do
        "new" -> put_override(conn, "new")
        "old" -> put_override(conn, "old")
        "default" -> conn |> delete_resp_cookie(@cookie) |> delete_session(@session_key)
        _ -> sync_session(conn)
      end

    maybe_bypass_shared_caches(conn)
  end

  @doc """
  Whether `page` (e.g. `:home`) should render its redesigned template for
  this request. The override wins over the page's feature flag.

  Takes the `conn` in controllers, or the session map in a LiveView's
  `mount/3`.
  """
  def new?(%Plug.Conn{} = conn, page) do
    conn = fetch_cookies(conn)

    resolve(override(conn), page)
  end

  def new?(session, page) when is_map(session) do
    resolve(session[@session_key], page)
  end

  defp put_override(conn, value) do
    conn
    |> put_resp_cookie(@cookie, value, max_age: @cookie_max_age)
    |> put_session(@session_key, value)
  end

  # Marketing responses are `public, max-age=60, stale-while-revalidate=86400`,
  # and once the override cookie and session agree the response carries no
  # Set-Cookie — nothing would stop a shared cache from storing a previewer's
  # variant at the ordinary URL and serving it to every visitor. Any request
  # rendered under an override (or clearing one) must therefore not be stored.
  # register_before_send, because the controller stamps cache-control in a
  # plug that runs after this one and would overwrite a header set here.
  defp maybe_bypass_shared_caches(conn) do
    if conn.query_params["design"] in ["new", "old", "default"] or conn.cookies[@cookie] in ["new", "old"] do
      register_before_send(conn, &put_resp_header(&1, "cache-control", "private, no-store"))
    else
      conn
    end
  end

  # The cookie is the override's home, so a browser that got one before the
  # session mirror existed (or on a request without `?design=`) still has to
  # reach LiveViews. Only write when the two disagree, to leave the session
  # cookie untouched on the vast majority of requests.
  defp sync_session(conn) do
    cookie = conn.cookies[@cookie]
    cookie = if cookie in ["new", "old"], do: cookie

    cond do
      get_session(conn, @session_key) == cookie -> conn
      is_nil(cookie) -> delete_session(conn, @session_key)
      true -> put_session(conn, @session_key, cookie)
    end
  end

  defp resolve("new", _page), do: true
  defp resolve("old", _page), do: false
  defp resolve(_, page), do: Tuist.FeatureFlags.new_marketing_page_enabled?(page)

  # A `?design=` param must win within the request that sets the cookie too:
  # response cookies aren't visible in conn.cookies until the next request.
  defp override(conn) do
    case conn.query_params["design"] do
      value when value in ["new", "old"] -> value
      "default" -> nil
      _ -> conn.cookies[@cookie]
    end
  end
end
