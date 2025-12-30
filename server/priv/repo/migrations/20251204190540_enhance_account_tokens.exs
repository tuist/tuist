defmodule Tuist.Repo.Migrations.EnhanceAccountTokens do
  use Ecto.Migration

  def change do
    # Add new columns to account_tokens
    alter table(:account_tokens) do
      add :name, :string
      add :expires_at, :timestamptz
      add :created_by_account_id, references(:accounts, on_delete: :nilify_all)
      # When true, token has access to all projects under the account.
      # When false, access is restricted to projects in account_token_projects table.
      add :all_projects, :boolean, null: false, default: true
    end

    # Create the join table for project restrictions
    create table(:account_token_projects, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :account_token_id, references(:account_tokens, type: :uuid, on_delete: :delete_all),
        null: false

      add :project_id, references(:projects, on_delete: :delete_all), null: false

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:account_token_projects, [:account_token_id, :project_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:account_token_projects, [:project_id])
  end
end
