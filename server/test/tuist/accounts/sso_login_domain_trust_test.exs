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
    policy(false, [])
    :ok
  end

  test "parses an explicit instance policy and immutable administrator IDs" do
    assert {:ok, %{trust_unverified_domains: false, admin_user_ids: []}} =
             SSOLoginDomainTrust.parse_config(nil, nil, false)

    assert {:ok, %{trust_unverified_domains: true, admin_user_ids: [12, 34]}} =
             SSOLoginDomainTrust.parse_config("true", "12, 34", false)

    assert {:ok, %{trust_unverified_domains: false, admin_user_ids: [12]}} =
             SSOLoginDomainTrust.parse_config("false", "12", false)

    for {enabled, ids} <- [
          {"", nil},
          {"yes", "12"},
          {"1", "12"},
          {"true", nil},
          {"true", ""},
          {"true", "0"},
          {"true", "-1"},
          {"true", "12,12"},
          {"true", "12,"},
          {"true", "12abc"},
          {"true", "9223372036854775808"}
        ] do
      assert {:error, _} = SSOLoginDomainTrust.parse_config(enabled, ids, false)
    end
  end

  test "hosted startup and runtime independently deny the policy" do
    assert {:ok, _} = SSOLoginDomainTrust.parse_config("false", nil, true)
    assert {:error, _} = SSOLoginDomainTrust.parse_config("true", "12", true)
    assert {:error, _} = SSOLoginDomainTrust.parse_config("false", "12", true)

    assert Environment.sso_login_domain_policy(true, %{trust_unverified_domains: true, admin_user_ids: [12]}) ==
             %{trust_unverified_domains: false, admin_user_ids: []}
  end

  test "instance trust requires a custom provider and saved domain, without DNS writes" do
    organization = configured_organization()
    admin = AccountsFixtures.user_fixture()
    refute SSOLoginDomainTrust.trusted?(organization)
    policy(true, [admin.id])

    assert SSOLoginDomainTrust.trust(organization) == :instance
    refute SSOLoginDomainTrust.trusted?(%{organization | sso_login_domain: nil})
    refute SSOLoginDomainTrust.trusted?(%{organization | sso_provider: :google})

    assert {:ok, updated} =
             Accounts.update_sso_configuration(
               organization.id,
               :okta,
               %{sso_automatic_enrollment: true, sso_enforced: true},
               actor: admin
             )

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

    admin = AccountsFixtures.user_fixture()
    policy(true, [admin.id])
    assert {:ok, _} = Accounts.update_sso_configuration(second.id, :okta, %{sso_enforced: true}, actor: admin)

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
    policy(true, [user.id])

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
    admin = AccountsFixtures.user_fixture()
    policy(true, [admin.id])
    assert {:ok, discovered} = Accounts.sso_organization_for_user_email("new@example.com")
    assert discovered.id == custom.id
    assert Accounts.sso_automatic_enrollment_allowed?(google, "workspace@example.com")
  end

  test "only operator-selected users can mutate SSO, including through context entry points" do
    organization = configured_organization()
    admin = AccountsFixtures.user_fixture()
    ordinary_admin = AccountsFixtures.user_fixture()
    policy(true, [admin.id])

    for actor <- [nil, ordinary_admin, %{id: admin.id}] do
      assert {:error, changeset} =
               Accounts.update_sso_configuration(
                 organization.id,
                 :okta,
                 %{oauth2_user_info_url: "https://attacker.example/userinfo"},
                 actor: actor
               )

      assert changeset.errors[:sso_provider]

      assert {:error, _} =
               Accounts.update_organization(
                 organization,
                 %{"sso_provider" => :oauth2, "sso_organization_id" => "https://attacker.example"},
                 actor: actor
               )

      assert {:error, _} = Accounts.update_organization(organization, %{sso_default_role: "viewer"}, actor: actor)
    end

    assert {:ok, _} =
             Accounts.update_sso_configuration(organization.id, :okta, %{oauth2_client_secret: "rotated"}, actor: admin)

    assert {:ok, _} = Accounts.update_organization(organization, %{sso_default_role: "viewer"}, actor: admin)
  end

  test "creating an organization cannot grant authority to configure SSO" do
    user = AccountsFixtures.user_fixture()
    admin = AccountsFixtures.user_fixture()
    policy(true, [admin.id])
    assert {:ok, organization} = Accounts.create_organization(%{name: "ordinary-organization", creator: user})

    assert {:error, _} =
             Accounts.update_organization(
               organization,
               %{sso_provider: :google, sso_organization_id: "example.com"},
               actor: user
             )

    assert {:error, _} =
             Accounts.create_organization(%{name: "malicious-organization", creator: user},
               sso_provider: :google,
               sso_organization_id: "example.com"
             )
  end

  test "configuration restrictions survive disabling trust until the administrator list is removed" do
    organization = configured_organization()
    admin = AccountsFixtures.user_fixture()
    policy(false, [admin.id])
    refute Accounts.sso_configuration_allowed?(nil)
    assert {:error, _} = Accounts.update_sso_configuration(organization.id, :okta, %{oauth2_client_secret: "bad"})

    assert {:ok, _} =
             Accounts.update_sso_configuration(organization.id, :okta, %{oauth2_client_secret: "rotated"}, actor: admin)
  end

  test "withdrawal removes dynamic access, preserves identities and stored memberships, and allows secret rotation" do
    organization = configured_organization()
    admin = AccountsFixtures.user_fixture()
    user = AccountsFixtures.user_fixture(email: "enrolled@example.com")

    identity =
      AccountsFixtures.oauth2_identity_fixture(
        user: user,
        provider: :okta,
        provider_organization_id: organization.sso_organization_id
      )

    policy(true, [admin.id])

    assert {:ok, organization} =
             Accounts.update_sso_configuration(
               organization.id,
               :okta,
               %{sso_automatic_enrollment: true, sso_enforced: true},
               actor: admin
             )

    assert Accounts.organization_user?(user, organization)

    policy(false, [admin.id])
    refute Accounts.organization_user?(user, organization)
    refute Accounts.sso_identity_linking_allowed?(organization, user.email)
    assert {:error, :not_found} = Accounts.sso_organization_for_user_email("new@example.com")
    assert Repo.get!(Oauth2Identity, identity.id).user_id == user.id

    assert {:ok, rotated} =
             Accounts.update_sso_configuration(organization.id, :okta, %{oauth2_client_secret: "rotated"}, actor: admin)

    assert rotated.sso_enforced

    assert {:error, _} =
             Accounts.update_sso_configuration(organization.id, :okta, %{sso_login_domain: "other.com"}, actor: admin)

    assert :ok = Accounts.add_user_to_organization(user, organization, role: :user)
    assert Accounts.organization_user?(user, organization)
  end

  test "trust decisions and disabled-enrollment authorization add no database reads with either policy" do
    user = AccountsFixtures.user_fixture()
    organization = configured_organization()
    ref = TelemetryCapture.attach_event_handlers([[:tuist, :repo, :query]])

    for enabled <- [false, true] do
      policy(enabled, [user.id])
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

    admin = AccountsFixtures.user_fixture()
    policy(true, [admin.id])
    stub(SSOLoginDomainVerification, :verified?, fn _, _ -> false end)
    assert %{lapsed: 1} = SSOLoginDomainRecheck.sweep(~U[2026-09-23 12:00:00Z])
    assert SSOLoginDomainTrust.trust(Repo.reload!(organization)) == :instance
    policy(false, [])
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

  defp policy(enabled, ids) do
    stub(Environment, :sso_login_domain_policy, fn -> %{trust_unverified_domains: enabled, admin_user_ids: ids} end)
  end
end
