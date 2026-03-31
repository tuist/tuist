defmodule XcodeProcessorWeb.Endpoint do
  use Sentry.PlugCapture
  use Phoenix.Endpoint, otp_app: :xcode_processor

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Sentry.PlugContext

  plug Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Phoenix.json_library(),
    body_reader: {XcodeProcessorWeb.Plugs.CacheBodyReader, :read_body, []}

  plug XcodeProcessorWeb.Router
end
