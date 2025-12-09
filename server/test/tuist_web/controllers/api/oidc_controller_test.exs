defmodule TuistWeb.API.OIDCControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    # Clear the JWKS cache before each test
    Cachex.clear(:tuist)
    :ok
  end

  describe "POST /api/oidc/token" do
    test "returns access token when OIDC token is valid and project has VCS connection", %{conn: conn} do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_connection: [repository_full_handle: "tuist/tuist"],
          preload: [:account, :vcs_connection]
        )

      {token, jwks} = generate_test_token_and_jwks(repository: "tuist/tuist")

      stub(Req, :get, fn url ->
        if String.contains?(url, "token.actions.githubusercontent.com") do
          {:ok, %{status: 200, body: jwks}}
        else
          {:error, :not_found}
        end
      end)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/oidc/token", %{token: token})

      # Then
      response = json_response(conn, :ok)
      assert response["access_token"]
      assert response["token_type"] == "Bearer"
      assert response["expires_in"] == 3600

      # Verify the token can be used for authentication
      {:ok, claims} =
        Tuist.Guardian.decode_and_verify(response["access_token"])

      assert claims["type"] == "account"
      assert claims["scopes"] == ["project:cache:read", "project:cache:write", "project:previews:read", "project:previews:write"]
      assert claims["all_projects"] == false
      assert project.id in claims["project_ids"]
    end

    test "returns access token for multiple projects with same VCS connection (monorepo)", %{conn: conn} do
      # Given
      project1 =
        ProjectsFixtures.project_fixture(
          vcs_connection: [repository_full_handle: "tuist/monorepo"],
          preload: [:account, :vcs_connection]
        )

      project2 =
        ProjectsFixtures.project_fixture(
          account: project1.account,
          vcs_connection: [repository_full_handle: "tuist/monorepo"],
          preload: [:account, :vcs_connection]
        )

      {token, jwks} = generate_test_token_and_jwks(repository: "tuist/monorepo")

      stub(Req, :get, fn url ->
        if String.contains?(url, "token.actions.githubusercontent.com") do
          {:ok, %{status: 200, body: jwks}}
        else
          {:error, :not_found}
        end
      end)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/oidc/token", %{token: token})

      # Then
      response = json_response(conn, :ok)
      assert response["access_token"]

      {:ok, claims} = Tuist.Guardian.decode_and_verify(response["access_token"])
      assert project1.id in claims["project_ids"]
      assert project2.id in claims["project_ids"]
    end

    test "returns 403 when no project is linked to the repository", %{conn: conn} do
      # Given
      {token, jwks} = generate_test_token_and_jwks(repository: "nonexistent/repo")

      stub(Req, :get, fn url ->
        if String.contains?(url, "token.actions.githubusercontent.com") do
          {:ok, %{status: 200, body: jwks}}
        else
          {:error, :not_found}
        end
      end)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/oidc/token", %{token: token})

      # Then
      response = json_response(conn, :forbidden)
      assert response["message"] =~ "No projects linked"
    end

    test "returns 401 when OIDC token is invalid", %{conn: conn} do
      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/oidc/token", %{token: "invalid-token"})

      # Then
      response = json_response(conn, :unauthorized)
      assert response["message"] =~ "Invalid"
    end

    test "returns 401 when OIDC token has wrong issuer", %{conn: conn} do
      # Given
      {token, jwks} = generate_test_token_and_jwks(issuer: "https://wrong-issuer.com")

      stub(Req, :get, fn _url ->
        {:ok, %{status: 200, body: jwks}}
      end)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/oidc/token", %{token: token})

      # Then
      response = json_response(conn, :unauthorized)
      assert response["message"] =~ "issuer"
    end

    test "returns 401 when OIDC token is expired", %{conn: conn} do
      # Given
      {token, jwks} =
        generate_test_token_and_jwks(
          exp: DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.to_unix()
        )

      stub(Req, :get, fn _url ->
        {:ok, %{status: 200, body: jwks}}
      end)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/oidc/token", %{token: token})

      # Then
      response = json_response(conn, :unauthorized)
      assert response["message"] =~ "expired"
    end
  end

  defp generate_test_token_and_jwks(opts \\ []) do
    jwk = JOSE.JWK.generate_key({:rsa, 2048})

    claims =
      %{
        "iss" => Keyword.get(opts, :issuer, "https://token.actions.githubusercontent.com"),
        "sub" => "repo:tuist/tuist:ref:refs/heads/main",
        "aud" => "tuist",
        "exp" => Keyword.get(opts, :exp, DateTime.utc_now() |> DateTime.add(3600) |> DateTime.to_unix()),
        "iat" => DateTime.utc_now() |> DateTime.to_unix(),
        "repository" => Keyword.get(opts, :repository, "tuist/tuist"),
        "repository_owner" => "tuist",
        "ref" => "refs/heads/main",
        "workflow" => "CI",
        "actor" => "test-user",
        "run_id" => "123456789"
      }
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    jws = %{"alg" => "RS256", "kid" => "test-key-1"}
    jwt = JOSE.JWT.from_map(claims)
    {_, token} = jwk |> JOSE.JWT.sign(jws, jwt) |> JOSE.JWS.compact()

    {_, public_jwk_map} = jwk |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()

    jwks = %{
      "keys" => [
        public_jwk_map
        |> Map.put("use", "sig")
        |> Map.put("alg", "RS256")
        |> Map.put("kid", "test-key-1")
      ]
    }

    {token, jwks}
  end
end
