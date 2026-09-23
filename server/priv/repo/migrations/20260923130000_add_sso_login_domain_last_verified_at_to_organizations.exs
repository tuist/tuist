defmodule Tuist.Repo.Migrations.AddSsoLoginDomainLastVerifiedAtToOrganizations do
  use Ecto.Migration

  import Ecto.Query

  def up do
    alter table(:organizations) do
      add :sso_login_domain_last_verified_at, :timestamptz
    end

    flush()

    # A domain verified before this column existed has been seen at least once,
    # so it starts its grace period from that verification rather than expiring
    # on the first sweep.
    repo().update_all(
      from(organization in "organizations",
        where: not is_nil(organization.sso_login_domain_verified_at),
        update: [
          set: [sso_login_domain_last_verified_at: organization.sso_login_domain_verified_at]
        ]
      ),
      []
    )
  end

  def down do
    alter table(:organizations) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :sso_login_domain_last_verified_at
    end
  end
end
