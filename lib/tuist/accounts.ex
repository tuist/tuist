defmodule Tuist.Accounts do
  @moduledoc ~S"""
  A module that provides functions to interact with the accounts in the system.
  """
  alias Tuist.Accounts
  alias Ecto.Changeset
  alias Tuist.Projects.Project
  alias Tuist.CommandEvents.Event
  alias Tuist.Environment
  alias Tuist.Accounts.UserNotifier
  alias Tuist.Repo

  alias Tuist.Accounts.{
    User,
    Account,
    Organization,
    Role,
    UserRole,
    Oauth2Identity,
    DeviceCode,
    Invitation
  }

  alias Tuist.Billing
  import Ecto.Query, only: [from: 2]

  def update_account_cache_upload_event_count(%Account{} = account, count) do
    {:ok, _} = Repo.update(account |> Ecto.Changeset.change(cache_upload_event_count: count))
    Repo.reload(account)
  end

  @doc """
  Given an id, it returns the account associated with it.
  """
  def get_account_by_id(id) do
    Repo.get(Account, id)
  end

  def get_account_by_handle(handle) do
    Repo.one(from a in Account, where: a.name == ^handle)
  end

  @doc ~S"""
  Given an id, it returns the organization associated with it.
  """
  def get_organization_by_id(id, attrs \\ []) do
    preloads = attrs |> Keyword.get(:preloads, [])

    Repo.get(Organization, id) |> Repo.preload(preloads)
  end

  def get_organization_account_by_name(name) do
    query =
      from a in Account,
        join: o in Organization,
        on: a.organization_id == o.id,
        where: a.name == ^name,
        select: %{
          organization: o,
          account: a
        }

    Repo.one(query)
  end

  def get_organization_members(%Organization{id: organization_id}, role) do
    query =
      from(user_role in UserRole,
        join: r in Role,
        on: r.resource_type == "Organization" and r.resource_id == ^organization_id,
        join: u in User,
        on: user_role.user_id == u.id,
        on: user_role.role_id == r.id,
        where: r.name == ^Atom.to_string(role) and r.resource_type == "Organization",
        select: u
      )

    invited_members = Repo.all(query)

    case role do
      :admin ->
        invited_members
        |> Repo.preload(:account)

      :user ->
        invited_members_ids = Enum.map(invited_members, & &1.id)

        oauth2_identity_query =
          from(u in User,
            join: oauth in Oauth2Identity,
            on: oauth.user_id == u.id,
            join: org in Organization,
            on:
              org.id == ^organization_id and
                oauth.provider_organization_id == org.sso_organization_id and
                oauth.provider == org.sso_provider,
            where: org.id == ^organization_id and u.id not in ^invited_members_ids
          )

        (invited_members ++ Repo.all(oauth2_identity_query))
        |> Repo.preload(:account)
    end
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
    Repo.one(from u in User, where: u.email == ^email)
  end

  def get_user_by_id(id) do
    Repo.get(User, id)
  end

  def get_oauth2_identity_by_provider_and_id(provider, id_in_provider) do
    Repo.get_by(Oauth2Identity, provider: provider, id_in_provider: id_in_provider |> to_string())
  end

  def update_organization(%Organization{} = organization, attrs) do
    organization
    |> Organization.update_changeset(attrs)
    |> Repo.update()
  end

  @doc ~S"""
  Creates an organization with the given attributes.
  """
  def create_organization(
        %{name: name, creator: %User{id: user_id, email: user_email}},
        opts \\ []
      ) do
    sso_provider = opts |> Keyword.get(:sso_provider)
    sso_organization_id = opts |> Keyword.get(:sso_organization_id)
    created_at = opts |> Keyword.get(:created_at, DateTime.utc_now())
    setup_billing = opts |> Keyword.get(:setup_billing, not Tuist.Environment.on_premise?())

    current_month_remote_cache_hits_count =
      opts |> Keyword.get(:current_month_remote_cache_hits_count, 0)

    {:ok, %{organization: organization}} =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(
        :organization,
        Organization.create_changeset(%Organization{}, %{
          sso_provider: sso_provider,
          sso_organization_id: sso_organization_id,
          created_at: created_at
        })
      )
      |> Ecto.Multi.run(:account, fn repo, %{organization: %{id: organization_id}} ->
        repo.insert(
          Account.create_changeset(%Account{}, %{
            organization_id: organization_id,
            name: name,
            current_month_remote_cache_hits_count: current_month_remote_cache_hits_count,
            customer_id:
              Keyword.get(
                opts,
                :customer_id,
                if(setup_billing,
                  do: Billing.create_customer(%{name: name, email: user_email}),
                  else: nil
                )
              )
          })
        )
      end)
      |> Ecto.Multi.run(:role, fn repo, %{organization: %{id: organization_id}} ->
        repo.insert(
          Role.create_changeset(
            %Role{},
            %{
              name: "admin",
              resource_type: "Organization",
              resource_id: organization_id
            }
          )
        )
      end)
      |> Ecto.Multi.run(:user_role, fn repo, %{role: role} ->
        repo.insert(
          UserRole.create_changeset(%UserRole{}, %{
            user_id: user_id,
            role_id: role.id
          })
        )
      end)
      |> Repo.transaction()

    if setup_billing do
      account = Accounts.get_account_from_organization(organization)
      Billing.start_trial(%{plan: :air, account: account})
    end

    organization
  end

  def delete_user(%User{} = user) do
    account = get_account_from_user(user)

    {:ok, _} =
      Ecto.Multi.new()
      |> Ecto.Multi.delete_all(
        :delete_command_events,
        from(
          c in Event,
          join: p in Project,
          on: c.project_id == p.id,
          where: p.account_id == ^account.id
        )
      )
      |> Ecto.Multi.delete(:delete_account, account)
      |> Ecto.Multi.delete(:delete_user, user)
      |> Repo.transaction()
  end

  def delete_organization(%Organization{} = organization) do
    Repo.delete!(organization)
  end

  def find_or_create_user_from_oauth2(
        %{
          provider: provider,
          uid: id_in_provider,
          info: %{email: email}
        } = auth,
        opts \\ []
      ) do
    oauth2_identity = get_oauth2_identity_by_provider_and_id(provider, id_in_provider)

    provider_organization_id =
      case provider do
        # Google hosted domain. See more at https://developers.google.com/identity/openid-connect/openid-connect#an-id-tokens-payload
        :google -> auth.extra.raw_info.user["hd"]
        :github -> nil
        :okta -> nil
      end

    if oauth2_identity do
      if oauth2_identity.provider_organization_id != provider_organization_id do
        oauth2_identity
        |> Ecto.Changeset.change(provider_organization_id: provider_organization_id)
        |> Repo.update!()
      end

      get_user_by_id(oauth2_identity.user_id) |> Repo.preload(Keyword.get(opts, :preload, []))
    else
      oauth2_identity =
        create_oauth2_identity(%{
          provider: provider,
          id_in_provider: id_in_provider,
          email: email,
          provider_organization_id: provider_organization_id
        })

      get_user_by_id(oauth2_identity.user_id) |> Repo.preload(Keyword.get(opts, :preload, []))
    end
  end

  def find_oauth2_identity(%{user: %{id: user_id}, provider: provider}, opts \\ []) do
    provider_organization_id = opts |> Keyword.get(:provider_organization_id)

    if is_nil(provider_organization_id) do
      Repo.get_by(Oauth2Identity, user_id: user_id, provider: provider)
    else
      Repo.get_by(Oauth2Identity,
        user_id: user_id,
        provider: provider,
        provider_organization_id: provider_organization_id
      )
    end
  end

  @doc """
  Creates a user with the given attributes and its associated account.
  """
  def create_user(email, opts \\ []) do
    token = Tuist.Tokens.generate_token()
    password = opts |> Keyword.get(:password, "")
    confirmed_at = opts |> Keyword.get(:confirmed_at, nil)
    oauth2_identity = opts |> Keyword.get(:oauth2_identity, nil)
    suffix = opts |> Keyword.get(:suffix, "")
    created_at = opts |> Keyword.get(:created_at, DateTime.utc_now())
    setup_billing = opts |> Keyword.get(:setup_billing, not Tuist.Environment.on_premise?())

    current_month_remote_cache_hits_count =
      opts |> Keyword.get(:current_month_remote_cache_hits_count, 0)

    name =
      (email
       |> String.split("@")
       |> List.first()
       |> String.replace(".", "-")
       |> String.downcase()) <> suffix

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(
        :user,
        User.create_user_changeset(%User{}, %{
          email: email,
          token: token,
          password: password,
          confirmed_at: confirmed_at,
          created_at: created_at
        })
      )
      |> Ecto.Multi.run(:account, fn repo, %{user: %{id: user_id, email: email}} ->
        customer_id =
          Keyword.get(
            opts,
            :customer_id,
            if(setup_billing,
              do: Billing.create_customer(%{name: name, email: email}),
              else: nil
            )
          )

        repo.insert(
          Account.create_changeset(%Account{}, %{
            user_id: user_id,
            name: name,
            current_month_remote_cache_hits_count: current_month_remote_cache_hits_count,
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
              provider_organization_id: oauth2_identity.provider_organization_id,
              user_id: user_id
            })
          )
        end)
        |> Repo.transaction()
      end

    case user_account do
      {:ok, %{user: user}} ->
        if setup_billing do
          account = Accounts.get_account_from_user(user)
          Billing.start_trial(%{plan: :air, account: account})
        end

        Tuist.Analytics.user_create(user)

        {:ok, user}

      {:error, :account, %Changeset{} = changeset, _} ->
        parse_account_changeset_error(changeset, email, opts)

      {:error, :user, %Changeset{} = changeset, _} ->
        if Tuist.Ecto.Utils.unique_error?(changeset, :email) do
          {:error, :email_taken}
        else
          {:error, changeset}
        end
    end
  end

  defp parse_account_changeset_error(%Changeset{} = changeset, email, opts) do
    attempt = opts |> Keyword.get(:attempt, 0)
    suffix = opts |> Keyword.get(:suffix, "")

    cond do
      Tuist.Ecto.Utils.unique_error?(changeset, :name) and attempt < 5 ->
        next_suffix = if suffix == "", do: 1, else: (suffix |> String.to_integer()) + 1

        opts =
          opts
          |> Keyword.put(:attempt, attempt + 1)
          |> Keyword.put(:suffix, "#{next_suffix}")

        create_user(email, opts)

      Tuist.Ecto.Utils.unique_error?(changeset, :name) and attempt >= 5 ->
        {:error, :account_handle_taken}

      true ->
        {:error, Tuist.Ecto.Utils.errors_on(changeset)}
    end
  end

  def get_customer_ids_with_remote_cache_hits_stream() do
    now = Tuist.Time.utc_now()
    start_of_yesterday = now |> Timex.shift(days: -1) |> Timex.beginning_of_day()
    end_of_yesterday = now |> Timex.shift(days: -1) |> Timex.end_of_day()

    query =
      from e in Event,
        join: p in Project,
        on: e.project_id == p.id,
        join: a in Account,
        on: p.account_id == a.id,
        where: e.created_at >= ^start_of_yesterday and e.created_at <= ^end_of_yesterday,
        group_by: a.customer_id,
        select:
          {a.customer_id,
           count(
             fragment(
               "CASE WHEN COALESCE(array_length(?, 1), 0) > 0 OR COALESCE(array_length(?, 1), 0) > 0 THEN 1 ELSE NULL END",
               e.remote_cache_target_hits,
               e.remote_test_target_hits
             )
           )}

    query |> Repo.stream()
  end

  defp create_oauth2_identity(%{
         provider: provider,
         id_in_provider: id_in_provider,
         email: email,
         provider_organization_id: provider_organization_id
       }) do
    user = get_user_by_email(email)

    if user do
      {:ok, oauth2_identity} =
        Repo.insert(
          Oauth2Identity.create_changeset(%Oauth2Identity{}, %{
            provider: provider,
            id_in_provider: id_in_provider |> to_string(),
            user_id: user.id,
            provider_organization_id: provider_organization_id
          })
        )

      oauth2_identity
    else
      {:ok, user} =
        create_user(email,
          password: generate_random_string(16),
          oauth2_identity: %{
            provider: provider,
            id_in_provider: id_in_provider |> to_string(),
            provider_organization_id: provider_organization_id
          }
        )

      find_oauth2_identity(%{user: user, provider: provider})
    end
  end

  def organization_from_account(%Account{} = account) do
    if is_nil(account.organization_id) do
      nil
    else
      account.organization_id |> get_organization_by_id()
    end
  end

  def get_account_from_customer_id(customer_id) do
    query =
      from a in Account,
        where: a.customer_id == ^customer_id

    query |> Repo.one()
  end

  def get_account_from_user(%User{} = user) do
    query =
      from(a in Account,
        where: a.user_id == ^user.id
      )

    query |> Repo.one()
  end

  def get_account_from_organization(%Organization{} = organization) do
    query =
      from(a in Account,
        where: a.organization_id == ^organization.id
      )

    query |> Repo.one()
  end

  def owns_account_or_belongs_to_account_organization?(user, %{id: account_id}) do
    with {:account, %Account{} = account} <- {:account, account_id |> get_account_by_id()},
         {:organization, organization} <- {:organization, organization_from_account(account)} do
      belongs_to_account_organization =
        if organization != nil do
          organization_admin?(user, organization) or organization_user?(user, organization)
        else
          false
        end

      owns_account?(user, account) or belongs_to_account_organization
    else
      {:account, nil} -> false
    end
  end

  def owns_account_or_is_admin_to_account_organization?(user, %{id: account_id}) do
    with {:account, %Account{} = account} <- {:account, account_id |> get_account_by_id()},
         {:organization, organization} <- {:organization, organization_from_account(account)} do
      is_admin_to_account_organization =
        if organization != nil do
          organization_admin?(user, organization)
        else
          false
        end

      owns_account?(user, account) or is_admin_to_account_organization
    else
      {:account, nil} -> false
    end
  end

  defp owns_account?(user, account) do
    account.user_id == user.id
  end

  def add_user_to_organization(
        %User{id: user_id},
        %Organization{id: organization_id},
        opts \\ []
      ) do
    role = opts |> Keyword.get(:role, :user)

    query =
      from(u in UserRole,
        join: r in Role,
        on: u.role_id == r.id,
        where:
          u.user_id == ^user_id and r.name == ^~s(role) and r.resource_type == "Organization" and
            r.resource_id == ^organization_id
      )

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

  def remove_user_from_organization(
        %User{id: user_id} = user,
        %Organization{id: organization_id} = organization
      ) do
    query =
      from(u in UserRole,
        join: r in Role,
        on: u.role_id == r.id,
        where:
          u.user_id == ^user_id and r.resource_type == "Organization" and
            r.resource_id == ^organization_id,
        select: %{user_role: u, role: r}
      )

    result = Repo.one(query)

    cond do
      belongs_to_sso_organization?(user, organization) ->
        delete_user(user)
        :ok

      is_nil(result) ->
        :ok

      !is_nil(result) ->
        {:ok, _} =
          Ecto.Multi.new()
          |> Ecto.Multi.delete(:user_role, result.user_role)
          |> Ecto.Multi.delete(:role, result.role)
          |> Repo.transaction()

        :ok
    end
  end

  def get_user_role_in_organization(%User{id: user_id}, %Organization{id: organization_id}) do
    query =
      from(u in UserRole,
        join: r in Role,
        on: u.role_id == r.id,
        where:
          u.user_id == ^user_id and r.resource_type == "Organization" and
            r.resource_id == ^organization_id,
        select: r
      )

    Repo.one(query)
  end

  def update_user_role_in_organization(
        %User{id: user_id},
        %Organization{id: organization_id},
        role
      ) do
    query =
      from(u in UserRole,
        join: r in Role,
        on: u.role_id == r.id,
        where:
          u.user_id == ^user_id and r.resource_type == "Organization" and
            r.resource_id == ^organization_id,
        select: r
      )

    user_role = Repo.one(query)

    {:ok, updated_role} =
      Repo.update(user_role |> Ecto.Changeset.change(name: Atom.to_string(role)))

    updated_role
  end

  def get_user_organization_accounts(%User{id: user_id}) do
    query =
      from(u in UserRole,
        join: r in Role,
        on: u.role_id == r.id,
        join: o in Organization,
        on: o.id == r.resource_id,
        join: a in Account,
        on: a.organization_id == o.id,
        where: u.user_id == ^user_id and r.resource_type == "Organization",
        select: %{
          organization: o,
          account: a
        }
      )

    oauth_query =
      from(oauth in Oauth2Identity,
        join: u in User,
        on: oauth.user_id == u.id,
        join: org in Organization,
        on:
          oauth.provider_organization_id == org.sso_organization_id and
            org.sso_provider == oauth.provider,
        join: a in Account,
        on: a.organization_id == org.id,
        where: oauth.user_id == ^user_id,
        select: %{organization: org, account: a}
      )

    Repo.all(query) ++ Repo.all(oauth_query)
  end

  def invite_user_to_organization(
        email,
        %{
          inviter: %User{id: user_id} = inviter,
          to: %Organization{id: organization_id} = organization,
          url: url_fun
        },
        opts \\ []
      )
      when is_function(url_fun, 1) do
    account = get_account_from_organization(organization)
    token = Keyword.get(opts, :token, Tuist.Tokens.generate_token(16))

    {:ok, invitation} =
      Invitation.create_changeset(%Invitation{}, %{
        token: token,
        invitee_email: email,
        inviter_id: user_id,
        organization_id: organization_id
      })
      |> Repo.insert()

    if Environment.mail_configured?() do
      UserNotifier.deliver_invitation(email, %{
        inviter: inviter,
        to: %{organization: organization, account: account},
        url: url_fun.(token)
      })
    end

    invitation
  end

  def accept_invitation(%{
        invitation: %Invitation{} = invitation,
        invitee: %User{} = invitee,
        organization: %Organization{} = organization
      }) do
    add_user_to_organization(invitee, organization)
    Repo.delete(invitation)
  end

  def get_invitation_by_token(token, %User{} = invitee) do
    invitation = Repo.get_by(Invitation, token: token)

    cond do
      is_nil(invitation) ->
        {:error, :not_found}

      invitation.invitee_email != invitee.email ->
        {:error, :forbidden}

      !is_nil(invitation) ->
        {:ok, invitation}
    end
  end

  def belongs_to_organization?(%User{} = user, %Organization{} = organization) do
    organization_user?(user, organization) or organization_admin?(user, organization)
  end

  def belongs_to_sso_organization?(%User{} = user, %Organization{} = organization) do
    oauth2_identity_query =
      from(oauth in Oauth2Identity,
        join: u in User,
        on: oauth.user_id == u.id,
        join: org in Organization,
        on:
          oauth.provider_organization_id == org.sso_organization_id and
            oauth.provider == org.sso_provider,
        where: oauth.user_id == ^user.id and org.id == ^organization.id
      )

    Repo.exists?(oauth2_identity_query)
  end

  def organization_admin?(%User{id: user_id}, %Organization{} = %{id: organization_id}) do
    query =
      from(u in UserRole,
        join: r in Role,
        on: u.role_id == r.id,
        where:
          u.user_id == ^user_id and r.name == "admin" and r.resource_type == "Organization" and
            r.resource_id == ^organization_id
      )

    query |> Repo.exists?()
  end

  def organization_user?(
        %User{id: user_id} = user,
        %Organization{id: organization_id} = organization
      ) do
    query =
      from(u in UserRole,
        join: r in Role,
        on: u.role_id == r.id,
        where:
          u.user_id == ^user_id and r.name == "user" and r.resource_type == "Organization" and
            r.resource_id == ^organization_id
      )

    Repo.exists?(query) or belongs_to_sso_organization?(user, organization)
  end

  def get_invitation_by_id(id) do
    Repo.get(Invitation, id)
  end

  def get_invitation_by_invitee_email_and_organization(invitee_email, %Organization{
        id: organization_id
      }) do
    Repo.one(
      from i in Invitation,
        where: i.invitee_email == ^invitee_email,
        where: i.organization_id == ^organization_id
    )
  end

  def cancel_invitation(%Invitation{} = invitation) do
    {:ok, _} = Repo.delete(invitation)
    :ok
  end

  def get_role_by_id(id) do
    Repo.get(Role, id)
  end

  def update_last_visited_project(%User{} = user, last_visited_project_id) do
    {:ok, user} =
      Repo.update(user |> Ecto.Changeset.change(last_visited_project_id: last_visited_project_id))

    user
  end

  alias Tuist.Accounts.{User, UserToken, UserNotifier}

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
    user =
      Repo.one(from u in User, where: u.email == ^email)

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
  def get_user_by_session_token(token, opts \\ []) do
    preloads = opts |> Keyword.get(:preloads, [])
    {:ok, query} = UserToken.verify_session_token_query(token)

    Repo.one(query)
    |> Repo.preload(preloads)
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

      iex> deliver_user_confirmation_instructions(user, &url(~p"/users/confirm/#{&1}"))
      {:ok, %{to: ..., body: ...}}

      iex> deliver_user_confirmation_instructions(confirmed_user, &url(~p"/users/confirm/#{&1}"))
      {:error, :already_confirmed}

  """
  def deliver_user_confirmation_instructions(%{
        user: user,
        confirmation_url: confirmation_url,
        icon_url: icon_url
      })
      when is_function(confirmation_url, 1) do
    if user.confirmed_at do
      {:error, :already_confirmed}
    else
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)

      UserNotifier.deliver_confirmation_instructions(%{
        user: user,
        confirmation_url: confirmation_url.(encoded_token),
        icon_url: icon_url
      })
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

      iex> deliver_user_reset_password_instructions(user, &url(~p"/users/reset_password/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_reset_password_instructions(%{
        user: %User{} = user,
        reset_password_url: reset_password_url,
        icon_url: icon_url
      })
      when is_function(reset_password_url, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(user_token)

    UserNotifier.deliver_reset_password_instructions(%{
      user: user,
      reset_password_url: reset_password_url.(encoded_token),
      icon_url: icon_url
    })
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
