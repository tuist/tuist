defmodule LuftServer.FakeTuist do
  @moduledoc """
  A stand-in OpenID Provider for tests, answering through `Req.Test` the way
  the Tuist server does: discovery, a JWK Set, the token endpoint (which
  checks client authentication and PKCE) and the organizations API.
  """
  import Plug.Conn

  @issuer "https://tuist.test"
  @client_id "0b2f5c0e-7a3d-4c6e-9a51-2d4f8e1b6c37"

  def issuer, do: @issuer

  @doc """
  Stubs the provider for the calling test. `state` is an Agent holding the
  pending authorization (`:code`, `:challenge`, `:nonce`) and the
  organizations.
  """
  def stub(opts \\ []) do
    key = JOSE.JWK.generate_key({:rsa, 2048})

    {:ok, state} =
      Agent.start_link(fn ->
        %{organizations: Keyword.get(opts, :organizations, []), refreshes: 0}
      end)

    test_pid = self()

    Req.Test.stub(LuftServer.Tuist, fn conn -> handle(conn, key, state, opts, test_pid) end)
    %{key: key, state: state}
  end

  @doc "Records what an authorization request asked for, as Tuist would after the person signs in."
  def authorize(%{state: state}, authorization_url) do
    query = authorization_url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    code = "code-" <> Integer.to_string(System.unique_integer([:positive]))

    Agent.update(
      state,
      &Map.put(&1, :pending, %{
        code: code,
        challenge: query["code_challenge"],
        nonce: query["nonce"]
      })
    )

    {code, query}
  end

  defp handle(
         %Plug.Conn{request_path: "/.well-known/openid-configuration"} = conn,
         _key,
         _state,
         _opts,
         _pid
       ) do
    Req.Test.json(conn, %{
      "issuer" => @issuer,
      "authorization_endpoint" => @issuer <> "/oauth2/authorize",
      "token_endpoint" => @issuer <> "/oauth2/token",
      "jwks_uri" => @issuer <> "/oauth2/jwks",
      "revocation_endpoint" => @issuer <> "/oauth2/revoke"
    })
  end

  defp handle(%Plug.Conn{request_path: "/oauth2/jwks"} = conn, key, _state, _opts, _pid) do
    {_, public} = key |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()

    Req.Test.json(conn, %{
      "keys" => [Map.merge(public, %{"kid" => "k1", "use" => "sig", "alg" => "RS256"})]
    })
  end

  defp handle(%Plug.Conn{request_path: "/oauth2/token"} = conn, key, state, opts, _pid) do
    {:ok, body, conn} = read_body(conn)
    form = URI.decode_query(body)

    cond do
      get_req_header(conn, "authorization") != [
        "Basic " <> Base.encode64("#{@client_id}:test-secret")
      ] ->
        conn |> put_status(401) |> Req.Test.json(%{"error" => "invalid_client"})

      form["grant_type"] == "authorization_code" ->
        pending = Agent.get(state, & &1[:pending])

        challenge =
          :sha256
          |> :crypto.hash(form["code_verifier"] || "")
          |> Base.url_encode64(padding: false)

        if pending && pending.code == form["code"] && pending.challenge == challenge do
          Req.Test.json(conn, tokens(key, Keyword.get(opts, :nonce, pending.nonce), opts))
        else
          conn |> put_status(400) |> Req.Test.json(%{"error" => "invalid_grant"})
        end

      form["grant_type"] == "refresh_token" ->
        case Keyword.get(opts, :refresh, :ok) do
          :ok ->
            Agent.update(state, &Map.update!(&1, :refreshes, fn n -> n + 1 end))

            Req.Test.json(conn, %{
              "access_token" => "access-refreshed",
              "refresh_token" => "refresh-2",
              "expires_in" => 3600
            })

          :invalid_client ->
            conn |> put_status(401) |> Req.Test.json(%{"error" => "invalid_client"})

          :user_deleted ->
            Req.Test.json(conn, %{"token_type" => "bearer", "expires_in" => 3599})

          :invalid_grant ->
            conn |> put_status(400) |> Req.Test.json(%{"error" => "invalid_grant"})
        end
    end
  end

  defp handle(%Plug.Conn{request_path: "/oauth2/revoke"} = conn, _key, _state, _opts, _pid),
    do: send_resp(conn, 200, "")

  defp handle(
         %Plug.Conn{request_path: "/api/organizations", method: "GET"} = conn,
         _key,
         state,
         _opts,
         pid
       ) do
    send(pid, {:tuist_api, get_req_header(conn, "authorization")})
    Req.Test.json(conn, %{"organizations" => Agent.get(state, & &1.organizations)})
  end

  defp handle(
         %Plug.Conn{request_path: "/api/organizations", method: "POST"} = conn,
         _key,
         state,
         _opts,
         _pid
       ) do
    {:ok, body, conn} = read_body(conn)
    %{"name" => name} = JSON.decode!(body)
    organization = %{"id" => 2, "name" => name, "plan" => "none"}
    Agent.update(state, &Map.update!(&1, :organizations, fn orgs -> orgs ++ [organization] end))
    Req.Test.json(conn, organization)
  end

  defp tokens(key, nonce, opts) do
    now = System.system_time(:second)

    claims =
      Map.merge(
        %{
          "iss" => @issuer,
          "aud" => @client_id,
          "sub" => "42",
          "email" => "person@example.com",
          "preferred_username" => "person",
          "iat" => now,
          "exp" => now + 3600,
          "nonce" => nonce
        },
        Keyword.get(opts, :claims, %{})
      )

    {_, id_token} =
      key |> JOSE.JWT.sign(%{"alg" => "RS256", "kid" => "k1"}, claims) |> JOSE.JWS.compact()

    %{
      "access_token" => "access-1",
      "refresh_token" => "refresh-1",
      "expires_in" => Keyword.get(opts, :expires_in, 3600),
      "token_type" => "Bearer",
      "id_token" => id_token
    }
  end
end
