defmodule LuftServerWeb.Plugs.SecurityHeaders do
  @moduledoc """
  Security headers for the headless Luft origin.
  """
  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    merge_resp_headers(conn, [
      {"content-security-policy", "default-src 'none'; frame-ancestors 'none'; base-uri 'none'"},
      {"strict-transport-security", "max-age=31536000"},
      {"x-content-type-options", "nosniff"},
      {"referrer-policy", "strict-origin-when-cross-origin"}
    ])
  end
end
