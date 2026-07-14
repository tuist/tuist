defmodule Tuist.Authorization.ChecksTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Authorization.Checks
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    organization = AccountsFixtures.organization_fixture(preload: [:account])
    %{user: user, organization: organization}
  end

  describe "user_role" do
    test "returns true for role user when the user is a user of the organization", %{
      organization: organization,
      user: user
    } do
      # Given
      Accounts.add_user_to_organization(user, organization, role: :user)

      # Then
      assert Checks.user_role(user, organization.account, :user) == true
    end

    test "returns false for role admin when the user is a user of the organization", %{
      organization: organization,
      user: user
    } do
      # Given
      Accounts.add_user_to_organization(user, organization, role: :user)

      # Then
      assert Checks.user_role(user, organization.account, :admin) == false
    end

    test "returns true for role user when the user is an admin of the organization", %{
      organization: organization,
      user: user
    } do
      # Given
      Accounts.add_user_to_organization(user, organization, role: :admin)

      # Then
      assert Checks.user_role(user, organization.account, :user) == true
    end

    test "returns false for role user when the user doesn't belong to the organization",
         %{
           user: user
         } do
      # Given
      organization = AccountsFixtures.organization_fixture()

      # Then
      assert Checks.user_role(user, organization.account, :user) == false
    end

    test "returns true for role user when the user is a user of the project's organization", %{
      organization: organization,
      user: user
    } do
      # Given
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)
      Accounts.add_user_to_organization(user, organization, role: :user)

      # Then
      assert Checks.user_role(user, project, :user) == true
    end

    test "returns false for role admin when the user is a user of the project's organization", %{
      organization: organization,
      user: user
    } do
      # Given
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)
      Accounts.add_user_to_organization(user, organization, role: :user)

      # Then
      assert Checks.user_role(user, project, :admin) == false
    end

    test "returns true for role user when the user is an admin of the project's organization", %{
      organization: organization,
      user: user
    } do
      # Given
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)
      Accounts.add_user_to_organization(user, organization, role: :admin)

      # Then
      assert Checks.user_role(user, project, :user) == true
    end

    test "returns false for role user when the user doesn't belong to the project's organization",
         %{
           organization: organization,
           user: user
         } do
      # Given
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)

      # Then
      assert Checks.user_role(user, project, :user) == false
    end

    test "returns false when the subject is a project", %{
      organization: organization,
      user: _
    } do
      # Given
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)

      # Then
      assert Checks.user_role(project, project, :user) == false
    end
  end

  describe "authenticated_as_user/2" do
    test "returns true when the subject is a user", %{
      user: user
    } do
      # When/Then
      assert Checks.authenticated_as_user(user, user) == true
    end

    test "returns false when the subject is a project", %{} do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When/Then
      assert Checks.authenticated_as_user(project, project) == false
    end
  end

  describe "authenticated_as_project/2" do
    test "returns false when the subject is a user", %{
      organization: organization,
      user: user
    } do
      # Given
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)

      # Then
      assert Checks.authenticated_as_project(user, project) == false
    end

    test "returns true when the subject is a project", %{
      organization: organization
    } do
      # Given
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)

      # Then
      assert Checks.authenticated_as_project(project, project) == true
    end
  end

  describe "authenticated_as_account/2" do
    test "returns false when the subject is a user", %{
      organization: organization,
      user: user
    } do
      # When/Then
      assert Checks.authenticated_as_account(user, organization.account) == false
    end

    test "returns true when the subject is an account", %{
      organization: organization
    } do
      # When/Then
      assert Checks.authenticated_as_account(
               %AuthenticatedAccount{account: organization.account, scopes: []},
               organization.account
             ) == true
    end
  end

  describe "projects_match/2" do
    test "returns true when the projects match", %{
      organization: organization
    } do
      # Given
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)

      # Then
      assert Checks.projects_match(project, project) == true
    end

    test "returns false when the projects don't match", %{
      organization: organization
    } do
      # Given
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)
      other_project = ProjectsFixtures.project_fixture(account_id: organization.account.id)

      # Then
      assert Checks.projects_match(project, other_project) == false
    end
  end

  describe "public_project" do
    test "returns true when the object is a project and is public", %{
      organization: organization,
      user: user
    } do
      # Given
      project =
        ProjectsFixtures.project_fixture(account_id: organization.account.id, visibility: :public)

      # Then
      assert Checks.public_project(user, project) == true
    end

    test "returns false when the object is a project and is not public", %{
      organization: organization,
      user: user
    } do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          account_id: organization.account.id,
          visibility: :private
        )

      # Then
      assert Checks.public_project(user, project) == false
    end
  end

  describe "accounts_match/2" do
    test "returns true when the accounts match", %{
      organization: organization
    } do
      # Given
      account = organization.account

      # Then
      assert Checks.accounts_match(%AuthenticatedAccount{account: account, scopes: []}, account) ==
               true
    end

    test "returns false when the accounts don't match", %{
      organization: organization
    } do
      # Given
      account = organization.account
      other_account = AccountsFixtures.user_fixture(preload: [:account]).account

      # Then
      assert Checks.accounts_match(
               %AuthenticatedAccount{account: account, scopes: []},
               other_account
             ) == false
    end

    test "returns true when the project accounts match", %{
      organization: organization
    } do
      # Given
      account = organization.account
      project = ProjectsFixtures.project_fixture(account_id: account.id, preload: [:account])

      # Then
      assert Checks.accounts_match(project, account) ==
               true
    end

    test "returns false when the project accounts don't match", %{
      organization: organization
    } do
      # Given
      account = organization.account
      project = ProjectsFixtures.project_fixture(preload: [:account])

      # Then
      assert Checks.accounts_match(
               project,
               account
             ) == false
    end
  end

  describe "scopes_permit/3" do
    test "returns true when the scopes contain the required scope", %{user: user} do
      # When/Then
      assert Checks.scopes_permit(
               %AuthenticatedAccount{account: user.account, scopes: ["project:cache:read"]},
               user.account,
               "project:cache:read"
             ) == true
    end

    test "returns false when the scopes don't contain the required scope", %{user: user} do
      # When/Then
      assert Checks.scopes_permit(
               %AuthenticatedAccount{account: user.account, scopes: ["project:cache:read"]},
               user.account,
               "project:cache:write"
             ) == false
    end

    test "returns true for project when scopes match and all_projects is true", %{organization: organization} do
      # Given
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)

      # When/Then
      assert Checks.scopes_permit(
               %AuthenticatedAccount{
                 account: organization.account,
                 scopes: ["project:bundles:read"],
                 all_projects: true
               },
               project,
               "project:bundles:read"
             ) == true
    end

    test "returns false for project when scopes match but project belongs to another account", %{
      organization: organization
    } do
      project = ProjectsFixtures.project_fixture()

      assert Checks.scopes_permit(
               %AuthenticatedAccount{
                 account: organization.account,
                 scopes: ["project:bundles:read"],
                 all_projects: true
               },
               project,
               "project:bundles:read"
             ) == false
    end

    test "returns true for project when scopes match and project is in project_ids", %{organization: organization} do
      # Given
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)

      # When/Then
      assert Checks.scopes_permit(
               %AuthenticatedAccount{
                 account: organization.account,
                 scopes: ["project:bundles:read"],
                 all_projects: false,
                 project_ids: [project.id]
               },
               project,
               "project:bundles:read"
             ) == true
    end

    test "returns false for project when scopes match but project is not in project_ids", %{organization: organization} do
      # Given
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)
      other_project = ProjectsFixtures.project_fixture(account_id: organization.account.id)

      # When/Then
      assert Checks.scopes_permit(
               %AuthenticatedAccount{
                 account: organization.account,
                 scopes: ["project:bundles:read"],
                 all_projects: false,
                 project_ids: [other_project.id]
               },
               project,
               "project:bundles:read"
             ) == false
    end

    test "returns false for project when scopes don't match even with all_projects true", %{organization: organization} do
      # Given
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)

      # When/Then
      assert Checks.scopes_permit(
               %AuthenticatedAccount{
                 account: organization.account,
                 scopes: ["project:cache:read"],
                 all_projects: true
               },
               project,
               "project:bundles:read"
             ) == false
    end

    test "expands 'ci' scope to grant project:cache:write permission", %{organization: organization} do
      # Given
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)

      # When/Then
      assert Checks.scopes_permit(
               %AuthenticatedAccount{
                 account: organization.account,
                 scopes: ["ci"],
                 all_projects: true
               },
               project,
               "project:cache:write"
             ) == true
    end

    test "expands 'ci' scope to grant account:cache:write permission", %{organization: organization} do
      # When/Then
      assert Checks.scopes_permit(
               %AuthenticatedAccount{
                 account: organization.account,
                 scopes: ["ci"],
                 all_projects: true
               },
               organization.account,
               "account:cache:write"
             ) == true
    end

    test "expands 'ci' scope to grant project:runs:write permission", %{organization: organization} do
      # Given
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)

      # When/Then
      assert Checks.scopes_permit(
               %AuthenticatedAccount{
                 account: organization.account,
                 scopes: ["ci"],
                 all_projects: true
               },
               project,
               "project:runs:write"
             ) == true
    end

    test "expands 'ci' scope to grant project:bundles:write permission", %{organization: organization} do
      # Given
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)

      # When/Then
      assert Checks.scopes_permit(
               %AuthenticatedAccount{
                 account: organization.account,
                 scopes: ["ci"],
                 all_projects: true
               },
               project,
               "project:bundles:write"
             ) == true
    end

    test "expands 'ci' scope to grant project:previews:write permission", %{organization: organization} do
      # Given
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)

      # When/Then
      assert Checks.scopes_permit(
               %AuthenticatedAccount{
                 account: organization.account,
                 scopes: ["ci"],
                 all_projects: true
               },
               project,
               "project:previews:write"
             ) == true
    end

    test "'ci' scope does not grant permissions outside its group", %{user: user} do
      # When/Then
      assert Checks.scopes_permit(
               %AuthenticatedAccount{account: user.account, scopes: ["ci"]},
               user.account,
               "account:members:read"
             ) == false
    end

    test "'ci' scope respects project_ids restriction", %{organization: organization} do
      # Given
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)
      other_project = ProjectsFixtures.project_fixture(account_id: organization.account.id)

      # When/Then - should have access to project in project_ids
      assert Checks.scopes_permit(
               %AuthenticatedAccount{
                 account: organization.account,
                 scopes: ["ci"],
                 all_projects: false,
                 project_ids: [project.id]
               },
               project,
               "project:cache:write"
             ) == true

      # When/Then - should not have access to project not in project_ids
      assert Checks.scopes_permit(
               %AuthenticatedAccount{
                 account: organization.account,
                 scopes: ["ci"],
                 all_projects: false,
                 project_ids: [other_project.id]
               },
               project,
               "project:cache:write"
             ) == false
    end
  end

  describe "internal_ops_access/2 (the static /ops panel gate)" do
    setup do
      stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
      :ok
    end

    test "returns true for an operator-domain user signed in with Google" do
      operator =
        AccountsFixtures.user_fixture(
          email: "operator-#{TuistTestSupport.Utilities.unique_integer()}@tuist.dev",
          preload: [:account]
        )

      AccountsFixtures.oauth2_identity_fixture(user: operator, provider: :google)

      assert Checks.internal_ops_access(operator, nil) == true
      assert Checks.internal_ops_access(operator, :ops) == true
    end

    test "returns true on a self-hosted instance for an operator-domain user (no Google check)" do
      stub(Tuist.Environment, :tuist_hosted?, fn -> false end)

      operator =
        AccountsFixtures.user_fixture(
          email: "operator-#{TuistTestSupport.Utilities.unique_integer()}@tuist.dev",
          preload: [:account]
        )

      assert Checks.internal_ops_access(operator, nil) == true
    end

    test "returns false for a non-operator-domain user", %{user: user} do
      # Default fixture users are @tuist.io, not the operator domain.
      assert Checks.internal_ops_access(user, nil) == false
    end

    test "returns false for non-user subjects" do
      assert Checks.internal_ops_access(nil, nil) == false
      assert Checks.internal_ops_access("string", nil) == false
    end
  end

  describe "ops_access/2 (grant-based)" do
    setup %{organization: organization} do
      stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)
      %{project: project, account: organization.account, user: operator_user()}
    end

    test "true with a read grant covering the project's account", %{user: user, project: project} do
      user = put_grant(user, project.account_id, :read)
      assert Checks.ops_access(user, project) == true
    end

    test "false when the holder is not a Tuist operator", %{project: project} do
      # A regular customer session carrying a grant (e.g. a replayed token)
      # authorizes nothing, even though the grant's subject matches them.
      customer = AccountsFixtures.user_fixture(preload: [:account])
      user = put_grant(customer, project.account_id, :read)
      assert Checks.ops_access(user, project) == false
    end

    test "false when the grant subject is a different operator", %{user: user, project: project} do
      grant = %{put_grant(user, project.account_id, :read).operator_grant | sub: "someone-else@tuist.dev"}
      assert Checks.ops_access(%{user | operator_grant: grant}, project) == false
    end

    test "true with an admin grant (admin satisfies read)", %{user: user, project: project} do
      user = put_grant(user, project.account_id, :admin)
      assert Checks.ops_access(user, project) == true
    end

    test "true when the object is the Account itself", %{user: user, account: account} do
      user = put_grant(user, account.id, :read)
      assert Checks.ops_access(user, account) == true
    end

    test "resolves a wrapped project object", %{user: user, project: project} do
      user = put_grant(user, project.account_id, :read)
      assert Checks.ops_access(user, %{project: project}) == true
    end

    test "false when the grant is for a different account", %{user: user, project: project} do
      user = put_grant(user, project.account_id + 1, :read)
      assert Checks.ops_access(user, project) == false
    end

    test "false when the grant is expired", %{user: user, project: project} do
      user = put_grant(user, project.account_id, :read, exp: System.system_time(:second) - 1)
      assert Checks.ops_access(user, project) == false
    end

    test "false without a grant", %{user: user, project: project} do
      assert Checks.ops_access(user, project) == false
    end

    test "false for an unknown object shape", %{user: user, project: project} do
      user = put_grant(user, project.account_id, :read)
      assert Checks.ops_access(user, :something) == false
    end

    test "false for non-user subjects", %{project: project} do
      authenticated_account = %AuthenticatedAccount{account: project.account, scopes: []}
      assert Checks.ops_access(project, nil) == false
      assert Checks.ops_access(authenticated_account, nil) == false
      assert Checks.ops_access("string", nil) == false
    end
  end

  describe "ops_write_access/2 (admin-tier grant only)" do
    setup %{organization: organization} do
      stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)
      %{project: project, user: operator_user()}
    end

    test "true with an admin grant covering the account", %{user: user, project: project} do
      user = put_grant(user, project.account_id, :admin)
      assert Checks.ops_write_access(user, project) == true
    end

    test "false with only a read grant", %{user: user, project: project} do
      user = put_grant(user, project.account_id, :read)
      assert Checks.ops_write_access(user, project) == false
    end

    test "false without a grant", %{user: user, project: project} do
      assert Checks.ops_write_access(user, project) == false
    end
  end

  defp operator_user do
    user =
      AccountsFixtures.user_fixture(
        email: "operator-#{TuistTestSupport.Utilities.unique_integer()}@tuist.dev",
        preload: [:account]
      )

    AccountsFixtures.oauth2_identity_fixture(user: user, provider: :google)
    user
  end

  defp put_grant(user, account_id, tier, opts \\ []) do
    now = System.system_time(:second)

    grant = %{
      tier: tier,
      account_id: account_id,
      account_handle: "acme",
      sub: user.email,
      reason: "investigating",
      jti: "1",
      iat: now,
      exp: Keyword.get(opts, :exp, now + 600)
    }

    %{user | operator_grant: grant}
  end
end
