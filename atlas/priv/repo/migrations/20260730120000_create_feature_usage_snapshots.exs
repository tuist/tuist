defmodule Atlas.Repo.Migrations.CreateFeatureUsageSnapshots do
  use Ecto.Migration

  def change do
    create table(:feature_usage_snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :feature, :string, null: false
      add :events_last_24h, :integer, null: false, default: 0
      add :events_last_7d, :integer, null: false, default: 0
      add :events_prior_7d, :integer, null: false, default: 0
      add :last_used_at, :utc_datetime
      add :active, :boolean, null: false, default: false
      add :active_previous, :boolean, null: false, default: false
      add :computed_at, :utc_datetime, null: false

      timestamps()
    end

    create unique_index(:feature_usage_snapshots, [:account_id, :feature, :computed_at])
    create index(:feature_usage_snapshots, [:account_id, :feature])
    create index(:feature_usage_snapshots, [:feature, :active])
  end
end
