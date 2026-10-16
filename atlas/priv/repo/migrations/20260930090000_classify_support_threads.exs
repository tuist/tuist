defmodule Atlas.Repo.Migrations.ClassifySupportThreads do
  use Ecto.Migration

  def change do
    alter table(:support_threads) do
      add :classification, :string
      add :action_needed, :boolean
      add :urgency, :string
      add :classifier_confidence, :float
      add :classifier_reason, :text
      add :classified_at, :timestamptz
    end

    create index(:support_threads, [:classification])
    create index(:support_threads, [:action_needed, :urgency])
  end
end
