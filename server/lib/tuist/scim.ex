defmodule Tuist.SCIM do
  @moduledoc """
  SCIM 2.0 (RFC 7643/7644) provisioning context.

  Exposes inbound user and group provisioning from external Identity Providers
  (Okta, Azure AD/Entra, JumpCloud, etc.) into Tuist organizations. Each
  organization issues its own bearer token (`Tuist.Accounts.AccountToken` with
  the `account:scim:write` scope) which the IdP uses to authenticate against
  the SCIM endpoints under `/scim/v2/`.

  Users are deduplicated by email. Provisioning creates new users by email, or
  updates the organization role for users who are already members of the calling
  organization. Existing users from other organizations are not claimed.

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
  alias Tuist.SCIM.Filter

  require Logger

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

  If a user with this email already exists in the organization, their role is
  updated. If the email belongs to a user outside the organization, the request
  is rejected instead of claiming the account.
  """
  def provision_user(%Organization{} = organization, attrs) do
    email = attrs |> Map.fetch!(:user_name) |> String.downcase()
    role = attrs |> Map.get(:role, :user) |> normalize_role()
    active = Map.get(attrs, :active, true)

    fn ->
      user =
        case provisionable_user(organization, email) do
          {:ok, %User{} = user} -> user
          {:error, reason} -> Repo.rollback(reason)
        end

      if active do
        :ok = Accounts.add_user_to_organization(user, organization, role: role)

        case update_user_role_if_needed(user, organization, role) do
          {:ok, _} -> user
          {:error, reason} -> Repo.rollback(reason)
        end
      else
        :ok = remove_user_role_from_organization(user, organization)
        %{user | active: false}
      end
    end
    |> Repo.transaction()
    |> case do
      {:ok, user} -> {:ok, Repo.preload(user, :account)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp provisionable_user(%Organization{} = organization, email) do
    case Accounts.get_user_by_email(email) do
      {:ok, %User{} = user} ->
        if Accounts.belongs_to_organization?(user, organization) do
          {:ok, user}
        else
          {:error, :email_taken}
        end

      {:error, :not_found} ->
        case Accounts.create_user(email, confirmed_at: default_confirmed_at()) do
          {:ok, user} -> {:ok, user}
          {:error, changeset} -> if email_taken?(changeset), do: {:error, :email_taken}, else: {:error, changeset}
        end
    end
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
      {:ok, %{updated_user | active: false}}
    end
  end

  defp apply_attrs(%User{} = user, organization, attrs) do
    Multi.new()
    |> maybe_update_email(user, attrs)
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
      Multi.update(multi, :email, User.email_changeset(user, %{email: downcased}))
    end
  end

  defp maybe_update_email(multi, _user, _attrs), do: multi

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
  defp put_patch_attr("replace", "username", value, acc) when is_binary(value), do: Map.put(acc, :user_name, value)

  defp put_patch_attr(op, "roles", value, acc) when op in ["add", "replace"] do
    case extract_role(value) do
      nil -> acc
      role -> Map.put(acc, :role, role)
    end
  end

  defp put_patch_attr(_op, _path, _value, acc), do: acc

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
          remove_member(organization, user_id)
        end)

      op_name == "replace" and path in ["members", nil] ->
        target_users =
          value
          |> extract_member_ids()
          |> Enum.flat_map(fn user_id ->
            case get_user(organization, user_id) do
              {:ok, user} -> [user]
              {:error, :not_found} -> []
            end
          end)

        Enum.each(Accounts.get_organization_members(organization, role), fn u ->
          remove_member(organization, u.id)
        end)

        Enum.each(target_users, fn user ->
          add_member_user(organization, user, role)
        end)

      true ->
        :ok
    end
  end

  defp apply_group_op(organization, _role, %{"op" => op_name, "path" => path}) when is_binary(op_name) do
    if String.downcase(op_name) == "remove" do
      Enum.each(Filter.member_ids_from_path(path), fn user_id ->
        remove_member(organization, user_id)
      end)
    end
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

  defp remove_member(organization, user_id) do
    case get_user(organization, user_id) do
      {:ok, %User{} = user} -> remove_user_role_from_organization(user, organization)
      {:error, :not_found} -> :ok
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
