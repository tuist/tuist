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
               %AuthenticatedAccount{account: user.account, scopes: ["account:registry:read"]},
               user.account,
               "account:registry:read"
             ) == true
    end

    test "returns false when the scopes don't contain the required scope", %{user: user} do
      # When/Then
      assert Checks.scopes_permit(
               %AuthenticatedAccount{account: user.account, scopes: ["project:cache:read"]},
               user.account,
               "account:registry:read"
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
               "account:registry:read"
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

  describe "ops_access/2" do
    test "returns true when user is in ops_user_handles", %{user: user} do
      # Given
      expect(Tuist.Environment, :ops_user_handles, fn -> [user.account.name] end)

      # When/Then
      assert Checks.ops_access(user, nil) == true
    end

    test "returns false when user is not in ops_user_handles", %{user: user} do
      # Given
      expect(Tuist.Environment, :ops_user_handles, fn -> ["other_user"] end)

      # When/Then
      assert Checks.ops_access(user, nil) == false
    end

    test "returns false when user is nil" do
      # When/Then
      assert Checks.ops_access(nil, nil) == false
    end

    test "returns false for non-user subjects", %{organization: organization} do
      # Given
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)
      authenticated_account = %AuthenticatedAccount{account: organization.account, scopes: []}

      # When/Then
      assert Checks.ops_access(project, nil) == false
      assert Checks.ops_access(authenticated_account, nil) == false
      assert Checks.ops_access("string", nil) == false
    end
  end
end
