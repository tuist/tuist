defmodule Tuist.Accounts.Organization do
  @moduledoc ~S"""
  A module that represents the organizations table.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.Invitation
  alias Tuist.Vault.Binary

  @oauth2_endpoint_fields [
    :oauth2_authorize_url,
    :oauth2_token_url,
    :oauth2_user_info_url
  ]

  @oauth2_providers [:okta, :oauth2]

  schema "organizations" do
    field :sso_provider, Ecto.Enum, values: [okta: 1, google: 2, oauth2: 3]
    field :sso_organization_id, :string
    field :sso_enforced, :boolean, default: false
    field :oauth2_client_id, :string
    field :oauth2_encrypted_client_secret, Binary
    field :oauth2_authorize_url, :string
    field :oauth2_token_url, :string
    field :oauth2_user_info_url, :string

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
      :oauth2_client_id,
      :oauth2_encrypted_client_secret,
      :oauth2_authorize_url,
      :oauth2_token_url,
      :oauth2_user_info_url,
      :created_at
    ])
    |> normalize_oauth2_urls()
    |> validate_inclusion(:sso_provider, [:okta, :google, :oauth2])
    |> validate_oauth2_required_fields()
    |> validate_oauth2_urls()
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
      :oauth2_client_id,
      :oauth2_encrypted_client_secret,
      :oauth2_authorize_url,
      :oauth2_token_url,
      :oauth2_user_info_url
    ])
    |> normalize_oauth2_urls()
    |> validate_inclusion(:sso_provider, [:okta, :google, :oauth2])
    |> validate_oauth2_required_fields()
    |> validate_oauth2_urls()
    |> unique_constraint([:sso_provider, :sso_organization_id],
      message:
        "SSO provider and SSO organization ID must be unique. Make sure no other organization has the same SSO provider and SSO organization ID."
    )
  end

  defp validate_oauth2_required_fields(changeset) do
    if get_field(changeset, :sso_provider) in @oauth2_providers do
      changeset
      |> validate_required([:sso_organization_id, :oauth2_client_id])
      |> validate_oauth2_client_secret()
      |> validate_oauth2_endpoint_urls()
    else
      changeset
    end
  end

  defp validate_oauth2_client_secret(changeset) do
    if is_nil(get_field(changeset, :oauth2_encrypted_client_secret)) do
      add_error(changeset, :oauth2_encrypted_client_secret, "can't be blank")
    else
      changeset
    end
  end

  defp validate_oauth2_endpoint_urls(changeset) do
    if get_field(changeset, :sso_provider) in @oauth2_providers do
      validate_required(changeset, @oauth2_endpoint_fields)
    else
      changeset
    end
  end

  defp normalize_oauth2_urls(changeset) do
    case get_field(changeset, :sso_provider) do
      :okta ->
        changeset
        |> derive_okta_endpoint_urls()
        |> normalize_oauth2_endpoint_urls()

      :oauth2 ->
        changeset
        |> update_change(:sso_organization_id, &normalize_oauth2_site/1)
        |> normalize_oauth2_endpoint_urls()

      _ ->
        changeset
    end
  end

  # For Okta, the authorize/token/userinfo endpoints are conventionally derived
  # from the org's Okta domain. Callers can pass `sso_organization_id` alone
  # and we fill in the endpoint URLs; explicit values still take precedence.
  defp derive_okta_endpoint_urls(changeset) do
    case get_field(changeset, :sso_organization_id) do
      domain when is_binary(domain) and domain != "" ->
        changeset
        |> maybe_put_oauth2_url(:oauth2_authorize_url, "https://#{domain}/oauth2/v1/authorize")
        |> maybe_put_oauth2_url(:oauth2_token_url, "https://#{domain}/oauth2/v1/token")
        |> maybe_put_oauth2_url(:oauth2_user_info_url, "https://#{domain}/oauth2/v1/userinfo")

      _ ->
        changeset
    end
  end

  defp maybe_put_oauth2_url(changeset, field, value) do
    case get_field(changeset, field) do
      nil -> put_change(changeset, field, value)
      "" -> put_change(changeset, field, value)
      _ -> changeset
    end
  end

  defp validate_oauth2_urls(changeset) do
    case get_field(changeset, :sso_provider) do
      :oauth2 ->
        Enum.reduce([:sso_organization_id | @oauth2_endpoint_fields], changeset, fn field, changeset ->
          validate_change(changeset, field, fn ^field, url ->
            invalid_url_error(field, url)
          end)
        end)

      :okta ->
        Enum.reduce(@oauth2_endpoint_fields, changeset, fn field, changeset ->
          validate_change(changeset, field, fn ^field, url ->
            invalid_url_error(field, url)
          end)
        end)

      _ ->
        changeset
    end
  end

  defp valid_oauth2_url?(url), do: Tuist.URL.public_url?(url)

  defp normalize_oauth2_endpoint_urls(changeset) do
    Enum.reduce(@oauth2_endpoint_fields, changeset, fn field, changeset ->
      update_change(changeset, field, &trim_value/1)
    end)
  end

  defp normalize_oauth2_site(nil), do: nil
  defp normalize_oauth2_site(site), do: site |> String.trim() |> String.trim_trailing("/")

  defp trim_value(nil), do: nil
  defp trim_value(value), do: String.trim(value)

  defp invalid_url_error(field, url) do
    if valid_oauth2_url?(url) do
      []
    else
      [{field, "must be a valid URL"}]
    end
  end
end
