defmodule Tuist.Accounts.UserRole do
  @moduledoc ~S"""
  A module that represents the user_roles table.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:role_id, :id, autogenerate: true}
  schema "users_roles" do
    belongs_to :user, Tuist.Accounts.User

    # credo:disable-for-next-line Credo.Checks.TimestampsType
    timestamps(inserted_at: :created_at)
  end

  def create_changeset(user_role, attrs) do
    user_role
    |> cast(attrs, [:user_id, :role_id])
    |> validate_required([:user_id, :role_id])
  end
end
