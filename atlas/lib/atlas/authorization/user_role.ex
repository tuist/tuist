defmodule Atlas.Authorization.UserRole do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Authorization.Role
  alias Atlas.Users.User

  @primary_key false
  schema "user_roles" do
    belongs_to :user, User, primary_key: true
    belongs_to :role, Role, primary_key: true

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(user_role, attrs) do
    user_role
    |> cast(attrs, [:user_id, :role_id])
    |> validate_required([:user_id, :role_id])
    |> unique_constraint([:user_id, :role_id], name: :user_roles_pkey)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:role_id)
  end
end
