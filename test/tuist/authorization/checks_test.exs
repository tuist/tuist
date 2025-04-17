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
    test "returns true when the scopes permit :account_registry_read", %{user: user} do
      # When/Then
      assert Checks.scopes_permit(
               %AuthenticatedAccount{account: user.account, scopes: [:account_registry_read]},
               user,
               :account_registry_read
             ) == true
    end

    test "returns false when the scopes don't permit :account_registry_read", %{user: user} do
      # When/Then
      assert Checks.scopes_permit(
               %AuthenticatedAccount{account: user.account, scopes: [:account_token_create]},
               user,
               :account_registry_read
             ) == false
    end
  end
end
