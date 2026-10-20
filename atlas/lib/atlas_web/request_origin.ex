defmodule AtlasWeb.RequestOrigin do
  @moduledoc """
  Builds the externally-visible origin (scheme://host[:port]) for an
  incoming request. Honors `x-forwarded-host` when present and drops the
  port when it matches the default for the scheme. Shared by the OAuth
  well-known controller and the MCP auth plug so both produce identical
  URLs in metadata and `www-authenticate` headers.
  """

  alias Plug.Conn

  def from_conn(%Plug.Conn{} = conn) do
    scheme = Atom.to_string(conn.scheme)

    host =
      case Conn.get_req_header(conn, "x-forwarded-host") do
        [h | _] -> h
        _ -> conn.host
      end

    port = conn.port

    cond do
      scheme == "http" and port == 80 -> "http://#{host}"
      scheme == "https" and port == 443 -> "https://#{host}"
      true -> "#{scheme}://#{host}:#{port}"
    end
  end
end
