defmodule Tuist.Repo.Migrations.CreateSandboxAgentEnvironments do
  use Ecto.Migration

  # An Anthropic Managed Agents `self_hosted` environment connected to an
  # account. `environment_key` is Cloak-encrypted via `Tuist.Vault.Binary`;
  # the bytea column is what `Cloak.Ecto.Binary` writes back into. The
  # remaining columns are the template and VM shape every sandbox created
  # for this environment's sessions inherits.
  def change do
    create table(:sandbox_agent_environments) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :anthropic_environment_id, :string, null: false
      add :environment_key, :binary, null: false
      add :name, :string
      add :template, :string, null: false, default: "default"
      add :vcpus, :integer, null: false, default: 2
      add :memory_mb, :integer, null: false, default: 4096
      add :workspace_gb, :integer, null: false, default: 10
      add :max_idle_seconds, :integer, null: false, default: 30
      add :pause_grace_seconds, :integer, null: false, default: 30
      add :enabled, :boolean, null: false, default: true

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:sandbox_agent_environments, [:anthropic_environment_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:sandbox_agent_environments, [:account_id])
  end
end
