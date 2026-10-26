defmodule Tuist.Accounts.SSOLoginDomainTrust do
  @moduledoc """
  Resolves DNS and self-hosted instance trust without persisting operator
  assertions as DNS proofs. Only operator-selected users may configure SSO
  while instance trust is enabled.
  """

  import Ecto.Query

  alias Tuist.Accounts.Organization
  alias Tuist.Accounts.User
  alias Tuist.Environment
  alias Tuist.Repo

  @max_user_id 9_223_372_036_854_775_807

  def parse_config(trust, admin_ids, hosted) do
    with {:ok, enabled} <- parse_enabled(trust),
         {:ok, ids} <- parse_admin_ids(admin_ids) do
      cond do
        hosted and (enabled or ids != []) ->
          {:error, "SSO instance trust and configuration administrators are only supported on self-hosted instances"}

        enabled and ids == [] ->
          {:error, "TUIST_SSO_TRUST_UNVERIFIED_LOGIN_DOMAINS requires TUIST_SSO_CONFIGURATION_ADMIN_USER_IDS"}

        true ->
          {:ok, %{trust_unverified_domains: enabled, admin_user_ids: ids}}
      end
    end
  end

  defp parse_enabled(nil), do: {:ok, false}
  defp parse_enabled("false"), do: {:ok, false}
  defp parse_enabled("true"), do: {:ok, true}
  defp parse_enabled(_), do: {:error, "TUIST_SSO_TRUST_UNVERIFIED_LOGIN_DOMAINS must be true or false"}

  defp parse_admin_ids(nil), do: {:ok, []}

  defp parse_admin_ids(value) do
    ids = value |> String.split(",") |> Enum.map(&parse_id/1)

    if :error in ids or Enum.uniq(ids) != ids,
      do: {:error, "TUIST_SSO_CONFIGURATION_ADMIN_USER_IDS must contain unique positive integer user IDs"},
      else: {:ok, ids}
  end

  defp parse_id(value) do
    case Integer.parse(String.trim(value)) do
      {id, ""} when id > 0 and id <= @max_user_id -> id
      _ -> :error
    end
  end

  def configuration_allowed?(actor) do
    policy = Environment.sso_login_domain_policy()

    if policy.trust_unverified_domains or policy.admin_user_ids != [] do
      case actor do
        %User{id: id} when is_integer(id) -> id in policy.admin_user_ids
        _ -> false
      end
    else
      true
    end
  end

  def trust(%Organization{sso_login_domain: domain} = organization) when is_binary(domain) do
    cond do
      organization.sso_provider in [:okta, :oauth2] and
          Environment.sso_login_domain_policy().trust_unverified_domains ->
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
    Environment.sso_login_domain_policy().trust_unverified_domains and
      Repo.exists?(
        from(o in Organization,
          where: o.sso_provider in [:okta, :oauth2] and o.sso_login_domain == ^domain and o.id != ^id
        )
      )
  end

  def shared_domain?(_organization), do: false

  def discover(domain) when is_binary(domain) do
    if Environment.sso_login_domain_policy().trust_unverified_domains do
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
