defmodule TuistCloud.Accounts.DeviceCode do
  @moduledoc """
  A module that represents the device code.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias TuistCloud.Accounts.User

  schema "device_codes" do
    field :code, :string
    field :authenticated, :boolean, default: false
    belongs_to :user, User
    timestamps(inserted_at: :created_at)
  end

  def create_changeset(device_code, attrs) do
    device_code
    |> cast(attrs, [:code, :created_at])
    |> validate_required([:code])
    |> unique_constraint([:code])
  end

  def authenticate_changeset(device_code, attrs) do
    device_code
    |> cast(attrs, [:authenticated, :user_id])
    |> validate_required([:authenticated, :user_id])
  end
end
