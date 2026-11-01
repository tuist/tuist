defmodule Tuist.Repo.Migrations.AddBrowserSessionSecurityState do
  use Ecto.Migration

  def change do
    # No backfill: historical linked identities do not prove which IdP
    # authenticated a session, and migration time is not user activity.
    alter table(:users_tokens) do
      add :last_active_at, :timestamptz
      add :auth_provider, :string
      add :auth_provider_organization_id, :string
      add :auth_organization_id, references(:organizations, on_delete: :nilify_all)
    end
  end
end
