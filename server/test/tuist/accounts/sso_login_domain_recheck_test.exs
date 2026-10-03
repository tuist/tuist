defmodule Tuist.Accounts.SSOLoginDomainRecheckTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Accounts.Organization
  alias Tuist.Accounts.SSOLoginDomainRecheck
  alias Tuist.Accounts.SSOLoginDomainVerification
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :set_mimic_from_context

  describe "sweep/1" do
    test "refreshes a domain whose record still resolves" do
      now = ~U[2026-09-23 12:00:00Z]
      organization = verified_organization(last_verified_at: ~U[2026-09-20 12:00:00Z])
      stub(SSOLoginDomainVerification, :verified?, fn _domain, _token -> true end)

      assert %{refreshed: 1, missing: 0, lapsed: 0} = SSOLoginDomainRecheck.sweep(now)

      reloaded = Repo.reload!(organization)
      assert reloaded.sso_login_domain_last_verified_at == DateTime.truncate(now, :second)
      assert reloaded.sso_login_domain_verified_at
    end

    test "keeps a verification whose record is missing but still inside the grace period" do
      now = ~U[2026-09-23 12:00:00Z]
      organization = verified_organization(last_verified_at: ~U[2026-09-20 12:00:00Z])
      stub(SSOLoginDomainVerification, :verified?, fn _domain, _token -> false end)

      assert %{refreshed: 0, missing: 1, lapsed: 0} = SSOLoginDomainRecheck.sweep(now)

      reloaded = Repo.reload!(organization)
      assert reloaded.sso_login_domain_verified_at
      assert reloaded.sso_login_domain_last_verified_at == ~U[2026-09-20 12:00:00Z]
    end

    test "lapses a verification whose record stayed missing past the grace period" do
      now = ~U[2026-09-23 12:00:00Z]
      organization = verified_organization(last_verified_at: ~U[2026-09-01 12:00:00Z])
      stub(SSOLoginDomainVerification, :verified?, fn _domain, _token -> false end)

      assert %{refreshed: 0, missing: 0, lapsed: 1} = SSOLoginDomainRecheck.sweep(now)

      reloaded = Repo.reload!(organization)
      refute reloaded.sso_login_domain_verified_at

      # The domain and its token survive, so republishing the record and
      # verifying restores it without reconfiguring the provider.
      assert reloaded.sso_login_domain == organization.sso_login_domain
      assert reloaded.sso_login_domain_verification_token
    end

    test "leaves a domain that was never verified alone" do
      organization =
        AccountsFixtures.organization_fixture(
          sso_provider: :okta,
          sso_organization_id: "company.okta.com",
          oauth2_client_id: "client-id",
          oauth2_client_secret: "client-secret",
          sso_login_domain: "example.com",
          sso_login_domain_verification_token: "verification-token"
        )

      stub(SSOLoginDomainVerification, :verified?, fn _domain, _token ->
        flunk("an unverified domain must not be re-checked")
      end)

      assert %{refreshed: 0, missing: 0, lapsed: 0} =
               SSOLoginDomainRecheck.sweep(~U[2026-09-23 12:00:00Z])

      refute Repo.reload!(organization).sso_login_domain_verified_at
    end

    test "leaves a domain verified before re-checks existed alone" do
      organization = verified_organization(last_verified_at: nil)

      stub(SSOLoginDomainVerification, :verified?, fn _domain, _token ->
        flunk("a domain verified before re-checks existed must not be re-checked")
      end)

      assert %{refreshed: 0, missing: 0, lapsed: 0} =
               SSOLoginDomainRecheck.sweep(~U[2026-12-01 12:00:00Z])

      reloaded = Repo.reload!(organization)
      assert reloaded.sso_login_domain_verified_at
      refute reloaded.sso_login_domain_last_verified_at
    end

    test "keeps a verification made while the sweep was looking up the record" do
      now = ~U[2026-09-23 12:00:00Z]
      organization = verified_organization(last_verified_at: ~U[2026-09-01 12:00:00Z])

      stub(SSOLoginDomainVerification, :verified?, fn _domain, _token ->
        organization
        |> Organization.verify_sso_login_domain_changeset(~U[2026-09-23 11:59:00Z])
        |> Repo.update!()

        false
      end)

      assert %{refreshed: 0, missing: 0, lapsed: 0} = SSOLoginDomainRecheck.sweep(now)

      reloaded = Repo.reload!(organization)
      assert reloaded.sso_login_domain_verified_at == ~U[2026-09-23 11:59:00Z]
      assert reloaded.sso_login_domain_last_verified_at == ~U[2026-09-23 11:59:00Z]
    end

    test "does not refresh a domain that changed while the sweep was looking up the record" do
      now = ~U[2026-09-23 12:00:00Z]
      organization = verified_organization(last_verified_at: ~U[2026-09-20 12:00:00Z])

      stub(SSOLoginDomainVerification, :verified?, fn _domain, _token ->
        organization
        |> Ecto.Changeset.change(
          sso_login_domain: "replacement.example",
          sso_login_domain_verification_token: "replacement-token",
          sso_login_domain_verified_at: nil,
          sso_login_domain_last_verified_at: nil
        )
        |> Repo.update!()

        true
      end)

      assert %{refreshed: 0, missing: 0, lapsed: 0} = SSOLoginDomainRecheck.sweep(now)
      refute Repo.reload!(organization).sso_login_domain_last_verified_at
    end

    test "counts a resolver failure as missing rather than lapsing on it" do
      now = ~U[2026-09-23 12:00:00Z]
      verified_organization(last_verified_at: ~U[2026-09-22 12:00:00Z])
      stub(SSOLoginDomainVerification, :verified?, fn _domain, _token -> false end)

      assert %{missing: 1, lapsed: 0} = SSOLoginDomainRecheck.sweep(now)
    end
  end

  describe "expiring?/2" do
    test "is true once the record has been missing long enough to warn about" do
      organization = verified_organization(last_verified_at: ~U[2026-09-15 12:00:00Z])

      assert SSOLoginDomainRecheck.expiring?(organization, ~U[2026-09-23 12:00:00Z])
      assert SSOLoginDomainRecheck.awaiting_record?(organization, ~U[2026-09-23 12:00:00Z])
    end

    test "is false while the record keeps resolving" do
      organization = verified_organization(last_verified_at: ~U[2026-09-23 12:00:00Z])

      refute SSOLoginDomainRecheck.expiring?(organization, ~U[2026-09-23 12:00:00Z])
      refute SSOLoginDomainRecheck.awaiting_record?(organization, ~U[2026-09-23 12:00:00Z])
    end

    test "is false for a domain verified before re-checks existed" do
      organization = verified_organization(last_verified_at: nil)

      refute SSOLoginDomainRecheck.expiring?(organization, ~U[2026-12-01 12:00:00Z])
      refute SSOLoginDomainRecheck.awaiting_record?(organization, ~U[2026-12-01 12:00:00Z])
      assert SSOLoginDomainRecheck.expires_at(organization) == nil
    end

    test "is false for a domain that was never verified" do
      organization = AccountsFixtures.organization_fixture()

      refute SSOLoginDomainRecheck.expiring?(organization, ~U[2026-09-23 12:00:00Z])
      assert SSOLoginDomainRecheck.awaiting_record?(organization, ~U[2026-09-23 12:00:00Z])
    end
  end

  describe "days_until_expiry/2" do
    test "counts whole days and never goes below zero" do
      organization = verified_organization(last_verified_at: ~U[2026-09-20 12:00:00Z])

      assert SSOLoginDomainRecheck.days_until_expiry(organization, ~U[2026-09-23 12:00:00Z]) == 11
      assert SSOLoginDomainRecheck.days_until_expiry(organization, ~U[2026-10-30 12:00:00Z]) == 0
    end
  end

  defp verified_organization(opts) do
    organization =
      AccountsFixtures.organization_fixture(
        sso_provider: :okta,
        sso_organization_id: "tenant-#{TuistTestSupport.Utilities.unique_integer()}.okta.com",
        oauth2_client_id: "client-id",
        oauth2_client_secret: "client-secret",
        sso_login_domain: "domain-#{TuistTestSupport.Utilities.unique_integer()}.example",
        sso_login_domain_verification_token: "verification-token",
        sso_login_domain_verified_at: ~U[2026-09-01 12:00:00Z]
      )

    organization
    |> Ecto.Changeset.change(sso_login_domain_last_verified_at: Keyword.fetch!(opts, :last_verified_at))
    |> Repo.update!()
  end
end
