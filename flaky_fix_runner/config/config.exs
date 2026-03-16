import Config

config :flaky_fix_runner, FlakyFixRunnerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: FlakyFixRunnerWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: FlakyFixRunner.PubSub

config :flaky_fix_runner,
  env: config_env(),
  namespace: FlakyFixRunner

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

config :tuist_common, finch_name: FlakyFixRunner.Finch

config :sentry,
  client: TuistCommon.SentryHTTPClient,
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()],
  before_send: {TuistCommon.SentryEventFilter, :before_send}

import_config "#{config_env()}.exs"
