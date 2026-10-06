defmodule Tuist.Repo.Migrations.CreateOIDCScopeRules do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  def change do
    create table(:oidc_scope_rules, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all)
      add :project_id, references(:projects, on_delete: :delete_all)
      add :scope, :string, null: false
      add :refs, {:array, :string}, null: false, default: []
      add :job_workflow_refs, {:array, :string}, null: false, default: []
      add :environments, {:array, :string}, null: false, default: []

      timestamps(type: :timestamptz)
    end

    create unique_index(:oidc_scope_rules, [:project_id, :scope],
             where: "project_id IS NOT NULL",
             name: :oidc_scope_rules_project_id_scope_index
           )

    create unique_index(:oidc_scope_rules, [:account_id, :scope],
             where: "account_id IS NOT NULL",
             name: :oidc_scope_rules_account_id_scope_index
           )

    # A rule belongs to exactly one of a project or an account, and gates a
    # scope of that level.
    create constraint(:oidc_scope_rules, :oidc_scope_rules_scope_level,
             check:
               "(account_id IS NOT NULL AND project_id IS NULL AND scope LIKE 'account:%') OR " <>
                 "(project_id IS NOT NULL AND account_id IS NULL AND scope LIKE 'project:%')"
           )
  end
end
