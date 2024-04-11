defmodule TuistCloud.Accounts do
  @moduledoc ~S"""
  A module that provides functions to interact with the accounts in the system.
  """
  alias TuistCloud.Accounts.UserRole
  alias TuistCloud.Repo
  alias TuistCloud.Accounts.{User, Account, Organization, Role, OrganizationAccount}
  alias TuistCloud.Billing
  import Ecto.Query, only: [from: 2]

  def update_account_cache_upload_event_count(%Account{} = account, count) do
    {:ok, _} = Repo.update(account |> Ecto.Changeset.change(cache_upload_event_count: count))
    Repo.reload(account)
  end

  def upgrade_to_enterprise(%Account{} = account) do
    {:ok, _} = Repo.update(account |> Ecto.Changeset.change(plan: :enterprise))
    Repo.reload(account)
  end

  @doc """
  Given an id, it returns the account associated with it.
  """
  def get_account_by_id(id) do
    Repo.get(Account, id)
  end

  def get_account_by_handle(handle) do
    Repo.get_by(Account, name: handle)
  end

  # This method should be deleted once we implement auth properly
  def get_tuist_user() do
    Repo.get_by(User, email: "tuist@tuist.io")
  end

  @doc ~S"""
  Given an id, it returns the organization associated with it.
  """
  def get_organization_by_id(id) do
    Repo.get(Organization, id)
  end

  @doc """
  Given a token, it returns the user associated with it.
  """
  def get_user_by_token(token) do
    Repo.get_by(User, token: token)
  end

  @doc """
  Given an email address, it returns the user associated with it.

  # Parameters
    - `email` - The email address of the user.
  """
  def get_user_by_email(email) do
    Repo.get_by(User, email: email)
  end

  @doc ~S"""
  Creates an organization with the given attributes.
  """
  def create_organization(%{name: name}) do
    {:ok, %{organization: organization}} =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(:organization, %Organization{})
      |> Ecto.Multi.run(:account, fn repo, %{organization: %{id: organization_id}} ->
        repo.insert(
          Account.create_changeset(%Account{}, %{
            owner_type: "Organization",
            owner_id: organization_id,
            name: name
          })
        )
      end)
      |> Repo.transaction()

    organization
  end

  @doc """
  Creates a user with the given attributes and its associated account.
  """
  def create_user(email, opts \\ []) do
    token = TuistCloud.Tokens.generate_authentication_token()
    password = opts |> Keyword.get(:password, "")
    confirmed_at = opts |> Keyword.get(:confirmed_at, nil)

    name = email |> String.split("@") |> List.first()

    {:ok, %{user: user}} =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(
        :user,
        User.create_user_changeset(%User{}, %{
          email: email,
          token: token,
          password: password,
          confirmed_at: confirmed_at
        })
      )
      |> Ecto.Multi.run(:account, fn repo, %{user: %{id: user_id, email: email}} ->
        customer_id = create_customer_when_billing_enabled(name, email)

        repo.insert(
          Account.create_changeset(%Account{}, %{
            owner_type: "User",
            owner_id: user_id,
            name: name,
            customer_id: customer_id
          })
        )
      end)
      |> Repo.transaction()

    user
  end

  def organization_from_account(%Account{} = account) do
    if account.owner_type == "Organization" do
      account.owner_id |> get_organization_by_id()
    else
      nil
    end
  end

  def get_account_from_user(%User{} = user) do
    query =
      from a in Account,
        where: a.owner_type == "User" and a.owner_id == ^user.id

    query |> Repo.one()
  end

  def get_account_from_organization(%Organization{} = organization) do
    query =
      from a in Account,
        where: a.owner_type == "Organization" and a.owner_id == ^organization.id

    query |> Repo.one()
  end

  def owns_account_or_belongs_to_account_organization?(user, %{id: account_id}) do
    with {:account, %Account{} = account} <- {:account, account_id |> get_account_by_id()},
         {:organization, organization} <- {:organization, organization_from_account(account)} do
      belongs_to_account_organization =
        if organization != nil do
          admin?(user, organization) or user?(user, organization)
        else
          false
        end

      owns_account?(user, account) or belongs_to_account_organization
    else
      {:account, nil} -> false
    end
  end

  def owns_account_or_is_admin_to_account_organization?(user, account) do
    organization = organization_from_account(account)

    is_admin_to_account_organization =
      if organization != nil do
        admin?(user, organization)
      else
        false
      end

    owns_account?(user, account) or is_admin_to_account_organization
  end

  defp owns_account?(user, account) do
    account.owner_type == "User" and account.owner_id == user.id
  end

  def add_user_to_organization(
        %User{id: user_id},
        %Organization{id: organization_id},
        role \\ :user
      ) do
    query =
      from u in UserRole,
        join: r in Role,
        on: u.role_id == r.id,
        where:
          u.user_id == ^user_id and r.name == ^~s(role) and r.resource_type == "Organization" and
            r.resource_id == ^organization_id

    if Repo.exists?(query) do
      :ok
    else
      {:ok, _} =
        Ecto.Multi.new()
        |> Ecto.Multi.insert(:role, %Role{
          name: Atom.to_string(role),
          resource_type: "Organization",
          resource_id: organization_id
        })
        |> Ecto.Multi.insert(:user_role, fn %{role: role} ->
          %UserRole{user_id: user_id, role_id: role.id}
        end)
        |> Repo.transaction()

      :ok
    end
  end

  def get_user_organization_accounts(%User{id: user_id}) do
    query =
      from u in UserRole,
        join: r in Role,
        on: u.role_id == r.id,
        join: o in Organization,
        on: o.id == r.resource_id,
        join: a in Account,
        on: a.owner_type == "Organization" and a.owner_id == o.id,
        where: u.user_id == ^user_id and r.resource_type == "Organization",
        select: {o, a}

    Repo.all(query)
    |> Enum.map(fn {organization, account} ->
      %OrganizationAccount{organization: organization, account: account}
    end)
  end

  def admin?(%User{id: user_id}, %Organization{} = %{id: organization_id}) do
    query =
      from u in UserRole,
        join: r in Role,
        on: u.role_id == r.id,
        where:
          u.user_id == ^user_id and r.name == "admin" and r.resource_type == "Organization" and
            r.resource_id == ^organization_id

    query |> Repo.exists?()
  end

  def user?(%User{id: user_id}, %Organization{id: organization_id}) do
    query =
      from u in UserRole,
        join: r in Role,
        on: u.role_id == r.id,
        where:
          u.user_id == ^user_id and r.name == "user" and r.resource_type == "Organization" and
            r.resource_id == ^organization_id

    query |> Repo.exists?()
  end

  def get_role_by_id(id) do
    Repo.get(Role, id)
  end

  defp create_customer_when_billing_enabled(name, email) do
    if Billing.enabled? do
      Billing.create_customer(name: name, email: email)
    else
      nil
    end
  end
end
