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

  A domain verified before re-checks existed has no
  `sso_login_domain_last_verified_at` and is not re-checked, since its
  administrators were never asked to keep the record published. It joins the
  re-check the next time the domain is verified.
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
          count_if(counts, :refreshed, update_unchanged(organization, sso_login_domain_last_verified_at: now))

        expired?(organization, now) ->
          # The domain and its token stay, so publishing the record again and verifying restores it.
          count_if(counts, :lapsed, update_unchanged(organization, sso_login_domain_verified_at: nil))

        true ->
          Map.update!(counts, :missing, &(&1 + 1))
      end
    end)
  end

  @doc """
  When a verified domain loses its verification if its record stays absent.
  """
  def expires_at(%Organization{sso_login_domain_verified_at: nil}), do: nil
  def expires_at(%Organization{sso_login_domain_last_verified_at: nil}), do: nil

  def expires_at(%Organization{sso_login_domain_last_verified_at: last_verified_at}) do
    DateTime.add(last_verified_at, @grace_period_days, :day)
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
  def awaiting_record?(organization, now \\ DateTime.utc_now())
  def awaiting_record?(%Organization{sso_login_domain_verified_at: nil}, _now), do: true
  def awaiting_record?(%Organization{} = organization, now), do: expiring?(organization, now)

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
            not is_nil(organization.sso_login_domain_last_verified_at) and
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

  # The lookup ran against this snapshot, so a domain change or a verification
  # made while the sweep was running is left alone.
  defp update_unchanged(%Organization{} = organization, changes) do
    {count, _} =
      Repo.update_all(
        from(o in Organization,
          where: o.id == ^organization.id,
          where: o.sso_login_domain == ^organization.sso_login_domain,
          where: o.sso_login_domain_verification_token == ^organization.sso_login_domain_verification_token,
          where: o.sso_login_domain_verified_at == ^organization.sso_login_domain_verified_at,
          where: o.sso_login_domain_last_verified_at == ^organization.sso_login_domain_last_verified_at
        ),
        set: changes
      )

    count == 1
  end

  defp count_if(counts, key, true), do: Map.update!(counts, key, &(&1 + 1))
  defp count_if(counts, _key, false), do: counts
end
