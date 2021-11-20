defmodule TuistCloud.Accounts.Organization do
  alias TuistCloud.Accounts.Invitation

  @moduledoc ~S"""
  A module that represents the organizations table.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "organizations" do
    field :sso_provider, Ecto.Enum, values: [google: 2]
    field :sso_organization_id, :string

    has_many(:invitations, Invitation)
    timestamps(inserted_at: :created_at)
  end

  def create_changeset(organization, attrs \\ %{}) do
    organization
    |> cast(attrs, [:sso_provider, :sso_organization_id])
    |> validate_inclusion(:sso_provider, [:google])
    |> unique_constraint([:sso_provider, :sso_organization_id],
      message:
        "SSO provider and SSO organization ID must be unique. Make sure no other organization has the same SSO provider and SSO organization ID."
    )
  end

  def update_changeset(organization, attrs) do
    organization
    |> cast(attrs, [:sso_provider, :sso_organization_id])
    |> validate_inclusion(:sso_provider, [:google])
    |> unique_constraint([:sso_provider, :sso_organization_id],
      message:
        "SSO provider and SSO organization ID must be unique. Make sure no other organization has the same SSO provider and SSO organization ID."
    )
  end
end
