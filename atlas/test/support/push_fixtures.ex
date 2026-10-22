defmodule Atlas.PushFixtures do
  @moduledoc false

  import Ecto.Query

  alias Atlas.OAuth.AccessTokens
  alias Atlas.OAuth.Clients
  alias Atlas.Users.User
  alias Boruta.Ecto.Token

  @native_redirect_uri "dev.tuist.atlas://oauth-callback"

  def ios_token(seed \\ System.unique_integer([:positive])),
    do: :sha256 |> :crypto.hash("ios-#{seed}") |> Base.encode16(case: :lower)

  def android_token(seed \\ System.unique_integer([:positive])), do: "fcm-token:#{seed}-abcdefghijklmnop"

  def ios_device(attrs \\ %{}),
    do: Map.merge(%{"platform" => "ios", "token" => ios_token(), "environment" => "production"}, attrs)

  def android_device(attrs \\ %{}),
    do: Map.merge(%{"platform" => "android", "token" => android_token(), "environment" => "production"}, attrs)

  @doc "A bearer token issued to a dynamically registered native app client."
  def native_access_token(%User{} = user, redirect_uris \\ [@native_redirect_uri]) do
    {:ok, client} = Clients.create_client(%{"name" => "Atlas native", "redirect_uris" => redirect_uris})
    {:ok, token} = AccessTokens.create(%{client: client, scope: "mcp", sub: user.id}, refresh_token: true)
    {client.id, token.value}
  end

  @doc "The ID of a native client holding an active refresh grant for `user`."
  def native_client_id(%User{} = user) do
    {client_id, _token} = native_access_token(user)
    client_id
  end

  @doc "Rotates the client's active refresh grant the way the token endpoint does."
  def rotate_refresh_grant(client_id, %User{} = user) do
    # Boruta's refresh grant links the new row to the previous access token value.
    %{value: previous_value} =
      Atlas.Repo.one!(
        from t in Token,
          where: t.client_id == ^client_id and t.sub == ^user.id and is_nil(t.refresh_token_revoked_at)
      )

    client = Clients.get_client(client_id)

    {:ok, token} =
      AccessTokens.create(%{client: client, scope: "mcp", sub: user.id, previous_token: previous_value},
        refresh_token: true
      )

    token
  end

  @doc "Credentials unique to the calling test, so per-identity caches never collide across async tests."
  def apns_config do
    %{team_id: "TEAM123456", key_id: random_identifier(), private_key: ec_pem()}
  end

  def fcm_config do
    %{
      project_id: "atlas-test-project",
      client_email: "push-#{System.unique_integer([:positive])}@atlas-test-project.iam.gserviceaccount.com",
      private_key: rsa_pem()
    }
  end

  defp random_identifier, do: 6 |> :crypto.strong_rand_bytes() |> Base.encode32(padding: false) |> binary_part(0, 10)

  def ec_pem, do: cached_pem(:ec, fn -> JOSE.JWK.generate_key({:ec, "P-256"}) end)
  def rsa_pem, do: cached_pem(:rsa, fn -> JOSE.JWK.generate_key({:rsa, 2048}) end)

  defp cached_pem(type, generate) do
    key = {__MODULE__, type}

    case :persistent_term.get(key, nil) do
      nil ->
        {_meta, pem} = JOSE.JWK.to_pem(generate.())
        :persistent_term.put(key, pem)
        pem

      pem ->
        pem
    end
  end
end
