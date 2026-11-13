defmodule TuistWeb.API.OIDCControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.OAuth.Introspection
  alias Tuist.OIDC
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.SandboxesFixtures

  describe "POST /api/auth/oidc/token" do
    test "returns access token with cache write access when OIDC token is valid and project has VCS connection", %{
      conn: conn
    } do
      project =
        ProjectsFixtures.project_fixture(
          vcs_connection: [repository_full_handle: "tuist/tuist"],
          preload: [:account, :vcs_connection]
        )

      {:ok, account} = Accounts.update_account(project.account, %{cache_write_policy: :tokens_only})

      stub(OIDC, :claims, fn _token, _account -> {:ok, %{repository: "tuist/tuist"}} end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/auth/oidc/token", %{token: "oidc-token"})

      response = json_response(conn, :ok)
      assert response["access_token"]
      assert response["expires_in"] == 3600

      {:ok, claims} = Tuist.Guardian.decode_and_verify(response["access_token"])

      assert claims["type"] == "account"

      assert claims["scopes"] == ["ci"]

      assert project.id in claims["project_ids"]

      project_handle = "#{account.name}/#{project.name}"

      assert %{
               active: true,
               cache_grants: %{
                 "project" => %{"read" => [^project_handle], "write" => [^project_handle]}
               }
             } = Introspection.token_response(response["access_token"], account)
    end

    test "returns access token for multiple projects with same VCS connection (monorepo)", %{conn: conn} do
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

      unrelated = ProjectsFixtures.project_fixture(account: project1.account)
      stub(OIDC, :claims, fn _token, _account -> {:ok, %{repository: "tuist/monorepo", all_projects: true}} end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/auth/oidc/token", %{token: "oidc-token"})

      response = json_response(conn, :ok)
      assert response["access_token"]

      {:ok, claims} = Tuist.Guardian.decode_and_verify(response["access_token"])
      assert project1.id in claims["project_ids"]
      assert project2.id in claims["project_ids"]
      refute claims["all_projects"]
      refute unrelated.id in claims["project_ids"]
      future = ProjectsFixtures.project_fixture(account: project1.account)
      refute future.id in claims["project_ids"]
    end

    test "returns 403 naming the accounts when the repository is linked from multiple accounts", %{conn: conn} do
      project1 =
        ProjectsFixtures.project_fixture(
          vcs_connection: [repository_full_handle: "tuist/shared"],
          preload: [:account]
        )

      project2 =
        ProjectsFixtures.project_fixture(
          vcs_connection: [repository_full_handle: "tuist/shared"],
          preload: [:account]
        )

      stub(OIDC, :claims, fn _token, _account -> {:ok, %{repository: "tuist/shared"}} end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/auth/oidc/token", %{token: "oidc-token"})

      response = json_response(conn, :forbidden)
      refute response["access_token"]
      assert response["message"] =~ "'tuist/shared' is linked to projects in multiple Tuist accounts"

      assert response["message"] =~
               "(#{Enum.join(Enum.sort([project1.account.name, project2.account.name]), ", ")})"
    end

    test "returns access token when the repository claim differs in case from the linked repository", %{conn: conn} do
      project =
        ProjectsFixtures.project_fixture(
          vcs_connection: [repository_full_handle: "Tuist/Renamed"],
          preload: [:account]
        )

      stub(OIDC, :claims, fn _token, _account -> {:ok, %{repository: "tuist/renamed"}} end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/auth/oidc/token", %{token: "oidc-token"})

      response = json_response(conn, :ok)
      {:ok, claims} = Tuist.Guardian.decode_and_verify(response["access_token"])
      assert claims["project_ids"] == [project.id]
      assert claims["sub"] == to_string(project.account.id)
    end

    test "returns 403 when the repository is linked from multiple accounts with different casing", %{conn: conn} do
      ProjectsFixtures.project_fixture(vcs_connection: [repository_full_handle: "Tuist/Cased"])
      ProjectsFixtures.project_fixture(vcs_connection: [repository_full_handle: "tuist/cased"])

      stub(OIDC, :claims, fn _token, _account -> {:ok, %{repository: "tuist/cased"}} end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/auth/oidc/token", %{token: "oidc-token"})

      assert json_response(conn, :forbidden)["message"] =~ "is linked to projects in multiple Tuist accounts"
    end

    test "returns 403 when no project is linked to the repository", %{conn: conn} do
      stub(OIDC, :claims, fn _token, _account -> {:ok, %{repository: "nonexistent/repo"}} end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/auth/oidc/token", %{token: "oidc-token"})

      response = json_response(conn, :forbidden)
      assert response["message"] =~ "No projects linked"
    end

    test "returns 401 when OIDC token is invalid", %{conn: conn} do
      stub(OIDC, :claims, fn _token, _account -> {:error, :invalid_token} end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/auth/oidc/token", %{token: "invalid-token"})

      response = json_response(conn, :unauthorized)
      assert response["message"] =~ "Invalid"
    end

    test "returns 400 when OIDC token is from unsupported CI provider", %{conn: conn} do
      stub(OIDC, :claims, fn _token, _account -> {:error, :unsupported_provider, "https://gitlab.com"} end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/auth/oidc/token", %{token: "gitlab-token"})

      response = json_response(conn, :bad_request)
      assert response["message"] =~ "Unsupported CI provider"
      assert response["message"] =~ "gitlab.com"
      assert response["message"] =~ "GitHub Actions"
    end

    test "returns 401 when OIDC token is expired", %{conn: conn} do
      stub(OIDC, :claims, fn _token, _account -> {:error, :token_expired} end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/auth/oidc/token", %{token: "expired-token"})

      response = json_response(conn, :unauthorized)
      assert response["message"] =~ "expired"
    end

    test "returns 401 when OIDC token audience is invalid", %{conn: conn} do
      stub(OIDC, :claims, fn _token, _account -> {:error, :invalid_audience} end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/auth/oidc/token", %{token: "wrong-audience-token"})

      response = json_response(conn, :unauthorized)
      assert response["message"] =~ "audience"
    end
  end

  describe "POST /api/auth/oidc/token with a signed GitHub Actions token" do
    setup do
      stub(Tuist.KeyValueStore, :get_or_update, fn _key, _opts, func -> func.() end)
      :ok
    end

    test "does not authorize projects linked to a GitHub Enterprise Server repository with the same name", %{conn: conn} do
      account = AccountsFixtures.organization_fixture(preload: [:account]).account
      ghes_installation_fixture(account)

      ProjectsFixtures.project_fixture(
        account_id: account.id,
        vcs_connection: [repository_full_handle: "acme-internal/app"]
      )

      conn = exchange(conn, "acme-internal/app")

      assert json_response(conn, :forbidden)["message"] =~ "No projects linked"
    end

    test "authorizes only github.com-linked projects when a GitHub Enterprise Server link has the same name", %{
      conn: conn
    } do
      project =
        ProjectsFixtures.project_fixture(vcs_connection: [repository_full_handle: "acme/app"], preload: [:account])

      other_account = AccountsFixtures.organization_fixture(preload: [:account]).account
      ghes_installation_fixture(other_account)

      ProjectsFixtures.project_fixture(
        account_id: other_account.id,
        vcs_connection: [repository_full_handle: "acme/app"]
      )

      conn = exchange(conn, "acme/app")

      {:ok, claims} = Tuist.Guardian.decode_and_verify(json_response(conn, :ok)["access_token"])
      assert claims["sub"] == to_string(project.account.id)
      assert claims["project_ids"] == [project.id]
    end
  end

  describe "POST /api/auth/oidc/token with a Claude Code session token" do
    setup do
      stub(Tuist.KeyValueStore, :get_or_update, fn _key, _opts, func -> func.() end)
      stub(Tuist.FeatureFlags, :sandboxes_enabled?, fn _account -> true end)
      account = AccountsFixtures.organization_fixture(preload: [:account]).account

      SandboxesFixtures.agent_environment_fixture(
        account: account,
        kind: :claude_code,
        anthropic_environment_id: "ccpool_01connected"
      )

      %{account: account}
    end

    test "grants a session of a connected environment CI and sandbox access to its account, for no longer than the session token",
         %{conn: conn, account: account} do
      expires_at = DateTime.utc_now() |> DateTime.add(600) |> DateTime.to_unix()

      response = conn |> exchange_session_token(%{"exp" => expires_at}) |> json_response(:ok)

      {:ok, claims} = Tuist.Guardian.decode_and_verify(response["access_token"])
      assert claims["sub"] == to_string(account.id)
      assert claims["scopes"] == ["ci", "account:sandboxes:write"]
      assert claims["preferred_username"] == account.name
      assert claims["all_projects"] == true
      assert response["expires_in"] in 590..600
      assert claims["exp"] <= expires_at
    end

    test "refuses other tokens of self-hosted environments, which share the signing keys", %{conn: conn} do
      conn = exchange_session_token(conn, %{"ccr:role" => "runner"})

      assert json_response(conn, :unauthorized)
    end

    test "refuses a token whose audience is not its environment", %{conn: conn} do
      conn = exchange_session_token(conn, %{"aud" => ["anthropic-api", "ccpool_01other"]})

      assert json_response(conn, :unauthorized)
    end

    test "refuses sessions of an environment no account connected or that was disabled", %{
      conn: conn,
      account: account
    } do
      unknown =
        exchange_session_token(conn, %{
          "ccr:pool_id" => "ccpool_01unknown",
          "aud" => ["anthropic-api", "ccpool_01unknown"]
        })

      assert json_response(unknown, :forbidden)["message"] =~ "Claude Code environment is not connected"

      [environment] = Tuist.Sandboxes.list_agent_environments(account)
      environment |> Ecto.Changeset.change(enabled: false) |> Tuist.Repo.update!()

      assert build_conn() |> exchange_session_token() |> json_response(:forbidden)
    end

    test "accepts a session token only with Anthropic's self-hosted prefix", %{conn: conn} do
      conn = exchange_session_token(conn, %{}, "")

      refute conn.status == 200
    end
  end

  defp ghes_installation_fixture(account) do
    {:ok, _installation} =
      Tuist.VCS.create_github_app_installation(%{
        account_id: account.id,
        installation_id: "#{account.id}54321",
        client_url: "https://ghes.example.test"
      })
  end

  defp exchange_session_token(conn, claims \\ %{}, prefix \\ "sk-ant-cc-") do
    jwk = JOSE.JWK.generate_key({:ec, "P-256"})
    {_, public_jwk} = jwk |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()
    jwks = %{"keys" => [Map.merge(public_jwk, %{"use" => "sig", "alg" => "ES256", "kid" => "ccr-key"})]}

    claims =
      Map.merge(
        %{
          "iss" => "ccr",
          "sub" => "ccr:session:cse_01abc",
          "aud" => ["anthropic-api", "ccpool_01connected"],
          "exp" => DateTime.utc_now() |> DateTime.add(4 * 3600) |> DateTime.to_unix(),
          "iat" => DateTime.to_unix(DateTime.utc_now()),
          "ccr:role" => "session_worker",
          "ccr:pool_id" => "ccpool_01connected",
          "ccr:session_id" => "cse_01abc"
        },
        claims
      )

    {_, token} =
      jwk |> JOSE.JWT.sign(%{"alg" => "ES256", "kid" => "ccr-key"}, JOSE.JWT.from_map(claims)) |> JOSE.JWS.compact()

    stub(Req, :get, fn "https://api.anthropic.com/v1/code/.well-known/jwks.json", _opts ->
      {:ok, %{status: 200, body: jwks}}
    end)

    conn
    |> put_req_header("content-type", "application/json")
    |> post(~p"/api/auth/oidc/token", %{token: prefix <> token})
  end

  defp exchange(conn, repository) do
    jwk = JOSE.JWK.generate_key({:rsa, 2048})
    {_, public_jwk} = jwk |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()
    jwks = %{"keys" => [Map.merge(public_jwk, %{"use" => "sig", "alg" => "RS256", "kid" => "test-key"})]}

    claims = %{
      "iss" => "https://token.actions.githubusercontent.com",
      "aud" => "tuist",
      "exp" => DateTime.utc_now() |> DateTime.add(3600) |> DateTime.to_unix(),
      "repository" => repository
    }

    {_, token} =
      jwk |> JOSE.JWT.sign(%{"alg" => "RS256", "kid" => "test-key"}, JOSE.JWT.from_map(claims)) |> JOSE.JWS.compact()

    stub(Req, :get, fn "https://token.actions.githubusercontent.com/.well-known/jwks", _opts ->
      {:ok, %{status: 200, body: jwks}}
    end)

    conn
    |> put_req_header("content-type", "application/json")
    |> post(~p"/api/auth/oidc/token", %{token: token})
  end
end
