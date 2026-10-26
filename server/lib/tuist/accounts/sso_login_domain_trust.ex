defmodule Tuist.Accounts.SSOLoginDomainTrust do
  @moduledoc """
  Resolves login-domain trust without persisting instance policy as DNS proof.
  Instances trust saved custom-provider domains by default; requiring DNS
  verification is an explicit deployment policy.
  """

  import Ecto.Query

  alias Tuist.Accounts.Organization
  alias Tuist.Environment
  alias Tuist.Repo

  def parse_config(nil), do: {:ok, false}
  def parse_config("false"), do: {:ok, false}
  def parse_config("true"), do: {:ok, true}

  def parse_config(_value), do: {:error, "TUIST_SSO_REQUIRE_LOGIN_DOMAIN_VERIFICATION must be true or false"}

  def trust(%Organization{sso_login_domain: domain} = organization) when is_binary(domain) do
    cond do
      organization.sso_provider in [:okta, :oauth2] and
          not Environment.sso_require_login_domain_verification?() ->
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
    not Environment.sso_require_login_domain_verification?() and
      Repo.exists?(
        from(o in Organization,
          where: o.sso_provider in [:okta, :oauth2] and o.sso_login_domain == ^domain and o.id != ^id
        )
      )
  end

  def shared_domain?(_organization), do: false

  def discover(domain) when is_binary(domain) do
    if Environment.sso_require_login_domain_verification?() do
      :unbound
    else
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
    end
  end

  def discover(_domain), do: :unbound
end
