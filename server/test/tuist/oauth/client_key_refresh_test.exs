defmodule Tuist.OAuth.ClientKeyRefreshTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Boruta.Ecto.Client
  alias Boruta.Oauth.Authorization
  alias Boruta.Oauth.Request
  alias Tuist.OAuth.Clients
  alias Tuist.OAuth.Exchange
  alias Tuist.Repo
  alias TuistWeb.Oauth.TokenController

  test "an invalid JWT client assertion never holds a grant connection during key refresh" do
    {client, _key} = client_fixture()
    assertion = assertion(client, JOSE.JWK.generate_key({:rsa, 1024}))
    parent = self()

    expect(Finch, :request, fn _, OpenIDHttpClient ->
      send(parent, {:refresh_transaction, Repo.in_transaction?()})
      {:error, :closed}
    end)

    conn = Exchange.token(connection(client, assertion), TokenController)
    assert conn.status == 401, inspect(Map.take(JSON.decode!(conn.resp_body), ["error", "error_description"]))
    assert JSON.decode!(conn.resp_body)["error"] == "invalid_client"
    assert_receive {:refresh_transaction, false}
  end

  test "a rotated client key is fetched once before the grant transaction and remains stored" do
    {client, _old_key} = client_fixture()
    new_key = JOSE.JWK.generate_key({:rsa, 1024})
    parent = self()

    expect(Finch, :request, fn _, OpenIDHttpClient ->
      refute Repo.in_transaction?()
      send(parent, :key_fetched)
      {:ok, %Finch.Response{status: 200, headers: [], body: JSON.encode!(%{"keys" => [public_jwk(new_key)]})}}
    end)

    expect(Repo, :query!, fn "SET LOCAL lock_timeout = '5s'" = sql ->
      assert_receive :key_fetched
      assert Repo.in_transaction?()
      Mimic.call_original(Repo, :query!, [sql])
    end)

    conn = Exchange.token(connection(client, assertion(client, new_key)), TokenController)
    assert conn.status == 400
    assert JSON.decode!(conn.resp_body)["error"] == "invalid_grant"
    assert Repo.get!(Client, client.id).jwt_public_key == public_pem(new_key)
  end

  test "the adapter refuses remote key refresh inside any transaction" do
    {client, _} = client_fixture()
    reject(&Finch.request/2)
    assert {:ok, {:error, reason}} = Repo.transaction(fn -> Clients.refresh_jwk_from_jwks_uri(client.id) end)
    assert reason =~ "inside a transaction"
  end

  test "a key change after preflight cannot trigger a remote fetch under the lock" do
    {client, key} = client_fixture()
    reject(&Finch.request/2)
    replacement = public_pem(JOSE.JWK.generate_key({:rsa, 1024}))

    expect(Repo, :query!, fn "SET LOCAL lock_timeout = '5s'" = sql ->
      Client |> Repo.get!(client.id) |> Ecto.Changeset.change(jwt_public_key: replacement) |> Repo.update!()
      Mimic.call_original(Repo, :query!, [sql])
    end)

    conn = Exchange.token(connection(client, assertion(client, key)), TokenController)
    assert conn.status == 401
    assert JSON.decode!(conn.resp_body)["error"] == "invalid_client"
  end

  for grant <- ["authorization_code", "refresh_token"] do
    @tag grant: grant
    test "#{grant} preflight preserves the original upstream client error", %{grant: grant} do
      {client, _} = client_fixture()
      conn = connection(client, assertion(client, JOSE.JWK.generate_key({:rsa, 1024})), grant)

      expect(Finch, :request, 2, fn _, OpenIDHttpClient ->
        refute Repo.in_transaction?()
        {:error, :closed}
      end)

      assert {:ok, request} = Request.token_request(conn)
      assert {:error, expected} = Authorization.token(request)
      reject(&Repo.transaction/1)
      actual = Exchange.token(conn, TokenController)
      assert actual.status == 401

      assert JSON.decode!(actual.resp_body) == %{
               "error" => to_string(expected.error),
               "error_description" => expected.error_description
             }
    end
  end

  for failure <- [:unknown_client, :wrong_redirect, :missing_pkce, :unsupported_grant, :nil_redirect] do
    @tag client_failure: failure
    test "preflight preserves upstream #{failure} errors and does not claim a connection", %{client_failure: failure} do
      {client, key} = client_fixture()
      reject(&Finch.request/2)
      client = if failure == :unknown_client, do: %{client | id: Ecto.UUID.generate()}, else: client
      body = connection(client, assertion(client, key)).body_params

      body =
        case failure do
          :wrong_redirect -> Map.put(body, "redirect_uri", "https://other.example.test/callback")
          :nil_redirect -> Map.delete(body, "redirect_uri")
          _ -> body
        end

      case failure do
        :missing_pkce ->
          Client |> Repo.get!(client.id) |> Ecto.Changeset.change(pkce: true) |> Repo.update!()

        :unsupported_grant ->
          Client
          |> Repo.get!(client.id)
          |> Ecto.Changeset.change(supported_grant_types: ["refresh_token"])
          |> Repo.update!()

        _ ->
          :ok
      end

      conn = :post |> Plug.Test.conn("/oauth2/token", body) |> Plug.Conn.fetch_query_params()
      assert {:ok, request} = Request.token_request(conn)
      assert {:error, expected} = Authorization.token(request)
      reject(&Repo.transaction/1)
      actual = Exchange.token(conn, TokenController)

      assert JSON.decode!(actual.resp_body) == %{
               "error" => to_string(expected.error),
               "error_description" => expected.error_description
             }
    end
  end

  defp public_pem(key) do
    {_, pem} = key |> JOSE.JWK.to_public() |> JOSE.JWK.to_pem()
    pem
  end

  defp client_fixture do
    key = JOSE.JWK.generate_key({:rsa, 1024})

    attrs = %{
      redirect_uris: ["https://example.test/callback"],
      jwk: public_jwk(key),
      jwks_uri: "https://keys.example.test/jwks",
      confidential: true,
      token_endpoint_auth_methods: ["private_key_jwt"],
      token_endpoint_jwt_auth_alg: "RS256"
    }

    case Clients.create_client(attrs) do
      {:ok, client} -> {client, key}
      {:error, changeset} -> flunk("invalid JWT fixture: #{inspect(changeset.errors)}")
    end
  end

  defp public_jwk(key) do
    {_, map} = key |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()
    Map.put(map, "alg", "RS256")
  end

  defp assertion(client, key) do
    claims = %{
      "iss" => client.id,
      "sub" => client.id,
      "aud" => Boruta.Config.issuer(),
      "exp" => System.system_time(:second) + 60
    }

    {_, jwt} = key |> JOSE.JWT.sign(%{"alg" => "RS256"}, claims) |> JOSE.JWS.compact()
    jwt
  end

  defp connection(client, assertion, grant \\ "authorization_code") do
    params = %{
      "grant_type" => grant,
      "client_id" => client.id,
      "redirect_uri" => "https://example.test/callback",
      "code" => "unissued-code",
      "client_assertion_type" => "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
      "client_assertion" => assertion
    }

    params = if grant == "refresh_token", do: Map.put(params, "refresh_token", "unissued-refresh"), else: params
    :post |> Plug.Test.conn("/oauth2/token", params) |> Plug.Conn.fetch_query_params()
  end
end
