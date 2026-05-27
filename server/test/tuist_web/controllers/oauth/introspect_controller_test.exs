defmodule TuistWeb.Oauth.IntrospectControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Boruta.Oauth.Client
  alias Tuist.Accounts
  alias Tuist.OAuth.Clients
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup :set_mimic_from_context

  setup do
    introspection_client = %Client{
      id: "00000000-0000-0000-0000-000000000001",
      secret: "kura-secret",
      confidential: true,
      supported_grant_types: ["introspect"],
      token_endpoint_auth_methods: ["client_secret_post"]
    }

    stub(Clients, :get_client, fn
      "00000000-0000-0000-0000-000000000001" -> introspection_client
      _ -> nil
    end)

    {:ok, introspection_client: introspection_client}
  end

  describe "POST /oauth2/introspect" do
    test "returns cache grants for user tokens", %{conn: conn, introspection_client: client} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      organization = AccountsFixtures.organization_fixture(name: "acme-org", creator: user)
      Accounts.add_user_to_organization(user, organization, role: :admin)
      project = ProjectsFixtures.project_fixture(account: organization.account)

      conn =
        post(conn, "/oauth2/introspect", %{
          client_id: client.id,
          client_secret: client.secret,
          token: user.token
        })

      assert %{
               "active" => true,
               "principal_kind" => "user",
               "cache_grants" => %{
                 "account" => %{"read" => account_reads, "write" => account_writes},
                 "project" => %{"read" => project_reads, "write" => project_writes}
               }
             } = json_response(conn, 200)

      assert Enum.sort(account_reads) == Enum.sort([user.account.name, organization.account.name])
      assert Enum.sort(account_writes) == Enum.sort([user.account.name, organization.account.name])
      assert project_reads == ["#{organization.account.name}/#{project.name}"]
      assert project_writes == ["#{organization.account.name}/#{project.name}"]
    end

    test "keeps restricted account tokens project-scoped", %{conn: conn, introspection_client: client} do
      organization = AccountsFixtures.organization_fixture(name: "restricted-org")
      project = ProjectsFixtures.project_fixture(account: organization.account)

      {:ok, {_token, token_value}} =
        Accounts.create_account_token(
          %{
            account: organization.account,
            name: "restricted-cache",
            scopes: ["project:cache:read"],
            all_projects: false,
            project_ids: [project.id]
          },
          preload: [:account]
        )

      conn =
        post(conn, "/oauth2/introspect", %{
          client_id: client.id,
          client_secret: client.secret,
          token: token_value
        })

      assert %{
               "active" => true,
               "principal_kind" => "account",
               "scope" => "project:cache:read",
               "cache_grants" => %{
                 "account" => %{"read" => [], "write" => []},
                 "project" => %{"read" => project_reads, "write" => []}
               }
             } = json_response(conn, 200)

      assert project_reads == ["#{organization.account.name}/#{project.name}"]
    end

    test "grants tenant-scoped cache only when account cache scopes are present", %{
      conn: conn,
      introspection_client: client
    } do
      organization = AccountsFixtures.organization_fixture(name: "tenant-org")
      project = ProjectsFixtures.project_fixture(account: organization.account)

      {:ok, {_token, token_value}} =
        Accounts.create_account_token(
          %{
            account: organization.account,
            name: "tenant-cache",
            scopes: ["account:cache:write", "project:cache:read"],
            all_projects: false,
            project_ids: [project.id]
          },
          preload: [:account]
        )

      conn =
        post(conn, "/oauth2/introspect", %{
          client_id: client.id,
          client_secret: client.secret,
          token: token_value
        })

      assert %{
               "active" => true,
               "cache_grants" => %{
                 "account" => %{"read" => account_reads, "write" => account_writes},
                 "project" => %{"read" => project_reads, "write" => []}
               }
             } = json_response(conn, 200)

      assert account_reads == [organization.account.name]
      assert account_writes == [organization.account.name]
      assert project_reads == ["#{organization.account.name}/#{project.name}"]
    end

    test "returns inactive for unknown tokens", %{conn: conn, introspection_client: client} do
      conn =
        post(conn, "/oauth2/introspect", %{
          client_id: client.id,
          client_secret: client.secret,
          token: "unknown-token"
        })

      assert json_response(conn, 200) == %{"active" => false}
    end

    test "rejects invalid introspection clients", %{conn: conn} do
      conn =
        post(conn, "/oauth2/introspect", %{
          client_id: "00000000-0000-0000-0000-000000000001",
          client_secret: "wrong-secret",
          token: "unknown-token"
        })

      assert json_response(conn, 401) == %{
               "error" => "invalid_client",
               "error_description" => "Invalid client_id or client_secret."
             }
    end
  end
end
