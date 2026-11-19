defmodule LuftServerWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :luft_server

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

  # The web app's Vite build (`priv/static`, copied in by the Dockerfile).
  # Vite content-hashes everything under /assets, so it never changes and
  # Cloudflare and browsers keep it for a year; the Dockerfile adds the `.gz`
  # copies `gzip: true` serves. Only /assets: if luft/web gains a `public/`
  # directory, list its root files here, or they get the HTML shell. The shell
  # is `LuftServerWeb.WebController`'s.
  plug Plug.Static,
    at: "/",
    from: :luft_server,
    only: ~w(assets),
    gzip: true,
    headers: [{"cache-control", "public, max-age=31536000, immutable"}]

  plug Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Phoenix.json_library()

  plug Plug.Head
  plug Plug.Session, @session_options
  plug LuftServerWeb.Router
end
