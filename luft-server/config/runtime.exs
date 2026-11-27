import Config

config :luft_server, dns_cluster_query: System.get_env("DNS_CLUSTER_QUERY")
config :luft_server, git_endpoint: System.get_env("LUFT_GIT_ENDPOINT")

if System.get_env("PHX_SERVER") do
  config :luft_server, LuftServerWeb.Endpoint, server: true
end

if config_env() == :prod do
  fetch! = fn name ->
    System.get_env(name) || raise "environment variable #{name} is missing."
  end

  public_url = System.get_env("PUBLIC_URL", "https://luft.work")
  %URI{host: host} = URI.parse(public_url)

  config :luft_server, LuftServer.Repo,
    url: fetch!.("DATABASE_URL"),
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  config :luft_server, LuftServerWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: String.to_integer(System.get_env("PORT") || "8080")
    ],
    secret_key_base: fetch!.("SECRET_KEY_BASE")

  config :luft_server,
    tuist_issuer: System.get_env("TUIST_URL", "https://tuist.dev"),
    public_url: public_url,
    oauth_client_id: fetch!.("LUFT_SERVER_OAUTH_CLIENT_ID"),
    oauth_client_secret: fetch!.("LUFT_SERVER_OAUTH_CLIENT_SECRET"),
    # Optional: without it, ChatGPT subscriptions can't be connected.
    chatgpt_client_id: System.get_env("LUFT_CHATGPT_CLIENT_ID")
end
