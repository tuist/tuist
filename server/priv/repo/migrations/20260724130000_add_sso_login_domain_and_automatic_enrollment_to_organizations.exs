defmodule Tuist.Repo.Migrations.AddSsoLoginDomainAndAutomaticEnrollmentToOrganizations do
  use Ecto.Migration

  import Ecto.Query

  def up do
    # These values are the persisted Ecto.Enum mapping from Accounts.Organization.
    google_provider = 2
    legacy_login_domain_providers = [1, 3]

    alter table(:organizations) do
      add :sso_login_domain, :string
      add :sso_login_domain_verification_token, :string
      add :sso_login_domain_verified_at, :timestamptz

      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :sso_automatic_enrollment, :boolean, default: false, null: false
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :sso_legacy_email_domain_fallback, :boolean, default: false, null: false
    end

    flush()

    repo().update_all(
      from(organization in "organizations", where: organization.sso_provider == ^google_provider),
      set: [sso_automatic_enrollment: true]
    )

    repo().update_all(
      from(organization in "organizations",
        where: organization.sso_provider in ^legacy_login_domain_providers
      ),
      set: [sso_automatic_enrollment: true, sso_legacy_email_domain_fallback: true]
    )
  end

  def down do
    alter table(:organizations) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :sso_login_domain
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :sso_login_domain_verification_token
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :sso_login_domain_verified_at
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :sso_automatic_enrollment
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :sso_legacy_email_domain_fallback
    end
  end
end
