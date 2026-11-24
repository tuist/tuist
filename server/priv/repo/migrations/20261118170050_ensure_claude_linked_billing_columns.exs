defmodule Tuist.Repo.Migrations.EnsureClaudeLinkedBillingColumns do
  use Ecto.Migration

  # Staging recorded version 20261118170000 for a different migration that
  # briefly shared it, so it skipped AddClaudeLinkedBillingToOrganizationAi.
  # Apply its changes where they are missing, before the index that needs
  # `kind`. Everywhere else they already exist and this does nothing.
  def up do
    alter table(:organization_ai_connections) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add_if_not_exists :kind, :string, null: false, default: "api_key"
      add_if_not_exists :anthropic_connection_id, :string
    end

    # Dropping NOT NULL only updates the catalog and is a no-op when already dropped.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE organization_ai_connections ALTER COLUMN base_url DROP NOT NULL"
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE organization_ai_connections ALTER COLUMN api_key DROP NOT NULL"

    alter table(:organizations) do
      add_if_not_exists :anthropic_user_profile_id, :string
    end
  end

  def down, do: :ok
end
