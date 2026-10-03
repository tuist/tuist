defmodule Atlas.Repo.Migrations.CreateFeatureInterests do
  use Ecto.Migration

  def change do
    create table(:feature_interests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :canonical_title, :string, null: false
      add :status, :string, null: false, default: "open"
      add :interest_count, :integer, null: false, default: 0
      add :last_interested_at, :utc_datetime
      add :metadata, :map, null: false, default: %{}

      timestamps()
    end

    create unique_index(:feature_interests, [:canonical_title])
    create index(:feature_interests, [:status, :last_interested_at])

    create table(:feature_interest_accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :feature_interest_id,
          references(:feature_interests, type: :binary_id, on_delete: :delete_all),
          null: false

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :support_thread_id,
          references(:support_threads, type: :binary_id, on_delete: :nilify_all)

      add :summary, :text, null: false
      add :last_interested_at, :utc_datetime, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps()
    end

    create unique_index(:feature_interest_accounts, [:feature_interest_id, :account_id])
    create index(:feature_interest_accounts, [:account_id, :last_interested_at])
    create index(:feature_interest_accounts, [:support_thread_id])
  end
end
