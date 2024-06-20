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
    Accounts.add_user_to_organization(user, organization, role: :admin)

    # When
    assert Authorization.can(user, :update, account, :billing) == true
  end

  test "can.update.account.billing when the subject is a user of the account being read" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :user)

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

  test "can.create.project.cache when the subject is the same project being read" do
    # Given
    project = ProjectsFixtures.project_fixture()

    # When
    assert Authorization.can(project, :create, project, :cache) == true
  end

  test "can.create.project.cache when the subject is not the same project being read" do
    # Given
    project = ProjectsFixtures.project_fixture()
    another_project = ProjectsFixtures.project_fixture()

    # When
    assert Authorization.can(another_project, :create, project, :cache) == false
  end

  test "can.update.project.cache when the subject is the same project being read" do
    # Given
    project = ProjectsFixtures.project_fixture()

    # When
    assert Authorization.can(project, :update, project, :cache) == true
  end

  test "can.update.project.cache when the subject is not the same project being read" do
    # Given
    project = ProjectsFixtures.project_fixture()
    another_project = ProjectsFixtures.project_fixture()

    # When
    assert Authorization.can(another_project, :update, project, :cache) == false
  end

  test "can.read.project.cache when the subject is a user that belongs to the project organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)

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

  test "can.create.project.cache when the subject is a user that belongs to the project organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.can(user, :create, project, :cache) == true
  end

  test "can.create.project.cache when the subject is a user that doesn't belong to the project organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.can(user, :create, project, :cache) == false
  end

  test "can.update.project.cache when the subject is a user that belongs to the project organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.can(user, :update, project, :cache) == true
  end

  test "can.update.project.cache when the subject is a user that doesn't belong to the project organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.can(user, :update, project, :cache) == false
  end

  test "can.create.project.command_event when the subject is a user that belongs to the project organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.can(user, :create, project, :command_event, is_ci: false) == true
  end

  test "can.create.project.command_event when the subject is a user that belongs to the project organization and is ci" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.can(user, :create, project, :command_event, is_ci: true) == false
  end

  test "can.create.project.command_event when the subject is a user that doesn't belong to the project organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.can(user, :create, project, :command_event, is_ci: false) == false
  end

  test "can.create.project.command_event when the subject is the same project being read and is not ci" do
    # Given
    project = ProjectsFixtures.project_fixture()

    # When
    assert Authorization.can(project, :create, project, :command_event, is_ci: false) == false
  end

  test "can.create.project.command_event when the subject is the same project being read" do
    # Given
    project = ProjectsFixtures.project_fixture()

    # When
    assert Authorization.can(project, :create, project, :command_event, is_ci: true) == true
  end

  test "can.create.project.command_event when the subject is not the same project being read" do
    # Given
    project = ProjectsFixtures.project_fixture()
    another_project = ProjectsFixtures.project_fixture()

    # When
    assert Authorization.can(another_project, :create, project, :command_event, is_ci: true) ==
             false
  end

  test "can.update.project.command_event when the subject is a user that belongs to the project organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.can(user, :update, project, :command_event, is_ci: false) == true
  end

  test "can.update.project.command_event when the subject is a user that belongs to the project organization and is ci" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.can(user, :update, project, :command_event, is_ci: true) == false
  end

  test "can.update.project.command_event when the subject is a user that doesn't belong to the project organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.can(user, :update, project, :command_event, is_ci: false) == false
  end

  test "can.update.project.command_event when the subject is the same project being read and is not ci" do
    # Given
    project = ProjectsFixtures.project_fixture()

    # When
    assert Authorization.can(project, :update, project, :command_event, is_ci: false) == false
  end

  test "can.update.project.command_event when the subject is the same project being read" do
    # Given
    project = ProjectsFixtures.project_fixture()

    # When
    assert Authorization.can(project, :update, project, :command_event, is_ci: true) == true
  end

  test "can.update.project.command_event when the subject is not the same project being read" do
    # Given
    project = ProjectsFixtures.project_fixture()
    another_project = ProjectsFixtures.project_fixture()

    # When
    assert Authorization.can(another_project, :update, project, :command_event, is_ci: true) ==
             false
  end

  test "can.read.project.command_event when the subject is a user that belongs to the project organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.can(user, :read, project, :command_event) == true
  end

  test "can.read.project.command_event when the subject is a user that doesn't belong to the project organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.can(user, :read, project, :command_event) == false
  end

  test "can.read.project.command_event when the subject is a user that doesn't belong to the project organization and the project's visibility is public" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id, visibility: :public)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.can(user, :read, project, :command_event) == true
  end

  test "can.read.project.command_event when the subject is an anonymous user and project's visibility is private" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id, visibility: :private)

    # When
    assert Authorization.can(nil, :read, project, :command_event) == false
  end

  test "can.read.project.command_event when the subject is an anonymous user and project's visibility is public" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id, visibility: :public)

    # When
    assert Authorization.can(nil, :read, project, :command_event) == true
  end

  test "can.create.account.project when the subject is a user that belongs to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization)

    # When
    assert Authorization.can(user, :create, account, :project) == true
  end

  test "can.create.account.project when the subject is a user that doesn't belong to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.can(user, :create, account, :project) == false
  end

  test "can.update.account.project when the subject is a user that belongs to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization)

    # When
    assert Authorization.can(user, :update, account, :project) == false
  end

  test "can.update.account.project when the subject is a user that is admin of an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :admin)

    # When
    assert Authorization.can(user, :update, account, :project) == true
  end

  test "can.update.account.project when the subject is a user that doesn't belong to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.can(user, :update, account, :project) == false
  end

  test "can.read.account.project when the subject is a user that belongs to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization)

    # When
    assert Authorization.can(user, :read, account, :project) == true
  end

  test "can.read.account.project when the subject is a user that doesn't belong to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.can(user, :read, account, :project) == false
  end

  test "can.read.project.dashboard when the subject is a user that belongs to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)

    # When
    assert Authorization.can(user, :read, project, :dashboard) == true
  end

  test "can.read.project.dashboard when the subject is a user that doesn't belong to an organization" do
    # Given
    user = AccountsFixtures.user_fixture()
    project = ProjectsFixtures.project_fixture()

    # When
    assert Authorization.can(user, :read, project, :dashboard) == false
  end

  test "can.read.project.dashboard when the subject is a user and a project is public" do
    # Given
    user = AccountsFixtures.user_fixture()
    project = ProjectsFixtures.project_fixture(visibility: :public)

    # When
    assert Authorization.can(user, :read, project, :dashboard) == true
  end

  test "can.read.project.dashboard when the subject is an anonymous user and a project is private" do
    # Given
    project = ProjectsFixtures.project_fixture(visibility: :private)

    # When
    assert Authorization.can(nil, :read, project, :dashboard) == false
  end

  test "can.read.project.dashboard when the subject is an anonymous user and a project is public" do
    # Given
    project = ProjectsFixtures.project_fixture(visibility: :public)

    # When
    assert Authorization.can(nil, :read, project, :dashboard) == true
  end

  test "can.delete.account.project when the subject is a user that belongs to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization)

    # When
    assert Authorization.can(user, :delete, account, :project) == false
  end

  test "can.delete.account.project when the subject is a user that is admin of an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :admin)

    # When
    assert Authorization.can(user, :delete, account, :project) == true
  end

  test "can.delete.account.project when the subject is a user that doesn't belong to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.can(user, :delete, account, :project) == false
  end

  test "can.read.account.organization when the subject is a user that is admin of an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :admin)

    # When
    assert Authorization.can(user, :read, account, :organization) == true
  end

  test "can.read.account.organization when the subject is a user that belongs to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.can(user, :read, account, :organization) == true
  end

  test "can.read.account.organization when the subject is a user that doesn't belong to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.can(user, :read, account, :organization) == false
  end

  test "can.read.account.oragnization_usage when the subject is a user that is admin of an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :admin)

    # When
    assert Authorization.can(user, :read, account, :organization_usage) == true
  end

  test "can.read.account.oragnization_usage when the subject is a user that belongs to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.can(user, :read, account, :organization_usage) == true
  end

  test "can.read.account.oragnization_usage when the subject is a user that doesn't belong to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.can(user, :read, account, :organization_usage) == false
  end

  test "can.update.account.organization when the subject is a user that is admin of an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :admin)

    # When
    assert Authorization.can(user, :update, account, :organization) == true
  end

  test "can.update.account.organization when the subject is a user that belongs to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.can(user, :update, account, :organization) == false
  end

  test "can.update.account.organization when the subject is a user that doesn't belong to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.can(user, :update, account, :organization) == false
  end

  test "can.delete.account.organization when the subject is a user that is admin of an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :admin)

    # When
    assert Authorization.can(user, :delete, account, :organization) == true
  end

  test "can.delete.account.organization when the subject is a user that belongs to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.can(user, :delete, account, :organization) == false
  end

  test "can.delete.account.organization when the subject is a user that doesn't belong to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.can(user, :delete, account, :organization) == false
  end

  test "can.create.account.invitation when the subject is a user that is admin of an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :admin)

    # When
    assert Authorization.can(user, :create, account, :invitation) == true
  end

  test "can.create.account.invitation when the subject is a user that belongs to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.can(user, :create, account, :invitation) == false
  end

  test "can.create.account.invitation when the subject is a user that doesn't belong to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.can(user, :create, account, :invitation) == false
  end

  test "can.delete.account.invitation when the subject is a user that is admin of an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :admin)

    # When
    assert Authorization.can(user, :delete, account, :invitation) == true
  end

  test "can.delete.account.invitation when the subject is a user that belongs to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.can(user, :delete, account, :invitation) == false
  end

  test "can.delete.account.invitation when the subject is a user that doesn't belong to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.can(user, :delete, account, :invitation) == false
  end

  test "can.delete.account.member when the subject is a user that is admin of an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :admin)

    # When
    assert Authorization.can(user, :delete, account, :member) == true
  end

  test "can.delete.account.member when the subject is a user that belongs to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.can(user, :delete, account, :member) == false
  end

  test "can.delete.account.member when the subject is a user that doesn't belong to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.can(user, :delete, account, :member) == false
  end

  test "can.update.account.member when the subject is a user that is admin of an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :admin)

    # When
    assert Authorization.can(user, :update, account, :member) == true
  end

  test "can.update.account.member when the subject is a user that belongs to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.can(user, :update, account, :member) == false
  end

  test "can.update.account.member when the subject is a user that doesn't belong to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.can(user, :update, account, :member) == false
  end
end
