defmodule LuftServerWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :luft_server

  socket "/threads/socket", LuftServerWeb.ConversationsSocket,
    auth_token: true,
    websocket: true,
    longpoll: false

  # Only the in-flight sign-in (state, nonce and PKCE verifier) lives in this
  # signed cookie, for the round trip to Tuist. It must be `Lax`: Tuist's
  # redirect back to `/auth/callback` is a cross-site navigation, which
  # carries no `Strict` cookies. The session proper is `LuftServerWeb.Auth`'s
  # opaque cookie, backed by the database.
  @session_options [
    store: :cookie,
    key: "_luft_signin",
    secure: Application.compile_env(:luft_server, :secure_cookies, true),
    signing_salt: "luft-signin",
    encryption_salt: "luft-signin-enc",
    same_site: "Lax",
    http_only: true,
    max_age: 600
  ]

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]
  plug LuftServerWeb.Plugs.SecurityHeaders

  plug Plug.Parsers,
    parsers: [:urlencoded, :json],
    pass: ["application/json", "application/x-www-form-urlencoded"],
    json_decoder: Phoenix.json_library()

  plug Plug.Head
  plug Plug.Session, @session_options
  plug LuftServerWeb.Router
end
