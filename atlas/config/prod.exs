import Config

alias AtlasWeb.Plugs.PagesSubdomain
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

# Widen the Atlas session cookie so every `<slug>.atlas.tuist.dev` Pages site
# inherits the same authentication as the dashboard. Nothing else lives under
# the atlas.tuist.dev host, so scoping to that parent is safe.
config :atlas, PagesSubdomain, host_suffix: "atlas.tuist.dev"
config :atlas, :session_cookie_domain, ".atlas.tuist.dev"

# Do not print debug messages in production
config :logger, level: :info

# Configure Swoosh API Client
config :swoosh, api_client: Req

# Disable Swoosh Local Memory Storage
config :swoosh, local: false

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
