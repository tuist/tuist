import Config

config :cache,
  namespace: Cache

# Configures the endpoint
config :cache, CacheWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Phoenix.Endpoint.Cowboy2Adapter,
  render_errors: [
    formats: [json: CacheWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Cache.PubSub,
  live_view: [signing_salt: "unique_salt_here"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON encoding
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
