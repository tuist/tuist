defmodule Tuist.Projects.FlyOIDCTrustPolicy do
  @moduledoc """
  Project-scoped trust in a Fly.io organization and application identity.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Projects.Project

  schema "project_fly_oidc_trust_policies" do
    field :issuer, :string
    field :organization_id, :string
    field :application_id, :string
    belongs_to :project, Project

    timestamps(type: :utc_datetime)
  end

  def changeset(policy \\ %__MODULE__{}, attrs) do
    policy
    |> cast(attrs, [:issuer, :organization_id, :application_id])
    |> validate_required([:issuer, :organization_id, :application_id])
    |> validate_format(:issuer, ~r/\Ahttps:\/\/oidc\.fly\.io\/[a-z0-9]+(?:-[a-z0-9]+)*\z/,
      message: "must be https://oidc.fly.io/<organization-slug>"
    )
    |> validate_length(:issuer, max: 255)
    |> validate_format(:organization_id, ~r/\A[0-9]+\z/)
    |> validate_length(:organization_id, max: 64)
    |> validate_format(:application_id, ~r/\A[0-9]+\z/)
    |> validate_length(:application_id, max: 64)
    |> unique_constraint(:issuer,
      name: :project_fly_oidc_trust_policies_identity_index
    )
  end
end
