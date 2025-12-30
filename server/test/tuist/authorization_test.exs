defmodule Tuist.AuthorizationTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Authorization
  alias Tuist.Environment
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  test "can.update.account.billing when the subject is the same account being read and it's on-premise" do
    # Given
    user = AccountsFixtures.user_fixture()
    account = Accounts.get_account_from_user(user)
    stub(Environment, :tuist_hosted?, fn -> false end)

    # When
    assert Authorization.authorize(:billing_update, user, account) == {:error, :forbidden}
  end

  test "can.update.account.billing when the subject is the same account being read and it's not on-premise" do
    # Given
    user = AccountsFixtures.user_fixture()
    account = Accounts.get_account_from_user(user)
    stub(Environment, :tuist_hosted?, fn -> true end)

    # When
    assert Authorization.authorize(:billing_update, user, account) == :ok
  end

  test "can.update.account.billing when the subject is not the same account being read and it's on-premise" do
    # Given
    user = AccountsFixtures.user_fixture()
    user_two = AccountsFixtures.user_fixture()
    account_two = Accounts.get_account_from_user(user_two)
    stub(Environment, :tuist_hosted?, fn -> false end)

    # When
    assert Authorization.authorize(:billing_update, user, account_two) ==
             {:error, :forbidden}
  end

  test "can.update.account.billing when the subject is not the same account being read and it's not on-premise" do
    # Given
    user = AccountsFixtures.user_fixture()
    user_two = AccountsFixtures.user_fixture()
    account_two = Accounts.get_account_from_user(user_two)
    stub(Environment, :tuist_hosted?, fn -> true end)

    # When
    assert Authorization.authorize(:billing_update, user, account_two) ==
             {:error, :forbidden}
  end

  test "can.update.account.billing when the subject is an admin of the account being read and it's on-premise" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :admin)
    stub(Environment, :tuist_hosted?, fn -> false end)

    # When
    assert Authorization.authorize(:billing_update, user, account) == {:error, :forbidden}
  end

  test "can.update.account.billing when the subject is an admin of the account being read and it's not on-premise" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :admin)
    stub(Environment, :tuist_hosted?, fn -> true end)

    # When
    assert Authorization.authorize(:billing_update, user, account) == :ok
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
    assert Authorization.authorize(:billing_update, user, account) == {:error, :forbidden}
  end

  test "can.update.account.billing when the subject is a user of the account being read and it's on-premise" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :user)
    stub(Environment, :tuist_hosted?, fn -> false end)

    # When
    assert Authorization.authorize(:billing_update, user, account) == {:error, :forbidden}
  end

  test "can.update.account.billing when the subject is a user of the account being read and it's not on-premise" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :user)
    stub(Environment, :tuist_hosted?, fn -> true end)

    # When
    assert Authorization.authorize(:billing_update, user, account) == {:error, :forbidden}
  end

  test "can.read.project.cache when the subject is the same project being read" do
    # Given
    project = ProjectsFixtures.project_fixture()

    # When
    assert Authorization.authorize(:cache_read, project, project) == :ok
  end

  test "can.read.project.cache when the subject is not the same project being read" do
    # Given
    project = ProjectsFixtures.project_fixture()
    another_project = ProjectsFixtures.project_fixture()

    # When
    assert Authorization.authorize(:cache_read, another_project, project) ==
             {:error, :forbidden}
  end

  test "can.create.project.cache when the subject is the same project being read" do
    # Given
    project = ProjectsFixtures.project_fixture()

    # When
    assert Authorization.authorize(:cache_create, project, project) == :ok
  end

  test "can.create.project.cache when the subject is not the same project being read" do
    # Given
    project = ProjectsFixtures.project_fixture()
    another_project = ProjectsFixtures.project_fixture()

    # When
    assert Authorization.authorize(:cache_create, another_project, project) ==
             {:error, :forbidden}
  end

  test "can.update.project.cache when the subject is the same project being read" do
    # Given
    project = ProjectsFixtures.project_fixture()

    # When
    assert Authorization.authorize(:cache_update, project, project) == :ok
  end

  test "can.update.project.cache when the subject is not the same project being read" do
    # Given
    project = ProjectsFixtures.project_fixture()
    another_project = ProjectsFixtures.project_fixture()

    # When
    assert Authorization.authorize(:cache_update, another_project, project) ==
             {:error, :forbidden}
  end

  test "can.read.project.cache when the subject is a user that belongs to the project organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.authorize(:cache_read, user, project) == :ok
  end

  test "can.read.project.cache when the subject is a user that doesn't belong to the project organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.authorize(:cache_read, user, project) == {:error, :forbidden}
  end

  test "can.read.project.cache when the subject is a user that doesn't belong to the project organization and the project is public" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id, visibility: :public)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.authorize(:cache_read, user, project) == :ok
  end

  test "can.create.project.cache when the subject is a user that belongs to the project organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.authorize(:cache_create, user, project) == :ok
  end

  test "can.create.project.cache when the subject is a user that doesn't belong to the project organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.authorize(:cache_create, user, project) ==
             {:error, :forbidden}
  end

  test "can.update.project.cache when the subject is a user that belongs to the project organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.authorize(:cache_update, user, project) == :ok
  end

  test "can.update.project.cache when the subject is a user that doesn't belong to the project organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.authorize(:cache_update, user, project) ==
             {:error, :forbidden}
  end

  test "can.access.project.url returns true when the project is public and the subject is nil" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id, visibility: :public)

    # When/Then
    assert Authorization.authorize(:project_url_access, nil, project) == :ok
  end

  test "can.access.project.url returns true when the project is public and the subject is not nil" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id, visibility: :public)
    user = AccountsFixtures.user_fixture()

    # When/Then
    assert Authorization.authorize(:project_url_access, user, project) == :ok
  end

  test "can.access.project.url returns false when the project is private and the subject is nil" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id, visibility: :private)

    # When/Then
    assert Authorization.authorize(:project_url_access, nil, project) == {:error, :forbidden}
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
    assert Authorization.authorize(:project_url_access, user, project) == :ok
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
    assert Authorization.authorize(:project_url_access, user, project) == :ok
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
    assert Authorization.authorize(:project_url_access, user, project) == {:error, :forbidden}
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
    assert Authorization.authorize(:command_event_read, user, command_event) == :ok
  end

  test "can.read.command_event when the subject is a user that doesn't belong to the command event's project organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()
    command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)

    # When
    assert Authorization.authorize(:command_event_read, user, command_event) ==
             {:error, :forbidden}
  end

  test "can.read.command_event when the subject is a user that doesn't belong to the command event's project organization and the project's visibility is public" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id, visibility: :public)
    user = AccountsFixtures.user_fixture()
    command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)

    # When
    assert Authorization.authorize(:command_event_read, user, command_event) == :ok
  end

  test "can.read.command_event when the subject is an anonymous user and the command event's project's visibility is private" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id, visibility: :private)
    command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)

    # When
    assert Authorization.authorize(:command_event_read, nil, command_event) ==
             {:error, :forbidden}
  end

  test "can.read.command_event when the subject is an anonymous user and the command event's project's visibility is public" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id, visibility: :public)
    command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)

    # When
    assert Authorization.authorize(:command_event_read, nil, command_event) == :ok
  end

  test "can.create.account.project when the subject is a user that belongs to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization)

    # When
    assert Authorization.authorize(:project_create, user, account) == :ok
  end

  test "can.create.account.project when the subject is a user that doesn't belong to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.authorize(:project_create, user, account) == {:error, :forbidden}
  end

  test "can.update.account.project when the subject is a user that belongs to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization)

    # When
    assert Authorization.authorize(:project_update, user, account) == {:error, :forbidden}
  end

  test "can.update.account.project when the subject is a user that is admin of an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :admin)

    # When
    assert Authorization.authorize(:project_update, user, account) == :ok
  end

  test "can.update.account.project when the subject is a user that doesn't belong to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.authorize(:project_update, user, account) == {:error, :forbidden}
  end

  test "can.read.account.project when the subject is a user that belongs to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization)

    # When
    assert Authorization.authorize(:project_read, user, account) == :ok
  end

  test "can.read.account.project when the subject is a user that doesn't belong to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.authorize(:project_read, user, account) == {:error, :forbidden}
  end

  test "can.read.project.dashboard when the subject is a user that belongs to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)

    # When
    assert Authorization.authorize(:dashboard_read, user, project) == :ok
  end

  test "can.read.project.dashboard when the subject is a user that doesn't belong to an organization" do
    # Given
    user = AccountsFixtures.user_fixture()
    project = ProjectsFixtures.project_fixture()

    # When
    assert Authorization.authorize(:dashboard_read, user, project) == {:error, :forbidden}
  end

  test "can.read.project.dashboard when the subject is a user and a project is public" do
    # Given
    user = AccountsFixtures.user_fixture()
    project = ProjectsFixtures.project_fixture(visibility: :public)

    # When
    assert Authorization.authorize(:dashboard_read, user, project) == :ok
  end

  test "can.read.project.dashboard when the subject is an anonymous user and a project is private" do
    # Given
    project = ProjectsFixtures.project_fixture(visibility: :private)

    # When
    assert Authorization.authorize(:dashboard_read, nil, project) == {:error, :forbidden}
  end

  test "can.read.project.dashboard when the subject is an anonymous user and a project is public" do
    # Given
    project = ProjectsFixtures.project_fixture(visibility: :public)

    # When
    assert Authorization.authorize(:dashboard_read, nil, project) == :ok
  end

  test "can.delete.account.project when the subject is a user that belongs to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization)

    # When
    assert Authorization.authorize(:project_delete, user, account) == {:error, :forbidden}
  end

  test "can.delete.account.project when the subject is a user that is admin of an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :admin)

    # When
    assert Authorization.authorize(:project_delete, user, account) == :ok
  end

  test "can.delete.account.project when the subject is a user that doesn't belong to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.authorize(:project_delete, user, account) == {:error, :forbidden}
  end

  test "can.read.account.projects when the subject is a user that is admin of an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :admin)

    # When
    assert Authorization.authorize(:projects_read, user, account) == :ok
  end

  test "can.read.account.projects when the subject is a user that belongs to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.authorize(:projects_read, user, account) == :ok
  end

  test "can.read.account.projects when the subject is a user that doesn't belong to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.authorize(:projects_read, user, account) == {:error, :forbidden}
  end

  test "can.read.account.organization when the subject is a user that is admin of an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :admin)

    # When
    assert Authorization.authorize(:organization_read, user, account) == :ok
  end

  test "can.read.account.billing when the subject is a user that belongs to the organization and it's on-premise" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)
    stub(Environment, :tuist_hosted?, fn -> false end)

    # When
    assert Authorization.authorize(:billing_read, user, account) == {:error, :forbidden}
  end

  test "can.read.account.billing when the subject is a user that belongs to the organization and it's not on-premise" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)
    stub(Environment, :tuist_hosted?, fn -> true end)

    # When
    assert Authorization.authorize(:billing_read, user, account) == {:error, :forbidden}
  end

  test "can.read.account.billing when the subject is a user that doesn't belong to an organization and it's on-premise" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    stub(Environment, :tuist_hosted?, fn -> false end)

    # When
    assert Authorization.authorize(:billing_read, user, account) == {:error, :forbidden}
  end

  test "can.read.account.billing when the subject is a user that doesn't belong to an organization and it's not on-premise" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    stub(Environment, :tuist_hosted?, fn -> true end)

    # When
    assert Authorization.authorize(:billing_read, user, account) == {:error, :forbidden}
  end

  test "can.read.account.billing when the subject is a user is admin of the organization and it's on-premise" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :admin)
    stub(Environment, :tuist_hosted?, fn -> false end)

    # When
    assert Authorization.authorize(:billing_read, user, account) == {:error, :forbidden}
  end

  test "can.read.account.billing when the subject is a user is admin of the organization and it's not on-premise" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :admin)
    stub(Environment, :tuist_hosted?, fn -> true end)

    # When
    assert Authorization.authorize(:billing_read, user, account) == :ok
  end

  test "can.read.account.billing when the subject is interacting with its account and it's on-premise" do
    # Given
    user = AccountsFixtures.user_fixture(preload: [:account])
    stub(Environment, :tuist_hosted?, fn -> false end)

    # When
    assert Authorization.authorize(:billing_read, user, user.account) ==
             {:error, :forbidden}
  end

  test "can.read.account.billing when the subject is interacting with its account and it's not on-premise" do
    # Given
    user = AccountsFixtures.user_fixture(preload: [:account])
    stub(Environment, :tuist_hosted?, fn -> true end)

    # When
    assert Authorization.authorize(:billing_read, user, user.account) == :ok
  end

  test "can.read.account.billing when the subject is interacting with its account and the account has an open_source subscription" do
    # Given
    user = AccountsFixtures.user_fixture(preload: [:account])

    BillingFixtures.subscription_fixture(account_id: user.account.id, plan: :open_source)

    stub(Environment, :tuist_hosted?, fn -> true end)

    # When
    assert Authorization.authorize(:billing_read, user, user.account) ==
             {:error, :forbidden}
  end

  test "can.read.account.organization when the subject is a user that belongs to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.authorize(:organization_read, user, account) == :ok
  end

  test "can.read.account.organization when the subject is a user that doesn't belong to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.authorize(:organization_read, user, account) ==
             {:error, :forbidden}
  end

  test "can.read.account.oragnization_usage when the subject is a user that is admin of an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :admin)

    # When
    assert Authorization.authorize(:billing_usage_read, user, account) == :ok
  end

  test "can.read.account.oragnization_usage when the subject is a user that belongs to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.authorize(:billing_usage_read, user, account) == :ok
  end

  test "can.read.account.oragnization_usage when the subject is a user that doesn't belong to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.authorize(:billing_usage_read, user, account) ==
             {:error, :forbidden}
  end

  test "can.update.account.organization when the subject is a user that is admin of an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :admin)

    # When
    assert Authorization.authorize(:organization_update, user, account) == :ok
  end

  test "can.update.account.organization when the subject is a user that belongs to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.authorize(:organization_update, user, account) ==
             {:error, :forbidden}
  end

  test "can.update.account.organization when the subject is a user that doesn't belong to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.authorize(:organization_update, user, account) ==
             {:error, :forbidden}
  end

  test "can.delete.account.organization when the subject is a user that is admin of an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :admin)

    # When
    assert Authorization.authorize(:organization_delete, user, account) == :ok
  end

  test "can.delete.account.organization when the subject is a user that belongs to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.authorize(:organization_delete, user, account) ==
             {:error, :forbidden}
  end

  test "can.delete.account.organization when the subject is a user that doesn't belong to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.authorize(:organization_delete, user, account) ==
             {:error, :forbidden}
  end

  test "can.create.account.invitation when the subject is a user that is admin of an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :admin)

    # When
    assert Authorization.authorize(:invitation_create, user, account) == :ok
  end

  test "can.create.account.invitation when the subject is a user that belongs to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.authorize(:invitation_create, user, account) ==
             {:error, :forbidden}
  end

  test "can.create.account.invitation when the subject is a user that doesn't belong to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.authorize(:invitation_create, user, account) ==
             {:error, :forbidden}
  end

  test "can.delete.account.invitation when the subject is a user that is admin of an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :admin)

    # When
    assert Authorization.authorize(:invitation_delete, user, account) == :ok
  end

  test "can.delete.account.invitation when the subject is a user that belongs to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.authorize(:invitation_delete, user, account) ==
             {:error, :forbidden}
  end

  test "can.delete.account.invitation when the subject is a user that doesn't belong to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.authorize(:invitation_delete, user, account) ==
             {:error, :forbidden}
  end

  test "can.delete.account.member when the subject is a user that is admin of an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :admin)

    # When
    assert Authorization.authorize(:member_delete, user, account) == :ok
  end

  test "can.delete.account.member when the subject is a user that belongs to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.authorize(:member_delete, user, account) == {:error, :forbidden}
  end

  test "can.delete.account.member when the subject is a user that doesn't belong to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.authorize(:member_delete, user, account) == {:error, :forbidden}
  end

  test "can.update.account.member when the subject is a user that is admin of an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :admin)

    # When
    assert Authorization.authorize(:member_update, user, account) == :ok
  end

  test "can.update.account.member when the subject is a user that belongs to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.authorize(:member_update, user, account) == {:error, :forbidden}
  end

  test "can.update.account.member when the subject is a user that doesn't belong to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.authorize(:member_update, user, account) == {:error, :forbidden}
  end

  test "can.create.account.token when the subject is the same account being read" do
    # Given
    user = AccountsFixtures.user_fixture()
    account = Accounts.get_account_from_user(user)

    # When
    assert Authorization.authorize(:account_token_create, user, account) == :ok
  end

  test "can.create.account.token when the subject is not the same account being read" do
    # Given
    user = AccountsFixtures.user_fixture()
    user_two = AccountsFixtures.user_fixture()
    account_two = Accounts.get_account_from_user(user_two)

    # When
    assert Authorization.authorize(:account_token_read, user, account_two) == {:error, :forbidden}
  end

  test "can.create.account.token when the subject is an admin of the account being read" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :admin)

    # When
    assert Authorization.authorize(:account_token_create, user, account) == :ok
  end

  test "can.create.account.token when the subject is a user of the account being read" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.authorize(:account_token_create, user, account) == :ok
  end

  test "can.create.account.token when the subject does not belong to the account organization" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)

    # When
    assert Authorization.authorize(:account_token_create, user, account) == {:error, :forbidden}
  end

  test "can.read.account.token when the subject is not the same account being read" do
    # Given
    user = AccountsFixtures.user_fixture()
    user_two = AccountsFixtures.user_fixture()
    account_two = Accounts.get_account_from_user(user_two)

    # When
    assert Authorization.authorize(:account_token_read, user, account_two) == {:error, :forbidden}
  end

  test "can.read.account.token when the subject is an admin of the account being read" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :admin)

    # When
    assert Authorization.authorize(:account_token_read, user, account) == :ok
  end

  test "can.read.account.token when the subject is a user of the account being read" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.authorize(:account_token_read, user, account) == :ok
  end

  test "can.read.account.token when the subject does not belong to the account organization" do
    # Given
    user = AccountsFixtures.user_fixture()
    account = Accounts.get_account_from_user(user)

    # When
    assert Authorization.authorize(:account_token_read, user, account) == :ok
  end

  test "can.delete.account.token when the subject is not the same account being read" do
    # Given
    user = AccountsFixtures.user_fixture()
    user_two = AccountsFixtures.user_fixture()
    account_two = Accounts.get_account_from_user(user_two)

    # When
    assert Authorization.authorize(:account_token_delete, user, account_two) ==
             {:error, :forbidden}
  end

  test "can.delete.account.token when the subject is an admin of the account being read" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :admin)

    # When
    assert Authorization.authorize(:account_token_delete, user, account) == :ok
  end

  test "can.delete.account.token when the subject is a user of the account being read" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.authorize(:account_token_delete, user, account) == {:error, :forbidden}
  end

  test "can.delete.account.token when the subject does not belong to the account organization" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)

    # When
    assert Authorization.authorize(:account_token_delete, user, account) == {:error, :forbidden}
  end

  test "can.create.project.preview when the subject is not the same project account being created" do
    # Given
    user = AccountsFixtures.user_fixture()
    user_two = AccountsFixtures.user_fixture()
    account_two = Accounts.get_account_from_user(user_two)
    project = ProjectsFixtures.project_fixture(account_id: account_two.id)

    # When
    assert Authorization.authorize(:preview_create, user, project) == {:error, :forbidden}
  end

  test "can.create.project.preview when the subject is an admin of the project organization being created" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :admin)
    project = ProjectsFixtures.project_fixture(account_id: account.id)

    # When
    assert Authorization.authorize(:preview_create, user, project) == :ok
  end

  test "can.create.project.preview when the subject is a user of the project organization being created" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :user)
    project = ProjectsFixtures.project_fixture(account_id: account.id)

    # When
    assert Authorization.authorize(:preview_create, user, project) == :ok
  end

  test "can.create.project.preview when the subject does not belong to the project organization" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)

    # When
    assert Authorization.authorize(:preview_create, user, project) == {:error, :forbidden}
  end

  test "can.create.project.preview when the subject is the same project previews are being created for" do
    # Given
    project = ProjectsFixtures.project_fixture()

    # When
    assert Authorization.authorize(:preview_create, project, project) == :ok
  end

  test "can.create.project.preview when the subject is not the same project previews are being created for" do
    # Given
    project = ProjectsFixtures.project_fixture()
    another_project = ProjectsFixtures.project_fixture()

    # When
    assert Authorization.authorize(:preview_create, another_project, project) ==
             {:error, :forbidden}
  end

  test "can.read.project.preview when the subject is not the same project account being read" do
    # Given
    user = AccountsFixtures.user_fixture()
    user_two = AccountsFixtures.user_fixture()
    account_two = Accounts.get_account_from_user(user_two)
    project = ProjectsFixtures.project_fixture(account_id: account_two.id)

    # When
    assert Authorization.authorize(:preview_read, user, project) == {:error, :forbidden}
  end

  test "can.read.project.preview when the subject is an admin of the project organization being read" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :admin)
    project = ProjectsFixtures.project_fixture(account_id: account.id)

    # When
    assert Authorization.authorize(:preview_read, user, project) == :ok
  end

  test "can.read.project.preview when the subject is a user of the project organization being read" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :user)
    project = ProjectsFixtures.project_fixture(account_id: account.id)

    # When
    assert Authorization.authorize(:preview_read, user, project) == :ok
  end

  test "can.read.project.preview when the subject does not belong to the project organization" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)

    # When
    assert Authorization.authorize(:preview_read, user, project) == {:error, :forbidden}
  end

  test "can.read.project.preview when the subject does not belong to the project organization and the project is public" do
    # Given
    user = AccountsFixtures.user_fixture()
    project = ProjectsFixtures.project_fixture(visibility: :public)

    # When
    assert Authorization.authorize(:preview_read, user, project) == :ok
  end

  test "can.read.project.preview when the subject is anonymous and the project is public" do
    # Given
    project = ProjectsFixtures.project_fixture(visibility: :public)

    # When
    assert Authorization.authorize(:preview_read, nil, project) == :ok
  end

  test "can.update.project.settings when the subject is not the same project account being updated" do
    # Given
    user = AccountsFixtures.user_fixture()
    user_two = AccountsFixtures.user_fixture()
    account_two = Accounts.get_account_from_user(user_two)
    project = ProjectsFixtures.project_fixture(account_id: account_two.id)

    # When
    assert Authorization.authorize(:project_update, user, project) ==
             {:error, :forbidden}
  end

  test "can.update.project.settings when the subject is an admin of the project organization being updated" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :admin)
    project = ProjectsFixtures.project_fixture(account_id: account.id)

    # When
    assert Authorization.authorize(:project_update, user, project) == :ok
  end

  test "can.update.project.settings when the subject is a user of the project organizatio being updated" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :user)
    project = ProjectsFixtures.project_fixture(account_id: account.id)

    # When
    assert Authorization.authorize(:project_update, user, project) ==
             {:error, :forbidden}
  end

  test "can.update.project.settings when the subject does not belong to the project organization" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)

    # When
    assert Authorization.authorize(:project_update, user, project) ==
             {:error, :forbidden}
  end

  test "can.user.read.ops when the environment is :dev" do
    # Given
    stub(Environment, :dev?, fn -> true end)
    user = AccountsFixtures.user_fixture()

    # Then
    assert Authorization.authorize(:ops_read, user, :ops) == :ok
  end

  test "can.user.read.ops when the environment is not dev and the account handle is not included in the list of super admin handles" do
    # Given
    stub(Environment, :env, fn -> :prod end)
    user = AccountsFixtures.user_fixture(preload: [:account])
    stub(Environment, :ops_user_handles, fn -> [] end)

    # Then
    assert Authorization.authorize(:command_event_read, user, :ops) == {:error, :forbidden}
  end

  test "can.user.read.ops when the environment is not dev and the account handle is included in the list of super admin handles" do
    # Given
    stub(Environment, :env, fn -> :prod end)
    user = AccountsFixtures.user_fixture(preload: [:account])
    stub(Environment, :ops_user_handles, fn -> [user.account.name] end)

    # Then
    assert Authorization.authorize(:ops_read, user, :ops) == :ok
  end

  test "can.read.account.registry when the subject is the same account being read and the scopes permit the action" do
    # Given
    account = AccountsFixtures.user_fixture(preload: [:account]).account

    # When
    assert Authorization.authorize(
             :registry_read,
             %AuthenticatedAccount{account: account, scopes: ["account:registry:read"]},
             account
           ) == :ok
  end

  test "can.read.account.registry when the subject is the same account being read and the scopes don't permit the action" do
    # Given
    account = AccountsFixtures.user_fixture(preload: [:account]).account

    # When
    assert Authorization.authorize(
             :registry_read,
             %AuthenticatedAccount{account: account, scopes: ["account:registry:create"]},
             account
           ) == {:error, :forbidden}
  end

  test "can.read.account.registry when the subject is not the same account being read" do
    # Given
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    another_account = AccountsFixtures.user_fixture(preload: [:account]).account

    # When
    assert Authorization.authorize(
             :registry_read,
             %AuthenticatedAccount{account: account, scopes: ["account:registry:read"]},
             another_account
           ) == {:error, :forbidden}
  end

  test "can.read.account.registry when the subject is project" do
    # Given
    project = ProjectsFixtures.project_fixture()
    account = AccountsFixtures.user_fixture(preload: [:account]).account

    # When
    assert Authorization.authorize(
             :registry_read,
             project,
             account
           ) == {:error, :forbidden}
  end
end
