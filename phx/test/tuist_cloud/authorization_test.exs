defmodule TuistCloud.AuthorizationTest do
  alias TuistCloud.Accounts
  alias TuistCloud.AccountsFixtures
  alias TuistCloud.Authorization
  alias TuistCloud.ProjectsFixtures
  use TuistCloud.DataCase

  test "can.update.account.billing when the subject is the same account being read" do
    # Given
    user = AccountsFixtures.user_fixture()
    account = Accounts.get_account_from_user(user)

    # When
    assert Authorization.can(user, :update, account, :billing) == true
  end

  test "can.update.account.billing when the subject is not the same account being read" do
    # Given
    user = AccountsFixtures.user_fixture()
    user_two = AccountsFixtures.user_fixture()
    account_two = Accounts.get_account_from_user(user_two)


    # When
    assert Authorization.can(user, :update, account_two, :billing) == false
  end

  test "can.update.account.billing when the subject is an admin of the account being read" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, :admin)

    # When
    assert Authorization.can(user, :update, account, :billing) == true
  end

  test "can.update.account.billing when the subject is a user of the account being read" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, :user)

    # When
    assert Authorization.can(user, :update, account, :billing) == false
  end

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
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, :user)

    # When
    assert Authorization.can(user, :read, project, :cache) == true
  end

  test "can.read.project.cache when the subject is a user that doesn't belong to the project organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.can(user, :read, project, :cache) == false
  end

  test "can.write.project.cache when the subject is a user that belongs to the project organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, :user)

    # When
    assert Authorization.can(user, :write, project, :cache) == true
  end

  test "can.write.project.cache when the subject is a user that doesn't belong to the project organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.can(user, :write, project, :cache) == false
  end
end
