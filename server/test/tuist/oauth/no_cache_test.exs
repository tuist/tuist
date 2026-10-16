defmodule Tuist.OAuth.NoCacheTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Boruta.Ecto.AccessTokens
  alias Boruta.Ecto.Client
  alias Boruta.Ecto.Codes
  alias Boruta.Ecto.Scope
  alias Boruta.Ecto.Scopes
  alias Boruta.Ecto.Token
  alias Boruta.Oauth.Token, as: OAuthToken
  alias Tuist.OAuth.Clients
  alias Tuist.OAuth.NoCache
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :set_mimic_from_context

  test "Boruta uses an inert entity cache and upstream Ecto adapters" do
    assert Boruta.Config.cache_backend() == NoCache
    assert Boruta.Config.access_tokens() == AccessTokens
    assert Boruta.Config.codes() == Codes
    assert Boruta.Config.scopes() == Scopes
    assert :ok = NoCache.put(:grant, %{revoked_at: nil}, ttl: 60_000)
    assert :ok = NoCache.put(:client, %{name: "not retained"})
    assert NoCache.get(:grant) == nil
    assert NoCache.get(:client) == nil
    assert :ok = NoCache.delete(:grant)
    assert NoCache.get(:grant) == nil
  end

  test "client security metadata changes are visible after an earlier lookup" do
    client = create_client()
    assert Clients.get_client(client.id).name == "before"

    Client
    |> Repo.get!(client.id)
    |> Ecto.Changeset.change(name: "after", redirect_uris: ["https://example.com/changed"], confidential: true)
    |> Repo.update!()

    fresh = Clients.get_client(client.id)
    assert fresh.name == "after"
    assert fresh.redirect_uris == ["https://example.com/changed"]
    assert fresh.confidential
  end

  test "client deletion is visible after an earlier lookup" do
    client = create_client()
    assert Clients.get_client(client.id).id == client.id
    Client |> Repo.get!(client.id) |> Repo.delete!()
    assert Clients.get_client(client.id) == nil
  end

  test "a database failure is not masked by an earlier client lookup" do
    client = create_client()
    assert Clients.get_client(client.id).id == client.id

    expect(Repo, :get_by, fn Client, [id: id] ->
      assert id == client.id
      raise DBConnection.ConnectionError, "owned database failure"
    end)

    assert_raise DBConnection.ConnectionError, "owned database failure", fn ->
      Clients.get_client(client.id)
    end
  end

  test "access and refresh token revocations are fresh after earlier lookups" do
    token = create_access_token()
    refute OAuthToken.revoked?(AccessTokens.get_by(value: token.value), :access_token)
    refute OAuthToken.revoked?(AccessTokens.get_by(refresh_token: token.refresh_token), :refresh_token)

    update_token(token, refresh_token_revoked_at: DateTime.utc_now())
    fresh = AccessTokens.get_by(refresh_token: token.refresh_token)
    assert {:error, "Token revoked."} = OAuthToken.ensure_valid(fresh, :refresh_token)
    refute OAuthToken.revoked?(AccessTokens.get_by(value: token.value), :access_token)

    update_token(token, revoked_at: DateTime.utc_now())
    assert {:error, "Token revoked."} = OAuthToken.ensure_valid(AccessTokens.get_by(value: token.value))
  end

  test "token expiry changes are fresh after an earlier lookup" do
    token = create_access_token()
    assert :ok = OAuthToken.ensure_valid(AccessTokens.get_by(value: token.value))
    update_token(token, expires_at: System.system_time(:second) - 1)
    assert {:error, "Token expired."} = OAuthToken.ensure_valid(AccessTokens.get_by(value: token.value))
  end

  test "token deletion is visible through value and refresh-token lookups" do
    token = create_access_token()
    assert AccessTokens.get_by(value: token.value).id == token.id
    assert AccessTokens.get_by(refresh_token: token.refresh_token).id == token.id
    Token |> Repo.get!(token.id) |> Repo.delete!()
    assert AccessTokens.get_by(value: token.value) == nil
    assert AccessTokens.get_by(refresh_token: token.refresh_token) == nil
  end

  test "code lookups by value, id and redirect URI observe database revocation" do
    client = create_client()
    user = AccountsFixtures.user_fixture()

    assert {:ok, code} =
             Codes.create(%{
               client: client,
               sub: to_string(user.id),
               redirect_uri: hd(client.redirect_uris),
               scope: "mcp",
               state: "state",
               code_challenge: nil,
               code_challenge_method: nil,
               authorization_details: []
             })

    # Boruta never caches codes by ID; that variant retains database-path parity coverage.
    lookups = [[value: code.value], [id: code.id], [value: code.value, redirect_uri: code.redirect_uri]]
    for lookup <- lookups, do: refute(OAuthToken.revoked?(Codes.get_by(lookup), :access_token))
    update_token(code, revoked_at: DateTime.utc_now())

    for lookup <- lookups do
      assert {:error, "Token revoked."} = lookup |> Codes.get_by() |> OAuthToken.ensure_valid()
    end
  end

  test "client grant additions and removals remain authoritative" do
    client = create_client()
    scope = create_scope()
    assert Clients.authorized_scopes(client) == []
    update_client_scopes(client, [scope])
    assert Enum.map(Clients.authorized_scopes(client), & &1.name) == [scope.name]
    update_client_scopes(client, [])
    assert Clients.authorized_scopes(client) == []
  end

  test "public scopes observe visibility changes after an earlier lookup" do
    scope = create_scope()
    assert Enum.any?(Scopes.public(), &(&1.id == scope.id))
    scope |> Ecto.Changeset.change(public: false) |> Repo.update!()
    refute Enum.any?(Scopes.public(), &(&1.id == scope.id))
    assert Enum.any?(Scopes.all(), &(&1.id == scope.id))
  end

  test "all scopes observe deletion after an earlier lookup" do
    scope = create_scope()
    assert Enum.any?(Scopes.all(), &(&1.id == scope.id))
    Repo.delete!(scope)
    refute Enum.any?(Scopes.all(), &(&1.id == scope.id))
  end

  defp create_scope do
    Repo.insert!(%Scope{name: "scope:#{Ecto.UUID.generate()}", public: true})
  end

  defp update_client_scopes(client, scopes) do
    Client
    |> Repo.get!(client.id)
    |> Repo.preload(:authorized_scopes)
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:authorized_scopes, scopes)
    |> Repo.update!()
  end

  defp create_client do
    {:ok, client} = Clients.create_client(%{redirect_uris: ["http://localhost:3000/callback"], name: "before"})
    client
  end

  defp create_access_token do
    client = create_client()
    user = AccountsFixtures.user_fixture()
    {:ok, token} = AccessTokens.create(%{client: client, sub: to_string(user.id), scope: "mcp"}, refresh_token: true)
    token
  end

  defp update_token(token, changes) do
    Token |> Repo.get!(token.id) |> Ecto.Changeset.change(changes) |> Repo.update!()
  end
end
