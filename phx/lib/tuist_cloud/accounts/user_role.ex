defmodule TuistCloud.Accounts.UserRole do
  @moduledoc ~S"""
  A module that represents the user_roles table.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{
          role_id: integer(),
          user_id: integer(),
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:role_id, :id, autogenerate: true}
  schema "users_roles" do
    field :user_id, :id

    timestamps(inserted_at: :created_at)
  end
end
