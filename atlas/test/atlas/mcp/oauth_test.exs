defmodule Atlas.MCP.OAuthTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.Audit
  alias Atlas.Audit.Activity
  alias Atlas.MCP
  alias Atlas.MCP.OAuth
  alias Atlas.MCP.OAuthSession
  alias Atlas.MCP.Proxy.Config
  alias Atlas.MCP.Proxy.Server
  alias Atlas.Repo
  alias Atlas.Users.User

  setup :verify_on_exit!

  setup do
    user =
      %User{}
      |> User.changeset(%{email: "mcp-oauth-#{System.unique_integer()}@example.com", name: "MCP OAuth"})
      |> Repo.insert!()

    server = %Server{
      name: "grafana",
      url: "https://mcp.grafana.example/mcp",
      auth_type: :oauth2,
      token_url: "https://grafana.example/oauth/token",
      client_id: "atlas",
      client_secret: "secret"
    }

    {:ok, user: user, server: server}
  end

  test "records an authorization without storing bearer credentials in the audit trail", %{user: user, server: server} do
    assert {:ok, session} =
             MCP.upsert_oauth_session(user, server, %{
               access_token: "access-token",
               refresh_token: "refresh-token",
               expires_at: ~U[2026-08-24 12:00:00Z],
               scopes: ["dashboards:read"]
             })

    activity = Repo.get_by!(Activity, action: "mcp_oauth_session.authorized", target_id: session.id)
    assert activity.actor_id == user.id
    assert activity.metadata["server_name"] == "grafana"
    refute Map.has_key?(activity.metadata, "access_token")
    refute Map.has_key?(activity.metadata, "refresh_token")
  end

  test "returns a valid access token without refreshing", %{user: user, server: server} do
    insert_session!(user, server, %{
      access_token: "valid-token",
      refresh_token: "refresh-token",
      expires_at: DateTime.utc_now() |> DateTime.add(600, :second) |> DateTime.truncate(:second)
    })

    assert {:ok, "valid-token"} = MCP.access_token_for(user, server)
  end

  test "refreshes an expired session and stores the new token", %{user: user, server: server} do
    insert_session!(user, server, %{
      access_token: "expired-token",
      refresh_token: "refresh-token",
      expires_at: DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)
    })

    expect(Req, :post, fn %Req.Request{} = request ->
      assert URI.to_string(request.url) == "https://grafana.example/oauth/token"
      assert request.options.form["grant_type"] == "refresh_token"
      assert request.options.form["refresh_token"] == "refresh-token"
      assert request.options.form["client_id"] == "atlas"
      assert request.options.form["client_secret"] == "secret"

      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "access_token" => "fresh-token",
           "refresh_token" => "fresh-refresh-token",
           "expires_in" => 3600,
           "scope" => "dashboards:read"
         }
       }}
    end)

    assert {:ok, "fresh-token"} = MCP.access_token_for(user, server)

    session = MCP.get_oauth_session(user, "grafana")
    assert session.access_token == "fresh-token"
    assert session.refresh_token == "fresh-refresh-token"
    assert session.scopes == ["dashboards:read"]

    activity = Repo.get_by!(Activity, action: "mcp_oauth_session.refreshed", target_id: session.id)
    refute Map.has_key?(activity.metadata, "access_token")
    refute Map.has_key?(activity.metadata, "refresh_token")
  end

  test "marks refresh failures as needing authorization", %{user: user, server: server} do
    insert_session!(user, server, %{
      access_token: "expired-token",
      refresh_token: "refresh-token",
      expires_at: DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)
    })

    expect(Req, :post, fn %Req.Request{} ->
      {:ok, %Req.Response{status: 401, body: %{"error" => "invalid_grant"}}}
    end)

    assert {:error, {:refresh_failed, {:http, 401, %{"error" => "invalid_grant"}}}} =
             Audit.with_context(%{actor: user, interface: "mcp"}, fn ->
               MCP.access_token_for(user, server)
             end)

    session = MCP.get_oauth_session(user, "grafana")
    assert session.status == "needs_authorization"
    assert session.access_token == nil
    assert session.last_error =~ "invalid_grant"

    activity = Repo.get_by!(Activity, action: "mcp_oauth_session.authorization_required", target_id: session.id)
    assert activity.interface == "mcp"
    assert activity.actor_id == user.id
  end

  test "uses a shared OAuth session for other users when configured", %{user: owner, server: server} do
    other_user = insert_user!("mcp-shared-other@example.com")
    server = %{server | shared_oauth: true}

    insert_session!(owner, server, %{
      access_token: "shared-token",
      refresh_token: "refresh-token",
      expires_at: DateTime.utc_now() |> DateTime.add(600, :second) |> DateTime.truncate(:second)
    })

    assert {:ok, "shared-token"} = MCP.access_token_for(other_user, server)
  end

  test "does not expose shared OAuth sessions without an authenticated user", %{user: owner, server: server} do
    server = %{server | shared_oauth: true}

    insert_session!(owner, server, %{
      access_token: "shared-token",
      refresh_token: "refresh-token",
      expires_at: DateTime.utc_now() |> DateTime.add(600, :second) |> DateTime.truncate(:second)
    })

    assert {:error, :unsupported_auth_type} = MCP.access_token_for(nil, server)
  end

  test "uses the configured shared OAuth user when present", %{user: owner, server: server} do
    other_user = insert_user!("mcp-configured-shared-other@example.com")
    server = %{server | shared_oauth: true, shared_oauth_user_email: owner.email}

    insert_session!(owner, server, %{
      access_token: "owner-token",
      refresh_token: "refresh-token",
      expires_at: DateTime.utc_now() |> DateTime.add(600, :second) |> DateTime.truncate(:second)
    })

    insert_session!(other_user, server, %{
      access_token: "other-token",
      refresh_token: "refresh-token",
      expires_at: DateTime.utc_now() |> DateTime.add(600, :second) |> DateTime.truncate(:second)
    })

    assert {:ok, "owner-token"} = MCP.access_token_for(other_user, server)
  end

  test "does not fall back to another shared session when the configured shared OAuth user is missing", %{
    user: owner,
    server: server
  } do
    other_user = insert_user!("mcp-missing-shared-other@example.com")
    server = %{server | shared_oauth: true, shared_oauth_user_email: "missing@example.com"}

    insert_session!(owner, server, %{
      access_token: "owner-token",
      refresh_token: "refresh-token",
      expires_at: DateTime.utc_now() |> DateTime.add(600, :second) |> DateTime.truncate(:second)
    })

    assert {:error, :authorization_required} = MCP.access_token_for(other_user, server)
  end

  test "refreshes expiring OAuth sessions through a row lock", %{user: user, server: server} do
    insert_session!(user, server, %{
      access_token: "expiring-token",
      refresh_token: "refresh-token",
      expires_at: DateTime.utc_now() |> DateTime.add(300, :second) |> DateTime.truncate(:second)
    })

    stub(Config, :get, fn ->
      [servers: [server]]
    end)

    expect(Req, :post, fn %Req.Request{} = request ->
      assert URI.to_string(request.url) == "https://grafana.example/oauth/token"
      assert request.options.form["grant_type"] == "refresh_token"

      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "access_token" => "proactive-token",
           "refresh_token" => "proactive-refresh-token",
           "expires_in" => 3600
         }
       }}
    end)

    assert {:ok, %{refreshed: 1, skipped: 0, failed: 0}} = MCP.refresh_expiring_oauth_sessions()

    session = MCP.get_oauth_session(user, "grafana")
    assert session.access_token == "proactive-token"
    assert session.refresh_token == "proactive-refresh-token"

    activity = Repo.get_by!(Activity, action: "mcp_oauth_session.refreshed", target_id: session.id)
    assert activity.interface == "worker"
  end

  test "does not refresh sessions outside the proactive window", %{user: user, server: server} do
    insert_session!(user, server, %{
      access_token: "valid-token",
      refresh_token: "refresh-token",
      expires_at: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)
    })

    stub(Config, :get, fn ->
      [servers: [server]]
    end)

    reject(&Req.post/1)

    assert {:ok, %{refreshed: 0, skipped: 0, failed: 0}} = MCP.refresh_expiring_oauth_sessions()
    assert MCP.get_oauth_session(user, "grafana").access_token == "valid-token"
  end

  test "registers a dynamic client when no static client is configured", %{user: user} do
    server = %Server{
      name: "grafana",
      url: "https://mcp.grafana.example/mcp",
      auth_type: :oauth2,
      authorization_url: "https://grafana.example/oauth/authorize",
      token_url: "https://grafana.example/oauth/token",
      registration_url: "https://grafana.example/oauth/register",
      scopes: ["grafana:read", "grafana:write"]
    }

    expect(Req, :post, fn %Req.Request{} = request ->
      assert URI.to_string(request.url) == "https://grafana.example/oauth/register"
      assert request.options.json["client_name"] == "Atlas grafana"
      assert request.options.json["redirect_uris"] == ["http://localhost:3030/mcps/grafana/callback"]
      assert request.options.json["grant_types"] == ["authorization_code", "refresh_token"]
      assert request.options.json["token_endpoint_auth_method"] == "none"

      {:ok, %Req.Response{status: 201, body: %{"client_id" => "dynamic-client"}}}
    end)

    assert {:ok, url} =
             OAuth.authorization_url(
               server,
               user,
               "http://localhost:3030/mcps/grafana/callback",
               "/admin/mcps"
             )

    params = url |> URI.parse() |> then(&URI.decode_query(&1.query))

    assert String.starts_with?(url, "https://grafana.example/oauth/authorize?")
    assert params["client_id"] == "dynamic-client"
    assert params["redirect_uri"] == "http://localhost:3030/mcps/grafana/callback"
    assert params["scope"] == "grafana:read grafana:write"
  end

  defp insert_session!(user, server, attrs) do
    defaults = %{
      status: "authorized",
      token_type: "Bearer",
      scopes: []
    }

    %OAuthSession{user_id: user.id, server_name: server.name}
    |> OAuthSession.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_user!(email) do
    %User{}
    |> User.changeset(%{email: email, name: "MCP OAuth"})
    |> Repo.insert!()
  end
end
