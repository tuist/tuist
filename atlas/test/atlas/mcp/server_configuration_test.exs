defmodule Atlas.MCP.ServerConfigurationTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.MCP
  alias Atlas.MCP.OAuthSession
  alias Atlas.MCP.Proxy
  alias Atlas.MCP.ServerConfiguration
  alias Atlas.Users.User

  setup :verify_on_exit!

  test "an administrator-managed server is available immediately and removal revokes its sessions" do
    assert {:ok, server} = MCP.create_server_configuration(Map.put(oauth_attrs(), :read_only, false))
    assert {:ok, proxy_server} = Proxy.fetch_server(server.name)
    assert proxy_server.scopes == ["tools:read", "profile"]
    assert proxy_server.read_only
    assert proxy_server.auth_type == :oauth2

    session = insert_session!(server)

    assert {:ok, _deleted} = MCP.delete_server_configuration(server.id)
    assert {:error, _} = Proxy.fetch_server(server.name)
    refute Repo.get(OAuthSession, session.id)
  end

  test "rejects private and non-encrypted endpoints" do
    for url <- ["http://tools.example.org/mcp", "https://127.0.0.1/mcp", "https://localhost/mcp"] do
      for attrs <- [oauth_attrs(), bearer_attrs()] do
        changeset = ServerConfiguration.changeset(%ServerConfiguration{}, Map.put(attrs, :url, url))
        refute changeset.valid?
        assert "must be a public HTTPS URL" in errors_on(changeset).url
      end
    end
  end

  test "updating a server applies its settings and revokes saved sessions" do
    {:ok, server} = MCP.create_server_configuration(oauth_attrs())
    session = insert_session!(server)
    attrs = oauth_attrs() |> Map.put(:url, "https://new.example.org/mcp") |> Map.put(:scope_list, "tools:search")

    assert {:ok, updated} = MCP.update_server_configuration(server.id, attrs)
    assert updated.name == attrs.name
    assert {:error, _} = Proxy.fetch_server(server.name)
    assert {:ok, proxy_server} = Proxy.fetch_server(updated.name)
    assert proxy_server.url == attrs.url
    assert proxy_server.scopes == ["tools:search"]
    refute Repo.get(OAuthSession, session.id)
  end

  test "saving unchanged settings keeps saved sessions" do
    {:ok, server} = MCP.create_server_configuration(oauth_attrs())
    session = insert_session!(server)

    assert {:ok, _} = MCP.update_server_configuration(server.id, %{name: server.name, scope_list: "tools:read profile"})
    assert Repo.get(OAuthSession, session.id)
  end

  test "shared bearer keys are encrypted, redacted, and available immediately" do
    assert {:ok, server} = MCP.create_server_configuration(bearer_attrs())
    assert MCP.get_server_configuration(server.id).bearer_token == "integral-test-key"
    refute inspect(server) =~ "integral-test-key"

    %{rows: [[ciphertext]]} =
      Repo.query!("SELECT bearer_token FROM mcp_server_configurations WHERE name = $1", [server.name])

    refute ciphertext == "integral-test-key"
    refute ciphertext =~ "integral-test-key"

    assert {:ok, proxy_server} = Proxy.fetch_server(server.name)
    assert proxy_server.auth_type == :bearer_token
    assert proxy_server.bearer_token == "integral-test-key"
    refute inspect(proxy_server) =~ "integral-test-key"
    assert proxy_server.read_only
    assert proxy_server.authorization_url == nil
    refute inspect(Proxy.list_servers()) =~ "integral-test-key"
  end

  test "bearer keys are sent for discovery and calls, while write tools remain blocked" do
    {:ok, server} = MCP.create_server_configuration(bearer_attrs())

    stub(Req, :post, fn request ->
      assert request.options.auth == {:bearer, "integral-test-key"}

      result =
        case request.options.json["method"] do
          "initialize" ->
            %{"protocolVersion" => "2025-03-26", "capabilities" => %{}}

          "notifications/initialized" ->
            %{}

          "tools/list" ->
            %{
              "tools" => [
                %{"name" => "list_invoices", "annotations" => %{"readOnlyHint" => true}},
                %{"name" => "create_invoice", "annotations" => %{"readOnlyHint" => false}}
              ]
            }

          "tools/call" ->
            assert request.options.json["params"]["name"] == "list_invoices"
            %{"content" => [%{"type" => "text", "text" => "ok"}]}
        end

      {:ok,
       %Req.Response{status: 200, body: %{"jsonrpc" => "2.0", "id" => request.options.json["id"], "result" => result}}}
    end)

    assert {:ok, [%{"name" => "list_invoices"}]} = Proxy.list_tools(server.name)
    assert {:ok, %{"content" => [%{"text" => "ok"}]}} = Proxy.call_tool(server.name, "list_invoices", %{})
    assert {:error, _} = Proxy.call_tool(server.name, "create_invoice", %{})
  end

  test "accepts the standard bearer-token alphabet, including padding" do
    changeset =
      ServerConfiguration.changeset(%ServerConfiguration{}, Map.put(bearer_attrs(), :bearer_token, "abAZ09-._~+/=="))

    assert changeset.valid?
  end

  test "editing a blank key preserves it and a replacement rotates it" do
    {:ok, server} = MCP.create_server_configuration(bearer_attrs())
    assert {:ok, saved} = MCP.update_server_configuration(server.id, %{bearer_token: ""})
    assert saved.bearer_token == "integral-test-key"

    assert {:ok, _} = MCP.update_server_configuration(server.id, %{bearer_token: "replacement-key"})
    assert {:ok, proxy_server} = Proxy.fetch_server(server.name)
    assert proxy_server.bearer_token == "replacement-key"
  end

  test "switching authentication clears unused credentials and OAuth sessions" do
    {:ok, server} = MCP.create_server_configuration(oauth_attrs())
    session = insert_session!(server)

    assert {:ok, bearer} = MCP.update_server_configuration(server.id, %{auth_type: "bearer_token", bearer_token: "key"})
    assert bearer.authorization_url == nil
    assert bearer.token_url == nil
    assert bearer.scopes == []
    refute Repo.get(OAuthSession, session.id)

    assert {:ok, oauth} = MCP.update_server_configuration(server.id, Map.put(oauth_attrs(), :name, server.name))
    assert oauth.bearer_token == nil
    assert oauth.auth_type == "oauth2"
    assert MCP.get_server_configuration(server.id).bearer_token == nil
  end

  test "requires the credential matching the authentication type and rejects unsupported types" do
    assert {:error, changeset} = MCP.create_server_configuration(Map.delete(bearer_attrs(), :bearer_token))
    assert "can't be blank" in errors_on(changeset).bearer_token

    assert {:error, changeset} =
             MCP.create_server_configuration(%{name: unique_name(), url: "https://tools.example.org/mcp"})

    assert "can't be blank" in errors_on(changeset).authorization_url
    assert "can't be blank" in errors_on(changeset).token_url

    assert {:error, changeset} = MCP.create_server_configuration(Map.put(bearer_attrs(), :auth_type, "none"))
    assert "is invalid" in errors_on(changeset).auth_type

    for token <- ["Bearer key", "key\r\nheader:value", "key with spaces", "key\n"] do
      assert {:error, changeset} = MCP.create_server_configuration(Map.put(bearer_attrs(), :bearer_token, token))
      assert errors_on(changeset).bearer_token
    end
  end

  defp unique_name, do: "example-#{System.unique_integer([:positive])}"

  defp oauth_attrs do
    %{
      name: unique_name(),
      url: "https://tools.example.org/mcp",
      auth_type: "oauth2",
      authorization_url: "https://tools.example.org/oauth/authorize",
      token_url: "https://tools.example.org/oauth/token",
      scope_list: "tools:read profile"
    }
  end

  defp bearer_attrs do
    %{
      name: unique_name(),
      url: "https://tools.example.org/mcp",
      auth_type: "bearer_token",
      bearer_token: "integral-test-key"
    }
  end

  defp insert_session!(server) do
    user =
      %User{}
      |> User.changeset(%{email: "mcp-managed-#{System.unique_integer([:positive])}@example.org", name: "MCP"})
      |> Repo.insert!()

    %OAuthSession{user_id: user.id, server_name: server.name}
    |> OAuthSession.changeset(%{access_token: "token"})
    |> Repo.insert!()
  end
end
