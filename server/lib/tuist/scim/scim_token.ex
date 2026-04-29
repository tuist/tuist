defmodule Tuist.SCIM.SCIMToken do
  @moduledoc """
  A bearer token issued to an organization for SCIM 2.0 provisioning by an
  external Identity Provider (Okta, Azure AD, etc.).

  Unlike `Tuist.Accounts.AccountToken`, SCIM tokens are not user-facing API
  tokens — they authenticate an IdP into a single organization's SCIM
  endpoints. The plaintext token is shown once on creation; only a Bcrypt hash
  is persisted.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Organization

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "scim_tokens" do
    field :encrypted_token_hash, :string
    field :name, :string
    field :last_used_at, :utc_datetime

    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:organization_id, :encrypted_token_hash, :name])
    |> validate_required([:organization_id, :encrypted_token_hash])
    |> validate_length(:name, max: 64)
  end
end
