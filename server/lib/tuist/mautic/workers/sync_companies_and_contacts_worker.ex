defmodule Tuist.Mautic.Workers.SyncCompaniesAndContactsWorker do
  @moduledoc ~S"""
  Worker that syncs Tuist accounts (organizations and users) with Mautic.
  """
  use Oban.Worker

  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.Accounts.Organization
  alias Tuist.Accounts.User
  alias Tuist.Billing.Subscription
  alias Tuist.Mautic
  alias Tuist.Repo

  @impl Oban.Worker
  def perform(job) do
    args = job.args || %{}
    sync_contacts = Map.get(args, "sync_contacts", true)
    sync_companies = Map.get(args, "sync_companies", true)
    sync_memberships = Map.get(args, "sync_memberships", true)

    mautic_contacts =
      if sync_contacts or sync_memberships do
        {:ok, contacts} = Mautic.contacts()
        Map.filter(contacts, &mautic_tuist_account_id_filter/1)
      else
        %{}
      end

    mautic_companies =
      if sync_companies or sync_memberships do
        {:ok, companies} = Mautic.companies()
        Map.filter(companies, &mautic_tuist_account_id_filter/1)
      else
        %{}
      end

    if sync_contacts do
      users = users()
      sync_users(mautic_contacts, users)
    end

    if sync_companies do
      organizations = organizations()
      sync_organizations(mautic_companies, organizations)
    end

    if sync_memberships do
      sync_memberships(mautic_contacts, mautic_companies)
    end

    :ok
  end

  defp mautic_tuist_account_id_filter({_, value}) do
    tuist_account_id =
      get_in(value, ["fields", "tuist_account_id"]) ||
        get_in(value, ["fields", "all", "tuist_account_id"])

    not is_nil(tuist_account_id)
  end

  defp users do
    subscriptions_query = from(s in Subscription, order_by: [desc: s.inserted_at])

    Repo.all(
      from(u in User,
        preload: [account: [subscriptions: ^subscriptions_query]]
      )
    )
  end

  defp organizations do
    subscriptions_query = from(s in Subscription, order_by: [desc: s.inserted_at])

    Repo.all(
      from(o in Organization,
        preload: [account: [subscriptions: ^subscriptions_query]]
      )
    )
  end

  defp sync_users(mautic_contacts, users) do
    :ok = users |> Enum.map(&build_contact_data/1) |> Mautic.create_contacts()

    user_account_ids = Enum.map(users, &Integer.to_string(&1.account.id))

    :ok =
      mautic_contacts
      |> Enum.flat_map(fn {id, contact} ->
        contact_tuist_account_id =
          get_in(contact, ["fields", "tuist_account_id"]) ||
            get_in(contact, ["fields", "all", "tuist_account_id"])

        if contact_tuist_account_id in user_account_ids do
          []
        else
          [id]
        end
      end)
      |> Mautic.remove_contacts()
  end

  def build_contact_data(%{account: account} = user) do
    subscription = get_current_active_subscription(account)
    subscription_type = if subscription, do: to_string(subscription.plan), else: "air"

    %{
      "email" => user.email,
      "firstname" => account.name,
      "custom_fields" => %{
        "tuist_account_id" => Integer.to_string(account.id),
        "tuist_user_id" => Integer.to_string(user.id),
        "tuist_billing_email" => account.billing_email,
        "tuist_is_confirmed" => not is_nil(user.confirmed_at),
        "tuist_subscription_type" => subscription_type,
        "tuist_has_active_subscription" => not is_nil(subscription)
      }
    }
  end

  defp sync_organizations(mautic_companies, organizations) do
    Enum.each(organizations, fn organization ->
      company_data = build_organization_data(organization)
      existing_company = find_company_by_account_id(mautic_companies, organization.account.id)

      if existing_company do
        {:ok, _} = Mautic.update_company(existing_company["id"], company_data)
      else
        {:ok, _} = Mautic.create_company(company_data)
      end
    end)

    organization_account_ids = Enum.map(organizations, &Integer.to_string(&1.account.id))

    Enum.each(mautic_companies, fn {id, company} ->
      company_tuist_account_id =
        get_in(company, ["fields", "tuist_account_id"]) ||
          get_in(company, ["fields", "all", "tuist_account_id"])

      if company_tuist_account_id not in organization_account_ids do
        :ok = Mautic.remove_company(id)
      end
    end)
  end

  defp sync_memberships(mautic_contacts, mautic_companies) do
    get_organization_memberships()
    |> Enum.group_by(& &1.organization_id)
    |> Enum.flat_map(fn {_org_id, memberships} ->
      org_account_id = hd(memberships).organization_account_id

      case find_company_by_account_id(mautic_companies, org_account_id) do
        nil -> []
        company -> Enum.map(memberships, &{&1, company["id"]})
      end
    end)
    |> Enum.each(fn {membership, company_id} ->
      case find_contact_by_user_id(mautic_contacts, membership.user_id) do
        nil -> :ok
        contact -> Mautic.add_contact_to_company(contact["id"], company_id)
      end
    end)
  end

  defp get_organization_memberships do
    organizations = organizations()

    Enum.flat_map(organizations, fn organization ->
      members = Accounts.get_organization_members_with_role(organization)

      Enum.map(members, fn [user, role_name] ->
        %{
          user_id: user.id,
          user_email: user.email,
          organization_id: organization.id,
          organization_account_id: organization.account.id,
          role: role_name
        }
      end)
    end)
  end

  defp find_contact_by_user_id(mautic_contacts, user_id) do
    mautic_contacts
    |> Enum.find(fn {_, contact} ->
      tuist_user_id =
        get_in(contact, ["fields", "tuist_user_id"]) ||
          get_in(contact, ["fields", "all", "tuist_user_id"])

      tuist_user_id == Integer.to_string(user_id)
    end)
    |> case do
      {_, contact} -> contact
      nil -> nil
    end
  end

  defp find_company_by_account_id(mautic_companies, account_id) do
    mautic_companies
    |> Enum.find(fn {_, company} ->
      tuist_account_id =
        get_in(company, ["fields", "tuist_account_id"]) ||
          get_in(company, ["fields", "all", "tuist_account_id"])

      tuist_account_id == Integer.to_string(account_id)
    end)
    |> case do
      {_, company} -> company
      nil -> nil
    end
  end

  defp get_current_active_subscription(%{subscriptions: subscriptions}) do
    Enum.find(subscriptions, fn subscription ->
      subscription.status == "active" or subscription.status == "trialing"
    end)
  end

  defp get_current_active_subscription(_account), do: nil

  def build_organization_data(%{account: account} = organization) do
    subscription = get_current_active_subscription(account)
    subscription_type = if subscription, do: to_string(subscription.plan), else: "air"

    %{
      "companyname" => account.name || account.email,
      "companyemail" => account.billing_email || account.email,
      "custom_fields" => %{
        "tuist_account_id" => Integer.to_string(account.id),
        "tuist_organization_id" => Integer.to_string(organization.id),
        "tuist_billing_email" => account.billing_email,
        "tuist_current_month_cache_hits" => account.current_month_remote_cache_hits_count || 0,
        "tuist_subscription_type" => subscription_type,
        "tuist_has_active_subscription" => not is_nil(subscription),
        "tuist_customer_id" => account.customer_id
      }
    }
  end
end
