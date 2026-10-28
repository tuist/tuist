defmodule Atlas.Repo.Migrations.AddEventSourcesAndNotesToFeatureInterests do
  use Ecto.Migration

  def change do
    alter table(:feature_interest_accounts) do
      add :account_event_id,
          references(:account_events, type: :binary_id, on_delete: :nilify_all)

      add :notes, :text
    end

    create index(:feature_interest_accounts, [:account_event_id])
  end
end
