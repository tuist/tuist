import Config

config :logger, level: :warning

config :luft_server, LuftServer.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "luft_server_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :luft_server, LuftServerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4201],
  secret_key_base: "test_secret_key_base_only_for_tests____________________________________",
  server: false

config :luft_server,
  tuist_issuer: "https://tuist.test",
  public_url: "https://luft.test",
  oauth_client_id: "0b2f5c0e-7a3d-4c6e-9a51-2d4f8e1b6c37",
  oauth_client_secret: "test-secret",
  # Requests to Tuist go to `Req.Test` stubs.
  req_options: [plug: {Req.Test, LuftServer.Tuist}, retry: false],
  # Requests to OpenAI go to their own `Req.Test` stubs.
  openai_req_options: [plug: {Req.Test, LuftServer.OpenAI}],
  mcp_req_options: [plug: {Req.Test, LuftServer.MCPServers}],
  chatgpt_client_id: "test-chatgpt-client",
  # Each test stubs its own provider; a node-wide cache would leak between them.
  cache_provider_metadata: false

config :phoenix, :plug_init_mode, :runtime
config :luft_server, migrate_on_boot: false
config :luft_server, start_thread_runtime: false
config :luft_server, Oban, testing: :manual
