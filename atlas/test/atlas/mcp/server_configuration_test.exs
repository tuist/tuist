defmodule Atlas.MCP.ServerConfigurationTest do
  use Atlas.DataCase, async: true

  alias Atlas.MCP
  alias Atlas.MCP.OAuthSession
  alias Atlas.MCP.Proxy
  alias Atlas.MCP.ServerConfiguration
  alias Atlas.Users.User

  test "an administrator-managed server is available immediately and removal revokes its sessions" do
    assert {:ok, server} =
             MCP.create_server_configuration(%{
               name: "example",
               url: "https://tools.example.org/mcp",
               authorization_url: "https://tools.example.org/oauth/authorize",
               token_url: "https://tools.example.org/oauth/token",
               scope_list: "tools:read profile",
               auth_type: "none",
               read_only: false
             })

    assert {:ok, proxy_server} = Proxy.fetch_server("example")
    assert proxy_server.scopes == ["tools:read", "profile"]
    assert proxy_server.read_only
    assert proxy_server.auth_type == :oauth2

    user =
      %User{}
      |> User.changeset(%{email: "mcp-managed-#{System.unique_integer()}@example.org", name: "MCP"})
      |> Repo.insert!()

    %OAuthSession{user_id: user.id, server_name: server.name}
    |> OAuthSession.changeset(%{access_token: "token"})
    |> Repo.insert!()

    assert {:ok, _deleted} = MCP.delete_server_configuration(server.id)
    assert {:error, _} = Proxy.fetch_server("example")
    assert Repo.get_by(OAuthSession, server_name: server.name) == nil
  end

  test "rejects private and non-encrypted endpoints" do
    for url <- ["http://tools.example.org/mcp", "https://127.0.0.1/mcp", "https://localhost/mcp"] do
      changeset =
        ServerConfiguration.changeset(%ServerConfiguration{}, %{
          name: "example",
          url: url,
          authorization_url: "https://tools.example.org/oauth/authorize",
          token_url: "https://tools.example.org/oauth/token"
        })

      refute changeset.valid?
      assert "must be a public HTTPS URL" in errors_on(changeset).url
    end
  end
end
