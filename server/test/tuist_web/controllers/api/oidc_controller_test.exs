defmodule TuistWeb.API.OIDCControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Authentication
  alias Tuist.Authorization
  alias Tuist.OAuth.Introspection
  alias Tuist.OIDC
  alias Tuist.OIDC.ScopeRules
  alias TuistTestSupport.Fixtures.ProjectsFixtures

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

      stub(OIDC, :claims, fn _token -> {:ok, %{repository: "tuist/tuist"}} end)

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

      stub(OIDC, :claims, fn _token -> {:ok, %{repository: "tuist/monorepo"}} end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/auth/oidc/token", %{token: "oidc-token"})

      response = json_response(conn, :ok)
      assert response["access_token"]

      {:ok, claims} = Tuist.Guardian.decode_and_verify(response["access_token"])
      assert project1.id in claims["project_ids"]
      assert project2.id in claims["project_ids"]
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

      stub(OIDC, :claims, fn _token -> {:ok, %{repository: "tuist/shared"}} end)

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

      stub(OIDC, :claims, fn _token -> {:ok, %{repository: "tuist/renamed"}} end)

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

      stub(OIDC, :claims, fn _token -> {:ok, %{repository: "tuist/cased"}} end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/auth/oidc/token", %{token: "oidc-token"})

      assert json_response(conn, :forbidden)["message"] =~ "is linked to projects in multiple Tuist accounts"
    end

    test "returns 403 when no project is linked to the repository", %{conn: conn} do
      stub(OIDC, :claims, fn _token -> {:ok, %{repository: "nonexistent/repo"}} end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/auth/oidc/token", %{token: "oidc-token"})

      response = json_response(conn, :forbidden)
      assert response["message"] =~ "No projects linked"
    end

    test "returns 401 when OIDC token is invalid", %{conn: conn} do
      stub(OIDC, :claims, fn _token -> {:error, :invalid_token} end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/auth/oidc/token", %{token: "invalid-token"})

      response = json_response(conn, :unauthorized)
      assert response["message"] =~ "Invalid"
    end

    test "returns 400 when OIDC token is from unsupported CI provider", %{conn: conn} do
      stub(OIDC, :claims, fn _token -> {:error, :unsupported_provider, "https://gitlab.com"} end)

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
      stub(OIDC, :claims, fn _token -> {:error, :token_expired} end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/auth/oidc/token", %{token: "expired-token"})

      response = json_response(conn, :unauthorized)
      assert response["message"] =~ "expired"
    end

    test "returns 401 when OIDC token audience is invalid", %{conn: conn} do
      stub(OIDC, :claims, fn _token -> {:error, :invalid_audience} end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/auth/oidc/token", %{token: "wrong-audience-token"})

      response = json_response(conn, :unauthorized)
      assert response["message"] =~ "audience"
    end
  end

  describe "POST /api/auth/oidc/token with OIDC scope rules" do
    setup do
      project =
        ProjectsFixtures.project_fixture(
          vcs_connection: [repository_full_handle: "tuist/rules"],
          preload: [:account, :vcs_connection]
        )

      %{project: project, account: project.account}
    end

    defp exchange(conn, claims) do
      stub(OIDC, :claims, fn _token ->
        {:ok, Map.merge(%{repository: "tuist/rules", provider: :github_actions}, claims)}
      end)

      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-tuist-cli-version", "4.300.0")
      |> post(~p"/api/auth/oidc/token", %{token: "oidc-token"})
    end

    defp warnings(conn) do
      case get_resp_header(conn, "x-tuist-cloud-warnings") do
        [encoded] -> encoded |> Base.decode64!() |> JSON.decode!()
        [] -> []
      end
    end

    test "keeps every scope when the rules match", %{conn: conn, project: project} do
      {:ok, _} = ScopeRules.put_project_rule(project, "project:previews:write", %{refs: ["refs/heads/main"]})

      conn = exchange(conn, %{ref: "refs/heads/main"})

      response = json_response(conn, :ok)
      {:ok, claims} = Tuist.Guardian.decode_and_verify(response["access_token"])
      refute Map.has_key?(claims, "withheld_scopes")
      assert warnings(conn) == []

      subject = Authentication.authenticated_subject(response["access_token"])
      assert :ok = Authorization.authorize(:preview_create, subject, project)
    end

    test "withholds preview uploads for a non-matching branch but keeps other writes", %{conn: conn, project: project} do
      {:ok, _} = ScopeRules.put_project_rule(project, "project:previews:write", %{refs: ["refs/heads/main"]})

      conn = exchange(conn, %{ref: "refs/heads/feature"})

      response = json_response(conn, :ok)
      {:ok, claims} = Tuist.Guardian.decode_and_verify(response["access_token"])
      assert claims["withheld_scopes"] == %{"project:previews:write" => [project.id]}

      assert [warning] = warnings(conn)
      assert warning =~ "project:previews:write"
      assert warning =~ "refs/heads/feature"

      subject = Authentication.authenticated_subject(response["access_token"])
      assert {:error, :forbidden} = Authorization.authorize(:preview_create, subject, project)
      assert :ok = Authorization.authorize(:preview_read, subject, project)
      assert :ok = Authorization.authorize(:test_create, subject, project)
      assert :ok = Authorization.authorize(:project_cache_create, subject, project)
    end

    test "downgrades a withheld cache write to read access", %{conn: conn, project: project, account: account} do
      {:ok, _} = ScopeRules.put_project_rule(project, "project:cache:write", %{environments: ["production"]})

      response = conn |> exchange(%{ref: "refs/heads/main"}) |> json_response(:ok)

      project_handle = "#{account.name}/#{project.name}"

      assert %{cache_grants: %{"project" => %{"read" => [^project_handle], "write" => []}}} =
               Introspection.token_response(response["access_token"], account)

      subject = Authentication.authenticated_subject(response["access_token"])
      assert {:error, :forbidden} = Authorization.authorize(:project_cache_create, subject, project)
      assert :ok = Authorization.authorize(:project_cache_read, subject, project)

      # Cache nodes read these handles as read and write access, so a
      # project whose write was withheld must not be listed.
      access =
        build_conn()
        |> put_req_header("authorization", "Bearer #{response["access_token"]}")
        |> get(~p"/api/cache/access")
        |> json_response(:ok)

      assert access["projects"] == []
    end

    test "withholds the account-wide cache by the account's own rules", %{conn: conn, project: project, account: account} do
      {:ok, _} = ScopeRules.put_account_rule(account, "account:cache:write", %{refs: ["refs/heads/main"]})

      conn = exchange(conn, %{ref: "refs/heads/feature"})
      response = json_response(conn, :ok)

      {:ok, claims} = Tuist.Guardian.decode_and_verify(response["access_token"])
      assert claims["withheld_scopes"] == %{"account:cache:write" => [account.id]}
      assert [warning] = warnings(conn)
      assert warning =~ "account:cache:write"

      subject = Authentication.authenticated_subject(response["access_token"])
      assert {:error, :forbidden} = Authorization.authorize(:account_cache_create, subject, account)
      assert :ok = Authorization.authorize(:account_cache_read, subject, account)
      assert :ok = Authorization.authorize(:project_cache_create, subject, project)
    end

    test "withholds ruled scopes from providers other than GitHub Actions", %{conn: conn, project: project} do
      {:ok, _} = ScopeRules.put_project_rule(project, "project:bundles:write", %{refs: ["**"]})

      stub(OIDC, :claims, fn _token -> {:ok, %{repository: "tuist/rules", provider: :circleci}} end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-tuist-cli-version", "4.300.0")
        |> post(~p"/api/auth/oidc/token", %{token: "oidc-token"})

      response = json_response(conn, :ok)
      {:ok, claims} = Tuist.Guardian.decode_and_verify(response["access_token"])
      assert claims["withheld_scopes"] == %{"project:bundles:write" => [project.id]}
      assert [warning] = warnings(conn)
      assert warning =~ "only support GitHub Actions"
    end
  end
end
