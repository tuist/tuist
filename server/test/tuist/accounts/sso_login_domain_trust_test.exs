defmodule Tuist.Accounts.SSOLoginDomainTrustTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Ecto.Changeset
  alias Tuist.Accounts
  alias Tuist.Accounts.Oauth2Identity
  alias Tuist.Accounts.SSOLoginDomainRecheck
  alias Tuist.Accounts.SSOLoginDomainTrust
  alias Tuist.Accounts.SSOLoginDomainVerification
  alias Tuist.Environment
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.TelemetryCapture

  setup do
    trust_unverified_domains(false)
    :ok
  end

  test "parses a single explicit instance-wide switch without additional configuration" do
    assert {:ok, false} = SSOLoginDomainTrust.parse_config(nil, false)
    assert {:ok, false} = SSOLoginDomainTrust.parse_config("false", false)
    assert {:ok, true} = SSOLoginDomainTrust.parse_config("true", false)

    for invalid <- ["", "yes", "1", "TRUE", " true "] do
      assert {:error, _} = SSOLoginDomainTrust.parse_config(invalid, false)
    end
  end

  test "hosted startup and runtime independently deny enabling trust" do
    assert {:ok, false} = SSOLoginDomainTrust.parse_config(nil, true)
    assert {:ok, false} = SSOLoginDomainTrust.parse_config("false", true)
    assert {:error, _} = SSOLoginDomainTrust.parse_config("true", true)
    refute Environment.sso_trust_unverified_login_domains?(true, true)
    refute Environment.sso_trust_unverified_login_domains?(false, false)
    assert Environment.sso_trust_unverified_login_domains?(false, true)
  end

  test "instance trust requires a custom provider and saved domain, without DNS writes" do
    organization = configured_organization()
    refute SSOLoginDomainTrust.trusted?(organization)
    trust_unverified_domains(true)

    assert SSOLoginDomainTrust.trust(organization) == :instance
    refute SSOLoginDomainTrust.trusted?(%{organization | sso_login_domain: nil})
    refute SSOLoginDomainTrust.trusted?(%{organization | sso_provider: :google})

    assert {:ok, updated} =
             Accounts.update_sso_configuration(organization.id, :okta, %{
               sso_automatic_enrollment: true,
               sso_enforced: true
             })

    refute updated.sso_login_domain_verified_at
    refute updated.sso_login_domain_last_verified_at
    assert Accounts.sso_automatic_enrollment_allowed?(updated, "employee@EXAMPLE.com")
    assert Accounts.sso_identity_linking_allowed?(updated, "employee@example.com")
    refute Accounts.sso_automatic_enrollment_allowed?(updated, "employee@other.com")
    refute Accounts.sso_identity_linking_allowed?(updated, "employee@other.com")
    assert {:ok, discovered} = Accounts.sso_organization_for_user_email("new@example.com")
    assert discovered.id == organization.id
    assert Accounts.sso_enforced_for_email?("new@example.com")
  end

  test "multiple pending claims are ambiguous, but a later DNS proof wins discovery" do
    first = configured_organization()
    second = configured_organization(sso_organization_id: "other.okta.com")

    verified =
      configured_organization(
        sso_organization_id: "verified.okta.com",
        sso_login_domain_verified_at: DateTime.utc_now()
      )

    trust_unverified_domains(true)
    assert {:ok, _} = Accounts.update_sso_configuration(second.id, :okta, %{sso_enforced: true})
    assert {:ok, discovered} = Accounts.sso_organization_for_user_email("new@example.com")
    assert discovered.id == verified.id
    assert Accounts.sso_identity_linking_allowed?(first, "employee@example.com")
    assert Accounts.sso_identity_linking_allowed?(second, "employee@example.com")

    verified |> Changeset.change(sso_login_domain: nil) |> Repo.update!()
    assert {:error, :login_domain_ambiguous} = Accounts.sso_organization_for_user_email("new@example.com")
    assert Accounts.sso_enforced_for_email?("new@example.com")
  end

  test "existing membership routing survives ambiguous domain discovery" do
    user = AccountsFixtures.user_fixture(email: "member@example.com")
    first = configured_organization(creator: user)
    configured_organization(sso_organization_id: "other.okta.com")
    trust_unverified_domains(true)
    assert {:ok, organization} = Accounts.sso_organization_for_user_email(user.email)
    assert organization.id == first.id
  end

  test "Google stale domains neither affect discovery nor require instance domain trust" do
    google =
      configured_organization(
        sso_provider: :google,
        sso_organization_id: "example.com",
        sso_automatic_enrollment: true,
        sso_login_domain_verified_at: DateTime.utc_now()
      )

    custom = configured_organization()
    trust_unverified_domains(true)
    assert {:ok, discovered} = Accounts.sso_organization_for_user_email("new@example.com")
    assert discovered.id == custom.id
    assert Accounts.sso_automatic_enrollment_allowed?(google, "workspace@example.com")
  end

  test "instance trust does not add administrator allowlists to context configuration" do
    trust_unverified_domains(true)
    creator = AccountsFixtures.user_fixture()
    organization = configured_organization(creator: creator)

    assert {:ok, updated} =
             Accounts.update_sso_configuration(organization.id, :okta, %{
               oauth2_client_secret: "rotated",
               oauth2_user_info_url: "https://example.okta.com/new-userinfo"
             })

    assert updated.oauth2_user_info_url == "https://example.okta.com/new-userinfo"
    assert {:ok, updated} = Accounts.update_organization(updated, %{sso_default_role: "viewer"})
    assert updated.sso_default_role == "viewer"
  end

  test "withdrawal removes dynamic access, preserves identities and stored memberships, and allows secret rotation" do
    organization = configured_organization()
    user = AccountsFixtures.user_fixture(email: "enrolled@example.com")

    identity =
      AccountsFixtures.oauth2_identity_fixture(
        user: user,
        provider: :okta,
        provider_organization_id: organization.sso_organization_id
      )

    trust_unverified_domains(true)

    assert {:ok, organization} =
             Accounts.update_sso_configuration(organization.id, :okta, %{
               sso_automatic_enrollment: true,
               sso_enforced: true
             })

    assert Accounts.organization_user?(user, organization)
    trust_unverified_domains(false)
    refute Accounts.organization_user?(user, organization)
    refute Accounts.sso_identity_linking_allowed?(organization, user.email)
    assert {:error, :not_found} = Accounts.sso_organization_for_user_email("new@example.com")
    assert Repo.get!(Oauth2Identity, identity.id).user_id == user.id

    assert {:ok, rotated} =
             Accounts.update_sso_configuration(organization.id, :okta, %{oauth2_client_secret: "rotated"})

    assert rotated.sso_enforced
    assert {:error, _} = Accounts.update_sso_configuration(organization.id, :okta, %{sso_login_domain: "other.com"})
    assert :ok = Accounts.add_user_to_organization(user, organization, role: :user)
    assert Accounts.organization_user?(user, organization)
  end

  test "trust decisions and disabled-enrollment authorization add no database reads with either policy" do
    user = AccountsFixtures.user_fixture()
    organization = configured_organization()
    ref = TelemetryCapture.attach_event_handlers([[:tuist, :repo, :query]])

    for enabled <- [false, true] do
      trust_unverified_domains(enabled)
      SSOLoginDomainTrust.trust(organization)
      refute_received {[:tuist, :repo, :query], ^ref, _, _}

      for provider <- [nil, :okta, :oauth2, :google],
          check <- [&Accounts.organization_user?/2, &Accounts.organization_viewer?/2] do
        candidate = %{organization | sso_provider: provider}
        refute check.(user, candidate)
        assert_received {[:tuist, :repo, :query], ^ref, _, _}
        refute_received {[:tuist, :repo, :query], ^ref, _, _}
        refute check.(%{user | organization_roles: %{}}, candidate)
        refute_received {[:tuist, :repo, :query], ^ref, _, _}
      end
    end
  end

  test "DNS rechecks cannot revoke instance trust, and independent DNS trust survives policy removal" do
    organization = configured_organization(sso_login_domain_verified_at: ~U[2026-09-01 12:00:00Z])

    organization =
      organization |> Changeset.change(sso_login_domain_last_verified_at: ~U[2026-09-01 12:00:00Z]) |> Repo.update!()

    trust_unverified_domains(true)
    stub(SSOLoginDomainVerification, :verified?, fn _, _ -> false end)
    assert %{lapsed: 1} = SSOLoginDomainRecheck.sweep(~U[2026-09-23 12:00:00Z])
    assert SSOLoginDomainTrust.trust(Repo.reload!(organization)) == :instance
    trust_unverified_domains(false)
    assert SSOLoginDomainTrust.trust(organization) == :dns_verified
  end

  defp configured_organization(opts \\ []) do
    AccountsFixtures.organization_fixture(
      Keyword.merge(
        [
          sso_provider: :okta,
          sso_organization_id: "example.okta.com",
          sso_login_domain: "example.com",
          sso_login_domain_verification_token: "token",
          oauth2_client_id: "client",
          oauth2_client_secret: "secret"
        ],
        opts
      )
    )
  end

  defp trust_unverified_domains(enabled) do
    stub(Environment, :sso_trust_unverified_login_domains?, fn -> enabled end)
  end
end
