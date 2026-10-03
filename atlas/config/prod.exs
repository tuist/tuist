import Config

alias Swoosh.ApiClient.Req
# before starting your production server.
# known as HSTS. If you have a health check endpoint, you may want to exclude it below.
# Note `:force_ssl` is required to be set at compile-time.
config :atlas, AtlasWeb.Endpoint, cache_static_manifest: "priv/static/cache_manifest.json"

config :atlas, AtlasWeb.Endpoint,
  force_ssl: [
    rewrite_on: [:x_forwarded_proto],
    exclude: [paths: ["/up"]]
  ]

# Do not print debug messages in production
config :logger, level: :info

# Configure Swoosh API Client
config :swoosh, api_client: Req

# Disable Swoosh Local Memory Storage
config :swoosh, local: false

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
