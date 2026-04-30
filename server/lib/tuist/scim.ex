defmodule Tuist.SCIM do
  @moduledoc """
  SCIM 2.0 (RFC 7643/7644) provisioning context.

  Exposes inbound user and group provisioning from external Identity Providers
  (Okta, Azure AD/Entra, JumpCloud, etc.) into Tuist organizations. Each
  organization issues its own bearer token (`Tuist.Accounts.AccountToken` with
  the `account:scim:write` scope) which the IdP uses to authenticate against
  the SCIM endpoints under `/scim/v2/`.

  Users are deduplicated by email. Provisioning a user that already exists in
  Tuist adds them to the calling organization with the requested role; it does
  not overwrite their account.

  Groups are synthetic: each organization exposes exactly two groups, "Admins"
  and "Users", which mirror the existing role hierarchy. Group membership ops
  (PATCH) translate into role assignments on the organization.
  """
  import Ecto.Query

  alias Ecto.Multi
  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.AccountToken
  alias Tuist.Accounts.Organization
  alias Tuist.Accounts.Role
  alias Tuist.Accounts.User
  alias Tuist.Accounts.UserRole
  alias Tuist.Base64
  alias Tuist.Environment
  alias Tuist.Repo

  @group_admins "admins"
  @group_users "users"

  ## Tokens

  @doc """
  Issues a new SCIM bearer token for an organization. Returns `{:ok, {token,
  plaintext}}`. The plaintext is shown to the user once and never persisted.
  """
  def create_token(%Organization{} = organization, attrs \\ %{}) do
    account = organization_account(organization)
    raw = Base64.encode(:crypto.strong_rand_bytes(24))
    encrypted = Bcrypt.hash_pwd_salt(raw <> Environment.secret_key_password())

    case %AccountToken{}
         |> Ecto.Changeset.change(%{
           account_id: account.id,
           encrypted_token_hash: encrypted,
           scopes: [AccountToken.scim_scope()],
           name: Map.get(attrs, :name),
           all_projects: false
         })
         |> Ecto.Changeset.validate_required([:account_id, :encrypted_token_hash, :scopes, :name])
         |> Ecto.Changeset.validate_length(:name, max: 64)
         |> Ecto.Changeset.unique_constraint([:account_id, :encrypted_token_hash])
         |> Ecto.Changeset.unique_constraint([:account_id, :name], name: "account_tokens_account_id_name_index")
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
    with {:ok, %AccountToken{} = token} <-
           plaintext |> account_token_plaintext() |> Accounts.account_token(preload: [account: :organization]),
         true <- scim_token?(token),
         %Account{organization: %Organization{} = organization} <- token.account do
      {:ok, Repo.preload(organization, :account), token}
    else
      _ -> {:error, :invalid_token}
    end
  end

  def authenticate_token(_), do: {:error, :invalid_token}

  defp account_token_plaintext(plaintext) do
    case String.split(plaintext, "_", parts: 4) do
      ["tuist", "scim", token_id, raw] -> "tuist_#{token_id}_#{raw}"
      _ -> plaintext
    end
  end

  defp scim_token?(%AccountToken{scopes: scopes}), do: AccountToken.scim_scope() in scopes

  defp organization_account(%Organization{account: %Account{} = account}), do: account
  defp organization_account(%Organization{} = organization), do: Repo.preload(organization, :account).account

  @doc """
  Best-effort touch of `last_used_at`. Failures are swallowed.
  """
  def touch_token(%AccountToken{} = token) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    Repo.update_all(from(t in AccountToken, where: t.id == ^token.id), set: [last_used_at: now])
  rescue
    _ -> :ok
  end

  ## Users

  def list_users(%Organization{} = organization, opts \\ []) do
    filter = Keyword.get(opts, :filter)
    start_index = max(Keyword.get(opts, :start_index, 1), 1)
    count = opts |> Keyword.get(:count, 100) |> min(200) |> max(0)

    base = members_query(organization)

    base =
      case filter do
        %{attribute: "userName", op: :eq, value: value} ->
          downcased = String.downcase(value)
          from u in base, where: u.email == ^downcased

        %{attribute: "externalId", op: :eq, value: value} ->
          from u in base, where: u.email == ^String.downcase(value) or u.token == ^value

        nil ->
          base

        _other ->
          base
      end

    total =
      Repo.one(from u in subquery(from(u in base, select: %{id: u.id})), select: count(u.id))

    users =
      from(u in base,
        order_by: u.id,
        offset: ^(start_index - 1),
        limit: ^count
      )
      |> Repo.all()
      |> Repo.preload(:account)

    %{total: total, users: users, start_index: start_index, count: length(users)}
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

  If a user with this email already exists, they are added to the organization
  with the requested role (idempotent if already a member). Otherwise a new
  user account is created and added.
  """
  def provision_user(%Organization{} = organization, attrs) do
    email = attrs |> Map.fetch!(:user_name) |> String.downcase()
    role = attrs |> Map.get(:role, :user) |> normalize_role()
    active = Map.get(attrs, :active, true)

    case Accounts.get_user_by_email(email) do
      {:ok, %User{} = user} ->
        with :ok <- Accounts.add_user_to_organization(user, organization, role: role),
             {:ok, _} <- update_user_role_if_needed(user, organization, role),
             {:ok, user} <- set_active(user, active) do
          {:ok, Repo.preload(user, :account)}
        end

      {:error, :not_found} ->
        with {:ok, user} <- Accounts.create_user(email, confirmed_at: default_confirmed_at()),
             :ok <- Accounts.add_user_to_organization(user, organization, role: role),
             {:ok, user} <- set_active(user, active) do
          {:ok, Repo.preload(user, :account)}
        end
    end
  end

  defp default_confirmed_at do
    NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
  end

  defp update_user_role_if_needed(user, organization, role) do
    case Accounts.get_user_role_in_organization(user, organization) do
      %{name: name} when name in ["admin", "user"] ->
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

  defp apply_attrs(%User{} = user, organization, %{active: false} = attrs) do
    with {:ok, updated_user} <- apply_attrs(user, organization, Map.delete(attrs, :active)),
         :ok <- remove_user_role_from_organization(updated_user, organization) do
      set_active(updated_user, false)
    end
  end

  defp apply_attrs(%User{} = user, organization, attrs) do
    Multi.new()
    |> maybe_update_email(user, attrs)
    |> maybe_update_active(user, attrs)
    |> maybe_update_role(user, organization, attrs)
    |> Repo.transaction()
    |> case do
      {:ok, _changes} ->
        {:ok, user |> Repo.reload!() |> Repo.preload(:account)}

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  defp maybe_update_email(multi, user, %{user_name: new_email}) when is_binary(new_email) do
    downcased = String.downcase(new_email)

    if downcased == user.email do
      multi
    else
      Multi.update(multi, :email, Ecto.Changeset.change(user, email: downcased))
    end
  end

  defp maybe_update_email(multi, _user, _attrs), do: multi

  defp maybe_update_active(multi, user, %{active: active}) when is_boolean(active) and active != user.active do
    Multi.update(multi, :active, User.active_changeset(user, active))
  end

  defp maybe_update_active(multi, _user, _attrs), do: multi

  defp maybe_update_role(multi, user, organization, %{role: role}) when role in [:admin, :user] do
    Multi.run(multi, :role, fn _repo, _ ->
      :ok = Accounts.add_user_to_organization(user, organization, role: role)

      case Accounts.update_user_role_in_organization(user, organization, role) do
        {:ok, _} -> {:ok, :ok}
        {:error, :not_found} -> {:ok, :ok}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp maybe_update_role(multi, _user, _organization, _attrs), do: multi

  defp ops_to_attrs([], acc), do: acc

  defp ops_to_attrs([op | rest], acc) do
    acc =
      case normalize_op(op) do
        {:replace, "active", value} when is_boolean(value) ->
          Map.put(acc, :active, value)

        {:replace, "username", value} when is_binary(value) ->
          Map.put(acc, :user_name, value)

        {op, "roles", value} when op in [:add, :replace] ->
          case extract_role(value) do
            nil -> acc
            role -> Map.put(acc, :role, role)
          end

        _ ->
          acc
      end

    ops_to_attrs(rest, acc)
  end

  defp normalize_op(%{"op" => op, "path" => path, "value" => value}) when is_binary(op) and is_binary(path) do
    case safe_atom(String.downcase(op)) do
      :invalid -> :invalid
      atom -> {atom, String.downcase(path), value}
    end
  end

  defp normalize_op(%{"op" => op, "value" => value}) when is_binary(op) and is_map(value) do
    op_atom = safe_atom(String.downcase(op))

    cond do
      op_atom == :invalid ->
        :invalid

      Map.has_key?(value, "active") ->
        {op_atom, "active", Map.get(value, "active")}

      Map.has_key?(value, "userName") ->
        {op_atom, "username", Map.get(value, "userName")}

      true ->
        :invalid
    end
  end

  defp normalize_op(_), do: :invalid

  defp safe_atom("add"), do: :add
  defp safe_atom("replace"), do: :replace
  defp safe_atom("remove"), do: :remove
  defp safe_atom(_), do: :invalid

  defp extract_role(value) when is_binary(value), do: normalize_role_string(value)
  defp extract_role([%{"value" => v} | _]) when is_binary(v), do: normalize_role_string(v)
  defp extract_role([v | _]) when is_binary(v), do: normalize_role_string(v)
  defp extract_role(%{"value" => v}) when is_binary(v), do: normalize_role_string(v)
  defp extract_role(_), do: nil

  defp normalize_role_string(s) do
    case String.downcase(s) do
      "admin" -> :admin
      "admins" -> :admin
      "user" -> :user
      "users" -> :user
      _ -> nil
    end
  end

  defp normalize_role(:admin), do: :admin
  defp normalize_role(:user), do: :user
  defp normalize_role(other) when is_binary(other), do: normalize_role_string(other) || :user
  defp normalize_role(_), do: :user

  @doc """
  Soft-deactivates a user via SCIM `DELETE /Users/:id`. Sets `active: false`
  and removes their role in the organization.
  """
  def deactivate_user(%Organization{} = organization, user_id) do
    with {:ok, user} <- get_user(organization, user_id) do
      :ok = remove_user_role_from_organization(user, organization)
      set_active(user, false)
    end
  end

  defp set_active(%User{active: same} = user, same), do: {:ok, user}

  defp set_active(%User{} = user, active) do
    user |> User.active_changeset(active) |> Repo.update()
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
    [build_group(organization, :admin), build_group(organization, :user)]
  end

  def get_group(%Organization{} = organization, @group_admins), do: {:ok, build_group(organization, :admin)}
  def get_group(%Organization{} = organization, @group_users), do: {:ok, build_group(organization, :user)}
  def get_group(_organization, _id), do: {:error, :not_found}

  defp build_group(%Organization{} = organization, role) do
    members = Accounts.get_organization_members(organization, role)

    handle =
      case organization do
        %Organization{account: %Account{name: name}} -> name
        _ -> Repo.preload(organization, :account).account.name
      end

    %{
      id: group_id(role),
      display_name: "#{handle} #{group_label(role)}",
      members: members
    }
  end

  defp group_id(:admin), do: @group_admins
  defp group_id(:user), do: @group_users
  defp group_label(:admin), do: "Admins"
  defp group_label(:user), do: "Users"

  def patch_group(%Organization{} = organization, group_id, ops) when group_id in [@group_admins, @group_users] do
    role = if group_id == @group_admins, do: :admin, else: :user

    Enum.each(ops, fn op -> apply_group_op(organization, role, op) end)
    get_group(organization, group_id)
  end

  def patch_group(_org, _id, _ops), do: {:error, :not_found}

  defp apply_group_op(organization, role, %{"op" => op_str, "value" => value} = op) do
    op_atom = safe_atom(String.downcase(op_str))
    path = Map.get(op, "path")

    cond do
      op_atom == :add ->
        Enum.each(extract_member_ids(value), fn user_id ->
          add_member(organization, user_id, role)
        end)

      op_atom == :remove ->
        ids = member_ids_from_path(path) ++ extract_member_ids(value)

        Enum.each(ids, fn user_id ->
          remove_member(organization, user_id)
        end)

      op_atom == :replace and path in ["members", nil] ->
        Enum.each(Accounts.get_organization_members(organization, role), fn u ->
          remove_member(organization, u.id)
        end)

        Enum.each(extract_member_ids(value), fn user_id ->
          add_member(organization, user_id, role)
        end)

      true ->
        :ok
    end
  end

  defp apply_group_op(organization, _role, %{"op" => "remove", "path" => path}) do
    Enum.each(member_ids_from_path(path), fn user_id ->
      remove_member(organization, user_id)
    end)
  end

  defp apply_group_op(_organization, _role, _op), do: :ok

  defp extract_member_ids(values) when is_list(values) do
    Enum.flat_map(values, fn
      %{"value" => v} when is_binary(v) -> [v]
      v when is_binary(v) -> [v]
      _ -> []
    end)
  end

  defp extract_member_ids(%{"value" => v}) when is_binary(v), do: [v]
  defp extract_member_ids(_), do: []

  # Parses Okta-style `members[value eq "user-id"]` filters.
  defp member_ids_from_path(path) when is_binary(path) do
    ~r/value\s+eq\s+"([^"]+)"/i
    |> Regex.scan(path)
    |> Enum.map(fn [_, id] -> id end)
  end

  defp member_ids_from_path(_), do: []

  defp add_member(organization, user_id, role) do
    case Accounts.get_user_by_id(user_id) do
      %User{} = user ->
        :ok = Accounts.add_user_to_organization(user, organization, role: role)
        Accounts.update_user_role_in_organization(user, organization, role)

      _ ->
        :ok
    end
  end

  defp remove_member(organization, user_id) do
    case Accounts.get_user_by_id(user_id) do
      %User{} = user -> remove_user_role_from_organization(user, organization)
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
