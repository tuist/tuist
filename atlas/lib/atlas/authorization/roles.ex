defmodule Atlas.Authorization.Roles do
  @moduledoc """
  Context for managing authorization roles and role assignments.
  """

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Authorization
  alias Atlas.Authorization.Role
  alias Atlas.Authorization.UserRole
  alias Atlas.Repo
  alias Atlas.Users.User

  @executive_slug "executive"
  @member_slug "member"
  @member_excluded_areas ~w(finance documents admin)

  def executive_slug, do: @executive_slug
  def member_slug, do: @member_slug

  def list_roles do
    from(role in Role, order_by: [desc: role.builtin, asc: fragment("lower(?)", role.name)])
    |> Repo.all()
  end

  def get_role(id), do: Repo.get(Role, id)

  def get_role_by_slug(slug), do: Repo.get_by(Role, slug: slug)

  def change_role(%Role{} = role, attrs \\ %{}), do: Role.changeset(role, attrs)

  def create_role(attrs) do
    %Role{}
    |> Role.changeset(attrs)
    |> Repo.insert()
    |> tap_audit("role.created")
  end

  def update_role(%Role{} = role, attrs) do
    role
    |> Role.changeset(attrs)
    |> Repo.update()
    |> tap_audit("role.updated")
  end

  def delete_role(%Role{builtin: true}), do: {:error, :builtin_role}

  def delete_role(%Role{} = role) do
    role
    |> Repo.delete()
    |> tap_audit("role.deleted")
  end

  def list_roles_for_user(%User{id: user_id}) do
    from(role in Role,
      join: user_role in UserRole,
      on: user_role.role_id == role.id,
      where: user_role.user_id == ^user_id,
      order_by: [asc: fragment("lower(?)", role.name)]
    )
    |> Repo.all()
  end

  def scopes_for_user(%User{} = user) do
    user
    |> list_roles_for_user()
    |> Enum.flat_map(& &1.scopes)
    |> Authorization.expand()
  end

  def has_scope?(%User{} = user, scope) when is_binary(scope) do
    scope in scopes_for_user(user)
  end

  def has_scope?(_user, _scope), do: false

  def set_user_roles(%User{} = user, role_ids) when is_list(role_ids) do
    Repo.transaction(fn ->
      previous_ids = user |> list_roles_for_user() |> Enum.map(& &1.id) |> Enum.sort()
      requested_ids = role_ids |> Enum.uniq() |> Enum.sort()

      Repo.delete_all(from(ur in UserRole, where: ur.user_id == ^user.id))

      Enum.each(requested_ids, fn role_id ->
        %UserRole{}
        |> UserRole.changeset(%{user_id: user.id, role_id: role_id})
        |> Repo.insert!()
      end)

      Audit.record("user.roles_updated", %{
        target_type: "user",
        target_id: user.id,
        target_label: user.email,
        metadata: %{"previous" => previous_ids, "current" => requested_ids}
      })

      requested_ids
    end)
  end

  @doc """
  Ensure the seeded `executive` role exists and carries every scope. Used both
  by the roles migration and as a safety net at boot.
  """
  def ensure_executive_role! do
    scopes = Authorization.executive_scopes()

    case get_role_by_slug(@executive_slug) do
      nil ->
        {:ok, role} =
          create_role(%{
            name: "Executive",
            slug: @executive_slug,
            description: "Grants every scope, including admin access.",
            scopes: scopes,
            builtin: true
          })

        role

      %Role{} = role ->
        {:ok, updated} = update_role(role, %{scopes: scopes, builtin: true})
        updated
    end
  end

  @doc """
  Ensure the seeded `member` role exists. It carries every scope except those
  in `@member_excluded_areas` (currently `finance` and `documents`, which hold
  payroll and other sensitive material).
  """
  def ensure_member_role! do
    scopes =
      Authorization.all_scopes()
      |> Enum.reject(fn scope ->
        case Authorization.parse(scope) do
          {:ok, area, _action} -> area in @member_excluded_areas
          :error -> true
        end
      end)

    case get_role_by_slug(@member_slug) do
      nil ->
        {:ok, role} =
          create_role(%{
            name: "Member",
            slug: @member_slug,
            description: "Grants every scope except finance and documents (payroll).",
            scopes: scopes,
            builtin: true
          })

        role

      %Role{} = role ->
        {:ok, updated} = update_role(role, %{scopes: scopes, builtin: true})
        updated
    end
  end

  defp tap_audit({:ok, %Role{} = role} = result, action) do
    Audit.record(action, %{
      target_type: "role",
      target_id: role.id,
      target_label: role.slug,
      metadata: %{"scopes" => role.scopes}
    })

    result
  end

  defp tap_audit(other, _action), do: other
end
