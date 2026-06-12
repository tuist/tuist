defmodule TuistOpsWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :tuist_ops

  # Slack and Pomerium both POST application/json — no static assets,
  # no LiveView socket, no session cookies needed. The Slack webhook
  # plug reads raw body for signature verification.

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library(),
    body_reader: {TuistOpsWeb.Plugs.CachingBodyReader, :read_body, []}

  plug Plug.MethodOverride
  plug Plug.Head
  plug TuistOpsWeb.Router
end
