defmodule LuftServerWeb.Plugs.SecurityHeaders do
  @moduledoc """
  Security headers for every response on `luft.work`, the web app's static
  files and shell as well as the API. The content security policy allows
  `'wasm-unsafe-eval'` so the browser can compile the Luft core's WebAssembly.
  In development the page also connects to Vite's HMR WebSocket.
  """
  @behaviour Plug

  import Plug.Conn

  alias LuftServer.Config

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    merge_resp_headers(conn, [
      {"content-security-policy", content_security_policy()},
      {"strict-transport-security", "max-age=31536000"},
      {"x-content-type-options", "nosniff"},
      {"referrer-policy", "strict-origin-when-cross-origin"}
    ])
  end

  defp content_security_policy do
    connect_src = Enum.join(["'self'", "https:", "wss:" | vite_hmr_sources()], " ")

    "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; connect-src #{connect_src}; " <>
      "img-src 'self' data: https:; style-src 'self' 'unsafe-inline'; frame-ancestors 'none'; " <>
      "base-uri 'self'; form-action 'self'; object-src 'none'"
  end

  defp vite_hmr_sources do
    case Config.vite_dev_server() do
      nil -> []
      url -> [String.replace_prefix(url, "http", "ws")]
    end
  end
end
