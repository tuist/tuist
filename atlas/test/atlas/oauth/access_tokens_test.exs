defmodule Atlas.OAuth.AccessTokensTest do
  use Atlas.DataCase, async: true

  alias Atlas.OAuth.AccessTokens
  alias Atlas.OAuth.Clients
  alias Boruta.Ecto.Client
  alias Boruta.Ecto.Clients, as: EctoClients
  alias Boruta.Ecto.Token
  alias Boruta.Oauth.Client, as: OAuthClient
  alias Boruta.Oauth.Error, as: OAuthError
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    {:ok, client} =
      Clients.create_client(%{
        "name" => "Grant concurrency test",
        "redirect_uris" => ["https://example.com/callback"],
        "grant_types" => ["authorization_code", "refresh_token"]
      })

    {:ok, client: client}
  end

  test "a stale authorization-code read cannot mint a second access token", %{client: client} do
    code = insert_code(client)
    params = %{client: client, scope: "mcp", sub: code.sub, previous_code: code.value}

    assert {:ok, _token} = AccessTokens.create(params, refresh_token: true)

    assert {:error, %OAuthError{status: :bad_request, error: :invalid_grant}} =
             AccessTokens.create(params, refresh_token: true)

    assert Repo.aggregate(from(t in Token, where: t.previous_code == ^code.value), :count) == 1
  end

  test "failed replacement creation does not consume the authorization code", %{client: client} do
    code = insert_code(client)
    params = %{client: client, scope: %{"invalid" => "scope"}, sub: code.sub, previous_code: code.value}

    assert {:error, _reason} = AccessTokens.create(params, refresh_token: true)
    assert is_nil(Repo.get!(Token, code.id).revoked_at)
  end

  test "a stale refresh-token read cannot rotate twice", %{client: client} do
    assert {:ok, previous} =
             AccessTokens.create(%{client: client, scope: "mcp", sub: Ecto.UUID.generate()}, refresh_token: true)

    params = %{client: client, scope: "mcp", sub: previous.sub, previous_token: previous.value}

    assert {:ok, _token} = AccessTokens.create(params, refresh_token: true)

    assert {:error, %OAuthError{status: :bad_request, error: :invalid_grant}} =
             AccessTokens.create(params, refresh_token: true)

    assert AccessTokens.get_by(refresh_token: previous.refresh_token).refresh_token_revoked_at
  end

  test "expired grants cannot be consumed after stale preauthorization", %{client: client} do
    code = insert_code(client)
    Repo.update_all(from(t in Token, where: t.id == ^code.id), set: [expires_at: 0])

    assert {:error, %OAuthError{status: :bad_request, error: :invalid_grant}} =
             AccessTokens.create(%{client: client, scope: "mcp", sub: code.sub, previous_code: code.value},
               refresh_token: true
             )

    assert {:ok, previous} =
             AccessTokens.create(%{client: client, scope: "mcp", sub: Ecto.UUID.generate()}, refresh_token: true)

    Repo.update_all(from(t in Token, where: t.value == ^previous.value),
      set: [inserted_at: ~U[2000-01-01 00:00:00.000000Z]]
    )

    assert {:error, %OAuthError{status: :bad_request, error: :invalid_grant}} =
             AccessTokens.create(%{client: client, scope: "mcp", sub: previous.sub, previous_token: previous.value},
               refresh_token: true
             )
  end

  test "consumption preserves UTC timestamps and refresh validity on a non-UTC database", %{client: client} do
    Repo.query!("SET LOCAL TIME ZONE 'Pacific/Kiritimati'")
    code = insert_code(client)

    assert {:ok, previous} =
             AccessTokens.create(%{client: client, scope: "mcp", sub: code.sub, previous_code: code.value},
               refresh_token: true
             )

    # One hour of validity remains. A UTC+14 session must not interpret the
    # naive UTC insertion timestamp as local time and expire it early.
    inserted_at = DateTime.add(DateTime.utc_now(), -client.refresh_token_ttl + 3_600, :second)
    Repo.update_all(from(t in Token, where: t.value == ^previous.value), set: [inserted_at: inserted_at])

    assert {:ok, _replacement} =
             AccessTokens.create(%{client: client, scope: "mcp", sub: code.sub, previous_token: previous.value},
               refresh_token: true
             )

    assert %{rows: [[utc_now]]} = Repo.query!("SELECT statement_timestamp() AT TIME ZONE 'UTC'")
    revoked_at = Repo.get!(Token, code.id).revoked_at |> DateTime.to_naive()
    refresh_revoked_at = Repo.get_by!(Token, value: previous.value).refresh_token_revoked_at |> DateTime.to_naive()
    assert NaiveDateTime.diff(utc_now, revoked_at) in 0..5
    assert NaiveDateTime.diff(utc_now, refresh_revoked_at) in 0..5
  end

  test "code and refresh grants serialize across independent database connections" do
    {client, code} =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          {:ok, client} = EctoClients.create_client(%{"name" => "Concurrent grant test"})
          {client, insert_code(client)}
        end)
      end)
      |> Task.await()

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        Repo.delete_all(from(t in Token, where: t.client_id == ^client.id))
        Repo.delete_all(from(c in Client, where: c.id == ^client.id))
      end)
    end)

    params = %{client: client, scope: "mcp", sub: code.sub, previous_code: code.value}
    results = concurrent_creates(params)
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1, inspect(results)
    [{:ok, previous}] = Enum.filter(results, &match?({:ok, _}, &1))
    assert Enum.count(results, &match?({:error, _}, &1)) == 9

    results = concurrent_creates(%{client: client, scope: "mcp", sub: code.sub, previous_token: previous.value})
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, _}, &1)) == 9
  end

  test "client updates are visible after a prior lookup", %{client: %OAuthClient{id: id}} do
    assert Clients.get_client(id).name == "Grant concurrency test"
    Repo.update_all(from(c in Client, where: c.id == ^id), set: [name: "Updated on another replica"])
    assert Clients.get_client(id).name == "Updated on another replica"
  end

  defp concurrent_creates(params) do
    1..10
    |> Task.async_stream(
      fn _ ->
        Sandbox.unboxed_run(Repo, fn -> AccessTokens.create(params, refresh_token: true) end)
      end,
      max_concurrency: 2,
      timeout: :infinity
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end

  defp insert_code(client) do
    Repo.insert!(%Token{
      type: "code",
      client_id: client.id,
      value: "code-#{System.unique_integer([:positive])}",
      redirect_uri: "https://example.com/callback",
      scope: "mcp",
      sub: Ecto.UUID.generate(),
      expires_at: System.os_time(:second) + 60
    })
  end
end
