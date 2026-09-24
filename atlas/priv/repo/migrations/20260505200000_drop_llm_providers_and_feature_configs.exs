defmodule Atlas.Repo.Migrations.DropLlmProvidersAndFeatureConfigs do
  use Ecto.Migration

  def up do
    drop table(:llm_feature_configs)
    drop table(:llm_providers)
  end

  def down do
    create table(:llm_providers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :model, :string, null: false
      add :api_key, :binary
      add :base_url, :string

      timestamps()
    end

    create unique_index(:llm_providers, [:name])

    create table(:llm_feature_configs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :feature, :string, null: false

      add :llm_provider_id,
          references(:llm_providers, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps()
    end

    create unique_index(:llm_feature_configs, [:feature])
  end
end
