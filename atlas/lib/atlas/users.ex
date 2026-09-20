defmodule Atlas.Users do
  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Authorization.Roles
  alias Atlas.Repo
  alias Atlas.Users.User

  def get_user(id), do: Repo.get(User, id)

  def get_user_by_email(email), do: Repo.get_by(User, email: email)

  def list_users do
    from(user in User,
      order_by: [
        asc: fragment("lower(coalesce(?, ''))", user.name),
        asc: fragment("lower(?)", user.email)
      ]
    )
    |> Repo.all()
  end

  @doc """
  All scope strings currently granted to a user, expanded so that any
  `<area>:write` scope also grants `<area>:read`.
  """
  def scopes_for(%User{} = user), do: Roles.scopes_for_user(user)
  def scopes_for(_user), do: []

  @doc "True if the user carries the required scope, either directly or via a write override."
  def has_scope?(%User{} = user, scope) when is_binary(scope), do: Roles.has_scope?(user, scope)
  def has_scope?(_user, _scope), do: false

  @doc """
  Backwards-compatible predicate for legacy call sites: a user is considered an
  "administrator" of Atlas when they hold `admin:write`. New code should ask
  for the specific scope it needs via `has_scope?/2` instead.
  """
  def admin?(%User{} = user), do: has_scope?(user, "admin:write")
  def admin?(_user), do: false

  def find_or_create_user_from_auth(%Ueberauth.Auth{} = auth) do
    email = auth.info.email

    if allowed_email?(email) do
      case Repo.get_by(User, email: email) do
        nil ->
          %User{}
          |> User.changeset(%{email: email, name: auth.info.name})
          |> Repo.insert()

        user ->
          user
          |> User.changeset(%{name: auth.info.name})
          |> Repo.update()
      end
    else
      {:error, :unauthorized_domain}
    end
  end

  defp allowed_email?(email) when is_binary(email) do
    case Application.fetch_env!(:atlas, :allowed_email_domain) do
      nil -> true
      domain -> String.ends_with?(String.downcase(email), "@" <> String.downcase(domain))
    end
  end

  defp allowed_email?(_email), do: false

  def delete_user(%User{} = user) do
    user
    |> Repo.delete()
    |> tap(fn
      {:ok, deleted} ->
        Audit.record("user.deleted", %{
          target_type: "user",
          target_id: deleted.id,
          target_label: deleted.email
        })

      _ ->
        :ok
    end)
  end
end
