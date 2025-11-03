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
    # Get the configured app URL
    app_url = Tuist.Environment.app_url([route_type: :app])
    %{host: app_host, scheme: app_scheme, port: app_port} = URI.parse(app_url)

    # Override the x-forwarded-host header with the configured host
    # Ueberauth checks x-forwarded-host first when building callback URLs
    conn
    |> put_req_header("x-forwarded-host", app_host)
    |> put_req_header("x-forwarded-proto", app_scheme)
    |> maybe_put_forwarded_port(app_port, app_scheme)
  end

  defp maybe_put_forwarded_port(conn, nil, _scheme), do: conn
  defp maybe_put_forwarded_port(conn, 80, "http"), do: conn
  defp maybe_put_forwarded_port(conn, 443, "https"), do: conn
  defp maybe_put_forwarded_port(conn, port, _scheme) when is_integer(port) do
    put_req_header(conn, "x-forwarded-port", Integer.to_string(port))
  end
  defp maybe_put_forwarded_port(conn, _port, _scheme), do: conn
end
