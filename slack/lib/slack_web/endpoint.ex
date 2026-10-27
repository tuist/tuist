defmodule SlackWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :slack

  alias Phoenix.LiveView.Socket

  @session_options [
    store: :cookie,
    key: "_slack_key",
    signing_salt: "p3m0Ss1v",
    same_site: "Lax"
  ]

  socket "/live", Socket,
    websocket: [connect_info: [:peer_data, session: @session_options]],
    longpoll: [connect_info: [:peer_data, session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :slack,
    gzip: false,
    only: SlackWeb.static_paths()

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug SlackWeb.Router
end
