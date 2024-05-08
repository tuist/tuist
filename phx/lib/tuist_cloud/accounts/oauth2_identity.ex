defmodule TuistCloud.Accounts.Oauth2Identity do
  @moduledoc ~S"""
  A module that represents the oauth2 identity.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "oauth2_identities" do
    field :provider, Ecto.Enum, values: [github: 0, okta: 1, google: 2]
    field :id_in_provider, :string
    belongs_to :user, TuistCloud.Accounts.User
  end

  def create_changeset(oauth2_identity, attrs) do
    oauth2_identity
    |> cast(attrs, [:provider, :id_in_provider, :user_id])
    |> validate_required([:provider, :id_in_provider, :user_id])
    |> unique_constraint([:provider, :id_in_provider],
      name: "index_oauth2_identities_on_provider_and_id_in_provider"
    )
    |> validate_inclusion(:provider, [:github, :okta, :google])
    |> foreign_key_constraint(:user_id)
  end
end
