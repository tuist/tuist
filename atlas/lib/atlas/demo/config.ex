defmodule Atlas.Demo.Config do
  @moduledoc false

  @allowed_keys ~w(ATLAS_DEMO_MODE ATLAS_ALLOWED_EMAIL_DOMAIN ATLAS_CLICKHOUSE_ENABLED ATLAS_VERSION ATLAS_GIT_COMMIT SENTRY_RELEASE)
  @integration_prefixes ~w(ATLAS_ GOOGLE_ MAILGUN_ STRIPE_ LLM_ QONTO_ MERCURY_ GRANOLA_ APOLLO_ SLACK_ SENTRY_ GRAFANA_ TUIST_SERVER_ TUIST_MCP_ PAPERLESS_)
  @integration_keys ~w(BRAVE_SEARCH_API_KEY SUPER_ADMIN_PASSWORD CHROME_PATH)

  # Pure validation also makes runtime configuration testable without changing
  # the process-wide environment in concurrently running tests.
  def validate!(env) do
    database = env |> Map.get("DATABASE_URL", "") |> URI.parse()

    if !(database.path == "/atlas_demo" and database.query == nil) do
      raise "Atlas demo requires a dedicated DATABASE_URL ending in /atlas_demo"
    end

    if Map.get(env, "ATLAS_CLICKHOUSE_ENABLED") not in [nil, "", "false", "0"] do
      raise "ClickHouse must be disabled in the Atlas demo"
    end

    if Map.get(env, "MCP_PROXY_SERVERS") not in [nil, "", "[]"] do
      raise "Upstream MCP servers must be disabled in the Atlas demo"
    end

    Enum.each(env, fn {key, value} ->
      if value not in [nil, ""] and key not in @allowed_keys and
           (key in @integration_keys or Enum.any?(@integration_prefixes, &String.starts_with?(key, &1))) do
        raise "Integration configuration #{key} is not permitted in the Atlas demo"
      end
    end)

    :ok
  end
end
