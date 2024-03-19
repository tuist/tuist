defmodule TuistCloud.Accounts.Organization do
  @moduledoc ~S"""
  A module that represents the organizations table.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "organizations" do
    timestamps(inserted_at: :created_at)
  end
end
