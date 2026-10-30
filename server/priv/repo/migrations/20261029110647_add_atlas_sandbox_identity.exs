defmodule Tuist.Repo.Migrations.AddAtlasSandboxIdentity do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create table(:sandbox_provider_environments, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :external_key, :string, null: false
      add :generation, :bigint, null: false, default: 0
      add :enabled, :boolean, null: false, default: false
      timestamps(type: :timestamptz)
    end

    create unique_index(:sandbox_provider_environments, [:account_id, :external_key],
             concurrently: true
           )

    alter table(:sandboxes) do
      add :provider_environment_id,
          references(:sandbox_provider_environments, type: :uuid, on_delete: :nilify_all)
    end

    create unique_index(:sandboxes, [:provider_environment_id], concurrently: true)
  end
end
