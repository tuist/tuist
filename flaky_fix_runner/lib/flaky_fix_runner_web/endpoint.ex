defmodule FlakyFixRunnerWeb.Endpoint do
  use Sentry.PlugCapture
  use Phoenix.Endpoint, otp_app: :flaky_fix_runner

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])
  plug(Sentry.PlugContext)

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Phoenix.json_library(),
    body_reader: {FlakyFixRunnerWeb.Plugs.CacheBodyReader, :read_body, []}
  )

  plug(FlakyFixRunnerWeb.Router)
end
