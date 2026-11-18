defmodule Tuist.Repo.Migrations.AddClaudeLinkedBillingToOrganizationAi do
  use Ecto.Migration

  def change do
    alter table(:organization_ai_connections) do
      # A constant default is metadata-only in PostgreSQL, so the table isn't rewritten.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :kind, :string, null: false, default: "api_key"
      add :anthropic_connection_id, :string
    end

    # A linked Claude organization has no endpoint or key of its own. Only the
    # nullability changes, so the column types are left untouched. Dropping NOT
    # NULL only updates the catalog; it doesn't scan or rewrite the table.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE organization_ai_connections ALTER COLUMN base_url DROP NOT NULL",
            "ALTER TABLE organization_ai_connections ALTER COLUMN base_url SET NOT NULL"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE organization_ai_connections ALTER COLUMN api_key DROP NOT NULL",
            "ALTER TABLE organization_ai_connections ALTER COLUMN api_key SET NOT NULL"

    alter table(:organizations) do
      add :anthropic_user_profile_id, :string
    end
  end
end
