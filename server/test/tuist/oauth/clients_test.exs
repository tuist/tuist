defmodule Tuist.OAuth.ClientsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Boruta.Oauth.Client
  alias Tuist.Environment
  alias Tuist.OAuth.Clients

  setup :set_mimic_from_context

  describe "create_client/1" do
    test "creates and fetches a dynamically registered client" do
      assert {:ok, %Client{id: client_id} = created_client} =
               Clients.create_client(%{
                 redirect_uris: ["http://localhost:3000/callback"],
                 name: "mcp-test-client"
               })

      assert %Client{id: ^client_id} = Clients.get_client(client_id)
      assert created_client.redirect_uris == ["http://localhost:3000/callback"]
      assert created_client.name == "mcp-test-client"
    end
  end

  describe "get_client/1" do
    test "returns the dedicated Kura control-plane client" do
      stub(Environment, :kura_control_plane_configured?, fn -> true end)
      stub(Environment, :kura_control_plane_client_id, fn -> "kura-control-plane" end)
      stub(Environment, :kura_control_plane_client_secret, fn -> "kura-secret" end)

      assert %Client{} = client = Clients.get_client("kura-control-plane")
      assert client.id == "kura-control-plane"
      assert client.secret == "kura-secret"
      assert client.confidential == true
      assert client.supported_grant_types == ["introspect", "kura_usage"]
      assert client.token_endpoint_auth_methods == ["client_secret_basic", "client_secret_post"]
    end

    test "keeps the Tuist CLI OAuth client separate from introspection" do
      stub(Environment, :kura_control_plane_configured?, fn -> false end)
      stub(Environment, :oauth_client_id, fn -> "tuist-cli" end)
      stub(Environment, :oauth_client_secret, fn -> "tuist-cli-secret" end)
      stub(Environment, :oauth_client_name, fn -> "Tuist CLI" end)
      stub(Environment, :oauth_jwt_public_key, fn -> nil end)
      stub(Environment, :oauth_private_key, fn -> nil end)

      assert %Client{} = client = Clients.get_client("tuist-cli")
      assert client.id == "tuist-cli"
      refute "introspect" in client.supported_grant_types
    end
  end
end
