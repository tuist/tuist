import Config

if System.get_env("PHX_SERVER") do
  config :tuist_jit, TuistJitWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      Should be a postgres:// URL pointing at the JIT CNPG cluster.
      """

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      Generate via `mix phx.gen.secret`.
      """

  host = System.get_env("PHX_HOST") || "tuist-jit.tuist.dev"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :tuist_jit, TuistJit.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    show_sensitive_data_on_connection_error: false

  config :tuist_jit, TuistJitWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base
end
