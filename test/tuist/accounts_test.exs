defmodule Tuist.AccountsTest do
  use Tuist.DataCase, async: false
  use Tuist.StubCase, billing: true

  alias Tuist.Accounts.Account
  alias Tuist.Billing
  alias Tuist.CommandEvents
  alias Tuist.CommandEventsFixtures
  alias Tuist.Projects
  alias Tuist.ProjectsFixtures
  alias Tuist.Accounts
  alias Tuist.AccountsFixtures
  alias Tuist.Environment

  use Mimic

  setup do
    JOSE.JWT
    |> stub(:peek_payload, fn _ ->
      %JOSE.JWT{
        fields: %{
          "iss" => "https://tuist.okta.com"
        }
      }
    end)

    :ok
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
      Environment |> stub(:on_premise?, fn -> false end)
      Billing |> expect(:start_trial, fn %{plan: :air, account: _} -> :ok end)

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
      Environment |> stub(:on_premise?, fn -> false end)
      Billing |> expect(:start_trial, fn %{plan: :air, account: _} -> :ok end)

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
      Environment |> stub(:on_premise?, fn -> false end)
      Billing |> expect(:start_trial, fn %{plan: :air, account: _} -> :ok end)

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
      Environment |> stub(:on_premise?, fn -> false end)
      Billing |> expect(:start_trial, fn %{plan: :air, account: _} -> :ok end)

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
      Environment |> stub(:on_premise?, fn -> false end)
      Billing |> expect(:start_trial, fn %{plan: :air, account: _} -> :ok end)

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
      Environment |> stub(:on_premise?, fn -> false end)
      Billing |> expect(:start_trial, fn %{plan: :air, account: _} -> :ok end)

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
      Environment |> stub(:on_premise?, fn -> false end)
      Billing |> stub(:start_trial, fn %{plan: :air, account: _} -> :ok end)

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
      assert got == invitation
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
      Tuist.Environment
      |> stub(:smtp_user_name, fn -> "smtp_user_name" end)

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

  import Tuist.AccountsFixtures
  alias Tuist.Accounts.{User, UserToken}

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
      Environment |> stub(:on_premise?, fn -> true end)
      user = AccountsFixtures.user_fixture()

      # When
      organization = Accounts.create_organization(%{name: "tuist", creator: user})

      # Then
      assert organization == Accounts.get_organization_by_id(organization.id)
      assert Accounts.organization_admin?(user, organization) == true
    end

    test "creates an organization" do
      # Given
      Environment |> stub(:on_premise?, fn -> false end)
      Billing |> expect(:start_trial, fn %{plan: :air, account: _} -> :ok end)
      user = AccountsFixtures.user_fixture()

      # When
      organization = Accounts.create_organization(%{name: "tuist", creator: user})

      # Then
      assert organization == Accounts.get_organization_by_id(organization.id)
      assert Accounts.organization_admin?(user, organization) == true
    end

    test "creates an organization when new pricing model is enabled" do
      # Given
      Billing
      |> expect(:start_trial, fn %{plan: :air, account: %Account{}} -> {:ok, %{}} end)

      user = AccountsFixtures.user_fixture()

      # When
      organization = Accounts.create_organization(%{name: "tuist", creator: user})

      # Then
      assert organization == Accounts.get_organization_by_id(organization.id)
      assert Accounts.organization_admin?(user, organization) == true
    end

    test "creates an organization with SSO provider" do
      # Given
      Environment |> stub(:on_premise?, fn -> false end)
      Billing |> stub(:start_trial, fn %{plan: :air, account: _} -> :ok end)
      user = AccountsFixtures.user_fixture()

      # When
      organization =
        Accounts.create_organization(
          %{
            name: "tuist",
            creator: user
          },
          sso_provider: :google,
          sso_organization_id: "tuist.io"
        )

      # Then
      assert organization == Accounts.get_organization_by_id(organization.id)
      assert organization.sso_provider == :google
      assert organization.sso_organization_id == "tuist.io"
      assert Accounts.organization_admin?(user, organization) == true
    end

    test "creates an organization when billing is enabled" do
      # Given
      Environment |> stub(:on_premise?, fn -> false end)
      user = AccountsFixtures.user_fixture()

      # When
      organization = Accounts.create_organization(%{name: "tuist", creator: user})

      # Then
      assert organization == Accounts.get_organization_by_id(organization.id)
      assert Accounts.get_account_from_organization(organization).customer_id != ""
      assert Accounts.organization_admin?(user, organization) == true
    end
  end

  describe "delete_organization/1" do
    test "deletes an organization" do
      # Given
      Environment |> stub(:on_premise?, fn -> false end)
      Billing |> expect(:start_trial, fn %{plan: :air, account: _} -> :ok end)

      user = AccountsFixtures.user_fixture()
      organization = Accounts.create_organization(%{name: "tuist", creator: user})
      account = Accounts.get_account_from_organization(organization)

      # When
      Accounts.delete_organization(organization)

      # Then
      assert Accounts.get_organization_by_id(organization.id) == nil
      assert Accounts.get_account_by_id(account.id) == nil
    end
  end

  describe "find_or_create_user_from_oauth2" do
    test "handles creating another account with the same handle gracefully" do
      # Given
      Environment |> stub(:on_premise?, fn -> false end)

      Billing
      |> expect(:start_trial, fn %{plan: :air, account: _} -> :ok end)
      |> expect(:start_trial, fn %{plan: :air, account: _} -> :ok end)

      first_oauth_identity = %{
        provider: :github,
        uid: 123,
        info: %{email: "find_or_create_user_from_oauth2@tuist.io"}
      }

      second_oauth_identity = %{
        provider: :github,
        uid: 456,
        info: %{email: "find_or_create_user_from_oauth2@tuist.test.io"}
      }

      # When
      %{account: %{name: first_account_handle}} =
        Accounts.find_or_create_user_from_oauth2(first_oauth_identity, preload: [:account])

      %{account: %{name: second_account_handle}} =
        Accounts.find_or_create_user_from_oauth2(second_oauth_identity, preload: [:account])

      # Then
      assert first_account_handle == "find_or_create_user_from_oauth2"
      assert second_account_handle == "find_or_create_user_from_oauth21"
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
      assert CommandEvents.get_command_event_by_id(command_event.id) == nil
      assert Accounts.get_device_code(code.code) == nil
    end
  end

  describe "get_organization_account_by_name/1" do
    test "gets a given organization account doing a case-insensitive search" do
      # Given
      Environment |> stub(:on_premise?, fn -> false end)
      Billing |> expect(:start_trial, fn %{plan: :air, account: _} -> :ok end)
      user = AccountsFixtures.user_fixture()
      organization = Accounts.create_organization(%{name: "tuist", creator: user})
      account = Accounts.get_account_from_organization(organization)

      # When
      got = Accounts.get_organization_account_by_name("TUIST")

      # Then
      assert %{
               account: account,
               organization: organization
             } == got
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
      Environment |> stub(:on_premise?, fn -> true end)
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
      Environment |> stub(:on_premise?, fn -> false end)
      Billing |> stub(:start_trial, fn %{plan: :air, account: _} -> :ok end)
      email = unique_user_email()

      # When
      {:ok, user} = Accounts.create_user(email, password: valid_user_password())

      # Then
      assert user.email == email
      assert is_binary(user.encrypted_password)
      assert is_nil(user.confirmed_at)
    end

    test "create a user with a password when new pricing model is enabled" do
      # Given
      Billing
      |> expect(:start_trial, fn %{plan: :air, account: %Account{}} -> {:ok, %{}} end)

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
      Environment |> stub(:on_premise?, fn -> false end)
      Billing |> expect(:start_trial, fn %{plan: :air, account: _} -> :ok end)
      email = "#{Tuist.TestUtilities.unique_integer()}@TUIST.io"

      # When
      {:ok, user} = Accounts.create_user(email, password: valid_user_password())

      # Then
      assert user.email == String.downcase(email)
    end

    test "create a user with a password when email has a dot in the username" do
      # Given
      Environment |> stub(:on_premise?, fn -> false end)
      Billing |> expect(:start_trial, fn %{plan: :air, account: _} -> :ok end)
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
      Environment |> stub(:on_premise?, fn -> false end)
      Billing |> stub(:start_trial, fn %{plan: :air, account: _} -> :ok end)
      Accounts.create_user("foo@tuist.io")

      # When
      assert %{name: "foo1"} =
               Accounts.create_user("foo@tuist.test")
               |> elem(1)
               |> Accounts.get_account_from_user()
    end

    test "errors after attempting finding a unique account handle using suffixes" do
      # Given
      Environment |> stub(:on_premise?, fn -> false end)
      Billing |> stub(:start_trial, fn %{plan: :air, account: _} -> :ok end)
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
      Environment |> stub(:on_premise?, fn -> false end)
      Billing |> expect(:start_trial, fn %{plan: :air, account: _} -> :ok end)
      Accounts.create_user("foo@tuist.io")

      # When
      assert {:error, :email_taken} = Accounts.create_user("foo@tuist.io")
    end
  end

  describe "change_user_password/2" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_password(%User{})
      assert changeset.required == [:encrypted_password]
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
      Tuist.Environment
      |> stub(:smtp_user_name, fn -> "stmp_user_name" end)

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

      Tuist.Environment
      |> stub(:smtp_user_name, fn -> "stmp_user_name" end)

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
      Tuist.Environment
      |> stub(:smtp_user_name, fn -> "stmp_user_name" end)

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

      Tuist.Environment
      |> stub(:smtp_user_name, fn -> "stmp_user_name" end)

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
  end

  describe "find_or_create_user_from_oauth2/1" do
    test "creates a user from a github identity" do
      # Given
      Environment |> stub(:on_premise?, fn -> false end)
      Billing |> expect(:start_trial, fn %{plan: :air, account: _} -> :ok end)

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
      Environment |> stub(:on_premise?, fn -> false end)
      Billing |> expect(:start_trial, fn %{plan: :air, account: _} -> :ok end)

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
      Environment |> stub(:on_premise?, fn -> false end)
      Billing |> expect(:start_trial, fn %{plan: :air, account: _} -> :ok end)

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
      Stripe.Customer
      |> stub(:create, fn _ -> {:ok, %Stripe.Customer{id: "customer_id"}} end)

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
      Environment |> stub(:on_premise?, fn -> false end)
      Billing |> expect(:start_trial, fn %{plan: :air, account: _} -> :ok end)

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
      assert [user_one.id, user_three.id] == Enum.map(got, & &1.id) |> Enum.sort()
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
      assert [user_one.id, user_three.id] == Enum.map(got, & &1.id) |> Enum.sort()
    end

    test "returns users of an organization with a google hosted domain" do
      # Given
      Environment |> stub(:on_premise?, fn -> false end)
      Billing |> stub(:start_trial, fn %{plan: :air, account: _} -> :ok end)
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
      assert [user_one.id, user_three.id] == Enum.map(got, & &1.id) |> Enum.sort()
    end

    test "returns users of an organization with a given okta id" do
      # Given
      Environment |> stub(:on_premise?, fn -> false end)
      Billing |> stub(:start_trial, fn %{plan: :air, account: _} -> :ok end)
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

      JOSE.JWT
      |> stub(:peek_payload, fn _ ->
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
      assert [user_one.id, user_three.id] == Enum.map(got, & &1.id) |> Enum.sort()
    end
  end
end
