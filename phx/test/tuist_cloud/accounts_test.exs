defmodule TuistCloud.AccountsTest do
  alias TuistCloud.Accounts
  alias TuistCloud.Accounts.OrganizationAccount
  alias TuistCloud.AccountsFixtures
  alias TuistCloud.Environment
  use TuistCloud.DataCase
  use Mimic

  describe "admin?/2" do
    test "admin? returns false if the user is not an admin" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture()

      # When
      assert Accounts.admin?(user, organization) == false
    end

    test "admin? returns true if the user is the admin of the organization" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture()
      Accounts.add_user_to_organization(user, organization, role: :admin)

      # When
      assert Accounts.admin?(user, organization) == true
    end
  end

  describe "user?/2" do
    test "user? returns false if the user is not an admin" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture()

      # When
      assert Accounts.user?(user, organization) == false
    end

    test "user? returns true if the user is user of the organization" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture()
      Accounts.add_user_to_organization(user, organization, role: :user)

      # When
      assert Accounts.user?(user, organization) == true
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

    test "returns false if the user is not an admin nor an user of the organization" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture()

      # When
      assert Accounts.belongs_to_organization?(user, organization) == false
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
    test "returns a given invitation" do
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
        Accounts.get_invitation_by_invitee_email_and_organization("new@tuist.io", organization)

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
      :tls_certificate_check
      |> stub(:options, fn _ -> %{} end)

      TuistCloud.Environment
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
    assert organization == hd(got).organization
  end

  import TuistCloud.AccountsFixtures
  alias TuistCloud.Accounts.{User, UserToken}

  describe "get_user_by_email/1" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email("unknown@example.com")
    end

    test "returns the user if the email exists" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user_by_email(user.email)
    end
  end

  describe "get_user_by_email_and_password/2" do
    setup do
      TuistCloud.Environment
      |> stub(:secret_key_password, fn -> "secret_key_password" end)

      :ok
    end

    test "does not return the user if the email does not exist" do
      assert {:error, :invalid_email_or_password} =
               Accounts.get_user_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "does not return the user if the password is not valid" do
      user = user_fixture()

      assert {:error, :invalid_email_or_password} =
               Accounts.get_user_by_email_and_password(user.email, "invalid")
    end

    test "returns the user if the email and password are valid" do
      %{id: id} = user = user_fixture()

      assert {:ok, %User{id: ^id}} =
               Accounts.get_user_by_email_and_password(user.email, valid_user_password())
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
    test "creates an organization" do
      # Given
      user = AccountsFixtures.user_fixture()

      # When
      organization = Accounts.create_organization(%{name: "tuist", creator: user})

      # Then
      assert organization == Accounts.get_organization_by_id(organization.id)
      assert Accounts.admin?(user, organization) == true
    end

    test "creates an organization when billing is enabled" do
      # Given
      user = AccountsFixtures.user_fixture()

      Environment
      |> stub(:stripe_configured?, fn -> true end)

      Stripe.Customer
      |> stub(:create, fn _ -> {:ok, %Stripe.Customer{id: "customer_id"}} end)

      # When
      organization = Accounts.create_organization(%{name: "tuist", creator: user})

      # Then
      assert organization == Accounts.get_organization_by_id(organization.id)
      assert Accounts.get_account_from_organization(organization).customer_id == "customer_id"
      assert Accounts.admin?(user, organization) == true
    end
  end

  describe "delete_organization/1" do
    test "deletes an organization" do
      # Given
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

  describe "get_organization_account_by_name/1" do
    test "gets a given organization account" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = Accounts.create_organization(%{name: "tuist", creator: user})
      account = Accounts.get_account_from_organization(organization)

      # When
      got = Accounts.get_organization_account_by_name("tuist")

      # Then
      assert %OrganizationAccount{
               account: account,
               organization: organization
             } == got
    end
  end

  describe "create_user/1" do
    test "create a user with a password" do
      email = unique_user_email()
      user = Accounts.create_user(email, password: valid_user_password())
      assert user.email == email
      assert is_binary(user.encrypted_password)
      assert is_nil(user.confirmed_at)
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
      :tls_certificate_check
      |> stub(:options, fn _ -> %{} end)

      TuistCloud.Environment
      |> stub(:smtp_user_name, fn -> "stmp_user_name" end)

      %{user: user_fixture(confirmed_at: nil)}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
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

      :tls_certificate_check
      |> stub(:options, fn _ -> %{} end)

      TuistCloud.Environment
      |> stub(:smtp_user_name, fn -> "stmp_user_name" end)

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
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
      :tls_certificate_check
      |> stub(:options, fn _ -> %{} end)

      TuistCloud.Environment
      |> stub(:smtp_user_name, fn -> "stmp_user_name" end)

      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
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

      :tls_certificate_check
      |> stub(:options, fn _ -> %{} end)

      TuistCloud.Environment
      |> stub(:smtp_user_name, fn -> "stmp_user_name" end)

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
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
      TuistCloud.Environment
      |> stub(:secret_key_password, fn -> "secret_key_password" end)

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

  describe "find_or_create_user_from_oauth2/1" do
    test "creates a user from the github identity" do
      user =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :github,
          uid: 123,
          info: %{
            email: "tuist@tuist.io"
          }
        })

      assert user.email == "tuist@tuist.io"
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
      assert Accounts.find_oauth2_identity_by_user_id(user.id)
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
      Environment
      |> stub(:stripe_configured?, fn -> true end)

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

  describe "update_plan/2" do
    test "sets plan to :enterprise" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      # When
      Accounts.update_plan(account, :enterprise)

      # Then
      assert account.plan == nil
      assert Accounts.get_account_by_id(account.id).plan == :enterprise
    end

    test "sets plan to nil" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      Accounts.update_plan(account, :enterprise)
      account_with_enterprise = Accounts.get_account_by_id(account.id)

      # When
      Accounts.update_plan(account_with_enterprise, nil)

      # Then
      assert account_with_enterprise.plan == :enterprise
      assert Accounts.get_account_by_id(account.id).plan == nil
    end
  end

  describe "remove_user_from_organization/1" do
    test "returns a user from an organization" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture()
      Accounts.add_user_to_organization(user, organization, role: :user)

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
      assert Accounts.admin?(user, organization) == true
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
      assert Accounts.admin?(user, organization) == false
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
      organization = AccountsFixtures.organization_fixture()
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
  end
end
