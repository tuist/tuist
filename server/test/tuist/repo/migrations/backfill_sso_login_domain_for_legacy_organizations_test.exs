Code.require_file(
  Path.expand(
    "../../../../priv/repo/migrations/20260910120000_backfill_sso_login_domain_for_legacy_organizations.exs",
    __DIR__
  )
)

defmodule Tuist.Repo.Migrations.BackfillSsoLoginDomainForLegacyOrganizationsTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Accounts
  alias Tuist.Repo
  alias Tuist.Repo.Migrations.BackfillSsoLoginDomainForLegacyOrganizations
  alias TuistTestSupport.Fixtures.AccountsFixtures

  test "seeds the domain its members share, ready to verify" do
    organization = legacy_organization(["ada@acme.test", "grace@acme.test", "alan@acme.test"])

    BackfillSsoLoginDomainForLegacyOrganizations.backfill_login_domains!(Repo)

    backfilled = reload(organization)
    assert backfilled.sso_login_domain == "acme.test"
    assert String.length(backfilled.sso_login_domain_verification_token) == 32
  end

  test "leaves the domain unverified" do
    organization = legacy_organization(["ada@acme.test", "grace@acme.test"])

    BackfillSsoLoginDomainForLegacyOrganizations.backfill_login_domains!(Repo)

    backfilled = reload(organization)
    assert is_nil(backfilled.sso_login_domain_verified_at)
    assert backfilled.sso_legacy_email_domain_fallback
  end

  test "answers nothing for a membership split across domains" do
    organization =
      legacy_organization([
        "ada@one.test",
        "grace@one.test",
        "alan@two.test",
        "edsger@two.test"
      ])

    BackfillSsoLoginDomainForLegacyOrganizations.backfill_login_domains!(Repo)

    assert is_nil(reload(organization).sso_login_domain)
  end

  test "keeps a domain an admin already configured" do
    organization =
      legacy_organization(["ada@acme.test", "grace@acme.test"],
        sso_login_domain: "chosen.test",
        sso_login_domain_verification_token: "chosen-token"
      )

    BackfillSsoLoginDomainForLegacyOrganizations.backfill_login_domains!(Repo)

    backfilled = reload(organization)
    assert backfilled.sso_login_domain == "chosen.test"
    assert backfilled.sso_login_domain_verification_token == "chosen-token"
  end

  test "leaves organizations that never held the legacy fallback alone" do
    organization = legacy_organization(["ada@acme.test", "grace@acme.test"], legacy: false)

    BackfillSsoLoginDomainForLegacyOrganizations.backfill_login_domains!(Repo)

    assert is_nil(reload(organization).sso_login_domain)
  end

  defp legacy_organization([creator_email | member_emails], opts \\ []) do
    tenant = "tenant-#{TuistTestSupport.Utilities.unique_integer()}.okta.com"

    organization =
      AccountsFixtures.organization_fixture(
        creator: AccountsFixtures.user_fixture(email: creator_email),
        sso_provider: :okta,
        sso_organization_id: tenant,
        oauth2_client_id: "client-id",
        oauth2_client_secret: "client-secret",
        sso_legacy_email_domain_fallback: Keyword.get(opts, :legacy, true),
        sso_login_domain: Keyword.get(opts, :sso_login_domain),
        sso_login_domain_verification_token: Keyword.get(opts, :sso_login_domain_verification_token)
      )

    for email <- member_emails do
      Accounts.add_user_to_organization(AccountsFixtures.user_fixture(email: email), organization)
    end

    organization
  end

  # excellent_migrations:safety-assured-for-next-line operation_reload
  defp reload(organization), do: Repo.reload!(organization)
end
