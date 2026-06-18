import Config

config :tuist_ops, TuistOps.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "tuist_ops_dev",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :tuist_ops, TuistOpsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4100],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev_secret_key_base_only_for_local_development_do_not_use_in_prod_____",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:tuist_ops, ~w(--sourcemap=inline --watch)]}
  ]

config :logger, :console, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
