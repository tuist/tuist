defmodule Tuist.Accounts.DeviceCode do
  @moduledoc """
  A module that represents the device code.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.User

  schema "device_codes" do
    field :code, :string
    field :authenticated, :boolean, default: false
    # The single sign-on the approving browser session proved (see
    # `Tuist.Accounts.UserToken.sso_claims/1`).
    field :auth_provider, :string
    field :auth_provider_organization_id, :string
    field :auth_organization_id, :id
    belongs_to :user, User
    # credo:disable-for-next-line Credo.Checks.TimestampsType
    timestamps(inserted_at: :created_at)
  end

  def create_changeset(device_code, attrs) do
    device_code
    |> cast(attrs, [:code, :created_at])
    |> validate_required([:code])
    |> unique_constraint([:user_id], name: "index_device_codes_on_user_id")
  end

  def authenticate_changeset(device_code, attrs) do
    device_code
    |> cast(attrs, [:authenticated, :user_id, :auth_provider, :auth_provider_organization_id, :auth_organization_id])
    |> validate_required([:authenticated, :user_id])
  end
end
