defmodule Tuist.Accounts.Organization do
  @moduledoc ~S"""
  A module that represents the organizations table.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.Invitation
  alias Tuist.Accounts.Role
  alias Tuist.Vault.Binary

  @oauth2_endpoint_fields [
    :oauth2_authorize_url,
    :oauth2_token_url,
    :oauth2_user_info_url
  ]

  @oauth2_providers [:okta, :oauth2]

  # Automatic enrollment must never mint an admin, so the default is limited to
  # the two non-privileged roles.
  @sso_default_roles Role.names() -- ["admin"]

  @sso_update_fields [
    :sso_provider,
    :sso_organization_id,
    :sso_additional_organization_ids,
    :sso_enforced,
    :sso_login_domain,
    :sso_automatic_enrollment,
    :sso_default_role,
    :oauth2_client_id,
    :oauth2_encrypted_client_secret,
    :oauth2_authorize_url,
    :oauth2_token_url,
    :oauth2_user_info_url
  ]

  @sso_verification_fields [
    :sso_login_domain_verification_token,
    :sso_login_domain_verified_at,
    :sso_login_domain_last_verified_at
  ]

  schema "organizations" do
    field :sso_provider, Ecto.Enum, values: [okta: 1, google: 2, oauth2: 3]
    field :sso_organization_id, :string
    field :sso_additional_organization_ids, {:array, :string}, default: []
    field :sso_enforced, :boolean, default: false
    field :sso_login_domain, :string
    field :sso_login_domain_verification_token, :string
    field :sso_login_domain_verified_at, :utc_datetime
    field :sso_login_domain_last_verified_at, :utc_datetime
    field :sso_automatic_enrollment, :boolean, default: false
    field :sso_default_role, :string, default: "user"
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
      :sso_additional_organization_ids,
      :sso_enforced,
      :sso_login_domain,
      :sso_login_domain_verification_token,
      :sso_login_domain_verified_at,
      :sso_automatic_enrollment,
      :sso_default_role,
      :oauth2_client_id,
      :oauth2_encrypted_client_secret,
      :oauth2_authorize_url,
      :oauth2_token_url,
      :oauth2_user_info_url,
      :created_at
    ])
    |> normalize_sso_login_domain()
    |> normalize_oauth2_urls()
    |> validate_sso_login_domain()
    |> validate_sso_additional_organization_ids()
    |> validate_sso_security_policy()
    |> validate_inclusion(:sso_default_role, @sso_default_roles)
    |> validate_inclusion(:sso_provider, [:okta, :google, :oauth2])
    |> validate_oauth2_required_fields()
    |> validate_oauth2_urls()
    |> unique_constraint([:sso_provider, :sso_organization_id],
      message:
        "SSO provider and SSO organization ID must be unique. Make sure no other organization has the same SSO provider and SSO organization ID."
    )
    |> unique_constraint(:sso_login_domain,
      name: :organizations_verified_sso_login_domain_index,
      message: "has already been verified by another organization"
    )
  end

  def update_changeset(organization, attrs) do
    update_changeset(organization, attrs, @sso_update_fields)
  end

  def sso_configuration_changeset(organization, attrs, opts \\ []) do
    update_changeset(organization, attrs, @sso_update_fields ++ @sso_verification_fields, opts)
  end

  defp update_changeset(organization, attrs, fields, opts \\ []) do
    organization
    |> cast(attrs, fields)
    |> normalize_sso_login_domain()
    |> normalize_oauth2_urls()
    |> validate_sso_login_domain()
    |> validate_sso_additional_organization_ids()
    |> then(fn changeset ->
      if Keyword.get(opts, :validate_security_policy, true),
        do: validate_sso_security_policy(changeset),
        else: changeset
    end)
    |> validate_inclusion(:sso_default_role, @sso_default_roles)
    |> validate_inclusion(:sso_provider, [:okta, :google, :oauth2])
    |> validate_oauth2_required_fields()
    |> validate_oauth2_urls()
    |> unique_constraint([:sso_provider, :sso_organization_id],
      message:
        "SSO provider and SSO organization ID must be unique. Make sure no other organization has the same SSO provider and SSO organization ID."
    )
    |> unique_constraint(:sso_login_domain,
      name: :organizations_verified_sso_login_domain_index,
      message: "has already been verified by another organization"
    )
  end

  @doc """
  The provider organization identifiers (`hd` for Google) a sign-in can carry
  to satisfy the organization's SSO. Google organizations accept their
  additional Workspace domains next to the primary one; they only satisfy
  enforcement and never drive automatic enrollment or discovery, which keep
  using `sso_organization_id` alone.
  """
  def sso_provider_organization_ids(%__MODULE__{sso_organization_id: nil}), do: []

  def sso_provider_organization_ids(%__MODULE__{sso_provider: :google} = organization) do
    [organization.sso_organization_id | organization.sso_additional_organization_ids]
  end

  def sso_provider_organization_ids(%__MODULE__{sso_organization_id: id}), do: [id]

  def verify_sso_login_domain_changeset(organization, verified_at) do
    organization
    |> change(
      sso_login_domain_verified_at: verified_at,
      sso_login_domain_last_verified_at: verified_at
    )
    |> unique_constraint(:sso_login_domain,
      name: :organizations_verified_sso_login_domain_index,
      message: "has already been verified by another organization"
    )
  end

  def validate_sso_security_policy(changeset, domain_trust \\ :dns) do
    if get_field(changeset, :sso_provider) in @oauth2_providers do
      changeset
      |> require_verified_domain(:sso_automatic_enrollment, domain_trust)
      |> require_verified_domain(:sso_enforced, domain_trust)
    else
      changeset
    end
  end

  defp normalize_sso_login_domain(changeset) do
    update_change(changeset, :sso_login_domain, &normalize_domain/1)
  end

  defp validate_sso_login_domain(changeset) do
    validate_format(
      changeset,
      :sso_login_domain,
      domain_regex(),
      message: "must be a valid domain"
    )
  end

  # Not unique across organizations: nothing looks an organization up by them,
  # and an admin can't prove control of another Workspace, so uniqueness would
  # let one organization squat a domain another needs.
  defp validate_sso_additional_organization_ids(changeset) do
    if get_field(changeset, :sso_provider) == :google do
      changeset = update_change(changeset, :sso_additional_organization_ids, &normalize_domains/1)
      domains = get_field(changeset, :sso_additional_organization_ids) || []
      primary = changeset |> get_field(:sso_organization_id) |> normalize_domain()

      cond do
        not Enum.all?(domains, &Regex.match?(domain_regex(), &1)) ->
          add_error(changeset, :sso_additional_organization_ids, "must be valid domains")

        primary in domains ->
          add_error(changeset, :sso_additional_organization_ids, "must not include the primary domain")

        true ->
          changeset
      end
    else
      if get_field(changeset, :sso_additional_organization_ids) in [nil, []],
        do: changeset,
        else: put_change(changeset, :sso_additional_organization_ids, [])
    end
  end

  defp normalize_domains(nil), do: []

  defp normalize_domains(domains), do: domains |> Enum.map(&normalize_domain/1) |> Enum.reject(&(&1 == "")) |> Enum.uniq()

  defp normalize_domain(nil), do: nil
  defp normalize_domain(domain), do: domain |> String.trim() |> String.trim_trailing(".") |> String.downcase()

  defp domain_regex,
    do: ~r/\A(?=.{1,253}\z)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/

  # Existing enabled policies survive loss or absence of domain trust so admins
  # can edit their configuration. Enrollment still checks trust at runtime.
  defp require_verified_domain(changeset, field, domain_trust) do
    previously_enabled? = Map.get(changeset.data, field) == true and get_change(changeset, field) != true

    cond do
      get_field(changeset, field) != true -> changeset
      trusted_domain?(changeset, domain_trust) -> changeset
      previously_enabled? -> changeset
      true -> add_error(changeset, field, "requires a verified login email domain for this provider")
    end
  end

  defp trusted_domain?(changeset, :dns) do
    domain = get_field(changeset, :sso_login_domain)
    verified_at = get_field(changeset, :sso_login_domain_verified_at)
    is_binary(domain) and not is_nil(verified_at)
  end

  defp trusted_domain?(_changeset, trust), do: trust in [:instance, :dns_verified]

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

  defp valid_oauth2_url?(url), do: Tuist.URL.sso_url?(url)

  defp normalize_oauth2_endpoint_urls(changeset) do
    Enum.reduce(@oauth2_endpoint_fields, changeset, fn field, changeset ->
      update_change(changeset, field, &trim_value/1)
    end)
  end

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
