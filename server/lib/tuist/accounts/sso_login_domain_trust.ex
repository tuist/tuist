defmodule Tuist.Accounts.SSOLoginDomainTrust do
  @moduledoc """
  Resolves DNS and self-hosted instance trust without persisting operator
  assertions as DNS proofs. Enabling instance trust explicitly trusts the
  instance's organization administrators to configure identity providers.
  """

  import Ecto.Query

  alias Tuist.Accounts.Organization
  alias Tuist.Environment
  alias Tuist.Repo

  def parse_config(nil, _hosted), do: {:ok, false}
  def parse_config("false", _hosted), do: {:ok, false}
  def parse_config("true", false), do: {:ok, true}

  def parse_config("true", true),
    do: {:error, "TUIST_SSO_TRUST_UNVERIFIED_LOGIN_DOMAINS is only supported on self-hosted instances"}

  def parse_config(_value, _hosted), do: {:error, "TUIST_SSO_TRUST_UNVERIFIED_LOGIN_DOMAINS must be true or false"}

  def trust(%Organization{sso_login_domain: domain} = organization) when is_binary(domain) do
    cond do
      organization.sso_provider in [:okta, :oauth2] and
          Environment.sso_trust_unverified_login_domains?() ->
        :instance

      not is_nil(organization.sso_login_domain_verified_at) ->
        :dns_verified

      true ->
        :untrusted
    end
  end

  def trust(%Organization{}), do: :untrusted

  def trusted?(organization), do: trust(organization) in [:instance, :dns_verified]

  def trusted_for_email?(organization, email) do
    email_domain(email) == organization.sso_login_domain and trusted?(organization)
  end

  def email_domain(email) when is_binary(email) do
    case String.split(email, "@") do
      [_local, domain] -> domain |> String.trim() |> String.trim_trailing(".") |> String.downcase()
      _ -> nil
    end
  end

  def email_domain(_email), do: nil

  def shared_domain?(%Organization{sso_login_domain: domain, id: id}) when is_binary(domain) do
    Environment.sso_trust_unverified_login_domains?() and
      Repo.exists?(
        from(o in Organization,
          where: o.sso_provider in [:okta, :oauth2] and o.sso_login_domain == ^domain and o.id != ^id
        )
      )
  end

  def shared_domain?(_organization), do: false

  def discover(domain) when is_binary(domain) do
    if Environment.sso_trust_unverified_login_domains?() do
      organizations =
        Repo.all(
          from(o in Organization,
            where: o.sso_provider in [:okta, :oauth2] and o.sso_login_domain == ^domain,
            order_by: [desc: not is_nil(o.sso_login_domain_verified_at), asc: o.id],
            limit: 2
          )
        )

      case organizations do
        [%{sso_login_domain_verified_at: verified_at} = organization | _] when not is_nil(verified_at) ->
          {:ok, organization}

        [organization] ->
          {:ok, organization}

        [] ->
          :unbound

        _ ->
          {:error, :login_domain_ambiguous}
      end
    else
      :unbound
    end
  end

  def discover(_domain), do: :unbound
end
