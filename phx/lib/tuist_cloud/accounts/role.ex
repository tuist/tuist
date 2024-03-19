defmodule TuistCloud.Accounts.Role do
  @moduledoc ~S"""
  A module that represents the roles table.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{
          name: String.t(),
          resource_type: String.t(),
          resource_id: integer(),
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "roles" do
    field :name, :string
    field :resource_type, :string
    field :resource_id, :integer
    timestamps(inserted_at: :created_at)
  end
end
