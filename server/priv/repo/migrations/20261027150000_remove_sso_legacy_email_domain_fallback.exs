defmodule Tuist.Repo.Migrations.RemoveSsoLegacyEmailDomainFallback do
  use Ecto.Migration

  def up do
    # Fail instead of queuing organization reads/writes behind a busy table.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "SET LOCAL lock_timeout = '5s'"

    alter table(:organizations) do
      # Runtime readers and writers were removed in the preceding release.
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :sso_legacy_email_domain_fallback
    end
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "SET LOCAL lock_timeout = '5s'"

    alter table(:organizations) do
      # Restore the shape without re-enabling retired trust for any organization.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :sso_legacy_email_domain_fallback, :boolean, default: false, null: false
    end
  end
end
