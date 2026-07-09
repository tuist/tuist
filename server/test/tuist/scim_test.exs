defmodule Tuist.SCIMTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Accounts
  alias Tuist.Accounts.AccountToken
  alias Tuist.SCIM
  alias Tuist.SCIM.Workers.AttachmentNotifierWorker

  setup :verify_on_exit!

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

    test "authenticate_token/1 rejects generic organization account tokens with the SCIM scope" do
      organization = organization_fixture(preload: [:account])

      {:ok, {_token, plaintext}} =
        Accounts.create_account_token(%{
          account: organization.account,
          scopes: [AccountToken.scim_scope()],
          name: "scim"
        })

      assert {:error, :invalid_token} = SCIM.authenticate_token(plaintext)
    end

    test "authenticate_token/1 rejects the generic form of a SCIM token" do
      organization = organization_fixture()
      {:ok, {_token, plaintext}} = SCIM.create_token(organization, %{name: "x"})

      generic_plaintext = String.replace(plaintext, "tuist_scim_", "tuist_", global: false)

      assert {:error, :invalid_token} = Accounts.account_token(generic_plaintext)
      assert {:error, :invalid_token} = SCIM.authenticate_token(generic_plaintext)
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

    test "provision_user/2 attaches an existing Tuist user to the organization", %{organization: org} do
      existing = user_fixture(email: "outsider@example.com")
      refute Accounts.belongs_to_organization?(existing, org)

      assert {:ok, user} = SCIM.provision_user(org, %{user_name: "outsider@example.com", role: :admin})
      assert user.id == existing.id
      assert Accounts.belongs_to_organization?(user, org)
      assert %{name: "admin"} = Accounts.get_user_role_in_organization(user, org)

      assert_enqueued(
        worker: AttachmentNotifierWorker,
        args: %{"user_id" => existing.id, "organization_id" => org.id}
      )
    end

    test "provision_user/2 attaches a user when creation reports the email was taken after lookup", %{
      organization: org
    } do
      email = "race@example.com"
      existing = user_fixture(email: email)
      lookup_counter = start_supervised!({Agent, fn -> 0 end})

      expect(Accounts, :get_user_by_email, 2, fn ^email ->
        Agent.get_and_update(lookup_counter, fn
          0 -> {{:error, :not_found}, 1}
          count -> {{:ok, existing}, count + 1}
        end)
      end)

      expect(Accounts, :create_user, fn ^email, opts ->
        assert Keyword.has_key?(opts, :confirmed_at)
        {:error, :email_taken}
      end)

      assert {:ok, user} = SCIM.provision_user(org, %{user_name: email})
      assert user.id == existing.id
      assert Accounts.belongs_to_organization?(user, org)
    end

    test "provision_user/2 does not enqueue a notification when a brand-new user is created", %{organization: org} do
      assert {:ok, _user} = SCIM.provision_user(org, %{user_name: "fresh@example.com"})

      refute_enqueued(worker: AttachmentNotifierWorker)
    end

    test "provision_user/2 does not re-notify an existing org member on idempotent calls", %{organization: org} do
      existing = user_fixture(email: "member@example.com")
      :ok = Accounts.add_user_to_organization(existing, org, role: :user)

      assert {:ok, _} = SCIM.provision_user(org, %{user_name: "member@example.com", role: :admin})

      refute_enqueued(worker: AttachmentNotifierWorker)
    end

    test "provision_user/2 with active: false does not add a brand-new user to the organization", %{organization: org} do
      assert {:ok, user} = SCIM.provision_user(org, %{user_name: "carol@example.com", active: false})
      assert user.active == false
      assert Accounts.get_user_by_id(user.id).active == true
      refute Accounts.belongs_to_organization?(user, org)
    end

    test "provision_user/2 with active: false rejects an existing user who isn't a member of the org", %{
      organization: org
    } do
      _existing = user_fixture(email: "stranger@example.com")

      # 201 + Location for a user we never attach would point at a SCIM
      # resource that immediately 404s on GET. Reject with 409 so the IdP
      # uses PATCH (the verb actually meant for deactivation) instead.
      assert {:error, :email_taken} =
               SCIM.provision_user(org, %{user_name: "stranger@example.com", active: false})
    end

    test "provision_user/2 with active: false deactivates an existing member", %{organization: org} do
      existing = user_fixture(email: "leaving@example.com")
      :ok = Accounts.add_user_to_organization(existing, org, role: :admin)

      assert {:ok, user} = SCIM.provision_user(org, %{user_name: "leaving@example.com", active: false})
      assert user.active == false
      refute Accounts.belongs_to_organization?(existing, org)
    end

    test "list_users/2 paginates with a userName filter", %{organization: org} do
      {:ok, _} = SCIM.provision_user(org, %{user_name: "x@example.com"})
      {:ok, _} = SCIM.provision_user(org, %{user_name: "y@example.com"})

      assert {:ok, page} = SCIM.list_users(org)
      assert page.total >= 2
      assert length(page.users) == page.total
      assert "x@example.com" in Enum.map(page.users, & &1.email)
      assert "y@example.com" in Enum.map(page.users, & &1.email)

      assert {:ok, %{total: 1, users: [%{email: "x@example.com"}]}} =
               SCIM.list_users(org, filter: %{attribute: "userName", op: :eq, value: "x@example.com"})
    end

    test "list_users/2 rejects unsupported filter attributes", %{organization: org} do
      assert {:error, :unsupported_filter} =
               SCIM.list_users(org, filter: %{attribute: "displayName", op: :eq, value: "alice"})
    end

    test "patch_user/3 deactivates and removes role via replace active=false", %{organization: org} do
      {:ok, user} = SCIM.provision_user(org, %{user_name: "d@example.com"})

      ops = [%{"op" => "replace", "path" => "active", "value" => false}]

      assert {:ok, updated} = SCIM.patch_user(org, user.id, ops)
      assert updated.active == false
      assert Accounts.get_user_by_id(user.id).active == true
      refute Accounts.belongs_to_organization?(user, org)
    end

    test "patch_user/3 deactivates and removes role via value-only replace (Azure-style)", %{organization: org} do
      {:ok, user} = SCIM.provision_user(org, %{user_name: "e@example.com"})

      ops = [%{"op" => "Replace", "value" => %{"active" => false}}]

      assert {:ok, updated} = SCIM.patch_user(org, user.id, ops)
      assert updated.active == false
      assert Accounts.get_user_by_id(user.id).active == true
      refute Accounts.belongs_to_organization?(user, org)
    end

    test "patch_user/3 returns a changeset when an email update conflicts", %{organization: org} do
      {:ok, user} = SCIM.provision_user(org, %{user_name: "rename@example.com"})
      _taken = user_fixture(email: "taken-rename@example.com")

      ops = [%{"op" => "replace", "path" => "userName", "value" => "taken-rename@example.com"}]

      assert {:error, %Ecto.Changeset{}} = SCIM.patch_user(org, user.id, ops)
    end

    test "deactivate_user/2 returns inactive and removes role without flipping the global user flag", %{organization: org} do
      {:ok, user} = SCIM.provision_user(org, %{user_name: "f@example.com"})

      assert {:ok, deactivated} = SCIM.deactivate_user(org, user.id)
      assert deactivated.active == false
      assert Accounts.get_user_by_id(user.id).active == true

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
      assert Accounts.get_user_by_id(user.id).active == true
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
      assert [_ | _] = admins
      assert [_ | _] = users
    end

    test "patch_group/3 add op promotes a user", %{organization: org, regular: regular} do
      ops = [%{"op" => "add", "value" => [%{"value" => to_string(regular.id)}]}]

      {:ok, _} = SCIM.patch_group(org, "admins", ops)
      assert %{name: "admin"} = Accounts.get_user_role_in_organization(regular, org)
    end

    test "patch_group/3 add op ignores users outside the organization", %{organization: org} do
      outsider = user_fixture()
      ops = [%{"op" => "add", "value" => [%{"value" => to_string(outsider.id)}]}]

      {:ok, _} = SCIM.patch_group(org, "admins", ops)
      refute Accounts.belongs_to_organization?(outsider, org)
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
