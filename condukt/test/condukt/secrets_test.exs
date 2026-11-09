defmodule Condukt.SecretsTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Condukt.{Message, Secrets}
  alias Condukt.Redactor
  alias Condukt.Secrets.Providers.OnePassword

  setup :set_mimic_from_context
  setup :verify_on_exit!

  test "resolves static and environment provider secrets" do
    assert {:ok, secrets} =
             Secrets.resolve(
               API_TOKEN: {:static, "static-token"},
               ENV_TOKEN:
                 {:env,
                  name: "CONDUKT_TEST_TOKEN",
                  fetch_env: fn
                    "CONDUKT_TEST_TOKEN" -> {:ok, "env-token"}
                    _name -> :error
                  end}
             )

    assert {"API_TOKEN", "static-token"} in secrets.env
    assert {"ENV_TOKEN", "env-token"} in secrets.env
    assert Enum.sort(Secrets.names(secrets)) == ["API_TOKEN", "ENV_TOKEN"]
  end

  test "later declarations replace earlier declarations" do
    assert {:ok, secrets} =
             Secrets.resolve(
               TOKEN: {:static, "old"},
               TOKEN: {:static, "new"}
             )

    assert secrets.env == [{"TOKEN", "new"}]
  end

  test "rejects invalid environment names" do
    assert {:error, {:invalid_secret_env_name, "not-valid-name"}} =
             Secrets.resolve(%{"not-valid-name" => {:static, "value"}})
  end

  test "redacts resolved secrets through the redactor pipeline" do
    {:ok, secrets} = Secrets.resolve(API_TOKEN: {:static, "secret-token"})

    messages = [
      Message.user("use secret-token"),
      Message.tool_result("call-1", %{"token" => "secret-token", "list" => ["secret-token"]})
    ]

    assert [
             %Message{content: "use [REDACTED:API_TOKEN]"},
             %Message{content: tool_content}
           ] = Redactor.redact_messages(Secrets.redactor(secrets), messages)

    assert JSON.decode!(tool_content) == %{
             "token" => "[REDACTED:API_TOKEN]",
             "list" => ["[REDACTED:API_TOKEN]"]
           }
  end

  test "redacts resolved secrets from stored tool result structures" do
    {:ok, secrets} = Secrets.resolve(API_TOKEN: {:static, "secret-token"})

    assert %{"token" => "[REDACTED:API_TOKEN]", "list" => ["[REDACTED:API_TOKEN]"]} =
             Secrets.redact_result(secrets, %{"token" => "secret-token", "list" => ["secret-token"]})
  end

  test "does not redact very short values" do
    {:ok, secrets} = Secrets.resolve(PIN: {:static, "123"})

    assert "pin 123" == Secrets.redact_text(secrets, "pin 123")
  end

  test "one password provider loads a secret reference with op read" do
    MuonTrap
    |> expect(:cmd, fn "op", ["read", "op://Engineering/GitHub/token", "--account", "acme"], opts ->
      assert opts[:stderr_to_stdout] == true
      assert opts[:timeout] == 5_000
      assert {"OP_SERVICE_ACCOUNT_TOKEN", "service-token"} in opts[:env]
      {"github-token\n", 0}
    end)

    assert {:ok, "github-token"} =
             OnePassword.load(
               ref: "op://Engineering/GitHub/token",
               account: "acme",
               timeout: 5_000,
               env: [OP_SERVICE_ACCOUNT_TOKEN: "service-token"]
             )
  end
end
