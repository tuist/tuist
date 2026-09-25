defmodule Tuist.Repo.Migrations.AddSsoLoginDomainLastVerifiedAtToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :sso_login_domain_last_verified_at, :timestamptz
    end
  end
end
