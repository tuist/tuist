import Config

{:ok, ip} = System.get_env("HOST", "127.0.0.1") |> String.to_charlist() |> :inet.parse_address()
port = String.to_integer(System.get_env("PORT", "3077"))
origin = System.get_env("PUBLIC_URL", "http://localhost:#{port}") |> String.trim_trailing("/")
url = URI.parse(origin)

config :tuist_labels, TuistLabelsWeb.Endpoint,
  http: [ip: ip, port: port],
  url: [host: url.host, scheme: url.scheme, port: url.port],
  check_origin: [origin, "http://localhost:#{port}", "http://127.0.0.1:#{port}"],
  secret_key_base:
    System.get_env("SECRET_KEY_BASE") || Base.encode64(:crypto.strong_rand_bytes(64))
