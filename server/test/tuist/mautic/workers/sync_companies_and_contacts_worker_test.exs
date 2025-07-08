defmodule Tuist.Mautic.Workers.SyncCompaniesAndContactsWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Mautic
  alias Tuist.Mautic.Workers.SyncCompaniesAndContactsWorker
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  describe "perform/1" do
    test "creates and removes mautic contacts as expected" do
      # Given
      user = AccountsFixtures.user_fixture()

      _subscription =
        BillingFixtures.subscription_fixture(account_id: user.account.id, plan: :pro)

      user = Repo.preload(user, [account: :subscriptions], force: true)
      mautic_contact_id_to_delete = UUIDv7.generate()

      # Only mock contacts operations since we're only syncing contacts
      expect(Mautic, :contacts, fn ->
        {:ok,
         %{
           mautic_contact_id_to_delete => %{
             "fields" => %{"tuist_account_id" => UUIDv7.generate()}
           }
         }}
      end)

      # Expect contact operations
      contacts_to_create = [SyncCompaniesAndContactsWorker.build_contact_data(user)]

      expect(Mautic, :create_contacts, fn ^contacts_to_create ->
        :ok
      end)

      contacts_to_delete = [mautic_contact_id_to_delete]

      expect(Mautic, :remove_contacts, fn ^contacts_to_delete ->
        :ok
      end)

      # When/Then - only sync contacts
      assert perform_job(SyncCompaniesAndContactsWorker, %{
               "sync_contacts" => true,
               "sync_companies" => false,
               "sync_memberships" => false
             }) ==
               :ok
    end

    test "creates and removes mautic companies as expected" do
      # Given
      organization = AccountsFixtures.organization_fixture()

      _subscription =
        BillingFixtures.subscription_fixture(
          account_id: organization.account.id,
          plan: :enterprise
        )

      organization = Repo.preload(organization, [account: :subscriptions], force: true)
      mautic_company_id_to_delete = UUIDv7.generate()

      # Only mock companies operations since we're only syncing companies
      expect(Mautic, :companies, fn ->
        {:ok,
         %{
           mautic_company_id_to_delete => %{
             "fields" => %{"tuist_account_id" => UUIDv7.generate()}
           }
         }}
      end)

      # Expect company operations
      expect(Mautic, :create_company, 1, fn company_data ->
        assert company_data["companyname"] == organization.account.name
        assert company_data["custom_fields"]["tuist_subscription_type"] == "enterprise"
        assert company_data["custom_fields"]["tuist_has_active_subscription"] == true
        {:ok, %{"company" => %{"id" => 123}}}
      end)

      # Expect company removal (should be called for companies that no longer exist)
      expect(Mautic, :remove_company, 1, fn company_id ->
        assert company_id == mautic_company_id_to_delete
        :ok
      end)

      # When/Then - only sync companies
      assert perform_job(SyncCompaniesAndContactsWorker, %{
               "sync_contacts" => false,
               "sync_companies" => true,
               "sync_memberships" => false
             }) ==
               :ok
    end

    test "syncs contact-to-company memberships" do
      # Given - Create an organization and add users to it
      organization = AccountsFixtures.organization_fixture()
      user1 = AccountsFixtures.user_fixture()
      user2 = AccountsFixtures.user_fixture()

      # Add users to the organization (using the existing Accounts context)
      :ok = Accounts.add_user_to_organization(user1, organization, role: :admin)
      :ok = Accounts.add_user_to_organization(user2, organization, role: :user)

      # Create subscriptions
      _org_subscription =
        BillingFixtures.subscription_fixture(
          account_id: organization.account.id,
          plan: :enterprise
        )

      _user1_subscription =
        BillingFixtures.subscription_fixture(account_id: user1.account.id, plan: :pro)

      _user2_subscription =
        BillingFixtures.subscription_fixture(account_id: user2.account.id, plan: :air)

      # Mock Mautic API calls
      company_id = "mautic_company_123"
      contact1_id = "mautic_contact_456"
      contact2_id = "mautic_contact_789"

      # Mock contacts query - return existing contacts for our users
      expect(Mautic, :contacts, fn ->
        {:ok,
         %{
           contact1_id => %{
             "id" => contact1_id,
             "fields" => %{
               "tuist_account_id" => Integer.to_string(user1.account.id),
               "tuist_user_id" => Integer.to_string(user1.id)
             }
           },
           contact2_id => %{
             "id" => contact2_id,
             "fields" => %{
               "tuist_account_id" => Integer.to_string(user2.account.id),
               "tuist_user_id" => Integer.to_string(user2.id)
             }
           }
         }}
      end)

      # Mock companies query - return existing company for our organization
      expect(Mautic, :companies, fn ->
        {:ok,
         %{
           company_id => %{
             "id" => company_id,
             "fields" => %{
               "tuist_account_id" => Integer.to_string(organization.account.id)
             }
           }
         }}
      end)

      # Expect membership API calls
      expect(Mautic, :add_contact_to_company, 2, fn contact_id, comp_id ->
        assert comp_id == company_id
        assert contact_id in [contact1_id, contact2_id]
        :ok
      end)

      # When/Then - only sync memberships
      assert perform_job(SyncCompaniesAndContactsWorker, %{
               "sync_contacts" => false,
               "sync_companies" => false,
               "sync_memberships" => true
             }) == :ok
    end

    test "handles missing contacts or companies gracefully in membership sync" do
      # Given - Create organization and user but no Mautic entities
      organization = AccountsFixtures.organization_fixture()
      user = AccountsFixtures.user_fixture()

      # Add user to organization
      :ok = Accounts.add_user_to_organization(user, organization, role: :admin)

      # Mock empty Mautic responses
      expect(Mautic, :contacts, fn -> {:ok, %{}} end)
      expect(Mautic, :companies, fn -> {:ok, %{}} end)

      # Should not call add_contact_to_company since entities don't exist
      # (No expect calls means it shouldn't be called)

      # When/Then - should complete without errors
      assert perform_job(SyncCompaniesAndContactsWorker, %{
               "sync_contacts" => false,
               "sync_companies" => false,
               "sync_memberships" => true
             }) == :ok
    end
  end
end
