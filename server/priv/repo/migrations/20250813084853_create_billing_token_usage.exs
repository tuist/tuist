defmodule Tuist.Repo.Migrations.CreateBillingTokenUsage do
  use Ecto.Migration

  def change do
    create table(:token_usages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :input_tokens, :integer, null: false
      add :output_tokens, :integer, null: false
      add :model, :string, null: false
      add :feature, :string, null: false
      add :feature_resource_id, :binary_id, null: false

      add :account_id, references(:accounts, on_delete: :delete_all), null: false

      add :timestamp, :timestamptz, null: false

      timestamps(type: :timestamptz)
    end

    create index(:token_usages, [:feature_resource_id])
    create index(:token_usages, [:timestamp])

    create index(:token_usages, [:account_id, :feature, "timestamp DESC"],
             name: :token_usages_account_feature_timestamp_idx
           )
  end
end
