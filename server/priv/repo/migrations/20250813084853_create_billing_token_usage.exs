defmodule Tuist.Repo.Migrations.CreateBillingTokenUsage do
  use Ecto.Migration

  def change do
    create table(:billing_token_usage, primary_key: false) do
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

    create index(:billing_token_usage, [:account_id])
    create index(:billing_token_usage, [:feature])
    create index(:billing_token_usage, [:feature_resource_id])
    create index(:billing_token_usage, [:timestamp])
    create index(:billing_token_usage, [:account_id, :feature])
    create index(:billing_token_usage, [:account_id, :timestamp])
  end
end
