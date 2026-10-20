defmodule Atlas.Repo.Migrations.CreateLlmProvidersAndSignalSummaries do
  use Ecto.Migration

  def change do
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

    create table(:signal_summaries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :body, :text, null: false
      add :signal_id, references(:signals, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:signal_summaries, [:signal_id])
  end
end
