defmodule TuistOpsWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :tuist_ops

  # The operator HTML pages need the Noora bundle; Slack/Pomerium are
  # still JSON. The Slack webhook plug reads raw body for signatures.

  # Cookie session, used only to carry the CSRF token for the grant
  # reason form (identity is Pomerium's, not this session). SameSite=Lax
  # so a cross-site POST can't replay it.
  @session_options [
    store: :cookie,
    key: "_tuist_ops_key",
    signing_salt: "tuist-ops-session",
    same_site: "Lax"
  ]

  plug Plug.Static,
    at: "/",
    from: {:tuist_ops, "priv/static"},
    gzip: false,
    only: TuistOpsWeb.static_paths()

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library(),
    body_reader: {TuistOpsWeb.Plugs.CachingBodyReader, :read_body, []}

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug TuistOpsWeb.Router
end
