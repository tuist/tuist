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

    test "returns configured static service clients" do
      stub(Environment, :kura_control_plane_configured?, fn -> false end)
      stub(Environment, :oauth_client_id, fn -> "tuist-cli" end)
      stub(Environment, :oauth_client_secret, fn -> "tuist-cli-secret" end)
      stub(Environment, :oauth_client_name, fn -> "Tuist CLI" end)

      stub(Environment, :oauth_service_clients, fn ->
        [
          %{
            "id" => "service-client",
            "secret" => "service-secret",
            "name" => "Service client",
            "access_token_ttl" => 120
          }
        ]
      end)

      assert %Client{} = client = Clients.get_client("service-client")
      assert client.id == "service-client"
      assert client.secret == "service-secret"
      assert client.name == "Service client"
      assert client.access_token_ttl == 120
      assert client.refresh_token_ttl == 120
      assert client.confidential == true
      assert client.supported_grant_types == ["client_credentials"]
      assert client.token_endpoint_auth_methods == ["client_secret_basic", "client_secret_post"]
      assert Clients.service_client?("service-client")
      refute Clients.service_client?("tuist-cli")
    end

    test "restricts a service client to its configured scopes" do
      stub(Environment, :kura_control_plane_configured?, fn -> false end)
      stub(Environment, :oauth_client_id, fn -> "tuist-cli" end)
      stub(Environment, :oauth_client_secret, fn -> "tuist-cli-secret" end)
      stub(Environment, :oauth_client_name, fn -> "Tuist CLI" end)

      stub(Environment, :oauth_service_clients, fn ->
        [
          %{
            "id" => "service-client",
            "secret" => "service-secret",
            "scopes" => ["account:service:read:any"]
          }
        ]
      end)

      client = Clients.get_client("service-client")

      assert client.authorize_scope == true
      assert Enum.map(client.authorized_scopes, & &1.name) == ["account:service:read:any"]
      assert Enum.map(Clients.authorized_scopes(client), & &1.name) == ["account:service:read:any"]
    end

    test "grants a service client no scopes when none are configured" do
      stub(Environment, :kura_control_plane_configured?, fn -> false end)
      stub(Environment, :oauth_client_id, fn -> "tuist-cli" end)
      stub(Environment, :oauth_client_secret, fn -> "tuist-cli-secret" end)
      stub(Environment, :oauth_client_name, fn -> "Tuist CLI" end)

      stub(Environment, :oauth_service_clients, fn ->
        [%{"id" => "service-client", "secret" => "service-secret"}]
      end)

      client = Clients.get_client("service-client")

      assert client.authorize_scope == true
      assert client.authorized_scopes == []
      assert Clients.authorized_scopes(client) == []
    end

    test "ignores a service client whose id collides with the Tuist CLI client" do
      stub(Environment, :kura_control_plane_configured?, fn -> false end)
      stub(Environment, :oauth_client_id, fn -> "tuist-cli" end)
      stub(Environment, :oauth_client_secret, fn -> "tuist-cli-secret" end)
      stub(Environment, :oauth_client_name, fn -> "Tuist CLI" end)
      stub(Environment, :oauth_jwt_public_key, fn -> nil end)
      stub(Environment, :oauth_private_key, fn -> nil end)

      stub(Environment, :oauth_service_clients, fn ->
        [
          %{
            "id" => "tuist-cli",
            "secret" => "service-secret",
            "scopes" => ["account:service:read:any"]
          }
        ]
      end)

      client = Clients.get_client("tuist-cli")

      assert client.secret == "tuist-cli-secret"
      assert client.confidential == false
      refute Clients.service_client?("tuist-cli")
    end

    test "caps a service client access token TTL" do
      stub(Environment, :kura_control_plane_configured?, fn -> false end)
      stub(Environment, :oauth_client_id, fn -> "tuist-cli" end)
      stub(Environment, :oauth_client_secret, fn -> "tuist-cli-secret" end)
      stub(Environment, :oauth_client_name, fn -> "Tuist CLI" end)

      stub(Environment, :oauth_service_clients, fn ->
        [
          %{
            "id" => "service-client",
            "secret" => "service-secret",
            "access_token_ttl" => 99_999
          }
        ]
      end)

      client = Clients.get_client("service-client")

      assert client.access_token_ttl == 3600
      assert client.refresh_token_ttl == 3600
    end
  end
end
