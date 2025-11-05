defmodule TuistWeb.Plugs.UeberauthHostPlug do
  @moduledoc """
  Sets the correct host header for Ueberauth OAuth callbacks when behind a load balancer.

  When using a load balancer (e.g., Cloudflare) that forwards requests with a different
  Host header than the public-facing domain, Ueberauth will build OAuth callback URLs
  using the internal host. This plug ensures the public app URL is used instead.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    app_url = Tuist.Environment.app_url(route_type: :app)
    %{host: app_host, scheme: app_scheme} = URI.parse(app_url)

    conn
    |> put_req_header("x-forwarded-host", app_host)
    |> put_req_header("x-forwarded-proto", app_scheme)
  end
end
