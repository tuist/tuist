defmodule Atlas.Users do
  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Repo
  alias Atlas.Users.User

  def get_user(id), do: Repo.get(User, id)

  def get_user_by_email(email), do: Repo.get_by(User, email: email)

  def list_users do
    from(user in User,
      order_by: [
        asc: fragment("case when ? = 'executive' then 0 else 1 end", user.role),
        asc: fragment("lower(coalesce(?, ''))", user.name),
        asc: fragment("lower(?)", user.email)
      ]
    )
    |> Repo.all()
  end

  def change_user_role(%User{} = user, attrs \\ %{}) do
    User.role_changeset(user, attrs)
  end

  def update_user_role(%User{} = user, attrs) do
    changeset = User.role_changeset(user, attrs)

    changeset
    |> Repo.update()
    |> tap(fn
      {:ok, updated_user} ->
        Audit.record("user.role_updated", %{
          target_type: "user",
          target_id: updated_user.id,
          target_label: updated_user.email,
          metadata: %{"changed" => Audit.changeset_changes(changeset)}
        })

      _result ->
        :ok
    end)
  end

  def executive?(%User{role: :executive}), do: true
  def executive?(_user), do: false

  def find_or_create_user_from_auth(%Ueberauth.Auth{} = auth) do
    email = auth.info.email

    if allowed_email?(email) do
      case Repo.get_by(User, email: email) do
        nil ->
          %User{}
          |> User.changeset(%{
            email: email,
            name: auth.info.name
          })
          |> Repo.insert()

        user ->
          user
          |> User.changeset(%{
            name: auth.info.name
          })
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
end
