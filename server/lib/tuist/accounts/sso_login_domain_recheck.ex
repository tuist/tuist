defmodule Tuist.Accounts.SSOLoginDomainRecheck do
  @moduledoc """
  Re-checks the text record behind a verified login email domain.

  Verification proves control of a domain at one point in time, while the
  trust it grants (provider discovery, identity linking, and the bound on
  automatic enrollment) lasts as long as the domain stays verified. A domain
  that is given up and registered by someone else would otherwise keep that
  trust, so the record is re-checked and the verification lapses once the
  record has been absent for `grace_period_days/0`.

  A lookup that fails for any reason simply does not refresh the timestamp, so
  a transient resolver failure costs one day of the grace period rather than
  the verification.
  """

  import Ecto.Query

  alias Tuist.Accounts.Organization
  alias Tuist.Accounts.SSOLoginDomainVerification
  alias Tuist.Repo

  @grace_period_days 14
  @expiring_within_days 7

  def grace_period_days, do: @grace_period_days

  @doc """
  Re-checks every verified login email domain, refreshing the ones still
  publishing their record and lapsing the ones past the grace period.
  """
  def sweep(now \\ DateTime.utc_now()) do
    now = DateTime.truncate(now, :second)

    Enum.reduce(verified_organizations(), %{refreshed: 0, missing: 0, lapsed: 0}, fn organization, counts ->
      cond do
        record_published?(organization) ->
          refresh(organization, now)
          Map.update!(counts, :refreshed, &(&1 + 1))

        expired?(organization, now) ->
          lapse(organization)
          Map.update!(counts, :lapsed, &(&1 + 1))

        true ->
          Map.update!(counts, :missing, &(&1 + 1))
      end
    end)
  end

  @doc """
  When a verified domain loses its verification if its record stays absent.
  """
  def expires_at(%Organization{sso_login_domain_verified_at: nil}), do: nil

  def expires_at(%Organization{} = organization) do
    case last_seen_at(organization) do
      nil -> nil
      last_seen_at -> DateTime.add(last_seen_at, @grace_period_days, :day)
    end
  end

  @doc """
  Whether a verified domain is close enough to lapsing to tell its
  administrators about it.
  """
  def expiring?(organization, now \\ DateTime.utc_now())

  def expiring?(%Organization{} = organization, now) do
    case expires_at(organization) do
      nil -> false
      expires_at -> DateTime.diff(expires_at, now, :day) <= @expiring_within_days
    end
  end

  def expiring?(_organization, _now), do: false

  @doc """
  Whether the organization still has a record to publish, either because the
  domain was never verified or because the record stopped resolving.
  """
  def awaiting_record?(%Organization{sso_login_domain_verified_at: nil}), do: true
  def awaiting_record?(%Organization{} = organization), do: expiring?(organization)

  @doc """
  Whole days until a verified domain lapses, floored at zero.
  """
  def days_until_expiry(organization, now \\ DateTime.utc_now()) do
    case expires_at(organization) do
      nil -> nil
      expires_at -> expires_at |> DateTime.diff(now, :day) |> max(0)
    end
  end

  defp verified_organizations do
    Repo.all(
      from(organization in Organization,
        where:
          not is_nil(organization.sso_login_domain_verified_at) and
            not is_nil(organization.sso_login_domain) and
            not is_nil(organization.sso_login_domain_verification_token)
      )
    )
  end

  defp record_published?(%Organization{sso_login_domain: domain, sso_login_domain_verification_token: token}) do
    SSOLoginDomainVerification.verified?(domain, token)
  end

  defp expired?(organization, now) do
    case expires_at(organization) do
      nil -> false
      expires_at -> DateTime.after?(now, expires_at)
    end
  end

  defp refresh(organization, now) do
    organization
    |> Ecto.Changeset.change(sso_login_domain_last_verified_at: now)
    |> Repo.update!()
  end

  defp lapse(organization) do
    organization
    |> Organization.lapse_sso_login_domain_verification_changeset()
    |> Repo.update!()
  end

  defp last_seen_at(%Organization{sso_login_domain_last_verified_at: nil} = organization) do
    organization.sso_login_domain_verified_at
  end

  defp last_seen_at(%Organization{sso_login_domain_last_verified_at: last_verified_at}) do
    last_verified_at
  end
end
