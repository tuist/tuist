defmodule Tuist.AuthorizationTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Authorization
  alias Tuist.Environment
  alias Tuist.VCS
  alias Tuist.VCS.Repositories.Permission
  alias Tuist.VCS.Repositories.Repository
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  test "can.update.account.billing when the subject is the same account being read and it's on-premise" do
    # Given
    user = AccountsFixtures.user_fixture()
    account = Accounts.get_account_from_user(user)
    stub(Environment, :tuist_hosted?, fn -> false end)

    # When
    assert Authorization.can(user, :update, account, :billing) == false
  end

  test "can.update.account.billing when the subject is the same account being read and it's not on-premise" do
    # Given
    user = AccountsFixtures.user_fixture()
    account = Accounts.get_account_from_user(user)
    stub(Environment, :tuist_hosted?, fn -> true end)

    # When
    assert Authorization.can(user, :update, account, :billing) == true
  end

  test "can.update.account.billing when the subject is not the same account being read and it's on-premise" do
    # Given
    user = AccountsFixtures.user_fixture()
    user_two = AccountsFixtures.user_fixture()
    account_two = Accounts.get_account_from_user(user_two)
    stub(Environment, :tuist_hosted?, fn -> false end)

    # When
    assert Authorization.can(user, :update, account_two, :billing) == false
  end

  test "can.update.account.billing when the subject is not the same account being read and it's not on-premise" do
    # Given
    user = AccountsFixtures.user_fixture()
    user_two = AccountsFixtures.user_fixture()
    account_two = Accounts.get_account_from_user(user_two)
    stub(Environment, :tuist_hosted?, fn -> true end)

    # When
    assert Authorization.can(user, :update, account_two, :billing) == false
  end

  test "can.update.account.billing when the subject is an admin of the account being read and it's on-premise" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :admin)
    stub(Environment, :tuist_hosted?, fn -> false end)

    # When
    assert Authorization.can(user, :update, account, :billing) == false
  end

  test "can.update.account.billing when the subject is an admin of the account being read and it's not on-premise" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :admin)
    stub(Environment, :tuist_hosted?, fn -> true end)

    # When
    assert Authorization.can(user, :update, account, :billing) == true
  end

  test "can.update.account.billing when the subject is an admin of the account being read, it's not on-premise, and the account has an open_source plan" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :admin)
    BillingFixtures.subscription_fixture(plan: :open_source, account_id: account.id)
    stub(Environment, :tuist_hosted?, fn -> true end)

    # When
    assert Authorization.can(user, :update, account, :billing) == false
  end

  test "can.update.account.billing when the subject is a user of the account being read and it's on-premise" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :user)
    stub(Environment, :tuist_hosted?, fn -> false end)

    # When
    assert Authorization.can(user, :update, account, :billing) == false
  end

  test "can.update.account.billing when the subject is a user of the account being read and it's not on-premise" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :user)
    stub(Environment, :tuist_hosted?, fn -> true end)

    # When
    assert Authorization.can(user, :update, account, :billing) == false
  end

  test "can.read.project.cache when the subject is the same project being read" do
    # Given
    project = ProjectsFixtures.project_fixture()

    # When
    assert Authorization.can?(:project_cache_read, project, project) == true
  end

  test "can.read.project.cache when the subject is not the same project being read" do
    # Given
    project = ProjectsFixtures.project_fixture()
    another_project = ProjectsFixtures.project_fixture()

    # When
    assert Authorization.can?(:project_cache_read, another_project, project) == false
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
    assert Authorization.can?(:project_cache_read, user, project) == true
  end

  test "can.read.project.cache when the subject is a user that doesn't belong to the project organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.can?(:project_cache_read, user, project) == false
  end

  test "can.read.project.cache when the subject is a user that doesn't belong to the project organization and the project is public" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id, visibility: :public)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.can?(:project_cache_read, user, project) == true
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

  test "can.access.project.url returns true when the project is public and the subject is nil" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id, visibility: :public)

    # When/Then
    assert Authorization.can(nil, :access, project, :url) == true
  end

  test "can.access.project.url returns true when the project is public and the subject is not nil" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id, visibility: :public)
    user = AccountsFixtures.user_fixture()

    # When/Then
    assert Authorization.can(user, :access, project, :url) == true
  end

  test "can.access.project.url returns false when the project is private and the subject is nil" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id, visibility: :private)

    # When/Then
    assert Authorization.can(nil, :access, project, :url) == false
  end

  test "can.access.project.url returns true when the project is private and the subject is user of the organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)

    project =
      ProjectsFixtures.project_fixture(
        account_id: account.id,
        visibility: :private,
        preload: [:account]
      )

    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When/Then
    assert Authorization.can(user, :access, project, :url) == true
  end

  test "can.access.project.url returns true when the project is private and the subject is admin of the organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)

    project =
      ProjectsFixtures.project_fixture(
        account_id: account.id,
        visibility: :private,
        preload: [:account]
      )

    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :admin)

    # When/Then
    assert Authorization.can(user, :access, project, :url) == true
  end

  test "can.access.project.url returns true when the project is private and the subject doesn't belong to the organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)

    project =
      ProjectsFixtures.project_fixture(
        account_id: account.id,
        visibility: :private,
        preload: [:account]
      )

    user = AccountsFixtures.user_fixture()

    # When/Then
    assert Authorization.can(user, :access, project, :url) == false
  end

  test "can.read.command_event when the subject is a user that belongs to the command event's project organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)
    command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)

    # When
    assert Authorization.can(user, :read, command_event) == true
  end

  test "can.read.command_event when the subject is a user that doesn't belong to the command event's project organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()
    command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)

    # When
    assert Authorization.can(user, :read, command_event) == false
  end

  test "can.read.command_event when the subject is a user that doesn't belong to the command event's project organization and the project's visibility is public" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id, visibility: :public)
    user = AccountsFixtures.user_fixture()
    command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)

    # When
    assert Authorization.can(user, :read, command_event) == true
  end

  test "can.read.command_event when the subject is an anonymous user and the command event's project's visibility is private" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id, visibility: :private)
    command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)

    # When
    assert Authorization.can(nil, :read, command_event) == false
  end

  test "can.read.command_event when the subject is an anonymous user and the command event's project's visibility is public" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id, visibility: :public)
    command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)

    # When
    assert Authorization.can(nil, :read, command_event) == true
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

  test "can.update.project.repository when the subject is a user that doesn't belong to the project organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()

    repository = %Repository{
      full_handle: "tuist/tuist",
      provider: :github,
      default_branch: "main"
    }

    # When
    assert Authorization.can(user, :update, project, %{repository: repository}) == false
  end

  test "can.update.project.repository when the subject is a user that is a user of the project organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization)

    repository = %Repository{
      full_handle: "tuist/tuist",
      provider: :github,
      default_branch: "main"
    }

    # When
    assert Authorization.can(user, :update, project, %{repository: repository}) == false
  end

  test "can.update.project.repository when the subject is a user that is an admin of the project organization and has write repository permission" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :admin)

    stub(VCS, :get_user_permission, fn _ ->
      {:ok, %Permission{permission: "write"}}
    end)

    repository = %Repository{
      full_handle: "tuist/tuist",
      provider: :github,
      default_branch: "main"
    }

    # When
    assert Authorization.can(user, :update, project, %{repository: repository}) == true
  end

  test "can.update.project.repository when the subject is a user that is an admin of the project organization and has admin repository permission" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :admin)

    stub(VCS, :get_user_permission, fn _ ->
      {:ok, %Permission{permission: "admin"}}
    end)

    repository = %Repository{
      full_handle: "tuist/tuist",
      provider: :github,
      default_branch: "main"
    }

    # When
    assert Authorization.can(user, :update, project, %{repository: repository}) == true
  end

  test "can.update.project.repository when the subject is a user that is an admin of the project organization and has read repository permission" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :admin)

    stub(VCS, :get_user_permission, fn _ ->
      {:ok, %Permission{permission: "read"}}
    end)

    repository = %Repository{
      full_handle: "tuist/tuist",
      provider: :github,
      default_branch: "main"
    }

    # When
    assert Authorization.can(user, :update, project, %{repository: repository}) == false
  end

  test "can.update.project.repository when the subject is a user that is an admin of the project organization and the permission was not found" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :admin)

    stub(VCS, :get_user_permission, fn _ ->
      {:error, :not_found}
    end)

    repository = %Repository{
      full_handle: "tuist/tuist",
      provider: :github,
      default_branch: "main"
    }

    # When
    assert Authorization.can(user, :update, project, %{repository: repository}) == false
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

  test "can.read.account.projects when the subject is a user that is admin of an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :admin)

    # When
    assert Authorization.can(user, :read, account, :projects) == true
  end

  test "can.read.account.projects when the subject is a user that belongs to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.can(user, :read, account, :projects) == true
  end

  test "can.read.account.projects when the subject is a user that doesn't belong to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.can(user, :read, account, :projects) == false
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

  test "can.read.account.billing when the subject is a user that belongs to the organization and it's on-premise" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)
    stub(Environment, :tuist_hosted?, fn -> false end)

    # When
    assert Authorization.can(user, :read, account, :billing) == false
  end

  test "can.read.account.billing when the subject is a user that belongs to the organization and it's not on-premise" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)
    stub(Environment, :tuist_hosted?, fn -> true end)

    # When
    assert Authorization.can(user, :read, account, :billing) == false
  end

  test "can.read.account.billing when the subject is a user that doesn't belong to an organization and it's on-premise" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    stub(Environment, :tuist_hosted?, fn -> false end)

    # When
    assert Authorization.can(user, :read, account, :billing) == false
  end

  test "can.read.account.billing when the subject is a user that doesn't belong to an organization and it's not on-premise" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    stub(Environment, :tuist_hosted?, fn -> true end)

    # When
    assert Authorization.can(user, :read, account, :billing) == false
  end

  test "can.read.account.billing when the subject is a user is admin of the organization and it's on-premise" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :admin)
    stub(Environment, :tuist_hosted?, fn -> false end)

    # When
    assert Authorization.can(user, :read, account, :billing) == false
  end

  test "can.read.account.billing when the subject is a user is admin of the organization and it's not on-premise" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :admin)
    stub(Environment, :tuist_hosted?, fn -> true end)

    # When
    assert Authorization.can(user, :read, account, :billing) == true
  end

  test "can.read.account.billing when the subject is interacting with its account and it's on-premise" do
    # Given
    user = AccountsFixtures.user_fixture(preload: [:account])
    stub(Environment, :tuist_hosted?, fn -> false end)

    # When
    assert Authorization.can(user, :read, user.account, :billing) == false
  end

  test "can.read.account.billing when the subject is interacting with its account and it's not on-premise" do
    # Given
    user = AccountsFixtures.user_fixture(preload: [:account])
    stub(Environment, :tuist_hosted?, fn -> true end)

    # When
    assert Authorization.can(user, :read, user.account, :billing) == true
  end

  test "can.read.account.billing when the subject is interacting with its account and the account has an open_source subscription" do
    # Given
    user = AccountsFixtures.user_fixture(preload: [:account])

    BillingFixtures.subscription_fixture(account_id: user.account.id, plan: :open_source)

    stub(Environment, :tuist_hosted?, fn -> true end)

    # When
    assert Authorization.can(user, :read, user.account, :billing) == false
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

  test "can.create.account.token when the subject is the same account being read" do
    # Given
    user = AccountsFixtures.user_fixture()
    account = Accounts.get_account_from_user(user)

    # When
    assert Authorization.can(user, :create, account, :token) == true
  end

  test "can.create.account.token when the subject is not the same account being read" do
    # Given
    user = AccountsFixtures.user_fixture()
    user_two = AccountsFixtures.user_fixture()
    account_two = Accounts.get_account_from_user(user_two)

    # When
    assert Authorization.can(user, :read, account_two, :token) == false
  end

  test "can.create.account.token when the subject is an admin of the account being read" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :admin)

    # When
    assert Authorization.can(user, :create, account, :token) == true
  end

  test "can.create.account.token when the subject is a user of the account being read" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.can(user, :create, account, :token) == true
  end

  test "can.create.account.token when the subject does not belong to the account organization" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)

    # When
    assert Authorization.can(user, :create, account, :token) == false
  end

  test "can.read.account.token when the subject is not the same account being read" do
    # Given
    user = AccountsFixtures.user_fixture()
    user_two = AccountsFixtures.user_fixture()
    account_two = Accounts.get_account_from_user(user_two)

    # When
    assert Authorization.can(user, :read, account_two, :token) == false
  end

  test "can.read.account.token when the subject is an admin of the account being read" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :admin)

    # When
    assert Authorization.can(user, :read, account, :token) == true
  end

  test "can.read.account.token when the subject is a user of the account being read" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.can(user, :read, account, :token) == true
  end

  test "can.read.account.token when the subject does not belong to the account organization" do
    # Given
    user = AccountsFixtures.user_fixture()
    account = Accounts.get_account_from_user(user)

    # When
    assert Authorization.can(user, :read, account, :token) == true
  end

  test "can.delete.account.token when the subject is not the same account being read" do
    # Given
    user = AccountsFixtures.user_fixture()
    user_two = AccountsFixtures.user_fixture()
    account_two = Accounts.get_account_from_user(user_two)

    # When
    assert Authorization.can(user, :delete, account_two, :token) == false
  end

  test "can.delete.account.token when the subject is an admin of the account being read" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :admin)

    # When
    assert Authorization.can(user, :delete, account, :token) == true
  end

  test "can.delete.account.token when the subject is a user of the account being read" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.can(user, :delete, account, :token) == false
  end

  test "can.delete.account.token when the subject does not belong to the account organization" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)

    # When
    assert Authorization.can(user, :delete, account, :token) == false
  end

  test "can.create.project.preview when the subject is not the same project account being created" do
    # Given
    user = AccountsFixtures.user_fixture()
    user_two = AccountsFixtures.user_fixture()
    account_two = Accounts.get_account_from_user(user_two)
    project = ProjectsFixtures.project_fixture(account_id: account_two.id)

    # When
    assert Authorization.can?(:project_preview_create, user, project) == false
  end

  test "can.create.project.preview when the subject is an admin of the project organization being created" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :admin)
    project = ProjectsFixtures.project_fixture(account_id: account.id)

    # When
    assert Authorization.can?(:project_preview_create, user, project) == true
  end

  test "can.create.project.preview when the subject is a user of the project organization being created" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :user)
    project = ProjectsFixtures.project_fixture(account_id: account.id)

    # When
    assert Authorization.can?(:project_preview_create, user, project) == true
  end

  test "can.create.project.preview when the subject does not belong to the project organization" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)

    # When
    assert Authorization.can?(:project_preview_create, user, project) == false
  end

  test "can.create.project.preview when the subject is the same project previews are being created for" do
    # Given
    project = ProjectsFixtures.project_fixture()

    # When
    assert Authorization.can?(:project_preview_create, project, project) == true
  end

  test "can.create.project.preview when the subject is not the same project previews are being created for" do
    # Given
    project = ProjectsFixtures.project_fixture()
    another_project = ProjectsFixtures.project_fixture()

    # When
    assert Authorization.can?(:project_preview_create, another_project, project) == false
  end

  test "can.read.project.preview when the subject is not the same project account being read" do
    # Given
    user = AccountsFixtures.user_fixture()
    user_two = AccountsFixtures.user_fixture()
    account_two = Accounts.get_account_from_user(user_two)
    project = ProjectsFixtures.project_fixture(account_id: account_two.id)

    # When
    assert Authorization.can?(:project_preview_read, user, project) == false
  end

  test "can.read.project.preview when the subject is an admin of the project organization being read" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :admin)
    project = ProjectsFixtures.project_fixture(account_id: account.id)

    # When
    assert Authorization.can?(:project_preview_read, user, project) == true
  end

  test "can.read.project.preview when the subject is a user of the project organization being read" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :user)
    project = ProjectsFixtures.project_fixture(account_id: account.id)

    # When
    assert Authorization.can?(:project_preview_read, user, project) == true
  end

  test "can.read.project.preview when the subject does not belong to the project organization" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)

    # When
    assert Authorization.can?(:project_preview_read, user, project) == false
  end

  test "can.read.project.preview when the subject does not belong to the project organization and the project is public" do
    # Given
    user = AccountsFixtures.user_fixture()
    project = ProjectsFixtures.project_fixture(visibility: :public)

    # When
    assert Authorization.can?(:project_preview_read, user, project) == true
  end

  test "can.read.project.preview when the subject is anonymous and the project is public" do
    # Given
    project = ProjectsFixtures.project_fixture(visibility: :public)

    # When
    assert Authorization.can?(:project_preview_read, nil, project) == true
  end

  test "can.read.preview when the subject is a creator of the project and the preview is ipa" do
    # Given
    user = AccountsFixtures.user_fixture()
    project = ProjectsFixtures.project_fixture(user_id: user.id)
    preview = AppBuildsFixtures.preview_fixture(project: project)

    app_build =
      TuistTestSupport.Fixtures.AppBuildsFixtures.app_build_fixture(
        preview: preview,
        project: project,
        type: :ipa
      )

    updated_preview = Tuist.AppBuilds.update_preview_with_app_build(preview.id, app_build)

    # When
    assert Authorization.can(user, :read, updated_preview) == true
  end

  test "can.read.preview when the subject is anonymous and the preview is ipa" do
    # Given
    preview = AppBuildsFixtures.preview_fixture()

    app_build =
      TuistTestSupport.Fixtures.AppBuildsFixtures.app_build_fixture(
        preview: preview,
        type: :ipa
      )

    updated_preview = Tuist.AppBuilds.update_preview_with_app_build(preview.id, app_build)

    # When
    assert Authorization.can(nil, :read, updated_preview) == true
  end

  test "can.read.preview when the subject is a creator of the project and the preview is private" do
    # Given
    user = Repo.preload(AccountsFixtures.user_fixture(), :account)
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)

    preview =
      AppBuildsFixtures.preview_fixture(project: project, visibility: :private)

    # When
    assert Authorization.can(user, :read, preview) == true
  end

  test "can.read.preview when the subject is anonymous and the preview is private" do
    # Given
    preview = AppBuildsFixtures.preview_fixture(visibility: :private)

    # When
    assert Authorization.can(nil, :read, preview) == false
  end

  test "can.read.preview when the subject is anonymous, the preview is private, and the project is public" do
    # Given
    project = ProjectsFixtures.project_fixture(visibility: :public)
    preview = AppBuildsFixtures.preview_fixture(project: project, visibility: :private)

    # When
    assert Authorization.can(nil, :read, preview) == true
  end

  test "can.update.project.settings when the subject is not the same project account being updated" do
    # Given
    user = AccountsFixtures.user_fixture()
    user_two = AccountsFixtures.user_fixture()
    account_two = Accounts.get_account_from_user(user_two)
    project = ProjectsFixtures.project_fixture(account_id: account_two.id)

    # When
    assert Authorization.can(user, :update, project, :settings) == false
  end

  test "can.update.project.settings when the subject is an admin of the project organization being updated" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :admin)
    project = ProjectsFixtures.project_fixture(account_id: account.id)

    # When
    assert Authorization.can(user, :update, project, :settings) == true
  end

  test "can.update.project.settings when the subject is a user of the project organizatio being updated" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :user)
    project = ProjectsFixtures.project_fixture(account_id: account.id)

    # When
    assert Authorization.can(user, :update, project, :settings) == false
  end

  test "can.update.project.settings when the subject does not belong to the project organization" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)

    # When
    assert Authorization.can(user, :update, project, :settings) == false
  end

  test "can.user.read.ops when the environment is :dev" do
    # Given
    stub(Environment, :dev?, fn -> true end)
    user = AccountsFixtures.user_fixture()

    # Then
    assert Authorization.can(user, :read, :ops) == true
  end

  test "can.user.read.ops when the environment is not dev and the account handle is not included in the list of super admin handles" do
    # Given
    stub(Environment, :env, fn -> :prod end)
    user = AccountsFixtures.user_fixture(preload: [:account])
    stub(Environment, :ops_user_handles, fn -> [] end)

    # Then
    assert Authorization.can(user, :read, :ops) == false
  end

  test "can.user.read.ops when the environment is not dev and the account handle is included in the list of super admin handles" do
    # Given
    stub(Environment, :env, fn -> :prod end)
    user = AccountsFixtures.user_fixture(preload: [:account])
    stub(Environment, :ops_user_handles, fn -> [user.account.name] end)

    # Then
    assert Authorization.can(user, :read, :ops) == true
  end

  test "can.read.account.registry when the subject is the same account being read and the scopes permit the action" do
    # Given
    account = AccountsFixtures.user_fixture(preload: [:account]).account

    # When
    assert Authorization.can?(
             :account_registry_read,
             %AuthenticatedAccount{account: account, scopes: [:account_registry_read]},
             account
           ) == true
  end

  test "can.read.account.registry when the subject is the same account being read and the scopes don't permit the action" do
    # Given
    account = AccountsFixtures.user_fixture(preload: [:account]).account

    # When
    assert Authorization.can?(
             :account_registry_read,
             %AuthenticatedAccount{account: account, scopes: [:account_registry_write]},
             account
           ) == false
  end

  test "can.read.account.registry when the subject is not the same account being read" do
    # Given
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    another_account = AccountsFixtures.user_fixture(preload: [:account]).account

    # When
    assert Authorization.can?(
             :account_registry_read,
             %AuthenticatedAccount{account: account, scopes: [:account_registry_read]},
             another_account
           ) == false
  end

  test "can.read.account.registry when the subject is project" do
    # Given
    project = ProjectsFixtures.project_fixture()
    account = AccountsFixtures.user_fixture(preload: [:account]).account

    # When
    assert Authorization.can?(
             :account_registry_read,
             project,
             account
           ) == false
  end
end
