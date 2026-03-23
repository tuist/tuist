defmodule Tuist.Accounts.Organization do
  @moduledoc ~S"""
  A module that represents the organizations table.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.Invitation
  alias Tuist.Vault.Binary

  schema "organizations" do
    field :sso_provider, Ecto.Enum, values: [okta: 1, google: 2, custom_oauth2: 3]
    field :sso_organization_id, :string
    field :sso_enforced, :boolean, default: false
    field :okta_client_id, :string
    field :okta_encrypted_client_secret, Binary
    field :custom_oauth2_client_id, :string
    field :custom_oauth2_encrypted_client_secret, Binary
    field :custom_oauth2_authorize_url, :string
    field :custom_oauth2_token_url, :string
    field :custom_oauth2_user_info_url, :string

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
      :sso_enforced,
      :okta_client_id,
      :okta_encrypted_client_secret,
      :custom_oauth2_client_id,
      :custom_oauth2_encrypted_client_secret,
      :custom_oauth2_authorize_url,
      :custom_oauth2_token_url,
      :custom_oauth2_user_info_url,
      :created_at
    ])
    |> normalize_custom_oauth2_site()
    |> validate_inclusion(:sso_provider, [:okta, :google, :custom_oauth2])
    |> validate_custom_oauth2_site()
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
      :sso_enforced,
      :okta_client_id,
      :okta_encrypted_client_secret,
      :custom_oauth2_client_id,
      :custom_oauth2_encrypted_client_secret,
      :custom_oauth2_authorize_url,
      :custom_oauth2_token_url,
      :custom_oauth2_user_info_url
    ])
    |> normalize_custom_oauth2_site()
    |> validate_inclusion(:sso_provider, [:okta, :google, :custom_oauth2])
    |> validate_custom_oauth2_site()
    |> unique_constraint([:sso_provider, :sso_organization_id],
      message:
        "SSO provider and SSO organization ID must be unique. Make sure no other organization has the same SSO provider and SSO organization ID."
    )
  end

  defp normalize_custom_oauth2_site(changeset) do
    if get_field(changeset, :sso_provider) == :custom_oauth2 do
      update_change(changeset, :sso_organization_id, fn
        nil -> nil
        site -> site |> String.trim() |> String.trim_trailing("/")
      end)
    else
      changeset
    end
  end

  defp validate_custom_oauth2_site(changeset) do
    if get_field(changeset, :sso_provider) == :custom_oauth2 do
      validate_change(changeset, :sso_organization_id, fn :sso_organization_id, site ->
        case URI.parse(site) do
          %URI{scheme: scheme, host: host, query: nil, fragment: nil}
          when scheme in ["http", "https"] and is_binary(host) and host != "" ->
            []

          _ ->
            [sso_organization_id: "must be a valid URL"]
        end
      end)
    else
      changeset
    end
  end
end
