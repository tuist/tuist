defmodule TuistCloud.Accounts do
  @moduledoc ~S"""
  A module that provides functions to interact with the accounts in the system.
  """
  alias TuistCloud.Repo

  alias TuistCloud.Accounts.{
    User,
    Account,
    Organization,
    Role,
    OrganizationAccount,
    UserRole,
    Oauth2Identity,
    DeviceCode
  }

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

  def get_device_code(code) do
    Repo.get_by(DeviceCode, code: code)
  end

  def authenticate_device_code(code, %User{} = user) do
    device_code = get_device_code(code)

    {:ok, device_code} =
      DeviceCode.authenticate_changeset(device_code, %{authenticated: true, user_id: user.id})
      |> Repo.update()

    device_code
  end

  def create_device_code(code, attrs \\ []) do
    created_at = attrs |> Keyword.get(:created_at, DateTime.utc_now())

    {:ok, device_code} =
      Repo.insert(
        DeviceCode.create_changeset(%DeviceCode{}, %{code: code, created_at: created_at})
      )

    device_code
  end

  @doc """
  Given an email address, it returns the user associated with it.

  # Parameters
    - `email` - The email address of the user.
  """
  def get_user_by_email(email) do
    Repo.get_by(User, email: email)
  end

  def get_user_by_id(id) do
    Repo.get(User, id)
  end

  def get_oauth2_identity_by_provider_and_id(provider, id_in_provider) do
    Repo.get_by(Oauth2Identity, provider: provider, id_in_provider: id_in_provider |> to_string())
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

  def find_or_create_user_from_oauth2(%{
        provider: provider,
        uid: id_in_provider,
        info: %{email: email}
      }) do
    oauth2_identity = get_oauth2_identity_by_provider_and_id(provider, id_in_provider)

    if oauth2_identity do
      get_user_by_id(oauth2_identity.user_id)
    else
      oauth2_identity =
        create_oauth2_identity(
          provider: provider,
          id_in_provider: id_in_provider,
          email: email
        )

      get_user_by_id(oauth2_identity.user_id)
    end
  end

  def find_oauth2_identity_by_user_id(user_id) do
    Repo.get_by(Oauth2Identity, user_id: user_id)
  end

  @doc """
  Creates a user with the given attributes and its associated account.
  """
  def create_user(email, opts \\ []) do
    token = TuistCloud.Tokens.generate_authentication_token()
    password = opts |> Keyword.get(:password, "")
    confirmed_at = opts |> Keyword.get(:confirmed_at, nil)
    oauth2_identity = opts |> Keyword.get(:oauth2_identity, nil)

    name = email |> String.split("@") |> List.first()

    multi =
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

    user_account =
      if is_nil(oauth2_identity) do
        Repo.transaction(multi)
      else
        multi
        |> Ecto.Multi.run(:oauth2_identity, fn repo, %{user: %{id: user_id}} ->
          repo.insert(
            Oauth2Identity.create_changeset(%Oauth2Identity{}, %{
              provider: oauth2_identity.provider,
              id_in_provider: oauth2_identity.id_in_provider |> to_string(),
              user_id: user_id
            })
          )
        end)
        |> Repo.transaction()
      end

    {:ok, %{user: user}} = user_account
    user
  end

  def create_oauth2_identity(opts) do
    provider = opts |> Keyword.get(:provider)
    id_in_provider = opts |> Keyword.get(:id_in_provider)
    email = opts |> Keyword.get(:email)

    user = get_user_by_email(email)

    if user do
      {:ok, oauth2_identity} =
        Repo.insert(
          Oauth2Identity.create_changeset(%Oauth2Identity{}, %{
            provider: provider,
            id_in_provider: id_in_provider |> to_string(),
            user_id: user.id
          })
        )

      oauth2_identity
    else
      user =
        create_user(email,
          password: generate_random_string(16),
          oauth2_identity: %{
            provider: provider,
            id_in_provider: id_in_provider |> to_string()
          }
        )

      find_oauth2_identity_by_user_id(user.id)
    end
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
    if Billing.enabled?() do
      Billing.create_customer(name: name, email: email)
    else
      nil
    end
  end

  def update_last_visited_project(%User{} = user, last_visited_project_id) do
    {:ok, _} =
      Repo.update(user |> Ecto.Changeset.change(last_visited_project_id: last_visited_project_id))

    Repo.reload(user)
  end

  alias TuistCloud.Accounts.{User, UserToken, UserNotifier}

  ## Database getters

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)

    if User.valid_password?(user, password) do
      if is_nil(user.confirmed_at) do
        {:error, :not_confirmed}
      else
        {:ok, user}
      end
    else
      {:error, :invalid_email_or_password}
    end
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## Settings

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}) do
    User.password_changeset(user, attrs)
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end

  ## Confirmation

  @doc ~S"""
  Delivers the confirmation email instructions to the given user.

  ## Examples

      iex> deliver_user_confirmation_instructions(user, &url(~p"/v2/users/confirm/#{&1}"))
      {:ok, %{to: ..., body: ...}}

      iex> deliver_user_confirmation_instructions(confirmed_user, &url(~p"/v2/users/confirm/#{&1}"))
      {:error, :already_confirmed}

  """
  def deliver_user_confirmation_instructions(user, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    if user.confirmed_at do
      {:error, :already_confirmed}
    else
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)
      UserNotifier.deliver_confirmation_instructions(user, confirmation_url_fun.(encoded_token))
    end
  end

  @doc """
  Confirms a user by the given token.

  If the token matches, the user account is marked as confirmed
  and the token is deleted.
  """
  def confirm_user(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
         %User{} = user <- Repo.one(query),
         {:ok, %{user: user}} <- Repo.transaction(confirm_user_multi(user)) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  defp confirm_user_multi(user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.confirm_changeset(user))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, ["confirm"]))
  end

  ## Reset password

  @doc ~S"""
  Delivers the reset password email to the given user.

  ## Examples

      iex> deliver_user_reset_password_instructions(user, &url(~p"/v2/users/reset_password/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(user_token)
    UserNotifier.deliver_reset_password_instructions(user, reset_password_url_fun.(encoded_token))
  end

  @doc """
  Gets the user by reset password token.

  ## Examples

      iex> get_user_by_reset_password_token("validtoken")
      %User{}

      iex> get_user_by_reset_password_token("invalidtoken")
      nil

  """
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Resets the user password.

  ## Examples

      iex> reset_user_password(user, %{password: "new long password", password_confirmation: "new long password"})
      {:ok, %User{}}

      iex> reset_user_password(user, %{password: "valid", password_confirmation: "not the same"})
      {:error, %Ecto.Changeset{}}

  """
  def reset_user_password(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.password_changeset(user, attrs))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  defp generate_random_string(length) do
    length
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
    |> binary_part(0, length)
  end
end
