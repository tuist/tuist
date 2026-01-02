defmodule Tuist.AccountsTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use TuistTestSupport.Cases.StubCase, billing: true
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.AccountToken
  alias Tuist.Accounts.Role
  alias Tuist.Accounts.User
  alias Tuist.Accounts.UserRole
  alias Tuist.Accounts.UserToken
  alias Tuist.Base64
  alias Tuist.Billing
  alias Tuist.CommandEvents
  alias Tuist.Environment
  alias Tuist.Projects
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    stub(JOSE.JWT, :peek_payload, fn _ ->
      %JOSE.JWT{
        fields: %{
          "iss" => "https://tuist.okta.com"
        }
      }
    end)

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

      user =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :okta,
          uid: 123,
          info: %{
            email: "tuist@tuist.dev"
          },
          extra: %{
            raw_info: %{
              user: %{},
              token: %OAuth2.AccessToken{
                other_params: %{
                  "id_token" => "jwt-token"
                }
              }
            }
          }
        })

      organization =
        AccountsFixtures.organization_fixture(
          sso_provider: :okta,
          sso_organization_id: "tuist.okta.com"
        )

      # When
      assert Accounts.organization_user?(user, organization) == true
    end

    test "organization_user? returns true if the user's sso matches the organization's when the sso is Okta" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)

      user =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :google,
          uid: 123,
          info: %{
            email: "tuist@tuist.dev"
          },
          extra: %{
            raw_info: %{
              user: %{
                "hd" => "tuist.io"
              }
            }
          }
        })

      organization =
        AccountsFixtures.organization_fixture(
          sso_provider: :google,
          sso_organization_id: "tuist.io"
        )

      # When
      assert Accounts.organization_user?(user, organization) == true
    end

    test "organization_user? returns false if the user's sso domain matches the organization's but the providers are different" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)

      user =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :google,
          uid: 123,
          info: %{
            email: "tuist@tuist.dev"
          },
          extra: %{
            raw_info: %{
              user: %{
                "hd" => "tuist.io"
              }
            }
          }
        })

      organization =
        AccountsFixtures.organization_fixture(
          sso_provider: :okta,
          sso_organization_id: "tuist.io"
        )

      # When
      assert Accounts.organization_user?(user, organization) == false
    end

    test "organization_user? returns false if the user's sso does not match the organization's when both are Google" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)

      user =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :google,
          uid: 123,
          info: %{
            email: "tuist@tools.io"
          },
          extra: %{
            raw_info: %{
              user: %{
                "hd" => "tools.io"
              }
            }
          }
        })

      organization =
        AccountsFixtures.organization_fixture(
          sso_provider: :google,
          sso_organization_id: "tuist.io"
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

      user =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :google,
          uid: 123,
          info: %{
            email: "tuist@tuist.dev"
          },
          extra: %{
            raw_info: %{
              user: %{
                "hd" => "tuist.io"
              }
            }
          }
        })

      organization =
        AccountsFixtures.organization_fixture(
          sso_provider: :google,
          sso_organization_id: "tuist.io"
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

      user =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :google,
          uid: 123,
          info: %{
            email: "tuist@tuist.dev"
          },
          extra: %{
            raw_info: %{
              user: %{
                "hd" => "tuist.io"
              }
            }
          }
        })

      organization =
        AccountsFixtures.organization_fixture(
          sso_provider: :google,
          sso_organization_id: "tuist.io"
        )

      # When
      got = Accounts.belongs_to_sso_organization?(user, organization)

      # Then
      assert got == true
    end

    test "returns false if the user's sso does not match the organization's" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)

      user =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :google,
          uid: 123,
          info: %{
            email: "tuist@tools.io"
          },
          extra: %{
            raw_info: %{
              user: %{
                "hd" => "tools.io"
              }
            }
          }
        })

      organization =
        AccountsFixtures.organization_fixture(
          sso_provider: :google,
          sso_organization_id: "tuist.io"
        )

      # When
      got = Accounts.belongs_to_sso_organization?(user, organization)

      # Then
      assert got == false
    end
  end

  describe "update_okta_configuration/2" do
    test "updates Okta configuration for an existing organization" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: user)

      # When
      result =
        Accounts.update_okta_configuration(organization.id, %{
          okta_client_id: "test_client_id",
          okta_client_secret: "test_secret",
          sso_organization_id: "https://test.okta.com"
        })

      # Then
      assert {:ok, updated_org} = result
      assert updated_org.okta_client_id == "test_client_id"
      assert updated_org.sso_provider == :okta
      assert updated_org.sso_organization_id == "https://test.okta.com"
      # Check that the secret is stored (encrypted)
      assert updated_org.okta_encrypted_client_secret
    end

    test "encrypts the client secret when storing" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: user)
      plain_secret = "my_super_secret_key"

      # When
      {:ok, updated_org} =
        Accounts.update_okta_configuration(organization.id, %{
          okta_client_id: "test_client_id",
          okta_client_secret: plain_secret,
          sso_organization_id: "https://test.okta.com"
        })

      # Then
      # Verify the secret was stored
      assert updated_org.okta_encrypted_client_secret
      # Reload from database to ensure we're testing the persisted value
      {:ok, reloaded_org} = Accounts.get_organization_by_id(updated_org.id)

      # The Vault.Binary type should automatically decrypt when loaded
      # so we should get back the original plain text
      assert reloaded_org.okta_encrypted_client_secret == plain_secret
    end

    test "returns error when organization doesn't exist" do
      # When
      result =
        Accounts.update_okta_configuration(999_999, %{
          okta_client_id: "test_client_id"
        })

      # Then
      assert result == {:error, :not_found}
    end

    test "automatically sets sso_provider to okta" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: user, sso_provider: :google)

      # When - update Okta configuration
      {:ok, updated_org} =
        Accounts.update_okta_configuration(organization.id, %{
          okta_client_id: "test_client_id"
        })

      # Then - sso_provider should be changed to :okta
      assert updated_org.sso_provider == :okta
    end

    test "can update partial Okta configuration" do
      # Given
      user = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          okta_client_id: "old_client_id",
          sso_organization_id: "https://old.okta.com",
          sso_provider: :okta
        )

      # When - update only the client ID
      {:ok, updated_org} =
        Accounts.update_okta_configuration(organization.id, %{
          okta_client_id: "new_client_id"
        })

      # Then
      assert updated_org.okta_client_id == "new_client_id"
      # unchanged
      assert updated_org.sso_organization_id == "https://old.okta.com"
      # still okta
      assert updated_org.sso_provider == :okta
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

      # When
      {:ok, organization} =
        Accounts.create_organization(
          %{
            name: "tuist",
            creator: user
          },
          sso_provider: :google,
          sso_organization_id: "tuist.io"
        )

      # Then
      assert {:ok, organization} ==
               Accounts.get_organization_by_id(organization.id, preload: [:account])

      assert organization.sso_provider == :google
      assert organization.sso_organization_id == "tuist.io"
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
        uid: 123,
        info: %{email: "find_or_create_user_from_oauth2@tuist.io"}
      }

      second_oauth_identity = %{
        provider: :github,
        uid: 456,
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
      organization =
        AccountsFixtures.organization_fixture(
          sso_provider: :google,
          sso_organization_id: "tuist.io"
        )

      oauth_identity = %{
        provider: :google,
        uid: System.unique_integer([:positive]),
        info: %{email: "google-sso@tuist.io"},
        extra: %{
          raw_info: %{
            user: %{"hd" => "tuist.io"}
          }
        }
      }

      # When
      user = Accounts.find_or_create_user_from_oauth2(oauth_identity)

      # Then
      assert Accounts.belongs_to_organization?(user, organization)
      assert Accounts.get_user_role_in_organization(user, organization).name == "user"
    end

    test "assigns user role to SSO users for Okta SSO" do
      # Given
      organization =
        AccountsFixtures.organization_fixture(
          sso_provider: :okta,
          sso_organization_id: "tuist.okta.com"
        )

      oauth_identity = %{
        provider: :okta,
        uid: 890,
        info: %{email: "okta-sso@tuist.io"},
        extra: %{
          raw_info: %{
            user: %{},
            token: %{
              other_params: %{
                "id_token" => "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJodHRwczovL3R1aXN0Lm9rdGEuY29tIn0.test"
              }
            }
          }
        }
      }

      # When
      user = Accounts.find_or_create_user_from_oauth2(oauth_identity)

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

    test "sanitizes handle when creating user from OAuth2 with multiple special characters" do
      # Given
      oauth_identity = %{
        provider: :github,
        uid: System.unique_integer([:positive]),
        info: %{email: "user+name@test&example.com"}
      }

      # When
      user = Accounts.find_or_create_user_from_oauth2(oauth_identity, preload: [:account])

      # Then
      assert user.account.name == "username"
    end

    test "sanitizes handle when creating user from OAuth2 with spaces and special characters" do
      # Given
      oauth_identity = %{
        provider: :github,
        uid: System.unique_integer([:positive]),
        info: %{email: "user name@test.com"}
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
        uid: 123,
        info: %{
          email: user.email
        }
      })

      Accounts.find_or_create_user_from_oauth2(%{
        provider: :google,
        uid: 123,
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
        uid: 123,
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
        uid: "uid",
        info: %{
          email: user.email
        },
        extra: %{
          raw_info: %{
            user: %{},
            token: %{
              other_params: %{
                "id_token" => "jwt-token"
              }
            }
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
        uid: 123,
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
        uid: 123,
        info: %{
          email: user.email
        }
      })

      oauth2_identity = Accounts.find_oauth2_identity(%{user: user, provider: :github})
      organization = AccountsFixtures.organization_fixture()
      Accounts.add_user_to_organization(user, organization)

      command_event =
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
      assert CommandEvents.get_command_event_by_id(command_event.id) == {:error, :not_found}
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

    test "sanitizes handle by removing multiple special characters" do
      # Given
      email = "user+name@test&example.com"

      # When
      {:ok, user} = Accounts.create_user(email, password: valid_user_password())

      # Then
      assert user.account.name == "username"
    end

    test "sanitizes handle by removing spaces and special characters" do
      # Given
      email = "user name@test.com"

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
      {:ok, _} =
        Accounts.reset_user_password(user, %{"password" => "new valid password"})

      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "deletes all tokens for the given user", %{user: user} do
      _ = Accounts.generate_user_session_token(user)
      {:ok, _} = Accounts.reset_user_password(user, %{"password" => "new valid password"})
      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "update_organization/2" do
    test "updates organization with a google hosted domain" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: user)

      # When
      {:ok, organization} =
        Accounts.update_organization(organization, %{
          sso_provider: :google,
          sso_organization_id: "tuist.io"
        })

      # Then
      assert organization.sso_organization_id == "tuist.io"
      assert organization.sso_provider == :google
    end

    test "updates organization with an okta hosted domain" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: user)

      # When
      {:ok, organization} =
        Accounts.update_organization(organization, %{
          sso_provider: :okta,
          sso_organization_id: "tuist.okta.com"
        })

      # Then
      assert organization.sso_organization_id == "tuist.okta.com"
      assert organization.sso_provider == :okta
    end

    test "assigns existing SSO users when enabling Google SSO" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)

      organization = AccountsFixtures.organization_fixture()

      # Create an existing user with Google OAuth2 identity
      existing_user =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :google,
          uid: System.unique_integer([:positive]),
          info: %{email: "user@tuist.io"},
          extra: %{
            raw_info: %{
              user: %{"hd" => "tuist.io"}
            }
          }
        })

      # Verify user is not yet assigned to organization
      refute Accounts.belongs_to_organization?(existing_user, organization)

      # When - Enable Google SSO for the organization
      {:ok, updated_organization} =
        Accounts.update_organization(organization, %{
          sso_provider: :google,
          sso_organization_id: "tuist.io"
        })

      # Then
      assert updated_organization.sso_provider == :google
      assert updated_organization.sso_organization_id == "tuist.io"

      # Existing SSO user should now be assigned to the organization with explicit role
      assert Accounts.belongs_to_organization?(existing_user, updated_organization)

      assert Accounts.get_user_role_in_organization(existing_user, updated_organization).name ==
               "user"
    end

    test "assigns existing SSO users when enabling Okta SSO" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)

      organization = AccountsFixtures.organization_fixture()

      # Create an existing user with Okta OAuth2 identity
      existing_user =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :okta,
          uid: System.unique_integer([:positive]),
          info: %{email: "user@tuist.io"},
          extra: %{
            raw_info: %{
              user: %{},
              token: %{
                other_params: %{
                  "id_token" => "eyJhbGciOiJSUzI1NiJ9.eyJpc3MiOiJodHRwczovL3R1aXN0Lm9rdGEuY29tIn0.signature"
                }
              }
            }
          }
        })

      # Verify user is not yet assigned to organization
      refute Accounts.belongs_to_organization?(existing_user, organization)

      # When - Enable Okta SSO for the organization
      {:ok, updated_organization} =
        Accounts.update_organization(organization, %{
          sso_provider: :okta,
          sso_organization_id: "tuist.okta.com"
        })

      # Then
      assert updated_organization.sso_provider == :okta
      assert updated_organization.sso_organization_id == "tuist.okta.com"

      # Existing SSO user should now be assigned to the organization with explicit role
      assert Accounts.belongs_to_organization?(existing_user, updated_organization)

      assert Accounts.get_user_role_in_organization(existing_user, updated_organization).name ==
               "user"
    end

    test "does not assign users when SSO is updated but not newly enabled" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)

      # Create organization with SSO already enabled
      organization =
        AccountsFixtures.organization_fixture(
          sso_provider: :google,
          sso_organization_id: "existing.io"
        )

      # Create a user with a domain that doesn't match any SSO organization yet
      other_user =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :google,
          uid: System.unique_integer([:positive]),
          info: %{email: "user@tuist.io"},
          extra: %{
            raw_info: %{
              user: %{"hd" => "tuist.io"}
            }
          }
        })

      # Verify user is not assigned to organization (different domain)
      refute Accounts.belongs_to_organization?(other_user, organization)

      # When - Update SSO organization ID (not newly enabling)
      {:ok, updated_organization} =
        Accounts.update_organization(organization, %{
          sso_organization_id: "tuist.io"
        })

      # Then
      assert updated_organization.sso_organization_id == "tuist.io"

      # User should have SSO-based access (automatic through belongs_to_sso_organization)
      assert Accounts.belongs_to_sso_organization?(other_user, updated_organization)

      # But should NOT have an explicit role assignment (because SSO wasn't newly enabled)
      assert is_nil(Accounts.get_user_role_in_organization(other_user, updated_organization))
    end

    test "assigns multiple existing SSO users when enabling SSO" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)

      organization = AccountsFixtures.organization_fixture()

      # Create multiple existing users with Google OAuth2 identities
      user1 =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :google,
          uid: System.unique_integer([:positive]),
          info: %{email: "user1@tuist.io"},
          extra: %{
            raw_info: %{
              user: %{"hd" => "tuist.io"}
            }
          }
        })

      user2 =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :google,
          uid: System.unique_integer([:positive]),
          info: %{email: "user2@tuist.io"},
          extra: %{
            raw_info: %{
              user: %{"hd" => "tuist.io"}
            }
          }
        })

      # Verify users are not yet assigned to organization
      refute Accounts.belongs_to_organization?(user1, organization)
      refute Accounts.belongs_to_organization?(user2, organization)

      # When - Enable Google SSO for the organization
      {:ok, updated_organization} =
        Accounts.update_organization(organization, %{
          sso_provider: :google,
          sso_organization_id: "tuist.io"
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

      # When
      user =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :github,
          uid: 123,
          info: %{
            email: "tuist@tuist.dev"
          }
        })

      # Then
      assert user.email == "tuist@tuist.dev"
    end

    test "creates a user from a google identity with a hosted domain" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)

      # When
      user =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :google,
          uid: 123,
          info: %{
            email: "tuist@tuist.dev"
          },
          extra: %{
            raw_info: %{
              user: %{
                "hd" => "tuist.io"
              }
            }
          }
        })

      # Then
      assert user.email == "tuist@tuist.dev"
      oauth2_identity = Accounts.get_oauth2_identity_by_provider_and_id(:google, 123)
      assert oauth2_identity.provider_organization_id == "tuist.io"
    end

    test "creates a user from a google identity without a hosted domain" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)

      # When
      user =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :google,
          uid: 123,
          info: %{
            email: "tuist@tuist.dev"
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
      assert user.email == "tuist@tuist.dev"
      oauth2_identity = Accounts.get_oauth2_identity_by_provider_and_id(:google, 123)
      assert oauth2_identity.provider_organization_id == nil
    end

    test "updates an existing user with a new github identity" do
      user = user_fixture(email: "tuist@tuist.dev")

      got =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :github,
          uid: 123,
          info: %{
            email: "tuist@tuist.dev"
          }
        })

      assert user.email == got.email
      assert Accounts.find_oauth2_identity(%{user: user, provider: :github})
    end

    test "updates an existing user with a new okta identity" do
      user = user_fixture(email: "tuist@tuist.dev")

      got =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :okta,
          uid: 123,
          info: %{
            email: "tuist@tuist.dev"
          },
          extra: %{
            raw_info: %{
              user: %{},
              token: %{
                other_params: %{
                  "id_token" => "jwt-token"
                }
              }
            }
          }
        })

      assert user.email == got.email
      assert Accounts.find_oauth2_identity(%{user: user, provider: :okta})
    end

    test "handles reserved handle names by adding a suffix" do
      # When
      user =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :github,
          uid: 123,
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

      organization =
        AccountsFixtures.organization_fixture(
          sso_provider: :google,
          sso_organization_id: "tuist.io"
        )

      user =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :google,
          uid: 123,
          info: %{
            email: "tuist@tuist.dev"
          },
          extra: %{
            raw_info: %{
              user: %{
                "hd" => "tuist.io"
              }
            }
          }
        })

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

      organization =
        AccountsFixtures.organization_fixture(
          sso_provider: :google,
          sso_organization_id: "tuist.io"
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

      organization =
        AccountsFixtures.organization_fixture(
          sso_provider: :google,
          sso_organization_id: "tuist.io"
        )

      Accounts.add_user_to_organization(user_one, organization, role: :user)
      AccountsFixtures.user_fixture()

      user_three =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :google,
          uid: 123,
          info: %{
            email: "tuist@tuist.dev"
          },
          extra: %{
            raw_info: %{
              user: %{
                "hd" => "tuist.io"
              }
            }
          }
        })

      Accounts.find_or_create_user_from_oauth2(%{
        provider: :google,
        uid: 1234,
        info: %{
          email: "tuist-tools@tools.io"
        },
        extra: %{
          raw_info: %{
            user: %{
              "hd" => "tools.io"
            }
          }
        }
      })

      # When
      got = Accounts.get_organization_members(organization, :user)

      # Then
      assert [user_one.id, user_three.id] == got |> Enum.map(& &1.id) |> Enum.sort()
    end

    test "returns users of an organization with a given okta id" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
      user_one = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(
          sso_provider: :okta,
          sso_organization_id: "tuist.okta.com"
        )

      Accounts.add_user_to_organization(user_one, organization, role: :user)
      AccountsFixtures.user_fixture()

      user_three =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :okta,
          uid: 123,
          info: %{
            email: "tuist@tuist.dev"
          },
          extra: %{
            raw_info: %{
              user: %{},
              token: %{
                other_params: %{
                  "id_token" => "jwt-token"
                }
              }
            }
          }
        })

      stub(JOSE.JWT, :peek_payload, fn _ ->
        %JOSE.JWT{
          fields: %{
            "iss" => "https://different-org.okta.com"
          }
        }
      end)

      Accounts.find_or_create_user_from_oauth2(%{
        provider: :okta,
        uid: 1234,
        info: %{
          email: "tuist-tools@tools.io"
        },
        extra: %{
          raw_info: %{
            user: %{},
            token: %{
              other_params: %{
                "id_token" => "different-jwt-token"
              }
            }
          }
        }
      })

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

      organization =
        AccountsFixtures.organization_fixture(
          creator: user_one,
          sso_provider: :google,
          sso_organization_id: "tuist.io"
        )

      # Create an SSO user
      sso_user =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :google,
          uid: 123,
          info: %{email: "sso@tuist.io"},
          extra: %{
            raw_info: %{
              user: %{"hd" => "tuist.io"}
            }
          }
        })

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

      organization =
        AccountsFixtures.organization_fixture(
          creator: user_one,
          sso_provider: :okta,
          sso_organization_id: "tuist.okta.com"
        )

      # Create an SSO user
      sso_user =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :okta,
          uid: 456,
          info: %{email: "okta@tuist.io"},
          extra: %{
            raw_info: %{
              user: %{},
              token: %{
                other_params: %{"id_token" => "jwt-token"}
              }
            }
          }
        })

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
        Accounts.create_account_token(%{account: account, scopes: ["account:registry:read"], name: "test-token"})

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
          scopes: ["account:registry:read"],
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

      # Create organization without SSO initially
      organization = AccountsFixtures.organization_fixture()

      # Create a user with matching Google OAuth2 identity
      unassigned_user =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :google,
          uid: System.unique_integer([:positive]),
          info: %{email: "unassigned@tuist.io"},
          extra: %{
            raw_info: %{
              user: %{"hd" => "tuist.io"}
            }
          }
        })

      # Create a user already assigned to the organization
      assigned_user =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :google,
          uid: System.unique_integer([:positive]),
          info: %{email: "assigned@tuist.io"},
          extra: %{
            raw_info: %{
              user: %{"hd" => "tuist.io"}
            }
          }
        })

      Accounts.add_user_to_organization(assigned_user, organization, role: :user)

      # Create a user with different SSO provider
      different_provider_user =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :github,
          uid: System.unique_integer([:positive]),
          info: %{email: "github@tuist.io"}
        })

      # When
      unassigned_users = Accounts.find_unassigned_sso_users(organization, :google, "tuist.io")

      # Then
      user_ids = Enum.map(unassigned_users, & &1.id)
      assert unassigned_user.id in user_ids
      refute assigned_user.id in user_ids
      refute different_provider_user.id in user_ids
    end

    test "returns empty list when no matching users exist" do
      # Given
      organization =
        AccountsFixtures.organization_fixture(
          sso_provider: :google,
          sso_organization_id: "tuist.io"
        )

      # When
      unassigned_users = Accounts.find_unassigned_sso_users(organization, :google, "tuist.io")

      # Then
      assert unassigned_users == []
    end
  end

  describe "assign_existing_sso_users_to_organization/3" do
    test "assigns matching SSO users to organization and returns count" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)

      organization = AccountsFixtures.organization_fixture()

      # Create multiple users with matching Google OAuth2 identities
      user1 =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :google,
          uid: System.unique_integer([:positive]),
          info: %{email: "user1@tuist.io"},
          extra: %{
            raw_info: %{
              user: %{"hd" => "tuist.io"}
            }
          }
        })

      user2 =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :google,
          uid: System.unique_integer([:positive]),
          info: %{email: "user2@tuist.io"},
          extra: %{
            raw_info: %{
              user: %{"hd" => "tuist.io"}
            }
          }
        })

      # Verify users are not assigned to organization
      refute Accounts.belongs_to_organization?(user1, organization)
      refute Accounts.belongs_to_organization?(user2, organization)

      # When
      count =
        Accounts.assign_existing_sso_users_to_organization(organization, :google, "tuist.io")

      # Then
      assert count == 2
      assert Accounts.belongs_to_organization?(user1, organization)
      assert Accounts.belongs_to_organization?(user2, organization)
      assert Accounts.get_user_role_in_organization(user1, organization).name == "user"
      assert Accounts.get_user_role_in_organization(user2, organization).name == "user"
    end

    test "returns 0 when no matching users exist" do
      # Given
      organization = AccountsFixtures.organization_fixture()

      # When
      count =
        Accounts.assign_existing_sso_users_to_organization(organization, :google, "tuist.io")

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

  describe "okta_organization_for_user_email/1" do
    test "returns organization when user exists and has okta organization" do
      # Given
      user = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :okta,
          sso_organization_id: "company.okta.com"
        )

      # When
      {:ok, got_organization} = Accounts.okta_organization_for_user_email(user.email)

      # Then
      assert got_organization.id == organization.id
      assert got_organization.sso_provider == :okta
    end

    test "falls back to domain-based matching when user doesn't exist" do
      # Given - no user exists but organization exists for domain
      AccountsFixtures.organization_fixture(
        sso_provider: :okta,
        sso_organization_id: "company.okta.com"
      )

      # When
      {:ok, organization} = Accounts.okta_organization_for_user_email("newuser@company.com")

      # Then
      assert organization.sso_provider == :okta
      assert organization.sso_organization_id == "company.okta.com"
    end

    test "falls back to domain-based matching when user has no okta organization" do
      # Given
      user = AccountsFixtures.user_fixture(email: "user@company.com")
      # User has no organization

      # But organization exists for domain
      AccountsFixtures.organization_fixture(
        sso_provider: :okta,
        sso_organization_id: "company.okta.com"
      )

      # When
      {:ok, organization} = Accounts.okta_organization_for_user_email(user.email)

      # Then
      assert organization.sso_provider == :okta
      assert organization.sso_organization_id == "company.okta.com"
    end

    test "returns error when user does not exist" do
      # When / Then
      assert {:error, :not_found} ==
               Accounts.okta_organization_for_user_email("nonexistent@example.com")
    end

    test "returns error when user exists but has no okta organization" do
      # Given
      user = AccountsFixtures.user_fixture()

      # When / Then
      assert {:error, :not_found} == Accounts.okta_organization_for_user_email(user.email)
    end

    test "returns error when user has organization but no sso configured" do
      # Given
      user = AccountsFixtures.user_fixture()
      AccountsFixtures.organization_fixture(creator: user)

      # When / Then
      assert {:error, :not_found} == Accounts.okta_organization_for_user_email(user.email)
    end

    test "returns error when user has google sso instead of okta" do
      # Given
      user = AccountsFixtures.user_fixture()

      AccountsFixtures.organization_fixture(
        creator: user,
        sso_provider: :google,
        sso_organization_id: "company.com"
      )

      # When / Then
      assert {:error, :not_found} == Accounts.okta_organization_for_user_email(user.email)
    end
  end

  describe "get_okta_configuration_by_organization_id/1" do
    test "returns okta configuration when organization has okta configured with db values" do
      # Given
      user = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :okta,
          sso_organization_id: "company.okta.com",
          okta_client_id: "test_client_id",
          okta_client_secret: "test_client_secret"
        )

      # When
      {:ok, config} = Accounts.get_okta_configuration_by_organization_id(organization.id)

      # Then
      assert config.client_id == "test_client_id"
      assert config.client_secret == "test_client_secret"
      assert config.site == "company.okta.com"
    end

    test "returns error when organization does not have okta configured" do
      # Given
      user = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :google,
          sso_organization_id: "company.com"
        )

      # When / Then
      assert {:error, :not_found} ==
               Accounts.get_okta_configuration_by_organization_id(organization.id)
    end

    test "returns error when organization has okta as provider but no client_id" do
      # Given
      user = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :okta,
          sso_organization_id: "company.okta.com"
        )

      # When / Then
      assert {:error, :not_found} ==
               Accounts.get_okta_configuration_by_organization_id(organization.id)
    end

    test "returns error when organization does not exist" do
      # When / Then
      assert {:error, :not_found} == Accounts.get_okta_configuration_by_organization_id(999_999)
    end
  end

  describe "create_namespace_tenant_for_account/1" do
    test "creates a tenant and updates account with namespace_tenant_id" do
      # Given
      %{account: account} = AccountsFixtures.user_fixture()
      namespace_tenant_id = "tenant-123"
      account_name = account.name
      account_id = account.id

      expect(Tuist.Namespace, :create_tenant, 1, fn ^account_name, ^account_id ->
        {:ok, %{"tenant" => %{"id" => namespace_tenant_id}}}
      end)

      # When
      {:ok, updated_account} = Accounts.create_namespace_tenant_for_account(account)

      # Then
      assert updated_account.namespace_tenant_id == namespace_tenant_id
      assert updated_account.id == account.id
    end

    test "returns error when Namespace.create_tenant fails" do
      # Given
      %{account: account} = AccountsFixtures.user_fixture()
      error_reason = "Namespace API error"

      expect(Tuist.Namespace, :create_tenant, 1, fn _account_name, _account_id ->
        {:error, error_reason}
      end)

      # When
      {:error, reason} = Accounts.create_namespace_tenant_for_account(account)

      # Then
      assert reason == error_reason
      {:ok, reloaded_account} = Accounts.get_account_by_id(account.id)
      assert is_nil(reloaded_account.namespace_tenant_id)
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

    test "extracts issuer domain for Okta provider" do
      # Given
      auth = %{
        provider: :okta,
        extra: %{
          raw_info: %{
            token: %{
              other_params: %{
                "id_token" => "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJodHRwczovL3R1aXN0Lm9rdGEuY29tIn0.test"
              }
            }
          }
        }
      }

      # When
      result = Accounts.extract_provider_organization_id(auth)

      # Then
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
    test "returns custom endpoints when account has them configured" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      {:ok, _} = Accounts.create_account_cache_endpoint(account, %{url: "https://cache1.example.com"})
      {:ok, _} = Accounts.create_account_cache_endpoint(account, %{url: "https://cache2.example.com"})

      # When
      endpoints = Accounts.get_cache_endpoints_for_handle(account.name)

      # Then
      assert Enum.sort(endpoints) == Enum.sort(["https://cache1.example.com", "https://cache2.example.com"])
    end

    test "returns default endpoints when account has no custom endpoints" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      default_endpoints = ["https://default.tuist.dev"]
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
end
