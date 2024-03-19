defmodule TuistCloud.AuthorizationTest do
  alias TuistCloud.Accounts
  alias TuistCloud.AccountsFixtures
  alias TuistCloud.Authorization
  alias TuistCloud.ProjectsFixtures
  use TuistCloud.DataCase

  test "can.read.project.cache when the subject is the same project being read" do
    # Given
    project = ProjectsFixtures.project_fixture()

    # When
    assert Authorization.can(project, :read, project, :cache) == true
  end

  test "can.read.project.cache when the subject is not the same project being read" do
    # Given
    project = ProjectsFixtures.project_fixture()
    another_project = ProjectsFixtures.project_fixture()

    # When
    assert Authorization.can(another_project, :read, project, :cache) == false
  end

  test "can.write.project.cache when the subject is the same project being read" do
    # Given
    project = ProjectsFixtures.project_fixture()

    # When
    assert Authorization.can(project, :write, project, :cache) == true
  end

  test "can.write.project.cache when the subject is not the same project being read" do
    # Given
    project = ProjectsFixtures.project_fixture()
    another_project = ProjectsFixtures.project_fixture()

    # When
    assert Authorization.can(another_project, :write, project, :cache) == false
  end

  test "can.read.project.cache when the subject is a user that belongs to the project organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, :user)

    # When
    assert Authorization.can(user, :read, project, :cache) == true
  end

  test "can.read.project.cache when the subject is a user that doesn't belong to the project organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.can(user, :read, project, :cache) == false
  end

  test "can.write.project.cache when the subject is a user that belongs to the project organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, :user)

    # When
    assert Authorization.can(user, :write, project, :cache) == true
  end

  test "can.write.project.cache when the subject is a user that doesn't belong to the project organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.can(user, :write, project, :cache) == false
  end
end
