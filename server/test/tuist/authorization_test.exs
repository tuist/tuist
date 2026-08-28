defmodule Tuist.AuthorizationTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Authorization
  alias Tuist.Environment
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  test "can.read.account_dashboard when the account is public and the subject is anonymous" do
    # Given
    account = AccountsFixtures.organization_fixture(preload: [:account]).account
    {:ok, public_account} = Accounts.update_account_visibility(account, :public)

    # Then
    assert Authorization.authorize(:account_dashboard_read, nil, public_account) == :ok
  end

  test "cannot.read.account_dashboard when the account is private and the subject is anonymous" do
    # Given
    account = AccountsFixtures.organization_fixture(preload: [:account]).account

    # Then
    assert Authorization.authorize(:account_dashboard_read, nil, account) == {:error, :forbidden}
  end

  test "cannot.read.runners on a public account when the subject is not a member" do
    # Given — a public account exposes its dashboards, but attaching to a
    # running VM over VNC/shell stays members-only.
    account = AccountsFixtures.organization_fixture(preload: [:account]).account
    {:ok, public_account} = Accounts.update_account_visibility(account, :public)
    non_member = AccountsFixtures.user_fixture()

    # Then
    assert Authorization.authorize(:runners_read, nil, public_account) == {:error, :forbidden}
    assert Authorization.authorize(:runners_read, non_member, public_account) == {:error, :forbidden}
    assert Authorization.authorize(:account_dashboard_read, non_member, public_account) == :ok
  end

  test "can.update.account when the subject has an admin operator grant" do
    # Given — the grant only authorizes a Tuist operator (signed in with
    # Google) whose email matches the grant's subject. Operators only exist
    # on tuist-hosted instances.
    stub(Environment, :tuist_hosted?, fn -> true end)
    user = AccountsFixtures.user_fixture(email: "operator-#{System.unique_integer([:positive])}@tuist.dev")
    AccountsFixtures.oauth2_identity_fixture(user: user, provider: :google)
    account = AccountsFixtures.organization_fixture(preload: [:account]).account
    now = System.system_time(:second)

    user = %{
      user
      | operator_grant: %{
          tier: :admin,
          account_id: account.id,
          account_handle: account.name,
          sub: user.email,
          reason: "support",
          jti: "1",
          iat: now,
          exp: now + 600
        }
    }

    # When
    assert Authorization.authorize(:account_update, user, account) == :ok
  end

  test "cannot.update.account when the subject is not an admin or operator" do
    # Given
    user = AccountsFixtures.user_fixture()
    account = AccountsFixtures.organization_fixture(preload: [:account]).account

    # When
    assert Authorization.authorize(:account_update, user, account) == {:error, :forbidden}
  end

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
    assert Authorization.authorize(:project_cache_read, project, project) == :ok
  end

  test "can discover account cache endpoints with project cache access without gaining account cache access" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = organization.account
    project = ProjectsFixtures.project_fixture(account: account)

    subject = %AuthenticatedAccount{
      account: account,
      scopes: ["project:cache:read"],
      all_projects: false,
      project_ids: [project.id]
    }

    # When/Then
    assert Authorization.authorize(:account_cache_endpoint_read, subject, account) == :ok
    assert Authorization.authorize(:account_cache_read, subject, account) == {:error, :forbidden}
  end

  test "cannot discover account cache endpoints when project cache access has no accessible projects" do
    # Given
    account = AccountsFixtures.organization_fixture().account

    subject = %AuthenticatedAccount{
      account: account,
      scopes: ["project:cache:read"],
      all_projects: false,
      project_ids: []
    }

    # When/Then
    assert Authorization.authorize(:account_cache_endpoint_read, subject, account) == {:error, :forbidden}
  end

  test "can.read.project.cache when the subject is not the same project being read" do
    # Given
    project = ProjectsFixtures.project_fixture()
    another_project = ProjectsFixtures.project_fixture()

    # When
    assert Authorization.authorize(:project_cache_read, another_project, project) ==
             {:error, :forbidden}
  end

  test "can.create.project.cache when the subject is the same project being read" do
    # Given
    project = ProjectsFixtures.project_fixture()

    # When
    assert Authorization.authorize(:project_cache_create, project, project) == :ok
  end

  test "can.create.project.cache when the subject is not the same project being read" do
    # Given
    project = ProjectsFixtures.project_fixture()
    another_project = ProjectsFixtures.project_fixture()

    # When
    assert Authorization.authorize(:project_cache_create, another_project, project) ==
             {:error, :forbidden}
  end

  test "can.update.project.cache when the subject is the same project being read" do
    # Given
    project = ProjectsFixtures.project_fixture()

    # When
    assert Authorization.authorize(:project_cache_update, project, project) == :ok
  end

  test "can.update.project.cache when the subject is not the same project being read" do
    # Given
    project = ProjectsFixtures.project_fixture()
    another_project = ProjectsFixtures.project_fixture()

    # When
    assert Authorization.authorize(:project_cache_update, another_project, project) ==
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
    assert Authorization.authorize(:project_cache_read, user, project) == :ok
  end

  test "can.read.project.cache when the subject is a user that doesn't belong to the project organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.authorize(:project_cache_read, user, project) == {:error, :forbidden}
  end

  test "can.read.project.cache when the subject is a user that doesn't belong to the project organization and the project is public" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id, visibility: :public)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.authorize(:project_cache_read, user, project) == :ok
  end

  test "can.create.project.cache when the subject is a user that belongs to the project organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.authorize(:project_cache_create, user, project) == :ok
  end

  test "cannot.create.project.cache when the account restricts cache writes to tokens" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    {:ok, account} = Accounts.update_account(organization.account, %{cache_write_policy: :tokens_only})
    project = ProjectsFixtures.project_fixture(account: account)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :admin)

    # When
    assert Authorization.authorize(:project_cache_create, user, project) == {:error, :forbidden}
  end

  test "can.read.project.cache when the account restricts cache writes to tokens" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    {:ok, account} = Accounts.update_account(organization.account, %{cache_write_policy: :tokens_only})
    project = ProjectsFixtures.project_fixture(account: account)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :admin)

    # When
    assert Authorization.authorize(:project_cache_read, user, project) == :ok
  end

  test "can.create.project.cache when an account token has cache write scope and writes are restricted to tokens" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    {:ok, account} = Accounts.update_account(organization.account, %{cache_write_policy: :tokens_only})
    project = ProjectsFixtures.project_fixture(account: account)

    subject = %AuthenticatedAccount{
      account: account,
      scopes: ["project:cache:write"],
      all_projects: true
    }

    # When
    assert Authorization.authorize(:project_cache_create, subject, project) == :ok
  end

  test "can.create.account.cache when a CI account token writes to a token-restricted account" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    {:ok, account} = Accounts.update_account(organization.account, %{cache_write_policy: :tokens_only})

    subject = %AuthenticatedAccount{
      account: account,
      scopes: ["ci"],
      all_projects: true
    }

    # When
    assert Authorization.authorize(:account_cache_create, subject, account) == :ok
  end

  test "cannot.create.project.cache when a user-issued account token writes to a token-restricted account" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture(creator: user)
    {:ok, account} = Accounts.update_account(organization.account, %{cache_write_policy: :tokens_only})
    project = ProjectsFixtures.project_fixture(account: account)

    subject = %AuthenticatedAccount{
      account: user.account,
      issued_by: user,
      scopes: ["project:cache:write"],
      all_projects: true
    }

    # When
    assert Authorization.authorize(:project_cache_create, subject, project) == {:error, :forbidden}
  end

  test "can.create.project.cache when the subject is a user that doesn't belong to the project organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.authorize(:project_cache_create, user, project) ==
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
    assert Authorization.authorize(:project_cache_update, user, project) == :ok
  end

  test "can.update.project.cache when the subject is a user that doesn't belong to the project organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.authorize(:project_cache_update, user, project) ==
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

  test "can.read.account.runners when the subject is a user that belongs to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.authorize(:runners_read, user, account) == :ok
  end

  test "can.read.account.runners when the subject is a user that doesn't belong to an organization" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture()

    # When
    assert Authorization.authorize(:runners_read, user, account) == {:error, :forbidden}
  end

  test "can.read.account.runners when an account token has runner read scope" do
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)

    subject = %AuthenticatedAccount{
      account: account,
      scopes: ["account:runners:read"]
    }

    assert Authorization.authorize(:runners_read, subject, account) == :ok
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

  test "can.read.account.organization when the subject is a matching account token with members read scope" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    subject = %AuthenticatedAccount{account: account, scopes: ["account:members:read"]}

    # When
    assert Authorization.authorize(:organization_read, subject, account) == :ok
  end

  test "cannot.read.account.organization when the subject is an account token for another account" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    other_account = AccountsFixtures.organization_fixture(preload: [:account]).account
    subject = %AuthenticatedAccount{account: other_account, scopes: ["account:members:read"]}

    # When
    assert Authorization.authorize(:organization_read, subject, account) ==
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

  test "can.create.account.invitation when the subject is a matching account token with members write scope" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    subject = %AuthenticatedAccount{account: account, scopes: ["account:members:write"]}

    # When
    assert Authorization.authorize(:invitation_create, subject, account) == :ok
  end

  test "cannot.create.account.invitation when the subject is a matching account token with members read scope" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    subject = %AuthenticatedAccount{account: account, scopes: ["account:members:read"]}

    # When
    assert Authorization.authorize(:invitation_create, subject, account) ==
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

  test "can.delete.account.invitation when the subject is a matching account token with members write scope" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    subject = %AuthenticatedAccount{account: account, scopes: ["account:members:write"]}

    # When
    assert Authorization.authorize(:invitation_delete, subject, account) == :ok
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

  test "can.delete.account.member when the subject is a matching account token with members write scope" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    subject = %AuthenticatedAccount{account: account, scopes: ["account:members:write"]}

    # When
    assert Authorization.authorize(:member_delete, subject, account) == :ok
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

  test "can.update.account.member when the subject is a matching account token with members write scope" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    subject = %AuthenticatedAccount{account: account, scopes: ["account:members:write"]}

    # When
    assert Authorization.authorize(:member_update, subject, account) == :ok
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

  test "cannot.create.account.token when the subject is a user of the account being read" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    assert Authorization.authorize(:account_token_create, user, account) == {:error, :forbidden}
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

  test "can.attach.runners.interactive when the subject is a user of the account" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    Accounts.add_user_to_organization(user, organization, role: :user)

    # Then
    assert Authorization.authorize(:runners_interactive_access, user, account) == :ok
  end

  test "can.user.read.ops when the environment is :dev" do
    # Given
    stub(Environment, :dev?, fn -> true end)
    user = AccountsFixtures.user_fixture()

    # Then
    assert Authorization.authorize(:ops_read, user, :ops) == :ok
  end

  test "cannot.user.read.ops when the user is not an operator" do
    # Given
    user = AccountsFixtures.user_fixture(preload: [:account])
    stub(Accounts, :tuist_operator?, fn _ -> false end)

    # Then
    assert Authorization.authorize(:command_event_read, user, :ops) == {:error, :forbidden}
  end

  test "can.user.read.ops when the user is an operator" do
    # Given
    user = AccountsFixtures.user_fixture(preload: [:account])
    stub(Accounts, :tuist_operator?, fn _ -> true end)

    # Then
    assert Authorization.authorize(:ops_read, user, :ops) == :ok
  end

  describe "viewer role" do
    setup do
      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)
      viewer = AccountsFixtures.user_fixture()
      Accounts.add_user_to_organization(viewer, organization, role: :viewer)

      %{organization: organization, account: account, project: project, viewer: viewer}
    end

    test "can read a project's tests", %{project: project, viewer: viewer} do
      assert Authorization.authorize(:test_read, viewer, project) == :ok
    end

    test "cannot update a test case, which is how test cases get quarantined", %{
      project: project,
      viewer: viewer
    } do
      assert Authorization.authorize(:test_update, viewer, project) == {:error, :forbidden}
    end

    test "can read a project's runs and builds", %{project: project, viewer: viewer} do
      assert Authorization.authorize(:run_read, viewer, project) == :ok
      assert Authorization.authorize(:build_read, viewer, project) == :ok
    end

    test "cannot create or update a project's runs", %{project: project, viewer: viewer} do
      assert Authorization.authorize(:run_create, viewer, project) == {:error, :forbidden}
      assert Authorization.authorize(:run_update, viewer, project) == {:error, :forbidden}
      assert Authorization.authorize(:build_create, viewer, project) == {:error, :forbidden}
    end

    test "can reach a private project's dashboards and URLs", %{
      account: account,
      project: project,
      viewer: viewer
    } do
      assert Authorization.authorize(:dashboard_read, viewer, project) == :ok
      assert Authorization.authorize(:project_url_access, viewer, project) == :ok
      assert Authorization.authorize(:account_dashboard_read, viewer, account) == :ok
    end

    test "can read a project's command events", %{project: project, viewer: viewer} do
      command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)

      assert Authorization.authorize(:command_event_read, viewer, command_event) == :ok
    end

    test "cannot write to the project or account cache", %{
      account: account,
      project: project,
      viewer: viewer
    } do
      assert Authorization.authorize(:project_cache_read, viewer, project) == :ok
      assert Authorization.authorize(:project_cache_create, viewer, project) == {:error, :forbidden}
      assert Authorization.authorize(:project_cache_update, viewer, project) == {:error, :forbidden}
      assert Authorization.authorize(:account_cache_read, viewer, account) == :ok
      assert Authorization.authorize(:account_cache_create, viewer, account) == {:error, :forbidden}
    end

    test "cannot manage the project, the organization, or its members", %{
      account: account,
      project: project,
      viewer: viewer
    } do
      assert Authorization.authorize(:project_create, viewer, account) == {:error, :forbidden}
      assert Authorization.authorize(:project_update, viewer, project) == {:error, :forbidden}
      assert Authorization.authorize(:project_delete, viewer, project) == {:error, :forbidden}
      assert Authorization.authorize(:organization_update, viewer, account) == {:error, :forbidden}
      assert Authorization.authorize(:member_update, viewer, account) == {:error, :forbidden}
      assert Authorization.authorize(:member_delete, viewer, account) == {:error, :forbidden}
      assert Authorization.authorize(:invitation_create, viewer, account) == {:error, :forbidden}
      assert Authorization.authorize(:account_update, viewer, account) == {:error, :forbidden}
      assert Authorization.authorize(:account_delete, viewer, account) == {:error, :forbidden}
    end

    test "can read runner state but cannot attach an interactive shell or VNC session", %{
      account: account,
      viewer: viewer
    } do
      # Given — attaching executes commands on the running VM and reaches the
      # secrets the job was given, so it is withheld even though the runner
      # dashboards are readable.
      assert Authorization.authorize(:runners_read, viewer, account) == :ok

      assert Authorization.authorize(:runners_interactive_access, viewer, account) ==
               {:error, :forbidden}
    end

    test "cannot manage automation alerts but can read them", %{project: project, viewer: viewer} do
      assert Authorization.authorize(:automation_alert_read, viewer, project) == :ok
      assert Authorization.authorize(:automation_alert_create, viewer, project) == {:error, :forbidden}
      assert Authorization.authorize(:automation_alert_update, viewer, project) == {:error, :forbidden}
      assert Authorization.authorize(:automation_alert_delete, viewer, project) == {:error, :forbidden}
    end

    test "cannot create or delete previews but can read them", %{project: project, viewer: viewer} do
      assert Authorization.authorize(:preview_read, viewer, project) == :ok
      assert Authorization.authorize(:preview_create, viewer, project) == {:error, :forbidden}
      assert Authorization.authorize(:preview_delete, viewer, project) == {:error, :forbidden}
    end

    test "cannot reach account tokens at all", %{account: account, viewer: viewer} do
      # Given — tokens are credentials management rather than dashboard reading,
      # and granting the read half-opens the settings shell around them.
      assert Authorization.authorize(:account_token_read, viewer, account) == {:error, :forbidden}
      assert Authorization.authorize(:account_token_create, viewer, account) == {:error, :forbidden}
      assert Authorization.authorize(:account_token_delete, viewer, account) == {:error, :forbidden}
    end
  end
end
