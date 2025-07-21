defmodule Tuist.AccountsTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use TuistTestSupport.Cases.StubCase, billing: true
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Accounts
  alias Tuist.Accounts.AccountToken
  alias Tuist.Accounts.User
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

      _command_event =
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

  describe "list_customer_id_and_remote_cache_hits_count_pairs/1" do
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
        created_at: ~U[2025-01-01 23:00:00Z]
      )

      CommandEventsFixtures.command_event_fixture(
        name: "generate",
        project_id: second_user_project.id,
        user_id: second_user.id,
        remote_cache_target_hits: ["Module"],
        remote_test_target_hits: ["ModuleTeests"],
        created_at: ~U[2025-01-01 23:00:00Z]
      )

      # When
      assert {[{^first_account_customer_id, 1}], _} =
               Accounts.list_customer_id_and_remote_cache_hits_count_pairs()
    end

    test "returns only the customers with a customer_id present (ClickHouse)" do
      # Given
      stub(FunWithFlags, :enabled?, fn :clickhouse_events -> true end)

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
        remote_cache_target_hits: ["Module"],
        remote_test_target_hits: ["ModuleTeests"],
        ran_at: ~U[2025-01-01 23:00:00Z]
      )

      # When
      assert {[{^first_account_customer_id, 1}], _} =
               Accounts.list_customer_id_and_remote_cache_hits_count_pairs()
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
            email: "tuist@tuist.io"
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
            email: "tuist@tuist.io"
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
            email: "tuist@tuist.io"
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
            email: "tuist@tuist.io"
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
            email: "tuist@tuist.io"
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

  describe "get_invitation_by_id/1" do
    test "returns a given invitation" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: user)

      invitation =
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

      invitation =
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

      invitation =
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

      invitation =
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

    test "returns :forbidden error when invitee email does not match" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: user)
      invitee = AccountsFixtures.user_fixture(email: "new@tuist.io")

      invitation =
        Accounts.invite_user_to_organization("different@tuist.io", %{
          inviter: user,
          to: organization,
          url: fn token -> token end
        })

      # When
      got = Accounts.get_invitation_by_token(invitation.token, invitee)

      # Then
      assert got == {:error, :forbidden}
    end

    test "returns :not_found when an invitation with a given token does not exist" do
      # Given
      invitee = AccountsFixtures.user_fixture(email: "new@tuist.io")

      # When
      got = Accounts.get_invitation_by_token("non-existent", invitee)

      # Then
      assert got == {:error, :not_found}
    end
  end

  describe "accept_invitation/1" do
    test "accepts an invitation" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: user)
      invitee = AccountsFixtures.user_fixture(email: "new@tuist.io")

      invitation =
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
      stub(Tuist.Environment, :smtp_user_name, fn -> "smtp_user_name" end)
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
      assert invitation.token == "token"
      assert invitation.invitee_email == "test@tuist.io"
      assert invitation.inviter_type == "User"
      assert invitation.organization_id == organization.id
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
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email("unknown@example.com")
    end

    test "returns the user if the email exists doing a case-insensitive search" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user_by_email(String.upcase(user.email))
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
      assert Accounts.get_account_by_id(account.id) == nil
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
      assert Accounts.get_account_by_id(account.id) == nil
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
      assert got != nil
    end
  end

  describe "create_user/1" do
    test "doesn't start biling trial if it's an on-premise environment" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> false end)
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
      Accounts.create_user("foo1@tuist.io")
      Accounts.create_user("foo2@tuist.io")
      Accounts.create_user("foo3@tuist.io")
      Accounts.create_user("foo4@tuist.io")
      Accounts.create_user("foo5@tuist.io")

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
      assert !is_nil(get_change(changeset, :encrypted_password))
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
      stub(Tuist.Environment, :smtp_user_name, fn -> "stmp_user_name" end)
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

      stub(Tuist.Environment, :smtp_user_name, fn -> "stmp_user_name" end)

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
      stub(Tuist.Environment, :smtp_user_name, fn -> "stmp_user_name" end)
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

      stub(Tuist.Environment, :smtp_user_name, fn -> "stmp_user_name" end)

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
            email: "tuist@tuist.io"
          }
        })

      # Then
      assert user.email == "tuist@tuist.io"
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
            email: "tuist@tuist.io"
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
      assert user.email == "tuist@tuist.io"
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
            email: "tuist@tuist.io"
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
      assert user.email == "tuist@tuist.io"
      oauth2_identity = Accounts.get_oauth2_identity_by_provider_and_id(:google, 123)
      assert oauth2_identity.provider_organization_id == nil
    end

    test "updates an existing user with a new github identity" do
      user = user_fixture(email: "tuist@tuist.io")

      got =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :github,
          uid: 123,
          info: %{
            email: "tuist@tuist.io"
          }
        })

      assert user.email == got.email
      assert Accounts.find_oauth2_identity(%{user: user, provider: :github}) != nil
    end

    test "updates an existing user with a new okta identity" do
      user = user_fixture(email: "tuist@tuist.io")

      got =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :okta,
          uid: 123,
          info: %{
            email: "tuist@tuist.io"
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
      assert Accounts.find_oauth2_identity(%{user: user, provider: :okta}) != nil
    end

    test "handles reserved handle names by adding a suffix" do
      # Given
      stub(Environment, :tuist_hosted?, fn -> true end)
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
    test "returns the account with the given customer_id" do
      # Given
      stub(Stripe.Customer, :create, fn _ -> {:ok, %Stripe.Customer{id: "customer_id"}} end)
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      customer_id = account.customer_id

      # When
      got = Accounts.get_account_from_customer_id(customer_id)

      # Then
      assert got == account
    end

    test "returns nil if the account with the given customer_id does not exist" do
      # Given
      AccountsFixtures.user_fixture()

      # When
      got = Accounts.get_account_from_customer_id("unknown")

      # Then
      assert got == nil
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
            email: "tuist@tuist.io"
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

  describe "update_user_role_in_organization/3" do
    test "Updates user role from user to admin" do
      # Given
      admin = AccountsFixtures.user_fixture()
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: admin)
      Accounts.add_user_to_organization(user, organization, role: :user)

      # When
      Accounts.update_user_role_in_organization(user, organization, :admin)

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
      Accounts.update_user_role_in_organization(user, organization, :user)

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
            email: "tuist@tuist.io"
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
            email: "tuist@tuist.io"
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
        Accounts.create_account_token(%{account: account, scopes: [:account_registry_read]})

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
        Accounts.create_account_token(%{account: account, scopes: [:account_registry_read]})

      # Then
      %{id: token_id} = Repo.one(AccountToken)
      assert "tuist_#{token_id}_generated-hash" == got_token_value
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
      assert Accounts.get_account_by_id(account.id) == nil
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
      assert Accounts.get_account_by_id(account.id) == nil
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
end
