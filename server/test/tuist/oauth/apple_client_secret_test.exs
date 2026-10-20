defmodule Tuist.OAuth.AppleClientSecretTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.OAuth.Apple

  test "removes indentation from the configured private key" do
    private_key =
      {:ec, :secp256r1}
      |> JOSE.JWK.generate_key()
      |> JOSE.JWK.to_pem()
      |> unwrap_pem()

    indented_private_key =
      private_key
      |> String.split("\n")
      |> Enum.map_join("\n", &("    " <> &1))

    stub(KeyValueStore, :get_or_update, fn _key, _opts, func -> func.() end)
    stub(Environment, :apple_private_key_id, fn -> "test_key_id" end)
    stub(Environment, :apple_team_id, fn -> "test_team_id" end)
    stub(Environment, :apple_private_key, fn -> indented_private_key end)

    client_secret = Apple.client_secret(client_id: "test.app.client.id")

    assert [_header, _payload, _signature] = String.split(client_secret, ".")
  end

  defp unwrap_pem(pem) when is_binary(pem), do: pem
  defp unwrap_pem({_modules, pem}) when is_binary(pem), do: pem
end
