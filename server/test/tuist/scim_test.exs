defmodule Tuist.SCIMTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Accounts
  alias Tuist.Accounts.AccountToken
  alias Tuist.SCIM

  describe "tokens" do
    test "create_token/2 issues a usable bearer and persists only its hash" do
      organization = organization_fixture(preload: [:account])

      assert {:ok, {token, plaintext}} = SCIM.create_token(organization, %{name: "okta"})
      assert token.account_id == organization.account.id
      assert token.scopes == [AccountToken.scim_scope()]
      assert token.encrypted_token_hash != plaintext
      assert String.starts_with?(plaintext, "tuist_scim_")

      assert {:ok, ^organization, _token} = plaintext |> SCIM.authenticate_token() |> resolve(organization)
    end

    test "authenticate_token/1 accepts organization account tokens with the SCIM scope" do
      organization = organization_fixture(preload: [:account])

      {:ok, {_token, plaintext}} =
        Accounts.create_account_token(%{
          account: organization.account,
          scopes: [AccountToken.scim_scope()],
          name: "scim"
        })

      assert {:ok, ^organization, _token} = plaintext |> SCIM.authenticate_token() |> resolve(organization)
    end

    test "authenticate_token/1 rejects account tokens without the SCIM scope" do
      organization = organization_fixture(preload: [:account])

      {:ok, {_token, plaintext}} =
        Accounts.create_account_token(%{
          account: organization.account,
          scopes: ["project:cache:read"],
          name: "cache"
        })

      assert {:error, :invalid_token} = SCIM.authenticate_token(plaintext)
    end

    test "authenticate_token/1 rejects SCIM-scoped personal account tokens" do
      user = user_fixture(preload: [:account])

      {:ok, {_token, plaintext}} =
        Accounts.create_account_token(%{
          account: user.account,
          scopes: [AccountToken.scim_scope()],
          name: "scim"
        })

      assert {:error, :invalid_token} = SCIM.authenticate_token(plaintext)
    end

    test "authenticate_token/1 rejects a tampered token" do
      organization = organization_fixture()
      {:ok, {_token, plaintext}} = SCIM.create_token(organization, %{name: "x"})

      assert {:error, :invalid_token} = SCIM.authenticate_token(plaintext <> "x")
      assert {:error, :invalid_token} = SCIM.authenticate_token("tuist_scim_not-a-uuid_xxx")
      assert {:error, :invalid_token} = SCIM.authenticate_token("garbage")
    end

    test "revoke_token/1 invalidates the bearer" do
      organization = organization_fixture()
      {:ok, {token, plaintext}} = SCIM.create_token(organization, %{name: "x"})

      {:ok, _} = SCIM.revoke_token(token)

      assert {:error, :invalid_token} = SCIM.authenticate_token(plaintext)
    end
  end

  describe "users" do
    setup do
      organization = organization_fixture()
      %{organization: organization}
    end

    test "provision_user/2 creates a new user and adds them to the org as user", %{organization: org} do
      assert {:ok, user} = SCIM.provision_user(org, %{user_name: "alice@example.com"})
      assert user.email == "alice@example.com"
      assert user.active == true
      assert Accounts.belongs_to_organization?(user, org)
      assert %{name: "user"} = Accounts.get_user_role_in_organization(user, org)
    end

    test "provision_user/2 promotes role on an existing user", %{organization: org} do
      existing = user_fixture(email: "bob@example.com")
      :ok = Accounts.add_user_to_organization(existing, org, role: :user)

      assert {:ok, _} = SCIM.provision_user(org, %{user_name: "bob@example.com", role: :admin})
      assert %{name: "admin"} = Accounts.get_user_role_in_organization(existing, org)
    end

    test "provision_user/2 with active: false creates an inactive user", %{organization: org} do
      assert {:ok, user} = SCIM.provision_user(org, %{user_name: "carol@example.com", active: false})
      assert user.active == false
    end

    test "list_users/2 paginates with a userName filter", %{organization: org} do
      {:ok, _} = SCIM.provision_user(org, %{user_name: "x@example.com"})
      {:ok, _} = SCIM.provision_user(org, %{user_name: "y@example.com"})

      page = SCIM.list_users(org)
      assert page.total >= 2
      assert length(page.users) == page.total
      assert "x@example.com" in Enum.map(page.users, & &1.email)
      assert "y@example.com" in Enum.map(page.users, & &1.email)

      assert %{total: 1, users: [%{email: "x@example.com"}]} =
               SCIM.list_users(org, filter: %{attribute: "userName", op: :eq, value: "x@example.com"})
    end

    test "patch_user/3 deactivates and removes role via replace active=false", %{organization: org} do
      {:ok, user} = SCIM.provision_user(org, %{user_name: "d@example.com"})

      ops = [%{"op" => "replace", "path" => "active", "value" => false}]

      assert {:ok, updated} = SCIM.patch_user(org, user.id, ops)
      assert updated.active == false
      refute Accounts.belongs_to_organization?(user, org)
    end

    test "patch_user/3 deactivates and removes role via value-only replace (Azure-style)", %{organization: org} do
      {:ok, user} = SCIM.provision_user(org, %{user_name: "e@example.com"})

      ops = [%{"op" => "Replace", "value" => %{"active" => false}}]

      assert {:ok, updated} = SCIM.patch_user(org, user.id, ops)
      assert updated.active == false
      refute Accounts.belongs_to_organization?(user, org)
    end

    test "deactivate_user/2 sets active false and removes role", %{organization: org} do
      {:ok, user} = SCIM.provision_user(org, %{user_name: "f@example.com"})

      assert {:ok, deactivated} = SCIM.deactivate_user(org, user.id)
      assert deactivated.active == false

      refute Accounts.belongs_to_organization?(user, org)
    end

    test "deactivate_user/2 preserves SSO-linked users while removing their explicit role" do
      org =
        organization_fixture(
          sso_provider: :google,
          sso_organization_id: "sso-deactivate-#{System.unique_integer([:positive])}.com"
        )

      {:ok, user} = SCIM.provision_user(org, %{user_name: "sso-deactivate@example.com"})

      {:ok, _oauth_identity} =
        Accounts.link_oauth_identity_to_user(user, %{
          provider: :google,
          id_in_provider: "google-#{System.unique_integer([:positive])}",
          provider_organization_id: org.sso_organization_id
        })

      assert Accounts.belongs_to_sso_organization?(user, org)

      assert {:ok, deactivated} = SCIM.deactivate_user(org, user.id)
      assert deactivated.active == false
      assert Accounts.get_user_by_id(user.id)
      assert Accounts.get_user_role_in_organization(user, org) == nil
    end

    test "get_user/2 returns not_found for a non-member", %{organization: org} do
      stranger = user_fixture()
      assert {:error, :not_found} = SCIM.get_user(org, stranger.id)
    end

    test "get_user/2 returns not_found for a non-integer id", %{organization: org} do
      assert {:error, :not_found} = SCIM.get_user(org, "not-an-id")
    end
  end

  describe "groups" do
    setup do
      organization = organization_fixture()
      {:ok, admin} = SCIM.provision_user(organization, %{user_name: "g-admin@example.com", role: :admin})
      {:ok, regular} = SCIM.provision_user(organization, %{user_name: "g-user@example.com", role: :user})
      %{organization: organization, admin: admin, regular: regular}
    end

    test "list_groups/1 returns the two synthetic groups", %{organization: org} do
      assert [%{id: "admins", members: admins}, %{id: "users", members: users}] = SCIM.list_groups(org)
      assert length(admins) >= 1
      assert length(users) >= 1
    end

    test "patch_group/3 add op promotes a user", %{organization: org, regular: regular} do
      ops = [%{"op" => "add", "value" => [%{"value" => to_string(regular.id)}]}]

      {:ok, _} = SCIM.patch_group(org, "admins", ops)
      assert %{name: "admin"} = Accounts.get_user_role_in_organization(regular, org)
    end

    test "patch_group/3 remove op via Okta-style path filter removes the member", %{
      organization: org,
      admin: admin
    } do
      ops = [%{"op" => "remove", "path" => ~s(members[value eq "#{admin.id}"])}]

      {:ok, _} = SCIM.patch_group(org, "admins", ops)
      refute Accounts.belongs_to_organization?(admin, org)
    end
  end

  defp resolve({:ok, org, token}, expected) do
    if org.id == expected.id, do: {:ok, expected, token}, else: {:error, :mismatch}
  end

  defp resolve(other, _), do: other
end
