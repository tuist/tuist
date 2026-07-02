defmodule Tuist.OAuth.IntrospectionTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Accounts
  alias Tuist.OAuth.Introspection
  alias Tuist.Projects
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  describe "token_response/1" do
    test "returns inactive for unknown tokens" do
      assert Introspection.token_response("unknown-token") == %{active: false}
    end

    test "returns user cache grants for personal and organization accounts" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      organization = AccountsFixtures.organization_fixture(name: "acme-org", creator: user)
      Accounts.add_user_to_organization(user, organization, role: :admin)
      project = ProjectsFixtures.project_fixture(account: organization.account)

      response = Introspection.token_response(user.token)

      assert %{
               active: true,
               iss: issuer,
               principal_kind: "user",
               sub: user_id,
               username: user_email,
               cache_grants: %{
                 "account" => %{"read" => account_reads, "write" => account_writes},
                 "project" => %{"read" => project_reads, "write" => project_writes}
               }
             } = response

      refute Map.has_key?(response, :scope)
      assert issuer == configured_issuer()
      assert user_id == to_string(user.id)
      assert user_email == user.email
      assert Enum.sort(account_reads) == Enum.sort([user.account.name, organization.account.name])
      assert Enum.sort(account_writes) == Enum.sort([user.account.name, organization.account.name])
      assert project_reads == ["#{organization.account.name}/#{project.name}"]
      assert project_writes == ["#{organization.account.name}/#{project.name}"]
    end

    test "keeps project-only account tokens scoped to selected projects" do
      organization = AccountsFixtures.organization_fixture(name: "project-only-org")
      project = ProjectsFixtures.project_fixture(account: organization.account)

      {:ok, {_token, token_value}} =
        Accounts.create_account_token(
          %{
            account: organization.account,
            name: "project-cache",
            scopes: ["project:cache:read"],
            all_projects: false,
            project_ids: [project.id]
          },
          preload: [:account]
        )

      assert %{
               active: true,
               principal_kind: "account",
               scope: "project:cache:read",
               username: "project-only-org",
               cache_grants: %{
                 "account" => %{"read" => [], "write" => []},
                 "project" => %{"read" => project_reads, "write" => []}
               }
             } = Introspection.token_response(token_value)

      assert project_reads == ["#{organization.account.name}/#{project.name}"]
    end

    test "returns account cache grants only when account cache scopes are present" do
      organization = AccountsFixtures.organization_fixture(name: "account-cache-org")
      project = ProjectsFixtures.project_fixture(account: organization.account)

      {:ok, {_token, token_value}} =
        Accounts.create_account_token(
          %{
            account: organization.account,
            name: "account-cache",
            scopes: ["account:cache:write", "project:cache:read"],
            all_projects: false,
            project_ids: [project.id]
          },
          preload: [:account]
        )

      assert %{
               active: true,
               principal_kind: "account",
               scope: "account:cache:write project:cache:read",
               cache_grants: %{
                 "account" => %{
                   "read" => ["account-cache-org"],
                   "write" => ["account-cache-org"]
                 },
                 "project" => %{"read" => project_reads, "write" => []}
               }
             } = Introspection.token_response(token_value)

      assert project_reads == ["#{organization.account.name}/#{project.name}"]
    end

    test "returns project cache grants for project tokens" do
      project = ProjectsFixtures.project_fixture()
      token = Projects.create_project_token(project)

      assert %{
               active: true,
               principal_kind: "project",
               scope: "project:cache:read project:cache:write",
               username: project_handle,
               cache_grants: %{
                 "account" => %{"read" => [], "write" => []},
                 "project" => %{"read" => project_reads, "write" => project_writes}
               }
             } = Introspection.token_response(token)

      assert project_handle == "#{project.account.name}/#{project.name}"
      assert project_reads == [project_handle]
      assert project_writes == [project_handle]
    end
  end

  describe "token_response/2 (tenant-scoped)" do
    test "returns inactive for unknown tokens" do
      account = AccountsFixtures.organization_fixture().account
      assert Introspection.token_response("unknown-token", account) == %{active: false}
    end

    test "constrains grants to the given account and drops other tenants" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      organization = AccountsFixtures.organization_fixture(name: "scoped-org", creator: user)
      Accounts.add_user_to_organization(user, organization, role: :admin)
      project = ProjectsFixtures.project_fixture(account: organization.account)

      assert %{
               active: true,
               principal_kind: "user",
               cache_grants: %{
                 "account" => %{"read" => account_reads, "write" => account_writes},
                 "project" => %{"read" => project_reads, "write" => project_writes}
               }
             } = Introspection.token_response(user.token, organization.account)

      assert account_reads == [organization.account.name]
      assert account_writes == [organization.account.name]
      assert project_reads == ["#{organization.account.name}/#{project.name}"]
      assert project_writes == ["#{organization.account.name}/#{project.name}"]
    end

    test "returns inactive when the token has no grant for the account" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      unrelated = AccountsFixtures.organization_fixture(name: "unrelated-org")

      assert Introspection.token_response(user.token, unrelated.account) == %{active: false}
    end

    test "scopes project tokens to their own account" do
      project = ProjectsFixtures.project_fixture()
      token = Projects.create_project_token(project)
      other = AccountsFixtures.organization_fixture(name: "other-tenant-org")

      assert %{active: true, principal_kind: "project"} =
               Introspection.token_response(token, project.account)

      assert Introspection.token_response(token, other.account) == %{active: false}
    end
  end

  defp configured_issuer do
    :tuist
    |> Application.fetch_env!(Tuist.Guardian)
    |> Keyword.fetch!(:issuer)
  end
end
