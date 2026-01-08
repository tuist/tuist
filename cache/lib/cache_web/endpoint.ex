defmodule CacheWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :cache

  @session_options [
    store: :cookie,
    key: "_cache_key",
    signing_salt: "oban_web_salt",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  if code_reloading? do
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]
  plug TuistCommon.Plugs.RequestContextPlug
  plug Cache.Appsignal.SamplingPlug

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride

  plug Plug.Session, @session_options

  plug CacheWeb.Router
end
