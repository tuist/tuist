defmodule Tuist.SCIM do
  @moduledoc """
  SCIM 2.0 (RFC 7643/7644) provisioning context.

  Exposes inbound user and group provisioning from external Identity Providers
  (Okta, Azure AD/Entra, JumpCloud, etc.) into Tuist organizations. Each
  organization issues its own bearer token (`Tuist.Accounts.AccountToken` with
  the `account:scim:write` scope) which the IdP uses to authenticate against
  the SCIM endpoints under `/scim/v2/`.

  Users are deduplicated by email. Provisioning creates new users by email,
  updates the organization role for users who are already members of the
  calling organization, and attaches existing Tuist users to the organization
  when SCIM POSTs an email that already exists globally. Attached users
  receive an email notification so they can audit/leave if unexpected.

  A provisioning request that names a recognized role gets that role, including
  explicit downgrades. Without a recognized role, existing members keep their
  stored role and new memberships get the organization's configured SSO
  enrollment role.

  Groups are synthetic: each organization exposes one group per organization
  role, "Tuist Admins", "Tuist Users", and "Tuist Viewers", which mirror the
  existing role hierarchy. Adding a member to a group assigns that role.
  Removing a member from the group matching their current role moves them back
  to the enrollment role rather than out of the organization.
  """
  import Ecto.Query

  alias Ecto.Multi
  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.AccountToken
  alias Tuist.Accounts.AgentRegistration
  alias Tuist.Accounts.Oauth2Identity
  alias Tuist.Accounts.Organization
  alias Tuist.Accounts.Role
  alias Tuist.Accounts.SSOLoginDomainTrust
  alias Tuist.Accounts.User
  alias Tuist.Accounts.UserRole
  alias Tuist.Base64
  alias Tuist.Environment
  alias Tuist.Repo
  alias Tuist.SCIM.Filter
  alias Tuist.SCIM.Workers.AttachmentNotifierWorker

  require Logger

  @group_admins "admins"
  @group_users "users"
  @group_viewers "viewers"

  @groups %{@group_admins => :admin, @group_users => :user, @group_viewers => :viewer}

  @role_precedence [:admin, :user, :viewer]

  ## Tokens

  @doc """
  Issues a new SCIM bearer token for an organization. Returns `{:ok, {token,
  plaintext}}`. The plaintext is shown to the user once and never persisted.
  """
  def create_token(%Organization{} = organization, attrs \\ %{}) do
    account = organization_account(organization)
    raw = Base64.encode(:crypto.strong_rand_bytes(24))
    encrypted = Bcrypt.hash_pwd_salt(scim_token_secret(raw))

    case %{
           account_id: account.id,
           encrypted_token_hash: encrypted,
           scopes: [AccountToken.scim_scope()],
           name: Map.get(attrs, :name),
           all_projects: false
         }
         |> AccountToken.scim_changeset()
         |> Repo.insert() do
      {:ok, token} -> {:ok, {token, "tuist_scim_#{token.id}_#{raw}"}}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def list_tokens(%Organization{} = organization) do
    account = organization_account(organization)
    scope = AccountToken.scim_scope()

    Repo.all(
      from t in AccountToken,
        where: t.account_id == ^account.id and ^scope in t.scopes,
        order_by: [desc: t.inserted_at]
    )
  end

  def revoke_token(%AccountToken{} = token), do: Repo.delete(token)

  def revoke_token(%Organization{} = organization, token_id) when is_binary(token_id) do
    account = organization_account(organization)
    scope = AccountToken.scim_scope()

    with {:ok, _} <- UUIDv7.cast(token_id),
         %AccountToken{} = token <-
           Repo.one(
             from t in AccountToken,
               where: t.id == ^token_id and t.account_id == ^account.id and ^scope in t.scopes
           ) do
      Repo.delete(token)
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Looks up the organization that owns the given plaintext bearer token.
  """
  def authenticate_token(plaintext) when is_binary(plaintext) do
    scope = AccountToken.scim_scope()

    with {:ok, token_id, raw} <- parse_scim_token(plaintext),
         {:ok, _} <- UUIDv7.cast(token_id),
         %AccountToken{} = token <-
           Repo.one(
             from t in AccountToken,
               where: t.id == ^token_id and ^scope in t.scopes,
               preload: [account: :organization]
           ),
         false <- Accounts.account_token_expired?(token),
         true <- verify_scim_token(token, raw),
         %Account{organization: %Organization{} = organization} <- token.account do
      {:ok, Repo.preload(organization, :account), token}
    else
      _ -> {:error, :invalid_token}
    end
  end

  def authenticate_token(_), do: {:error, :invalid_token}

  defp parse_scim_token(plaintext) do
    case String.split(plaintext, "_", parts: 4) do
      ["tuist", "scim", token_id, raw] -> {:ok, token_id, raw}
      _ -> {:error, :invalid_token}
    end
  end

  defp verify_scim_token(%AccountToken{} = token, raw) do
    Bcrypt.verify_pass(scim_token_secret(raw), token.encrypted_token_hash)
  end

  defp scim_token_secret(raw), do: "scim:" <> raw <> Environment.secret_key_password()

  defp organization_account(%Organization{account: %Account{} = account}), do: account
  defp organization_account(%Organization{} = organization), do: Repo.preload(organization, :account).account

  @doc """
  Best-effort touch of `last_used_at`. Failures are logged without blocking the request.
  """
  def touch_token(%AccountToken{} = token) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    Repo.update_all(from(t in AccountToken, where: t.id == ^token.id), set: [last_used_at: now])
  rescue
    exception ->
      Logger.warning("Failed to touch SCIM token last_used_at: #{Exception.message(exception)}")

      :ok
  end

  ## Users

  def list_users(%Organization{} = organization, opts \\ []) do
    filter = Keyword.get(opts, :filter)
    start_index = max(Keyword.get(opts, :start_index, 1), 1)
    count = opts |> Keyword.get(:count, 100) |> min(200) |> max(0)

    base = members_query(organization)

    filtered =
      case filter do
        %{attribute: "userName", op: :eq, value: value} ->
          downcased = String.downcase(value)
          from u in base, where: u.email == ^downcased

        %{attribute: "externalId", op: :eq, value: value} ->
          from u in base, where: u.email == ^String.downcase(value) or u.token == ^value

        nil ->
          base

        _other ->
          {:error, :unsupported_filter}
      end

    with %Ecto.Query{} = query <- filtered do
      total =
        Repo.one(from u in subquery(from(u in query, select: %{id: u.id})), select: count(u.id))

      users =
        from(u in query,
          order_by: u.id,
          offset: ^(start_index - 1),
          limit: ^count
        )
        |> Repo.all()
        |> Repo.preload(:account)

      {:ok, %{total: total, users: users, start_index: start_index, count: length(users)}}
    end
  end

  defp members_query(%Organization{id: organization_id}) do
    from u in User,
      join: ur in "users_roles",
      on: ur.user_id == u.id,
      join: r in "roles",
      on: r.id == ur.role_id and r.resource_type == "Organization" and r.resource_id == ^organization_id,
      distinct: u.id
  end

  def get_user(%Organization{} = organization, user_id) do
    case normalize_user_id(user_id) do
      {:ok, user_id} ->
        case Repo.one(from u in members_query(organization), where: u.id == ^user_id, preload: [:account]) do
          nil -> {:error, :not_found}
          user -> {:ok, user}
        end

      :error ->
        {:error, :not_found}
    end
  end

  @doc """
  Provisions a user from a SCIM `POST /Users` request.

  Behavior:
    * Email matches a member of the calling org → role updated only when a recognized role is supplied.
    * Email matches a Tuist user not yet in the org → attached and notified, unless another org's
      SCIM provisioned the account, which is refused with `{:error, :email_taken}`.
    * Email is unknown → a new Tuist user is created and attached.
    * Email is unknown and in a reserved domain (another organization's verified login domain, or the operator email domain on tuist.dev) → refused with `{:error, :reserved_email}`.
    * Email is unknown and in the operator email domain of a self-hosted instance that the org hasn't DNS-verified → refused with an `:email` changeset error.

  Attaching pre-existing users keeps SCIM POST idempotent and unblocks IdP-driven
  rollouts where members predate SSO. The notification email gives attached users
  visibility to leave if the membership is unexpected.
  """
  def provision_user(%Organization{} = organization, attrs) do
    email = attrs |> Map.fetch!(:user_name) |> String.downcase()
    role = attrs |> Map.get(:role) |> normalize_role()
    active = Map.get(attrs, :active, true)

    case Repo.transaction(fn -> apply_provision(organization, email, role, active) end) do
      {:ok, user} -> {:ok, Repo.preload(user, :account)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_provision(organization, email, role, active) do
    {user, provenance} =
      case provisionable_user(email, organization) do
        {:ok, %User{} = u, p} -> {u, p}
        {:error, reason} -> Repo.rollback(reason)
      end

    cond do
      active ->
        attach_active_user(user, organization, role, provenance)

      provenance == :existing and not Accounts.belongs_to_organization?(user, organization) ->
        # Refuse to "create" a SCIM resource we wouldn't be able to represent
        # afterwards: the controller would answer 201 + Location, but a
        # follow-up GET /Users/:id would 404 because we never created any
        # membership. PATCH is the right verb for deactivating someone who
        # is already a member; POST + active=false on a non-member is a bug.
        Repo.rollback(:email_taken)

      true ->
        :ok = remove_user_role_from_organization(user, organization)
        %{user | active: false}
    end
  end

  defp attach_active_user(user, organization, role, provenance) do
    # Serialize concurrent SCIM POSTs for the same (user, org). Without
    # this, two simultaneous Okta requests can both pass the membership
    # check below and both call add_user_to_organization/3, producing
    # duplicate (role, users_roles) grants — which then make every
    # subsequent Repo.one lookup in get_user_role_in_organization/2 raise
    # Ecto.MultipleResultsError. The lock is released at transaction end.
    lock_membership(user.id, organization.id)

    if provenance == :existing and not Accounts.belongs_to_organization?(user, organization) do
      enqueue_attachment_notification(user, organization)
    end

    :ok = Accounts.add_user_to_organization(user, organization, role: role || enrollment_role(organization))

    case update_user_role_if_needed(user, organization, role) do
      {:ok, _} -> user
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp lock_membership(user_id, organization_id) do
    Repo.query!("SELECT pg_advisory_xact_lock($1::integer, $2::integer)", [user_id, organization_id])
  end

  defp enqueue_attachment_notification(%User{id: user_id}, %Organization{id: organization_id}) do
    %{user_id: user_id, organization_id: organization_id}
    |> AttachmentNotifierWorker.new()
    |> Oban.insert!()
  end

  defp provisionable_user(email, %Organization{} = organization, opts \\ []) do
    retry_after_email_taken = Keyword.get(opts, :retry_after_email_taken, true)

    case Accounts.get_user_by_email(email) do
      {:ok, %User{} = user} ->
        # An account another organization's SCIM created stays that
        # organization's: attaching it would let this organization's provider
        # sign in to it.
        if user.provisioned_by_organization_id in [nil, organization.id] or
             Accounts.belongs_to_organization?(user, organization),
           do: {:ok, user, :existing},
           else: {:error, :email_taken}

      {:error, :not_found} ->
        cond do
          operator_email_refused?(organization, email) -> {:error, operator_email_error(%User{}, email)}
          reserved_email?(email, organization) -> {:error, :reserved_email}
          true -> create_provisioned_user(email, organization, retry_after_email_taken)
        end
    end
  end

  defp create_provisioned_user(email, organization, retry_after_email_taken) do
    # Recorded so the organization's identity provider can link the
    # account it created without a verified login email domain.
    case Accounts.create_user(email,
           confirmed_at: default_confirmed_at(),
           provisioned_by_organization_id: organization.id
         ) do
      {:ok, user} ->
        {:ok, user, :created}

      {:error, :email_taken} when retry_after_email_taken ->
        provisionable_user(email, organization, retry_after_email_taken: false)

      {:error, :email_taken} ->
        {:error, :email_taken}

      {:error, %Ecto.Changeset{} = changeset} ->
        if email_taken?(changeset), do: {:error, :email_taken}, else: {:error, changeset}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # An address in the operator domain makes its account a Tuist operator on
  # self-hosted instances, so an organization's IdP may assign one only after
  # the organization proved it owns that domain through DNS.
  defp operator_email_refused?(organization, email) do
    Accounts.operator_email_address?(email) and
      not (SSOLoginDomainTrust.trust(organization) == :dns_verified and
             SSOLoginDomainTrust.email_domain(email) == organization.sso_login_domain)
  end

  defp operator_email_error(user, email) do
    user
    |> Ecto.Changeset.change(email: email)
    |> Ecto.Changeset.add_error(:email, "is reserved for Tuist operators")
  end

  defp email_taken?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {:email, {_message, opts}} -> Keyword.get(opts, :constraint) == :unique
      _ -> false
    end)
  end

  defp default_confirmed_at do
    NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
  end

  defp update_user_role_if_needed(_user, _organization, nil), do: {:ok, :unchanged}

  defp update_user_role_if_needed(user, organization, role) do
    case Accounts.get_user_role_in_organization(user, organization) do
      %{name: name} when name in ["admin", "user", "viewer"] ->
        if to_string(role) == name do
          {:ok, :unchanged}
        else
          Accounts.update_user_role_in_organization(user, organization, role)
        end

      _ ->
        {:ok, :unchanged}
    end
  end

  def replace_user(%Organization{} = organization, user_id, attrs) do
    with {:ok, user} <- get_user(organization, user_id) do
      apply_attrs(user, organization, attrs)
    end
  end

  @doc """
  Applies a parsed list of SCIM PATCH ops to a user.
  """
  def patch_user(%Organization{} = organization, user_id, ops) when is_list(ops) do
    with {:ok, user} <- get_user(organization, user_id) do
      attrs = ops_to_attrs(ops, %{})
      apply_attrs(user, organization, attrs)
    end
  end

  # Deprovisioning goes through even when the rest of the request is refused,
  # so an unrelated rejected attribute never keeps someone's access.
  defp apply_attrs(%User{} = user, organization, %{active: false} = attrs) do
    result = apply_attrs(user, organization, Map.delete(attrs, :active))
    :ok = remove_user_role_from_organization(user, organization)

    with {:ok, updated_user} <- result do
      {:ok, %{updated_user | active: false}}
    end
  end

  defp apply_attrs(%User{} = user, organization, attrs) do
    Multi.new()
    |> maybe_update_email(user, organization, attrs)
    |> maybe_update_role(user, organization, attrs)
    |> Repo.transaction()
    |> case do
      {:ok, _changes} ->
        {:ok, user |> Repo.reload!() |> Repo.preload(:account)}

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  # Renaming an account sends its password resets to the new address, so an
  # organization may rename only accounts it still manages on its own (see
  # `managed_only_by?/2`). The new address is unproven until its owner confirms
  # it.
  defp maybe_update_email(multi, user, organization, %{user_name: new_email}) when is_binary(new_email) do
    downcased = String.downcase(new_email)

    if downcased == user.email do
      multi
    else
      Multi.run(multi, :email, fn repo, _changes ->
        # The row lock makes concurrent SCIM requests for the account check and
        # rename one at a time. A sign-in that proves the old address while the
        # rename commits records nothing (`Accounts.record_mailbox_proof/1`
        # checks the address it proved).
        locked = repo.one!(from(u in User, where: u.id == ^user.id, lock: "FOR UPDATE"))

        cond do
          not managed_only_by?(locked, organization) ->
            {:error, :email_not_managed}

          operator_email_refused?(organization, downcased) ->
            {:error, operator_email_error(locked, downcased)}

          reserved_email?(downcased, organization) ->
            {:error, :reserved_email}

          true ->
            locked
            |> User.email_changeset(%{email: downcased})
            |> Ecto.Changeset.put_change(:email_verified_at, nil)
            |> repo.update()
        end
      end)
    end
  end

  defp maybe_update_email(multi, _user, _organization, _attrs), do: multi

  # Addresses an identity provider never gets to assign: on tuist.dev, the
  # operator email domain, and a login domain another organization verified,
  # which that organization's SCIM would attach. On self-hosted instances,
  # `operator_email_refused?/2` covers the operator domain.
  defp reserved_email?(email, %Organization{id: organization_id}) do
    domain = SSOLoginDomainTrust.email_domain(email)

    (Environment.tuist_hosted?() and Accounts.operator_domain_email?(email)) or
      (is_binary(domain) and
         Repo.exists?(
           from(o in Organization,
             where:
               o.sso_login_domain == ^domain and not is_nil(o.sso_login_domain_verified_at) and
                 o.id != ^organization_id
           )
         ))
  end

  # The organization created the account, and nobody has claimed it outside the
  # organization since: no password, no sign-in identity other than the
  # organization's own provider, no agent registration, and no other
  # organization. Someone who proved the address some other way owns the
  # account even if the organization created it first.
  defp managed_only_by?(%User{id: user_id} = user, %Organization{id: organization_id} = organization) do
    organization_identity = {organization.sso_provider, organization.sso_organization_id}

    user.provisioned_by_organization_id == organization_id and not User.password_set?(user) and
      from(i in Oauth2Identity, where: i.user_id == ^user_id, select: {i.provider, i.provider_organization_id})
      |> Repo.all()
      |> Enum.all?(&(&1 == organization_identity)) and
      not Repo.exists?(from(r in AgentRegistration, where: r.claimed_by_user_id == ^user_id)) and
      Enum.all?(Accounts.get_user_organization_accounts(user), &(&1.organization.id == organization_id))
  end

  defp maybe_update_role(multi, user, organization, %{role: role}) when role in [:admin, :user, :viewer] do
    Multi.run(multi, :role, fn _repo, _ ->
      :ok = Accounts.add_user_to_organization(user, organization, role: role)

      case Accounts.update_user_role_in_organization(user, organization, role) do
        {:ok, _} -> {:ok, :ok}
        {:error, :not_found} -> {:ok, :ok}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp maybe_update_role(multi, user, organization, %{role: role} = attrs) when is_binary(role) do
    maybe_update_role(multi, user, organization, %{attrs | role: normalize_role_string(role)})
  end

  defp maybe_update_role(multi, _user, _organization, _attrs), do: multi

  defp ops_to_attrs([], acc), do: acc

  defp ops_to_attrs([%{"op" => op, "path" => path, "value" => value} | rest], acc)
       when is_binary(op) and is_binary(path) do
    ops_to_attrs(rest, put_patch_attr(String.downcase(op), String.downcase(path), value, acc))
  end

  defp ops_to_attrs([%{"op" => op, "value" => value} | rest], acc) when is_binary(op) and is_map(value) do
    op = String.downcase(op)

    acc =
      cond do
        op == "replace" and Map.has_key?(value, "active") ->
          put_patch_attr(op, "active", Map.get(value, "active"), acc)

        op == "replace" and Map.has_key?(value, "userName") ->
          put_patch_attr(op, "username", Map.get(value, "userName"), acc)

        true ->
          acc
      end

    ops_to_attrs(rest, acc)
  end

  defp ops_to_attrs([_op | rest], acc), do: ops_to_attrs(rest, acc)

  defp put_patch_attr("replace", "active", value, acc) when is_boolean(value), do: Map.put(acc, :active, value)

  defp put_patch_attr("replace", "active", value, acc) when is_binary(value) do
    case String.downcase(value) do
      "true" -> Map.put(acc, :active, true)
      "false" -> Map.put(acc, :active, false)
      _ -> acc
    end
  end

  defp put_patch_attr("replace", "username", value, acc) when is_binary(value), do: Map.put(acc, :user_name, value)

  defp put_patch_attr(op, "roles", value, acc) when op in ["add", "replace"] do
    case most_privileged_role(value) do
      nil -> acc
      role -> Map.put(acc, :role, role)
    end
  end

  defp put_patch_attr(_op, _path, _value, acc), do: acc

  @doc """
  Resolves a SCIM `roles` attribute to a single organization role.

  Identity providers can send every app role a user holds, and Tuist's roles
  nest, so the most privileged recognized value wins. Values this server does
  not recognize are ignored, and a value naming no recognized role resolves to
  `nil`.
  """
  def most_privileged_role(value) do
    recognized = value |> role_values() |> MapSet.new()

    Enum.find(@role_precedence, &MapSet.member?(recognized, &1))
  end

  defp role_values(values) when is_list(values), do: Enum.flat_map(values, &role_values/1)

  defp role_values(%{"value" => value}) when is_binary(value), do: role_values(value)

  defp role_values(value) when is_binary(value) do
    case value |> unwrap_app_role_assignment() |> normalize_role_string() do
      nil -> []
      role -> [role]
    end
  end

  defp role_values(_), do: []

  defp unwrap_app_role_assignment(value) do
    case JSON.decode(value) do
      {:ok, %{"value" => role}} when is_binary(role) -> role
      _ -> value
    end
  end

  defp normalize_role_string(s) do
    case String.downcase(s) do
      "admin" -> :admin
      "admins" -> :admin
      "user" -> :user
      "users" -> :user
      "viewer" -> :viewer
      "viewers" -> :viewer
      _ -> nil
    end
  end

  defp normalize_role(role) when role in [:admin, :user, :viewer], do: role
  defp normalize_role(role) when is_binary(role), do: normalize_role_string(role)
  defp normalize_role(_role), do: nil

  defp enrollment_role(%Organization{} = organization) do
    organization |> Accounts.sso_default_role() |> String.to_existing_atom()
  end

  @doc """
  Deprovisions a user via SCIM `DELETE /Users/:id` by removing their role in the organization.
  """
  def deactivate_user(%Organization{} = organization, user_id) do
    with {:ok, user} <- get_user(organization, user_id) do
      :ok = remove_user_role_from_organization(user, organization)
      {:ok, %{user | active: false}}
    end
  end

  defp remove_user_role_from_organization(%User{id: user_id}, %Organization{id: organization_id}) do
    case organization_role_membership(user_id, organization_id) do
      nil ->
        :ok

      %{user_role: user_role, role: role} ->
        {:ok, _} =
          Multi.new()
          |> Multi.delete(:user_role, user_role)
          |> Multi.delete(:role, role)
          |> Repo.transaction()

        :ok
    end
  end

  defp organization_role_membership(user_id, organization_id) do
    Repo.one(
      from ur in UserRole,
        join: r in Role,
        on: ur.role_id == r.id,
        where:
          ur.user_id == ^user_id and r.resource_type == "Organization" and
            r.resource_id == ^organization_id,
        select: %{user_role: ur, role: r}
    )
  end

  ## Groups

  def list_groups(%Organization{} = organization) do
    Enum.map([:admin, :user, :viewer], &build_group(organization, &1))
  end

  def get_group(%Organization{} = organization, group_id) when is_map_key(@groups, group_id) do
    {:ok, build_group(organization, Map.fetch!(@groups, group_id))}
  end

  def get_group(_organization, _id), do: {:error, :not_found}

  defp build_group(%Organization{} = organization, role) do
    %{
      id: group_id(role),
      display_name: "Tuist #{group_label(role)}",
      members: Accounts.get_organization_members(organization, role)
    }
  end

  defp group_id(:admin), do: @group_admins
  defp group_id(:user), do: @group_users
  defp group_id(:viewer), do: @group_viewers
  defp group_label(:admin), do: "Admins"
  defp group_label(:user), do: "Users"
  defp group_label(:viewer), do: "Viewers"

  def patch_group(%Organization{} = organization, group_id, ops) when is_map_key(@groups, group_id) do
    role = Map.fetch!(@groups, group_id)

    Enum.each(ops, fn op -> apply_group_op(organization, role, op) end)
    get_group(organization, group_id)
  end

  def patch_group(_org, _id, _ops), do: {:error, :not_found}

  defp apply_group_op(organization, role, %{"op" => op_str, "value" => value} = op) do
    op_name = String.downcase(op_str)
    path = Map.get(op, "path")

    cond do
      op_name == "add" ->
        Enum.each(extract_member_ids(value), fn user_id ->
          add_member(organization, user_id, role)
        end)

      op_name == "remove" ->
        ids = Filter.member_ids_from_path(path) ++ extract_member_ids(value)

        Enum.each(ids, fn user_id ->
          demote_member(organization, user_id, role)
        end)

      op_name == "replace" ->
        case replacement_member_ids(path, value) do
          {:ok, user_ids} -> replace_members(organization, role, user_ids)
          :error -> :ok
        end

      true ->
        :ok
    end
  end

  defp apply_group_op(organization, role, %{"op" => op_name, "path" => path}) when is_binary(op_name) do
    if String.downcase(op_name) == "remove" do
      Enum.each(Filter.member_ids_from_path(path), fn user_id ->
        demote_member(organization, user_id, role)
      end)
    end
  end

  defp apply_group_op(_organization, _role, _op), do: :ok

  # A path-less replace only targets members when its value carries them. Okta
  # renames a pushed group with `value: %{"displayName" => ...}` and no path,
  # and the group names are synthetic, so anything else is ignored.
  defp replacement_member_ids("members", value), do: {:ok, extract_member_ids(value)}
  defp replacement_member_ids(nil, value) when is_list(value), do: {:ok, extract_member_ids(value)}
  defp replacement_member_ids(nil, %{"members" => members}), do: {:ok, extract_member_ids(members)}
  defp replacement_member_ids(_path, _value), do: :error

  defp replace_members(organization, role, user_ids) do
    target_users =
      Enum.flat_map(user_ids, fn user_id ->
        case get_user(organization, user_id) do
          {:ok, user} -> [user]
          {:error, :not_found} -> []
        end
      end)

    target_user_ids = MapSet.new(target_users, & &1.id)

    organization
    |> Accounts.get_organization_members(role)
    |> Enum.reject(&MapSet.member?(target_user_ids, &1.id))
    |> Enum.each(&demote_member(organization, &1.id, role))

    Enum.each(target_users, fn user ->
      add_member_user(organization, user, role)
    end)
  end

  defp extract_member_ids(values) when is_list(values) do
    Enum.flat_map(values, fn
      %{"value" => v} when is_binary(v) -> [v]
      v when is_binary(v) -> [v]
      _ -> []
    end)
  end

  defp extract_member_ids(%{"value" => v}) when is_binary(v), do: [v]
  defp extract_member_ids(_), do: []

  defp add_member(organization, user_id, role) do
    case get_user(organization, user_id) do
      {:ok, %User{} = user} -> add_member_user(organization, user, role)
      {:error, :not_found} -> :ok
    end
  end

  defp add_member_user(organization, user, role) do
    :ok = Accounts.add_user_to_organization(user, organization, role: role)

    case Accounts.update_user_role_in_organization(user, organization, role) do
      {:ok, _} -> :ok
      {:error, :not_found} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Leaving a group revokes that group's role without ending the membership, so
  # a member the identity provider moves between groups keeps their access
  # whichever order the add and remove arrive in. Membership itself ends through
  # the user resource.
  defp demote_member(organization, user_id, role) do
    role_name = Atom.to_string(role)

    with {:ok, %User{} = user} <- get_user(organization, user_id),
         %Role{name: ^role_name} <- Accounts.get_user_role_in_organization(user, organization) do
      add_member_user(organization, user, enrollment_role(organization))
    else
      _ -> :ok
    end
  end

  defp normalize_user_id(user_id) when is_integer(user_id), do: {:ok, user_id}

  defp normalize_user_id(user_id) when is_binary(user_id) do
    case Integer.parse(user_id) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  defp normalize_user_id(_), do: :error
end
