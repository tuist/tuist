defmodule Tuist.Accounts do
  @moduledoc ~S"""
  A module that provides functions to interact with the accounts in the system.
  """
  import Ecto.Query, only: [from: 2]

  alias Ecto.Changeset
  alias Ecto.Multi
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.AccountCacheEndpoint
  alias Tuist.Accounts.AccountToken
  alias Tuist.Accounts.AccountTokenProject
  alias Tuist.Accounts.AgentAuthJTI
  alias Tuist.Accounts.AgentRegistration
  alias Tuist.Accounts.AgentRegistrationEvent
  alias Tuist.Accounts.DeviceCode
  alias Tuist.Accounts.Invitation
  alias Tuist.Accounts.Oauth2Identity
  alias Tuist.Accounts.Organization
  alias Tuist.Accounts.Role
  alias Tuist.Accounts.User
  alias Tuist.Accounts.UserNotifier
  alias Tuist.Accounts.UserRole
  alias Tuist.Accounts.UserToken
  alias Tuist.Base64
  alias Tuist.Billing
  alias Tuist.CacheEndpoints
  alias Tuist.CommandEvents
  alias Tuist.Ecto.Utils
  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.Kura
  alias Tuist.Namespace
  alias Tuist.Repo
  alias Tuist.Time

  require Logger

  @reset_password_delivery_cooldown_in_minutes 5
  @agent_registration_scopes ["mcp"]
  @agent_registration_claim_token_ttl_seconds 30 * 60
  @agent_registration_otp_ttl_seconds 10 * 60
  @agent_registration_access_token_ttl_seconds 24 * 60 * 60
  @agent_registration_max_otp_attempts 5

  def agent_registration_scopes, do: @agent_registration_scopes

  def new_organizations_in_last_hour do
    Repo.all(from(o in Organization, where: o.created_at > ago(1, "hour"), preload: [:account]))
  end

  def new_users_in_last_hour do
    Repo.all(from(u in User, where: u.created_at > ago(1, "hour"), preload: [:account]))
  end

  def create_customer_when_absent(%Account{} = account) do
    if is_nil(account.customer_id) do
      customer_id =
        Billing.create_customer(%{
          name: account.name,
          email: account.billing_email
        })

      account
      |> Account.update_customer_id_changeset(%{customer_id: customer_id})
      |> Repo.update!()
    else
      account
    end
  end

  def get_users_count do
    Repo.aggregate(User, :count, :id)
  end

  def get_organizations_count do
    Repo.aggregate(Organization, :count, :id)
  end

  @doc """
  Given an id, it returns the account associated with it.
  """
  def get_account_by_id(id, opts \\ []) do
    preload = Keyword.get(opts, :preload, [])

    case Repo.get(Account, id) do
      nil -> {:error, :not_found}
      account -> {:ok, Repo.preload(account, preload)}
    end
  end

  def get_account_by_handle(handle) do
    Repo.one(from(a in Account, where: ilike(a.name, ^handle)))
  end

  @doc ~S"""
  Given an id, it returns the organization associated with it.
  """
  def get_organization_by_id(id, attrs \\ []) do
    preload = Keyword.get(attrs, :preload, [:account])

    case Repo.one(from(o in Organization, where: o.id == ^id, preload: ^preload)) do
      nil -> {:error, :not_found}
      %Organization{} = organization -> {:ok, organization}
    end
  end

  def get_organization_by_handle(handle) do
    query =
      from(o in Organization,
        join: a in assoc(o, :account),
        where: a.name == ^handle,
        select: o,
        preload: [:account]
      )

    Repo.one(query)
  end

  def organization_by_sso_credentials(provider, provider_organization_id) do
    query =
      from(o in Organization,
        where: o.sso_provider == ^provider and o.sso_organization_id == ^provider_organization_id,
        preload: [:account]
      )

    Repo.one(query)
  end

  def get_organization_members(%Organization{id: organization_id}) do
    Repo.all(
      from(u in User,
        preload: [:account],
        join: ur in UserRole,
        on: ur.user_id == u.id,
        join: r in Role,
        on: ur.role_id == r.id,
        join: a in assoc(u, :account),
        where: r.resource_type == "Organization" and r.resource_id == ^organization_id,
        order_by: a.name
      )
    )
  end

  def get_organization_members_with_role(%Organization{id: organization_id}) do
    Repo.all(
      from(u in User,
        preload: [:account],
        join: ur in UserRole,
        on: ur.user_id == u.id,
        join: r in Role,
        on: ur.role_id == r.id,
        where: r.resource_type == "Organization" and r.resource_id == ^organization_id,
        distinct: u.id,
        select: [u, r.name]
      )
    )
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
        Repo.preload(invited_members, :account)

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

        Repo.preload(invited_members ++ Repo.all(oauth2_identity_query), :account)
    end
  end

  @doc """
  Given a token, it returns the user associated with it.
  """
  def get_user_by_token(token) do
    Repo.one(
      from(u in User,
        where: u.token == ^token,
        preload: [:account]
      )
    )
  end

  def get_device_code(code) do
    Repo.get_by(DeviceCode, code: code)
  end

  def authenticate_device_code(code, %User{} = user) do
    device_code = get_device_code(code)

    {:ok, device_code} =
      device_code
      |> DeviceCode.authenticate_changeset(%{authenticated: true, user_id: user.id})
      |> Repo.update()

    device_code
  end

  def create_device_code(code, attrs \\ []) do
    created_at = Keyword.get(attrs, :created_at, DateTime.utc_now())

    {:ok, device_code} =
      Repo.insert(DeviceCode.create_changeset(%DeviceCode{}, %{code: code, created_at: created_at}))

    device_code
  end

  @doc """
  Given an email address, it returns the user associated with it.

  # Parameters
    - `email` - The email address of the user.

  # Returns
    - `{:ok, user}` - If the user is found.
    - `{:error, :not_found}` - If the user is not found.
  """
  def get_user_by_email(email) do
    case Repo.one(from(u in User, where: u.email == ^email, preload: [:account])) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  def get_user_by_id(id) do
    Repo.one(from(u in User, where: u.id == ^id, preload: [:account]))
  end

  def list_users_with_accounts_by_ids(ids) when is_list(ids) do
    Repo.all(from(u in User, where: u.id in ^ids, preload: [:account]))
  end

  def get_oauth2_identity_by_provider_and_id(provider, id_in_provider) do
    Repo.get_by(Oauth2Identity, provider: provider, id_in_provider: to_string(id_in_provider))
  end

  def update_sso_configuration(organization_id, sso_provider, attrs) do
    case get_organization_by_id(organization_id) do
      {:ok, organization} ->
        sso_attrs =
          attrs
          |> Map.put(:sso_provider, sso_provider)
          |> maybe_rename_secret(
            :oauth2_client_secret,
            :oauth2_encrypted_client_secret
          )

        organization
        |> Organization.update_changeset(sso_attrs)
        |> Repo.update()

      {:error, :not_found} = error ->
        error
    end
  end

  defp maybe_rename_secret(attrs, secret_key, encrypted_secret_key) do
    case Map.pop(attrs, secret_key) do
      {nil, attrs} -> attrs
      {secret, attrs} -> Map.put(attrs, encrypted_secret_key, secret)
    end
  end

  def update_organization(%Organization{} = organization, attrs) do
    Multi.new()
    |> Multi.update(:organization, Organization.update_changeset(organization, attrs))
    |> Multi.run(:assign_sso_users, fn _repo, %{organization: updated_organization} ->
      if sso_newly_enabled?(
           organization.sso_provider,
           updated_organization.sso_provider,
           organization.sso_organization_id,
           updated_organization.sso_organization_id
         ) do
        count =
          assign_existing_sso_users_to_organization(
            updated_organization,
            updated_organization.sso_provider,
            updated_organization.sso_organization_id
          )

        {:ok, count}
      else
        {:ok, 0}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{organization: updated_organization}} -> {:ok, updated_organization}
      {:error, :organization, changeset, _changes} -> {:error, changeset}
      {:error, :assign_sso_users, reason, _changes} -> {:error, reason}
    end
  end

  @doc """
  Creates an organization with the given attributes.
  """
  def create_organization(attrs, opts \\ []) do
    attrs
    |> create_organization_multi(opts)
    |> Repo.transaction()
    |> case do
      {:ok, %{organization: organization}} ->
        organization = Repo.preload(organization, :account)

        {:ok, organization}

      {:error, part, changeset, _changes} when part in [:organization, :account] ->
        {:error, changeset}

      {:error, part, changeset, _changes} ->
        Logger.error("Unknown error caught: #{part}, #{inspect(changeset)}")
        {:error, :internal_server_error}
    end
  end

  defp create_organization_multi(%{name: name, creator: %User{id: user_id, email: user_email}}, opts) do
    sso_provider = Keyword.get(opts, :sso_provider)
    sso_organization_id = Keyword.get(opts, :sso_organization_id)
    oauth2_client_id = Keyword.get(opts, :oauth2_client_id)
    oauth2_client_secret = Keyword.get(opts, :oauth2_client_secret)
    oauth2_authorize_url = Keyword.get(opts, :oauth2_authorize_url)
    oauth2_token_url = Keyword.get(opts, :oauth2_token_url)
    oauth2_user_info_url = Keyword.get(opts, :oauth2_user_info_url)
    created_at = Keyword.get(opts, :created_at, DateTime.utc_now())

    current_month_remote_cache_hits_count =
      Keyword.get(opts, :current_month_remote_cache_hits_count, 0)

    Multi.new()
    |> Multi.insert(
      :organization,
      Organization.create_changeset(%Organization{}, %{
        sso_provider: sso_provider,
        sso_organization_id: sso_organization_id,
        oauth2_client_id: oauth2_client_id,
        oauth2_encrypted_client_secret: oauth2_client_secret,
        oauth2_authorize_url: oauth2_authorize_url,
        oauth2_token_url: oauth2_token_url,
        oauth2_user_info_url: oauth2_user_info_url,
        created_at: created_at
      })
    )
    |> Multi.run(:account, fn repo, %{organization: %{id: organization_id}} ->
      repo.insert(
        Account.create_changeset(%Account{}, %{
          organization_id: organization_id,
          name: name,
          current_month_remote_cache_hits_count: current_month_remote_cache_hits_count,
          billing_email: user_email,
          customer_id:
            Keyword.get(
              opts,
              :customer_id
            )
        })
      )
    end)
    |> Multi.run(:role, fn repo, %{organization: %{id: organization_id}} ->
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
    |> Multi.run(:user_role, fn repo, %{role: role} ->
      repo.insert(
        UserRole.create_changeset(%UserRole{}, %{
          user_id: user_id,
          role_id: role.id
        })
      )
    end)
  end

  def delete_user(%User{} = user) do
    account = get_account_from_user(user)

    {:ok, _} =
      Multi.new()
      |> Multi.run(:delete_command_events, fn _repo, _changes ->
        CommandEvents.delete_account_events(account.id)
        {:ok, :deleted}
      end)
      |> Multi.delete(:delete_account, account)
      |> Multi.delete(:delete_user, user)
      |> Repo.transaction()
  end

  def delete_organization!(%Organization{} = organization) do
    Repo.delete!(organization)
  end

  def find_or_create_user_from_oauth2(
        %{provider: provider, uid: id_in_provider, info: %{email: email}} = auth,
        opts \\ []
      ) do
    oauth2_identity = get_oauth2_identity_by_provider_and_id(provider, id_in_provider)

    provider_organization_id =
      case provider do
        # Google hosted domain. See more at https://developers.google.com/identity/openid-connect/openid-connect#an-id-tokens-payload
        :google ->
          auth.extra.raw_info.user["hd"]

        :github ->
          nil

        :apple ->
          nil

        provider when provider in [:okta, :oauth2] ->
          auth.extra.raw_info[:provider_organization_id] ||
            auth.extra.raw_info["provider_organization_id"]
      end

    if oauth2_identity do
      if oauth2_identity.provider_organization_id != provider_organization_id do
        oauth2_identity
        |> Changeset.change(provider_organization_id: provider_organization_id)
        |> Repo.update!()
      end

      oauth2_identity.user_id
      |> get_user_by_id()
      |> Repo.preload(Keyword.get(opts, :preload, [:account]))
    else
      oauth2_identity =
        create_oauth2_identity(%{
          provider: provider,
          id_in_provider: id_in_provider,
          email: email,
          provider_organization_id: provider_organization_id
        })

      user =
        oauth2_identity.user_id
        |> get_user_by_id()
        |> Repo.preload(Keyword.get(opts, :preload, [:account]))

      # Add SSO user to their organization with default :user role
      assign_sso_user_to_organization(user, provider, provider_organization_id)

      user
    end
  end

  @doc """
  Links an OAuth identity to an existing user.
  Used when a user signs in with OAuth using an email that already exists.
  """
  def link_oauth_identity_to_user(%User{id: user_id} = user, attrs) do
    case Repo.insert(
           Oauth2Identity.create_changeset(%Oauth2Identity{}, %{
             provider: attrs.provider,
             id_in_provider: to_string(attrs.id_in_provider),
             user_id: user_id,
             provider_organization_id: attrs[:provider_organization_id]
           })
         ) do
      {:ok, oauth_identity} ->
        assign_sso_user_to_organization(user, attrs.provider, attrs[:provider_organization_id])
        {:ok, oauth_identity}

      error ->
        error
    end
  end

  @doc """
  Gets an OAuth2 identity by provider and id, preloading the user and account.
  Used to determine if a user signing in via OAuth is new or existing.

  For per-issuer providers (`:okta`, `:oauth2`) the caller MUST pass the
  `provider_organization_id` that identifies the issuer. OIDC `sub` is only
  unique within a single issuer, so looking up without the issuer across these
  providers would allow cross-tenant account takeover — two different
  customer-configured IdPs can legally return the same `sub`. Passing `nil`
  for a per-issuer provider returns `{:error, :not_found}` on purpose, as a
  safer default: a buggy caller causes a loud login failure instead of a
  silent authentication as the wrong user.

  For global providers (`:github`, `:google`, `:apple`) the `sub` is globally
  unique and `provider_organization_id` is ignored.

  Returns `{:ok, identity}` if found, `{:error, :not_found}` otherwise.
  """
  def get_oauth2_identity(provider, id_in_provider, provider_organization_id \\ nil)

  def get_oauth2_identity(provider, _id_in_provider, provider_organization_id)
      when provider in [:okta, :oauth2] and (is_nil(provider_organization_id) or provider_organization_id == "") do
    {:error, :not_found}
  end

  def get_oauth2_identity(provider, id_in_provider, provider_organization_id) do
    query =
      from(o in Oauth2Identity,
        where: o.provider == ^provider and o.id_in_provider == ^to_string(id_in_provider),
        preload: [user: [:account]]
      )

    query =
      if provider in [:okta, :oauth2] do
        from o in query, where: o.provider_organization_id == ^provider_organization_id
      else
        query
      end

    case Repo.one(query) do
      nil -> {:error, :not_found}
      identity -> {:ok, identity}
    end
  end

  @doc """
  Extracts the provider organization ID from an OAuth auth struct.
  Used during OAuth sign-up to store the SSO organization info.
  """
  def extract_provider_organization_id(auth) do
    case auth.provider do
      :google ->
        auth.extra.raw_info.user["hd"]

      :github ->
        nil

      :apple ->
        nil

      provider when provider in [:okta, :oauth2] ->
        auth.extra.raw_info[:provider_organization_id] ||
          auth.extra.raw_info["provider_organization_id"]
    end
  end

  @doc """
  Creates a user from pending OAuth sign-up data with a specific username.
  Used after the user selects their username during OAuth sign-up flow.
  """
  def create_user_from_pending_oauth(oauth_data, username) do
    oauth2_attrs = %{
      provider: String.to_existing_atom(oauth_data["provider"]),
      id_in_provider: oauth_data["uid"],
      provider_organization_id: oauth_data["provider_organization_id"]
    }

    case create_user(oauth_data["email"],
           password: generate_random_string(16),
           handle: username,
           oauth2_identity: oauth2_attrs
         ) do
      {:ok, user} ->
        assign_sso_user_to_organization(
          user,
          String.to_existing_atom(oauth_data["provider"]),
          oauth_data["provider_organization_id"]
        )

        {:ok, user}

      error ->
        error
    end
  end

  def find_oauth2_identity(%{user: %{id: user_id}, provider: provider}, opts \\ []) do
    provider_organization_id = Keyword.get(opts, :provider_organization_id)

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

    suffix = Keyword.get(opts, :suffix, "")

    handle =
      Keyword.get(
        opts,
        :handle
      ) ||
        (email
         |> String.split("@")
         |> List.first()
         |> String.replace(".", "-")
         |> String.replace("_", "-")
         |> String.replace(~r/[^a-zA-Z0-9-]/, "")
         |> String.downcase()) <> suffix

    password = Keyword.get(opts, :password, "")
    confirmed_at = Keyword.get(opts, :confirmed_at, default_confirmed_at())
    oauth2_identity = Keyword.get(opts, :oauth2_identity, nil)
    created_at = Keyword.get(opts, :created_at, DateTime.utc_now())

    multi =
      Multi.new()
      |> Multi.insert(
        :user,
        User.create_user_changeset(%User{}, %{
          email: email,
          token: token,
          password: password,
          confirmed_at: confirmed_at,
          created_at: created_at
        })
      )
      |> Multi.run(:account, fn repo, %{user: %{id: user_id, email: email}} ->
        customer_id =
          Keyword.get(
            opts,
            :customer_id
          )

        repo.insert(
          Account.create_changeset(%Account{}, %{
            user_id: user_id,
            name: handle,
            current_month_remote_cache_hits_count: Keyword.get(opts, :current_month_remote_cache_hits_count, 0),
            current_month_remote_cache_hits_count_updated_at:
              Keyword.get(opts, :current_month_remote_cache_hits_count_updated_at),
            customer_id: customer_id,
            billing_email: email
          })
        )
      end)

    user_account =
      if is_nil(oauth2_identity) do
        Repo.transaction(multi)
      else
        multi
        |> Multi.run(:oauth2_identity, fn repo, %{user: %{id: user_id}} ->
          repo.insert(
            Oauth2Identity.create_changeset(%Oauth2Identity{}, %{
              provider: oauth2_identity.provider,
              id_in_provider: to_string(oauth2_identity.id_in_provider),
              provider_organization_id: oauth2_identity.provider_organization_id,
              user_id: user_id
            })
          )
        end)
        |> Repo.transaction()
      end

    case user_account do
      {:ok, %{user: user}} ->
        user = Repo.preload(user, :account)
        Tuist.Analytics.user_create(user)

        {:ok, user}

      {:error, :account, %Changeset{} = changeset, _} ->
        parse_account_changeset_error(changeset, email, opts)

      {:error, :user, %Changeset{} = changeset, _} ->
        if Utils.unique_error?(changeset, :email) do
          {:error, :email_taken}
        else
          {:error, changeset}
        end
    end
  end

  defp parse_account_changeset_error(%Changeset{} = changeset, email, opts) do
    attempt = Keyword.get(opts, :attempt, 0)
    suffix = Keyword.get(opts, :suffix, "")
    explicit_handle = Keyword.has_key?(opts, :handle)

    cond do
      # If an explicit handle was provided, don't retry - just return the error
      Utils.unique_error?(changeset, :name) and explicit_handle ->
        {:error, :account_handle_taken}

      Utils.unique_error?(changeset, :name) and attempt < 20 ->
        next_suffix = if suffix == "", do: 1, else: String.to_integer(suffix) + 1

        opts =
          opts
          |> Keyword.put(:attempt, attempt + 1)
          |> Keyword.put(:suffix, "#{next_suffix}")

        create_user(email, opts)

      Utils.unique_error?(changeset, :name) and attempt >= 20 ->
        {:error, :account_handle_taken}

      true ->
        {:error, Utils.errors_on(changeset)}
    end
  end

  def update_account_current_month_usage(account_id, %{remote_cache_hits_count: remote_cache_hits_count}, opts \\ []) do
    %Account{id: account_id}
    |> Account.billing_changeset(%{
      current_month_remote_cache_hits_count: remote_cache_hits_count,
      current_month_remote_cache_hits_count_updated_at: Keyword.get(opts, :updated_at, NaiveDateTime.utc_now())
    })
    |> Repo.update!()
  end

  def account_month_usage(account_id, date \\ DateTime.utc_now()) do
    CommandEvents.account_month_usage(account_id, date)
  end

  def list_accounts_with_usage_not_updated_today(attrs \\ %{}) do
    start_of_today = Timex.beginning_of_day(DateTime.utc_now())

    query =
      from(a in Account,
        where:
          is_nil(a.current_month_remote_cache_hits_count_updated_at) or
            a.current_month_remote_cache_hits_count_updated_at < ^start_of_today
      )

    Flop.validate_and_run!(query, attrs, for: Account)
  end

  @doc """
  Returns a paginated list of accounts. Accepts any Flop params (`page`,
  `page_size`, `filters`, `order_by`, ...). Use the `:search` custom filter
  for a handle substring match — see `Account.search_filter/3`. Callers are
  expected to preload associations they need.
  """
  def list_accounts(attrs \\ %{}) do
    base_query = from(a in Account, order_by: [asc: a.name])
    Flop.validate_and_run!(base_query, attrs, for: Account)
  end

  def list_billable_customers do
    Repo.all(
      from(a in Account,
        where: not is_nil(a.customer_id),
        select: a.customer_id
      )
    )
  end

  defp create_oauth2_identity(%{
         provider: provider,
         id_in_provider: id_in_provider,
         email: email,
         provider_organization_id: provider_organization_id
       }) do
    case get_user_by_email(email) do
      {:ok, user} ->
        {:ok, oauth2_identity} =
          Repo.insert(
            Oauth2Identity.create_changeset(%Oauth2Identity{}, %{
              provider: provider,
              id_in_provider: to_string(id_in_provider),
              user_id: user.id,
              provider_organization_id: provider_organization_id
            })
          )

        oauth2_identity

      {:error, :not_found} ->
        user = create_oauth2_user(email, provider, id_in_provider, provider_organization_id)
        find_oauth2_identity(%{user: user, provider: provider})
    end
  end

  defp create_oauth2_user(email, provider, id_in_provider, provider_organization_id) do
    oauth2_attrs = %{
      provider: provider,
      id_in_provider: to_string(id_in_provider),
      provider_organization_id: provider_organization_id
    }

    case create_user(email, password: generate_random_string(16), oauth2_identity: oauth2_attrs) do
      {:ok, user} ->
        user

      {:error, %{name: _name_error}} ->
        # If name has an error (reserved, taken, etc), retry with a random suffix
        {:ok, user} =
          create_user(email,
            password: generate_random_string(16),
            suffix: "-#{:rand.uniform(9999)}",
            oauth2_identity: oauth2_attrs
          )

        user

      error ->
        # Re-raise any other errors
        {:ok, _} = error
    end
  end

  defp assign_sso_user_to_organization(user, provider, provider_organization_id)
       when not is_nil(provider_organization_id) do
    organization = organization_by_sso_credentials(provider, provider_organization_id)

    if organization do
      add_user_to_organization(user, organization, role: :user)
    end
  end

  defp assign_sso_user_to_organization(_user, _provider, nil), do: :ok

  defp sso_newly_enabled?(old_provider, new_provider, old_org_id, new_org_id) do
    is_nil(old_provider) and not is_nil(new_provider) and
      is_nil(old_org_id) and not is_nil(new_org_id)
  end

  @doc """
  Finds existing users who have oauth2_identities matching the given provider and provider_organization_id
  but are not yet assigned to the given organization.
  """
  def find_unassigned_sso_users(organization, provider, provider_organization_id) do
    Repo.all(
      from(u in User,
        join: oi in assoc(u, :oauth2_identities),
        left_join: ur in assoc(u, :user_roles),
        left_join: r in Role,
        on: ur.role_id == r.id,
        where: oi.provider == ^provider and oi.provider_organization_id == ^provider_organization_id,
        where: is_nil(r.id) or r.resource_type != "Organization" or r.resource_id != ^organization.id,
        distinct: u.id,
        preload: [:oauth2_identities]
      )
    )
  end

  @doc """
  Assigns existing SSO users to an organization when SSO is enabled.
  This handles the case where users logged in before the organization configured SSO.
  """
  def assign_existing_sso_users_to_organization(organization, provider, provider_organization_id)
      when not is_nil(provider) and not is_nil(provider_organization_id) do
    users = find_unassigned_sso_users(organization, provider, provider_organization_id)

    Enum.each(users, fn user ->
      add_user_to_organization(user, organization, role: :user)
    end)

    length(users)
  end

  def assign_existing_sso_users_to_organization(_organization, _provider, _provider_organization_id), do: 0

  def get_account_from_customer_id(customer_id) do
    query =
      from(a in Account,
        where: a.customer_id == ^customer_id
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      account -> {:ok, account}
    end
  end

  def get_account_from_user(%User{} = user) do
    query =
      from(a in Account,
        where: a.user_id == ^user.id
      )

    Repo.one(query)
  end

  def get_account_from_organization(%Organization{} = organization) do
    query =
      from(a in Account,
        where: a.organization_id == ^organization.id
      )

    Repo.one(query)
  end

  def owns_account_or_belongs_to_account_organization?(user, %{id: account_id}) do
    case get_account_by_id(account_id, preload: [:organization]) do
      {:ok, %Account{organization: nil} = account} ->
        owns_account?(user, account)

      {:ok, %Account{organization: organization} = account} ->
        owns_account?(user, account) or organization_admin?(user, organization) or
          organization_user?(user, organization)

      {:error, :not_found} ->
        false
    end
  end

  def owns_account_or_is_admin_to_account_organization?(user, %{id: account_id}) do
    case get_account_by_id(account_id, preload: [:organization]) do
      {:ok, %Account{organization: nil} = account} ->
        owns_account?(user, account)

      {:ok, %Account{organization: organization} = account} ->
        owns_account?(user, account) or organization_admin?(user, organization)

      {:error, :not_found} ->
        false
    end
  end

  defp owns_account?(user, account) do
    account.user_id == user.id
  end

  def add_user_to_organization(%User{id: user_id}, %Organization{id: organization_id}, opts \\ []) do
    role = Keyword.get(opts, :role, :user)

    query =
      from(u in UserRole,
        join: r in Role,
        on: u.role_id == r.id,
        where:
          u.user_id == ^user_id and r.resource_type == "Organization" and
            r.resource_id == ^organization_id
      )

    if Repo.exists?(query) do
      :ok
    else
      {:ok, _} =
        Multi.new()
        |> Multi.insert(:role, %Role{
          name: Atom.to_string(role),
          resource_type: "Organization",
          resource_id: organization_id
        })
        |> Multi.insert(:user_role, fn %{role: role} ->
          %UserRole{user_id: user_id, role_id: role.id}
        end)
        |> Repo.transaction()

      :ok
    end
  end

  def remove_user_from_organization(%User{id: user_id} = user, %Organization{id: organization_id} = organization) do
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

    if result do
      {:ok, _} =
        Multi.new()
        |> Multi.delete(:user_role, result.user_role)
        |> Multi.delete(:role, result.role)
        |> Repo.transaction()
    end

    # If user belongs to SSO organization, delete the user entirely after removing their role
    if belongs_to_sso_organization?(user, organization) do
      delete_user(user)
    end

    :ok
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

  def update_user_role_in_organization(%User{id: user_id}, %Organization{id: organization_id}, role) do
    query =
      from(u in UserRole,
        join: r in Role,
        on: u.role_id == r.id,
        where:
          u.user_id == ^user_id and r.resource_type == "Organization" and
            r.resource_id == ^organization_id,
        select: r
      )

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      user_role ->
        user_role
        |> Changeset.change(name: Atom.to_string(role))
        |> Repo.update()
    end
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
        distinct: o.id,
        select: %{
          organization: o,
          account: a
        }
      )

    Repo.all(query)
  end

  def list_invitations(organization) do
    Repo.one(
      from(o in Organization,
        join: i in Invitation,
        on: i.organization_id == o.id,
        where: o.id == ^organization.id,
        select: i
      )
    )
  end

  def invite_user_to_organization(
        email,
        %{inviter: %User{id: user_id} = inviter, to: %Organization{id: organization_id} = organization, url: url_fun},
        opts \\ []
      )
      when is_function(url_fun, 1) do
    account = get_account_from_organization(organization)
    token = Keyword.get(opts, :token, Tuist.Tokens.generate_token(16))

    invitation =
      %Invitation{}
      |> Invitation.create_changeset(%{
        token: token,
        invitee_email: email,
        inviter_id: user_id,
        organization_id: organization_id
      })
      |> Repo.insert()

    if match?({:ok, _invitation}, invitation) and Environment.mail_configured?() do
      UserNotifier.deliver_invitation(email, %{
        inviter: inviter,
        to: %{organization: organization, account: account},
        url: url_fun.(token)
      })
    end

    invitation
  end

  def invite_users_to_organization(emails, %{
        inviter: %User{id: user_id} = inviter,
        to: %Organization{id: organization_id} = organization,
        url: url_fun
      }) do
    account = get_account_from_organization(organization)

    multi =
      Enum.reduce(emails, Multi.new(), fn email, multi_acc ->
        token = Tuist.Tokens.generate_token(16)

        invitation_changeset =
          Invitation.create_changeset(%Invitation{}, %{
            token: token,
            invitee_email: email,
            inviter_id: user_id,
            organization_id: organization_id
          })

        Multi.insert(multi_acc, {:invitation, email}, invitation_changeset)
      end)

    case Repo.transaction(multi) do
      {:ok, results} ->
        if Environment.mail_configured?() do
          send_invitation_emails(results, inviter, organization, account, url_fun)
        end

        {:ok, results}

      {:error, _failed_operation_key, _failed_value, _changes_so_far} = error ->
        error
    end
  end

  defp send_invitation_emails(results, inviter, organization, account, url_fun) do
    Enum.each(results, fn {{:invitation, email}, invitation} ->
      token = invitation.token

      UserNotifier.deliver_invitation(email, %{
        inviter: inviter,
        to: %{organization: organization, account: account},
        url: url_fun.(token)
      })
    end)
  end

  def accept_invitation(%{
        invitation: %Invitation{} = invitation,
        invitee: %User{} = invitee,
        organization: %Organization{} = organization
      }) do
    add_user_to_organization(invitee, organization)
    Repo.delete(invitation)
  end

  def delete_invitation(%{invitation: %Invitation{} = invitation}) do
    Repo.delete(invitation)
  end

  def get_invitation_by_token(token, %User{} = invitee) do
    invitation =
      Invitation
      |> Repo.get_by(token: token, invitee_email: invitee.email)
      |> Repo.preload(inviter: :account)

    cond do
      is_nil(invitation) ->
        {:error, :not_found}

      !is_nil(invitation) ->
        {:ok, invitation}
    end
  end

  def get_invitation_by_token(token) do
    invitation =
      Invitation
      |> Repo.get_by(token: token)
      |> Repo.preload(inviter: :account)

    case invitation do
      nil -> {:error, :not_found}
      invitation -> {:ok, invitation}
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

    Repo.exists?(query)
  end

  def organization_user?(%User{id: user_id} = user, %Organization{id: organization_id} = organization) do
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

  def get_invitation_by_invitee_email_and_organization(invitee_email, %Organization{id: organization_id}) do
    Repo.one(
      from(i in Invitation,
        where: i.invitee_email == ^invitee_email,
        where: i.organization_id == ^organization_id
      )
    )
  end

  def get_pending_invitations_by_email(invitee_email) do
    Repo.all(
      from(i in Invitation,
        where: i.invitee_email == ^invitee_email,
        order_by: [desc: i.created_at]
      )
    )
  end

  def cancel_invitation(%Invitation{} = invitation) do
    {:ok, _} = Repo.delete(invitation)
    :ok
  end

  def get_role_by_id(id) do
    Repo.get(Role, id)
  end

  def update_user_preferred_locale(%User{} = user, preferred_locale) do
    user
    |> User.preferred_locale_changeset(%{preferred_locale: preferred_locale})
    |> Repo.update()
  end

  def update_last_visited_project(%User{} = user, last_visited_project_id) do
    {:ok, user} =
      user
      |> Changeset.change(last_visited_project_id: last_visited_project_id)
      |> Repo.update()

    user
  end

  ## Database getters

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password) when is_binary(email) and is_binary(password) do
    user =
      Repo.one(from(u in User, where: u.email == ^email, preload: [:account]))

    if User.valid_password?(user, password) do
      cond do
        is_nil(user.confirmed_at) ->
          {:error, :not_confirmed}

        not user.active ->
          {:error, :invalid_email_or_password}

        true ->
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
  def get_user!(id, opts \\ []) do
    preload = Keyword.get(opts, :preload, [])

    User
    |> Repo.get!(id)
    |> Repo.preload(preload)
  end

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
  Updates the account's name.
  """
  def update_account(%Account{} = account, attrs) do
    account
    |> Account.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Creates a namespace tenant for the account and updates the account with the namespace_tenant_id.
  """
  def create_namespace_tenant_for_account(%Account{} = account) do
    case Namespace.create_tenant(
           account.name,
           account.id
         ) do
      {:ok, %{"tenant" => %{"id" => namespace_tenant_id}}} ->
        account
        |> Account.update_changeset(%{namespace_tenant_id: namespace_tenant_id})
        |> Repo.update()

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_session_token(token, opts \\ []) do
    preload = Keyword.get(opts, :preload, [])
    {:ok, query} = UserToken.verify_session_token_query(token)

    case query |> Repo.one() |> Repo.preload(preload) do
      %User{active: false} -> nil
      user -> user
    end
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
  def deliver_user_confirmation_instructions(%{user: user, confirmation_url: confirmation_url})
      when is_function(confirmation_url, 1) do
    if user.confirmed_at do
      {:error, :already_confirmed}
    else
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)

      UserNotifier.deliver_confirmation_instructions(%{
        user: user,
        confirmation_url: confirmation_url.(encoded_token)
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
    Multi.new()
    |> Multi.update(:user, User.confirm_changeset(user))
    |> Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, ["confirm"]))
  end

  ## Reset password

  @doc ~S"""
  Delivers the reset password email to the given user.

  ## Examples

      iex> deliver_user_reset_password_instructions(user, &url(~p"/users/reset_password/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_reset_password_instructions(%{user: %User{} = user, reset_password_url: reset_password_url})
      when is_function(reset_password_url, 1) do
    if recently_sent_reset_password_instructions?(user) do
      :ok
    else
      Repo.delete_all(UserToken.by_user_and_contexts_query(user, ["reset_password"]))

      {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
      Repo.insert!(user_token)

      UserNotifier.deliver_reset_password_instructions(%{
        user: user,
        reset_password_url: reset_password_url.(encoded_token)
      })
    end
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
      {:ok, %{user: %User{}, revoked_session_live_socket_ids: []}}

      iex> reset_user_password(user, %{password: "valid", password_confirmation: "not the same"})
      {:error, %Ecto.Changeset{}}

  """
  def reset_user_password(user, attrs) do
    Multi.new()
    |> Multi.all(:session_tokens, UserToken.by_user_and_contexts_query(user, ["session"]))
    |> Multi.update(:user, User.password_changeset(user, attrs))
    |> Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user, session_tokens: session_tokens}} ->
        {:ok,
         %{
           user: user,
           revoked_session_live_socket_ids: Enum.map(session_tokens, &UserToken.live_socket_id/1)
         }}

      {:error, :user, changeset, _} ->
        {:error, changeset}
    end
  end

  defp recently_sent_reset_password_instructions?(%User{id: user_id}) do
    Repo.exists?(
      from t in UserToken,
        where:
          t.user_id == ^user_id and
            t.context == "reset_password" and
            t.inserted_at > ago(@reset_password_delivery_cooldown_in_minutes, "minute")
    )
  end

  defp generate_random_string(length) do
    length
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
    |> binary_part(0, length)
  end

  @doc """
  Creates a new account token with fine-grained permissions.

  ## Parameters
  - `account` - The account that owns the token
  - `scopes` - List of scope strings (e.g., ["project:cache:read", "account:members:read"])
  - `created_by_account` - Optional account that created this token (for tracking)
  - `name` - Optional friendly name for the token
  - `expires_at` - Optional expiration datetime
  - `all_projects` - When true, token has access to all projects (default: false)
  - `project_ids` - List of project IDs to restrict access to (only used when all_projects is false)
  """
  def create_account_token(%{account: %Account{} = account, scopes: scopes} = params, opts \\ []) do
    preload = Keyword.get(opts, :preload, [])
    token_hash = Base64.encode(:crypto.strong_rand_bytes(20))

    encrypted_token_hash =
      Bcrypt.hash_pwd_salt(token_hash <> Environment.secret_key_password())

    created_by_account = Map.get(params, :created_by_account)
    name = Map.get(params, :name)
    expires_at = Map.get(params, :expires_at)
    all_projects = Map.get(params, :all_projects, false)
    project_ids = Map.get(params, :project_ids, [])

    token_changeset =
      AccountToken.create_changeset(%{
        account_id: account.id,
        created_by_account_id: created_by_account && created_by_account.id,
        encrypted_token_hash: encrypted_token_hash,
        scopes: scopes,
        name: name,
        expires_at: expires_at,
        all_projects: all_projects
      })

    result =
      Multi.new()
      |> Multi.insert(:token, token_changeset)
      |> Multi.run(:project_associations, fn _repo, %{token: token} ->
        Enum.each(project_ids, fn project_id ->
          %{account_token_id: token.id, project_id: project_id}
          |> AccountTokenProject.create_changeset()
          |> Repo.insert!()
        end)

        {:ok, :created}
      end)
      |> Repo.transaction()

    case result do
      {:ok, %{token: token}} ->
        token = Repo.preload(token, preload)
        {:ok, {token, "tuist_#{token.id}_#{token_hash}"}}

      {:error, :token, changeset, _changes} ->
        {:error, changeset}
    end
  end

  @doc """
  Retrieves and validates an account token from its full token string.

  Returns `{:ok, token}` if valid, or `{:error, reason}` where reason is one of:
  - `:not_found` - Token does not exist
  - `:expired` - Token has expired
  - `:invalid_token` - Token format is invalid or hash doesn't match
  """
  def account_token(full_token, opts \\ []) do
    preload = Keyword.get(opts, :preload, []) ++ [:account_token_projects]
    full_token_components = String.split(full_token, "_")

    if length(full_token_components) == 3 do
      [_audience, token_id, token_hash] = full_token_components

      with {:ok, _} <- UUIDv7.cast(token_id),
           token when not is_nil(token) <-
             from(t in AccountToken, where: t.id == ^token_id)
             |> Repo.one()
             |> Repo.preload(preload),
           false <- account_token_expired?(token),
           :ok <- reject_inactive_account_token_users(token),
           true <- verify_pass(token, token_hash) do
        {:ok, token}
      else
        nil -> {:error, :not_found}
        true -> {:error, :expired}
        {:error, :inactive_user} -> {:error, :inactive_user}
        _ -> {:error, :invalid_token}
      end
    else
      {:error, :invalid_token}
    end
  end

  defp reject_inactive_account_token_users(%AccountToken{} = token) do
    token = Repo.preload(token, account: :user, created_by_account: :user)

    if account_user_inactive?(token.account) or account_user_inactive?(token.created_by_account) do
      {:error, :inactive_user}
    else
      :ok
    end
  end

  defp account_user_inactive?(%Account{user: %User{active: false}}), do: true
  defp account_user_inactive?(_account), do: false

  @doc """
  Lists account tokens for a given account with pagination support via Flop.
  """
  def list_account_tokens(%Account{} = account, attrs \\ %{}) do
    base_query =
      from(t in AccountToken,
        where: t.account_id == ^account.id,
        preload: [:projects, :created_by_account]
      )

    Flop.validate_and_run!(base_query, attrs, for: AccountToken)
  end

  @doc """
  Gets a specific account token by name for a given account.
  """
  def get_account_token_by_name(%Account{} = account, token_name, opts \\ []) do
    preload = Keyword.get(opts, :preload, [:projects, :created_by_account])

    case Repo.one(
           from(t in AccountToken,
             where: t.name == ^token_name and t.account_id == ^account.id,
             preload: ^preload
           )
         ) do
      nil -> {:error, :not_found}
      token -> {:ok, token}
    end
  end

  @doc """
  Deletes (revokes) an account token.
  """
  def delete_account_token(%AccountToken{} = token) do
    Repo.delete(token)
  end

  def create_agent_registration(
        %{email: email, requested_credential_type: requested_credential_type, claim_view_url: claim_view_url} = attrs
      )
      when requested_credential_type in [:access_token, :api_key] and is_function(claim_view_url, 1) do
    email = normalize_agent_registration_email(email)

    with :ok <- validate_agent_registration_email(email) do
      now = Time.utc_now()
      claim = build_agent_registration_claim_bundle()

      claim_token_expires_at = DateTime.add(now, @agent_registration_claim_token_ttl_seconds, :second)
      otp_expires_at = DateTime.add(now, @agent_registration_otp_ttl_seconds, :second)

      changeset =
        AgentRegistration.create_email_verification_changeset(%{
          registration_type: :email_verification,
          status: :pending,
          requested_credential_type: requested_credential_type,
          email: email,
          claim_token_hash: claim.claim_token_hash,
          claim_view_token_hash: claim.claim_view_token_hash,
          otp_hash: claim.otp_hash,
          claim_token_expires_at: claim_token_expires_at,
          otp_expires_at: otp_expires_at,
          claim_attempt_id: claim.claim_attempt_id,
          registration_ip: Map.get(attrs, :registration_ip),
          claim_requested_ip: Map.get(attrs, :registration_ip)
        })

      with {:ok, registration} <- Repo.insert(changeset) do
        insert_agent_registration_event!(registration, :created, %{
          actor_ip: Map.get(attrs, :registration_ip),
          metadata: %{
            claim_attempt_id: claim.claim_attempt_id,
            credential_type: Atom.to_string(requested_credential_type),
            registration_type: "email_verification"
          },
          occurred_at: now
        })

        email_delivery =
          UserNotifier.deliver_agent_registration_claim_instructions(%{
            email: email,
            claim_view_url: claim_view_url.(claim.claim_view_token)
          })

        {:ok,
         %{
           registration: registration,
           claim_token: claim.claim_token,
           claim_token_expires_at: claim_token_expires_at,
           email_delivery: email_delivery
         }}
      end
    end
  end

  def create_agent_registration(%{requested_credential_type: requested_credential_type})
      when requested_credential_type not in [:access_token, :api_key] do
    {:error, :unsupported_credential_type}
  end

  def create_agent_registration(%{registration_type: :anonymous, requested_credential_type: :api_key} = attrs) do
    now = Time.utc_now()
    claim_token = prefixed_agent_registration_token("clm")
    claim_token_expires_at = DateTime.add(now, @agent_registration_claim_token_ttl_seconds, :second)

    with {:ok, anonymous_user} <- create_anonymous_agent_registration_user(),
         {:ok, {account_token, api_key}} <-
           create_account_token(%{
             account: anonymous_user.account,
             created_by_account: anonymous_user.account,
             scopes: @agent_registration_scopes,
             name: agent_registration_token_name(),
             all_projects: true
           }),
         {:ok, registration} <-
           %{
             registration_type: :anonymous,
             status: :pending,
             requested_credential_type: :api_key,
             email: anonymous_user.email,
             claim_token_hash: hash_agent_registration_secret(claim_token),
             claim_token_expires_at: claim_token_expires_at,
             registration_ip: Map.get(attrs, :registration_ip),
             account_token_id: account_token.id
           }
           |> AgentRegistration.create_anonymous_changeset()
           |> Repo.insert() do
      insert_agent_registration_event!(registration, :created, %{
        actor_ip: Map.get(attrs, :registration_ip),
        metadata: %{
          credential_type: "api_key",
          registration_type: "anonymous"
        },
        occurred_at: now
      })

      {:ok,
       %{
         registration: registration,
         credential_type: :api_key,
         credential: api_key,
         credential_expires_at: nil,
         scopes: @agent_registration_scopes,
         claim_token: claim_token,
         claim_token_expires_at: claim_token_expires_at
       }}
    end
  end

  def create_agent_registration(
        %{
          registration_type: :agent_provider,
          assertion: assertion,
          requested_credential_type: requested_credential_type,
          audience: audience
        } = attrs
      )
      when requested_credential_type in [:access_token, :api_key] do
    now = Time.utc_now()

    with {:ok, claims} <- verify_agent_auth_jwt(assertion, audience, :id_jag),
         {:ok, email} <- verified_agent_auth_email(claims),
         {:ok, user} <- get_or_provision_agent_registration_user_from_assertion(claims, email, audience),
         {:ok, credential} <- issue_agent_registration_credential(user, requested_credential_type),
         {:ok, registration} <-
           %{
             registration_type: :agent_provider,
             status: :claimed,
             requested_credential_type: requested_credential_type,
             email: email,
             claim_token_hash: hash_agent_registration_secret(prefixed_agent_registration_token("clm")),
             claim_token_expires_at: DateTime.add(now, @agent_registration_claim_token_ttl_seconds, :second),
             claimed_at: now,
             claimed_by_user_id: user.id,
             account_token_id: credential[:account_token_id],
             issuer: claims["iss"],
             subject: claims["sub"],
             audience: audience,
             client_id: claims["client_id"],
             assertion_jti: claims["jti"],
             credential_jti: credential[:credential_jti]
           }
           |> AgentRegistration.create_agent_provider_changeset()
           |> Repo.insert() do
      insert_agent_registration_event!(registration, :created, %{
        actor_ip: Map.get(attrs, :registration_ip),
        claimed_by_user_id: user.id,
        metadata: agent_provider_event_metadata(claims, requested_credential_type),
        occurred_at: now
      })

      insert_agent_registration_event!(registration, :claimed, %{
        actor_ip: Map.get(attrs, :registration_ip),
        claimed_by_user_id: user.id,
        metadata: agent_provider_event_metadata(claims, requested_credential_type),
        occurred_at: now
      })

      {:ok,
       %{
         registration: registration,
         credential_type: requested_credential_type,
         credential: credential.credential,
         credential_expires_at: credential.expires_at,
         scopes: @agent_registration_scopes
       }}
    end
  end

  def create_agent_registration(_), do: {:error, :invalid_request}

  def revoke_agent_registrations(logout_token, audience) do
    now = Time.utc_now()

    with {:ok, claims} <- verify_agent_auth_jwt(logout_token, audience, :logout),
         :ok <- validate_agent_auth_revocation_event(claims) do
      registrations = list_revocable_agent_provider_registrations(claims, audience)

      Enum.each(registrations, fn registration ->
        revoke_agent_registration_credential(registration)

        {:ok, revoked_registration} =
          registration
          |> AgentRegistration.revoke_changeset(%{status: :revoked, revoked_at: now})
          |> Repo.update()

        insert_agent_registration_event!(revoked_registration, :revoked, %{
          metadata: %{
            issuer: claims["iss"],
            subject: claims["sub"],
            audience: audience,
            assertion_jti: claims["jti"]
          },
          occurred_at: now
        })
      end)

      {:ok, %{revoked_count: length(registrations)}}
    end
  end

  def agent_registration_credential_revoked?(%{"jti" => jti}) when is_binary(jti) do
    Repo.exists?(
      from(r in AgentRegistration,
        where: r.status == :revoked and r.credential_jti == ^jti
      )
    )
  end

  def agent_registration_credential_revoked?(_claims), do: false

  def resend_agent_registration_claim(%{claim_token: claim_token, claim_view_url: claim_view_url} = attrs)
      when is_function(claim_view_url, 1) do
    email = attrs |> Map.get(:email) |> normalize_agent_registration_email()

    fn ->
      with {:ok, registration} <- get_agent_registration_by_claim_token(claim_token, lock: "FOR UPDATE"),
           :ok <- validate_agent_registration_email(email),
           :ok <- ensure_registration_email_matches(registration, email),
           :ok <- ensure_agent_registration_not_claimed(registration),
           :ok <- ensure_agent_registration_claim_token_valid(registration) do
        claim = build_agent_registration_claim_bundle()
        now = Time.utc_now()
        otp_expires_at = DateTime.add(now, @agent_registration_otp_ttl_seconds, :second)

        {:ok, registration} =
          registration
          |> AgentRegistration.refresh_claim_changeset(%{
            claim_view_token_hash: claim.claim_view_token_hash,
            otp_hash: claim.otp_hash,
            otp_expires_at: otp_expires_at,
            claim_attempt_id: claim.claim_attempt_id,
            otp_attempt_count: 0,
            claim_requested_ip: Map.get(attrs, :claim_requested_ip),
            email: email
          })
          |> Repo.update()

        insert_agent_registration_event!(registration, :claim_resent, %{
          actor_ip: Map.get(attrs, :claim_requested_ip),
          metadata: %{claim_attempt_id: claim.claim_attempt_id, email: email},
          occurred_at: now
        })

        email_delivery =
          UserNotifier.deliver_agent_registration_claim_instructions(%{
            email: email,
            claim_view_url: claim_view_url.(claim.claim_view_token)
          })

        %{
          registration: registration,
          otp_expires_at: otp_expires_at,
          email_delivery: email_delivery
        }
      end
    end
    |> Repo.transaction()
    |> unwrap_repo_transaction()
  end

  def complete_agent_registration_claim(%{claim_token: claim_token, otp: otp} = attrs) do
    fn ->
      with {:ok, registration} <- get_agent_registration_by_claim_token(claim_token, lock: "FOR UPDATE"),
           :ok <- ensure_agent_registration_not_claimed(registration),
           :ok <- ensure_agent_registration_claim_token_valid(registration),
           :ok <- ensure_agent_registration_otp_valid(registration),
           true <- secure_compare_hash(hash_agent_registration_secret(otp), registration.otp_hash) do
        user = get_or_provision_agent_registration_user!(registration.email)
        now = Time.utc_now()
        {:ok, credential} = claim_agent_registration_credential(registration, user)

        {:ok, registration} =
          registration
          |> AgentRegistration.claim_changeset(%{
            status: :claimed,
            claimed_at: now,
            claim_completed_ip: Map.get(attrs, :claim_completed_ip),
            claimed_by_user_id: user.id,
            account_token_id: credential[:account_token_id],
            credential_jti: credential[:credential_jti]
          })
          |> Repo.update()

        insert_agent_registration_event!(registration, :claimed, %{
          actor_ip: Map.get(attrs, :claim_completed_ip),
          claimed_by_user_id: user.id,
          metadata: %{claim_attempt_id: registration.claim_attempt_id},
          occurred_at: now
        })

        %{
          registration: registration,
          credential_type: registration.requested_credential_type,
          credential: credential.credential,
          credential_expires_at: credential.expires_at,
          scopes: @agent_registration_scopes
        }
      else
        false ->
          case get_agent_registration_by_claim_token(claim_token, lock: "FOR UPDATE") do
            {:ok, registration} ->
              now = Time.utc_now()

              updated_registration =
                registration
                |> AgentRegistration.increment_otp_attempts_changeset()
                |> Repo.update!()

              insert_agent_registration_event!(updated_registration, :otp_failed, %{
                actor_ip: Map.get(attrs, :claim_completed_ip),
                metadata: %{
                  claim_attempt_id: updated_registration.claim_attempt_id,
                  otp_attempt_count: updated_registration.otp_attempt_count
                },
                occurred_at: now
              })

              if updated_registration.otp_attempt_count >= @agent_registration_max_otp_attempts do
                {:error, :rate_limited}
              else
                {:error, :otp_invalid}
              end

            {:error, reason} ->
              {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
    |> Repo.transaction()
    |> unwrap_repo_transaction()
  end

  def get_agent_registration_claim_view(claim_view_token) when is_binary(claim_view_token) do
    with {:ok, registration} <- get_agent_registration_by_claim_view_token(claim_view_token),
         :ok <- ensure_agent_registration_not_claimed(registration),
         :ok <- ensure_agent_registration_claim_token_valid(registration),
         :ok <- ensure_agent_registration_otp_window_valid(registration) do
      {:ok,
       %{
         registration: registration,
         otp: derive_agent_registration_otp(claim_view_token),
         otp_expires_at: registration.otp_expires_at
       }}
    end
  end

  @doc """
  Checks if the token has expired.
  """
  def account_token_expired?(%AccountToken{expires_at: nil}), do: false

  def account_token_expired?(%AccountToken{expires_at: expires_at}) do
    DateTime.compare(expires_at, DateTime.utc_now()) != :gt
  end

  # Bcrypt does CPU-intensive operations and it can easily slow-down requests when
  # there are bursts of requests coming through the API.
  defp verify_pass(token, token_hash) do
    Bcrypt.verify_pass(
      token_hash <> Environment.secret_key_password(),
      token.encrypted_token_hash
    )
  end

  def avatar_color(%Account{name: name}) do
    index = :erlang.phash2(name, Enum.count(available_avatar_colors()))

    Enum.at(available_avatar_colors(), index)
  end

  defp available_avatar_colors do
    ~w(gray red orange yellow azure blue purple pink)
  end

  @okta_authorize_path "/oauth2/v1/authorize"
  @okta_token_path "/oauth2/v1/token"
  @okta_userinfo_path "/oauth2/v1/userinfo"

  def oauth2_config_for_organization(%Organization{
        sso_provider: provider,
        sso_organization_id: sso_organization_id,
        oauth2_client_id: client_id,
        oauth2_encrypted_client_secret: client_secret,
        oauth2_authorize_url: authorize_url,
        oauth2_token_url: token_url,
        oauth2_user_info_url: user_info_url
      })
      when provider in [:okta, :oauth2] and not is_nil(sso_organization_id) and not is_nil(client_id) and
             not is_nil(client_secret) and not is_nil(authorize_url) and not is_nil(token_url) and
             not is_nil(user_info_url) do
    site = if provider == :okta, do: "https://#{sso_organization_id}", else: sso_organization_id

    {:ok,
     %{
       site: site,
       provider_organization_id: sso_organization_id,
       client_id: client_id,
       client_secret: client_secret,
       authorize_url: authorize_url,
       token_url: token_url,
       user_info_url: user_info_url
     }}
  end

  def oauth2_config_for_organization(_organization) do
    {:error, :oauth2_not_configured}
  end

  def okta_authorize_url(domain), do: "https://#{domain}#{@okta_authorize_path}"
  def okta_token_url(domain), do: "https://#{domain}#{@okta_token_path}"
  def okta_userinfo_url(domain), do: "https://#{domain}#{@okta_userinfo_path}"

  def sso_organization_for_user_email(email) do
    with {:ok, user} <- get_user_by_email(email),
         organization when not is_nil(organization) <- user_sso_organization(user) do
      {:ok, organization}
    else
      _ ->
        sso_organization_for_email_domain(email)
    end
  end

  defp sso_organization_for_email_domain(email) do
    case String.split(email, "@") do
      [_username, domain] ->
        okta_domain = String.replace(domain, ".com", ".okta.com")
        url_domain = "https://#{domain}"

        case Repo.one(
               from(o in Organization,
                 where: o.sso_provider in [:okta, :oauth2],
                 where:
                   o.sso_organization_id == ^domain or
                     o.sso_organization_id == ^okta_domain or
                     o.sso_organization_id == ^url_domain
               )
             ) do
          %Organization{} = organization -> {:ok, organization}
          nil -> {:error, :not_found}
        end

      _ ->
        {:error, :not_found}
    end
  end

  defp user_sso_organization(user) do
    user_organizations = get_user_organization_accounts(user)

    Enum.find_value(user_organizations, fn %{organization: organization} ->
      if organization.sso_provider in [:okta, :oauth2] && organization.sso_organization_id do
        organization
      end
    end)
  end

  def delete_account!(%Account{} = account) do
    cond do
      user?(account) ->
        account_user = get_user_by_id(account.user_id)
        delete_user(account_user)

      organization?(account) ->
        {:ok, account_organization} = get_organization_by_id(account.organization_id)
        delete_organization!(account_organization)
    end
  end

  def organization?(account), do: !is_nil(account.organization_id)
  def user?(account), do: !is_nil(account.user_id)

  @doc """
  Lists all account cache endpoints for the given account and cache technology.
  """
  def list_account_cache_endpoints(%Account{} = account, technology \\ :default) do
    Repo.all(
      from(e in AccountCacheEndpoint,
        where: e.account_id == ^account.id and e.technology == ^technology
      )
    )
  end

  @doc """
  Returns whether custom cache endpoints are available for the given account.
  """
  def custom_cache_endpoints_available?(%Account{} = account) do
    if Environment.tuist_hosted?() do
      case Billing.get_current_active_subscription(account) do
        %{plan: :enterprise} -> true
        _ -> false
      end
    else
      false
    end
  end

  @doc """
  Returns cache endpoint URLs for the given account handle and cache technology.

  For the default cache technology, custom endpoints are only returned when:
  - The account exists
  - The account is on the enterprise plan when Tuist-hosted
  - The account has `custom_cache_endpoints_enabled` set to `true`
  - The account has at least one custom cache endpoint configured

  For Kura, account-specific endpoints are returned only when they have been configured.
  """
  def get_cache_endpoints_for_handle(account_handle, technology \\ :default)

  def get_cache_endpoints_for_handle(account_handle, :default) when is_binary(account_handle) do
    if Environment.tuist_hosted?() do
      account_handle
      |> get_account_by_handle()
      |> custom_cache_endpoints()
      |> case do
        [] -> CacheEndpoints.active_endpoint_urls()
        endpoints -> Enum.map(endpoints, & &1.url)
      end
    else
      CacheEndpoints.active_endpoint_urls()
    end
  end

  def get_cache_endpoints_for_handle(account_handle, :kura) when is_binary(account_handle) do
    case get_account_by_handle(account_handle) do
      %Account{} = account -> kura_cache_endpoint_urls(account)
      _ -> []
    end
  end

  def get_cache_endpoints_for_handle(_, :default), do: CacheEndpoints.active_endpoint_urls()
  def get_cache_endpoints_for_handle(_, :kura), do: []

  defp custom_cache_endpoints(%Account{custom_cache_endpoints_enabled: true} = account) do
    if custom_cache_endpoints_available?(account) do
      list_account_cache_endpoints(account)
    else
      []
    end
  end

  defp custom_cache_endpoints(_), do: []

  defp kura_cache_endpoints(%Account{} = account), do: list_account_cache_endpoints(account, :kura)
  defp kura_cache_endpoints(_), do: []

  defp kura_cache_endpoint_urls(%Account{} = account) do
    endpoints = kura_cache_endpoints(account)
    global_candidate_url = Kura.global_cache_endpoint_candidate_url(account)

    case {endpoints, Kura.global_cache_endpoint_url(account)} do
      {[], _global_url} -> []
      {_endpoints, global_url} when is_binary(global_url) -> [global_url]
      {endpoints, _global_url} -> endpoints |> Enum.map(& &1.url) |> Enum.reject(&(&1 == global_candidate_url))
    end
  end

  @doc """
  Creates a custom cache endpoint for the given account.
  """
  def create_account_cache_endpoint(%Account{} = account, attrs) do
    %AccountCacheEndpoint{}
    |> AccountCacheEndpoint.create_changeset(Map.put(attrs, :account_id, account.id))
    |> Repo.insert()
  end

  @doc """
  Deletes a custom cache endpoint.
  """
  def delete_account_cache_endpoint(%AccountCacheEndpoint{} = endpoint) do
    Repo.delete(endpoint)
  end

  @doc """
  Gets a custom cache endpoint by its ID.
  """
  def get_account_cache_endpoint!(id) do
    Repo.get!(AccountCacheEndpoint, id)
  end

  @doc """
  Gets a custom cache endpoint by ID, scoped to the given account.
  Returns `nil` if the endpoint doesn't exist or doesn't belong to the account.
  """
  def get_account_cache_endpoint(%Account{} = account, id) do
    Repo.get_by(AccountCacheEndpoint, id: id, account_id: account.id)
  end

  defp default_confirmed_at do
    if Environment.skip_email_confirmation?() do
      NaiveDateTime.utc_now()
    end
  end

  defp validate_agent_registration_email(email) do
    if User.email_valid?(email) do
      :ok
    else
      {:error, :invalid_email}
    end
  end

  defp normalize_agent_registration_email(email) when is_binary(email) do
    email
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_agent_registration_email(_), do: nil

  defp ensure_registration_email_matches(_registration, nil), do: :ok
  defp ensure_registration_email_matches(%AgentRegistration{registration_type: :anonymous}, _email), do: :ok

  defp ensure_registration_email_matches(%AgentRegistration{email: registration_email}, email) do
    if registration_email == email do
      :ok
    else
      {:error, :invalid_claim_token}
    end
  end

  defp ensure_agent_registration_not_claimed(%AgentRegistration{status: :claimed}), do: {:error, :previously_claimed}
  defp ensure_agent_registration_not_claimed(_registration), do: :ok

  defp ensure_agent_registration_claim_token_valid(%AgentRegistration{} = registration) do
    if agent_registration_claim_token_expired?(registration) do
      maybe_expire_agent_registration(registration)
      {:error, :claim_expired}
    else
      :ok
    end
  end

  defp ensure_agent_registration_otp_window_valid(%AgentRegistration{} = registration) do
    if agent_registration_otp_expired?(registration) do
      {:error, :otp_expired}
    else
      :ok
    end
  end

  defp ensure_agent_registration_otp_valid(%AgentRegistration{} = registration) do
    cond do
      registration.otp_attempt_count >= @agent_registration_max_otp_attempts ->
        {:error, :rate_limited}

      agent_registration_otp_expired?(registration) ->
        {:error, :otp_expired}

      true ->
        :ok
    end
  end

  defp verify_agent_auth_jwt(token, audience, token_type) do
    with {:ok, header} <- peek_agent_auth_jwt_header(token),
         :ok <- validate_agent_auth_jwt_type(header, token_type),
         {:ok, issuer} <- peek_agent_auth_jwt_issuer(token),
         {:ok, provider} <- trusted_agent_auth_provider(issuer),
         {:ok, jwks} <- fetch_agent_auth_jwks(provider),
         {:ok, claims} <- verify_agent_auth_jwt_signature(token, jwks, header),
         :ok <- validate_agent_auth_claims(claims, audience, provider, token_type),
         :ok <- record_agent_auth_jti(claims) do
      {:ok, claims}
    end
  end

  defp peek_agent_auth_jwt_header(token) do
    with [header_b64 | _] <- String.split(token, "."),
         {:ok, header_json} <- Base.url_decode64(header_b64, padding: false),
         {:ok, header} <- JSON.decode(header_json) do
      {:ok, header}
    else
      _ -> {:error, :invalid_signature}
    end
  end

  defp peek_agent_auth_jwt_issuer(token) do
    case JOSE.JWT.peek_payload(token) do
      %JOSE.JWT{fields: %{"iss" => issuer}} when is_binary(issuer) -> {:ok, issuer}
      _ -> {:error, :invalid_issuer}
    end
  rescue
    _ -> {:error, :invalid_signature}
  end

  defp validate_agent_auth_jwt_type(%{"typ" => "oauth-id-jag+jwt"}, :id_jag), do: :ok
  defp validate_agent_auth_jwt_type(%{"typ" => "logout+jwt"}, :logout), do: :ok
  defp validate_agent_auth_jwt_type(_header, _token_type), do: {:error, :invalid_signature}

  defp trusted_agent_auth_provider(issuer) do
    provider =
      Enum.find(Environment.agent_auth_trusted_providers(), fn provider ->
        provider_value(provider, "issuer") == issuer
      end)

    case provider do
      nil -> {:error, :invalid_issuer}
      provider -> {:ok, provider}
    end
  end

  defp fetch_agent_auth_jwks(provider) do
    cond do
      is_map(provider_value(provider, "jwks")) ->
        {:ok, provider_value(provider, "jwks")}

      is_binary(provider_value(provider, "jwks_uri")) ->
        jwks_uri = provider_value(provider, "jwks_uri")

        KeyValueStore.get_or_update(["agent_auth", "jwks", jwks_uri], [ttl: to_timeout(minute: 15)], fn ->
          case Req.get(jwks_uri, connect_options: [timeout: 10_000]) do
            {:ok, %{status: 200, body: body}} -> {:ok, body}
            _ -> {:error, :invalid_signature}
          end
        end)

      is_binary(provider_value(provider, "issuer")) ->
        issuer = provider_value(provider, "issuer")
        fetch_agent_auth_jwks(Map.put(provider, "jwks_uri", "#{issuer}/.well-known/jwks.json"))

      true ->
        {:error, :invalid_signature}
    end
  end

  defp verify_agent_auth_jwt_signature(token, %{"keys" => keys}, header) do
    algorithms = header |> Map.get("alg") |> List.wrap()

    with {:ok, key} <- find_agent_auth_jwk(keys, Map.get(header, "kid")),
         {true, %JOSE.JWT{fields: claims}, _jws} <- JOSE.JWT.verify_strict(JOSE.JWK.from_map(key), algorithms, token) do
      {:ok, claims}
    else
      _ -> {:error, :invalid_signature}
    end
  end

  defp verify_agent_auth_jwt_signature(_token, _jwks, _header), do: {:error, :invalid_signature}

  defp find_agent_auth_jwk(keys, nil), do: {:ok, List.first(keys)}

  defp find_agent_auth_jwk(keys, kid) do
    case Enum.find(keys, &(&1["kid"] == kid)) do
      nil -> {:error, :invalid_signature}
      key -> {:ok, key}
    end
  end

  defp validate_agent_auth_claims(claims, audience, provider, token_type) do
    with :ok <- validate_agent_auth_audience(claims, audience),
         :ok <- validate_agent_auth_expiration(claims),
         :ok <- validate_agent_auth_issued_at(claims),
         :ok <- validate_agent_auth_required_claims(claims),
         :ok <- validate_agent_auth_client_id(claims, provider) do
      validate_agent_auth_identity_claims(claims, token_type)
    end
  end

  defp validate_agent_auth_audience(%{"aud" => audience}, audience), do: :ok

  defp validate_agent_auth_audience(%{"aud" => audiences}, audience) when is_list(audiences) do
    if audience in audiences, do: :ok, else: {:error, :invalid_audience}
  end

  defp validate_agent_auth_audience(_claims, _audience), do: {:error, :invalid_audience}

  defp validate_agent_auth_expiration(%{"exp" => exp}) when is_integer(exp) do
    if exp > DateTime.to_unix(Time.utc_now()), do: :ok, else: {:error, :expired}
  end

  defp validate_agent_auth_expiration(_claims), do: {:error, :expired}

  defp validate_agent_auth_issued_at(%{"iat" => iat}) when is_integer(iat) do
    if iat <= DateTime.to_unix(Time.utc_now()) + 120 do
      :ok
    else
      {:error, :insufficient_user_authentication}
    end
  end

  defp validate_agent_auth_issued_at(_claims), do: {:error, :insufficient_user_authentication}

  defp validate_agent_auth_required_claims(%{"iss" => iss, "sub" => sub, "jti" => jti, "client_id" => client_id})
       when is_binary(iss) and is_binary(sub) and is_binary(jti) and is_binary(client_id) do
    :ok
  end

  defp validate_agent_auth_required_claims(_claims), do: {:error, :invalid_signature}

  defp validate_agent_auth_client_id(%{"client_id" => client_id}, provider) do
    case provider_value(provider, "client_ids") do
      client_ids when is_list(client_ids) and client_ids != [] ->
        if client_id in client_ids, do: :ok, else: {:error, :invalid_client_id}

      _ ->
        :ok
    end
  end

  defp validate_agent_auth_identity_claims(_claims, :logout), do: :ok

  defp validate_agent_auth_identity_claims(%{"email" => email, "email_verified" => true}, :id_jag)
       when is_binary(email) do
    :ok
  end

  defp validate_agent_auth_identity_claims(_claims, :id_jag), do: {:error, :missing_verified_email}

  defp record_agent_auth_jti(%{"iss" => issuer, "jti" => jti, "exp" => exp}) do
    expires_at = DateTime.from_unix!(exp)

    case %{issuer: issuer, jti: jti, expires_at: expires_at}
         |> AgentAuthJTI.create_changeset()
         |> Repo.insert() do
      {:ok, _jti} -> :ok
      {:error, _changeset} -> {:error, :replay_detected}
    end
  end

  defp verified_agent_auth_email(%{"email" => email, "email_verified" => true}) when is_binary(email) do
    {:ok, normalize_agent_registration_email(email)}
  end

  defp verified_agent_auth_email(_claims), do: {:error, :missing_verified_email}

  defp get_or_provision_agent_registration_user_from_assertion(claims, email, audience) do
    case get_agent_registration_user_by_delegation(claims, audience) do
      %User{} = user -> {:ok, Repo.preload(user, :account)}
      nil -> {:ok, get_or_provision_agent_registration_user!(email)}
    end
  end

  defp get_agent_registration_user_by_delegation(%{"iss" => issuer, "sub" => subject}, audience) do
    from(r in AgentRegistration,
      where:
        r.registration_type == :agent_provider and r.status == :claimed and r.issuer == ^issuer and
          r.subject == ^subject and r.audience == ^audience,
      order_by: [desc: r.claimed_at],
      preload: [claimed_by_user: :account],
      limit: 1
    )
    |> Repo.one()
    |> case do
      %AgentRegistration{claimed_by_user: user} -> user
      nil -> nil
    end
  end

  defp validate_agent_auth_revocation_event(%{"events" => events}) when is_map(events) do
    if Map.has_key?(events, "https://schemas.workos.com/events/agent/auth/identity/assertion/revoked") do
      :ok
    else
      {:error, :invalid_request}
    end
  end

  defp validate_agent_auth_revocation_event(_claims), do: {:error, :invalid_request}

  defp list_revocable_agent_provider_registrations(%{"iss" => issuer, "sub" => subject}, audience) do
    Repo.all(
      from(r in AgentRegistration,
        where:
          r.registration_type == :agent_provider and r.status == :claimed and r.issuer == ^issuer and
            r.subject == ^subject and r.audience == ^audience
      )
    )
  end

  defp revoke_agent_registration_credential(%AgentRegistration{account_token_id: account_token_id})
       when not is_nil(account_token_id) do
    Repo.delete_all(from(t in AccountToken, where: t.id == ^account_token_id))
  end

  defp revoke_agent_registration_credential(%AgentRegistration{credential_jti: credential_jti})
       when not is_nil(credential_jti) do
    Repo.delete_all(from(t in "guardian_tokens", where: field(t, :jti) == ^credential_jti))
  end

  defp revoke_agent_registration_credential(_registration), do: :ok

  defp agent_provider_event_metadata(claims, requested_credential_type) do
    %{
      issuer: claims["iss"],
      subject: claims["sub"],
      client_id: claims["client_id"],
      assertion_jti: claims["jti"],
      credential_type: Atom.to_string(requested_credential_type),
      registration_type: "agent_provider"
    }
  end

  defp provider_value(provider, key) when is_map(provider) do
    Map.get(provider, key) || Map.get(provider, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(provider, key)
  end

  defp get_agent_registration_by_claim_token(claim_token, opts) do
    claim_token_hash = hash_agent_registration_secret(claim_token)
    preload = Keyword.get(opts, :preload, [])

    query =
      maybe_lock_query(
        from(r in AgentRegistration, where: r.claim_token_hash == ^claim_token_hash, preload: ^preload),
        opts
      )

    case Repo.one(query) do
      nil -> {:error, :invalid_claim_token}
      registration -> {:ok, registration}
    end
  end

  defp get_agent_registration_by_claim_view_token(claim_view_token, opts \\ []) do
    claim_view_token_hash = hash_agent_registration_secret(claim_view_token)

    query = maybe_lock_query(from(r in AgentRegistration, where: r.claim_view_token_hash == ^claim_view_token_hash), opts)

    case Repo.one(query) do
      nil -> {:error, :invalid_claim_token}
      registration -> {:ok, registration}
    end
  end

  defp maybe_lock_query(query, lock: "FOR UPDATE"), do: from(r in query, lock: "FOR UPDATE")
  defp maybe_lock_query(query, _opts), do: query

  defp maybe_expire_agent_registration(%AgentRegistration{status: :pending} = registration) do
    case registration
         |> AgentRegistration.expire_changeset()
         |> Repo.update() do
      {:ok, expired_registration} ->
        insert_agent_registration_event!(expired_registration, :expired, %{
          metadata: %{claim_attempt_id: expired_registration.claim_attempt_id},
          occurred_at: Time.utc_now()
        })

        {:ok, expired_registration}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp maybe_expire_agent_registration(_registration), do: {:ok, nil}

  defp agent_registration_claim_token_expired?(%AgentRegistration{claim_token_expires_at: claim_token_expires_at}) do
    DateTime.compare(claim_token_expires_at, Time.utc_now()) != :gt
  end

  defp agent_registration_otp_expired?(%AgentRegistration{otp_expires_at: otp_expires_at}) do
    DateTime.compare(otp_expires_at, Time.utc_now()) != :gt
  end

  defp build_agent_registration_claim_bundle do
    claim_token = prefixed_agent_registration_token("clm")
    claim_view_token = prefixed_agent_registration_token("clv")
    otp = derive_agent_registration_otp(claim_view_token)

    %{
      claim_token: claim_token,
      claim_token_hash: hash_agent_registration_secret(claim_token),
      claim_view_token: claim_view_token,
      claim_view_token_hash: hash_agent_registration_secret(claim_view_token),
      otp_hash: hash_agent_registration_secret(otp),
      claim_attempt_id: UUIDv7.generate()
    }
  end

  defp prefixed_agent_registration_token(prefix) do
    "#{prefix}_#{Tuist.Tokens.generate_token(24)}"
  end

  defp derive_agent_registration_otp(claim_view_token) do
    <<value::unsigned-integer-size(32), _::binary>> =
      :crypto.mac(:hmac, :sha256, Environment.secret_key_password(), claim_view_token)

    value
    |> rem(1_000_000)
    |> Integer.to_string()
    |> String.pad_leading(6, "0")
  end

  defp hash_agent_registration_secret(secret) when is_binary(secret) do
    :crypto.hash(:sha256, secret)
  end

  defp claim_agent_registration_credential(%AgentRegistration{registration_type: :anonymous} = registration, user) do
    account_token = Repo.get!(AccountToken, registration.account_token_id)

    {:ok, account_token} =
      account_token
      |> Changeset.change(account_id: user.account.id, created_by_account_id: user.account.id)
      |> Repo.update()

    {:ok,
     %{
       credential: nil,
       expires_at: account_token.expires_at,
       account_token_id: account_token.id,
       credential_jti: nil
     }}
  end

  defp claim_agent_registration_credential(%AgentRegistration{} = registration, user) do
    issue_agent_registration_credential(user, registration.requested_credential_type)
  end

  defp issue_agent_registration_credential(user, :access_token) do
    access_token_expires_at = DateTime.add(Time.utc_now(), @agent_registration_access_token_ttl_seconds, :second)

    {:ok, access_token, claims} =
      Tuist.Guardian.encode_and_sign(
        user.account,
        %{
          "type" => "account",
          "scopes" => @agent_registration_scopes,
          "all_projects" => true,
          "user_id" => user.id,
          "preferred_username" => user.account.name,
          "email" => user.email
        },
        token_type: "access_token",
        ttl: {@agent_registration_access_token_ttl_seconds, :second}
      )

    {:ok,
     %{
       credential: access_token,
       expires_at: access_token_expires_at,
       account_token_id: nil,
       credential_jti: claims["jti"]
     }}
  end

  defp issue_agent_registration_credential(user, :api_key) do
    {:ok, {account_token, api_key}} =
      create_account_token(%{
        account: user.account,
        created_by_account: user.account,
        scopes: @agent_registration_scopes,
        name: agent_registration_token_name(),
        all_projects: true
      })

    {:ok,
     %{
       credential: api_key,
       expires_at: account_token.expires_at,
       account_token_id: account_token.id,
       credential_jti: nil
     }}
  end

  defp create_anonymous_agent_registration_user do
    id = UUIDv7.generate()

    create_user(
      "agent-#{id}@agents.tuist.local",
      confirmed_at: NaiveDateTime.utc_now(),
      handle: "agent-#{String.slice(id, 0, 12)}"
    )
  end

  defp agent_registration_token_name do
    "agent-auth-#{String.slice(UUIDv7.generate(), 0, 12)}"
  end

  defp secure_compare_hash(left, right) when is_binary(left) and is_binary(right) do
    Plug.Crypto.secure_compare(left, right)
  end

  defp get_or_provision_agent_registration_user!(email) do
    case get_user_by_email(email) do
      {:ok, %User{} = user} ->
        maybe_confirm_agent_registration_user!(user)

      {:error, :not_found} ->
        case create_user(email, confirmed_at: NaiveDateTime.utc_now()) do
          {:ok, user} ->
            user

          {:error, :email_taken} ->
            {:ok, user} = get_user_by_email(email)
            maybe_confirm_agent_registration_user!(user)
        end
    end
  end

  defp maybe_confirm_agent_registration_user!(%User{confirmed_at: nil} = user) do
    {:ok, user} =
      user
      |> User.confirm_changeset()
      |> Repo.update()

    Repo.preload(user, :account)
  end

  defp maybe_confirm_agent_registration_user!(%User{} = user) do
    Repo.preload(user, :account)
  end

  defp insert_agent_registration_event!(%AgentRegistration{} = registration, event_type, attrs) do
    attrs
    |> Map.merge(%{
      agent_registration_id: registration.id,
      event_type: event_type,
      occurred_at: Map.get(attrs, :occurred_at, Time.utc_now())
    })
    |> AgentRegistrationEvent.create_changeset()
    |> Repo.insert!()
  end

  defp unwrap_repo_transaction({:ok, {:error, reason}}), do: {:error, reason}
  defp unwrap_repo_transaction({:ok, result}), do: {:ok, result}
  defp unwrap_repo_transaction({:error, reason}), do: {:error, reason}
end
