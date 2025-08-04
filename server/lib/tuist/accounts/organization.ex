defmodule Tuist.Accounts.Organization do
  @moduledoc ~S"""
  A module that represents the organizations table.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.Invitation

  schema "organizations" do
    field :sso_provider, Ecto.Enum, values: [okta: 1, google: 2]
    field :sso_organization_id, :string
    field :okta_client_id, :string
    field :okta_encrypted_client_secret, Tuist.Vault.Binary

    has_one(:account, Account, foreign_key: :organization_id, on_delete: :delete_all)
    has_many(:invitations, Invitation)
    # credo:disable-for-next-line Credo.Checks.TimestampsType
    timestamps(inserted_at: :created_at)
  end

  def create_changeset(organization \\ %__MODULE__{}, attrs \\ %{}) do
    organization
    |> cast(attrs, [
      :sso_provider,
      :sso_organization_id,
      :okta_client_id,
      :okta_encrypted_client_secret,
      :created_at
    ])
    |> validate_inclusion(:sso_provider, [:okta, :google])
    |> unique_constraint([:sso_provider, :sso_organization_id],
      message:
        "SSO provider and SSO organization ID must be unique. Make sure no other organization has the same SSO provider and SSO organization ID."
    )
  end

  def update_changeset(organization, attrs) do
    organization
    |> cast(attrs, [
      :sso_provider,
      :sso_organization_id,
      :okta_client_id,
      :okta_encrypted_client_secret
    ])
    |> validate_inclusion(:sso_provider, [:okta, :google])
    |> unique_constraint([:sso_provider, :sso_organization_id],
      message:
        "SSO provider and SSO organization ID must be unique. Make sure no other organization has the same SSO provider and SSO organization ID."
    )
  end
end
