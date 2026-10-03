defmodule Atlas.Repo.Migrations.AddPriorityToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :priority, :string
      add :priority_reason, :text
      add :priority_signals, :map, default: %{"items" => []}, null: false
      add :priority_previous, :string
      add :priority_changed_at, :utc_datetime
      add :priority_updated_at, :utc_datetime
      add :deal_stage_changed_at, :utc_datetime
    end

    create index(:accounts, [:priority])
  end
end
