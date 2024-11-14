defmodule Tuist.Authorization.ChecksTest do
  use Tuist.DataCase, async: true
  use Mimic
  alias Tuist.AccountsFixtures
  alias Tuist.Accounts
  alias Tuist.Authorization.Checks
  alias Tuist.ProjectsFixtures

  setup do
    user = AccountsFixtures.user_fixture(preloads: [:account])
    organization = AccountsFixtures.organization_fixture(preloads: [:account])
    %{user: user, organization: organization}
  end

  describe "user_role" do
    test "returns true for role user when the user is a user of the organization", %{
      organization: organization,
      user: user
    } do
      # Given
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)
      Accounts.add_user_to_organization(user, organization, role: :user)

      # Then
      assert Checks.user_role(user, project, :user) == true
    end

    test "returns true for role user when the user is an admin of the organization", %{
      organization: organization,
      user: user
    } do
      # Given
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)
      Accounts.add_user_to_organization(user, organization, role: :admin)

      # Then
      assert Checks.user_role(user, project, :user) == true
    end

    test "returns true for role user when the user doesn't belong to the organization", %{
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

  describe "matches_authenticated_project" do
    test "returns false when the subject is a user and the object is a project", %{
      organization: organization,
      user: user
    } do
      # Given
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)

      # Then
      assert Checks.matches_authenticated_project(user, project) == false
    end

    test "returns true when the subject and the object are projects and they match", %{
      organization: organization
    } do
      # Given
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)

      # Then
      assert Checks.matches_authenticated_project(project, project) == true
    end

    test "returns false when the subject and the object are projects and they don't match", %{
      organization: organization
    } do
      # Given
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)
      other_project = ProjectsFixtures.project_fixture(account_id: organization.account.id)

      # Then
      assert Checks.matches_authenticated_project(project, other_project) == false
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
end
