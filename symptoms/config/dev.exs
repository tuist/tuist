import Config

config :logger, :console, format: "[$level] $message\n"

config :phoenix, :plug_init_mode, :runtime
config :phoenix, :stacktrace_depth, 20

config :symptoms, Symptoms.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "symptoms_dev",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :symptoms, SymptomsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4200],
  check_origin: false,
  code_reloader: true,
  debug_errors: true
