defmodule Atlas.ConnectionsTest do
  use Atlas.DataCase, async: true
  use Mimic

  import Atlas.MCP.ToolCase, only: [insert_user!: 0]

  alias Atlas.Audit
  alias Atlas.Connections
  alias Atlas.Connections.Config
  alias Atlas.Connections.Connection
  alias Atlas.MCP.Tools.ManageAccountConnections

  setup do
    stub(Config, :credentials, fn _ -> %{client_id: "test-client", client_secret: "test-secret"} end)
    %{user: insert_user!()}
  end

  test "GitHub credentials are encrypted, personal, audited, and never exposed through MCP", %{user: user} do
    stub(Req, :request, fn opts ->
      case opts[:url] do
        "https://github.com/login/oauth/access_token" ->
          response(%{
            "access_token" => "github-secret",
            "expires_in" => 28_800,
            "refresh_token" => "github-refresh",
            "scope" => ""
          })

        "https://api.github.com/user" ->
          response(%{"id" => 42, "login" => "octocat"})
      end
    end)

    before_connect = DateTime.truncate(DateTime.utc_now(), :second)
    assert {:ok, connection} = Connections.connect(user, "github", "code", "https://atlas.test/callback", "verifier")
    after_connect = DateTime.truncate(DateTime.utc_now(), :second)
    assert {:ok, "github-secret"} = Connections.access_token(user, "github")
    refute inspect(connection) =~ "github-secret"
    refute inspect(connection) =~ "github-refresh"
    assert connection.refresh_token == "github-refresh"
    assert DateTime.compare(connection.expires_at, DateTime.add(before_connect, 28_800, :second)) != :lt
    assert DateTime.compare(connection.expires_at, DateTime.add(after_connect, 28_800, :second)) != :gt

    [[stored]] =
      Repo.query!("SELECT access_token FROM user_connections WHERE id = $1", [Ecto.UUID.dump!(connection.id)]).rows

    refute stored == "github-secret"
    assert [%{account_name: "octocat", status: "connected", scopes: []} | _] = Connections.list(user)

    other_user = insert_user!()
    assert {:error, :not_connected} = Connections.access_token(other_user, "github")
    assert {:ok, :ok} = Connections.disconnect(other_user, "github")
    assert {:ok, "github-secret"} = Connections.access_token(user, "github")

    result = ManageAccountConnections.call(%{assigns: %{current_user: user}}, %{"action" => "list"})
    refute JSON.encode!(result) =~ "github-secret"
    assert [%{"account_name" => "octocat"} | _] = result["structuredContent"]["connections"]

    assert {:ok, _} =
             ManageAccountConnections.execute(%{assigns: %{current_user: user}}, %{
               "action" => "disconnect",
               "provider" => "github"
             })

    assert {:error, :not_connected} = Connections.access_token(user, "github")
    assert Repo.get(Connection, connection.id) == nil

    {activities, _} = Audit.list_activities(actor_id: user.id)
    assert Enum.any?(activities, &(&1.action == "connection.connected"))
    assert Enum.any?(activities, &(&1.action == "connection.disconnected"))
    assert Enum.all?(activities, &(Audit.serialize(&1).target.path == "/settings/connections"))
    refute inspect(activities) =~ "github-secret"
  end

  test "Slack retains the user grant rather than the bot grant", %{user: user} do
    stub(Req, :request, fn opts ->
      case opts[:url] do
        "https://slack.com/api/oauth.v2.access" ->
          response(%{
            "ok" => true,
            "access_token" => "bot-secret",
            "token_type" => "bot",
            "authed_user" => %{
              "access_token" => "user-secret",
              "token_type" => "user",
              "scope" => "search:read,chat:write"
            }
          })

        "https://slack.com/api/auth.test" ->
          assert opts[:auth] == {:bearer, "user-secret"}
          response(%{"ok" => true, "user_id" => "U42", "user" => "octocat", "team_id" => "T42", "team" => "Test"})
      end
    end)

    assert {:ok, connection} = Connections.connect(user, "slack", "code", "https://atlas.test/callback", "verifier")
    assert connection.provider_user_id == "U42"
    assert connection.workspace_id == "T42"
    assert {:ok, "user-secret"} = Connections.access_token(user, "slack")

    stub(Req, :request, fn _ -> response(%{"ok" => true, "access_token" => "bot-secret", "token_type" => "bot"}) end)

    assert {:error, :missing_user_token} =
             Connections.connect(user, "slack", "code", "https://atlas.test/callback", "verifier")

    assert {:ok, "user-secret"} = Connections.access_token(user, "slack")
  end

  test "Google refresh retains an omitted refresh token but never carries it to a different account", %{user: user} do
    connection = insert_connection!(user, "google", %{expires_at: past(), refresh_token: "original-refresh"})

    stub(Req, :request, fn opts ->
      assert opts[:form]["refresh_token"] == "original-refresh"
      response(%{"access_token" => "new-access", "expires_in" => 3600})
    end)

    assert {:ok, "new-access"} = Connections.access_token(user, "google")
    assert Repo.get!(Connection, connection.id).refresh_token == "original-refresh"

    stub(Req, :request, fn opts ->
      case opts[:method] do
        :post -> response(%{"access_token" => "reconnected-access", "expires_in" => 3600, "scope" => "openid email"})
        :get -> response(%{"sub" => "different-account", "email" => "different@example.com"})
      end
    end)

    assert {:ok, updated} = Connections.connect(user, "google", "code", "https://atlas.test/callback", "verifier")
    assert updated.id == connection.id
    assert updated.refresh_token == nil
    assert updated.account_name == "different@example.com"
    assert updated.scopes == ["openid", "email"]
  end

  test "Slack refresh rotates the refresh token and a subsequent consumer uses the current grant", %{user: user} do
    connection = insert_connection!(user, "slack", %{expires_at: past(), refresh_token: "old-refresh"})

    stub(Req, :request, fn opts ->
      assert opts[:form]["refresh_token"] == "old-refresh"

      response(%{
        "ok" => true,
        "access_token" => "new-user",
        "refresh_token" => "new-refresh",
        "token_type" => "user",
        "expires_in" => 43_200
      })
    end)

    assert {:ok, "new-user"} = Connections.access_token(user, "slack")
    assert {:ok, "new-user"} = Connections.access_token(user, "slack")
    assert Repo.get!(Connection, connection.id).refresh_token == "new-refresh"
  end

  test "GitHub App user tokens rotate and an invalid refresh token requires reconnection", %{user: user} do
    connection = insert_connection!(user, "github", %{expires_at: past(), refresh_token: "old-refresh"})

    stub(Req, :request, fn opts ->
      assert opts[:url] == "https://github.com/login/oauth/access_token"

      assert opts[:form] == %{
               "client_id" => "test-client",
               "client_secret" => "test-secret",
               "grant_type" => "refresh_token",
               "refresh_token" => "old-refresh"
             }

      response(%{
        "access_token" => "new-user",
        "refresh_token" => "new-refresh",
        "token_type" => "bearer",
        "expires_in" => 28_800,
        "scope" => ""
      })
    end)

    assert {:ok, "new-user"} = Connections.access_token(user, "github")
    refreshed = Repo.get!(Connection, connection.id)
    assert refreshed.refresh_token == "new-refresh"
    assert refreshed.scopes == []

    stub(Req, :request, fn _ -> flunk("An unexpired user token must not refresh again") end)
    assert {:ok, "new-user"} = Connections.access_token(user, "github")

    Repo.update!(Ecto.Changeset.change(refreshed, expires_at: past()))

    stub(Req, :request, fn opts ->
      assert opts[:form]["refresh_token"] == "new-refresh"
      response(%{"error" => "bad_refresh_token"})
    end)

    assert {:error, :needs_authorization} = Connections.access_token(user, "github")
    assert Enum.find(Connections.list(user), &(&1.provider == "github")).status == "needs_authorization"
  end

  test "invalid refresh grants require reconnection while temporary failures remain retryable", %{user: user} do
    connection = insert_connection!(user, "google", %{expires_at: past(), refresh_token: "refresh"})
    stub(Req, :request, fn _ -> {:ok, %Req.Response{status: 503, body: "unavailable"}} end)
    assert {:error, :provider_unavailable} = Connections.access_token(user, "google")
    refute Repo.get!(Connection, connection.id).needs_authorization

    stub(Req, :request, fn _ -> {:ok, %Req.Response{status: 400, body: %{"error" => "invalid_grant"}}} end)
    assert {:error, :needs_authorization} = Connections.access_token(user, "google")
    assert Repo.get!(Connection, connection.id).needs_authorization
    assert Enum.find(Connections.list(user), &(&1.provider == "google")).status == "needs_authorization"
  end

  test "an expired grant without refresh credentials is never returned", %{user: user} do
    insert_connection!(user, "github", %{expires_at: past()})
    assert {:error, :needs_authorization} = Connections.access_token(user, "github")
  end

  defp insert_connection!(user, provider, attrs) do
    %Connection{user_id: user.id, provider: provider}
    |> Connection.changeset(
      Map.merge(%{provider_user_id: "original", account_name: "Original", access_token: "old-access"}, attrs)
    )
    |> Repo.insert!()
  end

  defp past, do: DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)
  defp response(body), do: {:ok, %Req.Response{status: 200, body: body}}
end
