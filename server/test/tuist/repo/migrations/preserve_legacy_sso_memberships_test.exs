Code.require_file(
  Path.expand("../../../../priv/repo/migrations/20261027103000_preserve_legacy_sso_memberships.exs", __DIR__)
)

defmodule Tuist.Repo.Migrations.PreserveLegacySsoMembershipsTest do
  use TuistTestSupport.Cases.DataCase, async: false

  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.Accounts.Role
  alias Tuist.Accounts.UserRole
  alias Tuist.Repo
  alias Tuist.Repo.Migrations.PreserveLegacySsoMemberships
  alias TuistTestSupport.Fixtures.AccountsFixtures

  test "preserves each implicit member and the configured role for Okta and custom providers" do
    for provider <- [:okta, :oauth2] do
      organization = organization(provider, sso_default_role: "viewer")
      # excellent_migrations:safety-assured-for-next-line operation_update
      organization = organization |> Ecto.Changeset.change(sso_enforced: true) |> Repo.update!()
      members = for _ <- 1..2, do: linked_user(organization)

      Accounts.link_oauth_identity_to_user(hd(members), %{
        provider: provider,
        provider_organization_id: organization.sso_organization_id,
        id_in_provider: "second-identity"
      })

      other_organization = AccountsFixtures.organization_fixture()
      Accounts.add_user_to_organization(hd(members), other_organization)
      refute Accounts.belongs_to_organization?(hd(members), organization)

      assert :ok = PreserveLegacySsoMemberships.preserve_memberships!(Repo)

      for member <- members do
        assert Accounts.get_user_role_in_organization(member, organization).name == "viewer"
        assert Accounts.sso_enforced_for_email?(member.email)
        assert {:ok, discovered} = Accounts.sso_organization_for_user_email(member.email)
        assert discovered.id == organization.id
      end

      assert role_count(organization) == 3
      assert :ok = PreserveLegacySsoMemberships.preserve_memberships!(Repo)
      assert role_count(organization) == 3
      refute Accounts.sso_automatic_enrollment_allowed?(organization, "new@unverified.example")
    end
  end

  test "does not change explicit admin, user or viewer roles" do
    organization = organization(:oauth2)

    for role <- [:admin, :user, :viewer] do
      member = linked_user(organization)
      Accounts.add_user_to_organization(member, organization, role: role)
      PreserveLegacySsoMemberships.preserve_memberships!(Repo)
      assert Accounts.get_user_role_in_organization(member, organization).name == Atom.to_string(role)
    end

    assert role_count(organization) == 4
  end

  test "uses the runtime user-role default when the stored enrollment role is null" do
    organization = organization(:oauth2)
    # excellent_migrations:safety-assured-for-next-line operation_update
    organization = organization |> Ecto.Changeset.change(sso_default_role: nil) |> Repo.update!()
    member = linked_user(organization)
    PreserveLegacySsoMemberships.preserve_memberships!(Repo)
    assert Accounts.get_user_role_in_organization(member, organization).name == "user"
  end

  test "does not enroll invitation-only, nonlegacy, Google or wrong-issuer identities" do
    for opts <- [
          [sso_automatic_enrollment: false],
          [sso_legacy_email_domain_fallback: false, sso_automatic_enrollment: false]
        ] do
      organization = organization(:oauth2, opts)
      member = linked_user(organization)
      PreserveLegacySsoMemberships.preserve_memberships!(Repo)
      refute Accounts.get_user_role_in_organization(member, organization)
      assert role_count(organization) == 1
    end

    google = AccountsFixtures.organization_fixture(sso_provider: :google, sso_organization_id: "google.example")
    _google_member = linked_user(google)
    organization = organization(:okta)
    _other_issuer = linked_user(%{organization | sso_organization_id: "other.okta.com"})
    PreserveLegacySsoMemberships.preserve_memberships!(Repo)
    assert role_count(google) == 1
    assert role_count(organization) == 1
  end

  defp organization(provider, opts \\ []) do
    tenant = "tenant-#{System.unique_integer([:positive])}.example"
    issuer = if provider == :okta, do: tenant, else: "https://#{tenant}"

    AccountsFixtures.organization_fixture(
      Keyword.merge(
        [
          sso_provider: provider,
          sso_organization_id: issuer,
          sso_legacy_email_domain_fallback: true,
          sso_automatic_enrollment: true,
          oauth2_client_id: "client",
          oauth2_client_secret: "secret",
          oauth2_authorize_url: "https://#{tenant}/authorize",
          oauth2_token_url: "https://#{tenant}/token",
          oauth2_user_info_url: "https://#{tenant}/userinfo"
        ],
        opts
      )
    )
  end

  defp linked_user(organization) do
    user = AccountsFixtures.user_fixture()

    {:ok, _} =
      Accounts.link_oauth_identity_to_user(user, %{
        provider: organization.sso_provider,
        provider_organization_id: organization.sso_organization_id,
        id_in_provider: "identity-#{user.id}"
      })

    user
  end

  defp role_count(organization) do
    # excellent_migrations:safety-assured-for-next-line operation_aggregate
    Repo.aggregate(
      from(r in Role,
        join: ur in UserRole,
        on: ur.role_id == r.id,
        where: r.resource_type == "Organization" and r.resource_id == ^organization.id
      ),
      :count
    )
  end
end
