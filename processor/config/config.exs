import Config

config :processor, ProcessorWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: ProcessorWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Processor.PubSub

config :processor,
  env: config_env(),
  namespace: Processor

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, JSON

config :tuist_common, finch_name: Processor.Finch

config :sentry,
  client: TuistCommon.SentryHTTPClient,
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()],
  before_send: {TuistCommon.SentryEventFilter, :before_send}

import_config "#{config_env()}.exs"
