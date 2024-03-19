defmodule TuistCloud.Accounts.User do
  @moduledoc ~S"""
  A module that represents the user table.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          token: String.t()
        }

  schema "users" do
    field :token, :string
    field :email, :string

    timestamps(inserted_at: :created_at)
  end

  def create_user_changeset(user, attrs) do
    user
    |> cast(attrs, [:token, :email])
    |> validate_required([:token, :email])
    |> unique_constraint(:token)
    |> unique_constraint(:email)
  end
end
