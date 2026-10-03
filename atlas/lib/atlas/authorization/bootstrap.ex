defmodule Atlas.Authorization.Bootstrap do
  @moduledoc """
  Grants the first administrator role to an existing, explicitly selected user.

  This operation is only available to deployment operators. It never runs on
  sign-in and cannot be repeated after initialization, even if the administrator
  is subsequently removed.
  """

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Audit.Activity
  alias Atlas.Authorization.Role
  alias Atlas.Authorization.Roles
  alias Atlas.Authorization.UserRole
  alias Atlas.Repo
  alias Atlas.Users.User

  @lock_key 0x41544C4153424F4F
  @action "installation.administrator_bootstrapped"

  def run(email) when is_binary(email) do
    email = email |> String.trim() |> String.downcase()

    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock($1)", [@lock_key])

      if initialized?(), do: Repo.rollback(:already_initialized)

      user = find_user!(email)
      role = Roles.ensure_executive_role!()

      %UserRole{}
      |> UserRole.changeset(%{user_id: user.id, role_id: role.id})
      |> Repo.insert!()

      case Audit.log(@action, %{
             interface: "system",
             target_type: "user",
             target_id: user.id,
             target_label: user.email,
             metadata: %{"authorization" => "deployment_operator", "role_id" => role.id}
           }) do
        {:ok, _activity} -> user
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  def run(_email), do: {:error, :invalid_email}

  defp initialized? do
    executive_slug = Roles.executive_slug()

    Repo.exists?(from(activity in Activity, where: activity.action == ^@action)) or
      Repo.exists?(
        from(user_role in UserRole,
          join: role in Role,
          on: role.id == user_role.role_id,
          where: "admin:write" in role.scopes or role.slug == ^executive_slug
        )
      )
  end

  defp find_user!(email) do
    case Repo.all(from(user in User, where: fragment("lower(?)", user.email) == ^email, limit: 2, lock: "FOR UPDATE")) do
      [user] -> user
      [] -> Repo.rollback(:user_not_found)
      _users -> Repo.rollback(:ambiguous_email)
    end
  end
end
