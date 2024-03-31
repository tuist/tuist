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
    field :encrypted_password, :string, default: ""
    field :confirmed_at, :naive_datetime

    timestamps(inserted_at: :created_at)
  end

  def create_user_changeset(user, attrs) do
    password_to_hash =
      "#{attrs |> Map.get(:password, "")}#{TuistCloud.Environment.secret_key_password()}"

    attrs = Map.put(attrs, :encrypted_password, Bcrypt.hash_pwd_salt(password_to_hash))

    user
    |> cast(attrs, [:token, :email, :encrypted_password, :confirmed_at])
    |> validate_required([:token, :email])
    |> unique_constraint(:token)
    |> unique_constraint(:email)
  end
end
