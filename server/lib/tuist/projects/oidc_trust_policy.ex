defmodule Tuist.Projects.OIDCTrustPolicy do
  @moduledoc "Project-scoped trust in an explicitly configured workload identity provider."
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Projects.Project

  @reserved_claims ~w(iss aud exp nbf iat jti)

  schema "project_oidc_trust_policies" do
    field :name, :string
    field :issuer, :string
    field :jwks_url, :string
    field :audience, :string, default: "tuist"
    field :claims, :map
    belongs_to :project, Project

    timestamps(type: :utc_datetime)
  end

  def changeset(policy \\ %__MODULE__{}, attrs) do
    policy
    |> cast(attrs, [:name, :issuer, :jwks_url, :audience, :claims])
    |> validate_required([:name, :issuer, :jwks_url, :audience, :claims])
    |> validate_length(:name, max: 100)
    |> validate_length(:issuer, max: 512)
    |> validate_length(:jwks_url, max: 2048)
    |> validate_length(:audience, max: 255)
    |> validate_change(:issuer, &validate_issuer/2)
    |> validate_change(:jwks_url, &validate_jwks_url/2)
    |> validate_change(:claims, &validate_claims/2)
    |> unique_constraint(:name, name: :project_oidc_trust_policies_project_id_name_index)
  end

  def reserved_issuer?(issuer) do
    issuer == "https://token.actions.githubusercontent.com" or
      String.starts_with?(issuer, "https://token.actions.githubusercontent.com/") or
      issuer == "https://token.builds.bitrise.io" or
      String.starts_with?(issuer, "https://oidc.circleci.com/org/")
  end

  def https_url?(value) when is_binary(value) do
    case URI.new(value) do
      {:ok, %URI{scheme: "https", host: host, userinfo: nil, fragment: nil}} when is_binary(host) and host != "" -> true
      _ -> false
    end
  end

  def https_url?(_), do: false

  def matches?(policy, claims) do
    claims["iss"] == policy.issuer and audience_matches?(claims["aud"], policy.audience) and
      Enum.all?(policy.claims, fn {key, value} -> Map.has_key?(claims, key) and claims[key] === value end)
  end

  defp audience_matches?(audience, expected) when is_binary(audience), do: audience == expected

  defp audience_matches?(audiences, expected) when is_list(audiences),
    do: Enum.all?(audiences, &is_binary/1) and expected in audiences

  defp audience_matches?(_, _), do: false

  defp validate_issuer(field, value) do
    cond do
      not https_url?(value) or not is_nil(URI.parse(value).query) ->
        [{field, "must be an HTTPS issuer without query parameters"}]

      reserved_issuer?(value) ->
        [{field, "uses built-in repository authentication"}]

      true ->
        []
    end
  end

  defp validate_jwks_url(field, value) do
    if https_url?(value), do: [], else: [{field, "must be an HTTPS URL without credentials or a fragment"}]
  end

  defp validate_claims(field, claims) do
    valid? =
      map_size(claims) in 1..10 and Enum.all?(claims, &valid_claim?/1)

    if valid?, do: [], else: [{field, "must contain 1 to 10 exact string, 64-bit integer or boolean identity claims"}]
  end

  defp valid_claim?({key, value}) do
    is_binary(key) and byte_size(key) in 1..128 and key not in @reserved_claims and valid_claim_value?(value)
  end

  defp valid_claim_value?(value) when is_binary(value), do: byte_size(value) in 1..512

  defp valid_claim_value?(value) when is_integer(value),
    do: value in -9_223_372_036_854_775_808..9_223_372_036_854_775_807

  defp valid_claim_value?(value), do: is_boolean(value)
end
