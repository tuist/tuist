defmodule CacheWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :cache

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library(),
    body_reader: {CacheWeb.Plugs.CacheBodyReader, :read_body, []}

  plug Plug.MethodOverride
  plug Plug.Head

  plug CacheWeb.Router
end