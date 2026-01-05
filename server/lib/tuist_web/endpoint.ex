defmodule TuistWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :tuist

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  alias TuistWeb.Plugs.WebhookPlug
  alias TuistWeb.Webhooks.BillingController
  alias TuistWeb.Webhooks.GitHubController

  @session_options [
    store: :cookie,
    key: "_tuist_key",
    signing_salt: "tmgjS63H",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [:user_agent, session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  socket "/socket", TuistWeb.Socket,
    websocket: true,
    longpoll: false

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :tuist,
    gzip: false,
    only: TuistWeb.static_paths()

  if Code.ensure_loaded?(Tidewave) do
    plug Tidewave
  end

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :tuist
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]
  plug TuistCommon.Plugs.RequestContextPlug, enabled_fn: &Tuist.Environment.error_tracking_enabled?/0
  plug TuistWeb.Plugs.CloseConnectionOnErrorPlug

  plug Stripe.WebhookPlug,
    at: "/webhooks/stripe",
    handler: BillingController,
    secret: {Tuist.Environment, :stripe_endpoint_secret, []}

  plug WebhookPlug,
    at: "/webhooks/github",
    handler: GitHubController,
    secret: {Tuist.Environment, :github_app_webhook_secret, []},
    signature_header: "x-hub-signature-256",
    signature_prefix: "sha256="

  plug WebhookPlug,
    at: "/webhooks/cache",
    handler: TuistWeb.Webhooks.CacheController,
    secret: {Tuist.Environment, :cache_api_key, []},
    signature_header: "x-cache-signature"

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug TuistWeb.Router
end
