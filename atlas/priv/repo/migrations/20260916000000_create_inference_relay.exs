defmodule Atlas.Repo.Migrations.CreateInferenceRelay do
  use Ecto.Migration

  def change do
    create table(:inference_model_bindings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :upstream_provider, :string, null: false
      add :upstream_model, :string, null: false
      add :input_cost_per_million, :decimal, precision: 18, scale: 9
      add :output_cost_per_million, :decimal, precision: 18, scale: 9
      add :enabled, :boolean, null: false, default: true
      add :atlas_inference, :boolean, null: false, default: false
      add :atlas_coding, :boolean, null: false, default: false
      add :atlas_embedding, :boolean, null: false, default: false
      add :last_used_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:inference_model_bindings, [:name])
    create index(:inference_model_bindings, [:enabled])

    create unique_index(:inference_model_bindings, [:atlas_inference],
             where: "atlas_inference",
             name: :inference_model_bindings_single_atlas_inference_index
           )

    create unique_index(:inference_model_bindings, [:atlas_coding],
             where: "atlas_coding",
             name: :inference_model_bindings_single_atlas_coding_index
           )

    create unique_index(:inference_model_bindings, [:atlas_embedding],
             where: "atlas_embedding",
             name: :inference_model_bindings_single_atlas_embedding_index
           )

    create table(:inference_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :token_hash, :string, null: false
      add :token_ciphertext, :text
      add :atlas_role, :string
      add :enabled, :boolean, null: false, default: true
      add :expires_at, :utc_datetime
      add :last_used_at, :utc_datetime

      add :model_binding_id,
          references(:inference_model_bindings, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:inference_tokens, [:token_hash])
    create index(:inference_tokens, [:model_binding_id])
    create index(:inference_tokens, [:enabled])

    create unique_index(:inference_tokens, [:model_binding_id, :atlas_role],
             where: "atlas_role IS NOT NULL",
             name: :inference_tokens_model_binding_atlas_role_index
           )

    create table(:inference_usages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :operation, :string, null: false, default: "chat_completion"
      add :upstream_provider, :string, null: false
      add :upstream_model, :string, null: false
      add :status, :integer, null: false
      add :input_tokens, :integer, null: false, default: 0
      add :output_tokens, :integer, null: false, default: 0
      add :total_tokens, :integer, null: false, default: 0
      add :cost_usd, :decimal, precision: 18, scale: 9, null: false, default: 0

      add :model_binding_id,
          references(:inference_model_bindings, type: :binary_id, on_delete: :delete_all),
          null: false

      add :token_id,
          references(:inference_tokens, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:inference_usages, [:model_binding_id, :inserted_at])
    create index(:inference_usages, [:token_id, :inserted_at])
    create index(:inference_usages, [:operation, :inserted_at])

    create table(:inference_providers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :string, null: false
      add :base_url, :string, null: false
      add :api_key_ciphertext, :text
      add :timeout, :integer, null: false, default: 300_000

      timestamps(type: :utc_datetime)
    end

    create unique_index(:inference_providers, [:key])
  end
end
