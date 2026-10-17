defmodule Atlas.Demo.ConfigTest do
  use ExUnit.Case, async: true

  alias Atlas.Demo.Config

  @env %{"DATABASE_URL" => "ecto://reader:password@demo-postgres/atlas_demo"}

  test "accepts only an isolated database and no integrations" do
    assert :ok = Config.validate!(@env)
    assert :ok = Config.validate!(Map.merge(@env, %{"MCP_PROXY_SERVERS" => "[]", "CHROME_PATH" => ""}))
  end

  test "rejects a production database or connection parameters" do
    for url <- ["ecto://reader:password@postgres/atlas", "ecto://reader:password@postgres/atlas_demo?options=unsafe"] do
      assert_raise RuntimeError, ~r/dedicated DATABASE_URL/, fn ->
        Config.validate!(Map.put(@env, "DATABASE_URL", url))
      end
    end
  end

  test "rejects credentials and upstream configuration" do
    for key <-
          ~w(STRIPE_API_KEY LLM_API_KEY GOOGLE_CLIENT_ID MAILGUN_API_KEY ATLAS_OBJECT_STORAGE_BUCKET ATLAS_GITHUB_APP_ID SLACK_COMPANY_BOT_TOKEN ATLAS_LICENSE_SIGNING_PRIVATE_KEY TUIST_SERVER_TOKEN_PATH ATLAS_CLICKHOUSE_PASSWORD ATLAS_TAX_CERTIFICATE_SIGNATURE_JPEG_BASE64 ATLAS_INVOICE_FOOTER LLM_MODEL LLM_BASE_URL TUIST_MCP_BASE_URL SUPER_ADMIN_PASSWORD ATLAS_FUTURE_INTEGRATION_TOKEN) do
      assert_raise RuntimeError, ~r/not permitted/, fn ->
        Config.validate!(Map.put(@env, key, "configured"))
      end
    end

    assert_raise RuntimeError, ~r/ClickHouse must be disabled/, fn ->
      Config.validate!(Map.put(@env, "ATLAS_CLICKHOUSE_ENABLED", "true"))
    end

    assert_raise RuntimeError, ~r/Upstream MCP servers/, fn ->
      Config.validate!(Map.put(@env, "MCP_PROXY_SERVERS", "tuist-managed"))
    end
  end
end
