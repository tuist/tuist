defmodule TuistWeb.RequestOrigin do
  @moduledoc false

  def from_conn(conn) do
    scheme =
      case Plug.Conn.get_req_header(conn, "x-forwarded-proto") do
        [proto] -> proto
        _ -> Atom.to_string(conn.scheme)
      end

    default_port = if scheme == "https", do: 443, else: 80
    authority = if conn.port == default_port, do: conn.host, else: "#{conn.host}:#{conn.port}"
    "#{scheme}://#{authority}"
  end
end
