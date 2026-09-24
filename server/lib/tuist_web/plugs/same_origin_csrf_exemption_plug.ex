defmodule TuistWeb.Plugs.SameOriginCSRFExemptionPlug do
  @moduledoc """
  Exempts provably same-origin requests from `Plug.CSRFProtection`.

  Marketing HTML is stored by shared caches without `Set-Cookie`, so the
  CSRF token embedded in a cached page belongs to whichever session
  produced the copy and never validates for the visitors it is served to.
  Endpoints posted to from those pages cannot rely on the page's token.
  This plug lets them prove same-origin through headers the browser sets
  and page scripts cannot forge instead:

    * `Sec-Fetch-Site: same-origin` is authoritative when present.
    * Older browsers only send `Origin`, which must equal the public
      origin of this request (`TuistWeb.RequestOrigin.from_conn/1`)
      exactly.

  Anything else, including a missing `Origin`, falls through to the
  regular token check. Pipe it before the pipeline that plugs
  `:protect_from_forgery`, and only through a scope that contains the
  routes meant to be exempt, because the exemption applies to every
  request that passes through it.
  """

  @behaviour Plug

  import Plug.Conn

  alias TuistWeb.RequestOrigin

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if same_origin_request?(conn) do
      put_private(conn, :plug_skip_csrf_protection, true)
    else
      conn
    end
  end

  def same_origin_request?(conn) do
    case get_req_header(conn, "sec-fetch-site") do
      ["same-origin"] -> true
      [] -> get_req_header(conn, "origin") == [RequestOrigin.from_conn(conn)]
      _ -> false
    end
  end
end
