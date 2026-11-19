defmodule Tuist.Accounts.DeviceCode do
  @moduledoc """
  A module that represents the device code.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.User

  schema "device_codes" do
    field :code, :string
    # Set only for codes issued by the standard device flow (RFC 8628): the
    # short code a person types to approve it. `code` is then the secret the
    # client polls with and is never shown in a browser.
    field :user_code, :string
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
    |> cast(attrs, [:code, :user_code, :created_at])
    |> validate_required([:code])
    |> unique_constraint([:user_id], name: "index_device_codes_on_user_id")
    |> unique_constraint([:user_code])
  end
end
