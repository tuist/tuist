defmodule Tuist.Accounts.Oauth2Identity do
  @moduledoc ~S"""
  A module that represents the oauth2 identity.
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "oauth2_identities" do
    field :provider, Ecto.Enum, values: [github: 0, okta: 1, google: 2, apple: 3, oauth2: 4]
    field :id_in_provider, :string
    field :provider_organization_id, :string
    belongs_to :user, Tuist.Accounts.User
  end

  @per_issuer_providers [:okta, :oauth2]

  def create_changeset(oauth2_identity, attrs) do
    oauth2_identity
    |> cast(attrs, [:provider, :id_in_provider, :user_id, :provider_organization_id])
    |> validate_required([:provider, :id_in_provider, :user_id])
    |> validate_provider_organization_id_for_per_issuer_providers()
    |> unique_constraint([:provider, :id_in_provider],
      name: "oauth2_identities_global_provider_unique_index"
    )
    |> unique_constraint([:provider, :id_in_provider, :provider_organization_id],
      name: "oauth2_identities_per_issuer_unique_index"
    )
    |> validate_inclusion(:provider, [:github, :okta, :google, :apple, :oauth2])
    |> foreign_key_constraint(:user_id)
  end

  # OIDC `sub` is only unique per issuer, so for `:okta` and `:oauth2` we
  # must always know which issuer the identity belongs to. Rejecting writes
  # with a NULL/empty `provider_organization_id` keeps the uniqueness key
  # meaningful and prevents a new row from falling outside the per-issuer
  # partial unique index.
  defp validate_provider_organization_id_for_per_issuer_providers(changeset) do
    if get_field(changeset, :provider) in @per_issuer_providers do
      changeset
      |> validate_change(:provider_organization_id, fn :provider_organization_id, value ->
        if is_binary(value) and value != "" do
          []
        else
          [{:provider_organization_id, "can't be blank for per-issuer providers"}]
        end
      end)
      |> validate_required([:provider_organization_id])
    else
      changeset
    end
  end
end
