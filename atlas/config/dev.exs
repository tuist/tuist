import Config

alias Atlas.Config.DevInstance
alias Atlas.Documents.Storage.Local

Code.require_file("dev_instance.exs", __DIR__)

# Configure your database.
config :atlas, Atlas.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: DevInstance.database_name("atlas_dev"),
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  # Binding to loopback ipv4 address prevents access from other machines.
  # Change to `ip: {0, 0, 0, 0}` to allow access from other machines.
  pool_size: 10

config :atlas, AtlasWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "VBnDAN2tqeGopnE7orVBM/MteFQDk5yi/VVW6ACe/Ga2WKy+xZ9uiOJdhdFcU0zO",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:atlas, ~w(--sourcemap=inline --watch)]}
  ]

# Reload browser tabs when matching files change.
config :atlas, AtlasWeb.Endpoint,
  live_reload: [
    web_console_logger: true,
    patterns: [
      # Static assets, except user uploads
      ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$",
      # Gettext translations
      ~r"priv/gettext/.*\.po$",
      # Router, Controllers, LiveViews and LiveComponents
      ~r"lib/atlas_web/router\.ex$",
      ~r"lib/atlas_web/(controllers|live|components)/.*\.(ex|heex)$"
    ]
  ]

# In development, store document objects inside the gitignored repository tmp
# directory so the upload and import flows work without S3 credentials.
config :atlas, :documents,
  storage_client: Local,
  local_storage_path: "tmp/documents",
  embedding_client: Atlas.Documents.Embedding.Local,
  embedding_model: "local-hash-embedding"

# Development-only Ed25519 private key. Production uses a separately managed key.
config :atlas, :licenses, signing_private_key: "ceVGk4YZk7sbZwxHUUlONbFr+rmJ1V9KlTWUdkHjyMI="

# Default admin password for development.
config :atlas, admin_password: "admin"

# Enable dev routes for dashboard and mailbox.
config :atlas, dev_routes: true

# Do not include metadata nor timestamps in development logs.
config :logger, :default_formatter, format: "[$level] $message\n"

# Initialize plugs at runtime for faster development compilation.
config :phoenix, :plug_init_mode, :runtime

# Set a higher stacktrace during development. Avoid configuring this in
# production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

config :phoenix_live_view,
  # Include debug annotations and locations in rendered markup.
  # Changing this configuration will require mix clean and a full recompile.
  debug_heex_annotations: true,
  debug_attributes: true,
  # Enable helpful, but potentially expensive runtime checks
  enable_expensive_runtime_checks: true

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false
