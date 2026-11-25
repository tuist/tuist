import Config

if System.get_env("PHX_SERVER") do
  config :symptoms, SymptomsWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      Should be a postgres:// URL pointing at the Symptoms CNPG cluster.
      """

  host = System.get_env("PHX_HOST") || "symptoms.tuist.dev"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :symptoms, Symptoms.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    show_sensitive_data_on_connection_error: false

  config :symptoms, SymptomsWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: port]

  config :symptoms, migrate_on_boot: System.get_env("SKIP_MIGRATIONS") != "true"
end

# Every SYMPTOMS_* variable the evaluator reads, in one place. Modules read
# application config only; infra/helm/symptoms sets these (its README has the
# table).
if config_env() != :test do
  present = fn pairs -> Enum.reject(pairs, fn {_key, value} -> is_nil(value) or value == "" end) end

  kubernetes_host = System.get_env("KUBERNETES_SERVICE_HOST")
  kubernetes_port = System.get_env("KUBERNETES_SERVICE_PORT", "443")

  config :symptoms,
         Symptoms.Sources.Prometheus,
         present.(
           base_url: System.get_env("SYMPTOMS_PROMETHEUS_URL"),
           user: System.get_env("SYMPTOMS_PROMETHEUS_USER"),
           token: System.get_env("SYMPTOMS_PROMETHEUS_TOKEN")
         )

  config :symptoms,
         Symptoms.Sources.Pulse,
         present.(
           base_url: System.get_env("SYMPTOMS_PULSE_URL"),
           user: System.get_env("SYMPTOMS_PULSE_USER"),
           token: System.get_env("SYMPTOMS_PULSE_TOKEN"),
           write_user: System.get_env("SYMPTOMS_PULSE_WRITE_USER"),
           write_token: System.get_env("SYMPTOMS_PULSE_WRITE_TOKEN")
         )

  config :symptoms, :api_auth,
    server_namespace: System.get_env("SYMPTOMS_SERVER_NAMESPACE"),
    server_service_account: System.get_env("SYMPTOMS_SERVER_SERVICE_ACCOUNT"),
    base_url: if(kubernetes_host, do: "https://#{kubernetes_host}:#{kubernetes_port}"),
    token_path: "/var/run/secrets/kubernetes.io/serviceaccount/token",
    ca_file: "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"

  config :symptoms, :paging,
    enabled: System.get_env("SYMPTOMS_PAGING_ENABLED") == "true",
    webhook_url: System.get_env("SYMPTOMS_IRM_WEBHOOK_URL"),
    token: System.get_env("SYMPTOMS_IRM_WEBHOOK_TOKEN"),
    link_base_url: System.get_env("SYMPTOMS_LINK_BASE_URL")

  # The Tuist server: state read-back, with the projected
  # ServiceAccount token.
  config :symptoms, :state,
    base_url: System.get_env("SYMPTOMS_STATE_URL"),
    token_path: System.get_env("SYMPTOMS_STATE_TOKEN_PATH", "/var/run/secrets/tuist-symptoms-state/token")

  # The `environment` of every entity the sources report.
  config :symptoms, environment: System.get_env("SYMPTOMS_ENVIRONMENT", "production")
end
