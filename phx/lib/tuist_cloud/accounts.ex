defmodule TuistCloud.Accounts do
  @moduledoc ~S"""
  A module that provides functions to interact with the accounts in the system.
  """
  alias TuistCloud.Accounts.UserRole
  alias TuistCloud.Repo
  alias TuistCloud.Accounts.{User, Account, Organization, Role}
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
        name = email |> String.split("@") |> List.first()

        repo.insert(
          Account.create_changeset(%Account{}, %{
            owner_type: "User",
            owner_id: user_id,
            name: name
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

  def account_from_organization(%Organization{} = organization) do
    query =
      from a in Account,
        where: a.owner_type == "Organization" and a.owner_id == ^organization.id

    query |> Repo.one()
  end

  def owns_account_or_belongs_to_account_organization?(user, %{id: account_id} = _account) do
    with {:account, %Account{} = account} <- {:account, account_id |> get_account_by_id()},
         {:organization, organization} <- {:organization, organization_from_account(account)} do
      is_user_account = account.owner_type == "User" and account.owner_id == user.id

      belongs_to_account_organization =
        if organization != nil do
          admin?(user, organization) or user?(user, organization)
        else
          false
        end

      is_user_account or belongs_to_account_organization
    else
      {:account, nil} -> false
    end
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
end
