defmodule LuftServerWeb.Plugs.SecurityHeaders do
  @moduledoc """
  Security headers for the Luft origin: the headless API allows nothing, and
  the GPUI web edge under `/app` allows only what it needs.
  """
  @behaviour Plug

  import Plug.Conn

  @api_policy "default-src 'none'; frame-ancestors 'none'; base-uri 'none'"

  # Its own scripts and wasm module, the inline styles it sets on its canvas
  # and accessibility elements, and API calls to this origin. Its page sets
  # `<base href="/app/">`.
  @app_policy Enum.join(
                [
                  "default-src 'none'",
                  "script-src 'self' 'wasm-unsafe-eval'",
                  "connect-src 'self'",
                  "style-src 'self' 'unsafe-inline'",
                  "img-src 'self' data: blob:",
                  "frame-ancestors 'none'",
                  "base-uri 'self'",
                  "form-action 'none'"
                ],
                "; "
              )

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    policy =
      case conn.path_info do
        ["app" | _] -> @app_policy
        _ -> @api_policy
      end

    merge_resp_headers(conn, [
      {"content-security-policy", policy},
      {"strict-transport-security", "max-age=31536000"},
      {"x-content-type-options", "nosniff"},
      {"referrer-policy", "strict-origin-when-cross-origin"}
    ])
  end
end
