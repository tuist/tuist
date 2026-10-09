defmodule TuistWeb.AuthenticationPlugTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import Plug.Test

  alias Tuist.Accounts
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Projects
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.AuthenticationPlug
  alias TuistWeb.Headers

  # This is needed in combination with "async: false" to ensure
  # that mocks are used within the cache process.
  setup :set_mimic_from_context

  setup do
    cache = String.to_atom(UUIDv7.generate())
    {:ok, _} = Cachex.start_link(name: cache)
    {:ok, cache: cache}
  end

  describe "load_authenticated_subject" do
    test "reloads credentials on every request even when caching is requested", %{cache: cache} do
      # Given
      opts = AuthenticationPlug.init(:load_authenticated_subject)
      user = AccountsFixtures.user_fixture(preload: [:account])

      {:ok, {account_token, account_token_value}} =
        Accounts.create_account_token(
          %{
            account: user.account,
            name: "test-token",
            scopes: ["project:cache:read"]
          },
          preload: [:account]
        )

      authenticated_account = %AuthenticatedAccount{
        account: account_token.account,
        scopes: ["account:members:read"]
      }

      # Credential validity is authoritative on every request
      expect(Tuist.Authentication, :authenticated_subject, 10, fn ^account_token_value ->
        authenticated_account
      end)

      conn =
        :get
        |> conn("/")
        |> assign(:caching, true)
        |> assign(:cache, cache)
        |> assign(:cache_ttl, to_timeout(minute: 1))
        |> put_req_header("authorization", "Bearer " <> account_token_value)

      # When/Then
      for _n <- 1..10 do
        got = AuthenticationPlug.call(conn, opts)
        assert got.assigns[:current_subject] == authenticated_account
        assert(TuistWeb.Authentication.authenticated?(got) == true)
      end
    end

    test "rejects a token revoked after an earlier request", %{cache: cache} do
      user = AccountsFixtures.user_fixture(preload: [:account])

      {:ok, {token, value}} =
        Accounts.create_account_token(%{
          account: user.account,
          name: "revoked-token",
          scopes: ["project:cache:read"]
        })

      conn =
        :get
        |> conn("/")
        |> assign(:cache, cache)
        |> assign(:caching, true)
        |> put_req_header("authorization", "Bearer " <> value)

      opts = AuthenticationPlug.init(:load_authenticated_subject)
      assert TuistWeb.Authentication.authenticated?(AuthenticationPlug.call(conn, opts))
      {:ok, _} = Accounts.delete_account_token(token)
      refute TuistWeb.Authentication.authenticated?(AuthenticationPlug.call(conn, opts))
    end

    test "project-token traffic reuses bcrypt proofs but observes revocation immediately" do
      project = ProjectsFixtures.project_fixture(preload: [:account])
      value = Projects.create_project_token(project)
      {:ok, token} = Projects.get_project_token(value)
      Cachex.clear(:token_verification)

      expect(Bcrypt, :verify_pass, 1, fn _secret, stored_hash ->
        assert stored_hash == token.encrypted_token_hash
        true
      end)

      conn = :get |> conn("/") |> assign(:caching, true) |> put_req_header("authorization", "Bearer " <> value)
      opts = AuthenticationPlug.init(:load_authenticated_subject)

      for _ <- 1..100 do
        assert TuistWeb.Authentication.current_project(AuthenticationPlug.call(conn, opts)).id == project.id
      end

      {:ok, _} = Projects.revoke_project_token(token)
      refute TuistWeb.Authentication.authenticated?(AuthenticationPlug.call(conn, opts))
    end

    test "account-token traffic reuses bcrypt proofs but reads current scopes and expiry" do
      user = AccountsFixtures.user_fixture(preload: [:account])

      {:ok, {token, value}} =
        Accounts.create_account_token(%{
          account: user.account,
          name: "hot-path-token",
          scopes: ["project:cache:read"]
        })

      expect(Bcrypt, :verify_pass, 1, fn _secret, stored_hash ->
        assert stored_hash == token.encrypted_token_hash
        true
      end)

      conn = :get |> conn("/") |> assign(:caching, true) |> put_req_header("authorization", "Bearer " <> value)
      opts = AuthenticationPlug.init(:load_authenticated_subject)

      for _ <- 1..100 do
        assert AuthenticationPlug.call(conn, opts).assigns.current_subject.scopes == ["project:cache:read"]
      end

      token = token |> Ecto.Changeset.change(scopes: ["project:builds:read"]) |> Tuist.Repo.update!()
      assert AuthenticationPlug.call(conn, opts).assigns.current_subject.scopes == ["project:builds:read"]

      token
      |> Ecto.Changeset.change(expires_at: DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.truncate(:second))
      |> Tuist.Repo.update!()

      refute TuistWeb.Authentication.authenticated?(AuthenticationPlug.call(conn, opts))
    end

    test "mixed-token API traffic verifies each credential once, not once per request" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account: user.account)

      credentials =
        Enum.flat_map(1..10, fn n ->
          project_value = Projects.create_project_token(project)

          {:ok, {account_token, account_value}} =
            Accounts.create_account_token(%{
              account: user.account,
              name: "efficiency-#{n}",
              scopes: ["project:cache:read"]
            })

          [
            {project_value, {:project, project.id}},
            {account_value, {:account, account_token.account_id}}
          ]
        end)

      # Mock only the expensive primitive. Subject resolution and token reads
      # still use the real authentication context and database on every request.
      expect(Bcrypt, :verify_pass, length(credentials), fn _secret, _stored_hash -> true end)
      opts = AuthenticationPlug.init(:load_authenticated_subject)

      for _ <- 1..20, {value, expected_subject} <- credentials do
        conn = :get |> conn("/") |> assign(:caching, true) |> put_req_header("authorization", "Bearer " <> value)
        result = AuthenticationPlug.call(conn, opts)
        assert TuistWeb.Authentication.authenticated?(result)

        case expected_subject do
          {:project, id} -> assert TuistWeb.Authentication.current_project(result).id == id
          {:account, id} -> assert result.assigns.current_subject.account.id == id
        end
      end
    end

    test "a warmed account-token proof cannot bypass user deactivation" do
      user = AccountsFixtures.user_fixture(preload: [:account])

      {:ok, {_token, value}} =
        Accounts.create_account_token(%{
          account: user.account,
          name: "inactive-user-token",
          scopes: ["project:cache:read"]
        })

      conn = :get |> conn("/") |> put_req_header("authorization", "Bearer " <> value)
      opts = AuthenticationPlug.init(:load_authenticated_subject)
      assert TuistWeb.Authentication.authenticated?(AuthenticationPlug.call(conn, opts))
      user |> Ecto.Changeset.change(active: false) |> Tuist.Repo.update!()
      refute TuistWeb.Authentication.authenticated?(AuthenticationPlug.call(conn, opts))
    end

    test "loads the authenticated account" do
      # Given
      opts = AuthenticationPlug.init(:load_authenticated_subject)

      {:ok, {account_token, account_token_value}} =
        Accounts.create_account_token(
          %{
            account: AccountsFixtures.user_fixture(preload: [:account]).account,
            name: "test-token",
            scopes: ["project:cache:read"]
          },
          preload: [:account]
        )

      conn = :get |> conn("/") |> put_req_header("authorization", "Bearer " <> account_token_value)

      # When
      got = AuthenticationPlug.call(conn, opts)

      # Then
      assert got.assigns[:current_subject].account == account_token.account
      assert got.assigns[:current_subject].scopes == ["project:cache:read"]

      assert TuistWeb.Authentication.authenticated?(got) == true
    end

    test "loads the confirmed user for a claimed auth.md credential on the MCP endpoint" do
      opts = AuthenticationPlug.init(:load_authenticated_subject)
      user = AccountsFixtures.user_fixture(preload: [:account])
      token_id = UUIDv7.generate()
      token = "claimed-agent-token"

      authenticated_account = %AuthenticatedAccount{
        account: user.account,
        scopes: ["mcp"],
        token_id: token_id
      }

      expect(Tuist.Authentication, :authenticated_subject, fn ^token -> authenticated_account end)
      expect(Accounts, :claimed_agent_registration_user, fn ^token_id -> user end)

      conn = :post |> conn("/mcp") |> put_req_header("authorization", "Bearer " <> token)

      got = AuthenticationPlug.call(conn, opts)

      assert got.assigns.current_subject == authenticated_account
      assert TuistWeb.Authentication.current_user(got).id == user.id
    end

    test "does not promote a claimed agent user outside the MCP endpoint" do
      opts = AuthenticationPlug.init(:load_authenticated_subject)
      user = AccountsFixtures.user_fixture(preload: [:account])
      token = "claimed-agent-token"

      authenticated_account = %AuthenticatedAccount{
        account: user.account,
        scopes: ["mcp"],
        token_id: UUIDv7.generate()
      }

      expect(Tuist.Authentication, :authenticated_subject, fn ^token -> authenticated_account end)

      conn = :get |> conn("/api/projects") |> put_req_header("authorization", "Bearer " <> token)

      got = AuthenticationPlug.call(conn, opts)

      assert got.assigns.current_subject == authenticated_account
      assert TuistWeb.Authentication.current_user(got) == nil
    end

    test "loads the authenticated user" do
      # Given
      opts = AuthenticationPlug.init(:load_authenticated_subject)
      user = AccountsFixtures.user_fixture()
      conn = :get |> conn("/") |> put_req_header("authorization", "Bearer " <> user.token)

      # When
      got = AuthenticationPlug.call(conn, opts)

      # Then
      assert TuistWeb.Authentication.current_user(got).id == user.id
      assert TuistWeb.Authentication.authenticated?(got) == true
    end

    test "loads the authenticated project with a legacy token" do
      # Given
      opts = AuthenticationPlug.init(:load_authenticated_subject)
      project = ProjectsFixtures.project_fixture(preload: [:account])
      conn = :get |> conn("/") |> put_req_header("authorization", "Bearer " <> project.token)

      # When
      got =
        conn
        |> Plug.Conn.put_req_header(Headers.cli_version_header(), "4.21.0")
        |> AuthenticationPlug.call(opts)

      # Then
      assert TuistWeb.Authentication.current_project(got).id == project.id
      assert TuistWeb.Authentication.authenticated?(got) == true

      assert TuistWeb.WarningsHeaderPlug.get_warnings(got) ==
               [
                 "The project token you are using is deprecated. Please create a new token by running `tuist projects token create #{project.account.name}/#{project.name}."
               ]
    end

    test "loads the authenticated project with a legacy token without warnings if the version is lower than 4.21.0" do
      # Given
      opts = AuthenticationPlug.init(:load_authenticated_subject)
      project = ProjectsFixtures.project_fixture(preload: [:account])

      conn =
        :get
        |> conn("/")
        |> Plug.Conn.put_req_header(Headers.cli_version_header(), "4.20.0")
        |> put_req_header("authorization", "Bearer " <> project.token)

      # When
      got = AuthenticationPlug.call(conn, opts)

      # Then
      assert TuistWeb.Authentication.current_project(got).id == project.id
      assert TuistWeb.Authentication.authenticated?(got) == true

      assert TuistWeb.WarningsHeaderPlug.get_warnings(got) == []
    end

    test "loads the authenticated project" do
      # Given
      opts = AuthenticationPlug.init(:load_authenticated_subject)
      project = ProjectsFixtures.project_fixture(preload: [:account])
      token = Projects.create_project_token(project)
      conn = :get |> conn("/") |> put_req_header("authorization", "Bearer " <> token)

      # When
      got = AuthenticationPlug.call(conn, opts)

      # Then
      assert TuistWeb.Authentication.current_project(got).id == project.id
      assert TuistWeb.Authentication.authenticated?(got) == true
      assert TuistWeb.WarningsHeaderPlug.get_warnings(got) == []
    end

    test "doesn't load anything if the token is absent" do
      # Given
      opts = AuthenticationPlug.init(:load_authenticated_subject)
      conn = conn(:get, "/")

      # When
      got = AuthenticationPlug.call(conn, opts)

      # Then
      assert TuistWeb.Authentication.current_project(got) == nil
      assert TuistWeb.Authentication.current_user(got) == nil
      assert TuistWeb.Authentication.authenticated?(got) == false
    end

    test "doesn't load anything if the the token is invalid" do
      # Given
      opts = AuthenticationPlug.init(:load_authenticated_subject)
      conn = :get |> conn("/") |> put_req_header("authorization", "Bearer " <> "invalid-token")

      # When
      got = AuthenticationPlug.call(conn, opts)

      # Then
      assert TuistWeb.Authentication.current_project(got) == nil
      assert TuistWeb.Authentication.current_user(got) == nil
      assert TuistWeb.Authentication.authenticated?(got) == false
    end
  end

  describe "require_authentication" do
    test "returns :unauthorized if the user is not authenticated" do
      # Given
      opts = AuthenticationPlug.init({:require_authentication, response_type: :open_api})
      conn = build_conn(:get, "/")

      # # When
      conn = AuthenticationPlug.call(conn, opts)

      # # Then
      assert conn.halted == true

      assert json_response(conn, :unauthorized) == %{
               "message" => "You need to be authenticated to access this resource."
             }
    end

    test "returns mcp bearer challenge with request origin metadata when not authenticated" do
      opts = AuthenticationPlug.init({:require_authentication, response_type: :mcp})

      conn =
        :post
        |> build_conn("/mcp")
        |> Map.put(:scheme, :https)
        |> Map.put(:host, "mcp.tuist.dev")
        |> Map.put(:port, 8443)

      conn = AuthenticationPlug.call(conn, opts)

      assert conn.halted == true
      assert conn.status == 401

      assert get_resp_header(conn, "www-authenticate") == [
               ~s(Bearer realm="tuist-mcp", resource_metadata="https://mcp.tuist.dev:8443/.well-known/oauth-protected-resource/mcp")
             ]

      assert json_response(conn, :unauthorized) == %{
               "auth_md" => "https://mcp.tuist.dev:8443/auth.md",
               "authentication_instructions" =>
                 "Fetch auth_md and follow Tuist's discovery, registration, identity-assertion exchange, and claim-polling flow before falling back to browser Open Authorization.",
               "error" => "invalid_token",
               "error_description" => "Missing or invalid access token."
             }
    end
  end
end
