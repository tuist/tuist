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
    Accounts.add_user_to_organization(user, organization, role: :user)
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

  describe "get_project_account_by_project_id/1" do
    test "returns nil if a project does not exist" do
      assert nil == Projects.get_project_account_by_project_id(1)
    end

    test "returns project account" do
      # Given
      organization = AccountsFixtures.organization_fixture(name: "tuist")
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      got = Projects.get_all_project_accounts(account)

      # Then
      assert ["#{account.name}/#{project.name}"] == Enum.map(got, & &1.handle)
    end
  end

  describe "delete_project/1" do
    test "deletes a project" do
      # Given
      organization = AccountsFixtures.organization_fixture(name: "tuist")
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      Projects.delete_project(project)

      # Then
      assert nil == Projects.get_project_by_id(project.id)
    end
  end

  describe "get_all_project_accounts/1" do
    test "get all project accounts for an account" do
      # Given
      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      got = Projects.get_all_project_accounts(account)

      # Then
      assert [
               %ProjectAccount{
                 handle: "#{account.name}/#{project.name}",
                 account: account,
                 project: project
               }
             ] == got
    end

    test "get all project accounts for a user" do
      # Given
      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      project_one = ProjectsFixtures.project_fixture(account_id: account.id)
      user = AccountsFixtures.user_fixture()
      user_account = Accounts.get_account_from_user(user)
      Accounts.add_user_to_organization(user, organization, role: :user)
      project_two = ProjectsFixtures.project_fixture(account_id: user_account.id)

      # When
      got = Projects.get_all_project_accounts(user)

      # Then
      assert [
               %ProjectAccount{
                 handle: "#{account.name}/#{project_one.name}",
                 account: account,
                 project: project_one
               },
               %ProjectAccount{
                 handle: "#{user_account.name}/#{project_two.name}",
                 account: user_account,
                 project: project_two
               }
             ] == got
    end
  end
end
