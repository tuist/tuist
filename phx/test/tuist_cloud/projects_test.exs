defmodule TuistCloud.ProjectsTest do
  alias TuistCloud.Accounts.ProjectAccount
  alias TuistCloud.AccountsFixtures
  alias TuistCloud.ProjectsFixtures
  alias TuistCloud.Projects
  alias TuistCloud.Accounts
  use TuistCloud.DataCase

  test "returns command average duration" do
    # Given
    organization = AccountsFixtures.organization_fixture(name: "tuist")
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(name: "tuist-project", account_id: account.id)

    # When
    {:ok, got} = Projects.get_project_by_slug("tuist/tuist-project")

    # Then
    assert got == project
  end

  test "returns all projects associated with a user" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, :user)
    organization_two = AccountsFixtures.organization_fixture()
    account_two = Accounts.get_account_from_organization(organization_two)
    ProjectsFixtures.project_fixture(account_id: account_two.id)

    # When
    got = Projects.get_all_project_accounts(user)

    # Then
    assert [
             %ProjectAccount{
               handle: "#{account.name}/#{project.name}",
               account: account,
               project: project
             }
           ] == got
  end

  test "returns missing handle or project name" do
    assert {:error, :missing_handle_or_project_name} == Projects.get_project_by_slug("tuist")
  end
end
