defmodule TuistWeb.RequestOrigin do
  @moduledoc false

  def from_conn(conn) do
    scheme = Atom.to_string(conn.scheme)
    default_port = if scheme == "https", do: 443, else: 80
    authority = if conn.port == default_port, do: conn.host, else: "#{conn.host}:#{conn.port}"
    "#{scheme}://#{authority}"
  end
end
