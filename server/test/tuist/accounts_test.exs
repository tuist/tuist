defmodule Tuist.AccountsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use TuistTestSupport.Cases.StubCase, billing: true
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.AccountToken
  alias Tuist.Accounts.AgentRegistration
  alias Tuist.Accounts.AgentRegistrationEvent
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.Invitation
  alias Tuist.Accounts.Organization
  alias Tuist.Accounts.Role
  alias Tuist.Accounts.User
  alias Tuist.Accounts.UserRole
  alias Tuist.Accounts.UserToken
  alias Tuist.Authentication
  alias Tuist.Base64
  alias Tuist.Billing
  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.Kura.Registrations
  alias Tuist.Projects
  alias Tuist.Runners.Profiles, as: RunnerProfiles
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    :ok
  end

  describe "new_organizations_in_last_hour/0" do
    test "returns organizations created less than an hour ago" do
      # Given
      organization = AccountsFixtures.organization_fixture()

      # When
      assert Accounts.new_organizations_in_last_hour() == [organization]
    end

    test "doesn't return organizations created more than an hour ago" do
      # Given
      AccountsFixtures.organization_fixture(created_at: DateTime.add(DateTime.utc_now(), -2, :hour))

      # When
      assert Accounts.new_organizations_in_last_hour() == []
    end
  end

  describe "new_users_in_last_hour/0" do
    test "returns organizations created less than an hour ago" do
      # Given
      user = AccountsFixtures.user_fixture()

      # When
      assert Accounts.new_users_in_last_hour() == [user]
    end

    test "doesn't return organizations created more than an hour ago" do
      # Given
      AccountsFixtures.user_fixture(created_at: DateTime.add(DateTime.utc_now(), -2, :hour))

      # When
      assert Accounts.new_users_in_last_hour() == []
    end
  end

  describe "create_customer_when_absent/1" do
    test "doesn't create the customer if it's already present" do
      # Given
      %{account: account} = AccountsFixtures.user_fixture()
      Mimic.reject(Billing, :create_customer, 1)

      # When
      got = Accounts.create_customer_when_absent(account)

      # Then
      assert got == account
    end

    test "creates the customer when it's absent" do
      # Given
      %{account: account} = AccountsFixtures.user_fixture(customer_id: nil)
      customer_id = UUIDv7.generate()
      billing_email = account.billing_email
      customer_name = account.name

      expect(Billing, :create_customer, 1, fn %{name: ^customer_name, email: ^billing_email} ->
        customer_id
      end)

      # When
      got = Accounts.create_customer_when_absent(account)

      # Then
      assert got == %{account | customer_id: customer_id}
    end
  end

  describe "get_users_count/0" do
    test "returns the total number of users" do
      # Given
      AccountsFixtures.user_fixture()

      # When
      got = Accounts.get_users_count()

      # Then
      assert got == 1
    end
  end

  describe "update_account_current_month_usage/2" do
    test "updates the account usage" do
      # Given
      now = ~N[2025-05-18 15:27:00Z]
      _user = %{account: %{id: account_id}} = AccountsFixtures.user_fixture()

      # When
      got =
        Accounts.update_account_current_month_usage(
          account_id,
          %{
            remote_cache_hits_count: 20
          },
          updated_at: now
        )

      # Then
      assert %{
               current_month_remote_cache_hits_count: 20,
               current_month_remote_cache_hits_count_updated_at: ~N[2025-05-18 15:27:00]
             } = got
    end
  end

  describe "account_month_usage/1" do
    test "returns the right value when there are remote cache hits" do
      # Given
      now = ~U[2025-05-18 15:27:00Z]
      stub(DateTime, :utc_now, fn -> now end)
      _user = %{account: %{id: account_id}} = AccountsFixtures.user_fixture()
      _project = %{id: project_id} = ProjectsFixtures.project_fixture(account_id: account_id)

      CommandEventsFixtures.command_event_fixture(
        project_id: project_id,
        remote_test_target_hits: ["Core"],
        remote_cache_target_hits: ["Kit"],
        created_at: ~U[2025-05-17 15:27:00Z]
      )

      # When
      got = Accounts.account_month_usage(account_id)

      # Then
      assert %{remote_cache_hits_count: 1} == got
    end

    test "returns the right value when there are no remote cache hits" do
      # Given
      now = ~U[2025-05-18 15:27:00Z]
      _user = %{account: %{id: account_id}} = AccountsFixtures.user_fixture()
      _project = %{id: _project_id} = ProjectsFixtures.project_fixture(account_id: account_id)

      # When
      got = Accounts.account_month_usage(account_id, now)

      # Then
      assert %{remote_cache_hits_count: 0} == got
    end
  end

  describe "list_accounts_with_usage_not_updated_today/1" do
    test "returns the accounts not updated today" do
      # Given
      now = ~U[2025-05-18 14:30:00Z]
      stub(DateTime, :utc_now, fn -> now end)

      _user_not_updated_today =
        %{account: %{id: account_id_from_user_not_updated_today}} =
        AccountsFixtures.user_fixture(current_month_remote_cache_hits_count_updated_at: ~U[2025-05-17 14:30:00Z])

      _user_updated_today =
        AccountsFixtures.user_fixture(current_month_remote_cache_hits_count_updated_at: ~U[2025-05-18 12:30:00Z])

      # When
      got = Accounts.list_accounts_with_usage_not_updated_today()

      # Then
      assert {[%{id: ^account_id_from_user_not_updated_today}], _flop_meta} = got
    end

    test "returns the accounts that have never been updated" do
      # Given
      now = ~U[2025-05-18 14:30:00Z]
      stub(DateTime, :utc_now, fn -> now end)

      _user_never_updated =
        %{account: %{id: account_id_from_user_never_updated}} =
        AccountsFixtures.user_fixture(current_month_remote_cache_hits_count_updated_at: nil)

      _user_updated_today =
        AccountsFixtures.user_fixture(current_month_remote_cache_hits_count_updated_at: ~U[2025-05-18 12:30:00Z])

      # When
      got = Accounts.list_accounts_with_usage_not_updated_today()

      # Then
      assert {[%{id: ^account_id_from_user_never_updated}], _flop_meta} = got
    end
  end

  describe "list_billable_customers/1" do
    test "returns only the customers with a customer_id present" do
      # Given
      first_user =
        %{account: %{customer_id: first_account_customer_id} = first_account} =
        AccountsFixtures.user_fixture(customer_id: UUIDv7.generate())

      second_user = %{account: second_account} = AccountsFixtures.user_fixture(customer_id: nil)
      first_user_project = ProjectsFixtures.project_fixture(account_id: first_account.id)
      second_user_project = ProjectsFixtures.project_fixture(account_id: second_account.id)
      today = ~U[2025-01-02 23:00:00Z]
      stub(DateTime, :utc_now, fn -> today end)

      CommandEventsFixtures.command_event_fixture(
        name: "generate",
        project_id: first_user_project.id,
        user_id: first_user.id,
        remote_cache_target_hits: ["Module"],
        remote_test_target_hits: ["ModuleTeests"],
        ran_at: ~U[2025-01-01 23:00:00Z]
      )

      CommandEventsFixtures.command_event_fixture(
        name: "generate",
        project_id: second_user_project.id,
        user_id: second_user.id,
        remote_cache_target_hits: ["Module2"],
        remote_test_target_hits: ["Module2Tests"],
        ran_at: ~U[2025-01-01 23:00:00Z]
      )

      # When
      assert [^first_account_customer_id] = Accounts.list_billable_customers()
    end

    test "includes customers with LLM token usage yesterday, even without command events" do
      # Given
      today = ~U[2025-01-02 23:00:00Z]
      stub(DateTime, :utc_now, fn -> today end)

      org = AccountsFixtures.organization_fixture()
      account = Tuist.Repo.get_by!(Account, organization_id: org.id)
      account = Tuist.Repo.update!(Account.billing_changeset(account, %{customer_id: UUIDv7.generate()}))

      {:ok, _} =
        Billing.create_token_usage(%{
          input_tokens: 42,
          output_tokens: 24,
          model: "gpt-4",
          feature: "qa",
          feature_resource_id: UUIDv7.generate(),
          account_id: account.id,
          timestamp: ~U[2025-01-01 10:00:00Z]
        })

      # When
      customer_ids = Accounts.list_billable_customers()

      # Then
      assert account.customer_id in customer_ids
    end

    test "includes customers with a customer_id regardless of token usage timing" do
      # Given
      today = ~U[2025-01-02 23:00:00Z]
      stub(DateTime, :utc_now, fn -> today end)

      org = AccountsFixtures.organization_fixture()
      account = Tuist.Repo.get_by!(Account, organization_id: org.id)
      account = Tuist.Repo.update!(Account.billing_changeset(account, %{customer_id: UUIDv7.generate()}))

      {:ok, _} =
        Billing.create_token_usage(%{
          input_tokens: 11,
          output_tokens: 22,
          model: "gpt-4",
          feature: "qa",
          feature_resource_id: UUIDv7.generate(),
          account_id: account.id,
          timestamp: ~U[2024-12-31 10:00:00Z]
        })

      # When
      customer_ids = Accounts.list_billable_customers()

      # Then
      assert account.customer_id in customer_ids
    end
  end

  describe "get_organizations_count/0" do
    test "returns the total number of users" do
      # Given
      AccountsFixtures.organization_fixture()

      # When
      got = Accounts.get_organizations_count()

      # Then
      assert got == 1
    end
  end

  describe "tuist_operator?/1" do
    setup do
      stub(Environment, :tuist_hosted?, fn -> true end)
      :ok
    end

    test "true on a self-hosted instance for an operator-domain email (no Google check)" do
      # Self-hosted has no Tuist Google Workspace; the operator-domain email
      # match alone qualifies, with no Google identity required.
      stub(Environment, :tuist_hosted?, fn -> false end)

      user =
        user_fixture(
          email: "selfhosted-#{System.unique_integer([:positive])}@tuist.dev",
          confirmed_at: nil
        )

      assert Accounts.tuist_operator?(user)
    end

    test "false on a self-hosted instance for a non-operator-domain email" do
      stub(Environment, :tuist_hosted?, fn -> false end)

      user =
        user_fixture(
          email: "ext-#{System.unique_integer([:positive])}@example.com",
          confirmed_at: nil
        )

      refute Accounts.tuist_operator?(user)
    end

    test "true for an operator-domain email in the operator Google Workspace" do
      # Google sign-ins never set confirmed_at; membership is proven by the
      # hosted-domain (hd) claim stored as the identity's provider_organization_id.
      user =
        user_fixture(
          email: "g-#{System.unique_integer([:positive])}@tuist.dev",
          confirmed_at: nil
        )

      oauth2_identity_fixture(user: user, provider: :google, provider_organization_id: "tuist.dev")

      assert Accounts.tuist_operator?(user)
    end

    test "false for an operator-domain email whose Google identity has no hosted domain" do
      # The historical-row case: a Google identity without a captured hd does
      # not prove Workspace membership, so it must not qualify.
      user =
        user_fixture(
          email: "nohd-#{System.unique_integer([:positive])}@tuist.dev",
          confirmed_at: nil
        )

      oauth2_identity_fixture(user: user, provider: :google, provider_organization_id: nil)

      refute Accounts.tuist_operator?(user)
    end

    test "false for an operator-domain email signed into a different Google Workspace" do
      user =
        user_fixture(
          email: "other-#{System.unique_integer([:positive])}@tuist.dev",
          confirmed_at: nil
        )

      oauth2_identity_fixture(user: user, provider: :google, provider_organization_id: "evil.example")

      refute Accounts.tuist_operator?(user)
    end

    test "false for an operator-domain email that only confirmed via the email flow" do
      user =
        user_fixture(
          email: "op-#{System.unique_integer([:positive])}@tuist.dev",
          confirmed_at: DateTime.utc_now()
        )

      refute Accounts.tuist_operator?(user)
    end

    test "false for an operator-domain email signed in with a non-Google provider" do
      user =
        user_fixture(
          email: "gh-#{System.unique_integer([:positive])}@tuist.dev",
          confirmed_at: nil
        )

      oauth2_identity_fixture(user: user, provider: :github)

      refute Accounts.tuist_operator?(user)
    end

    test "false for a non-operator-domain email in its own Google Workspace" do
      user =
        user_fixture(
          email: "ext-#{System.unique_integer([:positive])}@example.com",
          confirmed_at: nil
        )

      oauth2_identity_fixture(user: user, provider: :google, provider_organization_id: "example.com")

      refute Accounts.tuist_operator?(user)
    end
  end

  describe "organization_admin?/2" do
    test "organization_admin? returns false if the user is not an admin" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture()

      # When
      assert Accounts.organization_admin?(user, organization) == false
    end

    test "organization_admin? returns true if the user is the admin of the organization" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture()
      Accounts.add_user_to_organization(user, organization, role: :admin)

      # When
      assert Accounts.organization_admin?(user, organization) == true
    end
  end

  describe "organization_user?/2" do
    test "organization_user? returns false if the user is not an admin" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture()

      # When
      assert Accounts.organization_user?(user, organization) == false
    end

    test "organization_user? returns true if the user is user of the organization" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture()
      Accounts.add_user_to_organization(user, organization, role: :user)

      # When
      assert Accounts.organization_user?(user, organization) == true
    end

    test "organization_user? returns true if the user's sso matches the organization's when the sso is Google" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      provider_organization_id = unique_sso_domain("okta")

      user =
        Accounts.find_or_create_user_from_oauth2(okta_oauth_identity(provider_organization_id))

      organization =
        AccountsFixtures.organization_fixture(
          sso_provider: :okta,
          sso_organization_id: provider_organization_id,
          oauth2_client_id: "client-id",
          oauth2_client_secret: "client-secret"
        )

      # When
      assert Accounts.organization_user?(user, organization) == true
    end

    test "organization_user? returns true if the user's sso matches the organization's when the sso is Okta" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      domain = unique_sso_domain()

      user =
        Accounts.find_or_create_user_from_oauth2(google_oauth_identity(domain))

      organization =
        AccountsFixtures.organization_fixture(
          sso_provider: :google,
          sso_organization_id: domain
        )

      # When
      assert Accounts.organization_user?(user, organization) == true
    end

    test "organization_user? returns false if the user's sso domain matches the organization's but the providers are different" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      domain = unique_sso_domain()

      user =
        Accounts.find_or_create_user_from_oauth2(google_oauth_identity(domain))

      organization =
        AccountsFixtures.organization_fixture(
          sso_provider: :okta,
          sso_organization_id: domain,
          oauth2_client_id: "client-id",
          oauth2_client_secret: "client-secret"
        )

      # When
      assert Accounts.organization_user?(user, organization) == false
    end

    test "organization_user? returns false if the user's sso does not match the organization's when both are Google" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      user_domain = unique_sso_domain("tools")
      organization_domain = unique_sso_domain()

      user =
        Accounts.find_or_create_user_from_oauth2(google_oauth_identity(user_domain))

      organization =
        AccountsFixtures.organization_fixture(
          sso_provider: :google,
          sso_organization_id: organization_domain
        )

      # When
      assert Accounts.organization_user?(user, organization) == false
    end
  end

  describe "belongs_to_organization?/2" do
    test "returns true if the user is a user of the organization" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture()
      Accounts.add_user_to_organization(user, organization, role: :user)

      # When
      got = Accounts.belongs_to_organization?(user, organization)

      # Then
      assert got == true
    end

    test "returns true if the user is an admin of the organization" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture()
      Accounts.add_user_to_organization(user, organization, role: :admin)

      # When
      got = Accounts.belongs_to_organization?(user, organization)

      # Then
      assert got == true
    end

    test "returns true if the user's sso matches the organization's" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      domain = unique_sso_domain()

      user =
        Accounts.find_or_create_user_from_oauth2(google_oauth_identity(domain))

      organization =
        AccountsFixtures.organization_fixture(
          sso_provider: :google,
          sso_organization_id: domain
        )

      # When
      assert Accounts.belongs_to_organization?(user, organization) == true
    end

    test "returns false if the user is not an admin nor an user of the organization" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture()

      # When
      assert Accounts.belongs_to_organization?(user, organization) == false
    end
  end

  describe "get_user_role_in_organization/2" do
    test "returns a user role when a user is a member of an organization" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture()
      Accounts.add_user_to_organization(user, organization, role: :user)

      # When
      got = Accounts.get_user_role_in_organization(user, organization)

      # Then
      assert got.name == "user"
    end

    test "returns a user role when a user is an admin of an organization" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture()
      Accounts.add_user_to_organization(user, organization, role: :admin)

      # When
      got = Accounts.get_user_role_in_organization(user, organization)

      # Then
      assert got.name == "admin"
    end

    test "returns nil when a user does not belong to it" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture()

      # When
      got = Accounts.get_user_role_in_organization(user, organization)

      # Then
      assert got == nil
    end
  end

  describe "belongs_to_sso_organization?/2" do
    test "returns true if the user's sso matches the organization's" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      domain = unique_sso_domain()

      user =
        Accounts.find_or_create_user_from_oauth2(google_oauth_identity(domain))

      organization =
        AccountsFixtures.organization_fixture(
          sso_provider: :google,
          sso_organization_id: domain
        )

      # When
      got = Accounts.belongs_to_sso_organization?(user, organization)

      # Then
      assert got == true
    end

    test "returns false if the user's sso does not match the organization's" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      user_domain = unique_sso_domain("tools")
      organization_domain = unique_sso_domain()

      user =
        Accounts.find_or_create_user_from_oauth2(google_oauth_identity(user_domain))

      organization =
        AccountsFixtures.organization_fixture(
          sso_provider: :google,
          sso_organization_id: organization_domain
        )

      # When
      got = Accounts.belongs_to_sso_organization?(user, organization)

      # Then
      assert got == false
    end
  end

  describe "update_sso_configuration/3" do
    test "updates Okta SSO configuration using shared fields" do
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: user)

      result =
        Accounts.update_sso_configuration(organization.id, :okta, %{
          oauth2_client_id: "test_client_id",
          oauth2_client_secret: "test_secret",
          sso_organization_id: "test.okta.com",
          oauth2_authorize_url: "https://test.okta.com/oauth2/v1/authorize",
          oauth2_token_url: "https://test.okta.com/oauth2/v1/token",
          oauth2_user_info_url: "https://test.okta.com/oauth2/v1/userinfo"
        })

      assert {:ok, updated_org} = result
      assert updated_org.oauth2_client_id == "test_client_id"
      assert updated_org.sso_provider == :okta
      assert updated_org.sso_organization_id == "test.okta.com"
      assert updated_org.oauth2_encrypted_client_secret
    end

    test "encrypts the client secret when storing" do
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: user)
      plain_secret = "my_super_secret_key"

      {:ok, updated_org} =
        Accounts.update_sso_configuration(organization.id, :okta, %{
          oauth2_client_id: "test_client_id",
          oauth2_client_secret: plain_secret,
          sso_organization_id: "test.okta.com",
          oauth2_authorize_url: "https://test.okta.com/oauth2/v1/authorize",
          oauth2_token_url: "https://test.okta.com/oauth2/v1/token",
          oauth2_user_info_url: "https://test.okta.com/oauth2/v1/userinfo"
        })

      assert updated_org.oauth2_encrypted_client_secret
      {:ok, reloaded_org} = Accounts.get_organization_by_id(updated_org.id)
      assert reloaded_org.oauth2_encrypted_client_secret == plain_secret
    end

    test "returns error when organization doesn't exist" do
      result =
        Accounts.update_sso_configuration(999_999, :okta, %{
          oauth2_client_id: "test_client_id"
        })

      assert result == {:error, :not_found}
    end

    test "automatically sets sso_provider" do
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: user, sso_provider: :google)

      {:ok, updated_org} =
        Accounts.update_sso_configuration(organization.id, :okta, %{
          oauth2_client_id: "test_client_id",
          oauth2_client_secret: "test_secret",
          sso_organization_id: "test.okta.com",
          oauth2_authorize_url: "https://test.okta.com/oauth2/v1/authorize",
          oauth2_token_url: "https://test.okta.com/oauth2/v1/token",
          oauth2_user_info_url: "https://test.okta.com/oauth2/v1/userinfo"
        })

      assert updated_org.sso_provider == :okta
    end

    test "can update partial Okta configuration" do
      user = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          oauth2_client_id: "old_client_id",
          oauth2_client_secret: "old_secret",
          sso_organization_id: "old.okta.com",
          sso_provider: :okta
        )

      {:ok, updated_org} =
        Accounts.update_sso_configuration(organization.id, :okta, %{
          oauth2_client_id: "new_client_id"
        })

      assert updated_org.oauth2_client_id == "new_client_id"
      assert updated_org.sso_organization_id == "old.okta.com"
      assert updated_org.sso_provider == :okta
    end

    test "updates custom OAuth2 configuration for an existing organization" do
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: user)

      assert {:ok, updated_org} =
               Accounts.update_sso_configuration(organization.id, :oauth2, %{
                 oauth2_client_id: "test_client_id",
                 oauth2_client_secret: "test_secret",
                 oauth2_authorize_url: "https://auth.example.com/oauth2/authorize",
                 oauth2_token_url: "https://auth.example.com/oauth2/token",
                 oauth2_user_info_url: "https://auth.example.com/oauth2/userinfo",
                 sso_organization_id: "https://auth.example.com/"
               })

      assert updated_org.oauth2_client_id == "test_client_id"
      assert updated_org.oauth2_authorize_url == "https://auth.example.com/oauth2/authorize"
      assert updated_org.oauth2_token_url == "https://auth.example.com/oauth2/token"
      assert updated_org.oauth2_user_info_url == "https://auth.example.com/oauth2/userinfo"
      assert updated_org.oauth2_encrypted_client_secret
      assert updated_org.sso_provider == :oauth2
      assert updated_org.sso_organization_id == "https://auth.example.com"
    end

    test "returns error for oauth2 when organization doesn't exist" do
      result =
        Accounts.update_sso_configuration(999_999, :oauth2, %{
          oauth2_client_id: "test_client_id"
        })

      assert result == {:error, :not_found}
    end
  end

  describe "oauth2_config_for_organization/1" do
    test "returns config for a custom OAuth2 organization" do
      organization = %Organization{
        sso_provider: :oauth2,
        sso_organization_id: "https://auth.example.com",
        oauth2_client_id: "test_client_id",
        oauth2_encrypted_client_secret: "test_client_secret",
        oauth2_authorize_url: "https://auth.example.com/oauth2/authorize",
        oauth2_token_url: "https://auth.example.com/oauth2/token",
        oauth2_user_info_url: "https://auth.example.com/oauth2/userinfo"
      }

      assert {:ok, config} = Accounts.oauth2_config_for_organization(organization)

      assert config.site == "https://auth.example.com"
      assert config.provider_organization_id == "https://auth.example.com"
      assert config.client_id == "test_client_id"
      assert config.client_secret == "test_client_secret"
      assert config.authorize_url == "https://auth.example.com/oauth2/authorize"
      assert config.token_url == "https://auth.example.com/oauth2/token"
      assert config.user_info_url == "https://auth.example.com/oauth2/userinfo"
    end

    test "returns config for an Okta organization using shared fields" do
      organization = %Organization{
        sso_provider: :okta,
        sso_organization_id: "dev-example.okta.com",
        oauth2_client_id: "test_client_id",
        oauth2_encrypted_client_secret: "test_client_secret",
        oauth2_authorize_url: "https://dev-example.okta.com/oauth2/v1/authorize",
        oauth2_token_url: "https://dev-example.okta.com/oauth2/v1/token",
        oauth2_user_info_url: "https://dev-example.okta.com/oauth2/v1/userinfo"
      }

      assert {:ok, config} = Accounts.oauth2_config_for_organization(organization)

      assert config.site == "https://dev-example.okta.com"
      assert config.provider_organization_id == "dev-example.okta.com"
      assert config.client_id == "test_client_id"
      assert config.client_secret == "test_client_secret"
      assert config.authorize_url == "https://dev-example.okta.com/oauth2/v1/authorize"
      assert config.token_url == "https://dev-example.okta.com/oauth2/v1/token"
      assert config.user_info_url == "https://dev-example.okta.com/oauth2/v1/userinfo"
    end

    test "returns error for a non-OAuth2 organization" do
      organization = %Organization{
        sso_provider: :google,
        sso_organization_id: "example.com"
      }

      assert {:error, :oauth2_not_configured} =
               Accounts.oauth2_config_for_organization(organization)
    end
  end

  describe "get_invitation_by_id/1" do
    test "returns a given invitation" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: user)

      {:ok, invitation} =
        Accounts.invite_user_to_organization("new@tuist.io", %{
          inviter: user,
          to: organization,
          url: fn token -> token end
        })

      # When
      got = Accounts.get_invitation_by_id(invitation.id)

      # Then
      assert got == invitation
    end
  end

  describe "get_invitation_by_invitee_email_and_organization/2" do
    test "returns a given invitation doing a case-insensitive search" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: user)

      Accounts.invite_user_to_organization("new@tuist.io", %{
        inviter: user,
        to: AccountsFixtures.organization_fixture(creator: user),
        url: fn token -> token end
      })

      {:ok, invitation} =
        Accounts.invite_user_to_organization("new@tuist.io", %{
          inviter: user,
          to: organization,
          url: fn token -> token end
        })

      # When
      got =
        Accounts.get_invitation_by_invitee_email_and_organization(
          String.upcase("new@tuist.io"),
          organization
        )

      # Then
      assert got == invitation
    end
  end

  describe "cancel_invitation/1" do
    test "cancels an invitation" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(name: "tuist-org", creator: user)

      {:ok, invitation} =
        Accounts.invite_user_to_organization("new@tuist.io", %{
          inviter: user,
          to: organization,
          url: fn token -> token end
        })

      Accounts.invite_user_to_organization("new@tuist.io", %{
        inviter: user,
        to: AccountsFixtures.organization_fixture(name: "tuist-org-2", creator: user),
        url: fn token -> token end
      })

      # When
      :ok =
        Accounts.cancel_invitation(invitation)

      # Then
      assert Accounts.get_invitation_by_id(invitation.id) == nil
    end
  end

  describe "get_invitation_by_token/2" do
    test "returns the invitation with the given token" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: user)
      invitee = AccountsFixtures.user_fixture(email: "new@tuist.io")

      {:ok, invitation} =
        Accounts.invite_user_to_organization("new@tuist.io", %{
          inviter: user,
          to: organization,
          url: fn token -> token end
        })

      # When
      {:ok, got} = Accounts.get_invitation_by_token(invitation.token, invitee)

      # Then
      assert got == Repo.preload(invitation, inviter: :account)
    end

    test "returns :not_found error when invitee email does not match" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: user)
      invitee = AccountsFixtures.user_fixture(email: "new@tuist.io")

      {:ok, invitation} =
        Accounts.invite_user_to_organization("different@tuist.io", %{
          inviter: user,
          to: organization,
          url: fn token -> token end
        })

      # When
      got = Accounts.get_invitation_by_token(invitation.token, invitee)

      # Then
      assert got == {:error, :not_found}
    end

    test "returns :not_found when an invitation with a given token does not exist" do
      # Given
      invitee = AccountsFixtures.user_fixture(email: "new@tuist.io")

      # When
      got = Accounts.get_invitation_by_token("non-existent", invitee)

      # Then
      assert got == {:error, :not_found}
    end

    test "returns invitation when invitee email case differs from invitation email" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: user)
      invitee = AccountsFixtures.user_fixture(email: "NEW@tuist.io")

      {:ok, invitation} =
        Accounts.invite_user_to_organization("neW@tuist.io", %{
          inviter: user,
          to: organization,
          url: fn token -> token end
        })

      # When
      {:ok, got} = Accounts.get_invitation_by_token(invitation.token, invitee)

      # Then
      assert got == Repo.preload(invitation, inviter: :account)
    end
  end

  describe "get_pending_invitations_by_email/1" do
    test "returns invitations for the given email" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: user)

      {:ok, invitation} =
        Accounts.invite_user_to_organization("new@tuist.io", %{
          inviter: user,
          to: organization,
          url: fn token -> token end
        })

      # When
      got = Accounts.get_pending_invitations_by_email("new@tuist.io")

      # Then
      assert [%{id: id}] = got
      assert id == invitation.id
    end

    test "orders invitations by most recent first" do
      # Given
      user = AccountsFixtures.user_fixture()

      {:ok, older} =
        Accounts.invite_user_to_organization("new@tuist.io", %{
          inviter: user,
          to: AccountsFixtures.organization_fixture(creator: user),
          url: fn token -> token end
        })

      {:ok, newer} =
        Accounts.invite_user_to_organization("new@tuist.io", %{
          inviter: user,
          to: AccountsFixtures.organization_fixture(creator: user),
          url: fn token -> token end
        })

      Tuist.Repo.update_all(
        from(i in Invitation, where: i.id == ^older.id),
        set: [created_at: ~N[2026-01-01 00:00:00]]
      )

      Tuist.Repo.update_all(
        from(i in Invitation, where: i.id == ^newer.id),
        set: [created_at: ~N[2026-02-01 00:00:00]]
      )

      # When
      got = Accounts.get_pending_invitations_by_email("new@tuist.io")

      # Then
      assert Enum.map(got, & &1.id) == [newer.id, older.id]
    end

    test "returns an empty list when no invitations exist for the given email" do
      # When
      got = Accounts.get_pending_invitations_by_email("nobody@tuist.io")

      # Then
      assert got == []
    end

    test "does not return invitations for other emails" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: user)

      {:ok, _invitation} =
        Accounts.invite_user_to_organization("someone@tuist.io", %{
          inviter: user,
          to: organization,
          url: fn token -> token end
        })

      # When
      got = Accounts.get_pending_invitations_by_email("other@tuist.io")

      # Then
      assert got == []
    end
  end

  describe "accept_invitation/1" do
    test "accepts an invitation" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: user)
      invitee = AccountsFixtures.user_fixture(email: "new@tuist.io")

      {:ok, invitation} =
        Accounts.invite_user_to_organization("new@tuist.io", %{
          inviter: user,
          to: organization,
          url: fn token -> token end
        })

      # When
      Accounts.accept_invitation(%{
        invitation: invitation,
        invitee: invitee,
        organization: organization
      })

      # Then
      assert Enum.map(Accounts.get_organization_members(organization, :user), & &1.id) == [
               invitee.id
             ]

      assert Accounts.get_invitation_by_id(invitation.id) == nil
    end
  end

  describe "invite_user_to_organization/2" do
    setup do
      stub(Environment, :mailing_from_address, fn -> "noreply@tuist.dev" end)
      :ok
    end

    test "creates an invitation" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture()

      # When
      invitation =
        Accounts.invite_user_to_organization(
          "test@tuist.io",
          %{inviter: user, to: organization, url: fn token -> token end},
          token: "token"
        )

      # Then
      assert {:ok, invitation} = invitation
      assert invitation.token == "token"
      assert invitation.invitee_email == "test@tuist.io"
      assert invitation.inviter_type == "User"
      assert invitation.organization_id == organization.id
    end

    test "returns errors" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture()

      {:ok, _invitation} =
        Accounts.invite_user_to_organization(
          "test@tuist.io",
          %{inviter: user, to: organization, url: fn token -> token end},
          token: "token"
        )

      # When
      result =
        Accounts.invite_user_to_organization(
          "test@tuist.io",
          %{inviter: user, to: organization, url: fn token -> token end},
          token: "token2"
        )

      # Then
      assert {:error, changeset} = result
      assert "has already been taken" in errors_on(changeset).invitee_email
    end
  end

  test "get all organization accounts for a given user" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)

    # When
    got = Accounts.get_user_organization_accounts(user)

    # Then
    assert organization.id == hd(got).organization.id
  end

  describe "get_user_by_email/1" do
    test "returns {:error, :not_found} if the email does not exist" do
      assert {:error, :not_found} = Accounts.get_user_by_email("unknown@example.com")
    end

    test "returns {:ok, user} if the email exists doing a case-insensitive search" do
      %{id: id} = user = user_fixture()
      assert {:ok, %User{id: ^id}} = Accounts.get_user_by_email(String.upcase(user.email))
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "does not return the user if the email does not exist" do
      assert {:error, :invalid_email_or_password} =
               Accounts.get_user_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "does not return the user if the password is not valid" do
      user = user_fixture()

      assert {:error, :invalid_email_or_password} =
               Accounts.get_user_by_email_and_password(user.email, "invalid")
    end

    test "returns the user if the email and password are valid doing a case-insensitive search" do
      %{id: id} = user = user_fixture()

      assert {:ok, %User{id: ^id}} =
               Accounts.get_user_by_email_and_password(
                 String.upcase(user.email),
                 valid_user_password()
               )
    end
  end

  describe "get_user!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!(-1)
      end
    end

    test "returns the user with the given id" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user!(user.id)
    end
  end

  describe "create_organization/1" do
    test "doesn't start the billing trial if it's an on-premise environment" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> false end)
      user = AccountsFixtures.user_fixture()

      # When
      {:ok, organization} = Accounts.create_organization(%{name: "tuist", creator: user})

      # Then
      assert {:ok, organization} == Accounts.get_organization_by_id(organization.id)
      assert Accounts.organization_admin?(user, organization) == true
    end

    test "creates an organization" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      user = AccountsFixtures.user_fixture()

      # When
      {:ok, organization} = Accounts.create_organization(%{name: "tuist", creator: user})

      # Then
      assert {:ok, organization} == Accounts.get_organization_by_id(organization.id)
      assert Accounts.organization_admin?(user, organization) == true
    end

    test "auto-bootstraps the protected linux runner profile" do
      # Every new organization account lands with the default `linux`
      # profile so `runs-on: <prefix>linux` resolves the moment the
      # account exists — without it the customer's first workflow
      # would error out before they ever see the Profiles UI.
      stub(Environment, :tuist_hosted?, fn -> true end)
      user = AccountsFixtures.user_fixture()

      {:ok, organization} = Accounts.create_organization(%{name: "tuist", creator: user})

      profiles = RunnerProfiles.list_for_account(organization.account)

      assert %{name: "linux", protected: true, vcpus: 2, memory_gb: 8} =
               Enum.find(profiles, &(&1.name == "linux"))
    end

    test "creates an organization when new pricing model is enabled" do
      # Given
      Billing

      user = AccountsFixtures.user_fixture()

      # When
      {:ok, organization} = Accounts.create_organization(%{name: "tuist", creator: user})

      # Then
      assert {:ok, organization} == Accounts.get_organization_by_id(organization.id)
      assert Accounts.organization_admin?(user, organization) == true
    end

    test "creates an organization with SSO provider" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      user = AccountsFixtures.user_fixture()
      domain = unique_sso_domain()

      # When
      {:ok, organization} =
        Accounts.create_organization(
          %{
            name: "tuist",
            creator: user
          },
          sso_provider: :google,
          sso_organization_id: domain
        )

      # Then
      assert {:ok, organization} ==
               Accounts.get_organization_by_id(organization.id, preload: [:account])

      assert organization.sso_provider == :google
      assert organization.sso_organization_id == domain
      assert Accounts.organization_admin?(user, organization) == true
    end

    test "creates an organization when billing is enabled" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      user = AccountsFixtures.user_fixture()

      # When
      {:ok, organization} = Accounts.create_organization(%{name: "tuist", creator: user})

      # Then
      assert {:ok, organization} == Accounts.get_organization_by_id(organization.id)
      assert Accounts.get_account_from_organization(organization).customer_id != ""
      assert Accounts.organization_admin?(user, organization) == true
    end
  end

  describe "delete_organization/1" do
    test "deletes an organization" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      user = AccountsFixtures.user_fixture()
      {:ok, organization} = Accounts.create_organization(%{name: "tuist", creator: user})
      account = Accounts.get_account_from_organization(organization)

      # When
      Accounts.delete_organization!(organization)

      # Then
      assert Accounts.get_organization_by_id(organization.id) == {:error, :not_found}
      assert Accounts.get_account_by_id(account.id) == {:error, :not_found}
    end
  end

  describe "get_organization_by_id/1" do
    test "returns organization when organization exists" do
      # Given
      user = AccountsFixtures.user_fixture()

      # When
      {:ok, organization} = Accounts.create_organization(%{name: "test-org", creator: user})

      # Then
      assert {:ok, organization} == Accounts.get_organization_by_id(organization.id)
    end

    test "returns not found error when organization does not exist" do
      # When / Then
      assert {:error, :not_found} == Accounts.get_organization_by_id(999)
    end
  end

  describe "find_or_create_user_from_oauth2" do
    test "handles creating another account with the same handle gracefully" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)

      first_oauth_identity = %{
        provider: :github,
        uid: System.unique_integer([:positive]),
        info: %{email: "find_or_create_user_from_oauth2@tuist.io"}
      }

      second_oauth_identity = %{
        provider: :github,
        uid: System.unique_integer([:positive]),
        info: %{email: "find_or_create_user_from_oauth1@tuist.test.io"}
      }

      # When
      %{account: %{name: first_account_handle}} =
        Accounts.find_or_create_user_from_oauth2(first_oauth_identity, preload: [:account])

      %{account: %{name: second_account_handle}} =
        Accounts.find_or_create_user_from_oauth2(second_oauth_identity, preload: [:account])

      # Then
      assert first_account_handle == "find-or-create-user-from-oauth2"
      assert second_account_handle == "find-or-create-user-from-oauth1"
    end

    test "assigns user role to SSO users for Google SSO" do
      # Given
      domain = unique_sso_domain()

      organization =
        AccountsFixtures.organization_fixture(
          sso_provider: :google,
          sso_organization_id: domain
        )

      # When
      user =
        Accounts.find_or_create_user_from_oauth2(google_oauth_identity(domain, email: unique_email(domain, "google-sso")))

      # Then
      assert Accounts.belongs_to_organization?(user, organization)
      assert Accounts.get_user_role_in_organization(user, organization).name == "user"
    end

    test "assigns user role to SSO users for Okta SSO" do
      # Given
      provider_organization_id = unique_sso_domain("okta")

      organization =
        AccountsFixtures.organization_fixture(
          sso_provider: :okta,
          sso_organization_id: provider_organization_id,
          oauth2_client_id: "client-id",
          oauth2_client_secret: "client-secret"
        )

      # When
      user =
        Accounts.find_or_create_user_from_oauth2(
          okta_oauth_identity(provider_organization_id, email: unique_email("tuist.dev", "okta-sso"))
        )

      # Then
      assert Accounts.belongs_to_organization?(user, organization)
      assert Accounts.get_user_role_in_organization(user, organization).name == "user"
    end

    test "sanitizes handle when creating user from OAuth2 with special characters in email" do
      # Given
      oauth_identity = %{
        provider: :github,
        uid: System.unique_integer([:positive]),
        info: %{email: "user+test@example.com"}
      }

      # When
      user = Accounts.find_or_create_user_from_oauth2(oauth_identity, preload: [:account])

      # Then
      assert user.account.name == "usertest"
    end

    test "sanitizes handle when creating user from OAuth2 with dots and underscores" do
      # Given
      oauth_identity = %{
        provider: :github,
        uid: System.unique_integer([:positive]),
        info: %{email: "user.name_test@example.com"}
      }

      # When
      user = Accounts.find_or_create_user_from_oauth2(oauth_identity, preload: [:account])

      # Then
      assert user.account.name == "user-name-test"
    end

    test "sanitizes handle when creating user from OAuth2 with plus sign" do
      # Given
      oauth_identity = %{
        provider: :github,
        uid: System.unique_integer([:positive]),
        info: %{email: "user+name@example.com"}
      }

      # When
      user = Accounts.find_or_create_user_from_oauth2(oauth_identity, preload: [:account])

      # Then
      assert user.account.name == "username"
    end

    test "sanitizes handle when creating user from OAuth2 with percent sign" do
      # Given
      oauth_identity = %{
        provider: :github,
        uid: System.unique_integer([:positive]),
        info: %{email: "user%name@test.com"}
      }

      # When
      user = Accounts.find_or_create_user_from_oauth2(oauth_identity, preload: [:account])

      # Then
      assert user.account.name == "username"
    end
  end

  describe "find_oauth2_identity/2" do
    test "returns github oauth2 identity when user also has a google identity" do
      # Given
      user = AccountsFixtures.user_fixture()

      Accounts.find_or_create_user_from_oauth2(%{
        provider: :github,
        uid: System.unique_integer([:positive]),
        info: %{
          email: user.email
        }
      })

      Accounts.find_or_create_user_from_oauth2(%{
        provider: :google,
        uid: System.unique_integer([:positive]),
        info: %{
          email: user.email
        },
        extra: %{
          raw_info: %{
            user: %{}
          }
        }
      })

      # When
      got = Accounts.find_oauth2_identity(%{user: user, provider: :github})

      # Then
      assert got.provider == :github
    end

    test "returns google oauth2 identity" do
      # Given
      user = AccountsFixtures.user_fixture()

      Accounts.find_or_create_user_from_oauth2(%{
        provider: :google,
        uid: System.unique_integer([:positive]),
        info: %{
          email: user.email
        },
        extra: %{
          raw_info: %{
            user: %{}
          }
        }
      })

      # When
      got = Accounts.find_oauth2_identity(%{user: user, provider: :google})

      # Then
      assert got.provider == :google
    end

    test "returns okta oauth2 identity" do
      # Given
      user = AccountsFixtures.user_fixture()

      Accounts.find_or_create_user_from_oauth2(%{
        provider: :okta,
        uid: "uid-#{System.unique_integer([:positive])}",
        info: %{
          email: user.email
        },
        extra: %{
          raw_info: %{
            provider_organization_id: unique_sso_domain("okta")
          }
        }
      })

      # When
      got = Accounts.find_oauth2_identity(%{user: user, provider: :okta})

      # Then
      assert got.provider == :okta
    end

    test "returns nil when a user only has a github identity" do
      # Given
      user = AccountsFixtures.user_fixture()

      Accounts.find_or_create_user_from_oauth2(%{
        provider: :github,
        uid: System.unique_integer([:positive]),
        info: %{
          email: user.email
        }
      })

      # When
      got = Accounts.find_oauth2_identity(%{user: user, provider: :google})

      # Then
      assert got == nil
    end
  end

  describe "delete_user/1" do
    test "deletes a user" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      Accounts.find_or_create_user_from_oauth2(%{
        provider: :github,
        uid: System.unique_integer([:positive]),
        info: %{
          email: user.email
        }
      })

      oauth2_identity = Accounts.find_oauth2_identity(%{user: user, provider: :github})
      organization = AccountsFixtures.organization_fixture()
      Accounts.add_user_to_organization(user, organization)

      CommandEventsFixtures.command_event_fixture(
        name: "generate",
        project_id: project.id,
        user_id: user.id
      )

      Accounts.update_last_visited_project(user, project.id)
      code = Accounts.create_device_code("some-code")
      Accounts.authenticate_device_code(code.code, user)

      # When
      Accounts.delete_user(user)

      # Then
      assert Accounts.get_user_by_id(user.id) == nil
      assert Accounts.get_account_by_id(account.id) == {:error, :not_found}
      assert Projects.get_project_by_id(project.id) == nil

      assert Accounts.get_oauth2_identity_by_provider_and_id(
               :github,
               oauth2_identity.id_in_provider
             ) == nil

      assert Accounts.belongs_to_organization?(user, organization) == false
      # ClickHouse event deletion is async (mutations_sync = 0), so we don't
      # assert immediate removal — the mutation will complete eventually.
      assert Accounts.get_device_code(code.code) == nil
    end
  end

  describe "get_organization_by_handle/1" do
    test "gets a given organization account doing a case-insensitive search" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      user = AccountsFixtures.user_fixture()

      {:ok, organization} =
        Accounts.create_organization(%{name: "tuist", creator: user}, preload: [:account])

      # When
      got = Accounts.get_organization_by_handle("TUIST")

      # Then
      assert organization == got
    end
  end

  describe "get_account_by_handle/1" do
    test "does case-insensitive searches" do
      # Given
      %{account: %{name: handle}} = AccountsFixtures.user_fixture(preload: [:account])

      # When
      got = Accounts.get_account_by_handle(String.upcase(handle))

      # Then
      assert got
    end
  end

  describe "create_user/1" do
    test "doesn't start biling trial if it's an on-premise environment" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> false end)
      stub(Environment, :skip_email_confirmation?, fn -> false end)
      email = unique_user_email()

      # When
      {:ok, user} = Accounts.create_user(email, password: valid_user_password())

      # Then
      assert user.email == email
      assert is_binary(user.encrypted_password)
      assert is_nil(user.confirmed_at)
    end

    test "create a user with a password" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      stub(Environment, :skip_email_confirmation?, fn -> false end)
      email = unique_user_email()

      # When
      {:ok, user} = Accounts.create_user(email, password: valid_user_password())

      # Then
      assert user.email == email
      assert is_binary(user.encrypted_password)
      assert is_nil(user.confirmed_at)
    end

    test "auto-bootstraps the protected linux runner profile" do
      # Same default-profile invariant the organization path enforces:
      # personal accounts land with the `linux` profile so the
      # `<prefix>linux` label resolves from the first workflow run.
      stub(Environment, :tuist_hosted?, fn -> true end)
      stub(Environment, :skip_email_confirmation?, fn -> false end)

      {:ok, user} = Accounts.create_user(unique_user_email(), password: valid_user_password())

      profiles = RunnerProfiles.list_for_account(user.account)

      assert %{name: "linux", protected: true, vcpus: 2, memory_gb: 8} =
               Enum.find(profiles, &(&1.name == "linux"))
    end

    test "creates the user infering the handle from the email when no handle is provided" do
      # Given
      stub(Environment, :skip_email_confirmation?, fn -> false end)
      email = unique_user_email()

      # When
      {:ok, user} = Accounts.create_user(email, password: valid_user_password())

      # Then
      assert user.account.name == email |> String.split("@") |> List.first()
      assert is_binary(user.encrypted_password)
      assert is_nil(user.confirmed_at)
    end

    test "create a user with a password when new pricing model is enabled" do
      # Given
      stub(Environment, :skip_email_confirmation?, fn -> false end)
      email = unique_user_email()

      # When
      {:ok, user} = Accounts.create_user(email, password: valid_user_password())

      # Then
      assert user.email == email
      assert is_binary(user.encrypted_password)
      assert is_nil(user.confirmed_at)
    end

    test "create a user lowercasing the email" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      email = "#{unique_integer()}@TUIST.io"

      # When
      {:ok, user} = Accounts.create_user(email, password: valid_user_password())

      # Then
      assert user.email == String.downcase(email)
    end

    test "create a user with a password when email has a dot in the username" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      stub(Environment, :skip_email_confirmation?, fn -> false end)
      email = "username.with.dot@tuist.io"

      # When
      {:ok, user} = Accounts.create_user(email, password: valid_user_password())

      # Then
      account = Accounts.get_account_from_user(user)
      assert user.email == email
      assert account.name == "username-with-dot"
      assert is_binary(user.encrypted_password)
      assert is_nil(user.confirmed_at)
    end

    test "creates the user when there's already a user with the same handle derived from email" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      Accounts.create_user("foo@tuist.io")

      # When
      assert %{name: "foo1"} =
               "foo@tuist.test"
               |> Accounts.create_user()
               |> elem(1)
               |> Accounts.get_account_from_user()
    end

    test "errors after attempting finding a unique account handle using suffixes" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      Accounts.create_user("foo@tuist.io")

      for i <- 1..20 do
        Accounts.create_user("foo#{i}@tuist.io")
      end

      # When
      {:error, :account_handle_taken} = Accounts.create_user("foo@tuist.test")
    end

    test "errors after creating user with an email that already exists" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      Accounts.create_user("foo@tuist.io")

      # When
      assert {:error, :email_taken} = Accounts.create_user("foo@tuist.io")
    end

    test "sanitizes handle by removing non-alphanumeric characters from email" do
      # Given
      email = "user+test@example.com"

      # When
      {:ok, user} = Accounts.create_user(email, password: valid_user_password())

      # Then
      assert user.account.name == "usertest"
    end

    test "sanitizes handle by removing special characters and preserving dots as hyphens" do
      # Given
      email = "user.name_test@example.com"

      # When
      {:ok, user} = Accounts.create_user(email, password: valid_user_password())

      # Then
      assert user.account.name == "user-name-test"
    end

    test "sanitizes handle by removing plus sign" do
      # Given
      email = "user+name@example.com"

      # When
      {:ok, user} = Accounts.create_user(email, password: valid_user_password())

      # Then
      assert user.account.name == "username"
    end

    test "sanitizes handle by removing percent sign" do
      # Given
      email = "user%name@test.com"

      # When
      {:ok, user} = Accounts.create_user(email, password: valid_user_password())

      # Then
      assert user.account.name == "username"
    end
  end

  describe "change_user_password/2" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_password(%User{})
      assert changeset.required == [:password]
    end

    test "allows fields to be set" do
      changeset =
        Accounts.change_user_password(%User{}, %{
          "password" => "new valid password"
        })

      assert changeset.valid?
      assert get_change(changeset, :encrypted_password)
    end
  end

  describe "update_account/2" do
    setup do
      %{user: user_fixture()}
    end

    test "updates the user's name", %{user: user} do
      account = Repo.preload(user, :account).account
      assert {:ok, account} = Accounts.update_account(account, %{name: "christoph"})
      assert account.name == "christoph"
    end

    test "persists the custom cache endpoints enabled flag", %{user: user} do
      account = Repo.preload(user, :account).account
      assert account.custom_cache_endpoints_enabled == false

      assert {:ok, account} =
               Accounts.update_account(account, %{custom_cache_endpoints_enabled: true})

      assert account.custom_cache_endpoints_enabled == true

      assert {:ok, reloaded_account} = Accounts.get_account_by_id(account.id)
      assert reloaded_account.custom_cache_endpoints_enabled == true
    end

    test "persists the Kura cache write policy", %{user: user} do
      account = Repo.preload(user, :account).account
      assert account.kura_cache_write_policy == :members_and_tokens

      assert {:ok, account} =
               Accounts.update_account(account, %{kura_cache_write_policy: :tokens_only})

      assert account.kura_cache_write_policy == :tokens_only

      assert {:ok, reloaded_account} = Accounts.get_account_by_id(account.id)
      assert reloaded_account.kura_cache_write_policy == :tokens_only
    end

    test "validates name format", %{user: user} do
      account = Repo.preload(user, :account).account

      assert {:error, changeset} =
               Accounts.update_account(account, %{name: "Christoph.Schmatzler"})

      assert changeset.errors[:name]
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "session"

      # Creating the same token for another user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture().id,
          context: "session"
        })
      end
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert session_user = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
    end

    test "returns user by token with a preloaded account", %{user: user, token: token} do
      assert session_user = Accounts.get_user_by_session_token(token, preload: [:account])
      assert session_user.id == user.id
      assert session_user.account == Accounts.get_account_from_user(user)
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_session_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "delete_user_session_token/1" do
    test "deletes the token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.delete_user_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "deliver_user_confirmation_instructions/2" do
    setup do
      stub(Environment, :mailing_from_address, fn -> "noreply@tuist.dev" end)
      %{user: user_fixture(confirmed_at: nil)}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn confirmation_url ->
          Accounts.deliver_user_confirmation_instructions(%{
            user: user,
            confirmation_url: confirmation_url
          })
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "confirm"
    end
  end

  describe "confirm_user/1" do
    setup do
      user = user_fixture(confirmed_at: nil)

      stub(Environment, :mailing_from_address, fn -> "noreply@tuist.dev" end)

      token =
        extract_user_token(fn confirmation_url ->
          Accounts.deliver_user_confirmation_instructions(%{
            user: user,
            confirmation_url: confirmation_url
          })
        end)

      %{user: user, token: token}
    end

    test "confirms the email with a valid token", %{user: user, token: token} do
      assert {:ok, confirmed_user} = Accounts.confirm_user(token)
      assert confirmed_user.confirmed_at
      assert confirmed_user.confirmed_at != user.confirmed_at
      assert Repo.get!(User, user.id).confirmed_at
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not confirm with invalid token", %{user: user} do
      assert Accounts.confirm_user("oops") == :error
      refute Repo.get!(User, user.id).confirmed_at
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not confirm email if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      assert Accounts.confirm_user(token) == :error
      refute Repo.get!(User, user.id).confirmed_at
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "deliver_user_reset_password_instructions/2" do
    setup do
      stub(Environment, :mailing_from_address, fn -> "noreply@tuist.dev" end)
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn reset_password_url ->
          Accounts.deliver_user_reset_password_instructions(%{
            user: user,
            reset_password_url: reset_password_url
          })
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "reset_password"
    end

    test "does not create another reset password token during the cooldown window", %{user: user} do
      reset_password_url = &"/users/reset_password/#{&1}"

      Accounts.deliver_user_reset_password_instructions(%{
        user: user,
        reset_password_url: reset_password_url
      })

      assert Repo.aggregate(
               from(t in UserToken, where: t.user_id == ^user.id and t.context == "reset_password"),
               :count,
               :id
             ) == 1

      assert :ok =
               Accounts.deliver_user_reset_password_instructions(%{
                 user: user,
                 reset_password_url: reset_password_url
               })

      assert Repo.aggregate(
               from(t in UserToken, where: t.user_id == ^user.id and t.context == "reset_password"),
               :count,
               :id
             ) == 1
    end
  end

  describe "get_user_by_reset_password_token/1" do
    setup do
      user = user_fixture()

      stub(Environment, :mailing_from_address, fn -> "noreply@tuist.dev" end)

      token =
        extract_user_token(fn reset_password_url ->
          Accounts.deliver_user_reset_password_instructions(%{
            user: user,
            reset_password_url: reset_password_url
          })
        end)

      %{user: user, token: token}
    end

    test "returns the user with valid token", %{user: %{id: id}, token: token} do
      assert %User{id: ^id} = Accounts.get_user_by_reset_password_token(token)
      assert Repo.get_by(UserToken, user_id: id)
    end

    test "does not return the user with invalid token", %{user: user} do
      refute Accounts.get_user_by_reset_password_token("oops")
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not return the user if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Accounts.get_user_by_reset_password_token(token)
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "reset_user_password/2" do
    setup do
      %{user: user_fixture()}
    end

    test "updates the password", %{user: user} do
      {:ok, %{user: updated_user}} =
        Accounts.reset_user_password(user, %{"password" => "new valid password"})

      assert updated_user.id == user.id
      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "deletes all tokens for the given user", %{user: user} do
      _ = Accounts.generate_user_session_token(user)
      {:ok, _} = Accounts.reset_user_password(user, %{"password" => "new valid password"})
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "returns revoked session live socket ids", %{user: user} do
      session_token = Accounts.generate_user_session_token(user)

      assert {:ok, %{revoked_session_live_socket_ids: [live_socket_id]}} =
               Accounts.reset_user_password(user, %{"password" => "new valid password"})

      assert live_socket_id == UserToken.live_socket_id(session_token)
    end
  end

  describe "update_organization/2" do
    test "updates organization with a google hosted domain" do
      # Given
      domain = unique_sso_domain()
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: user)

      # When
      {:ok, organization} =
        Accounts.update_organization(organization, %{
          sso_provider: :google,
          sso_organization_id: domain
        })

      # Then
      assert organization.sso_organization_id == domain
      assert organization.sso_provider == :google
    end

    test "updates organization with an okta hosted domain" do
      # Given
      provider_organization_id = unique_sso_domain("okta")
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: user)

      # When
      {:ok, organization} =
        Accounts.update_organization(organization, %{
          sso_provider: :okta,
          sso_organization_id: provider_organization_id,
          oauth2_client_id: "client-id",
          oauth2_encrypted_client_secret: "client-secret",
          oauth2_authorize_url: "https://#{provider_organization_id}/oauth2/v1/authorize",
          oauth2_token_url: "https://#{provider_organization_id}/oauth2/v1/token",
          oauth2_user_info_url: "https://#{provider_organization_id}/oauth2/v1/userinfo"
        })

      # Then
      assert organization.sso_organization_id == provider_organization_id
      assert organization.sso_provider == :okta
    end

    test "assigns existing SSO users when enabling Google SSO" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      domain = unique_sso_domain()

      organization = AccountsFixtures.organization_fixture()

      # Create an existing user with Google OAuth2 identity
      existing_user =
        Accounts.find_or_create_user_from_oauth2(google_oauth_identity(domain, email: unique_email(domain, "user")))

      # Verify user is not yet assigned to organization
      refute Accounts.belongs_to_organization?(existing_user, organization)

      # When - Enable Google SSO for the organization
      {:ok, updated_organization} =
        Accounts.update_organization(organization, %{
          sso_provider: :google,
          sso_organization_id: domain
        })

      # Then
      assert updated_organization.sso_provider == :google
      assert updated_organization.sso_organization_id == domain

      # Existing SSO user should now be assigned to the organization with explicit role
      assert Accounts.belongs_to_organization?(existing_user, updated_organization)

      assert Accounts.get_user_role_in_organization(existing_user, updated_organization).name ==
               "user"
    end

    test "assigns existing SSO users when enabling Okta SSO" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      provider_organization_id = unique_sso_domain("okta")

      organization = AccountsFixtures.organization_fixture()

      # Create an existing user with Okta OAuth2 identity
      existing_user =
        Accounts.find_or_create_user_from_oauth2(
          okta_oauth_identity(provider_organization_id, email: unique_email("tuist.dev", "user"))
        )

      # Verify user is not yet assigned to organization
      refute Accounts.belongs_to_organization?(existing_user, organization)

      # When - Enable Okta SSO for the organization
      {:ok, updated_organization} =
        Accounts.update_organization(organization, %{
          sso_provider: :okta,
          sso_organization_id: provider_organization_id,
          oauth2_client_id: "client-id",
          oauth2_encrypted_client_secret: "client-secret",
          oauth2_authorize_url: "https://#{provider_organization_id}/oauth2/v1/authorize",
          oauth2_token_url: "https://#{provider_organization_id}/oauth2/v1/token",
          oauth2_user_info_url: "https://#{provider_organization_id}/oauth2/v1/userinfo"
        })

      # Then
      assert updated_organization.sso_provider == :okta
      assert updated_organization.sso_organization_id == provider_organization_id

      # Existing SSO user should now be assigned to the organization with explicit role
      assert Accounts.belongs_to_organization?(existing_user, updated_organization)

      assert Accounts.get_user_role_in_organization(existing_user, updated_organization).name ==
               "user"
    end

    test "does not assign users when SSO is updated but not newly enabled" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      existing_domain = unique_sso_domain("existing")
      new_domain = unique_sso_domain()

      # Create organization with SSO already enabled
      organization =
        AccountsFixtures.organization_fixture(
          sso_provider: :google,
          sso_organization_id: existing_domain
        )

      # Create a user with a domain that doesn't match any SSO organization yet
      other_user =
        Accounts.find_or_create_user_from_oauth2(
          google_oauth_identity(new_domain, email: unique_email(new_domain, "user"))
        )

      # Verify user is not assigned to organization (different domain)
      refute Accounts.belongs_to_organization?(other_user, organization)

      # When - Update SSO organization ID (not newly enabling)
      {:ok, updated_organization} =
        Accounts.update_organization(organization, %{
          sso_organization_id: new_domain
        })

      # Then
      assert updated_organization.sso_organization_id == new_domain

      # User should have SSO-based access (automatic through belongs_to_sso_organization)
      assert Accounts.belongs_to_sso_organization?(other_user, updated_organization)

      # But should NOT have an explicit role assignment (because SSO wasn't newly enabled)
      assert is_nil(Accounts.get_user_role_in_organization(other_user, updated_organization))
    end

    test "assigns multiple existing SSO users when enabling SSO" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      domain = unique_sso_domain()

      organization = AccountsFixtures.organization_fixture()

      # Create multiple existing users with Google OAuth2 identities
      user1 =
        Accounts.find_or_create_user_from_oauth2(google_oauth_identity(domain, email: unique_email(domain, "user1")))

      user2 =
        Accounts.find_or_create_user_from_oauth2(google_oauth_identity(domain, email: unique_email(domain, "user2")))

      # Verify users are not yet assigned to organization
      refute Accounts.belongs_to_organization?(user1, organization)
      refute Accounts.belongs_to_organization?(user2, organization)

      # When - Enable Google SSO for the organization
      {:ok, updated_organization} =
        Accounts.update_organization(organization, %{
          sso_provider: :google,
          sso_organization_id: domain
        })

      # Then
      # Both existing SSO users should now be assigned to the organization with explicit roles
      assert Accounts.belongs_to_organization?(user1, updated_organization)
      assert Accounts.belongs_to_organization?(user2, updated_organization)
      assert Accounts.get_user_role_in_organization(user1, updated_organization).name == "user"
      assert Accounts.get_user_role_in_organization(user2, updated_organization).name == "user"
    end
  end

  describe "find_or_create_user_from_oauth2/1" do
    test "creates a user from a github identity" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      email = unique_user_email()

      # When
      user =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :github,
          uid: System.unique_integer([:positive]),
          info: %{
            email: email
          }
        })

      # Then
      assert user.email == email
    end

    test "creates a user from a google identity with a hosted domain" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      domain = unique_sso_domain()
      uid = System.unique_integer([:positive])
      email = unique_email(domain)

      # When
      user =
        Accounts.find_or_create_user_from_oauth2(google_oauth_identity(domain, uid: uid, email: email))

      # Then
      assert user.email == email
      oauth2_identity = Accounts.get_oauth2_identity_by_provider_and_id(:google, uid)
      assert oauth2_identity.provider_organization_id == domain
    end

    test "creates a user from a google identity without a hosted domain" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      uid = System.unique_integer([:positive])
      email = unique_user_email()

      # When
      user =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :google,
          uid: uid,
          info: %{
            email: email
          },
          extra: %{
            raw_info: %{
              user: %{
                "hd" => nil
              }
            }
          }
        })

      # Then
      assert user.email == email
      oauth2_identity = Accounts.get_oauth2_identity_by_provider_and_id(:google, uid)
      assert oauth2_identity.provider_organization_id == nil
    end

    test "updates an existing user with a new github identity" do
      email = unique_user_email()
      user = user_fixture(email: email)

      got =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :github,
          uid: System.unique_integer([:positive]),
          info: %{
            email: email
          }
        })

      assert user.email == got.email
      assert Accounts.find_oauth2_identity(%{user: user, provider: :github})
    end

    test "updates an existing user with a new okta identity" do
      email = unique_user_email()
      provider_organization_id = unique_sso_domain("okta")
      user = user_fixture(email: email)

      got =
        Accounts.find_or_create_user_from_oauth2(okta_oauth_identity(provider_organization_id, email: email))

      assert user.email == got.email
      assert Accounts.find_oauth2_identity(%{user: user, provider: :okta})
    end

    test "handles reserved handle names by adding a suffix" do
      # When
      user =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :github,
          uid: System.unique_integer([:positive]),
          info: %{
            email: "admin@example.com"
          }
        })

      # Then
      assert user.email == "admin@example.com"
      account = Accounts.get_account_from_user(user)
      # The handle should be "admin-" followed by a random number
      assert String.starts_with?(account.name, "admin-")
      assert account.name != "admin"
    end
  end

  describe "authenticate_device_code/2" do
    test "authenticates existing DeviceCode" do
      # Given
      device_code = Accounts.create_device_code("AOKJ-1234")
      user = AccountsFixtures.user_fixture()

      # When
      authenticated_device_code = Accounts.authenticate_device_code(device_code.code, user)

      # Then
      assert device_code.authenticated == false
      assert authenticated_device_code.authenticated == true
      assert authenticated_device_code.user_id == user.id
    end
  end

  describe "get_account_from_customer_id/1" do
    test "returns {:ok, account} with the given customer_id" do
      # Given
      stub(Stripe.Customer, :create, fn _ -> {:ok, %Stripe.Customer{id: "customer_id"}} end)
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      customer_id = account.customer_id

      # When
      got = Accounts.get_account_from_customer_id(customer_id)

      # Then
      assert got == {:ok, account}
    end

    test "returns {:error, :not_found} if the account with the given customer_id does not exist" do
      # Given
      AccountsFixtures.user_fixture()

      # When
      got = Accounts.get_account_from_customer_id("unknown")

      # Then
      assert got == {:error, :not_found}
    end
  end

  describe "remove_user_from_organization/1" do
    test "removes a user from an organization" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture()
      Accounts.add_user_to_organization(user, organization, role: :user)

      # When
      :ok = Accounts.remove_user_from_organization(user, organization)

      # Then
      assert Accounts.get_organization_members(organization, :user) == []
    end

    test "deletes a user when a user belongs to the SSO organization" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      domain = unique_sso_domain()

      organization =
        AccountsFixtures.organization_fixture(
          sso_provider: :google,
          sso_organization_id: domain
        )

      user =
        Accounts.find_or_create_user_from_oauth2(google_oauth_identity(domain))

      # When
      :ok = Accounts.remove_user_from_organization(user, organization)

      # Then
      assert Accounts.get_organization_members(organization, :user) == []
    end

    test "returns :ok if a user does not belong to the organization" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture()

      # When
      got = Accounts.remove_user_from_organization(user, organization)

      # Then
      assert got == :ok
    end
  end

  describe "add_user_to_organization/3" do
    test "does not create duplicate roles when called twice with same role" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture()

      # When - Add user to organization twice with :user role
      :ok = Accounts.add_user_to_organization(user, organization, role: :user)
      :ok = Accounts.add_user_to_organization(user, organization, role: :user)

      # Then - Should only have one role/user_role for this user+organization
      roles =
        Tuist.Repo.all(
          from(ur in UserRole,
            join: r in Role,
            on: ur.role_id == r.id,
            where:
              ur.user_id == ^user.id and r.resource_type == "Organization" and
                r.resource_id == ^organization.id,
            select: r
          )
        )

      assert length(roles) == 1
      assert hd(roles).name == "user"
    end

    test "does not create duplicate roles when called twice with different roles" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture()

      # When - Add user as :user, then try to add again as :admin (should not create duplicate)
      :ok = Accounts.add_user_to_organization(user, organization, role: :user)
      :ok = Accounts.add_user_to_organization(user, organization, role: :admin)

      # Then - Should only have one role (the first one created)
      roles =
        Tuist.Repo.all(
          from(ur in UserRole,
            join: r in Role,
            on: ur.role_id == r.id,
            where:
              ur.user_id == ^user.id and r.resource_type == "Organization" and
                r.resource_id == ^organization.id,
            select: r
          )
        )

      # The second call should be a no-op if a role already exists
      assert length(roles) == 1
    end
  end

  describe "update_user_role_in_organization/3" do
    test "Updates user role from user to admin" do
      # Given
      admin = AccountsFixtures.user_fixture()
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: admin)
      Accounts.add_user_to_organization(user, organization, role: :user)

      # When
      {:ok, _} = Accounts.update_user_role_in_organization(user, organization, :admin)

      # Then
      assert Accounts.organization_admin?(user, organization) == true
    end

    test "Updates user role from admin to user" do
      # Given
      admin = AccountsFixtures.user_fixture()
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: admin)
      Accounts.add_user_to_organization(user, organization, role: :admin)

      # When
      {:ok, _} = Accounts.update_user_role_in_organization(user, organization, :user)

      # Then
      assert Accounts.organization_admin?(user, organization) == false
    end
  end

  describe "get_organization_members/1" do
    test "returns admins of an organization" do
      # Given
      user_one = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: user_one)
      user_two = AccountsFixtures.user_fixture()
      Accounts.add_user_to_organization(user_two, organization, role: :user)
      user_three = AccountsFixtures.user_fixture()
      Accounts.add_user_to_organization(user_three, organization, role: :admin)

      organization_two = AccountsFixtures.organization_fixture()
      Accounts.add_user_to_organization(user_one, organization_two, role: :admin)

      # When
      got = Accounts.get_organization_members(organization, :admin)

      # Then
      assert [user_one.id, user_three.id] == got |> Enum.map(& &1.id) |> Enum.sort()
    end

    test "returns users of an organization" do
      # Given
      user_one = AccountsFixtures.user_fixture()
      domain = unique_sso_domain()

      organization =
        AccountsFixtures.organization_fixture(
          sso_provider: :google,
          sso_organization_id: domain
        )

      Accounts.add_user_to_organization(user_one, organization, role: :user)
      user_two = AccountsFixtures.user_fixture()
      Accounts.add_user_to_organization(user_two, organization, role: :admin)
      user_three = AccountsFixtures.user_fixture()
      Accounts.add_user_to_organization(user_three, organization, role: :user)

      organization_two = AccountsFixtures.organization_fixture()
      Accounts.add_user_to_organization(user_one, organization_two, role: :user)

      # When
      got = Accounts.get_organization_members(organization, :user)

      # Then
      assert [user_one.id, user_three.id] == got |> Enum.map(& &1.id) |> Enum.sort()
    end

    test "returns users of an organization with a google hosted domain" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      user_one = AccountsFixtures.user_fixture()
      domain = unique_sso_domain()
      other_domain = unique_sso_domain("tools")

      organization =
        AccountsFixtures.organization_fixture(
          sso_provider: :google,
          sso_organization_id: domain
        )

      Accounts.add_user_to_organization(user_one, organization, role: :user)
      AccountsFixtures.user_fixture()

      user_three =
        Accounts.find_or_create_user_from_oauth2(google_oauth_identity(domain))

      Accounts.find_or_create_user_from_oauth2(
        google_oauth_identity(other_domain, email: unique_email(other_domain, "tools"))
      )

      # When
      got = Accounts.get_organization_members(organization, :user)

      # Then
      assert [user_one.id, user_three.id] == got |> Enum.map(& &1.id) |> Enum.sort()
    end

    test "returns users of an organization with a given okta id" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      user_one = AccountsFixtures.user_fixture()
      provider_organization_id = unique_sso_domain("okta")
      other_provider_organization_id = unique_sso_domain("different-org")

      organization =
        AccountsFixtures.organization_fixture(
          sso_provider: :okta,
          sso_organization_id: provider_organization_id,
          oauth2_client_id: "client-id",
          oauth2_client_secret: "client-secret"
        )

      Accounts.add_user_to_organization(user_one, organization, role: :user)
      AccountsFixtures.user_fixture()

      user_three =
        Accounts.find_or_create_user_from_oauth2(okta_oauth_identity(provider_organization_id))

      Accounts.find_or_create_user_from_oauth2(
        okta_oauth_identity(other_provider_organization_id, email: unique_email("tuist.dev", "tools"))
      )

      # When
      got = Accounts.get_organization_members(organization, :user)

      # Then
      assert [user_one.id, user_three.id] == got |> Enum.map(& &1.id) |> Enum.sort()
    end
  end

  describe "get_organization_members_with_role/1" do
    test "returns members of an organization" do
      user_one = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: user_one)
      user_two = AccountsFixtures.user_fixture()
      Accounts.add_user_to_organization(user_two, organization, role: :user)
      user_three = AccountsFixtures.user_fixture()
      Accounts.add_user_to_organization(user_three, organization, role: :admin)

      organization_two = AccountsFixtures.organization_fixture()
      Accounts.add_user_to_organization(user_one, organization_two, role: :admin)

      # When
      got =
        organization
        |> Accounts.get_organization_members_with_role()
        |> Enum.sort(&(hd(&1).id < hd(&2).id))

      # Then
      assert [[user_one, "admin"], [user_two, "user"], [user_three, "admin"]] == got
    end

    test "includes SSO users for organizations with Google SSO" do
      user_one = AccountsFixtures.user_fixture()
      domain = unique_sso_domain()

      organization =
        AccountsFixtures.organization_fixture(
          creator: user_one,
          sso_provider: :google,
          sso_organization_id: domain
        )

      # Create an SSO user
      sso_user =
        Accounts.find_or_create_user_from_oauth2(google_oauth_identity(domain, email: unique_email(domain, "sso")))

      # Add a regular user
      user_two = AccountsFixtures.user_fixture()
      Accounts.add_user_to_organization(user_two, organization, role: :user)

      # When
      got =
        organization
        |> Accounts.get_organization_members_with_role()
        |> Enum.sort(&(hd(&1).id < hd(&2).id))

      # Then - should include admin, regular user, and SSO user
      assert length(got) == 3
      assert Enum.any?(got, fn [user, role] -> user.id == user_one.id and role == "admin" end)
      assert Enum.any?(got, fn [user, role] -> user.id == user_two.id and role == "user" end)
      assert Enum.any?(got, fn [user, role] -> user.id == sso_user.id and role == "user" end)
    end

    test "includes SSO users for organizations with Okta SSO" do
      user_one = AccountsFixtures.user_fixture()
      provider_organization_id = unique_sso_domain("okta")

      organization =
        AccountsFixtures.organization_fixture(
          creator: user_one,
          sso_provider: :okta,
          sso_organization_id: provider_organization_id,
          oauth2_client_id: "client-id",
          oauth2_client_secret: "client-secret"
        )

      # Create an SSO user
      sso_user =
        Accounts.find_or_create_user_from_oauth2(
          okta_oauth_identity(provider_organization_id, email: unique_email("tuist.dev", "okta"))
        )

      # When
      got =
        organization
        |> Accounts.get_organization_members_with_role()
        |> Enum.sort(&(hd(&1).id < hd(&2).id))

      # Then - should include admin and SSO user
      assert length(got) == 2
      assert Enum.any?(got, fn [user, role] -> user.id == user_one.id and role == "admin" end)
      assert Enum.any?(got, fn [user, role] -> user.id == sso_user.id and role == "user" end)
    end
  end

  describe "account_token/1" do
    test "returns account token" do
      # Given
      account = AccountsFixtures.user_fixture(preload: [:account]).account

      {:ok, {account_token, account_token_value}} =
        Accounts.create_account_token(%{account: account, scopes: ["project:cache:read"], name: "test-token"})

      # When
      {:ok, got} = Accounts.account_token(account_token_value)

      # Then
      assert got.id == account_token.id
    end

    test "returns invalid if the token is invalid" do
      # When
      got = Accounts.account_token("invalid-token")

      # Then
      assert {:error, :invalid_token} == got
    end

    test "returns invalid if the token root schema is valid, but the UUIDv7 component is invalid" do
      # When
      got = Accounts.account_token("audience_token-id-as-invalid-uuidv7_hash")

      # Then
      assert {:error, :invalid_token} == got
    end

    test "returns not found if the token does not exist" do
      # When
      got = Accounts.account_token("tuist_0fcc7a05-4f0d-490d-8545-1fe3171a2880_some-hash")

      # Then
      assert {:error, :not_found} == got
    end
  end

  describe "create_account_token/1" do
    test "creates account token" do
      # Given
      account = AccountsFixtures.user_fixture(preload: [:account]).account

      expect(Base64, :encode, fn _ -> "generated-hash" end)

      # When
      {:ok, {_, got_token_value}} =
        Accounts.create_account_token(%{
          account: account,
          scopes: ["project:cache:read"],
          name: "my-token"
        })

      # Then
      %{id: token_id} = Repo.one(AccountToken)
      assert "tuist_#{token_id}_generated-hash" == got_token_value
    end

    test "creates account token with all_projects: false by default" do
      # Given
      account = AccountsFixtures.user_fixture(preload: [:account]).account

      # When
      {:ok, {token, _}} =
        Accounts.create_account_token(%{
          account: account,
          scopes: ["project:cache:read"],
          name: "default-token"
        })

      # Then
      assert token.all_projects == false
    end

    test "creates account token with all_projects: true when explicitly set" do
      # Given
      account = AccountsFixtures.user_fixture(preload: [:account]).account

      # When
      {:ok, {token, _}} =
        Accounts.create_account_token(%{
          account: account,
          scopes: ["project:cache:read"],
          name: "all-projects-token",
          all_projects: true
        })

      # Then
      assert token.all_projects == true
    end

    test "creates account token with project restrictions" do
      # Given
      account = AccountsFixtures.user_fixture(preload: [:account]).account
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      {:ok, {token, _}} =
        Accounts.create_account_token(%{
          account: account,
          scopes: ["project:cache:read"],
          name: "restricted-token",
          all_projects: false,
          project_ids: [project.id]
        })

      # Then
      assert token.all_projects == false
      token_with_projects = Repo.preload(token, :projects)
      assert length(token_with_projects.projects) == 1
      assert hd(token_with_projects.projects).id == project.id
    end

    test "creates account token with multiple project restrictions" do
      # Given
      account = AccountsFixtures.user_fixture(preload: [:account]).account
      project1 = ProjectsFixtures.project_fixture(account_id: account.id)
      project2 = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      {:ok, {token, _}} =
        Accounts.create_account_token(%{
          account: account,
          scopes: ["project:cache:read"],
          name: "multi-project-token",
          all_projects: false,
          project_ids: [project1.id, project2.id]
        })

      # Then
      assert token.all_projects == false
      token_with_projects = Repo.preload(token, :projects)
      assert length(token_with_projects.projects) == 2
      project_ids = Enum.map(token_with_projects.projects, & &1.id)
      assert project1.id in project_ids
      assert project2.id in project_ids
    end
  end

  describe "list_account_tokens/2" do
    test "returns tokens for the account with pagination" do
      # Given
      account = AccountsFixtures.user_fixture(preload: [:account]).account
      AccountsFixtures.account_token_fixture(account: account, name: "token-1")
      AccountsFixtures.account_token_fixture(account: account, name: "token-2")

      # When
      {tokens, meta} = Accounts.list_account_tokens(account, %{page: 1, page_size: 10})

      # Then
      assert length(tokens) == 2
      assert meta.total_count == 2
    end

    test "does not return tokens from other accounts" do
      # Given
      account1 = AccountsFixtures.user_fixture(preload: [:account]).account
      account2 = AccountsFixtures.user_fixture(preload: [:account]).account
      AccountsFixtures.account_token_fixture(account: account1, name: "token-1")
      AccountsFixtures.account_token_fixture(account: account2, name: "token-2")

      # When
      {tokens, _meta} = Accounts.list_account_tokens(account1)

      # Then
      assert length(tokens) == 1
      assert hd(tokens).name == "token-1"
    end

    test "preloads projects association" do
      # Given
      account = AccountsFixtures.user_fixture(preload: [:account]).account
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      {:ok, {_token, _}} =
        Accounts.create_account_token(%{
          account: account,
          scopes: ["project:cache:read"],
          name: "restricted-token",
          all_projects: false,
          project_ids: [project.id]
        })

      # When
      {tokens, _meta} = Accounts.list_account_tokens(account)

      # Then
      assert length(tokens) == 1
      token = hd(tokens)
      assert Ecto.assoc_loaded?(token.projects)
      assert length(token.projects) == 1
      assert hd(token.projects).id == project.id
    end
  end

  describe "get_account_token_by_name/3" do
    test "returns token when found" do
      # Given
      account = AccountsFixtures.user_fixture(preload: [:account]).account
      token = AccountsFixtures.account_token_fixture(account: account, name: "my-token")

      # When
      {:ok, found_token} = Accounts.get_account_token_by_name(account, "my-token")

      # Then
      assert found_token.id == token.id
      assert found_token.name == "my-token"
    end

    test "returns error when token not found" do
      # Given
      account = AccountsFixtures.user_fixture(preload: [:account]).account

      # When
      result = Accounts.get_account_token_by_name(account, "non-existent")

      # Then
      assert {:error, :not_found} == result
    end

    test "does not return token from different account" do
      # Given
      account1 = AccountsFixtures.user_fixture(preload: [:account]).account
      account2 = AccountsFixtures.user_fixture(preload: [:account]).account
      AccountsFixtures.account_token_fixture(account: account1, name: "shared-name")

      # When
      result = Accounts.get_account_token_by_name(account2, "shared-name")

      # Then
      assert {:error, :not_found} == result
    end

    test "preloads specified associations" do
      # Given
      account = AccountsFixtures.user_fixture(preload: [:account]).account
      AccountsFixtures.account_token_fixture(account: account, name: "my-token")

      # When
      {:ok, found_token} =
        Accounts.get_account_token_by_name(account, "my-token", preload: [:projects])

      # Then
      assert Ecto.assoc_loaded?(found_token.projects)
    end
  end

  describe "delete_account_token/1" do
    test "deletes an account token" do
      # Given
      account = AccountsFixtures.user_fixture(preload: [:account]).account
      token = AccountsFixtures.account_token_fixture(account: account, name: "token-to-delete")

      # When
      {:ok, deleted_token} = Accounts.delete_account_token(token)

      # Then
      assert deleted_token.id == token.id
      assert {:error, :not_found} == Accounts.get_account_token_by_name(account, "token-to-delete")
    end

    test "deletes an account token with project associations" do
      # Given
      account = AccountsFixtures.user_fixture(preload: [:account]).account
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      {:ok, {token, _}} =
        Accounts.create_account_token(%{
          account: account,
          scopes: ["project:cache:read"],
          name: "restricted-token",
          all_projects: false,
          project_ids: [project.id]
        })

      # When
      {:ok, _} = Accounts.delete_account_token(token)

      # Then
      assert {:error, :not_found} == Accounts.get_account_token_by_name(account, "restricted-token")
    end
  end

  describe "account_token_expired?/1" do
    test "returns false when expires_at is nil" do
      # Given
      token = %AccountToken{expires_at: nil}

      # When/Then
      refute Accounts.account_token_expired?(token)
    end

    test "returns false when expires_at is in the future" do
      # Given
      token = %AccountToken{expires_at: DateTime.add(DateTime.utc_now(), 1, :hour)}

      # When/Then
      refute Accounts.account_token_expired?(token)
    end

    test "returns true when expires_at is in the past" do
      # Given
      token = %AccountToken{expires_at: DateTime.add(DateTime.utc_now(), -1, :hour)}

      # When/Then
      assert Accounts.account_token_expired?(token)
    end
  end

  describe "find_unassigned_sso_users/3" do
    test "finds users with matching SSO credentials not assigned to organization" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      domain = unique_sso_domain()

      # Create organization without SSO initially
      organization = AccountsFixtures.organization_fixture()

      # Create a user with matching Google OAuth2 identity
      unassigned_user =
        Accounts.find_or_create_user_from_oauth2(google_oauth_identity(domain, email: unique_email(domain, "unassigned")))

      # Create a user already assigned to the organization
      assigned_user =
        Accounts.find_or_create_user_from_oauth2(google_oauth_identity(domain, email: unique_email(domain, "assigned")))

      Accounts.add_user_to_organization(assigned_user, organization, role: :user)

      # Create a user with different SSO provider
      different_provider_user =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :github,
          uid: System.unique_integer([:positive]),
          info: %{email: unique_email(domain, "github")}
        })

      # When
      unassigned_users = Accounts.find_unassigned_sso_users(organization, :google, domain)

      # Then
      user_ids = Enum.map(unassigned_users, & &1.id)
      assert unassigned_user.id in user_ids
      refute assigned_user.id in user_ids
      refute different_provider_user.id in user_ids
    end

    test "returns empty list when no matching users exist" do
      # Given
      domain = unique_sso_domain()

      organization =
        AccountsFixtures.organization_fixture(
          sso_provider: :google,
          sso_organization_id: domain
        )

      # When
      unassigned_users = Accounts.find_unassigned_sso_users(organization, :google, domain)

      # Then
      assert unassigned_users == []
    end
  end

  describe "assign_existing_sso_users_to_organization/3" do
    test "assigns matching SSO users to organization and returns count" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      domain = unique_sso_domain()

      organization = AccountsFixtures.organization_fixture()

      # Create multiple users with matching Google OAuth2 identities
      user1 =
        Accounts.find_or_create_user_from_oauth2(google_oauth_identity(domain, email: unique_email(domain, "user1")))

      user2 =
        Accounts.find_or_create_user_from_oauth2(google_oauth_identity(domain, email: unique_email(domain, "user2")))

      # Verify users are not assigned to organization
      refute Accounts.belongs_to_organization?(user1, organization)
      refute Accounts.belongs_to_organization?(user2, organization)

      # When
      count =
        Accounts.assign_existing_sso_users_to_organization(organization, :google, domain)

      # Then
      assert count == 2
      assert Accounts.belongs_to_organization?(user1, organization)
      assert Accounts.belongs_to_organization?(user2, organization)
      assert Accounts.get_user_role_in_organization(user1, organization).name == "user"
      assert Accounts.get_user_role_in_organization(user2, organization).name == "user"
    end

    test "returns 0 when no matching users exist" do
      # Given
      domain = unique_sso_domain()
      organization = AccountsFixtures.organization_fixture()

      # When
      count =
        Accounts.assign_existing_sso_users_to_organization(organization, :google, domain)

      # Then
      assert count == 0
    end
  end

  describe "delete_account/1" do
    test "deletes a user account successfully" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      # When
      Accounts.delete_account!(account)

      # Then
      assert Accounts.get_user_by_id(user.id) == nil
      assert Accounts.get_account_by_id(account.id) == {:error, :not_found}
    end

    test "deletes an organization account successfully" do
      # Given
      user = AccountsFixtures.user_fixture()
      {:ok, organization} = Accounts.create_organization(%{name: "test-org", creator: user})
      account = Accounts.get_account_from_organization(organization)

      # When
      Accounts.delete_account!(account)

      # Then
      assert Accounts.get_organization_by_id(organization.id) == {:error, :not_found}
      assert Accounts.get_account_by_id(account.id) == {:error, :not_found}
    end
  end

  describe "sso_configured?/0" do
    test "returns false when no organization has SSO configured" do
      AccountsFixtures.organization_fixture()

      refute Accounts.sso_configured?()
    end

    test "returns true when an organization has Okta SSO configured" do
      AccountsFixtures.organization_fixture(
        sso_provider: :okta,
        sso_organization_id: "company.okta.com",
        oauth2_client_id: "client-id",
        oauth2_client_secret: "client-secret"
      )

      assert Accounts.sso_configured?()
    end

    test "returns true when an organization has generic OAuth2 SSO configured" do
      AccountsFixtures.organization_fixture(
        sso_provider: :oauth2,
        sso_organization_id: "https://id.company.com",
        oauth2_client_id: "client-id",
        oauth2_client_secret: "client-secret",
        oauth2_authorize_url: "https://id.company.com/authorize",
        oauth2_token_url: "https://id.company.com/token",
        oauth2_user_info_url: "https://id.company.com/userinfo"
      )

      assert Accounts.sso_configured?()
    end

    test "returns false when the only SSO organization uses Google" do
      AccountsFixtures.organization_fixture(sso_provider: :google, sso_organization_id: "company.com")

      refute Accounts.sso_configured?()
    end
  end

  describe "sso_organization_for_user_email/1" do
    test "returns organization when user exists and has okta organization" do
      user = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :okta,
          sso_organization_id: "company.okta.com",
          oauth2_client_id: "client-id",
          oauth2_client_secret: "client-secret"
        )

      {:ok, got_organization} = Accounts.sso_organization_for_user_email(user.email)

      assert got_organization.id == organization.id
      assert got_organization.sso_provider == :okta
    end

    test "returns error when user does not exist" do
      assert {:error, :not_found} ==
               Accounts.sso_organization_for_user_email("nonexistent@example.com")
    end

    test "returns error when user exists but has no SSO organization" do
      user = AccountsFixtures.user_fixture()

      assert {:error, :not_found} == Accounts.sso_organization_for_user_email(user.email)
    end

    test "returns error when user has organization but no sso configured" do
      user = AccountsFixtures.user_fixture()
      AccountsFixtures.organization_fixture(creator: user)

      assert {:error, :not_found} == Accounts.sso_organization_for_user_email(user.email)
    end

    test "returns error when user has google sso instead of okta" do
      user = AccountsFixtures.user_fixture()

      AccountsFixtures.organization_fixture(
        creator: user,
        sso_provider: :google,
        sso_organization_id: "company.com"
      )

      assert {:error, :not_found} == Accounts.sso_organization_for_user_email(user.email)
    end

    test "falls back to domain-based matching for okta when user is not in SSO organization" do
      creator = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(
          creator: creator,
          sso_provider: :okta,
          sso_organization_id: "example.okta.com",
          oauth2_client_id: "client-id",
          oauth2_client_secret: "client-secret"
        )

      {:ok, got_organization} =
        Accounts.sso_organization_for_user_email("someone@example.com")

      assert got_organization.id == organization.id
    end

    test "falls back to domain-based matching for custom oauth2 when user is not in SSO organization" do
      creator = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(
          creator: creator,
          sso_provider: :oauth2,
          sso_organization_id: "https://example.com",
          oauth2_client_id: "client-id",
          oauth2_client_secret: "client-secret",
          oauth2_authorize_url: "https://example.com/authorize",
          oauth2_token_url: "https://example.com/token",
          oauth2_user_info_url: "https://example.com/userinfo"
        )

      {:ok, got_organization} =
        Accounts.sso_organization_for_user_email("someone@example.com")

      assert got_organization.id == organization.id
    end

    test "domain-based fallback returns error when no matching organization" do
      assert {:error, :not_found} ==
               Accounts.sso_organization_for_user_email("someone@nomatch.com")
    end

    test "domain-based fallback skips Google SSO organizations" do
      creator = AccountsFixtures.user_fixture()

      _google_org =
        AccountsFixtures.organization_fixture(
          creator: creator,
          sso_provider: :google,
          sso_organization_id: "example.com"
        )

      assert {:error, :not_found} ==
               Accounts.sso_organization_for_user_email("someone@example.com")
    end
  end

  describe "get_oauth2_identity/2" do
    test "returns {:ok, identity} when OAuth2 identity exists" do
      # Given
      provider = :github
      uid = System.unique_integer([:positive])

      user =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: provider,
          uid: uid,
          info: %{email: "oauth-exists-test-#{uid}@example.com"}
        })

      # When
      {:ok, identity} = Accounts.get_oauth2_identity(provider, uid)

      # Then
      assert identity.provider == provider
      assert identity.id_in_provider == to_string(uid)
      assert identity.user.id == user.id
    end

    test "returns {:error, :not_found} when OAuth2 identity does not exist" do
      # When/Then
      assert {:error, :not_found} = Accounts.get_oauth2_identity(:github, "nonexistent-uid")
    end

    test "returns {:error, :not_found} for different provider with same uid" do
      # Given
      uid = System.unique_integer([:positive])

      Accounts.find_or_create_user_from_oauth2(%{
        provider: :github,
        uid: uid,
        info: %{email: "oauth-provider-test-#{uid}@example.com"}
      })

      # When/Then
      assert {:error, :not_found} = Accounts.get_oauth2_identity(:google, uid)
    end
  end

  describe "link_oauth_identity_to_user/2" do
    test "links OAuth identity to an existing user" do
      # Given
      user = user_fixture(email: "existing-user@example.com")

      attrs = %{
        provider: :google,
        id_in_provider: "google-uid-#{System.unique_integer([:positive])}",
        provider_organization_id: nil
      }

      # When
      {:ok, oauth_identity} = Accounts.link_oauth_identity_to_user(user, attrs)

      # Then
      assert oauth_identity.user_id == user.id
      assert oauth_identity.provider == :google
      assert oauth_identity.id_in_provider == to_string(attrs.id_in_provider)
    end

    test "the linked OAuth identity can be retrieved" do
      # Given
      user = user_fixture(email: "link-test@example.com")
      uid = "google-uid-#{System.unique_integer([:positive])}"

      attrs = %{
        provider: :google,
        id_in_provider: uid,
        provider_organization_id: nil
      }

      # When
      {:ok, _oauth_identity} = Accounts.link_oauth_identity_to_user(user, attrs)

      # Then
      {:ok, retrieved} = Accounts.get_oauth2_identity(:google, uid)
      assert retrieved.user.id == user.id
    end

    test "assigns user to SSO organization when provider_organization_id matches" do
      # Given
      organization =
        organization_fixture(
          sso_provider: :google,
          sso_organization_id: "link-sso-test.io"
        )

      user = user_fixture(email: "link-sso-user@example.com")

      attrs = %{
        provider: :google,
        id_in_provider: "google-uid-#{System.unique_integer([:positive])}",
        provider_organization_id: "link-sso-test.io"
      }

      # When
      {:ok, _oauth_identity} = Accounts.link_oauth_identity_to_user(user, attrs)

      # Then
      assert Accounts.belongs_to_organization?(user, organization)
    end

    test "returns error when OAuth identity already exists for that provider and uid" do
      # Given
      user1 = user_fixture(email: "user1@example.com")
      user2 = user_fixture(email: "user2@example.com")
      uid = "shared-uid-#{System.unique_integer([:positive])}"

      attrs = %{
        provider: :github,
        id_in_provider: uid,
        provider_organization_id: nil
      }

      # First link succeeds
      {:ok, _} = Accounts.link_oauth_identity_to_user(user1, attrs)

      # When - second link to same OAuth identity fails
      {:error, changeset} = Accounts.link_oauth_identity_to_user(user2, attrs)

      # Then
      assert changeset.errors != []
    end
  end

  describe "extract_provider_organization_id/1" do
    test "extracts hosted domain for Google provider" do
      # Given
      auth = %{
        provider: :google,
        extra: %{
          raw_info: %{
            user: %{"hd" => "tuist.io"}
          }
        }
      }

      # When
      result = Accounts.extract_provider_organization_id(auth)

      # Then
      assert result == "tuist.io"
    end

    test "returns nil for Google provider without hosted domain" do
      # Given
      auth = %{
        provider: :google,
        extra: %{
          raw_info: %{
            user: %{}
          }
        }
      }

      # When
      result = Accounts.extract_provider_organization_id(auth)

      # Then
      assert is_nil(result)
    end

    test "returns nil for GitHub provider" do
      # Given
      auth = %{
        provider: :github,
        extra: %{
          raw_info: %{
            user: %{}
          }
        }
      }

      # When
      result = Accounts.extract_provider_organization_id(auth)

      # Then
      assert is_nil(result)
    end

    test "returns nil for Apple provider" do
      # Given
      auth = %{
        provider: :apple,
        extra: %{
          raw_info: %{
            user: %{}
          }
        }
      }

      # When
      result = Accounts.extract_provider_organization_id(auth)

      # Then
      assert is_nil(result)
    end

    test "extracts provider_organization_id for Okta provider" do
      auth = %{
        provider: :okta,
        extra: %{
          raw_info: %{
            provider_organization_id: "tuist.okta.com"
          }
        }
      }

      result = Accounts.extract_provider_organization_id(auth)

      assert result == "tuist.okta.com"
    end
  end

  describe "create_user_from_pending_oauth/2" do
    test "creates user with specified username" do
      # Given
      oauth_data = %{
        "provider" => "github",
        "uid" => "oauth-uid-#{System.unique_integer([:positive])}",
        "email" => "newuser-#{System.unique_integer([:positive])}@example.com",
        "provider_organization_id" => nil
      }

      username = "chosen-username-#{System.unique_integer([:positive])}"

      # When
      {:ok, user} = Accounts.create_user_from_pending_oauth(oauth_data, username)

      # Then
      assert user.account.name == username
      assert user.email == oauth_data["email"]
    end

    test "creates OAuth2 identity for the user" do
      # Given
      uid = "oauth-uid-#{System.unique_integer([:positive])}"

      oauth_data = %{
        "provider" => "github",
        "uid" => uid,
        "email" => "newuser-#{System.unique_integer([:positive])}@example.com",
        "provider_organization_id" => nil
      }

      username = "chosen-username-#{System.unique_integer([:positive])}"

      # When
      {:ok, _user} = Accounts.create_user_from_pending_oauth(oauth_data, username)

      # Then
      assert {:ok, _identity} = Accounts.get_oauth2_identity(:github, uid)
    end

    test "assigns user to SSO organization when provider_organization_id matches" do
      # Given
      organization =
        AccountsFixtures.organization_fixture(
          sso_provider: :google,
          sso_organization_id: "sso-test.io"
        )

      oauth_data = %{
        "provider" => "google",
        "uid" => "oauth-uid-#{System.unique_integer([:positive])}",
        "email" => "ssouser-#{System.unique_integer([:positive])}@sso-test.io",
        "provider_organization_id" => "sso-test.io"
      }

      username = "sso-user-#{System.unique_integer([:positive])}"

      # When
      {:ok, user} = Accounts.create_user_from_pending_oauth(oauth_data, username)

      # Then
      assert Accounts.belongs_to_organization?(user, organization)
    end

    test "returns error when username is already taken" do
      # Given
      existing_user = AccountsFixtures.user_fixture()
      existing_username = existing_user.account.name

      oauth_data = %{
        "provider" => "github",
        "uid" => "oauth-uid-#{System.unique_integer([:positive])}",
        "email" => "newuser-#{System.unique_integer([:positive])}@example.com",
        "provider_organization_id" => nil
      }

      # When
      result = Accounts.create_user_from_pending_oauth(oauth_data, existing_username)

      # Then
      assert {:error, :account_handle_taken} = result
    end

    test "returns error for invalid username format" do
      # Given
      oauth_data = %{
        "provider" => "github",
        "uid" => "oauth-uid-#{System.unique_integer([:positive])}",
        "email" => "newuser-#{System.unique_integer([:positive])}@example.com",
        "provider_organization_id" => nil
      }

      invalid_username = "invalid username with spaces"

      # When
      result = Accounts.create_user_from_pending_oauth(oauth_data, invalid_username)

      # Then
      assert {:error, errors} = result
      assert Map.has_key?(errors, :name)
    end
  end

  describe "list_account_cache_endpoints/1" do
    test "returns empty list when account has no cache endpoints" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      # When
      endpoints = Accounts.list_account_cache_endpoints(account)

      # Then
      assert endpoints == []
    end

    test "returns cache endpoints for account" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      {:ok, endpoint1} = Accounts.create_account_cache_endpoint(account, %{url: "https://cache1.example.com"})
      {:ok, endpoint2} = Accounts.create_account_cache_endpoint(account, %{url: "https://cache2.example.com"})

      # When
      endpoints = Accounts.list_account_cache_endpoints(account)

      # Then
      assert length(endpoints) == 2
      endpoint_ids = Enum.map(endpoints, & &1.id)
      assert endpoint1.id in endpoint_ids
      assert endpoint2.id in endpoint_ids
    end

    test "returns only endpoints for the requested technology" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      {:ok, default_endpoint} = Accounts.create_account_cache_endpoint(account, %{url: "https://cache1.example.com"})

      {:ok, _kura_endpoint} =
        Accounts.create_account_cache_endpoint(account, %{
          url: "https://kura-cache.example.com",
          technology: :kura
        })

      # When
      endpoints = Accounts.list_account_cache_endpoints(account, :default)

      # Then
      assert Enum.map(endpoints, & &1.id) == [default_endpoint.id]
    end
  end

  describe "create_account_cache_endpoint/2" do
    test "creates cache endpoint with valid URL" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      # When
      {:ok, endpoint} = Accounts.create_account_cache_endpoint(account, %{url: "https://cache.example.com"})

      # Then
      assert endpoint.url == "https://cache.example.com"
      assert endpoint.account_id == account.id
      assert endpoint.technology == :default
    end

    test "returns error for invalid URL" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      # When
      {:error, changeset} = Accounts.create_account_cache_endpoint(account, %{url: "not-a-url"})

      # Then
      assert %{url: ["must be a valid HTTP or HTTPS URL"]} = errors_on(changeset)
    end

    test "returns error when adding duplicate URL for same account" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      {:ok, _endpoint} = Accounts.create_account_cache_endpoint(account, %{url: "https://cache.example.com"})

      # When
      {:error, changeset} = Accounts.create_account_cache_endpoint(account, %{url: "https://cache.example.com"})

      # Then
      assert %{account_id: ["has already been added"]} = errors_on(changeset)
    end

    test "allows same URL for different accounts" do
      # Given
      user1 = AccountsFixtures.user_fixture()
      user2 = AccountsFixtures.user_fixture()
      account1 = Accounts.get_account_from_user(user1)
      account2 = Accounts.get_account_from_user(user2)
      {:ok, _endpoint1} = Accounts.create_account_cache_endpoint(account1, %{url: "https://cache.example.com"})

      # When
      result = Accounts.create_account_cache_endpoint(account2, %{url: "https://cache.example.com"})

      # Then
      assert {:ok, endpoint} = result
      assert endpoint.url == "https://cache.example.com"
    end

    test "allows same URL for different cache technologies on the same account" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      {:ok, _endpoint1} = Accounts.create_account_cache_endpoint(account, %{url: "https://cache.example.com"})

      # When
      result =
        Accounts.create_account_cache_endpoint(account, %{
          url: "https://cache.example.com",
          technology: :kura
        })

      # Then
      assert {:ok, endpoint} = result
      assert endpoint.technology == :kura
    end
  end

  describe "delete_account_cache_endpoint/1" do
    test "deletes the cache endpoint" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      {:ok, endpoint} = Accounts.create_account_cache_endpoint(account, %{url: "https://cache.example.com"})

      # When
      {:ok, _} = Accounts.delete_account_cache_endpoint(endpoint)

      # Then
      assert Accounts.list_account_cache_endpoints(account) == []
    end
  end

  describe "get_account_cache_endpoint!/1" do
    test "returns the cache endpoint" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      {:ok, endpoint} = Accounts.create_account_cache_endpoint(account, %{url: "https://cache.example.com"})

      # When
      fetched_endpoint = Accounts.get_account_cache_endpoint!(endpoint.id)

      # Then
      assert fetched_endpoint.id == endpoint.id
      assert fetched_endpoint.url == endpoint.url
    end

    test "raises when endpoint does not exist" do
      # Given / When / Then
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_account_cache_endpoint!(Ecto.UUID.generate())
      end
    end
  end

  describe "get_cache_endpoints_for_handle/1" do
    test "returns custom endpoints when account has them configured and enabled" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)
      {:ok, account} = Accounts.update_account(account, %{custom_cache_endpoints_enabled: true})
      {:ok, _} = Accounts.create_account_cache_endpoint(account, %{url: "https://cache1.example.com"})
      {:ok, _} = Accounts.create_account_cache_endpoint(account, %{url: "https://cache2.example.com"})

      # When
      endpoints = Accounts.get_cache_endpoints_for_handle(account.name)

      # Then
      assert Enum.sort(endpoints) == Enum.sort(["https://cache1.example.com", "https://cache2.example.com"])
    end

    test "returns account Kura endpoints when the client requests Kura and the account is opted in" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)
      {:ok, account} = Accounts.update_account(account, %{custom_cache_endpoints_enabled: true})

      {:ok, _} = Accounts.create_account_cache_endpoint(account, %{url: "https://custom-cache.example.com"})

      {:ok, _} =
        Accounts.create_account_cache_endpoint(account, %{
          url: "https://kura-cache.example.com",
          technology: :kura
        })

      default_endpoints = ["https://default.tuist.dev"]
      stub(Environment, :cache_endpoints, fn -> default_endpoints end)
      stub(FeatureFlags, :kura_cache_enabled?, fn %{id: account_id} -> account_id == account.id end)

      # When
      endpoints = Accounts.get_cache_endpoints_for_handle(account.name, :kura)

      # Then
      assert endpoints == ["https://kura-cache.example.com"]
    end

    test "surfaces registered self-hosted node addresses for an entitled account" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)
      stub(FeatureFlags, :kura_cache_enabled?, fn %{id: account_id} -> account_id == account.id end)
      stub(Registrations, :active_advertised_urls, fn _ -> ["https://node.acme.example:8080"] end)

      # When
      endpoints = Accounts.get_cache_endpoints_for_handle(account.name, :kura)

      # Then
      assert endpoints == ["https://node.acme.example:8080"]
    end

    test "hides registered self-hosted node addresses when the account is not entitled to self-hosting" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)
      stub(FeatureFlags, :kura_cache_enabled?, fn %{id: account_id} -> account_id == account.id end)
      reject(&Registrations.active_advertised_urls/1)
      default_endpoints = ["https://default.tuist.dev"]
      stub(Environment, :cache_endpoints, fn -> default_endpoints end)

      # When
      endpoints = Accounts.get_cache_endpoints_for_handle(account.name, :kura)

      # Then
      assert endpoints == default_endpoints
    end

    test "returns custom endpoints when the client requests Kura but the account is not opted in" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)
      {:ok, account} = Accounts.update_account(account, %{custom_cache_endpoints_enabled: true})

      {:ok, _} = Accounts.create_account_cache_endpoint(account, %{url: "https://custom-cache.example.com"})

      {:ok, _} =
        Accounts.create_account_cache_endpoint(account, %{
          url: "https://kura-cache.example.com",
          technology: :kura
        })

      # When
      endpoints = Accounts.get_cache_endpoints_for_handle(account.name, :kura)

      # Then
      assert endpoints == ["https://custom-cache.example.com"]
    end

    test "returns custom endpoints when the client does not request Kura even if the account is opted in" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)
      {:ok, account} = Accounts.update_account(account, %{custom_cache_endpoints_enabled: true})

      {:ok, _} = Accounts.create_account_cache_endpoint(account, %{url: "https://custom-cache.example.com"})

      {:ok, _} =
        Accounts.create_account_cache_endpoint(account, %{
          url: "https://kura-cache.example.com",
          technology: :kura
        })

      stub(FeatureFlags, :kura_cache_enabled?, fn %{id: account_id} -> account_id == account.id end)

      # When
      endpoints = Accounts.get_cache_endpoints_for_handle(account.name)

      # Then
      assert endpoints == ["https://custom-cache.example.com"]
    end

    test "returns default endpoints when the account is not opted in to Kura and has no custom endpoints" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      default_endpoints = ["https://default.tuist.dev"]
      stub(Environment, :cache_endpoints, fn -> default_endpoints end)

      {:ok, _} =
        Accounts.create_account_cache_endpoint(account, %{
          url: "https://kura-cache.example.com",
          technology: :kura
        })

      # When
      endpoints = Accounts.get_cache_endpoints_for_handle(account.name, :kura)

      # Then
      assert endpoints == default_endpoints
    end

    test "returns default endpoints when account has no custom endpoints" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)
      {:ok, _} = Accounts.update_account(account, %{custom_cache_endpoints_enabled: true})
      default_endpoints = ["https://default.tuist.dev"]
      stub(Environment, :cache_endpoints, fn -> default_endpoints end)

      # When
      endpoints = Accounts.get_cache_endpoints_for_handle(account.name)

      # Then
      assert endpoints == default_endpoints
    end

    test "returns default endpoints when custom endpoints exist but are disabled" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)
      {:ok, _} = Accounts.create_account_cache_endpoint(account, %{url: "https://cache1.example.com"})
      default_endpoints = ["https://default.tuist.dev"]
      stub(Environment, :cache_endpoints, fn -> default_endpoints end)

      # When
      endpoints = Accounts.get_cache_endpoints_for_handle(account.name)

      # Then
      assert endpoints == default_endpoints
    end

    test "returns default endpoints when account is not enterprise on hosted" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      {:ok, account} = Accounts.update_account(account, %{custom_cache_endpoints_enabled: true})
      {:ok, _} = Accounts.create_account_cache_endpoint(account, %{url: "https://cache1.example.com"})
      default_endpoints = ["https://default.tuist.dev"]
      stub(Environment, :cache_endpoints, fn -> default_endpoints end)

      # When
      endpoints = Accounts.get_cache_endpoints_for_handle(account.name)

      # Then
      assert endpoints == default_endpoints
    end

    test "returns environment endpoints when self-hosted" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> false end)
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      {:ok, _} = Accounts.update_account(account, %{custom_cache_endpoints_enabled: true})
      {:ok, _} = Accounts.create_account_cache_endpoint(account, %{url: "https://cache1.example.com"})
      default_endpoints = ["https://cache-self-hosted.example.com"]
      stub(Environment, :cache_endpoints, fn -> default_endpoints end)

      # When
      endpoints = Accounts.get_cache_endpoints_for_handle(account.name)

      # Then
      assert endpoints == default_endpoints
    end

    test "returns default endpoints when account handle does not exist" do
      # Given
      default_endpoints = ["https://default.tuist.dev"]
      stub(Environment, :cache_endpoints, fn -> default_endpoints end)

      # When
      endpoints = Accounts.get_cache_endpoints_for_handle("nonexistent-account")

      # Then
      assert endpoints == default_endpoints
    end

    test "returns default endpoints when handle is nil" do
      # Given
      default_endpoints = ["https://default.tuist.dev"]
      stub(Environment, :cache_endpoints, fn -> default_endpoints end)

      # When
      endpoints = Accounts.get_cache_endpoints_for_handle(nil)

      # Then
      assert endpoints == default_endpoints
    end
  end

  describe "update_user_preferred_locale/2" do
    # "es"/"ja" are only valid supported locales when TUIST_DEV_ALL_LOCALES=1.
    @tag :locale
    test "sets a supported locale" do
      # Given
      user = AccountsFixtures.user_fixture()

      # When
      {:ok, updated_user} = Accounts.update_user_preferred_locale(user, "es")

      # Then
      assert updated_user.preferred_locale == "es"
    end

    @tag :locale
    test "clears the locale when set to nil" do
      # Given
      user = AccountsFixtures.user_fixture()
      {:ok, user} = Accounts.update_user_preferred_locale(user, "ja")

      # When
      {:ok, updated_user} = Accounts.update_user_preferred_locale(user, nil)

      # Then
      assert updated_user.preferred_locale == nil
    end

    test "returns an error for an unsupported locale" do
      # Given
      user = AccountsFixtures.user_fixture()

      # When
      {:error, changeset} = Accounts.update_user_preferred_locale(user, "xx")

      # Then
      assert "is invalid" in errors_on(changeset).preferred_locale
    end
  end

  describe "list_accounts/1" do
    test "paginates and filters by handle via the :search custom Flop filter" do
      # Given — three handles, two of which share a substring.
      AccountsFixtures.organization_fixture(name: "acme")
      AccountsFixtures.organization_fixture(name: "acmetools")
      AccountsFixtures.organization_fixture(name: "other")

      # When — search narrows to just the matching pair.
      {accounts, _meta} =
        Accounts.list_accounts(%{
          page: 1,
          page_size: 10,
          filters: [%{field: :search, op: :==, value: "acme"}]
        })

      # Then
      assert accounts |> Enum.map(& &1.name) |> Enum.sort() == ["acme", "acmetools"]
    end
  end

  describe "agent registration" do
    setup do
      stub(Environment, :mailing_from_address, fn -> "noreply@tuist.dev" end)
      stub(Environment, :email_icon_url, fn -> "https://tuist.dev/icon.png" end)
      stub(Environment, :agent_auth_trusted_providers, fn -> [] end)
      :ok
    end

    test "creates an email-required registration and emails a claim link" do
      email = AccountsFixtures.unique_user_email()

      {:ok, result} =
        Accounts.create_agent_registration(%{
          email: String.upcase(email),
          requested_credential_type: :access_token,
          claim_view_url: &"https://tuist.dev/agent/auth/claim/view?token=#{&1}",
          registration_ip: "127.0.0.1"
        })

      assert result.claim_token =~ "clm_"

      assert %AgentRegistration{
               email: ^email,
               status: :pending,
               registration_ip: "127.0.0.1",
               claim_requested_ip: "127.0.0.1"
             } = Repo.get!(AgentRegistration, result.registration.id)

      assert [%AgentRegistrationEvent{event_type: :created, actor_ip: "127.0.0.1", metadata: metadata}] =
               Repo.all(
                 from(e in AgentRegistrationEvent,
                   where: e.agent_registration_id == ^result.registration.id,
                   order_by: e.occurred_at
                 )
               )

      assert metadata == %{
               "claim_attempt_id" => result.registration.claim_attempt_id,
               "credential_type" => "access_token",
               "registration_type" => "email_verification"
             }

      assert result.email_delivery.subject == "Your Tuist agent sign-in code"
      assert result.email_delivery.html_body =~ "/agent/auth/claim/view?token="
      refute result.email_delivery.html_body =~ result.claim_token
      refute result.email_delivery.html_body =~ "<div class=\"otp\">"
    end

    test "claims the registration for an existing unconfirmed user" do
      email = AccountsFixtures.unique_user_email()
      user = AccountsFixtures.user_fixture(email: email, confirmed_at: nil)

      {:ok, result} =
        Accounts.create_agent_registration(%{
          email: email,
          requested_credential_type: :access_token,
          claim_view_url: &"https://tuist.dev/agent/auth/claim/view?token=#{&1}",
          registration_ip: "127.0.0.1"
        })

      claim_view_token = extract_claim_view_token(result.email_delivery.html_body)
      {:ok, %{otp: otp}} = Accounts.get_agent_registration_claim_view(claim_view_token)

      {:ok, claimed} =
        Accounts.complete_agent_registration_claim(%{
          claim_token: result.claim_token,
          otp: otp,
          claim_completed_ip: "192.0.2.4"
        })

      assert %AgentRegistration{
               status: :claimed,
               claim_completed_ip: "192.0.2.4",
               claimed_by_user_id: claimed_by_user_id
             } = Repo.get!(AgentRegistration, claimed.registration.id)

      assert claimed_by_user_id == user.id
      assert %User{confirmed_at: confirmed_at} = Repo.get!(User, user.id)
      assert confirmed_at

      assert %AuthenticatedAccount{
               account: %{user_id: ^claimed_by_user_id},
               scopes: ["mcp"],
               all_projects: true,
               issued_by: %{id: ^claimed_by_user_id, email: ^email}
             } = Authentication.authenticated_subject(claimed.credential)

      assert [:created, :claimed] =
               claimed.registration.id
               |> agent_registration_events()
               |> Enum.map(& &1.event_type)
    end

    test "provisions and claims a new user when none exists" do
      email = AccountsFixtures.unique_user_email()

      {:ok, result} =
        Accounts.create_agent_registration(%{
          email: email,
          requested_credential_type: :access_token,
          claim_view_url: &"https://tuist.dev/agent/auth/claim/view?token=#{&1}",
          registration_ip: "127.0.0.1"
        })

      claim_view_token = extract_claim_view_token(result.email_delivery.html_body)
      {:ok, %{otp: otp}} = Accounts.get_agent_registration_claim_view(claim_view_token)

      {:ok, claimed} =
        Accounts.complete_agent_registration_claim(%{
          claim_token: result.claim_token,
          otp: otp,
          claim_completed_ip: "192.0.2.5"
        })

      {:ok, user} = Accounts.get_user_by_email(email)
      user_id = user.id

      assert user.confirmed_at
      assert claimed.registration.claimed_by_user_id == user_id

      assert %AuthenticatedAccount{
               account: %{user_id: ^user_id},
               issued_by: %{id: ^user_id, email: ^email}
             } = Authentication.authenticated_subject(claimed.credential)
    end

    test "resends claim instructions and records an audit event" do
      email = AccountsFixtures.unique_user_email()

      {:ok, result} =
        Accounts.create_agent_registration(%{
          email: email,
          requested_credential_type: :access_token,
          claim_view_url: &"https://tuist.dev/agent/auth/claim/view?token=#{&1}",
          registration_ip: "127.0.0.1"
        })

      {:ok, resent} =
        Accounts.resend_agent_registration_claim(%{
          claim_token: result.claim_token,
          email: email,
          claim_view_url: &"https://tuist.dev/agent/auth/claim/view?token=#{&1}",
          claim_requested_ip: "192.0.2.10"
        })

      assert resent.registration.claim_requested_ip == "192.0.2.10"

      assert [
               %AgentRegistrationEvent{event_type: :created},
               %AgentRegistrationEvent{event_type: :claim_resent, actor_ip: "192.0.2.10", metadata: metadata}
             ] = agent_registration_events(result.registration.id)

      assert metadata == %{
               "claim_attempt_id" => resent.registration.claim_attempt_id,
               "email" => email
             }
    end

    test "persists failed OTP attempts and records audit events" do
      email = AccountsFixtures.unique_user_email()

      {:ok, result} =
        Accounts.create_agent_registration(%{
          email: email,
          requested_credential_type: :access_token,
          claim_view_url: &"https://tuist.dev/agent/auth/claim/view?token=#{&1}",
          registration_ip: "127.0.0.1"
        })

      assert {:error, :otp_invalid} =
               Accounts.complete_agent_registration_claim(%{
                 claim_token: result.claim_token,
                 otp: "000000",
                 claim_completed_ip: "192.0.2.11"
               })

      assert %AgentRegistration{otp_attempt_count: 1} = Repo.get!(AgentRegistration, result.registration.id)

      assert [
               %AgentRegistrationEvent{event_type: :created},
               %AgentRegistrationEvent{event_type: :otp_failed, actor_ip: "192.0.2.11", metadata: metadata}
             ] = agent_registration_events(result.registration.id)

      assert metadata == %{
               "claim_attempt_id" => result.registration.claim_attempt_id,
               "otp_attempt_count" => 1
             }
    end

    test "creates an anonymous API key and later claims it for a real user" do
      email = AccountsFixtures.unique_user_email()

      {:ok, result} =
        Accounts.create_agent_registration(%{
          registration_type: :anonymous,
          requested_credential_type: :api_key,
          registration_ip: "127.0.0.1"
        })

      assert result.credential_type == :api_key
      assert result.credential =~ "tuist_"
      assert result.scopes == ["mcp"]

      assert %AuthenticatedAccount{account: %{user_id: anonymous_user_id}} =
               Authentication.authenticated_subject(result.credential)

      {:ok, resent} =
        Accounts.resend_agent_registration_claim(%{
          claim_token: result.claim_token,
          email: email,
          claim_view_url: &"https://tuist.dev/agent/auth/claim/view?token=#{&1}",
          claim_requested_ip: "192.0.2.20"
        })

      claim_view_token = extract_claim_view_token(resent.email_delivery.html_body)
      {:ok, %{otp: otp}} = Accounts.get_agent_registration_claim_view(claim_view_token)

      {:ok, claimed} =
        Accounts.complete_agent_registration_claim(%{
          claim_token: result.claim_token,
          otp: otp,
          claim_completed_ip: "192.0.2.21"
        })

      {:ok, claimed_user} = Accounts.get_user_by_email(email)
      assert claimed.registration.claimed_by_user_id == claimed_user.id

      assert %AuthenticatedAccount{account: %{user_id: claimed_user_id}, scopes: ["mcp"]} =
               Authentication.authenticated_subject(result.credential)

      assert claimed_user_id == claimed_user.id
      refute claimed_user_id == anonymous_user_id

      assert [:created, :claim_resent, :claimed] =
               result.registration.id
               |> agent_registration_events()
               |> Enum.map(& &1.event_type)
    end

    test "creates an agent-provider access token and revokes it from a logout token" do
      email = AccountsFixtures.unique_user_email()
      {provider, assertion, jwk} = id_jag_with_jwk(email, "id-jag-to-revoke")
      stub(Environment, :agent_auth_trusted_providers, fn -> [provider] end)

      {:ok, result} =
        Accounts.create_agent_registration(%{
          registration_type: :agent_provider,
          assertion: assertion,
          requested_credential_type: :access_token,
          audience: "https://tuist.dev",
          registration_ip: "127.0.0.1"
        })

      assert result.credential_type == :access_token
      assert result.scopes == ["mcp"]

      assert %AuthenticatedAccount{issued_by: %{email: ^email}} =
               Authentication.authenticated_subject(result.credential)

      assert %AgentRegistration{
               registration_type: :agent_provider,
               status: :claimed,
               email: ^email,
               issuer: "https://agent-provider.example.com",
               subject: "provider-user-1",
               client_id: "test-agent-client",
               assertion_jti: "id-jag-to-revoke"
             } = Repo.get!(AgentRegistration, result.registration.id)

      assert [:created, :claimed] =
               result.registration.id
               |> agent_registration_events()
               |> Enum.map(& &1.event_type)

      logout_token = logout_token(jwk, "logout-jti")

      assert {:ok, %{revoked_count: 1}} = Accounts.revoke_agent_registrations(logout_token, "https://tuist.dev")
      assert Authentication.authenticated_subject(result.credential) == nil

      assert %AgentRegistration{status: :revoked, revoked_at: revoked_at} =
               Repo.get!(AgentRegistration, result.registration.id)

      assert revoked_at

      assert [:created, :claimed, :revoked] =
               result.registration.id
               |> agent_registration_events()
               |> Enum.map(& &1.event_type)
    end

    test "creates an agent-provider API key and revokes the backing account token" do
      email = AccountsFixtures.unique_user_email()
      {provider, assertion, jwk} = id_jag_with_jwk(email, "id-jag-api-key")
      stub(Environment, :agent_auth_trusted_providers, fn -> [provider] end)

      {:ok, result} =
        Accounts.create_agent_registration(%{
          registration_type: :agent_provider,
          assertion: assertion,
          requested_credential_type: :api_key,
          audience: "https://tuist.dev",
          registration_ip: "127.0.0.1"
        })

      assert result.credential_type == :api_key

      {:ok, user} = Accounts.get_user_by_email(email)

      assert %AuthenticatedAccount{account: %{user_id: user_id}, scopes: ["mcp"]} =
               Authentication.authenticated_subject(result.credential)

      assert user_id == user.id

      assert %AgentRegistration{account_token_id: account_token_id} = result.registration
      assert Repo.get!(AccountToken, account_token_id)

      logout_token = logout_token(jwk, "logout-api-key-jti")

      assert {:ok, %{revoked_count: 1}} = Accounts.revoke_agent_registrations(logout_token, "https://tuist.dev")
      assert Repo.get(AccountToken, account_token_id) == nil
      assert Authentication.authenticated_subject(result.credential) == nil
    end

    test "rejects an agent-provider assertion from an untrusted issuer" do
      email = AccountsFixtures.unique_user_email()
      {_provider, assertion, _jwk} = id_jag_with_jwk(email, "untrusted-id-jag")

      assert {:error, :invalid_issuer} =
               Accounts.create_agent_registration(%{
                 registration_type: :agent_provider,
                 assertion: assertion,
                 requested_credential_type: :access_token,
                 audience: "https://tuist.dev"
               })
    end

    test "rejects replayed agent-provider assertions" do
      email = AccountsFixtures.unique_user_email()
      {provider, assertion, _jwk} = id_jag_with_jwk(email, "replayed-id-jag")
      stub(Environment, :agent_auth_trusted_providers, fn -> [provider] end)

      attrs = %{
        registration_type: :agent_provider,
        assertion: assertion,
        requested_credential_type: :access_token,
        audience: "https://tuist.dev"
      }

      assert {:ok, _result} = Accounts.create_agent_registration(attrs)
      assert {:error, :replay_detected} = Accounts.create_agent_registration(attrs)
    end

    test "rejects agent-provider assertions without a verified email" do
      jwk = JOSE.JWK.generate_key({:rsa, 2048})
      provider = agent_auth_provider(jwk)
      stub(Environment, :agent_auth_trusted_providers, fn -> [provider] end)

      assertion =
        sign_agent_auth_jwt(
          jwk,
          "oauth-id-jag+jwt",
          claims("agent@example.com", "unverified-email-jti", %{
            "email_verified" => false
          })
        )

      assert {:error, :missing_verified_email} =
               Accounts.create_agent_registration(%{
                 registration_type: :agent_provider,
                 assertion: assertion,
                 requested_credential_type: :access_token,
                 audience: "https://tuist.dev"
               })
    end

    test "rejects agent-provider assertions for the wrong client" do
      jwk = JOSE.JWK.generate_key({:rsa, 2048})
      provider = agent_auth_provider(jwk)
      stub(Environment, :agent_auth_trusted_providers, fn -> [provider] end)

      assertion =
        sign_agent_auth_jwt(
          jwk,
          "oauth-id-jag+jwt",
          claims("agent@example.com", "wrong-client-jti", %{
            "client_id" => "other-client"
          })
        )

      assert {:error, :invalid_client_id} =
               Accounts.create_agent_registration(%{
                 registration_type: :agent_provider,
                 assertion: assertion,
                 requested_credential_type: :access_token,
                 audience: "https://tuist.dev"
               })
    end

    test "refuses email-verification registration for SSO-enforced existing users" do
      email = AccountsFixtures.unique_user_email()
      user = AccountsFixtures.user_fixture(email: email)
      org = sso_enforced_organization_fixture()
      Accounts.add_user_to_organization(user, org)

      assert {:error, :sso_required} =
               Accounts.create_agent_registration(%{
                 email: email,
                 requested_credential_type: :access_token,
                 claim_view_url: &"https://tuist.dev/agent/auth/claim/view?token=#{&1}",
                 registration_ip: "127.0.0.1"
               })

      assert Repo.aggregate(AgentRegistration, :count) == 0
    end

    test "refuses email-verification registration when the email domain maps to an SSO-enforced org" do
      org = sso_enforced_organization_fixture(sso_organization_id: "acme.com")
      assert org.sso_organization_id == "acme.com"
      email = "new-user-#{TuistTestSupport.Utilities.unique_integer(6)}@acme.com"

      assert {:error, :sso_required} =
               Accounts.create_agent_registration(%{
                 email: email,
                 requested_credential_type: :access_token,
                 claim_view_url: &"https://tuist.dev/agent/auth/claim/view?token=#{&1}",
                 registration_ip: "127.0.0.1"
               })

      assert {:error, :not_found} = Accounts.get_user_by_email(email)
    end

    test "refuses agent-provider registration when the asserted email is SSO-enforced" do
      email = AccountsFixtures.unique_user_email()
      user = AccountsFixtures.user_fixture(email: email)
      org = sso_enforced_organization_fixture()
      Accounts.add_user_to_organization(user, org)

      {provider, assertion, _jwk} = id_jag_with_jwk(email, "sso-enforced-id-jag")
      stub(Environment, :agent_auth_trusted_providers, fn -> [provider] end)

      assert {:error, :sso_required} =
               Accounts.create_agent_registration(%{
                 registration_type: :agent_provider,
                 assertion: assertion,
                 requested_credential_type: :access_token,
                 audience: "https://tuist.dev",
                 registration_ip: "127.0.0.1"
               })

      assert Repo.aggregate(AgentRegistration, :count) == 0
    end

    test "refuses anonymous claim when the supplied email is SSO-enforced" do
      email = AccountsFixtures.unique_user_email()
      user = AccountsFixtures.user_fixture(email: email)
      org = sso_enforced_organization_fixture()
      Accounts.add_user_to_organization(user, org)

      {:ok, anonymous} =
        Accounts.create_agent_registration(%{
          registration_type: :anonymous,
          requested_credential_type: :api_key,
          registration_ip: "127.0.0.1"
        })

      assert {:error, :sso_required} =
               Accounts.resend_agent_registration_claim(%{
                 claim_token: anonymous.claim_token,
                 email: email,
                 claim_view_url: &"https://tuist.dev/agent/auth/claim/view?token=#{&1}",
                 claim_requested_ip: "192.0.2.30"
               })
    end
  end

  defp sso_enforced_organization_fixture(opts \\ []) do
    sso_organization_id =
      Keyword.get(opts, :sso_organization_id, "sso-org-#{TuistTestSupport.Utilities.unique_integer(6)}.com")

    org =
      AccountsFixtures.organization_fixture(
        sso_provider: :okta,
        sso_organization_id: sso_organization_id,
        oauth2_client_id: "client-id",
        oauth2_client_secret: "client-secret"
      )

    {:ok, org} =
      org
      |> Ecto.Changeset.change(sso_enforced: true)
      |> Repo.update()

    org
  end

  describe "sso_enforced_for_email?/1" do
    test "returns true when the existing user belongs to an SSO-enforced organization" do
      email = AccountsFixtures.unique_user_email()
      user = AccountsFixtures.user_fixture(email: email)
      org = sso_enforced_organization_fixture()
      Accounts.add_user_to_organization(user, org)

      assert Accounts.sso_enforced_for_email?(email)
    end

    test "returns false when the existing user has no SSO-enforced organization" do
      email = AccountsFixtures.unique_user_email()
      _user = AccountsFixtures.user_fixture(email: email)

      refute Accounts.sso_enforced_for_email?(email)
    end

    test "returns true for an unknown email whose domain maps to an SSO-enforced org" do
      _org = sso_enforced_organization_fixture(sso_organization_id: "example-sso.com")
      email = "unknown-#{TuistTestSupport.Utilities.unique_integer(6)}@example-sso.com"

      assert Accounts.sso_enforced_for_email?(email)
    end

    test "returns false for malformed input" do
      refute Accounts.sso_enforced_for_email?(nil)
      refute Accounts.sso_enforced_for_email?("not-an-email")
    end
  end

  defp extract_claim_view_token(html_body) do
    [_, encoded_token] = Regex.run(~r{/agent/auth/claim/view\?token=([^"&]+)}, html_body)
    URI.decode_www_form(encoded_token)
  end

  defp unique_sso_domain(prefix \\ "tuist") do
    "#{prefix}-#{TuistTestSupport.Utilities.unique_integer(6)}.io"
  end

  defp unique_email(domain, local \\ "tuist") do
    "#{local}-#{TuistTestSupport.Utilities.unique_integer(6)}@#{domain}"
  end

  defp google_oauth_identity(domain, opts \\ []) do
    %{
      provider: :google,
      uid: Keyword.get_lazy(opts, :uid, fn -> System.unique_integer([:positive]) end),
      info: %{
        email: Keyword.get_lazy(opts, :email, fn -> unique_email(domain) end)
      },
      extra: %{
        raw_info: %{
          user: %{
            "hd" => domain
          }
        }
      }
    }
  end

  defp okta_oauth_identity(provider_organization_id, opts \\ []) do
    %{
      provider: :okta,
      uid: Keyword.get_lazy(opts, :uid, fn -> System.unique_integer([:positive]) end),
      info: %{
        email: Keyword.get_lazy(opts, :email, fn -> unique_email("tuist.dev") end)
      },
      extra: %{
        raw_info: %{
          provider_organization_id: provider_organization_id
        }
      }
    }
  end

  defp agent_registration_events(agent_registration_id) do
    Repo.all(
      from(e in AgentRegistrationEvent,
        where: e.agent_registration_id == ^agent_registration_id,
        order_by: e.occurred_at
      )
    )
  end

  defp id_jag_with_jwk(email, jti) do
    jwk = JOSE.JWK.generate_key({:rsa, 2048})
    provider = agent_auth_provider(jwk)

    {provider, sign_agent_auth_jwt(jwk, "oauth-id-jag+jwt", claims(email, jti)), jwk}
  end

  defp agent_auth_provider(jwk) do
    {_, public_jwk} = jwk |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()
    public_jwk = Map.put(public_jwk, "kid", "agent-auth-test-key")

    %{
      "issuer" => "https://agent-provider.example.com",
      "jwks" => %{"keys" => [public_jwk]},
      "client_ids" => ["test-agent-client"]
    }
  end

  defp logout_token(jwk, jti) do
    sign_agent_auth_jwt(jwk, "logout+jwt", %{
      "iss" => "https://agent-provider.example.com",
      "sub" => "provider-user-1",
      "aud" => "https://tuist.dev",
      "client_id" => "test-agent-client",
      "jti" => jti,
      "iat" => DateTime.to_unix(DateTime.utc_now()),
      "exp" => DateTime.utc_now() |> DateTime.add(300, :second) |> DateTime.to_unix(),
      "events" => %{
        "https://schemas.workos.com/events/agent/auth/identity/assertion/revoked" => %{}
      }
    })
  end

  defp claims(email, jti, overrides \\ %{}) do
    Map.merge(
      %{
        "iss" => "https://agent-provider.example.com",
        "sub" => "provider-user-1",
        "aud" => "https://tuist.dev",
        "client_id" => "test-agent-client",
        "jti" => jti,
        "iat" => DateTime.to_unix(DateTime.utc_now()),
        "exp" => DateTime.utc_now() |> DateTime.add(300, :second) |> DateTime.to_unix(),
        "email" => email,
        "email_verified" => true
      },
      overrides
    )
  end

  defp sign_agent_auth_jwt(jwk, typ, claims) do
    jwt = JOSE.JWT.from_map(claims)
    jws = %{"alg" => "RS256", "kid" => "agent-auth-test-key", "typ" => typ}
    {_, token} = jwk |> JOSE.JWT.sign(jws, jwt) |> JOSE.JWS.compact()
    token
  end
end
